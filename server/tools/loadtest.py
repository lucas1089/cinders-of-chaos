#!/usr/bin/env python3
"""Load test: N bot characters log in over the 10.98 protocol, walk around and talk, while the server is measured.

Standard library only (Python 3.7+). Three commands:

  setup    create the bot accounts and characters in the game database (mysql client; CHAOS_DB_* as for backup.sh)
             python3 -I server/tools/loadtest.py setup --count 30 [--pos 1500,1500,7 | --spread SERVER/data/chaos_poi.lua]
                 [--town 1] [--vocation 4] [--hash-iterations 120000] [--town-share 0.34] [--area-level 150] [--health 1500]
                 [--classes NAME:WEIGHT,... --levels L,L,... --server-data SERVER_DIR [--power 1.0]]
  run      log the bots in, walk, talk, measure, print a report
             python3 -I server/tools/loadtest.py run --count 30 --host 127.0.0.1 --port 7171 --duration 120
                 [--server-pid PID] [--server-log PATH] [--key key.pem] [--ramp 0.5] [--walk 1.0] [--say 20]
                 [--dev-key | --client-key HEX] [--client-build N] [--login-timeout 20] [--hunt]
                 [--reconnect MIN,MAX] [--drop P] [--abort P] [--opcodes FILE] [--opcode-every S] [--pm S] [--party S]
                 [--classes ... --levels ... --server-data SERVER_DIR [--pull STEPS,SECONDS] [--rotation-model CSV]]
  cleanup  delete the bot characters and accounts again
             python3 -I server/tools/loadtest.py cleanup

Accounts are named loadbot0000..., password "loadbot", stored as the website stores it (PBKDF2 with --hash-iterations,
which must equal the server's passwordHashIterations, default 120000; one salt for all bots). --hash-iterations 0 writes
the old unsalted SHA-1, which every first login re-hashes and writes back: only to test that migration, it is not what a
new player's login costs. One character each ("Loadbot Aaa", "Loadbot Aab", ...), level 100, placed at --pos (spread
over a square around it) with lastlogin set, so the new-player tutorial and kit do not start. --spread reads the
installed server's map markers (data/chaos_poi.lua, install step poi) and spreads the bots over the towns and the hunting
areas instead: --town-share of them (default 0.34) round the 20 temples, the rest over the hunting areas whose level
band starts at --area-level or below (default 150: the bots are level 100; 0 = every area), a few tiles around each
marker (a blocked tile puts the character on the nearest free one, or at its temple).
Hunting: --hunt sends the fight modes (offensive, chase on) after entering. The bots cannot pick a monster themselves
(that needs the creature ids of the map description, which they do not parse), so the TEST ONLY script
server/tools/loadtest_hunt.lua gives every bot near a monster that monster as its target and keeps the bots alive; with
it the bots fight the monsters of their hunting area (melee, the monsters' spells, loot, respawn) and never die (a real
player dies now and then; a level 100 bot in a level 400 area would nearly die every second, and every lethal hit runs
all prepare-death events, which is not what players cost). --health sets the bots' health.
Classes (server/README.md "Load test with area classes"): --classes "Elementalist:5,Berserker:4,..." (vocation names of
the installed data/XML/vocations.xml, weights) and --levels 100,300,600,1000 give bot i the class of a weighted round
robin and, class by class, the next level band (assign(); setup and run need the same two options, and run uses the
first --count of the plan). setup writes the vocation, level, its experience, health and mana by the vocation's gains,
a magic level and weapon skills of a hunter of that level (--power multiplies both: gear, gems and the tree), and 30
days of premium (the stamina bonus of a paying player; no spell needs premium since server/README.md "Free spells"). It places the bots in hunts of their level band: the map
markers of data/chaos_poi.lua and, through the hunt teleports' data/lib/chaos_hunt_places.lua, spawn points of the
planned hunts (up to 12 each), a band starting at half the level to the level; each position is moved to the nearest
spawn centre (a tile a monster stands on, so no wall: a character on a wall goes to its temple); --town-share of them,
spread evenly over the bots, at the temples. run reads the installed data/spells/spells.xml and
server/data/spells/rotation_model.csv (--rotation-model): each bot casts, by the real say packet, the attack spells
its class and level may use (no learned spells, no hand-cast utilities), the area spells first (most targets of 5),
each when its own and its group's cooldown are over, plus the class's pet and rage spells (CLASS_SUPPORT). --pull
STEPS,SECONDS: a lure of STEPS steps mostly one way (one per --walk), then SECONDS standing to fight (attack spells
only then), then the next lure. The bots need the server-side TEST ONLY hunt script (a target, kept alive, mana kept
up, faced to the target for the wave spells, a class weapon) as for --hunt; the report counts the casts.
Storms and spam (the stress test of server/README.md "Stress test"):
  --reconnect MIN,MAX  each bot leaves after MIN..MAX s in game and logs in again (a reconnect loop) until the run ends
  --drop P             a session ends without the logout packet (the socket is closed: a crashed client), chance P
  --abort P            a login is cut off half way, chance P: after the character list (no game connection), right
                       after the game login was sent (the answer is never read) or right after the first answer
  --opcodes FILE       a JSON list of [opcode, payload] (payload a string or a JSON object; "{name}" is replaced with the
                       bot's name, "{online}" with another bot in game, "{other}" with any other bot of the run, in game
                       or not); --opcode-every S sends a random one every S s
  --pm S               a private message to another bot every S s
  --party S            every S s: invite another bot in game into a party (it joins), or leave the party
  The report counts the sessions, cut logins, the opcodes, messages and party actions sent, and every kick.
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
Client guard (server/README.md "Client guard", engine src-patch 0021): by default the bots send the stock client version
1098 in the u32 client version fields, which a server with clientGuardMode "off" or "log" lets in (log: one line per
bot in data/logs/clientguard.log). Against "enforce" give the bots the client's key: --dev-key (the public development
key; the server needs clientGuardAllowDevKey = true, a test server only) or --client-key HEX / the environment variable
CHAOS_CLIENT_KEY (the real key: keep it out of shell history and logs). Then each bot sends the official identifier
(0x4343 << 16 | --client-build, default 1), answers the server's challenge on extended opcode 189 with the HMAC the
client computes and sends the module hello on extended opcode 190, as the client does.
RSA: m^65537 mod n. n is read from --key (the server's key.pem, PKCS#1, only the modulus is used) or is the standard
open-server public key that the client also ships.
The os sent is 10 (OTClient on Linux), so the engine enables extended opcodes and the Chaos modules talk to the bots
at login as they do to real clients. Each bot connects from its own loopback address (127.0.0.N) when --host is a
loopback address, because the Chaos multi-client rule allows only 2 characters per IP.

Measured: how many bots really entered the game, and for every other bot why not, grouped (the server's text from
the login error packet, a timeout and at which step, a connection the server closed without a message, a kick right
after entering with the server's text); login time (p50 / p90 / p95 / max) and its first part, the character list
(the login server's answer: account lookup and password check on the engine's login worker), bytes received, disconnects. A progress line
every 10 s says how many bots are in game, still logging in and failed; Ctrl+C or SIGTERM ends the run early and
still prints the report. Timeouts: 10 s per connect, 15 s for the login server's answer and for the game server's
challenge, 20 s for the answer to the game login (--login-timeout S sets the last one). With --server-pid
the server's CPU (% of one core) and memory (RSS) every second and the three busiest threads (the dispatcher, the game
loop, is the busiest; Linux /proc); with --server-log the lines of the probe server/tools/loadtest_probe.lua (TEST
ONLY) that the server printed during the run: the game loop lag (and the p95 of each 5 s when the probe prints
lag_p95_ms).
"""
import asyncio
import base64
import glob
import hashlib
import hmac
import json
import math
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
# client guard (engine src-patch 0021, client base patch 0035)
GUARD_TAG = 0x4343
GUARD_OPCODE = 189
GUARD_HELLO_OPCODE = 190
GUARD_DEV_KEY = bytes.fromhex('4445562d4b45592d63696e646572732d6f662d6368616f732d554e5341464521')  # "DEV-KEY-cinders-of-chaos-UNSAFE!"
DELTA = 0x9E3779B9
MASK = 0xFFFFFFFF
PREFIX = 'loadbot'
WORDS = ['hunting rotworms', 'anyone for a rift?', 'nice drop', 'where is the bank', 'level up!', 'orb of upheaval please',
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
    b = s.encode('latin-1') if isinstance(s, str) else s
    return struct.pack('<H', len(b)) + b


def guard_mac(key, nonce, account, character, build):
    """HMAC-SHA256(key, nonce || u16le #account || account || u16le #character || character || u16le build)"""
    a, c = account.encode('latin-1'), character.encode('latin-1')
    data = nonce + struct.pack('<H', len(a)) + a + struct.pack('<H', len(c)) + c + struct.pack('<H', build)
    return hmac.new(key, data, hashlib.sha256).digest()


def guard_answer(key, nonce, account, character, build):
    return 'cg1:%d:%s' % (build, guard_mac(key, nonce, account, character, build).hex())


def find_challenge(plain):
    """the nonce of a client guard challenge (0x32, opcode 189, string "cg1:<32 hex>") in a decrypted message, or None"""
    m = re.search(re.escape(bytes([0x32, GUARD_OPCODE])) + rb'\x24\x00cg1:([0-9a-f]{32})', plain)
    return bytes.fromhex(m.group(1).decode()) if m else None


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
        self.stage = 'start'
        self.cid = 0  # the creature id of the character (the first game message, 0x17)
        self.guard_wait = 0  # while set (a monotonic deadline) the reader looks for a late client guard challenge
        self.invited_by = []  # creature ids of bots that invited this one into a party
        self.rotation = []  # spells this bot casts (rotation_for), with --classes
        self.ready = {}  # spell words / spell group -> monotonic time it may be cast again

    def key(self):
        return [random.getrandbits(32) for _ in range(4)]

    async def open(self, port):
        local = (self.source, 0) if self.source else None
        reader, writer = await asyncio.wait_for(asyncio.open_connection(self.args.host, port, local_addr=local), 10)
        return Conn(reader, writer)

    async def login_server(self):
        self.stage = 'login server: connect'
        c = await self.open(self.args.port)
        c.key = self.key()
        rsa1 = b'\x00' + struct.pack('<4I', *c.key) + string(self.account) + string(self.password)
        rsa2 = b'\x00' + string('') + b'\x00'
        body = (b'\x01' + struct.pack('<HHI', OS_OTCLIENT_LINUX, VERSION, self.args.client_id) + struct.pack('<3I', 0, 0, 0)
                + b'\x00' + rsa_block(rsa1, self.n) + rsa_block(rsa2, self.n))
        c.send_raw(body)
        await c.w.drain()
        self.stage = 'login server: waiting for the character list'
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
        self.stage = 'game server: connect'
        c = await self.open(port)
        self.stage = 'game server: waiting for the challenge'
        msg = await asyncio.wait_for(c.read_message(), 15)
        if len(msg) < 12 or msg[6] != 0x1F:
            raise RuntimeError('no challenge from the game server')
        ts, rnd = struct.unpack_from('<IB', msg, 7)
        c.key = self.key()
        rsa = (b'\x00' + struct.pack('<4I', *c.key) + b'\x00' + string(session) + string(self.name)
               + struct.pack('<IB', ts, rnd) + struct.pack('<H', 0))
        body = (b'\x0A' + struct.pack('<HHI', OS_OTCLIENT_LINUX, VERSION, self.args.client_id) + b'\x00'
                + struct.pack('<H', 0) + rsa_block(rsa, self.n))
        c.send_raw(body)
        await c.w.drain()
        if self.abort_at == 'sent':
            c.w.close()
            raise LoginAborted('cut off right after the game login')
        self.stage = 'game server: waiting for the game login answer'
        first = c.decrypt(await asyncio.wait_for(c.read_message(), self.args.login_timeout))
        if first and first[0] in (0x14, 0x0B):
            text, _ = read_string(first, 1)
            raise RuntimeError('game refused: ' + text.replace('\n', ' '))
        if first and first[0] == 0x16:
            raise RuntimeError('waiting list (server full)')
        if len(first) >= 5 and first[0] == 0x17:
            self.cid = struct.unpack_from('<I', first, 1)[0]
        if self.abort_at == 'answer':
            c.w.close()
            raise LoginAborted('cut off after the first game answer')
        if self.args.guard_key:
            await self.answer_guard(c, first)
        return c

    async def answer_guard(self, c, first):
        """the client guard: the HMAC answer to the challenge (it comes with the first messages), then the module hello"""
        nonce, msg, extra = find_challenge(first), first, 0
        while nonce is None and extra < 3:
            try:
                msg = c.decrypt(await asyncio.wait_for(c.read_message(), 2))
            except asyncio.TimeoutError:
                break
            extra += 1
            if msg and msg[0] == 0x14:
                text, _ = read_string(msg, 1)
                raise RuntimeError('game refused: ' + text.replace('\n', ' '))
            nonce = find_challenge(msg)
        if nonce is None:
            # the server's client guard is off (or log mode with a refused id), or the challenge comes later (a busy
            # server, a reconnect to a character still in the game sends the map first): drain() keeps looking
            self.guard_wait = time.monotonic() + 15
            return
        self.send_guard_answer(c, nonce)
        await c.w.drain()

    def send_guard_answer(self, c, nonce):
        self.guard_wait = 0
        build = self.args.client_build
        c.send(b'\x32' + bytes([GUARD_OPCODE]) + string(guard_answer(self.args.guard_key, nonce, self.account, self.name, build)))
        hello = json.dumps({'action': 'hello', 'data': {'build': build, 'modules': 99}}, separators=(',', ':'))
        c.send(b'\x32' + bytes([GUARD_HELLO_OPCODE]) + string(hello))

    async def run(self, clock):
        """one session, or with --reconnect sessions until the run ends"""
        a = self.args
        if not a.reconnect:
            await self.session(clock, float('inf'))
            return
        lo, hi = a.reconnect
        while time.monotonic() < clock['until'] and not self.stats['stop']:
            failed = len(self.stats['failed'])
            await self.session(clock, time.monotonic() + lo + random.random() * (hi - lo))
            # a refused login is tried again a few seconds later, as a player would (not at once: that only floods
            # the login worker's queue)
            await asyncio.sleep(random.random() + (2 + 3 * random.random() if len(self.stats['failed']) > failed else 0))

    async def session(self, clock, leave_at):
        t0 = time.monotonic()
        a, st = self.args, self.stats
        self.abort_at = None
        if a.abort > 0 and random.random() < a.abort:
            self.abort_at = random.choice(('charlist', 'sent', 'answer'))
        st['connecting'] += 1
        try:
            session, world = await self.login_server()
            st.setdefault('charlist_ms', []).append((time.monotonic() - t0) * 1000)
            if self.abort_at == 'charlist':
                raise LoginAborted('cut off after the character list')
            self.conn = await self.enter_game(session, world)
        except LoginAborted:
            st['connecting'] -= 1
            st['aborted'] = st.get('aborted', 0) + 1
            return
        except Exception as e:  # noqa: BLE001 - every failure is a result of the test
            st['connecting'] -= 1
            st['failed'].append((self.name, failure_reason(self.stage, e)))
            return
        st['connecting'] -= 1
        st['login_ms'].append((time.monotonic() - t0) * 1000)
        st['in_game'] += 1
        st['sessions'] = st.get('sessions', 0) + 1
        self.entered = time.monotonic()
        self.alive = True
        ONLINE[self.cid] = self
        reader = asyncio.ensure_future(self.drain())
        if a.hunt:
            # fight modes as the client sends them: offensive, chase on, secure (no unmarked players), pvp mode
            self.conn.send(b'\xA0\x01\x01\x00\x00')
        dropped = False
        try:
            await self.act(clock, leave_at)
        finally:
            ONLINE.pop(self.cid, None)
            reader.cancel()
            if self.alive:
                dropped = a.drop > 0 and random.random() < a.drop
                if dropped:
                    st['dropped'] = st.get('dropped', 0) + 1
                else:
                    try:
                        self.conn.send(b'\x14')  # logout
                        await self.conn.w.drain()
                    except Exception:  # noqa: BLE001
                        pass
            self.conn.w.close()
            st['bytes'] += self.conn.received
            if self.alive:
                self.alive = False
                st['in_game'] -= 1

    async def drain(self):
        last = None
        try:
            while True:
                last = await self.conn.read_message()
                if self.guard_wait:
                    if time.monotonic() > self.guard_wait:
                        self.guard_wait = 0
                        self.stats['no_challenge'] += 1
                    else:
                        nonce = find_challenge(self.conn.decrypt(last))
                        if nonce is not None:
                            self.send_guard_answer(self.conn, nonce)
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001 - the server closed the connection
            if self.alive:
                self.alive = False
                self.stats['in_game'] -= 1
                self.stats['disconnects'] += 1
                text = None
                try:
                    text = disconnect_text(self.conn.decrypt(last)) if last else None
                except Exception:  # noqa: BLE001 - not a message we can read
                    pass
                after = time.monotonic() - self.entered
                if after < 10:
                    self.stats['kicked'].append((self.name, 'kicked %s after entering%s' % (
                        'within 10 s', ': ' + text if text else ' (no message)')))

    async def act(self, clock, leave_at=float('inf')):
        a = self.args
        def first(every):
            return time.monotonic() + random.random() * every if every > 0 else float('inf')
        next_walk = time.monotonic() + random.random() * a.walk
        next_say = first(a.say)
        next_op, next_pm, next_party = first(a.opcode_every), first(a.pm), first(a.party)
        next_ping = time.monotonic() + 2
        lure = {'steps': 0, 'fight_until': 0.0, 'dir': 0x65}
        while self.alive and time.monotonic() < min(clock['until'], leave_at) and not self.stats['stop']:
            now = time.monotonic()
            if self.rotation:
                # with --pull the attack spells wait for the fight part (a player lures without attacking)
                spell = next_spell(self.rotation, self.ready, now, attack=not a.pull or lure['fight_until'] > now)
                if spell:
                    self.conn.send(b'\x96\x01' + string(spell['words']))
                    self.ready[spell['words']] = now + spell['cooldown'] / 1000.0 + 0.1
                    self.ready[spell['group']] = now + spell['groupcooldown'] / 1000.0 + 0.1
                    self.count('casts' if spell['group'] == 'attack' else 'support_casts')
            if now >= next_op and a.opcode_list:
                op, payload = random.choice(a.opcode_list)
                self.conn.send(b'\x32' + bytes([op]) + string(self.fill(payload)))
                self.count('opcodes')
                next_op = now + a.opcode_every * (0.75 + random.random() * 0.5)
            if now >= next_pm:
                other = self.other()
                if other:
                    self.conn.send(b'\x96\x05' + string(other.name) + string(random.choice(WORDS)))
                    self.count('pms')
                next_pm = now + a.pm * (0.75 + random.random() * 0.5)
            if now >= next_party:
                self.party_step()
                next_party = now + a.party * (0.75 + random.random() * 0.5)
            if now >= next_walk and a.walk > 0 and a.pull:
                # lure: --pull STEPS steps mostly one way (the monsters on the way follow), then stand and fight
                # for the --pull seconds, then the next lure in a new direction
                if lure['fight_until'] <= now:
                    if lure['steps'] <= 0:
                        lure['steps'], lure['dir'] = a.pull[0], random.choice((0x65, 0x66, 0x67, 0x68))
                    self.conn.send(bytes([lure['dir'] if random.random() < 0.75 else random.choice((0x65, 0x66, 0x67, 0x68))]))
                    self.stats['walks'] += 1
                    lure['steps'] -= 1
                    if lure['steps'] <= 0:
                        lure['fight_until'] = now + a.pull[1] * (0.75 + random.random() * 0.5)
                next_walk = now + a.walk * (0.75 + random.random() * 0.5)
            elif now >= next_walk and a.walk > 0:
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


def next_spell(rotation, ready, now, attack=True):
    """the first spell of the rotation whose own cooldown and group cooldown are over (the area spells come first in
    it); attack=False: only the support spells (a lure)"""
    for s in rotation:
        if s['group'] == 'attack' and not attack:
            continue
        if ready.get(s['group'], 0) <= now and ready.get(s['words'], 0) <= now:
            return s
    return None


class LoginAborted(Exception):
    pass


ONLINE = {}  # creature id -> Bot in game (the targets of private messages and party invites)


def _bot_fill(self, payload):
    """{name}: this bot; {online}: another bot in game; {other}: any other bot of the run (in game or not)"""
    if '{online}' in payload:
        other = self.other()
        payload = payload.replace('{online}', other.name if other else self.name)
    if '{other}' in payload:
        i = random.randrange(self.args.count - 1) if self.args.count > 1 else 0
        payload = payload.replace('{other}', bot_name(i + 1 if i >= self.index else i) if self.args.count > 1 else self.name)
    return payload.replace('{name}', self.name)


def _bot_other(self):
    ids = [cid for cid in ONLINE if cid != self.cid]
    return ONLINE[random.choice(ids)] if ids else None


def _bot_count(self, key):
    self.stats[key] = self.stats.get(key, 0) + 1


def _bot_party_step(self):
    """join a party this bot was invited to, else leave (now and then) or invite another bot in game"""
    while self.invited_by:
        leader = self.invited_by.pop()
        if leader in ONLINE:
            self.conn.send(b'\xA4' + struct.pack('<I', leader))
            self.count('party_joins')
            return
    if random.random() < 0.2:
        self.conn.send(b'\xA7')
        self.count('party_leaves')
        return
    other = self.other()
    if other:
        self.conn.send(b'\xA3' + struct.pack('<I', other.cid))
        other.invited_by.append(self.cid)
        self.count('party_invites')


Bot.fill, Bot.other, Bot.count, Bot.party_step = _bot_fill, _bot_other, _bot_count, _bot_party_step


def disconnect_text(plain):
    """the text of a game server disconnect message (0x14 or 0x0B, u16 length, text), else None"""
    if len(plain) >= 3 and plain[0] in (0x14, 0x0B):
        try:
            text, _ = read_string(plain, 1)
        except struct.error:
            return None
        return text.replace('\n', ' ')
    return None


def failure_reason(stage, e):
    """one line why a bot did not enter the game; equal causes give equal lines (they are counted in the report)"""
    if isinstance(e, asyncio.TimeoutError):
        return 'timeout at %s' % stage
    if isinstance(e, asyncio.IncompleteReadError):
        return 'connection closed by the server without a message at %s' % stage
    if isinstance(e, ConnectionError) or isinstance(e, OSError):
        return '%s at %s' % (type(e).__name__ + (': ' + e.strerror if getattr(e, 'strerror', None) else ''), stage)
    text = str(e) or type(e).__name__
    # "You are at place 12 on the waiting list", retry times ...: numbers would split one cause into many lines
    return re.sub(r'\d+', 'N', text)


def group_reasons(failed):
    """[(name, reason)] -> [(count, reason, first names)] most frequent first"""
    groups = {}
    for name, reason in failed:
        groups.setdefault(reason, []).append(name)
    return sorted(((len(v), k, v[:3]) for k, v in groups.items()), key=lambda g: (-g[0], g[1]))


def bot_name(index):
    letters = 'abcdefghijklmnopqrstuvwxyz'
    i, suffix = index, ''
    for _ in range(3):
        suffix = letters[i % 26] + suffix
        i //= 26
    return 'Loadbot ' + suffix.capitalize()


# ------------------------------------------------------------------------------------------------ classes and spells
# support spells that are part of a class's damage (a pet, a rage): cast whenever ready, beside the attack rotation
CLASS_SUPPORT = ('vael ferh', 'vyr sang khar', 'vael oss')


def _attrs(text):
    return dict(re.findall(r'([\w-]+)\s*=\s*"([^"]*)"', text))


def parse_vocations(text):
    """{name: {'id', 'hp', 'mana'}} of a data/XML/vocations.xml (gainhp / gainmana per level)"""
    out = {}
    for m in re.finditer(r'<vocation\b([^>]*)>', re.sub(r'<!--.*?-->', '', text, flags=re.S)):
        a = _attrs(m.group(1))
        if 'id' in a and 'name' in a:
            out[a['name']] = {'id': int(a['id']), 'hp': int(a.get('gainhp', 5)), 'mana': int(a.get('gainmana', 5))}
    return out


def parse_spells(text):
    """[{words, name, group, level, mana, cooldown, groupcooldown, needtarget, vocations}] of the instant spells of a
    data/spells/spells.xml (comments skipped; an empty vocation list means every vocation, as in the engine)"""
    out = []
    text = re.sub(r'<!--.*?-->', '', text, flags=re.S)
    for m in re.finditer(r'<instant\b([^>]*?)(/>|>(.*?)</instant>)', text, flags=re.S):
        a = _attrs(m.group(1))
        if 'words' not in a:
            continue
        out.append({'words': a['words'], 'name': a.get('name', ''), 'group': a.get('group', ''),
                    'level': int(a.get('level', a.get('lvl', 0)) or 0), 'mana': int(a.get('mana', 0) or 0),
                    'cooldown': int(a.get('cooldown', 2000) or 0), 'groupcooldown': int(a.get('groupcooldown', 2000) or 0),
                    'needtarget': a.get('needtarget') == '1', 'needlearn': a.get('needlearn') == '1',
                    'params': a.get('params') == '1',
                    'vocations': set(re.findall(r'<vocation\s+name\s*=\s*"([^"]+)"', m.group(3) or ''))})
    return out


def parse_rotation_model(text):
    """{words: (targets hit in a pack of 5, flags)} of server/data/spells/rotation_model.csv"""
    import csv
    import io
    out = {}
    for row in csv.DictReader(io.StringIO(text)):
        try:
            out[row['words']] = (float(row['t5'] or 1), row.get('flags') or '')
        except (KeyError, ValueError):
            continue
    return out


def rotation_for(spells, model, vocation, level):
    """the spells a bot of this vocation and level casts: the attack spells it may use (not learned ones, not the
    hand-cast utilities of rotation_model.csv), area spells first (most targets of 5, then the higher level spell),
    and the class's pet / rage support spells (CLASS_SUPPORT)"""
    rot = []
    for s in spells:
        if s['level'] > level or s['needlearn'] or s['params'] or (s['vocations'] and vocation not in s['vocations']):
            continue
        t5, flags = model.get(s['words'], (1.0, ''))
        if s['group'] == 'attack' and 'utility' not in flags and 'skip' not in flags:
            rot.append(dict(s, t5=t5))
        elif s['words'] in CLASS_SUPPORT:
            rot.append(dict(s, t5=0.0, group='support'))
    rot.sort(key=lambda s: (s['group'] != 'support', -s['t5'], -s['level'], s['words']))
    return rot


def parse_weights(text):
    """'Elementalist:4,Berserker:2' -> [('Elementalist', 4), ('Berserker', 2)]"""
    out = []
    for part in text.split(','):
        part = part.strip()
        if not part:
            continue
        name, _, w = part.partition(':')
        try:
            weight = int(w) if w else 1
        except ValueError:
            weight = -1
        if weight < 1:
            raise ValueError('class weight must be a whole number 1 or more: %r' % part)
        out.append((name.strip(), weight))
    return out


def assign(index, classes, levels):
    """(class, level) of bot index: the classes round robin by weight, each class through every level band in turn
    (setup and run compute the same, so both need the same --classes and --levels)"""
    wheel = [name for name, w in classes for _ in range(w)]
    return wheel[index % len(wheel)], levels[(index // len(wheel)) % len(levels)]


def exp_for_level(level):
    lv = level - 1
    return (50 * lv ** 3 - 150 * lv ** 2 + 400 * lv) // 3


MAGES = {'Mystic', 'Elementalist', 'Illusionist', 'Necromancer', 'Lich', 'Bone Lord'}


def class_stats(vocation, level, gains, power=1.0):
    """health, mana, magic level and weapon skill of a bot: a hunter of that level, roughly (hp / mana per level of
    vocations.xml; magic level and skills grow slower than level, as in play); power multiplies the magic level and
    the skill (what gear, gems and the passive tree add to a real character's damage)"""
    hp = 185 + (level - 8) * gains.get('hp', 5)
    mana = 90 + (level - 8) * gains.get('mana', 5)
    skill = int(min(130, 40 + 22 * math.log(max(1, level) / 20.0 + 1, 2)) * power)
    if vocation in MAGES:
        return hp, mana, int(min(140, 30 + 20 * math.log(level / 20.0 + 1, 2)) * power), 20
    return hp, mana, int(min(60, 5 + level / 25.0) * power), skill


def hunt_marks(text):
    """[(low, high, x, y, z)] of the hunt marks of a data/chaos_poi.lua that name a level band (hunting levels since
    2026-10-27, gen_poi.py)"""
    out = []
    for m in re.finditer(r'\{k = "hunt", x = (\d+), y = (\d+), z = (\d+), n = "([^"]*)"', text):
        band = re.search(r'\(level (\d+)-(\d+)\)', m.group(4))
        if band:
            out.append((int(band.group(1)), int(band.group(2)), int(m.group(1)), int(m.group(2)), int(m.group(3))))
    return out


def place_marks(places_text, spawn_text, per_place=12, reach=150):
    """[(low, high, x, y, z)] in the planned hunts that the hunt teleports lead to (data/lib/chaos_hunt_places.lua,
    install step contentareas): up to per_place spawn centres of the spawn file round each place's arrival (within
    `reach` sqm, one floor up or down, the nearest arrival wins), spread over the place; its level band"""
    places = [(int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5)))
              for m in re.finditer(r'level = \{(\d+), (\d+)\}.*?arrival = \{x = (\d+), y = (\d+), z = (\d+)\}',
                                   places_text)]
    if not places:
        return []
    near = {i: [] for i in range(len(places))}
    for m in re.finditer(r'<spawn\s+centerx="(\d+)"\s+centery="(\d+)"\s+centerz="(\d+)"', spawn_text):
        x, y, z = int(m.group(1)), int(m.group(2)), int(m.group(3))
        best = None
        for i, p in enumerate(places):
            d = max(abs(x - p[2]), abs(y - p[3]))
            if d <= reach and abs(z - p[4]) <= 1 and (best is None or d < best[0]):
                best = (d, i)
        if best:
            near[best[1]].append((x, y, z))
    out = []
    for i, p in enumerate(places):
        pts = sorted(near[i])
        step = max(1, len(pts) // per_place)
        out.extend((p[0], p[1]) + pt for pt in pts[::step][:per_place])
    return out


def spawn_index(spawn_text, cell=16):
    """{(x // cell, y // cell, z): [(x, y, z)]} of the spawn centres of a spawn file"""
    out = {}
    for m in re.finditer(r'<spawn\s+centerx="(\d+)"\s+centery="(\d+)"\s+centerz="(\d+)"', spawn_text):
        x, y, z = int(m.group(1)), int(m.group(2)), int(m.group(3))
        out.setdefault((x // cell, y // cell, z), []).append((x, y, z))
    return out


def snap_to_spawn(pos, index, reach=12, cell=16, centre_levels=None, max_level=None):
    """the spawn centre nearest to pos on its floor within reach sqm (a tile a monster stands on, so not a wall: a
    character placed on a wall goes to its temple), else pos. With centre_levels (spawn_levels) and max_level: only a
    centre whose monsters all have a hunting level of at most max_level (an unknown centre never)"""
    x, y, z = pos
    best = None
    for cx in range((x - reach) // cell, (x + reach) // cell + 1):
        for cy in range((y - reach) // cell, (y + reach) // cell + 1):
            for p in index.get((cx, cy, z), ()):
                d = max(abs(p[0] - x), abs(p[1] - y))
                if d > reach or (best is not None and (d, p) >= best):
                    continue
                if centre_levels is not None and max_level is not None and centre_levels.get(p, 10 ** 9) > max_level:
                    continue
                best = (d, p)
    return best[1] if best else pos


def pool_levels(pool_text):
    """{lower monster name: level} of the hunting part of data/scripts/chaos/bounty_pool.lua (the fair-hunt level; the
    hunting level is twice it, pace_config.lua baseLevelMult)"""
    hunt = pool_text.split('bosses =')[0]
    return {m.group(1).lower(): int(m.group(2))
            for m in re.finditer(r'\{name = "([^"]+)", level = (\d+)', hunt)}


def base_level_mult(path=None):
    """pace_config.lua baseLevelMult (the hunting level is the pool level times it); the repo's copy unless `path`"""
    path = path or os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'data', 'scripts', 'chaos',
                                'pace_config.lua')
    m = re.search(r'\bbaseLevelMult\s*=\s*(\d+)', read_text(path))
    if not m:
        raise ValueError('baseLevelMult not found in %s' % path)
    return int(m.group(1))


def spawn_levels(spawn_text, levels, mult=None):
    """{(x, y, z): the highest hunting level (mult x the pool level, mult: baseLevelMult) of the monsters of the spawn at
    that centre; the pool levels of pool_levels stay pool levels, only the map marks print hunting levels); a monster
    the pool does not know counts as unknown (never safe)"""
    mult = base_level_mult() if mult is None else mult
    out = {}
    for m in re.finditer(r'<spawn\s+centerx="(\d+)"\s+centery="(\d+)"\s+centerz="(\d+)"[^>]*>(.*?)</spawn>',
                         spawn_text, re.S):
        centre = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
        top = 0
        for name in re.findall(r'<monster\s+name="([^"]+)"', m.group(4)):
            lv = levels.get(name.lower())
            top = max(top, 10 ** 9 if lv is None else mult * lv)
        out[centre] = max(out.get(centre, 0), top)
    return out


def hunts_for_level(hunts, level):
    """the hunts a character of this level would pick: band low end at or under the level and at least half of it
    (a level 1000 hunts 500+, a level 100 hunts 50-100); else the hunts with the highest low end under it (or, with
    none under it, the lowest ones)"""
    fit = [h for h in hunts if level * 0.5 <= h[0] <= level]
    if not fit:
        under = [h for h in hunts if h[0] <= level]
        if under:
            top = max(h[0] for h in under)
            fit = [h for h in under if h[0] >= top * 0.8]
        else:
            low = min(h[0] for h in hunts)
            fit = [h for h in hunts if h[0] == low]
    return fit


def level_positions(hunts, temples, levels_of_bots, town_share, pick=None):
    """one position per bot: a town_share of them (spread evenly over the bots, so over every class and level) round
    robin over the temples, the others over the hunts of their level (hunts_for_level, or pick(hunts, level)), up to 3
    tiles off the mark; deterministic"""
    out, used = [], {}
    for i, level in enumerate(levels_of_bots):
        rnd = random.Random(i)
        if int((i + 1) * town_share + 1e-9) > int(i * town_share + 1e-9) or not hunts:
            x, y, z = temples[i % len(temples)]
            off = 5
        else:
            fit = (pick or hunts_for_level)(hunts, level)
            k = used.get(level, 0)
            used[level] = k + 1
            x, y, z = fit[(k * 7919 + level) % len(fit)][2:]
            off = 3
        out.append((x + rnd.randint(-off, off), y + rnd.randint(-off, off), z))
    return out


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
        return time.monotonic(), cpu, rss, threads, self.read_threads()

    def read_threads(self):
        """{'name/tid': utime + stime} of every thread of the server (the dispatcher is the game loop)"""
        out = {}
        base = '/proc/%d/task' % self.pid
        try:
            tids = os.listdir(base)
        except OSError:
            return out
        for tid in tids:
            try:
                with open('%s/%s/stat' % (base, tid)) as f:
                    raw = f.read()
            except OSError:
                continue
            name = raw[raw.index('(') + 1:raw.rindex(')')]
            fields = raw.rsplit(')', 1)[1].split()
            out['%s/%s' % (name, tid)] = int(fields[11]) + int(fields[12])
        return out

    async def loop(self):
        prev = self.read()
        while True:
            await asyncio.sleep(1)
            cur = self.read()
            dt = cur[0] - prev[0]
            per = {k: 100.0 * (v - prev[4].get(k, v)) / self.tick / dt for k, v in cur[4].items()}
            self.samples.append({'t': cur[0], 'cpu': 100.0 * (cur[1] - prev[1]) / self.tick / dt, 'rss': cur[2],
                                 'threads': cur[3], 'per_thread': per, 'busiest': max(per.values() or [0])})
            prev = cur


def thread_summary(rows, top=3):
    """[(thread, avg %, p95 %)] of the threads with the most CPU over the samples, most first"""
    acc = {}
    for r in rows:
        for k, v in r.get('per_thread', {}).items():
            acc.setdefault(k, []).append(v)
    out = [(k, sum(v) / len(rows), pct(v, 95)) for k, v in acc.items()]
    return sorted(out, key=lambda x: -x[1])[:top]


def pct(values, p):
    if not values:
        return 0
    s = sorted(values)
    return s[min(len(s) - 1, int(round(p / 100.0 * (len(s) - 1))))]


def spread(values):
    """'p50 .. ms, p90 .. ms, p95 .. ms, max .. ms' of a list of times in ms"""
    return 'p50 %.0f ms, p90 %.0f ms, p95 %.0f ms, max %.0f ms' % (
        pct(values, 50), pct(values, 90), pct(values, 95), max(values or [0]))


def probe_lines(path, start, end):
    out = []
    try:
        with open(path, errors='replace') as f:
            for line in f:
                m = re.search(r'\[loadtest-probe\] t=(\d+) players=(\d+) lag_avg_ms=([\d.]+) lag_max_ms=(\d+)'
                              r'(?: samples=\d+)?(?: lag_p95_ms=(\d+))?', line)
                if m and start <= int(m.group(1)) <= end:
                    out.append((int(m.group(1)), int(m.group(2)), float(m.group(3)), int(m.group(4)),
                                int(m.group(5)) if m.group(5) else None))
    except OSError:
        pass
    return out


async def run_test(args):
    n = modulus_from_pem(args.key) if args.key else OT_RSA_N
    stats = {'login_ms': [], 'charlist_ms': [], 'failed': [], 'kicked': [], 'bytes': 0, 'disconnects': 0, 'walks': 0,
             'says': 0, 'no_challenge': 0, 'in_game': 0, 'connecting': 0, 'stop': False, 'reconnect': bool(args.reconnect)}
    sampler = Sampler(args.server_pid) if args.server_pid else None
    baseline = None
    if sampler:
        sampler.task = asyncio.ensure_future(sampler.loop())
        await asyncio.sleep(5)
        baseline = list(sampler.samples)
    wall0 = time.time()
    t0 = time.monotonic()
    # the hold starts when the last bot was started (the ramp takes longer than ramp x count on a busy machine)
    clock = {'until': float('inf')}
    bots = [Bot(i, args, n, stats) for i in range(args.count)]
    plan = class_plan(args)
    if plan:
        spells = parse_spells(read_text(os.path.join(args.server_data, 'data', 'spells', 'spells.xml')))
        model_path = args.rotation_model or os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data',
                                                         'spells', 'rotation_model.csv')
        model = parse_rotation_model(read_text(model_path)) if os.path.exists(model_path) else {}
        rotations = {}
        for bot, key in zip(bots, plan):
            if key not in rotations:
                rotations[key] = rotation_for(spells, model, key[0], key[1])
            bot.rotation = rotations[key]
        for (cls, level), rot in sorted(rotations.items()):
            area = [s['name'] for s in rot if s['group'] == 'attack' and s['t5'] > 1]
            print('  %s %d: %d spells, area: %s' % (cls, level, len(rot), ', '.join(area) or 'none'))
    tasks = []
    loop = asyncio.get_event_loop()
    for sig in ('SIGINT', 'SIGTERM'):
        try:
            loop.add_signal_handler(getattr(__import__('signal'), sig), lambda: stats.update(stop=True))
        except (NotImplementedError, AttributeError, RuntimeError):
            pass  # Windows: Ctrl+C still ends the run, without a report
    progress = asyncio.ensure_future(report_progress(stats, args.count, t0))
    for bot in bots:
        if stats['stop']:
            break
        tasks.append(asyncio.ensure_future(bot.run(clock)))
        await asyncio.sleep(args.ramp)
    ramp_end = time.monotonic()
    until = clock['until'] = ramp_end + args.duration
    print('%d bots started in %.1fs (%d in game, %d logging in, %d failed); holding for %ds ...' % (
        len(tasks), time.monotonic() - t0, stats['in_game'], stats['connecting'], len(stats['failed']), args.duration),
        flush=True)
    await asyncio.gather(*tasks)
    progress.cancel()
    wall1 = time.time()
    if sampler:
        sampler.task.cancel()
    report(args, stats, sampler, baseline, ramp_end, until, wall0, wall1)


async def report_progress(stats, count, t0):
    while True:
        await asyncio.sleep(10)
        if stats.get('reconnect'):
            print('  [%4.0fs] in game %d, logging in %d, failed %d, sessions %d, cut off %d, dropped %d' % (
                time.monotonic() - t0, stats['in_game'], stats['connecting'], len(stats['failed']),
                stats.get('sessions', 0), stats.get('aborted', 0), stats.get('dropped', 0)), flush=True)
            continue
        print('  [%4.0fs] in game %d, logging in %d, failed %d, not started %d' % (
            time.monotonic() - t0, stats['in_game'], stats['connecting'], len(stats['failed']),
            count - len(stats['login_ms']) - len(stats['failed']) - stats['connecting']), flush=True)


def report(args, s, sampler, baseline, ramp_end, until, wall0, wall1):
    ok = len(s['login_ms'])
    print()
    print('Load test: %d bots, %ds at full load, walk every %.1fs, say every %ss%s' % (
        args.count, args.duration, args.walk, args.say, ' (stopped early)' if s['stop'] else ''))
    if args.reconnect:
        print('  %d bots, %d logins entered the game (reconnect loops); failed %d; kicked within 10 s of entering %d' % (
            args.count, ok, len(s['failed']), len(s['kicked'])))
    else:
        print('  entered the game %d / %d; failed %d; kicked within 10 s of entering %d' % (
            ok, args.count, len(s['failed']), len(s['kicked'])))
    print('  login time %s (connect to in game)' % spread(s['login_ms']))
    if s.get('charlist_ms'):
        print('  character list %s (%d answers; the login server part of the above)' % (
            spread(s['charlist_ms']), len(s['charlist_ms'])))
    for count, reason, names in group_reasons(s['failed'] + s['kicked']):
        print('  %4d x %s (%s%s)' % (count, reason, ', '.join(names), ', ...' if count > len(names) else ''))
    print('  disconnects during the run: %d; steps sent %d, chat lines %d; received %.1f MB' % (
        s['disconnects'], s['walks'], s['says'], s['bytes'] / 1e6))
    extra = [(k, s.get(k, 0)) for k in ('casts', 'support_casts', 'sessions', 'aborted', 'dropped', 'opcodes', 'pms', 'party_invites',
                                       'party_joins', 'party_leaves') if s.get(k)]
    if extra:
        print('  ' + ', '.join('%s %d' % kv for kv in extra))
    if args.guard_key:
        print('  client guard: build %d, %s key; logins without a challenge (guard off): %d' % (
            args.client_build, 'development' if args.guard_key == GUARD_DEV_KEY else 'given', s['no_challenge']))
    else:
        print('  client guard: stock client version 1098 sent (only a server in clientGuardMode "off" or "log" lets it in)')
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
            print('    busiest threads: ' + ', '.join('%s avg %.1f%% p95 %.1f%%' % t for t in thread_summary(rows)))
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
            p95s = [l[4] for l in loaded if l[4] is not None]
            if p95s:
                print('    p95 of each 5 s: median %d ms, worst %d ms; 5 s windows with a stall of 500 ms or more: %d'
                      % (pct(p95s, 50), max(p95s), sum(1 for l in loaded if l[3] >= 500)))
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


def password_hash(password, iterations):
    """accounts.password as the website writes it (engine src-patch 0014): pbkdf2-sha256$<iterations>$<salt>$<key>,
    standard base64. 0 iterations: the old unsalted SHA-1 (the first login re-hashes it: the migration path)"""
    if iterations <= 0:
        return hashlib.sha1(password.encode()).hexdigest()
    salt = os.urandom(16)
    key = hashlib.pbkdf2_hmac('sha256', password.encode(), salt, iterations, 32)
    return 'pbkdf2-sha256$%d$%s$%s' % (iterations, base64.b64encode(salt).decode(), base64.b64encode(key).decode())


def poi_marks(text, max_area_level=0):
    """[(kind, x, y, z)] of the temple and hunt marks of a data/chaos_poi.lua (gen_poi.py's format); with
    max_area_level only the hunting areas whose level band starts at or below it ("... (level 70-90)")"""
    out = []
    for m in re.finditer(r'\{k = "(temple|hunt)", x = (\d+), y = (\d+), z = (\d+), n = "([^"]*)"', text):
        band = re.search(r'\(level (\d+)-\d+\)', m.group(5))
        if m.group(1) == 'hunt' and max_area_level and band and int(band.group(1)) > max_area_level:
            continue
        out.append((m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4))))
    return out


def spread_positions(marks, count, town_share):
    """count positions: the first round(count * town_share) round robin over the temples (up to 5 tiles off), the
    others over the hunting areas (up to 3 tiles off); the same marks and count give the same positions"""
    temples = [m[1:] for m in marks if m[0] == 'temple']
    hunts = [m[1:] for m in marks if m[0] == 'hunt']
    if not temples or not hunts:
        raise ValueError('no temple or no hunting marks (is it data/chaos_poi.lua of an installed server?)')
    towns = int(round(count * town_share))
    out = []
    for i in range(count):
        rnd = random.Random(i)
        (x, y, z), off = (temples[i % len(temples)], 5) if i < towns else (hunts[(i - towns) % len(hunts)], 3)
        out.append((x + rnd.randint(-off, off), y + rnd.randint(-off, off), z))
    return out


def read_text(path):
    with open(path, errors='replace') as f:
        return f.read()


def class_plan(args):
    """[(class, level)] per bot from --classes / --levels, or None (every bot --vocation at level 100)"""
    if not args.classes:
        return None
    return [assign(i, args.class_weights, args.level_list) for i in range(args.count)]


def setup_classes(args, plan):
    data = os.path.join(args.server_data, 'data')
    vocs = parse_vocations(read_text(os.path.join(data, 'XML', 'vocations.xml')))
    missing = sorted({c for c, _ in plan} - set(vocs))
    if missing:
        sys.exit('--classes: no such vocation in vocations.xml: %s' % ', '.join(missing))
    poi = read_text(os.path.join(data, 'chaos_poi.lua'))
    temples = [m[1:] for m in poi_marks(poi) if m[0] == 'temple']
    hunts = hunt_marks(poi)
    places = os.path.join(data, 'lib', 'chaos_hunt_places.lua')
    spawns = sorted(glob.glob(os.path.join(data, 'world', '*-spawn.xml')))[:1]
    if os.path.exists(places) and spawns:
        planned = place_marks(read_text(places), read_text(spawns[0]))
        print('hunts: %d of the map markers, %d spawn points of %d planned hunts' % (
            len(hunts), len(planned), len({h[:2] for h in planned})))
        hunts += planned
    positions = level_positions(hunts, temples, [lv for _, lv in plan], args.town_share)
    if spawns:
        index = spawn_index(read_text(spawns[0]))
        positions = [snap_to_spawn(p, index) for p in positions]
    pw = password_hash(PREFIX, args.hash_iterations)
    st = []
    for i, (cls, level) in enumerate(plan):
        acc = '%s%04d' % (PREFIX, i)
        hp, mana, ml, skill = class_stats(cls, level, vocs[cls], args.power)
        px, py, z = positions[i]
        # premium for 30 days: the stamina bonus of a paying player (spells are free, README "Free spells")
        st.append("INSERT IGNORE INTO `accounts` (`name`, `password`, `email`, `premium_ends_at`) VALUES ('%s', '%s', '', "
                  "UNIX_TIMESTAMP() + 30 * 86400);" % (acc, pw))
        st.append("INSERT IGNORE INTO `players` (`name`, `account_id`, `group_id`, `vocation`, `level`, `health`, "
                  "`healthmax`, `experience`, `mana`, `manamax`, `maglevel`, `skill_fist`, `skill_club`, `skill_sword`, "
                  "`skill_axe`, `skill_dist`, `skill_shielding`, `cap`, `town_id`, `posx`, `posy`, `posz`, `lastlogin`, "
                  "`looktype`) SELECT '%s', `id`, 1, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, 3000, %d, "
                  "%d, %d, %d, UNIX_TIMESTAMP() - 86400, 128 FROM `accounts` WHERE `name` = '%s';"
                  % (bot_name(i), vocs[cls]['id'], level, hp, hp, exp_for_level(level), mana, mana, ml, skill, skill,
                     skill, skill, skill, skill, args.town, px, py, z, acc))
    return st


def setup(args):
    plan = class_plan(args)
    if plan:
        sql(args, setup_classes(args, plan))
        out = sql(args, ["SELECT p.`vocation`, p.`level`, COUNT(*) FROM `players` p JOIN `accounts` a ON a.`id` = "
                         "p.`account_id` WHERE a.`name` LIKE '%s%%' GROUP BY 1, 2;" % PREFIX])
        print('bot characters in the database (vocation, level, count):\n' + out.strip())
        return
    if args.spread:
        with open(args.spread, errors='replace') as f:
            positions = spread_positions(poi_marks(f.read(), args.area_level), args.count, args.town_share)
    else:
        x, y, z = (int(v) for v in args.pos.split(','))
        side = max(1, int(args.count ** 0.5 + 0.999))
        positions = [(x - side // 2 + i % side, y - side // 2 + i // side, z) for i in range(args.count)]
    pw = password_hash(PREFIX, args.hash_iterations)
    st = []
    for i in range(args.count):
        acc = '%s%04d' % (PREFIX, i)
        st.append("INSERT IGNORE INTO `accounts` (`name`, `password`, `email`) VALUES ('%s', '%s', '');" % (acc, pw))
        px, py, z = positions[i]
        st.append("INSERT IGNORE INTO `players` (`name`, `account_id`, `group_id`, `vocation`, `level`, `health`, "
                  "`healthmax`, `experience`, `mana`, `manamax`, `cap`, `town_id`, `posx`, `posy`, `posz`, `lastlogin`, "
                  "`looktype`) SELECT '%s', `id`, 1, %d, 100, %d, %d, 15694800, 500, 500, 1500, %d, %d, %d, %d, "
                  "UNIX_TIMESTAMP() - 86400, 128 FROM `accounts` WHERE `name` = '%s';"
                  % (bot_name(i), args.vocation, args.health, args.health, args.town, px, py, z, acc))
    sql(args, st)
    out = sql(args, ["SELECT COUNT(*) FROM `players` p JOIN `accounts` a ON a.`id` = p.`account_id` "
                     "WHERE a.`name` LIKE '%s%%';" % PREFIX])
    print('bot characters in the database: %s' % out.split()[-1])


def cleanup(args):
    sql(args, ["DELETE p FROM `players` p JOIN `accounts` a ON a.`id` = p.`account_id` WHERE a.`name` LIKE '%s____';"
               % PREFIX, "DELETE FROM `accounts` WHERE `name` LIKE '%s____';" % PREFIX])
    print('loadbot accounts and characters deleted')


def load_opcodes(path):
    """[(opcode, payload text)] of a --opcodes file: a JSON list of [opcode, payload]"""
    with open(path) as f:
        rows = json.load(f)
    out = []
    for row in rows:
        if not (isinstance(row, list) and len(row) == 2 and isinstance(row[0], int) and 0 < row[0] < 256):
            sys.exit('--opcodes: every entry is [opcode 1..255, payload]: %r' % (row,))
        payload = row[1] if isinstance(row[1], str) else json.dumps(row[1], separators=(',', ':'))
        out.append((row[0], payload))
    if not out:
        sys.exit('--opcodes: the file lists no opcode')
    return out


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
                '--pos': '1500,1500,7', '--town': 1, '--vocation': 4, '--db': '', '--client-key': '',
                '--client-build': 1, '--login-timeout': 20.0, '--hash-iterations': 120000, '--spread': '',
                '--town-share': 0.34, '--health': 1500, '--area-level': 150, '--reconnect': '', '--drop': 0.0,
                '--abort': 0.0, '--opcodes': '', '--opcode-every': 0.0, '--pm': 0.0, '--party': 0.0,
                '--classes': '', '--levels': '100', '--power': 1.0, '--server-data': '', '--pull': '', '--rotation-model': ''}
    vals = dict(defaults)
    flags = {'--no-source-ips': False, '--dev-key': False, '--hunt': False}
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
    if not 0 <= a.town_share <= 1:
        sys.exit('--town-share 0..1')
    if a.count < 1 or a.count > 9999:
        sys.exit('--count 1..9999')
    if not 1 <= a.client_build <= 0xFFFF:
        sys.exit('--client-build 1..65535')
    if a.reconnect:
        m = re.match(r'^(\d+(?:\.\d+)?),(\d+(?:\.\d+)?)$', a.reconnect)
        if not m or float(m.group(1)) > float(m.group(2)):
            sys.exit('--reconnect MIN,MAX (seconds, MIN <= MAX)')
        a.reconnect = (float(m.group(1)), float(m.group(2)))
    if not (0 <= a.drop <= 1 and 0 <= a.abort <= 1):
        sys.exit('--drop and --abort are chances 0..1')
    a.opcode_list = load_opcodes(a.opcodes) if a.opcodes else []
    try:
        a.class_weights = parse_weights(a.classes)
        a.level_list = [int(v) for v in a.levels.split(',') if v.strip()]
    except ValueError as e:
        sys.exit('--classes NAME:WEIGHT,... / --levels L,L,...: %s' % e)
    if not a.level_list or any(not 1 <= lv <= 5000 for lv in a.level_list):
        sys.exit('--levels: levels 1..5000')
    if a.classes and a.cmd != 'cleanup' and not a.server_data:
        sys.exit('--classes needs --server-data SERVER_DIR (its vocations.xml, spells.xml and chaos_poi.lua)')
    if not 0.1 <= a.power <= 10:
        sys.exit('--power 0.1..10')
    if a.pull:
        m = re.match(r'^(\d+),(\d+(?:\.\d+)?)$', a.pull)
        if not m or int(m.group(1)) < 1:
            sys.exit('--pull STEPS,SECONDS (STEPS 1 or more)')
        a.pull = (int(m.group(1)), float(m.group(2)))
    key = a.client_key or os.environ.get('CHAOS_CLIENT_KEY', '')
    if a.dev_key:
        a.guard_key = GUARD_DEV_KEY
    elif key:
        if not re.match(r'^[0-9a-fA-F]{64}$', key.strip()):
            sys.exit('--client-key / CHAOS_CLIENT_KEY must be 64 hex digits')
        a.guard_key = bytes.fromhex(key.strip())
    else:
        a.guard_key = None
    a.client_id = (GUARD_TAG << 16 | a.client_build) if a.guard_key else VERSION
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
