#!/usr/bin/env python3
"""Tests of patch_monster_corpses.py and guard for engine src-patch 0089 (the loot bag instead of monster bodies,
server/README.md "Loot bag instead of corpses", O435): python3 -I server/tools/patch_monster_corpses_test.py

Part 1, the items.xml step on a synthetic file: the bag entry gets its name, slots, decayTo 0 and duration from the
config, keeps corpseType and other attributes, no other item changes, a second run changes nothing, a file without the
item or without a container is refused, and the real corpse_config.lua parses.
Part 1b (O565), the look in items.otb on a synthetic file: the node of the bag gets the client id `look` of the config and
nothing else changes (group, flags, server id, the other attributes, every other node, the file length), the animation flag
is dropped, a second run changes nothing, a file without the node is refused, the real config's look is a plain pouch of
the current pair (client 19202, not the stock dark lump), the written files are parsed again, a dry run writes nothing,
items.otb.bak keeps the original, --check says so.
Part 2, the patch: only Monster::getLookCorpse asks the bag table (src/monster.h); player.h / player.cpp and
creature.cpp are not in the patch, so a player's body never changes; the Lua function is registered and declared; the
header is a clean new file; the patch says it applies after 0088.
A fake patch that touches Player::getLookCorpse is caught (self-test)."""
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_monster_corpses as P

PATCH = os.path.join(HERE, '..', 'src-patches', '0089-monster-loot-bag.patch')
CONFIG = os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'corpse_config.lua')

fails = 0


def check(cond, label):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + label)


SAMPLE = '''<items>
	<item id="6067" article="a" name="dead rat">
		<attribute key="containerSize" value="8" />
		<attribute key="decayTo" value="6070" />
		<attribute key="duration" value="10" />
		<attribute key="corpseType" value="blood" />
	</item>
	<item id="6068" name="demon dust">
		<attribute key="containerSize" value="24" />
		<attribute key="decayTo" value="5527" />
		<attribute key="duration" value="10" />
		<attribute key="corpseType" value="undead" />
		<attribute key="description" value="Kept." />
	</item>
	<item id="6069" article="a" name="dead carrion worm">
		<attribute key="containerSize" value="10" />
		<attribute key="decayTo" value="5540" />
		<attribute key="duration" value="10" />
		<attribute key="corpseType" value="blood" />
	</item>
</items>
'''
CONF = {'bagId': 6068, 'name': 'sack of loot', 'article': 'a', 'slots': 60, 'seconds': 180}

# ---- part 1
new, changed = P.patch_text(SAMPLE, CONF)
check(changed, 'the stock entry is changed')
m = re.search(r'<item id="6068"([^>]*)>(.*?)</item>', new, re.S)
check(m is not None, 'the entry is still there')
head, body = m.group(1), m.group(2)
check('name="sack of loot"' in head and 'article="a"' in head and 'demon dust' not in new, 'name and article')
check('key="containerSize" value="60"' in body, 'slots')
check('key="decayTo" value="0"' in body and 'value="5527"' not in body, 'decays to nothing (no remains)')
check('key="duration" value="180"' in body, 'duration')
check('key="corpseType" value="undead"' in body, 'corpseType stays: it still counts as a corpse')
check('key="description" value="Kept."' in body, 'other attributes stay')
check(new.count('<item id="6067"') == 1 and SAMPLE.split('<item id="6068"')[0] == new.split('<item id="6068"')[0],
      'items before it are untouched')
check(SAMPLE.split('</item>', 2)[2] == new.split('</item>', 2)[2], 'items after it are untouched')
again, changed2 = P.patch_text(new, CONF)
check(not changed2 and again == new, 'idempotent')

for bad, why in ((SAMPLE.replace('id="6068"', 'id="6099"'), 'no item'),
                 (SAMPLE.replace('<attribute key="corpseType" value="undead" />', ''), 'no corpse type'),
                 (SAMPLE.replace('<attribute key="containerSize" value="24" />', ''), 'no container')):
    try:
        P.patch_text(bad, CONF)
        check(False, 'refused: ' + why)
    except ValueError:
        pass

# an entry that lacks decayTo and duration (a bag that never decayed) gets both
bare = '<items>\n\t<item id="6068" name="x">\n\t\t<attribute key="containerSize" value="24" />\n\t\t<attribute key="corpseType" value="blood" />\n\t</item>\n</items>\n'
out, ch = P.patch_text(bare, CONF)
check('key="decayTo" value="0"' in out and 'key="duration" value="180"' in out, 'missing decayTo and duration are added')
check(P.patch_text(out, CONF)[1] is False, 'idempotent after adding')

conf = P.read_config(open(CONFIG, encoding='utf-8').read())
check(conf['bagId'] == 6068 and conf['slots'] >= 60 and 30 <= conf['seconds'] <= 300 and conf['name'], 'the real config parses: %r' % conf)


# ---- part 1b: items.otb
from install_gems import escape, attr, scan, START, END, A_SERVERID, A_CLIENTID, FLAG_ANIMATION  # noqa: E402


def item_node(sid, cid, flags=0, group=0, extra=()):
    body = struct.pack('<I', flags) + attr(A_SERVERID, struct.pack('<H', sid)) + attr(A_CLIENTID, struct.pack('<H', cid))
    for k, v in extra:
        body += attr(k, v)
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def otb(nodes):
    root = bytes([START, 0]) + escape(struct.pack('<I', 0))
    return b'\x00\x00\x00\x00' + root + b''.join(nodes) + bytes([END])


LOOK = 19202
CONF2 = dict(CONF, look=LOOK)
HASH = (32, bytes(range(16)))
NODES = [item_node(2160, 3031), item_node(6067, 6067, flags=1 << 26, group=2), item_node(6068, 6068, flags=(1 << 26) | FLAG_ANIMATION, group=2, extra=(HASH,)),
         item_node(6069, 6069, flags=1 << 26, group=2)]
RAW = otb(NODES)
new_otb, ch = P.patch_otb(RAW, CONF2)
check(ch and len(new_otb) == len(RAW), 'otb: the bag node is rewritten, the file keeps its length')
kids = scan(new_otb)[0]
old = {k[2]: k for k in scan(RAW)[0]}
byk = {k[2]: k for k in kids}
check(byk[6068][3] == LOOK, 'otb: the bag draws the look')
check(byk[6068][4] == 2 and byk[6068][5] == (1 << 26) and byk[6068][2] == 6068, 'otb: group and server id stay, flags stay without the animation flag')
check([a for a in byk[6068][6] if a[0] == 32] == [HASH], 'otb: the other attributes of the node stay')
for sid in (2160, 6067, 6069):
    check(new_otb[byk[sid][0]:byk[sid][1]] == RAW[old[sid][0]:old[sid][1]], 'otb: node %d untouched' % sid)
check(P.patch_otb(new_otb, CONF2) == (new_otb, False), 'otb: idempotent')
check(P.verify_otb(new_otb, CONF2) == 4, 'otb: verified')
try:
    P.verify_otb(RAW, CONF2)
    check(False, 'otb: an unpatched file does not verify')
except AssertionError:
    pass
try:
    P.patch_otb(otb([item_node(2160, 3031)]), CONF2)
    check(False, 'otb: a file without the bag node is refused')
except ValueError:
    pass
# a client id that needs escaping (0xFD / 0xFE / 0xFF bytes) round-trips
conf3 = dict(CONF, look=0x00FD)
o3, _c = P.patch_otb(RAW, conf3)
check({k[2]: k for k in scan(o3)[0]}[6068][3] == 0x00FD and P.patch_otb(o3, conf3)[1] is False, 'otb: a look id with an escape byte round-trips')

import tempfile, shutil  # noqa: E402
d = tempfile.mkdtemp()
try:
    os.makedirs(os.path.join(d, 'items'))
    xmlp, otbp = os.path.join(d, 'items', 'items.xml'), os.path.join(d, 'items', 'items.otb')
    open(xmlp, 'w', encoding='latin-1', newline='').write(SAMPLE)
    open(otbp, 'wb').write(RAW)
    cfgp = os.path.join(d, 'corpse_config.lua')
    open(cfgp, 'w').write('return {\n\tbagId = 6068,\n\tlook = %d,\n\tname = "sack of loot",\n\tarticle = "a",\n\tslots = 60,\n\tseconds = 180,\n}\n' % LOOK)
    import io, contextlib
    def run(*extra):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = P.main([d, '--config', cfgp] + list(extra))
        return rc, buf.getvalue()
    rc, out = run('--check')
    check(rc == 1 and 'differs' in out, 'main: --check on an old install says it differs')
    rc, out = run('--dry-run')
    check(rc == 0 and open(otbp, 'rb').read() == RAW and not os.path.exists(otbp + '.bak') and open(xmlp, encoding='latin-1').read() == SAMPLE
          and '(changed) (dry run)' in out, 'main: a dry run writes nothing')
    rc, out = run()
    check(rc == 0 and open(otbp, 'rb').read() == new_otb, 'main: the otb is written')
    check(os.path.exists(otbp + '.bak') and open(otbp + '.bak', 'rb').read() == RAW, 'main: items.otb.bak keeps the original')
    rc, out = run()
    check(rc == 0 and 'already set' in out and '(changed)' not in out, 'main: a second run changes nothing: ' + out)
    check(open(otbp + '.bak', 'rb').read() == RAW, 'main: the .bak is written once')
    rc, out = run('--check')
    check(rc == 0 and 'matches' in out, 'main: --check on a patched install matches')
    os.unlink(otbp)
    rc, out = run()
    check(rc == 1 and 'items.otb' in out, 'main: no items.otb is refused')
finally:
    shutil.rmtree(d)

conf = P.read_config(open(CONFIG, encoding='utf-8').read())
check(conf['look'] == 19202, 'the real config: the look is client 19202 (a plain leather pouch of the current pair, not the stock lump 6068)')
check(conf['look'] != conf['bagId'], 'the look is not the stock id of the bag')

# ---- part 2
def files_of(text):
    """{path: [added and context lines]} of a patch"""
    out, cur = {}, None
    for line in text.split('\n'):
        mm = re.match(r'\+\+\+ b/(\S+)', line)
        if mm:
            cur = mm.group(1)
            out[cur] = []
        elif cur and line[:1] in ('+', ' ') and not line.startswith('+++'):
            out[cur].append(line)
        elif line.startswith('diff '):
            cur = None
    return out


def hunks_ok(text):
    """every hunk's line counts match its header (so `patch` takes it)"""
    lines = text.split('\n')
    i = 0
    while i < len(lines):
        mm = re.match(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@', lines[i])
        if mm:
            old = int(mm.group(2) if mm.group(2) is not None else 1)
            new = int(mm.group(4) if mm.group(4) is not None else 1)
            i += 1
            while (old > 0 or new > 0) and i < len(lines):
                c = lines[i][:1]
                if c == ' ':
                    old -= 1
                    new -= 1
                elif c == '-':
                    old -= 1
                elif c == '+':
                    new -= 1
                elif lines[i] == '':
                    old -= 1
                    new -= 1
                i += 1
            if old != 0 or new != 0:
                return False
            continue
        i += 1
    return True


def guard(text):
    """list of problems of a patch text"""
    bad = []
    f = files_of(text)
    if set(f) != {'src/monster.h', 'src/luascript.cpp', 'src/luascript.h', 'src/chaoslootbag.h'}:
        bad.append('files: %s' % sorted(f))
    for path in f:
        if path.startswith('src/player') or path == 'src/creature.cpp' or path == 'src/creature.h':
            bad.append('touches %s: a player body could change' % path)
    mh = '\n'.join(f.get('src/monster.h', []))
    if 'ChaosLootBag::corpseOf(ChaosLootBag::current(), mType->info.lookcorpse)' not in mh:
        bad.append('Monster::getLookCorpse does not ask the bag table')
    asks = [p for p, ls in f.items() if p != 'src/chaoslootbag.h' and any('corpseOf(' in l for l in ls)]
    if asks != ['src/monster.h']:
        bad.append('corpseOf called outside monster.h: %s' % asks)
    if 'registerMethod("Game", "setMonsterLootBag"' not in '\n'.join(f.get('src/luascript.cpp', [])):
        bad.append('Game.setMonsterLootBag not registered')
    if 'luaGameSetMonsterLootBag' not in '\n'.join(f.get('src/luascript.h', [])):
        bad.append('Game.setMonsterLootBag not declared')
    if 'after 0001-0088' not in text:
        bad.append('does not say it applies after 0001-0088')
    if not hunks_ok(text):
        bad.append('a hunk does not match its header')
    return bad


text = open(PATCH, encoding='utf-8').read()
for p in guard(text):
    check(False, 'patch 0089: ' + p)

fake = text.replace('diff --git a/src/luascript.h b/src/luascript.h',
                    'diff --git a/src/player.cpp b/src/player.cpp\n--- a/src/player.cpp\n+++ b/src/player.cpp\n@@ -1,1 +1,1 @@\n-x\n+corpseOf(y)\n'
                    'diff --git a/src/luascript.h b/src/luascript.h', 1)
check(any('player' in p for p in guard(fake)), 'self-test: a patch that touches player.cpp is caught')
fake2 = text.replace('ChaosLootBag::corpseOf(ChaosLootBag::current(), mType->info.lookcorpse)', 'mType->info.lookcorpse')
check(guard(fake2), 'self-test: a patch whose Monster::getLookCorpse does not ask the table is caught')

# stock skinning off: the marked line after onUse, after the professions hook, idempotent, CRLF kept, Lua still parses
import shutil, subprocess, tempfile
import install_professions as IP
SKIN = 'local skins = {}\r\nfunction onUse(player, item, fromPosition, target, toPosition, isHotkey)\r\n\tlocal skin = skins[target.itemid]\r\n\treturn skin ~= nil\r\nend\r\n'
new, ch = P.patch_skinning(SKIN)
check(ch and new.count(P.SKIN_MARK) == 1, 'skinning: marked line added once')
check(new.splitlines()[2].startswith('\tdo return false end'), 'skinning: right after the onUse line')
check('\r\n' + P.SKIN_LINE + '\r\n' in new and '\n' not in new.replace('\r\n', ''), 'skinning: CRLF kept')
check(P.patch_skinning(new) == (new, False), 'skinning: second run changes nothing')
hooked, _ = IP.patch_hook(SKIN.replace('\r\n', '\n'), 'tool')
both, _ = P.patch_skinning(hooked)
ls = both.splitlines()
check(IP.MARK in ls[2] and P.SKIN_MARK in ls[3], 'skinning: after the professions hook (professions first)')
late, _ = IP.patch_hook(P.patch_skinning(SKIN.replace('\r\n', '\n'))[0], 'tool')
ls = late.splitlines()
check(IP.MARK in ls[2] and P.SKIN_MARK in ls[3], 'skinning: professions run later still puts its hook first')
try:
    P.patch_skinning('local x = 1\n')
    check(False, 'skinning: no onUse raises')
except ValueError:
    pass
for lua in ('luajit', 'lua5.3'):
    if shutil.which(lua):
        with tempfile.NamedTemporaryFile('w', suffix='.lua', delete=False) as f:
            f.write(both + 'assert(onUse(nil, nil, nil, {itemid = 1}, nil) == false)\n')
        r = subprocess.run([lua, f.name], capture_output=True, text=True,
                           env={'PATH': os.environ.get('PATH', '')})
        os.unlink(f.name)
        check(r.returncode == 0, 'skinning: %s runs the patched script (%s)' % (lua, r.stderr.strip()))
d = tempfile.mkdtemp()
try:
    os.makedirs(os.path.join(d, 'actions', 'scripts', 'tools'))
    open(os.path.join(d, 'actions', 'actions.xml'), 'w').write('<actions>\n\t<action itemid="5908" script="tools/skinning.lua" />\n</actions>\n')
    sp = os.path.join(d, 'actions', 'scripts', 'tools', 'skinning.lua')
    open(sp, 'wb').write(SKIN.encode())
    check('(changed)' in P.skinning_off(d, True) and open(sp, 'rb').read() == SKIN.encode(), 'skinning: dry run writes nothing')
    check('(changed)' in P.skinning_off(d, False) and P.SKIN_MARK.encode() in open(sp, 'rb').read(), 'skinning: written')
    check('(already off)' in P.skinning_off(d, False), 'skinning: second run reports already off')
    check('nothing to do' in P.skinning_off(tempfile.gettempdir() + '/no_such_dir_x', False), 'skinning: no actions.xml is fine')
finally:
    shutil.rmtree(d)

if fails:
    sys.exit('%d check(s) failed' % fails)
print('patch_monster_corpses_test: ok')
