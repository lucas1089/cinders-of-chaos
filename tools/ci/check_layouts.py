#!/usr/bin/env python3
"""Client .otui layout check: no fit-children box layout on an anchor-sized widget.

A widget whose box layout has `fit-children: true` resizes itself to its
children. If the same widget also has its size fixed by anchors on that axis
(anchors.fill, or top+bottom for a verticalBox, left+right for a horizontalBox)
the layout and the anchors fight: each resize schedules another relayout and
the client logs "ATTENTION the event list is not getting empty" forever
(setRect / internalUpdate / updateLater), even while the window is hidden.

Only the widget's own lines are checked (not inherited styles).
Run from the repo root: python3 -I tools/ci/check_layouts.py
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
MODULES = ROOT / 'client' / 'overlay' / 'modules'


def parse(path):
    """Return a list of (indent, text, lineno, children) trees."""
    root = (-1, '', 0, [])
    stack = [root]
    for no, raw in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
        text = raw.strip()
        if not text or text.startswith('//'):
            continue
        indent = len(raw) - len(raw.lstrip(' '))
        while stack[-1][0] >= indent:
            stack.pop()
        node = (indent, text, no, [])
        stack[-1][3].append(node)
        stack.append(node)
    return root


def prop(text):
    if ':' not in text:
        return None, None
    key, _, value = text.partition(':')
    return key.strip(), value.strip()


def check_widget(path, node, errors):
    anchors = set()
    layout_type, fit = None, False
    for child in node[3]:
        key, value = prop(child[1])
        if key is None:
            continue
        if key.startswith('anchors.'):
            anchors.add(key[len('anchors.'):])
        elif key == 'layout':
            if value:
                layout_type = value
            for sub in child[3]:
                k, v = prop(sub[1])
                if k == 'type':
                    layout_type = v
                elif k == 'fit-children':
                    fit = v == 'true'
    if not fit:
        return
    if layout_type == 'verticalBox':
        fixed = 'fill' in anchors or {'top', 'bottom'} <= anchors
    elif layout_type == 'horizontalBox':
        fixed = 'fill' in anchors or {'left', 'right'} <= anchors
    else:
        fixed = 'fill' in anchors
    if fixed:
        rel = path.relative_to(ROOT)
        errors.append('%s:%d: %s has %s fit-children and anchors %s fixing that size '
                      '(relayout loop: drop fit-children or an anchor)'
                      % (rel, node[2], node[1], layout_type, ', '.join(sorted(anchors))))


def walk(path, node, errors):
    for child in node[3]:
        key, _ = prop(child[1])
        if key is None:  # a widget or style declaration
            check_widget(path, child, errors)
        walk(path, child, errors)


def main():
    errors = []
    files = sorted(MODULES.glob('*/*.otui'))
    for path in files:
        walk(path, parse(path), errors)
    for e in errors:
        print(e)
    if errors:
        return 1
    print('check_layouts: %d .otui files ok' % len(files))
    return 0


if __name__ == '__main__':
    sys.exit(main())
