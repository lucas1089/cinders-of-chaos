#!/usr/bin/env python3
"""Install the five relic sets (owner 2026-10-30, "Aprovo, pode importar os sets como itens"; 65 pieces of PixelLab art, client pair 58)
into a base server: items.otb, items.xml, the equip entries in movements.xml and the weapon entries in weapons.xml.

usage: python3 -I install_relic_sets.py DATA_DIR [--dry-run] [--manifest CSV]
       python3 -I install_relic_sets.py --lua [--check] [--manifest CSV]   (server/data/lib/chaos_relic_sets_items.lua)

The manifest (default server/data/items/relic_sets.csv) is client/tools/sprites/import_art_things.py's --manifest-out of
client/tools/sprites/art_import/relic_sets.csv (gen_relic_sets_art.py): client ids 44446..44510 (appended to pair 58), server id =
client id + 4000 (48446..48510, the pair 50 rule), 13 pieces per set, `extra` = set, kind, fit (A anyone for the helmets, chest
armours and legs; 1 / 2 hands for melee weapons), level and description.

Every number is the equipment sets' (install_gear_sets.py `stats_of`, the same curves): a piece is 100% of the curve at its set's
level (one level per set: Venomcoil 640, Hoarglass 860, Kilnforged 1400, Halogild 1700, Deepdirge 2050), so the weapon audit's 80% rule
and the gear audit's power column hold. The element, resisted element, weak element and missiles are the set's (SETS below).
Who may wear or wield what is install_gear_sets.py's FITS: fit A pieces, boots, rings and amulets everyone; shields the Warrior,
Juggernaut and the Templar line; spellbooks the Mystic and Necromancer lines; swords, axes and hammers every melee class (the
Berserker only the two-handed axe); bows the Ranger, Deadeye and Beastmaster; the wand or rod of a set (one per set, so a set arms
every class) every caster: the Mystic, Elementalist, Illusionist and the Necromancer line.

1. items.otb: one node per row (install_pack_items.py's node rules; refused when a server id belongs to another item).
2. items.xml: the entries between two marker comments before </items>, rewritten when the manifest or a number changed.
3. movements.xml: an Equip / DeEquip pair per piece (slot, level, classes) in a marked block before </movements>. Run after the
   vocations step: the lists name the Chaos classes.
4. weapons.xml: a melee / distance / wand entry per weapon (level, classes; wands and rods damage, mana and element) in a marked
   block before </weapons>.
An id with an entry outside a block stops the script. No shop sells or buys them (the Auto Seller price comes from
tools/gen_item_prices.py). Drops, set bonuses and the transmog rule: data/lib/chaos_gear_sets.lua (it reads the generated
data/lib/chaos_relic_sets_items.lua), data/scripts/chaos/gear_sets.lua adds the loot while ChaosGearSets.PAIR58 is on.

Client pair guard (server/README.md "Client pair guard"): the items need the pair 58 client (client ids 44446-44510). While
config.lua's chaosClientPair is lower than 58 or missing the step prints a warning and writes nothing; from 58 on it installs.
Idempotent: a second run changes nothing.
"""
import os, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair  # noqa: E402
import install_gear_sets as GS  # noqa: E402
from install_pack_items import read_manifest, patch_otb, verify_otb  # noqa: E402
from install_dark_tiles import xml_escape  # noqa: E402
from install_fist_weapons import replace_block as _replace_block  # noqa: E402

REPO_DATA = os.path.join(os.path.dirname(HERE), 'data')
DEFAULT_MANIFEST = os.path.join(REPO_DATA, 'items', 'relic_sets.csv')
LUA_OUT = os.path.join(REPO_DATA, 'lib', 'chaos_relic_sets_items.lua')
FIRST, LAST = 48446, 48510
SERVER_OFFSET = 4000
BEGIN = '\t<!-- Chaos relic sets of pair 58 (server/tools/install_relic_sets.py, do not edit by hand) -->\n'
END = '\t<!-- end of the Chaos relic sets of pair 58 -->\n'
KINDS = ('helmet', 'armor', 'legs', 'boots', 'shield', 'spellbook', 'sword', 'axe', 'club', 'bow', 'wand', 'rod', 'ring', 'amulet')
# key, name, level (one per set), damage element, resisted element, weak element, wand missile, bow missile, crossbow missile
SETS = [
    ('venomcoil', 'Venomcoil', 640, 'earth', 'earth', 'fire', 'poison', 'poisonarrow', 'drillbolt'),
    ('hoarglass', 'Hoarglass', 860, 'ice', 'ice', 'fire', 'smallice', 'shiverarrow', 'prismaticbolt'),
    ('kilnforged', 'Kilnforged', 1400, 'fire', 'fire', 'ice', 'fire', 'flammingarrow', 'infernalbolt'),
    ('halogild', 'Halogild', 1700, 'holy', 'death', 'earth', 'smallholy', 'crystallinearrow', 'prismaticbolt'),
    ('deepdirge', 'Deepdirge', 2050, 'death', 'death', 'holy', 'suddendeath', 'onyxarrow', 'drillbolt'),
]
RELIC_BY_KEY = {s[0]: s for s in SETS}
# a set has one staff, so it is wielded by every caster (the stock wand is the Elementalist's, the rod the Illusionist's): a set must arm every class
STAFF_CLASSES = GS.MYSTIC + GS.NECRO
for _s in SETS:   # one pseudo set per relic set for stats_of (install_gear_sets.py reads SET_BY_KEY: key, name, band, element ...)
    GS.SET_BY_KEY.setdefault(_s[0], (_s[0], _s[1], (_s[2], _s[2])) + _s[3:9])


def rows_of(path=DEFAULT_MANIFEST):
    """the manifest rows with level, fit, classes and stats ([(items.xml key, value)]; `wand` for wands and rods) set"""
    rows = read_manifest(path)
    ids = [r['server_id'] for r in rows]
    assert len(ids) == len(set(ids)), 'duplicate server ids in the relic sets manifest'
    keys = [r['key'] for r in rows]
    assert len(keys) == len(set(keys)), 'duplicate keys in the relic sets manifest'
    for r in rows:
        ex = r['ex']
        assert r['mode'] == 'new' and r['server_id'] == r['client_id'] + SERVER_OFFSET, \
            '%s: server id must be client id + %d' % (r['key'], SERVER_OFFSET)
        assert FIRST <= r['server_id'] <= LAST, '%s: server id %d outside %d..%d' % (r['key'], r['server_id'], FIRST, LAST)
        assert ex.get('set') in RELIC_BY_KEY and r['kind'] == ex.get('kind') and r['kind'] in KINDS, '%s: set / kind' % r['key']
        assert ex.get('level', '').isdigit() and int(ex['level']) == RELIC_BY_KEY[ex['set']][2], '%s: level of the set' % r['key']
        r['level'] = int(ex['level'])
        r['ex'] = dict(ex)
        r['ex'].setdefault('fit', '')
        r['classes'] = STAFF_CLASSES if r['kind'] in ('wand', 'rod') else GS.classes_of(r)
        r['stats'] = GS.stats_of(r)
    rows.sort(key=lambda r: r['server_id'])
    return rows


# ------------------------------------------------------------------------------------------------ items.xml
def xml_item(r):
    k = r['kind']
    art = GS.article_of(r['name'])
    head = 'id="%d"%s name="%s"' % (r['server_id'], ' article="%s"' % art if art else '', xml_escape(r['name']))
    attrs = [('description', r['ex'].get('description', '')), ('weight', GS.weight_of(r))]
    if GS.weapon_type(k):
        attrs.append(('weaponType', GS.weapon_type(k)))
    if k in GS.SLOT:
        attrs.append(('slotType', GS.SLOT[k] if k != 'armor' else 'body'))
    if k in ('bow', 'crossbow') or r['ex']['fit'] == '2':
        attrs.append(('slotType', 'two-handed'))
    attrs += r['stats']
    body = ''.join('\t\t<attribute key="%s" value="%s" />\n' % (key, xml_escape(str(v))) for key, v in attrs if v != '')
    return '\t<item %s>\n%s\t</item>\n' % (head, body)


def replace_block(text, begin, end, block, root, ids, what):
    try:
        new, note = _replace_block(text, begin, end, block, root, ids, what)
    except SystemExit as e:
        raise SystemExit(str(e).replace('fist weapon block', 'relic sets block'))
    return new, note.replace('fist weapon block', 'relic sets block')


def patch_xml(text, rows):
    block = BEGIN + ''.join(xml_item(r) for r in rows) + END
    return replace_block(text, BEGIN, END, block, '</items>', [r['server_id'] for r in rows], 'items.xml')


def patch_moves(text, rows):
    block = BEGIN + ''.join(GS.move_entries(r) for r in rows) + END
    return replace_block(text, BEGIN, END, block, '</movements>', [r['server_id'] for r in rows], 'movements.xml')


def patch_weapons(text, rows):
    ws = GS.weapon_rows(rows)
    block = BEGIN + ''.join(GS.weapon_entry(r) for r in ws) + END
    return replace_block(text, BEGIN, END, block, '</weapons>', [r['server_id'] for r in ws], 'weapons.xml')


# ------------------------------------------------------------------------------------------------ Lua data
def lua_text(rows):
    L = ['-- The pieces of the five relic sets of client pair 58 (server/tools/install_relic_sets.py --lua, from',
         '-- server/data/items/relic_sets.csv). Generated; do not edit by hand. Read by data/lib/chaos_gear_sets.lua, which adds them',
         '-- to the equipment sets (same piece format as chaos_gear_sets_items.lua: id, key, set, kind, fit (A anyone, 1 / 2 hands),',
         '-- level, name, classes ({} = everyone), stats = the items.xml numbers, wandMin / wandMax / mana for wands and rods).',
         '-- The sets, sources and bonuses are in chaos_gear_sets.lua; the items exist only with the pair 58 client.',
         '', 'return {', '\tfirst = %d,' % FIRST, '\tlast = %d,' % LAST, '\tsets = {']
    for key, name, level, dmg, res, *_r in SETS:
        L.append('\t\t%s = {name = "%s", band = {%d, %d}, element = "%s", resist = "%s", relic = true},' % (key, name, level, level, dmg, res))
    L += ['\t},', '\tpieces = {']
    for r in rows:
        st = ', '.join('%s = %s' % (k, GS.lua_value(v)) for k, v in r['stats'])
        if r.get('wand'):
            st += ', wandMin = %d, wandMax = %d, mana = %d' % r['wand'][:3]
        L.append('\t\t{id = %d, key = "%s", set = "%s", kind = "%s", fit = "%s", level = %d, name = "%s", classes = {%s},'
                 % (r['server_id'], r['key'], r['ex']['set'], r['kind'], r['ex']['fit'], r['level'], r['name'],
                    ', '.join('"%s"' % c for c in r['classes'])))
        L.append('\t\t\tstats = {%s}, relic = true},' % st)
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
                print('%s is stale: run install_relic_sets.py --lua' % LUA_OUT)
                return 1
            print('chaos_relic_sets_items.lua up to date')
            return 0
        open(LUA_OUT, 'w').write(text)
        print('wrote', LUA_OUT)
        return 0
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    ok, why = client_pair.allows(data_dir, client_pair.PAIR_RELIC, 'relicsets')
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
