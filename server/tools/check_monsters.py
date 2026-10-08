#!/usr/bin/env python3
"""Validate monster definitions against our server data.

usage: python3 -I check_monsters.py ITEMS_OTB DAT_OUTFIT_COUNT MONSTER_FILE_OR_DIR... [--known NAMES.txt]

Checks per monster (XML <monster> or Lua Game.createMonsterType):
  * lookType <= outfit count of our Tibia.dat (else the client has no sprite)
  * corpse and loot item ids exist in items.otb (server ids)
  * summon names are defined (needs --known with one lowercase name per line)
Prints one line per problem and a summary. Exit 1 if any problem.
"""
import os, re, struct, sys

TOK = re.compile(rb'\xfd.|\xfe|\xff', re.S)
UNESC = re.compile(rb'\xfd(.)', re.S)

def otb_ids(path, with_client=False):
    """set of server ids; with_client=True -> {server id: client id or None} (attribute 0x11)."""
    d = open(path, 'rb').read()
    pending, first, valid = None, True, {}
    spans = []
    for m in TOK.finditer(d, 4):
        s = m.group()
        if len(s) == 2: continue
        pos = m.start()
        if pending is not None:
            spans.append((pending[0], pending[1], pos)); pending = None
        if s == b'\xfe': pending = (d[pos + 1], pos + 2)
    for _t, a, b in spans:
        if first: first = False; continue
        pl = UNESC.sub(rb'\1', d[a:b])
        k = 4
        sid = cid = None
        while k + 3 <= len(pl):
            at, ln = pl[k], struct.unpack_from('<H', pl, k + 1)[0]; k += 3
            if at == 0x10 and ln == 2: sid = struct.unpack_from('<H', pl, k)[0]
            if at == 0x11 and ln == 2: cid = struct.unpack_from('<H', pl, k)[0]
            k += ln
        if sid: valid[sid] = cid
    return valid if with_client else set(valid)

def parse(path):
    t = open(path, errors='ignore').read()
    if path.endswith('.xml'):
        m = re.search(r'<monster\s+name="([^"]+)"', t)
        if not m: return None
        look = re.search(r'<look\s+type="(\d+)"', t)
        corpse = re.search(r'<look[^>]*corpse="(\d+)"', t)
        loot = [int(x) for x in re.findall(r'<item\s+id="(\d+)"', t)]
        summ = re.findall(r'<summon\s+name="([^"]+)"', t)
        return m.group(1), int(look.group(1)) if look else None, int(corpse.group(1)) if corpse else None, loot, summ
    m = re.search(r'createMonsterType\(\s*"([^"]+)"', t)
    if not m: return None
    look = re.search(r'lookType\s*=\s*(\d+)', t)
    corpse = re.search(r'monster\.corpse\s*=\s*(\d+)', t)
    loot = [int(x) for x in re.findall(r'\{\s*id\s*=\s*(\d+)', t)]
    summ = re.findall(r'monster\.summon\s*=.*?\}', t, re.S)
    names = re.findall(r'name\s*=\s*"([^"]+)"', summ[0]) if summ else []
    return m.group(1), int(look.group(1)) if look else None, int(corpse.group(1)) if corpse else None, loot, names

def main():
    args = sys.argv[1:]
    known = set()
    if '--known' in args:
        i = args.index('--known'); known = {l.strip().lower() for l in open(args[i + 1])}; del args[i:i + 2]
    valid, outfits, paths = otb_ids(args[0]), int(args[1]), args[2:]
    files = []
    for p in paths:
        if os.path.isdir(p):
            files += [os.path.join(r, f) for r, _, fs in os.walk(p) for f in fs if f.endswith(('.xml', '.lua'))]
        else: files.append(p)
    bad = total = 0
    for f in sorted(files):
        r = parse(f)
        if not r: continue
        total += 1
        name, look, corpse, loot, summ = r
        probs = []
        if look is not None and look > outfits: probs.append(f'lookType {look} > {outfits} (no sprite)')
        if corpse and corpse not in valid: probs.append(f'corpse {corpse} not in items.otb')
        miss = sorted({i for i in loot if i not in valid})
        if miss: probs.append(f'{len(miss)} loot ids not in items.otb: {miss[:6]}')
        if known:
            ms = [s for s in summ if s.lower() not in known]
            if ms: probs.append(f'undefined summons: {ms}')
        if probs:
            bad += 1; print(f'{name}: ' + '; '.join(probs) + f'  [{os.path.basename(f)}]')
    print(f'{total} monsters checked, {bad} with problems')
    sys.exit(1 if bad else 0)

if __name__ == '__main__':
    main()
