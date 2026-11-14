#!/usr/bin/env python3
"""Close control check of the hub menu windows (O572, client/MANIFEST.md "Windows open centred").

Owner 2026-11-14: the Forge window had no X to close it. Every window the hub menu (and the text menu) opens must have a
way to close it that a player can see: a widget of the window block in its .otui that is a close control, that is
  - the style ChaosCloseX (client_chaos_theme/styles.otui, the X in the top right corner), WindowCloseButton or CloseButton, or
  - a widget whose id holds "close" or "cancel" (closeButton, closeX, cancelButton, buttonCancel ...), or
  - a button whose text is Close or Cancel (or Fechar, Cancelar): a dialog closes by its Cancel button.
The windows are the window blocks (a window style or an instance of a window class, followed through the style chain) of
every module the menu registers: the modules named in the CATEGORIES list of chaos_topbar.lua and every module that calls
api.addEntry. A window that must not close, or that closes by its own answer buttons, is named in ALLOWED with the reason.

  python3 -I tools/ci/check_window_close.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MOD = os.path.join(ROOT, 'client', 'overlay', 'modules')

# window id (or style name for a window made from a style) -> why it has no close control
ALLOWED = {
    'presenceCheckWindow': 'anti-bot check: the player must answer it, it cannot be closed',
    'DescentOfferWindow': 'an offer: Accept / Decline buttons close it, a static window',
    'GqCheckWindow': 'ready check of the group queue: Accept / Decline close it',
    'MentorOfferWindow': 'an offer: Accept / Decline buttons close it',
    'PartyInvitedWindow': 'an invitation: Accept / Decline buttons close it',
    'ConfirmWindow': 'a yes / no question of the supply stash, not a window of the menu',
}

WINDOW_BASES = ('UIWindow', 'MainWindow', 'Window', 'MiniMainWindow')
CLOSE_STYLES = ('ChaosCloseX', 'WindowCloseButton', 'CloseButton')
Q = r"'((?:[^'\\]|\\.)*)'"


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def hub_modules(topbar_text, module_sources):
    """module names the menu registers: modules = { 'x' } of CATEGORIES, and every module with an api.addEntry call"""
    mods = set()
    start = topbar_text.index('local CATEGORIES')
    end = topbar_text.index('local CATEGORY_ALIAS')
    mods |= set(re.findall(r"'((?:game|client)_\w+)'", topbar_text[start:end]))
    for name, src in module_sources.items():
        if 'api.addEntry,' in src:
            mods.add(name)
    return mods


def split_blocks(text):
    """top level blocks of an .otui file: [(head line, [lines])]"""
    blocks, cur = [], None
    for line in text.split('\n'):
        line = line.rstrip('\r')
        if not line.strip() or line.lstrip().startswith('//'):
            continue
        if not line[0].isspace():
            cur = (line.strip(), [])
            blocks.append(cur)
        elif cur is not None:
            cur[1].append(line)
    return blocks


def parse_head(head):
    m = re.match(r'^(\w+)\s*<\s*(\w+)\s*$', head)
    if m:
        return m.group(1), m.group(2), True      # name, base, is a style
    m = re.match(r'^(\w+)\s*$', head)
    if m:
        return m.group(1), None, False           # an instance: the class is the head
    return None, None, False


def style_chain(styles, name):
    out, seen = [], set()
    while name and name not in seen:
        seen.add(name)
        out.append(name)
        name = styles.get(name)
    return out


def has_close(body):
    """does the block body (the lines under the head) hold a close control"""
    cls = None
    for line in body:
        s = line.strip()
        deep = (len(line) - len(line.lstrip())) >= 4    # a child widget, not a property of the window itself
        m = re.match(r'^(\w+)\s*$', s)
        if m and (len(line) - len(line.lstrip())) >= 2:
            cls = m.group(1)
            if cls in CLOSE_STYLES:
                return True
        m = re.match(r'^id:\s*(\S+)', s)
        if m and deep and ('close' in m.group(1).lower() or 'cancel' in m.group(1).lower()):
            return True
        m = deep and re.match(r'^!?text:\s*(?:tr\(\s*[\'"](.*?)[\'"]\s*\)|[\'"]?(.*?)[\'"]?)\s*$', s)
        if m:
            value = (m.group(1) or m.group(2) or '').strip()
            if value in ('Close', 'Fechar', 'Cancel', 'Cancelar'):
                return True
    return False


def windows_of(module_files):
    """module_files = {module: {path: text}}. Returns [(module, path, id or name, has_close)] of the window blocks"""
    styles = {}
    for files in module_files.values():
        for text in files.values():
            for head, _ in split_blocks(text):
                name, base, is_style = parse_head(head)
                if is_style:
                    styles[name] = base
    out = []
    for module, files in sorted(module_files.items()):
        for path, text in sorted(files.items()):
            for head, body in split_blocks(text):
                name, base, is_style = parse_head(head)
                if not name:
                    continue
                cls = base if is_style else name
                if not any(c in WINDOW_BASES for c in style_chain(styles, cls)):
                    continue
                if is_style and not body:
                    continue    # a name only (client_chaos_theme/compat.otui, admin_fallback.otui): no window
                if is_style and any(re.match(r'^\s*virtual:\s*true\s*$', l) for l in body if re.match(r'^  \S', l)):
                    continue
                idm = None
                for line in body:
                    idm = re.match(r'^  id:\s*(\w+)', line)
                    if idm:
                        break
                wid = idm.group(1) if idm else name
                close = has_close(body)
                if not close and any(c in CLOSE_STYLES for c in style_chain(styles, cls)):
                    close = True
                out.append((module, path, wid, name if is_style else None, close))
    return out


def problems(windows, allowed=ALLOWED):
    out = []
    for module, path, wid, style, close in windows:
        if close:
            continue
        if wid in allowed or (style and style in allowed):
            continue
        out.append('%s: window %s (%s) has no close control: add ChaosCloseX with @onClick, or name it in ALLOWED with the reason' % (
            module, wid, os.path.relpath(path, ROOT).replace(os.sep, '/')))
    seen = set((w[2] for w in windows)) | set((w[3] for w in windows if w[3]))
    for name in allowed:
        if name not in seen:
            out.append('ALLOWED names %s, which is no window of the hub menu: remove it' % name)
    return out


def load():
    topbar = read(os.path.join(MOD, 'client_chaos_topbar', 'chaos_topbar.lua'))
    sources, files = {}, {}
    for module in sorted(os.listdir(MOD)):
        d = os.path.join(MOD, module)
        if not os.path.isdir(d):
            continue
        lua_text, otui = [], {}
        for r, _, fs in os.walk(d):
            for f in sorted(fs):
                p = os.path.join(r, f)
                if f.endswith('.otui'):
                    otui[p] = read(p)
                elif f.endswith('.lua') and not f.endswith('_test.lua') and module != 'client_chaos_topbar':
                    lua_text.append(read(p))
        sources[module] = '\n'.join(lua_text)
        files[module] = otui
    return topbar, sources, files


def main():
    topbar, sources, files = load()
    mods = hub_modules(topbar, sources)
    hub_files = dict((m, f) for m, f in files.items() if m in mods)
    # the styles of every module (a window style may come from the theme), the windows of the hub modules only
    windows = windows_of(dict(files))
    windows = [w for w in windows if w[0] in mods]
    found = problems(windows)
    for p in found:
        print('window close: ' + p)
    print('window close: %d hub modules, %d windows: %s' % (len(hub_files), len(windows), 'OK' if not found else '%d problem(s)' % len(found)))
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main())
