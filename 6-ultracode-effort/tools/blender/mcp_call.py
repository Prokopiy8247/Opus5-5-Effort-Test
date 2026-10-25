#!/usr/bin/env python3
"""Call a tool of this project's Blender MCP server over stdio JSON-RPC.

The server is exactly the one configured in the project's .mcp.json ("blender-opus55-ultracode":
uvx mcp-for-blender --port 9882), which talks to the Blender add-on on localhost:9882 that serves the master file.
Use this when the host session cannot attach that MCP server directly (it dropped out of the session after a
restart). Each call starts the configured server, performs the MCP handshake, calls one tool and shuts it down.

Usage (run from the project root):
  python tools/blender/mcp_call.py list
  python tools/blender/mcp_call.py call get_scene_info
  python tools/blender/mcp_call.py call execute_blender_code --code "import bpy; print(bpy.data.filepath)"
  python tools/blender/mcp_call.py call execute_blender_code --code-file tools/blender/props/nature_kit.py
  python tools/blender/mcp_call.py call look --args '{"mode": "angles", "shading": "material", "max_size": 640}' \
      --image-out qa_output/blender_look/nature.png
Images returned by a tool are written to --image-out (numbered when there are several) and their paths printed.
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SERVER = "blender-opus55-ultracode"
PORT = "9882"


def server_command():
    with open(os.path.join(ROOT, ".mcp.json"), encoding="utf-8") as f:
        cfg = json.load(f)["mcpServers"][SERVER]
    args = list(cfg.get("args", []))
    if "--port" not in args or args[args.index("--port") + 1] != PORT:
        sys.exit("refusing: .mcp.json entry is not on port %s" % PORT)
    return [cfg["command"]] + args


class Client:
    def __init__(self, timeout):
        self.timeout = timeout
        self.proc = subprocess.Popen(server_command(), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, cwd=ROOT, bufsize=0)
        self.lines = []
        self.cv = threading.Condition()
        threading.Thread(target=self._reader, daemon=True).start()
        self.next_id = 1

    def _reader(self):
        buf = b""
        while True:
            chunk = self.proc.stdout.read1(65536) if hasattr(self.proc.stdout, "read1") else self.proc.stdout.read(1)
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                if line.strip():
                    with self.cv:
                        self.lines.append(line)
                        self.cv.notify_all()
        with self.cv:
            self.lines.append(None)
            self.cv.notify_all()

    def send(self, msg):
        self.proc.stdin.write((json.dumps(msg) + "\n").encode("utf-8"))
        self.proc.stdin.flush()

    def request(self, method, params):
        rid = self.next_id
        self.next_id += 1
        self.send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        deadline = time.time() + self.timeout
        with self.cv:
            while True:
                for i, line in enumerate(self.lines):
                    if line is None:
                        sys.exit("MCP server exited before answering %s" % method)
                    try:
                        msg = json.loads(line)
                    except ValueError:
                        continue
                    if msg.get("id") == rid:
                        del self.lines[: i + 1]
                        if "error" in msg:
                            sys.exit("MCP error: %s" % json.dumps(msg["error"]))
                        return msg["result"]
                left = deadline - time.time()
                if left <= 0:
                    sys.exit("timeout waiting for %s" % method)
                self.cv.wait(min(left, 1.0))

    def initialize(self):
        self.request("initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                                    "clientInfo": {"name": "sunward-mcp-call", "version": "1.0"}})
        self.send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def close(self):
        try:
            self.proc.stdin.close()
            self.proc.wait(timeout=10)
        except Exception:
            self.proc.kill()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("action", choices=["list", "call"])
    ap.add_argument("tool", nargs="?")
    ap.add_argument("--args", default="{}", help="tool arguments as JSON")
    ap.add_argument("--code", help="shortcut: code argument for execute_blender_code")
    ap.add_argument("--code-file", help="shortcut: exec a project file inside Blender via execute_blender_code")
    ap.add_argument("--image-out", default=os.path.join(ROOT, "qa_output", "blender_look", "look.png"))
    ap.add_argument("--timeout", type=float, default=900.0)
    a = ap.parse_args()
    c = Client(a.timeout)
    try:
        c.initialize()
        if a.action == "list":
            for t in c.request("tools/list", {}).get("tools", []):
                print("== %s\n%s\n%s\n" % (t["name"], t.get("description", "")[:1500], json.dumps(t.get("inputSchema", {}))))
            return
        args = json.loads(a.args)
        if a.code is not None:
            args["code"] = a.code
        if a.code_file:
            path = os.path.abspath(a.code_file)
            args["code"] = ("import os\n__p = %r\nexec(compile(open(__p, encoding='utf-8').read(), __p, 'exec'), "
                            "{'__name__': '__main__', '__file__': __p})" % path)
        res = c.request("tools/call", {"name": a.tool, "arguments": args})
        n = 0
        for item in res.get("content", []):
            if item.get("type") == "text":
                print(item.get("text", ""))
            elif item.get("type") == "image":
                out = a.image_out
                if n > 0:
                    root, ext = os.path.splitext(out)
                    out = "%s_%d%s" % (root, n, ext or ".png")
                os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
                with open(out, "wb") as f:
                    f.write(base64.b64decode(item["data"]))
                print("[image] %s" % os.path.abspath(out))
                n += 1
        if res.get("isError"):
            sys.exit(1)
    finally:
        c.close()


if __name__ == "__main__":
    main()
