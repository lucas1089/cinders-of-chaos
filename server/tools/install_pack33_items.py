#!/usr/bin/env python3
"""Install the harvest kit items of the client pair 33 (import-only third-party kit, `set33 kit`) into a base server.

usage: python3 -I install_pack33_items.py DATA_DIR [--dry-run]
       python3 -I install_pack33_items.py --manifest [--check]   (server/data/items/pack33_kit.csv from the things file)
       python3 -I install_pack33_items.py --lua [--check]        (server/data/lib/chaos_pack33_kit.lua)

The things file client/tools/sprites/art_import/pack33_kit.csv (client/tools/sprites/gen_pack33.py) lists the kit's
514 items (client ids 38093..38606) and the boss corpse (38607). --manifest turns it into the importer's manifest format
(the columns of import_art_things.py --manifest-out: client id, server id = client id + 3000, so 41093..41607; group,
flags and top order of the importer's OTB table, ground speed, light) with the review below applied, so the server side
needs no built pair. The pair itself is not built yet (client/MANIFEST.md "Pair 33 packs"); once it is, its importer
manifest must give the same client ids (--manifest --check against the things file stays the CI guard).

Review of the analysis draft (gen_pack33.py KIT_KINDS; 2026-10-21): walls, fences, corn, big props and the closed or
upright states block; decals, roofs, stairs, open doors and gates, seedlings, circles and the portal are walkable decor.
Changed here (REVIEW): the open coffin and the open sarcophagus, the dug grave and the emptied coffins block (one stands
in them, not on them). A footprint over one tile blocks only its anchor tile (bottom-right): the map blocks the others.
Timed states (DECAY, items.xml decayTo + duration; the engine starts the decay of map items at load and a script calls
item:decay() after a transform): the pumpkin growth stages, the crypt seal (breaking -> open -> sealed again), the
grave and the upright coffin after they burst, the ritual circle (lighting -> flare -> portal open -> closing ->
dormant), the portcullis, the lantern post lighting, the sliding sarcophagus lid, the tolling bell. Decoration never
uses a state with a decay (it would change on its own): data/scripts/chaos/harvest_event.lua places those.

1. data/items/items.otb: a node per row (patch_otb of install_pack_items.py: left alone when identical, replaced when
   the same group and flags, refused otherwise; items.otb.bak keeps the original the first time; parsed again).
2. data/items/items.xml: a block between two marker comments before </items> (name, article, decay; the corpse a
   container of 20 that decays away in 10 minutes). An id with an entry outside the block stops the script.
3. --lua: data/lib/chaos_pack33_kit.lua (key -> id, size, kind, blocking, light, animation, mechanic state; the decay
   chains), read by the area planner (tools/areaplan_build.lua, biomes harvest and harvest_crypt) and the event.

The items exist once the pair 33 things are in the client. ChaosHarvestArt.PAIR33 (data/lib/chaos_harvest_art.lua) is
off: the items may be installed, nothing in the game uses them (server/README.md "Haunted Harvest"). Idempotent.
"""
import csv, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_pack_items import read_manifest, patch_otb, verify_otb, xml_item as corpse_xml_item  # noqa: E402
from install_dark_tiles import xml_escape  # noqa: E402

SERVER = os.path.dirname(HERE)
REPO = os.path.dirname(SERVER)
THINGS = os.path.join(REPO, 'client', 'tools', 'sprites', 'art_import', 'pack33_kit.csv')
MANIFEST = os.path.join(SERVER, 'data', 'items', 'pack33_kit.csv')
LUA_OUT = os.path.join(SERVER, 'data', 'lib', 'chaos_pack33_kit.lua')
SWITCH = os.path.join(SERVER, 'data', 'lib', 'chaos_harvest_art.lua')
XML_BEGIN = '\t<!-- Chaos harvest kit items of pair 33 (server/tools/install_pack33_items.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos harvest kit items of pair 33 -->\n'
FIRST_CLIENT, LAST_CLIENT, OFFSET = 38093, 38607, 3000
FIRST, LAST = FIRST_CLIENT + OFFSET, LAST_CLIENT + OFFSET
HEADER = ['client_id', 'server_id', 'key', 'kind', 'mode', 'name', 'size', 'otb_group', 'otb_flags', 'top_order',
          'speed', 'light_level', 'light_color', 'extra']
# the importer's items.otb table (client/tools/sprites/import_art_things.py OTB, SOLID, ANIM)
SOLID, PICKUP, MOVE, STACK = 1, 32, 64, 128
ONTOP, HANG, ANIM, FORCEUSE = 1 << 13, 1 << 16, 1 << 24, 1 << 26
OTB = {'ground': (1, 0, 0), 'border': (0, ONTOP, 1), 'decor': (0, 0, 0), 'stump': (0, SOLID | ONTOP, 2),
       'wall': (0, HANG, 0), 'corpse': (2, FORCEUSE, 0)}
BLOCK_FLAGS = 'bottom notwalkable notmoveable'
# key (without kit__) -> kind: the review of the draft (see the docstring)
REVIEW = {'coffin_open': 'stump', 'sarcophagus_open': 'stump', 'grave_dug': 'stump',
          'grave_coffin_open_empty': 'stump', 'coffin_up_open_skeleton': 'stump'}
# timed states: key -> (key it turns into, seconds)
DECAY = {
    'pumpkin_stage_1_mound': ('pumpkin_stage_2_sprout', 90),
    'pumpkin_stage_2_sprout': ('pumpkin_stage_3_vine', 90),
    'pumpkin_stage_3_vine': ('pumpkin_stage_4_green', 120),
    'pumpkin_stage_4_green': ('pumpkin_stage_5_ripe', 120),
    'pumpkin_stage_6_lit': ('pumpkin_stage_1_mound', 8),
    'seal_breaking': ('seal_open', 1),
    'seal_open': ('seal_sealed', 240),
    'grave_dug': ('grave_coffin_closed', 2),
    'grave_coffin_bursting': ('grave_coffin_open_empty', 1),
    'grave_coffin_open_empty': ('grave_mound', 180),
    'coffin_up_opening': ('coffin_up_open_skeleton', 1),
    'coffin_up_open_skeleton': ('coffin_up_closed', 180),
    'circle_candles_lighting': ('circle_flare', 2),
    'circle_flare': ('portal_open', 1),
    'portal_open': ('portal_closing', 120),
    'portal_closing': ('circle_dormant', 1),
    'portcullis_rising_h': ('portcullis_open_h', 2),
    'portcullis_rising_v': ('portcullis_open_v', 2),
    'portcullis_open_h': ('portcullis_closed_h', 60),
    'portcullis_open_v': ('portcullis_closed_v', 60),
    'lantern_post_lighting': ('lantern_post_lit', 1),
    'sarcophagus_lid_slide': ('sarcophagus_open', 1),
    'cursed_bell_tolling': ('cursed_bell_still', 4),
}
# in-game names where the catalogue name is not one (else: the catalogue name in lower case without the variant
# number, the direction and the H / V of a wall piece)
NAMES = {
    'pumpkin_stage_1_mound': 'pumpkin mound', 'pumpkin_stage_2_sprout': 'pumpkin sprout',
    'pumpkin_stage_3_vine': 'pumpkin vine', 'pumpkin_stage_4_green': 'green pumpkin',
    'pumpkin_stage_5_ripe': 'ripe pumpkin', 'pumpkin_stage_6_lit': 'waking pumpkin',
    'circle_dormant': 'ritual circle', 'circle_candles_lighting': 'kindling ritual circle',
    'circle_flare': 'flaring ritual circle', 'portal_open': 'ritual portal', 'portal_closing': 'fading ritual portal',
    'seal_sealed': 'crypt seal', 'seal_breaking': 'breaking crypt seal', 'seal_open': 'open crypt seal',
    'grave_mound': 'fresh grave', 'grave_dug': 'dug grave', 'grave_coffin_closed': 'buried coffin',
    'grave_coffin_bursting': 'bursting coffin', 'grave_coffin_open_empty': 'empty grave',
    'candy_cauldron_full': 'candy cauldron', 'cauldron_mimic': 'cauldron mimic',
    'coffin_up_closed': 'upright coffin', 'coffin_up_opening': 'creaking coffin',
    'coffin_up_open_skeleton': 'open upright coffin', 'cursed_bell_still': 'cursed bell',
    'cursed_bell_tolling': 'tolling cursed bell', 'lantern_post_unlit': 'unlit lantern post',
    'lantern_post_lighting': 'lantern post', 'lantern_post_lit': 'lantern post',
    'gibbet_empty': 'gibbet', 'gibbet_bones': 'gibbet', 'gibbet_swing': 'creaking gibbet',
    'altar_bare': 'offering altar', 'altar_offerings': 'offering altar', 'altar_burning': 'burning offering altar',
    'corn_wall_gap_h': 'gap in the corn', 'corn_wall_gap_v': 'gap in the corn',
    # a stock item is "witch hat" (monster loot by name): a second one makes the loot name ambiguous
    'witch_hat': 'crooked witch hat',
}
VARIANT = re.compile(r'(\s(n|s|e|w|ne|nw|se|sw|in \w+|h|v|h strip|v strip|l|mid|r|[hv][12])|\s\d+|\sstrip)+$')


def switch_on(path=SWITCH):
    if not os.path.isfile(path):
        return False
    return re.search(r'^M\.PAIR33\s*=\s*true\b', open(path, encoding='utf-8').read(), re.M) is not None


def extra_of(text):
    return dict(p.split('=', 1) for p in (text or '').split('|') if '=' in p)


def short(key):
    return key[5:] if key.startswith('kit__') else key


def game_name(key, name, kind, family=''):
    k = short(key)
    if k in NAMES:
        return NAMES[k]
    if kind == 'corpse':
        return name
    n = name.lower()
    n = re.sub(r'^(catacomb stairs) (up|down) .*$', r'\1', n)
    n = VARIANT.sub('', n).strip()
    n = re.sub(r'^(.+) on (.+)$', r'\1 edge', n) if kind == 'border' else n
    if family == 'roofs':
        return 'dark shingle roof' if n.startswith('dark shingle') else 'rusty tin roof'
    n = re.sub(r' [ab]$', '', n)
    n = re.sub(r'^jack lantern \w+$', "jack-o'-lantern", n)
    n = {'sarcophagus closed': 'sarcophagus', 'well old': 'old well', 'birch bare': 'bare birch',
         'bone pile large': 'large bone pile', 'urn large': 'large urn', 'dead tree gnarled': 'gnarled dead tree',
         'dead tree small': 'small dead tree', 'pumpkin big': 'big pumpkin', 'pumpkin giant': 'giant pumpkin',
         'pumpkin rotten': 'rotten pumpkin', 'pumpkin small': 'small pumpkin', 'signpost crooked': 'crooked signpost',
         'crypt small': 'small crypt', 'bones small': 'small bones', 'corn single': 'corn stalk',
         'broom leaning': 'leaning broom', 'crows ground': 'crows', 'puddle crypt': 'puddle', 'puddle moon': 'puddle',
         'candles cluster': 'candles', 'leaves orange': 'fallen leaves', 'leaves red': 'fallen leaves',
         'coffin open': 'open coffin', 'sarcophagus open': 'open sarcophagus',
         'sarcophagus lid slide': 'sarcophagus', 'portcullis rising': 'portcullis', 'portcullis closed': 'portcullis',
         'portcullis open': 'open portcullis'}.get(n, n)
    if family in ('walls', 'cata_walls') and not any(w in n for w in ('door', 'window', 'wall', 'portcullis')):
        n = re.sub(r'^(.+?)( post| corner| end| broken| hayloft)?$', lambda m: m.group(1) + ' wall' + (m.group(2) or ''), n)
    elif family == 'fences' and not any(w in n for w in ('fence', 'gate', 'rail')):
        n = re.sub(r'^(.+?)( post| corner| end)?$', lambda m: m.group(1) + ' fence' + (m.group(2) or ''), n)
    return n


def manifest_rows(things=THINGS):
    """the things file -> manifest rows (lists of the HEADER columns); the review applied"""
    out = []
    for r in csv.DictReader(open(things, newline='', encoding='utf-8')):
        if r['cat'] != 'item':
            continue
        ex = extra_of(r['extra'])
        cid = int(ex['id'])
        assert FIRST_CLIENT <= cid <= LAST_CLIENT, '%s: client id %d outside the kit block' % (r['key'], cid)
        kind = REVIEW.get(short(r['key']), r['kind'])
        flags = r['flags']
        if kind == 'stump' and r['kind'] != 'stump':
            flags = BLOCK_FLAGS + ''.join(' ' + t for t in flags.split() if t.startswith(('light:', 'animate')))
        toks = {t.split(':')[0]: t.split(':')[1:] for t in flags.split()}
        g, fl, top = OTB[kind]
        if 'notwalkable' in toks:
            fl |= SOLID
        phases = sum(int(p) for p in str(r['phases'] or '1').split('+'))
        if phases > 1:
            fl |= ANIM
        speed = int(toks['ground'][0]) if 'ground' in toks else 0
        light = tuple(int(v) for v in toks['light']) if 'light' in toks else (0, 0)
        size = ex.get('footprint') or '%sx%s' % (r['w'], r['h'])
        keep = [p for p in r['extra'].split('|') if p.split('=', 1)[0] not in ('id', 'footprint')]
        k = short(r['key'])
        if k in DECAY:
            keep.append('decay=%s:%d' % DECAY[k])
        if kind != r['kind']:
            keep.append('review=%s' % r['kind'])
        out.append([cid, cid + OFFSET, k, kind, "new", game_name(r["key"], r["name"], kind, ex.get("family", "")), size, g, fl, top, speed,
                    light[0], light[1], '|'.join(keep)])
    out.sort(key=lambda x: x[0])
    ids = [x[0] for x in out]
    assert ids == list(range(FIRST_CLIENT, LAST_CLIENT + 1)), 'the kit items are not one run %d..%d' % (
        FIRST_CLIENT, LAST_CLIENT)
    keys = {x[2] for x in out}
    for k, (to, s) in DECAY.items():
        assert k in keys and to in keys and s > 0, 'decay %s -> %s: unknown key' % (k, to)
    for k in REVIEW:
        assert k in keys, 'review: unknown key %s' % k
    return out


def manifest_text(rows):
    import io
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator='\n')
    w.writerow(HEADER)
    for r in rows:
        w.writerow(r)
    return buf.getvalue()


def load_rows(path=MANIFEST):
    rows = read_manifest(path)
    for r in rows:
        assert r['server_id'] == r['client_id'] + OFFSET and FIRST <= r['server_id'] <= LAST, r['key']
        if r['kind'] == 'stump':
            assert r['otb_flags'] & SOLID, '%s: a stump blocks' % r['key']
        elif r['kind'] == 'decor':
            assert not r['otb_flags'] & SOLID, '%s: decor does not block' % r['key']
        elif r['kind'] == 'wall':
            assert r['otb_flags'] & HANG, '%s: a wall item is hangable' % r['key']
        elif r['kind'] == 'ground':
            assert r['otb_group'] == 1, '%s: a ground is in the ground group' % r['key']
    return rows


def article(name):
    return 'an' if name[0].lower() in 'aeiou' else 'a'


def by_key(rows):
    return {r['key']: r for r in rows}


def xml_row(r, keys):
    if r['kind'] == 'corpse':
        return corpse_xml_item(r)
    name = r['name']
    plain = r['kind'] in ('ground', 'border') or name.startswith(('gap ',))
    head = '\t<item id="%d"%s name="%s"' % (r['server_id'], '' if plain else ' article="%s"' % article(name),
                                            xml_escape(name))
    dec = r['ex'].get('decay')
    if not dec:
        return head + ' />\n'
    to, sec = dec.split(':')
    return head + '>\n\t\t<attribute key="decayTo" value="%d" />\n\t\t<attribute key="duration" value="%s" />\n\t</item>\n' % (
        keys[to]['server_id'], sec)


def patch_xml(text, rows):
    keys = by_key(rows)
    block = XML_BEGIN + ''.join(xml_row(r, keys) for r in rows) + XML_END
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: pair 33 kit block start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for r in rows:
        sid = r['server_id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the pair 33 kit block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: pair 33 kit block up to date (%d items)' % len(rows)
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: pair 33 kit block rewritten (%d items)' % len(rows)
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: pair 33 kit block added (%d items)' % len(rows)


def lq(s):
    return '"%s"' % s.replace('\\', '\\\\').replace('"', '\\"')


def lua_text(rows):
    keys = by_key(rows)
    L = ['-- Server ids of the harvest kit items of the client pair 33 (server/tools/install_pack33_items.py --lua, from',
         '-- server/data/items/pack33_kit.csv). Generated; do not edit by hand. Read by tools/areaplan_build.lua (biomes',
         '-- harvest and harvest_crypt) and data/scripts/chaos/harvest_event*.lua; used in the game only while',
         '-- ChaosHarvestArt.PAIR33 (data/lib/chaos_harvest_art.lua) is on. Plain Lua (Lua 5.1 / LuaJIT and 5.3).', '',
         'return {', '\tfirst = %d,' % FIRST, '\tlast = %d,' % LAST,
         '\t-- key = {id, w, h (footprint, anchored bottom-right), kind, block, light, anim (phases), family, name}',
         '\titems = {']
    states = {}
    for r in rows:
        w, h = (int(v) for v in r['size'].split('x'))
        ex = r['ex']
        L.append('\t\t%s = {id = %d, w = %d, h = %d, kind = %s, block = %s, light = %d, anim = %s, family = %s, name = %s},' % (
            r['key'], r['server_id'], w, h, lq(r['kind']), 'true' if r['otb_flags'] & SOLID else 'false',
            r['light_level'], 'true' if r['otb_flags'] & ANIM else 'false', lq(ex.get('family', r['kind'])),
            lq(r['name'])))
        mech = ex.get('mechanic')
        if mech and mech != 'event_decor':
            st = ex.get('state') or ex.get('stage')
            states.setdefault(mech, []).append((st, r['server_id']))
    L += ['\t},', '\t-- mechanic -> state -> id (the event mechanics of the kit)', '\tstates = {']
    for m in sorted(states):
        L.append('\t\t%s = {%s},' % (m, ', '.join('[%s] = %d' % (lq(s), i) for s, i in states[m])))
    L += ['\t},', '\t-- id -> {to, seconds} (items.xml decayTo / duration of the timed states)', '\tdecay = {']
    for r in rows:
        dec = r['ex'].get('decay')
        if dec:
            to, sec = dec.split(':')
            L.append('\t\t[%d] = {to = %d, seconds = %s}, -- %s -> %s' % (r['server_id'], keys[to]['server_id'], sec,
                                                                          r['key'], to))
    L += ['\t}', '}', '']
    return '\n'.join(L)


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
    check = '--check' in args
    if '--manifest' in args:
        return write_or_check(MANIFEST, manifest_text(manifest_rows()), check, 'install_pack33_items.py --manifest')
    if '--lua' in args:
        return write_or_check(LUA_OUT, lua_text(load_rows()), check, 'install_pack33_items.py --lua')
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    otb = os.path.join(args[0], 'items', 'items.otb')
    xml = os.path.join(args[0], 'items', 'items.xml')
    if not os.path.exists(otb) or not os.path.exists(xml):
        print('items.otb / items.xml not found in', os.path.join(args[0], 'items'))
        return 1
    rows = load_rows()
    raw = open(otb, 'rb').read()
    new, c = patch_otb(raw, rows)
    n = verify_otb(new, rows)
    print('items.otb: %d nodes added, %d updated; verified (%d item nodes)' % (c['new'], c['updated'], n))
    text = open(xml, encoding='utf-8', errors='surrogateescape').read()
    new_text, note = patch_xml(text, rows)
    print(note)
    print('switch ChaosHarvestArt.PAIR33 is %s' % ('on' if switch_on() else 'off (the items exist but nothing uses them)'))
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
