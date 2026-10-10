#!/usr/bin/env python3
"""Install the base server parts of the factions (server/data/scripts/chaos/factions*.lua; README "Factions").

usage: python3 -I install_factions.py DATA_DIR [--dry-run]

Everything is read from server/data/scripts/chaos/factions_config.lua (`tokens`: id, sourceId, article, name, plural,
weight, description per faction; `factions[i].npc.name`), the same file the Lua side uses.

1. data/items/items.otb: per faction token a copy of the stock node `sourceId` with the server id `id` (32091..32094:
   the pyre ash sigil, cinderforge seal, veiled eye and thornbound leaf; all stackable, as their stock nodes are, so the
   client reads the count byte it expects). Their client ids stay the stock ones: the client needs no change. The
   nodes are appended at the end of the root; a node already there with the same bytes is left alone, one with other
   bytes (a changed config) is replaced, and a server id that belongs to another client id stops the script (nothing
   is written). items.otb.bak keeps the original the first time; the written file is parsed again and the nodes checked.
   (Ranges in use: see install_omens.py; omens 32071..32072, Ascended 32073..32077, pouches 32081..32083, faction
   tokens 32091..32094, supports 32101..32200.)
2. data/items/items.xml: the entries (name, plural, description, weight) between two marker comments before </items>,
   rewritten when the config changed. An id that already has an entry outside the block stops the script.
3. data/npc: the four faction NPCs (server/data/npc/<name>.xml, their scripts and the shared
   npc/scripts/chaos_faction_npc.lua); only new or different files are written. factions.lua places them next to the
   temples at startup.

Idempotent: a second run changes nothing.
"""
import filecmp, os, re, shutil, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_gems import scan, escape, attr, xml_escape, START, END, A_SERVERID, FLAG_STACKABLE, FLAG_PICKUPABLE, FLAG_MOVEABLE  # noqa: E402

SERVER = os.path.dirname(HERE)
CONFIG = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'factions_config.lua')
REPO_NPC = os.path.join(SERVER, 'data', 'npc')
XML_BEGIN = '\t<!-- Chaos factions: the faction tokens (server/tools/install_factions.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos faction tokens -->\n'


def read_config(path=CONFIG):
    text = open(path, encoding='utf-8').read()
    block = re.search(r'\n\ttokens = \{(.*?)\n\t\}', text, re.S).group(1)
    out = []
    for m in re.finditer(r'\n\t\t(\w+) = \{(.*?)\},?(?=\n\t\t\w+ = \{|$)', block, re.S):
        key, body = m.group(1), m.group(2)

        def num(k):
            return int(re.search(r'\b%s\s*=\s*(\d+)' % k, body).group(1))

        def string(k):
            mm = re.search(r'\b%s\s*=\s*((?:"[^"]*"\s*(?:\.\.\s*)?)+)' % k, body, re.S)
            return ''.join(re.findall(r'"([^"]*)"', mm.group(1)))

        cfg = {'key': key, 'id': num('id'), 'sourceId': num('sourceId'), 'weight': num('weight'), 'name': string('name'),
               'plural': string('plural'), 'article': string('article'), 'description': string('description')}
        assert cfg['id'] > 0 and cfg['sourceId'] > 0 and cfg['name'], 'factions_config.lua: token %s incomplete' % key
        out.append(cfg)
    assert len(out) >= 1, 'factions_config.lua: no tokens'
    assert len({t['id'] for t in out}) == len(out), 'factions_config.lua: token ids must differ'
    npcs = re.findall(r'npc = \{name = "([^"]+)"', text)
    return out, npcs


def node(stock, cfg):
    """a copy of the stock node (group, flags, every attribute) with the new server id; stackable"""
    _s, _e, _sid, _cid, group, flags, attrs = stock
    flags |= FLAG_PICKUPABLE | FLAG_MOVEABLE | FLAG_STACKABLE
    body = struct.pack('<I', flags)
    for k, v in attrs:
        if k == A_SERVERID:
            v = struct.pack('<H', cfg['id'])
        body += attr(k, v)
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def patch_otb(data, tokens):
    notes, wanted = [], {}
    out = bytes(data)
    for cfg in tokens:
        kids, root_end = scan(out)
        by_sid = {k[2]: k for k in kids}
        stock = by_sid.get(cfg['sourceId'])
        if stock is None:
            raise SystemExit('items.otb: no stock node %d (token %s source); nothing written' % (cfg['sourceId'], cfg['key']))
        if not stock[5] & FLAG_STACKABLE:
            raise SystemExit('items.otb: stock node %d (token %s source) is not stackable; the client would misread the '
                             'count. Pick a stackable source; nothing written' % (cfg['sourceId'], cfg['key']))
        want = node(stock, cfg)
        k = by_sid.get(cfg['id'])
        buf = bytearray(out)
        if k is None:
            buf[root_end:root_end] = want
            notes.append('items.otb: %s token node added (server id %d, client id %d)' % (cfg['key'], cfg['id'], stock[3]))
        elif k[3] != stock[3]:
            raise SystemExit('items.otb: server id %d already belongs to client id %s, not %d; nothing written'
                             % (cfg['id'], k[3], stock[3]))
        elif out[k[0]:k[1]] != want:
            buf[k[0]:k[1]] = want
            notes.append('items.otb: %s token node updated' % cfg['key'])
        else:
            notes.append('items.otb: %s token node present' % cfg['key'])
        out = bytes(buf)
        wanted[cfg['key']] = (want, stock[3])
    return out, notes, wanted


def verify_otb(data, tokens, wanted):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    for cfg in tokens:
        want, cid = wanted[cfg['key']]
        k = by_sid.get(cfg['id'])
        assert k and k[3] == cid, 'token %s node %d' % (cfg['key'], cfg['id'])
        assert k[5] & FLAG_STACKABLE, 'token %s stackable flag' % cfg['key']
        assert data[k[0]:k[1]] == want, 'token %s node bytes' % cfg['key']
    sids = [k[2] for k in kids]
    assert len(sids) == len(set(sids)), 'duplicate server ids in items.otb'
    return len(kids)


def xml_block(tokens):
    body = ''
    for cfg in tokens:
        body += ('\t<item id="%d" article="%s" name="%s" plural="%s">\n'
                 '\t\t<attribute key="description" value="%s" />\n'
                 '\t\t<attribute key="weight" value="%d" />\n'
                 '\t</item>\n' % (cfg['id'], xml_escape(cfg['article']), xml_escape(cfg['name']),
                                  xml_escape(cfg['plural']), xml_escape(cfg['description']), cfg['weight']))
    return XML_BEGIN + body + XML_END


def patch_xml(text, tokens):
    block = xml_block(tokens)
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: faction token start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for cfg in tokens:
        sid = cfg['id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the faction block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: faction token block up to date'
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: faction token block rewritten'
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: faction token block added (%d tokens)' % len(tokens)


def npc_files(npcs):
    """(source, path below npc/) of the faction NPCs: their XML, the script it names and the shared dialogue"""
    out = []
    for name in npcs:
        xml = os.path.join(REPO_NPC, name + '.xml')
        if not os.path.isfile(xml):
            raise SystemExit('server/data/npc/%s.xml is missing' % name)
        out.append((xml, name + '.xml'))
        script = re.search(r'script="([^"]+)"', open(xml, encoding='utf-8').read()).group(1)
        out.append((os.path.join(REPO_NPC, 'scripts', script), os.path.join('scripts', script)))
    out.append((os.path.join(REPO_NPC, 'scripts', 'chaos_faction_npc.lua'), os.path.join('scripts', 'chaos_faction_npc.lua')))
    return out


def copy_npcs(data_dir, npcs, dry):
    notes = []
    for src, rel in npc_files(npcs):
        dst = os.path.join(data_dir, 'npc', rel)
        if os.path.isfile(dst) and filecmp.cmp(src, dst, shallow=False):
            notes.append('npc/%s: up to date' % rel)
            continue
        if not dry:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)
        notes.append('npc/%s: copied%s' % (rel, ' (dry run)' if dry else ''))
    return notes


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    tokens, npcs = read_config()
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    if not os.path.exists(otb) or not os.path.exists(xml):
        print('items.otb / items.xml not found in', os.path.join(data_dir, 'items'))
        return 1
    if not os.path.isdir(os.path.join(data_dir, 'npc')):
        print('%s: no npc folder (is this a server data folder?)' % data_dir)
        return 1
    raw = open(otb, 'rb').read()
    new, notes, wanted = patch_otb(raw, tokens)
    n = verify_otb(new, tokens, wanted)
    for note in notes:
        print(note)
    print('items.otb: verified (%d item nodes; faction tokens %s, stackable)' % (n, ', '.join(str(t['id']) for t in tokens)))
    text = open(xml, encoding='utf-8', errors='surrogateescape').read()
    new_text, xnote = patch_xml(text, tokens)
    print(xnote)
    for note in copy_npcs(data_dir, npcs, dry):
        print(note)
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
