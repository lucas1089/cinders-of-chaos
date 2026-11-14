#!/usr/bin/env python3
"""Hub menu tree check (O550, client/MANIFEST.md "Menu hubs").

The top menu is six hubs (bar badges) with tabs and cards: client/overlay/modules/client_chaos_topbar/topbar_tree.lua
(hub -> tab -> card text) and topbar_cards.lua (card text -> glyph slot and one line). Every window a module registers
with ChaosTopBar.addEntry (or the CATEGORIES list of chaos_topbar.lua) must have a card, or be named on purpose in
DROPPED, SHARED, TEXT_ONLY or NPC_ONLY, so a new module can never vanish from the menu without this check failing.
It also fails when:
  - a card names an entry nobody registers, a card is listed twice, a hub has more than 6 tabs or a tab more than 6 cards;
  - a card has no glyph or no line, a line is longer than 34 characters, a glyph is not drawn by client/tools/topbar_glyphs.py,
    or a glyph is used twice on one tab;
  - an entry with a hotkey is not on the first tab of its hub (two clicks from the bar);
  - a hub name, a tab name or a card line has no pt-BR text (client_chaos_locale/pt_br.lua).

  python3 -I tools/ci/check_topbar_tree.py
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MOD = os.path.join(ROOT, 'client', 'overlay', 'modules')
TOPBAR = os.path.join(MOD, 'client_chaos_topbar')
MAX_HUBS, MAX_TAB_CARDS, MAX_LINE = 6, 6, 34


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def lua_str(s):
    return s.replace("\\'", "'").replace('\\\\', '\\')


Q = r"'((?:[^'\\]|\\.)*)'"


def parse_tree(text):
    """{'hubs': [{id, name, glyph, tabs: [{id, name, cards}]}], 'category_hub', 'dropped', 'shared', 'text_only'}"""
    hubs, cur = [], None
    for line in text.split('\n'):
        m = re.match(r"\s*\{ id = %s, name = %s, glyph = %s, tabs = \{\s*$" % (Q, Q, Q), line)
        if m:
            cur = {'id': lua_str(m.group(1)), 'name': lua_str(m.group(2)), 'glyph': lua_str(m.group(3)), 'tabs': []}
            hubs.append(cur)
            continue
        m = re.match(r"\s*\{ id = %s, name = %s, cards = \{(.*)\} \},\s*$" % (Q, Q), line)
        if m and cur is not None:
            cards = [lua_str(c) for c in re.findall(Q, m.group(3))]
            cur['tabs'].append({'id': lua_str(m.group(1)), 'name': lua_str(m.group(2)), 'cards': cards})

    def table(name):
        m = re.search(r'^T\.%s = \{(.*?)\}\s*$' % name, text, re.M | re.S)
        return m.group(1) if m else ''

    category_hub = dict((lua_str(a), lua_str(b)) for a, b in re.findall(r"(\w+) = '(\w+)'", table('CATEGORY_HUB')))
    dropped = set(lua_str(x) for x in re.findall(r"\['((?:[^'\\]|\\.)*)'\] = true", table('DROPPED')))
    text_only = set(lua_str(x) for x in re.findall(r"\['((?:[^'\\]|\\.)*)'\] = true", table('TEXT_ONLY')))
    pin_only = set(lua_str(x) for x in re.findall(r"\['((?:[^'\\]|\\.)*)'\] = true", table('PIN_ONLY')))
    shared = dict((lua_str(a), lua_str(b)) for a, b in re.findall(r"\['((?:[^'\\]|\\.)*)'\] = '((?:[^'\\]|\\.)*)'", table('SHARED')))
    return {'hubs': hubs, 'category_hub': category_hub, 'dropped': dropped, 'shared': shared, 'text_only': text_only,
            'pin_only': pin_only}


def parse_cards(text):
    cards = {}
    for m in re.finditer(r"^\s*\[%s\] = \{ %s, %s \},\s*$" % (Q, Q, Q), text, re.M):
        cards[lua_str(m.group(1))] = (lua_str(m.group(2)), lua_str(m.group(3)))
    icon_glyph = {}
    m = re.search(r'^C\.ICON_GLYPH = \{(.*?)^\}', text, re.M | re.S)
    if m:
        icon_glyph = dict(re.findall(r"(\w+) = '(\w+)'", m.group(1)))
    fm = re.search(r"^C\.FALLBACK_GLYPH = '(\w+)'", text, re.M)
    return {'cards': cards, 'icon_glyph': icon_glyph, 'fallback': fm.group(1) if fm else None}


def parse_glyph_names(text):
    m = re.search(r'^NAMES = \((.*?)\)', text, re.M | re.S)
    return set(re.findall(r"'(\w+)'", m.group(1))) if m else set()


def parse_npc_only(text):
    m = re.search(r'^T\.NPC_ONLY = \{(.*)\}\s*$', text, re.M)
    return set(re.findall(r"\['((?:[^'\\]|\\.)*)'\] = true", m.group(1))) if m else set()


def parse_pt_br(text):
    out = {}
    for m in re.finditer(r'^\s*\["((?:[^"\\]|\\.)*)"\] = "((?:[^"\\]|\\.)*)",?\s*$', text, re.M):
        out[m.group(1).replace('\\"', '"')] = m.group(2)
    return out


def registered_from_topbar(text):
    """{text: {'key': hotkey or ''}} of the entries of the CATEGORIES list (sub-menu headers left out)"""
    start = text.index('local CATEGORIES')
    end = text.index('local CATEGORY_ALIAS')
    out = {}
    for line in text[start:end].split('\n'):
        m = re.match(r"\s*entry\(%s,\s*'\w+',\s*(.*)$" % Q, line)
        if not m or 'sub = {' in m.group(2):
            continue
        k = re.search(r"key = '([^']+)'", m.group(2))
        out[lua_str(m.group(1))] = {'key': k.group(1) if k else '', 'where': 'chaos_topbar.lua'}
    return out


def registered_from_modules(files):
    """entries the modules add: files = {relative path: source}. Returns (entries, unreadable calls)"""
    out, bad = {}, []
    for name, src in sorted(files.items()):
        calls = len(re.findall(r'api\.addEntry,', src))
        found = 0
        for m in re.finditer(r"api\.addEntry,\s*'(\w+)',\s*(?:\n\s*)?(\{[^\n]*\}|menuEntry)(?:,\s*'(\w+)')?", src):
            body = m.group(2)
            if body == 'menuEntry':
                mm = re.search(r"menuEntry = (\{[^\n]*\})", src)
                if not mm:
                    continue
                body = mm.group(1)
            t = re.search(r"text = %s" % Q, body)
            if not t:
                continue
            found += 1
            k = re.search(r"key = '([^']+)'", body)
            out[lua_str(t.group(1))] = {'key': k.group(1) if k else '', 'where': name, 'category': m.group(1)}
        if found != calls:
            bad.append('%s: %d addEntry call(s), %d readable' % (name, calls, found))
    return out, bad


def problems(tree, cards, glyph_names, registered, npc_only, pt_br):
    out = []
    hubs = tree['hubs']
    if not hubs:
        out.append('topbar_tree.lua: no hubs read')
    if len(hubs) > MAX_HUBS:
        out.append('%d hubs, at most %d fit the bar' % (len(hubs), MAX_HUBS))
    placed, where, ids = {}, {}, set()
    for hub in hubs:
        if hub['id'] in ids:
            out.append('hub id twice: ' + hub['id'])
        ids.add(hub['id'])
        if hub['glyph'] not in glyph_names:
            out.append('hub %s: glyph %r is not drawn by topbar_glyphs.py' % (hub['id'], hub['glyph']))
        if ('hub.' + hub['id']) not in pt_br or not pt_br['hub.' + hub['id']]:
            out.append('hub %s: no pt-BR name (key hub.%s)' % (hub['id'], hub['id']))
        tab_ids = set()
        for ti, tab in enumerate(hub['tabs']):
            if tab['id'] in tab_ids:
                out.append('tab id twice in %s: %s' % (hub['id'], tab['id']))
            tab_ids.add(tab['id'])
            key = 'tab.%s.%s' % (hub['id'], tab['id'])
            if key not in pt_br or not pt_br[key]:
                out.append('tab %s/%s: no pt-BR name (key %s)' % (hub['id'], tab['id'], key))
            if not 1 <= len(tab['cards']) <= MAX_TAB_CARDS:
                out.append('tab %s/%s holds %d cards (1 to %d)' % (hub['id'], tab['id'], len(tab['cards']), MAX_TAB_CARDS))
            glyphs_here = {}
            for text in tab['cards']:
                if text in placed:
                    out.append('card twice: ' + text)
                placed[text] = (hub, tab)
                where[text] = ti
                spec = cards['cards'].get(text)
                if not spec:
                    out.append('card %r has no glyph and line in topbar_cards.lua' % text)
                    continue
                glyph, line = spec
                if glyph not in glyph_names:
                    out.append('card %r: glyph %r is not drawn by topbar_glyphs.py' % (text, glyph))
                if glyph in glyphs_here:
                    out.append('glyph %r used twice on tab %s/%s: %s and %s' % (glyph, hub['id'], tab['id'], glyphs_here[glyph], text))
                glyphs_here[glyph] = text
                if not 0 < len(line) <= MAX_LINE:
                    out.append('card %r: its line is %d characters (1 to %d)' % (text, len(line), MAX_LINE))
                if not pt_br.get(line):
                    out.append('card %r: the line %r has no pt-BR text' % (text, line))
    for text in cards['cards']:
        if text not in placed and text not in tree.get('pin_only', ()):
            out.append('topbar_cards.lua names %r, which is on no tab' % text)
    for cat, hub_id in tree['category_hub'].items():
        if hub_id not in ids:
            out.append('CATEGORY_HUB %s -> %s: no such hub' % (cat, hub_id))
    for slot_text, slot in tree['shared'].items():
        if slot not in placed:
            out.append('SHARED %r points at %r, which is no card' % (slot_text, slot))
    for icon, glyph in cards['icon_glyph'].items():
        if glyph not in glyph_names:
            out.append('ICON_GLYPH %s: glyph %r is not drawn' % (icon, glyph))
    if cards['fallback'] not in glyph_names:
        out.append('FALLBACK_GLYPH %r is not drawn' % cards['fallback'])
    for text in npc_only:
        if text in placed:
            out.append('%r opens from its NPC, not from a card' % text)
    allowed = set(placed) | tree.get('pin_only', set()) | tree['dropped'] | tree['text_only'] | set(tree['shared']) | npc_only
    for text in sorted(registered):
        if text not in allowed:
            out.append('entry %r (%s) has no card: add it to a tab of topbar_tree.lua and to topbar_cards.lua, or to DROPPED' % (text, registered[text].get('where', '?')))
    for text in sorted(placed):
        if text not in registered:
            out.append('card %r: no module registers an entry with this text' % text)
    for text, info in sorted(registered.items()):
        if info.get('key') and text in placed and where[text] != 0:
            out.append('%r has the hotkey %s but is not on the first tab of its hub' % (text, info['key']))
    return out


def tracked_module_files():
    try:
        names = subprocess.check_output(['git', '-C', ROOT, 'grep', '-l', 'api.addEntry,', '--', 'client/overlay/modules'], text=True).split()
    except subprocess.CalledProcessError:
        names = []
    return [n for n in names if not n.endswith('_test.lua') and '/client_chaos_topbar/' not in n]


def main():
    tree = parse_tree(read(os.path.join(TOPBAR, 'topbar_tree.lua')))
    cards = parse_cards(read(os.path.join(TOPBAR, 'topbar_cards.lua')))
    glyph_names = parse_glyph_names(read(os.path.join(ROOT, 'client', 'tools', 'topbar_glyphs.py')))
    npc_only = parse_npc_only(read(os.path.join(TOPBAR, 'topbarlogic.lua')))
    pt_br = parse_pt_br(read(os.path.join(MOD, 'client_chaos_locale', 'pt_br.lua')))
    registered = registered_from_topbar(read(os.path.join(TOPBAR, 'chaos_topbar.lua')))
    files = dict((n, read(os.path.join(ROOT, n))) for n in tracked_module_files())
    added, bad = registered_from_modules(files)
    registered.update(added)
    found = problems(tree, cards, glyph_names, registered, npc_only, pt_br) + bad
    for p in found:
        print('topbar tree: ' + p)
    ncards = sum(len(t['cards']) for h in tree['hubs'] for t in h['tabs'])
    print('topbar tree: %d hubs, %d tabs, %d cards, %d entries registered: %s' % (
        len(tree['hubs']), sum(len(h['tabs']) for h in tree['hubs']), ncards, len(registered), 'OK' if not found else '%d problem(s)' % len(found)))
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main())
