#!/usr/bin/env python3
"""Tests of tools/patch_base_npcs.py step 5 (an NPC script name in another letter case than its file)."""
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import patch_base_npcs as P  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL: ' + what)


XML = '<?xml version="1.0"?>\n<npc name="Addoner" script="addoner.lua" walkinterval="2000">\n</npc>\n'
new, old = P.fix_script_case(XML, {'Addoner.lua', 'other.lua'})
check(old == 'addoner.lua' and 'script="Addoner.lua"' in new and new.replace('Addoner.lua', 'addoner.lua', 1) == XML,
      'the real file name: %s' % new)
check(P.fix_script_case(new, {'Addoner.lua'}) == (new, None), 'a name that matches is left alone')
check(P.fix_script_case(XML, {'x.lua'}) == (XML, None), 'no file of that name: left alone (the engine reports it)')
check(P.fix_script_case(XML, {'Addoner.lua', 'ADDONER.lua'}) == (XML, None), 'two candidates: left alone')
check(P.fix_script_case('<npc name="A">\n</npc>\n', {'a.lua'})[1] is None, 'no script attribute')

root = tempfile.mkdtemp(prefix='npcs_test_')
try:
    os.makedirs(os.path.join(root, 'scripts'))
    open(os.path.join(root, 'scripts', 'Addoner.lua'), 'w').write('-- x\n')
    open(os.path.join(root, 'Addoner.xml'), 'w').write(XML)
    P.patch_script_case(root, dry=True)
    check(open(os.path.join(root, 'Addoner.xml')).read() == XML, 'dry run writes nothing')
    P.patch_script_case(root, dry=False)
    once = open(os.path.join(root, 'Addoner.xml')).read()
    check('script="Addoner.lua"' in once, 'written')
    P.patch_script_case(root, dry=False)
    check(open(os.path.join(root, 'Addoner.xml')).read() == once, 'a second run changes nothing')
finally:
    shutil.rmtree(root, ignore_errors=True)

print('patch_base_npcs_test: %s' % ('ok' if not failed else '%d failed' % failed))
sys.exit(1 if failed else 0)
