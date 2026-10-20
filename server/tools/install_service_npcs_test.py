#!/usr/bin/env python3
"""Tests of install_service_npcs.py: the five NPCs of the config, their files, a dry run, idempotence, a changed file.

Run: python3 -I server/tools/install_service_npcs_test.py (standard library only)."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_service_npcs as I  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL: ' + what)


npcs = I.read_npcs()
check([n for n, _ in npcs] == ['Tavish Coldhand', 'Vessa Hollowmark', 'Cassian Auric', 'Halvard Deedkeeper', 'Pell Ashmere'],
      'the five NPCs in the owner order: %s' % npcs)
for name, script in npcs:
    xml = open(os.path.join(I.REPO_NPC, name + '.xml'), encoding='utf-8').read()
    check('walkinterval="0"' in xml, name + ': never walks (a booth)')
    check('script="%s"' % script in xml, name + ': its XML names ' + script)
    body = open(os.path.join(I.REPO_NPC, 'scripts', script), encoding='utf-8').read()
    check('SERVICE_KEY = "' in body and 'chaos_service_npc.lua' in body, name + ': runs the shared dialogue')

root = tempfile.mkdtemp(prefix='install_service_npcs_test_')
try:
    data = os.path.join(root, 'data')
    os.makedirs(os.path.join(data, 'npc'))
    run = lambda *a: subprocess.run([sys.executable, '-I', os.path.join(HERE, 'install_service_npcs.py'), *a],
                                    capture_output=True, text=True)
    r = run(data, '--dry-run')
    check(r.returncode == 0 and 'dry run' in r.stdout, 'dry run succeeds')
    check(not os.path.exists(os.path.join(data, 'npc', 'Pell Ashmere.xml')), 'a dry run writes nothing')
    r = run(data)
    check(r.returncode == 0 and r.stdout.count('copied') == 11, 'first run copies 5 XML, 5 scripts, the shared dialogue: ' + r.stdout)
    check(os.path.isfile(os.path.join(data, 'npc', 'scripts', 'chaos_service_npc.lua')), 'the shared dialogue is there')
    r = run(data)
    check(r.returncode == 0 and 'copied' not in r.stdout and r.stdout.count('up to date') == 11, 'second run changes nothing')
    path = os.path.join(data, 'npc', 'Cassian Auric.xml')
    open(path, 'a').write('<!-- edited -->\n')
    r = run(data)
    check(r.stdout.count('copied') == 1 and 'edited' not in open(path).read(), 'a changed file is written again, nothing else')
    check(run(os.path.join(root, 'nothing')).returncode == 1, 'a folder without npc/ is refused')
finally:
    shutil.rmtree(root, ignore_errors=True)

print('install_service_npcs_test: %d failure(s)' % failed)
sys.exit(1 if failed else 0)
