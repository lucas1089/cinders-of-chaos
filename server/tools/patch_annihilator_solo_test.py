#!/usr/bin/env python3
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_annihilator_solo as P

BASE = os.environ.get('CHAOS_BASE_DATA', '')  # a base server data folder; the real-file checks are skipped when unset
fails = 0
def ok(c, m):
    global fails
    if not c:
        fails += 1
        print('FAIL', m)

synthetic = 'local config = {}\nfunction onUse(player, item)\n\tif item.itemid == 1946 then\n\t\tlocal storePlayers, playerTile = {}\n\n' + P.OLD_LOOP + '\n' + P.OLD_DEMONS + '\tend\nend\n'
new, ch = P.patch(synthetic)
ok(len(ch) == 2 and P.MARKER in new, 'patched')
ok('You need 4 players' not in new and 'math.min(#config.demonPositions, #storePlayers * 2)' in new, 'content')
again, ch2 = P.patch(new)
ok(again == new and ch2 == [], 'idempotent')
_, ch3 = P.patch('function onUse() end')
ok(ch3 and ch3[0].startswith('REFUSED'), 'refused on unknown code')

d = tempfile.mkdtemp()
try:
    path = os.path.join(d, P.LEVER)
    os.makedirs(os.path.dirname(path))
    open(path, 'w', newline='').write(synthetic.replace('\n', '\r\n'))
    ok(P.main([d, '--dry-run']) == 0 and P.MARKER not in open(path).read(), 'dry run writes nothing')
    ok(P.main([d]) == 0 and P.MARKER in open(path).read(), 'writes')
    ok('\r\n' in open(path, newline='').read(), 'CRLF kept')
    ok(P.main([d]) == 0, 'second run')
    ok(P.main([os.path.join(d, 'none')]) == 0, 'missing file skipped')
finally:
    shutil.rmtree(d)
real = os.path.join(BASE, P.LEVER)
if os.path.isfile(real):
    _, chr_ = P.patch(open(real, newline='').read().replace('\r\n', '\n'))
    ok(len(chr_) == 2, 'applies to the real base lever')
print('patch_annihilator_solo_test: %s' % ('all checks passed' if not fails else '%d FAILED' % fails))
sys.exit(1 if fails else 0)
