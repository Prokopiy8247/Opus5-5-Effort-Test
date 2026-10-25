"""Read-only probe of the Blender endpoint on localhost:9880.

Sends one JSON command and prints the raw reply. Used only to identify the
protocol spoken by the dedicated Blender instance for this project.
"""
import json
import socket
import sys

HOST = "127.0.0.1"
PORT = 9880


def main() -> None:
    cmd = {"type": sys.argv[1] if len(sys.argv) > 1 else "get_scene_info", "params": {}}
    with socket.create_connection((HOST, PORT), timeout=10) as s:
        s.sendall(json.dumps(cmd).encode("utf-8"))
        buf = b""
        s.settimeout(10)
        while True:
            try:
                chunk = s.recv(65536)
            except socket.timeout:
                print("TIMEOUT; partial:", buf[:2000])
                return
            if not chunk:
                break
            buf += chunk
            try:
                json.loads(buf.decode("utf-8"))
                break
            except ValueError:
                continue
    print(buf.decode("utf-8", "replace")[:8000])


if __name__ == "__main__":
    main()
