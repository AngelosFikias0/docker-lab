"""
Minimal HTTP server - stdlib only, no pip install.
Purpose: give the Dockerfile something real to build and run.
"""

import http.server
import os

PORT = int(os.environ.get("PORT", 8080))
APP_ENV = os.environ.get("APP_ENV", "development")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = f"env={APP_ENV} path={self.path}\n".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} {fmt % args}")


if __name__ == "__main__":
    print(f"Starting on port {PORT} - APP_ENV={APP_ENV}")
    with http.server.HTTPServer(("", PORT), Handler) as srv:
        srv.serve_forever()
