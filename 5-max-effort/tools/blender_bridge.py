"""Minimal client for the Blender MCP add-on socket of THIS project.

Routing rule (see DEVELOPMENT.md): the only permitted endpoint is localhost:9881,
the dedicated Blender instance that has ./Opus55ForzaMaxEffort.blend open.
Host and port are hard-coded on purpose and cannot be overridden.

Usage:
  python tools/blender_bridge.py info                      # get_scene_info (read-only)
  python tools/blender_bridge.py object <name>             # get_object_info (read-only)
  python tools/blender_bridge.py code "<python>"           # execute_code with inline code
  python tools/blender_bridge.py exec <file.py> [k=v ...]  # execute_code with a file (k=v -> ARGS dict)
  python tools/blender_bridge.py shot <out.png> [max_px]   # get_viewport_screenshot
"""
import json
import os
import socket
import sys

HOST = "127.0.0.1"
PORT = 9881
EXPECTED_BLEND = os.path.normcase(os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "Opus55ForzaMaxEffort.blend")))


def send(command_type: str, params: dict | None = None, timeout: float = 600.0) -> dict:
    payload = json.dumps({"type": command_type, "params": params or {}}).encode("utf-8")
    with socket.create_connection((HOST, PORT), timeout=timeout) as sock:
        sock.sendall(payload)
        chunks = []
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
            try:
                return json.loads(b"".join(chunks).decode("utf-8"))
            except json.JSONDecodeError:
                continue
    raw = b"".join(chunks).decode("utf-8", errors="replace")
    raise RuntimeError(f"Incomplete response from Blender ({len(raw)} bytes): {raw[:500]}")


def _guard_code(code: str) -> str:
    # Every write script runs only if the open file is exactly the project's master .blend.
    guard = (
        "import bpy as _bpy_guard, os as _os_guard\n"
        f"_expected = {EXPECTED_BLEND!r}\n"
        "if _os_guard.path.normcase(_os_guard.path.abspath(_bpy_guard.data.filepath)) != _expected:\n"
        "    raise RuntimeError('ROUTING GUARD: open file ' + _bpy_guard.data.filepath + ' is not the project master')\n"
    )
    return guard + code


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    cmd = sys.argv[1]
    if cmd == "info":
        resp = send("get_scene_info")
    elif cmd == "object":
        resp = send("get_object_info", {"name": sys.argv[2]})
    elif cmd == "code":
        resp = send("execute_code", {"code": _guard_code(sys.argv[2])})
    elif cmd == "exec":
        with open(sys.argv[2], "r", encoding="utf-8") as f:
            body = f.read()
        args = {}
        for kv in sys.argv[3:]:
            k, _, v = kv.partition("=")
            args[k] = v
        prelude = f"ARGS = {args!r}\nPROJECT_DIR = {os.path.dirname(EXPECTED_BLEND)!r}\n"
        resp = send("execute_code", {"code": _guard_code(prelude + body)})
    elif cmd == "shot":
        out = os.path.abspath(sys.argv[2])
        max_px = int(sys.argv[3]) if len(sys.argv) > 3 else 1200
        resp = send("get_viewport_screenshot", {"max_size": max_px, "filepath": out, "format": "png"})
    else:
        print(f"unknown command {cmd}")
        return 2
    status = resp.get("status")
    if status == "success" and isinstance(resp.get("result"), dict) and "result" in resp["result"] and len(resp["result"]) <= 2:
        # execute_code returns {"executed": True, "result": <stdout>}
        print(resp["result"]["result"])
    else:
        print(json.dumps(resp, indent=1)[:20000])
    return 0 if status == "success" else 1


if __name__ == "__main__":
    sys.exit(main())
