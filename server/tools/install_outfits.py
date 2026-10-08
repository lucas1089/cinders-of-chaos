#!/usr/bin/env python3
"""Add the Chaos class outfits to a base server's data/XML/outfits.xml.

usage: python3 -I install_outfits.py DATA_DIR [--dry-run]

Reads Chaos.classes.outfits from data/scripts/chaos/chaos_constants.lua (look type and name per class) and writes one
<outfit> line per look type for each sex (type 0 and 1, same name, so the store's Sex Change pairs them), locked
(unlocked="no": ascension.lua gives them). The lines sit in a block between two marker comments before </outfits>;
the block is rewritten when the list changed. A look type that already has an entry outside the block stops the
script (nothing is written). Idempotent: a second run changes nothing.

The look types exist only in the client pair that has the class outfits (client/tools/sprites/import_outfits.py,
outfits 1505-1510); install both, or the outfits show as nothing in the client.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CONSTANTS = os.path.join(os.path.dirname(HERE), 'data', 'scripts', 'chaos', 'chaos_constants.lua')
BEGIN = '\t<!-- Chaos class outfits (server/tools/install_outfits.py, do not edit by hand) -->\n'
END = '\t<!-- end of the Chaos class outfits -->\n'


def class_outfits(path=CONSTANTS):
    """[(lookType, name)] in the order of Chaos.classes.outfits"""
    text = open(path, encoding='utf-8').read()
    m = re.search(r'\n\toutfits = \{\n(.*?)\n\t\},?\n', text, re.S)
    if not m:
        sys.exit('%s: no Chaos.classes.outfits block' % path)
    found = re.findall(r'lookType\s*=\s*(\d+)\s*,\s*name\s*=\s*"([^"]+)"', m.group(1))
    if not found:
        sys.exit('%s: Chaos.classes.outfits has no entries' % path)
    return [(int(t), n) for t, n in found]


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1:
        print(__doc__)
        return 2
    path = os.path.join(args[0], 'XML', 'outfits.xml')
    if not os.path.isfile(path):
        print('missing ' + path)
        return 1
    text = open(path, encoding='utf-8', errors='surrogateescape').read()
    rest = re.sub(re.escape(BEGIN) + r'.*?' + re.escape(END), '', text, flags=re.S)
    outfits = class_outfits()
    taken = {int(t) for t in re.findall(r'looktype="(\d+)"', rest)}
    clash = sorted(t for t, _ in outfits if t in taken)
    if clash:
        print('outfits.xml already has look type(s) %s outside the Chaos block; nothing written' % clash)
        return 1
    lines = ''.join('\t<outfit type="%d" looktype="%d" name="%s" premium="no" unlocked="no" enabled="yes" />\n'
                    % (sex, look, name) for sex in (0, 1) for look, name in outfits)
    at = rest.rfind('</outfits>')
    if at < 0:
        print(path + ': no </outfits>')
        return 1
    new = rest[:at] + BEGIN + lines + END + rest[at:]
    if new == text:
        print('outfits.xml: %d class outfits already installed' % len(outfits))
        return 0
    if not dry:
        open(path, 'w', encoding='utf-8', errors='surrogateescape').write(new)
    print('outfits.xml: %d class outfits written (%d lines)%s' % (len(outfits), 2 * len(outfits),
                                                                  ' (dry run)' if dry else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
