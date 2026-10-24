#!/usr/bin/env python3
"""A creatures.xml of the Chaos monsters for the map editor, so they can be placed (and their spawns shown) in it.

usage: python3 -I tools/windows/editor_creatures.py OUT.xml MONSTER_DIR [MONSTER_DIR ...]

Reads every monster / npc XML under the given folders (name and <look type/head/body/legs/feet/addons or typeex>) and
writes OUT.xml with one <creature type="monster|npc" .../> line per name (sorted; the first file of a name wins). The
map editor reads the server's Lua monsters itself (Server Workspace), but this server's monsters are XML files, so
this file is its "user" creature list: <editor folder>\\data\\user\\data\\1098\\creatures.xml. It is written new each
time (nothing is merged, running it again gives the same bytes). Used by .github/workflows/windows-package.yml.
"""
import os
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import quoteattr


def creatures(dirs):
    found = {}
    for top in dirs:
        for root, subdirs, files in os.walk(top):
            subdirs.sort()
            for name in sorted(files):
                if not name.endswith('.xml'):
                    continue
                path = os.path.join(root, name)
                try:
                    node = ET.parse(path).getroot()
                except ET.ParseError as e:
                    print(f'skip {path}: {e}', file=sys.stderr)
                    continue
                if node.tag not in ('monster', 'npc') or not node.get('name'):
                    continue
                look = node.find('look')
                if look is None:
                    continue
                attrs = {'name': node.get('name'), 'type': node.tag}
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


def render(found):
    lines = ['<?xml version="1.0"?>\n', '<creatures>\n']
    for _, attrs in sorted(found.items()):
        lines.append('\t<creature ' + ' '.join(f'{k}={quoteattr(v)}' for k, v in attrs.items()) + ' />\n')
    lines.append('</creatures>\n')
    return ''.join(lines)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    out, dirs = sys.argv[1], sys.argv[2:]
    found = creatures(dirs)
    if not found:
        print(f'{out}: no monster or npc with a <look> under {dirs}', file=sys.stderr)
        return 1
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, 'w', encoding='utf-8', newline='\n') as f:
        f.write(render(found))
    print(f'{out}: {len(found)} creature(s)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
