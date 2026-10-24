#!/usr/bin/env python3
"""The same requests against server/tools/clientservices.py and the Rust port; the answers must match.

Starts both on free local ports with one data file, sends raw bytes (well-formed and broken requests), and compares
the status, the JSON body, and the headers the client relies on. Where the port is stricter on purpose (see
server/README.md "Rust services (O153)") the case says so and checks the Rust side alone.

Run: python3 -I server/services/clientservices-rs/compare_test.py [--bin PATH]
The binary: --bin, else $CLIENTSERVICES_RS_BIN, else target/release|debug/clientservices-rs next to this file.
Standard library only."""
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PY = os.path.join(HERE, '..', '..', 'tools', 'clientservices.py')

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL: ' + what)


def find_bin():
    if '--bin' in sys.argv:
        return sys.argv[sys.argv.index('--bin') + 1]
    if os.environ.get('CLIENTSERVICES_RS_BIN'):
        return os.environ['CLIENTSERVICES_RS_BIN']
    target = os.environ.get('CARGO_TARGET_DIR') or os.path.join(HERE, 'target')
    for kind in ('release', 'debug'):
        p = os.path.join(target, kind, 'clientservices-rs')
        if os.path.isfile(p):
            return p
    print('clientservices compare_test: no binary (cargo build --locked first, or --bin PATH)')
    sys.exit(1)


def free_port():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    port = s.getsockname()[1]
    s.close()
    return port


def start(cmd, port):
    p = subprocess.Popen(cmd + ['--host', '127.0.0.1', '--port', str(port)], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)
    for _ in range(100):
        try:
            socket.create_connection(('127.0.0.1', port), 0.2).close()
            return p
        except OSError:
            time.sleep(0.05)
    p.kill()
    raise SystemExit('server did not start: %s' % cmd)


def talk(port, raw, timeout=5):
    """Sends raw bytes, reads until the server closes; returns (status, headers dict lower-case, body bytes)."""
    s = socket.create_connection(('127.0.0.1', port), timeout)
    try:
        if raw:
            s.sendall(raw)
        s.shutdown(socket.SHUT_WR)
    except OSError:
        pass
    buf = b''
    try:
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
    except OSError:
        pass
    s.close()
    if not buf:
        return None, {}, b''
    if not buf.startswith(b'HTTP/'):
        # Python before 3.13 answers a request line it cannot parse in HTTP/0.9 style: the bare error page, no
        # status line and no headers; the code is in the page
        m = re.search(rb'Error code: (\d{3})', buf)
        return (int(m.group(1)) if m else -1), {}, buf
    head, _, body = buf.partition(b'\r\n\r\n')
    lines = head.decode('latin-1').split('\r\n')
    status = int(lines[0].split()[1])
    headers = {}
    for ln in lines[1:]:
        k, _, v = ln.partition(':')
        headers[k.strip().lower()] = v.strip()
    return status, headers, body


def post(body, extra=b''):
    return b'POST /clientservices HTTP/1.1\r\nHost: x\r\nContent-Length: ' + str(len(body)).encode() + b'\r\n' + extra + b'\r\n' + body


DATA = {
    'boostedcreature': {'name': 'Rotworm', 'looktype': 26, 'text': 'café ü'},
    'eventschedule': {'eventlist': [{'name': 'Double XP', 'startdate': 1, 'enddate': 2}]},
    'cacheinfo': {'playersonline': 12, 'online': '12 players online'},
}

# (name, raw request, compare the body JSON too)
CASES = [
    ('GET /', b'GET / HTTP/1.1\r\nHost: x\r\n\r\n'),
    ('GET any path', b'GET /clientservices HTTP/1.0\r\n\r\n'),
    ('GET type=eventschedule', b'GET /?type=eventschedule HTTP/1.1\r\n\r\n'),
    ('GET type=cacheinfo&x=1', b'GET /a?x=1&type=cacheinfo HTTP/1.1\r\n\r\n'),
    ('GET type last wins', b'GET /?type=cacheinfo&type=boostedcreature HTTP/1.1\r\n\r\n'),
    ('GET unknown type is everything', b'GET /?type=nope HTTP/1.1\r\n\r\n'),
    ('GET type without value', b'GET /?type HTTP/1.1\r\n\r\n'),
    ('GET percent is not decoded', b'GET /?type=cache%69nfo HTTP/1.1\r\n\r\n'),
    ('GET bare LF line ends', b'GET /?type=cacheinfo HTTP/1.1\nHost: x\n\n'),
    ('GET no headers, no blank line', b'GET /?type=cacheinfo HTTP/1.1\r\n'),
    ('POST boostedcreature', post(b'{"type": "boostedcreature"}')),
    ('POST eventschedule', post(b'{"type":"eventschedule"}')),
    ('POST cacheinfo with extra keys', post(b'{"type":"cacheinfo","x":[1,2,{"y":null}]}')),
    ('POST unknown type', post(b'{"type": "nope"}')),
    ('POST type is a number', post(b'{"type": 5}')),
    ('POST type is a list', post(b'{"type": ["cacheinfo"]}')),
    ('POST no type', post(b'{}')),
    ('POST not an object', post(b'[1,2]')),
    ('POST a string', post(b'"cacheinfo"')),
    ('POST invalid json', post(b'{"type": ')),
    ('POST not utf-8', post(b'{"type": "\xff\xfe"}')),
    ('POST empty body, length 0', b'POST / HTTP/1.1\r\nContent-Length: 0\r\n\r\n'),
    ('POST no Content-Length', b'POST / HTTP/1.1\r\n\r\n'),
    ('POST Content-Length padded', b'POST / HTTP/1.1\r\nContent-Length:   26  \r\n\r\n{"type": "boostedcreature"}'),
    ('POST Content-Length 65537', b'POST / HTTP/1.1\r\nContent-Length: 65537\r\n\r\n'),
    ('POST Content-Length huge', b'POST / HTTP/1.1\r\nContent-Length: 99999999999999999999999\r\n\r\n'),
    ('POST Content-Length negative', b'POST / HTTP/1.1\r\nContent-Length: -1\r\n\r\n'),
    ('POST Content-Length words', b'POST / HTTP/1.1\r\nContent-Length: abc\r\n\r\n'),
    ('POST Content-Length 65536 short body', b'POST / HTTP/1.1\r\nContent-Length: 65536\r\n\r\n{"type":"cacheinfo"}'),
    ('POST first Content-Length wins', b'POST / HTTP/1.1\r\nContent-Length: 0\r\nContent-Length: 20\r\n\r\n{"type":"cacheinfo"}'),
    ('POST header name case', b'POST / HTTP/1.1\r\ncontent-LENGTH: 20\r\n\r\n{"type":"cacheinfo"}'),
    ('POST body shorter than length', b'POST / HTTP/1.1\r\nContent-Length: 40\r\n\r\n{"type":"cacheinfo"}'),
    ('POST body longer than length', b'POST / HTTP/1.1\r\nContent-Length: 20\r\n\r\n{"type":"cacheinfo"} trailing'),
    ('POST header line without a colon', b'POST / HTTP/1.1\r\nbroken line\r\nContent-Length: 20\r\n\r\n{"type":"cacheinfo"}'),
    ('OPTIONS', b'OPTIONS / HTTP/1.1\r\n\r\n', False),
    ('PUT', b'PUT / HTTP/1.1\r\n\r\n', False),
    ('DELETE', b'DELETE / HTTP/1.1\r\n\r\n', False),
    ('HEAD', b'HEAD / HTTP/1.1\r\n\r\n', False),
    ('lower-case method', b'get / HTTP/1.1\r\n\r\n', False),
    ('HTTP/2.0', b'GET / HTTP/2.0\r\n\r\n', False),
    ('HTTP/1.x garbage', b'GET / HTTP/1.x\r\n\r\n', False),
    ('not HTTP', b'GET / FTP/1.0\r\n\r\n', False),
    ('four words', b'GET / HTTP/1.1 extra\r\n\r\n', False),
    ('binary junk', bytes(range(256)) + b'\r\n\r\n', False),
    ('request line too long', b'GET /' + b'a' * 70000 + b' HTTP/1.1\r\n\r\n', False),
    ('header line too long', b'GET / HTTP/1.1\r\nX: ' + b'a' * 70000 + b'\r\n\r\n', False),
    ('101 headers', b'GET / HTTP/1.1\r\n' + b''.join(b'X%d: 1\r\n' % i for i in range(101)) + b'\r\n', False),
    ('100 headers', b'GET / HTTP/1.1\r\n' + b''.join(b'X%d: 1\r\n' % i for i in range(100)) + b'\r\n'),
    ('empty connection', b''),
    ('blank line only', b'\r\n', False),
]

# the Rust side is stricter or simpler on purpose: the status must match unless noted, the body is not compared
RUST_ONLY = [
    # name, raw, wanted status
    ('HTTP/0.9 request line (not served)', b'GET /\r\n\r\n', 400),
    ('headers beyond 128 KiB together', b'GET / HTTP/1.1\r\n' + b''.join(b'X%d: %s\r\n' % (i, b'a' * 4000) for i in range(40)) + b'\r\n', 431),
]


def sub_compare(name, py, rs, body_too):
    ps, ph, pb = py
    rstat, rh, rb = rs
    if name.endswith('empty connection') or name.endswith('blank line only'):
        check(ps is None and rstat is None, '%s: both close without an answer (%r, %r)' % (name, ps, rstat))
        return
    check(ps == rstat, '%s: status python %r, rust %r' % (name, ps, rstat))
    check(rh.get('access-control-allow-origin') == '*', '%s: rust CORS origin' % name)
    check(int(rh.get('content-length', -1)) == len(rb), '%s: rust Content-Length matches its body' % name)
    check('date' in rh and rh.get('server', '').startswith('ChaosClientServices'), '%s: rust Date and Server' % name)
    if ps == 200 or ps == 400 and body_too:
        check(rh.get('content-type') == 'application/json', '%s: rust content type' % name)
        try:
            check(json.loads(pb) == json.loads(rb), '%s: body python %r, rust %r' % (name, pb[:120], rb[:120]))
        except ValueError:
            check(False, '%s: a body is not JSON (%r / %r)' % (name, pb[:60], rb[:60]))
    if ps == 204:
        check(rh.get('access-control-allow-headers') == 'Content-Type', '%s: allow headers' % name)


def main():
    rbin = find_bin()
    tmp = tempfile.mkdtemp(prefix='cs-compare-')
    datafile = os.path.join(tmp, 'chaos_clientservices.json')
    procs = []
    try:
        with open(datafile, 'w', encoding='utf-8') as f:
            json.dump(DATA, f)
        pp, rp = free_port(), free_port()
        procs.append(start([sys.executable, '-I', PY, datafile], pp))
        procs.append(start([rbin, datafile], rp))

        def run_cases(label):
            for case in CASES:
                name, raw = case[0], case[1]
                body_too = case[2] if len(case) > 2 else True
                sub_compare(label + name, talk(pp, raw), talk(rp, raw), body_too)

        # normal file
        run_cases('')
        # spot checks on what the answers must contain, so two equal wrong answers cannot pass
        st, _, body = talk(rp, b'GET /?type=cacheinfo HTTP/1.1\r\n\r\n')
        check(st == 200 and json.loads(body) == DATA['cacheinfo'], 'rust: cacheinfo is the file part')
        st, _, body = talk(rp, post(b'{"type":"nope"}'))
        check(st == 400 and json.loads(body) == {'error': 'unknown type',
                                                 'types': ['boostedcreature', 'eventschedule', 'cacheinfo']},
              'rust: unknown type answer')
        st, _, body = talk(rp, post(b'{'))
        check(st == 400 and json.loads(body) == {'error': 'invalid json'}, 'rust: invalid json answer')
        st, _, body = talk(rp, b'POST / HTTP/1.1\r\nContent-Length: 70000\r\n\r\n')
        check(st == 413 and json.loads(body) == {'error': 'request too large'}, 'rust: 413 answer')
        st, h, body = talk(rp, b'OPTIONS / HTTP/1.1\r\n\r\n')
        check(st == 204 and body == b'', 'rust: OPTIONS is 204 with no body')
        for name, raw, want in RUST_ONLY:
            st, _, _ = talk(rp, raw)
            check(st == want, 'rust only, %s: status %r, wanted %r' % (name, st, want))

        # the other shapes of the file; the data is read on every request
        variants = {
            'parts are [] (Lua empty table)': {'boostedcreature': [], 'eventschedule': [], 'cacheinfo': []},
            'parts are wrong types': {'boostedcreature': 'x', 'eventschedule': 5, 'cacheinfo': None},
            'parts missing': {},
            'extra keys': dict(DATA, extra={'a': 1}),
        }
        for label, data in variants.items():
            with open(datafile, 'w', encoding='utf-8') as f:
                json.dump(data, f)
            run_cases(label + ': ')
        for label, text in (('top level is an array', '[1, 2]'), ('not JSON', 'garbage{'), ('empty file', ''),
                            ('top level is a string', '"x"')):
            with open(datafile, 'w', encoding='utf-8') as f:
                f.write(text)
            run_cases(label + ': ')
        os.remove(datafile)
        run_cases('file missing: ')
        # a big file is ignored by the port (16 MiB); the Python service serves it, so rust alone
        with open(datafile, 'w', encoding='utf-8') as f:
            f.write('{"cacheinfo": {"pad": "' + 'a' * (17 * 1024 * 1024) + '"}}')
        st, _, body = talk(rp, b'GET /?type=cacheinfo HTTP/1.1\r\n\r\n')
        check(st == 200 and json.loads(body) == {'playersonline': 0, 'online': '0 players online'},
              'rust: a file over 16 MiB is ignored (the empty answer)')

        # a slow client does not stop the others (one thread per connection)
        slow = socket.create_connection(('127.0.0.1', rp), 5)
        slow.sendall(b'GET / HTTP/1.1\r\nX-Slow: ')
        with open(datafile, 'w', encoding='utf-8') as f:
            json.dump(DATA, f)
        st, _, _ = talk(rp, b'GET / HTTP/1.1\r\n\r\n')
        check(st == 200, 'rust: a half-sent request does not block another')
        slow.close()

        # the command line
        r = subprocess.run([rbin, '--bogus'], capture_output=True, timeout=10)
        check(r.returncode == 2, 'rust: an unknown option exits 2')
        r = subprocess.run([rbin, '--port', 'x'], capture_output=True, timeout=10)
        check(r.returncode == 2, 'rust: a bad port exits 2')
        busy = socket.socket()
        busy.bind(('127.0.0.1', 0))
        busy.listen(1)
        r = subprocess.run([rbin, datafile, '--host', '127.0.0.1', '--port', str(busy.getsockname()[1])],
                           capture_output=True, timeout=10)
        check(r.returncode == 1, 'rust: a port in use exits 1')
        busy.close()
        port3 = free_port()
        q = subprocess.Popen([rbin, datafile, '--host=127.0.0.1', '--port=%d' % port3], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL)
        procs.append(q)
        line = q.stdout.readline().decode()
        check(line.startswith('serving ') and line.rstrip().endswith('http://127.0.0.1:%d/' % port3),
              'rust: the start line %r' % line)
    finally:
        for p in procs:
            p.kill()
            p.wait()
        shutil.rmtree(tmp, ignore_errors=True)
    print('clientservices compare_test: %s' % ('ok' if not failed else '%d failure(s)' % failed))
    sys.exit(1 if failed else 0)


main()
