#!/usr/bin/env python3
"""Cooldowns and group cooldowns of base attack spells, from server/data/spells/spell_timings.csv (idempotent).

usage: python3 -I patch_spell_timings.py DATA_DIR [--dry-run]

The rotation pass (2026-10-14, owner: "Faça todas as classes terem até 5 magias na rotação e nunca ficarem 2s sem uma";
server/data/spells/README.md "Rotations"): a base spell whose group cooldown locked the whole attack group for longer
than the 2 s every other attack spell uses left a window with nothing to cast (Sunder Guard: 12 s, the owner saw it on
the Mystic). The 4 s locks of the supreme strikes and the big area spells stay: they hold back strong spells (without
them a Mystic casting everything deals ~30% more), and the rotations of at most 5 spells leave those spells out.
Each row of the csv names a base spell by its script
(rename_spells.py changes names and words, never scripts) and the values it gets in data/spells/spells.xml: an empty
cell keeps the attribute as it is. The Chaos block is never touched (its numbers are in chaos/spells_chaos.xml).
Refuses (exit 1), changing nothing, when a script of the csv has no <instant> outside the Chaos block.
"""
import csv, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CSV = os.path.join(HERE, '..', 'data', 'spells', 'spell_timings.csv')
ATTRS = ('cooldown', 'groupcooldown', 'secondarygroup', 'secondarygroupcooldown')
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
    print('patch_spell_timings: %d change(s)%s' % (len(changes), ' (dry run)' if '--dry-run' in argv else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
