#!/usr/bin/env python3
"""Guard for engine src-patch 0093: the bot signals the engine counts for the bot detection (O722).

The patch adds Player::getChaosBotSignals (a ChaosBotSignals::Signals of src/chaosbotsignals.h), four one-line hooks and the Lua method
player:getBotSignals(). This test reads the patch text and checks that
  * it is the only patch numbered 0093 and no later patch removes what it adds,
  * it only adds lines (no removed line of the engine), touches exactly game.cpp, luascript.cpp, luascript.h, player.h and player.cpp and adds
    chaosbotsignals.h (no config key, no SQL, no change to how a player walks or attacks),
  * the four hooks are the ones the design names, each a single call: Game::playerMove -> keyStep, Game::playerAutoWalk -> pathCommand with the
    command's length, Player::onCreatureMove -> seen for a monster that was out of view and is in it now, Game::playerSetAttackedCreature ->
    attacked for a NEW target that is a monster,
  * the Lua method is registered next to the fist attack methods, reads and resets, returns nil when there is nothing or the player is gone,
  * nothing is saved (no database or save code).
It then rebuilds a source tree from the context lines of every hunk (the base tree is not in the repository) and applies the patch to it with
patch -p1 --fuzz=0, so the format, the hunk counts and the order of the hunks are proven; with SRC_TREE=<source root with patches 0001-0092
applied> it also runs patch --fuzz=0 --dry-run on the real tree (server/README.md "Bot detection events and scores (O722)").
Run: python3 -I server/tools/botsignals_patch_test.py (standard library only; patch(1) is optional, the apply step is skipped without it)."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'src-patches')
NAME = '0093-bot-signals.patch'
fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


def eq(a, b, what):
    check(a == b, '%s: %r != %r' % (what, a, b))


files = sorted(f for f in os.listdir(PATCHES) if f.endswith('.patch'))
eq([f for f in files if f.startswith('0093-')], [NAME], 'one patch numbered 0093')
text = open(os.path.join(PATCHES, NAME), encoding='utf-8').read()
body = text[text.index('diff --git'):]
touched = re.findall(r'^diff --git a/(\S+) b/\S+', body, re.M)
eq(touched, ['src/game.cpp', 'src/luascript.cpp', 'src/luascript.h', 'src/player.h', 'src/player.cpp', 'src/chaosbotsignals.h'],
   'the files the patch touches')
check(body.count('new file mode') == 1, 'chaosbotsignals.h is the only new file')

for f in files:
    if f > NAME:
        gone = [l for l in open(os.path.join(PATCHES, f), encoding='utf-8').read().splitlines()
                if l.startswith('-') and not l.startswith('---')]
        check(not any('BotSignals' in l or 'patch 0093' in l for l in gone), 'no later patch removes what 0093 adds: ' + f)
    elif f != NAME:
        other = open(os.path.join(PATCHES, f), encoding='utf-8').read()
        check('chaosBotSignals' not in other and 'getBotSignals' not in other, f + ' does not touch the bot signals')

added = [l[1:] for l in body.splitlines() if l.startswith('+') and not l.startswith('+++')]
removed = [l[1:] for l in body.splitlines() if l.startswith('-') and not l.startswith('---')]
eq(removed, [], 'the patch removes no line of the engine (it only adds)')
code = '\n'.join(added)
check(not re.search(r'saveStorage|setStorageValue|DBInsert|DBResult|IOLoginData|db\.|SQL', code), 'nothing is saved or written to the database')
check(not re.search(r'g_config|ConfigManager', code), 'no config key')


def part(path, nxt):
    start = body.index('diff --git a/' + path)
    end = body.index('diff --git a/' + nxt) if nxt else len(body)
    return body[start:end]


game = part('src/game.cpp', 'src/luascript.cpp')
check('+\tplayer->getChaosBotSignals().keyStep(); // Chaos (src-patch 0093)\n \tplayer->startAutoWalk(direction);' in game,
      'a key step is counted in Game::playerMove, right before startAutoWalk(direction)')
check('+\tplayer->getChaosBotSignals().pathCommand(listDir.size()); // Chaos (src-patch 0093)\n \tplayer->startAutoWalk(listDir);' in game,
      'a path command is counted in Game::playerAutoWalk with its length')
check('+\tif (newTarget && attackCreature && attackCreature->getMonster()) {' in game and
      '+\t\tplayer->getChaosBotSignals().attacked(attackCreature->getID(), OTSYS_TIME());' in game,
      'an attack counts for a NEW target that is a monster')
eq(game.count('getChaosBotSignals()'), 3, 'three calls in game.cpp')
check('chaosKiteWalkOn(player));\n+\tplayer->getChaosBotSignals' in game, 'the key step hook sits after the kite walk line of patch 0028')
check('const bool newTarget = player->getAttackedCreature() != attackCreature;\n \tplayer->setAttackedCreature(attackCreature);\n+' in game,
      'the attack hook sits right after setAttackedCreature (patch 0066 context)')

pcpp = part('src/player.cpp', 'src/chaosbotsignals.h')
check('+\tif (creature != this && creature->getMonster() && !canSee(oldPos) && canSee(newPos)) {\n+\t\tchaosBotSignals.seen(creature->getID(), OTSYS_TIME());\n+\t}'
      in pcpp, 'seen: a monster that was out of view and is in it now')
check('+\n \tCreature::onCreatureMove(creature, newTile, newPos, oldTile, oldPos, teleport);' in pcpp, 'before the base call, which is not touched')
eq(pcpp.count('@@'), 2, 'one hunk in player.cpp')

lua_cpp = part('src/luascript.cpp', 'src/luascript.h')
check('registerMethod("Player", "getBotSignals", LuaScriptInterface::luaPlayerGetBotSignals);' in lua_cpp, 'getBotSignals is registered')
check('+\tregisterMethod("Player", "getBotSignals"' in lua_cpp and ' \tregisterMethod("Player", "getFistAttack"' in lua_cpp,
      'registered right after the fist attack methods of patch 0091')
check('player->getChaosBotSignals().drain()' in lua_cpp, 'it reads and resets with drain()')
check(lua_cpp.count('lua_pushnil(L);') == 2, 'a player that is gone and an empty drain both give nil')
for key in ('"keys"', '"paths"', '"pathSteps"', '"reactions"'):
    check(key in lua_cpp, 'the table has ' + key)
fn = lua_cpp[lua_cpp.index('+int LuaScriptInterface::luaPlayerGetBotSignals(lua_State* L)'):lua_cpp.index('+}\n', lua_cpp.index('+int LuaScriptInterface::luaPlayerGetBotSignals'))]
check(not re.search(r'\bstatic\b(?!_cast)', fn), 'no static state in the Lua function')

# every hunk has as many leading as trailing context lines: patch(1) takes a hunk with fewer trailing than leading lines as anchored at the end
# of the file (and one with fewer leading as anchored at the start), so an asymmetric hunk fails with --fuzz=0 on a real tree
for blk in re.split(r'(?m)^(?=diff --git )', body):
    if 'new file mode' in blk:
        continue
    for h in re.split(r'(?m)^(?=@@ )', blk)[1:]:
        kinds = [l[:1] for l in h.splitlines()[1:]]
        lead = 0
        while lead < len(kinds) and kinds[lead] == ' ':
            lead += 1
        trail = 0
        while trail < len(kinds) and kinds[len(kinds) - 1 - trail] == ' ':
            trail += 1
        check(lead == trail and lead >= 2, 'hunk %r has %d leading and %d trailing context lines' % (h.splitlines()[0][:40], lead, trail))
check('static int luaPlayerGetBotSignals(lua_State* L);' in part('src/luascript.h', 'src/player.h'), 'declared in luascript.h')

player_h = part('src/player.h', 'src/player.cpp')
check('#include "chaosbotsignals.h"' in player_h, 'player.h includes the header')
check('ChaosBotSignals::Signals chaosBotSignals; // Chaos (src-patch 0093)' in player_h, 'the member')
check('ChaosBotSignals::Signals& getChaosBotSignals() {' in player_h, 'the accessor')

# the header
header = body[body.index('diff --git a/src/chaosbotsignals.h'):]
for want in ('constexpr size_t SEEN_CAP = 64;', 'constexpr size_t REACTION_CAP = 32;', 'constexpr int64_t SEEN_MAX_AGE_MS = 30000;',
             'constexpr uint32_t MAX_PATH_STEPS = 4096;', '#include <cstdint>', '#include <vector>'):
    check(want in header, 'header: ' + want)
check(not re.search(r'#include "(?!chaos)', header) and '#include "' not in header, 'the header includes no engine header (pure)')
hdr_lines = [l[1:] for l in header.splitlines() if l.startswith('+') and not l.startswith('+++')]
shipped = open(os.path.join(HERE, 'chaosbotsignals_test.cpp'), encoding='utf-8').read()
check('chaosbotsignals.h' in shipped, 'the C++ test includes the header cut out of the patch')
count_line = re.search(r'^@@ -0,0 \+1,(\d+) @@', header, re.M)
check(count_line is not None and int(count_line.group(1)) == len(hdr_lines), 'the new file hunk count is right')

# the patch applied to a tree rebuilt from its own context
patch = shutil.which('patch')
if patch:
    tmp = tempfile.mkdtemp()
    try:
        blocks = re.split(r'(?m)^(?=diff --git )', body)
        for blk in blocks:
            m = re.match(r'diff --git a/(\S+) b/\S+', blk)
            if not m or 'new file mode' in blk:
                continue
            path = os.path.join(tmp, m.group(1))
            os.makedirs(os.path.dirname(path), exist_ok=True)
            out = []
            n = 0
            for h in re.split(r'(?m)^(?=@@ )', blk)[1:]:
                n += 1
                out.append('// filler before hunk %d' % n)
                out += [l[1:] for l in h.splitlines()[1:] if l[:1] in (' ', '-')]
                out.append('// filler after hunk %d' % n)
            with open(path, 'w', encoding='utf-8') as fh:
                fh.write('\n'.join(out) + '\n')
        r = subprocess.run([patch, '-p1', '--fuzz=0', '-i', os.path.join(PATCHES, NAME)], cwd=tmp, capture_output=True, text=True)
        check(r.returncode == 0, 'patch -p1 --fuzz=0 applies to a tree of its own context: ' + r.stdout + r.stderr)
        check(os.path.exists(os.path.join(tmp, 'src', 'chaosbotsignals.h')), 'the header file is created')
        if r.returncode == 0:
            for path, want in (('src/game.cpp', 'keyStep();'), ('src/player.cpp', 'chaosBotSignals.seen('), ('src/luascript.h', 'luaPlayerGetBotSignals')):
                check(want in open(os.path.join(tmp, path), encoding='utf-8').read(), 'applied: ' + want)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
src = os.environ.get('SRC_TREE')
if src:
    r = subprocess.run(['patch', '-p1', '--fuzz=0', '--dry-run', '-i', os.path.join(PATCHES, NAME)], cwd=src, capture_output=True, text=True)
    check(r.returncode == 0, 'patch --dry-run on SRC_TREE: ' + r.stdout + r.stderr)

if fails:
    print('%d failed' % fails)
    sys.exit(1)
print('bot signals patch tests: ok')
