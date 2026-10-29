-- luajit skillstats_glue_test.lua && lua5.3 skillstats_glue_test.lua   (from the repo root or this folder)
-- Runs skillstats.lua against a mocked client: fake Skills window rows, a fake protocol, the opcode handler.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- widgets
local function widget(id)
  local w = { id = id, text = '0', visible = true, children = {} }
  function w:setText(t) self.text = t end
  function w:setColor(c) self.color = c end
  function w:setTooltip(t) self.tip = t end
  function w:setVisible(v) self.visible = v end
  function w:isExplicitlyVisible() return self.visible end
  function w:recursiveGetChildById(cid) return self.children[cid] end
  return w
end
local rows = {}
local function addRow(id, valueId)
  local r = widget(id)
  r.children[valueId] = widget(valueId)
  rows[id] = r
end
addRow('damageHealing', 'damageHealingLabel'); rows.damageHealing.children.damageHealingLabel.id = 'damageHealingLabel'
for _, id in ipairs({ 'attackValue', 'defenseValue', 'armorValue', 'mantraValue', 'mitigationValue' }) do addRow(id, 'value') end
local fitted = 0
local win = widget('skills')
function win:recursiveGetChildById(id) return rows[id] end
function win:setContentMaximumHeight() fitted = fitted + 1 end
modules = { game_skills = { skillsWindow = win, getContentPanelHeight = function() return 300 end } }

-- engine
local online, sent, registered, scheduled = true, {}, {}, {}
local protocol = { sendExtendedOpcode = function(_, op, buf) sent[#sent + 1] = { op = op, buf = buf } end }
g_game = { isOnline = function() return online end, getProtocolGame = function() return protocol end }
ProtocolGame = {
  registerExtendedJSONOpcode = function(op, fn) registered[op] = fn end,
  unregisterExtendedJSONOpcode = function(op) registered[op] = nil end,
}
json = { encode = function(t) return t.action end }
local connected
function connect(_, h) connected = h end
function disconnect() connected = nil end
function scheduleEvent(fn) scheduled[#scheduled + 1] = fn end
function tr(s) return s end
function formatShortNumber(n) if n >= 1000 then return string.format('%.1fk', n / 1000) end return tostring(n) end
local function runScheduled() local q = scheduled; scheduled = {}; for _, f in ipairs(q) do f() end end

dofile(dir .. 'skillstatsview.lua')
dofile(dir .. 'skillstats.lua')

init()
eq(registered[119] ~= nil, true, 'opcode 119 registered')
runScheduled()
eq(rows.armorValue.children.value.text, '-', 'before the server speaks: armor reads -')
eq(rows.mitigationValue.children.value.text, '-', 'mitigation reads -')
eq(rows.damageHealing.children.damageHealingLabel.text, '-', 'damage reads -')
eq(rows.mantraValue.visible, false, 'mantra hidden')
eq(#sent, 1, 'asks the server once'); eq(sent[1].op, 119, 'on opcode 119'); eq(sent[1].buf, 'get', 'with get')
ok = fitted > 0; eq(ok, true, 'the window is fitted to the rows')

registered[119](protocol, 119, { action = 'stats', data = { damage = 15300, attack = 55, defense = 41, armor = 75, mitigation = 0.2308 } })
eq(rows.damageHealing.children.damageHealingLabel.text, '15.3k', 'damage in short form')
eq(rows.attackValue.children.value.text, '55', 'attack')
eq(rows.defenseValue.children.value.text, '41', 'defence')
eq(rows.armorValue.children.value.text, '75', 'armor')
eq(rows.mitigationValue.children.value.text, '+23.1%', 'mitigation')
eq(rows.armorValue.tip ~= nil and #rows.armorValue.tip > 0, true, 'a tooltip says what the number is')

registered[119](protocol, 119, { action = 'stats', data = { defense = 3, armor = 0, mitigation = 0 } })
eq(rows.attackValue.visible, false, 'a wand: attack row hidden')
eq(rows.damageHealing.visible, false, 'a wand: damage row hidden')
eq(rows.armorValue.children.value.text, '0', 'a real zero stays 0')
registered[119](protocol, 119, { action = 'stats', data = { damage = 10, attack = 5, defense = 3, armor = 0, mitigation = 0 } })
eq(rows.attackValue.visible, true, 'a weapon again: attack row back')

registered[119](protocol, 119, { action = 'other', data = {} })
registered[119](protocol, 119, 'junk')
eq(rows.attackValue.children.value.text, '5', 'other actions and junk are ignored')

-- a new game start forgets the numbers
connected.onGameStart(); runScheduled()
eq(rows.armorValue.children.value.text, '-', 'a new game: back to -')

terminate()
eq(registered[119], nil, 'opcode unregistered')
eq(rows.mantraValue.visible, true, 'terminate gives the rows back')

print(fails == 0 and 'skillstats_glue_test: ok' or ('skillstats_glue_test: ' .. fails .. ' failed'))
os.exit(fails == 0 and 0 or 1)
