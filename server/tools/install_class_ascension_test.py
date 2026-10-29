#!/usr/bin/env python3
"""Test of install_class_ascension.py's NPC copy: every NPC of server/data/npc reaches DATA_DIR/npc (the hub NPCs of the
Chaos systems, among them Archivist Odrenna of the line spell quests), a second run changes nothing.
usage: python3 -I server/tools/install_class_ascension_test.py"""
import io, os, sys, tempfile, contextlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_class_ascension as T  # noqa: E402

fails = []


def check(ok, msg):
    if not ok:
        fails.append(msg)
        print('FAIL ' + msg)


with tempfile.TemporaryDirectory() as data:
    os.makedirs(os.path.join(data, 'npc'))
    with contextlib.redirect_stdout(io.StringIO()):
        dry = T.copy_npcs(data, True)
        check(not os.path.exists(os.path.join(data, 'npc', 'Archivist Odrenna.xml')), 'a dry run writes nothing')
        first = T.copy_npcs(data, False)
        second = T.copy_npcs(data, False)
    check(dry == first, 'the dry run lists what the run writes')
    for need in ('Archivist Odrenna.xml', 'Archivist Maelis.xml', 'Keeper of Trials.xml', 'Ascendant Oracle.xml',
                 os.path.join('scripts', 'archivist_odrenna.lua'), os.path.join('scripts', 'keeper_of_trials.lua')):
        check(need in first and os.path.isfile(os.path.join(data, 'npc', need)), need + ' is installed')
    check(second == [], 'a second run changes nothing: %s' % second)
    check('Ysolde' not in open(os.path.join(data, 'npc', 'Archivist Odrenna.xml'), encoding='utf-8').read().replace('Warden Ysolde', ''),
          'the old name is gone')
print('install_class_ascension_test: %s' % ('ok' if not fails else '%d failed' % len(fails)))
sys.exit(1 if fails else 0)
