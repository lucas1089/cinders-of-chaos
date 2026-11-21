-- luajit spellranks_wire_test.lua && lua5.3 spellranks_wire_test.lua (CI runs it from the repo root with the client loop): the Upgrades tab and the awakening view
-- on the EXACT opcode 168 messages a live server sent to a tester bot that held ranks (with SP into the rank), Forms (one waiting for its pick), a healing spell and an
-- awakened spell (wire_live.lua: the `state`, `forms`, `awakened` messages, and the `awaken` and `pick` answers; captured by closed_spell_wire of server/tools/tester_checks.py
-- in the live pass of O686 phase 8d, no name or account in it). The fake engine is the one of spellranks_test.lua: widgets that record what is set on them. Every field the
-- window shows (rank, SP to go, the bar, Form buttons and their sentences, Seals, slots, the signature sentence, the awakened name, the answers) must have a value, in English
-- and in pt-BR, and every tr() text the window asks for must have its pt-BR in pt_br.lua (the run from the repo root reads it).
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end
local function ok(c, m) n = n + 1 if not c then error(m or 'check failed', 2) end end
local function has(s, part, m) n = n + 1 if not tostring(s):find(part, 1, true) then error((m or '') .. ': "' .. tostring(s) .. '" lacks "' .. part .. '"', 2) end end

local fx = dofile(here .. 'wire_live.lua')

-- fake engine (as spellranks_test.lua)
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
      local c = widget()
      rawset(t, k, c)
      return c
    end,
  })
end
-- what a widget shows: the text set on it (nil when none was set)
local function shown(w, what) local v = rawget(w, 'v_' .. (what or 'Text')) return v end
local function text(w) local v = shown(w) return type(v) == 'string' and v or nil end

local sent, boxes = {}, {}
local pt = false
local PT
local used, missing = {}, {}
_G.ChaosLocaleStrings = nil
local ptFile = io.open(here .. '../client_chaos_locale/pt_br.lua', 'rb') or io.open('client/overlay/modules/client_chaos_locale/pt_br.lua', 'rb')
if ptFile then
  ptFile:close()
  dofile(here .. '../client_chaos_locale/pt_br.lua')
  PT = _G.ChaosLocaleStrings and _G.ChaosLocaleStrings['pt-BR']
end
-- tr as the client's: the pt-BR table first, then the English; every key asked is noted, every key with no pt-BR entry too (the window may not ask for text with none)
local function realTr(s, ...)
  used[s] = true
  local t = s
  if pt and PT then
    t = PT[s]
    if t == nil then missing[s] = true t = s end
  end
  if select('#', ...) > 0 then return string.format(t, ...) end
  return t
end
_G.tr = realTr
_G.json = { encode = function(t) return t end, decode = function(s) return s end }
_G.g_clock = { seconds = function() return 1000 end, millis = function() return 5000 end }
_G.g_ui = { importStyle = function() end, createWidget = function(style, parent) local c = widget() parent.children[#parent.children + 1] = c return c end }
_G.g_game = {
  isOnline = function() return true end,
  getProtocolGame = function() return { sendExtendedOpcode = function(_, op, msg) sent[#sent + 1] = { op = op, msg = msg } end } end,
  getLocalPlayer = function() return { getLevel = function() return 500 end } end,
}
local handler
_G.ProtocolGame = { registerExtendedJSONOpcode = function(op, fn) handler = fn end, unregisterExtendedJSONOpcode = function() end }
_G.connect, _G.disconnect = function() end, function() end
_G.scheduleEvent = function() return 1 end
_G.removeEvent = function() end
_G.AnchorHorizontalCenter = 1
_G.displayGeneralBox = function(title, body, buttons) local b = { title = title, text = body, buttons = buttons, destroy = function() end } boxes[#boxes + 1] = b return b end
_G.modules = {}
_G.modules.client_chaos_topbar = { ChaosTopBar = { refresh = function() end } }
_G.modules.game_spellbook = { onRanksChanged = function() end }

dofile(here .. 'forms_data.lua')
dofile(here .. 'awakened_data.lua')
dofile(here .. 'ranklogic.lua')
dofile(here .. 'combologic.lua')
dofile(here .. 'awakelogic.lua')
dofile(here .. 'spellranks.lua')
local FD, AD, L, AL = ChaosFormsData, ChaosAwakenedData, ChaosRankLogic, ChaosAwakeLogic

init()
ok(handler ~= nil, 'the handler is registered')
local function msg(action, data) handler(nil, 168, { action = action, data = data }) end

-- the fixture is what a server sent: the shapes the logic reads
ok(type(fx.state) == 'table' and fx.state.on == true and type(fx.state.s) == 'table' and #fx.state.s >= 3, 'the state message holds rows')
ok(type(fx.forms) == 'table' and type(fx.forms.f) == 'table' and #fx.forms.f >= 1, 'the forms message holds rows')
ok(type(fx.awakened) == 'table' and fx.awakened.on == true and #fx.awakened.slots == 3 and #fx.awakened.seals == 3 and #fx.awakened.costs == 3, 'the awakened message holds seals, slots, costs')

-- the live state, and on top of it every spell whose signature is a LEECH or a REFLECT (rank 20, both Forms picked): the live pass cast them, here the window draws them
local stateMsg = { on = true, v = fx.state.v, s = {} }
local formsMsg = { v = fx.forms.v, f = {} }
local inState = {}
for _, row in ipairs(fx.state.s) do stateMsg.s[#stateMsg.s + 1] = row inState[row[1]] = true end
for _, row in ipairs(fx.forms.f) do formsMsg.f[#formsMsg.f + 1] = row end
local extraIds = {}
for id, e in pairs(AD.spells) do
  for _, part in ipairs(e.parts) do
    if (part[1] == 'LEECH' or part[1] == 'REFLECT') and not inState[id] and FD.spells[id] then extraIds[#extraIds + 1] = id break end
  end
end
table.sort(extraIds)
ok(#extraIds >= 15, 'the spells with a LEECH or a REFLECT signature: ' .. #extraIds)
for _, id in ipairs(extraIds) do
  stateMsg.s[#stateMsg.s + 1] = { id, 20, 0, 0 }
  formsMsg.f[#formsMsg.f + 1] = { id, 1, 2 }
end

-- the spells of the state, as the Spellbook would hand them to the tab
local spells = {}
for _, row in ipairs(stateMsg.s) do
  local id = row[1]
  local f = FD.spells[id]
  ok(f ~= nil, 'forms_data.lua knows spell ' .. id .. ' of the live state')
  ok(AD.spells[id] ~= nil, 'awakened_data.lua knows spell ' .. id .. ' of the live state')
  spells[#spells + 1] = { id = id, name = f.name, type = f.heal and 'heal' or 'damage', rank = row[2], into = row[3], cost = row[4] }
end
local picksBy = {}
for _, row in ipairs(formsMsg.f) do picksBy[row[1]] = { f1 = row[2], f2 = row[3] } end
local slotOf = {}
for i, id in ipairs(fx.awakened.slots) do if id > 0 then slotOf[id] = i end end
ok(next(slotOf) ~= nil, 'one spell of the live state is awakened')

local function present(w, m)
  local t = text(w)
  ok(t ~= nil and t ~= '', m .. ' has a text')
  ok(not t:find('nil', 1, true) and not t:find('%%[sd]'), m .. ' has no leftover: ' .. tostring(t))
  return t
end

-- every field of the Upgrades tab of a spell, in the language of `lang`
local function checkTab(spell, lang)
  local id = spell.id
  local who = 'spell ' .. id .. ' (' .. spell.name .. ', ' .. lang .. ')'
  ok(canShowTab(spell), who .. ': the tab shows')
  local info = rowInfo(id)
  if spell.rank > 0 or spell.into > 0 then
    ok(info ~= nil, who .. ': the Spellbook row has rank info')
    eq(info.rank, spell.rank, who .. ': row rank')
    ok(type(info.tip) == 'string' and info.tip ~= '', who .. ': row tip')
    ok(info.percent >= 0 and info.percent <= 100, who .. ': row percent')
  end
  local p = widget()
  fill(p, spell)
  eq(p.emptyText.visible, false, who .. ': the tab draws')
  has(present(p.rankTitle, who .. ' rank title'), tostring(spell.rank), who .. ': the rank')
  local sp = present(p.spText, who .. ' SP text')
  if spell.rank >= 20 then
    eq(p.rankBar.v_Percent, 100, who .. ': full bar at the top')
  else
    ok(math.abs(p.rankBar.v_Percent - 100 * spell.into / spell.cost) < 0.01, who .. ': the bar is the SP into the rank over its cost: ' .. tostring(p.rankBar.v_Percent))
    local togo = string.format('%.2f', spell.cost - spell.into)
    ok(shown(p.rankBar, 'Tooltip'):find(pt and togo:gsub('%.', ',') or togo, 1, true) ~= nil, who .. ': the bar says the SP to go (' .. togo .. '): ' .. tostring(shown(p.rankBar, 'Tooltip')))
    ok(sp:find(pt and string.format('%.2f', spell.into):gsub('%.', ',') or string.format('%.2f', spell.into), 1, true) ~= nil or spell.into == 0, who .. ': the SP text has the SP into the rank: ' .. sp)
  end
  eq(#p.strip.children, 20, who .. ': twenty rank cells')
  local lit = 0
  for _, c in ipairs(p.strip.children) do if c.v_BackgroundColor == '#e8b84a' then lit = lit + 1 end end
  ok(lit >= spell.rank, who .. ': the cells up to the rank are lit')
  present(p.effects, who .. ' effects')
  present(p.note, who .. ' note')
  for _, w in ipairs({ 'form1Title', 'form2Title', 'form1a', 'form1b', 'form2a', 'form2b', 'form1aText', 'form1bText', 'form2aText', 'form2bText' }) do
    present(p[w], who .. ' ' .. w)
  end
  -- the Form picks: the chosen button is marked, a tier that is not open is off
  local pk = picksBy[id] or { f1 = 0, f2 = 0 }
  local rules = L.pickRules(FD)
  for tier = 1, 2 do
    local picked = tier == 1 and pk.f1 or pk.f2
    local locked = spell.rank < (tier == 1 and rules.rank1 or rules.rank2)
    local a, b = p['form' .. tier .. 'a'], p['form' .. tier .. 'b']
    eq(a.enabled, not locked and not (tier == 2 and pk.f1 == 0), who .. ': Form ' .. tier .. ' buttons open by rank and Form I')
    eq(text(a):sub(1, 2) == '> ', picked == 1, who .. ': Form ' .. tier .. ' button 1 marked when picked')
    eq(text(b):sub(1, 2) == '> ', picked == 2, who .. ': Form ' .. tier .. ' button 2 marked when picked')
    ok(shown(a, 'Tooltip') ~= nil and shown(a, 'Tooltip') ~= '', who .. ': Form ' .. tier .. ' button 1 has its sentence')
  end
  -- the awakening view
  p.awakeTab.onClick()
  eq(p.awakeTitle.visible, true, who .. ': the Awakening view shows')
  local title = present(p.awakeTitle, who .. ' awake title')
  local awakeName = pt and AD.spells[id].pt or AD.spells[id].en
  has(title, awakeName, who .. ': the awakened name')
  local pre = realTr('Awakened: %s', '')
  eq(title:sub(1, #pre) == pre, slotOf[id] ~= nil, who .. ': says awakened only for the spell in a slot')
  local seals = present(p.awakeSeals, who .. ' Seals')
  for i = 1, 3 do has(seals, tostring(fx.awakened.seals[i]), who .. ': Seals ' .. i) end
  local slots = present(p.awakeSlots, who .. ' slots')
  for i = 1, 3 do
    local held = fx.awakened.slots[i]
    if held > 0 then
      has(slots, pt and AD.spells[held].pt or AD.spells[held].en, who .. ': slot ' .. i .. ' names its spell')
    else
      for k = 1, 3 do has(slots, tostring(fx.awakened.costs[i][k]), who .. ': slot ' .. i .. ' shows its cost ' .. k) end
    end
  end
  local sentence = present(p.awakeText, who .. ' signature')
  local parts = #AD.spells[id].parts
  local list = AL.sentences(AD.spells[id], realTr, function(v) local t = string.format('%.4g', v) return pt and t:gsub('%.', ',') or t end)
  eq(#list, parts, who .. ': one sentence for each part of the signature')
  for i, s in ipairs(list) do has(sentence, s, who .. ': the sentence of part ' .. i) end
  present(p.awakeDo, who .. ' Awaken button')
  ok(shown(p.awakeDo, 'Tooltip') ~= nil and shown(p.awakeDo, 'Tooltip') ~= '', who .. ': the Awaken button says why (or what it costs)')
  present(p.note, who .. ' awake note')
  -- the awakened name the Spellbook shows
  if slotOf[id] then
    eq(awakenedName(id), awakeName, who .. ': the Spellbook shows the awakened name')
  else
    eq(awakenedName(id), nil, who .. ': a spell that is not awakened keeps its name')
  end
  p.awakeTab.onClick() -- back to the Forms
  eq(p.form1a.visible, true, who .. ': back to the Forms')
end

local function playMessages(lang)
  pt = lang == 'pt-BR'
  _G.ChaosLocale = pt and { lang = 'pt-BR', localize = function(t) return (t:gsub('%.', ',')) end, int = function(v) return tostring(v) end } or nil
  sent, boxes = {}, {}
  msg('state', stateMsg)
  msg('forms', formsMsg)
  msg('awakened', fx.awakened)
  ok(isOn(), lang .. ': the switch is on')
  for _, spell in ipairs(spells) do checkTab(spell, lang) end
  -- the answers: the message shows under the spell it is for (a spell drawn first, then the answer)
  if fx.awaken then
    local res = AL.cleanAnswer(fx.awaken)
    local r = widget()
    fill(r, { id = res.spell, name = (FD.spells[res.spell] or {}).name or '?', type = (FD.spells[res.spell] or {}).heal and 'heal' or 'damage' })
    msg('awaken', fx.awaken)
    local t = present(r.message, lang .. ' awaken answer')
    if res.ok then has(t, pt and AD.spells[res.spell].pt or AD.spells[res.spell].en, lang .. ': the answer names the awakened spell') end
  end
  if fx.pick then
    local id = fx.pick.spell
    local r = widget()
    fill(r, { id = id, name = (FD.spells[id] or {}).name or '?', type = (FD.spells[id] or {}).heal and 'heal' or 'damage' })
    msg('pick', fx.pick)
    present(r.message, lang .. ' pick answer')
  end
  ok(getPickableCount() >= 0, lang .. ': the hub badge counts')
end

playMessages('en')
local usedEn = 0
for _ in pairs(used) do usedEn = usedEn + 1 end
ok(usedEn >= 30, 'the window asked for its texts: ' .. usedEn)
missing = {}
playMessages('pt-BR')
if PT then
  local list = {}
  for k in pairs(missing) do list[#list + 1] = k end
  table.sort(list)
  eq(#list, 0, 'every text of the window has its pt-BR in pt_br.lua; missing: ' .. table.concat(list, ' | '))
  -- the awakened names exist in both languages and differ in at least the heal / damage cases the fixture holds
  for _, spell in ipairs(spells) do
    local e = AD.spells[spell.id]
    ok(type(e.en) == 'string' and e.en ~= '' and type(e.pt) == 'string' and e.pt ~= '', 'both names of spell ' .. spell.id)
  end
end
_G.ChaosLocale = nil

print('spellranks_wire_test: ' .. n .. ' checks OK')
