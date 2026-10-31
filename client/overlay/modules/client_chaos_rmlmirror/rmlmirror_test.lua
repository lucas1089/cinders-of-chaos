-- Self test of the window mirror (rmlmirror.lua) and the form layer parts it relies on (rmlform.lua), with mock widgets
-- (no client needed). Run from the repository root (CI runs it with luajit and lua5.3):
--   luajit client/overlay/modules/client_chaos_rmlmirror/rmlmirror_test.lua
local here = (arg and arg[0] or ''):match('^(.*[/\\])') or './'

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format('FAIL %s: got %q, want %q', what, tostring(got), tostring(want)))
  end
end
local function has(s, part, what) eq(tostring(s):find(part, 1, true) ~= nil, true, what .. ' (' .. part .. ')') end

function tr(s) return s end

local function widget(cls, fields)
  local w = { cls = cls, children = {}, visible = true, enabled = true, text = '', style = '', opacity = 1,
              rect = { x = 0, y = 0, width = 100, height = 100 } }
  for k, v in pairs(fields or {}) do w[k] = v end
  function w:getChildren() return self.children end
  function w:getChildCount() return #self.children end
  function w:getClassName() return self.cls end
  function w:getStyleName() return self.style end
  function w:isExplicitlyVisible() return self.visible end
  function w:isEnabled() return self.enabled end
  function w:getText() return self.text end
  function w:getTooltip() return self.tooltip end
  function w:getId() return self.id end
  function w:getOpacity() return self.opacity end
  function w:getRect() return self.rect end
  function w:getParent() return self.parent end
  return w
end
local function add(parent, ...)
  for _, c in ipairs({ ... }) do
    parent.children[#parent.children + 1] = c
    c.parent = parent
  end
  return parent
end
local function button(id, text) return widget('UIButton', { id = id, text = text }) end
local function label(id, text) return widget('UILabel', { id = id, text = text }) end

dofile(here .. '../client_chaos_rmlform/rmlform.lua')
dofile(here .. 'rmlmirror.lua')
local F, M = ChaosRmlForm, ChaosRmlMirror

-- keyOf: one number per widget, kept on it
local a, b = widget('UIWidget'), widget('UIWidget')
eq(F.keyOf(a), F.keyOf(a), 'keyOf stable')
eq(F.keyOf(a) ~= F.keyOf(b), true, 'keyOf differs')
eq(M.keyOf(a), F.keyOf(a), 'mirror keyOf is the form one')

-- collect skips widgets faded to opacity 0 and the theme's corner pieces
local box = add(widget('UIMessageBox', { id = 'box' }),
  label('msg', 'Hello'),
  button('ok', 'Ok'),
  button('gone', 'Hidden by opacity'),
  widget('UIWidget', { id = 'chaosOrnTL', imageSource = '/images/x', size = { width = 44, height = 44 } }))
box.children[3].opacity = 0
local orn = box.children[4]
function orn:getImageSource() return self.imageSource end
function orn:getSize() return self.size end
local items = F.collect(box)
eq(#items, 2, 'collect: label and button only')
eq(items[1].kind, 'label', 'collect: label')
eq(items[2].text, 'Ok', 'collect: the visible button')

-- signature: stable for the same widgets, independent of tostring
local sig = F.signature(items)
eq(F.signature(F.collect(box)), sig, 'signature stable')
eq(sig:find('table:', 1, true), nil, 'signature without addresses')
box.children[3].opacity = 1
eq(F.signature(F.collect(box)) ~= sig, true, 'signature changes when a widget shows')
box.children[3].opacity = 0

-- list rows: text in a span (a flex box draws no loose text)
local list = add(widget('UIScrollArea', { id = 'list', style = 'TextList' }), label('r1', 'Row <1>'))
local rml = F.rml(F.collect(add(widget('UIWindow'), list)), function(s) return (s:gsub('<', '&lt;'):gsub('>', '&gt;')) end)
has(rml, '<div class="row" id="c2"><span>Row &lt;1&gt;</span>', 'row text in a span')

-- eligible
eq(#M.eligible(box), 2, 'eligible: its items')
local hidden = add(widget('UIWindow', { visible = false }), button('x', 'X'))
eq(select(2, M.eligible(hidden)), 'hidden', 'eligible: hidden')
local mini = add(widget('UIMiniWindow'), button('x', 'X'))
eq(select(2, M.eligible(mini)), 'class', 'eligible: not a window class')
local own = add(widget('UIWindow', { chaosNoMirror = true }), button('x', 'X'))
eq(select(2, M.eligible(own)), 'skip', 'eligible: chaosNoMirror')
local classic = add(widget('UIWindow', { chaosRmlSkip = true }), button('x', 'X'))
eq(select(2, M.eligible(classic)), 'skip', 'eligible: sent to the classic look')
local denied = add(widget('UIWindow'), button('x', 'X'))
eq(select(2, M.eligible(denied, { [F.keyOf(denied)] = true })), 'skip', 'eligible: denied')
local items2 = add(widget('UIWindow'), button('x', 'X'), widget('UIItem'), widget('UICreature'), widget('UIItem'))
eq(select(2, M.eligible(items2)), 'unsupported: UICreature, UIItem', 'eligible: unsupported classes, sorted, once')
local empty = add(widget('UIWindow'), widget('UIHorizontalSeparator'))
empty.children[1].cls = 'UIWidget'
empty.children[1].style = 'HorizontalSeparator'
eq(select(2, M.eligible(empty)), 'empty', 'eligible: nothing to draw')

-- candidates: the children of each root once
local root = widget('UIWidget')
local gameRoot = widget('UIWidget')
local w1, w2 = widget('UIWindow'), widget('UIWindow')
add(root, w1, gameRoot)
add(gameRoot, w2)
local shared = { getChildren = function() return { w1, w2 } end }
local cand = M.candidates({ root, gameRoot, shared })
eq(#cand, 3, 'candidates: once each')
eq(cand[1], w1, 'candidates: order')
eq(cand[3], w2, 'candidates: second root')

-- covered: an unmirrored window or menu drawn after it over its rect
local parent = widget('UIWidget')
local win = widget('UIWindow', { rect = { x = 100, y = 100, width = 200, height = 150 } })
local menu = widget('UIPopupMenu', { rect = { x = 250, y = 200, width = 80, height = 60 } })
local below = widget('UIWindow', { rect = { x = 100, y = 100, width = 200, height = 150 } })
local far = widget('UIWindow', { rect = { x = 400, y = 100, width = 50, height = 50 } })
add(parent, below, win, far, menu)
eq(M.covered(win, {}), true, 'covered: a menu over it')
menu.visible = false
eq(M.covered(win, {}), false, 'covered: the menu hidden')
menu.visible = true
menu.rect = { x = 300, y = 100, width = 50, height = 50 }
eq(M.covered(win, {}), false, 'covered: edges only touch')
local over = widget('UIWindow', { rect = { x = 120, y = 120, width = 50, height = 50 } })
add(parent, over)
eq(M.covered(win, {}), true, 'covered: a window over it')
eq(M.covered(win, { [F.keyOf(over)] = true }), false, 'covered: not by a mirrored window')
eq(M.covered(below, { [F.keyOf(win)] = true, [F.keyOf(over)] = true }), false, 'covered: windows below are not covered by mirrors')
eq(M.covered(widget('UIWindow'), {}), false, 'covered: no parent')

-- centreShift: a grown mirror moves up by half the growth, never above the screen
eq(M.centreShift(200, 100, 100), 0, 'centreShift: same height')
eq(M.centreShift(200, 100, 90), 0, 'centreShift: smaller')
eq(M.centreShift(200, 100, 141), 20, 'centreShift: half, rounded down')
eq(M.centreShift(10, 100, 200), 10, 'centreShift: clamped at the top')

print(string.format('rmlmirror_test: %d checks, %d failures', checks, failures))
if failures > 0 then os.exit(1) end
