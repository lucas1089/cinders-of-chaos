#!/usr/bin/env python3
"""Test of rml_window_audit.py on synthetic .otui text (python3 -I client/tools/rml_window_audit_test.py)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rml_window_audit as A  # noqa: E402

FAILS = []


def check(ok, what):
    if not ok:
        FAILS.append(what)
        print('FAIL ' + what)


OTUI = '''
// a comment
MyButton < Button
  height: 22

ShopRow < UIWidget
  height: 30
  Item
    id: icon

FormWindow < MainWindow
  id: formWindow
  size: 300 200

  Label
    id: hint
    text-wrap: true
  MyButton
    id: go
    width: 40
    !text: tr('Go somewhere far')
  Panel
    id: rows
    layout: verticalBox

ShopWindow
  id: shopWindow
  ShopRow
    id: first
  UnknownThing
    id: what
'''

styles, instances = {}, []
for n in A.parse('x.otui', OTUI):
    (styles.__setitem__(n.name, n) if n.base else instances.append(n))
check(A.resolve('MyButton', styles) == 'UIButton', 'resolve: style chain to a base class')
check(A.resolve('UnknownThing', styles) is None, 'resolve: unknown name')
wins = A.windows(styles, instances)
names = sorted(A.prop(w, styles, 'id') or w.name for w in wins)
check(names == ['formWindow'], 'windows: the styled window with an id (ShopWindow resolves to nothing): %s' % names)
styles['ShopWindow'] = A.Node('ShopWindow', 'MainWindow', 0, 'x.otui', 1)
form = [w for w in A.windows(styles, instances) if w.name == 'FormWindow'][0]
rep = A.audit_window(form, styles)
check(rep['wrap'] == ['hint'], 'audit: wrapped label')
check(len(rep['tight']) == 1 and rep['tight'][0].startswith('go (40 px'), 'audit: tight button %s' % rep['tight'])
check(rep['empty'] == ['rows'], 'audit: a container Lua fills')
check(A.verdict(form, rep) == ('mirror', ''), 'verdict: a plain form mirrors')
shop = [w for w in instances if w.name == 'ShopWindow'][0]
rep = A.audit_window(shop, styles)
check(rep['unsupported'] == {'UIItem'} and rep['unknown'] == {'UnknownThing'}, 'audit: an inherited item child, unknown style')
check(A.verdict(shop, rep)[0] == 'otui', 'verdict: a window with items stays OTUI')
check(A.verdict(shop, {'nomirror': True})[1] == 'chaosNoMirror', 'verdict: chaosNoMirror')
# the real overlay parses and the passive tree is classic
s, i = A.load()
real = {A.prop(w, s, 'id') or w.name: w for w in A.windows(s, i)}
check('helperWindow' in real, 'overlay: the Helper window is found')
tree = [w for w in A.windows(s, i) if w.path.endswith('passivetree.otui')]
check(tree and A.no_mirror(tree[0]), 'overlay: the passive tree window is chaosNoMirror')

print('rml_window_audit_test: %s' % ('OK' if not FAILS else '%d failed' % len(FAILS)))
sys.exit(1 if FAILS else 0)
