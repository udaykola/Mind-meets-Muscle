import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.abspath(__file__))


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/config.js":
            cfg = {
                "url": os.environ.get("SUPABASE_URL", ""),
                "key": os.environ.get("SUPABASE_ANON_KEY", ""),
            }
            self._send(200, ("window.CFG=" + json.dumps(cfg) + ";").encode(), "application/javascript")
        elif path in ("/", "/index.html"):
            with open(os.path.join(ROOT, "index.html"), "rb") as f:
                self._send(200, f.read(), "text/html; charset=utf-8")
        elif path == "/healthz":
            self._send(200, b"ok", "text/plain")
        else:
            self._send(404, b"Not found", "text/plain")


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "10000"))
    print(f"Problem Crackers listening on {port}")
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
