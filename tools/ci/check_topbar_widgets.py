#!/usr/bin/env python3
"""Hub menu widget check (O550, client/MANIFEST.md "Menu hubs").

The hub window and the bar badges are built in Lua (client/overlay/modules/client_chaos_topbar/topbar_hub.lua) from styles
in topbar_hub.otui. The engine is not in CI, so a typo in a widget id would only show in a client. This check reads the two
files as text and fails when:
  - Lua looks up an id (`get(widget, 'id')`, `getChildById('id')`, `recursiveGetChildById('id')`) that no widget of
    topbar_hub.otui (or topbar.otui) declares with `id:`;
  - Lua creates a style (`g_ui.createWidget('Style', ...)`) that no .otui of the module, the theme (styles.otui) or the
    engine styles named in STOCK declares;
  - an anchor of the .otui names a sibling id (`anchors.top: name.bottom`) that no widget of the file declares;
  - the hub window, a card or a badge has no $mobile rule (the phone gets taller cards and bigger text, owner spec O550).

  python3 -I tools/ci/check_topbar_widgets.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODULE = os.path.join(ROOT, 'client', 'overlay', 'modules', 'client_chaos_topbar')
THEME = os.path.join(ROOT, 'client', 'overlay', 'modules', 'client_chaos_theme', 'styles.otui')
LUA_FILES = ('topbar_hub.lua',)
OTUI_FILES = ('topbar_hub.otui', 'topbar.otui')
STOCK = {'UIWidget', 'UIButton', 'UILabel', 'UIWindow'}
MOBILE_STYLES = ('ChaosHubWindow', 'ChaosHubCard', 'ChaosHubBadge')


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def style_blocks(otui):
    """{style name: body text} of the top level styles of an .otui text (`Name < Parent`)"""
    blocks, name, body = {}, None, []
    for line in otui.split('\n'):
        m = re.match(r'^([A-Za-z]\w*)\s*<\s*\w+\s*$', line)
        if m:
            if name:
                blocks[name] = '\n'.join(body)
            name, body = m.group(1), []
        elif name is not None:
            body.append(line)
    if name:
        blocks[name] = '\n'.join(body)
    return blocks


def declared_ids(otui):
    return set(re.findall(r'^\s*id:\s*([A-Za-z_]\w*)\s*$', otui, re.M))


def lua_lookups(lua):
    ids = set(re.findall(r"\bget\(\s*[\w.:]+\s*,\s*'(\w+)'\s*\)", lua))
    ids |= set(re.findall(r":(?:recursiveGetChildById|getChildById)\('(\w+)'\)", lua))
    return ids


def lua_styles(lua):
    return set(re.findall(r"createWidget\(\s*'(\w+)'", lua))


def anchor_problems(blocks, file_ids):
    out = []
    for name, body in blocks.items():
        for m in re.finditer(r'anchors\.\w+:\s*(\w+)\.\w+', body):
            ref = m.group(1)
            if ref not in ('parent', 'prev', 'next') and ref not in file_ids:
                out.append("style %s: anchor to '%s', which no widget of the file declares" % (name, ref))
    return out


def problems(lua_by_file, otui_by_file, theme_otui):
    out = []
    ids = declared_ids('\n'.join(otui_by_file.values()))
    styles = set()
    for text in list(otui_by_file.values()) + [theme_otui]:
        styles |= set(style_blocks(text))
    for fname, lua in sorted(lua_by_file.items()):
        for i in sorted(lua_lookups(lua)):
            if i not in ids:
                out.append("%s looks up the id '%s', which no widget of the .otui declares" % (fname, i))
        for st in sorted(lua_styles(lua)):
            if st not in styles and st not in STOCK:
                out.append("%s creates the style '%s', which no .otui declares" % (fname, st))
    blocks = style_blocks(otui_by_file.get('topbar_hub.otui', ''))
    out += anchor_problems(blocks, declared_ids(otui_by_file.get('topbar_hub.otui', '')))
    for st in MOBILE_STYLES:
        if st in blocks and '$mobile' not in blocks[st]:
            out.append('style %s has no $mobile rule' % st)
    return out


def main():
    lua = {f: read(os.path.join(MODULE, f)) for f in LUA_FILES}
    otui = {f: read(os.path.join(MODULE, f)) for f in OTUI_FILES}
    found = problems(lua, otui, read(THEME))
    for p in found:
        print('topbar widgets: ' + p)
    n_ids = sum(len(lua_lookups(t)) for t in lua.values())
    n_styles = sum(len(lua_styles(t)) for t in lua.values())
    print('topbar widgets: %d ids and %d styles looked up by Lua: %s' % (n_ids, n_styles, 'OK' if not found else '%d problem(s)' % len(found)))
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main())
