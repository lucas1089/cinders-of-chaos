#!/usr/bin/env python3
"""Tests of install_apothecary.py: the NPC's files, a dry run, idempotence, a changed file; and that the later steps that
rewrite every NPC shop (the rune prices, the Everfull potions, the item price table) leave her list sound.

Run: python3 -I server/tools/install_apothecary_test.py (standard library only)."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_apothecary as I  # noqa: E402
import install_item_prices as IP  # noqa: E402
import install_potions as POT  # noqa: E402
import install_rune_supply as RS  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL: ' + what)


name = I.npc_name()
check(name == 'Veyra the Apothecary', 'the NPC of the config: %s' % name)
files = I.npc_files(name)
check([rel for _, rel in files] == ['Veyra the Apothecary.xml', os.path.join('scripts', 'veyra_the_apothecary.lua')],
      'the XML and the script it names: %s' % files)

root = tempfile.mkdtemp(prefix='install_apothecary_test_')
try:
    data = os.path.join(root, 'data')
    os.makedirs(os.path.join(data, 'npc'))
    run = lambda *a: subprocess.run([sys.executable, '-I', os.path.join(HERE, 'install_apothecary.py'), *a],
                                    capture_output=True, text=True)
    r = run(data, '--dry-run')
    check(r.returncode == 0 and 'dry run' in r.stdout, 'dry run succeeds')
    check(not os.path.exists(os.path.join(data, 'npc', name + '.xml')), 'a dry run writes nothing')
    r = run(data)
    check(r.returncode == 0 and r.stdout.count('copied') == 2, 'first run copies the XML and the script: ' + r.stdout)
    r = run(data)
    check(r.returncode == 0 and 'copied' not in r.stdout and r.stdout.count('up to date') == 2, 'second run changes nothing')
    path = os.path.join(data, 'npc', name + '.xml')
    open(path, 'a').write('<!-- edited -->\n')
    r = run(data)
    check(r.stdout.count('copied') == 1 and 'edited' not in open(path).read(), 'a changed file is written again, nothing else')
    check(run(os.path.join(root, 'nothing')).returncode == 1, 'a folder without npc/ is refused')
finally:
    shutil.rmtree(root, ignore_errors=True)

# the later steps on the real XML: the rune prices stay, no Everfull is sold (O273), and the
# item price table changes none of her asking prices (every one is at least twice what an NPC pays)
text = open(os.path.join(I.REPO_NPC, name + '.xml'), encoding='utf-8').read()
rcfg = RS.load_config()
prices = {r['id']: r['price'] for r in rcfg['runes']}
out, n = RS.reprice_xml(text, prices)
check(n == 0 and out == text, 'the rune installer finds every rune at the supply price (changed %d)' % n)

pcfg = POT.read_config()
out, info = POT.patch_npc_xml(text, pcfg)
check(info['ever'] == 0, 'the potion installer finds no Everfull in her trade: %s' % info)
out2, info2 = POT.patch_npc_xml(out, pcfg)
check(info2['ever'] == 0 and out2 == out, 'and changes nothing twice')

ip_prices, share = IP.load_prices()
stats = {'sell': 0, 'buy': 0}
out = IP.patch_xml(text, ip_prices, share, stats)
check(stats['buy'] == 0, 'the item price table raises none of her asking prices (%d)' % stats['buy'])
check(stats['sell'] == 0, 'and she already pays the table price for flasks (%d)' % stats['sell'])
check(out == text, 'the XML is byte for byte the same')

print('install_apothecary_test: %d failure(s)' % failed)
sys.exit(1 if failed else 0)
