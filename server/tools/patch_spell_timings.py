#!/usr/bin/env python3
"""Cooldowns, group cooldowns, levels and mana costs of base attack spells, from server/data/spells/spell_timings.csv
(idempotent).

usage: python3 -I patch_spell_timings.py DATA_DIR [--dry-run]

The rotation pass (2026-10-14, owner: "Faça todas as classes terem até 5 magias na rotação e nunca ficarem 2s sem uma";
server/data/spells/README.md "Rotations"): a base spell whose group cooldown locked the whole attack group for longer
than the 2 s every other attack spell uses left a window with nothing to cast (Sunder Guard: 12 s, the owner saw it on
the Mystic). Bonebreaker's 6 s cooldown (2026-10-14, second pass) left the Warrior line at levels 16-29 with one
spell and a 6 s gap. The 4 s locks of the supreme strikes and the big area spells stay: they hold back strong spells (without
them a Mystic casting everything deals ~30% more), and the rotations of at most 5 spells leave those spells out.
Level and mana (2026-10-17, owner debug items 44 and 45: "A maioria das classes não tem magia no level 8", "Magias com
custo de mana muito alto, difíceis de manter"): the Warrior and Ranger lines have no Chaos attack spell before level 30, so
their first stock spells (Bonebreaker, Phantom Javelin) come at level 8 like the other classes' first spell, and the stock
Warrior spells cost what a Warrior's mana pool and regeneration can sustain (server/data/spells/README.md "Mana runway").
Each row of the csv names a base spell by its script
(rename_spells.py changes names and words, never scripts) and the values it gets in data/spells/spells.xml: an empty
cell keeps the attribute as it is. The Chaos block is never touched (its numbers are in chaos/spells_chaos.xml).
Refuses (exit 1), changing nothing, when a script of the csv has no <instant> outside the Chaos block.
The cooldown ladder (2026-10-20, owner: "faça todas as magias de ataque terem 2s de diferença"): every class's attack
spells have the cooldowns 2, 4, 6 s ... (server/data/spells/README.md "Cooldown ladder"); the stock ones are rows here.
Two base scripts put their own cooldown condition on the caster (SCRIPT_COOLDOWNS); its length follows the csv too.
"""
import csv, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CSV = os.path.join(HERE, '..', 'data', 'spells', 'spell_timings.csv')
ATTRS = ('cooldown', 'groupcooldown', 'secondarygroup', 'secondarygroupcooldown', 'level', 'mana')
# base scripts that put their own cooldown condition on the caster after the cast (data/spells/scripts/<script>): the
# hard-coded length follows the csv cooldown, else it would outlast the spells.xml one (the engine keeps the longer of
# two cooldown conditions of one spell). Headsman's Hurl set (18000 * 1000) ms, five hours, next to its 18 s.
SCRIPT_COOLDOWNS = {
    'attack/divine_grenade.lua': (re.compile(r'(local cooldown = )(\d+)( -- Fixed cooldown)'), 1),       # seconds
    'attack/executioners_throw.lua': (re.compile(r'(condition:setTicks\()(\(\d+ \* 1000\)/ 1|\d+)(\))'), 1000),  # ms
}
CHAOS_BEGIN = '<!-- BEGIN chaos spells'
CHAOS_END = '<!-- END chaos spells -->'


def load():
    return list(csv.DictReader(open(CSV, encoding='utf-8')))


def set_attr(tag, attr, value):
    if re.search(r'\b%s="[^"]*"' % attr, tag):
        return re.sub(r'(\b%s=")[^"]*(")' % attr, lambda m: m.group(1) + value + m.group(2), tag, count=1)
    return re.sub(r'(<instant\b)', lambda m: '%s %s="%s"' % (m.group(1), attr, value), tag, count=1)


def patch_text(text, rows):
    """returns (new text, changes, missing scripts)"""
    head, sep, rest = text.partition(CHAOS_BEGIN)
    block, sep2, tail = rest.partition(CHAOS_END) if sep else ('', '', '')
    changes, found = [], set()

    def fix(part):
        def tag(m):
            t = m.group(0)
            script = re.search(r'\bscript="([^"]*)"', t)
            for r in rows:
                if script and script.group(1) == r['script']:
                    found.add(r['script'])
                    for a in ATTRS:
                        v = (r.get(a) or '').strip()
                        old = re.search(r'\b%s="([^"]*)"' % a, t)
                        if v and (not old or old.group(1) != v):
                            t = set_attr(t, a, v)
                            changes.append('%s: %s %s -> %s' % (r['name'], a, old.group(1) if old else '-', v))
            return t
        return re.sub(r'<instant\b[^>]*>', tag, part)
    new = fix(head) + sep + block + sep2 + (fix(tail) if sep else '')
    missing = [r['script'] for r in rows if r['script'] not in found]
    return new, changes, missing


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    if not args:
        print(__doc__)
        return 2
    path = os.path.join(args[0], 'spells', 'spells.xml')
    text = open(path, encoding='utf-8', errors='surrogateescape').read()
    new, changes, missing = patch_text(text, load())
    if missing:
        print('patch_spell_timings: no base spell with script %s in %s' % (', '.join(missing), path))
        return 1
    for c in changes:
        print('  ' + c)
    if new != text and '--dry-run' not in argv:
        open(path, 'w', encoding='utf-8', errors='surrogateescape').write(new)
    for r in load():
        cd = (r.get('cooldown') or '').strip()
        if not cd or r['script'] not in SCRIPT_COOLDOWNS:
            continue
        pat, unit = SCRIPT_COOLDOWNS[r['script']]
        spath = os.path.join(args[0], 'spells', 'scripts', r['script'])
        if not os.path.isfile(spath):
            continue
        s = open(spath, 'rb').read().decode('latin-1')
        value = str(int(cd) // 1000) if unit == 1 else cd
        t = pat.sub(lambda m: m.group(1) + value + m.group(3), s, count=1)
        if t != s:
            changes.append('%s: script cooldown -> %s' % (r['name'], value))
            print('  %s: script cooldown -> %s' % (r['name'], value))
            if '--dry-run' not in argv:
                open(spath, 'wb').write(t.encode('latin-1'))
    print('patch_spell_timings: %d change(s)%s' % (len(changes), ' (dry run)' if '--dry-run' in argv else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
