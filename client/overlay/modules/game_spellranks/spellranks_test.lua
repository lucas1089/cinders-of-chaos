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
local nowMs = 5000
_G.g_clock = { seconds = function() return 1000 end, millis = function() return nowMs end }
_G.g_ui = { importStyle = function() end, createWidget = function(style, parent) local c = widget() parent.children[#parent.children + 1] = c return c end }
_G.g_game = {
  isOnline = function() return online end,
  getProtocolGame = function() return { sendExtendedOpcode = function(_, op, msg) sent[#sent + 1] = { op = op, msg = msg } end } end,
  getLocalPlayer = function() return { getLevel = function() return 1000 end } end,
}
local handler
_G.ProtocolGame = { registerExtendedJSONOpcode = function(op, fn) handler = fn end, unregisterExtendedJSONOpcode = function() end }
_G.connect, _G.disconnect = function() end, function() end
local eventMs = {}
_G.scheduleEvent = function(fn, ms) events[#events + 1] = fn eventMs[#eventMs + 1] = ms return #events end
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
dofile(here .. 'awakened_data.lua')
dofile(here .. 'ranklogic.lua')
dofile(here .. 'combologic.lua')
dofile(here .. 'awakelogic.lua')
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

-- awakening (phase 7): the second view of the tab, the Seals, the slots, the confirm box, the answers, the awakened name
do
  sent, boxes = {}, {}
  msg('state', { on = true, v = 1, s = { { 206, 20, 0, 0 } } })
  msg('forms', { v = 1, f = { { 206, 1, 2 } } })
  local dm = { id = 206, name = 'Doomtide', type = 'damage' }
  local q = widget()
  fill(q, dm)
  eq(q.awakeTab.visible, false, 'no Awakening button before the server sends the awakened state')
  eq(awakenedName(206), nil, 'no awakened name yet')
  local costs = { { 40, 36, 16 }, { 70, 60, 28 }, { 100, 90, 40 } }
  msg('awakened', { on = true, v = 1, seals = { 3, 2, 1 }, slots = { 0, 0, 0 }, costs = costs, held = 0, bonus = 0.1 })
  eq(q.awakeTab.visible, true, 'the Awakening button shows') has(q.awakeTab.v_Text, 'Awakening', 'its label')
  eq(q.awakeTitle.visible, false, 'the Forms view first') eq(q.form1a.visible, true, 'the Forms show')
  q.awakeTab.onClick()
  eq(q.awakeTitle.visible, true, 'the Awakening view') eq(q.form1a.visible, false, 'the Forms hide') eq(q.effects.visible, false, 'and the effects line')
  eq(q.rankTitle.visible, true, 'the rank stays')
  has(q.awakeTab.v_Text, 'Forms', 'the button goes back to the Forms')
  has(q.awakeTitle.v_Text, 'Awakens as: Cataclysm of Cinders', 'the name it awakens as')
  has(q.awakeSeals.v_Text, 'Seals: 3 Waystone, 2 Rift, 1 Pinnacle', 'the Seals')
  has(q.awakeSeals.v_Tooltip, 'tier XVI to XXV', 'where Seals come from')
  has(q.awakeSlots.v_Text, 'Slot 1: free, 40 Waystone, 36 Rift, 16 Pinnacle Seals', 'slot 1 and its cost')
  has(q.awakeSlots.v_Text, 'Slot 3: free, 100 Waystone, 90 Rift, 40 Pinnacle Seals', 'slot 3 and its cost')
  has(q.awakeText.v_Text, 'A ring stays 6 s and pulses 3 times for 40% of the hit.', 'the signature sentence')
  has(q.awakeText.v_Text, 'hits or heals 10% more', 'the bonus sentence')
  has(q.awakeText.v_Text, 'PvP', 'the PvP note')
  has(q.note.v_Text, 'Awakened spells: 0 of 3', 'the slots held')
  eq(q.awakeDo.enabled, false, 'the button is off with too few Seals') has(q.awakeDo.v_Tooltip, 'Not enough Seals: 37 Waystone, 34 Rift and 15 Pinnacle more.', 'it says what is missing')
  -- a spell at rank 19 says the rank
  msg('state', { on = true, v = 1, s = { { 206, 19, 0.5, 1 } } })
  eq(q.awakeDo.enabled, false, 'rank 19: off') has(q.awakeDo.v_Tooltip, 'needs rank 20', 'it says the rank')
  msg('state', { on = true, v = 1, s = { { 206, 20, 0, 0 } } })
  msg('forms', { v = 1, f = { { 206, 1, 0 } } })
  has(q.awakeDo.v_Tooltip, 'Pick both Forms', 'no Form II: it says so')
  msg('forms', { v = 1, f = { { 206, 1, 2 } } })
  -- enough Seals
  msg('awakened', { on = true, v = 1, seals = { 40, 36, 16 }, slots = { 0, 0, 0 }, costs = costs, held = 0, bonus = 0.1 })
  eq(q.awakeDo.enabled, true, 'the button is on') has(q.awakeDo.v_Tooltip, '40 Waystone, 36 Rift and 16 Pinnacle', 'with the cost')
  q.awakeDo.onClick()
  eq(#sent, 0, 'a click asks first') eq(#boxes, 1, 'the question') has(boxes[1].title, 'Awaken spell', 'its title')
  has(boxes[1].text, 'Awaken Doomtide as Cataclysm of Cinders', 'it names both') has(boxes[1].text, '40 Waystone, 36 Rift and 16 Pinnacle Seals and takes slot 1', 'the price and the slot')
  has(boxes[1].text, 'not returned', 'the dormant warning')
  boxes[1].buttons[2].callback()
  eq(#sent, 0, 'Cancel sends nothing')
  q.awakeDo.onClick()
  boxes[#boxes].buttons[1].callback()
  eq(#sent, 1, 'Awaken sends') eq(sent[1].op, 168, 'opcode') eq(sent[1].msg.action, 'awaken', 'action')
  eq(sent[1].msg.data.spell, 206, 'spell') eq(sent[1].msg.data.slot, 1, 'slot')
  msg('awaken', { ok = true, why = 'ok', spell = 206, slot = 1, name = 'Cataclysm of Cinders', namePt = 'Cataclismo de Cinzas' })
  has(q.message.v_Text, 'Awakened: Cataclysm of Cinders', 'the answer') eq(q.message.v_Color, '#4fd07f', 'good colour')
  msg('awakened', { on = true, v = 1, seals = { 0, 0, 0 }, slots = { 206, 0, 0 }, costs = costs, held = 1, bonus = 0.1 })
  has(q.awakeTitle.v_Text, 'Awakened: Cataclysm of Cinders', 'now awakened') eq(q.awakeDo.enabled, false, 'the button is off')
  has(q.awakeDo.v_Tooltip, 'This spell is awakened.', 'and says why')
  has(q.awakeSlots.v_Text, 'Slot 1: Cataclysm of Cinders', 'the slot holds the spell') has(q.awakeSlots.v_Text, 'Slot 2: free, 70 Waystone', 'slot 2 is next')
  eq(awakenedName(206), 'Cataclysm of Cinders', 'the Spellbook shows the new name') eq(awakenedName(2), nil, 'another spell keeps its name')
  eq(book >= 3, true, 'the Spellbook is told at each awakened message')
  _G.ChaosLocale = { lang = 'pt-BR' }
  eq(awakenedName(206), 'Cataclismo de Cinzas', 'pt-BR: the pt-BR name')
  _G.ChaosLocale = nil
  -- refusals of the server reach the player with the reason
  for _, row in ipairs({ { 'rank', 'needs rank 20' }, { 'forms', 'Pick both Forms' }, { 'already', 'is awakened' }, { 'slot', 'slots are taken' },
      { 'unknown', 'do not know' }, { 'spell', 'cannot be awakened' }, { 'off', 'not on yet' } }) do
    msg('awaken', { ok = false, why = row[1], spell = 206 })
    has(q.message.v_Text, row[2], 'the answer ' .. row[1]) eq(q.message.v_Color, '#e03a1e', 'bad colour for ' .. row[1])
  end
  msg('awaken', { ok = false, why = 'seals', spell = 206, need = { waystone = 5, rift = 0, pinnacle = 1 } })
  has(q.message.v_Text, 'Not enough Seals: 5 Waystone, 0 Rift and 1 Pinnacle more.', 'the Seals missing')
  msg('awaken', { ok = false, why = 'nonsense', spell = 206 })
  has(q.message.v_Text, 'did not accept that awakening', 'an unknown reason')
  msg('awaken', 'junk')
  -- another spell with no awakened row: no button
  local other = widget()
  fill(other, { id = 777, name = 'Nothing' })
  eq(other.awakeTab.visible, false, 'a spell with no awakened form has no button')
  -- the switch off clears the new name
  msg('state', { on = false, v = 1, s = {} })
  eq(awakenedName(206), nil, 'switch off: the spell keeps its own name')
end

-- the switch goes off again: everything hides
msg('pick', { ok = false, why = 'off' })
eq(isOn(), false, 'an off answer switches the tab off') eq(getPickableCount(), 0, 'badge 0')

-- combos (phase 6): the label on the engine's animated text and one of two chimes, the throttle, the translation
local texts, plays, mapAdds, warnings = {}, {}, {}, {}
_G.g_logger = { warning = function(m) warnings[#warnings + 1] = m end }
_G.AnimatedText = { create = function()
  local t = { }
  function t:setText(v) self.text = v end
  function t:setColor(v) self.color = v end
  texts[#texts + 1] = t
  return t
end }
_G.g_map = { addAnimatedText = function(t, pos) mapAdds[#mapAdds + 1] = { t = t, pos = pos } end }
_G.SoundChannels = { Effect = 1 }
_G.g_resources = { fileExists = function(f) return not f:find('missing', 1, true) end }
local channel = { play = function(self, file, loops, gain) plays[#plays + 1] = { file = file, gain = gain } return {} end }
_G.g_sounds = { getChannel = function() return channel end }
local savedTr = _G.tr
_G.tr = function(s, ...) if s == 'Steam Burst' then return 'Explosão de Vapor' end return savedTr(s, ...) end
nowMs = 20000
msg('combo', { id = 'steam_burst', n = 'Steam Burst', x = 1000, y = 1001, z = 7 })
eq(#mapAdds, 1, 'a label was added to the map') eq(mapAdds[1].pos.x, 1000, 'over the target tile') eq(mapAdds[1].pos.z, 7, 'on its floor')
eq(mapAdds[1].t.text, 'Explosão de Vapor', 'the text is the pt-BR name through tr()') eq(mapAdds[1].t.color, 143, 'the colour of the combo')
eq(#plays, 1, 'a chime played') eq(plays[1].file, '/modules/game_spellranks/sounds/combo_a.ogg', 'the reaction chime')
nowMs = 20100
msg('combo', { id = 'meat_grinder', n = 'Meat Grinder', x = 1000, y = 1001, z = 7 })
eq(#mapAdds, 1, 'a second label within 200 ms is thrown away') eq(#plays, 1, 'and its chime')
nowMs = 20400
msg('combo', { id = 'meat_grinder', n = 'Meat Grinder', x = 1000, y = 1001, z = 7 })
eq(#mapAdds, 2, 'a label 300 ms later shows') eq(plays[2].file, '/modules/game_spellranks/sounds/combo_b.ogg', 'the signature chime')
nowMs = 21000
msg('combo', { id = 5, x = 1, y = 1, z = 7 })
msg('combo', 'junk')
eq(#mapAdds, 2, 'junk shows nothing') eq(#plays, 2, 'and plays nothing')
-- a client with no animated text or no sound: no error, the other half still works
local savedAnim = _G.AnimatedText
_G.AnimatedText = nil
nowMs = 22000
msg('combo', { id = 'overload', x = 5, y = 6, z = 7 })
eq(#mapAdds, 2, 'no AnimatedText: no label') eq(#plays, 3, 'but the chime plays')
_G.AnimatedText = savedAnim
local savedSounds = _G.g_sounds
_G.g_sounds = nil
nowMs = 23000
msg('combo', { id = 'overload', x = 5, y = 6, z = 7 })
eq(#mapAdds, 3, 'no sound support: the label shows') eq(#plays, 3, 'no chime') eq(#warnings, 1, 'one warning, once')
nowMs = 24000
msg('combo', { id = 'overload', x = 9, y = 6, z = 7 })
eq(#warnings, 1, 'the warning is not repeated')
_G.g_sounds = savedSounds
-- an engine that throws: nothing escapes
_G.g_map.addAnimatedText = function() error('boom') end
nowMs = 25000
msg('combo', { id = 'overload', x = 1, y = 6, z = 7 })
eq(#plays, 4, 'a failing label does not stop the chime') eq(#warnings, 2, 'and is logged')
_G.tr = savedTr

-- the timer asks rarely: the server pushes ranks now
local longest = 0
for _, ms in ipairs(eventMs) do if ms > longest then longest = ms end end
eq(longest >= 300000, true, 'the fallback poll is every 5 minutes or more (the server pushes `rank`)')

-- logout clears
terminate()
eq(isOn(), false, 'cleared')
print('spellranks_test: ' .. n .. ' checks OK')
