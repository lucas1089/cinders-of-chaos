#!/usr/bin/env python3
"""Tests of loadtest.py: why a bot did not enter the game, the grouped report lines, the bots' password hashes.

Run: python3 -I server/tools/loadtest_test.py (standard library only; a fake login server on 127.0.0.1)."""
import asyncio
import base64
import hashlib
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import loadtest as lt  # noqa: E402

FAILS = []
CHECKS = [0]


def eq(got, want, what):
    CHECKS[0] += 1
    if got != want:
        FAILS.append('%s: got %r, want %r' % (what, got, want))


# ---------------------------------------------------------------- failure reasons
eq(lt.failure_reason('login server: waiting for the character list', asyncio.TimeoutError()),
   'timeout at login server: waiting for the character list', 'a timeout names the step')
eq(lt.failure_reason('game server: waiting for the challenge', asyncio.IncompleteReadError(b'', 2)),
   'connection closed by the server without a message at game server: waiting for the challenge', 'closed without a message')
eq(lt.failure_reason('login server: connect', ConnectionRefusedError(111, 'Connection refused')),
   'ConnectionRefusedError: Connection refused at login server: connect', 'refused connection')
eq(lt.failure_reason('x', RuntimeError('game refused: Too many players online. You are at place 12 on the waiting list.')),
   'game refused: Too many players online. You are at place N on the waiting list.', 'numbers folded, so equal causes group')
eq(lt.failure_reason('x', RuntimeError('waiting list (server full)')), 'waiting list (server full)', 'own text kept')

groups = lt.group_reasons([('A', 'r1'), ('B', 'r2'), ('C', 'r1'), ('D', 'r1'), ('E', 'r1'), ('F', 'r2'), ('G', 'r0')])
eq(groups[0], (4, 'r1', ['A', 'C', 'D']), 'most frequent first, three names')
eq(groups[1], (2, 'r2', ['B', 'F']), 'second')
eq(groups[2], (1, 'r0', ['G']), 'last')
eq(lt.group_reasons([]), [], 'nothing failed')

eq(lt.disconnect_text(b'\x14' + lt.string('You have been kicked.\nBye')), 'You have been kicked. Bye', 'kick text')
eq(lt.disconnect_text(b'\x0b' + lt.string('Too many logins')), 'Too many logins', '0x0B text')
eq(lt.disconnect_text(b'\x0a\x00\x00'), None, 'not a disconnect message')
eq(lt.disconnect_text(b'\x14\xff'), None, 'too short')

# ---------------------------------------------------------------- password hashes as the website writes them
h = lt.password_hash('loadbot', 1000)
parts = h.split('$')
eq(len(parts), 4, 'four parts')
eq(parts[0:2], ['pbkdf2-sha256', '1000'], 'scheme and iterations')
salt, key = base64.b64decode(parts[2]), base64.b64decode(parts[3])
eq((len(salt), len(key)), (16, 32), '16-byte salt, 32-byte key')
eq(key, hashlib.pbkdf2_hmac('sha256', b'loadbot', salt, 1000, 32), 'the key verifies')
eq(lt.password_hash('loadbot', 0), hashlib.sha1(b'loadbot').hexdigest(), '0 iterations: the old SHA-1')

a = lt.parse(['setup'])
eq(a.hash_iterations, 120000, 'default iterations = the server default')
eq(lt.parse(['run', '--login-timeout', '30']).login_timeout, 30.0, '--login-timeout')

# ---------------------------------------------------------------- a fake login server: the refusal text reaches the report
KEY = [1, 2, 3, 4]


def answer(payload):
    inner = struct.pack('<H', len(payload)) + payload
    inner += b'\x00' * ((8 - len(inner) % 8) % 8)
    body = lt.xtea_encrypt(inner, KEY)
    packet = struct.pack('<I', lt.adler32(body)) + body
    return struct.pack('<H', len(packet)) + packet


async def scenario(mode):
    async def handle(reader, writer):
        size = struct.unpack('<H', await reader.readexactly(2))[0]
        await reader.readexactly(size)
        if mode == 'refuse':
            writer.write(answer(b'\x0b' + lt.string('Too many logins at the moment.\nPlease try again in a few seconds.')))
            await writer.drain()
        writer.close()

    server = await asyncio.start_server(handle, '127.0.0.1', 0)
    port = server.sockets[0].getsockname()[1]
    args = lt.parse(['run', '--count', '1', '--port', str(port), '--ramp', '0', '--duration', '0', '--no-source-ips'])
    stats = {'login_ms': [], 'failed': [], 'kicked': [], 'bytes': 0, 'disconnects': 0, 'walks': 0, 'says': 0,
             'no_challenge': 0, 'in_game': 0, 'connecting': 0, 'stop': False}
    bot = lt.Bot(0, args, lt.OT_RSA_N, stats)
    bot.key = lambda: list(KEY)
    await bot.run({'until': 0})
    server.close()
    await server.wait_closed()
    return stats


s = asyncio.run(scenario('refuse'))
eq(s['failed'], [('Loadbot Aaa', 'login refused: Too many logins at the moment. Please try again in a few seconds.')],
   'the server text of the login error packet')
eq((s['in_game'], s['connecting'], len(s['login_ms'])), (0, 0, 0), 'counted as failed, not in game')
s = asyncio.run(scenario('close'))
eq(s['failed'], [('Loadbot Aaa', 'connection closed by the server without a message at login server: waiting for the '
                                 'character list')], 'a closed connection names the step')

# the login time spread of the report: nearest-rank percentiles, max
eq(lt.spread([float(v) for v in range(0, 101)]), 'p50 50 ms, p90 90 ms, p95 95 ms, max 100 ms', 'p50 / p90 / p95 / max')
eq(lt.spread([]), 'p50 0 ms, p90 0 ms, p95 0 ms, max 0 ms', 'no logins')

for f in FAILS:
    print('FAIL ' + f)
print('loadtest_test: %d checks, %d failures' % (CHECKS[0], len(FAILS)))
sys.exit(1 if FAILS else 0)
