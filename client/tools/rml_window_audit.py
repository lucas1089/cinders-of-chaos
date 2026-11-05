#!/usr/bin/env python3
"""Static audit of the RmlUi window mirror (client_chaos_rmlmirror, O406).

Reads every .otui of client/overlay, resolves each style to its engine class, and for every window defined there
(a top-level widget of class UIWindow, UIMessageBox or UIInputBox) says what the mirror does with it:
  mirror   drawn in RmlUi
  otui     stays in the classic look, with the reason (a widget class the form layer cannot draw, more icons than
           ChaosRmlForm.MAX_IMAGES, chaosNoMirror set in Lua)
It also notes what tends to look wrong in a mirror: Lua-made content it cannot see (an empty container in the .otui),
labels that wrap, buttons narrower than their text in the skin font.

Only what the .otui files say: widgets a module makes in Lua are not seen, and engine base styles (Button, Label...)
are mapped by name (BASE below).

  python3 -I client/tools/rml_window_audit.py            # table of every window
  python3 -I client/tools/rml_window_audit.py --otui     # only the ones that stay classic
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OVERLAY = os.path.join(ROOT, 'client', 'overlay')

# engine base styles (the base client's data/styles, not in this repository) -> engine class
BASE = {
    'UIWidget': 'UIWidget', 'Panel': 'UIWidget', 'FlatPanel': 'UIWidget', 'Image': 'UIWidget',
    'HorizontalSeparator': 'UIWidget', 'VerticalSeparator': 'UIWidget', 'UIWindow': 'UIWindow', 'Window': 'UIWindow',
    'MainWindow': 'UIWindow', 'StaticMainWindow': 'UIWindow', 'StaticWindow': 'UIWindow', 'NewWindow': 'UIWindow',
    'NewHeadlessWindow': 'UIWindow', 'HeadlessWindow': 'UIWindow', 'UIMessageBox': 'UIMessageBox',
    'MessageBox': 'UIMessageBox', 'UIInputBox': 'UIInputBox', 'UIButton': 'UIButton', 'Button': 'UIButton',
    'TabButton': 'UIButton', 'UILabel': 'UILabel', 'Label': 'UILabel', 'GameLabel': 'UILabel', 'FlatLabel': 'UILabel',
    'MenuLabel': 'UILabel', 'UICheckBox': 'UICheckBox', 'CheckBox': 'UICheckBox', 'UIComboBox': 'UIComboBox',
    'ComboBox': 'UIComboBox', 'UITextEdit': 'UITextEdit', 'TextEdit': 'UITextEdit', 'PasswordTextEdit': 'UITextEdit',
    'MultilineTextEdit': 'UITextEdit', 'UISpinBox': 'UISpinBox', 'SpinBox': 'UISpinBox',
    'UIProgressBar': 'UIProgressBar', 'ProgressBar': 'UIProgressBar', 'UIScrollBar': 'UIScrollBar',
    'HorizontalScrollBar': 'UIScrollBar', 'VerticalScrollBar': 'UIScrollBar', 'UIScrollArea': 'UIScrollArea',
    'ScrollablePanel': 'UIScrollArea', 'TextList': 'UIScrollArea', 'UITabBar': 'UITabBar', 'TabBar': 'UITabBar',
    'MoveableTabBar': 'UITabBar', 'UIItem': 'UIItem', 'Item': 'UIItem', 'UICreature': 'UICreature',
    'Creature': 'UICreature', 'UIMiniWindow': 'UIMiniWindow', 'MiniWindow': 'UIMiniWindow', 'UIMap': 'UIMap',
    'UIMinimap': 'UIMinimap', 'UIPopupMenu': 'UIPopupMenu', 'UIPopupScrollMenu': 'UIPopupScrollMenu',
    'UIResizeBorder': 'UIResizeBorder', 'ResizeBorder': 'UIResizeBorder', 'UIRadioGroup': 'UIRadioGroup',
    'UIGraph': 'UIGraph', 'UISprite': 'UISprite', 'UIQrCode': 'UIQrCode', 'UIParticles': 'UIParticles',
}

# client_chaos_rmlform.lua M.KNOWN
KNOWN = {'UIWidget', 'UIWindow', 'UIMessageBox', 'UIInputBox', 'UIScrollArea', 'UITabBar', 'UILabel', 'UIButton',
         'UICheckBox', 'UIComboBox', 'UIScrollBar', 'UITextEdit', 'UISpinBox', 'UIProgressBar', 'UIResizeBorder',
         'UIRadioGroup'}
WINDOWS = {'UIWindow', 'UIMessageBox', 'UIInputBox'}
MAX_IMAGES = 40          # ChaosRmlForm.MAX_IMAGES
SKIN_CHAR_PX = 7.5       # mean width of a character of the skin's 13 dp button font
BUTTON_PAD = 20          # the skin button's left and right padding

NAME = re.compile(r'^( *)([A-Z][A-Za-z0-9_]*)\s*(?:<\s*([A-Za-z0-9_]+))?\s*$')
PROP = re.compile(r'^( *)([!@$&]?[a-z][\w.\-]*(?:\s+!?\$?[\w-]+)*)\s*:\s*(.*)$')


class Node:
    def __init__(self, name, base, depth, path, line):
        self.name, self.base, self.depth, self.path, self.line = name, base, depth, path, line
        self.props, self.children = {}, []


def parse(path, text):
    """Top-level nodes of one .otui (styles have a base, instances do not)."""
    tops, stack = [], []
    for n, raw in enumerate(text.split('\n'), 1):
        line = raw.split('//', 1)[0].rstrip() if not raw.lstrip().startswith('//') else ''
        if not line.strip():
            continue
        m = NAME.match(line)
        if m:
            depth = len(m.group(1))
            node = Node(m.group(2), m.group(3), depth, path, n)
            while stack and stack[-1].depth >= depth:
                stack.pop()
            if stack:
                stack[-1].children.append(node)
            else:
                tops.append(node)
            stack.append(node)
            continue
        m = PROP.match(line)
        if m:
            depth = len(m.group(1))
            while stack and stack[-1].depth >= depth:
                stack.pop()
            if stack:
                stack[-1].props.setdefault(m.group(2), m.group(3).strip())
    return tops


def load(overlay=OVERLAY):
    styles, instances = {}, []
    for dirpath, _, files in os.walk(overlay):
        for f in sorted(files):
            if not f.endswith('.otui'):
                continue
            path = os.path.join(dirpath, f)
            with open(path, encoding='utf-8', errors='replace') as fh:
                for node in parse(os.path.relpath(path, ROOT), fh.read()):
                    if node.base:
                        styles.setdefault(node.name, node)
                    else:
                        instances.append(node)
    return styles, instances


def resolve(name, styles, seen=None):
    """Engine class of a style name, or None when the chain ends in a name BASE does not know."""
    seen = seen or set()
    while name not in BASE:
        if name in seen or name not in styles:
            return None
        seen.add(name)
        name = styles[name].base
    return BASE[name]


def chain(name, styles):
    """The style nodes from the instance's style down to the base (for inherited children and properties)."""
    out, seen = [], set()
    while name in styles and name not in seen:
        seen.add(name)
        out.append(styles[name])
        name = styles[name].base
    return out


def prop(node, styles, key):
    if key in node.props:
        return node.props[key]
    for s in chain(node.name, styles):
        if key in s.props:
            return s.props[key]
    return None


def kids(node, styles):
    out = list(node.children)
    for s in chain(node.name, styles):
        out.extend(s.children)
    return out


def audit_window(win, styles):
    report = {'unsupported': set(), 'unknown': set(), 'images': 0, 'empty': [], 'wrap': [], 'tight': []}

    def visit(node):
        cls = resolve(node.name, styles)
        if cls is None:
            report['unknown'].add(node.name)
            return
        if cls not in KNOWN:
            report['unsupported'].add(cls)
            return
        children = kids(node, styles)
        nid = prop(node, styles, 'id') or node.name
        img = prop(node, styles, 'image-source') or prop(node, styles, 'icon-source') or prop(node, styles, 'icon')
        if cls == 'UIWidget' and not children and img:
            report['images'] += 1
        if cls in ('UIWidget', 'UIScrollArea') and not children and not img and \
                (prop(node, styles, 'layout') is not None or cls == 'UIScrollArea'):
            report['empty'].append(nid)
        if cls == 'UILabel' and prop(node, styles, 'text-wrap') == 'true':
            report['wrap'].append(nid)
        if cls == 'UIButton':
            text = prop(node, styles, '!text') or prop(node, styles, 'text') or ''
            m = re.match(r"""tr\((['"])(.*?)\1\)""", text)
            text = m.group(2) if m else text.strip('"\'')
            width = prop(node, styles, 'width')
            size = prop(node, styles, 'size')
            if not width and size:
                width = size.split()[0]
            if text and width and width.isdigit() and len(text) * SKIN_CHAR_PX + BUTTON_PAD > int(width):
                report['tight'].append('%s (%s px, "%s")' % (nid, width, text))
        for c in children:
            visit(c)

    for c in kids(win, styles):
        visit(c)
    return report


def verdict(win, report):
    if report.get('nomirror'):
        return 'otui', 'chaosNoMirror'
    if report['unsupported']:
        return 'otui', 'draws ' + ', '.join(sorted(report['unsupported']))
    if report['images'] > MAX_IMAGES:
        return 'otui', '%d icons' % report['images']
    return 'mirror', ''


def windows(styles, instances):
    """Window instances of the .otui files, and window styles with an id of their own (made in Lua, the Helper)."""
    out = [n for n in instances if resolve(n.name, styles) in WINDOWS]
    for st in styles.values():
        if 'id' in st.props and resolve(st.name, styles) in WINDOWS:
            out.append(Node(st.name, None, 0, st.path, st.line))
    return out


def no_mirror(win, overlay=OVERLAY):
    """Does the module's Lua mark this window chaosNoMirror (within 3 lines of loading its .otui)?"""
    mod = os.path.join(ROOT, os.path.dirname(win.path))
    otui = os.path.splitext(os.path.basename(win.path))[0]
    load = re.compile(r"""loadUI\(\s*['"]%s['"]""" % re.escape(otui))
    for f in sorted(os.listdir(mod)) if os.path.isdir(mod) else []:
        if not f.endswith('.lua') or f.endswith('_test.lua'):
            continue
        with open(os.path.join(mod, f), encoding='utf-8', errors='replace') as fh:
            lines = fh.read().split('\n')
        for i, line in enumerate(lines):
            if load.search(line) and any('chaosNoMirror' in x for x in lines[i:i + 4]):
                return True
    return False


def main(argv):
    only_otui = '--otui' in argv
    styles, instances = load()
    rows = []
    for win in windows(styles, instances):
        rep = audit_window(win, styles)
        rep['nomirror'] = no_mirror(win)
        v, why = verdict(win, rep)
        if only_otui and v != 'otui':
            continue
        notes = []
        if rep['empty']:
            notes.append('Lua fills: ' + ', '.join(rep['empty'][:4]))
        if rep['tight']:
            notes.append('tight buttons: ' + '; '.join(rep['tight'][:3]))
        if rep['unknown']:
            notes.append('unknown styles: ' + ', '.join(sorted(rep['unknown'])[:4]))
        rows.append((win.path, prop(win, styles, 'id') or win.name, v, why, ' | '.join(notes)))
    rows.sort()
    for path, wid, v, why, notes in rows:
        print('%-6s %-28s %-58s %s %s' % (v, wid, path, why, ('  ' + notes) if notes else ''))
    counts = {}
    for r in rows:
        counts[r[2]] = counts.get(r[2], 0) + 1
    print('windows: %d (%s)' % (len(rows), ', '.join('%s %d' % kv for kv in sorted(counts.items()))))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
