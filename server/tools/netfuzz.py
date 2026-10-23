#!/usr/bin/env python3
"""Network fuzzer: malformed login and game packets against a running TEST server, until it crashes or hangs.

server/README.md "Engine hardening (sanitizers, fuzzing)". Standard library only. It reuses the protocol code of
loadtest.py (framing, adler32, XTEA, RSA, the client guard answer) and the bot accounts that `loadtest.py setup`
creates (loadbot accounts, password "loadbot"). Run it against the AddressSanitizer build of
server/tools/build_sanitized.sh: a memory error then ends the server with a report instead of passing unseen.

  python3 -I server/tools/netfuzz.py --host 127.0.0.1 --port 7171 --key SERVER/key.pem [--game-port 7172]
      [--dev-key | --client-key HEX] [--duration 1800] [--workers 4] [--seed N] [--server-pid PID]
      [--bots FIRST,COUNT] [--families raw,login,game,ingame] [--log FILE] [--cases N] [--replay SEED:CASE]

Every case is made from its own random generator, seeded with "SEED:CASE", so `--replay SEED:CASE` sends exactly the
same bytes again (the in-game cases also depend on the server's answers, such as the challenge). Families:
  raw     login port: random bytes, length headers that lie (0, 1, 65535, more or fewer bytes than said), a wrong
          checksum, every protocol id with a random body, the status protocol (0xFF) with random requests, PROXY
          protocol headers from an untrusted address, a packet sent a byte at a time, a connection that sends nothing
  login   login packets with a valid frame: a bad or short RSA block, valid RSA around mutated plain text (string
          lengths of 0 / 65535 / past the block, no leading zero, huge names), the second RSA block missing or bad,
          odd protocol versions and client ids, OTCv8 markers cut short, trailing bytes
  game    the game port: garbage instead of the login, game logins with valid RSA around a mutated session string
          (missing parts, a token time that does not fit, wrong challenge), huge or empty character names
  ingame  a bot of --bots logs in for real (character list, game login, client guard answer) and sends 5-60 packets:
          the game opcodes with random fields (positions, stack positions, item ids, creature ids, strings of 0-9000
          bytes), cut short, random opcodes with random bodies, extended opcodes (0x32) to every Chaos and base opcode with
          random bytes or odd JSON, malformed client guard answers (opcode 189), XTEA frames with a bad inner length or
          size, plain bytes after the session; then it logs out, drops the connection, or logs in again at once
Detection: every 5 s a probe logs in on the login server with the first bot of --bots (the character list must come
within 30 s; 3 misses in a row = a hang) and, with --server-pid, checks that the process lives. On a hit it prints
the last 40 cases (seed:case, family, kind) and stops with exit code 1; exit code 0 = the time ran out without one.
--log FILE gets one line per case. The bots of --bots must not be the ones a parallel loadtest.py run uses.
Never point it at a live server: it logs bots in, makes them trade, move items and post market offers at random.
"""
import argparse
import collections
import json
import os
import random
import socket
import struct
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import loadtest as LT  # noqa: E402  (framing, XTEA, RSA, the client guard answer)

CHAOS_CONSTANTS = os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'chaos_constants.lua')
PROBE_EVERY = 5.0
PROBE_TIMEOUT = 30.0
PROBE_MISSES = 3


# ------------------------------------------------------------------------------------------------ helpers
def chaos_opcodes():
    """the extended opcodes the Chaos scripts use (chaos_constants.lua ChaosOpcodes), plus the admin's 120 and the base
    server's own handlers (language 1, fusion 67, highscores 73, crafting 91, tasks 92, reputation 99, character stats
    106, inspect 107, party icons 136, upgrades 181, store 201, tier maps 202)"""
    found = {120, 1, 67, 73, 91, 92, 99, 106, 107, 136, 181, 201, 202}
    try:
        text = open(CHAOS_CONSTANTS, encoding='utf-8').read()
    except OSError:
        return sorted(found | set(range(150, 215)))
    import re
    body = re.search(r'^ChaosOpcodes = \{(.*?)^\}', text, re.S | re.M)
    for m in re.finditer(r'\b[A-Za-z_]\w*\s*=\s*(\d+)', body.group(1) if body else ''):
        found.add(int(m.group(1)))
    for m in re.finditer(r'^ChaosOpcodes\.\w+\s*=\s*(\d+)', text, re.M):
        found.add(int(m.group(1)))
    return sorted(v for v in found if 0 < v < 256)


def frame(body, checksum=True):
    packet = (struct.pack('<I', LT.adler32(body)) if checksum else b'') + body
    return struct.pack('<H', len(packet) & 0xFFFF) + packet


def xtea_frame(payload, key, inner=None, pad=True):
    inner_len = len(payload) if inner is None else inner
    data = struct.pack('<H', inner_len & 0xFFFF) + payload
    if pad:
        data += b'\x00' * ((8 - len(data) % 8) % 8)
        data = LT.xtea_encrypt(data, key)
    return frame(data)


def recv_exact(sock, n, deadline):
    buf = b''
    while len(buf) < n:
        left = deadline - time.monotonic()
        if left <= 0:
            raise socket.timeout('timed out')
        sock.settimeout(left)
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError('closed by the server')
        buf += chunk
    return buf


def recv_message(sock, timeout):
    deadline = time.monotonic() + timeout
    size = struct.unpack('<H', recv_exact(sock, 2, deadline))[0]
    return recv_exact(sock, size, deadline)


def decrypt(body, key):
    plain = LT.xtea_decrypt(body[4:], key)
    inner = struct.unpack_from('<H', plain)[0] if len(plain) >= 2 else 0
    return plain[2:2 + inner]


def rnd_bytes(r, n):
    return bytes(r.getrandbits(8) for _ in range(n))


def rnd_len(r):
    return r.choice([0, 1, 2, 7, 8, 15, 16, 31, 127, 128, 129, 255, 256, 1000, 4096, 8191, 8192, 8193, 9000,
                     r.randrange(0, 300)])


def rnd_string(r, n=None):
    n = rnd_len(r) if n is None else n
    kind = r.random()
    if kind < 0.3:
        return rnd_bytes(r, n)
    if kind < 0.5:
        return (b'%s%n' * 4 + b'\x00\xff\n{}[]"\\')[:n] * (n // 20 + 1)
    return bytes(r.choice(b'abcdefghijklmnopqrstuvwxyz ABCXYZ0123456789!?.,') for _ in range(n))


def lstring(r, data=None, lie=None):
    """u16 length + bytes; with lie: the length field says something else"""
    data = rnd_string(r) if data is None else data
    n = len(data) if lie is None else lie
    return struct.pack('<H', n & 0xFFFF) + data[:65535]


def rnd_pos(r, near=None):
    if near and r.random() < 0.5:
        x, y, z = near
        return struct.pack('<HHB', (x + r.randint(-9, 9)) & 0xFFFF, (y + r.randint(-7, 7)) & 0xFFFF, z)
    choice = r.random()
    if choice < 0.3:
        return struct.pack('<HHB', 0xFFFF, r.choice([0, 1, 64, 65535, r.getrandbits(16)]), r.getrandbits(8))
    if choice < 0.5:
        return struct.pack('<HHB', r.getrandbits(16), r.getrandbits(16), r.choice([0, 7, 15, 16, 255]))
    return struct.pack('<HHB', r.randint(0, 70000) & 0xFFFF, r.randint(0, 70000) & 0xFFFF, r.randint(0, 15))


def rnd_u8(r):
    return bytes([r.choice([0, 1, 2, 9, 10, 15, 16, 63, 64, 127, 128, 254, 255, r.getrandbits(8)])])


def rnd_u16(r):
    return struct.pack('<H', r.choice([0, 1, 100, 255, 256, 2000, 26000, 40000, 65534, 65535, r.getrandbits(16)]))


def rnd_u32(r, ids=()):
    if ids and r.random() < 0.4:
        return struct.pack('<I', r.choice(ids))
    return struct.pack('<I', r.choice([0, 1, 0x10000000, 0x40000000, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF,
                                       r.getrandbits(32)]))


# the client packets of ProtocolGame::parsePacket and their fields (protocol 10.98, OTCv8 extras)
FIELDS = {
    0x1D: '', 0x1E: '', 0x42: 'bb', 0x64: 'walk', 0x65: '', 0x66: '', 0x67: '', 0x68: '', 0x69: '', 0x6A: '',
    0x6B: '', 0x6C: '', 0x6D: '', 0x6F: '', 0x70: '', 0x71: '', 0x72: '', 0x77: 'hb', 0x78: 'phbpb', 0x79: 'hb',
    0x7A: 'hbbbb', 0x7B: 'hbbb', 0x7C: '', 0x7D: 'phbi', 0x7E: 'bb', 0x7F: '', 0x80: '', 0x82: 'phbb',
    0x83: 'phbphb', 0x84: 'phbi', 0x85: 'phb', 0x87: 'b', 0x88: 'b', 0x89: 'is', 0x8A: 'bis', 0x8B: 'phb',
    0x8C: 'phb', 0x8D: 'i', 0x8E: '', 0x96: 'say', 0x97: '', 0x98: 'h', 0x99: 'h', 0x9A: 's', 0x9E: '',
    0x9F: 'tip', 0xA0: 'bbbb', 0xA1: 'ii', 0xA2: 'ii', 0xA3: 'i', 0xA4: 'i', 0xA5: 'i', 0xA6: 'i', 0xA7: '',
    0xA8: 'b', 0xAA: '', 0xAB: 's', 0xAC: 's', 0xBE: '', 0xC9: 'p', 0xCA: 'b', 0xCB: 'p', 0xCC: 'bh', 0xD2: '',
    0xD3: 'hbbbbbhhhs', 0xD4: 'bbbb', 0xDC: 's', 0xDD: 'i', 0xDE: 'isib', 0xE6: 'bsp', 0xE7: '', 0xE8: 'ssss',
    0xF0: '', 0xF1: 'h', 0xF2: 'bbsssi', 0xF3: '', 0xF4: '', 0xF5: 'hh', 0xF6: 'bhhib', 0xF7: 'ih', 0xF8: 'ihh',
    0xF9: 'ibb',
}
SAFE_SKIP = {0x14, 0x0F}  # logout and enter: the case decides when to leave


def field_bytes(r, spec, state):
    out = b''
    for f in spec:
        if f == 'b':
            out += rnd_u8(r)
        elif f == 'h':
            out += rnd_u16(r)
        elif f == 'i':
            out += rnd_u32(r, state.get('ids', ()))
        elif f == 'p':
            out += rnd_pos(r, state.get('pos'))
        elif f == 's':
            lie = state.get('dirty') and r.random() < 0.15
            out += lstring(r, lie=r.choice([65535, 9000, 300])) if lie else lstring(r)
    return out


def game_packet(r, state):
    choice = r.random()
    if choice < 0.55:
        op = r.choice(sorted(FIELDS))
        spec = FIELDS[op]
        if spec == 'walk':
            n = r.choice([0, 1, 2, 50, 255])
            body = bytes([n]) + bytes(r.randint(0, 9) for _ in range(n if r.random() < 0.7 else r.randint(0, 255)))
        elif spec == 'say':
            kind = r.getrandbits(8) if r.random() < 0.3 else r.choice([1, 2, 3, 4, 5, 6, 7, 9, 11, 12, 13, 34, 36])
            body = bytes([kind])
            if r.random() < 0.5:
                body += lstring(r)
            if r.random() < 0.5:
                body += rnd_u16(r)
            body += lstring(r, data=r.choice([b'utevo lux', b'exura', b'!online', b'/a 1', b'hi', b'trade',
                                              rnd_string(r)]))
        elif spec == 'tip':
            body = rnd_u8(r) + rnd_u16(r) + rnd_u16(r) + rnd_pos(r, state.get('pos')) + rnd_u16(r) + rnd_u8(r)
        else:
            body = field_bytes(r, spec, state)
        if state.get('dirty') and r.random() < 0.2 and body:
            body = body[:r.randrange(len(body))]  # cut short: the engine sees a read past the end and disconnects
        elif r.random() < 0.1:
            body += rnd_bytes(r, r.randint(1, 40))  # trailing bytes
        return 'op %02x' % op, bytes([op]) + body
    if choice < 0.85 or not state.get('dirty'):
        opcode = r.choice(state['opcodes']) if r.random() < 0.85 else r.getrandbits(8)
        return 'ext %d' % opcode, b'\x32' + bytes([opcode]) + lstring(r, data=json_payload(r))
    op = r.getrandbits(8)
    if op in SAFE_SKIP:
        op = 0x8E
    return 'raw %02x' % op, bytes([op]) + rnd_bytes(r, r.randint(0, 64))


ACTIONS = ['open', 'close', 'hello', 'get', 'buy', 'sell', 'state', 'set', 'start', 'join', 'leave', 'list', 'search',
           'tree', 'allocate', 'respec', 'teleport', 'choice', 'choice_apply', 'show', 'claim', 'craft', 'upgrade',
           'invite', 'accept', 'decline', 'mem', 'memset', 'tracker', 'deposit', 'withdraw', 'move', 'equip', 'sort']


def json_value(r, depth=0):
    c = r.random()
    if depth > 3 or c < 0.3:
        return r.choice([0, -1, 1, 2 ** 31, 2 ** 53 + 1, -2 ** 63, 1e308, -0.5, 0.0001, True, False, None, '', 'x' * 300,
                         '\u0000', '../../etc', r.getrandbits(32), rnd_string(r, 20).decode('latin-1')])
    if c < 0.6:
        return [json_value(r, depth + 1) for _ in range(r.randint(0, 5))]
    keys = ['k', 'id', 'slot', 'pos', 'x', 'y', 'z', 'count', 'name', 'tier', 'node', 'clientId', 'choiceId', 'page',
            'item', 'amount', 'price', 'index', 'build', 'modules', 'lang', 'target', 'n', 'tab', 'filter']
    return {r.choice(keys): json_value(r, depth + 1) for _ in range(r.randint(0, 6))}


def json_payload(r):
    c = r.random()
    if c < 0.55:
        obj = {'action': r.choice(ACTIONS) if r.random() < 0.9 else json_value(r)}
        if r.random() < 0.85:
            obj['data'] = json_value(r)
        text = json.dumps(obj)
        if r.random() < 0.1:
            text = text[:r.randrange(len(text) + 1)]  # cut JSON
        return text.encode('utf-8', 'surrogatepass')[:9000]
    if c < 0.7:
        return (b'[' * r.choice([10, 100, 1000, 5000]))  # deep nesting
    if c < 0.8:
        return b'{"action":"' + b'A' * r.choice([300, 8000, 9000]) + b'"}'
    if c < 0.9:
        return r.choice([b'', b'null', b'[]', b'{}', b'"x"', b'1', b'{"action":null}', b'{"action":"open","data":null}',
                         b'S' + rnd_bytes(r, 10), b'E', b'P' + rnd_bytes(r, 30)])
    return rnd_string(r)


# ------------------------------------------------------------------------------------------------ the fuzzer
class Fuzzer:
    def __init__(self, a):
        self.a = a
        self.n = LT.modulus_from_pem(a.key) if a.key else LT.OT_RSA_N
        self.opcodes = chaos_opcodes()
        self.recent = collections.deque(maxlen=40)
        self.lock = threading.Lock()
        self.stop = threading.Event()
        self.hit = None
        self.counts = collections.Counter()
        self.case = 0
        self.logf = open(a.log, 'a') if a.log else None
        first, count = a.bots
        self.bot_pool = list(range(first + 1, first + count))  # the first one is the probe's
        self.bot_free = list(self.bot_pool)
        self.pace = 1.0  # waits are multiplied by it (netfuzz_test.py runs the cases fast against a stand-in server)

    # -- bookkeeping
    def next_case(self):
        with self.lock:
            self.case += 1
            if self.a.cases and self.case > self.a.cases:
                self.stop.set()
            return self.case

    def note(self, case, family, kind):
        line = '%d:%d %s %s' % (self.a.seed, case, family, kind)
        with self.lock:
            self.recent.append(line)
            self.counts[family] += 1
            if self.logf:
                self.logf.write('%.3f %s\n' % (time.time(), line))
                self.logf.flush()

    def source(self, r):
        # a different loopback source per case: the failed-login limits per IP (src-patch 0047) and the two
        # characters per IP rule never see two cases as one player
        return '127.%d.%d.%d' % (r.randint(100, 250), r.randint(0, 255), r.randint(1, 254))

    def connect(self, r, port):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(10)
        if self.a.host.startswith('127.'):
            s.bind((self.source(r), 0))
        s.connect((self.a.host, port))
        return s

    def rsa(self, plain):
        return LT.rsa_block(plain[:128], self.n)

    # -- families
    def case_raw(self, r):
        s = self.connect(r, self.a.port)
        kind = r.choice(['garbage', 'length', 'checksum', 'protocol', 'status', 'proxy', 'slow', 'idle', 'big'])
        if kind == 'garbage':
            s.sendall(rnd_bytes(r, r.randint(1, 600)))
        elif kind == 'length':
            claim = r.choice([0, 1, 2, 3, 4, 5, 8, 65535, 65534, 90459 & 0xFFFF, r.getrandbits(16)])
            s.sendall(struct.pack('<H', claim) + rnd_bytes(r, r.choice([0, 1, 4, 10, 200, 3000])))
            self.sleep(r.choice([0, 0, 0.2, 1.0]))
        elif kind == 'checksum':
            body = b'\x01' + rnd_bytes(r, r.randint(0, 300))
            pkt = frame(body)
            pkt = pkt[:2] + struct.pack('<I', r.getrandbits(32)) + pkt[6:] if r.random() < 0.5 else frame(body, False)
            s.sendall(pkt)
        elif kind == 'protocol':
            s.sendall(frame(bytes([r.getrandbits(8)]) + rnd_bytes(r, r.randint(0, 400)), r.random() < 0.7))
        elif kind == 'status':
            body = b'\xFF' + r.choice([b'\xFFinfo', b'\x01' + rnd_u16(r) + lstring(r), b'\x01\xff\xff', b'',
                                       bytes([r.getrandbits(8)]) + rnd_bytes(r, 20)])
            s.sendall(frame(body, r.random() < 0.5))
        elif kind == 'proxy':
            hdr = r.choice([b'PROXY TCP4 1.2.3.4 5.6.7.8 1 2\r\n', b'PROXY UNKNOWN\r\n', b'PROXY ' + b'A' * 200,
                            b'\r\n\r\n\x00\r\nQUIT\n\x21\x11\x00\x0c' + rnd_bytes(r, 12),
                            b'\r\n\r\n\x00\r\nQUIT\n\x21\x11\xff\xff' + rnd_bytes(r, 100)])
            s.sendall(hdr + frame(b'\x01' + rnd_bytes(r, 50)))
        elif kind == 'slow':
            pkt = frame(b'\x01' + struct.pack('<HHI', 10, 1098, 1098) + rnd_bytes(r, r.randint(0, 280)))
            for i in range(0, len(pkt), r.choice([1, 3, 17])):
                s.sendall(pkt[i:i + 3])
                self.sleep(0.01)
        elif kind == 'idle':
            self.sleep(r.choice([0.5, 2.0]))
        elif kind == 'big':
            s.sendall(struct.pack('<H', 65535) + rnd_bytes(r, 65535))
        self.drain(s, 1.0)
        return kind

    def login_body(self, r, account=None, password=None):
        """the login packet; returns body, kind"""
        kind = r.choice(['rsa-garbage', 'rsa-short', 'rsa-plain', 'strings', 'second', 'version', 'otcv8', 'tail'])
        version = 1098
        client_id = r.choice([1098, (LT.GUARD_TAG << 16) | 1, 0, 0xFFFFFFFF])
        key = [r.getrandbits(32) for _ in range(4)]
        acc = account if account is not None else rnd_string(r, r.choice([0, 1, 8, 30, 120]))
        pw = password if password is not None else rnd_string(r, r.choice([0, 1, 8, 60]))
        p1 = b'\x00' + struct.pack('<4I', *key) + lstring(r, acc) + lstring(r, pw)
        p2 = b'\x00' + lstring(r, b'') + b'\x00'
        tail = b''
        if kind == 'version':
            version = r.choice([0, 1, 760, 761, 970, 971, 1097, 1099, 1100, 65535])
        elif kind == 'strings':
            p1 = b'\x00' + struct.pack('<4I', *key) + lstring(r, acc, lie=r.choice([0, 65535, 127, 128, 200]))
            p1 += lstring(r, pw, lie=r.choice([0, 65535, 100]))
        elif kind == 'rsa-plain':
            p1 = r.choice([b'\x01', b'\xff']) + p1[1:]
        elif kind == 'second':
            p2 = r.choice([b'\x01' + rnd_bytes(r, 10), b'\x00' + lstring(r, lie=65535), b'\x00\xff\xff' + b'A' * 100])
        elif kind == 'otcv8':
            p1 += struct.pack('<H', 5) + r.choice([b'OTCv8', b'OTCv', b'OTCv8\xff\xff', b'XXXXX'])
        elif kind == 'tail':
            tail = rnd_bytes(r, r.choice([1, 7, 128, 129, 1000]))
        head = b'\x01' + struct.pack('<HHI', 10, version, client_id) + struct.pack('<3I', 0, 0, 0) + b'\x00'
        if kind == 'rsa-garbage':
            blocks = rnd_bytes(r, 128) + rnd_bytes(r, 128)
        elif kind == 'rsa-short':
            blocks = self.rsa(p1)[:r.choice([0, 1, 64, 127])]
        elif kind == 'second' and r.random() < 0.4:
            blocks = self.rsa(p1) + r.choice([b'', rnd_bytes(r, 60), rnd_bytes(r, 128)])
        else:
            blocks = self.rsa(p1) + self.rsa(p2)
        return head + blocks + tail, kind

    def case_login(self, r):
        s = self.connect(r, self.a.port)
        body, kind = self.login_body(r)
        s.sendall(frame(body, r.random() < 0.95))
        self.drain(s, 2.0)
        return kind

    def case_game(self, r):
        s = self.connect(r, self.a.game_port)
        kind = r.choice(['garbage', 'session', 'challenge', 'names', 'otcv8', 'short'])
        try:
            msg = recv_message(s, 10)
            ts, rnd = struct.unpack_from('<IB', msg, 7) if len(msg) >= 12 else (0, 0)
        except (OSError, struct.error):
            ts, rnd = 0, 0
        if kind == 'garbage':
            s.sendall(frame(bytes([r.choice([0x0A, 0x01, r.getrandbits(8)])]) + rnd_bytes(r, r.randint(0, 300)),
                            r.random() < 0.8))
            self.drain(s, 1.0)
            return kind
        key = [r.getrandbits(32) for _ in range(4)]
        bot = r.choice(self.bot_pool) if self.bot_pool else 0
        session = '\n'.join(['%s%04d' % (LT.PREFIX, bot), LT.PREFIX, '', str(int(time.time()))]).encode()
        name = LT.bot_name(bot).encode()
        if kind == 'session':
            session = r.choice([b'', b'a', b'a\nb', b'a\nb\nc', b'a\nb\nc\nnotanumber', b'a\nb\nc\n99999999999999999999999',
                                b'a\nb\nc\n-1', b'\n\n\n', b'a\nb\nc\nd\ne', rnd_string(r, 100)])
        elif kind == 'challenge':
            ts, rnd = r.getrandbits(32), r.getrandbits(8)
        elif kind == 'names':
            name = r.choice([b'', b' ', b'A' * 30, rnd_string(r, 40), b'Loadbot\x00Aaa'])
        tail = struct.pack('<H', 0)
        if kind == 'otcv8':
            tail = struct.pack('<H', 5) + b'OTCv8' + struct.pack('<H', r.getrandbits(16))
            tail += r.choice([b'', lstring(r, b'OTCv8TierByte'), lstring(r, b'OTCv8TierByte') + lstring(r, b'A'),
                              lstring(r, b'OTCv8TierByte') + lstring(r, b'A') + rnd_u32(r) + lstring(r, b'C') + rnd_u8(r),
                              lstring(r, lie=65535)])
        plain = (b'\x00' + struct.pack('<4I', *key) + b'\x00' + lstring(r, session) + lstring(r, name)
                 + struct.pack('<IB', ts, rnd) + tail)
        block = self.rsa(plain) if len(plain) <= 128 else rnd_bytes(r, 128)
        if kind == 'short':
            block = block[:r.choice([0, 1, 100, 127])]
        body = (b'\x0A' + struct.pack('<HHI', 10, 1098, r.choice([1098, (LT.GUARD_TAG << 16) | 1, 0]))
                + b'\x00' + struct.pack('<H', 0) + block)
        s.sendall(frame(body))
        self.drain(s, 3.0)
        return kind

    def take_bot(self):
        with self.lock:
            if not self.bot_free:
                return None
            return self.bot_free.pop(random.randrange(len(self.bot_free)))

    def give_bot(self, bot):
        with self.lock:
            self.bot_free.append(bot)

    def login(self, r, bot, probe=False):
        """character list on the login server; returns the session string and the game port"""
        s = self.connect(r, self.a.port) if not probe else self.connect_probe()
        try:
            key = [r.getrandbits(32) for _ in range(4)]
            account = '%s%04d' % (LT.PREFIX, bot)
            p1 = b'\x00' + struct.pack('<4I', *key) + LT.string(account) + LT.string(LT.PREFIX)
            p2 = b'\x00' + LT.string('') + b'\x00'
            body = (b'\x01' + struct.pack('<HHI', 10, 1098, self.a.client_id) + struct.pack('<3I', 0, 0, 0) + b'\x00'
                    + self.rsa(p1) + self.rsa(p2))
            s.sendall(frame(body))
            msg = decrypt(recv_message(s, PROBE_TIMEOUT if probe else 20), key)
        finally:
            s.close()
        i, session = 0, None
        while i < len(msg):
            op = msg[i]
            i += 1
            if op in (0x0A, 0x0B):
                text, i = LT.read_string(msg, i)
                raise RuntimeError('login refused: ' + text)
            if op == 0x0C:
                i += 1
            elif op == 0x14:
                _, i = LT.read_string(msg, i)
            elif op == 0x28:
                session, i = LT.read_string(msg, i)
            else:
                break
        if not session:
            raise RuntimeError('no session key')
        return session

    def connect_probe(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(10)
        if self.a.host.startswith('127.'):
            s.bind(('127.99.0.1', 0))
        s.connect((self.a.host, self.a.port))
        return s

    def enter(self, r, bot, session):
        s = self.connect(r, self.a.game_port)
        msg = recv_message(s, 15)
        ts, rnd = struct.unpack_from('<IB', msg, 7)
        key = [r.getrandbits(32) for _ in range(4)]
        name = LT.bot_name(bot)
        plain = (b'\x00' + struct.pack('<4I', *key) + b'\x00' + LT.string(session) + LT.string(name)
                 + struct.pack('<IB', ts, rnd) + struct.pack('<H', 0))
        body = (b'\x0A' + struct.pack('<HHI', 10, 1098, self.a.client_id) + b'\x00' + struct.pack('<H', 0)
                + self.rsa(plain))
        s.sendall(frame(body))
        first = decrypt(recv_message(s, 30), key)
        if first and first[0] in (0x14, 0x0B, 0x16):
            raise RuntimeError('game refused')
        state = {'pos': None, 'ids': [], 'opcodes': self.opcodes, 'key': key, 'name': name, 'bot': bot}
        if len(first) >= 5 and first[0] == 0x17:
            state['ids'].append(struct.unpack_from('<I', first, 1)[0])
        # the map description (0x64) carries the position
        idx = first.find(b'\x64')
        if idx >= 0 and len(first) >= idx + 6:
            state['pos'] = struct.unpack_from('<HHB', first, idx + 1)
        nonce = LT.find_challenge(first)
        deadline = time.monotonic() + 5
        while nonce is None and self.a.guard_key and time.monotonic() < deadline:
            try:
                nonce = LT.find_challenge(decrypt(recv_message(s, 2), key))
            except (socket.timeout, ConnectionError, struct.error):
                break
        if nonce is not None and self.a.guard_key:
            account = '%s%04d' % (LT.PREFIX, bot)
            if r.random() < 0.95:
                answer = LT.guard_answer(self.a.guard_key, nonce, account, name, self.a.client_build).encode()
            else:
                answer = r.choice([b'', b'cg1:', b'cg1:1:', b'cg1:99999:' + b'0' * 64, b'cg1:1:' + b'g' * 64,
                                   b'cg1:' + b'9' * 30 + b':' + b'0' * 64, rnd_string(r, 70)])
            s.sendall(xtea_frame(b'\x32' + bytes([LT.GUARD_OPCODE]) + LT.string(answer), key))
            hello = json.dumps({'action': 'hello', 'data': {'build': self.a.client_build, 'modules': 99}})
            s.sendall(xtea_frame(b'\x32' + bytes([LT.GUARD_HELLO_OPCODE]) + LT.string(hello), key))
        return s, state

    def case_ingame(self, r):
        bot = self.take_bot()
        if bot is None:
            return self.case_login(r)
        try:
            session = self.login(r, bot)
            s, state = self.enter(r, bot, session)
        except (OSError, RuntimeError, struct.error) as e:
            self.give_bot(bot)
            return 'login failed (%s)' % str(e)[:60]
        kinds = collections.Counter()
        # a dirty session also sends what makes the engine disconnect it (a read past the end, a bad guard answer);
        # a clean one only well-formed packets with odd values, so it lives long enough to reach the game code
        state['dirty'] = r.random() < 0.3
        kinds['dirty' if state['dirty'] else 'clean'] += 1
        try:
            key = state['key']
            for _ in range(r.randint(5, 60)):
                c = r.random() if state['dirty'] else 0
                if c < 0.86:
                    kind, payload = game_packet(r, state)
                    s.sendall(xtea_frame(payload, key))
                elif c < 0.9:
                    kind = 'guard'
                    s.sendall(xtea_frame(b'\x32' + bytes([LT.GUARD_OPCODE]) + lstring(r), key))
                elif c < 0.94:
                    kind = 'xtea inner'
                    payload = bytes([r.choice(sorted(FIELDS))]) + rnd_bytes(r, r.randint(0, 40))
                    s.sendall(xtea_frame(payload, key, inner=r.choice([0, 1, 65535, len(payload) + 8, len(payload) + 100])))
                elif c < 0.97:
                    kind = 'xtea size'
                    s.sendall(frame(rnd_bytes(r, r.choice([1, 7, 9, 15, 17, 100]))))
                else:
                    kind = 'plain'
                    s.sendall(frame(bytes([0x96, 1]) + lstring(r), r.random() < 0.5))
                kinds[kind.split()[0]] += 1
                # under maxPacketsPerSecond (the engine disconnects above it)
                self.drain(s, r.choice([0.02, 0.05, 0.1]))
            end = r.choice(['logout', 'drop', 'drop', 'relogin'])
            if end == 'logout':
                s.sendall(xtea_frame(b'\x14', key))
            self.drain(s, 0.5)
            s.close()
            if end == 'relogin':
                # the same character again at once: the engine's takeover of a lingering character
                try:
                    s2, _ = self.enter(r, bot, self.login(r, bot))
                    self.drain(s2, 0.5)
                    s2.close()
                except (OSError, RuntimeError, struct.error):
                    pass
        except OSError:
            end = 'closed by the server'
        finally:
            self.give_bot(bot)
        return '%s, %s' % (', '.join('%s %d' % kv for kv in sorted(kinds.items())), end)

    def sleep(self, seconds):
        time.sleep(seconds * self.pace)

    def drain(self, s, seconds):
        deadline = time.monotonic() + seconds * self.pace
        try:
            while time.monotonic() < deadline:
                s.settimeout(max(0.01, deadline - time.monotonic()))
                if not s.recv(65536):
                    break
        except OSError:
            pass
        finally:
            if seconds >= 0.5:
                s.close()

    # -- running
    def run_case(self, case, family=None):
        r = random.Random('%d:%d' % (self.a.seed, case))
        family = family or r.choice(self.a.families)
        fn = getattr(self, 'case_' + family)
        try:
            kind = fn(r)
        except (OSError, struct.error, RuntimeError, ValueError) as e:
            kind = 'error: %s' % str(e)[:80]
        self.note(case, family, kind)

    def worker(self):
        while not self.stop.is_set() and time.monotonic() < self.until:
            self.run_case(self.next_case())

    def probe(self):
        misses = 0
        r = random.Random(1)
        while not self.stop.is_set() and time.monotonic() < self.until:
            time.sleep(PROBE_EVERY)
            if self.a.server_pid:
                try:
                    os.kill(self.a.server_pid, 0)
                except OSError:
                    self.hit = 'the server process %d is gone (a crash: see its ASan / UBSan log)' % self.a.server_pid
                    break
                try:
                    with open('/proc/%d/stat' % self.a.server_pid) as f:
                        if f.read().split(')')[-1].split()[0] == 'Z':
                            self.hit = 'the server process %d is a zombie (it died)' % self.a.server_pid
                            break
                except OSError:
                    pass
            try:
                self.login(r, self.a.bots[0], probe=True)
                misses = 0
            except (OSError, RuntimeError, struct.error) as e:
                misses += 1
                print('probe miss %d: %s' % (misses, e), flush=True)
                if misses >= PROBE_MISSES:
                    self.hit = 'the login server did not answer %d probes in a row (a hang or a crash)' % misses
                    break
        self.stop.set()

    def run(self):
        a = self.a
        self.until = time.monotonic() + a.duration
        if a.replay:
            seed, case = a.replay
            a.seed = seed
            self.run_case(case)
            print('\n'.join(self.recent))
            return 0
        threads = [threading.Thread(target=self.worker, daemon=True) for _ in range(a.workers)]
        prober = threading.Thread(target=self.probe, daemon=True)
        for t in threads:
            t.start()
        prober.start()
        t0 = time.monotonic()
        last = 0
        try:
            while not self.stop.is_set() and time.monotonic() < self.until:
                time.sleep(1)
                if time.monotonic() - last >= 30:
                    last = time.monotonic()
                    print('[%5.0f s] %d cases: %s' % (last - t0, self.case, dict(self.counts)), flush=True)
        except KeyboardInterrupt:
            self.stop.set()
        self.stop.set()
        prober.join(PROBE_TIMEOUT + PROBE_EVERY + 5)
        for t in threads:
            t.join(5)
        print('done: %d cases in %.0f s, seed %d: %s' % (self.case, time.monotonic() - t0, a.seed, dict(self.counts)))
        if self.hit:
            print('HIT: ' + self.hit)
            print('the last cases (replay one with --replay SEED:CASE):')
            print('\n'.join('  ' + c for c in self.recent))
            return 1
        return 0


def parse(argv):
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    p.add_argument('--host', default='127.0.0.1')
    p.add_argument('--port', type=int, default=7171)
    p.add_argument('--game-port', type=int, default=7172)
    p.add_argument('--key', help="the server's key.pem (only its modulus is read)")
    p.add_argument('--dev-key', action='store_true', help='answer the client guard with the development key')
    p.add_argument('--client-key', help='answer the client guard with this key (64 hex digits)')
    p.add_argument('--client-build', type=int, default=1)
    p.add_argument('--duration', type=float, default=600)
    p.add_argument('--workers', type=int, default=4)
    p.add_argument('--seed', type=int, default=None)
    p.add_argument('--server-pid', type=int, default=0)
    p.add_argument('--bots', default='900,20', help='FIRST,COUNT of the loadbot accounts to use (the first is the probe)')
    p.add_argument('--families', default='raw,login,game,ingame')
    p.add_argument('--log')
    p.add_argument('--cases', type=int, default=0, help='stop after this many cases')
    p.add_argument('--replay', help='SEED:CASE: send that one case again')
    a = p.parse_args(argv)
    a.bots = tuple(int(x) for x in a.bots.split(','))
    if len(a.bots) != 2 or a.bots[1] < 1:
        p.error('--bots FIRST,COUNT')
    a.families = [f for f in a.families.split(',') if f]
    for f in a.families:
        if f not in ('raw', 'login', 'game', 'ingame'):
            p.error('unknown family: ' + f)
    a.guard_key = b''
    key = a.client_key or os.environ.get('CHAOS_CLIENT_KEY', '')
    if a.dev_key:
        a.guard_key = LT.GUARD_DEV_KEY
    elif key:
        try:
            a.guard_key = bytes.fromhex(key)
        except ValueError:
            p.error('--client-key must be 64 hex digits')
        if len(a.guard_key) != 32:
            p.error('--client-key must be 64 hex digits')
    a.client_id = (LT.GUARD_TAG << 16) | a.client_build if a.guard_key else LT.VERSION
    if a.replay:
        seed, case = a.replay.split(':')
        a.replay = (int(seed), int(case))
    if a.seed is None:
        a.seed = random.randrange(1, 1 << 30)
    return a


def main(argv):
    a = parse(argv)
    print('netfuzz: seed %d, %d workers, %s, families %s, bots %d..%d' % (
        a.seed, a.workers, 'client guard answered' if a.guard_key else 'no client guard answer', ','.join(a.families),
        a.bots[0], a.bots[0] + a.bots[1] - 1), flush=True)
    return Fuzzer(a).run()


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
