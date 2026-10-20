#!/usr/bin/env python3
"""Opens the gnome city teleports of the base server to every character (idempotent). install_all.py step `gnometeleports`.

usage: python3 -I patch_gnome_teleports.py DATA_DIR [--dry-run]

Owner 2026-10-18: "os teleports da cidade dos gnomos falam que eu não tenho permissão pra usar. Por favor libere todos".
DATA_DIR is the base server's data folder. Two movement scripts check the Bigfoot's Burden quest line:
  * movements/scripts/quests/bigfoot burden/GCTS.lua (the gnome city teleports: Gnomebase, Gnomebase Alpha, the
    crystal grounds, Truffles' Garden, the golems and the way out to each city): every destination wants a quest
    storage value (1, 14, 15, 16) and the city ones also consume a Teleport Crystal. The values become -1 (the quest
    line is -1 for everybody who never started it, so the check passes) and `needCrystal = true` becomes false.
  * movements/scripts/quests/bigfoot burden/warzoneTeleports.lua (the three warzone entrances): the storage 955 / 956 /
    957 must equal 1 / 2 / 3; the refusal is skipped.
The Warzone boss rooms are not touched. A second run changes nothing. Prints one line per changed file.
"""
import os
import re
import sys

MARKER = '-- Chaos: open to everyone (patch_gnome_teleports.py)'
GCTS = os.path.join('movements', 'scripts', 'quests', 'bigfoot burden', 'GCTS.lua')
WARZONE = os.path.join('movements', 'scripts', 'quests', 'bigfoot burden', 'warzoneTeleports.lua')

STORAGE_RE = re.compile(r'(storageValue\s*=\s*)(\d+)')
CRYSTAL_RE = re.compile(r'(needCrystal\s*=\s*)true')
REFUSAL = 'if player:getStorageValue(destination.storage) ~= destination.value then'


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def patch_gcts(text):
    """(new text, [change, ...])"""
    if MARKER in text:
        return text, []
    changes = []

    def storage(m):
        if int(m.group(2)) == 0:
            return m.group(0)
        changes.append('storageValue %s -> -1' % m.group(2))
        return m.group(1) + '-1'
    text = STORAGE_RE.sub(storage, text)

    def crystal(m):
        changes.append('needCrystal true -> false')
        return m.group(1) + 'false'
    text = CRYSTAL_RE.sub(crystal, text)
    if not changes:
        return text, []
    return MARKER + '\n' + text, changes


def patch_warzone(text):
    if MARKER in text or REFUSAL not in text:
        return text, []
    new = text.replace(REFUSAL, 'if false then ' + MARKER.replace('-- ', '-- ', 1) + '\n\t\t-- (was: ' + REFUSAL[3:-5] + ')')
    # the replaced line reads `if false then -- Chaos: ...` followed by the old condition as a comment
    return new, ['warzone entrances opened']


def main(argv):
    args = [a for a in argv if a != '--dry-run']
    dry = '--dry-run' in argv
    if len(args) != 1 or args[0].startswith('-'):
        print(__doc__)
        return 1
    data = args[0]
    done = 0
    for rel, fn in ((GCTS, patch_gcts), (WARZONE, patch_warzone)):
        path = os.path.join(data, rel)
        if not os.path.isfile(path):
            print('%s: not found (skipped)' % rel.replace(os.sep, '/'))
            continue
        text = read(path)
        new, changes = fn(text)
        if new == text:
            continue
        done += 1
        if not dry:
            write(path, new)
        print('%s: %d change(s)' % (rel.replace(os.sep, '/'), len(changes)))
    print('gnome teleports: %d file(s) %s' % (done, 'would change' if dry else 'changed') if done else
          'gnome teleports: nothing to change')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
