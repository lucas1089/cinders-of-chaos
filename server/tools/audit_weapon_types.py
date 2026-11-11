#!/usr/bin/env python3
"""Audit the weaponType of the stock weapons against what the item is by its name (O500, server/README.md "Stock weapon types (O500)").

usage: python3 -I server/tools/audit_weapon_types.py DATA_DIR [--table FILE] [--check] [--quiet]

Owner, 2026-11-11: "The item counts as an axe, but it is not." The tooltip said "Two-handed axe" for the Twin Hooks, a pair of hooked
blades. The weapon kind (items.xml weaponType: sword, axe, club) drives the skill, the family trait (sword tempo, axe cleave, club
daze), the modifiers a weapon may roll, the coverage tables and the tooltip's type line, so a wrong one shows in many places.

DATA_DIR is the data/ folder of a base server (the installed one or a copy: items/items.xml, weapons/weapons.xml and
XML/vocations.xml). Read only. Prints three lists:
  CLEAR  the name says one kind and the type another (the head noun of the name or plural: axe, hatchet, cleaver, halberd; sword, blade,
         sabre, rapier, dagger, knife; club, mace, hammer, staff, flail, maul; compounds such as greataxe or warhammer count). The
         ones not in the patch table (data/items/stock_weapon_types.csv) fail --check.
  ODD    no kind word in the name. A name with a hint word (hooks, claw, sickle, scythe, whip, lance, glaive, trident, ...) gets the
         kind the rule of the table gives it (HINTS below) and the reason; a name with no word at all keeps its type ("no clue").
         Items the patch table already moves, or keeps on purpose (new type = old type), are marked.
  SPEED  items whose `attackspeed` differs from the default interval (2000 ms is the engine's reference: an item without the
         attribute swings at its vocation's own interval, one with it at attackspeed x vocation / 2000), with the swing the
         vocations of its weapons.xml entry get from it. tools/two_handed.py gives two-handed weapons 1.5 x (3000 ms) on purpose.
Only melee kinds are judged (weaponType sword, axe, club); launchers, wands and thrown weapons have kinds of their own.
Exit 0; with --check 1 when a CLEAR mismatch is missing from the table."""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import survey_base_weapons as SV  # noqa: E402

TABLE = os.path.join(SERVER, 'data', 'items', 'stock_weapon_types.csv')
FIRST_CHAOS_ID = SV.FIRST_CHAOS_ID
DEFAULT_INTERVAL = 2000
SLOW_FROM = 2500

# the words, by head noun. A word in SUFFIX also counts at the end of a longer word (greataxe, longsword, warhammer, skullcrusher).
SWORD = {'sword', 'blade', 'sabre', 'saber', 'rapier', 'katana', 'scimitar', 'dagger', 'knife', 'dirk', 'epee', 'machete', 'claymore',
         'falchion', 'cutlass', 'stiletto', 'kris', 'shiv', 'kunai', 'sai', 'slicer', 'masterblade'}
AXE = {'axe', 'hatchet', 'cleaver', 'chopper', 'choppa', 'halberd', 'splitter'}
CLUB = {'club', 'mace', 'hammer', 'staff', 'flail', 'maul', 'sceptre', 'scepter', 'cudgel', 'bludgeon', 'truncheon', 'bat', 'basher',
        'mallet', 'cane', 'klubba', 'crusher', 'breaker', 'smasher', 'squelcher', 'stomper', 'whopper', 'crowbar', 'fists', 'fist'}
SUFFIX = {'sword', 'blade', 'axe', 'hammer', 'club', 'mace', 'staff', 'maul', 'slicer', 'chopper', 'crusher', 'breaker', 'basher',
          'squelcher', 'stomper', 'whopper', 'cleaver', 'hatchet', 'halberd', 'flail', 'sabre', 'dagger', 'knife', 'sceptre'}
KIND_OF = {}
for _k, _words in (('sword', SWORD), ('axe', AXE), ('club', CLUB)):
    for _w in _words:
        KIND_OF[_w] = _k

# odd things: word -> (kind, reason). The rule of O500: a bladed or hooked thing held like a sword is a sword; a hafted chopping head is
# an axe; anything blunt or a staff is a club; polearms follow their head (halberd axe; lances, glaives and tridents: the kind the stock
# data gives most of them, axe).
HINTS = {
    'hook': ('sword', 'hooked blades held like swords'), 'hooks': ('sword', 'hooked blades held like swords'),
    'claw': ('sword', 'a clawed blade held like a sword'), 'claws': ('sword', 'clawed blades held like swords'),
    'talon': ('sword', 'a bladed claw held like a sword'), 'fang': ('sword', 'a fang-shaped blade held like a sword'),
    'sickle': ('sword', 'a curved hooked blade held in one hand like a sword'),
    'scythe': ('sword', 'a long curved blade, not a chopping head'),
    'whip': ('club', 'not bladed or hafted; no whip kind, blunt strike'),
    'lance': ('axe', 'polearm; the stock data gives most polearms (halberds, lances, naginata) the axe'),
    'glaive': ('axe', 'polearm; the stock data gives most polearms the axe'),
    'naginata': ('axe', 'polearm; the stock data gives most polearms the axe'),
    'drakinata': ('axe', 'polearm; the stock data gives most polearms the axe'),
    'trident': ('axe', 'polearm; the stock data gives most polearms the axe'),
    'pike': ('axe', 'polearm; the stock data gives most polearms the axe'),
    'impaler': ('axe', 'polearm; the stock data gives most polearms the axe'),
    'spear': ('axe', 'polearm; the stock data gives most polearms the axe'),
    'pick': ('axe', 'a hafted head, like a chopping head'), 'pickaxe': ('axe', 'a hafted head'),
    'wrench': ('club', 'blunt tool'), 'broom': ('club', 'a staff-like haft'), 'rod': ('club', 'a staff-like haft'),
    'lyre': ('club', 'blunt instrument'), 'lute': ('club', 'blunt instrument'), 'harp': ('club', 'blunt instrument'),
    'flute': ('club', 'blunt instrument'), 'horn': ('club', 'blunt instrument'), 'guitar': ('club', 'blunt instrument'),
    'fencing': ('sword', 'a fencing blade held like a sword'), 'quill': ('sword', 'a fencing blade held like a sword'),
}


def words(text):
    return re.findall(r"[a-z]+", text.lower().replace("'", ''))


def word_kind(w):
    if w in KIND_OF:
        return KIND_OF[w]
    for suf in SUFFIX:
        if w.endswith(suf) and len(w) > len(suf):
            return KIND_OF[suf]
    return None


def kind_by_name(name):
    """(kind, word) from the head noun of a name; None when no word of the kinds is in it. The head is the part before ' of ' (a
    'blade of corruption' is a blade); the last word of it counts first, then the ones before it."""
    low = (name or '').lower().replace("'", '')
    head = re.split(r'\s+of\s+', low, maxsplit=1)[0]
    ws = words(head)
    if 'morning' in ws and 'star' in ws:
        return 'club', 'morning star'
    for w in reversed(ws):
        k = word_kind(w)
        if k:
            return k, w
    return None


def hint_by_name(name):
    for w in words((name or '').lower()):
        if w in HINTS:
            return w, HINTS[w][0], HINTS[w][1]
    return None


def read_table(path):
    """id -> {name, old, new, reason}"""
    out = {}
    if not os.path.isfile(path):
        return out
    with open(path, encoding='utf-8', newline='') as f:
        for row in csv.DictReader(f):
            out[int(row['id'])] = row
    return out


def read_heads(items_xml):
    out = {}
    for m in re.finditer(r'<item\s+([^>]*?)(/?)>', items_xml):
        head = dict(SV.ATTR.findall(m.group(1)))
        if head.get('id', '').isdigit():
            out[int(head['id'])] = head
    return out


def vocation_speeds(vocations_xml):
    return {n: int(s) for n, s in re.findall(r'<vocation\b[^>]*?\bname="([^"]+)"[^>]*?\battackspeed="(\d+)"', vocations_xml)}


def audit(data_dir, table=None):
    """{'clear': [...], 'odd': [...], 'speed': [...]}: each row a dict. Reads items.xml (and weapons.xml, vocations.xml for the speeds)"""
    table = read_table(TABLE) if table is None else table
    items_xml = SV.read(os.path.join(data_dir, 'items', 'items.xml'))
    heads = read_heads(items_xml)
    items = SV.weapon_items(items_xml)
    weapons_path = os.path.join(data_dir, 'weapons', 'weapons.xml')
    entries = SV.weapon_entries(SV.read(weapons_path)) if os.path.isfile(weapons_path) else {}
    voc_path = os.path.join(data_dir, 'XML', 'vocations.xml')
    vocs = vocation_speeds(SV.read(voc_path)) if os.path.isfile(voc_path) else {}
    clear, odd, speed = [], [], []
    for wid in sorted(items):
        a = items[wid]['attrs']
        wt = a['weapontype'].lower()
        h = heads.get(wid, {})
        name = items[wid]['name']
        two = a.get('slottype', '').lower() == 'two-handed'
        row = {'id': wid, 'name': name, 'type': wt, 'hands': 2 if two else 1, 'stock': wid < FIRST_CHAOS_ID,
               'in_table': wid in table}
        if wt in ('sword', 'axe', 'club'):
            found = kind_by_name(name)
            if found is None and h.get('plural'):
                found = kind_by_name(h['plural'])
            if found is not None:
                kind, word = found
                if kind != wt:
                    clear.append(dict(row, kind=kind, word=word))
            else:
                hint = hint_by_name(name)
                if hint:
                    word, kind, why = hint
                    odd.append(dict(row, kind=kind, word=word, reason=why))
                else:
                    odd.append(dict(row, kind=wt, word='', reason='no clue in the name'))
        # the interval: only the weapons that have an entry (the others are scenery or items of the Chaos tools)
        if 'attackspeed' in a and a['attackspeed'].isdigit() and int(a['attackspeed']) != DEFAULT_INTERVAL and wt in (
                'sword', 'axe', 'club', 'distance'):
            ms = int(a['attackspeed'])
            names = (entries.get(wid) or {}).get('classes', [])
            swings = sorted(set(ms * vocs[n] // 2000 for n in names if n in vocs))
            speed.append(dict(row, ms=ms, swings=swings))
    return {'clear': clear, 'odd': odd, 'speed': speed}


def render(res, quiet=False):
    lines = []
    clear, odd, speed = res['clear'], res['odd'], res['speed']
    lines.append('CLEAR mismatches (the name says one kind, the type another): %d' % len(clear))
    for r in clear:
        lines.append('  %6d  %-34s type %-5s name says %-5s (%s)%s%s' % (
            r['id'], r['name'], r['type'], r['kind'], r['word'], '' if r['stock'] else '  CHAOS ITEM',
            '  in the table' if r['in_table'] else '  NOT in the table'))
    hinted = [r for r in odd if r['word']]
    clue = [r for r in odd if not r['word']]
    lines.append('ODD items (no kind word in the name): %d, of them %d with a hint word, %d with no clue' % (len(odd), len(hinted), len(clue)))
    for r in hinted:
        verdict = 'keep' if r['kind'] == r['type'] else 'move to %s' % r['kind']
        lines.append('  %6d  %-34s type %-5s hint %-8s -> %-5s (%s: %s)%s' % (
            r['id'], r['name'], r['type'], r['word'], r['kind'], verdict, r['reason'], '  in the table' if r['in_table'] else ''))
    if not quiet:
        for r in clue:
            lines.append('  %6d  %-34s type %-5s no clue, keep' % (r['id'], r['name'], r['type']))
    by = {}
    for r in speed:
        by.setdefault(r['ms'], []).append(r)
    lines.append('SPEED: %d items carry an attackspeed other than %d ms: %s' % (
        len(speed), DEFAULT_INTERVAL, ', '.join('%d ms x %d' % (ms, len(v)) for ms, v in sorted(by.items()))))
    for r in speed:
        if quiet and r['hands'] == 2 and r['ms'] >= SLOW_FROM:
            continue
        lines.append('  %6d  %-34s %d ms  %s-handed  swing %s ms for its classes' % (
            r['id'], r['name'], r['ms'], r['hands'], '-'.join(str(x) for x in (r['swings'][:1] + r['swings'][-1:] if len(r['swings']) > 1 else r['swings'])) or '?'))
    slow = [r for r in speed if r['ms'] > SLOW_FROM]
    lines.append('SLOW (over %d ms): %d, of them %d two-handed' % (SLOW_FROM, len(slow), sum(1 for r in slow if r['hands'] == 2)))
    return lines


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    table = None
    if '--table' in argv:
        i = argv.index('--table')
        table = read_table(argv[i + 1])
        args = [a for a in args if a != argv[i + 1]]
    if len(args) != 1:
        print(__doc__)
        return 2
    res = audit(args[0], table)
    print('\n'.join(render(res, '--quiet' in argv)))
    if '--check' in argv:
        missing = [r for r in res['clear'] if r['stock'] and not r['in_table']]
        if missing:
            print('FAIL: %d clear mismatch(es) not in %s' % (len(missing), os.path.relpath(TABLE, os.path.dirname(SERVER))))
            return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
