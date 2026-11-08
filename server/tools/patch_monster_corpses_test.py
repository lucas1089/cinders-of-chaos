#!/usr/bin/env python3
"""Tests of patch_monster_corpses.py and guard for engine src-patch 0089 (the loot bag instead of monster bodies,
server/README.md "Loot bag instead of corpses", O435): python3 -I server/tools/patch_monster_corpses_test.py

Part 1, the items.xml step on a synthetic file: the bag entry gets its name, slots, decayTo 0 and duration from the
config, keeps corpseType and other attributes, no other item changes, a second run changes nothing, a file without the
item or without a container is refused, and the real corpse_config.lua parses.
Part 2, the patch: only Monster::getLookCorpse asks the bag table (src/monster.h); player.h / player.cpp and
creature.cpp are not in the patch, so a player's body never changes; the Lua function is registered and declared; the
header is a clean new file; the patch says it applies after 0088.
A fake patch that touches Player::getLookCorpse is caught (self-test)."""
import os
import re
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

if fails:
    sys.exit('%d check(s) failed' % fails)
print('patch_monster_corpses_test: ok')
