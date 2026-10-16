#!/usr/bin/env python3
"""Serves the admin panel locally without browser caching, so changes to the
panel always show up on reload. Usage: python3 serve.py [port]"""
import http.server
import sys


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8081
    print(f'Woops admin: http://localhost:{port}')
    http.server.ThreadingHTTPServer(('127.0.0.1', port), NoCacheHandler).serve_forever()
