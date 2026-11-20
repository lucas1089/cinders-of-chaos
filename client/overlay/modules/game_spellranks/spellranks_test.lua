-- luajit spellranks_test.lua && lua5.3 spellranks_test.lua (CI runs it from the repo root): the widget side of the Upgrades tab on a
-- fake engine (widgets that record what is set on them): the switch off shows nothing, a state and a Forms message draw the rank,
-- the bar, the Form buttons, the locked Forms; a click sends `pick`, the answers become messages, the hub count follows.
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end
local function has(s, part, m) n = n + 1 if not tostring(s):find(part, 1, true) then error((m or '') .. ': "' .. tostring(s) .. '" lacks "' .. part .. '"', 2) end end

-- fake engine
local W
local function widget()
  local w = { children = {}, enabled = true, visible = true }
  return setmetatable(w, {
    __index = function(t, k)
      if k == 'cellsBuilt' or k == 'onClick' then return nil end
      if k == 'getChildren' then return function(self) return self.children end end
      if k == 'destroy' then return function() end end
      if k == 'setEnabled' then return function(self, v) self.enabled = v end end
      if k == 'setVisible' then return function(self, v) self.visible = v end end
      if k:sub(1, 3) == 'set' then return function(self, v) rawset(self, 'v_' .. k:sub(4), v) end end
      local c = widget() -- a child by id
      rawset(t, k, c)
      return c
    end,
  })
end
local sent, events = {}, {}
local online = true
_G.tr = function(s, ...) if select('#', ...) > 0 then return string.format(s, ...) end return s end
_G.json = { encode = function(t) return t end, decode = function(s) return s end }
_G.g_clock = { seconds = function() return 1000 end }
_G.g_ui = { importStyle = function() end, createWidget = function(style, parent) local c = widget() parent.children[#parent.children + 1] = c return c end }
_G.g_game = {
  isOnline = function() return online end,
  getProtocolGame = function() return { sendExtendedOpcode = function(_, op, msg) sent[#sent + 1] = { op = op, msg = msg } end } end,
  getLocalPlayer = function() return { getLevel = function() return 1000 end } end,
}
local handler
_G.ProtocolGame = { registerExtendedJSONOpcode = function(op, fn) handler = fn end, unregisterExtendedJSONOpcode = function() end }
_G.connect, _G.disconnect = function() end, function() end
_G.scheduleEvent = function(fn, ms) events[#events + 1] = fn return #events end
_G.removeEvent = function() end
_G.AnchorHorizontalCenter = 1
local boxes = {}
_G.displayGeneralBox = function(title, text, buttons) local b = { title = title, text = text, buttons = buttons, destroy = function() end } boxes[#boxes + 1] = b return b end
_G.modules = {}
local topRefresh = 0
_G.modules.client_chaos_topbar = { ChaosTopBar = { refresh = function() topRefresh = topRefresh + 1 end } }
local book = 0
_G.modules.game_spellbook = { onRanksChanged = function() book = book + 1 end }

dofile(here .. 'forms_data.lua')
dofile(here .. 'ranklogic.lua')
dofile(here .. 'spellranks.lua')

init()
eq(handler ~= nil, true, 'the handler is registered')
local function msg(action, data) handler(nil, 168, { action = action, data = data }) end

-- the switch is off: nothing
local spell = { id = 2, name = 'Gorehook', type = 'damage' }
eq(isOn(), false, 'off before a state') eq(canShowTab(spell), false, 'no tab') eq(rowInfo(2), nil, 'no row info') eq(getPickableCount(), 0, 'no badge')
msg('state', { on = false, v = 1, s = { { 2, 12, 1, 4 } } })
eq(isOn(), false, 'a state with on = false') eq(rowInfo(2), nil, 'still no row info')
local p = widget()
fill(p, spell)
eq(p.emptyText.visible, true, 'the empty text shows') has(p.emptyText.v_Text, 'not on yet', 'says it is not on')
eq(p.rankTitle.visible, false, 'nothing else shows')

-- the switch is on
msg('state', { on = true, v = 1, s = { { 2, 12, 1.5, 6 }, { 3, 4, 0, 2 } } })
msg('forms', { v = 1, f = {} })
eq(isOn(), true, 'on') eq(canShowTab(spell), true, 'the tab shows for a spell with Forms') eq(canShowTab({ id = 777 }), false, 'not for a spell with neither')
local info = rowInfo(2)
eq(info.rank, 12, 'row rank') eq(info.percent, 25, 'row percent') has(info.tip, 'Rank 12 of 20', 'row tip')
eq(getPickableCount() >= 1, true, 'a Form can be picked: the hub badge counts it')
eq(topRefresh >= 1, true, 'the hub is asked to refresh') eq(book >= 1, true, 'the Spellbook is told')
fill(p, spell)
eq(p.emptyText.visible, false, 'the tab draws') has(p.rankTitle.v_Text, 'Rank 12 of 20', 'title')
eq(p.rankBar.v_Percent, 25, 'bar') has(p.spText.v_Text, '1.50 / 6.00 SP', 'sp text')
eq(#p.strip.children, 20, 'twenty cells') eq(p.strip.children[12].v_BackgroundColor, '#e8b84a', 'cell 12 lit') eq(p.strip.children[13].v_BackgroundColor, '#1a1416', 'cell 13 dark')
has(p.effects.v_Text, 'Now: +10.8% power', 'effects now') has(p.effects.v_Text, 'Rank 13 adds', 'effects next')
has(p.form1Title.v_Text, 'Form I', 'form I title') eq(p.form1a.enabled, true, 'Form I open at rank 12') eq(p.form1a.v_Text, 'Gravity Pull', 'Form I name, no pick yet')
has(p.form2Title.v_Text, 'opens at rank 20', 'Form II locked') eq(p.form2a.enabled, false, 'Form II buttons off')
has(p.note.v_Text, 'first pick', 'first pick note')

-- a first pick: free, sent at once
p.form1a.onClick()
eq(#sent, 1, 'a pick was sent') eq(sent[1].op, 168, 'opcode') eq(sent[1].msg.action, 'pick', 'action')
eq(sent[1].msg.data.spell, 2, 'spell') eq(sent[1].msg.data.tier, 1, 'tier') eq(sent[1].msg.data.pick, 1, 'pick')
eq(#boxes, 0, 'no question for a free pick')
msg('pick', { ok = true, why = 'first', price = 0, spell = 2, tier = 1, pick = 1, f1 = 1, f2 = 0 })
has(p.message.v_Text, 'Form chosen', 'message') eq(p.message.v_Color, '#4fd07f', 'good colour')
eq(p.form1a.v_Text, '> Gravity Pull', 'the chosen Form is marked')
has(p.note.v_Text, 'costs', 'a change costs gold now')

-- a change after the free window: asks first
p.form1b.onClick()
eq(#sent, 2, 'a change inside the free window is sent at once') -- the pick of this session just made
msg('pick', { ok = true, why = 'window', price = 0, spell = 2, tier = 1, pick = 2, f1 = 2, f2 = 0 })
has(p.message.v_Text, 'Free', 'free change')

-- a refusal
msg('pick', { ok = false, why = 'gold', price = 150000, spell = 2, tier = 1, pick = 1 })
has(p.message.v_Text, 'You need 150000 gold', 'gold message') eq(p.message.v_Color, '#e03a1e', 'bad colour')
msg('pick', { ok = false, why = 'rank', spell = 2, tier = 2, pick = 1 })
has(p.message.v_Text, 'rank 20', 'rank message')
msg('pick', { ok = false, why = 'whatever', spell = 2, tier = 1, pick = 1 })
has(p.message.v_Text, 'did not accept', 'unknown reason')

-- a rank 20 spell with Form I picked opens Form II
msg('state', { on = true, v = 1, s = { { 2, 20, 0, 0 } } })
msg('forms', { v = 1, f = { { 2, 2, 0 } } })
fill(p, spell)
eq(p.form2a.enabled, true, 'Form II open') has(p.rankTitle.v_Text, 'Rank 20 of 20', 'top rank') has(p.spText.v_Text, 'Top rank', 'top text')
eq(p.rankBar.v_Percent, 100, 'full bar')
eq(getPickableCount(), 1, 'Form II to pick')

-- a change of an old pick (other spell than the last one) is paid and asks first
msg('forms', { v = 1, f = { { 2, 2, 1 } } })
sent = {}
fill(p, { id = 2, name = 'Gorehook' })
p.form2b.onClick()
eq(#sent, 0, 'a paid change waits for the answer to the question') eq(#boxes, 1, 'the question') has(boxes[1].text, '150000', 'price in the question')
boxes[1].buttons[1].callback()
eq(#sent, 1, 'yes sends') eq(sent[1].msg.data.pick, 2, 'the pick')
p.form2a.onClick()
eq(#sent, 1, 'the chosen Form is already chosen: nothing sent') -- pick 1 of tier 2 is the current one? (f2 = 1)

-- the switch goes off again: everything hides
msg('pick', { ok = false, why = 'off' })
eq(isOn(), false, 'an off answer switches the tab off') eq(getPickableCount(), 0, 'badge 0')

-- logout clears
terminate()
eq(isOn(), false, 'cleared')
print('spellranks_test: ' .. n .. ' checks OK')
