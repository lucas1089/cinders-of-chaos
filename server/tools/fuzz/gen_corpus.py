#!/usr/bin/env python3
"""Write the seed corpus of the fuzz harnesses (server/tools/fuzz/corpus/<harness>/seed-*), deterministic.

usage: python3 -I server/tools/fuzz/gen_corpus.py [--check]

The seeds are valid and near-valid inputs of each harness's input layout (see the comment at the top of each
fuzz_*.cpp). Files named crash-* or regress-* in the same folders are inputs that once found a bug: they are kept by
hand, never written or removed here. --check: exit 1 when a seed file differs from what this script writes.
"""
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
CORPUS = os.path.join(HERE, 'corpus')


def adler(b):
    return zlib.adler32(b) & 0xFFFFFFFF


def lstr(b):
    return struct.pack('<H', len(b)) + b


def frame(body, checksum=True):
    packet = (struct.pack('<I', adler(body)) if checksum else b'') + body
    return struct.pack('<H', len(packet)) + packet


def v2(cmd, fam, payload):
    sig = b'\r\n\r\n\x00\r\nQUIT\n'
    return sig + bytes([0x20 | cmd, fam]) + struct.pack('>H', len(payload)) + payload


def proxyprotocol():
    s = {}
    s['v1-tcp4'] = b'\x00' + b'PROXY TCP4 203.0.113.7 10.0.0.5 51234 7172\r\n\x99\x00'
    s['v1-unknown'] = b'\x00' + b'PROXY UNKNOWN\r\nX'
    s['v1-tcp6'] = b'\x00' + b'PROXY TCP6 ::ffff:198.51.100.9 ::ffff:10.0.0.5 4000 7171\r\n'
    s['v1-long'] = b'\x00' + b'PROXY ' + b'A' * 120
    s['v2-tcp4'] = b'\x00' + v2(1, 0x11, bytes([192, 0, 2, 44, 10, 0, 0, 5, 0x1F, 0x90, 0x1C, 0x04])) + b'\x55'
    s['v2-tlv'] = b'\x00' + v2(1, 0x11, bytes([192, 0, 2, 45, 10, 0, 0, 5, 0, 1, 0, 2, 4, 0, 3]) + b'abc')
    s['v2-local'] = b'\x00' + v2(0, 0x00, b'')
    p6 = bytearray(36)
    p6[10] = p6[11] = 0xFF
    p6[12:16] = bytes([198, 51, 100, 1])
    s['v2-tcp6'] = b'\x00' + v2(1, 0x21, bytes(p6))
    s['v2-big'] = b'\x00' + v2(1, 0x11, b'\x01' * 512)
    s['trusted'] = b'\xC0' + b'10.0.0.0/8, 203.0.113.7 ,192.168.1.1/32\n\x7f\x00\x00\x01'
    s['trusted-bad'] = b'\xC1' + b'1.2.3.4/33, x.y, 300.1.1.1\n\x0a\x00\x00\x05'
    s['looks'] = b'\xE0' + b'\r\n'
    return s


def clientguard():
    s = {}
    build = struct.pack('<H', 1)
    s['answer'] = b'\x00' + build + b'cg1:1:' + b'0' * 64 + b'\nNONCE-16-BYTES!!\nloadbot0001\nLoadbot Aab'
    s['answer-upper'] = b'\x00' + build + b'cg1:1:' + b'AF' * 32 + b'\n\n\n'
    s['answer-build'] = b'\x00' + struct.pack('<H', 65535) + b'cg1:65535:' + b'1' * 64 + b'\nn\na\nc'
    s['answer-short'] = b'\x00' + build + b'cg1:'
    s['answer-colon'] = b'\x00' + build + b'cg1:12345:' + b'0' * 63
    s['builds'] = b'\xA1' + struct.pack('<I', 0x43430005) + b'1, 2;3 4,65535,65536,-1,x'
    s['builds-stock'] = b'\xA0' + struct.pack('<I', 1098) + b''
    s['manifest'] = b'\xE1' + struct.pack('<I', 0x43430007) + b'{"payload":"{\\"min_package\\": 5}"}'
    s['manifest-none'] = b'\xE1' + struct.pack('<I', 0x43430007) + b'min_package' + b'9' * 20
    return s


def loginlimit():
    s = {}
    ops = b''
    for i in range(30):
        ops += bytes([i % 3, 8, i % 2, 1, 0]) + b'loadbot0'
    s['mixed'] = bytes([3, 3, 20, 10]) + ops
    s['flood'] = bytes([2, 2, 5, 5]) + b''.join(bytes([i, 79, 0, 0, 1]) + bytes([65 + i % 26]) * 79 for i in range(40))
    s['off'] = bytes([0, 0, 0, 0]) + b''.join(bytes([1, 3, 0, 29, 0]) + b'abc' for _ in range(20))
    return s


def netmsg():
    s = {}
    key = struct.pack('<4I', 1, 2, 3, 4)
    block1 = (b'\x00' + key + lstr(b'account') + lstr(b'password')).ljust(128, b'\x00')
    block2 = (b'\x00' + lstr(b'') + b'\x00').ljust(128, b'\x00')
    login = b'\x01' + struct.pack('<HHI', 10, 1098, 1098) + struct.pack('<3I', 0, 0, 0) + b'\x00' + block1 + block2
    s['login'] = b'\x01' + frame(login)
    s['login-nochecksum'] = b'\x01' + frame(login, False)
    s['login-short'] = b'\x01' + frame(login[:40])
    session = b'account\npassword\n\n1700000000'
    gblock = (b'\x00' + key + b'\x00' + lstr(session) + lstr(b'Loadbot Aaa') + struct.pack('<IB', 7, 9)
              + struct.pack('<H', 5) + b'OTCv8' + struct.pack('<H', 261)).ljust(128, b'\x00')
    game = b'\x0A' + struct.pack('<HHI', 10, 1098, 1098) + b'\x00' + struct.pack('<H', 0) + gblock
    later = []
    for body in (b'\x96\x01' + lstr(b'hello'), b'\x82' + struct.pack('<HHB', 100, 100, 7) + b'\x01\x00\x00\x00',
                 b'\x32\x9e' + lstr(b'{"action":"hello"}'), b'\x64\x03\x01\x02\x03'):
        inner = struct.pack('<H', len(body)) + body
        inner += b'\x00' * ((8 - len(inner) % 8) % 8)
        later.append(frame(inner))
    s['game-plain-later'] = b'\x02' + frame(game) + b''.join(later)
    s['game'] = b'\x00' + frame(game) + b''.join(later)
    s['game-bad-length'] = b'\x02' + frame(game) + struct.pack('<H', 0xFFF0) + b'\x00' * 20
    return s


def main(argv):
    check = '--check' in argv
    bad = 0
    for name, fn in (('proxyprotocol', proxyprotocol), ('clientguard', clientguard), ('loginlimit', loginlimit),
                     ('netmsg', netmsg)):
        d = os.path.join(CORPUS, name)
        os.makedirs(d, exist_ok=True)
        for seed, data in sorted(fn().items()):
            path = os.path.join(d, 'seed-' + seed)
            old = open(path, 'rb').read() if os.path.exists(path) else None
            if old == data:
                continue
            if check:
                print('out of date: ' + os.path.relpath(path, HERE))
                bad = 1
            else:
                with open(path, 'wb') as f:
                    f.write(data)
                print('wrote ' + os.path.relpath(path, HERE))
    return bad


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
