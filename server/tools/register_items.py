#!/usr/bin/env python3
"""Idempotently merge data/items/chaos_items.xml into the server's data/items/items.xml (replace by server id, add if absent).

usage: python3 -I register_items.py ITEMS_XML CHAOS_ITEMS_XML [--otb ITEMS_OTB] [--dry-run]
  e.g. python3 -I tools/register_items.py data/items/items.xml data/items/chaos_items.xml --otb data/items/items.otb

Checks before touching anything (exit 1 on a problem):
  * chaos_items.xml is well-formed, every <item> has a numeric id, no duplicate ids / names
  * every id exists in items.otb (if --otb given; server ids, attribute 0x10)
  * every <attribute key> is one the Exodus parser knows (list copied from src/items.cpp ItemParseAttributesMap)
Replacement is textual: the stock <item id="N" ...>...</item> block (or self-closing tag) is replaced in place, so the rest of
items.xml keeps its formatting and comments. Items not present are appended before </items>. A .bak copy is written once.
The stock entry of every replaced id is OVERRIDDEN, i.e. the old name/stats are gone for every use of that id (NPC shops,
monster loot, quests): that is the point of this tool, but check data/ for references if you care.
"""
import os, re, struct, sys
import xml.etree.ElementTree as ET

KNOWN = {
    'type', 'description', 'runespellname', 'weight', 'showcount', 'armor',
    'defense', 'extradef', 'attack', 'attackspeed', 'rarity', 'rotateto',
    'wrapid', 'unwrapid', 'moveable', 'movable', 'blockprojectile', 'allowpickupable',
    'pickupable', 'forceserialize', 'forcesave', 'floorchange', 'corpsetype', 'containersize',
    'fluidsource', 'readable', 'writeable', 'maxtextlen', 'writeonceitemid', 'weapontype',
    'slottype', 'ammotype', 'shoottype', 'effect', 'range', 'stopduration',
    'decayto', 'transformequipto', 'transformdeequipto', 'duration', 'showduration', 'charges',
    'showcharges', 'showattributes', 'hitchance', 'maxhitchance', 'invisible', 'speed',
    'healthgain', 'healthticks', 'managain', 'manaticks', 'manashield', 'skillsword',
    'skillaxe', 'skillclub', 'skilldist', 'skillfish', 'skillmining', 'skillwoodcutting',
    'skillcrafting', 'skillherbalist', 'skillarmorsmith', 'skillweaponsmith', 'skilljewelsmith', 'skillshield',
    'skillfist', 'maxhitpoints', 'maxhitpointspercent', 'maxmanapoints', 'maxmanapointspercent', 'magicpoints',
    'magiclevelpoints', 'magicpointspercent', 'criticalhitchance', 'criticalhitamount', 'lifeleechchance', 'lifeleechamount',
    'manaleechchance', 'manaleechamount', 'fieldabsorbpercentenergy', 'fieldabsorbpercentfire', 'fieldabsorbpercentpoison', 'fieldabsorbpercentearth',
    'absorbpercentall', 'absorbpercentallelements', 'absorbpercentelements', 'absorbpercentmagic', 'absorbpercentenergy', 'absorbpercentfire',
    'absorbpercentpoison', 'absorbpercentearth', 'absorbpercentice', 'absorbpercentholy', 'absorbpercentdeath', 'absorbpercentwater',
    'absorbpercentarcane', 'absorbpercentlifedrain', 'absorbpercentmanadrain', 'absorbpercentdrown', 'absorbpercentphysical', 'absorbpercenthealing',
    'absorbpercentundefined', 'suppressdrunk', 'suppressenergy', 'suppressfire', 'suppresspoison', 'suppressdrown',
    'suppressphysical', 'suppressfreeze', 'suppressdazzle', 'suppresscurse', 'suppresssplashed', 'suppressbewitched',
    'field', 'replaceable', 'partnerdirection', 'leveldoor', 'maletransformto', 'malesleeper',
    'femaletransformto', 'femalesleeper', 'transformto', 'destroyto', 'elementice', 'elementearth',
    'elementfire', 'elementenergy', 'elementdeath', 'elementwater', 'elementarcane', 'elementholy',
    'walkstack', 'blocking', 'allowdistread', 'storeitem'
}

TOK = re.compile(rb'\xfd.|\xfe|\xff', re.S)
UNESC = re.compile(rb'\xfd(.)', re.S)


def otb_ids(path):
    """server ids in items.otb (same node walk as tools/check_monsters.py otb_ids)"""
    d = open(path, 'rb').read()
    pending, first, valid, spans = None, True, set(), []
    for m in TOK.finditer(d, 4):
        s = m.group()
        if len(s) == 2: continue
        pos = m.start()
        if pending is not None:
            spans.append((pending[0], pending[1], pos)); pending = None
        if s == b'\xfe': pending = (d[pos + 1], pos + 2)
    for _t, a, b in spans:
        if first: first = False; continue
        pl = UNESC.sub(rb'\1', d[a:b]); k = 4
        while k + 3 <= len(pl):
            at, ln = pl[k], struct.unpack_from('<H', pl, k + 1)[0]; k += 3
            if at == 0x10 and ln == 2: valid.add(struct.unpack_from('<H', pl, k)[0])
            k += ln
    return valid


def validate(chaos_path, otb_path):
    problems, ids, names = [], {}, set()
    root = ET.parse(chaos_path).getroot()
    for it in root.iter('item'):
        iid = it.get('id')
        if not iid or not iid.isdigit():
            problems.append('item without numeric id: %r' % it.attrib); continue
        iid = int(iid)
        if iid in ids: problems.append('duplicate id %d' % iid)
        ids[iid] = it
        nm = (it.get('name') or '').lower()
        if not nm: problems.append('id %d has no name' % iid)
        elif nm in names: problems.append('duplicate name %r' % nm)
        names.add(nm)
        for a in it.findall('attribute'):
            k = (a.get('key') or '').lower()
            if k not in KNOWN: problems.append('id %d: unknown attribute %r' % (iid, a.get('key')))
            if a.get('value') is None: problems.append('id %d: attribute %r without value' % (iid, k))
    if otb_path:
        valid = otb_ids(otb_path)
        for iid in ids:
            if iid not in valid: problems.append('id %d is not in items.otb' % iid)
    return ids, problems


def block_re(iid):
    # optional '<!-- N: ... -->' comment line we wrote + <item id="N" ...>...</item>  or  <item id="N" ... />
    return re.compile(r'(?:[ \t]*<!-- %d: [^\n]*-->\n)?[ \t]*<item\s+[^>]*?\bid="%d"[^>]*?(?:/>|>.*?</item>)[ \t]*\n?' % (iid, iid), re.S)


def main():
    a = [x for x in sys.argv[1:] if not x.startswith('--')]
    otb = sys.argv[sys.argv.index('--otb') + 1] if '--otb' in sys.argv else None
    if otb in a: a.remove(otb)
    dry = '--dry-run' in sys.argv
    if len(a) != 2:
        print(__doc__); return 2
    items_xml, chaos_xml = a
    ids, problems = validate(chaos_xml, otb)
    for p in problems: print('PROBLEM:', p)
    if problems: return 1
    t = open(items_xml, encoding='utf-8', errors='surrogateescape').read()
    chaos_text = open(chaos_xml, encoding='utf-8').read()
    # one text block per item (keep our formatting + the preceding comment)
    blocks = {}
    for m in re.finditer(r'(?:[ \t]*<!--[^\n]*-->\n)?[ \t]*<item\s+id="(\d+)".*?</item>\n', chaos_text, re.S):
        blocks[int(m.group(1))] = m.group(0)
    assert set(blocks) == set(ids), 'could not split chaos_items.xml into blocks'
    replaced = added = 0
    for iid in sorted(blocks):
        blk = blocks[iid]
        rx = block_re(iid)
        hits = rx.findall(t)
        if len(hits) > 1: print('PROBLEM: id %d appears %d times in %s' % (iid, len(hits), items_xml)); return 1
        if hits:
            if hits[0].strip() != blk.strip(): replaced += 1
            t = rx.sub(lambda m: blk, t, count=1)
        else:
            added += 1
            t = t.replace('</items>', blk + '</items>')
    ET.fromstring(t.encode('utf-8', 'surrogateescape'))  # result must still be well-formed
    print('%d items: %d replaced/changed, %d added, %d unchanged%s' % (len(blocks), replaced, added, len(blocks) - replaced - added, ' (dry run)' if dry else ''))
    if not dry:
        bak = items_xml + '.bak'
        if not os.path.exists(bak): open(bak, 'w', encoding='utf-8', errors='surrogateescape').write(open(items_xml, encoding='utf-8', errors='surrogateescape').read())
        open(items_xml, 'w', encoding='utf-8', errors='surrogateescape').write(t)
    return 0


if __name__ == '__main__':
    sys.exit(main())
