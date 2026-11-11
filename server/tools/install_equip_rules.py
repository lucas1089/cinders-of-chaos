#!/usr/bin/env python3
"""Write the rule every wearable item is held to for the item tooltip, in a base server (idempotent).

usage: python3 -I install_equip_rules.py DATA_DIR [--dry-run]

Owner, 2026-11-11: a Ring of Blue Plasma said "Level 30, all classes" and the server refused it (O489); "look for other items
that have the same bug" (O490). The tooltip's requirement chips read the engine's item type, and that holds only what the
look text shows: the SHOWN vocations (add_vocations.py hides the ascended class next to its base class, so a wand for the
Mystic and the Illusionist reads "mystics and necromancers" while the Elementalist is refused) and the level and class list
of one of the two entries an item can have (an Equip entry in movements.xml, a weapon entry in weapons.xml).

This step reads the installed movements.xml (Equip entries, the recorded stock rules of chaos_unique_equip.lua) and
weapons.xml and writes data/lib/chaos_equip_rules.lua: for each id with a class list, or whose two entries disagree on the
level, the level and magic level to meet (the higher of the two entries), the classes of both lists and an index into a table
of class lists. The item tooltip (data/scripts/chaos/item_tooltip_core.lua T.equipRuleOf) names those classes. Nothing is
changed about who can wear what; no XML is touched. Without the file the tooltip reads the engine's item type as before.
Run it after every step that writes movements.xml or weapons.xml (it is next to last in install_all.py); a re-run rebuilds
the file from the XML as it is. tools/equip_rules.py reads the XML; tools/audit_equip_tooltips.py checks the result.
server/README.md "Equip rules in the tooltip (O490)"; tools/install_equip_rules_test.py.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import equip_rules as R  # noqa: E402

REL = os.path.join('lib', 'chaos_equip_rules.lua')


def build(data_dir):
    """(file text, number of rules)"""
    rules = R.Rules(data_dir)
    text = R.lua_text(rules)
    return text, text.count('] = {')


def main(argv):
    dry = '--dry-run' in argv
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1 or any(a.startswith('--') and a != '--dry-run' for a in argv):
        print(__doc__)
        return 1
    data_dir = args[0]
    for rel in (os.path.join('movements', 'movements.xml'), os.path.join('weapons', 'weapons.xml')):
        if not os.path.exists(os.path.join(data_dir, rel)):
            print('not found:', os.path.join(data_dir, rel))
            return 1
    text, n = build(data_dir)
    path = os.path.join(data_dir, REL)
    old = R.read(path) if os.path.exists(path) else None
    state = 'up to date' if old == text else ('rewritten' if old is not None else 'written')
    print('lib/chaos_equip_rules.lua: %s (%d rules)' % (state, n))
    if dry:
        print('dry run: nothing written')
        return 0
    if old != text:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
