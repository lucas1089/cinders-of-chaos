#!/usr/bin/env python3
"""Test of apply_monster_looks.py for the pair 30 families: python3 -I tools/apply_monster_looks_test.py (from server/).

Works on temp copies: pack30_picks.csv (gallery rows, plus one row turned into a `hunt` row) and a temp monster folder.
A hunt row of a sheet look keeps head/body/legs/feet (addons go), a hunt row of another lib loses all five, the gallery
and sheetlook rows belong to no monster file (no "no monster file" problem), a monster file using one of them is
not reported by the family check, and a second run changes nothing.
"""
import csv, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
TOOL = os.path.join(HERE, 'apply_monster_looks.py')
PACK = os.path.join(REPO, 'client', 'tools', 'sprites', 'monster_looks', 'pack30_picks.csv')
HEAD = 'key,look,lib,lib_id,recolour,family,rank,monsters,description,edit\n'


def xml(name, look):
    return ('<monster name="%s"><look type="%d" head="1" body="2" legs="3" feet="4" addons="3" corpse="6068"/></monster>'
            % (name, look))


def run(d, picks, *extra):
    r = subprocess.run([sys.executable, '-I', TOOL, d, '--picks', picks, *extra], capture_output=True, text=True)
    return r.returncode, r.stdout


def main():
    rows = list(csv.DictReader(open(PACK, newline='')))
    assert rows and all(r['family'] == 'gallery' for r in rows), 'pack30_picks.csv: gallery rows expected'
    sheet = rows[0]
    with tempfile.TemporaryDirectory() as t:
        picks = os.path.join(t, 'picks.csv')
        hunt = dict(sheet, family='hunt', rank='hunt', monsters='Test Sheet Beast')
        other = {'key': 'other_look', 'look': '2999', 'lib': 'owner', 'lib_id': 'x', 'recolour': '', 'family': 'hunt',
                 'rank': 'hunt', 'monsters': 'Test Plain Beast', 'description': 'd', 'edit': 'e'}
        with open(picks, 'w', newline='') as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()), lineterminator='\n')
            w.writeheader()
            w.writerows(rows[1:] + [hunt, other])
            w.writerow(dict(sheet, key='sheet_only', family='sheetlook', look='2998'))
        d = os.path.join(t, 'monsters')
        os.makedirs(d)
        open(os.path.join(d, 'a.xml'), 'w').write(xml('Test Sheet Beast', 1))
        open(os.path.join(d, 'b.xml'), 'w').write(xml('Test Plain Beast', 1))
        code, out = run(d, picks, '--check')
        assert code == 1 and 'would update' in out, out
        code, out = run(d, picks)
        assert code == 0 and '0 problems' in out, out
        a = open(os.path.join(d, 'a.xml')).read()
        b = open(os.path.join(d, 'b.xml')).read()
        assert 'type="%s" head="1" body="2" legs="3" feet="4"' % sheet['look'] in a and 'addons' not in a, a
        assert 'type="2999"' in b and 'head' not in b and 'feet' not in b, b
        code, out = run(d, picks, '--check')
        assert code == 0 and '0 to update' in out, out
        # gallery rows belong to no monster file: a file using one is reported
        open(os.path.join(d, 'c.xml'), 'w').write(xml('Unrelated', int(rows[1]['look'])))
        code, out = run(d, picks, '--check')
        assert code == 1 and 'uses the rift / faction / exclusive look' in out, out
    print('apply_monster_looks_test: OK')


if __name__ == '__main__':
    main()
