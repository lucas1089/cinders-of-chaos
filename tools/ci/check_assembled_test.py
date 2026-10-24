#!/usr/bin/env python3
"""python3 -I tools/ci/check_assembled_test.py: check_assembled.py on small fake trees (ours only passes; the base helper
next to ours, in place of ours, or a clash of any other name fails)."""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_assembled as C  # noqa: E402

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        print('FAIL', what)
        fails += 1


OURS = 'Module\n  name: game_helper\n  scripts: [ helper ]\n'
BASE = 'Module\n  name: game_helper\n  scripts: [ helper, scripting ]\n'


def tree(root, files):
    for path, text in files.items():
        p = os.path.join(root, path)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, 'w', encoding='utf-8').write(text)


with tempfile.TemporaryDirectory() as tmp:
    overlay = os.path.join(tmp, 'overlay.otmod')
    open(overlay, 'w', encoding='utf-8').write(OURS)

    def run(name, files):
        root = os.path.join(tmp, name)
        tree(root, files)
        return C.check(root, overlay)

    ok(run('good', {'modules/game_helper/game_helper.otmod': OURS, 'mods/game_x/x.otmod': 'Module\n  name: game_x\n'}) == [],
       'ours alone passes')
    e = run('both', {'modules/game_helper/game_helper.otmod': OURS, 'mods/game_helper/helper.otmod': BASE})
    ok(any('defined 2 times' in x for x in e) and any('still in the tree' in x for x in e), 'the base helper next to ours fails')
    ok(run('stub', {'modules/game_helper/game_helper.otmod': OURS,
                    'mods/game_helper/helper.otmod': C.RETIRED_STUB}) == [], 'the retired stub passes')
    ok(run('stubplus', {'modules/game_helper/game_helper.otmod': OURS,
                        'mods/game_helper/helper.otmod': C.RETIRED_STUB,
                        'mods/game_helper/helper.lua': '--'}) != [], 'the stub with base files next to it fails')
    ok(run('base', {'mods/game_helper/helper.otmod': BASE}) != [], 'the base helper alone fails')
    ok(run('none', {'modules/game_x/x.otmod': 'Module\n  name: game_x\n'}) != [], 'no helper fails')
    ok(any('not the overlay' in x for x in run('other', {'modules/game_helper/game_helper.otmod': BASE})),
       'another otmod in the helper folder fails')
    ok(any('defined 2 times' in x for x in run('clash', {
        'modules/game_helper/game_helper.otmod': OURS, 'modules/a/a.otmod': 'Module\n  name: same\n',
        'mods/b/b.otmod': 'Module\n  name: same\n'})), 'any name clash fails')

ok(os.path.isfile(C.OVERLAY_OTMOD), 'overlay game_helper.otmod exists')
sys.exit(1 if fails else 0)
