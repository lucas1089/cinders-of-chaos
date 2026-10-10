#!/usr/bin/env python3
"""Turns the stock market off for players: the Chaos market (data/scripts/chaos/market.lua) replaces it.

usage: python3 -I patch_market.py DATA_DIR [--dry-run]

data/actions/actions.xml: every `<action ... function="market" ... />` line (the market item of the depot lockers,
item 14405) is commented out. Without it nothing puts a character into the stock market, so the client cannot browse,
create or accept stock market offers (the engine refuses those packets outside the market). market.lua registers the
same item id instead: using it opens the Chaos market window. The stock market's own config.lua settings and tables are
left alone (offers made before stay in `market_offers`, unreachable).

Idempotent: a commented line carries a marker and is not changed again. Run it again after replacing the base files.
"""
import os, re, sys

MARKER = 'Chaos: stock market off (patch_market.py)'
LINE = re.compile(r'^([ \t]*)(<action\b[^>]*\bfunction="market"[^>]*/>)[ \t]*$', re.M)


def patch_actions(text):
    """returns (new text, status) with status 'patched', 'already' or an error message"""
    hits = list(LINE.finditer(text))
    if not hits:
        if MARKER in text:
            return text, 'already'
        return text, 'no function="market" action found in actions.xml'
    out, last = [], 0
    for m in hits:
        out.append(text[last:m.start()])
        out.append('%s<!-- %s: %s -->' % (m.group(1), MARKER, m.group(2).replace('--', '- -')))
        last = m.end()
    out.append(text[last:])
    return ''.join(out), 'patched'


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1:
        print(__doc__.strip().splitlines()[2])
        return 2
    path = os.path.join(args[0], 'actions', 'actions.xml')
    if not os.path.isfile(path):
        print('%s: not found' % path)
        return 1
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    new, st = patch_actions(text)
    if st not in ('patched', 'already'):
        print('actions/actions.xml: %s' % st)
        return 1
    if st == 'patched' and not dry:
        with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
    print('actions/actions.xml: %s%s' % (st, ' (dry run, not written)' if dry and st == 'patched' else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
