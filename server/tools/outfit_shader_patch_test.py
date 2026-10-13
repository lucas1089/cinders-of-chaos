#!/usr/bin/env python3
"""Guard for engine src-patch 0036: outfit shaders can be owned.

Player::addShader keeps a character's shaders as bits in the reserved storage keys PSTRG_SHADERS_RANGE, 31 shaders per
key in 10 keys (shaders.xml ids 1-310; the key after them holds the worn one). The base Player::addStorageValue
accepted only the mount, wing and aura ranges of the reserved block and dropped the shader keys, so hasShader was
false for every shader, the outfit window packet listed none and a set-outfit request with a shader was refused
(server/README.md "Chaos outfit shaders", ROADMAP 86). This test reads the patch chain in order and checks that the
last patch that writes that line of src/player.cpp accepts SHADERS_RANGE next to the others, and that every shader the
server hands out (store offers, exclusives, the Chaos outfit shaders) has an id the range can hold.

Run: python3 -I server/tools/outfit_shader_patch_test.py (standard library only)."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'src-patches')
CHAOS = os.path.join(HERE, '..', 'data', 'scripts', 'chaos')
RANGE_KEYS, BITS = 10, 31  # PSTRG_SHADERS_RANGE_SIZE, bits per key in Player::addShader / hasShader


def allow_line(text):
    """the new text of the reserved-range allow line of Player::addStorageValue in a patch (src/player.cpp), or None"""
    inside, found = False, None
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.startswith('+++ '):
            inside = line[4:].split()[0].endswith('src/player.cpp')
            continue
        if not inside or line.startswith('-') or not line[:1] in ('+', ' '):
            continue
        if 'IS_IN_KEYRANGE(key, MOUNTS_RANGE)' in line:
            body = line[1:]
            j = i + 1
            while not body.rstrip().endswith('{') and j < len(lines) and lines[j][:1] in ('+', ' '):
                body += ' ' + lines[j][1:].strip()
                j += 1
            found = body
    return found


def shader_ids():
    """(where, id) of every shader the server scripts hand out"""
    out = []
    shop = open(os.path.join(CHAOS, 'shop_config.lua'), encoding='utf-8').read()
    out += [('store', int(i)) for i in re.findall(r'\{kind = "shader", id = (\d+)', shop)]
    out += [('store part', int(i)) for i in re.findall(r'"shader:(\d+)"', shop)]
    ex = open(os.path.join(CHAOS, 'exclusives_config.lua'), encoding='utf-8').read()
    out += [('exclusive', int(i)) for i in re.findall(r'kind = "shader", id = (\d+)', ex)]
    cos = open(os.path.join(CHAOS, 'cosmetics_config.lua'), encoding='utf-8').read()
    out += [('chaos shader', int(i)) for i in re.findall(r'shaderId = (\d+)', cos)]
    return out


def main():
    bad = 0
    last = None
    for name in sorted(os.listdir(PATCHES)):
        if name.endswith('.patch'):
            line = allow_line(open(os.path.join(PATCHES, name), encoding='utf-8', errors='replace').read())
            if line is not None:
                last = (name, line)
    if not last:
        print('no patch writes the reserved-range line of Player::addStorageValue'); bad += 1
    else:
        name, line = last
        for r in ('MOUNTS_RANGE', 'WINGS_RANGE', 'AURAS_RANGE', 'SHADERS_RANGE'):
            if 'IS_IN_KEYRANGE(key, %s)' % r not in line:
                print('%s: Player::addStorageValue does not accept %s' % (name, r)); bad += 1
    # the fake chain: a line without the shader range is caught
    if 'SHADERS_RANGE' in (allow_line('+++ b/src/player.cpp\n+\t\t} else if (IS_IN_KEYRANGE(key, MOUNTS_RANGE) || '
                                      'IS_IN_KEYRANGE(key, WINGS_RANGE)) {\n') or ''):
        print('self-test: a line without SHADERS_RANGE passed'); bad += 1
    ids = shader_ids()
    if len(ids) < 20:
        print('only %d shader ids read from the configs' % len(ids)); bad += 1
    for where, i in ids:
        if not 1 <= i <= RANGE_KEYS * BITS:
            print('%s shader id %d does not fit the engine shader storage (1..%d)' % (where, i, RANGE_KEYS * BITS)); bad += 1
    print('outfit shader patch test:', 'OK (%d shader ids, %s)' % (len(ids), last[0] if last else '-') if not bad
          else '%d problem(s)' % bad)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
