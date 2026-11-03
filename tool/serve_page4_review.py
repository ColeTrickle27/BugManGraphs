"""Loopback-only synthetic Graphs preview; no external services or production writes."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import re

class ReviewHandler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, '.mjs': 'application/javascript'}
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()
    def translate_path(self, path):
        if path.startswith('/review/'):
            name = path.split('?', 1)[0].removeprefix('/review/')
            if re.fullmatch(r'(standard|wide|tall)(-reference|-parity)?\.(pdf|png|json)', name):
                return str(self.exports / name)
        return super().translate_path(path)
    def do_POST(self):
        match = re.fullmatch(r'/__review/((standard|wide|tall)(-reference|-parity)?\.(pdf|png|json))', self.path)
        length = int(self.headers.get('Content-Length', '0'))
        if not match or length < 0 or length > 100 * 1024 * 1024:
            self.send_error(400)
            return
        self.exports.mkdir(parents=True, exist_ok=True)
        (self.exports / match[1]).write_bytes(self.rfile.read(length))
        self.send_response(200)
        self.end_headers()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', default=str(Path(__file__).resolve().parents[1] / 'build/web'))
    parser.add_argument('--exports', default=str(Path(__file__).resolve().parents[1] / 'artifacts/page4/exports'))
    parser.add_argument('--port', type=int, default=8794)
    args = parser.parse_args()
    ReviewHandler.exports = Path(args.exports).resolve()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), partial(ReviewHandler, directory=str(Path(args.root).resolve())))
    print(f'Graphs isolated preview: http://127.0.0.1:{args.port}/', flush=True)
    server.serve_forever()
