#!/usr/bin/env python3
"""Take the status-cleansing spells (and Hawkeye, Bulwark, Windrunner) out of the base spells.xml (idempotent).
install_all.py step `spells`, first.

usage: python3 -I retire_cure_spells.py DATA_DIR [--dry-run]       (python3 -I retire_cure_spells.py --list prints the table)

Owner decision (2026-10-20, C6): no class cleanses a status with a spell. The seven stock cure instants are commented
out of DATA_DIR/spells/spells.xml (marker "Chaos: cure retired", the original tag kept in the comment), whatever name and
words rename_spells.py gave them (they are found by script). Their spell ids are free for the Chaos block afterwards:
register_spells.py ignores comments, so it may use them; the ids are listed in server/tests/spell_ids_test.lua (RETIRED).
Lightward (Ranger line, data/spells/chaos/paladin/divine_ward.lua, a cleanse plus eight seconds of regeneration) is not a
cure spell and stays; it also takes the raid's Withering Hex off. Cure runes (Purge Rune) are runes, not spells.
Needs to run before register_spells.py (ids) and patch_spell_ids.py (it no longer moves Wash Taint / Break Glamour).
A spell a monster names (monster_spells.py) is kept in the monster-only form instead of the comment (no spellid, so its
id is free all the same); a comment of an earlier run comes back in that form (owner report 2026-10-21).

Owner decision (2026-10-20, beta report "the auto attack stops"): the stock Sharpshooter (Chaos name Hawkeye, stock words
"utito tempo san", Chaos words "vyr ira sol") goes too (OTHERS, marker "Chaos: spell retired"). Its script put a 70%
slow (CONDITION_PARALYZE, -0.7 x speed + 56) on the caster for 10 s next to the +50% distance skill; the most likely
way it stopped the bow: a slowed Ranger in Chase Opponent mode keeps stepping after its target and every chase step holds
a distance swing (engine 0042, stepEndTime), while the helper kept the buff up. Its id 135 belongs to the Chaos replacement
Tautstring (data/spells/chaos/paladin/tautstring.lua, no slow, no lock).

Owner decision (2026-10-20, "pode trocar essas duas também"): the stock Protector (Chaos name Bulwark, "utamo tempo" /
"tor ira", id 132, Warrior line) and Swift Foot (Windrunner, "utamo tempo san" / "tor ira sol", id 134, Ranger line) go
too. Both scripts add CONDITION_PACIFIED for 10 s (no auto attack at all) and a 10 s attack group cooldown; the helper's
Auto setup kept Protector up, so the Warrior did not attack. Their ids belong to the Chaos replacements Ironhold
(data/spells/chaos/knight/ironhold.lua) and Wildstride (data/spells/chaos/paladin/wildstride.lua), no pacify, no lock.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster_spells as MS  # noqa: E402

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
    'support/protector.lua': (132, 'Bulwark'),
    'support/swift_foot.lua': (134, 'Windrunner'),
}
OTHER_MARK = 'Chaos: spell retired (retire_cure_spells.py): '
FREED_IDS = sorted(i for i, _ in list(CURES.values()) + list(OTHERS.values()))
TAG = re.compile(r'<instant\b[^>]*?(?:/>|>.*?</instant>)', re.S)


def patch(text, needed=frozenset()):
    """(new text, spells retired, spells kept for monsters); spells inside comments (also earlier retirements) are
    left alone, except a retirement comment of a spell a monster names (needed, monster_spells.needed_names): it
    comes back in the monster-only form, which a spell a monster names gets instead of the comment"""
    text, kept = MS.restore(text, needed)
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
            if MS.is_monster_only(m.group(0)) and MS.needs(m.group(0), needed):
                continue
            out.append(text[pos:m.start()])
            mark = MARK if script.group(1) in CURES else OTHER_MARK
            out.append(MS.retire(text, m, mark, needed))
            pos = m.end()
            if MS.needs(m.group(0), needed):
                kept += 1
            else:
                count += 1
    out.append(text[pos:])
    return MS.tidy(''.join(out)), count, kept


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
    new, n, kept = patch(text, MS.needed_names(args[0]))
    if new != text and '--dry-run' not in argv:
        open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new)
    if new == text:
        print('cure spells, Hawkeye, Bulwark and Windrunner: nothing to retire')
    else:
        print('cure spells, Hawkeye, Bulwark and Windrunner: %d retired, %d kept or brought back for monsters only%s'
              % (n, kept, ' (dry run)' if '--dry-run' in argv else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
