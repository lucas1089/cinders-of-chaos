-- luajit helper_test.lua && lua5.3 helper_test.lua (from the repository root or this folder)
-- A smoke test of helper.lua against a mock engine: the window builds, a login loads the (missing) file, the tick heals,
-- drinks, shoots and saves, and the entry points other modules call exist. The decisions have their own tests.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ---------------------------------------------------------------- a widget that accepts every call
local registry = {}
local function widget(id)
  local w = { id = id, children = {}, checked = false, visible = true, text = '' }
  return setmetatable(w, { __index = function(t, k)
    if k == 'getChildById' or k == 'recursiveGetChildById' then
      return function(self, cid)
        registry[cid] = registry[cid] or widget(cid)
        return registry[cid]
      end
    end
    if k == 'setId' then return function(self, v) self.id = v; registry[v] = self end end
    if k == 'getId' then return function(self) return self.id end end
    if k == 'setChecked' then return function(self, v) self.checked = v end end
    if k == 'isChecked' then return function(self) return self.checked end end
    if k == 'isVisible' then return function(self) return self.visible end end
    if k == 'show' then return function(self) self.visible = true end end
    if k == 'hide' then return function(self) self.visible = false end end
    if k == 'setText' then return function(self, v) self.text = v end end
    if k == 'clearOptions' then return function(self) self.options = {} end end
    if k == 'addOption' then return function(self, text, data) self.options[#self.options + 1] = { text = text, data = data } end end
    if k == 'setCurrentOptionByData' then return function(self, d) self.current = d end end
    if type(k) == 'string' and k:sub(1, 2) ~= 'on' then return function() return nil end end
    return nil
  end })
end

-- ---------------------------------------------------------------- the engine
local now = 100000
local talked, cancelled = {}, 0
local files = {}
local events = {}
local pos = { x = 100, y = 100, z = 7 }
local player = {
  health = 40, maxHealth = 100, mana = 90, maxMana = 100, level = 100, vocation = 5, pz = false,
}
function player:getHealth() return self.health end
function player:getMaxHealth() return self.maxHealth end
function player:getMana() return self.mana end
function player:getMaxMana() return self.maxMana end
function player:getLevel() return self.level end
function player:getVocation() return self.vocation end
function player:getName() return 'Test Hero' end
function player:getId() return 1 end
function player:getPosition() return pos end
function player:getDirection() return 0 end
function player:isInProtectionZone() return self.pz end
function player:hasState() return false end
function player:getInventoryCount() return 0 end
function player:isPaladin() return false end

local spells = {
  ['Heal Me'] = { id = 1, name = 'Heal Me', words = 'exura vita', group = { [2] = 1000 }, mana = 20, level = 1,
    vocations = { 5 }, range = 0, icon = 'x' },
}
SpellInfo = { Default = spells }
SpellIcons = {}
SpelllistSettings = { Default = { iconsFolder = '/images/x' } }
SpellAreas = {}
Spells = {
  getSpellDataById = function(id) for _, s in pairs(spells) do if s.id == id then return s end end end,
  getSpellDataByWords = function(w) for _, s in pairs(spells) do if s.words == w then return s end end end,
  getImageClipNormal = function() return '0 0 32 32' end,
}
ChaosSpellFix = nil
PlayerStates = { Haste = 1, Hungry = 2 }
AnchorTop, AnchorLeft, AnchorRight, AnchorBottom = 1, 2, 3, 4

g_clock = { millis = function() return now end }
g_logger = { error = function(e) print('LOG ' .. tostring(e)) end }
g_resources = {
  fileExists = function(p) return files[p] ~= nil end,
  readFileContents = function(p) return files[p] end,
  writeFileContents = function(p, t) files[p] = t return true end,
  deleteFile = function(p) files[p] = nil end,
  makeDir = function() end,
}
json = { encode = function(t) return 'JSON' .. tostring(t.helperAutomaticFunctionsEnabled) end,
  decode = function(t) if t:sub(1, 4) == 'JSON' then return { version = 1 } end error('bad') end }
g_ui = {
  importStyle = function() end,
  getRootWidget = function() return widget('root') end,
  createWidget = function(style, parent) return widget(style) end,
  getActionTimer = function() return 0 end,
}
g_map = {
  getSpectators = function() return {} end,
  isSightClear = function() return true end,
  getCreatureById = function() return nil end,
  findItemsById = function() return {} end,
}
g_game = {
  isOnline = function() return true end,
  getLocalPlayer = function() return player end,
  talk = function(w) talked[#talked + 1] = w end,
  doThing = function() end,
  getFollowingCreature = function() return nil end,
  getAttackingCreature = function() return nil end,
  cancelAttack = function() cancelled = cancelled + 1 end,
  getElapsedTicksSinceLastRead = function() return 0 end,
  attack = function() end,
  turn = function() end,
  useInventoryItem = function() end,
  useInventoryItemWith = function() end,
  getCharacterName = function() return 'Test Hero' end,
}
LocalPlayer = {}
local connected = {}
connect = function(obj, handlers) connected[#connected + 1] = handlers end
disconnect = function() end
scheduleEvent = function(fn, ms)
  local e = { fn = fn, at = now + (ms or 0), cancel = function(self) self.dead = true end }
  events[#events + 1] = e
  return e
end
removeEvent = function(e) if type(e) == 'table' then e.dead = true end end
tr = function(s, ...) if select('#', ...) > 0 then return string.format(s, ...) end return s end
modules = { game_textmessage = { displayGameMessage = function() end, displayFailureMessage = function() end } }
table.contains = function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end

-- ---------------------------------------------------------------- the overlay modules the helper uses
local base = dir .. '../'
dofile(base .. 'game_helperrotation/helpersave.lua')
dofile(base .. 'game_helperrotation/rotation.lua')
dofile(base .. 'game_helpertimers/helpertimers.lua')
dofile(base .. 'game_helperrotation/potiongate.lua')
for _, f in ipairs({ 'helper_cycle', 'helper_spells', 'helper_potions', 'helper_config', 'helper_logic' }) do
  dofile(dir .. f .. '.lua')
end
ChaosHelperSave.clean = nil
dofile(dir .. 'helper.lua')

-- ---------------------------------------------------------------- the entry points other modules call
for _, name in ipairs({ 'toggle', 'hide', 'show', 'botStatus', 'toggleAutoTarget', 'toggleMagicShooter', 'toggleShooterPreset',
  'isMagicShooterActive', 'isAutoTargetActive', 'onDropSpell', 'onOpenHelperClick', 'move', 'onHelperViewportChange', 'init',
  'terminate' }) do
  eq(type(_G[name]), 'function', 'exports ' .. name)
end
eq(type(helperConfig), 'table', 'helperConfig is a table')
eq(helperConfig.currentLockedTargetId, 0, 'no locked target')

-- ---------------------------------------------------------------- a login
init()
local startHandlers
for _, h in ipairs(connected) do if h.onGameStart then startHandlers = h end end
eq(startHandlers ~= nil, true, 'the game events are connected')
startHandlers.onGameStart()
eq(type(helperConfig.spells), 'table', 'the config is loaded')
eq(helperConfig.helperAutomaticFunctionsEnabled, true, 'automatic functions on')

-- a heal row: Heal Me at 80 % of health, health is 40 %
helperConfig.spells[1].id = 1
helperConfig.spells[1].percent = 80
local function runDue()
  -- run every scheduled event once that is due
  local list = events
  events = {}
  for _, e in ipairs(list) do
    if e.dead then -- cancelled
    elseif e.at <= now then e.fn() else events[#events + 1] = e end
  end
end
for _ = 1, 6 do
  now = now + 60
  runDue()
end
eq(talked[1], 'exura vita', 'the heal spell was said')

-- the shooter and Auto Target against one monster next to the player (an error is logged by the helper: LOG lines)
spells['Fire Wave'] = { id = 2, name = 'Fire Wave', words = 'exevo flam', group = { [1] = 2000 }, mana = 10, level = 1,
  vocations = { 5 }, range = 0, icon = 'y', area = { { 1 }, { 1 }, { 3 } } }
local monster = { hp = 100 }
function monster:isMonster() return true end
function monster:isDead() return false end
function monster:getHealthPercent() return self.hp end
function monster:getMasterId() return 0 end
function monster:getName() return 'Rat' end
function monster:getId() return 77 end
function monster:getPosition() return { x = 100, y = 99, z = 7 } end
g_map.getSpectators = function() return { monster } end
g_map.getCreatureById = function() return monster end
local attacked = nil
g_game.attack = function(c) attacked = c end
player.health = 100
helperConfig.autoTargetEnabled = true
helperConfig.magicShooterEnabled = true
local profile = helperConfig.shooterProfiles[helperConfig.selectedShooterProfile]
profile.spells[1].id = 2
profile.spells[1].percent = 0
profile.spells[1].creatures = 1
talked = {}
for _ = 1, 40 do now = now + 60 runDue() end
eq(attacked, monster, 'Auto Target attacks the monster')
eq(talked[#talked], 'exevo flam', 'the shooter casts the wave at it')

-- a protection zone pauses the fight systems but not the settings
helperConfig.magicShooterEnabled = true
player.pz = true
for _ = 1, 6 do now = now + 60 runDue() end
eq(helperConfig.magicShooterEnabled, true, 'the settings are kept in a protection zone')
player.pz = false

-- the master switch
botStatus()
eq(helperConfig.helperAutomaticFunctionsEnabled, false, 'botStatus switches the helper off')
eq(isMagicShooterActive(), false, 'and the shooter reports off')
botStatus()
eq(isMagicShooterActive(), true, 'on again')
toggleAutoTarget()
eq(isAutoTargetActive(), false, 'toggleAutoTarget switches it off')
toggleAutoTarget()
eq(isAutoTargetActive(), true, 'and on')

-- a drop of a heal spell on the first row's icon
local icon = registry['spellButton0']
eq(icon ~= nil, true, 'the heal icon has the id the spell list drops on')
onDropSpell(icon, 'exura vita')
eq(helperConfig.spells[1].id, 1, 'the dropped spell is set')

-- a death keeps the settings
startHandlers.onDeath()
eq(helperConfig.magicShooterEnabled, true, 'a death keeps the shooter on')
eq(cancelled >= 1, true, 'a death cancels the attack')

-- logout writes the file and ends the session
local wrote = false
for _, h in ipairs(connected) do if h.onGameEnd then h.onGameEnd() end end
for path in pairs(files) do if path:find('helper.json', 1, true) then wrote = true end end
eq(wrote, true, 'the settings were saved at logout')

terminate()
if fails > 0 then os.exit(1) end
print('helper_test: ok')
