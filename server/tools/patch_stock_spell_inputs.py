#!/usr/bin/env python3
"""The two flat base spells read the level and the magic level (O468, idempotent).

usage: python3 -I patch_stock_spell_inputs.py DATA_DIR [--dry-run]

Owner 2026-11-10: a spell's damage is made of the character level, the magic level (and for a weapon line the weapon
skill). Two base-server attack spells ignored all three, a Mystic line caster dealt the same number at level 8 and at
level 1000 (server/data/spells/README.md "Spell scaling (O468)"):
  * Kindling Spark (attack/apprentice's_strike.lua, learned at level 8): a flat 10 to 20. Now the standard formula
    level / 5 + magic level x 0.2..0.3 + 7.5..17: a typical caster (server/tools/rotation_sim.py ANCHORS 'ml_caster', magic
    level 4.2 at level 8) deals 9.9 to 19.9 there, the old number, and the spell stays a cheap opener above it;
  * Bewitching Hex (custom/illusionist_class/bewitched_curse.lua, learned at level 60): four ticks of 128, 256, 384, 512
    whatever the caster. Now the first tick is level / 5 + magic level x 2 + 44.5 (128.0 for a typical caster at level
    60, magic level 35.8) and each tick adds that again, so the four ticks keep the 1 : 2 : 3 : 4 shape.
Only the damage numbers change, each in one line; every other line of the scripts (the Mystic effects wrap of
patch_mystic_stock_fx.py too) stays as it is. Marker: `chaos spell scaling (O468` in the changed lines, so a second run
changes nothing. Refuses (exit 1), changing nothing, when a script is missing or has neither the base line nor the marker.
install_all.py runs it in the `spells` step after patch_mystic_stock_fx.py.
"""
import os
import re
import sys

MARK = 'chaos spell scaling (O468, server/tools/patch_stock_spell_inputs.py)'
DONE = 'chaos spell scaling (O468'

SPARK = "attack/apprentice's_strike.lua"
HEX = 'custom/illusionist_class/bewitched_curse.lua'

# Kindling Spark: the base callback returns a flat -10, -20; (player, level, magicLevel) are the engine's arguments
SPARK_RE = re.compile(r'(function onGetFormulaValues\(player, level, magicLevel\)[ \t]*\r?\n[ \t]*)return -10, -20([ \t]*)(?=\r?\n)')
SPARK_NEW = r'\1return -(level / 5 + magicLevel * 0.2 + 7.5), -(level / 5 + magicLevel * 0.3 + 17) -- ' + MARK

# Bewitching Hex: the base script has two locals, 128 each (trailing blanks in the base file)
HEX_RE = re.compile(r'(?P<ind>[ \t]*)local baseDamage = 128[ \t]*(?P<eol>\r?\n)[ \t]*local damageIncrement = 128[ \t]*(?=\r?\n)')


def hex_new(m):
    i, e = m.group('ind'), m.group('eol')
    return (i + '-- ' + MARK + ': 128 for a typical caster at the level it is learned (60)' + e
            + i + 'local caster = creature:getPlayer()' + e
            + i + 'local baseDamage = caster and math.floor(caster:getLevel() / 5 + caster:getMagicLevel() * 2 + 44.5) or 128' + e
            + i + 'local damageIncrement = baseDamage')


def patch_text(name, text):
    """-> (new text, changed, error)"""
    if DONE in text:
        return text, False, None
    if name == SPARK:
        if not SPARK_RE.search(text):
            return text, False, 'no `return -10, -20` in onGetFormulaValues'
        return SPARK_RE.sub(SPARK_NEW, text, count=1), True, None
    if name == HEX:
        if not HEX_RE.search(text):
            return text, False, 'no `local baseDamage = 128` / `local damageIncrement = 128`'
        return HEX_RE.sub(hex_new, text, count=1), True, None
    return text, False, 'unknown script'


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1:
        print(__doc__)
        return 2
    base = os.path.join(os.path.abspath(args[0]), 'spells', 'scripts')
    todo = []
    for name in (SPARK, HEX):
        path = os.path.join(base, *name.split('/'))
        if not os.path.isfile(path):
            print('missing file: %s' % path)
            return 1
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        new, changed, err = patch_text(name, text)
        if err:
            print('%s: %s' % (name, err))
            return 1
        todo.append((path, name, new, changed))
    for path, name, new, changed in todo:
        if not changed:
            print('%s: already reads the level and the magic level' % name)
            continue
        print('%s: %s' % (name, 'would read' if dry else 'reads') + ' the level and the magic level')
        if not dry:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
