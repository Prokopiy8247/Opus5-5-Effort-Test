"""Minimal client for the Blender MCP add-on socket on localhost:9879.

The Claude session that built this project had no MCP tool namespace exposed for the
Blender MCP server, so it speaks the add-on's own JSON-over-TCP protocol directly,
on the one verified port only. Usage:

    python tools/blender_rpc.py info                 # get_scene_info (read-only)
    python tools/blender_rpc.py exec <file.py>       # execute_code with the file's contents
    python tools/blender_rpc.py raw '<json>'         # send an arbitrary command object
"""
import json
import socket
import sys

HOST = "127.0.0.1"
PORT = 9879  # the only permitted Blender endpoint for this project


def send(command: dict, timeout: float = 600.0) -> dict:
    with socket.create_connection((HOST, PORT), timeout=timeout) as s:
        s.sendall(json.dumps(command).encode("utf-8"))
        buf = b""
        while True:
            chunk = s.recv(1 << 16)
            if not chunk:
                break
            buf += chunk
            try:
                return json.loads(buf.decode("utf-8"))
            except json.JSONDecodeError:
                continue
    return json.loads(buf.decode("utf-8"))


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    mode = sys.argv[1]
    if mode == "info":
        cmd = {"type": "get_scene_info", "params": {}}
    elif mode == "exec":
        with open(sys.argv[2], "r", encoding="utf-8-sig") as f:
            code = f.read()
        cmd = {"type": "execute_code", "params": {"code": code}}
    elif mode == "raw":
        cmd = json.loads(sys.argv[2])
    else:
        print(__doc__)
        return 2
    resp = send(cmd)
    if mode == "exec" and isinstance(resp, dict) and resp.get("status") == "success":
        res = resp.get("result", {})
        out = res.get("result") if isinstance(res, dict) else res
        print(out if isinstance(out, str) else json.dumps(res, indent=1))
    else:
        print(json.dumps(resp, indent=1))
    return 0 if isinstance(resp, dict) and resp.get("status") != "error" else 1


if __name__ == "__main__":
    sys.exit(main())
