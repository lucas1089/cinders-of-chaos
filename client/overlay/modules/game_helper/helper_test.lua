-- luajit helper_test.lua && lua5.3 helper_test.lua (from the repository root or this folder)
-- A smoke test of helper.lua against a mock engine: the window builds, a login loads the (missing) file, the tick heals,
-- drinks, shoots and saves, and the entry points other modules call exist. The decisions have their own tests.
-- It also drives the runes, the party and friend heals, Follow and Auto sell through the tick, and the load of a file the
-- former helper wrote (its follow friend and Auto Sell Loot settings).
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
local used, followed, cancelledFollow = {}, {}, 0
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
local counts = {}
function player:getInventoryCount(id) return counts[id] or 0 end
function player:getFreeCapacity() return 500 end
function player:isPaladin() return false end

local spells = {
  ['Heal Me'] = { id = 1, name = 'Heal Me', words = 'exura vita', group = { [2] = 1000 }, mana = 20, level = 1,
    vocations = { 5 }, range = 0, icon = 'x' },
}
spells['Kindred Mend'] = { id = 84, name = 'Kindred Mend', words = 'saen kin', group = { [2] = 1000 }, mana = 20, level = 1,
  vocations = { 5 }, range = 0, icon = 'z', parameter = true }
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
  decode = function(t)
    if t:sub(1, 4) == 'JSON' then return { version = 1 } end
    -- a file of the former helper: its follow friend and Auto Sell Loot
    if t == 'OLDFILE' then
      return { followFriendEnabled = true, followFriendName = 'Zed', autoQuillSell = true, autoQuillSellBelowCap = true,
        autoQuillSellCapacity = 150 }
    end
    error('bad')
  end }
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
  useInventoryItemWith = function(id, to) used[#used + 1] = { id = id, to = to } end,
  follow = function(c) followed[#followed + 1] = c end,
  cancelFollow = function() cancelledFollow = cancelledFollow + 1 end,
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
local sold, synced = 0, 0
local seller = { known = true, unlocked = true, cooldown = 0 }
modules = { game_textmessage = { displayGameMessage = function() end, displayFailureMessage = function() end },
  game_pouches = { getAutoSeller = function() return seller end, sellAll = function() sold = sold + 1 end,
    syncAutoSeller = function() synced = synced + 1 end } }
table.contains = function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end

-- ---------------------------------------------------------------- the overlay modules the helper uses
local base = dir .. '../'
dofile(base .. 'game_helperrotation/helpersave.lua')
dofile(base .. 'game_helperrotation/rotation.lua')
dofile(base .. 'game_helpertimers/helpertimers.lua')
dofile(base .. 'game_helperrotation/potiongate.lua')
for _, f in ipairs({ 'helper_cycle', 'helper_spells', 'helper_potions', 'helper_runes', 'helper_sell', 'helper_ally',
  'helper_follow', 'helper_config', 'helper_logic' }) do
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
files['/characterdata/characters/test_20hero/helper.json'] = 'OLDFILE'
init()
local startHandlers
for _, h in ipairs(connected) do if h.onGameStart then startHandlers = h end end
eq(startHandlers ~= nil, true, 'the game events are connected')
startHandlers.onGameStart()
eq(type(helperConfig.spells), 'table', 'the config is loaded')
eq(helperConfig.helperAutomaticFunctionsEnabled, true, 'automatic functions on')
-- the former helper's file: follow friend and Auto Sell Loot carried over, the old file copied aside once
eq(helperConfig.follow.enabled, true, 'the old follow friend is taken over')
eq(helperConfig.follow.name, 'Zed', 'with its name')
eq(helperConfig.autoSell.enabled, true, 'the old Auto Sell Loot is taken over')
eq(helperConfig.autoSell.belowCap, true, 'with the low capacity option')
eq(helperConfig.autoSell.capacity, 150, 'and its capacity')
eq(files['/characterdata/characters/test_20hero/helper.json.pre-newhelper.bak'], 'OLDFILE', 'the old file is kept aside')
helperConfig.follow.enabled = false
helperConfig.autoSell.enabled = false

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
function monster:isPlayer() return false end
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

-- ---------------------------------------------------------------- party and friend heals, runes, Follow, Auto sell
local function run(n) for _ = 1, n do now = now + 60 runDue() end end
local friend = { hp = 40, pos = { x = 103, y = 100, z = 7 } }
function friend:isMonster() return false end
function friend:isPlayer() return true end
function friend:isDead() return false end
function friend:getHealthPercent() return self.hp end
function friend:getName() return 'Zed' end
function friend:getId() return 55 end
function friend:getPosition() return self.pos end
function friend:getShield() return 0 end
local spectators = { friend }
g_map.getSpectators = function() return spectators end
g_map.getCreatureById = function(id) for _, c in ipairs(spectators) do if c:getId() == id then return c end end end
helperConfig.magicShooterEnabled = false
helperConfig.autoTargetEnabled = false
player.health = 100
helperConfig.spells[1].id = 1
helperConfig.spells[1].percent = 80

-- a friend of the list below the percent is healed with the name in quotes, and not over and over
helperConfig.allies.friends = { enabled = true, percent = 60, names = { 'Zed', '', '', '', '' } }
helperConfig.allies.spell = 84
talked = {}
run(40)
local healsOfFriend = 0
for _, w in ipairs(talked) do if w == 'saen kin "Zed"' then healsOfFriend = healsOfFriend + 1 end end
eq(healsOfFriend >= 1, true, 'the friend is healed with the name')
eq(healsOfFriend <= 3, true, 'and not spammed (' .. healsOfFriend .. ' heals in 2.4 s)')
-- the friend above the percent is left alone
friend.hp = 90
talked = {}
run(40)
eq(#talked, 0, 'a friend above the percent is not healed')
-- a player who is not in the list is left alone
friend.hp = 40
helperConfig.allies.friends.names[1] = 'Other'
run(40)
eq(#talked, 0, 'a player outside the list is not healed')
helperConfig.allies.friends.names[1] = 'Zed'
-- yourself first: a heal row due by the numbers
player.health = 40
talked = {}
run(40)
local healedFriend = false
for _, w in ipairs(talked) do if w:find('saen kin', 1, true) then healedFriend = true end end
eq(healedFriend, false, 'the character heals itself before it heals a friend')
-- a protection zone pauses the ally heals
player.health = 100
player.pz = true
talked = {}
run(40)
eq(#talked, 0, 'no ally heal in a protection zone')
player.pz = false
-- out of line of sight
g_map.isSightClear = function() return false end
talked = {}
run(40)
eq(#talked, 0, 'no ally heal behind a wall')
g_map.isSightClear = function() return true end
helperConfig.allies.friends.enabled = false

-- a healing rune on yourself, from a carried stack
helperConfig.spells[1].id = 0
helperConfig.runeHeal[1] = { id = 3152, percent = 60 }
counts[3152] = 3
player.health = 40
used = {}
run(40)
eq(#used >= 1, true, 'the healing rune is used')
eq(used[1] and used[1].id, 3152, 'it is the Mending rune')
eq(used[1] and used[1].to, player, 'on the character')
eq(#used <= 3, true, 'and not every tick (' .. #used .. ' uses in 2.4 s)')
player.health = 100
used = {}
run(20)
eq(#used, 0, 'no healing rune at full health')
helperConfig.runeHeal[1].id = 0
helperConfig.spells[1].id = 1

-- an attack rune on the target while the Magic shooter is on
spectators = { monster }
local fighting = monster
g_game.getAttackingCreature = function() return fighting end
profile.spells[1].id = 0
profile.runes[1] = { id = 3155, creatures = 1, hpMin = 0, hpMax = 0, priority = 1 }
counts[3155] = 5
helperConfig.magicShooterEnabled = true
used = {}
run(40)
eq(#used >= 1, true, 'the attack rune is used')
eq(used[1] and used[1].id, 3155, 'it is the Reaper rune')
eq(used[1] and used[1].to, monster, 'on the target')
profile.runes[1].creatures = 4
used = {}
run(40)
eq(#used, 0, 'too few monsters: no rune')
profile.runes[1].creatures = 1
counts[3155] = 0
used = {}
run(40)
eq(#used <= 1, true, 'no rune in the backpack: at most one probe (' .. #used .. ')')
counts[3155] = 5
helperConfig.magicShooterEnabled = false
used = {}
run(40)
eq(#used, 0, 'Magic shooter off: no attack rune')
helperConfig.magicShooterEnabled = true
player.pz = true
run(10)
used = {}
run(40)
eq(#used, 0, 'no attack rune in a protection zone')
player.pz = false
helperConfig.magicShooterEnabled = false
profile.runes[1].id = 0
fighting = nil
g_game.getAttackingCreature = function() return nil end

-- Follow: asks for a follow of the named friend, not in a protection zone, lets go when the friend leaves the floor
spectators = { friend }
friend.hp = 100
friend.pos = { x = 104, y = 100, z = 7 }
helperConfig.follow = { enabled = true, mode = 'name', name = 'Zed', distance = 1 }
followed = {}
run(10)
eq(followed[1], friend, 'the helper follows the named friend')
eq(#followed <= 4, true, 'at a measured rate (' .. #followed .. ')')
g_game.getFollowingCreature = function() return friend end
local before = cancelledFollow
friend.pos = { x = 104, y = 100, z = 6 }
run(10)
eq(cancelledFollow > before, true, 'the follow is let go when the friend is on another floor')
g_game.getFollowingCreature = function() return nil end
friend.pos = { x = 104, y = 100, z = 7 }
player.pz = true
followed = {}
run(10)
eq(#followed, 0, 'no follow in a protection zone')
player.pz = false
helperConfig.follow.enabled = false
followed = {}
run(10)
eq(#followed, 0, 'Follow off: no follow')

-- Auto sell: asks the Auto Seller when the timer is out, never when it is locked, not twice in a row
helperConfig.autoSell = { enabled = true, minutes = 5, belowCap = false, capacity = 100 }
sold = 0
run(40)
eq(sold, 0, 'no sale at the start')
now = now + 5 * 60000 + 2000
run(20)
eq(sold, 1, 'one ask after the interval')
run(40)
eq(sold, 1, 'not again at once')
seller.unlocked = false
now = now + 6 * 60000
run(40)
eq(sold, 1, 'a locked Auto Seller is never asked to sell')
seller.unlocked = true
helperConfig.autoSell.enabled = false
now = now + 6 * 60000
run(40)
eq(sold, 1, 'Auto sell off: no ask')
local before2 = synced
modules.game_pouches.getAutoSeller = function() return { known = false } end
helperConfig.autoSell.enabled = true
run(40)
eq(synced > before2, true, 'an unknown seller state is asked for')
modules.game_pouches.getAutoSeller = function() return seller end
helperConfig.autoSell.enabled = false
spectators = { monster }
g_map.getCreatureById = function() return monster end
helperConfig.magicShooterEnabled = true

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
