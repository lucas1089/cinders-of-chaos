#!/usr/bin/env python3
"""Add the Chaos class outfits to a base server's data/XML/outfits.xml and the Chaos mounts to data/XML/mounts.xml.

usage: python3 -I install_outfits.py DATA_DIR [--dry-run]

Reads the class outfits (every `lookType = N, name = "..."` pair in the Chaos.classes.outfits block of
data/scripts/chaos/chaos_constants.lua, each once) and writes one
<outfit> line per look type for each sex (type 0 and 1, same name, so the store's Sex Change pairs them), locked
(unlocked="no": ascension.lua gives them). The lines sit in a block between two marker comments before </outfits>;
the block is rewritten when the list changed. A look type that already has an entry outside the block stops the
script (nothing is written). Idempotent: a second run changes nothing.

The class looks (class_looks_core.lua ChaosClassLooks.looks: a name and a male and a female look type per class) get
a second marked block: type 1 = the male look, type 0 = the female look (both lines when one look serves both sexes),
locked (unlocked="no": class_looks.lua gives them at login and at a class change). Same rules: rewritten when the list
changed, refused when a look type has an entry outside the block.

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
LOOKS = os.path.join(os.path.dirname(HERE), 'data', 'scripts', 'chaos', 'class_looks_core.lua')
CBEGIN = '\t<!-- Chaos class looks (server/tools/install_outfits.py, do not edit by hand) -->\n'
CEND = '\t<!-- end of the Chaos class looks -->\n'
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


def class_looks(path=LOOKS):
    """[(name, male look, female look)] in vocation id order"""
    text = open(path, encoding='utf-8').read()
    m = re.search(r'L\.looks = \{(.*?)\n\}', text, re.S)
    if not m:
        sys.exit('%s: no L.looks block' % path)
    rows = re.findall(r'\[(\d+)\] = \{name = "([^"]+)", male = (\d+), female = (\d+)\}', m.group(1))
    if not rows:
        sys.exit('%s: L.looks has no entries' % path)
    return [(n, int(a), int(b)) for _, n, a, b in sorted(rows, key=lambda r: int(r[0]))]


def install_class_looks(path, rest, original, dry):
    """rest: outfits.xml without the class looks block; returns (new text, exit code)"""
    looks = class_looks()
    taken = {int(t) for t in re.findall(r'looktype="(\d+)"', rest)}
    clash = sorted({t for _, m, f in looks for t in (m, f) if t in taken})
    if clash:
        print('outfits.xml already has look type(s) %s outside the class looks block; nothing written' % clash)
        return text, 1
    lines = ''.join('\t<outfit type="%d" looktype="%d" name="%s" premium="no" unlocked="no" enabled="yes" />\n'
                    % (sex, look, name) for sex in (0, 1) for name, m, f in looks for look in [(f if sex == 0 else m)])
    at = rest.rfind('</outfits>')
    new = rest[:at] + CBEGIN + lines + CEND + rest[at:]
    print('outfits.xml: %d class looks; %s' % (len(looks), 'already installed' if new == original else
                                                  'written%s' % (' (dry run)' if dry else '')))
    return new, 0


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
    rest = re.sub(re.escape(CBEGIN) + r'.*?' + re.escape(CEND), '', rest, flags=re.S)
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
    new, code = install_class_looks(path, new, text, dry)
    print('outfits.xml: %d class outfits (%d lines) in their block' % (len(outfits), 2 * len(outfits)))
    if code:
        return code
    if new != text and not dry:
        open(path, 'w', encoding='utf-8', errors='surrogateescape').write(new)
    return install_mounts(args[0], dry)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
