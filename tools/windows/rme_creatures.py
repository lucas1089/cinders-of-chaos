#!/usr/bin/env python3
"""Add the Chaos monsters to a map editor creatures.xml, so they can be placed (and their spawns shown) in the editor.

usage: python3 -I tools/windows/rme_creatures.py CREATURES_XML MONSTER_DIR [MONSTER_DIR ...]

Reads every monster XML under the given folders (name and <look type/head/body/legs/feet/addons or typeex>), and adds
a <creature type="monster" .../> line for each name the creatures.xml does not have yet, in a block marked with a
comment, before </creatures>. A name the file already has keeps its line. Running it again changes nothing (the
block is replaced, not repeated). Used by .github/workflows/windows-package.yml for the package's map editor.
"""
import os
import re
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import quoteattr

START = '\t<!-- Chaos monsters (tools/windows/rme_creatures.py) -->\n'
END = '\t<!-- end of Chaos monsters -->\n'


def monsters(dirs):
    found = {}
    for top in dirs:
        for root, _, files in os.walk(top):
            for name in sorted(files):
                if not name.endswith('.xml'):
                    continue
                path = os.path.join(root, name)
                try:
                    node = ET.parse(path).getroot()
                except ET.ParseError as e:
                    print(f'skip {path}: {e}', file=sys.stderr)
                    continue
                if node.tag != 'monster' or not node.get('name'):
                    continue
                look = node.find('look')
                if look is None:
                    continue
                attrs = {'name': node.get('name'), 'type': 'monster'}
                if look.get('typeex'):
                    attrs['lookitem'] = look.get('typeex')
                    attrs['looktype'] = '0'
                else:
                    attrs['looktype'] = look.get('type', '0')
                for src, dst in (('head', 'lookhead'), ('body', 'lookbody'), ('legs', 'looklegs'),
                                 ('feet', 'lookfeet'), ('addons', 'lookaddon')):
                    if look.get(src):
                        attrs[dst] = look.get(src)
                found.setdefault(attrs['name'].lower(), attrs)
    return found


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    path, dirs = sys.argv[1], sys.argv[2:]
    text = open(path, encoding='utf-8', errors='surrogateescape').read()
    # drop an earlier block of this tool
    text = re.sub(re.escape(START) + r'.*?' + re.escape(END), '', text, flags=re.S)
    have = {m.lower() for m in re.findall(r'<creature\s+name="([^"]*)"', text)}
    lines = []
    for key, attrs in sorted(monsters(dirs).items()):
        if key in have:
            continue
        lines.append('\t<creature ' + ' '.join(f'{k}={quoteattr(v)}' for k, v in attrs.items()) + '/>\n')
    at = text.rfind('</creatures>')
    if at < 0:
        print(f'{path}: no </creatures>', file=sys.stderr)
        return 1
    text = text[:at] + START + ''.join(lines) + END + text[at:]
    open(path, 'w', encoding='utf-8', errors='surrogateescape').write(text)
    print(f'{path}: {len(lines)} Chaos monster(s) added')
    return 0


if __name__ == '__main__':
    sys.exit(main())
