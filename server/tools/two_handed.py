#!/usr/bin/env python3
"""Two-handed weapons attack slower: give every two-handed weapon in items.xml an attack speed of 1.5x its current one
(the vocation default 2000 ms when it has none, so 3000 ms; 1800 -> 2700). The extra damage per hit is applied by
server/data/scripts/chaos/weapon_styles.lua (x1.6), so the weapon ends up slightly ahead of one hand + shield.

usage: python3 -I two_handed.py DATA_DIR [--dry-run]

Idempotent: a two-handed weapon whose attackspeed is already >= 2700 is taken as done (the base server's own
values are 1800-2000). Only items with slotType two-handed and a weaponType of sword, axe, club or distance change.
"""
import os, re, sys

FACTOR = 1.5
DEFAULT_SPEED = 2000
DONE_FROM = 2700
WEAPON_TYPES = ('sword', 'axe', 'club', 'distance')


def attrs(body):
    return dict(re.findall(r'key="(\w+)"\s+value="([^"]*)"', body))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    dry = '--dry-run' in sys.argv
    if len(args) != 1:
        print(__doc__)
        return 1
    path = os.path.join(args[0], 'items', 'items.xml')
    s = open(path, encoding='utf-8', errors='surrogateescape').read()
    changed = []

    def item(m):
        head, body = m.group(1), m.group(2)
        a = attrs(body)
        if a.get('slotType', '').lower() != 'two-handed' or a.get('weaponType', '').lower() not in WEAPON_TYPES:
            return m.group(0)
        current = int(a['attackspeed']) if a.get('attackspeed', '').isdigit() else None
        if current is not None and current >= DONE_FROM:
            return m.group(0)
        speed = int(round((current or DEFAULT_SPEED) * FACTOR))
        if current is None:
            indent = re.search(r'\n(\s*)<attribute', body)
            pad = indent.group(1) if indent else '\t\t'
            body = re.sub(r'(\s*)$', lambda e: '\n%s<attribute key="attackspeed" value="%d" />%s' % (pad, speed, e.group(1)), body, count=1)
        else:
            body = re.sub(r'(key="attackspeed"\s+value=")\d+(")', lambda e: e.group(1) + str(speed) + e.group(2), body, count=1)
        changed.append((re.search(r'id="(\d+)"', head).group(1), current or DEFAULT_SPEED, speed))
        return head + body + '</item>'

    out = re.sub(r'(<item\b[^>]*[^/]>)(.*?)</item>', item, s, flags=re.S)
    if changed and not dry:
        open(path, 'w', encoding='utf-8', errors='surrogateescape').write(out)
    for iid, old, new in changed[:10]:
        print(f'  {iid}: {old} -> {new} ms')
    print(f'{len(changed)} two-handed weapons {"would be " if dry else ""}slowed down')
    return 0


if __name__ == '__main__':
    sys.exit(main())
