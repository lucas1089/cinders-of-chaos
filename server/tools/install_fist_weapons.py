#!/usr/bin/env python3
"""Install the Monk line's fist weapons into a base server: items.otb, items.xml, the Monk-only equip entries in
movements.xml and the NPC shops.

usage: python3 -I install_fist_weapons.py DATA_DIR [--dry-run] [--manifest CSV]
       python3 -I install_fist_weapons.py --lua [--manifest CSV]   (rewrites server/data/lib/chaos_fist_weapons.lua)

The manifests (default server/data/items/fist_items.csv and fist_claws.csv; --manifest CSV reads that one alone):
  fist_items.csv   written by client/tools/sprites/import_art_things.py (--manifest-out) from
                   client/tools/sprites/art_import/fist_weapons.csv: mode `new`, client ids 33654..33659 (appended after the
                   store pouch looks), server id = client id + 3000 (36654..36659)
  fist_claws.csv   written by hand (owner 2026-10-23, "o monk nao tem armas"): mode `donor`, the 15 "claw" looks that the
                   donor B import already put in the pair (client ids 28000.., server id = client id + 12000, 40000..;
                   install_donor_items.py keeps their items.otb nodes and leaves their items.xml entries to this tool), so
                   the Monk's claw weapons need no new sprites and no client update
Both: name, and in `extra`: article, plural, weight, attack, defense, level, NPC prices (buy: NPCs sell it; sell: NPCs buy
it), loot (monster:chance per 100000; ...), description, unique (the item is the base of a unique of
data/items/chaos_items.xml and is in no shop or loot).
Without the matching client pair (client/MANIFEST.md "Fist weapons and bone effects") the items show as nothing.

A fist weapon is a hand item of weaponType "shield" with an attack (no stock shield has one): it goes in the shield
hand (the left hand only takes real weapons on this server), the engine still fights with fists (Weapon::useFist), and
monk_combat.lua / the Monk spells use its attack instead of the level-based fist attack when it is higher
(ChaosMonk.cfg.unarmed.fistWeapons). Its defense is a shield's defense; data/lib/chaos_item_mods.lua rolls weapon
modifiers on it.

1. data/items/items.otb: one node per row (install_pack_items.py's node layout: group 0, pickupable + moveable),
   appended at the end of the root; a node already there with the same bytes is left alone, one with the same group
   and flags is replaced (the client ids moved), anything else with that server id stops the script. items.otb.bak keeps
   the original the first time; the written file is parsed again and every node checked.
2. data/items/items.xml: the entries (article, name, plural, weight, description, weaponType shield, attack, defense)
   between two marker comments before </items>, rewritten when the manifest changed. An id with an entry outside the
   block stops the script.
3. data/movements/movements.xml: an Equip / DeEquip pair per item (slot shield, its level, the Monk line: Monk,
   Shadowfist, Iron Sage) between two marker comments before </movements>. The engine shows "It can only be wielded
   properly by monks of level N or higher" from it and refuses the item to everyone else.
4. NPC shops (data/npc/*.xml, `shop_buyable` / `shop_sellable` parameters): every weapon dealer (a buy list with the
   stock battle hammer, 2417: the town weapon shops) sells the rows with a `buy` price and buys back those rows at their
   `sell` price; the desert trader Grimgan buys every row with a `sell` price that no weapon dealer buys. Entries are added once (found by
   their id) and never changed afterwards. tools/gen_sell_prices.py picks the prices up for the Auto Seller.

Loot: data/scripts/chaos/fist_weapons.lua adds the `loot` rows to the monster types at startup (MonsterType:addLoot,
from data/lib/chaos_fist_weapons.lua); no monster file is changed. Idempotent: a second run changes nothing.
"""
import os, re, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_pack_items import read_manifest, patch_otb, verify_otb  # noqa: E402
from install_dark_tiles import xml_escape  # noqa: E402

REPO_DATA = os.path.join(os.path.dirname(HERE), 'data')
DEFAULT_MANIFESTS = [os.path.join(REPO_DATA, 'items', 'fist_items.csv'), os.path.join(REPO_DATA, 'items', 'fist_claws.csv')]
DEFAULT_MANIFEST = DEFAULT_MANIFESTS[0]
# server id = client id + this, by manifest mode (new: the pack importer's items; donor: the donor B looks of the pair)
ID_OFFSET = {'new': 3000, 'donor': 12000}
LUA_OUT = os.path.join(REPO_DATA, 'lib', 'chaos_fist_weapons.lua')
XML_BEGIN = '\t<!-- Chaos fist weapons (server/tools/install_fist_weapons.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos fist weapons -->\n'
MOVE_BEGIN = '\t<!-- Chaos fist weapons: Monk line only (server/tools/install_fist_weapons.py, do not edit by hand) -->\n'
MOVE_END = '\t<!-- end of the Chaos fist weapons -->\n'
MONK_LINE = ['Monk', 'Shadowfist', 'Iron Sage']
DEALER = re.compile(r'battle hammer\s*,\s*2417\s*,', re.I)
# the desert trader of the base server (Grimgan since the npcnames step; sha256 of his old file name)
TRADER = ('Grimgan', 'e1611e79c955724155c98b4d79dbc11406cd387773935da008cad6e854b36166')


def rows_of(paths):
    """the rows of one manifest or a list of them, each with its loot list, sorted by (level, server id)"""
    if isinstance(paths, str):
        paths = [paths]
    rows = []
    for path in paths:
        if os.path.exists(path):
            rows += read_manifest(path)
    ids = [r['server_id'] for r in rows]
    assert len(ids) == len(set(ids)), 'duplicate server ids in the fist weapon manifests'
    for r in rows:
        assert r['mode'] in ID_OFFSET and r['kind'] == 'weapon', r['key']
        assert r['server_id'] == r['client_id'] + ID_OFFSET[r['mode']], \
            'server id must be client id + %d (%s)' % (ID_OFFSET[r['mode']], r['key'])
        for k in ('weight', 'attack', 'defense', 'level'):
            assert r['ex'].get(k, '').isdigit(), '%s: %s missing' % (r['key'], k)
        r['loot'] = []
        for part in filter(None, (r['ex'].get('loot') or '').split(';')):
            mon, chance = part.rsplit(':', 1)
            r['loot'].append((mon.strip(), int(chance)))
    rows.sort(key=lambda r: (int(r['ex']['level']), r['server_id']))
    return rows


# ------------------------------------------------------------------------------------------------ items.xml
def xml_item(r):
    ex = r['ex']
    head = 'id="%d" article="%s" name="%s" plural="%s"' % (r['server_id'], xml_escape(ex.get('article', 'a')),
                                                         xml_escape(r['name']), xml_escape(ex.get('plural', r['name'])))
    attrs = [('description', ex.get('description', '')), ('weight', ex['weight']), ('weaponType', 'shield'),
             ('attack', ex['attack']), ('defense', ex['defense'])]
    body = ''.join('\t\t<attribute key="%s" value="%s" />\n' % (k, xml_escape(v)) for k, v in attrs if v != '')
    return '\t<item %s>\n%s\t</item>\n' % (head, body)


def replace_block(text, begin, end, block, root, ids, what):
    s = text.find(begin)
    if s >= 0:
        e = text.find(end, s)
        if e < 0:
            raise SystemExit('%s: start marker without end marker' % what)
        outside = text[:s] + text[e + len(end):]
    else:
        outside = text
    for sid in ids:
        if re.search(r'(?:\bid|itemid)="%d"' % sid, outside):
            raise SystemExit('%s: id %d already has an entry outside the fist weapon block; nothing written' % (what, sid))
        for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside):
            if int(a) <= sid <= int(b):
                raise SystemExit('%s: id %d is inside a range entry; nothing written' % (what, sid))
    if s >= 0:
        if text[s:e + len(end)] == block:
            return text, '%s: fist weapon block up to date' % what
        return text[:s] + block + text[e + len(end):], '%s: fist weapon block rewritten' % what
    at = text.rfind(root)
    if at < 0:
        raise SystemExit('%s: no %s' % (what, root))
    return text[:at] + block + text[at:], '%s: fist weapon block added' % what


def drop_donor_entries(text, rows):
    """the donor step's bare `<item id=".." name="claw N" />` entries of the claw rows leave the donor block (a server that
    ran the donor step before this tool took them over); the donor step no longer writes them"""
    for r in rows:
        if r['mode'] == 'donor':
            text = re.sub(r'[ \t]*<item id="%d" name="[^"]*" />\n' % r['server_id'], '', text)
    return text


def patch_xml(text, rows):
    text = drop_donor_entries(text, rows)
    block = XML_BEGIN + ''.join(xml_item(r) for r in rows) + XML_END
    return replace_block(text, XML_BEGIN, XML_END, block, '</items>', [r['server_id'] for r in rows], 'items.xml')


# ------------------------------------------------------------------------------------------------ movements.xml
def move_entries(r):
    voc = ''.join('\t\t<vocation name="%s"%s />\n' % (v, '' if v == MONK_LINE[0] else ' showInDescription="0"')
                  for v in MONK_LINE)
    return ('\t<movevent event="Equip" itemid="%d" slot="shield" level="%s" function="onEquipItem">\n%s\t</movevent>\n'
            '\t<movevent event="DeEquip" itemid="%d" slot="shield" function="onDeEquipItem" />\n'
            % (r['server_id'], r['ex']['level'], voc, r['server_id']))


def patch_moves(text, rows):
    block = MOVE_BEGIN + ''.join(move_entries(r) for r in rows) + MOVE_END
    return replace_block(text, MOVE_BEGIN, MOVE_END, block, '</movements>', [r['server_id'] for r in rows],
                         'movements.xml')


# ------------------------------------------------------------------------------------------------ NPC shops
def add_entries(text, key, entries):
    """append 'name,id,price' entries to a shop parameter; an id already listed is left as it is"""
    m = re.search(r'(<parameter\s+key="%s"\s+value=")([^"]*)(")' % key, text)
    if not m:
        return text, 0
    val = m.group(2)
    new = [e for sid, e in entries if not re.search(r',\s*%d\s*,' % sid, val)]
    if not new:
        return text, 0
    stripped = val.rstrip()
    sep = '' if not stripped or stripped.endswith(';') else ';'
    tail = val[len(stripped):]
    val2 = stripped + sep + ''.join(e + ';' for e in new) + tail
    return text[:m.start(2)] + val2 + text[m.end(2):], len(new)


def shop_name(r):
    return r['name']


def patch_npcs(npc_dir, rows, dry):
    buy = [r for r in rows if r['ex'].get('buy') and not r['ex'].get('unique')]
    sell = [r for r in rows if r['ex'].get('sell')]
    dealer_sell = [r for r in sell if r['ex'].get('buy')]
    trader_sell = [r for r in sell if not r['ex'].get('buy')]
    notes, changed = [], {}
    if not os.path.isdir(npc_dir):
        return ['npc: no data/npc folder, shops skipped'], changed
    dealers = 0
    import base_rename_lib
    trader = base_rename_lib.npc_file(npc_dir, *TRADER)
    for fn in sorted(os.listdir(npc_dir)):
        if not fn.endswith('.xml'):
            continue
        path = os.path.join(npc_dir, fn)
        text = open(path, encoding='utf-8', errors='surrogateescape').read()
        bm = re.search(r'<parameter\s+key="shop_buyable"\s+value="([^"]*)"', text)
        new = text
        n = 0
        if bm and DEALER.search(bm.group(1)):
            dealers += 1
            new, a = add_entries(new, 'shop_buyable', [(r['server_id'], '%s,%d,%s' % (shop_name(r), r['server_id'], r['ex']['buy']))
                                                      for r in buy])
            new, b = add_entries(new, 'shop_sellable', [(r['server_id'], '%s,%d,%s' % (shop_name(r), r['server_id'], r['ex']['sell']))
                                                       for r in dealer_sell])
            n = a + b
        elif fn == trader:
            new, n = add_entries(new, 'shop_sellable', [(r['server_id'], '%s,%d,%s' % (shop_name(r), r['server_id'], r['ex']['sell']))
                                                        for r in trader_sell])
        if new != text:
            changed[path] = new
            notes.append('npc %s: %d shop entries added' % (fn[:-4], n))
    notes.append('npc: %d weapon dealers sell %s; Grimgan buys %s' % (dealers, ', '.join(r['name'] for r in buy),
                                                                 ', '.join(r['name'] for r in trader_sell)))
    return notes, changed


# ------------------------------------------------------------------------------------------------ Lua data
def lua_text(rows):
    L = ['-- The Monk line\'s fist weapons (server/tools/install_fist_weapons.py --lua, from server/data/items/fist_items.csv and',
         '-- fist_claws.csv). Generated; do not edit by hand. The items exist after the "fistweapons" install step and need',
         '-- the matching client pair (client/tools/sprites/import_art_things.py with art_import/fist_weapons.csv for the',
         '-- 3665x items; the 4000x claws use looks the pair has already: donor B claws 1-13).',
         '-- ids: the server ids by level (the same list as ChaosMonk.cfg.unarmed.fistWeapons); items[id]: key, name, attack,',
         '-- defense, level; loot: {monster, item id, chance per 100000} added to the monster types at startup',
         '-- (data/scripts/chaos/fist_weapons.lua).', '', 'ChaosFistWeapons = {', '\tids = {%s},' % ', '.join(
             str(r['server_id']) for r in rows), '\titems = {']
    for r in rows:
        L.append('\t\t[%d] = {key = "%s", name = "%s", attack = %s, defense = %s, level = %s%s},' % (
            r['server_id'], r['key'], r['name'].replace('"', '\\"'), r['ex']['attack'], r['ex']['defense'], r['ex']['level'],
            ', unique = "%s"' % r['ex']['unique'] if r['ex'].get('unique') else ''))
    L += ['\t},', '\tloot = {']
    for r in rows:
        for mon, chance in r['loot']:
            L.append('\t\t{"%s", %d, %d},' % (mon, r['server_id'], chance))
    L += ['\t}', '}', '']
    return '\n'.join(L)


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    manifest = DEFAULT_MANIFESTS
    if '--manifest' in args:
        i = args.index('--manifest'); manifest = args[i + 1]; del args[i:i + 2]
    rows = rows_of(manifest)
    if '--lua' in args:
        open(LUA_OUT, 'w').write(lua_text(rows))
        print('wrote', LUA_OUT)
        return 0
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    moves = os.path.join(data_dir, 'movements', 'movements.xml')
    for p in (otb, xml, moves):
        if not os.path.exists(p):
            print('not found:', p)
            return 1
    raw = open(otb, 'rb').read()
    new_otb, c = patch_otb(raw, rows)
    n = verify_otb(new_otb, rows)
    print('items.otb: %d nodes added, %d updated; verified (%d item nodes)' % (c['new'], c['updated'], n))
    text = open(xml, encoding='utf-8', errors='surrogateescape').read()
    new_xml, note = patch_xml(text, rows)
    print(note)
    mtext = open(moves, encoding='utf-8', errors='surrogateescape').read()
    new_moves, mnote = patch_moves(mtext, rows)
    print(mnote)
    notes, npcs = patch_npcs(os.path.join(data_dir, 'npc'), rows, dry)
    for x in notes:
        print(x)
    if dry:
        print('dry run: nothing written')
        return 0
    if new_otb != raw:
        if not os.path.exists(otb + '.bak'):
            shutil.copy2(otb, otb + '.bak')
        open(otb, 'wb').write(new_otb)
    if new_xml != text:
        open(xml, 'w', encoding='utf-8', errors='surrogateescape').write(new_xml)
    if new_moves != mtext:
        open(moves, 'w', encoding='utf-8', errors='surrogateescape').write(new_moves)
    for path, t in npcs.items():
        open(path, 'w', encoding='utf-8', errors='surrogateescape').write(t)
    return 0


if __name__ == '__main__':
    sys.exit(main())
