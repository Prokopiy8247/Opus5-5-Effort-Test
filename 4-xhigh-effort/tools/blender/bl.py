"""Project-owned client for the dedicated Blender MCP add-on on localhost:9880.

The Blender MCP add-on inside the project's Blender instance listens on
127.0.0.1:9880 and speaks the blender-mcp JSON command protocol
({"type": <command>, "params": {...}}).  This client is hard-wired to that one
port; it never connects anywhere else.

Usage:
    python -I tools/blender/bl.py info                 # get_scene_info
    python -I tools/blender/bl.py path                 # print bpy.data.filepath (read-only)
    python -I tools/blender/bl.py exec <script.py> [k=v ...]
        Runs a Python file inside Blender.  Extra k=v pairs are injected as a
        dict named ARGS.  Every script first asserts that the open file is
        the project's master .blend (see GUARD below).
    python -I tools/blender/bl.py shot <out.png> [max_size]
        Viewport screenshot via the add-on's get_viewport_screenshot command.
"""
from __future__ import annotations

import json
import os
import socket
import sys

HOST = "127.0.0.1"
PORT = 9880
PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MASTER = os.path.join(PROJECT_DIR, "Opus55ForzaXhighEffort.blend")

# Prepended to every executed script: refuse to run unless Blender has the
# exact master file open.  Paths compared case-insensitively (Windows).
GUARD = (
    "import bpy, os\n"
    "_m = os.path.normcase(os.path.abspath(%r))\n"
    "_c = os.path.normcase(os.path.abspath(bpy.data.filepath)) if bpy.data.filepath else ''\n"
    "if _c != _m:\n"
    "    raise RuntimeError('ROUTING GUARD: open file %%r is not the master %%r' %% (bpy.data.filepath, _m))\n"
)


def send(cmd_type: str, params: dict | None = None, timeout: float = 600.0) -> dict:
    payload = json.dumps({"type": cmd_type, "params": params or {}}).encode("utf-8")
    with socket.create_connection((HOST, PORT), timeout=15) as s:
        s.sendall(payload)
        s.settimeout(timeout)
        buf = b""
        while True:
            chunk = s.recv(1 << 20)
            if not chunk:
                break
            buf += chunk
            try:
                return json.loads(buf.decode("utf-8"))
            except ValueError:
                continue
    return json.loads(buf.decode("utf-8"))


def exec_code(code: str, guard: bool = True, timeout: float = 600.0) -> dict:
    if guard:
        code = (GUARD % MASTER) + code
    return send("execute_code", {"code": code}, timeout=timeout)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    op = sys.argv[1]
    if op == "info":
        r = send("get_scene_info")
    elif op == "path":
        r = exec_code("import bpy\nprint(repr(bpy.data.filepath))\nprint(bpy.app.version_string)\n", guard=False)
    elif op == "exec":
        script = sys.argv[2]
        args = {}
        for kv in sys.argv[3:]:
            k, _, v = kv.partition("=")
            args[k] = v
        with open(script, "r", encoding="utf-8") as f:
            body = f.read()
        code = "ARGS = %r\nPROJECT_DIR = %r\n" % (args, PROJECT_DIR) + body
        r = exec_code(code)
    elif op == "shot":
        out = os.path.abspath(sys.argv[2])
        size = int(sys.argv[3]) if len(sys.argv) > 3 else 1200
        r = send("get_viewport_screenshot", {"filepath": out, "max_size": size, "format": "png"})
    else:
        print("unknown op", op)
        return 2
    status = r.get("status")
    res = r.get("result", r.get("message"))
    if isinstance(res, dict) and "result" in res and isinstance(res["result"], str):
        print(res["result"])
    else:
        print(json.dumps(res, indent=1)[:20000] if not isinstance(res, str) else res)
    if status != "success":
        print("STATUS:", status, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
