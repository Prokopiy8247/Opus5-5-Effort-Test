"""Minimal client for the Blender MCP add-on socket on localhost:9882 ONLY.

Usage:
  python tools/blender/bmcp.py <command_type> [json_params]
  python tools/blender/bmcp.py exec <path_to_python_file>   # execute_code with file contents
The port is hard-wired to 9882 (this project's dedicated Blender instance).
"""
import json
import socket
import sys

HOST = "127.0.0.1"
PORT = 9882


def send(cmd_type, params=None, timeout=600.0):
    payload = json.dumps({"type": cmd_type, "params": params or {}}).encode("utf-8")
    with socket.create_connection((HOST, PORT), timeout=timeout) as s:
        s.sendall(payload)
        chunks = []
        while True:
            try:
                data = s.recv(1 << 16)
            except socket.timeout:
                break
            if not data:
                break
            chunks.append(data)
            try:
                return json.loads(b"".join(chunks).decode("utf-8"))
            except json.JSONDecodeError:
                continue
    raw = b"".join(chunks).decode("utf-8", errors="replace")
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"status": "error", "message": "unparseable response", "raw": raw[:2000]}


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    cmd = sys.argv[1]
    if cmd == "exec":
        with open(sys.argv[2], "r", encoding="utf-8") as f:
            code = f.read()
        resp = send("execute_code", {"code": code})
    else:
        params = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
        resp = send(cmd, params)
    out = json.dumps(resp, indent=1, ensure_ascii=False)
    print(out[:20000])
    if isinstance(resp, dict) and resp.get("status") == "error":
        sys.exit(2)


if __name__ == "__main__":
    main()
