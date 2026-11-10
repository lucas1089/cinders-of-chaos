#!/usr/bin/env python3
"""Launch rehearsal (O441), the probe: one headless game client that stays in the game across a boundary of the shifted
clock and reads what a player gets: the store categories (opcode 218), the season window (246), the PvP window (200),
the weekend status line, and the broadcasts of the server. It writes counts, booleans and state words only: no name, no
password, no key and no text of the server ever goes into the output.

It uses the bot client of server/tools/loadtest.py (the login, the XTEA channel, the client guard answer). The account comes
from the environment (CHAOS_LIVE_ACCOUNT, CHAOS_LIVE_PASSWORD, CHAOS_LIVE_CHARACTER, the names of unity_live_check.sh), the guard
key from CHAOS_CLIENT_KEY or the clientGuardKey of the server's config.lua. The character of the probe is a staff character
(group 4, set by launch_rehearsal.sh in the rehearsal database) because "/weekend status" is a staff command.

usage: launch_rehearsal_probe.py --server DIR --fake-start "YYYY-MM-DD HH:MM:SS" --t0 REAL_EPOCH --samples 55,200 --out FILE
         [--host 127.0.0.1] [--port 7171] [--game-port 0] [--stay SECONDS]
  --t0       the real unix time tfs was started; samples are taken T0 + each number of real seconds
  --fake-start  the shifted local time at T0 (the clock runs at rate 1), written into each sample as "fake"
  --stay     keep the session open this many real seconds after T0 (default: the last sample + 10)
"""
import argparse
import asyncio
import datetime
import json
import os
import re
import struct
import sys
import time

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'server', 'tools'))
import loadtest as L  # noqa: E402

OP_SHOP, OP_SEASON, OP_BG = 218, 246, 200
COUNTS = {   # what a broadcast or a login line looks like (English client); counted over the whole session
    'season_begun': rb'has begun! New characters can join',
    'weekend_begins': rb'WEEKEND RITUAL: the weekend begins!',
    'weekend_preview': rb'Weekend Ritual starts',
    'save_first': rb'Server is saving game in 5\s+minute',
    'save_any': rb'Server is saving game in \d+\s+minute',
}


class Session:
    def __init__(self):
        self.counts = {k: 0 for k in COUNTS}
        self.frames = {OP_SHOP: [], OP_SEASON: [], OP_BG: []}   # parsed JSON per opcode, in arrival order
        self.partial = {}
        self.weekend = None      # None: no answer yet, else the status line kind: "running" | "off"
        self.alive = True
        self.cid = 0

    def feed(self, plain):
        for k, rx in COUNTS.items():
            self.counts[k] += len(re.findall(rx, plain))
        if b'[weekend] ' in plain:
            self.weekend = 'running' if re.search(rb'\[weekend\] [^\n]{0,40}Running', plain) else 'off'
        for op in self.frames:
            marker = bytes([0x32, op])
            i = plain.find(marker)
            while i >= 0:
                if i + 4 <= len(plain):
                    n = struct.unpack_from('<H', plain, i + 2)[0]
                    if i + 4 + n <= len(plain):
                        self.frame(op, plain[i + 4:i + 4 + n])
                i = plain.find(marker, i + 1)

    def frame(self, op, body):
        if not body:
            return
        head = body[:1]
        if head == b'S':
            self.partial[op] = bytearray(body[1:])
            return
        if head in (b'P', b'E') and op in self.partial:
            self.partial[op] += body[1:]
            if head == b'E':
                body = bytes(self.partial.pop(op))
            else:
                return
        elif head != b'{':
            return
        try:
            self.frames[op].append(json.loads(body.decode('utf-8', 'replace')))
        except ValueError:
            pass

    def last(self, op, action=None):
        for f in reversed(self.frames[op]):
            if isinstance(f, dict) and (action is None or f.get('action') == action):
                return f
        return None


def founder_listed(frame):
    """the Founder Pack category in the store list the client gets"""
    data = frame.get('data') if isinstance(frame, dict) else None
    if not isinstance(data, list):
        return None
    for c in data:
        if isinstance(c, dict) and 'founder' in str(c.get('name', '')).lower():
            return True
    return False


def season_view(frame):
    s = (frame or {}).get('data', {}).get('season') if isinstance(frame, dict) else None
    if not isinstance(s, dict):
        return {'status': 'none'}
    return {'status': s.get('status'), 'id': s.get('id'), 'startsIn': s.get('startsIn'), 'endsIn': s.get('endsIn')}


def pvp_view(frame):
    s = (frame or {}).get('data', {}).get('season') if isinstance(frame, dict) else None
    if not isinstance(s, dict):
        return {'id': None, 'endsIn': None}
    return {'id': s.get('id'), 'endsIn': s.get('endsIn')}


def guard_key(server):
    k = os.environ.get('CHAOS_CLIENT_KEY', '').strip()
    if not k:
        try:
            with open(os.path.join(server, 'config.lua')) as f:
                m = re.search(r'(?m)^\s*clientGuardKey\s*=\s*"([^"\n]+)"', f.read())
            k = m.group(1) if m else ''
        except OSError:
            k = ''
    if not k:
        return None
    return bytes.fromhex(k) if re.fullmatch(r'[0-9a-fA-F]{64}', k) else k.encode()


class A:
    host = '127.0.0.1'
    port = 7171
    game_port = 0
    client_id = (0x4343 << 16) | 5
    login_timeout = 30
    guard_key = None
    client_build = 5
    no_source_ips = True
    hunt = False


ACTIVE = [None]    # the session that reads every decrypted packet, the first answers of the login included
_decrypt = L.Conn.decrypt


def _tap(self, body):
    plain = _decrypt(self, body)
    if ACTIVE[0] is not None:
        ACTIVE[0].feed(plain)
    return plain


L.Conn.decrypt = _tap


async def reader(bot, sess):
    while True:
        try:
            raw = await bot.conn.read_message()
        except Exception:  # noqa: BLE001
            sess.alive = False
            return
        try:
            plain = bot.conn.decrypt(raw)
        except Exception:  # noqa: BLE001
            continue
        if bot.guard_wait:
            n = L.find_challenge(plain)
            if n is not None:
                bot.send_guard_answer(bot.conn, n)


async def ask(bot, sess, wait=4.0):
    """the four requests of a sample, then wait for the answers"""
    for op in sess.frames:
        sess.frames[op].clear()
    sess.weekend = None
    send = bot.conn.send
    send(b'\x32' + bytes([OP_SHOP]) + L.string('{"action":"init","data":{}}'))
    send(b'\x32' + bytes([OP_SEASON]) + L.string('{"action":"open","data":{}}'))
    send(b'\x32' + bytes([OP_BG]) + L.string('{"action":"open","data":{}}'))
    send(b'\x96\x01' + L.string('/weekend status'))
    await bot.conn.w.drain()
    end = time.monotonic() + wait
    while time.monotonic() < end and sess.alive:
        if (sess.last(OP_SHOP, 'categories') and sess.last(OP_SEASON, 'state') and sess.frames[OP_BG]
                and sess.weekend is not None):
            break
        send(b'\x1E')
        await bot.conn.w.drain()
        await asyncio.sleep(0.5)


def sample(sess, at, fake):
    return {
        'at': at, 'fake': fake,
        'founder': {'listed': founder_listed(sess.last(OP_SHOP, 'categories'))},
        'season': season_view(sess.last(OP_SEASON, 'state')),
        'pvp': pvp_view(sess.frames[OP_BG][-1] if sess.frames[OP_BG] else None),
        'weekend': {'running': None if sess.weekend is None else sess.weekend == 'running',
                    'preview': sess.counts['weekend_preview'] > 0},
        'broadcasts': dict(sess.counts),
        'online': sess.alive,
    }


async def run(a):
    args = A()
    args.host, args.port, args.game_port = a.host, a.port, a.game_port
    args.guard_key = guard_key(a.server)
    args.client_build = int(os.environ.get('CHAOS_LIVE_BUILD', '5'))
    pem = os.path.join(a.server, 'key.pem')
    n_rsa = L.modulus_from_pem(pem) if os.path.isfile(pem) else L.OT_RSA_N
    bot = L.Bot(0, args, n_rsa, {})
    bot.account = os.environ['CHAOS_LIVE_ACCOUNT']
    bot.password = os.environ['CHAOS_LIVE_PASSWORD']
    bot.name = os.environ['CHAOS_LIVE_CHARACTER']
    bot.abort_at = None
    sess = Session()
    ACTIVE[0] = sess
    session, world = await bot.login_server()
    bot.conn = await bot.enter_game(session, world)
    task = asyncio.ensure_future(reader(bot, sess))
    fake0 = datetime.datetime.strptime(a.fake_start, '%Y-%m-%d %H:%M:%S')
    out = []
    last = max(a.samples)
    stay = a.stay if a.stay else last + 10
    try:
        for at in a.samples:
            while time.time() < a.t0 + at and sess.alive:
                bot.conn.send(b'\x1E')
                await bot.conn.w.drain()
                await asyncio.sleep(min(2.0, max(0.05, a.t0 + at - time.time())))
            if sess.alive:
                await ask(bot, sess)
            fake = (fake0 + datetime.timedelta(seconds=time.time() - a.t0)).strftime('%Y-%m-%d %H:%M:%S')
            out.append(sample(sess, at, fake))
        # stay in the game (the save notices and the stop of the server are read from the counts of the last sample)
        while time.time() < a.t0 + stay and sess.alive:
            bot.conn.send(b'\x1E')
            await bot.conn.w.drain()
            await asyncio.sleep(2.0)
        if a.stay:
            out[-1]['broadcasts'] = dict(sess.counts)
            out[-1]['online'] = sess.alive
    finally:
        try:
            bot.conn.send(b'\x14')
            await bot.conn.w.drain()
        except Exception:  # noqa: BLE001
            pass
        task.cancel()
    return out


def main(argv):
    p = argparse.ArgumentParser()
    p.add_argument('--server', required=True)
    p.add_argument('--fake-start', required=True)
    p.add_argument('--t0', type=float, required=True)
    p.add_argument('--samples', required=True)
    p.add_argument('--out', required=True)
    p.add_argument('--host', default='127.0.0.1')
    p.add_argument('--port', type=int, default=7171)
    p.add_argument('--game-port', type=int, default=0)
    p.add_argument('--stay', type=float, default=0)
    a = p.parse_args(argv)
    a.samples = [float(x) for x in a.samples.split(',') if x]
    try:
        samples = asyncio.run(run(a))
        err = None
    except Exception as e:  # noqa: BLE001
        samples, err = [], type(e).__name__    # the class only: a message may carry a name
    data = {'facts': {}, 'samples': []}
    if os.path.isfile(a.out):
        with open(a.out) as f:
            data = json.load(f)
    data['samples'] = samples
    if err:
        data.setdefault('facts', {})['probe_error'] = err
    with open(a.out, 'w') as f:
        json.dump(data, f)
    print('probe: %d sample(s)%s' % (len(samples), ', error ' + err if err else ''))
    return 1 if err else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
