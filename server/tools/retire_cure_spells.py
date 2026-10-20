#!/usr/bin/env python3
"""Take the status-cleansing spells (and Hawkeye) out of the base spells.xml (idempotent). install_all.py step `spells`,
first.

usage: python3 -I retire_cure_spells.py DATA_DIR [--dry-run]       (python3 -I retire_cure_spells.py --list prints the table)

Owner decision (2026-10-20, C6): no class cleanses a status with a spell. The seven stock cure instants are commented
out of DATA_DIR/spells/spells.xml (marker "Chaos: cure retired", the original tag kept in the comment), whatever name and
words rename_spells.py gave them (they are found by script). Their spell ids are free for the Chaos block afterwards:
register_spells.py ignores comments, so it may use them; the ids are listed in server/tests/spell_ids_test.lua (RETIRED).
Lightward (Ranger line, data/spells/chaos/paladin/divine_ward.lua, a cleanse plus eight seconds of regeneration) is not a
cure spell and stays; it also takes the raid's Withering Hex off. Cure runes (Purge Rune) are runes, not spells.
Needs to run before register_spells.py (ids) and patch_spell_ids.py (it no longer moves Wash Taint / Break Glamour).

Owner decision (2026-10-20, beta report "the auto attack stops"): the stock Sharpshooter (Chaos name Hawkeye, stock words
"utito tempo san", Chaos words "vyr ira sol") goes too (OTHERS, marker "Chaos: spell retired"). Its script put a 70%
slow (CONDITION_PARALYZE, -0.7 x speed + 56) on the caster for 10 s next to the +50% distance skill; the most likely
way it stopped the bow: a slowed Ranger in Chase Opponent mode keeps stepping after its target and every chase step holds
a distance swing (engine 0042, stepEndTime), while the helper kept the buff up. Its id 135 belongs to the Chaos replacement
Tautstring (data/spells/chaos/paladin/tautstring.lua, no slow, no lock).
"""
import os
import re
import sys

MARK = 'Chaos: cure retired (retire_cure_spells.py): '
# script (relative to data/spells/scripts) -> (stock spell id after patch_spell_ids.py, Chaos name)
CURES = {
    'healing/cure_poison.lua': (29, 'Purge Venom'),
    'healing/cure_splashed.lua': (58, 'Wash Taint'),
    'healing/cure_bleeding.lua': (144, 'Staunch Blood'),
    'healing/cure_burning.lua': (145, 'Douse Embers'),
    'healing/cure_electrification.lua': (146, 'Ground Static'),
    'healing/cure_curse.lua': (147, 'Lift Hex'),
    'healing/cure_bewitched.lua': (164, 'Break Glamour'),
}
# other stock spells the owner retired: script -> (stock spell id, Chaos name)
OTHERS = {
    'support/sharpshooter.lua': (135, 'Hawkeye'),
}
OTHER_MARK = 'Chaos: spell retired (retire_cure_spells.py): '
FREED_IDS = sorted(i for i, _ in list(CURES.values()) + list(OTHERS.values()))
TAG = re.compile(r'<instant\b[^>]*?(?:/>|>.*?</instant>)', re.S)


def patch(text):
    """(new text, number of spells retired); spells inside comments (also earlier retirements) are left alone"""
    chaos_a = text.find('<!-- BEGIN chaos spells')
    chaos_b = text.find('<!-- END chaos spells -->')
    count = 0
    out, pos = [], 0
    for m in re.finditer(r'<!--.*?-->|' + TAG.pattern, text, re.S):
        if m.group(0).startswith('<!--'):
            continue
        if chaos_a != -1 and chaos_a <= m.start() < chaos_b:
            continue
        script = re.search(r'\bscript="([^"]*)"', m.group(0))
        if script and (script.group(1) in CURES or script.group(1) in OTHERS):
            out.append(text[pos:m.start()])
            mark = MARK if script.group(1) in CURES else OTHER_MARK
            out.append('<!-- ' + mark + m.group(0).replace('--', '- -') + ' -->')
            pos = m.end()
            count += 1
    out.append(text[pos:])
    return ''.join(out), count


def main(argv):
    if '--list' in argv:
        for script, (sid, name) in sorted(list(CURES.items()) + list(OTHERS.items()), key=lambda kv: kv[1][0]):
            print('%3d  %-14s %s' % (sid, name, script))
        return 0
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    path = os.path.join(args[0], 'spells', 'spells.xml')
    if not os.path.isfile(path):
        print('missing file: ' + path)
        return 1
    text = open(path, encoding='utf-8', errors='surrogateescape', newline='').read()
    new, n = patch(text)
    if n and '--dry-run' not in argv:
        open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new)
    print('cure spells and Hawkeye: %d retired%s' % (n, ' (dry run)' if '--dry-run' in argv else '') if n else
          'cure spells and Hawkeye: nothing to retire')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
