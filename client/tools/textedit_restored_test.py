#!/usr/bin/env python3
"""Model test of base patch 0124 (event list never empty: auto resize text edit with anchors on both sides).

The engine is not built in CI, so this models the loop:
  * UIWidget::setRect: the rect changes now, onGeometryChange runs one event later and only if the rect differs from
    the one it had when that event was scheduled (0110: otherwise onGeometryRestored runs);
  * the layout (anchors left and right) puts the widget back in its slot whenever it is updated;
  * UITextEdit::update (what onGeometryRestored runs) with text-auto-resize sizes the widget to its text (width), then the layout sizes it back.
The options' hotkey search box is such a widget. Before 0124 onGeometryRestored ran the whole update (auto resize
included): each pass scheduled the next one and the dispatcher ran 100 loops every poll ("event list is not getting
empty"). With 0124 the restored event only places the glyphs. Run: python3 -I client/tools/textedit_restored_test.py
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PATCH = os.path.join(ROOT, 'client', 'base-patches', '0124-textedit-restored-glyphs-only.patch')
SLOT = (40, 10, 200, 20)
TEXT_W = 30      # width of the text plus padding: what the auto resize wants


class Dispatcher:
    def __init__(self):
        self.events = []

    def add(self, fn):
        self.events.append(fn)

    def poll(self):
        """Returns the loops of one poll; the engine logs the error above 100."""
        loops = 0
        while self.events and loops <= 100:
            batch, self.events = self.events, []
            for fn in batch:
                fn()
            loops += 1
        return loops


class SearchBox:
    def __init__(self, d, glyphs_only_fix):
        self.d = d
        self.fix = glyphs_only_fix
        self.rect = (0, 0, 0, 0)
        self.glyphs_rect = None
        self.glyphs_only = False
        self.scheduled = False

    def layout(self):
        self.set_rect(SLOT)

    def set_rect(self, rect):
        if rect == self.rect:
            return
        old = self.rect
        self.rect = rect
        if self.scheduled:
            return
        self.scheduled = True

        def fire():
            self.scheduled = False
            if old != self.rect:
                self.glyphs_rect = self.rect   # onGeometryChange: the glyphs follow the rect
            else:
                self.on_geometry_restored()
        self.d.add(fire)

    def update(self, glyphs_only=False):
        if not (self.fix and glyphs_only):
            x, y, w, h = self.rect
            self.set_rect((x, y, TEXT_W, h))   # text-auto-resize
            self.d.add(self.layout)            # UILayout::updateLater: back to its slot
        self.glyphs_rect = self.rect

    def on_geometry_restored(self):
        if self.glyphs_rect != self.rect:
            self.update(glyphs_only=True)


def run(fix):
    d = Dispatcher()
    box = SearchBox(d, fix)
    box.layout()
    d.poll()
    box.glyphs_rect = None   # the text is set: update() sizes the box to it, the layout puts it back in the same frame
    box.update()
    box.layout()
    worst = 0
    for _ in range(5):
        worst = max(worst, d.poll())
    return worst, box


def main():
    fails = []
    stock, _ = run(False)
    fixed, box = run(True)
    if stock <= 100:
        fails.append('without 0124 the event list should not get empty, got %d loops' % stock)
    if fixed > 5:
        fails.append('with 0124 a poll should end in a few loops, got %d' % fixed)
    if box.rect != SLOT:
        fails.append('with 0124 the box should stay in its slot, got %r' % (box.rect,))
    if box.glyphs_rect != box.rect:
        fails.append('with 0124 the glyphs should be placed for the rect, got %r' % (box.glyphs_rect,))

    try:
        with open(PATCH, encoding='utf-8') as f:
            patch = f.read()
    except OSError:
        patch = ''
        fails.append('missing %s' % PATCH)
    for needle in ('+    if(!m_glyphsOnly && (!m_rect.isValid()', '+        m_glyphsOnly = true;',
                   '+        m_glyphsOnly = false;', '+    stdext::boolean<false> m_glyphsOnly;'):
        if patch and needle not in patch:
            fails.append('0124 lacks: %s' % needle.strip())

    for f in fails:
        print('FAIL', f)
    print('textedit_restored_test: stock %d loops, 0124 %d loops; %s'
          % (stock, fixed, 'FAILED' if fails else 'ok'))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
