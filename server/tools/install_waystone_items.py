#!/usr/bin/env python3
"""Install the Waystone Tier VII-XV items into a base server (server/README.md "Waystone tiers").

usage: python3 -I install_waystone_items.py DATA_DIR [--dry-run]

Owner 2026-10-23: waystones from monster level 1100 to 2500, +100 a tier. The base server has Waystone Tier I-VI
(29845-29850, level 1100-1600 now); VII-XV (41951-41959, level 1700-2500) are new. data/scripts/chaos/
waystone_tiers_config.lua lists every tier with its item; tools/patch_waystone_hideout.py part 3 lets the base device
take them.

1. data/items/items.otb: each new tier is a copy of a base tier's node (group, flags, every attribute) with its own
   server id, so its look is that base tablet's (no client change, no pair): VII the look of III, VIII-X of IV, XI-XII
   of V, XIII-XV of VI. Appended at the end of the root; a node already there with the same bytes is left alone, one
   with other bytes is replaced, a server id that belongs to another client id stops the script (nothing written).
   items.otb.bak keeps the original the first time; the written file is parsed again and the nodes checked.
2. data/items/items.xml: their entries (name "Waystone Tier VII", the base tablets' weight, a description with the
   monster level) between two marker comments before </items>, rewritten when they changed. An id with an entry
   outside the block stops the script.

Idempotent: a second run changes nothing.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_gems import xml_escape  # noqa: E402
import install_harvest_event as H  # noqa: E402

XML_BEGIN = '\t<!-- Chaos Waystone Tier VII-XV (server/tools/install_waystone_items.py, do not edit by hand) -->\n'
XML_END = '\t<!-- end of the Chaos Waystone Tier VII-XV -->\n'
ROMAN = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII', 'XIII', 'XIV', 'XV']
BASE_IDS = (29845, 29846, 29847, 29848, 29849, 29850)
# tier -> (server id, the base tier whose look it copies); levels as waystone_tiers_config.lua (1100 + 100 a tier)
NEW = {7: (41951, 3), 8: (41952, 4), 9: (41953, 4), 10: (41954, 4), 11: (41955, 5), 12: (41956, 5),
       13: (41957, 6), 14: (41958, 6), 15: (41959, 6)}
WEIGHT = 4000  # the base tablets' weight


def level(tier):
    return 1000 + 100 * tier


def rows():
    out = []
    for tier, (sid, look) in sorted(NEW.items()):
        out.append({'id': sid, 'source_id': BASE_IDS[look - 1], 'tier': tier, 'name': 'Waystone Tier %s' % ROMAN[tier - 1],
                    'description': 'Use this waystone on the waystone device in your hideout or house to open a map of '
                                   'monster level %d.' % level(tier)})
    return out


def xml_block(items):
    body = ''
    for r in items:
        body += ('\t<item id="%d" name="%s">\n'
                 '\t\t<attribute key="description" value="%s" />\n'
                 '\t\t<attribute key="weight" value="%d" />\n'
                 '\t</item>\n' % (r['id'], xml_escape(r['name']), xml_escape(r['description']), WEIGHT))
    return XML_BEGIN + body + XML_END


def patch_xml(text, items):
    block = xml_block(items)
    s = text.find(XML_BEGIN)
    if s >= 0:
        e = text.find(XML_END, s)
        if e < 0:
            raise SystemExit('items.xml: Waystone Tier start marker without end marker')
        outside = text[:s] + text[e + len(XML_END):]
    else:
        outside = text
    ranges = [(int(a), int(b)) for a, b in re.findall(r'fromid="(\d+)"\s+toid="(\d+)"', outside)]
    for r in items:
        sid = r['id']
        if re.search(r'<item\s+id="%d"' % sid, outside) or any(a <= sid <= b for a, b in ranges):
            raise SystemExit('items.xml: id %d already has an entry outside the Waystone Tier block; nothing written' % sid)
    if s >= 0:
        if text[s:e + len(XML_END)] == block:
            return text, 'items.xml: Waystone Tier VII-XV block up to date (%d items)' % len(items)
        return text[:s] + block + text[e + len(XML_END):], 'items.xml: Waystone Tier VII-XV block rewritten'
    end = text.rfind('</items>')
    if end < 0:
        raise SystemExit('items.xml: no </items>')
    return text[:end] + block + text[end:], 'items.xml: Waystone Tier VII-XV block added (%d items)' % len(items)


def main(argv):
    dry = '--dry-run' in argv
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    otb = os.path.join(args[0], 'items', 'items.otb')
    xml = os.path.join(args[0], 'items', 'items.xml')
    if not os.path.exists(otb) or not os.path.exists(xml):
        print('items.otb / items.xml not found in', args[0])
        return 1
    items = rows()
    raw = open(otb, 'rb').read()
    new, notes, wanted = H.patch_otb(raw, items)
    n = H.verify_otb(new, wanted)
    for note in notes:
        print(note)
    print('items.otb: verified (%d item nodes)' % n)
    text = open(xml, encoding='utf-8', errors='surrogateescape').read()
    new_text, xnote = patch_xml(text, items)
    print(xnote)
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
    sys.exit(main(sys.argv[1:]))
