"""Run locally with python3 backend/server.py; use HTTPS termination for devices."""
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from planner import generate

class APIError(Exception):
    def __init__(self, status, message): self.status, self.message = status, message

class Service:
    def __init__(self, model_call=None): self.model_call = model_call
    def dispatch(self, method, path, body, token):
        if method == "GET" and path == "/health": return {"status": "ok"}
        if method == "POST" and path == "/sidequest/plan": return generate(body, self.model_call)
        raise APIError(404, "Route not found")

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass  # No chat bodies, URLs containing tokens, or auth headers in logs.
    def do_GET(self): self.handle_request()
    def do_POST(self): self.handle_request()
    def handle_request(self):
        status = 200
        try:
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

def make_server(address=("127.0.0.1", 8787), model_call=None):
    server = ThreadingHTTPServer(address, Handler)
    server.service = Service(model_call)
    return server

if __name__ == "__main__":
    server = make_server((os.environ.get("HOST", "127.0.0.1"), int(os.environ.get("PORT", 8787))))
    print(f"SideQuest API listening on port {server.server_port}; conversation logging is disabled.")
    try: server.serve_forever()
    except KeyboardInterrupt: server.server_close()
