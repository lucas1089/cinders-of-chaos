#!/usr/bin/env python3
"""Audit the item tooltip's "who can wear it" chips against what the server enforces (server/README.md "Equip rules in the tooltip (O490)").

usage: python3 -I server/tools/audit_equip_tooltips.py DATA_DIR [--check] [--top N] [--examples N] [--list KIND]
                                                       [--lua BIN] [--movements-last]

Owner, 2026-11-11: a legendary Ring of Blue Plasma said "Level 30, all classes" and the server refused it ("This item cannot be
equipped in the ring slot"). "Look for other items that have the same bug." DATA_DIR is the data folder of an INSTALLED server
(or a copy of the files listed below). Read only. Not in CI (it needs an installed server's files; the test,
audit_equip_tooltips_test.py, runs the same maths on small synthetic files, one per kind). The tool prints a table.

What the server enforces (tools/equip_rules.py has the details)
  refusal   movements.xml Equip entries: level, magic level, every vocation (shown or hidden); an entry held by
            chaos_unique_equip.lua is held to its recorded stock rule for a plain copy. An unmet rule REFUSES the item.
  weapon    weapons.xml level, magic level, vocations: an unmet rule does not refuse the item, the weapon check gives no hit
            (half with unproperly="1" for level and magic level). A penalty, a kind of its own below.
  unique    a unique copy is held to its spec's own rule (data/lib/chaos_unique_specs.lua `equip`) as well.
What the tooltip shows: the REAL tooltip code (data/scripts/chaos/item_tooltip_core.lua T.build), run by
tools/audit_equip_tooltips.lua (luajit or lua5.3) on a mocked engine whose item types hold what the engine would hold for
the installed files (level, magic level, vocation string: only the shown vocations). The tooltip reads, when the folder has
them, lib/chaos_equip_rules.lua (install_equip_rules.py) and movements/scripts/chaos_unique_equip.lua.
The reading of the class chips the audit holds the tooltip to: a base class named alone stands for its whole line (the class and
its two ascended classes); a line that is only partly allowed is named class by class ("Mystic, Illusionist"; "Mystic only" is
the base class alone); "all classes" means every class. A chip set is right when the set of classes it stands for equals the set
the server lets through.

Kinds (an item counts once per kind; `unique copy:` is the tooltip of a copy that carries the unique mark)
  refused: level / magic level / class    the tooltip says yes, the Equip entry refuses  (--check fails)
  weapon check: level / magic level / class  the tooltip says yes, the weapon check gives no hit or half  (a penalty)
  tooltip stricter: level / magic level / class  the tooltip says no, the server allows it (lesser)
  tooltip error                            the tooltip code failed on the item (the run fails)
  unique copy: tooltip stricter: level     fails --check as well since O510 (it is 0): the chip names the unique's own level
                                           where the server asks none or less. Every unique is read, also one whose base item
                                           has no rule at all (the run lists them with the tooltips of the ids that have a rule)
`effective` is the reference for "stricter": the higher level, magic level and both class sets of the two rules.
Exit 0, 1 on a failed --check or a tooltip error, 2 on a usage error. The order the engine reads weapons.xml and movements.xml
in is not in this repository: the item types hold the weapon entry's numbers when both exist (--movements-last: the Equip entry's).
"""
import collections
import os
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import equip_rules as R  # noqa: E402

ROW_LIMIT = 120  # item_tooltip_core.lua classLine cuts the class row between two names here; a name it drops shows as `stricter: class`
WEAPON_TYPES = {'sword': 1, 'club': 2, 'axe': 3, 'shield': 4, 'distance': 5, 'wand': 6, 'ammunition': 7, 'quiver': 8}
AMMO_TYPES = {'bolt': 1, 'arrow': 2}
SLOT_BITS = {'head': 1, 'necklace': 2, 'backpack': 4, 'body': 8, 'armor': 8, 'right-hand': 16, 'legs': 64, 'feet': 128,
             'ring': 256, 'ammo': 512}
HAND = 48
TWO_HANDED = 48 + 2048
FAIL_KINDS = ('refused: level', 'refused: magic level', 'refused: class', 'tooltip error')
# O510 (2026-11-11): the kinds of a unique copy that fail --check as well, now that they are 0: its tooltip asks a level the
# server does not (35 older uniques did, 58 once every unique is read). The lesser kinds of a plain copy stay a list.
FAIL_LABELS = ('unique copy: tooltip stricter: level',)


def fails(label):
    """does a kind (as kind_label writes it) fail --check"""
    return label.replace('unique copy: ', '') in FAIL_KINDS or label in FAIL_LABELS


def load_items(data_dir):
    """{id: {name, weaponType, ammoType, slotType}} of items.xml"""
    out = {}
    path = os.path.join(data_dir, 'items', 'items.xml')
    if not os.path.exists(path):
        return out
    for e in ET.parse(path).getroot().iter('item'):
        if e.get('id') is None:
            continue
        attrs = {a.get('key'): a.get('value') for a in e.findall('attribute')}
        out[int(e.get('id'))] = {'name': e.get('name') or '', 'weaponType': attrs.get('weaponType', ''),
                                 'ammoType': attrs.get('ammoType', ''), 'slotType': attrs.get('slotType', '')}
    return out


def slot_position(info, equip_entry):
    """the slot position the engine's item type holds, as far as items.xml and the Equip entry tell it"""
    st, wt = info.get('slotType', ''), info.get('weaponType', '')
    if st == 'two-handed':
        return TWO_HANDED
    if wt == 'quiver':
        return SLOT_BITS['ammo']
    if wt in ('sword', 'club', 'axe', 'distance', 'wand', 'shield'):
        return HAND
    if st in SLOT_BITS:
        return SLOT_BITS[st]
    if equip_entry and equip_entry['slot'] in SLOT_BITS:
        return SLOT_BITS[equip_entry['slot']]
    if equip_entry and equip_entry['slot'] == 'hand':
        return HAND
    return 0


def shape(names):
    """the classes of a set as lines: `Mystic*` a whole line, `Mystic+Illusionist` the classes it has"""
    if names is None:
        return 'every class'
    out = []
    for line in R.LINES:
        got = [n for n in line if n in names]
        if len(got) == 3:
            out.append(line[0] + '*')
        elif got:
            out.append('+'.join(got))
    return ', '.join(out) or 'no class'


def find_lua(wanted):
    for name in ([wanted] if wanted else ['luajit', 'lua5.3', 'lua']):
        path = shutil.which(name)
        if path:
            return path
    raise SystemExit('no Lua interpreter (luajit, lua5.3) found; --lua BIN')


def run_tooltips(rules, items, data_dir, lua, weapons_last):
    """{('P'|'U', id): {level, magic, voc, equipLevel, equipVocs, entryLevel}} of the real tooltip, and [(id, message)] errors"""
    tmp = tempfile.mkdtemp(prefix='equipaudit')
    try:
        tsv = os.path.join(tmp, 'items.tsv')
        with open(tsv, 'w', encoding='utf-8') as f:
            for iid in rules.ids():
                info = items.get(iid, {})
                level, magic, voc = rules.item_type(iid, weapons_last)
                entry = (rules.equip.get(iid) or [None])[0]
                f.write('\t'.join(str(x) for x in (iid, level, magic, voc, WEAPON_TYPES.get(info.get('weaponType', ''), 0),
                                                   slot_position(info, entry), AMMO_TYPES.get(info.get('ammoType', ''), 0),
                                                   info.get('name', '').replace('\t', ' '))) + '\n')
        proc = subprocess.run([lua, 'tools/audit_equip_tooltips.lua', os.path.abspath(data_dir), tsv], cwd=SERVER,
                              capture_output=True, text=True)
        if proc.returncode != 0:
            raise SystemExit('the tooltip driver failed:\n' + proc.stderr + proc.stdout[-2000:])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    shown, errors = {}, []
    for line in proc.stdout.splitlines():
        f = line.split('\t')
        if f[0] == 'E':
            errors.append((int(f[1]), f[2] if len(f) > 2 else ''))
        elif f[0] in ('P', 'U') and len(f) >= 5:
            row = {'level': int(f[2]), 'magic': int(f[3]), 'voc': f[4]}
            if f[0] == 'U':
                row.update(equipLevel=f[5], equipVocs=f[6], entryLevel=int(f[7]), uniqueName=f[8] if len(f) > 8 else '')
            shown[(f[0], int(f[1]))] = row
    return shown, errors


def kinds_of(rules, iid, row, unique):
    """[kind] of one tooltip: row = the driver's numbers"""
    out = []
    refusal, weapon, eff = rules.refusal(iid), rules.weapon(iid), rules.effective(iid)
    if unique and row['equipLevel'] != '-':
        # a unique copy is held to its spec's rule as well
        own_set = None if row['equipVocs'] == '*' else frozenset(row['equipVocs'].split('|'))
        base = rules.entry_rule(iid) or {'level': 0, 'magic': 0, 'set': None}  # the engine checks the entry (the looser rule), then the spec
        refusal = {'level': max(base['level'], int(row['equipLevel'])), 'magic': base['magic'], 'set': R.meet(base['set'], own_set)}
        eff = {'level': max(refusal['level'], weapon['level'] if weapon else 0), 'magic': max(refusal['magic'], weapon['magic'] if weapon else 0),
               'set': R.meet(refusal['set'], weapon['set'] if weapon else None)}
    voc = row['voc']
    classes = R.read_chips(None if voc == '-' else voc)
    if refusal:
        if row['level'] < refusal['level']:
            out.append('refused: level')
        if row['magic'] < refusal['magic']:
            out.append('refused: magic level')
        if refusal['set'] is not None and classes - refusal['set']:
            out.append('refused: class')
    if weapon:
        if row['level'] < weapon['level']:
            out.append('weapon check: level')
        if row['magic'] < weapon['magic']:
            out.append('weapon check: magic level')
        if weapon['set'] is not None and classes - weapon['set']:
            out.append('weapon check: class')
    if not eff and unique:
        # O510: a unique copy of an id that has no rule at all (23 older uniques): the server asks nothing, so any level the
        # tooltip names is a level it does not ask (the audit read only the ids with a rule before)
        eff = {'level': 0, 'magic': 0, 'set': None}
    if eff:
        if row['level'] > eff['level']:
            out.append('tooltip stricter: level')
        if row['magic'] > eff['magic']:
            out.append('tooltip stricter: magic level')
        if (eff['set'] is None and classes != R.ALL_SET and voc != '-') or (eff['set'] is not None and eff['set'] - classes):
            out.append('tooltip stricter: class')
    return out


def audit(data_dir, lua=None, weapons_last=True):
    """the result of one run: {rules, items, found {(copy, id): [kind]}, rows, errors, longest}"""
    rules = R.Rules(data_dir)
    items = load_items(data_dir)
    shown, errors = run_tooltips(rules, items, data_dir, find_lua(lua), weapons_last)
    found = {}
    for (copy, iid), row in sorted(shown.items()):
        ks = kinds_of(rules, iid, row, copy == 'U')
        if ks:
            found[(copy, iid)] = ks
    for iid, _ in errors:
        found[('P', iid)] = ['tooltip error']
    longest = max(((len(r['voc']), c, i, r['voc']) for (c, i), r in shown.items() if r['voc'] != '-'), default=(0, '', 0, ''))
    return {'rules': rules, 'items': items, 'shown': shown, 'found': found, 'errors': errors, 'longest': longest}


def kind_label(copy, kind):
    return ('unique copy: ' if copy == 'U' else '') + kind


def rule_table(res):
    """the rules the audit read, as text lines"""
    rules = res['rules']
    scripts = collections.Counter(e['script'] or '(none)' for e in rules.entries)
    both = [i for i in rules.ids() if i in rules.equip and i in rules.weapons]
    differ = [i for i in both if rules.refusal(i)['level'] != rules.weapon(i)['level']
              or rules.refusal(i)['set'] != rules.weapon(i)['set']]
    lines = ['Rules read', '  Equip entries      %5d (%d ids; %d entries over an id range; %d ids with two entries)' % (
        len(rules.entries), len(rules.equip), sum(1 for e in rules.entries if len(e['ids']) > 1),
        sum(1 for v in rules.equip.values() if len(v) > 1)),
             '  with a class list  %5d' % sum(1 for e in rules.entries if e['vocs']),
             '  with a level       %5d' % sum(1 for e in rules.entries if e['level'] > 0),
             '  with a script      %5d (%s)' % (sum(n for s, n in scripts.items() if s != '(none)'),
                                              ', '.join('%s %d' % (s, n) for s, n in sorted(scripts.items()) if s != '(none)') or '-'),
             '  weapon entries     %5d (%s)' % (len(rules.weapons), ', '.join(
                 '%s %d' % (t, n) for t, n in sorted(collections.Counter(w['tag'] for w in rules.weapons.values()).items()))),
             '  with unproperly    %5d' % sum(1 for w in rules.weapons.values() if w['unproperly']),
             '  ids with both      %5d (%d with a different level or class list)' % (len(both), len(differ)),
             '  recorded stock     %5d (chaos_unique_equip.lua)' % len(rules.stock)]
    return lines


def report(res, top=20, examples=1, show=None):
    """the printed table, as a list of lines"""
    items, found, shown = res['items'], res['found'], res['shown']

    def name(iid):
        return items.get(iid, {}).get('name') or shown.get(('U', iid), {}).get('uniqueName') or '?'

    by_kind = collections.defaultdict(list)
    for (copy, iid), ks in sorted(found.items()):
        for k in ks:
            by_kind[kind_label(copy, k)].append(iid)
    lines = ['Tooltip against rule: %d tooltips read (%d plain copies, %d unique copies), %d items with a mismatch' % (
        len(shown), sum(1 for c, _ in shown if c == 'P'), sum(1 for c, _ in shown if c == 'U'), len({i for _, i in found}))]
    lines += rule_table(res)
    lines += ['', 'Mismatches by kind', '  %-40s %6s  %s' % ('kind', 'items', 'example')]
    for kind in sorted(by_kind, key=lambda k: (not fails(k), k)):
        ids = by_kind[kind]
        ex = ', '.join('%s (%d)' % (name(i), i) for i in ids[:examples])
        lines.append('  %-40s %6d  %s%s' % (kind, len(ids), ex, '  [check]' if fails(kind) else ''))
    if not by_kind:
        lines.append('  none')
    shapes = collections.OrderedDict()
    for (copy, iid), ks in sorted(found.items()):
        row = shown.get((copy, iid), {'voc': '?', 'level': 0})
        eff = res['rules'].effective(iid)
        key = (copy, tuple(ks), row['voc'], shape(eff['set']) if eff else '-')
        shapes.setdefault(key, []).append(iid)
    lines += ['', 'The %d most common shapes (kinds; the tooltip row; the effective rule as lines; one example)' % top]
    for (copy, ks, voc, truth), ids in sorted(shapes.items(), key=lambda kv: (-len(kv[1]), kv[0]))[:top]:
        lines.append('  %5d  %s%s | shows "%s" | rule %s | %s (%d)' % (len(ids), 'unique copy ' if copy == 'U' else '', ', '.join(ks),
                                                                   voc, truth, name(ids[0]), ids[0]))
    if not shapes:
        lines.append('  none')
    n, copy, iid, voc = res['longest']
    lines += ['', 'Longest class row: %d characters of %d (%s, %s copy): %s' % (n, ROW_LIMIT, '%s (%d)' % (name(iid), iid) if iid else '-', copy or '-', voc)]
    if show:
        lines += ['', 'Items of kind "%s"' % show]
        for kind, ids in sorted(by_kind.items()):
            if show in kind:
                for i in ids:
                    row = shown.get(('U' if kind.startswith('unique') else 'P', i), {})
                    lines.append('  %d  %s  shows level %s "%s"' % (i, name(i), row.get('level'), row.get('voc')))
    for iid, msg in res['errors'][:10]:
        lines.append('tooltip error: %s (%d): %s' % (name(iid), iid, msg))
    return lines


def main(argv):
    args, flags, opts = [], set(), {}
    it = iter(argv)
    for a in it:
        if a in ('--check', '--movements-last'):
            flags.add(a)
        elif a in ('--top', '--examples', '--list', '--lua'):
            opts[a] = next(it, None)
        elif a.startswith('--'):
            print(__doc__)
            return 2
        else:
            args.append(a)
    if len(args) != 1 or any(v is None for v in opts.values()) or not os.path.isdir(args[0]):
        print(__doc__)
        return 2
    res = audit(args[0], opts.get('--lua'), '--movements-last' not in flags)
    for line in report(res, int(opts.get('--top', 20)), int(opts.get('--examples', 1)), opts.get('--list')):
        print(line)
    failing = {kind_label(copy, k) for (copy, _), ks in res['found'].items() for k in ks if fails(kind_label(copy, k))}
    if res['errors']:
        return 1
    if '--check' in flags and failing:
        print('\nFAILED: %s' % ', '.join(sorted(failing)))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
