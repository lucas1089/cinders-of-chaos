#!/usr/bin/env python3
"""The start ticket's shared vector (O552 phase D): python3 -I client/tools/ticket_vector_test.py

The launcher (launcher/src/ticket.rs), the game (src/client/chaosticket.h, client base patch 0198; its test is
client/tools/chaosticket_test.cpp) and this file implement one ticket format. Here it is made a third time, with Python's
hmac and hashlib and no code of the other two, from a TEST key (never a real one: the real client key never enters the
repository, a log or a test), and compared with
  * launcher/tests/data/ticket_vector.json (read by the Rust test), and
  * the constants at the top of client/tools/chaosticket_test.cpp (the C++ test).
  UPDATE_TICKET_VECTOR=1 python3 -I client/tools/ticket_vector_test.py   rewrites the JSON.
Format: t1.<build>.<launcher>.<expiry>.<nonce hex32>.<mac hex64>, mac = HMAC-SHA256(sub_key, "t1|build|launcher|expiry|nonce"),
sub_key = HKDF-SHA256(client_key, no salt, info "cinders-launcher-ticket-v1", 32 bytes).
"""
import hashlib
import hmac
import json
import os
import re
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
JSON_PATH = os.path.join(ROOT, 'launcher', 'tests', 'data', 'ticket_vector.json')
CPP_PATH = os.path.join(ROOT, 'client', 'tools', 'chaosticket_test.cpp')

TEST_KEY = bytes([0x11]) * 32
INFO = b'cinders-launcher-ticket-v1'
BUILD, LAUNCHER, EXPIRY = 47, 200, 1_800_000_000
NONCE = '00112233445566778899aabbccddeeff'


def hkdf32(ikm, info):
    prk = hmac.new(b'\x00' * 32, ikm, hashlib.sha256).digest()
    return hmac.new(prk, info + b'\x01', hashlib.sha256).digest()


def mint(sub, build, launcher, expiry, nonce):
    mac = hmac.new(sub, f't1|{build}|{launcher}|{expiry}|{nonce}'.encode(), hashlib.sha256).hexdigest()
    return f't1.{build}.{launcher}.{expiry}.{nonce}.{mac}'


def vector():
    sub = hkdf32(TEST_KEY, INFO)
    return {
        'note': 'TEST key only. Made by client/tools/ticket_vector_test.py (UPDATE_TICKET_VECTOR=1); read by '
                'launcher/src/ticket.rs; the same constants are in client/tools/chaosticket_test.cpp.',
        'client_key_hex': TEST_KEY.hex(),
        'sub_key_hex': sub.hex(),
        'build': BUILD, 'launcher': LAUNCHER, 'expiry': EXPIRY, 'nonce': NONCE,
        'ticket': mint(sub, BUILD, LAUNCHER, EXPIRY, NONCE),
    }


class TicketVector(unittest.TestCase):
    def test_hkdf_is_rfc5869(self):
        # RFC 5869 test case 3: the first 32 bytes of its output
        self.assertEqual(hkdf32(bytes([0x0b]) * 22, b'').hex(),
                         '8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d')

    def test_the_json_is_the_vector(self):
        v = vector()
        if os.environ.get('UPDATE_TICKET_VECTOR') == '1':
            with open(JSON_PATH, 'w', encoding='utf-8') as f:
                json.dump(v, f, indent=1)
                f.write('\n')
        with open(JSON_PATH, encoding='utf-8') as f:
            self.assertEqual(json.load(f), v)

    def test_the_cpp_test_has_the_same_constants(self):
        v = vector()
        with open(CPP_PATH, encoding='utf-8') as f:
            text = f.read()
        for name, want in (('CLIENT_KEY_HEX', v['client_key_hex']), ('SUB_KEY_HEX', v['sub_key_hex']),
                           ('TICKET', v['ticket']), ('NONCE', v['nonce'])):
            m = re.search(r'VECTOR_%s\s*=\s*"([^"]*)"' % name, text)
            self.assertIsNotNone(m, name)
            self.assertEqual(m.group(1), want, name)
        for name, want in (('BUILD', BUILD), ('LAUNCHER', LAUNCHER), ('EXPIRY', EXPIRY)):
            m = re.search(r'VECTOR_%s\s*=\s*(\d+)' % name, text)
            self.assertIsNotNone(m, name)
            self.assertEqual(int(m.group(1)), want, name)

    def test_the_key_is_a_test_key(self):
        # the vector must never hold a real key: a real one is random, the test key is eleven bytes repeated
        self.assertEqual(set(TEST_KEY), {0x11})


if __name__ == '__main__':
    sys.exit(0 if unittest.main(verbosity=1, exit=False).result.wasSuccessful() else 1)
