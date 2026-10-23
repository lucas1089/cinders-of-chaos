#!/usr/bin/env python3
"""Tests of netfuzz.py: the cases run against a stand-in server, the same seed sends the same bytes, the opcode list.

Run: python3 -I server/tools/netfuzz_test.py (standard library only; a stand-in login and game server on 127.0.0.1
that keeps what each connection sent). The in-game family needs a real server and is not run here."""
import os
import socket
import struct
import sys
import threading

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import netfuzz as NF  # noqa: E402

FAILS = []
CHECKS = [0]


def eq(got, want, what):
    CHECKS[0] += 1
    if got != want:
        FAILS.append('%s: got %r, want %r' % (what, got, want))


class StandIn:
    """accepts on two ports; each connection's bytes go into self.got[port] in the order they closed"""

    def __init__(self):
        self.got = {}
        self.lock = threading.Lock()
        self.socks = []
        self.ports = []
        for greet in (False, True):
            ls = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            ls.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            ls.bind(('127.0.0.1', 0))
            ls.listen(64)
            port = ls.getsockname()[1]
            self.socks.append(ls)
            self.ports.append(port)
            self.got[port] = []
            threading.Thread(target=self.accept, args=(ls, port, greet), daemon=True).start()

    def accept(self, ls, port, greet):
        while True:
            try:
                c, _ = ls.accept()
            except OSError:
                return
            threading.Thread(target=self.serve, args=(c, port, greet), daemon=True).start()

    def serve(self, c, port, greet):
        data = b''
        c.settimeout(5)
        try:
            if greet:  # the game server's challenge: timestamp and random byte at offset 7 of the message
                c.sendall(NF.frame(b'\x00\x00\x06\x00\x1f' + struct.pack('<IB', 1700000000, 42)))
            while True:
                part = c.recv(65536)
                if not part:
                    break
                data += part
        except OSError:
            pass
        c.close()
        with self.lock:
            self.got[port].append(data)


def fuzzer(server, families, seed):
    a = NF.parse(['--port', str(server.ports[0]), '--game-port', str(server.ports[1]), '--families', families,
                  '--seed', str(seed), '--workers', '1'])
    f = NF.Fuzzer(a)
    f.pace = 0.01
    return f


def sent(server, port, fz, cases):
    """the bytes each case sent, one entry per case"""
    out = []
    for case in cases:
        before = len(server.got[port])
        fz.run_case(case)
        for _ in range(500):
            with server.lock:
                if len(server.got[port]) > before:
                    break
            threading.Event().wait(0.01)
        with server.lock:
            out.append(b''.join(server.got[port][before:]))
    return out


server = StandIn()
login_port, game_port = server.ports

# ---------------------------------------------------------------- every raw and login kind runs; replay is exact
fz = fuzzer(server, 'raw,login', 11)
first = sent(server, login_port, fz, range(1, 41))
kinds = [line.split(' ', 2)[2] for line in fz.recent]
eq([k for k in kinds if k.startswith('error')], [], 'no case of raw / login raised')
eq(len(first), 40, 'one connection per case')
eq(sum(1 for b in first if b), 40 - kinds.count('idle'), 'every case but idle sent bytes')
fz2 = fuzzer(server, 'raw,login', 11)
again = sent(server, login_port, fz2, range(1, 41))
eq(again == first, True, 'the same seed sends the same bytes')
fz3 = fuzzer(server, 'raw,login', 12)
eq(sent(server, login_port, fz3, range(1, 11)) == first[:10], False, 'another seed sends other bytes')

# ---------------------------------------------------------------- game family: reads the challenge, sends a login
fz = fuzzer(server, 'game', 5)
game = sent(server, game_port, fz, range(1, 21))
kinds = [line.split(' ', 2)[2] for line in fz.recent]
eq([k for k in kinds if k.startswith('error')], [], 'no case of game raised')
eq(all(len(b) >= 2 for b in game), True, 'every game case sent a frame')
for b, kind in zip(game, kinds):
    if kind != 'garbage':
        CHECKS[0] += 1
        if b[2 + 4] != 0x0A:
            FAILS.append('game case %s: protocol byte %r, want the game login 0x0A' % (kind, b[6]))

# ---------------------------------------------------------------- helpers
ops = NF.chaos_opcodes()
eq(120 in ops and all(0 < o < 256 for o in ops), True, 'opcodes: the admin opcode, all in one byte')
eq(len(ops) > 20, True, 'opcodes: the Chaos opcodes were read from chaos_constants.lua')
eq(NF.frame(b'abc', False), b'\x03\x00abc', 'frame without checksum')
eq(len(NF.frame(b'abc')), 2 + 4 + 3, 'frame with checksum')

for ls in server.socks:
    ls.close()
if FAILS:
    print('\n'.join(FAILS))
    print('netfuzz_test: %d of %d checks failed' % (len(FAILS), CHECKS[0]))
    sys.exit(1)
print('netfuzz_test: %d checks passed' % CHECKS[0])
