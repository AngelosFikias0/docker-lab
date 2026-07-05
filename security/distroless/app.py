import http.server
import socketserver

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"ok\n")

    def log_message(self, format, *args):
        pass

with socketserver.TCPServer(("", 8080), Handler) as httpd:
    httpd.serve_forever()
