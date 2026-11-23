#!/usr/bin/env python3
"""Guard for engine src-patch 0094: missile (distance effect) ids above 255 (O737).

The patch makes the missile id 16 bits in the engine (ShootType_t, CombatParams::distanceEffect, Game::addDistanceEffect, the overrides of
0045, Player / ProtocolGame::sendDistanceShoot) and writes it to the wire by the client: u16 to a client that asked in its login ("W"
block) and was told feature 77, one byte to any other client (an id above 255 as its Lua fallback or not at all). This test reads the
patch text and checks that
  * it is the only patch numbered 0094 and no later patch removes what it adds; it touches the files the design names and adds
    src/chaoswidemissile.h (no config key, nothing saved),
  * no one-byte missile type is left in the lines it writes (addDistanceEffect, sendDistanceShoot, setMissileOverride, the Lua binding),
  * the RSA block end is taken before RSA_decrypt, the "W" block is read only inside it and only after the capability byte of 0051,
  * feature 77 is announced only to a client that asked, inside the chaosClient block of sendFeatures,
  * sendDistanceShoot asks chaoswidemissile.h decide, returns before writing on DROP and writes u16 only on WORD,
  * Game.setMissileFallback is registered next to the 0045 methods, the cast hello gets flag 4,
  * every hunk has as many leading as trailing context lines (patch --fuzz=0 on a real tree).
It then rebuilds a source tree from the context lines of every hunk (the base tree is not in the repository) and applies the patch to it with
patch -p1 --fuzz=0; with SRC_TREE=<source root with patches 0001-0093 applied> it also runs patch --fuzz=0 --dry-run on the real tree
(server/README.md "Missile ids above 255 (O737)").
Run: python3 -I server/tools/wide_missile_patch_test.py (standard library only; patch(1) is optional, the apply step is skipped without it)."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'src-patches')
NAME = '0094-wide-missile-ids.patch'
fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


def eq(a, b, what):
    check(a == b, '%s: %r != %r' % (what, a, b))


files = sorted(f for f in os.listdir(PATCHES) if f.endswith('.patch'))
eq([f for f in files if f.startswith('0094-')], [NAME], 'one patch numbered 0094')
text = open(os.path.join(PATCHES, NAME), encoding='utf-8').read()
body = text[text.index('diff --git'):]
touched = re.findall(r'^diff --git a/(\S+) b/\S+', body, re.M)
eq(touched, ['src/const.h', 'src/combat.h', 'src/combat.cpp', 'src/game.h', 'src/game.cpp', 'src/player.h', 'src/protocolgame.h',
             'src/protocolgame.cpp', 'src/chaoscast.h', 'src/luascript.h', 'src/luascript.cpp', 'src/tools.cpp', 'src/chaoswidemissile.h'],
   'the files the patch touches')
check(body.count('new file mode') == 1, 'chaoswidemissile.h is the only new file')

for f in files:
    if f > NAME:
        gone = [l for l in open(os.path.join(PATCHES, f), encoding='utf-8').read().splitlines()
                if l.startswith('-') and not l.startswith('---')]
        check(not any('patch 0094' in l or 'ChaosWideMissile' in l or 'chaosWideMissiles' in l for l in gone),
              'no later patch removes what 0094 adds: ' + f)

added = [l[1:] for l in body.splitlines() if l.startswith('+') and not l.startswith('+++')]
code = '\n'.join(added)
check(not re.search(r'g_config|ConfigManager', code), 'no config key (a client that asks gets the feature)')
check(not re.search(r'DBInsert|DBResult|IOLoginData|saveStorage', code), 'nothing is saved')
check(not re.search(r'(addDistanceEffect|sendDistanceShoot|setMissileOverride)\([^)]*(uint8_t|unsigned char)', code),
      'no one-byte missile type is left in a signature the patch writes')
check('enum ShootType_t : uint16_t {' in code, 'ShootType_t is 16 bits')
check('uint16_t distanceEffect = CONST_ANI_NONE;' in code, 'CombatParams::distanceEffect is 16 bits')
check('params.distanceEffect = static_cast<uint16_t>(value);' in code, 'COMBAT_PARAM_DISTANCEEFFECT keeps 16 bits')


def part(path):
    start = body.index('diff --git a/' + path + ' ')
    nxt = body.find('\ndiff --git ', start + 1)
    return body[start:nxt + 1 if nxt >= 0 else len(body)]


game = part('src/game.cpp')
check('std::map<uint16_t, ChaosFxOverride> chaosMissileOverrides;' in game, 'the 0045 missile overrides are keyed by the 16-bit id')
check('-std::map<uint8_t, ChaosFxOverride> chaosMissileOverrides;' in game, 'the one-byte key goes')
check('+\t\teffect = it->second.effect;' in game, 'the override is sent whole, not cut to a byte')
check('ChaosWideMissile::Fallbacks chaosMissileFallbacks;' in game, 'the fallback table lives in game.cpp')
check('return chaosMissileFallbacks.set(id, fallback);' in game, 'setMissileFallback checks through the header')

proto = part('src/protocolgame.cpp')
i_end = proto.find('const size_t chaosRsaEnd = static_cast<size_t>(msg.getBufferPosition()) + 128;')
i_rsa = proto.find('if (!Protocol::RSA_decrypt(msg)) {')
check(0 <= i_end < i_rsa, 'the end of the RSA block is taken right before RSA_decrypt')
i_caps = proto.find('chaosWideSpellIdsAsked = (capabilities & CHAOS_CAPABILITY_WIDE_SPELL_IDS) != 0;')
i_fit = proto.find('if (ChaosWideMissile::markerFits(msg.getBufferPosition(), chaosRsaEnd)) {')
check(0 <= i_caps < i_fit, 'the "W" block is read after the capability byte, only when it fits the block')
check('if (length == 1) {' in proto and 'chaosWideMissilesAsked = ChaosWideMissile::markerAsks(length, letter, msg.getByte());' in proto,
      'only the exact marker asks')
feat = proto[proto.find('chaosImpactText = true;'):]
check('+\t\tif (chaosWideMissilesAsked) {\n+\t\t\tfeatures[GameDistanceEffectU16] = true;\n+\t\t\tchaosWideMissiles = true;\n+\t\t}' in feat,
      'feature 77 only to a client that asked, and the flag with it')
send = proto[proto.find('void ProtocolGame::sendDistanceShoot'):]
send = send[:send.find('void ProtocolGame::sendMagicEffect')]
check('ChaosWideMissile::decide(type, chaosWideMissiles, fallback);' in send, 'sendDistanceShoot asks decide')
i_drop = send.find('if (send.wire == ChaosWideMissile::Wire::DROP) {')
i_msg = send.find('NetworkMessage msg;')
check(0 <= i_drop < i_msg, 'a dropped missile returns before anything is written')
check('msg.add<uint16_t>(send.id);' in send and 'msg.addByte(static_cast<uint8_t>(send.id));' in send, 'u16 on WORD, a byte otherwise')
check('-\tmsg.addByte(type);' in send, 'the old one-byte write goes')
check('(type > 0xFF && !chaosWideMissiles) ? Game::getMissileFallback(type) : 0' in send, 'the table is asked only for an id above 255 to a one-byte client')
check('flags |= ChaosCast::HELLO_WIDE_MISSILES;' in proto, 'the cast hello says the missile width')
check('static constexpr uint8_t HELLO_WIDE_MISSILES = 4;' in part('src/chaoscast.h'), 'cast flag 4')

lua = part('src/luascript.cpp')
check('+\tregisterMethod("Game", "setMissileFallback", LuaScriptInterface::luaGameSetMissileFallback);' in lua and
      ' \tregisterMethod("Game", "clearEffectOverrides"' in lua, 'Game.setMissileFallback registered after the 0045 methods')
check('uint16_t stock = getNumber<uint16_t>(L, 1);' in lua and 'uint16_t missile = isNumber(L, 2) ? getNumber<uint16_t>(L, 2) : 0;' in lua,
      'Game.setMissileEffect takes 16-bit ids')
check('static int luaGameSetMissileFallback(lua_State* L);' in part('src/luascript.h'), 'declared in luascript.h')
check('return static_cast<ShootType_t>(ChaosWideMissile::parseId(strValue.c_str()));' in part('src/tools.cpp'),
      'getShootType takes a number for a missile with no name')
check('void sendDistanceShoot(const Position& from, const Position& to, uint16_t type) const {' in part('src/player.h'), 'Player::sendDistanceShoot')

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

header = body[body.index('diff --git a/src/chaoswidemissile.h'):]
hdr_lines = [l[1:] for l in header.splitlines() if l.startswith('+') and not l.startswith('+++')]
count_line = re.search(r'^@@ -0,0 \+1,(\d+) @@', header, re.M)
check(count_line is not None and int(count_line.group(1)) == len(hdr_lines), 'the new file hunk count is right')
hdr = '\n'.join(hdr_lines)
for want in ("static constexpr char MARKER = 'W';", 'static constexpr uint8_t CAPABILITY_MISSILE_U16 = 1 << 0;',
             'static constexpr uint8_t FEATURE_DISTANCE_EFFECT_U16 = 77;', 'static constexpr uint16_t FIRST_WIDE = 256;',
             '#include <cstdint>', '#include <map>'):
    check(want in hdr, 'header: ' + want)
check('#include "' not in hdr, 'the header includes no engine header (pure)')
check('chaoswidemissile.h' in open(os.path.join(HERE, 'chaoswidemissile_test.cpp'), encoding='utf-8').read(),
      'the C++ test includes the header cut out of the patch')

patch = shutil.which('patch')
if patch:
    tmp = tempfile.mkdtemp()
    try:
        for blk in re.split(r'(?m)^(?=diff --git )', body):
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
        check(os.path.exists(os.path.join(tmp, 'src', 'chaoswidemissile.h')), 'the header file is created')
        if r.returncode == 0:
            for path, want in (('src/const.h', 'ShootType_t : uint16_t'), ('src/protocolgame.cpp', 'chaosWideMissilesAsked'),
                               ('src/luascript.h', 'luaGameSetMissileFallback')):
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
print('wide missile patch tests: ok')
