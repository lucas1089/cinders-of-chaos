#!/usr/bin/env python3
"""Tests of loadtest.py: why a bot did not enter the game, the grouped report lines, the bots' password hashes, the
spread over temples and hunting areas.

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

# ---------------------------------------------------------------- --spread: temples and hunting areas of chaos_poi.lua
POI = """return {
	marks = {
		{k = "temple", x = 100, y = 200, z = 7, n = "Temple of A", r = 0},
		{k = "depot", x = 1, y = 2, z = 7, n = "Depot", r = 0},
		{k = "temple", x = 300, y = 400, z = 6, n = "Temple of B", r = 0},
		{k = "hunt", x = 1000, y = 2000, z = 8, n = "Hunting: Rat (level 1-10)", r = 1},
		{k = "hunt", x = 3000, y = 4000, z = 9, n = "Hunting: Wolf (level 10-20)", r = 1},
		{k = "hunt", x = 5000, y = 6000, z = 10, n = "Hunting: Bear (level 20-30)", r = 1},
	},
}"""
marks = lt.poi_marks(POI)
eq(len(marks), 5, 'temples and hunts only')
eq(marks[0], ('temple', 100, 200, 7), 'first mark')
eq([m[1] for m in lt.poi_marks(POI, 15) if m[0] == 'hunt'], [1000, 3000], 'areas above the level left out')
eq(len(lt.poi_marks(POI, 0)), 5, '0: every area')
pos = lt.spread_positions(marks, 9, 1 / 3.0)
eq(len(pos), 9, 'one position per bot')
eq(pos, lt.spread_positions(marks, 9, 1 / 3.0), 'deterministic')
for i, (x, y, z) in enumerate(pos[:3]):
    t = [(100, 200, 7), (300, 400, 6)][i % 2]
    eq(z == t[2] and abs(x - t[0]) <= 5 and abs(y - t[1]) <= 5, True, 'bot %d round its temple' % i)
for i, (x, y, z) in enumerate(pos[3:]):
    h = [(1000, 2000, 8), (3000, 4000, 9), (5000, 6000, 10)][i % 3]
    eq(z == h[2] and abs(x - h[0]) <= 3 and abs(y - h[1]) <= 3, True, 'bot %d in its hunting area' % (i + 3))
eq(all(p[2] in (8, 9, 10) for p in lt.spread_positions(marks, 4, 0)), True, 'town share 0: all hunting')
try:
    lt.spread_positions([('temple', 1, 1, 7)], 3, 0.5)
    eq('no error', 'ValueError', 'no hunting marks')
except ValueError:
    eq(True, True, 'no hunting marks')
eq(lt.parse(['setup', '--health', '60000']).health, 60000, '--health')
eq(lt.parse(['run', '--hunt']).hunt, True, '--hunt')
eq(lt.parse(['run']).hunt, False, 'no --hunt')

# ---------------------------------------------------------------- storms and spam (server/README.md "Stress test")
a = lt.parse(['run', '--reconnect', '5,25', '--drop', '0.3', '--abort', '0.15', '--pm', '4', '--party', '9'])
eq(a.reconnect, (5.0, 25.0), '--reconnect MIN,MAX')
eq((a.drop, a.abort, a.pm, a.party), (0.3, 0.15, 4.0, 9.0), 'chances and intervals')
eq(lt.parse(['run']).reconnect, '', 'one session by default')
for bad in (['--reconnect', '9,2'], ['--reconnect', 'x'], ['--drop', '2'], ['--abort', '-1']):
    try:
        lt.parse(['run'] + bad)
        eq('accepted', 'refused', 'bad option %r' % (bad,))
    except SystemExit:
        eq(True, True, 'bad option %r refused' % (bad,))
import json as _json
import tempfile as _tempfile
with _tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as f:
    _json.dump([[60, {'action': 'transfer', 'data': ['gold', '{other}', 7]}], [109, '{"action":"fetch"}']], f)
ops = lt.load_opcodes(f.name)
eq(ops[0], (60, '{"action":"transfer","data":["gold","{other}",7]}'), 'an object payload is sent as compact JSON')
eq(ops[1], (109, '{"action":"fetch"}'), 'a string payload as it is')
a = lt.parse(['run', '--count', '3', '--opcodes', f.name, '--opcode-every', '0.5'])
eq((len(a.opcode_list), a.opcode_every), (2, 0.5), '--opcodes and --opcode-every')
bot = lt.Bot(1, a, lt.OT_RSA_N, {})
for _ in range(20):
    eq(bot.fill('{other}') in (lt.bot_name(0), lt.bot_name(2)), True, '{other}: another bot of the run, never itself')
eq(bot.fill('{name}'), lt.bot_name(1), '{name}: the bot itself')
eq(bot.fill('{online}'), lt.bot_name(1), '{online} with nobody else in game: the bot itself')
with open(f.name, 'w') as g:
    _json.dump([[300, 'x']], g)
try:
    lt.load_opcodes(f.name)
    eq('accepted', 'refused', 'opcode over 255')
except SystemExit:
    eq(True, True, 'opcode over 255 refused')
os.unlink(f.name)

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

# ---------------------------------------------------------------- classes, levels and spell rotations (--classes)
VOCS = """<vocations>
	<!-- <vocation id="99" name="Old" gainhp="1"> -->
	<vocation id="5" clientid="13" name="Elementalist" description="an elementalist" gaincap="10" gainhp="5" gainmana="30">
	</vocation>
	<vocation id="14" clientid="21" name="Berserker" gainhp="14" gainmana="6">
	</vocation>
</vocations>"""
v = lt.parse_vocations(VOCS)
eq(v, {'Elementalist': {'id': 5, 'hp': 5, 'mana': 30}, 'Berserker': {'id': 14, 'hp': 14, 'mana': 6}}, 'vocations, comments skipped')

SPELLS = """<spells>
	<!-- <instant group="attack" name="Gone" words="gone" level="1" /> -->
	<instant group="attack" name="Big Ring" words="drai ring" level="200" mana="900" cooldown="20000" groupcooldown="2000" script="a.lua">
		<vocation name="Elementalist" />
	</instant>
	<instant group="attack" name="Fan" words="drai fan" level="50" mana="200" cooldown="4000" groupcooldown="2000" script="b.lua">
		<vocation name="Elementalist" />
		<vocation name="Mystic" />
	</instant>
	<instant group="attack" name="Bolt" words="kah bolt" level="10" mana="20" needtarget="1" cooldown="2000" script="c.lua">
		<vocation name="Elementalist" />
	</instant>
	<instant group="attack" name="Learned" words="kah learn" level="10" needlearn="1" script="d.lua">
		<vocation name="Elementalist" />
	</instant>
	<instant group="attack" name="Snare" words="drai snar" level="10" script="e.lua">
		<vocation name="Elementalist" />
	</instant>
	<instant group="support" name="Rage" words="vyr sang khar" level="120" mana="200" cooldown="30000" script="f.lua">
		<vocation name="Berserker" />
	</instant>
	<instant group="healing" name="Heal" words="heal" level="1" script="g.lua">
		<vocation name="Elementalist" />
	</instant>
	<instant name="Edit Door" words="aleta grav" level="1" script="h.lua" />
	<instant group="attack" name="Cleave" words="kah cleave" level="1" script="i.lua" />
</spells>"""
sp = lt.parse_spells(SPELLS)
eq([s['words'] for s in sp], ['drai ring', 'drai fan', 'kah bolt', 'kah learn', 'drai snar', 'vyr sang khar', 'heal',
                              'aleta grav', 'kah cleave'], 'every instant, comments skipped, self-closing ones too')
eq((sp[0]['level'], sp[0]['mana'], sp[0]['cooldown'], sp[0]['groupcooldown'], sp[0]['vocations']),
   (200, 900, 20000, 2000, {'Elementalist'}), 'level, mana, cooldowns, vocations')
eq((sp[2]['needtarget'], sp[3]['needlearn'], sp[7]['group'], sp[8]['vocations']), (True, True, '', set()),
   'needtarget, needlearn, no group, no vocation list')
MODEL = 'words,name,dmg,t5,flags,source\ndrai ring,Big Ring,1,5,,a\ndrai fan,Fan,1,4,,b\nkah bolt,Bolt,1,1,,c\n' \
        'drai snar,Snare,1,5,utility,e\nbad,Bad,1,x,,z\n'
model = lt.parse_rotation_model(MODEL)
eq(model['drai fan'], (4.0, ''), 'targets of 5 and flags')
eq('bad' in model, False, 'a row without a number is skipped')
eq([s['words'] for s in lt.rotation_for(sp, model, 'Elementalist', 300)], ['drai ring', 'drai fan', 'kah bolt', 'kah cleave'],
   'area first; no learned, utility, healing or house spell; a spell without a vocation list is everyone\'s')
eq([s['words'] for s in lt.rotation_for(sp, model, 'Elementalist', 100)], ['drai fan', 'kah bolt', 'kah cleave'],
   'a spell above the level left out')
eq([s['words'] for s in lt.rotation_for(sp, model, 'Berserker', 300)], ['vyr sang khar', 'kah cleave'],
   'the class support spell (rage) first, other vocations\' spells left out')
eq(lt.rotation_for(sp, model, 'Berserker', 300)[0]['group'], 'support', 'the rage is a support cast')

rot = lt.rotation_for(sp, model, 'Elementalist', 300)
ready = {}
eq(lt.next_spell(rot, ready, 0)['words'], 'drai ring', 'the biggest area spell first')
ready.update({'drai ring': 20.1, 'attack': 2.1})
eq(lt.next_spell(rot, ready, 1), None, 'the attack group cooldown holds every attack spell')
eq(lt.next_spell(rot, ready, 2.2)['words'], 'drai fan', 'then the next area spell whose cooldown is over')
eq(lt.next_spell(rot, {}, 0, attack=False), None, 'a lure casts no attack spell')
brot = lt.rotation_for(sp, model, 'Berserker', 300)
eq(lt.next_spell(brot, {'attack': 9}, 0, attack=False)['words'], 'vyr sang khar', 'a lure still casts the rage')

eq(lt.parse_weights('Elementalist:3, Berserker:1,Thief'), [('Elementalist', 3), ('Berserker', 1), ('Thief', 1)], 'weights')
for bad in ('A:0', 'A:x', 'A:-2'):
    try:
        lt.parse_weights(bad)
        eq('accepted', 'refused', 'bad weight %r' % bad)
    except ValueError:
        eq(True, True, 'bad weight %r refused' % bad)
classes = [('E', 2), ('B', 1)]
plan = [lt.assign(i, classes, [100, 300]) for i in range(12)]
eq(plan[:6], [('E', 100), ('E', 100), ('B', 100), ('E', 300), ('E', 300), ('B', 300)], 'class by weight, then the next level')
eq(sum(1 for c, _ in plan if c == 'E'), 8, 'weights kept')
eq(sorted(set(plan)), [('B', 100), ('B', 300), ('E', 100), ('E', 300)], 'every class at every level')
eq(lt.exp_for_level(100), 15694800, 'experience of level 100 (the engine formula)')
eq(lt.exp_for_level(1), 0, 'level 1: 0')
hp, mana, ml, skill = lt.class_stats('Elementalist', 300, {'hp': 5, 'mana': 30})
eq((hp, mana), (185 + 292 * 5, 90 + 292 * 30), 'health and mana per level')
eq(ml > 60 and skill == 20, True, 'a caster: magic level, no weapon skill')
hp, mana, ml, skill = lt.class_stats('Berserker', 1000, {'hp': 14, 'mana': 6})
eq(ml <= 60 and 100 <= skill <= 130, True, 'a fighter: weapon skill')
eq(lt.class_stats('Elementalist', 1000, {})[2] > lt.class_stats('Elementalist', 100, {})[2], True, 'magic level grows')
eq(lt.class_stats('Elementalist', 300, {}, 2.0)[2], 2 * lt.class_stats('Elementalist', 300, {})[2], '--power: magic level')
eq(lt.class_stats('Berserker', 300, {}, 1.5)[3], int(lt.class_stats('Berserker', 300, {})[3] * 1.5), '--power: skill')
eq(lt.parse(['setup', '--power', '1.6']).power, 1.6, '--power')

POI2 = POI.replace('(level 20-30)', '(level 500-900)').replace('Hunting: Rat (level 1-10)', 'Hunting: Rat (level 60-100)') \
    .replace('\t},', '\t\t{k = "hunt", x = 7000, y = 7000, z = 7, n = "Hunting: Nameless", r = 1},\n\t},')
hunts = lt.hunt_marks(POI2)
eq([h[:2] for h in hunts], [(60, 100), (10, 20), (500, 900)], 'hunts with a level band only')
eq([h[:2] for h in lt.hunts_for_level(hunts, 100)], [(60, 100)], 'level 100: a band starting at 50-100')
eq([h[:2] for h in lt.hunts_for_level(hunts, 1000)], [(500, 900)], 'level 1000: 500+')
eq([h[:2] for h in lt.hunts_for_level(hunts, 300)], [(60, 100)], 'nothing in 150-300: the highest band under it')
eq([h[:2] for h in lt.hunts_for_level(hunts, 5)], [(10, 20)], 'nothing under: the lowest bands')
temples = [(100, 200, 7)]
lp = lt.level_positions(hunts, temples, [100, 1000, 100, 1000], 0.25)
eq(lp, lt.level_positions(hunts, temples, [100, 1000, 100, 1000], 0.25), 'deterministic')
eq(abs(lp[3][0] - 100) <= 5 and lp[3][2] == 7, True, 'the town share at the temples, spread over the bots')
eq(abs(lp[0][0] - 1000) <= 3 and lp[0][2] == 8, True, 'the first bot hunts')
eq(sum(1 for i in range(100) if lt.level_positions(hunts, temples, [100] * 100, 0.1)[i][2] == 7), 10, '10% in town')
eq(abs(lp[1][0] - 5000) <= 3 and lp[1][2] == 10, True, 'a level 1000 bot in the 500+ hunt')
eq(abs(lp[2][0] - 1000) <= 3 and lp[2][2] == 8, True, 'a level 100 bot in the 60-100 hunt')

PLACES = '''return { places = {
	{id = "a", name = "A", level = {480, 640}, teleport = {x = 1, y = 1, z = 6}, arrival = {x = 1000, y = 1000, z = 8}},
	{id = "b", name = "B", level = {1000, 1120}, teleport = {x = 2, y = 1, z = 6}, arrival = {x = 1200, y = 1000, z = 9}},
}}'''
SPAWNS = ''.join('<spawn centerx="%d" centery="%d" centerz="%d" radius="2">\n' % p for p in
                 [(1010, 1000, 8), (1020, 1005, 9), (1090, 1000, 8), (1110, 1000, 9), (1180, 990, 10), (1000, 1300, 8),
                  (1000, 1000, 12)] + [(1000 + i, 990, 8) for i in range(30)])
pm = lt.place_marks(PLACES, SPAWNS, per_place=5)
eq(len([p for p in pm if p[:2] == (480, 640)]), 5, 'at most per_place points a place')
eq([p[2:] for p in pm if p[:2] == (1000, 1120)], [(1110, 1000, 9), (1180, 990, 10)], 'the nearest arrival wins, a floor off')
eq(all(p[2:] != (1000, 1300, 8) and p[2:] != (1000, 1000, 12) for p in pm), True, 'too far or too deep: left out')
eq(lt.place_marks('return {}', SPAWNS), [], 'no places')
idx = lt.spawn_index(SPAWNS)
eq(lt.snap_to_spawn((1012, 1003, 8), idx), (1010, 1000, 8), 'snapped to the nearest spawn centre on the floor')
eq(lt.snap_to_spawn((1000, 1290, 8), idx), (1000, 1300, 8), 'across a cell border')
eq(lt.snap_to_spawn((1012, 1003, 7), idx), (1012, 1003, 7), 'none on the floor: unchanged')
eq(lt.snap_to_spawn((1500, 1500, 8), idx), (1500, 1500, 8), 'none within reach: unchanged')

a = lt.parse(['run', '--classes', 'Elementalist:3,Berserker', '--levels', '100,600', '--server-data', '/x', '--pull', '5,8'])
eq((a.class_weights, a.level_list, a.pull), ([('Elementalist', 3), ('Berserker', 1)], [100, 600], (5, 8.0)),
   '--classes, --levels, --pull')
eq(lt.class_plan(a)[:4], [('Elementalist', 100)] * 3 + [('Berserker', 100)], 'the plan of setup and run')
eq(lt.class_plan(lt.parse(['run'])), None, 'no --classes: the old bots')
eq(lt.parse(['cleanup', '--classes', 'A']).classes, 'A', 'cleanup needs no server data')
for bad in (['--classes', 'A'], ['--classes', 'A:0', '--server-data', '/x'], ['--levels', '0'], ['--levels', ''],
            ['--pull', '0,5'], ['--pull', '5'], ['--power', '0']):
    try:
        lt.parse(['run'] + bad)
        eq('accepted', 'refused', 'bad option %r' % (bad,))
    except SystemExit:
        eq(True, True, 'bad option %r refused' % (bad,))

# ---------------------------------------------------------------- per-thread CPU and the probe's p95
rows = [{'per_thread': {'tfs/1': 50.0, 'disp/2': 80.0}}, {'per_thread': {'tfs/1': 10.0, 'disp/2': 60.0}}]
eq([t[0] for t in lt.thread_summary(rows)], ['disp/2', 'tfs/1'], 'the busiest thread first')
eq(lt.thread_summary(rows)[0][1], 70.0, 'its average')
with _tempfile.NamedTemporaryFile('w', suffix='.log', delete=False) as f:
    f.write('[loadtest-probe] t=100 players=5 lag_avg_ms=51.2 lag_max_ms=90 samples=80\n'
            '[loadtest-probe] t=105 players=5 lag_avg_ms=52.0 lag_max_ms=120 samples=80 lag_p95_ms=70 monsters=9 npcs=1\n'
            '[loadtest-probe] t=999 players=5 lag_avg_ms=52.0 lag_max_ms=120 samples=80\n')
eq(lt.probe_lines(f.name, 100, 200), [(100, 5, 51.2, 90, None), (105, 5, 52.0, 120, 70)], 'probe lines, p95 when printed')
os.unlink(f.name)

for f in FAILS:
    print('FAIL ' + f)
print('loadtest_test: %d checks, %d failures' % (CHECKS[0], len(FAILS)))
sys.exit(1 if FAILS else 0)
