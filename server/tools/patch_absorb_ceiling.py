#!/usr/bin/env python3
"""Absorb ceiling of 75 percent in the base absorb event (idempotent). install_all.py step `absorbceiling`.

usage: python3 -I patch_absorb_ceiling.py DATA_DIR [--dry-run]

Owner decision 2026-10-20 (server/README.md "Absorb ceiling", engine patch 0049-absorb-ceiling).
DATA_DIR is the base server's data folder. scripts/customs/rarity/rarity_onCombat_absorbs.lua adds the absorb storages of
a damage type (gear rarity rolls 977544.., passive tree and Paragon 977562..) and takes the sum off the hit, with no limit.
The patch limits that sum to CEILING (75) per type, the same number as CHAOS_ABSORB_CEILING_PERCENT in the engine patch and
ChaosItemMods.config.absorbCeiling. Marker: `-- Chaos: absorb ceiling (patch_absorb_ceiling.py)`. A second run changes nothing.
"""
import os
import sys

MARKER = '-- Chaos: absorb ceiling (patch_absorb_ceiling.py)'
TARGET = os.path.join('scripts', 'customs', 'rarity', 'rarity_onCombat_absorbs.lua')
CEILING = 75

OLD_RETURN = '''        total = total + v
    end
    return total
end
'''
NEW_RETURN = '''        total = total + v
    end
    return math.min(total, %d) -- Chaos: the ceiling
end
''' % CEILING


def patch(text):
    """(new text, [change, ...])"""
    if MARKER in text:
        return text, []
    if text.count(OLD_RETURN) != 1:
        return text, ['REFUSED: expected code not found (getCombinedAbsorb)']
    return MARKER + '\n' + text.replace(OLD_RETURN, NEW_RETURN), ['absorb sum limited to %d' % CEILING]


def main(argv):
    args = [a for a in argv if a != '--dry-run']
    dry = '--dry-run' in argv
    if len(args) != 1 or args[0].startswith('-'):
        print(__doc__)
        return 1
    path = os.path.join(args[0], TARGET)
    name = TARGET.replace(os.sep, '/')
    if not os.path.isfile(path):
        print('%s: not found (skipped)' % name)
        return 0
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    crlf = '\r\n' in text
    new, changes = patch(text.replace('\r\n', '\n'))
    if changes and changes[0].startswith('REFUSED'):
        print('%s: %s' % (name, changes[0]))
        return 1
    if not changes:
        print('absorb ceiling: nothing to change')
        return 0
    if crlf:
        new = new.replace('\n', '\r\n')
    if not dry:
        with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
    print('%s: %s' % (name, ', '.join(changes)))
    print('absorb ceiling: 1 file %s' % ('would change' if dry else 'changed'))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
