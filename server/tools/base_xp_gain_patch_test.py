#!/usr/bin/env python3
"""Guard for engine src-patch 0096: the "XP gain rate" of the Skills window shows the rate the server applies (O774).

Seen in a client 2026-11-27: the line read 100% while the Chaos Pact (+10% experience) was active. The base engine
sent a fixed 100 as the base XP gain rate of the stats packet and had no Player:setBaseXpGain, so the guarded call of
xp_rate_display.lua never ran. The patch adds Player::baseXpGain and the Lua methods. This test reads the patch text
and checks that
  * it is the only patch numbered 0096 and touches src/luascript.cpp, src/luascript.h, src/player.h and
    src/protocolgame.cpp only,
  * the only removed line is the fixed 100 of the stats packet, which now sends player->getBaseXpGain(),
  * the field defaults to 100 (a script that never sets it shows the base's 100%),
  * both Lua methods are registered, the setter clamps to 1..65535 and resends the stats only on a change,
  * no later patch removes it,
  * it applies with patch -p1 --fuzz=0 to a tree rebuilt from its own context (SRC_TREE=DIR: a dry run on a real
    source tree with 0001-0095 applied).
It also runs the clamp rule on the values xp_rate_display.lua sends.
Run: python3 -I server/tools/base_xp_gain_patch_test.py (standard library; the apply step needs the patch tool)."""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'src-patches')
NAME = '0096-base-xp-gain.patch'
FILES = ['src/luascript.cpp', 'src/luascript.h', 'src/player.h', 'src/protocolgame.cpp']
STOCK = ['msg.add<uint16_t>(100); // base xp gain rate']


def hunks(text):
    """{file: [(old lines, new lines)]} from a unified diff"""
    out, cur, old, new = {}, None, None, None
    for line in text.splitlines():
        if line.startswith('+++ b/'):
            cur = line[6:].split()[0]
            out[cur] = []
            old = new = None
        elif line.startswith('@@'):
            old, new = [], []
            out[cur].append((old, new))
        elif old is not None and cur and not line.startswith('--- ') and not line.startswith('diff '):
            if line.startswith('-'):
                old.append(line[1:])
            elif line.startswith('+'):
                new.append(line[1:])
            elif line.startswith(' ') or line == '':
                old.append(line[1:])
                new.append(line[1:])
    return out


def clamp(value):
    """the setter's rule: 1..65535, a bad number is 1"""
    try:
        v = float(value)
    except (TypeError, ValueError):
        return 1
    if not v >= 1:
        return 1
    return int(min(v, 65535))


def main():
    failures = []

    def check(cond, label):
        if not cond:
            failures.append(label)
            print('FAIL ' + label)

    names = sorted(os.listdir(PATCHES))
    mine = [n for n in names if n.startswith('0096-')]
    check(mine == [NAME], 'one patch 0096: %s' % mine)
    if mine != [NAME]:
        return 1
    text = open(os.path.join(PATCHES, NAME), encoding='utf-8').read()
    files = [l[6:].split()[0] for l in text.splitlines() if l.startswith('+++ b/')]
    check(files == FILES, 'files: %s' % files)
    removed = [l[1:].strip() for l in text.splitlines() if l.startswith('-') and not l.startswith('---')]
    added = [l[1:] for l in text.splitlines() if l.startswith('+') and not l.startswith('+++')]
    code = [l.strip() for l in added if l.strip() and not l.strip().startswith('//')]
    check(removed == STOCK, 'removes only the fixed 100 of the stats packet: %r' % removed)
    check(any(l.startswith('msg.add<uint16_t>(player->getBaseXpGain());') for l in code), 'the stats send the field')
    check(any(l.startswith('uint16_t baseXpGain = 100;') for l in code), 'the field defaults to 100')
    for m in ('getBaseXpGain', 'setBaseXpGain'):
        check(any('registerMethod("Player", "%s"' % m in l for l in code), 'Lua method registered: ' + m)
    check(any('value > 65535' in l for l in code) and any('!(value >= 1)' in l for l in code), 'the setter clamps')
    h = hunks(text)
    setter = [l for _, new in h.get('src/luascript.cpp', []) for l in new]
    body = '\n'.join(setter)
    i_change = body.find('if (gain != player->getBaseXpGain())')
    i_send = body.find('player->sendStats();', i_change)
    check(i_change >= 0 and i_send > i_change, 'the stats are resent only when the value changed')
    check(text.count('patch 0096') >= 5, 'every change carries a patch 0096 comment')
    for n in names:
        if n > NAME:
            other = open(os.path.join(PATCHES, n), encoding='utf-8').read()
            gone = [l for l in other.splitlines() if l.startswith('-') and not l.startswith('---')]
            check(not any('BaseXpGain' in l or 'baseXpGain' in l for l in gone), 'no later patch removes it: ' + n)

    # apply on a tree rebuilt from the patch's own context (the base tree is not in the repository)
    if shutil.which('patch'):
        tmp = tempfile.mkdtemp(prefix='p0096_')
        try:
            for f, hs in h.items():
                path = os.path.join(tmp, f)
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, 'w', encoding='utf-8') as out:
                    for old, _ in hs:
                        out.write('// filler\n' * 40)
                        out.write('\n'.join(old) + '\n')
            r = subprocess.run(['patch', '-p1', '--fuzz=0', '-s', '-i', os.path.join(PATCHES, NAME)], cwd=tmp,
                               capture_output=True, text=True)
            check(r.returncode == 0, 'applies with --fuzz=0 to a tree rebuilt from its context: ' + r.stdout + r.stderr)
            if r.returncode == 0:
                pg = open(os.path.join(tmp, 'src/protocolgame.cpp'), encoding='utf-8').read()
                check('msg.add<uint16_t>(100); // base xp gain rate' not in pg, 'the fixed 100 is gone after the apply')
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        tree = os.environ.get('SRC_TREE')
        if tree:
            r = subprocess.run(['patch', '-p1', '--fuzz=0', '--dry-run', '-i', os.path.join(PATCHES, NAME)], cwd=tree,
                               capture_output=True, text=True)
            check(r.returncode == 0, 'dry run on SRC_TREE: ' + r.stdout + r.stderr)

    # the values xp_rate_display.lua sends: the Pact's 110, a stacked 287, nonsense
    check(clamp(110) == 110, 'Pact +10%: 110')
    check(clamp(287.6) == 287, 'a whole percent')
    check(clamp(0) == 1 and clamp(-5) == 1 and clamp('x') == 1 and clamp(float('nan')) == 1, 'bad numbers: 1')
    check(clamp(10 ** 9) == 65535, 'the uint16 ceiling')
    if failures:
        return 1
    print('base xp gain patch test OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
