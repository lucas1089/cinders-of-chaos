#!/usr/bin/env python3
"""Install the salvage item (the Rune Shard) into a base server: one items.otb node and one items.xml entry.

usage: python3 -I install_salvage.py DATA_DIR [--dry-run]

Everything is read from server/data/scripts/chaos/salvage_config.lua (`shard`: id, sourceId, name, plural, article,
weight, description), the same file the Lua side uses.

1. data/items/items.otb: a copy of the stock node `sourceId` (the violet crystal shard: stackable, pickupable) with the
   server id `id` (32051). Its client id stays the stock one, so the client needs no change. The node is appended at the
   end of the root; a node already there with the same bytes is left alone, one with other bytes (a changed config) is
   replaced, and a server id that belongs to another client id stops the script (nothing is written). items.otb.bak keeps
   the original the first time; the written file is parsed again and the node checked.
   Ranges in use: gems 32001..32035 (install_gems.py), dark tiles 30484..30557, pack items 36000.., donor items 40000...
2. data/items/items.xml: the entry (name, plural, description, weight) between two marker comments before </items>,
   rewritten when the config changed. An id that already has an entry outside the block stops the script.

3. data/scripts/customs/upgrade/upgrade_slot_item.lua: the stock "Upgrade and Rarity Remover" (29623) destroys the
   target and gives a plain copy, which would drop the item lock (and make the item sellable). A guard at the top of
   levelRemover.onUse refuses a locked item ("This item is locked.").

Idempotent: a second run changes nothing.
"""
import os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_gems import scan, escape, attr, xml_escape, START, END, A_SERVERID, FLAG_STACKABLE, FLAG_PICKUPABLE, FLAG_MOVEABLE  # noqa: E402

CONFIG = os.path.join(os.path.dirname(HERE), 'data', 'scripts', 'chaos', 'salvage_config.lua')
XML_BEGIN = '\t<!-- Chaos salvage: the rune shard (server/tools/install_salvage.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos salvage items -->\n'


def read_config(path=CONFIG):
    text = open(path, encoding='utf-8').read()
    block = re.search(r'shard\s*=\s*\{(.*?)\n\t\}', text, re.S).group(1)

    def num(key):
        return int(re.search(r'\b%s\s*=\s*(\d+)' % key, block).group(1))

    def string(key):
        m = re.search(r'\b%s\s*=\s*((?:"[^"]*"\s*(?:\.\.\s*)?)+)' % key, block, re.S)
        return ''.join(re.findall(r'"([^"]*)"', m.group(1)))

    cfg = {'id': num('id'), 'sourceId': num('sourceId'), 'weight': num('weight'), 'name': string('name'),
           'plural': string('plural'), 'article': string('article'), 'description': string('description')}
    assert cfg['id'] > 0 and cfg['sourceId'] > 0 and cfg['name'], 'salvage_config.lua: shard incomplete'
    return cfg


def shard_node(stock, sid):
    """a copy of the stock node (group, flags, every attribute) with the new server id"""
    _s, _e, _sid, _cid, group, flags, attrs = stock
    flags |= FLAG_PICKUPABLE | FLAG_MOVEABLE | FLAG_STACKABLE
    body = struct.pack('<I', flags)
    for k, v in attrs:
        if k == A_SERVERID:
            v = struct.pack('<H', sid)
        body += attr(k, v)
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def patch_otb(data, cfg):
    kids, root_end = scan(data)
    by_sid = {k[2]: k for k in kids}
    stock = by_sid.get(cfg['sourceId'])
    if stock is None:
        raise SystemExit('items.otb: no stock node %d (salvage shard source); nothing written' % cfg['sourceId'])
    want = shard_node(stock, cfg['id'])
    k = by_sid.get(cfg['id'])
    out = bytearray(data)
    if k is None:
        out[root_end:root_end] = want
        note = 'items.otb: rune shard node added (server id %d, client id %d)' % (cfg['id'], stock[3])
    elif k[3] != stock[3]:
        raise SystemExit('items.otb: server id %d already belongs to client id %s, not %d; nothing written'
                         % (cfg['id'], k[3], stock[3]))
    elif data[k[0]:k[1]] != want:
        out[k[0]:k[1]] = want
        note = 'items.otb: rune shard node updated'
    else:
        note = 'items.otb: rune shard node present'
    return bytes(out), note, want, stock[3]


def verify_otb(data, cfg, want, cid):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    k = by_sid.get(cfg['id'])
    assert k and k[3] == cid and k[5] & FLAG_STACKABLE, 'rune shard node %d' % cfg['id']
    assert data[k[0]:k[1]] == want, 'rune shard node bytes'
    sids = [k[2] for k in kids]
    assert len(sids) == len(set(sids)), 'duplicate server ids in items.otb'
    return len(kids)


def xml_block(cfg):
    return (XML_BEGIN + '\t<item id="%d" article="%s" name="%s" plural="%s">\n'
            '\t\t<attribute key="description" value="%s" />\n'
            '\t\t<attribute key="weight" value="%d" />\n'
            '\t</item>\n' % (cfg['id'], xml_escape(cfg['article']), xml_escape(cfg['name']), xml_escape(cfg['plural']),
                             xml_escape(cfg['description']), cfg['weight']) + XML_END)


def patch_xml(text, cfg):
    block = xml_block(cfg)
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: salvage start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    sid = cfg['id']
    if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
        raise SystemExit('items.xml: id %d already has an entry outside the salvage block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: salvage block up to date'
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: salvage block rewritten'
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: salvage block added (the rune shard)'


REMOVER_MARKER = '-- Chaos: a locked item keeps its lock (install_salvage.py)'
REMOVER_GUARD = ('    ' + REMOVER_MARKER + '\n'
                 '    if itemEx and itemEx.isItem and itemEx:isItem() and (tonumber(itemEx:getCustomAttribute("chaos_locked")) or 0) ~= 0 then\n'
                 '        player:sendCancelMessage("This item is locked.")\n'
                 '        return true\n'
                 '    end\n')


def patch_remover(text):
    """The lock guard at the top of the stock rarity remover's onUse. Returns (text, note)."""
    if REMOVER_MARKER in text:
        return text, 'upgrade_slot_item.lua: lock guard already'
    m = re.search(r'^levelRemover\.onUse = function\(player, item, fromPosition, itemEx, toPosition\)\n', text, re.M)
    if not m:
        return text, 'upgrade_slot_item.lua: levelRemover.onUse not found'
    return text[:m.end()] + REMOVER_GUARD + text[m.end():], 'upgrade_slot_item.lua: lock guard added'


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    cfg = read_config()
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    if not os.path.exists(otb) or not os.path.exists(xml):
        print('items.otb / items.xml not found in', os.path.join(data_dir, 'items'))
        return 1
    raw = open(otb, 'rb').read()
    new, note, want, cid = patch_otb(raw, cfg)
    n = verify_otb(new, cfg, want, cid)
    print(note)
    print('items.otb: verified (%d item nodes, the rune shard a stackable copy of %d)' % (n, cfg['sourceId']))
    text = open(xml, encoding='utf-8', errors='surrogateescape').read()
    new_text, xnote = patch_xml(text, cfg)
    print(xnote)
    remover = os.path.join(data_dir, 'scripts', 'customs', 'upgrade', 'upgrade_slot_item.lua')
    rtext = rnew = None
    if os.path.exists(remover):
        rtext = open(remover, encoding='utf-8', errors='surrogateescape').read()
        rnew, rnote = patch_remover(rtext)
        print(rnote)
    else:
        print('upgrade_slot_item.lua: not found (no rarity remover to guard)')
    if dry:
        print('dry run: nothing written')
        return 0
    if rnew is not None and rnew != rtext:
        open(remover, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(rnew)
    if new != raw:
        if not os.path.exists(otb + '.bak'):
            open(otb + '.bak', 'wb').write(raw)
        open(otb, 'wb').write(new)
    if new_text != text:
        open(xml, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new_text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
