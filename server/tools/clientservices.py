#!/usr/bin/env python3
"""Client services endpoint for the login screen (boosted creature/boss, event calendar, players online).

usage: python3 clientservices.py [JSON_FILE] [--port 8090] [--host 0.0.0.0]

JSON_FILE defaults to ../data/chaos_clientservices.json next to this tool; the game server writes it
(data/scripts/chaos/clientservices.lua). The client posts {"type": "boostedcreature" | "eventschedule" |
"cacheinfo"} to the URL configured as clientServicesLink in the client's init.lua and gets the matching
part of that file back. Any path is accepted, so the link can be http://host:8090/clientservices.
Standard library only; it serves the file as it is on every request, so it never needs a restart.
"""
import argparse
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TYPES = ('boostedcreature', 'eventschedule', 'cacheinfo')
EMPTY = {
    'boostedcreature': {},
    'eventschedule': {'eventlist': []},
    'cacheinfo': {'playersonline': 0, 'online': '0 players online'},
}


def load(path):
    try:
        with open(path, encoding='utf-8') as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def answer(data, kind):
    part = data.get(kind)
    # the Lua encoder writes an empty table as [], the client wants an object
    if not isinstance(part, dict):
        part = EMPTY[kind]
    return part


class Handler(BaseHTTPRequestHandler):
    server_version = 'ChaosClientServices/1.0'
    timeout = 10  # seconds per connection: a client that sends nothing (or too slowly) does not hold a thread forever
    data_file = None

    def _send(self, code, payload):
        body = json.dumps(payload).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        # the browser client (future) calls this from another origin
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self._send(204, {})

    def do_GET(self):
        # handy for checking the endpoint from a browser: /?type=eventschedule, or everything
        kind = None
        if '?' in self.path:
            for pair in self.path.split('?', 1)[1].split('&'):
                key, _, value = pair.partition('=')
                if key == 'type':
                    kind = value
        data = load(self.data_file)
        if kind in TYPES:
            self._send(200, answer(data, kind))
        else:
            self._send(200, {k: answer(data, k) for k in TYPES})

    def do_POST(self):
        try:
            length = int(self.headers.get('Content-Length') or 0)
        except ValueError:
            length = -1
        if length < 0 or length > 64 * 1024:
            self._send(413, {'error': 'request too large'})
            return
        try:
            request = json.loads(self.rfile.read(length) or b'{}')
        except ValueError:
            self._send(400, {'error': 'invalid json'})
            return
        kind = request.get('type') if isinstance(request, dict) else None
        if kind not in TYPES:
            self._send(400, {'error': 'unknown type', 'types': list(TYPES)})
            return
        self._send(200, answer(load(self.data_file), kind))

    def log_message(self, fmt, *args):
        sys.stderr.write('[clientservices] %s %s\n' % (self.address_string(), fmt % args))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('file', nargs='?', default=os.path.join(here, '..', 'data', 'chaos_clientservices.json'))
    parser.add_argument('--port', type=int, default=8090)
    parser.add_argument('--host', default='0.0.0.0')
    args = parser.parse_args()
    Handler.data_file = os.path.abspath(args.file)
    print('serving %s on http://%s:%d/' % (Handler.data_file, args.host, args.port), flush=True)
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == '__main__':
    main()
