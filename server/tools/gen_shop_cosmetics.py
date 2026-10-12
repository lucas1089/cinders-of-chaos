#!/usr/bin/env python3
"""Write server/data/scripts/chaos/shop_cosmetics.lua: the outfits, outfit addons and mounts the store sells.

usage: python3 -I gen_shop_cosmetics.py SERVER_DATA_DIR [--check] [--list]

Reads the base server's data/XML/outfits.xml and mounts.xml (installed, with the Chaos blocks of install_outfits.py)
and leaves out everything that is an exclusive somewhere else:
  - class looks (class_looks_core.lua L.looks, and L.retired: the looks classes wore before) and the donor art class outfits (chaos_constants.lua Chaos.classes.outfits)
  - achievement rewards (achievements_data.lua: outfit female/male, mount id)
  - season track rewards (season_config.lua: outfit / addon male/female, mount id)
  - season pass and season pack rewards (seasonpass_config.lua, same shapes)
  - faction quartermaster mounts (factions_config.lua `kind = "mount"` offers)
  - the visual exclusives (exclusives_config.lua: outfit / addons male/female, mount id), achievement and boss rewards
  - EXCLUDED below: battle pass rewards of the base server, rented horses
The ascension quest gives a title only (ascension_quest_config.lua); staff outfits are not in outfits.xml.
shop.lua checks the same sources again at load (ChaosShopCore.exclusions), so a class look added later is never sold.

Pairs: the female and male entries of one outfit are paired by name (FEMALE_ALIAS for the names that differ) or by
PAIRS (outfits whose two looks have unrelated names). Outfits with unlocked="yes" (everyone has them) are sold as
"addons" offers. Prices come from TIERS (outfits by look type, mounts by client look type and speed); PRICE overrides
a single offer. Run it again after an outfit or mount is added to the XML; --check exits 1 when the file is stale.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CHAOS = os.path.join(os.path.dirname(HERE), 'data', 'scripts', 'chaos')
OUT = os.path.join(CHAOS, 'shop_cosmetics.lua')

# female name -> male name, where the two differ
FEMALE_ALIAS = {'noblewoman': 'nobleman', 'norsewoman': 'norseman', 'princess of lands': 'prince of lands',
                'honey': 'hooney'}
# (male look, female look, name): outfits whose two looks have unrelated names (base corrupted_outfit.lua)
PAIRS = [(1194, 1199, 'Corrupted Priest'), (1195, 1200, 'Corrupted Archer'), (1196, 1202, 'Corrupted Axe'),
         (1197, 1203, 'Corrupted Club'), (1198, 1204, 'Corrupted Sword'), (1224, 1201, 'Corrupted Mage')]
# shown names, where the XML name reads badly
RENAME = {'Demon Outfit': 'Demon', 'Battle mage': 'Battle Mage', 'Astral ice': 'Astral Ice', 'Hooney': 'Honey',
          'Shadowlotus Disciple': 'Shadowlotus', 'Nobleman': 'Noble', 'Norseman': 'Norse'}
# base server rewards that stay where they are: (look types, mount ids) with the reason
EXCLUDED = [
    ({1240, 1241, 1242, 1243, 1244, 1245, 1246, 1247, 1248, 1249, 1250, 1251, 1252, 1253}, set(),
     'battle pass reward (Retro outfits, base retro_box_outfit.lua)'),
    (set(), {122, 123}, 'battle pass reward (Fire Panther, Erect Raptor Drake)'),
    (set(), {22, 25, 26}, 'rented horse (temporary, base NPC)'),
]
# outfit price by the highest look type of the pair: (below, price)
OUTFIT_TIERS = [(400, 300), (900, 500), (100000, 750)]
ADDON_PRICE = 150
# mount price by client look type: (below, price); speed >= 30 is always the top tier
MOUNT_TIERS = [(500, 350), (900, 450), (1200, 550), (100000, 690)]
MOUNT_TOP = 690
PRICE = {'mount:104': 450}
# descriptions of the offers the store had before this list
DESCRIPTION = {
    'mount:121': 'A blood-red war beast.', 'mount:119': 'A wyrm of living ice.',
    'mount:141': 'A skeletal horse wreathed in grave-light.', 'mount:120': 'A tyrant of the swamps.',
    'mount:104': 'A radiant spirit steed.',
}


def read(path):
    return open(path, encoding='utf-8', errors='replace').read()


def attrs(line):
    return dict(re.findall(r'(\w+)="([^"]*)"', line))


def exclusions():
    """{'looks': {look: reason}, 'mounts': {id: reason}} from the repository's reward and class files"""
    looks, mounts = {}, {}
    text = read(os.path.join(CHAOS, 'class_looks_core.lua'))
    block = re.search(r'L\.looks = \{(.*?)\n\}', text, re.S).group(1)
    for m, f in re.findall(r'male\s*=\s*(\d+)\s*,\s*female\s*=\s*(\d+)', block):
        looks.setdefault(int(m), 'class look'); looks.setdefault(int(f), 'class look')
    # the things_custom19 class looks (L.pair19Looks): class looks once the pair 19 switch is on, never sold either way
    pair19 = re.search(r'L\.pair19Looks = \{(.*?)\n\}', text, re.S)
    for m, f in re.findall(r'male\s*=\s*(\d+)\s*,\s*female\s*=\s*(\d+)', pair19.group(1) if pair19 else ''):
        looks.setdefault(int(m), 'class look'); looks.setdefault(int(f), 'class look')
    retired = re.search(r'L\.retired = \{(.*?)\n\}', text, re.S)
    for m, f in re.findall(r'male\s*=\s*(\d+)\s*,\s*female\s*=\s*(\d+)', retired.group(1) if retired else ''):
        looks.setdefault(int(m), 'former class look'); looks.setdefault(int(f), 'former class look')
    text = read(os.path.join(CHAOS, 'chaos_constants.lua'))
    block = re.search(r'\n\toutfits = (.*?)\n\t(?:\}|end\)\(\)),?\n', text, re.S).group(1)
    for t in re.findall(r'lookType\s*=\s*(\d+)', block):
        looks.setdefault(int(t), 'class outfit (donor art)')
    for f, why in (('achievements_data.lua', 'achievement reward'), ('season_config.lua', 'season reward'),
                   ('seasonpass_config.lua', 'season pass reward'), ('exclusives_config.lua', 'exclusive (never sold)')):
        text = read(os.path.join(CHAOS, f))
        for a, b in re.findall(r'(?:fe)?male\s*=\s*(\d+)\s*,\s*(?:fe)?male\s*=\s*(\d+)', text):
            looks.setdefault(int(a), why); looks.setdefault(int(b), why)
        for i in re.findall(r'mount\s*=\s*\{[^}]*\bid\s*=\s*(\d+)', text):
            mounts.setdefault(int(i), why)
        for i in re.findall(r'kind\s*=\s*"mount"\s*,\s*id\s*=\s*(\d+)', text):
            mounts.setdefault(int(i), why)
    # faction quartermaster mounts (factions_config.lua offers: kind = "mount", ..., mount = N)
    text = read(os.path.join(CHAOS, 'factions_config.lua'))
    for i in re.findall(r'kind\s*=\s*"mount"[^}]*?\bmount\s*=\s*(\d+)', text):
        mounts.setdefault(int(i), 'faction reward')
    for ls, ms, why in EXCLUDED:
        for t in ls:
            looks.setdefault(t, why)
        for i in ms:
            mounts.setdefault(i, why)
    return {'looks': looks, 'mounts': mounts}


def tier(value, tiers):
    for below, price in tiers:
        if value < below:
            return price
    return tiers[-1][1]


def outfits(data, ex, skipped):
    female, male = {}, {}
    for line in read(os.path.join(data, 'XML', 'outfits.xml')).splitlines():
        if '<outfit ' not in line or line.strip().startswith('<!--'):
            continue
        a = attrs(line)
        if a.get('enabled', 'yes') != 'yes':
            continue
        e = {'look': int(a['looktype']), 'name': a['name'], 'premium': a.get('premium') == 'yes',
             'unlocked': a.get('unlocked') == 'yes'}
        (female if a['type'] == '0' else male)[e['look']] = e
    pairs, used_f = [], set()
    by_name_f = {}
    for e in female.values():
        n = e['name'].lower()
        by_name_f[FEMALE_ALIAS.get(n, n)] = e
    paired = {m: (f, n) for m, f, n in PAIRS}
    for m in sorted(male.values(), key=lambda e: e['look']):
        if m['look'] in paired:
            fl, name = paired[m['look']]
            f = female.get(fl)
        else:
            f, name = by_name_f.get(m['name'].lower()), m['name']
        if not f:
            skipped.append(('outfit', m['look'], m['name'], 'no female look'))
            continue
        used_f.add(f['look'])
        pairs.append((m, f, RENAME.get(name, name)))
    for f in female.values():
        if f['look'] not in used_f:
            skipped.append(('outfit', f['look'], f['name'], 'no male look'))
    full, addons = [], []
    for m, f, name in pairs:
        why = ex['looks'].get(m['look']) or ex['looks'].get(f['look'])
        if why:
            skipped.append(('outfit', m['look'], name, why))
            continue
        e = {'key': 'outfit:%d' % m['look'], 'looktype': m['look'], 'lookfemale': f['look'], 'name': name,
             'premium': m['premium'] or f['premium']}
        if m['unlocked'] and f['unlocked']:
            e['cost'] = PRICE.get(e['key'], ADDON_PRICE)
            addons.append(e)
        else:
            e['cost'] = PRICE.get(e['key'], tier(max(m['look'], f['look']), OUTFIT_TIERS))
            full.append(e)
    full.sort(key=lambda e: (-e['cost'], -e['looktype']))
    return full, addons


def mounts(data, ex, skipped):
    out = []
    for line in read(os.path.join(data, 'XML', 'mounts.xml')).splitlines():
        if '<mount ' not in line or line.strip().startswith('<!--'):
            continue
        a = attrs(line)
        i, look = int(a['id']), int(a['clientid'])
        why = ex['mounts'].get(i)
        if why:
            skipped.append(('mount', i, a['name'], why))
            continue
        key = 'mount:%d' % i
        cost = MOUNT_TOP if int(a.get('speed', '0')) >= 30 else tier(look, MOUNT_TIERS)
        out.append({'key': key, 'id': i, 'clientid': look, 'name': a['name'], 'premium': a.get('premium') == 'yes',
                    'cost': PRICE.get(key, cost)})
    out.sort(key=lambda e: (-e['cost'], -e['clientid']))
    return out


def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def render(full, addons, mts):
    lines = ['-- shop_cosmetics.lua: GENERATED by server/tools/gen_shop_cosmetics.py from the base outfits.xml and mounts.xml.',
             '-- Do not edit by hand: change the tool (tiers, names, exclusions) and run it again.',
             '-- Read by shop_config.lua (categories Outfits, Outfit Addons, Mounts). premium = the XML says premium="yes"',
             '-- (the engine lets only premium accounts wear it; shop.lua refuses the purchase without premium).',
             'return {', '\toutfits = {']
    for e in full:
        lines.append('\t\t{key = %s, looktype = %d, lookfemale = %d, name = %s, cost = %d%s},' % (
            lua_str(e['key']), e['looktype'], e['lookfemale'], lua_str(e['name']), e['cost'],
            ', premium = true' if e['premium'] else ''))
    lines += ['\t},', '\t-- outfits every character has: the two addons, for both looks', '\taddons = {']
    for e in addons:
        lines.append('\t\t{key = %s, looktype = %d, lookfemale = %d, name = %s, cost = %d%s},' % (
            lua_str('addons:%d' % e['looktype']), e['looktype'], e['lookfemale'], lua_str(e['name']), e['cost'],
            ', premium = true' if e['premium'] else ''))
    lines += ['\t},', '\tmounts = {']
    for e in mts:
        desc = DESCRIPTION.get(e['key'])
        lines.append('\t\t{key = %s, id = %d, clientid = %d, name = %s, cost = %d%s%s},' % (
            lua_str(e['key']), e['id'], e['clientid'], lua_str(e['name']), e['cost'],
            ', premium = true' if e['premium'] else '', (', description = ' + lua_str(desc)) if desc else ''))
    lines += ['\t}', '}', '']
    return '\n'.join(lines)


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1 or not os.path.isdir(os.path.join(args[0], 'XML')):
        sys.exit(__doc__)
    ex, skipped = exclusions(), []
    full, addons = outfits(args[0], ex, skipped)
    mts = mounts(args[0], ex, skipped)
    text = render(full, addons, mts)
    if '--list' in argv:
        for s in skipped:
            print('left out %s %s %s: %s' % s)
    print('outfits %d, addon sets %d, mounts %d, left out %d' % (len(full), len(addons), len(mts), len(skipped)))
    old = open(OUT, encoding='utf-8').read() if os.path.isfile(OUT) else ''
    if '--check' in argv:
        if old != text:
            print(OUT + ' is stale: run the tool')
            return 1
        return 0
    if old != text:
        open(OUT, 'w', encoding='utf-8').write(text)
        print('wrote ' + OUT)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
