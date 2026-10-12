#!/usr/bin/env python3
"""Install the base server parts of the professions (server/data/scripts/chaos/professions*.lua; README "Professions").

usage: python3 -I install_professions.py DATA_DIR [--dry-run]

Everything is read from server/data/scripts/chaos/professions_config.lua (`C.materials`: m(id, prof, tier, sourceId, name,
plural, text); `C.nodes`: node(id, prof, tier, sourceId, name, text); `C.professions` tools; `C.broker.npc`), the same
file the Lua side uses.

1. data/items/items.otb: per material a copy of the stock node `sourceId` with the server id `id` (32351..32370, the 20
   materials: ores, herbs, hides, fish; stackable, as their stock nodes must be, so the client reads the count byte it
   expects) and per gathering node a copy of the base server's vein / herb node (32371..32380; flags kept: not
   pickupable, not moveable, not stackable). Their client ids stay the stock ones: the client needs no change. Nodes
   are appended at the end of the root; a node already there with the same bytes is left alone, one with other bytes
   (a changed config) is replaced, and a server id that belongs to another client id stops the script (nothing is
   written). items.otb.bak keeps the original the first time; the written file is parsed again and the nodes checked.
   (Ranges in use: see install_charms.py; charms 32301..32309, professions 32351..32399.)
2. data/items/items.xml: the entries (name, plural, description, weight) between two marker comments before </items>,
   rewritten when the config changed. An id that already has an entry outside the block stops the script.
3. data/npc: the Material Broker (server/data/npc/Material Broker.xml and the script it names); only new or different
   files are written. professions.lua places one next to every temple at startup.
4. The stock tool scripts named in data/actions/actions.xml for the professions' tools get one marked line each:
     the pick (2553), the sickle (2405) and the obsidian knife (5908): first line of onUse,
       if ChaosProfessions and ChaosProfessions.onTool and ChaosProfessions.onTool(player, item, target, toPosition) ...
       (it handles only the professions' nodes and flaying corpses; anything else goes on to the stock code)
     the fishing rod (2580): right before the stock cast adds its Fishing skill try,
       if ChaosProfessions and ChaosProfessions.onFishCast then pcall(ChaosProfessions.onFishCast, ...) end
       (the Angling roll; the stock catch is not changed)
   A line that is already there is left alone (or rewritten when it changed). A script that cannot be found or has no
   onUse / no skill try line is reported and skipped: the nodes still work by "use" with the tool in the backpack.

Idempotent: a second run changes nothing.
"""
import filecmp, os, re, shutil, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_gems import scan, escape, attr, xml_escape, START, END, A_SERVERID, FLAG_STACKABLE, FLAG_PICKUPABLE, FLAG_MOVEABLE  # noqa: E402

SERVER = os.path.dirname(HERE)
CONFIG = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'professions_config.lua')
REPO_NPC = os.path.join(SERVER, 'data', 'npc')
XML_BEGIN = '\t<!-- Chaos professions: materials and gathering nodes (server/tools/install_professions.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos professions -->\n'
MARK = '-- Chaos professions (tools/install_professions.py)'
MATERIAL_SUFFIX = ' Sell it to a Material Broker.'  # professions_config.lua m() appends it
TOOL_HOOKS = [(2553, 'tool'), (2405, 'tool'), (5908, 'tool'), (2580, 'fish')]


def read_config(path=CONFIG):
    text = open(path, encoding='utf-8').read()
    items = []
    for m in re.finditer(r'\n\tm\((\d+), "(\w+)", (\d+), (\d+), "([^"]+)", "([^"]+)", "([^"]*)"\)', text):
        items.append({'id': int(m.group(1)), 'key': m.group(5), 'prof': m.group(2), 'tier': int(m.group(3)),
                      'sourceId': int(m.group(4)), 'article': 'a', 'name': m.group(5), 'plural': m.group(6),
                      'description': m.group(7) + MATERIAL_SUFFIX, 'weight': 50, 'stackable': True})
    nodes = 0
    for m in re.finditer(r'\n\tnode\((\d+), "(\w+)", (\d+), (\d+), "([^"]+)", "([^"]*)"\)', text):
        items.append({'id': int(m.group(1)), 'key': m.group(5), 'prof': m.group(2), 'tier': int(m.group(3)),
                      'sourceId': int(m.group(4)), 'article': 'a', 'name': m.group(5), 'plural': m.group(5) + 's',
                      'description': m.group(6), 'weight': 0, 'stackable': False})
        nodes += 1
    assert len(items) - nodes >= 1 and nodes >= 1, 'professions_config.lua: no materials or nodes found'
    assert len({t['id'] for t in items}) == len(items), 'professions_config.lua: item ids must differ'
    for t in items:
        assert 32351 <= t['id'] <= 32399, 'professions_config.lua: id %d outside 32351..32399' % t['id']
    npc = re.search(r'\n\tnpc = "([^"]+)"', text).group(1)
    return items, npc


def node(stock, cfg):
    """a copy of the stock node (group, flags, every attribute) with the new server id; materials stackable"""
    _s, _e, _sid, _cid, group, flags, attrs = stock
    if cfg['stackable']:
        flags |= FLAG_PICKUPABLE | FLAG_MOVEABLE | FLAG_STACKABLE
    body = struct.pack('<I', flags)
    for k, v in attrs:
        if k == A_SERVERID:
            v = struct.pack('<H', cfg['id'])
        body += attr(k, v)
    return bytes([START]) + escape(bytes([group])) + escape(body) + bytes([END])


def patch_otb(data, items):
    notes, wanted = [], {}
    out = bytes(data)
    for cfg in items:
        kids, root_end = scan(out)
        by_sid = {k[2]: k for k in kids}
        stock = by_sid.get(cfg['sourceId'])
        if stock is None:
            raise SystemExit('items.otb: no stock node %d (%s source); nothing written' % (cfg['sourceId'], cfg['name']))
        if bool(stock[5] & FLAG_STACKABLE) != cfg['stackable']:
            raise SystemExit('items.otb: stock node %d (%s source) is %sstackable, the item must %sbe; the client would '
                             'misread the count. Pick another source; nothing written'
                             % (cfg['sourceId'], cfg['name'], '' if stock[5] & FLAG_STACKABLE else 'not ',
                                '' if cfg['stackable'] else 'not '))
        want = node(stock, cfg)
        k = by_sid.get(cfg['id'])
        buf = bytearray(out)
        if k is None:
            buf[root_end:root_end] = want
            notes.append('items.otb: %s added (server id %d, client id %d)' % (cfg['name'], cfg['id'], stock[3]))
        elif k[3] != stock[3]:
            raise SystemExit('items.otb: server id %d already belongs to client id %s, not %d; nothing written'
                             % (cfg['id'], k[3], stock[3]))
        elif out[k[0]:k[1]] != want:
            buf[k[0]:k[1]] = want
            notes.append('items.otb: %s updated' % cfg['name'])
        else:
            notes.append('items.otb: %s present' % cfg['name'])
        out = bytes(buf)
        wanted[cfg['id']] = (want, stock[3])
    return out, notes, wanted


def verify_otb(data, items, wanted):
    kids, _ = scan(data)
    by_sid = {k[2]: k for k in kids}
    for cfg in items:
        want, cid = wanted[cfg['id']]
        k = by_sid.get(cfg['id'])
        assert k and k[3] == cid, '%s node %d' % (cfg['name'], cfg['id'])
        assert bool(k[5] & FLAG_STACKABLE) == cfg['stackable'], '%s stackable flag' % cfg['name']
        assert data[k[0]:k[1]] == want, '%s node bytes' % cfg['name']
    sids = [k[2] for k in kids]
    assert len(sids) == len(set(sids)), 'duplicate server ids in items.otb'
    return len(kids)


def xml_block(items):
    body = ''
    for cfg in items:
        body += ('\t<item id="%d" article="%s" name="%s" plural="%s">\n'
                 '\t\t<attribute key="description" value="%s" />\n' % (cfg['id'], xml_escape(cfg['article']),
                                                                       xml_escape(cfg['name']), xml_escape(cfg['plural']),
                                                                       xml_escape(cfg['description'])))
        if cfg['weight'] > 0:
            body += '\t\t<attribute key="weight" value="%d" />\n' % cfg['weight']
        body += '\t</item>\n'
    return XML_BEGIN + body + XML_END


def patch_xml(text, items):
    block = xml_block(items)
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: professions start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for cfg in items:
        sid = cfg['id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the professions block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: professions block up to date'
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: professions block rewritten'
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: professions block added (%d items)' % len(items)


def npc_files(name):
    xml = os.path.join(REPO_NPC, name + '.xml')
    if not os.path.isfile(xml):
        raise SystemExit('server/data/npc/%s.xml is missing' % name)
    script = re.search(r'script="([^"]+)"', open(xml, encoding='utf-8').read()).group(1)
    return [(xml, name + '.xml'), (os.path.join(REPO_NPC, 'scripts', script), os.path.join('scripts', script))]


def copy_npc(data_dir, name, dry):
    notes = []
    for src, rel in npc_files(name):
        dst = os.path.join(data_dir, 'npc', rel)
        if os.path.isfile(dst) and filecmp.cmp(src, dst, shallow=False):
            notes.append('npc/%s: up to date' % rel)
            continue
        if not dry:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)
        notes.append('npc/%s: copied%s' % (rel, ' (dry run)' if dry else ''))
    return notes


# ------------------------------------------------------------------------------------------------ the tool hooks
def action_scripts(data_dir):
    """item id -> script path below data/actions/scripts, from actions.xml"""
    path = os.path.join(data_dir, 'actions', 'actions.xml')
    out = {}
    if not os.path.isfile(path):
        return out
    for tag in re.findall(r'<action\s[^>]*>', open(path, encoding='utf-8', errors='replace').read()):
        iid = re.search(r'\bitemid="(\d+)"', tag)
        script = re.search(r'\bscript="([^"]+)"', tag)
        if iid and script:
            out.setdefault(int(iid.group(1)), script.group(1))
    return out


def hook_line(kind, indent, params):
    player, item, target, to = params[0], params[1], params[3], params[4]
    if kind == 'tool':
        return ('%sif ChaosProfessions and ChaosProfessions.onTool and ChaosProfessions.onTool(%s, %s, %s, %s) then return true end %s\n'
                % (indent, player, item, target, to, MARK))
    return ('%sif ChaosProfessions and ChaosProfessions.onFishCast then pcall(ChaosProfessions.onFishCast, %s, %s, %s, %s) end %s\n'
            % (indent, player, item, target, to, MARK))


def patch_hook(text, kind):
    """returns (new text, note); raises ValueError when the place is not found"""
    lines = text.splitlines(True)
    head = None
    for i, l in enumerate(lines):
        m = re.match(r'\s*function\s+onUse\s*\(([^)]*)\)', l)
        if m:
            head = (i, [p.strip() for p in m.group(1).split(',')])
            break
    if not head or len(head[1]) < 5:
        raise ValueError('no onUse(player, item, fromPosition, target, toPosition, ...)')
    marked = [i for i, l in enumerate(lines) if MARK in l]
    if kind == 'tool':
        at, indent = head[0] + 1, '\t'
    else:
        at = None
        for i, l in enumerate(lines):
            if MARK not in l and re.search(r':addSkillTries\(\s*SKILL_FISHING', l):
                at, indent = i, re.match(r'(\s*)', l).group(1)
                break
        if at is None:
            raise ValueError('no addSkillTries(SKILL_FISHING, ...) line')
    want = hook_line(kind, indent, head[1])
    if marked:
        i = marked[0]
        if lines[i] == want:
            return text, 'present'
        lines[i] = want
        return ''.join(lines), 'updated'
    lines.insert(at, want)
    return ''.join(lines), 'added'


def patch_hooks(data_dir, dry):
    notes = []
    scripts = action_scripts(data_dir)
    done = set()
    for iid, kind in TOOL_HOOKS:
        rel = scripts.get(iid)
        if not rel:
            notes.append('hook: no action script for item %d in actions.xml; skipped' % iid)
            continue
        path = os.path.join(data_dir, 'actions', 'scripts', rel)
        if path in done:
            continue
        done.add(path)
        if not os.path.isfile(path):
            notes.append('hook: %s missing; skipped' % rel)
            continue
        text = open(path, encoding='utf-8', errors='surrogateescape').read()
        try:
            new, what = patch_hook(text, kind)
        except ValueError as e:
            notes.append('hook: %s: %s; skipped' % (rel, e))
            continue
        notes.append('hook: actions/scripts/%s %s%s' % (rel, what, ' (dry run)' if dry and new != text else ''))
        if new != text and not dry:
            open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new)
    return notes


def main():
    args = sys.argv[1:]
    dry = '--dry-run' in args
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    items, npc = read_config()
    otb = os.path.join(data_dir, 'items', 'items.otb')
    xml = os.path.join(data_dir, 'items', 'items.xml')
    if not os.path.exists(otb) or not os.path.exists(xml):
        print('items.otb / items.xml not found in', os.path.join(data_dir, 'items'))
        return 1
    if not os.path.isdir(os.path.join(data_dir, 'npc')):
        print('%s: no npc folder (is this a server data folder?)' % data_dir)
        return 1
    raw = open(otb, 'rb').read()
    new, notes, wanted = patch_otb(raw, items)
    n = verify_otb(new, items, wanted)
    for note in notes:
        print(note)
    print('items.otb: verified (%d item nodes; professions %d..%d)' % (n, min(t['id'] for t in items),
                                                                      max(t['id'] for t in items)))
    text = open(xml, encoding='utf-8', errors='surrogateescape').read()
    new_text, xnote = patch_xml(text, items)
    print(xnote)
    for note in copy_npc(data_dir, npc, dry):
        print(note)
    for note in patch_hooks(data_dir, dry):
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
