#!/usr/bin/env python3
"""Load test: N bot characters log in over the 10.98 protocol, walk around and talk, while the server is measured.

Standard library only (Python 3.7+). Three commands:

  setup    create the bot accounts and characters in the game database (mysql client; CHAOS_DB_* as for backup.sh)
             python3 -I server/tools/loadtest.py setup --count 30 [--pos 1500,1500,7] [--town 1] [--vocation 4]
  run      log the bots in, walk, talk, measure, print a report
             python3 -I server/tools/loadtest.py run --count 30 --host 127.0.0.1 --port 7171 --duration 120
                 [--server-pid PID] [--server-log PATH] [--key key.pem] [--ramp 0.5] [--walk 1.0] [--say 20]
  cleanup  delete the bot characters and accounts again
             python3 -I server/tools/loadtest.py cleanup

Accounts are named loadbot0001..., password "loadbot", one character each ("Loadbot Aa", "Loadbot Ab", ...), level 100,
placed at --pos (spread over a square around it) with lastlogin set, so the new-player tutorial and kit do not start.
Never run setup against a live database you cannot clean: cleanup removes exactly the loadbot accounts and their
characters.

Protocol (what the engine's protocollogin.cpp / protocolgame.cpp expect, the same as the client sends):
  every packet   u16 length, u32 adler32 of the rest, then the body; after the first packet the body is XTEA encrypted
                 (u16 inner length + payload, padded to 8 bytes, 32 rounds, little endian)
  login (7171)   0x01, u16 os, u16 1098, u32 1098, 3 x u32 signatures, u8 0, then two 128-byte RSA blocks:
                 [0, xtea key, account, password] and [0, token "", stay-logged 0]; the answer carries the session key
                 (0x28) and the character list (0x64), or an error (0x0B)
  game (7172)    the server first sends a challenge (0x1F, u32 timestamp, u8 random); the client answers 0x0A, u16 os,
                 u16 1098, u32 1098, u8, u16, then one RSA block [0, xtea key, gm 0, session key, character name,
                 timestamp, random]
  in game        0x65-0x68 walk north/east/south/west, 0x96 say (type 1, text), 0x1E ping (keeps the engine's
                 no-pong kick away); everything the server sends is read and counted, only the first message is
                 decrypted (to tell a login error from entering the game)
RSA: m^65537 mod n. n is read from --key (the server's key.pem, PKCS#1, only the modulus is used) or is the standard
open-server public key that the client also ships.
The os sent is 10 (OTClient on Linux), so the engine enables extended opcodes and the Chaos modules talk to the bots
at login as they do to real clients. Each bot connects from its own loopback address (127.0.0.N) when --host is a
loopback address, because the Chaos multi-client rule allows only 2 characters per IP.

Measured: logins (ok / failed and why), login time (p50 / p95 / max), bytes received, disconnects; with --server-pid
the server's CPU (% of one core) and memory (RSS) every second (Linux /proc); with --server-log the lines of the
probe server/tools/loadtest_probe.lua (TEST ONLY) that the server printed during the run: the game loop lag.
"""
import asyncio
import base64
import os
import random
import re
import shutil
import statistics
import struct
import subprocess
import sys
import tempfile
import time
import zlib

VERSION = 1098
OS_OTCLIENT_LINUX = 10
# the standard open-server RSA modulus (public); the client ships the same number
OT_RSA_N = int(
    '1091201329673994292788609605089955415282375029027981291234687579'
    '3726629149257644633073969600111060390723088861007265581882535850'
    '3429057592827629436413108566029093628212635953836686562675849720'
    '6207862794310902180176810615217550567108238764764442605581471797'
    '07119674283982419152118103759076030616683978566631413')
DELTA = 0x9E3779B9
MASK = 0xFFFFFFFF
PREFIX = 'loadbot'
WORDS = ['hunting rotworms', 'anyone for a rift?', 'nice drop', 'where is the bank', 'level up!', 'chaos orb please',
         'brb', 'going to the tower', 'who wants to party', 'that goblin escaped again', 'lag?', 'gg']


# ------------------------------------------------------------------------------------------------ crypto
def adler32(data):
    return zlib.adler32(data) & MASK


def xtea_encrypt(data, key):
    out = bytearray()
    for i in range(0, len(data), 8):
        v0, v1 = struct.unpack_from('<2I', data, i)
        s = 0
        for _ in range(32):
            v0 = (v0 + ((((v1 << 4) ^ (v1 >> 5)) + v1) ^ (s + key[s & 3]))) & MASK
            s = (s + DELTA) & MASK
            v1 = (v1 + ((((v0 << 4) ^ (v0 >> 5)) + v0) ^ (s + key[(s >> 11) & 3]))) & MASK
        out += struct.pack('<2I', v0, v1)
    return bytes(out)


def xtea_decrypt(data, key):
    out = bytearray()
    for i in range(0, len(data) - len(data) % 8, 8):
        v0, v1 = struct.unpack_from('<2I', data, i)
        s = (DELTA * 32) & MASK
        for _ in range(32):
            v1 = (v1 - ((((v0 << 4) ^ (v0 >> 5)) + v0) ^ (s + key[(s >> 11) & 3]))) & MASK
            s = (s - DELTA) & MASK
            v0 = (v0 - ((((v1 << 4) ^ (v1 >> 5)) + v1) ^ (s + key[s & 3]))) & MASK
        out += struct.pack('<2I', v0, v1)
    return bytes(out)


def rsa_block(payload, n):
    if len(payload) > 128:
        raise ValueError('RSA block too long (%d bytes): shorter account / character names' % len(payload))
    m = int.from_bytes(payload + b'\x00' * (128 - len(payload)), 'big')
    return pow(m, 65537, n).to_bytes(128, 'big')


def modulus_from_pem(path):
    """n of a PKCS#1 'RSA PRIVATE KEY' or PKCS#8 'PRIVATE KEY' PEM (a tiny DER reader, no dependencies)"""
    text = open(path).read()
    der = base64.b64decode(''.join(l for l in text.splitlines() if l and not l.startswith('-----')))

    def tlv(buf, i):
        tag, length = buf[i], buf[i + 1]
        i += 2
        if length & 0x80:
            k = length & 0x7F
            length = int.from_bytes(buf[i:i + k], 'big')
            i += k
        return tag, buf[i:i + length], i + length

    tag, seq, _ = tlv(der, 0)
    _, _, i = tlv(seq, 0)                       # version
    tag, val, j = tlv(seq, i)
    if tag == 0x30:                             # PKCS#8: AlgorithmIdentifier, then OCTET STRING with PKCS#1 inside
        _, inner, _ = tlv(seq, j)
        _, seq, _ = tlv(inner, 0)
        _, _, i = tlv(seq, 0)
        tag, val, _ = tlv(seq, i)
    return int.from_bytes(val, 'big')


def string(s):
    b = s.encode('latin-1')
    return struct.pack('<H', len(b)) + b


# ------------------------------------------------------------------------------------------------ framing
class Conn:
    def __init__(self, reader, writer):
        self.r, self.w = reader, writer
        self.key = None
        self.received = 0

    def send_raw(self, body):
        packet = struct.pack('<I', adler32(body)) + body
        self.w.write(struct.pack('<H', len(packet)) + packet)

    def send(self, payload):
        inner = struct.pack('<H', len(payload)) + payload
        inner += b'\x00' * ((8 - len(inner) % 8) % 8)
        self.send_raw(xtea_encrypt(inner, self.key))

    async def read_message(self):
        head = await self.r.readexactly(2)
        size = struct.unpack('<H', head)[0]
        body = await self.r.readexactly(size)
        self.received += 2 + size
        return body

    def decrypt(self, body):
        """checksum stripped, decrypted, inner length applied"""
        plain = xtea_decrypt(body[4:], self.key)
        inner = struct.unpack_from('<H', plain)[0]
        return plain[2:2 + inner]


def read_string(buf, i):
    n = struct.unpack_from('<H', buf, i)[0]
    return buf[i + 2:i + 2 + n].decode('latin-1'), i + 2 + n


# ------------------------------------------------------------------------------------------------ bot
class Bot:
    def __init__(self, index, args, n_rsa, stats):
        self.index = index
        self.account = '%s%04d' % (PREFIX, index)
        self.password = PREFIX
        self.name = bot_name(index)
        self.args, self.n, self.stats = args, n_rsa, stats
        self.source = None
        if args.host.startswith('127.') and not args.no_source_ips:
            self.source = '127.0.%d.%d' % (1 + index // 250, 1 + index % 250 + 1)
        self.conn = None
        self.alive = False

    def key(self):
        return [random.getrandbits(32) for _ in range(4)]

    async def open(self, port):
        local = (self.source, 0) if self.source else None
        reader, writer = await asyncio.wait_for(asyncio.open_connection(self.args.host, port, local_addr=local), 10)
        return Conn(reader, writer)

    async def login_server(self):
        c = await self.open(self.args.port)
        c.key = self.key()
        rsa1 = b'\x00' + struct.pack('<4I', *c.key) + string(self.account) + string(self.password)
        rsa2 = b'\x00' + string('') + b'\x00'
        body = (b'\x01' + struct.pack('<HHI', OS_OTCLIENT_LINUX, VERSION, VERSION) + struct.pack('<3I', 0, 0, 0)
                + b'\x00' + rsa_block(rsa1, self.n) + rsa_block(rsa2, self.n))
        c.send_raw(body)
        await c.w.drain()
        msg = c.decrypt(await asyncio.wait_for(c.read_message(), 15))
        c.w.close()
        i, session, world = 0, None, None
        while i < len(msg):
            op = msg[i]
            i += 1
            if op in (0x0A, 0x0B):
                text, i = read_string(msg, i)
                raise RuntimeError('login refused: ' + text.replace('\n', ' '))
            if op == 0x0D:
                raise RuntimeError('login refused: authenticator token')
            if op == 0x0C:
                i += 1
            elif op == 0x14:
                _, i = read_string(msg, i)
            elif op == 0x28:
                session, i = read_string(msg, i)
            elif op == 0x64:
                count = msg[i]
                i += 1
                for _ in range(count):
                    i += 1
                    _, i = read_string(msg, i)
                    host, i = read_string(msg, i)
                    port = struct.unpack_from('<H', msg, i)[0]
                    i += 3
                    world = (host, port)
                break
            else:
                break
        if not session or not world:
            raise RuntimeError('no session key / world in the login answer')
        return session, world

    async def enter_game(self, session, world):
        port = self.args.game_port or world[1]
        c = await self.open(port)
        msg = await asyncio.wait_for(c.read_message(), 15)
        if len(msg) < 12 or msg[6] != 0x1F:
            raise RuntimeError('no challenge from the game server')
        ts, rnd = struct.unpack_from('<IB', msg, 7)
        c.key = self.key()
        rsa = (b'\x00' + struct.pack('<4I', *c.key) + b'\x00' + string(session) + string(self.name)
               + struct.pack('<IB', ts, rnd) + struct.pack('<H', 0))
        body = (b'\x0A' + struct.pack('<HHI', OS_OTCLIENT_LINUX, VERSION, VERSION) + b'\x00' + struct.pack('<H', 0)
                + rsa_block(rsa, self.n))
        c.send_raw(body)
        await c.w.drain()
        first = c.decrypt(await asyncio.wait_for(c.read_message(), 20))
        if first and first[0] in (0x14, 0x0B):
            text, _ = read_string(first, 1)
            raise RuntimeError('game refused: ' + text.replace('\n', ' '))
        if first and first[0] == 0x16:
            raise RuntimeError('waiting list (server full)')
        return c

    async def run(self, until):
        t0 = time.monotonic()
        try:
            session, world = await self.login_server()
            self.conn = await self.enter_game(session, world)
        except Exception as e:  # noqa: BLE001 - every failure is a result of the test
            self.stats['failed'].append('%s: %s' % (self.name, str(e) or type(e).__name__))
            return
        self.stats['login_ms'].append((time.monotonic() - t0) * 1000)
        self.alive = True
        reader = asyncio.ensure_future(self.drain())
        try:
            await self.act(until)
        finally:
            reader.cancel()
            if self.alive:
                try:
                    self.conn.send(b'\x14')  # logout
                    await self.conn.w.drain()
                except Exception:  # noqa: BLE001
                    pass
            self.conn.w.close()
            self.stats['bytes'] += self.conn.received

    async def drain(self):
        try:
            while True:
                await self.conn.read_message()
        except Exception:  # noqa: BLE001 - the server closed the connection
            if self.alive:
                self.alive = False
                self.stats['disconnects'] += 1

    async def act(self, until):
        a = self.args
        next_walk = time.monotonic() + random.random() * a.walk
        next_say = time.monotonic() + random.random() * a.say if a.say > 0 else float('inf')
        next_ping = time.monotonic() + 2
        while self.alive and time.monotonic() < until:
            now = time.monotonic()
            if now >= next_walk and a.walk > 0:
                self.conn.send(bytes([random.choice((0x65, 0x66, 0x67, 0x68))]))
                self.stats['walks'] += 1
                next_walk = now + a.walk * (0.75 + random.random() * 0.5)
            if now >= next_say:
                self.conn.send(b'\x96\x01' + string(random.choice(WORDS)))
                self.stats['says'] += 1
                next_say = now + a.say * (0.75 + random.random() * 0.5)
            if now >= next_ping:
                self.conn.send(b'\x1E')
                next_ping = now + 2
            try:
                await self.conn.w.drain()
            except Exception:  # noqa: BLE001
                break
            await asyncio.sleep(0.1)


def bot_name(index):
    letters = 'abcdefghijklmnopqrstuvwxyz'
    i, suffix = index, ''
    for _ in range(3):
        suffix = letters[i % 26] + suffix
        i //= 26
    return 'Loadbot ' + suffix.capitalize()


# ------------------------------------------------------------------------------------------------ server sampling
class Sampler:
    def __init__(self, pid):
        self.pid, self.samples, self.task = pid, [], None
        self.tick = os.sysconf('SC_CLK_TCK')

    def read(self):
        with open('/proc/%d/stat' % self.pid) as f:
            fields = f.read().rsplit(')', 1)[1].split()
        cpu = int(fields[11]) + int(fields[12])  # utime + stime
        rss = int(fields[21]) * os.sysconf('SC_PAGE_SIZE')
        threads = int(fields[17])
        return time.monotonic(), cpu, rss, threads

    async def loop(self):
        prev = self.read()
        while True:
            await asyncio.sleep(1)
            cur = self.read()
            dt = cur[0] - prev[0]
            self.samples.append({'t': cur[0], 'cpu': 100.0 * (cur[1] - prev[1]) / self.tick / dt, 'rss': cur[2],
                                 'threads': cur[3]})
            prev = cur


def pct(values, p):
    if not values:
        return 0
    s = sorted(values)
    return s[min(len(s) - 1, int(round(p / 100.0 * (len(s) - 1))))]


def probe_lines(path, start, end):
    out = []
    try:
        with open(path, errors='replace') as f:
            for line in f:
                m = re.search(r'\[loadtest-probe\] t=(\d+) players=(\d+) lag_avg_ms=([\d.]+) lag_max_ms=(\d+)', line)
                if m and start <= int(m.group(1)) <= end:
                    out.append((int(m.group(1)), int(m.group(2)), float(m.group(3)), int(m.group(4))))
    except OSError:
        pass
    return out


async def run_test(args):
    n = modulus_from_pem(args.key) if args.key else OT_RSA_N
    stats = {'login_ms': [], 'failed': [], 'bytes': 0, 'disconnects': 0, 'walks': 0, 'says': 0}
    sampler = Sampler(args.server_pid) if args.server_pid else None
    baseline = None
    if sampler:
        sampler.task = asyncio.ensure_future(sampler.loop())
        await asyncio.sleep(5)
        baseline = list(sampler.samples)
    wall0 = time.time()
    t0 = time.monotonic()
    ramp_end = t0 + args.ramp * args.count
    until = ramp_end + args.duration
    bots = [Bot(i, args, n, stats) for i in range(args.count)]
    tasks = []
    for bot in bots:
        tasks.append(asyncio.ensure_future(bot.run(until)))
        await asyncio.sleep(args.ramp)
    print('%d bots started in %.1fs; holding for %ds ...' % (args.count, time.monotonic() - t0, args.duration), flush=True)
    await asyncio.gather(*tasks)
    wall1 = time.time()
    if sampler:
        sampler.task.cancel()
    report(args, stats, sampler, baseline, ramp_end, until, wall0, wall1)


def report(args, s, sampler, baseline, ramp_end, until, wall0, wall1):
    ok = len(s['login_ms'])
    print()
    print('Load test: %d bots, %ds at full load, walk every %.1fs, say every %ss' % (args.count, args.duration, args.walk,
                                                                                     args.say))
    print('  logins ok %d / %d; login time p50 %.0f ms, p95 %.0f ms, max %.0f ms' % (
        ok, args.count, pct(s['login_ms'], 50), pct(s['login_ms'], 95), max(s['login_ms'] or [0])))
    for f in s['failed'][:10]:
        print('  failed: ' + f)
    if len(s['failed']) > 10:
        print('  ... %d more failures' % (len(s['failed']) - 10))
    print('  disconnects during the run: %d; steps sent %d, chat lines %d; received %.1f MB' % (
        s['disconnects'], s['walks'], s['says'], s['bytes'] / 1e6))
    if sampler and sampler.samples:
        def window(a, b):
            return [x for x in sampler.samples if a <= x['t'] <= b]
        full = window(ramp_end + 5, until)
        for label, rows in (('idle (before)', baseline or []), ('full load', full)):
            if not rows:
                continue
            cpu = [r['cpu'] for r in rows]
            rss = [r['rss'] / 1048576.0 for r in rows]
            print('  server %-14s CPU avg %5.1f%%  p95 %5.1f%%  max %5.1f%% of one core; RSS avg %.0f MB, max %.0f MB'
                  % (label, statistics.mean(cpu), pct(cpu, 95), max(cpu), statistics.mean(rss), max(rss)))
    if args.server_log:
        idle = probe_lines(args.server_log, int(wall0) - 60, int(wall0))
        lines = probe_lines(args.server_log, int(wall0), int(wall1) + 1)
        loaded = [l for l in lines if ok and l[1] >= ok * 0.9]
        if idle:
            print('  game loop lag before the run (probe, %d reports): avg %.1f ms, max %d ms (the engine timer floor)'
                  % (len(idle), statistics.mean(l[2] for l in idle), max(l[3] for l in idle)))
        if loaded:
            print('  game loop lag at %d+ players (probe, %d reports): avg %.1f ms, worst 5 s avg %.1f ms, max %d ms'
                  % (min(l[1] for l in loaded), len(loaded), statistics.mean(l[2] for l in loaded),
                     max(l[2] for l in loaded), max(l[3] for l in loaded)))
        if not idle and not loaded:
            print('  no [loadtest-probe] lines in %s (copy server/tools/loadtest_probe.lua into data/scripts and restart)'
                  % args.server_log)


# ------------------------------------------------------------------------------------------------ database setup
def mysql_base(args):
    db = args.db or os.environ.get('CHAOS_DB_NAME')
    if not db:
        sys.exit('no database: --db or CHAOS_DB_NAME')
    fd, opt = tempfile.mkstemp(prefix='chaos_lt_', suffix='.cnf')
    os.chmod(opt, 0o600)
    with os.fdopen(fd, 'w') as f:
        f.write('[client]\n')
        for key, env in (('host', 'CHAOS_DB_HOST'), ('port', 'CHAOS_DB_PORT'), ('user', 'CHAOS_DB_USER'),
                         ('password', 'CHAOS_DB_PASS')):
            if os.environ.get(env):
                f.write('%s="%s"\n' % (key, os.environ[env].replace('\\', '\\\\').replace('"', '\\"')))
    return [shutil.which('mysql') or 'mysql', '--defaults-extra-file=' + opt, '--batch', db], opt


def sql(args, statements):
    base, opt = mysql_base(args)
    try:
        proc = subprocess.run(base, input='\n'.join(statements).encode(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if proc.returncode != 0:
            sys.exit(proc.stdout.decode(errors='replace'))
        return proc.stdout.decode(errors='replace')
    finally:
        os.unlink(opt)


def setup(args):
    import hashlib
    x, y, z = (int(v) for v in args.pos.split(','))
    side = max(1, int(args.count ** 0.5 + 0.999))
    pw = hashlib.sha1(PREFIX.encode()).hexdigest()
    st = []
    for i in range(args.count):
        acc = '%s%04d' % (PREFIX, i)
        st.append("INSERT IGNORE INTO `accounts` (`name`, `password`, `email`) VALUES ('%s', '%s', '');" % (acc, pw))
        px, py = x - side // 2 + i % side, y - side // 2 + i // side
        st.append("INSERT IGNORE INTO `players` (`name`, `account_id`, `group_id`, `vocation`, `level`, `health`, "
                  "`healthmax`, `experience`, `mana`, `manamax`, `cap`, `town_id`, `posx`, `posy`, `posz`, `lastlogin`, "
                  "`looktype`) SELECT '%s', `id`, 1, %d, 100, 1500, 1500, 15694800, 500, 500, 1500, %d, %d, %d, %d, "
                  "UNIX_TIMESTAMP() - 86400, 128 FROM `accounts` WHERE `name` = '%s';"
                  % (bot_name(i), args.vocation, args.town, px, py, z, acc))
    sql(args, st)
    out = sql(args, ["SELECT COUNT(*) FROM `players` p JOIN `accounts` a ON a.`id` = p.`account_id` "
                     "WHERE a.`name` LIKE '%s%%';" % PREFIX])
    print('bot characters in the database: %s' % out.split()[-1])


def cleanup(args):
    sql(args, ["DELETE p FROM `players` p JOIN `accounts` a ON a.`id` = p.`account_id` WHERE a.`name` LIKE '%s____';"
               % PREFIX, "DELETE FROM `accounts` WHERE `name` LIKE '%s____';" % PREFIX])
    print('loadbot accounts and characters deleted')


# ------------------------------------------------------------------------------------------------ main
class Args:
    pass


def parse(argv):
    if not argv or argv[0] not in ('setup', 'run', 'cleanup'):
        print(__doc__)
        sys.exit(2)
    a = Args()
    a.cmd = argv[0]
    defaults = {'--count': 30, '--host': '127.0.0.1', '--port': 7171, '--game-port': 0, '--duration': 120,
                '--server-pid': 0, '--server-log': '', '--key': '', '--ramp': 0.5, '--walk': 1.0, '--say': 20.0,
                '--pos': '1500,1500,7', '--town': 1, '--vocation': 4, '--db': ''}
    vals = dict(defaults)
    flags = {'--no-source-ips': False}
    i = 1
    while i < len(argv):
        k = argv[i]
        if k in flags:
            flags[k] = True
        elif k in vals and i + 1 < len(argv):
            v = argv[i + 1]
            vals[k] = type(defaults[k])(v) if not isinstance(defaults[k], str) else v
            i += 1
        else:
            sys.exit('unknown option %s' % k)
        i += 1
    for k, v in list(vals.items()) + list(flags.items()):
        setattr(a, k.lstrip('-').replace('-', '_'), v)
    if a.count < 1 or a.count > 9999:
        sys.exit('--count 1..9999')
    return a


def main(argv):
    args = parse(argv)
    if args.cmd == 'setup':
        setup(args)
    elif args.cmd == 'cleanup':
        cleanup(args)
    else:
        asyncio.run(run_test(args))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
