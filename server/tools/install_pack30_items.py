#!/usr/bin/env python3
"""Install the items of the client pair 30 (third-party art packs, import-only) into a base server.

usage: python3 -I install_pack30_items.py DATA_DIR [--dry-run] [--items-dir DIR]
       python3 -I install_pack30_items.py --lua [--check] [--items-dir DIR]          (server/data/lib/chaos_pack30_items.lua)
       python3 -I install_pack30_items.py --hideout-lua [--check] [--items-dir DIR]  (server/data/scripts/chaos/hideout_pack30_config.lua)

The manifests are written by the importer (client/tools/sprites/import_art_things.py --manifest-out), one per category:
server/data/items/pack30_<cat>.csv (items, looks' corpses, strips' corpses, grounds, decor, bldg, anim, a second building
file for the overflow, ...). Every file whose header starts with client_id,server_id,key is read (other pack30_*.csv, such as
the outfit table, are not item manifests and are skipped). No manifest yet: nothing to install, the generated files are empty
and --check passes; add the files and run again.
Client ids from 34443; server id = client id + 3000. Allowed server ids 37443..39999 (the clean run; 37000..37442 are the
equipment sets) and 40113..65535 (the overflow range after the donor items 40000..40112). Blocks (client ids): items-A..D
34443..34758, corpses 34759..34858, grounds 34859..35158, decor 35159..36058, buildings 36059..36458, animated 36459..36758.
Rows with extra blank=1 (or mode=blank) only pad the block to its next id: they get no items.otb / items.xml entry.
Row rules (checked, a failure stops before anything is written): ids as above, no id twice, kind weapons (sword, axe, club,
bow, ... weapon) pickupable, flask stackable and pickupable, wall hangable, stump blocking, decor not blocking, ground
in the ground group. A server id that already belongs to another item stops the script.

1. data/items/items.otb: a node per row (patch_otb of install_pack_items.py: left alone when identical, replaced when the
   same group and flags, refused otherwise; items.otb.bak keeps the original the first time; the result is parsed again).
2. data/items/items.xml: a block between two marker comments before </items> (name, article, description
   "A <kind> from the pack art (pair 30)."; corpses: container size 20, decay 0, duration 600, corpse type by race).
   An id with an entry outside the block stops the script.
3. --lua: data/lib/chaos_pack30_items.lua (key -> server id, size, kind; groups of big art with their pieces for the
   gallery). --hideout-lua: the decoration catalogue entries of the Hideout (README "Pack art (pair 30)").

The items exist once the pair 30 things are in the client. ChaosPack30Art.PAIR30 (data/lib/chaos_pack30_art.lua) is off:
the items may be installed, nothing in the game uses them. Idempotent.
"""
import csv, glob, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_pack_items import read_manifest, patch_otb, verify_otb, xml_item as corpse_xml_item  # noqa: E402
from install_dark_tiles import xml_escape  # noqa: E402

REPO_DATA = os.path.join(os.path.dirname(HERE), 'data')
ITEMS_DIR = os.path.join(REPO_DATA, 'items')
LUA_OUT = os.path.join(REPO_DATA, 'lib', 'chaos_pack30_items.lua')
HIDEOUT_OUT = os.path.join(REPO_DATA, 'scripts', 'chaos', 'hideout_pack30_config.lua')
SWITCH = os.path.join(REPO_DATA, 'lib', 'chaos_pack30_art.lua')
XML_BEGIN = '\t<!-- Chaos pack art items of pair 30 (server/tools/install_pack30_items.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos pack art items of pair 30 -->\n'
# allowed server ids: clean run, then the overflow range after the donor items 40000..40112
RANGES = ((37443, 39999), (40113, 65535))
# otb flag bits
SOLID, PICKUPABLE, STACKABLE, HANGABLE = 1, 32, 128, 1 << 16
WEAPON_KINDS = ('sword', 'axe', 'club', 'bow', 'crossbow', 'wand', 'rod', 'weapon', 'spear', 'dagger', 'staff', 'mace',
                'hammer', 'shield')
HIDEOUT_PRICE = {(1, 1): 80, (1, 2): 120, (2, 1): 120, (2, 2): 200}
HIDEOUT_CATS = (  # first match of a key word wins
    ('rug', ('rug', 'carpet', 'mat')),
    ('banner', ('banner', 'flag', 'pennant')),
    ('light', ('torch', 'candle', 'lamp', 'lantern', 'brazier', 'fire', 'light', 'chandelier')),
    ('macabre', ('bone', 'bones', 'skull', 'skeleton', 'coffin', 'grave', 'tomb', 'sarcophagus', 'gibbet')),
    ('statue', ('statue', 'gargoyle', 'idol', 'totem', 'obelisk', 'bust')),
    ('nature', ('tree', 'bush', 'flower', 'plant', 'rock', 'grass', 'shrub', 'mushroom', 'stone', 'log', 'hay')),
    ('furniture', ('table', 'chair', 'bed', 'chest', 'barrel', 'throne', 'stove', 'shelf', 'cabinet', 'desk', 'bench',
                   'crate', 'cart', 'stool', 'wardrobe', 'bookcase')),
)


def pair30_on(path=SWITCH):
    if not os.path.isfile(path):
        return False
    return re.search(r'^M\.PAIR30\s*=\s*true\b', open(path, encoding='utf-8').read(), re.M) is not None


def manifest_files(items_dir=ITEMS_DIR):
    out = []
    for p in sorted(glob.glob(os.path.join(items_dir, 'pack30_*.csv'))):
        with open(p, newline='') as f:
            head = f.readline().strip().split(',')
        if head[:3] == ['client_id', 'server_id', 'key']:
            out.append(p)
    return out


def allowed(sid):
    return any(a <= sid <= b for a, b in RANGES)


def is_blank(r):
    return r['mode'] == 'blank' or r['ex'].get('blank') == '1'


def check_row(r, src):
    k = r['key']
    assert r['server_id'] == r['client_id'] + 3000, '%s: %s: server id must be client id + 3000' % (src, k)
    assert allowed(r['server_id']), '%s: %s: server id %d outside %s' % (src, k, r['server_id'], RANGES)
    assert r['mode'] == 'new', '%s: %s: mode must be new' % (src, k)
    assert r['name'].strip(), '%s: %s: no name' % (src, k)
    fl, kind = r['otb_flags'] or 0, r['kind']
    if kind in WEAPON_KINDS:
        assert fl & PICKUPABLE, '%s: %s: a %s must be pickupable' % (src, k, kind)
    elif kind == 'flask':
        assert fl & PICKUPABLE and fl & STACKABLE, '%s: %s: a flask is pickupable and stackable' % (src, k)
    elif kind == 'wall':
        assert fl & HANGABLE, '%s: %s: a wall item is hangable' % (src, k)
    elif kind == 'stump':
        assert fl & SOLID, '%s: %s: a stump blocks' % (src, k)
    elif kind == 'decor':
        assert not fl & SOLID, '%s: %s: decor does not block' % (src, k)
    elif kind in ('ground', 'water'):
        assert r['otb_group'] == 1, '%s: %s: a ground is in the ground group' % (src, k)


def load_rows(paths):
    """real rows (blank padding dropped) of every manifest, each tagged with its file"""
    rows, sids, keys = [], {}, {}
    for p in paths:
        src = os.path.basename(p)
        for r in read_manifest(p):
            if is_blank(r):
                continue
            check_row(r, src)
            assert r['server_id'] not in sids, '%s: %s: server id %d is also %s (%s)' % (
                src, r['key'], r['server_id'], sids[r['server_id']][1], sids[r['server_id']][0])
            assert r['key'] not in keys, '%s: key %s is also in %s' % (src, r['key'], keys[r['key']])
            sids[r['server_id']] = (src, r['key'])
            keys[r['key']] = src
            r['src'] = src
            rows.append(r)
    rows.sort(key=lambda r: r['server_id'])
    return rows


def article(name):
    return 'an' if name[0].lower() in 'aeiou' else 'a'


def xml_row(r):
    if r['kind'] == 'corpse':
        return corpse_xml_item(r)
    desc = 'A %s from the pack art (pair 30).' % r['kind']
    return '\t<item id="%d" article="%s" name="%s">\n\t\t<attribute key="description" value="%s" />\n\t</item>\n' % (
        r['server_id'], article(r['name']), xml_escape(r['name']), xml_escape(desc))


def patch_xml(text, rows):
    block = XML_BEGIN + ''.join(xml_row(r) for r in rows) + XML_END
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: pair 30 block start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for r in rows:
        sid = r['server_id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the pair 30 block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: pair 30 block up to date (%d items)' % len(rows)
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: pair 30 block rewritten (%d items)' % len(rows)
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: pair 30 block added (%d items)' % len(rows)


def lq(s):
    return '"%s"' % s.replace('\\', '\\\\').replace('"', '\\"')


def size_of(r):
    m = re.match(r'^(\d+)x(\d+)$', r['size'] or '')
    assert m, '%s: size %r is not WxH' % (r['key'], r['size'])
    return int(m.group(1)), int(m.group(2))


def lua_text(rows):
    L = ['-- Server ids of the third-party pack art items of the client pair 30 (server/tools/install_pack30_items.py --lua,',
         '-- from server/data/items/pack30_*.csv). Generated; do not edit by hand. Used by data/lib/chaos_pack30_art.lua and',
         '-- the admin gallery, and only while its switch ChaosPack30Art.PAIR30 is on.', '',
         'return {', '\tfirst = 37443,', '\t-- key = {id, size w x h, kind, name}', '\titems = {']
    groups = {}
    for r in rows:
        w, h = size_of(r)
        L.append('\t\t[%s] = {id = %d, w = %d, h = %d, kind = %s, name = %s},' % (
            lq(r['key']), r['server_id'], w, h, lq(r['kind']), lq(r['name'])))
        g = r['ex'].get('group')
        if g:
            gw, gh = int(r['ex'].get('gw', 0)), int(r['ex'].get('gh', 0))
            pr, pc = (int(x) for x in r['ex']['piece'].split(','))
            groups.setdefault(g, {'gw': gw, 'gh': gh, 'p': []})['p'].append((pr, pc, r['server_id']))
    L += ['\t},', '\t-- group = {gw, gh (tiles of the whole), pieces = {{row, col, id}, ...}} (big art cut in pieces of 4x4 at most)',
          '\tgroups = {']
    for g in sorted(groups):
        d = groups[g]
        ps = ', '.join('{%d, %d, %d}' % p for p in sorted(d['p']))
        L.append('\t\t[%s] = {gw = %d, gh = %d, pieces = {%s}},' % (lq(g), d['gw'], d['gh'], ps))
    L += ['\t}', '}', '']
    return '\n'.join(L)


def hideout_cat(key):
    words = set(w for w in re.split(r'[^a-z0-9]+', key.lower()) if w)
    for cat, kws in HIDEOUT_CATS:
        if words & set(kws):
            return cat
    return 'furniture'


def hideout_ok(r):
    """flag hideout=1 in, hideout=0 out; otherwise decor-block items of 2x2 at most, kind decor or stump, no pieces"""
    f = r['ex'].get('hideout')
    if f == '0' or r['ex'].get('group'):
        return False
    if f == '1':
        return True
    return r['src'].startswith('pack30_decor') and size_of(r) <= (2, 2) and r['kind'] in ('decor', 'stump') \
        and r['ex'].get('low') != '1'


def hideout_text(rows):
    L = ['-- Hideout decorations of the third-party pack art of the client pair 30 (server/tools/install_pack30_items.py',
         '-- --hideout-lua, from server/data/items/pack30_*.csv). Generated; do not edit by hand. A list of entries of the',
         '-- format of data/scripts/chaos/hideout_config.lua `decorations`, appended by it; keys are stored in the',
         '-- database: never renamed. Prices are placeholders (1x1 80, 1x2 / 2x1 120, 2x2 200).', '', 'return {']
    seen, out = set(), []
    for r in rows:
        if not hideout_ok(r):
            continue
        w, h = size_of(r)
        assert w <= 2 and h <= 2, '%s: hideout item larger than 2x2' % r['key']
        key = 'p30_' + re.sub(r'[^a-z0-9_]+', '_', r['key'].lower())
        assert key not in seen, 'hideout key %s twice' % key
        seen.add(key)
        name = r['name'].title()
        cat = 'wall' if r['kind'] == 'wall' else hideout_cat(r['key'] + ' ' + r['name'])
        price = HIDEOUT_PRICE[(w, h)]
        src = 'source = {type = "store", price = %d}' % price
        if r['kind'] == 'wall':
            out.append('\t{key = %s, name = %s, cat = "wall", layer = "wall", wall = {n = %d, w = %d}, %s}' % (
                lq(key), lq(name), r['server_id'], r['server_id'], src))
        else:
            layer = 'floor' if cat == 'rug' else 'object'
            blk = ', block = true' if r['kind'] == 'stump' and layer == 'object' else ''
            out.append('\t{key = %s, name = %s, cat = %s, layer = "%s", ids = {%d}%s, %s}' % (
                lq(key), lq(name), lq(cat), layer, r['server_id'], blk, src))
    L.append(',\n'.join(out))
    L += ['}', '']
    return '\n'.join(L).replace('return {\n\n}', 'return {\n}')


def write_or_check(path, text, check, tool):
    if check:
        if not os.path.isfile(path) or open(path, encoding='utf-8').read() != text:
            print('%s is stale: run %s' % (path, tool))
            return 1
        print('%s up to date' % os.path.basename(path))
        return 0
    open(path, 'w', encoding='utf-8', newline='').write(text)
    print('wrote', path)
    return 0


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    items_dir = ITEMS_DIR
    if '--items-dir' in args:
        i = args.index('--items-dir')
        items_dir = args[i + 1]
        del args[i:i + 2]
    rows = load_rows(manifest_files(items_dir))
    check = '--check' in args
    if '--lua' in args:
        return write_or_check(LUA_OUT, lua_text(rows), check, 'install_pack30_items.py --lua')
    if '--hideout-lua' in args:
        return write_or_check(HIDEOUT_OUT, hideout_text(rows), check, 'install_pack30_items.py --hideout-lua')
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    otb = os.path.join(args[0], 'items', 'items.otb')
    xml = os.path.join(args[0], 'items', 'items.xml')
    if not os.path.exists(otb) or not os.path.exists(xml):
        print('items.otb / items.xml not found in', os.path.join(args[0], 'items'))
        return 1
    if not rows:
        print('pack30: no manifests (server/data/items/pack30_*.csv) yet; nothing to install')
        return 0
    raw = open(otb, 'rb').read()
    new, c = patch_otb(raw, rows)
    n = verify_otb(new, rows)
    print('items.otb: %d nodes added, %d updated; verified (%d item nodes)' % (c['new'], c['updated'], n))
    text = open(xml, encoding='utf-8', errors='surrogateescape').read()
    new_text, note = patch_xml(text, rows)
    print(note)
    print('switch ChaosPack30Art.PAIR30 is %s' % ('on' if pair30_on() else 'off (the items exist but nothing uses them)'))
    if dry:
        print('dry run: nothing written')
        return 0
    if new != raw:
        if not os.path.exists(otb + '.bak'):
            open(otb + '.bak', 'wb').write(raw)
        open(otb, 'wb').write(new)
    if new_text != text:
        open(xml, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new_text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
