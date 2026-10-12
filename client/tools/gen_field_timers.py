#!/usr/bin/env python3
"""Write client/overlay/modules/game_tileoverlays/fielddata.lua: the timed fields the client counts down (magic walls,
wild growth, fire / poison / energy fields) as client item id -> time until the field is gone.

usage: python3 -I client/tools/gen_field_timers.py SERVER_DIR [--out PATH] [--check]
  SERVER_DIR  an installed base server (after server/tools/install_all.py): data/items/items.xml and items.otb are read
  --out       where to write (default: the module's fielddata.lua in this repository)
  --check     do not write; exit 1 when the file differs from what would be written

What counts: every items.xml item of type "magicfield" with a duration (seconds) and a decayTo. Its time is its own
duration plus the durations of the items it decays into, until one decays to nothing (decayTo 0); a chain that turns
into an item without a duration stops there (the client drops the timer when the id changes), and a chain that comes
back to itself never goes away and is left out. Server ids become client ids through items.otb. When two server items
share a client id with different times the id is left out (the client could not tell them apart); a server item without
a decay that shares the client id of a timed one (a field placed on the map) is ignored: such a field is shown as "~"
(start unknown) because it is already there when it comes into view.
"""
import os, re, struct, sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.join(HERE, '..', 'overlay', 'modules', 'game_tileoverlays', 'fielddata.lua')

TOK = re.compile(rb'\xfd.|\xfe|\xff', re.S)
UNESC = re.compile(rb'\xfd(.)', re.S)


def otb_client_ids(data):
    """{server id: client id} from the bytes of an items.otb (attribute 0x10 server id, 0x11 client id)."""
    pending, first, out, spans = None, True, {}, []
    for m in TOK.finditer(data, 4):
        s = m.group()
        if len(s) == 2:
            continue
        pos = m.start()
        if pending is not None:
            spans.append((pending, pos))
            pending = None
        if s == b'\xfe':
            pending = pos + 2  # node start, type byte, then the payload
    for a, b in spans:
        if first:  # the root node (version info)
            first = False
            continue
        pl = UNESC.sub(rb'\1', data[a:b])
        k = 4  # u32 flags
        sid = cid = None
        while k + 3 <= len(pl):
            at, ln = pl[k], struct.unpack_from('<H', pl, k + 1)[0]
            k += 3
            if at == 0x10 and ln == 2:
                sid = struct.unpack_from('<H', pl, k)[0]
            elif at == 0x11 and ln == 2:
                cid = struct.unpack_from('<H', pl, k)[0]
            k += ln
        if sid and cid:
            out[sid] = cid
    return out


def read_items(xml_bytes):
    """{server id: {name, type, decayTo, duration}} from items.xml (ranges fromid..toid included)."""
    root = ET.fromstring(xml_bytes)
    items = {}
    for it in root.iter('item'):
        attrs = {}
        for a in it.findall('attribute'):
            if a.get('key') is not None:
                attrs[a.get('key').lower()] = a.get('value')
        if it.get('id') is not None:
            ids = [int(it.get('id'))]
        elif it.get('fromid') is not None and it.get('toid') is not None:
            ids = list(range(int(it.get('fromid')), int(it.get('toid')) + 1))
        else:
            continue
        for i in ids:
            items[i] = {'name': it.get('name') or '', 'type': (attrs.get('type') or '').lower(),
                        'decayTo': int(attrs['decayto']) if attrs.get('decayto') not in (None, '') else None,
                        'duration': int(attrs['duration']) if attrs.get('duration') not in (None, '') else 0}
    return items


def chain_seconds(items, sid):
    """seconds until server item sid is gone (its decay chain), or None when it never goes away / has no decay."""
    total, seen, cur = 0, set(), sid
    while True:
        if cur in seen:
            return None  # a cycle: permanent
        seen.add(cur)
        it = items.get(cur)
        if not it or it['decayTo'] is None or it['duration'] <= 0:
            return total if cur != sid else None  # turns into something lasting: the timer ends with the change
        total += it['duration']
        if it['decayTo'] == 0:
            return total
        cur = it['decayTo']


def build(items, cids):
    """{client id: (ms, name)} and a list of notes (ids left out)."""
    found, notes = {}, []
    for sid in sorted(items):
        it = items[sid]
        if it['type'] != 'magicfield' or it['decayTo'] is None or it['duration'] <= 0:
            continue
        secs = chain_seconds(items, sid)
        if secs is None:
            notes.append('server id %d (%s): decays in a cycle, never goes away' % (sid, it['name']))
            continue
        cid = cids.get(sid)
        if not cid:
            notes.append('server id %d (%s): no client id in items.otb' % (sid, it['name']))
            continue
        found.setdefault(cid, []).append((secs * 1000, it['name'], sid))
    table, clash = {}, set()
    for cid, rows in found.items():
        if len({r[0] for r in rows}) > 1:
            clash.add(cid)
            notes.append('client id %d: server ids %s have different times, left out'
                         % (cid, ', '.join(str(r[2]) for r in rows)))
            continue
        table[cid] = (rows[0][0], rows[0][1])
    return table, notes


def lua_string(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'") + "'"


def render(table):
    lines = ['-- GENERATED by client/tools/gen_field_timers.py from the installed base server\'s items.xml and items.otb.',
             '-- Do not edit; run the generator again when items change (client/MANIFEST.md "game_tileoverlays").',
             '-- client item id -> {t = ms until the field is gone (its duration and the stages it decays into), n = name}',
             'TileOverlayFields = {']
    for cid in sorted(table):
        ms, name = table[cid]
        lines.append('  [%d] = { t = %d, n = %s },' % (cid, ms, lua_string(name)))
    lines.append('}')
    return '\n'.join(lines) + '\n'


def generate(server_dir):
    base = os.path.join(server_dir, 'data', 'items')
    with open(os.path.join(base, 'items.xml'), 'rb') as f:
        items = read_items(f.read())
    with open(os.path.join(base, 'items.otb'), 'rb') as f:
        cids = otb_client_ids(f.read())
    table, notes = build(items, cids)
    return render(table), table, notes


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    out = DEFAULT_OUT
    if '--out' in argv:
        i = argv.index('--out')
        out = argv[i + 1]
        args = [a for a in args if a != out]
    if len(args) != 1:
        print(__doc__)
        return 2
    text, table, notes = generate(args[0])
    for n in notes:
        print('note:', n)
    if '--check' in argv:
        cur = open(out, encoding='utf-8').read() if os.path.exists(out) else ''
        if cur != text:
            print('%s is not up to date' % out)
            return 1
        print('%s is up to date (%d fields)' % (out, len(table)))
        return 0
    with open(out, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('wrote %s (%d fields)' % (out, len(table)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
