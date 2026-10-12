#!/usr/bin/env python3
"""Local test server for the signed updater (client/MANIFEST.md "Signed updater", tests). TESTS ONLY: production
serves the update folder from the website over HTTPS (website/README.md "Client updates").

  python3 -I client/tools/serve_updates.py PUBLISH_DIR [--port 8095] [--rate KBPS] [--latency MS]
          [--no-range] [--drop-every N] [--cert CERT --certkey KEY]

Serves PUBLISH_DIR (manifest.json, files/xx/<sha256>) with HTTP range requests (206), like a web server does.
--rate: bytes per second per connection in KB (simulates a real link; parallel requests then add up);
--latency: delay before each answer; --no-range: ignore Range (answers 200 with the whole file);
--drop-every N: cut every Nth file response in the middle (tests retries and resume);
--cert/--certkey: HTTPS with that certificate (self-signed is fine for a local test if the client trusts it).
"""
import argparse, http.server, os, re, ssl, sys, threading, time

state = {'count': 0, 'lock': threading.Lock()}


def make_handler(root, rate, latency, no_range, drop_every):
    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def log_message(self, fmt, *args):
            sys.stderr.write('%s %s\n' % (self.log_date_time_string(), fmt % args))

        def do_GET(self):
            path = self.path.split('?', 1)[0]
            if not re.fullmatch(r'/(manifest\.json|files/[0-9a-f]{2}/[0-9a-f]{64})', path):
                return self.send_error(404)
            full = os.path.join(root, path.lstrip('/'))
            if not os.path.isfile(full):
                return self.send_error(404)
            size = os.path.getsize(full)
            start, end, status = 0, size - 1, 200
            rng = self.headers.get('Range')
            if rng and not no_range:
                m = re.fullmatch(r'bytes=(\d+)-(\d*)', rng.strip())
                if not m or int(m.group(1)) >= size:
                    self.send_response(416)
                    self.send_header('Content-Range', f'bytes */{size}')
                    self.send_header('Content-Length', '0')
                    self.end_headers()
                    return
                start = int(m.group(1))
                end = min(int(m.group(2)) if m.group(2) else size - 1, size - 1)
                status = 206
            if latency:
                time.sleep(latency / 1000)
            length = end - start + 1
            drop = False
            if drop_every and path.startswith('/files/'):
                with state['lock']:
                    state['count'] += 1
                    drop = state['count'] % drop_every == 0
            self.send_response(status)
            self.send_header('Content-Length', str(length))
            self.send_header('Accept-Ranges', 'none' if no_range else 'bytes')
            if status == 206:
                self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
            self.send_header('Cache-Control', 'no-cache' if path == '/manifest.json' else 'public, max-age=31536000, immutable')
            self.send_header('Connection', 'close')
            self.end_headers()
            sent, block = 0, 64 * 1024
            t0 = time.monotonic()
            with open(full, 'rb') as f:
                f.seek(start)
                while sent < length:
                    if drop and sent >= length // 2:
                        self.connection.shutdown(2)  # cut mid-body: the client must retry/resume
                        return
                    data = f.read(min(block, length - sent))
                    if not data:
                        break
                    try:
                        self.wfile.write(data)
                    except (BrokenPipeError, ConnectionResetError):
                        return
                    sent += len(data)
                    if rate:
                        ahead = sent / (rate * 1024) - (time.monotonic() - t0)
                        if ahead > 0:
                            time.sleep(ahead)
            self.close_connection = True

    return Handler


def main():
    ap = argparse.ArgumentParser(description='local test server for the signed updater (tests only)')
    ap.add_argument('root')
    ap.add_argument('--host', default='127.0.0.1')
    ap.add_argument('--port', type=int, default=8095)
    ap.add_argument('--rate', type=float, default=0)
    ap.add_argument('--latency', type=int, default=0)
    ap.add_argument('--no-range', action='store_true')
    ap.add_argument('--drop-every', type=int, default=0)
    ap.add_argument('--cert')
    ap.add_argument('--certkey')
    a = ap.parse_args()
    handler = make_handler(os.path.abspath(a.root), a.rate, a.latency, a.no_range, a.drop_every)
    srv = http.server.ThreadingHTTPServer((a.host, a.port), handler)
    scheme = 'http'
    if a.cert:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(a.cert, a.certkey)
        srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
        scheme = 'https'
    print(f'serving {a.root} at {scheme}://{a.host}:{a.port}/manifest.json (tests only)', flush=True)
    srv.serve_forever()


if __name__ == '__main__':
    main()
