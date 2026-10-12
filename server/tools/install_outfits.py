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
locked (unlocked="no": class_looks.lua gives them at login and at a class change, each with both addons through
Player:addOutfitAddon; outfits.xml has no way to grant addons, and unlocked="yes" would give the look to every
character). Same rules: rewritten when the list changed, refused when a look type has an entry outside the block.
With the pair 19 switch on (class_looks_core.lua L.PAIR19_LOOKS = true) the six classes of L.pair19Looks get their
things_custom19 looks (2161-2172) and their replaced looks stay as "<name> (old)" (on since 2026-10-12); with it off
(the rollback) no line names 2161-2172, so a client on an older pair is never offered them. The pair 20 switch
(L.PAIR20_LOOKS, L.pair20Looks: things_custom20, 2173-2184; off until that pair is on windows-assets) works the same
way for its six classes.

Mounts (MOUNTS below) go into mounts.xml the same way: a marked block before </mounts>; a mount id or client id that
already has an entry outside the block stops the script.

The visual exclusives (data/scripts/chaos/exclusives_config.lua, never sold) add their looks the same way: the
outfits (kind "outfit": male / female look, a third outfits.xml block "Chaos exclusive outfits", locked), the mounts
(kind "mount": id and look, appended to MOUNTS), the wings (kind "wings": a wings.xml block) and the outfit shaders
(kind "shader": a shaders.xml block, only for ids the base file does not have; an id there under another name stops
the script). Base looks of the client pair that no XML line had (exclusives_config.lua lists them).

The look types exist only in the client pair that has them (client/tools/sprites/import_outfits.py, outfits 1505-1510;
import_donor_things.py, the donor B first set, outfits 1551-1561; the faction mounts 2132-2135, things_custom14; the
achievement wings 2140-2142, things_custom17);
install both, or they show as nothing in the client.
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
# (mount id, client look type, name, speed). Bone Steed is sold in the store (shop_config.lua); 142..145 are the faction
# mounts (factions_config.lua quartermasters, Exalted; donor-library looks 2132..2135 of things_custom14, picks.csv rows
# mount_*), never sold (gen_shop_cosmetics.py excludes factions_config.lua mounts)
MOUNTS = [(141, 1561, 'Bone Steed', 30),
          (142, 2132, 'Pyrewarden Charger', 30), (143, 2133, 'Forgeborn Emberwolf', 30),
          (144, 2134, 'Veilrunner', 30), (145, 2135, 'Thornbound Stag', 30)]
EXCLUSIVES = os.path.join(os.path.dirname(HERE), 'data', 'scripts', 'chaos', 'exclusives_config.lua')
XBEGIN = '\t<!-- Chaos exclusive outfits (server/tools/install_outfits.py, do not edit by hand) -->\n'
XEND = '\t<!-- end of the Chaos exclusive outfits -->\n'
WBEGIN = '\t<!-- Chaos wings (server/tools/install_outfits.py, do not edit by hand) -->\n'
WEND = '\t<!-- end of the Chaos wings -->\n'
SBEGIN = '\t<!-- Chaos shaders (server/tools/install_outfits.py, do not edit by hand) -->\n'
SEND = '\t<!-- end of the Chaos shaders -->\n'


def exclusives(path=EXCLUSIVES):
    """{'outfit': [(male, female, name)], 'mount': [(id, look, name, 30)], 'wings': [(id, look, name)],
    'shader': [(id, name)]} of exclusives_config.lua (one entry per line: key, kind, fields, ..., name)"""
    out = {'outfit': [], 'mount': [], 'wings': [], 'shader': []}
    if not os.path.isfile(path):
        return out
    text = open(path, encoding='utf-8').read()
    for m in re.finditer(r'\{key = "[\w]+", kind = "(outfit|mount|wings|shader)", ([^\n]*)\n[^\n]*?name = "([^"]+)"', text):
        kind, fields, name = m.group(1), m.group(2), m.group(3)
        f = dict(re.findall(r'(\w+) = (\d+)', fields))
        if kind == 'outfit':
            out['outfit'].append((int(f['male']), int(f['female']), name))
        elif kind == 'mount':
            out['mount'].append((int(f['id']), int(f['look']), name, 30))
        elif kind == 'wings':
            out['wings'].append((int(f['id']), int(f['look']), name))
        else:
            out['shader'].append((int(f['id']), re.search(r'shader = "([^"]+)"', fields).group(1)))
    return out


def install_block(path, begin, end, close, lines, taken_re, dry, label):
    """a marked block of `lines` before `close`; taken_re finds ids outside the block that clash (list of strings)"""
    if not os.path.isfile(path):
        print('missing ' + path)
        return 1
    text = open(path, encoding='utf-8', errors='surrogateescape').read()
    rest = re.sub(re.escape(begin) + r'.*?' + re.escape(end), '', text, flags=re.S)
    clash = taken_re(rest)
    if clash:
        print('%s already has %s outside the Chaos block; nothing written' % (os.path.basename(path), clash))
        return 1
    at = rest.rfind(close)
    if at < 0:
        print(path + ': no ' + close)
        return 1
    new = rest[:at] + (begin + ''.join(lines) + end if lines else '') + rest[at:]
    if new == text:
        print('%s: %d %s already installed' % (os.path.basename(path), len(lines), label))
        return 0
    if not dry:
        open(path, 'w', encoding='utf-8', errors='surrogateescape').write(new)
    print('%s: %d %s written%s' % (os.path.basename(path), len(lines), label, ' (dry run)' if dry else ''))
    return 0


def install_wings(data, dry, ex):
    rows = ex['wings']
    lines = ['\t<wing id="%d" clientid="%d" name="%s" speed="20" />\n' % r for r in rows]

    def taken(rest):
        ids = {int(x) for x in re.findall(r'<wing\s[^>]*\bid="(\d+)"', rest)}
        looks = {int(x) for x in re.findall(r'clientid="(\d+)"', rest)}
        return [r for r in rows if r[0] in ids or r[1] in looks]
    return install_block(os.path.join(data, 'XML', 'wings.xml'), WBEGIN, WEND, '</wings>', lines, taken, dry, 'Chaos wings')


def install_shaders(data, dry, ex):
    path = os.path.join(data, 'XML', 'shaders.xml')
    if not os.path.isfile(path):
        print('missing ' + path)
        return 1
    text = open(path, encoding='utf-8', errors='surrogateescape').read()
    rest = re.sub(re.escape(SBEGIN) + r'.*?' + re.escape(SEND), '', text, flags=re.S)
    base = {int(i): n for i, n in re.findall(r'<shader\s[^>]*\bid="(\d+)"[^>]*\bname="([^"]*)"', rest)}
    clash = [(i, n) for i, n in ex['shader'] if i in base and base[i] != n]
    if clash:
        print('shaders.xml has id(s) %s under another name outside the Chaos block; nothing written' % clash)
        return 1
    rows = [(i, n) for i, n in ex['shader'] if i not in base]
    lines = ['\t<shader id="%d" name="%s" premium="no" />\n' % r for r in rows]
    return install_block(path, SBEGIN, SEND, '</shaders>', lines, lambda r: [], dry, 'Chaos shaders')


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
    """[(name, male look, female look)] in vocation id order: L.looks, with the pair switches applied
    (L.PAIR19_LOOKS / L.PAIR20_LOOKS = true: the L.pair19Looks / L.pair20Looks ids replace their class's look, and the
    replaced looks follow as "<name> (old)" so the characters that own them can still wear them; class_looks_core.lua
    L.applyPairs)"""
    text = open(path, encoding='utf-8').read()
    m = re.search(r'L\.looks = \{(.*?)\n\}', text, re.S)
    if not m:
        sys.exit('%s: no L.looks block' % path)
    rows = re.findall(r'\[(\d+)\] = \{name = "([^"]+)", male = (\d+), female = (\d+)\}', m.group(1))
    if not rows:
        sys.exit('%s: L.looks has no entries' % path)
    new = {}
    for n in (19, 20):
        if re.search(r'^L\.PAIR%d_LOOKS = true$' % n, text, re.M):
            new.update(pair_looks(text, n))
    looks, former = [], []
    for v, n, a, b in sorted(rows, key=lambda r: int(r[0])):
        if int(v) in new:
            looks.append((n, new[int(v)][0], new[int(v)][1]))
            former.append((n + ' (old)', int(a), int(b)))
        else:
            looks.append((n, int(a), int(b)))
    return looks + former


def pair_looks(text, n=19):
    """{vocation id: (male, female)} of the L.pair<n>Looks block (the things_custom<n> class looks)"""
    m = re.search(r'L\.pair%dLooks = \{(.*?)\n\}' % n, text, re.S)
    if not m:
        sys.exit('no L.pair%dLooks block' % n)
    return {int(v): (int(a), int(b)) for v, a, b in
            re.findall(r'\[(\d+)\] = \{male = (\d+), female = (\d+)\}', m.group(1))}


def install_class_looks(path, rest, original, dry):
    """rest: outfits.xml without the class looks block; returns (new text, exit code)"""
    looks = class_looks()
    taken = {int(t) for t in re.findall(r'looktype="(\d+)"', rest)}
    clash = sorted({t for _, m, f in looks for t in (m, f) if t in taken})
    if clash:
        print('outfits.xml already has look type(s) %s outside the class looks block; nothing written' % clash)
        return rest, 1
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
    mounts = MOUNTS + exclusives()['mount']
    clash = [m for m in mounts if m[0] in ids or m[1] in looks]
    if clash:
        print('mounts.xml already has mount id / client id of %s outside the Chaos block; nothing written' % clash)
        return 1
    lines = ''.join('\t<mount id="%d" clientid="%d" name="%s" speed="%d" premium="no" />\n' % m for m in mounts)
    at = rest.rfind('</mounts>')
    if at < 0:
        print(path + ': no </mounts>')
        return 1
    new = rest[:at] + MBEGIN + lines + MEND + rest[at:]
    if new == text:
        print('mounts.xml: %d Chaos mounts already installed' % len(mounts))
        return 0
    if not dry:
        open(path, 'w', encoding='utf-8', errors='surrogateescape').write(new)
    print('mounts.xml: %d Chaos mounts written%s' % (len(mounts), ' (dry run)' if dry else ''))
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
    rest = re.sub(re.escape(XBEGIN) + r'.*?' + re.escape(XEND), '', rest, flags=re.S)
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
    new, code = install_class_looks(path, new, re.sub(re.escape(XBEGIN) + r'.*?' + re.escape(XEND), '', text, flags=re.S), dry)
    print('outfits.xml: %d class outfits (%d lines) in their block' % (len(outfits), 2 * len(outfits)))
    if code:
        return code
    # the exclusive outfits (exclusives_config.lua): type 1 = male look, type 0 = female look, locked
    ex = exclusives()
    taken = {int(t) for t in re.findall(r'looktype="(\d+)"', new)}
    clash = sorted({t for m, f, _ in ex['outfit'] for t in (m, f) if t in taken})
    if clash:
        print('outfits.xml already has look type(s) %s outside the exclusive outfits block; nothing written' % clash)
        return 1
    xlines = ''.join('\t<outfit type="%d" looktype="%d" name="%s" premium="no" unlocked="no" enabled="yes" />\n'
                     % (sex, (f if sex == 0 else m), name) for sex in (0, 1) for m, f, name in ex['outfit'])
    if xlines:
        at = new.rfind('</outfits>')
        new = new[:at] + XBEGIN + xlines + XEND + new[at:]
    print('outfits.xml: %d exclusive outfits in their block' % len(ex['outfit']))
    if new != text and not dry:
        open(path, 'w', encoding='utf-8', errors='surrogateescape').write(new)
    code = install_mounts(args[0], dry)
    code = install_wings(args[0], dry, ex) or code
    return install_shaders(args[0], dry, ex) or code


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
