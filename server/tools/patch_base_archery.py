#!/usr/bin/env python3
"""Infinite arrows and quivers in the base server's data (server/README.md "Infinite arrows and quivers").

usage: python3 -I patch_base_archery.py DATA_DIR [--dry-run]

Everything is read from server/data/lib/chaos_archery_config.lua (launchers, bands, missileByName, crossbowWords,
quivers, mods, ammo, conjureScripts), the same file the Lua side (data/lib/chaos_archery_core.lua) uses.

1. items.xml, bows and crossbows (two-handed, weaponType distance, an ammoType): the ammoType goes, so the engine fires
   the launcher itself (Player::getWeapon asks for ammunition only when the weapon has an ammo type, and
   Weapons::loadDefaults then gives it a distance weapon of its own). attack = its own + the band's ammunition attack,
   hitChance = the band's hit chance + its own hit bonus (at most 100; the engine uses a non-zero hitChance of the
   weapon as the whole chance), shootType = the band's missile (an elemental one by name). The kind and level come from
   the config's launchers table, else from the ammoType and the weapons.xml level (printed). A launcher without an
   ammoType is done: a second run changes nothing.
2. items.xml, quivers (the config's quivers): no containerSize, no stock abilities; weaponType quiver and slotType
   right-hand: worn in the off-hand (the shield hand) next to a bow or crossbow, the rule of engine src-patch 0023
   (Player::queryAdd; an engine without it does not know the weapon type and lets no quiver be worn); the description
   names the implicit modifiers. An entry of the earlier layout (slotType ammo) is rewritten.
3. items.otb: the quiver nodes lose the container group (2 -> 0), flags and attributes stay. The engine makes a
   container only of that group. items.otb.bak keeps the original the first time. What players kept inside a quiver is
   moved out by server/sql/chaos_archery.sql (before the first start with the new items.otb).
4. movements.xml: every equip entry of a quiver is replaced by one Chaos pair (slot shield, the hands): Equip with
   onEquipItem, the quiver's level and the vocations that may fire a launcher (the union of the launchers'
   weapons.xml lists), DeEquip.
5. spells.xml: the spells that conjured ammunition (conjureScripts) are commented out.
6. data/monster (XML and Lua): one-line loot entries of an arrow or bolt (by id or by name) are removed.
7. data/npc: shop lists of the XML NPCs lose every arrow and bolt; in the NPC scripts one-line shop entries of them go
   and buy keywords for them are commented out.
8. Base Lua scripts (not data/scripts/chaos, not data/monster): rewards of ammunition become gold coins worth its refund
   ({id, n} pairs with n < 1000, addItem(id, n), itemId = id, count = n); a trade of something for ammunition in an
   NPC script gives gold coins; removeItem(id, n) asks for gold instead, and the NPC's texts that asked for
   "<n> arrows" / "<n> bolts" ask for that gold (also on a script an earlier version of this tool patched).
9. The second ring slot (engine src-patch 0023 makes the ammunition slot take rings only and run the ring events
   there): base Lua tables that map an inventory slot to its slot position bit (`[CONST_SLOT_AMMO] = SLOTP_AMMO`, in
   data/scripts/customs/rarity/base_rarity.lua and data/lib/core/itemtype.lua) map it to SLOTP_RING, so the base
   rarity conditions and ItemType.usesSlot treat a ring there as in the ring slot.
10. data/scripts/eventcallbacks/player/default_onMoveItem.lua: the base's convenience swap (a two-handed weapon taken
   into the weapon hand puts the off-hand item into the container it came from) keeps a quiver beside a bow or
   crossbow (ChaosArchery.handsAllowed); without this, equipping a bow would push the quiver out of the off-hand.
11. items.xml, one might ring at a time: the config's mightRings, and the ids they turn into on equip and de-equip
   (transformEquipTo / transformDeEquipTo, followed to the end), get <attribute key="chaosMightRing" value="1" />.
   Engine src-patch 0023 reads the key: Player::queryAdd refuses a might ring in a ring slot while the other ring slot
   holds one; the login check (archery.lua) reads it through itemType:isMightRing().

Idempotent: a second run changes nothing. Unknown file layouts are left alone and listed.
"""
import os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_gems import scan, escape, attr, START, END  # noqa: E402

CONFIG = os.path.join(os.path.dirname(HERE), 'data', 'lib', 'chaos_archery_config.lua')
QUIVER_MARK = '<!-- Chaos quiver (server/tools/patch_base_archery.py) -->'
MOVE_BEGIN = '\t<!-- Chaos quivers (server/tools/patch_base_archery.py, do not edit by hand) -->'
MOVE_END = '\t<!-- end of the Chaos quivers -->'
SPELL_MARK = 'Chaos: no ammunition (patch_base_archery.py): '
LUA_MARK = '-- Chaos: no ammunition (patch_base_archery.py) '
GOLD = 2148
QUIVER_NOTE = 'Works only while you hold a bow or crossbow.'
KEEP_QUIVER_ATTRS = ('weight', 'showattributes')


# ------------------------------------------------------------------------------------------------ config
def _strip_comments(text):
    return re.sub(r'--[^\n]*', '', text)


def _block(text, name):
    m = re.search(r'\b%s\s*=\s*\{' % name, text)
    if not m:
        raise SystemExit('chaos_archery_config.lua: no %s' % name)
    depth, i = 1, m.end()
    while depth:
        c = text[i]
        depth += c == '{'
        depth -= c == '}'
        i += 1
    return text[m.end():i - 1]


def read_config(path=CONFIG):
    text = _strip_comments(open(path, encoding='utf-8').read())
    cfg = {}
    cfg['launchers'] = {int(i): (k, int(lv)) for i, k, lv in
                        re.findall(r'\[(\d+)\]\s*=\s*\{"(\w+)",\s*(\d+)\}', _block(text, 'launchers'))}
    cfg['crossbowWords'] = re.findall(r'"([^"]+)"', _block(text, 'crossbowWords'))
    bands = _block(text, 'bands')
    cfg['bands'] = {}
    for kind in ('bow', 'crossbow'):
        rows = re.findall(r'\{(\d+),\s*(\d+),\s*(\d+),\s*"(\w+)"\}', _block(bands, kind))
        cfg['bands'][kind] = [(int(a), int(b), int(c), d) for a, b, c, d in rows]
        assert cfg['bands'][kind], 'no %s bands' % kind
    cfg['missileByName'] = re.findall(r'\{"(\w+)",\s*"(\w+)",\s*"(\w+)"\}', _block(text, 'missileByName'))
    cfg['quivers'] = {}
    for qid, lv, imp in re.findall(r'\[(\d+)\]\s*=\s*\{(\d+),\s*\{([^}]*)\}\}', _block(text, 'quivers')):
        cfg['quivers'][int(qid)] = (int(lv), [(k, int(v)) for k, v in re.findall(r'(\w+)\s*=\s*(\d+)', imp)])
    cfg['mods'] = {}
    for body in re.findall(r'\{(key\s*=.*?tiers\s*=)', _block(text, 'mods'), re.S):
        key = re.search(r'key\s*=\s*"(\w+)"', body).group(1)
        label = re.search(r'label\s*=\s*"([^"]+)"', body).group(1)
        fmt = re.search(r'fmt\s*=\s*"(\w+)"', body)
        cfg['mods'][key] = (label, fmt.group(1) if fmt else 'pct')
    cfg['ammo'] = {int(i): int(v) for i, v in re.findall(r'\[(\d+)\]\s*=\s*(\d+)', _block(text, 'ammo'))}
    cfg['defaultRefund'] = int(re.search(r'defaultRefund\s*=\s*(\d+)', text).group(1))
    cfg['conjureScripts'] = re.findall(r'"([^"]+)"', _block(text, 'conjureScripts'))
    cfg['mightRings'] = [int(i) for i in re.findall(r'\d+', _block(text, 'mightRings'))]
    assert cfg['mightRings'], 'no mightRings'
    for qid, (_lv, imp) in cfg['quivers'].items():
        for k, _v in imp:
            assert k in cfg['mods'], 'quiver %d: implicit %s is no quiver modifier' % (qid, k)
    return cfg


def band(cfg, kind, level):
    rows = cfg['bands']['crossbow' if kind == 'crossbow' else 'bow']
    best = rows[0]
    for r in rows:
        if level >= r[0]:
            best = r
    return best


def missile(cfg, kind, level, name):
    low = name.lower()
    for word, arrow, bolt in cfg['missileByName']:
        if word in low:
            return bolt if kind == 'crossbow' else arrow
    return band(cfg, kind, level)[3]


def refund(cfg, iid, count):
    return cfg['ammo'].get(iid, cfg['defaultRefund']) * count


# ------------------------------------------------------------------------------------------------ items.xml
ITEM_RE = re.compile(r'([ \t]*)<item\s([^>]*?)(/>|>(.*?)</item>)', re.S)


def _attrs(body):
    return {k.lower(): v for k, v in re.findall(r'key="(\w+)"\s+value="([^"]*)"', body or '')}


def _ids(head):
    one = re.search(r'\bid="(\d+)"', head)
    if one:
        return [int(one.group(1))]
    fr, to = re.search(r'\bfromid="(\d+)"', head), re.search(r'\btoid="(\d+)"', head)
    if fr and to:
        return list(range(int(fr.group(1)), int(to.group(1)) + 1))
    return []


def weapon_levels(weapons_text):
    """weapons.xml: launcher id -> (level, [(vocation line), ...])"""
    out = {}
    for m in re.finditer(r'<distance\s([^>]*?)(/>|>(.*?)</distance>)', weapons_text or '', re.S):
        iid = re.search(r'\bid="(\d+)"', m.group(1))
        if not iid:
            continue
        lv = re.search(r'\blevel="(\d+)"', m.group(1))
        vocs = re.findall(r'<vocation\s[^>]*?/>', m.group(3) or '')
        out[int(iid.group(1))] = (int(lv.group(1)) if lv else 0, vocs)
    return out


def ammo_ids(cfg, items_text):
    """every arrow and bolt: the config's list and any ammunition of ammo type arrow or bolt; -> {id: name}"""
    out = {}
    for m in ITEM_RE.finditer(items_text):
        a = _attrs(m.group(4))
        name = re.search(r'\bname="([^"]*)"', m.group(2))
        for iid in _ids(m.group(2)):
            ammo = a.get('weapontype', '').lower() == 'ammunition' and a.get('ammotype', '').lower() in ('arrow', 'bolt')
            if ammo or iid in cfg['ammo']:
                out[iid] = name.group(1) if name else ''
    for iid in cfg['ammo']:
        out.setdefault(iid, '')
    return out


def launcher_ids(items_text):
    """every two-handed distance weapon of items.xml (patched or not)"""
    out = set()
    for m in ITEM_RE.finditer(items_text):
        a = _attrs(m.group(4))
        if a.get('weapontype', '').lower() == 'distance' and a.get('slottype', '').lower() == 'two-handed':
            out.update(_ids(m.group(2)))
    return out


def _set_attr(body, key, value, pad, tail):
    """set (or add, before the closing tag: tail = the line end and indent of </item>) one attribute"""
    pat = re.compile(r'<attribute\s+key="%s"\s+value="[^"]*"\s*/>' % key, re.I)
    line = '<attribute key="%s" value="%s" />' % (key, value)
    if pat.search(body):
        return pat.sub(line, body, count=1)
    nl = '\r\n' if '\r\n' in tail else '\n'
    return body.rstrip(' \t\r\n') + nl + pad + line + tail


def _drop_attr(body, key):
    return re.sub(r'[ \t]*<attribute\s+key="%s"\s+value="[^"]*"\s*/>[ \t]*\r?\n?' % key, '', body, flags=re.I)


def patch_items(text, cfg, weapons_text=''):
    """-> new text, notes, {launcher id: (kind, level)}"""
    nl = '\r\n' if '\r\n' in text else '\n'
    levels = weapon_levels(weapons_text)
    notes, launchers, unlisted, quivers_done = [], {}, [], 0
    changed = {'launchers': 0, 'quivers': 0}

    def item(m):
        indent, head, close, body = m.group(1), m.group(2), m.group(3), m.group(4)
        ids = _ids(head)
        if not ids:
            return m.group(0)
        a = _attrs(body)
        name = (re.search(r'\bname="([^"]*)"', head) or re.search(r'()', '')).group(1)
        pad = indent + '\t'
        # quivers
        if ids[0] in cfg['quivers']:
            lv, imp = cfg['quivers'][ids[0]]
            keep = [l for l in re.findall(r'<attribute\b[^>]*/>', body or '')
                    if re.search(r'key="(\w+)"', l).group(1).lower() in KEEP_QUIVER_ATTRS]
            parts = []
            for k, v in imp:
                label, fmt = cfg['mods'][k]
                parts.append('%s +%d%s' % (label, v, '' if fmt == 'flat' else '%'))
            desc = 'Implicit: %s. %s' % (', '.join(parts), QUIVER_NOTE)
            lines = [indent + '<item %s>' % head.strip(), pad + QUIVER_MARK,
                     pad + '<attribute key="weaponType" value="quiver" />',
                     pad + '<attribute key="slotType" value="right-hand" />']
            lines += [pad + l for l in keep]
            lines.append(pad + '<attribute key="description" value="%s" />' % desc)
            lines.append(indent + '</item>')
            want = nl.join(lines)
            if want != m.group(0):
                changed['quivers'] += 1
            return want
        # launchers
        if a.get('weapontype', '').lower() != 'distance' or a.get('slottype', '').lower() != 'two-handed':
            return m.group(0)
        ammo = a.get('ammotype', '').lower()
        if not ammo:
            return m.group(0)  # done (or never fired ammunition)
        entry = cfg['launchers'].get(ids[0])
        if entry:
            kind, level = entry
        else:
            kind = 'crossbow' if ammo == 'bolt' else 'bow'
            level = levels.get(ids[0], (0, []))[0]
            unlisted.append('%d %s (%s, level %d)' % (ids[0], name, kind, level))
        b = band(cfg, kind, level)
        old_attack = int(a.get('attack', '0') or 0)
        old_hit = int(a.get('hitchance', '0') or 0)
        tail = nl + indent
        body = _drop_attr(body, 'ammoType')
        body = _set_attr(body, 'attack', old_attack + b[1], pad, tail)
        body = _set_attr(body, 'hitChance', max(1, min(100, b[2] + old_hit)), pad, tail)
        body = _set_attr(body, 'shootType', missile(cfg, kind, level, name), pad, tail)
        for iid in ids:
            launchers[iid] = (kind, level)
        changed['launchers'] += 1
        return indent + '<item ' + head + '>' + body + '</item>'

    out = ITEM_RE.sub(item, text)
    notes.append('items.xml: %d launcher entr%s fire without ammunition' % (changed['launchers'],
                 'y' if changed['launchers'] == 1 else 'ies') if changed['launchers'] else
                 'items.xml: every launcher fires without ammunition')
    for u in unlisted:
        notes.append('items.xml: launcher not in chaos_archery_config.lua, by its ammo type and level: ' + u)
    found = {iid for m in ITEM_RE.finditer(out) for iid in _ids(m.group(2)) if iid in cfg['quivers']}
    for qid in sorted(set(cfg['quivers']) - found):
        notes.append('items.xml: quiver %d has no entry' % qid)
    notes.append('items.xml: %d quiver entr%s made equipment' % (changed['quivers'], 'y' if changed['quivers'] == 1 else 'ies')
                 if changed['quivers'] else 'items.xml: the %d quivers are equipment' % len(found))
    return out, notes, launchers


# ------------------------------------------------------------------------------------------------ might rings
MIGHT_KEY = 'chaosMightRing'


def might_ring_ids(items_text, ids):
    """the config's might rings and every id they turn into on equip or de-equip, followed to the end"""
    links = {}
    for m in ITEM_RE.finditer(items_text):
        a = _attrs(m.group(4))
        for iid in _ids(m.group(2)):
            links[iid] = [int(a[k]) for k in ('transformequipto', 'transformdeequipto') if a.get(k, '').isdigit()]
    out, todo = set(), list(ids)
    while todo:
        iid = todo.pop()
        if iid in out or not iid:
            continue
        out.add(iid)
        todo.extend(links.get(iid, []))
    return out


def patch_might_rings(text, ids):
    """-> new text, notes. Marks every might ring id (one item entry each) with the key chaosMightRing."""
    want = might_ring_ids(text, ids)
    nl = '\r\n' if '\r\n' in text else '\n'
    found, changed, notes = set(), [], []

    def item(m):
        indent, head, close, body = m.group(1), m.group(2), m.group(3), m.group(4)
        ids_here = _ids(head)
        hit = [i for i in ids_here if i in want]
        if not hit:
            return m.group(0)
        if len(ids_here) > 1:
            notes.append('items.xml: might ring %s is part of a fromid/toid range, left alone' % hit)
            return m.group(0)
        found.add(ids_here[0])
        if _attrs(body).get(MIGHT_KEY.lower()) == '1':
            return m.group(0)
        changed.append(ids_here[0])
        if close == '/>':
            return '%s<item %s>%s%s\t<attribute key="%s" value="1" />%s%s</item>' % (
                indent, head.rstrip(' /'), nl, indent, MIGHT_KEY, nl, indent)
        body = _set_attr(body, MIGHT_KEY, '1', indent + '\t', nl + indent)
        return indent + '<item ' + head + '>' + body + '</item>'

    out = ITEM_RE.sub(item, text)
    for iid in sorted(want - found):
        notes.append('items.xml: might ring %d has no entry' % iid)
    notes.append('items.xml: might rings %s marked (one at a time)' % ', '.join(map(str, sorted(changed))) if changed
                 else 'items.xml: the might rings %s are marked' % ', '.join(map(str, sorted(found))))
    return out, notes


# ------------------------------------------------------------------------------------------------ items.otb
def quiver_node(k):
    _s, _e, _sid, _cid, _group, flags, attrs = k
    body = struct.pack('<I', flags)
    for kind, v in attrs:
        body += attr(kind, v)
    return bytes([START]) + escape(bytes([0])) + escape(body) + bytes([END])


def patch_otb(data, ids):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    replace, notes = [], []
    for sid in ids:
        k = by_sid.get(sid)
        if k is None:
            notes.append('items.otb: no node for quiver %d' % sid)
            continue
        if k[4] != 0:
            replace.append((k[0], k[1], quiver_node(k)))
    out = bytearray(data)
    for s, e, b in sorted(replace, reverse=True):
        out[s:e] = b
    notes.append('items.otb: %d quiver(s) no longer containers' % len(replace) if replace else
                 'items.otb: no quiver is a container')
    return bytes(out), notes


def verify_otb(data, ids):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    for sid in ids:
        if sid in by_sid:
            assert by_sid[sid][4] == 0, 'quiver %d still a container' % sid
    return len(kids)


# ------------------------------------------------------------------------------------------------ movements.xml
def patch_movements(text, cfg, weapons_text, launchers):
    nl = '\r\n' if '\r\n' in text else '\n'
    # drop the earlier Chaos block and every stock quiver entry
    text2 = re.sub(re.escape(MOVE_BEGIN) + r'.*?' + re.escape(MOVE_END) + r'\r?\n?', '', text, flags=re.S)
    ids = set(cfg['quivers'])

    def drop(m):
        iid = re.search(r'\bitemid="(\d+)"', m.group(1))
        return '' if iid and int(iid.group(1)) in ids else m.group(0)
    text2 = re.sub(r'[ \t]*<movevent\s([^>]*?)(?:/>|>.*?</movevent>)[ \t]*\r?\n?', drop, text2, flags=re.S)
    # who may fire a launcher: the vocation lines of the launchers in weapons.xml
    levels = weapon_levels(weapons_text)
    vocs, seen = [], set()
    for iid, (_lv, lines) in sorted(levels.items()):
        if iid in launchers:
            for line in lines:
                n = re.search(r'name="([^"]+)"', line).group(1)
                if n.lower() not in seen:
                    seen.add(n.lower())
                    vocs.append(line)
    lines = [MOVE_BEGIN]
    for qid in sorted(ids):
        lv = cfg['quivers'][qid][0]
        lines.append('\t<movevent event="Equip" itemid="%d" slot="shield" level="%d" function="onEquipItem">' % (qid, lv))
        lines += ['\t\t' + v for v in vocs]
        lines.append('\t</movevent>')
        lines.append('\t<movevent event="DeEquip" itemid="%d" slot="shield" function="onDeEquipItem" />' % qid)
    lines.append(MOVE_END)
    block = nl.join(lines) + nl
    if '</movements>' not in text2:
        raise SystemExit('movements.xml: </movements> not found; nothing written')
    out = text2.replace('</movements>', block + '</movements>', 1)
    note = 'movements.xml: %d quiver entries (%s)' % (len(ids), ', '.join(
        re.search(r'name="([^"]+)"', v).group(1) for v in vocs) or 'every vocation')
    return out, ('movements.xml: quiver entries present' if out == text else note)


# ------------------------------------------------------------------------------------------------ spells.xml
def patch_spells(text, cfg):
    comments = [(m.start(), m.end()) for m in re.finditer(r'<!--.*?-->', text, re.S)]

    def inside(pos):
        return any(s <= pos < e for s, e in comments)
    n = [0]

    def spell(m):
        script = re.search(r'\bscript="([^"]+)"', m.group(1))
        if not script or os.path.basename(script.group(1)) not in cfg['conjureScripts'] or inside(m.start()):
            return m.group(0)
        n[0] += 1
        return '<!-- ' + SPELL_MARK + m.group(0).replace('--', '- -') + ' -->'
    out = re.sub(r'<(?:instant|conjure)\s([^>]*?)(?:/>|>.*?</(?:instant|conjure)>)', spell, text, flags=re.S)
    return out, ('spells.xml: %d ammunition spell(s) switched off' % n[0] if n[0] else
                 'spells.xml: no ammunition spell is active')


# ------------------------------------------------------------------------------------------------ loot, shops, rewards
def _id_or_name(ammo, names):
    def is_ammo(token):
        token = token.strip().strip('"\'')
        if token.isdigit():
            return int(token) in ammo
        return token.lower() in names
    return is_ammo


def patch_monster_xml(text, is_ammo):
    n = [0]

    def line(m):
        tag = m.group(0)
        iid = re.search(r'\bid="(\d+)"', tag)
        name = re.search(r'\bname="([^"]+)"', tag)
        if (iid and is_ammo(iid.group(1))) or (name and is_ammo(name.group(1))):
            n[0] += 1
            return ''
        return tag
    out = re.sub(r'^[ \t]*<item\b[^>\n]*/>[ \t]*(?:<!--[^\n]*?-->[ \t]*)?\r?\n', line, text, flags=re.M)
    return out, n[0]


LUA_ENTRY = re.compile(r'^[ \t]*\{[^{}\n]*\}[ \t]*,?[ \t]*(?:--[^\n]*)?\r?\n', re.M)


def patch_monster_lua(text, is_ammo):
    n = [0]

    def line(m):
        e = m.group(0)
        v = re.search(r'\b(?:id|name)\s*=\s*("[^"]*"|\'[^\']*\'|\d+)', e)
        if v and is_ammo(v.group(1)):
            n[0] += 1
            return ''
        return e
    return LUA_ENTRY.sub(line, text), n[0]


def patch_npc_xml(text, ammo):
    n = [0]

    def param(m):
        chunks = m.group(2).split(';')
        keep = []
        for c in chunks:
            f = [x.strip() for x in c.split(',')]
            if len(f) >= 2 and f[1].isdigit() and int(f[1]) in ammo:
                n[0] += 1
                continue
            keep.append(c)
        return m.group(1) + ';'.join(keep) + m.group(3)
    out = re.sub(r'(<parameter\s+key="shop_\w+"\s+value=")([^"]*)(")', param, text)
    return out, n[0]


def patch_npc_lua(text, ammo):
    n = [0]
    ids = '|'.join(str(i) for i in sorted(ammo))

    def entry(m):
        e = m.group(0)
        if re.search(r'\bid\s*=\s*(%s)\b' % ids, e):
            n[0] += 1
            return ''
        return e
    out = LUA_ENTRY.sub(entry, text)

    def keyword(m):
        n[0] += 1
        return m.group(1) + LUA_MARK + m.group(2)
    out = re.sub(r'^([ \t]*)((?:shopModule:)?add(?:Buyable|Sellable)(?:Keyword|Item)\([^\n]*?\b(?:%s)\b[^\n]*)$' % ids,
                 keyword, out, flags=re.M)
    return out, n[0]


def patch_rewards(text, cfg, ammo, npc_script=False):
    """ammunition given or asked for by a script: gold coins worth its refund instead. -> new text, changes"""
    ids = '|'.join(str(i) for i in sorted(ammo))
    n = [0]

    def gold(iid, count):
        n[0] += 1
        return max(1, refund(cfg, int(iid), int(count)))

    def pair(m):  # {id, n} with a small n: a reward list entry
        return '{%s%d%s%d%s}' % (m.group(1), GOLD, m.group(3), gold(m.group(2), m.group(4)), m.group(5))

    def add(m):  # addItem(id, n)
        return 'addItem(%s%d%s%d%s)' % (m.group(1), GOLD, m.group(3), gold(m.group(2), m.group(4)), m.group(5))

    def counted(m):  # itemId = id, count = n
        return 'itemId%s%d%s%d' % (m.group(1), GOLD, m.group(3), gold(m.group(2), m.group(4)))

    def single(m):  # itemId = id
        n[0] += 1
        return m.group(1) + str(GOLD)

    def take(m):  # removeItem(id, n): the price of new ammunition
        n[0] += 1
        return 'removeMoney(%d)' % (2 * max(1, refund(cfg, int(m.group(2)), int(m.group(4)))))

    def trade(m):  # {item asked, ammunition given} in an NPC trade table
        n[0] += 1
        return m.group(1) + str(GOLD) + m.group(3)
    out = re.sub(r'\{(\s*)(%s)(\s*,\s*)(\d{1,3})(\s*)\}' % ids, pair, text)
    out = re.sub(r'addItem\((\s*)(%s)(\s*,\s*)(\d{1,3})(\s*)\)' % ids, add, out)
    out = re.sub(r'itemId(\s*=\s*)(%s)(\s*,\s*count\s*=\s*)(\d+)' % ids, counted, out)
    out = re.sub(r'(\bitemId\s*=\s*)(%s)\b(?!\s*,\s*count)' % ids, single, out)
    out = re.sub(r'removeItem\((\s*)(%s)(\s*,\s*)(\d+)(\s*)\)' % ids, take, out)
    if npc_script:
        out = re.sub(r'(\{\s*\d{3,5}\s*,\s*)(%s)(\s*\})' % ids, trade, out)
    return out, n[0]


def patch_ammo_dialogue(text, cfg):
    """an NPC script that asks for gold instead of ammunition (removeMoney(M), written by patch_rewards) no longer says
    "<N> arrows" / "<N> bolts" in its texts when M is the price of N pieces: the text says "<M> gold". Works on a script
    patched by an earlier version of this tool too. -> new text, changes"""
    monies = {int(m) for m in re.findall(r'removeMoney\(\s*(\d+)\s*\)', text)}
    if not monies:
        return text, 0
    rates = set(cfg['ammo'].values()) | {cfg['defaultRefund']}
    n = [0]

    def phrase(m):
        count = int(m.group(1))
        price = sorted(g for g in monies if any(g == 2 * max(1, count * r) for r in rates))
        if len(price) != 1:
            return m.group(0)
        n[0] += 1
        return '%d gold' % price[0]

    def literal(m):
        return re.sub(r'\b(\d+) (?:arrows?|bolts?)\b', phrase, m.group(0), flags=re.I)
    out = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', literal, text)
    return out, n[0]


# ------------------------------------------------------------------------------------------------ second ring slot
RING_SLOT_RE = re.compile(r'\[CONST_SLOT_AMMO\](\s*)=(\s*)SLOTP_AMMO\b')
RING_SLOT_MARK = ' -- Chaos: the second ring slot (patch_base_archery.py)'


def patch_ring_slot(text):
    """slot -> slot position maps: the ammunition slot is the second ring slot. -> new text, changes"""
    n = [0]

    def ring(m):
        n[0] += 1
        return '[CONST_SLOT_AMMO]%s=%sSLOTP_RING' % (m.group(1), m.group(2))
    out = RING_SLOT_RE.sub(ring, text)
    if n[0]:
        # the mark after the first changed line's value (a trailing comma stays in front of it)
        out = re.sub(r'(\[CONST_SLOT_AMMO\]\s*=\s*SLOTP_RING,?)(?![^\n]*Chaos: the second ring slot)', r'\1' + RING_SLOT_MARK,
                     out)
    return out, n[0]


# ------------------------------------------------------------------------------------------------ the base swap
SWAP_FILE = os.path.join('scripts', 'eventcallbacks', 'player', 'default_onMoveItem.lua')
SWAP_MARK = '-- Chaos: a quiver stays beside a bow or crossbow (patch_base_archery.py)'
SWAP_RE = re.compile(r'^([ \t]*)moveItem = self:getSlotItem\(CONST_SLOT_RIGHT\)[ \t]*\r?\n', re.M)


def patch_swap(text):
    """-> new text, status"""
    if SWAP_MARK in text:
        return text, 'default_onMoveItem.lua: the quiver stays beside a launcher'
    m = SWAP_RE.search(text)
    if not m:
        return text, 'default_onMoveItem.lua: two-handed swap not found, left alone'
    ind = m.group(1)
    nl = '\r\n' if m.group(0).endswith('\r\n') else '\n'
    add = (ind + SWAP_MARK + nl
           + ind + 'if moveItem and ChaosArchery and ChaosArchery.handsAllowed(ChaosArchery.handKind(itemType),' + nl
           + ind + '\t\tChaosArchery.handKind(ItemType(moveItem:getId()))) then' + nl
           + ind + '\tmoveItem = nil' + nl
           + ind + 'end' + nl)
    return text[:m.end()] + add + text[m.end():], 'default_onMoveItem.lua: a quiver stays beside a launcher'


# ------------------------------------------------------------------------------------------------ files
def read(path):
    return open(path, encoding='utf-8', errors='surrogateescape', newline='').read()


def write(path, text):
    open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(text)


def walk(root, exts):
    for d, _dirs, files in os.walk(root):
        for f in sorted(files):
            if f.lower().endswith(exts):
                yield os.path.join(d, f)


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data = args[0]
    cfg = read_config()
    xml_path = os.path.join(data, 'items', 'items.xml')
    otb_path = os.path.join(data, 'items', 'items.otb')
    weapons_path = os.path.join(data, 'weapons', 'weapons.xml')
    moves_path = os.path.join(data, 'movements', 'movements.xml')
    spells_path = os.path.join(data, 'spells', 'spells.xml')
    for p in (xml_path, otb_path, weapons_path, moves_path):
        if not os.path.exists(p):
            print('not found:', p)
            return 1
    writes = {}
    weapons = read(weapons_path)
    items = read(xml_path)
    ammo = ammo_ids(cfg, items)
    names = {v.lower() for v in ammo.values() if v}
    is_ammo = _id_or_name(set(ammo), names)

    new_items, notes, _launchers = patch_items(items, cfg, weapons)
    new_items, mnotes = patch_might_rings(new_items, cfg['mightRings'])
    for note in notes + mnotes:
        print(note)
    if new_items != items:
        writes[xml_path] = new_items

    raw = open(otb_path, 'rb').read()
    new_otb, onotes = patch_otb(raw, sorted(cfg['quivers']))
    n = verify_otb(new_otb, sorted(cfg['quivers']))
    for note in onotes:
        print(note)
    print('items.otb: verified (%d item nodes)' % n)

    moves = read(moves_path)
    new_moves, mnote = patch_movements(moves, cfg, weapons, launcher_ids(items) | set(cfg['launchers']))
    print(mnote)
    if new_moves != moves:
        writes[moves_path] = new_moves

    if os.path.exists(spells_path):
        spells = read(spells_path)
        new_spells, snote = patch_spells(spells, cfg)
        print(snote)
        if new_spells != spells:
            writes[spells_path] = new_spells

    loot = files = 0
    for p in walk(os.path.join(data, 'monster'), ('.xml', '.lua')):
        if os.sep + 'chaos' + os.sep in p:
            continue
        t = read(p)
        new, k = (patch_monster_xml if p.lower().endswith('.xml') else patch_monster_lua)(t, is_ammo)
        if k:
            loot += k
            files += 1
            writes[p] = new
    print('monsters: %d arrow / bolt loot entr%s removed in %d file(s)' % (loot, 'y' if loot == 1 else 'ies', files))

    shop = 0
    for p in walk(os.path.join(data, 'npc'), ('.xml', '.lua')):
        t = read(p)
        if p.lower().endswith('.xml'):
            new, k = patch_npc_xml(t, set(ammo))
        else:
            new, k = patch_npc_lua(t, set(ammo))
            new, k2 = patch_rewards(new, cfg, set(ammo), npc_script=True)
            new, k3 = patch_ammo_dialogue(new, cfg)
            k += k2 + k3
            if k3:
                print('  dialogue: %s (%d text%s ask for gold)' % (os.path.relpath(p, data), k3, '' if k3 == 1 else 's'))
        if k:
            shop += k
            writes[p] = new
    print('NPCs: %d arrow / bolt offer(s) or reward(s) removed' % shop)

    rewards = 0
    skip = (os.path.join(data, 'scripts', 'chaos'), os.path.join(data, 'monster'), os.path.join(data, 'npc'),
            os.path.join(data, 'lib'), os.path.join(data, 'weapons'), os.path.join(data, 'spells'))
    for p in walk(data, ('.lua',)):
        if p.startswith(skip):
            continue
        t = read(p)
        new, k = patch_rewards(t, cfg, set(ammo))
        if k:
            rewards += k
            writes[p] = new
            print('  rewards: %s (%d)' % (os.path.relpath(p, data), k))
    print('scripts: %d ammunition reward(s) turned into gold' % rewards)

    swap_path = os.path.join(data, SWAP_FILE)
    if os.path.exists(swap_path):
        t = writes.get(swap_path) or read(swap_path)
        new, note = patch_swap(t)
        print(note)
        if new != t:
            writes[swap_path] = new
    else:
        print('default_onMoveItem.lua: not found')

    rings = 0
    for p in walk(data, ('.lua',)):
        if p.startswith(os.path.join(data, 'scripts', 'chaos')):
            continue
        t = writes.get(p) or read(p)
        new, k = patch_ring_slot(t)
        if k:
            rings += k
            writes[p] = new
            print('  second ring slot: %s' % os.path.relpath(p, data))
    print('second ring slot: %d slot map(s) changed' % rings if rings else 'second ring slot: the slot maps are done')

    if dry:
        print('dry run: nothing written (%d file(s) would change%s)' % (len(writes) + (new_otb != raw),
              '' if new_otb == raw else ', items.otb among them'))
        return 0
    if new_otb != raw:
        if not os.path.exists(otb_path + '.bak'):
            open(otb_path + '.bak', 'wb').write(raw)
        open(otb_path, 'wb').write(new_otb)
    for p, t in writes.items():
        write(p, t)
    print('%d file(s) written' % (len(writes) + (new_otb != raw)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
