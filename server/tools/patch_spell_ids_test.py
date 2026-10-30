#!/usr/bin/env python3
"""patch_spell_ids.py on a small spells.xml: renumbers, refuses a real clash, lets a Chaos spell hold a retired spell's id."""
import os, subprocess, sys, tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patch_spell_ids import NEW_IDS, CAP_RETIRED  # noqa: E402

TOOL = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'patch_spell_ids.py')


def run(xml):
    d = tempfile.mkdtemp()
    os.makedirs(os.path.join(d, 'spells', 'scripts'))
    path = os.path.join(d, 'spells', 'spells.xml')
    # every kept script of NEW_IDS must be there; old ids 300+ clash with nothing
    rest = ''.join('<instant spellid="%d" name="S%d" script="%s">\n' % (300 + i, i, s)
                   for i, s in enumerate(sorted(NEW_IDS)) if s not in CAP_RETIRED and s not in xml)
    open(path, 'w').write('<spells>\n' + rest + xml + '\n</spells>\n')
    r = subprocess.run([sys.executable, '-I', TOOL, d], capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr, open(path).read()


def main():
    beam = '<instant spellid="260" name="Grand Death Beam" script="attack/grand_death_beam.lua">'
    howl = '<instant spellid="35" name="Pack Howl" script="chaos/beastmaster/pack_howl.lua">'
    grenade = '<instant spellid="258" name="Divine Grenade" script="attack/divine_grenade.lua">'
    # retired by the cap: commented out, its id 35 is free for a Chaos spell
    code, out, text = run(grenade + '\n<!-- ' + beam + ' -->\n' + howl)
    assert code == 0, out
    assert 'spellid="34" name="Divine Grenade"' in text, text
    assert 'spellid="35" name="Pack Howl"' in text, text
    # the same spell still registered: a real clash, refused, file untouched
    code, out, text = run(grenade + '\n' + beam + '\n' + howl)
    assert code == 1 and 'spellid 35 is already used by chaos/beastmaster/pack_howl.lua' in out, out
    assert 'spellid="260"' in text and 'spellid="258"' in text, text
    print('patch_spell_ids_test: ok')


if __name__ == '__main__':
    main()
