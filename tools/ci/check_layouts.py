#!/usr/bin/env python3
"""Client .otui layout checks: no fit-children box layout on an anchor-sized widget, no anchor cycle.

A widget whose box layout has `fit-children: true` resizes itself to its
children. If the same widget also has its size fixed by anchors on that axis
(anchors.fill, or top+bottom for a verticalBox, left+right for a horizontalBox)
the layout and the anchors fight: each resize schedules another relayout and
the client logs "ATTENTION the event list is not getting empty" forever
(setRect / internalUpdate / updateLater), even while the window is hidden.

Anchor cycles: two sibling widgets anchored to each other, on any axis (a.right: b.left and b.verticalCenter:
a.verticalCenter), make the client log "anchor dependency cycle detected ... layout update aborted" each layout pass and
leave the widgets where they were (the Auto Seller window's item row, live test 2026-10-14). The anchors of the widgets
declared side by side under one parent are followed (anchors.fill / centerIn included; prev and next are the sibling
declared before and after, so a widget whose id is "next" cannot be reached by name: the candlemark window's "week" label
was anchored to `next.bottom`, its next sibling, which was anchored to "week" (log 2026-10-16)).

Handlers: an `@onClick:` (any `@on...:` line or `|` block) runs in the global environment, not in the module's. A
sandboxed module's function called bare (`hide()`, `toggle()`) is nil there and the handler throws (passivetree and daily,
2026-10-16; bank's Escape). Every call in a handler must be qualified (`modules.<name>.fn()`, `self:fn()`, `obj.fn()`),
a function the handler defines itself, or a global of KNOWN_GLOBALS.

Only the widget's own lines are checked (not inherited styles).
Run from the repo root: python3 -I tools/ci/check_layouts.py
"""
import pathlib
import re
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


# globals a handler may call bare: Lua's own and the client's corelib / gamelib ones
KNOWN_GLOBALS = {
    'tr', 'print', 'pairs', 'ipairs', 'next', 'type', 'tostring', 'tonumber', 'pcall', 'xpcall', 'select', 'error',
    'assert', 'unpack', 'rawget', 'rawset', 'setmetatable', 'getmetatable', 'require', 'dofile',
    'scheduleEvent', 'addEvent', 'removeEvent', 'cycleEvent', 'connect', 'disconnect', 'signalcall',
    'displayInfoBox', 'displayErrorBox', 'displayCancelBox', 'displayGeneralBox', 'formatShortNumber',
    'toboolean', 'fromboolean', 'comma_value', 'tocolor',
}
LUA_WORDS = {'function', 'if', 'then', 'else', 'elseif', 'end', 'and', 'or', 'not', 'return', 'local', 'for', 'in',
             'do', 'while', 'repeat', 'until', 'nil', 'true', 'false', 'break', 'goto'}
_BARE_CALL = re.compile(r'(?<![\w.:])([A-Za-z_]\w*)\s*\(')
_STRING = re.compile(r"'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"")
_DEFINED = re.compile(r'\bfunction\s+([A-Za-z_]\w*)\s*\(|\blocal\s+function\s+([A-Za-z_]\w*)|\blocal\s+([A-Za-z_]\w*)\s*=')


def bare_calls(code):
    """names called bare in handler code that are not Lua words, known globals or defined in the code itself"""
    code = _STRING.sub('""', code)
    code = re.sub(r'--[^\n]*', '', code)
    defined = {n for m in _DEFINED.finditer(code) for n in m.groups() if n}
    return sorted({n for n in _BARE_CALL.findall(code)
                   if n not in LUA_WORDS and n not in KNOWN_GLOBALS and n not in defined})


def check_handlers(path, errors):
    lines = path.read_text(encoding='utf-8').splitlines()
    i = 0
    while i < len(lines):
        m = re.match(r'^(\s*)(@on\w*):\s*(.*)$', lines[i])
        if not m:
            i += 1
            continue
        indent, name, code = len(m.group(1)), m.group(2), m.group(3)
        j = i + 1
        if code.strip() == '|':
            code = ''
            while j < len(lines) and (not lines[j].strip() or len(lines[j]) - len(lines[j].lstrip()) > indent):
                code += lines[j] + '\n'
                j += 1
        for bare in bare_calls(code):
            errors.append('%s:%d: %s calls %s() bare: handlers run in the global environment, so a sandboxed '
                          "module's function is nil there (write modules.<module>.%s())" % (shown(path), i + 1, name,
                                                                                              bare, bare))
        i = j


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
        rel = shown(path)
        errors.append('%s:%d: %s has %s fit-children and anchors %s fixing that size '
                      '(relayout loop: drop fit-children or an anchor)'
                      % (rel, node[2], node[1], layout_type, ', '.join(sorted(anchors))))


def shown(path):
    try:
        return path.relative_to(ROOT)
    except ValueError:
        return path


def anchor_targets(node, prev_id=None, next_id=None):
    """the sibling ids a widget node's own anchors point at (prev / next: the siblings declared before / after)"""
    out = set()
    for child in node[3]:
        key, value = prop(child[1])
        if key and key.startswith('anchors.') and value:
            target = value.split('.')[0].strip()
            if target == 'prev':
                target = prev_id
            elif target == 'next':
                target = next_id
            if target and target not in ('parent', 'none'):
                out.add(target)
    return out


def check_cycles(path, node, errors):
    """anchor cycles among the widgets declared under `node`"""
    graph, lines = {}, {}
    widgets = []
    for child in node[3]:
        key, _ = prop(child[1])
        if key is not None:
            continue
        wid = None
        for sub in child[3]:
            k, v = prop(sub[1])
            if k == 'id':
                wid = v
        widgets.append((wid or '#%d' % child[2], child))  # a widget without id can still be prev / next
    for i, (wid, child) in enumerate(widgets):
        prev_id = widgets[i - 1][0] if i > 0 else None
        next_id = widgets[i + 1][0] if i + 1 < len(widgets) else None
        graph[wid] = anchor_targets(child, prev_id, next_id)
        lines[wid] = child[2]
    state = {}

    def visit(n, stack):
        state[n] = 1
        stack.append(n)
        for t in sorted(graph.get(n, ())):
            if t not in graph:
                continue
            if state.get(t) == 1:
                cycle = stack[stack.index(t):] + [t]
                rel = shown(path)
                errors.append('%s:%d: anchor cycle %s (the client aborts the layout: anchor one of them elsewhere)'
                              % (rel, lines[t], ' -> '.join(cycle)))
            elif t not in state:
                visit(t, stack)
        stack.pop()
        state[n] = 2

    for n in sorted(graph):
        if n not in state:
            visit(n, [])


def walk(path, node, errors):
    check_cycles(path, node, errors)
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
        check_handlers(path, errors)
    for e in errors:
        print(e)
    if errors:
        return 1
    print('check_layouts: %d .otui files ok' % len(files))
    return 0


if __name__ == '__main__':
    sys.exit(main())
