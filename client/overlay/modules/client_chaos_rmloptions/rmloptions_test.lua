-- Self test of rmloptions.lua with mock widgets, a fake client_settings and a fake g_rml (no client needed). Run from the
-- repository root (CI runs it with luajit and lua5.3):  luajit client/overlay/modules/client_chaos_rmloptions/rmloptions_test.lua
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
local events = {}
function addEvent(f) events[#events + 1] = f end
function scheduleEvent(f) events[#events + 1] = f end
function signalcall(f, ...)
  if type(f) == 'function' then return f(...) end
  if type(f) == 'table' then for _, g in ipairs(f) do g(...) end end
end
local function runEvents()
  local list = events
  events = {}
  for _, f in ipairs(list) do f() end
end

-- mock widgets: just what collect() and the engine side read
local applied = {}
local function widget(cls, fields)
  local w = { cls = cls, children = {}, visible = true, enabled = true, text = '', style = '' }
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
  return w
end
local function check(id, text, on)
  local w = widget('UICheckBox', { id = id, text = text, checked = on })
  function w:isChecked() return self.checked end
  function w:setChecked(v)
    if self.checked == v then return end
    self.checked = v
    applied[#applied + 1] = id .. '=' .. tostring(v)
  end
  function w:onClick() self:setChecked(not self:isChecked()) end
  return w
end
local function slider(id, lo, hi, v, orient)
  local w = widget('UIScrollBar', { id = id, minimum = lo, maximum = hi, value = v, orientation = orient or 'horizontal' })
  function w:getOrientation() return self.orientation end
  function w:getMinimum() return self.minimum end
  function w:getMaximum() return self.maximum end
  function w:getValue() return self.value end
  function w:setValue(x)
    x = math.max(math.min(x, self.maximum), self.minimum)
    if x == self.value then return end
    self.value = x
    applied[#applied + 1] = id .. '=' .. x
  end
  return w
end
local function combo(id, opts, idx)
  local o = {}
  for i, t in ipairs(opts) do o[i] = { text = t } end
  local w = widget('UIComboBox', { id = id, options = o, currentIndex = idx })
  function w:setCurrentIndex(i)
    self.currentIndex = i
    applied[#applied + 1] = id .. '=' .. i
  end
  return w
end
local function add(parent, ...)
  for _, c in ipairs({ ... }) do parent.children[#parent.children + 1] = c end
  return parent
end

-- a page like graphics.otui: loose label + combo, a FlatPanel with a check and a help icon, a label + slider panel,
-- a hidden check, a vertical page scroll bar, a reset button
local engine = combo('antialiasing', { 'None', 'Antialiasing', 'Smooth <Retro>' }, 1)
local hd = check('hdmodeBox', 'HD Sprite Upscaling', false)
local light = slider('ambientLight', 0, 100, 25)
local lightLabel = widget('UILabel', { text = 'Ambient Light: 25 %' })
local hidden = check('hiddenBox', 'Hidden', true)
hidden.visible = false
local reset = widget('UIButton', { id = 'resetButton', text = 'Reset' })
local resets = 0
reset.onClick = function() resets = resets + 1 end
local page = widget('UIWidget', { id = 'graphics' })
local scroll = widget('UIScrollArea')
add(page, slider('graphicsScrollBar', 0, 10, 0, 'vertical'), scroll)
add(scroll,
  widget('UILabel', { text = 'Antialiasing Mode:' }), engine,
  add(widget('UIWidget', { style = 'FlatPanel' }), hd, widget('UIWidget', { tooltip = 'Sharper look.\nMore CPU.' })),
  add(widget('UIWidget', { style = 'FlatPanel' }), lightLabel, light),
  hidden, reset)

dofile(here .. '../client_chaos_rmlform/rmlform.lua')
dofile(here .. 'rmloptions.lua')

-- 1. collect: reading order, kinds, hidden and vertical skipped
local items = ChaosRmlOptions.collect(page)
local kinds = {}
for _, it in ipairs(items) do kinds[#kinds + 1] = it.kind end
eq(table.concat(kinds, ','), 'label,select,group,check,help,endgroup,group,label,range,endgroup,button', 'collect order')
eq(items[2].options[3], 'Smooth <Retro>', 'combo options')
eq(items[9].min .. '-' .. items[9].max, '0-100', 'range bounds')

-- 2. page RML: ids, escaping, help text after its panel, loose rows grouped
local function escape(s) return (s:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;')) end
local rml = ChaosRmlOptions.pageRml(items, escape)
has(rml, '<div class="group loose"><div class="pair"><span class="lbl" id="c1">Antialiasing Mode:</span><select id="c2">', 'loose row')
has(rml, '<option value="3">Smooth &lt;Retro&gt;</option>', 'escaped option')
has(rml, '<input type="checkbox" id="c4"/><span id="c4l">HD Sprite Upscaling</span>', 'check')
has(rml, '<span class="help" id="h5"></span></div><div class="helptext" id="t5">Sharper look.<br/>More CPU.</div>', 'help after panel')
has(rml, '<div class="pair"><span class="lbl" id="c8">Ambient Light: 25 %</span><input type="range" id="c9" min="0" max="100" step="1"/></div></div>', 'label and range share a row')
has(rml, '<button class="act" id="c11">Reset</button></div>', 'button closes the last loose row')
eq(items[4].el, 'c4', 'element id kept on the item')
local _, opens = rml:gsub('<div class="group', '')
local _, closes = rml:gsub('</div>', '')
local _, pairs = rml:gsub('<div class="pair"', '')
eq(closes - opens - pairs, 1, 'balanced: one extra close for the help text div')

-- 3. menu
local nav = ChaosRmlOptions.navRml(ChaosRmlOptions.PAGES, 'graphics', escape, tr)
has(nav, '<button class="nav on" id="p_graphics">Graphics</button>', 'current page')
has(nav, '<button class="nav sub classic" id="p_customHotkeys">Custom Hotkeys</button>', 'hotkey page')

-- 4. wantedValue: only real differences
eq(ChaosRmlOptions.wantedValue(items[4], true, ''), true, 'check differs')
eq(ChaosRmlOptions.wantedValue(items[4], false, ''), nil, 'check equal')
eq(ChaosRmlOptions.wantedValue(items[9], false, '60.4'), 60, 'range rounds')
eq(ChaosRmlOptions.wantedValue(items[9], false, '25'), nil, 'range equal')
eq(ChaosRmlOptions.wantedValue(items[2], false, '2'), 2, 'select differs')
eq(ChaosRmlOptions.wantedValue(items[2], false, 'x'), nil, 'select garbage')

-- 5. no g_rml: nothing hooked, classic window stays
g_rml = nil
local classicOpened = {}
modules = { client_settings = {
  loadedWindows = { graphics = page, controls = widget('UIWidget'), customHotkeys = widget('UIWidget') },
  closed = 0,
} }
local cs = modules.client_settings
cs.openOptions = function(self, redirectId) classicOpened[#classicOpened + 1] = tostring(redirectId) end
cs.closeOptions = function() cs.closed = cs.closed + 1 end
local classic = cs.openOptions
init()
eq(cs.openOptions, classic, 'no g_rml: not hooked')
eq(ChaosRmlOptions.available(), false, 'no g_rml: not available')
terminate()

-- 6. fake g_rml: the hook opens the RML window and drives the classic widgets
local state = { checked = {}, value = {}, text = {}, inner = {}, class = {}, disabled = {} }
local callback, visible = nil, false
g_rml = {
  init = function() return true end,
  escape = escape,
  loadFont = function() return true end,
  loadDocument = function() return 3 end,
  setEventCallback = function(f) callback = f end,
  setText = function(d, id, t) state.text[id] = t return true end,
  setInnerRml = function(d, id, r) state.inner[id] = r return true end,
  setClass = function(d, id, c, on) state.class[id .. '.' .. c] = on return true end,
  setScrollTop = function() return true end,
  setProperty = function() return true end,
  show = function() visible = true return true end,
  close = function() visible = false return true end,
  isVisible = function() return visible end,
  getValue = function(d, id) return state.value[id] or '' end,
  setValue = function(d, id, v) state.value[id] = v return true end,
  isChecked = function(d, id) return state.checked[id] == true end,
  setChecked = function(d, id, v) state.checked[id] = v return true end,
  setDisabled = function(d, id, v) state.disabled[id] = v return true end,
}
init()
eq(cs.openOptions ~= classic, true, 'g_rml: hooked')
cs.openOptions(cs, 'graphics')
eq(visible, true, 'opened in RmlUi')
eq(#classicOpened, 0, 'classic not opened')
has(state.inner.content, 'id="c4"', 'graphics page drawn')
eq(state.text.title, 'Options - Graphics', 'title')
eq(state.value.c9, '25', 'slider synced from the classic widget')
eq(state.value.c2, '1', 'combo synced')
eq(state.checked.c4, false, 'check synced')

-- the player ticks the check box: the classic box gets the click, nothing else changes
state.checked.c4 = true
callback(3, 'c4', 'change')
eq(hd.checked, true, 'classic check box ticked')
eq(table.concat(applied, ' '), 'hdmodeBox=true', 'one change applied')
-- a change event the sync itself caused does nothing
callback(3, 'c4', 'change')
eq(#applied, 1, 'no double apply')
-- slider and combo
state.value.c9 = '70'
callback(3, 'c9', 'change')
eq(light.value, 70, 'slider applied')
state.value.c2 = '3'
callback(3, 'c2', 'change')
eq(engine.currentIndex, 3, 'combo applied')
-- a disabled classic widget is not changed, the RML side is put back
hd.enabled = false
state.checked.c4 = false
callback(3, 'c4', 'change')
eq(hd.checked, true, 'disabled: not changed')
eq(state.checked.c4, true, 'disabled: RML put back')
eq(state.disabled.c4, true, 'disabled shown')
hd.enabled = true
-- a label the settings code rewrites is read again
lightLabel.text = 'Ambient Light: 70 %'
runEvents()
eq(state.text.c8, 'Ambient Light: 70 %', 'label refreshed')
-- buttons and help
callback(3, 'c11', 'click')
eq(resets, 1, 'reset button')
callback(3, 'h5', 'click')
eq(state.class['t5.open'], true, 'help opens')
callback(3, 'h5', 'click')
eq(state.class['t5.open'], false, 'help closes')
-- another page through the menu, a hotkey page shows the link to the classic window
callback(3, 'p_customHotkeys', 'click')
has(state.inner.content, 'id="openclassic"', 'hotkey page note')
callback(3, 'openclassic', 'click')
eq(visible, false, 'RML closed for the classic window')
eq(classicOpened[1], 'customHotkeys', 'classic window on the hotkey page')
eq(cs.closed, 1, 'close applies and saves')
-- a hotkey shortcut goes straight to the classic window; the menu button toggles the RML window
cs.openOptions(cs, 'customHotkeys')
eq(classicOpened[2], 'customHotkeys', 'hotkey redirect stays classic')
cs.openOptions(cs)
eq(visible, true, 'toggle opens')
cs.openOptions(cs)
eq(visible, false, 'toggle closes')
-- unload puts the classic openOptions back
terminate()
eq(cs.openOptions, classic, 'unhooked on unload')

print(string.format('rmloptions_test: %d checks, %d failures', checks, failures))
if failures > 0 then os.exit(1) end
