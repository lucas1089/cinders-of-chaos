#!/usr/bin/env python3
"""Corpses stay at most 5 minutes (idempotent).

usage: python3 -I patch_corpse_decay.py DATA_DIR [--dry-run]

Owner, 2026-10-20 (beta, the ground label "Corpse: 1 item 20:41"): "reduza esses timers pra 5min no máximo" and "o
tempo em que os corpos ficam no chão pra 5min também". A corpse decays through stages (items.xml decayTo + duration):
fresh with the loot, decayed (often still a container), then remains. In data/items/items.xml every chain of corpse
items (corpseType set) is shortened so that the whole chain, from the first stage to the last, lasts at most MAX_S
seconds: when a chain is longer, every stage's duration is scaled down by the same factor (at least 1 s each), so the
stages keep their proportions and the loot stage, the longest, gets most of the time. A chain within MAX_S is left as
it is, so a second run changes nothing. Only single-id <item id="..."> entries are changed; a corpse defined by a
fromid/toid range is reported and kept.
"""
import os, re, sys

MAX_S = 300
ATTR = re.compile(r'<attribute\s+key="([^"]+)"\s+value="([^"]*)"\s*/>', re.I)


def parse(text):
    """id -> {duration, decayTo, corpse, span (start, end of the duration value)}; ranges listed apart"""
    items, ranges = {}, []
    for m in re.finditer(r'<item\b([^>]*)>', text):
        head = m.group(1)
        if head.rstrip().endswith('/'):
            continue
        end = text.find('</item>', m.end())
        if end < 0:
            continue
        body_start = m.end()
        body = text[body_start:end]
        attrs = {}
        spans = {}
        for a in ATTR.finditer(body):
            key = a.group(1).lower()
            attrs[key] = a.group(2)
            spans[key] = (body_start + a.start(2), body_start + a.end(2))
        if 'corpsetype' not in attrs:
            continue
        idm = re.search(r'\bid="(\d+)"', head)
        if not idm:
            ranges.append(head.strip())
            continue
        try:
            dur = int(attrs.get('duration', '0') or 0)
            to = int(attrs.get('decayto', '0') or 0)
        except ValueError:
            continue
        items[int(idm.group(1))] = {'duration': dur, 'decayTo': to, 'span': spans.get('duration')}
    return items, ranges


def chains(items):
    """lists of ids, from each first stage (no corpse decays into it) to the last corpse stage"""
    targets = {v['decayTo'] for v in items.values()}
    out = []
    for start in sorted(items):
        if start in targets:
            continue
        chain, seen, cur = [], set(), start
        while cur in items and cur not in seen:
            seen.add(cur)
            chain.append(cur)
            cur = items[cur]['decayTo']
        out.append(chain)
    return out


def plan(items):
    """id -> new duration. Chains can share their later stages (two corpses that decay into the same remains), so the
    scaling repeats until every chain fits: each pass shortens the stages of the chains still over MAX_S."""
    cur = {i: v['duration'] for i, v in items.items()}
    for _ in range(20):
        over = False
        for chain in chains(items):
            total = sum(cur[i] for i in chain)
            if total <= MAX_S:
                continue
            over = True
            k = MAX_S / float(total)
            for i in chain:
                if cur[i] > 0:
                    cur[i] = max(1, int(cur[i] * k))
        if not over:
            break
    return {i: d for i, d in cur.items() if d != items[i]['duration'] and items[i]['span']}


def patch_text(text):
    items, ranges = parse(text)
    new = plan(items)
    edits = sorted(((items[i]['span'], v) for i, v in new.items()), reverse=True)
    for (a, b), v in edits:
        text = text[:a] + str(v) + text[b:]
    return text, len(new), ranges


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1:
        print(__doc__)
        return 2
    path = os.path.join(args[0], 'items', 'items.xml')
    if not os.path.isfile(path):
        print('no items.xml: %s' % path)
        return 1
    text = open(path, encoding='latin-1').read()
    new, n, ranges = patch_text(text)
    if n and not dry:
        open(path, 'w', encoding='latin-1', newline='').write(new)
    print('corpse decay: %d stage(s) shortened so every corpse lasts at most %d s%s'
          % (n, MAX_S, ' (dry run)' if dry else ''))
    if ranges:
        print('  kept (fromid/toid ranges): %d' % len(ranges))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
