import socket, json, sys
def call(t, p=None):
    s = socket.create_connection(("localhost", 9877), timeout=600)
    s.sendall(json.dumps({"type": t, "params": p or {}}).encode())
    buf = b""
    while True:
        c = s.recv(65536)
        if not c: break
        buf += c
        try: return json.loads(buf)
        except ValueError: pass
    return json.loads(buf)
if __name__ == "__main__":
    if sys.argv[1] == "code":
        r = call("execute_code", {"code": open(sys.argv[2], encoding="utf-8").read()}); print(str(r)[-1500:])
    else:
        print(json.dumps(call(sys.argv[1]), indent=1))
