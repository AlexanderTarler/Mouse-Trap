"""Serves the web build locally the way itch.io does with "SharedArrayBuffer
support" ticked (the build needs it: Godot's threaded web template, which
TerraBrush's web library requires): with cross-origin isolation headers.

    python tools/serve_web.py          # then open http://localhost:8060
"""
import http.server
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8060
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web"))


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        super().end_headers()


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
