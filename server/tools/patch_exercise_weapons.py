#!/usr/bin/env python3
"""The exercise (training) weapons: one melee weapon, every class has one (idempotent). install_all.py step `exercise`.

usage: python3 -I patch_exercise_weapons.py DATA_DIR [--dry-run]

Owner request 2026-10-23: the Monk could use none that helped it, and the axe, sword and club weapons should be one melee
weapon. data/scripts/chaos/exercise_training.lua (rules: exercise_core.lua, lists: exercise_config.lua) now runs all 21
weapons; this tool does the base data's half:

1. data/actions/actions.xml: the 21 lines `<action itemid="277nn" script="other/exercise_weapons.lua" />` are commented out
   (a marker comment says why), so the revscript owns the item ids (an id registered twice would keep the XML one). The
   stock script and the edits of patch_base_classes.py / patch_base_events.py stay in the folder, unused.
2. data/items/items.xml: the description of each of the 21 weapons says what it trains and who may use it, and the three
   sword chests (27761, 27768, 27775: the melee chests now) say they give the melee weapon. The names come from
   data/items/base_item_names.csv (patch_base_item_names.py: "exercise melee weapon", ...). The axe and club weapons and
   chests keep their names and still work; an old axe or club weapon turns into the melee one on its first use.
3. data/npc/*.xml: the NPC shop lists lose the exercise axe and club chests (27762, 27763, 27769, 27770, 27776, 27777, one
   line each); the sword chests (the melee ones), the bow, rod, wand and shield chests stay. Chests bought before still
   open.

Idempotent: a second run changes nothing. Run it after the base files are replaced. --dry-run writes nothing.
"""
import glob
import os
import re
import sys

MARK = 'Chaos: exercise weapons run by exercise_training.lua (patch_exercise_weapons.py)'

# item id -> what it trains and who may use it (kept in step with data/scripts/chaos/exercise_config.lua; the test reads both)
MELEE = 'Trains the melee skill on a training dummy (fist fighting for the Monk line). For the Warrior, Thief, Monk and Templar lines.'
RANGED = 'Trains distance fighting on a training dummy. For the Ranger and Thief lines.'
MAGIC = 'Trains the magic level on a training dummy. For the Mystic, Necromancer and Templar lines.'
SHIELD = 'Trains shielding on a training dummy. For every class.'
WEAPONS = {}
for i in (27732, 27733, 27734, 27738, 27739, 27740, 27744, 27745, 27746):
    WEAPONS[i] = MELEE
for i in (27735, 27741, 27747):
    WEAPONS[i] = RANGED
for i in (27736, 27737, 27742, 27743, 27748, 27749):
    WEAPONS[i] = MAGIC
for i in (27758, 27759, 27760):
    WEAPONS[i] = SHIELD
CHEST = 'Use the chest to obtain 1 melee training weapon. It trains the melee skill (fist fighting for the Monk line).'
CHESTS = {27761: CHEST, 27768: CHEST, 27775: CHEST}
DESCRIPTIONS = dict(WEAPONS)
DESCRIPTIONS.update(CHESTS)

RETIRED_CHESTS = (27762, 27763, 27769, 27770, 27776, 27777)

ACTION_LINE = re.compile(r'^([ \t]*)(<action\b[^>\n]*\bscript="other/exercise_weapons\.lua"[^>\n]*/>)[ \t]*(\r?)$', re.M)
NPC_LINE = re.compile(r'^[ \t]*[^,;\r\n"<>]*,[ \t]*(?:%s)[ \t]*,[ \t]*\d+[ \t]*;[ \t]*\r?\n'
                      % '|'.join(str(i) for i in RETIRED_CHESTS), re.M)
DESC_ATTR = re.compile(r'(<attribute\s+key="description"\s+value=")[^"]*(")', re.I)


def patch_actions(text):
    """returns (new text, status): 'patched', 'already' or an error message"""
    hits = list(ACTION_LINE.finditer(text))
    if not hits:
        if MARK in text:
            return text, 'already'
        return text, 'no script="other/exercise_weapons.lua" action found in actions.xml'

    def comment(m):
        return '%s<!-- %s: %s -->%s' % (m.group(1), MARK, m.group(2).replace('--', '- -'), m.group(3))
    return ACTION_LINE.sub(comment, text), 'patched'


def patch_items(text):
    """returns (new text, [problems], changed count)"""
    problems, changed = [], 0
    for iid, desc in sorted(DESCRIPTIONS.items()):
        pat = re.compile(r'(<item\s+id="%d"[^>]*?)(/>|>(.*?)</item>)' % iid, re.S)
        m = pat.search(text)
        if not m:
            problems.append('item %d not found in items.xml' % iid)
            continue
        if m.group(2) == '/>':
            problems.append('item %d has no attribute block' % iid)
            continue
        body = m.group(3)
        if DESC_ATTR.search(body):
            new_body = DESC_ATTR.sub(lambda a: a.group(1) + desc + a.group(2), body, count=1)
        else:
            eol = '\r\n' if '\r\n' in body else '\n'
            indent = re.search(r'([ \t]*)<attribute', body)
            indent = indent.group(1) if indent else '\t\t'
            tail = re.search(r'[ \t]*$', body).group(0)
            new_body = body[:len(body) - len(tail)].rstrip('\r\n') + eol + indent + \
                '<attribute key="description" value="%s" />' % desc + eol + tail
        if new_body != body:
            text = text[:m.start(3)] + new_body + text[m.end(3):]
            changed += 1
    return text, problems, changed


def patch_npc(text):
    """returns (new text, removed line count)"""
    new, n = NPC_LINE.subn('', text)
    return new, n


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1:
        print(__doc__.strip().splitlines()[2])
        return 2
    data = args[0]
    ok = True

    path = os.path.join(data, 'actions', 'actions.xml')
    if os.path.isfile(path):
        new, status = patch_actions(read(path))
        if status not in ('patched', 'already'):
            print('actions/actions.xml: %s' % status)
            ok = False
        else:
            if status == 'patched' and not dry:
                write(path, new)
            print('actions/actions.xml: %s' % status)
    else:
        print('%s: not found' % path)
        ok = False

    path = os.path.join(data, 'items', 'items.xml')
    if os.path.isfile(path):
        new, problems, changed = patch_items(read(path))
        for p in problems:
            print('items/items.xml: %s' % p)
        ok = ok and not problems
        if changed and not dry:
            write(path, new)
        print('items/items.xml: %d description(s) %s' % (changed, 'would change' if dry else 'changed'))
    else:
        print('%s: not found' % path)
        ok = False

    removed = 0
    for path in sorted(glob.glob(os.path.join(data, 'npc', '*.xml'))):
        text = read(path)
        new, n = patch_npc(text)
        if n:
            removed += n
            if not dry:
                write(path, new)
    print('npc: %d retired chest line(s) %s' % (removed, 'would go' if dry else 'removed'))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
