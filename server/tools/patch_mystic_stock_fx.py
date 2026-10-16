#!/usr/bin/env python3
"""Mystic line effects in two base-server spell scripts: Bewitching Hex and Arcane Ripple (idempotent).

usage: python3 -I patch_mystic_stock_fx.py DATA_DIR [--dry-run]

The two most cast spells of the Mystic and Illusionist rotations are base scripts (docs/CLASSES.md "Rotations"; their
names come from rename_spells.py). Bewitching Hex sent a 1 x 1 missile and a 1 x 1 effect, nearly invisible; Arcane
Ripple a cone of 1 x 1 rune rings (server/data/spells/README_FX.md "Mystic line effects"). Each script gets:
  * a load of data/lib/chaos_mystic_fx.lua at its top;
  * Bewitching Hex: its effect and missile ids wrapped in ChaosMysticFx.stockEffect / stockMissile, which give the
    none ids when the pack arcane bolt and arcane hit are in the client pair (the old ids otherwise);
  * at its end, onCastSpell wrapped by ChaosMysticFx.wrapStock: after a successful cast the arcane bolt flies, the
    arcane hit lands on its arrival and the curse mark (tick_curse) on each of the four ticks (Bewitching Hex); the
    arcane hit at the wave's mouth and a hexagon sigil on each monster in the cone (Arcane Ripple).
Damage, areas and timing stay as the base scripts have them. Every block sits between marker lines, so a second run
changes nothing. Refuses (exit 1), changing nothing, when a script is missing or a line to wrap is not there.
"""
import os
import re
import sys

HEAD_BEGIN = '-- >>> chaos mystic fx (server/tools/patch_mystic_stock_fx.py)'
HEAD_END = '-- <<< chaos mystic fx'
TAIL_BEGIN = '-- >>> chaos mystic fx wrap (server/tools/patch_mystic_stock_fx.py)'
TAIL_END = '-- <<< chaos mystic fx wrap'

# script under data/spells/scripts -> (key in ChaosMysticFx.STOCK, [(regex of a base line, replacement, what, the text
# a patched script has instead)])
SCRIPTS = {
    'custom/illusionist_class/bewitched_curse.lua': ('bewitching_hex', [
        (r'(combat:setParameter\(COMBAT_PARAM_EFFECT,\s*)(\d+)(\))',
         r'\1ChaosMysticFx and ChaosMysticFx.stockEffect("bewitching_hex", \2) or \2\3', 'the effect id',
         'ChaosMysticFx.stockEffect("bewitching_hex"'),
        (r'(combat:setParameter\(COMBAT_PARAM_DISTANCEEFFECT,\s*)(\d+)(\))',
         r'\1ChaosMysticFx and ChaosMysticFx.stockMissile("bewitching_hex", \2) or \2\3', 'the missile id',
         'ChaosMysticFx.stockMissile("bewitching_hex"'),
    ]),
    'custom/illusionist_class/arcane_wave.lua': ('arcane_ripple', []),
}


def head_block():
    return '\n'.join([HEAD_BEGIN, 'if not ChaosMysticFx then', "\tpcall(dofile, 'data/lib/chaos_mystic_fx.lua')", 'end',
                      HEAD_END]) + '\n'


def tail_block(key):
    return '\n'.join([TAIL_BEGIN, 'if ChaosMysticFx and ChaosMysticFx.wrapStock and onCastSpell then',
                      '\tonCastSpell = ChaosMysticFx.wrapStock("%s", onCastSpell)' % key, 'end', TAIL_END]) + '\n'


def patch_text(text, key, reps):
    """-> (new text, changes, error)"""
    changes = []
    new = text
    if HEAD_BEGIN not in new:
        new = head_block() + new
        changes.append('load chaos_mystic_fx.lua')
    for pattern, repl, what, done in reps:
        if done in new:
            continue
        if not re.search(pattern, new):
            return text, [], 'no line that sets %s' % what
        new = re.sub(pattern, repl, new, count=1)
        changes.append('wrap ' + what)
    if 'function onCastSpell' not in new:
        return text, [], 'no onCastSpell'
    if TAIL_BEGIN not in new:
        if not new.endswith('\n'):
            new += '\n'
        new += tail_block(key)
        changes.append('wrap onCastSpell')
    return new, changes, None


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    if not args:
        print(__doc__)
        return 2
    base = os.path.join(args[0], 'spells', 'scripts')
    out, total = {}, 0
    for rel, (key, reps) in SCRIPTS.items():
        path = os.path.join(base, rel)
        if not os.path.isfile(path):
            print('patch_mystic_stock_fx: %s is missing' % path)
            return 1
        text = open(path, encoding='utf-8', errors='surrogateescape').read()
        new, changes, err = patch_text(text, key, reps)
        if err:
            print('patch_mystic_stock_fx: %s: %s' % (rel, err))
            return 1
        for c in changes:
            print('  %s: %s' % (rel, c))
        total += len(changes)
        out[path] = (text, new)
    if '--dry-run' not in argv:
        for path, (text, new) in out.items():
            if new != text:
                open(path, 'w', encoding='utf-8', errors='surrogateescape').write(new)
    print('patch_mystic_stock_fx: %d change(s)%s' % (total, ' (dry run)' if '--dry-run' in argv else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
