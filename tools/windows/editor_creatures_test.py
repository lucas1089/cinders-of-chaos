#!/usr/bin/env python3
"""Tests of editor_creatures.py on synthetic files: python3 -I tools/windows/editor_creatures_test.py"""
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import editor_creatures as ec  # noqa: E402

failures = 0


def check(cond, what):
    global failures
    if not cond:
        failures += 1
        print('FAIL', what)


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    (root / 'm' / 'sub').mkdir(parents=True)
    (root / 'm' / 'a.xml').write_text(
        '<monster name="Ash Wolf"><look type="27" head="1" body="2" legs="3" feet="4" addons="2"/></monster>')
    (root / 'm' / 'sub' / 'b.xml').write_text(
        '<monster name="Cinder Chest"><look typeex="1740"/></monster>')
    (root / 'm' / 'dup.xml').write_text('<monster name="ash wolf"><look type="99"/></monster>')
    (root / 'm' / 'bad.xml').write_text('<monster name="Broken"')
    (root / 'm' / 'nolook.xml').write_text('<monster name="Blind"/>')
    (root / 'm' / 'other.xml').write_text('<items><item id="1"/></items>')
    (root / 'n').mkdir()
    (root / 'n' / 'v.xml').write_text('<npc name="Vendor"><look type="128" head="95"/></npc>')

    found = ec.creatures([str(root / 'm'), str(root / 'n')])
    check(sorted(found) == ['ash wolf', 'cinder chest', 'vendor'], f'names {sorted(found)}')
    check(found['ash wolf']['looktype'] == '27', 'first file of a name wins (a.xml before dup.xml)')
    check(found['cinder chest'].get('lookitem') == '1740' and found['cinder chest']['looktype'] == '0', 'typeex')
    check(found['vendor']['type'] == 'npc', 'npc type')

    out = root / 'out' / 'deep' / 'creatures.xml'
    cmd = [sys.executable, '-I', str(HERE / 'editor_creatures.py'), str(out), str(root / 'm'), str(root / 'n')]
    r = subprocess.run(cmd, capture_output=True, text=True)
    check(r.returncode == 0, f'run: {r.stderr}')
    first = out.read_bytes()
    tree = ET.fromstring(first)
    check(tree.tag == 'creatures' and len(tree) == 3, 'output is a <creatures> list of 3')
    check(tree[0].get('name') == 'Ash Wolf' and tree[0].get('lookaddon') == '2', 'attributes kept')
    subprocess.run(cmd, capture_output=True, text=True)
    check(out.read_bytes() == first, 'running again gives the same bytes')
    r = subprocess.run([sys.executable, '-I', str(HERE / 'editor_creatures.py'), str(root / 'x.xml'), str(root / 'empty')],
                       capture_output=True, text=True)
    check(r.returncode == 1 and not (root / 'x.xml').exists(), 'no creature: error, no file')

print('FAILED' if failures else 'ok editor_creatures_test', failures or '')
sys.exit(1 if failures else 0)
