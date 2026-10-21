#!/usr/bin/env python3
"""Model test of base patch 0110 (console lines drawn over each other).

The engine is not built in CI, so this models the parts that decide where a console line is drawn:
  * UIWidget::setRect: the rect changes now, onGeometryChange runs one event later and only if the rect differs from
    the one it had when that event was scheduled (0110: otherwise onGeometryRestored runs);
  * UITextEdit::update: places the glyphs for the rect it has at that moment (screen coordinates), auto-resizes the
    height to the wrapped text; onGeometryChange (and with 0110 onGeometryRestored) runs it again;
  * UIVerticalLayout with align-bottom (consoleBuffer), UILayout::update / updateLater, setVisible / moveChildToIndex /
    reorderChildren updating the layout;
  * game_console after 0056: shared hidden labels, internalUpdateLastLabel (rotate, updateLabel, show, move to the
    bottom), internalUpdateLabels (first IMMEDIATE lines now, the rest one event later), Message:updateLabel ending in
    show(), and game_cosmetics / game_chatlinks setting the coloured text after it.
A line whose glyphs were placed for another rect is drawn where they are. Run: python3 -I client/tools/console_glyphs_test.py
"""
import os
import random
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PATCH = os.path.join(ROOT, 'client', 'base-patches', '0110-console-line-glyphs-follow-rect.patch')

VIEW_H = 80                      # consoleBuffer padding rect at the default console height, about five lines
FONT_H, Y_OFFSET, LINE_STEP = 14, -1, 11   # verdana-11px-monochrome: height 14, y-offset -1, spacing 0 -3
CHAR_W = 6


class Dispatcher:
    def __init__(self):
        self.events = []

    def add(self, fn):
        self.events.append(fn)

    def poll(self):
        loops = 0
        while self.events and loops <= 100:
            batch, self.events = self.events, []
            for fn in batch:
                fn()
            loops += 1


class Model:
    def __init__(self, restored_hook, max_lines, immediate):
        self.restored_hook = restored_hook
        self.max_lines = max_lines
        self.immediate = immediate
        self.d = Dispatcher()
        self.buffer = Widget(self, None)
        self.buffer.layout = BottomLayout(self, self.buffer, left=2, bottom=VIEW_H - 2, width=380)
        self.labels = []
        for i in range(max_lines):
            label = TextEdit(self, self.buffer)
            label.hide()
            self.labels.append(label)
        self.pending = None
        self.d.poll()


def empty(rect):
    return rect[2] <= 0 or rect[3] <= 0


class Widget:
    def __init__(self, model, parent):
        self.m = model
        self.rect = (0, 0, 0, 0)
        self.visible = True
        self.children = []
        self.parent = parent
        self.layout = None
        self.event_scheduled = False
        self.margin_left = 0
        if parent:
            parent.children.append(self)
            if parent.layout:
                parent.layout.update()

    def set_rect(self, rect):
        if rect == self.rect:
            return False
        old = self.rect
        self.rect = rect
        self.update_layout()
        if not self.event_scheduled:
            self.event_scheduled = True

            def fire(old=old):
                self.event_scheduled = False
                if old != self.rect:
                    self.on_geometry_change(old, self.rect)
                elif self.m.restored_hook:
                    self.on_geometry_restored()
            self.m.d.add(fire)
        return True

    def on_geometry_change(self, old, new):
        pass

    def on_geometry_restored(self):
        pass

    def update_layout(self):
        if self.layout:
            self.layout.update()
        if self.parent and self.parent.layout:
            self.parent.layout.update_later()

    def set_visible(self, visible):
        if self.visible != visible:
            self.visible = visible
            if self.parent:
                self.parent.update_layout()

    def show(self):
        self.set_visible(True)

    def hide(self):
        self.set_visible(False)

    def move_child_to_index(self, child, index):
        self.children.remove(child)
        self.children.insert(index - 1, child)
        self.update_layout()

    def reorder_children(self, children):
        self.children = list(children)
        self.update_layout()


class BottomLayout:
    def __init__(self, model, widget, left, bottom, width):
        self.m = model
        self.w = widget
        self.left, self.bottom, self.width = left, bottom, width
        self.updating = False
        self.scheduled = False

    def update(self):
        if self.updating:
            self.update_later()
            return
        self.updating = True
        y = self.bottom
        for child in reversed(self.w.children):
            if not child.visible:
                continue
            h = child.rect[3]
            y -= h
            width = self.width - child.margin_left
            child.set_rect((self.left + (self.width - width) // 2, y, width, h))
        self.updating = False

    def update_later(self):
        if self.scheduled:
            return
        self.scheduled = True

        def run():
            self.scheduled = False
            self.update()
        self.m.d.add(run)


def text_height(text, width):
    if not text:
        return FONT_H
    per_line = max(1, width // CHAR_W)
    lines = max(1, -(-len(text) // per_line))
    return Y_OFFSET + FONT_H + LINE_STEP * (lines - 1)


class TextEdit(Widget):
    def __init__(self, model, parent):
        self.text = ''
        self.glyphs_rect = None
        Widget.__init__(self, model, parent)
        self.margin_left = 2
        self.rect = (0, 0, 0, FONT_H)

    def update(self):
        if empty(self.rect):
            return
        x, y, w, _ = self.rect
        self.set_rect((x, y, w, text_height(self.text, w)))
        self.glyphs_rect = self.rect

    def set_colored_text(self, text):
        self.text = text
        self.update()

    def on_geometry_change(self, old, new):
        self.update()

    def on_geometry_restored(self):
        if self.glyphs_rect != self.rect:
            self.update()


class Tab:
    def __init__(self, max_lines):
        self.messages = [None] * max_lines
        self.active = 0


def update_label(text, label, coloured):
    label.set_colored_text(text)      # Message:updateLabel ...
    label.show()                      # ... ends in show()
    if coloured:                      # game_cosmetics name colour / game_chatlinks link colour, after it
        label.set_colored_text(text)


def flush(m):
    p, m.pending = m.pending, None
    if p:
        p()


def add_message(m, tab, text, coloured):
    tab.messages.pop(0)
    tab.messages.append((text, coloured))
    tab.active = min(m.max_lines, tab.active + 1)
    flush(m)
    first = m.labels.pop(0)
    m.labels.append(first)
    update_label(text, first, coloured)
    first.show()
    m.buffer.move_child_to_index(first, m.max_lines)


def fill(m, tab, message, label, i):
    if i <= tab.active:
        label.show()
        update_label(message[0], label, message[1])
    else:
        label.hide()


def update_labels(m, tab):
    m.pending = None
    for i in range(1, m.max_lines + 1):
        mi = m.max_lines - i + 1
        label = m.labels[mi - 1]
        label.index = mi
        if i <= m.immediate:
            fill(m, tab, tab.messages[mi - 1] or ('', False), label, i)
        else:
            label.hide()
    m.labels.sort(key=lambda l: l.index)
    m.buffer.reorder_children(m.labels)

    def rest():
        for i in range(m.immediate + 1, m.max_lines + 1):
            mi = m.max_lines - i + 1
            fill(m, tab, tab.messages[mi - 1] or ('', False), m.labels[mi - 1], i)
    m.pending = rest
    m.d.add(lambda: m.pending is rest and flush(m))


def stale_lines(m):
    """Visible lines in view whose glyphs are not where the label is."""
    return [(l.rect, l.glyphs_rect) for l in m.buffer.children
            if l.visible and l.text and l.glyphs_rect != l.rect and l.rect[1] < VIEW_H and l.rect[1] + l.rect[3] > 0]


def owner_report(restored_hook):
    """Two long lines, a tab switch, then short lines, the last two with a coloured name."""
    m = Model(restored_hook, max_lines=6, immediate=2)
    tabs = [Tab(6), Tab(6)]
    cur = tabs[0]
    for step in [('msg', 90, False), ('msg', 90, False), ('switch',), ('msg', 10, False), ('msg', 10, True),
                 ('msg', 10, True), ('msg', 10, False), ('msg', 90, True)]:
        if step[0] == 'switch':
            cur = tabs[1]
            update_labels(m, cur)
        else:
            add_message(m, cur, 'x' * step[1], step[2])
        m.d.poll()
    return m, stale_lines(m)


def sweep(restored_hook, seeds=150, steps=60):
    bad = 0
    for seed in range(seeds):
        rnd = random.Random(seed)
        m = Model(restored_hook, max_lines=12, immediate=4)
        tabs = [Tab(12), Tab(12)]
        cur = 0
        for _ in range(steps):
            r = rnd.random()
            if r < 0.7:
                n, coloured, which = rnd.choice([10, 30, 60, 90]), rnd.random() < 0.5, rnd.randrange(2)
                if which == cur:
                    add_message(m, tabs[cur], 'x' * n, coloured)
                else:
                    t = tabs[which]
                    t.messages.pop(0)
                    t.messages.append(('x' * n, coloured))
                    t.active = min(12, t.active + 1)
            elif r < 0.85:
                cur = 1 - cur
                update_labels(m, tabs[cur])
            else:
                update_labels(m, tabs[cur])  # slow mode, NPC chat and the read-only tab render the same tab again
            m.d.poll()
            if stale_lines(m):
                bad += 1
                break
    return bad


def main():
    fails = []

    m, stale = owner_report(restored_hook=False)
    newest = m.buffer.children[-1]
    if not stale or newest.rect[1] + newest.rect[3] != VIEW_H - 2 or newest.glyphs_rect[1] > 10:
        fails.append('stock rule: the newest line should be drawn near the top, got %r' % (stale,))
    m, stale = owner_report(restored_hook=True)
    if stale:
        fails.append('0110 rule: lines drawn away from their labels: %r' % (stale,))

    stock = sweep(restored_hook=False)
    fixed = sweep(restored_hook=True)
    if stock == 0:
        fails.append('stock rule: the sweep should find a stale line')
    if fixed:
        fails.append('0110 rule: %d sweep runs with a stale line' % fixed)

    try:
        with open(PATCH, encoding='utf-8') as f:
            patch = f.read()
    except OSError:
        patch = ''
        fails.append('missing %s' % PATCH)
    for needle in ('+                self->onGeometryRestored();', '+void UITextEdit::onGeometryRestored()',
                   '+    m_glyphsRect = m_rect;', '+    if(m_glyphsRect != m_rect)'):
        if patch and needle not in patch:
            fails.append('0110 lacks: %s' % needle.strip())

    for f in fails:
        print('FAIL', f)
    print('console_glyphs_test: stock sweep %d stale runs, 0110 sweep %d; %s'
          % (stock, fixed, 'FAILED' if fails else 'ok'))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
