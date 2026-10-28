#!/usr/bin/env python3
"""Install the 34 weapons above level 800 (owner 2026-10-28, "pode criar mais armas pros levels acima de 800"; nine bows, four
crossbows, nine wands, nine rods, a two-handed sword, axe and maul) into a base server: items.otb, items.xml, the equip entries
in movements.xml and the weapon entries in weapons.xml.

usage: python3 -I install_weapons800.py DATA_DIR [--dry-run] [--manifest CSV]
       python3 -I install_weapons800.py --lua [--check] [--manifest CSV]   (server/data/lib/chaos_weapons800.lua)

The manifest (default server/data/items/weapons800.csv) is client/tools/sprites/import_art_things.py's --manifest-out of
client/tools/sprites/art_import/weapons800.csv (gen_weapons800_art.py): client ids 44412..44445 (appended to pair 56), server id =
client id + 4000 (48412..48445, the pair 50 rule), `extra` = type (bow, crossbow, wand, rod, sword2, axe2, club2), level, element,
loot (monster:chance per 100000; ...) and description.

Every number is the equipment sets' (install_gear_sets.py `stats_of`, the same curves): a weapon is 100% of the tier of its own
level, so the weapon audit's 80% rule holds. Bows and crossbows fire without ammunition like every launcher (attack and hit chance
are the sets' curve, the element picks the missile), wands and rods get their damage, mana, element and range from the curve, the
two-handed melee weapons 3000 ms interval and 35% of the attack as the element. Who may wield what (FITS of install_gear_sets.py):
two-handed melee every melee class (the Berserker included), bows the Ranger line and the Beastmaster, crossbows the Ranger line only,
wands the Mystic, Elementalist and Necromancer lines, rods the Mystic, Illusionist and Necromancer lines.

1. items.otb: one node per row (install_pack_items.py's node rules; refused when a server id belongs to another item).
2. items.xml: the entries between two marker comments before </items>, rewritten when the manifest or a number changed.
3. movements.xml: an Equip / DeEquip pair per weapon (slot hand, level, classes) in a marked block before </movements>. Run after
   the vocations step: the lists name the Chaos classes.
4. weapons.xml: a melee / distance / wand entry per weapon (level, classes; wands and rods damage, mana and element) in a marked
   block before </weapons>.
An id with an entry outside a block stops the script. No shop sells or buys them (the Auto Seller price comes from
tools/gen_item_prices.py). Drop: data/scripts/chaos/weapons800.lua adds the `loot` rows to the monster types at startup, and the
bases are in the families of data/lib/chaos_class_loot.lua (bow, crossbow, wand, rod, melee2h); they are NOT in the equipment sets'
level gear pool (ChaosGearSets.levelDrop) so the set weapons keep their drop chance.

Client pair guard (server/README.md "Client pair guard"): the items need the pair 56 client (client ids 44412-44445). While
config.lua's chaosClientPair is lower than 56 or missing the step prints a warning and writes nothing; from 56 on it installs.
Idempotent: a second run changes nothing.
"""
import os, re, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair  # noqa: E402
import install_gear_sets as GS  # noqa: E402
from install_pack_items import read_manifest, patch_otb, verify_otb  # noqa: E402
from install_dark_tiles import xml_escape  # noqa: E402
from install_fist_weapons import replace_block as _replace_block  # noqa: E402

REPO_DATA = os.path.join(os.path.dirname(HERE), 'data')
DEFAULT_MANIFEST = os.path.join(REPO_DATA, 'items', 'weapons800.csv')
LUA_OUT = os.path.join(REPO_DATA, 'lib', 'chaos_weapons800.lua')
FIRST, LAST = 48412, 48445
SERVER_OFFSET = 4000
BEGIN = '\t<!-- Chaos weapons above level 800 (server/tools/install_weapons800.py, do not edit by hand) -->\n'
END = '\t<!-- end of the Chaos weapons above level 800 -->\n'
TYPES = ('bow', 'crossbow', 'wand', 'rod', 'sword2', 'axe2', 'club2')
KIND_OF = {'bow': 'bow', 'crossbow': 'crossbow', 'wand': 'wand', 'rod': 'rod', 'sword2': 'sword', 'axe2': 'axe', 'club2': 'club'}
# the class loot family of a type (data/lib/chaos_class_loot.lua L.bases)
FAMILY_OF = {'bow': 'bow', 'crossbow': 'crossbow', 'wand': 'wand', 'rod': 'rod', 'sword2': 'melee2h', 'axe2': 'melee2h',
             'club2': 'melee2h'}
# the element of a weapon: the sets' damage element, resisted element, weak element and missiles of the set that has it
ELEMENT_SET = {'fire': 'cinderwrought', 'earth': 'wyrmscale', 'ice': 'rimewraith', 'holy': 'azurevigil', 'death': 'bloodmoon',
               'energy': 'gildcrown'}
WEIGHT = {'bow': 3100, 'crossbow': 4000, 'wand': 1900, 'rod': 2400, 'sword2': 6500, 'axe2': 7000, 'club2': 7500}
MIN_LEVEL, MAX_LEVEL = 800, 2400
BAND_MAX_LOOT = 100000
for _el, _src in ELEMENT_SET.items():   # one pseudo set per element for stats_of (no leech: it is Bloodmoon's alone)
    GS.SET_BY_KEY['w800_' + _el] = ('w800_' + _el, 'weapons above 800', (MIN_LEVEL, MAX_LEVEL)) + GS.SET_BY_KEY[_src][3:9]


def rows_of(path=DEFAULT_MANIFEST):
    """the manifest rows with level, element, classes, stats ([(items.xml key, value)]), `wand` and `loot` set; sorted by level"""
    rows = read_manifest(path)
    ids = [r['server_id'] for r in rows]
    assert len(ids) == len(set(ids)), 'duplicate server ids in the weapons800 manifest'
    keys = [r['key'] for r in rows]
    assert len(keys) == len(set(keys)), 'duplicate keys in the weapons800 manifest'
    for r in rows:
        ex = r['ex']
        assert r['mode'] == 'new' and r['server_id'] == r['client_id'] + SERVER_OFFSET, \
            '%s: server id must be client id + %d' % (r['key'], SERVER_OFFSET)
        assert FIRST <= r['server_id'] <= LAST, '%s: server id %d outside %d..%d' % (r['key'], r['server_id'], FIRST, LAST)
        assert ex.get('type') in TYPES and KIND_OF[ex['type']] == r['kind'], '%s: type %s / kind %s' % (r['key'], ex.get('type'), r['kind'])
        assert ex.get('element') in ELEMENT_SET, '%s: element %s' % (r['key'], ex.get('element'))
        assert ex.get('level', '').isdigit() and MIN_LEVEL < int(ex['level']) <= MAX_LEVEL, '%s: level' % r['key']
        r['level'] = int(ex['level'])
        r['type'] = ex['type']
        r['element'] = ex['element']
        r['fit'] = '2' if ex['type'] in ('sword2', 'axe2', 'club2') else ''
        r['ex'] = dict(ex, fit=r['fit'], set='w800_' + ex['element'])   # what install_gear_sets.py's helpers read
        r['classes'] = GS.FITS[ex['type']]
        r['stats'] = GS.stats_of(r)
        r['loot'] = []
        for part in filter(None, (ex.get('loot') or '').split(';')):
            mon, chance = part.rsplit(':', 1)
            assert 0 < int(chance) <= BAND_MAX_LOOT, r['key']
            r['loot'].append((mon.strip(), int(chance)))
        assert r['loot'], '%s: no monster loot (the weapon audit counts a weapon only with a source)' % r['key']
    rows.sort(key=lambda r: (r['level'], r['server_id']))
    return rows


# ------------------------------------------------------------------------------------------------ items.xml
def xml_item(r):
    t = r['type']
    name = r['name']
    art = GS.article_of(name)
    head = 'id="%d"%s name="%s"' % (r['server_id'], ' article="%s"' % art if art else '', xml_escape(name))
    attrs = [('description', r['ex'].get('description', '')), ('weight', WEIGHT[t]), ('weaponType', GS.weapon_type(r['kind']))]
    if t in ('bow', 'crossbow', 'sword2', 'axe2', 'club2'):
        attrs.append(('slotType', 'two-handed'))
    attrs += r['stats']
    body = ''.join('\t\t<attribute key="%s" value="%s" />\n' % (k, xml_escape(str(v))) for k, v in attrs if v != '')
    return '\t<item %s>\n%s\t</item>\n' % (head, body)


def replace_block(text, begin, end, block, root, ids, what):
    try:
        new, note = _replace_block(text, begin, end, block, root, ids, what)
    except SystemExit as e:
        raise SystemExit(str(e).replace('fist weapon block', 'weapons800 block'))
    return new, note.replace('fist weapon block', 'weapons800 block')


def patch_xml(text, rows):
    block = BEGIN + ''.join(xml_item(r) for r in rows) + END
    return replace_block(text, BEGIN, END, block, '</items>', [r['server_id'] for r in rows], 'items.xml')


def patch_moves(text, rows):
    block = BEGIN + ''.join(GS.move_entries(r) for r in rows) + END
    return replace_block(text, BEGIN, END, block, '</movements>', [r['server_id'] for r in rows], 'movements.xml')


def patch_weapons(text, rows):
    block = BEGIN + ''.join(GS.weapon_entry(r) for r in rows) + END
    return replace_block(text, BEGIN, END, block, '</weapons>', [r['server_id'] for r in rows], 'weapons.xml')


# ------------------------------------------------------------------------------------------------ Lua data
def lua_value(v):
    return '"%s"' % v if isinstance(v, str) else str(v)


def lua_text(rows):
    L = ['-- The weapons above level 800 (server/tools/install_weapons800.py --lua, from server/data/items/weapons800.csv).',
         '-- Generated; do not edit by hand. Needs the pair 56 client (client ids 44412-44445, gen_weapons800_art.py) and the',
         '-- `weapons800` install step, which waits for config.lua chaosClientPair >= 56 (README "Client pair guard").',
         '-- ids: the server ids by level; items[id]: key, name, type, family (the class loot family), level, element, classes',
         '-- ({} = everyone), stats (the items.xml numbers, wandMin / wandMax / mana for wands and rods); loot: {monster, item id,',
         '-- chance per 100000} added to the monster types at startup (data/scripts/chaos/weapons800.lua). The bases are also in',
         '-- data/lib/chaos_class_loot.lua L.bases (tests/class_loot_test.lua checks they agree).', '',
         'return {', '\tfirst = %d,' % FIRST, '\tlast = %d,' % LAST, '\tids = {%s},' % ', '.join(str(r['server_id']) for r in rows),
         '\titems = {']
    for r in rows:
        st = ', '.join('%s = %s' % (k, lua_value(v)) for k, v in r['stats'])
        if r.get('wand'):
            st += ', wandMin = %d, wandMax = %d, mana = %d' % r['wand'][:3]
        L.append('\t\t[%d] = {key = "%s", name = "%s", type = "%s", family = "%s", level = %d, element = "%s", classes = {%s},' % (
            r['server_id'], r['key'], r['name'], r['type'], FAMILY_OF[r['type']], r['level'], r['element'],
            ', '.join('"%s"' % c for c in r['classes'])))
        L.append('\t\t\tstats = {%s}},' % st)
    L += ['\t},', '\tloot = {']
    for r in rows:
        for mon, chance in r['loot']:
            L.append('\t\t{"%s", %d, %d},' % (mon, r['server_id'], chance))
    L += ['\t}', '}', '']
    return '\n'.join(L)


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    dry = '--dry-run' in args
    manifest = DEFAULT_MANIFEST
    if '--manifest' in args:
        i = args.index('--manifest'); manifest = args[i + 1]; del args[i:i + 2]
    rows = rows_of(manifest)
    if '--lua' in args:
        text = lua_text(rows)
        if '--check' in args:
            if not os.path.isfile(LUA_OUT) or open(LUA_OUT).read() != text:
                print('%s is stale: run install_weapons800.py --lua' % LUA_OUT)
                return 1
            print('chaos_weapons800.lua up to date')
            return 0
        open(LUA_OUT, 'w').write(text)
        print('wrote', LUA_OUT)
        return 0
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    ok, why = client_pair.allows(data_dir, client_pair.PAIR_W800, 'weapons800')
    print(why)
    if not ok:
        return 0
    paths = {'otb': os.path.join(data_dir, 'items', 'items.otb'), 'xml': os.path.join(data_dir, 'items', 'items.xml'),
             'moves': os.path.join(data_dir, 'movements', 'movements.xml'),
             'weapons': os.path.join(data_dir, 'weapons', 'weapons.xml')}
    for p in paths.values():
        if not os.path.exists(p):
            print('not found:', p)
            return 1
    raw = open(paths['otb'], 'rb').read()
    new_otb, c = patch_otb(raw, rows)
    n = verify_otb(new_otb, rows)
    print('items.otb: %d nodes added, %d updated; verified (%d item nodes)' % (c['new'], c['updated'], n))
    texts, news = {}, {}
    for key, fn in (('xml', patch_xml), ('moves', patch_moves), ('weapons', patch_weapons)):
        texts[key] = open(paths[key], encoding='utf-8', errors='surrogateescape').read()
        news[key], note = fn(texts[key], rows)
        print(note)
    if dry:
        print('dry run: nothing written')
        return 0
    if new_otb != raw:
        if not os.path.exists(paths['otb'] + '.bak'):
            shutil.copy2(paths['otb'], paths['otb'] + '.bak')
        open(paths['otb'], 'wb').write(new_otb)
    for key in news:
        if news[key] != texts[key]:
            open(paths[key], 'w', encoding='utf-8', errors='surrogateescape', newline='').write(news[key])
    return 0


if __name__ == '__main__':
    sys.exit(main())
