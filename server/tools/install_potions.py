#!/usr/bin/env python3
"""Potions (server/README.md "Potions"): no empty flasks, the Everfull health and mana potions.

usage: python3 -I install_potions.py DATA_DIR [--dry-run]

Everything is read from server/data/scripts/chaos/potions_config.lua (`everfull`, `flasks`, `flaskText`), the file the
Lua side (potions.lua, data/lib/chaos_potions.lua) uses too.

1. data/items/items.otb: per Everfull potion a copy of the stock node `sourceId` (7618 health potion, 7620 mana
   potion: group, flags, every attribute, the stock look) with the server id `id` (32085, 32086), stackable like the
   stock node (the 10.98 client reads a count for a stackable look; see install_store_food.py). A node already there
   with the same bytes is left alone, one with other bytes is replaced; a server id that belongs to another client id
   stops the script (nothing is written). items.otb.bak keeps the original the first time.
2. data/items/items.xml: the entries (article, name, plural, description "Never runs out. ...", weight) between two
   marker comments before </items>, rewritten when the config changed. An id with an entry outside the block stops the
   script. The flask entries (7634-7636): a description sentence about a deposit is removed (the config's flaskText
   when nothing is left).
3. No flasks: in every base Lua file under data/actions and data/scripts (not the Chaos folders) a statement that
   adds an empty flask (addItem / addItemEx / createItem / doPlayerAddItem with an argument named like `flask`, or a
   flask id) is commented out (marker "Chaos: no potion flasks"); inside a longer expression the call becomes nil.
   The stock potions.lua (`player:addItem(potion.flask, 1)`) and any base potion script of the fork are covered.
4. NPCs (data/npc/**/*.xml and *.lua): no NPC sells a flask any more (shop_buyable entries removed,
   addBuyableItem lines commented out, the `buy` of a {id = ..., buy = ...} row removed); NPCs still buy them
   (shop_sellable stays, at the price table's 5 gold). A string or attribute about a flask deposit (it says "deposit"
   and names a flask, vial or potion) loses its deposit sentences (the config's flaskText when nothing is left). Every
   potion seller (an NPC that sells 7618 or 7620 through shop_buyable or addBuyableItem) sells each Everfull potion at
   its config price.
5. data/npc/lib/npcsystem/modules.lua: ShopModule:callbackOnBuy hands an Everfull purchase to
   ChaosPotions.npcBuy (data/lib/chaos_potions.lua): one store-bound copy, refused while the character has one.

Idempotent: a second run changes nothing. Exit 1 when the ShopModule hook cannot be placed or no potion seller is
found (nothing is written then).
"""
import glob, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_gems import scan, xml_escape, FLAG_STACKABLE  # noqa: E402
from install_store_food import node  # noqa: E402

CONFIG = os.path.join(os.path.dirname(HERE), 'data', 'scripts', 'chaos', 'potions_config.lua')
XML_BEGIN = '\t<!-- Chaos Everfull potions (server/tools/install_potions.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos Everfull potions -->\n'
FLASK_MARK = 'Chaos: no potion flasks (install_potions.py): '
SELL_MARK = '-- Chaos: Everfull potions (install_potions.py)'
HOOK_MARK = '-- Chaos: Everfull potions (install_potions.py) v1'
SELLER_IDS = (7618, 7620)


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def lua_string(block, key):
    m = re.search(r'\b%s\s*=\s*((?:"[^"]*"\s*(?:\.\.\s*)?)+)' % key, block, re.S)
    return ''.join(re.findall(r'"([^"]*)"', m.group(1))) if m else ''


def read_config(path=CONFIG):
    text = read(path)
    body = re.search(r'\n\teverfull = \{(.*?)\n\t\},?\n', text, re.S).group(1)
    rows = []
    for chunk in re.findall(r'\n\t\t\{(.*?)\}(?=,?\n\t\t\{|\s*$)', body + '\n', re.S):
        def num(key):
            return int(re.search(r'\b%s\s*=\s*(\d+)' % key, chunk).group(1))
        rows.append({'key': lua_string(chunk, 'key'), 'id': num('id'), 'sourceId': num('sourceId'),
                     'weight': num('weight'), 'price': num('price'), 'article': lua_string(chunk, 'article'),
                     'name': lua_string(chunk, 'name'), 'plural': lua_string(chunk, 'plural'),
                     'description': lua_string(chunk, 'description')})
    flasks = [int(x) for x in re.findall(r'\d+', re.search(r'\n\tflasks = \{([^}]*)\}', text).group(1))]
    cfg = {'everfull': rows, 'flasks': flasks, 'flaskText': lua_string(text, 'flaskText')}
    assert len(rows) >= 2 and all(r['id'] and r['sourceId'] and r['name'] and r['price'] for r in rows), \
        'potions_config.lua: everfull incomplete'
    assert flasks and cfg['flaskText'], 'potions_config.lua: flasks or flaskText missing'
    return cfg


# ------------------------------------------------------------------------------------------------ 1. items.otb
def patch_otb(data, cfg):
    kids, root_end = scan(data)
    by_sid = {k[2]: k for k in kids}
    buf = bytearray(data)
    notes, wanted, inserts = [], [], b''
    # replacements from the end, so earlier offsets stay valid
    for row in sorted(cfg['everfull'], key=lambda r: -(by_sid[r['id']][0] if r['id'] in by_sid else -1)):
        stock = by_sid.get(row['sourceId'])
        if stock is None:
            raise SystemExit('items.otb: no stock node %d (the %s source); nothing written' % (row['sourceId'], row['name']))
        want = node(stock, row, stock[3])
        wanted.append((row, want, stock[3]))
        k = by_sid.get(row['id'])
        if k is None:
            inserts += want
            notes.append('items.otb: %s added (server id %d, client id %d)' % (row['name'], row['id'], stock[3]))
        elif k[3] != stock[3]:
            raise SystemExit('items.otb: server id %d already belongs to client id %s, not %d; nothing written'
                             % (row['id'], k[3], stock[3]))
        elif data[k[0]:k[1]] != want:
            buf[k[0]:k[1]] = want
            notes.append('items.otb: %s updated' % row['name'])
        else:
            notes.append('items.otb: %s present' % row['name'])
    if inserts:
        _kids, end = scan(bytes(buf))
        buf[end:end] = inserts
    return bytes(buf), notes, wanted


def verify_otb(data, wanted):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    for row, want, cid in wanted:
        k = by_sid.get(row['id'])
        assert k and k[3] == cid and data[k[0]:k[1]] == want, 'Everfull node %d' % row['id']
        stock = by_sid[row['sourceId']]
        assert bool(k[5] & FLAG_STACKABLE) == bool(stock[5] & FLAG_STACKABLE), 'stackable as its source'
    sids = [x[2] for x in kids]
    assert len(sids) == len(set(sids)), 'duplicate server ids in items.otb'
    return len(kids)


# ------------------------------------------------------------------------------------------------ 2. items.xml
def xml_block(cfg):
    out = XML_BEGIN
    for r in cfg['everfull']:
        out += ('\t<item id="%d" article="%s" name="%s" plural="%s">\n'
                '\t\t<attribute key="description" value="%s" />\n'
                '\t\t<attribute key="weight" value="%d" />\n'
                '\t</item>\n' % (r['id'], xml_escape(r['article']), xml_escape(r['name']), xml_escape(r['plural']),
                                 xml_escape(r['description']), r['weight']))
    return out + XML_END


def drop_deposit(text, fallback):
    """the sentences of a text that speak of a deposit or a flask / vial go; fallback when nothing is left"""
    parts = re.split(r'(?<=[.!?])\s+', text.strip())
    keep = [p for p in parts if not re.search(r'deposit|flask|vial', p, re.I)]
    return ' '.join(keep) if keep else fallback


def patch_flask_texts(text, cfg):
    """items.xml: a deposit sentence in the description of a flask entry"""
    n = [0]
    ids = set(cfg['flasks'])

    def entry(m):
        if int(m.group(2)) not in ids:
            return m.group(0)

        def desc(d):
            if not re.search(r'deposit', d.group(2), re.I):
                return d.group(0)
            n[0] += 1
            return d.group(1) + xml_escape(drop_deposit(d.group(2), cfg['flaskText'])) + d.group(3)
        return re.sub(r'(<attribute\s+key="description"\s+value=")([^"]*)(")', desc, m.group(0))
    out = re.sub(r'(<item\s+id=")(\d+)("[^>]*[^/]>.*?</item>)', entry, text, flags=re.S)
    return out, n[0]


def patch_xml(text, cfg):
    block = xml_block(cfg)
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: Everfull start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for r in cfg['everfull']:
        sid = r['id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the Everfull block; nothing written' % sid)
    notes = []
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            notes.append('items.xml: Everfull block up to date')
        else:
            text = text[:s] + block + text[e + len(XML_END):]
            notes.append('items.xml: Everfull block rewritten')
    else:
        end = text.rfind('</items>')
        if end < 0:
            raise SystemExit('items.xml: no </items>')
        text = text[:end] + block + text[end:]
        notes.append('items.xml: Everfull block added')
    text, n = patch_flask_texts(text, cfg)
    notes.append('items.xml: %d flask deposit text(s) rewritten' % n if n else 'items.xml: no flask deposit text')
    return text, notes


# ------------------------------------------------------------------------------------------------ 3. no flasks
ADD_CALL = re.compile(r'(?:\b[\w.]+\s*[:.]\s*)?\b(?:addItem|addItemEx|createItem|doPlayerAddItem|doCreateItem)\s*\(')


def call_end(text, i):
    """index after the parenthesis that closes the call opened at text[i - 1] == '('; None when it does not close"""
    depth = 1
    while i < len(text):
        c = text[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return i + 1
        elif c == '\n':
            return None
        i += 1
    return None


def makes_flask(args, flasks):
    first = args.split(',')[0] if args.strip() else ''
    if re.search(r'flask', first, re.I):
        return True
    nums = re.findall(r'\b\d+\b', args)
    # doPlayerAddItem(cid, 7636, 1): the id is the second argument
    return any(int(x) in flasks for x in nums[:2])


def patch_no_flasks(text, cfg):
    """comments out a statement line that adds a flask; a call inside a longer line becomes nil"""
    flasks = set(cfg['flasks'])
    nl = '\r\n' if '\r\n' in text else '\n'
    out, n = [], 0
    for line in text.split(nl):
        if FLASK_MARK.rstrip(': ') in line or line.lstrip().startswith('--'):
            out.append(line)
            continue
        code = line.split('--', 1)[0]
        hits = []
        for m in ADD_CALL.finditer(code):
            end = call_end(code, m.end())
            if end and makes_flask(code[m.end():end - 1], flasks):
                hits.append((m.start(), end))
        if not hits:
            out.append(line)
            continue
        n += len(hits)
        body = code.strip()
        whole = len(hits) == 1 and hits[0][0] == len(code) - len(code.lstrip()) and hits[0][1] == len(code.rstrip())
        oneliner = re.match(r'^if\b.*\bthen\b.*\bend$', body) is not None
        if whole or oneliner:
            indent = line[:len(line) - len(line.lstrip())]
            out.append(indent + '-- ' + FLASK_MARK + line.strip())
        else:
            for s, e in reversed(hits):
                line = line[:s] + 'nil' + line[e:]
            out.append(line + ' -- ' + FLASK_MARK.rstrip(': '))
    return nl.join(out), n


# ------------------------------------------------------------------------------------------------ 4. NPCs
SHOP_PARAM = re.compile(r'(<parameter\s+key="shop_buyable"\s+value=")([^"]*)(")')
LUA_ADD_LINE = re.compile(r'^([ \t]*)(\w+)\s*:\s*addBuyableItem\s*\(\s*(?:\{[^}]*\}|nil|"[^"]*"|\'[^\']*\')\s*,\s*(\d+)\s*,')
LUA_ROW = re.compile(r'\{[^{}]*?\bid\s*=\s*(\d+)[^{}]*?\}')
LITERAL = re.compile(r'''(['"])((?:\\.|(?!\1)[^\\\r\n])*)\1''')
XML_VALUE = re.compile(r'(\bvalue=")([^"]*)(")')


def deposit_text(s):
    return re.search(r'deposit', s, re.I) and re.search(r'flask|vial|potion', s, re.I)


def patch_shop_list(value, cfg):
    """shop_buyable: flask entries out; a potion seller gets the Everfull potions. -> (value, removed, added, seller)"""
    flasks = set(cfg['flasks'])
    entries = [e for e in value.split(';')]
    ids = []
    for e in entries:
        m = re.match(r'\s*[^,]*,\s*(\d+)\s*,', e)
        ids.append(int(m.group(1)) if m else None)
    keep = [e for e, i in zip(entries, ids) if i not in flasks]
    removed = len(entries) - len(keep)
    seller = any(i in SELLER_IDS for i in ids)
    have = {i for i in ids if i is not None}
    new = ['%s,%d,%d' % (r['name'], r['id'], r['price']) for r in cfg['everfull'] if seller and r['id'] not in have]
    if not removed and not new:
        return value, 0, 0, seller
    tail = ''
    if keep and keep[-1].strip() == '':
        tail = keep.pop()
    out = ';'.join(keep + new)
    out += ';' + tail if (value.rstrip().endswith(';') or new) else tail
    return out, removed, len(new), seller


def patch_npc_xml(text, cfg):
    m = SHOP_PARAM.search(text)
    removed = added = 0
    seller = False
    if m:
        val, removed, added, seller = patch_shop_list(m.group(2), cfg)
        text = text[:m.start(2)] + val + text[m.end(2):]
    deposits = [0]

    def attr(v):
        if not deposit_text(v.group(2)):
            return v.group(0)
        deposits[0] += 1
        return v.group(1) + xml_escape(drop_deposit(v.group(2), cfg['flaskText'])) + v.group(3)
    text = XML_VALUE.sub(attr, text)
    return text, {'removed': removed, 'added': added, 'seller': seller, 'deposit': deposits[0]}


def patch_lua_deposits(text, cfg):
    n = [0]

    def lit(m):
        if not deposit_text(m.group(2)):
            return m.group(0)
        n[0] += 1
        new = drop_deposit(m.group(2), cfg['flaskText']).replace(m.group(1), '\\' + m.group(1))
        return m.group(1) + new + m.group(1)
    out = []
    for line in text.split('\n'):
        if line.lstrip().startswith('--'):
            out.append(line)
        else:
            out.append(LITERAL.sub(lit, line))
    return '\n'.join(out), n[0]


def patch_npc_lua(text, cfg):
    flasks = set(cfg['flasks'])
    nl = '\r\n' if '\r\n' in text else '\n'
    lines = text.split(nl)
    removed, last_seller, have, var = 0, None, set(), None
    for i, line in enumerate(lines):
        m = LUA_ADD_LINE.match(line)
        if not m:
            continue
        iid = int(m.group(3))
        have.add(iid)
        if iid in flasks and FLASK_MARK not in line:
            lines[i] = m.group(1) + '-- ' + FLASK_MARK + line.strip()
            removed += 1
        elif iid in SELLER_IDS:
            last_seller, var = i, m.group(2)
    added = 0
    if last_seller is not None:
        indent = LUA_ADD_LINE.match(lines[last_seller]).group(1)
        new = ['%s%s:addBuyableItem({\'%s\'}, %d, %d, 1, \'%s\') %s' % (indent, var, r['name'], r['id'], r['price'],
                                                                         r['name'], SELL_MARK)
               for r in cfg['everfull'] if r['id'] not in have]
        lines[last_seller + 1:last_seller + 1] = new
        added = len(new)
    text = nl.join(lines)

    rows = [0]

    def row(m):
        if int(m.group(1)) not in flasks or not re.search(r'\bbuy\s*=', m.group(0)):
            return m.group(0)
        rows[0] += 1
        return re.sub(r',?\s*\bbuy\s*=\s*\d+', '', m.group(0), count=1)
    text = LUA_ROW.sub(row, text)
    removed += rows[0]
    text, deposits = patch_lua_deposits(text, cfg)
    return text, {'removed': removed, 'added': added, 'seller': last_seller is not None, 'deposit': deposits}


# ------------------------------------------------------------------------------------------------ 5. ShopModule
SHOP_BUY = re.compile(r'^([ \t]*)function\s+ShopModule\s*:\s*callbackOnBuy\s*\(\s*(\w+)\s*,\s*(\w+)[^)]*\)[ \t]*\r?\n', re.M)


def patch_shop_module(text):
    if HOOK_MARK in text:
        return text, 'modules.lua: ShopModule hook present'
    m = SHOP_BUY.search(text)
    if not m:
        return None, 'modules.lua: no ShopModule:callbackOnBuy'
    nl = '\r\n' if '\r\n' in text else '\n'
    ind = m.group(1) + '\t'
    cid, iid = m.group(2), m.group(3)
    hook = nl.join([
        ind + HOOK_MARK + ': one store-bound copy (data/lib/chaos_potions.lua)',
        ind + 'if ChaosPotions == nil then pcall(dofile, "data/lib/chaos_potions.lua") end',
        ind + 'if ChaosPotions and ChaosPotions.everfull and ChaosPotions.everfull(%s) then' % iid,
        ind + '\treturn ChaosPotions.npcBuy(%s, %s)' % (cid, iid),
        ind + 'end']) + nl
    return text[:m.end()] + hook + text[m.end():], 'modules.lua: ShopModule hook added'


# ------------------------------------------------------------------------------------------------ files
OWN_DIRS = (os.path.join('scripts', 'chaos'), os.path.join('spells', 'chaos'), os.path.join('monster', 'lua', 'chaos'))


AMOUNT_MARK = 'Chaos: potion amount'
AMOUNT_LOADER = ('if ChaosPotions == nil or ChaosPotions.amount == nil then pcall(dofile, "data/lib/chaos_potions.lua") end -- '
                 + AMOUNT_MARK + ' (fixed roll + percent of the maximum, potions_config.lua amount)\n')
AMOUNT_CALL = re.compile(r'doTargetCombat\(\s*player\s*,\s*target\s*,\s*(COMBAT_HEALING|COMBAT_MANADRAIN)\s*,\s*'
                         r'potion\.(health|mana)\[1\]\s*,\s*potion\.\2\[2\]\s*\)')


def patch_potion_amounts(text):
    """the stock potion script's health and mana rolls -> ChaosPotions.amount (owner 2026-10-22: a fixed amount + a
    percent of the maximum, so potions keep up with the level); (new text, number of calls changed)"""
    if AMOUNT_MARK in text:
        return text, 0

    def call(m):
        kind = m.group(2)
        return ('doTargetCombat(player, target, %s, (function() local v = (ChaosPotions and ChaosPotions.amount) and '
                'ChaosPotions.amount(player, target, "%s", potion.%s, potion.level) or math.random(potion.%s[1], '
                'potion.%s[2]) return v, v end)())' % (m.group(1), kind, kind, kind, kind))
    new, n = AMOUNT_CALL.subn(call, text)
    if n == 0:
        return text, 0
    return AMOUNT_LOADER + new, n


def base_lua_files(data_dir):
    out = []
    for sub in ('actions', 'scripts', 'creaturescripts', 'movements', 'talkactions', 'globalevents', 'npc'):
        for p in sorted(glob.glob(os.path.join(data_dir, sub, '**', '*.lua'), recursive=True)):
            rel = os.path.relpath(p, data_dir)
            if not any(rel.startswith(d + os.sep) for d in OWN_DIRS) and os.sep + 'lib' + os.sep not in os.sep + rel:
                out.append(p)
    return out


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    dry = '--dry-run' in args
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    cfg = read_config()
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    modules = os.path.join(data_dir, 'npc', 'lib', 'npcsystem', 'modules.lua')
    for path in (otb, xml, modules):
        if not os.path.exists(path):
            print('not found:', path)
            return 1
    changed, errors = {}, []

    raw = open(otb, 'rb').read()
    new_otb, notes, wanted = patch_otb(raw, cfg)
    n = verify_otb(new_otb, wanted)
    notes.append('items.otb: verified (%d item nodes)' % n)
    text = read(xml)
    new_xml, xnotes = patch_xml(text, cfg)
    notes += xnotes
    if new_xml != text:
        changed[xml] = new_xml

    flask_n, flask_files = 0, 0
    for path in base_lua_files(data_dir):
        t = read(path)
        new, k = patch_no_flasks(t, cfg)
        if not path.startswith(os.path.join(data_dir, 'npc')):
            new, d = patch_lua_deposits(new, cfg)
            k += d
        if new != t:
            changed[path] = new
            flask_files += 1
            flask_n += k
    notes.append('lua: %d flask line(s) / deposit text(s) in %d file(s)' % (flask_n, flask_files) if flask_n
                 else 'lua: no potion makes a flask')

    sellers, removed, added, deposits = [], 0, 0, 0
    npc_dir = os.path.join(data_dir, 'npc')
    npc_files = sorted(glob.glob(os.path.join(npc_dir, '**', '*.xml'), recursive=True)
                       + [p for p in glob.glob(os.path.join(npc_dir, '**', '*.lua'), recursive=True)
                          if os.sep + 'lib' + os.sep not in p])
    for path in npc_files:
        t = changed.get(path, read(path))
        new, info = (patch_npc_xml if path.endswith('.xml') else patch_npc_lua)(t, cfg)
        if info['seller']:
            sellers.append(os.path.relpath(path, npc_dir))
        removed += info['removed']
        added += info['added']
        deposits += info['deposit']
        if new != read(path):
            changed[path] = new
    notes.append('npc: %d potion seller(s); %d Everfull entr(ies) added, %d flask sale(s) removed, %d deposit text(s)'
                 % (len(sellers), added, removed, deposits))
    if not sellers:
        errors.append('npc: no NPC sells the health or mana potion (7618 / 7620): nobody would sell the Everfull potions')

    pot = os.path.join(data_dir, 'actions', 'scripts', 'other', 'potions.lua')
    if os.path.exists(pot):
        t = changed.get(pot, read(pot))
        new, k = patch_potion_amounts(t)
        if new != t:
            changed[pot] = new
        notes.append('potions.lua: %d potion roll(s) -> fixed + percent of the maximum' % k if k
                     else 'potions.lua: potion amounts already patched')
        if k == 0 and AMOUNT_MARK not in t:
            errors.append('potions.lua: no doTargetCombat(... potion.health[1], potion.health[2]) to patch')

    mt = read(modules)
    new_mt, mnote = patch_shop_module(mt)
    notes.append(mnote)
    if new_mt is None:
        errors.append(mnote)
    elif new_mt != mt:
        changed[modules] = new_mt

    for line in notes:
        print(line)
    if errors:
        for e in errors:
            print('ERROR', e)
        print('nothing written')
        return 1
    if dry:
        print('dry run: nothing written (%d file(s) would change)' % (len(changed) + (new_otb != raw)))
        return 0
    if new_otb != raw:
        if not os.path.exists(otb + '.bak'):
            open(otb + '.bak', 'wb').write(raw)
        open(otb, 'wb').write(new_otb)
    for path, t in sorted(changed.items()):
        write(path, t)
    return 0


if __name__ == '__main__':
    sys.exit(main())
