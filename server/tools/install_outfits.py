#!/usr/bin/env python3
"""Add the Chaos class outfits to a base server's data/XML/outfits.xml and the Chaos mounts to data/XML/mounts.xml.

usage: python3 -I install_outfits.py DATA_DIR [--dry-run]

Reads the class outfits (every `lookType = N, name = "..."` pair in the Chaos.classes.outfits block of
data/scripts/chaos/chaos_constants.lua, each once) and writes one
<outfit> line per look type for each sex (type 0 and 1, same name, so the store's Sex Change pairs them), locked
(unlocked="no": ascension.lua gives them). The lines sit in a block between two marker comments before </outfits>;
the block is rewritten when the list changed. A look type that already has an entry outside the block stops the
script (nothing is written). Idempotent: a second run changes nothing.

Mounts (MOUNTS below) go into mounts.xml the same way: a marked block before </mounts>; a mount id or client id that
already has an entry outside the block stops the script.

The look types exist only in the client pair that has them (client/tools/sprites/import_outfits.py, outfits 1505-1510;
import_donor_things.py, the donor B first set, outfits 1551-1561); install both, or they show as nothing in the client.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CONSTANTS = os.path.join(os.path.dirname(HERE), 'data', 'scripts', 'chaos', 'chaos_constants.lua')
BEGIN = '\t<!-- Chaos class outfits (server/tools/install_outfits.py, do not edit by hand) -->\n'
END = '\t<!-- end of the Chaos class outfits -->\n'
MBEGIN = '\t<!-- Chaos mounts (server/tools/install_outfits.py, do not edit by hand) -->\n'
MEND = '\t<!-- end of the Chaos mounts -->\n'
# (mount id, client look type, name, speed); sold in the store (shop_config.lua)
MOUNTS = [(141, 1561, 'Bone Steed', 30)]


def class_outfits(path=CONSTANTS):
    """[(lookType, name)] in the order of the Chaos.classes.outfits block, each look type once"""
    text = open(path, encoding='utf-8').read()
    m = re.search(r'\n\toutfits = (.*?)\n\t(?:\}|end\)\(\)),?\n', text, re.S)
    if not m:
        sys.exit('%s: no Chaos.classes.outfits block' % path)
    found, seen = [], {}
    for t, n in re.findall(r'lookType\s*=\s*(\d+)\s*,\s*name\s*=\s*"([^"]+)"', m.group(1)):
        t = int(t)
        if t in seen:
            if seen[t] != n:
                sys.exit('%s: look type %d has two names (%s, %s)' % (path, t, seen[t], n))
            continue
        seen[t] = n
        found.append((t, n))
    if not found:
        sys.exit('%s: Chaos.classes.outfits has no entries' % path)
    return found


def install_mounts(data, dry):
    path = os.path.join(data, 'XML', 'mounts.xml')
    if not os.path.isfile(path):
        print('missing ' + path)
        return 1
    text = open(path, encoding='utf-8', errors='surrogateescape').read()
    rest = re.sub(re.escape(MBEGIN) + r'.*?' + re.escape(MEND), '', text, flags=re.S)
    ids = {int(x) for x in re.findall(r'<mount\s+id="(\d+)"', rest)}
    looks = {int(x) for x in re.findall(r'clientid="(\d+)"', rest)}
    clash = [m for m in MOUNTS if m[0] in ids or m[1] in looks]
    if clash:
        print('mounts.xml already has mount id / client id of %s outside the Chaos block; nothing written' % clash)
        return 1
    lines = ''.join('\t<mount id="%d" clientid="%d" name="%s" speed="%d" premium="no" />\n' % m for m in MOUNTS)
    at = rest.rfind('</mounts>')
    if at < 0:
        print(path + ': no </mounts>')
        return 1
    new = rest[:at] + MBEGIN + lines + MEND + rest[at:]
    if new == text:
        print('mounts.xml: %d Chaos mounts already installed' % len(MOUNTS))
        return 0
    if not dry:
        open(path, 'w', encoding='utf-8', errors='surrogateescape').write(new)
    print('mounts.xml: %d Chaos mounts written%s' % (len(MOUNTS), ' (dry run)' if dry else ''))
    return 0


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
    else:
        if not dry:
            open(path, 'w', encoding='utf-8', errors='surrogateescape').write(new)
        print('outfits.xml: %d class outfits written (%d lines)%s' % (len(outfits), 2 * len(outfits),
                                                                      ' (dry run)' if dry else ''))
    return install_mounts(args[0], dry)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
