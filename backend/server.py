"""Run locally with python3 backend/server.py; use HTTPS termination for devices."""
import json
import os
import threading
import time
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from sessions import Service, APIError

def configure_private_environment(path=None):
    """Load this machine's credentials outside the checkout; never print their values."""
    path = Path(path or os.environ.get("SIDEQUEST_CONFIG", Path.home() / "Library/Application Support/SideQuest/server.json"))
    if not path.exists(): return
    info = path.stat()
    if info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise PermissionError("SideQuest server configuration must be owned by this user with mode 600")
    config = json.loads(path.read_text())
    for name in ("OPENAI_API_KEY", "OPENAI_MODEL"):
        if isinstance(config.get(name), str) and config[name].strip():
            os.environ.setdefault(name, config[name].strip())

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass  # No chat bodies, URLs containing tokens, or auth headers in logs.
    def do_GET(self): self.handle_request()
    def do_POST(self): self.handle_request()
    def handle_request(self):
        status = 200
        try:
            self.connection.settimeout(15)
            with self.server.limit_lock:
                now = time.monotonic()
                self.server.requests = [stamp for stamp in self.server.requests if now - stamp < 60]
                if len(self.server.requests) >= 180: raise APIError(429, "Please try again in a minute")
                self.server.requests.append(now)
            length = int(self.headers.get("Content-Length", 0))
            if not 0 <= length <= 150_000: raise APIError(413, "Request too large")
            body = json.loads(self.rfile.read(length)) if length else {}
            token = self.headers.get("Authorization", "").removeprefix("Bearer ")
            result = self.server.service.dispatch(self.command, self.path, body, token)
        except APIError as error: status, result = error.status, {"error": error.message}
        except (ValueError, TypeError, KeyError): status, result = 400, {"error": "Invalid request"}
        except Exception: status, result = 500, {"error": "Request could not be completed"}
        data = json.dumps(result, allow_nan=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers(); self.wfile.write(data)

def make_server(address=("127.0.0.1", 8787), model_call=None, database=":memory:"):
    server = ThreadingHTTPServer(address, Handler)
    server.service = Service(model_call, database)
    server.limit_lock = threading.Lock(); server.requests = []
    return server

if __name__ == "__main__":
    configure_private_environment()
    os.makedirs("backend/data", exist_ok=True)
    server = make_server((os.environ.get("HOST", "127.0.0.1"), int(os.environ.get("PORT", 8787))), database=os.environ.get("SIDEQUEST_DB", "backend/data/sidequest.sqlite"))
    print(f"SideQuest API listening on port {server.server_port}; conversation logging is disabled.")
    try: server.serve_forever()
    except KeyboardInterrupt: server.server_close()
