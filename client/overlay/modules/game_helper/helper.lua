-- game_helper: the helper (client/MANIFEST.md "Helper"). It heals, drinks potions, trains mana, hastes, fights with a
-- rotation of up to five spells (the magic shooter) and picks targets (Auto Target) while the player plays. The other
-- helper modules plug into it (game_helperrotation: Auto rotation, Auto setup, the save rules, potions in closed backpacks;
-- game_helpersupport: the Support tab; game_helpertimers: the cast rate guard; game_helperhud: the Bot HUD; game_autotarget:
-- which monster Auto Target picks; game_targetguard: no locks on the player's own summons).
--
-- The decisions are in the pure files of this module (helper_logic.lua, helper_spells.lua, helper_potions.lua,
-- helper_config.lua), each with a test. This file is the engine glue: the window, the tick, the casts and the save.
-- Rules that hold everywhere:
--   * a spell goes out only when the character can cast it: its class lists it, the level is reached, the server has it, it
--     is not a utility (the lanterns, the ghost rope, the town portal ...), the mana is there and it is off cooldown;
--   * every cast waits for the server's answer (ChaosHelperRotation) and keeps under the rate guard (ChaosHelperTimers);
--   * a cast-time spell that is charging is never interrupted by another attack spell;
--   * a protection zone, a follow and the helper switch pause the automation without touching the settings; a death only
--     drops the locked target and the attack;
--   * the settings are saved per character (/characterdata/characters/<name>/helper.json) through ChaosHelperSave: no save
--     before the file was read, a checked write with a backup, a save at once on death and logout.
-- Runes (helper_runes.lua: healing runes on yourself, attack runes on the target), Auto sell (helper_sell.lua: asks the
-- store's Auto Seller to sell the Loot Bag), Follow (helper_follow.lua) and the heals of the party and a list of friends
-- (helper_ally.lua) were added back on 2026-10-23 (owner request). There is no cavebot and there are no scripts.
_Helper = {}
local H = _Helper
H._suppressMessages = false

local Cfg = ChaosHelperCfg
local Logic = ChaosHelperLogic
local Spl = ChaosHelperSpells
local Pot = ChaosHelperPotions
local Runes = ChaosHelperRunes
local Sell = ChaosHelperSell
local Follow = ChaosHelperFollow
local Ally = ChaosHelperAlly

-- ---------------------------------------------------------------- numbers
local TICK_MS = 50
local EVERY = { heal = 250, mana = 100, routine = 1000, haste = 500, shooter = 100, target = 250, hud = 250, status = 500,
  exercise = 10000, runes = 250, ally = 250, follow = 250, sell = 1000 }
local AFK_SECONDS = 180        -- Auto Target switches itself off after this long without a key or click
local FREEZE_MS = 2500         -- the server sent nothing for this long: wait until it is back
local FREEZE_RESUME_MS = 1500
local SUMMONS_RADIUS = 6       -- "monsters around" for a spell that needs a target
local FOOD_GAP_MS = 120000     -- the gap between meals when the server does not say hungry
local FOOD_IDS = { 3577, 3578, 3579, 3581, 3582, 3583, 3585, 3586, 3587, 3588, 3589, 3592, 3595, 3597, 3600, 3601, 3602,
  3606, 3607, 3723, 3724, 3725, 3728, 3731, 3732, 8011, 8014, 8016, 8017, 12310, 14085, 17457, 17820, 17821, 21143, 21144,
  21146, 23535, 23545 }
-- the server's exercise weapons (client ids) and training dummies (server/README.md "Exercise weapons")
local EXERCISE = { { 27732, 'Exercise Sword' }, { 27733, 'Exercise Axe' }, { 27734, 'Exercise Club' },
  { 27735, 'Exercise Bow' }, { 27736, 'Exercise Rod' }, { 27737, 'Exercise Wand' }, { 27738, 'Durable Exercise Sword' },
  { 27758, 'Exercise Shield' } }
local DUMMIES = { 27751, 27752 }
local EXERCISE_IDLE_MS = 2000

-- ---------------------------------------------------------------- state
helperConfig = Cfg.defaults()
helperConfig.currentLockedTargetId = 0 -- read and written by the game interface and the battle list

local helper = nil           -- the window
local ui = { heal = {}, potion = {}, slot = {} }
local W = {}                 -- the window's named widgets
local building = false       -- the widgets are being filled: no change events
local currentTab = 'healingMenu'
local cycle = nil
local lastRun = {}
local spellCache = nil
local lists = nil            -- the spell pickers' options per kind
local rotation, castTimers = nil, nil
local spellsCooldown, groupsCooldown = {}, {}
local saveSession = nil
local saveEvent = nil
local loaded = false         -- this character's file was read
local status = { reason = nil }
local pzWas = false
local hasteState = { misses = 0 }
local lastFoodAt = nil
local lastPos, lastMovedAt = nil, 0
local frozenUntil = 0
local errorsSeen = {}
local lastLevel, lastVocation = nil, nil
local noticeAt = {}
local sellState, followState, allyState = Sell.newState(), Follow.newState(), Ally.newState()

local function now() return g_clock.millis() end
local function me() return g_game.getLocalPlayer() end

local function logOnce(tag, err)
  local key = tag .. tostring(err)
  if errorsSeen[key] then return end
  errorsSeen[key] = true
  g_logger.error('[helper] ' .. tag .. ': ' .. tostring(err))
end

-- ---------------------------------------------------------------- the spell table
local function buildSpellCache()
  spellCache = {}
  for k, s in pairs(SpellInfo and SpellInfo.Default or {}) do
    if type(s) == 'table' and type(s.id) == 'number' then
      -- the table's key is the spell's name; many entries have none of their own (the utility check needs it)
      if type(s.name) ~= 'string' and type(k) == 'string' then s.name = k end
      spellCache[s.id] = s
    end
  end
end

local function spellById(id)
  id = tonumber(id)
  if not id or id <= 0 then return nil end
  if not spellCache then buildSpellCache() end
  local s = spellCache[id]
  if s then return s end
  if Spells and Spells.getSpellDataById then
    local ok, v = pcall(Spells.getSpellDataById, id)
    if ok and type(v) == 'table' then return v end
  end
  return nil
end
H.getSpellDataById = spellById
getSpellDataById = spellById

local function playerHasSpell(player, spellId)
  -- the learned-spell list is only enforced when the server filled it
  if player and player.getSpells then
    local ok, spells = pcall(function() return player:getSpells() end)
    if ok and type(spells) == 'table' and next(spells) ~= nil then
      return table.contains(spells, spellId)
    end
  end
  return true
end
H.playerHasSpell = playerHasSpell

H.canUseByServerVoc = function(vocations, serverVocId)
  return serverVocId ~= nil and type(vocations) == 'table' and table.contains(vocations, serverVocId)
end

local function spellCtx(player, allowParameter)
  player = player or me()
  if not player then return nil end
  return { vocation = player:getVocation(), level = player:getLevel(), allowParameter = allowParameter == true,
    known = function(id) return playerHasSpell(player, id) end }
end

local function lineOf(player)
  local A = rawget(_G, 'ChaosAutoSetup')
  return A and A.lineOf and A.lineOf(player:getVocation()) or nil
end

-- ---------------------------------------------------------------- cooldowns and the cast
local function getRotation()
  if not rotation and ChaosHelperRotation and ChaosHelperRotation.new then rotation = ChaosHelperRotation.new() end
  return rotation
end
H.getRotation = getRotation

local function getTimers()
  if not castTimers and ChaosHelperTimers and ChaosHelperTimers.new then castTimers = ChaosHelperTimers.new() end
  return castTimers
end

function onSpellCooldown(spellId, delay)
  spellsCooldown[spellId] = now() + delay
  local r = getRotation()
  if r then ChaosHelperRotation.confirmSpell(r, spellId, now()) end
end

function onSpellGroupCooldown(groupId, delay)
  groupsCooldown[groupId] = now() + delay
  local r = getRotation()
  if r then ChaosHelperRotation.confirmGroup(r, groupId, now()) end
end

local function isSpellOnCooldown(spell)
  local t = now()
  if (spellsCooldown[spell.id] or 0) > t then return true end
  for _, g in ipairs(Spl.groupList(spell)) do
    if (groupsCooldown[g] or 0) > t then return true end
  end
  return false
end
H.isSpellOnCooldown = isSpellOnCooldown

local function safeDoThing(flag)
  if g_game and type(g_game.doThing) == 'function' then g_game.doThing(flag) end
end
H.safeDoThing = safeDoThing

local function casting()
  local r = getRotation()
  if r and ChaosHelperRotation.channeling(r, now()) then return true end
  local cb = modules.game_castbar
  return cb ~= nil and cb.isCasting ~= nil and cb.isCasting() == true
end

-- can this spell go out now: the character can cast it, the mana is there, it is off cooldown, the server's answer to its
-- last cast is in (ChaosHelperRotation). Returns true or false and a short reason.
local function ready(spell, player, holdGroups, allowParameter)
  if not spell then return false, 'unknown' end
  local ctx = spellCtx(player, allowParameter)
  local ok, why = Spl.castable(spell, ctx)
  if not ok then return false, why end
  if ChaosHelperRotation and not ChaosHelperRotation.castable(spell, player:getLevel(), player:getMana()) then
    return false, 'mana'
  end
  if isSpellOnCooldown(spell) then return false, 'cooldown' end
  local r = getRotation()
  if r and ChaosHelperRotation.blocked(r, spell.id, spell.group, now(), holdGroups) then return false, 'wait' end
  return true
end

-- say the spell's words (or `words`: the heal-others spells add a name), through the rate guard; true when they went out
local function cast(spell, channel, words)
  local t = now()
  local timers = getTimers()
  words = words or spell.words
  if timers and not ChaosHelperTimers.castAllowed(timers, channel or Spl.channel(spell), words, t) then
    return false
  end
  safeDoThing(false)
  g_game.talk(words)
  safeDoThing(true)
  local r = getRotation()
  if r then ChaosHelperRotation.cast(r, spell.id, spell.group, t) end
  return true
end

-- ---------------------------------------------------------------- pause rules
local function following()
  return g_game.getFollowingCreature ~= nil and g_game.getFollowingCreature() ~= nil
end

local function enabled() return helperConfig.helperAutomaticFunctionsEnabled == true end
H.isHelperAutomaticFunctionsEnabled = enabled

-- why the fight systems are paused now (nil: they run). A pause never touches a setting.
local function pausedWhy(player)
  if not enabled() then return 'helperoff' end
  if player:isInProtectionZone() then return 'pz' end
  if following() then return 'follow' end
  return nil
end

-- ---------------------------------------------------------------- save and load
local fs = {
  exists = function(p) return g_resources.fileExists(p) end,
  read = function(p) return g_resources.readFileContents(p) end,
  write = function(p, text)
    if g_resources.writeFileContents(p, text) == false then error('writeFileContents failed') end
  end,
  copy = function(a, b)
    local text = g_resources.readFileContents(a)
    if g_resources.writeFileContents(b, text) == false then error('copy failed') end
  end,
  delete = function(p) if g_resources.deleteFile then g_resources.deleteFile(p) end end,
}

local function characterName(player)
  local name = player and player.getName and player:getName() or nil
  if type(name) == 'string' and name ~= '' then return name end
  name = g_game.getCharacterName and g_game.getCharacterName() or nil
  return type(name) == 'string' and name or nil
end

-- /characterdata/characters/<name> with the characters that are not letters, digits, - or _ written as _XX
local function storageDir(player)
  local name = characterName(player)
  if not name or name == '' then return nil end
  local key = name:lower():gsub('[^%w%-_]', function(c) return string.format('_%02x', string.byte(c)) end)
  return '/characterdata/characters/' .. key
end

local function session()
  if not saveSession then saveSession = ChaosHelperSave.newSession() end
  return saveSession
end

local function writeNow()
  local HS = ChaosHelperSave
  local player = me()
  local dir = player and storageDir(player)
  if not dir or not HS.canSave(session(), dir) then return false end
  local out = {}
  for k, v in pairs(helperConfig) do out[k] = v end
  out.currentLockedTargetId = nil
  local ok, text = pcall(json.encode, out, 2)
  if not ok or type(text) ~= 'string' then
    g_logger.error('[helper] could not encode the settings: ' .. tostring(text))
    return false
  end
  g_resources.makeDir('/characterdata')
  g_resources.makeDir('/characterdata/characters')
  g_resources.makeDir(dir)
  local written = HS.write(fs, dir .. '/helper.json', text, json.decode)
  if written then
    HS.flushed(session())
  else
    g_logger.error('[helper] the settings file did not read back after the write')
  end
  return written
end

-- a change: written 500 ms after the last one; death and logout write at once
local function saveSettings()
  local player = me()
  local dir = player and storageDir(player)
  if not dir then return false end
  if not ChaosHelperSave.request(session(), dir, now()) then return false end
  if saveEvent then removeEvent(saveEvent) end
  saveEvent = scheduleEvent(function()
    saveEvent = nil
    writeNow()
  end, ChaosHelperSave.DEBOUNCE_MS)
  return true
end
H.saveSettings = saveSettings

local function flushSettings()
  if saveEvent then
    removeEvent(saveEvent)
    saveEvent = nil
  end
  return writeNow()
end
H.flushSettings = flushSettings

local function endSession()
  if saveEvent then removeEvent(saveEvent) saveEvent = nil end
  ChaosHelperSave.endSession(session())
  loaded = false
end

-- Read this character's file. A file of the helper this one replaced loads too (Cfg.sanitize turns its rules into
-- slots, and keeps what it does not use); it is copied once to helper.json.pre-newhelper.bak before the first save.
local function loadSettings()
  local HS = ChaosHelperSave
  local player = me()
  local dir = player and storageDir(player)
  if not dir then return false end
  local st = session()
  HS.beginLoad(st)
  local path = dir .. '/helper.json'
  local source = path
  if not fs.exists(path) then
    local legacy = '/characterdata/' .. player:getId() .. '/helper.json'
    if fs.exists(legacy) then source = legacy end
  end
  local value, readStatus = HS.read(fs, source, json.decode)
  if value then
    if value.version == nil and fs.exists(source) and not fs.exists(path .. '.pre-newhelper.bak') then
      pcall(fs.copy, source, path .. '.pre-newhelper.bak')
    end
    helperConfig = Cfg.sanitize(value)
  else
    helperConfig = Cfg.defaults()
  end
  helperConfig.currentLockedTargetId = 0
  HS.finishLoad(st, dir, readStatus)
  loaded = true
  if source ~= path then saveSettings() end -- copy the old-path file forward
  return value ~= nil
end

-- ---------------------------------------------------------------- the shooter profile
local function currentProfile()
  local profiles = helperConfig.shooterProfiles
  local p = profiles[helperConfig.selectedShooterProfile]
  if not p then
    helperConfig.selectedShooterProfile = Cfg.profileNames(helperConfig)[1] or 'Default'
    p = profiles[helperConfig.selectedShooterProfile]
    if not p then
      p = Cfg.newProfile()
      profiles[helperConfig.selectedShooterProfile] = p
    end
  end
  return p
end

local function ruleLookup(id)
  local s = spellById(id)
  return s and { name = s.name, words = s.words } or nil
end

-- the profile as the Auto rotation module reads it (rules, its marker)
H.getShooterProfile = function()
  return Cfg.rotationView(currentProfile(), ruleLookup)
end
H.getHelperConfig = function() return helperConfig end
getHelperConfig = H.getHelperConfig

-- ---------------------------------------------------------------- the widgets
local TAB_PANELS = { healingMenu = 'healingPanel', combatMenu = 'magicShooterPanel', runesMenu = 'runesPanel',
  alliesMenu = 'alliesPanel', supportMenu = 'supportHost', toolsMenu = 'toolsPanelContainer' }
local TAB_ORDER = { 'healingMenu', 'combatMenu', 'runesMenu', 'alliesMenu', 'supportMenu', 'toolsMenu' }

local MODE_NAMES = {
  [1] = tr('Closest'), [2] = tr('Farthest'), [3] = tr('Lowest health'), [4] = tr('Highest health'),
  [5] = tr('Most monsters hit'), [6] = tr('Closest, lowest health'), [7] = tr('Closest, highest health'),
  [8] = tr('Farthest, lowest health'),
}

local function setIcon(widget, id)
  if not widget then return end
  local spell = spellById(id)
  if not spell then
    widget:setImageSource('/images/ui/item')
    widget:setImageClip('0 0 32 32')
    widget:setTooltip('')
    return
  end
  local source = '/images/game/spells/spell-icons-32x32'
  if SpelllistSettings and SpelllistSettings.Default then
    source = SpelllistSettings.Default.iconsFolder or SpelllistSettings.Default.iconFile or source
  end
  local clip = '0 0 32 32'
  local iconId = SpellIcons and SpellIcons[spell.icon] and SpellIcons[spell.icon][1] or tonumber(spell.id)
  if Spells and Spells.getImageClipNormal and iconId then
    local ok, v = pcall(Spells.getImageClipNormal, iconId, 'Default')
    if ok and v then clip = v end
  end
  widget:setImageSource(source)
  widget:setImageClip(clip)
  widget:setTooltip(tr('Spell: %s\nWords: %s', spell.name or '', spell.words or ''))
end

local function percentOptions(from, to, step)
  local o = {}
  for v = from, to, step do o[#o + 1] = { text = v .. ' %', data = v } end
  return o
end

local function setOptions(combo, options, selected)
  if not combo then return end
  combo:clearOptions()
  for _, o in ipairs(options) do combo:addOption(o.text, o.data, true) end
  combo:setCurrentOptionByData(selected, true)
end

-- the pickers' spells, rebuilt on a level, class or login change
local function spellLists()
  if lists then return lists end
  lists = {}
  local ctx = spellCtx()
  for _, kind in ipairs({ 'attack', 'heal', 'training', 'haste' }) do
    lists[kind] = ctx and Spl.list(kind, SpellInfo and SpellInfo.Default or {}, ctx) or {}
  end
  return lists
end

local function spellOptions(kind, currentId)
  local o = { { text = tr('(empty)'), data = 0 } }
  local seen = {}
  for _, e in ipairs(spellLists()[kind] or {}) do
    o[#o + 1] = { text = e.name, data = e.spell.id }
    seen[e.spell.id] = true
  end
  currentId = tonumber(currentId) or 0
  if currentId > 0 and not seen[currentId] then
    local s = spellById(currentId)
    o[#o + 1] = { text = s and s.name or tostring(currentId), data = currentId }
  end
  return o
end

local function potionKey(row)
  local id = tonumber(row.id) or 0
  if id == 0 then return 0 end
  if Pot.isBoth(id) then return id .. ':' .. (tonumber(row.priority) == 2 and 2 or 1) end
  return tostring(id)
end

local function potionOptions(current)
  local o = { { text = tr('(empty)'), data = 0 } }
  local seen = {}
  for _, e in ipairs(Pot.options() or {}) do
    local text = tr(e.name)
    if Pot.isBoth(e.potion.id) then
      text = e.kind == 'mana' and tr('%s (mana)', text) or tr('%s (health)', text)
    end
    o[#o + 1] = { text = text, data = e.key }
    seen[e.key] = true
  end
  if current ~= 0 and not seen[current] then
    local id = tonumber(tostring(current):match('^(%d+)'))
    local info = id and Pot.info(id)
    o[#o + 1] = { text = info and tr(info.name) or tostring(current), data = current }
  end
  return o
end

local function potionUnit(row)
  local kind = Pot.rowKind(row)
  if kind == 'mana' then return tr('of mana') end
  if kind == 'health' then return tr('of health') end
  return ''
end

-- ---------------------------------------------------------------- runes (helper_runes.lua)
-- does the character's class list the rune (only the runes the table knows a class for are limited)
local function runeClassOk(rune, player)
  if not rune.vocations then return true end
  player = player or me()
  if not player then return false end
  return Spl.classOk({ vocations = rune.vocations }, player:getVocation())
end

local function runeCount(id, player)
  return tonumber(player:getInventoryCount(id, 0)) or 0
end

-- can the rune go out now: its channel is ready and the client counts one, or the probe gate allows a try (a rune in a
-- closed backpack is not counted)
local function runeReady(id, player, channel)
  local t = now()
  local timers = getTimers()
  if timers and not ChaosHelperTimers.useReady(timers, channel, t) then return false end
  if runeCount(id, player) > 0 then return true end
  local gate = ChaosPotionGate
  return gate ~= nil and gate.canUse(id, 0, t)
end

-- use the rune on a creature (the player itself for a healing rune); true when the use went out
local function useRune(id, creature, player, channel)
  if not creature or not runeReady(id, player, channel) then return false end
  local t = now()
  local count = runeCount(id, player)
  safeDoThing(false)
  g_game.useInventoryItemWith(id, creature, 0, true)
  safeDoThing(true)
  local gate = ChaosPotionGate
  if gate then gate.noteUse(id, count, t) end
  local timers = getTimers()
  if timers then ChaosHelperTimers.used(timers, channel, t) end
  return true
end

local function runeOptions(kind, current)
  local o = { { text = tr('(empty)'), data = 0 } }
  local player = me()
  local seen = {}
  for _, r in ipairs(Runes.offered(kind, function(rune) return runeClassOk(rune, player) end)) do
    o[#o + 1] = { text = tr(r.name), data = r.id }
    seen[r.id] = true
  end
  current = tonumber(current) or 0
  if current > 0 and not seen[current] then
    local info = Runes.info(current)
    o[#o + 1] = { text = info and tr(info.name) or tostring(current), data = current }
  end
  return o
end

-- the attack rune rows of the selected preset (older presets may lack them)
local function runeRowsOf(profile)
  if type(profile.runes) ~= 'table' then profile.runes = {} end
  for i = 1, Cfg.RUNE_ROWS do
    if type(profile.runes[i]) ~= 'table' then profile.runes[i] = Cfg.newRune(i) end
  end
  return profile.runes
end

-- the heal-others spells of the allies tab: { { name, spell, entry } } the class may cast (names allowed)
local function allyOptions(list, current)
  local o = { { text = tr('(empty)'), data = 0 } }
  local player = me()
  local seen = {}
  if player then
    local ctx = spellCtx(player, true)
    local offered = Ally.offered(list, spellById, function(sp) return Spl.castable(sp, ctx) end, player:getVocation())
    for _, e in ipairs(offered) do
      o[#o + 1] = { text = e.name, data = e.spell.id }
      seen[e.spell.id] = true
    end
  end
  current = tonumber(current) or 0
  if current > 0 and not seen[current] then
    local sp = spellById(current)
    o[#o + 1] = { text = sp and sp.name or tostring(current), data = current }
  end
  return o
end

local function changed()
  if building then return end
  saveSettings()
  if ChaosBotHud and ChaosBotHud.applyBotHudConfig then pcall(ChaosBotHud.applyBotHudConfig, helperConfig.botHud) end
end

-- one row builders ---------------------------------------------------
local function stack(parent, style, count, idPrefix)
  local rows, prev = {}, nil
  for i = 1, count do
    local row = g_ui.createWidget(style, parent)
    row:setId(idPrefix .. i)
    row:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    row:addAnchor(AnchorRight, 'parent', AnchorRight)
    if prev then row:addAnchor(AnchorTop, prev:getId(), AnchorBottom) else row:addAnchor(AnchorTop, 'parent', AnchorTop) end
    prev = row
    rows[i] = row
  end
  return rows
end

local function buildRows()
  local heal = stack(W.healRows, 'ChaosHelperHealRow', Cfg.SPELL_ROWS, 'healRow')
  for i, row in ipairs(heal) do
    local r = { row = row, icon = row:getChildById('icon'), spell = row:getChildById('spell'),
      percent = row:getChildById('percent') }
    r.icon:setId('spellButton' .. (i - 1)) -- the spell list's drag and drop finds the slot by this id
    r.spell.onOptionChange = function(_, _, data)
      if building then return end
      helperConfig.spells[i].id = tonumber(data) or 0
      setIcon(r.icon, helperConfig.spells[i].id)
      changed()
    end
    r.percent.onOptionChange = function(_, _, data)
      if building then return end
      helperConfig.spells[i].percent = tonumber(data) or 80
      changed()
    end
    ui.heal[i] = r
  end

  local potions = stack(W.potionRows, 'ChaosHelperPotionRow', Cfg.POTION_ROWS, 'potionRow')
  for i, row in ipairs(potions) do
    local r = { row = row, potion = row:getChildById('potion'), percent = row:getChildById('percent'),
      unit = row:getChildById('unit') }
    r.potion.onOptionChange = function(_, _, data)
      if building then return end
      local id, prio = tostring(data):match('^(%d+):?(%d*)$')
      helperConfig.potions[i].id = tonumber(id) or 0
      helperConfig.potions[i].priority = tonumber(prio) or 0
      r.unit:setText(potionUnit(helperConfig.potions[i]))
      changed()
    end
    r.percent.onOptionChange = function(_, _, data)
      if building then return end
      helperConfig.potions[i].percent = tonumber(data) or 50
      changed()
    end
    ui.potion[i] = r
  end

  local slots = stack(W.slotRows, 'ChaosHelperSlotRow', Cfg.SHOOTER_SLOTS, 'slotRow')
  for i, row in ipairs(slots) do
    local r = { row = row, icon = row:getChildById('icon'), spell = row:getChildById('spell'),
      percent = row:getChildById('percent'), creatures = row:getChildById('creatures'),
      force = row:getChildById('force'), selfCast = row:getChildById('selfCast') }
    r.icon:setId('attackSpellButton' .. (i - 1))
    local function slot() return currentProfile().spells[i] end
    r.spell.onOptionChange = function(_, _, data)
      if building then return end
      slot().id = tonumber(data) or 0
      setIcon(r.icon, slot().id)
      changed()
    end
    r.percent.onOptionChange = function(_, _, data)
      if building then return end
      slot().percent = tonumber(data) or 0
      changed()
    end
    r.creatures.onOptionChange = function(_, _, data)
      if building then return end
      slot().creatures = tonumber(data) or 1
      changed()
    end
    r.force.onCheckChange = function(_, checked)
      if building then return end
      slot().forceCast = checked
      changed()
    end
    r.selfCast.onCheckChange = function(_, checked)
      if building then return end
      slot().selfCast = checked
      changed()
    end
    ui.slot[i] = r
  end

  -- mana training and Auto Haste
  local t = W.trainingRow
  ui.training = { enable = t:getChildById('enable'), icon = t:getChildById('icon'), spell = t:getChildById('spell'),
    label = t:getChildById('label'), percent = t:getChildById('percent'), extra = t:getChildById('extra') }
  ui.training.icon:setId('spellTrainingButton')
  ui.training.extra:hide()
  ui.training.label:setText(tr('Cast at mana or above'))
  ui.training.enable:setTooltip(tr('Cast this spell by itself while your mana is at or above the percent'))
  ui.training.enable.onCheckChange = function(_, checked)
    if building then return end
    helperConfig.training[1].enabled = checked
    changed()
  end
  ui.training.spell.onOptionChange = function(_, _, data)
    if building then return end
    helperConfig.training[1].id = tonumber(data) or 0
    setIcon(ui.training.icon, helperConfig.training[1].id)
    changed()
  end
  ui.training.percent.onOptionChange = function(_, _, data)
    if building then return end
    helperConfig.training[1].percent = tonumber(data) or 100
    changed()
  end

  local h = W.hasteRow
  ui.haste = { enable = h:getChildById('enable'), icon = h:getChildById('icon'), spell = h:getChildById('spell'),
    label = h:getChildById('label'), percent = h:getChildById('percent'), extra = h:getChildById('extra') }
  ui.haste.icon:setId('hasteButton')
  ui.haste.label:hide()
  ui.haste.percent:hide()
  ui.haste.extra:setText(tr('Also in protection zones'))
  ui.haste.enable:setTooltip(tr('Cast the haste spell by itself whenever you are not hasted'))
  ui.haste.enable.onCheckChange = function(_, checked)
    if building then return end
    helperConfig.haste[1].enabled = checked
    changed()
  end
  ui.haste.spell.onOptionChange = function(_, _, data)
    if building then return end
    helperConfig.haste[1].id = tonumber(data) or 0
    setIcon(ui.haste.icon, helperConfig.haste[1].id)
    changed()
  end
  ui.haste.extra.onCheckChange = function(_, checked)
    if building then return end
    helperConfig.haste[1].safecast = checked
    changed()
  end
end

-- the rune rows and the allies' pickers (the Runes and Allies tabs)
local function buildRuneRows()
  ui.runeHeal, ui.rune = {}, {}
  for i, row in ipairs(stack(W.runeHealRows, 'ChaosHelperPotionRow', Cfg.RUNE_HEAL_ROWS, 'runeHealRow')) do
    local r = { potion = row:getChildById('potion'), percent = row:getChildById('percent'),
      unit = row:getChildById('unit') }
    r.unit:setText(tr('of health'))
    r.potion.onOptionChange = function(_, _, data)
      if building then return end
      helperConfig.runeHeal[i].id = tonumber(data) or 0
      changed()
    end
    r.percent.onOptionChange = function(_, _, data)
      if building then return end
      helperConfig.runeHeal[i].percent = tonumber(data) or 50
      changed()
    end
    ui.runeHeal[i] = r
  end
  for i, row in ipairs(stack(W.runeAttackRows, 'ChaosHelperRuneRow', Cfg.RUNE_ROWS, 'runeRow')) do
    local r = { rune = row:getChildById('rune'), creatures = row:getChildById('creatures'),
      hpMin = row:getChildById('hpMin'), hpMax = row:getChildById('hpMax') }
    local function cfgRow() return runeRowsOf(currentProfile())[i] end
    r.rune.onOptionChange = function(_, _, data)
      if building then return end
      cfgRow().id = tonumber(data) or 0
      changed()
    end
    r.creatures.onOptionChange = function(_, _, data)
      if building then return end
      cfgRow().creatures = tonumber(data) or 1
      changed()
    end
    r.hpMin.onOptionChange = function(_, _, data)
      if building then return end
      cfgRow().hpMin = tonumber(data) or 0
      changed()
    end
    r.hpMax.onOptionChange = function(_, _, data)
      if building then return end
      cfgRow().hpMax = tonumber(data) or 0
      changed()
    end
    ui.rune[i] = r
  end
end

-- the preset combo -----------------------------------------------------
local function fillPresets()
  local names = Cfg.profileNames(helperConfig)
  local o = {}
  for _, n in ipairs(names) do o[#o + 1] = { text = n, data = n } end
  setOptions(W.presetCombo, o, helperConfig.selectedShooterProfile)
end

local function selectProfile(name)
  if not helperConfig.shooterProfiles[name] then return end
  helperConfig.selectedShooterProfile = name
  helperConfig.autoTargetMode = currentProfile().autoTargetMode or Cfg.MODE_DEFAULT
end

-- the Runes tab from the config
local function refreshRunes()
  if not ui.rune then return end
  local was = building
  building = true
  local pcts = percentOptions(5, 95, 5)
  for i, r in ipairs(ui.runeHeal) do
    local e = helperConfig.runeHeal[i]
    setOptions(r.potion, runeOptions('heal', e.id), e.id)
    setOptions(r.percent, pcts, e.percent)
  end
  local rows = runeRowsOf(currentProfile())
  local counts, mins, maxs = {}, {}, { { text = tr('Any'), data = 0 } }
  for n = 1, Cfg.CREATURES_MAX do counts[#counts + 1] = { text = tostring(n), data = n } end
  for v = 0, 90, 10 do mins[#mins + 1] = { text = v .. ' %', data = v } end
  for v = 10, 100, 10 do maxs[#maxs + 1] = { text = v .. ' %', data = v } end
  for i, r in ipairs(ui.rune) do
    local e = rows[i]
    setOptions(r.rune, runeOptions('attack', e.id), e.id)
    setOptions(r.creatures, counts, e.creatures)
    setOptions(r.hpMin, mins, e.hpMin)
    setOptions(r.hpMax, maxs, e.hpMax)
  end
  building = was
end

-- the Allies tab from the config (party and friends heals, Follow)
local function refreshAllies()
  if not W.partyEnable then return end
  local was = building
  building = true
  local a = helperConfig.allies
  local pcts = percentOptions(5, 95, 5)
  W.partyEnable:setChecked(a.party.enabled == true)
  setOptions(W.partyPercent, pcts, a.party.percent)
  W.friendsEnable:setChecked(a.friends.enabled == true)
  setOptions(W.friendsPercent, pcts, a.friends.percent)
  for i = 1, Cfg.ALLY_NAMES do
    local w = W['friendName' .. i]
    if w then w:setText(a.friends.names[i] or '') end
  end
  local single = ui.allySpell
  setOptions(single.spell, allyOptions(Ally.SINGLE, a.spell), a.spell)
  setIcon(single.icon, a.spell)
  local group = ui.allyGroup
  setOptions(group.spell, allyOptions(Ally.GROUP, a.group.id), a.group.id)
  setIcon(group.icon, a.group.id)
  local counts = {}
  for n = 1, Cfg.GROUP_COUNT_MAX do counts[#counts + 1] = { text = tostring(n), data = n } end
  setOptions(group.count, counts, a.group.count)
  setOptions(ui.allyRune.spell, runeOptions('heal', a.rune.id), a.rune.id)
  local f = helperConfig.follow
  W.followEnable:setChecked(f.enabled == true)
  setOptions(W.followMode, { { text = tr('A friend by name'), data = 'name' }, { text = tr('The party leader'), data = 'leader' } },
    f.mode)
  W.followName:setText(f.name or '')
  W.followName:setEnabled(f.mode ~= 'leader')
  local d = {}
  for n = 1, Cfg.FOLLOW_DISTANCE_MAX do d[#d + 1] = { text = tostring(n), data = n } end
  setOptions(W.followDistance, d, f.distance)
  building = was
end

function H.refreshShooter()
  if not helper then return end
  building = true
  local profile = currentProfile()
  fillPresets()
  for i, r in ipairs(ui.slot) do
    local s = profile.spells[i]
    setOptions(r.spell, spellOptions('attack', s.id), s.id)
    setOptions(r.percent, percentOptions(0, 90, 10), s.percent)
    local c = {}
    for n = 1, Cfg.CREATURES_MAX do c[#c + 1] = { text = tostring(n), data = n } end
    setOptions(r.creatures, c, s.creatures)
    r.force:setChecked(s.forceCast == true)
    r.selfCast:setChecked(s.selfCast == true)
    setIcon(r.icon, s.id)
  end
  local modes = {}
  for i = 1, Cfg.MODE_MAX do modes[#modes + 1] = { text = Cfg.MODE_KEYS[i] .. ': ' .. MODE_NAMES[i], data = i } end
  setOptions(W.autoTargetMode, modes, helperConfig.autoTargetMode)
  W.enableMagicShooter:setChecked(helperConfig.magicShooterEnabled == true)
  W.enableAutoTarget:setChecked(helperConfig.autoTargetEnabled == true)
  local E = rawget(_G, 'ChaosAutoTargetEngine')
  W.priorityTargets:setChecked(E == nil or E.priorityEnabled())
  W.onlyReachable:setChecked(E == nil or E.reachableEnabled())
  W.priorityTargets:setEnabled(E ~= nil)
  W.onlyReachable:setEnabled(E ~= nil)
  building = false
  refreshRunes()
end

local function refreshHealing()
  building = true
  local pcts = percentOptions(5, 95, 5)
  for i, r in ipairs(ui.heal) do
    local s = helperConfig.spells[i]
    setOptions(r.spell, spellOptions('heal', s.id), s.id)
    setOptions(r.percent, pcts, s.percent)
    setIcon(r.icon, s.id)
  end
  for i, r in ipairs(ui.potion) do
    local p = helperConfig.potions[i]
    local key = potionKey(p)
    setOptions(r.potion, potionOptions(key), key)
    setOptions(r.percent, pcts, p.percent)
    r.unit:setText(potionUnit(p))
  end
  local t, tr_ = helperConfig.training[1], ui.training
  setOptions(tr_.spell, spellOptions('training', t.id), t.id)
  setOptions(tr_.percent, percentOptions(50, 100, 10), t.percent)
  tr_.enable:setChecked(t.enabled == true)
  setIcon(tr_.icon, t.id)
  local hs, h = helperConfig.haste[1], ui.haste
  setOptions(h.spell, spellOptions('haste', hs.id), hs.id)
  h.enable:setChecked(hs.enabled == true)
  h.extra:setChecked(hs.safecast == true)
  setIcon(h.icon, hs.id)
  building = false
end

local function refreshTools()
  building = true
  W.autoEat:setChecked(helperConfig.autoEatFood == true)
  local ex = helperConfig.exercise
  local o = { { text = tr('Any exercise weapon I carry'), data = 0 } }
  for _, e in ipairs(EXERCISE) do o[#o + 1] = { text = tr(e[2]), data = e[1] } end
  setOptions(W.exerciseWeapon, o, ex.id)
  W.exerciseEnable:setChecked(ex.enabled == true)
  local hud = helperConfig.botHud
  local sell = helperConfig.autoSell
  W.sellEnable:setChecked(sell.enabled == true)
  local mins = {}
  for _, m in ipairs(Sell.MINUTES) do mins[#mins + 1] = { text = tr('Every %d minutes', m), data = m } end
  setOptions(W.sellMinutes, mins, sell.minutes)
  W.sellBelowCap:setChecked(sell.belowCap == true)
  local caps, haveCap = {}, false
  for _, v in ipairs({ 50, 100, 200, 300, 500, 1000 }) do
    caps[#caps + 1] = { text = tr('At %d oz or less', v), data = v }
    if v == sell.capacity then haveCap = true end
  end
  if not haveCap then caps[#caps + 1] = { text = tr('At %d oz or less', sell.capacity), data = sell.capacity } end
  setOptions(W.sellCapacity, caps, sell.capacity)
  W.hudEnable:setChecked(hud.enabled == true)
  local sizes = {}
  for _, s in ipairs(Cfg.HUD_SIZES) do sizes[#sizes + 1] = { text = tr(s), data = s } end
  setOptions(W.hudSize, sizes, hud.size)
  W.hudTargeting:setChecked(hud.showTargeting ~= false)
  W.hudHaste:setChecked(hud.showHaste ~= false)
  W.hudHealing:setChecked(hud.showHealing ~= false)
  W.hudPlayer:setChecked(hud.showPlayer ~= false)
  building = false
end

-- the whole window from the config (login, a preset change, Auto setup)
function H.reloadUi()
  if not helper then return end
  lists = nil
  refreshHealing()
  H.refreshShooter()
  refreshAllies()
  refreshTools()
  building = true
  W.helperEnabled:setChecked(enabled())
  building = false
end
onLoadHelperData = H.reloadUi
magicShooter = { updateRulesList = function() H.refreshShooter() end, closeConditionSettings = function() end }
H.MagicShooter = { rebuildCache = function() lastRun.shooter = 0 end }

local function showTab(id)
  if not TAB_PANELS[id] then id = 'healingMenu' end
  currentTab = id
  for tab, panel in pairs(TAB_PANELS) do
    local button = helper:recursiveGetChildById(tab)
    local widget = helper:recursiveGetChildById(panel)
    if button then button:setChecked(tab == id) end
    if widget then widget:setVisible(tab == id) end
  end
  if id == 'supportMenu' and ChaosHelperSupportUI and ChaosHelperSupportUI.rebuild then
    pcall(ChaosHelperSupportUI.rebuild)
  end
end

local function updateStatus()
  if not helper or not helper:isVisible() then return end
  local reason = status.reason
  local text
  if reason == 'helperoff' then text = tr('The helper is off')
  elseif reason == 'pz' then text = tr('Paused: protection zone')
  elseif reason == 'follow' then text = tr('Paused: following')
  elseif reason == 'freeze' then text = tr('Paused: waiting for the server')
  else text = tr('Running') end
  W.statusLine:setText(text)
end

-- the on/off state seen by the window and the key bindings
function H.setHelperEnabled(on, showMessage)
  helperConfig.helperAutomaticFunctionsEnabled = on == true
  if helper then
    building = true
    W.helperEnabled:setChecked(on == true)
    building = false
  end
  if not on then
    helperConfig.currentLockedTargetId = 0
  end
  saveSettings()
  if showMessage and modules.game_textmessage then
    modules.game_textmessage.displayGameMessage(on and tr('Helper: On') or tr('Helper: Off'))
  end
end
H.setHelperAutomaticFunctionsEnabled = H.setHelperEnabled

-- the Allies tab: the pickers of the heal spells and the rune, and the switches of party, friends and Follow
local function buildAllyRows()
  local function pick(row)
    return { icon = row:getChildById('icon'), spell = row:getChildById('spell'), label = row:getChildById('label'),
      count = row:getChildById('count') }
  end
  local a = function() return helperConfig.allies end
  ui.allySpell, ui.allyGroup, ui.allyRune = pick(W.allySpellRow), pick(W.allyGroupRow), pick(W.allyRuneRow)
  ui.allySpell.icon:setId('allySpellIcon')
  ui.allySpell.label:hide()
  ui.allySpell.count:hide()
  ui.allySpell.spell.onOptionChange = function(_, _, data)
    if building then return end
    a().spell = tonumber(data) or 0
    setIcon(ui.allySpell.icon, a().spell)
    changed()
  end
  ui.allyGroup.icon:setId('allyGroupIcon')
  ui.allyGroup.label:setText(tr('when this many need it'))
  ui.allyGroup.spell.onOptionChange = function(_, _, data)
    if building then return end
    a().group.id = tonumber(data) or 0
    setIcon(ui.allyGroup.icon, a().group.id)
    changed()
  end
  ui.allyGroup.count.onOptionChange = function(_, _, data)
    if building then return end
    a().group.count = tonumber(data) or 1
    changed()
  end
  ui.allyRune.icon:hide()
  ui.allyRune.spell:setMarginLeft(0) -- no icon: the rune combo starts at the left edge
  ui.allyRune.label:hide()
  ui.allyRune.count:hide()
  ui.allyRune.spell.onOptionChange = function(_, _, data)
    if building then return end
    a().rune.id = tonumber(data) or 0
    changed()
  end
  W.partyEnable.onCheckChange = function(_, checked)
    if building then return end
    a().party.enabled = checked
    changed()
  end
  W.partyPercent.onOptionChange = function(_, _, data)
    if building then return end
    a().party.percent = tonumber(data) or 70
    changed()
  end
  W.friendsEnable.onCheckChange = function(_, checked)
    if building then return end
    a().friends.enabled = checked
    changed()
  end
  W.friendsPercent.onOptionChange = function(_, _, data)
    if building then return end
    a().friends.percent = tonumber(data) or 70
    changed()
  end
  for i = 1, Cfg.ALLY_NAMES do
    local w = W['friendName' .. i]
    w.onTextChange = function(_, text)
      if building then return end
      -- only a clean name is kept (letters, spaces, ' and -): it goes into a chat line
      a().friends.names[i] = Ally.cleanName(text) or ''
      changed()
    end
  end
  W.followEnable.onCheckChange = function(_, checked)
    if building then return end
    helperConfig.follow.enabled = checked
    changed()
  end
  W.followMode.onOptionChange = function(_, _, data)
    if building then return end
    helperConfig.follow.mode = data == 'leader' and 'leader' or 'name'
    W.followName:setEnabled(helperConfig.follow.mode ~= 'leader')
    changed()
  end
  W.followName.onTextChange = function(_, text)
    if building then return end
    helperConfig.follow.name = Ally.cleanName(text) or ''
    changed()
  end
  W.followDistance.onOptionChange = function(_, _, data)
    if building then return end
    helperConfig.follow.distance = tonumber(data) or 1
    changed()
  end
  -- Auto sell (the Tools tab)
  W.sellEnable.onCheckChange = function(_, checked)
    if building then return end
    helperConfig.autoSell.enabled = checked
    sellState = Sell.newState()
    changed()
  end
  W.sellMinutes.onOptionChange = function(_, _, data)
    if building then return end
    helperConfig.autoSell.minutes = tonumber(data) or Sell.DEFAULT_MINUTES
    changed()
  end
  W.sellBelowCap.onCheckChange = function(_, checked)
    if building then return end
    helperConfig.autoSell.belowCap = checked
    changed()
  end
  W.sellCapacity.onOptionChange = function(_, _, data)
    if building then return end
    helperConfig.autoSell.capacity = tonumber(data) or 100
    changed()
  end
end

local function buildWindow()
  g_ui.importStyle('styles/helper')
  helper = g_ui.createWidget('ChaosHelperWindow', g_ui.getRootWidget())
  helper:hide()
  local ids = { 'healRows', 'potionRows', 'slotRows', 'trainingRow', 'hasteRow', 'presetCombo', 'newPresetButton',
    'renameButton', 'duplicateButton', 'deleteButton', 'enableMagicShooter', 'enableAutoTarget', 'autoTargetMode',
    'priorityTargets', 'onlyReachable', 'autoEat', 'exerciseEnable', 'exerciseWeapon', 'hudEnable', 'hudSize',
    'hudTargeting', 'hudHaste', 'hudHealing', 'hudPlayer', 'closeButton', 'statusLine', 'helperEnabled',
    'runeHealRows', 'runeAttackRows', 'partyEnable', 'partyPercent', 'friendsEnable', 'friendsPercent', 'friendName1',
    'friendName2', 'friendName3', 'friendName4', 'friendName5', 'allySpellRow', 'allyGroupRow', 'allyRuneRow',
    'followEnable', 'followMode', 'followName', 'followDistance', 'sellEnable', 'sellMinutes', 'sellBelowCap',
    'sellCapacity' }
  for _, id in ipairs(ids) do W[id] = helper:recursiveGetChildById(id) end
  buildRows()
  buildRuneRows()
  buildAllyRows()

  helper.onEscape = function() H.hide() end
  W.closeButton.onClick = function() H.hide() end
  for _, tab in ipairs(TAB_ORDER) do
    helper:recursiveGetChildById(tab).onClick = function() showTab(tab) end
  end

  W.helperEnabled.onCheckChange = function(_, checked)
    if building then return end
    H.setHelperEnabled(checked, true)
  end

  -- combat
  W.enableMagicShooter.onCheckChange = function(_, checked)
    if building then return end
    helperConfig.magicShooterEnabled = checked
    changed()
  end
  W.enableAutoTarget.onCheckChange = function(_, checked)
    if building then return end
    helperConfig.autoTargetEnabled = checked
    if not checked then helperConfig.currentLockedTargetId = 0 end
    changed()
  end
  W.autoTargetMode.onOptionChange = function(_, _, data)
    if building then return end
    helperConfig.autoTargetMode = tonumber(data) or Cfg.MODE_DEFAULT
    currentProfile().autoTargetMode = helperConfig.autoTargetMode
    changed()
  end
  W.priorityTargets.onCheckChange = function(_, checked)
    if building then return end
    local E = rawget(_G, 'ChaosAutoTargetEngine')
    if E then E.setPriority(checked) end
  end
  W.onlyReachable.onCheckChange = function(_, checked)
    if building then return end
    local E = rawget(_G, 'ChaosAutoTargetEngine')
    if E then E.setReachable(checked) end
  end

  -- presets
  W.presetCombo.onOptionChange = function(_, _, data)
    if building then return end
    selectProfile(tostring(data))
    H.refreshShooter()
    changed()
  end
  local function askName(title, default, onOk)
    if not UIInputBox then return end
    local box = UIInputBox.create(title, function(text)
      text = (text or ''):match('^%s*(.-)%s*$')
      local why = Cfg.nameProblem(text, function(n) return helperConfig.shooterProfiles[n] ~= nil and n ~= default end)
      if text == default and default ~= '' then return end
      if why then
        if modules.game_textmessage then modules.game_textmessage.displayFailureMessage(tr(why)) end
        return
      end
      onOk(text)
    end, function() end)
    box:addLineEdit(tr('Preset name:'), default, Cfg.NAME_MAX)
    box:display()
  end
  W.newPresetButton.onClick = function()
    if Cfg.profileCount(helperConfig) >= Cfg.PROFILES_MAX then return end
    askName(tr('New preset'), '', function(name)
      helperConfig.shooterProfiles[name] = Cfg.newProfile()
      selectProfile(name)
      H.refreshShooter()
      changed()
    end)
  end
  W.duplicateButton.onClick = function()
    if Cfg.profileCount(helperConfig) >= Cfg.PROFILES_MAX then return end
    askName(tr('Duplicate preset'), '', function(name)
      helperConfig.shooterProfiles[name] = Cfg.copy(currentProfile())
      selectProfile(name)
      H.refreshShooter()
      changed()
    end)
  end
  W.renameButton.onClick = function()
    local old = helperConfig.selectedShooterProfile
    askName(tr('Rename preset'), old, function(name)
      helperConfig.shooterProfiles[name] = helperConfig.shooterProfiles[old]
      helperConfig.shooterProfiles[old] = nil
      helperConfig.selectedShooterProfile = name
      H.refreshShooter()
      changed()
    end)
  end
  W.deleteButton.onClick = function()
    if Cfg.profileCount(helperConfig) <= 1 then
      if modules.game_textmessage then
        modules.game_textmessage.displayFailureMessage(tr('You need at least one preset.'))
      end
      return
    end
    helperConfig.shooterProfiles[helperConfig.selectedShooterProfile] = nil
    selectProfile(Cfg.profileNames(helperConfig)[1])
    H.refreshShooter()
    changed()
  end

  -- tools
  W.autoEat.onCheckChange = function(_, checked)
    if building then return end
    helperConfig.autoEatFood = checked
    changed()
  end
  W.exerciseEnable.onCheckChange = function(_, checked)
    if building then return end
    helperConfig.exercise.enabled = checked
    changed()
  end
  W.exerciseWeapon.onOptionChange = function(_, _, data)
    if building then return end
    helperConfig.exercise.id = tonumber(data) or 0
    changed()
  end
  W.hudEnable.onCheckChange = function(_, checked)
    if building then return end
    helperConfig.botHud.enabled = checked
    changed()
  end
  W.hudSize.onOptionChange = function(_, _, data)
    if building then return end
    helperConfig.botHud.size = tostring(data)
    changed()
  end
  for id, key in pairs({ hudTargeting = 'showTargeting', hudHaste = 'showHaste', hudHealing = 'showHealing',
    hudPlayer = 'showPlayer' }) do
    W[id].onCheckChange = function(_, checked)
      if building then return end
      helperConfig.botHud[key] = checked
      changed()
    end
  end
  showTab(currentTab)
end

-- ---------------------------------------------------------------- the creatures around
local function isTargetable(c)
  if not c or not c:isMonster() then return false end
  if c.isDead and c:isDead() then return false end
  if c:getHealthPercent() <= 0 then return false end
  if c.getMasterId and c:getMasterId() ~= 0 then return false end
  local guard = ChaosTargetGuard
  if guard and guard.isSummon(c) then return false end
  local name = (c:getName() or ''):lower()
  if name:find('effigy', 1, true) or name:find('decoy', 1, true) then return false end
  return true
end

-- the monsters in the 7 x 5 window around `pos`, as { id, position, creature, hasSightClear }
local function gather(pos)
  local out = {}
  for _, c in pairs(g_map.getSpectators(pos, false) or {}) do
    if isTargetable(c) then
      local p = c:getPosition()
      if p and Logic.inReach(pos, p) then
        out[#out + 1] = { id = c:getId(), position = p, creature = c, hasSightClear = g_map.isSightClear(pos, p) }
      end
    end
  end
  return out
end

local function creaturesOf(entries)
  local list = {}
  for i, e in ipairs(entries) do list[i] = e.creature end
  return list
end

-- ---------------------------------------------------------------- healing, potions, training, haste, food
local function percentOf(v, max)
  if not max or max <= 0 then return 100 end
  return v * 100 / max
end

local function usePotion(id, player)
  local t = now()
  local timers = getTimers()
  if timers and not ChaosHelperTimers.useReady(timers, 'potion', t) then return false end
  local count = player:getInventoryCount(id, 0)
  local gate = ChaosPotionGate
  if gate then
    if not gate.allowed(gate.session, id, t, count) then return false end
  elseif not count or count <= 0 then
    return false
  end
  safeDoThing(false)
  g_game.useInventoryItemWith(id, player, 0, true)
  safeDoThing(true)
  if gate then gate.used(gate.session, id, t, count) end
  if timers then ChaosHelperTimers.used(timers, 'potion', t) end
  return true
end

local function potionAvailable(id, player)
  if not Pot.canDrink(id, lineOf(player), player:getLevel()) then return false end
  local timers = getTimers()
  if timers and not ChaosHelperTimers.useReady(timers, 'potion', now()) then return false end
  local count = player:getInventoryCount(id, 0)
  if count and count > 0 then return true end
  local gate = ChaosPotionGate
  return gate ~= nil and gate.allowed(gate.session, id, now(), 0)
end

local function healTick(player)
  local hpPct = percentOf(player:getHealth(), player:getMaxHealth())
  local id = Logic.pickHeal(helperConfig.spells, { healthPct = hpPct, ready = function(sid)
    local s = spellById(sid)
    return s ~= nil and ready(s, player, false) == true
  end })
  if id then cast(spellById(id), 'heal') end
  local manaPct = percentOf(player:getMana(), player:getMaxMana())
  -- the Everfull the character carries (server message, game_helperrotation/everfullheld.lua): the Health / Mana Potion
  -- rows follow an upgraded flask
  local held = ChaosEverfullHeld and ChaosEverfullHeld.get() or nil
  local potion = Pot.pick(helperConfig.potions, { healthPct = hpPct, manaPct = manaPct, held = held, level = player:getLevel(),
    available = function(pid) return potionAvailable(pid, player) end })
  if potion then usePotion(potion, player) end
  -- a healing rune on yourself (a carried rune, or a probe for one in a closed backpack)
  local rune = Runes.pickHeal(helperConfig.runeHeal, { healthPct = hpPct, available = function(rid)
    return runeReady(rid, player, 'healRune')
  end })
  if rune then useRune(rune, player, player, 'healRune') end
end

local function trainingTick(player)
  local row = helperConfig.training[1]
  if not Logic.trainingDue(row, percentOf(player:getMana(), player:getMaxMana())) then return end
  if casting() then return end
  local s = spellById(row.id)
  if s and ready(s, player) then cast(s) end
end

local function hasteTick(player, pz)
  local row = helperConfig.haste[1]
  if not row.enabled or (tonumber(row.id) or 0) <= 0 then return end
  local hasted = PlayerStates and PlayerStates.Haste and player:hasState(PlayerStates.Haste) or false
  Logic.hasteObserve(hasteState, hasted)
  if not Logic.hasteDue(row, { hasted = hasted, now = now(), last = hasteState.last, misses = hasteState.misses,
      inProtectionZone = pz }) then return end
  if casting() then return end
  local s = spellById(row.id)
  -- a saved haste the character cannot cast any more (Galeborne Stride, retired 2026-10-23): the best one it has
  if not (s and Spl.eligible('haste', s, spellCtx(player))) then
    local id = Spl.bestHaste(spellById, spellCtx(player))
    if not id then return end
    row.id = id
    s = spellById(id)
  end
  if s and ready(s, player) and cast(s, 'support') then Logic.hasteCast(hasteState, now()) end
end

local function foodTick(player)
  if not helperConfig.autoEatFood then return end
  local t = now()
  local hungry = PlayerStates and PlayerStates.Hungry and player:hasState(PlayerStates.Hungry) or false
  if not hungry and lastFoodAt and t - lastFoodAt < FOOD_GAP_MS then return end
  local timers = getTimers()
  if timers and not ChaosHelperTimers.useReady(timers, 'food', t) then return end
  for _, id in ipairs(FOOD_IDS) do
    if (player:getInventoryCount(id) or 0) > 0 then
      safeDoThing(false)
      g_game.useInventoryItem(id)
      safeDoThing(true)
      if timers then ChaosHelperTimers.used(timers, 'food', t) end
      lastFoodAt = t
      return
    end
  end
end

local function exerciseTick(player)
  local ex = helperConfig.exercise
  if not ex.enabled or not player:isInProtectionZone() then return end
  local t = now()
  if t - lastMovedAt < EXERCISE_IDLE_MS then return end
  local weapon
  for _, e in ipairs(EXERCISE) do
    if (ex.id == 0 or ex.id == e[1]) and (player:getInventoryCount(e[1], 0) or 0) > 0 then
      weapon = e[1]
      break
    end
  end
  if not weapon then return end
  local pos = player:getPosition()
  local best, bestDist
  for _, id in ipairs(DUMMIES) do
    for p, item in pairs(g_map.findItemsById(id, 5) or {}) do
      if p.z == pos.z and g_map.isSightClear(p, pos) then
        local d = Logic.distance(pos, p)
        if not bestDist or d < bestDist then best, bestDist = item, d end
      end
    end
  end
  if not best then return end
  safeDoThing(false)
  g_game.useInventoryItemWith(weapon, best)
  safeDoThing(true)
end

-- ---------------------------------------------------------------- allies, Follow, Auto sell, attack runes
-- the players in view around `pos`, as { id, name, health, position, shield, isSelf, creature }
local function playersAround(pos, multiFloor)
  local out = {}
  local selfId = me() and me():getId() or 0
  for _, c in pairs(g_map.getSpectators(pos, multiFloor == true) or {}) do
    if c:isPlayer() then
      local p = c:getPosition()
      if p then
        out[#out + 1] = { id = c:getId(), name = c:getName(), health = c:getHealthPercent(), position = p,
          shield = c.getShield and c:getShield() or 0, isSelf = c:getId() == selfId, creature = c }
      end
    end
  end
  return out
end

-- heal the party and the friends of the list (helper_ally.lua). Self comes first, a protection zone pauses it.
local function allyTick(player, pz)
  local cfg = helperConfig.allies
  if pz or not (cfg.party.enabled or cfg.friends.enabled) then return end
  local hpPct = percentOf(player:getHealth(), player:getMaxHealth())
  if Ally.selfFirst(helperConfig, hpPct) then return end
  local pos = player:getPosition()
  local cands = Ally.candidates(cfg, playersAround(pos), pos, { sight = function(a, b) return g_map.isSightClear(a, b) end })
  if #cands == 0 then return end
  local vocation = player:getVocation()
  local function spellFor(id)
    local entry = Ally.single(id) or Ally.group(id)
    if not entry then return nil end
    for _, v in ipairs(entry.vocations or { vocation }) do
      if v == vocation then return spellById(id) end
    end
    return nil
  end
  local pick = Ally.pick(cfg, { from = pos, cands = cands, selfFirst = false,
    manaPct = percentOf(player:getMana(), player:getMaxMana()), spellOf = spellFor,
    ready = function(spell) return ready(spell, player, false, true) == true end,
    runeAvailable = function(id)
      local info = Runes.info(id)
      return info ~= nil and runeClassOk(info, player) and runeReady(id, player, 'healRune')
    end })
  if not pick then return end
  local t = now()
  local key = pick.target and pick.target.id or ('group' .. tostring(pick.spell and pick.spell.id))
  if not Ally.allowed(allyState, key, t) then return end
  local went = false
  if pick.kind == 'rune' then
    went = useRune(pick.id, g_map.getCreatureById(pick.target.id), player, 'healRune')
  else
    went = cast(pick.spell, Spl.channel(pick.spell), pick.words)
  end
  if went then Ally.noted(allyState, key, t) end
end

-- follow a friend or the party leader (helper_follow.lua)
local function followTick(player, pz)
  local cfg = helperConfig.follow
  local pos = player:getPosition()
  local players = cfg.enabled and playersAround(pos, true) or {}
  local leader = Follow.leaderOf(cfg, players)
  local followed = g_game.getFollowingCreature and g_game.getFollowingCreature() or nil
  local act, why = Follow.decide(cfg, followState, { helperOn = enabled(), pz = pz, leader = leader, from = pos,
    following = followed and followed:getId() or nil, now = now() })
  status.follow = why
  if act == 'follow' and leader and leader.creature then
    g_game.follow(leader.creature)
  elseif act == 'release' then
    g_game.cancelFollow()
  end
end

-- ask the Auto Seller to sell the Loot Bag (helper_sell.lua); the server decides what is sold
local function sellTick(player)
  local cfg = helperConfig.autoSell
  if not cfg.enabled then return end
  local pouches = modules.game_pouches
  if not (pouches and pouches.getAutoSeller and pouches.sellAll and pouches.syncAutoSeller) then return end
  local act = Sell.decide(cfg, sellState, pouches.getAutoSeller(), { now = now(),
    freeCap = player.getFreeCapacity and player:getFreeCapacity() or nil, helperOn = enabled() })
  if act == 'sync' then pouches.syncAutoSeller() elseif act == 'sell' then pouches.sellAll() end
end

-- an attack rune on the target (helper_runes.lua), while the Magic shooter is on
local function runesTick(player)
  if not helperConfig.magicShooterEnabled then return end
  local target = g_game.getAttackingCreature()
  if not target or not isTargetable(target) then return end
  local pos = player:getPosition()
  local entries = gather(pos)
  for _, e in ipairs(entries) do e.health = e.creature:getHealthPercent() end
  local row = Runes.pickAttack(runeRowsOf(currentProfile()), {
    target = { position = target:getPosition(), health = target:getHealthPercent() }, from = pos, entries = entries,
    inRange = function(p) return p.z == pos.z and Logic.inReach(pos, p) and g_map.isSightClear(pos, p) end,
    available = function(id)
      local info = Runes.info(id)
      return info ~= nil and runeClassOk(info, player) and runeReady(id, player, 'attackRune')
    end })
  if row then useRune(row.id, target, player, 'attackRune') end
end

-- ---------------------------------------------------------------- Auto Target
local function lockedCreature()
  local id = tonumber(helperConfig.currentLockedTargetId) or 0
  if id == 0 then return nil end
  return g_map.getCreatureById(id)
end

local function attack(creature)
  safeDoThing(false)
  g_game.attack(creature)
  safeDoThing(true)
end

local function targetTick(player)
  if not helperConfig.autoTargetEnabled then return end
  if g_ui.getActionTimer and g_ui.getActionTimer() > AFK_SECONDS then
    helperConfig.autoTargetEnabled = false
    helperConfig.currentLockedTargetId = 0
    if helper then
      building = true
      W.enableAutoTarget:setChecked(false)
      building = false
    end
    saveSettings()
    return
  end
  local pos = player:getPosition()
  local E = rawget(_G, 'ChaosAutoTargetEngine')
  local guard = ChaosTargetGuard
  local mode = tonumber(helperConfig.autoTargetMode) or Cfg.MODE_DEFAULT
  local entries = gather(pos)

  local locked = lockedCreature()
  if locked and guard and not guard.keepLock(locked) then locked = nil end
  if locked and not (locked.isDead and locked:isDead()) and locked:getHealthPercent() > 0 and
      Logic.inReach(pos, locked:getPosition()) then
    local keep = true
    if E then
      keep = E.keepLock(locked, pos, mode, function() return creaturesOf(entries) end)
    end
    if keep then
      local attacking = g_game.getAttackingCreature()
      if not attacking or attacking:getId() ~= locked:getId() then
        if guard and guard.lockAction(nil, locked:getId(), attacking and attacking:getId() or 0, now()) == 'drop' then
          helperConfig.currentLockedTargetId = 0
          return
        end
        attack(locked)
      end
      return
    end
  end
  helperConfig.currentLockedTargetId = 0

  local monsters = creaturesOf(entries)
  if E then monsters = E.filter(monsters, pos) end
  local keep = {}
  for _, c in ipairs(monsters) do keep[c:getId()] = true end
  local cands = {}
  local area = SpellAreas and (player:isPaladin() and SpellAreas.AREA_CIRCLE2X2 or SpellAreas.AREA_CIRCLE3X3) or nil
  for _, e in ipairs(entries) do
    if keep[e.id] then
      local hits = 0
      if mode == Logic.MODES.hits and area then
        hits = Logic.countHits(e.position, Logic.DIR.East, area, entries, { ranged = true })
      end
      cands[#cands + 1] = { id = e.id, position = e.position, health = e.creature:getHealthPercent(), hits = hits,
        creature = e.creature }
    end
  end
  local pick = Logic.pickByMode(cands, pos, mode)
  local creature = pick and pick.creature or nil
  if E and creature then creature = E.adjust(creature, monsters, pos, mode) end
  if creature then
    local attacking = g_game.getAttackingCreature()
    if not attacking or attacking:getId() ~= creature:getId() then attack(creature) end
    helperConfig.currentLockedTargetId = creature:getId()
  end
end

-- ---------------------------------------------------------------- the magic shooter
local function monstersNear(entries, pos)
  local n = 0
  for _, e in ipairs(entries) do
    if Logic.distance(pos, e.position) <= SUMMONS_RADIUS then n = n + 1 end
  end
  return n
end

-- How many monsters the slot's spell would hit now, and the facing to cast it at (nil: keep the facing).
local function hitsOf(slot, spell, player, pos, entries, target)
  local R = ChaosHelperRotation
  local range = tonumber(spell.range) or 0
  local area = spell.area
  local targetable = (range > 0 and (not area or spell.needTarget)) and not slot.selfCast
  local sight = function(a, b) return g_map.isSightClear(a, b) end
  if targetable then
    if not target then return 0 end
    local tp = target:getPosition()
    if not tp or tp.z ~= pos.z or Logic.distance(pos, tp) > range then return 0 end
    if type(area) == 'table' then
      return Logic.countHits(tp, Logic.DIR.East, area, entries, { ranged = true }), nil
    end
    return monstersNear(entries, pos), nil
  end
  if type(area) == 'table' then
    local tp = target and target:getPosition() or nil
    if slot.forceCast and tp then
      local dir = Logic.facingToward(pos, tp)
      if dir then return Logic.countHits(pos, dir, area, entries, { sight = sight }), dir end
    end
    local dir, n = Logic.bestDirection(pos, area, entries, { sight = sight })
    return n, dir
  end
  if R and R.isSelfArea(spell) then
    return R.countNear(entries, pos, R.defaults.selfAreaRadius), nil
  end
  return #entries > 0 and 1 or 0, nil
end

local function shooterTick(player)
  if not helperConfig.magicShooterEnabled then return end
  if casting() then return end
  local pos = player:getPosition()
  local profile = currentProfile()
  local manaPct = percentOf(player:getMana(), player:getMaxMana())
  local entries = gather(pos)
  local target = g_game.getAttackingCreature()
  if target and not target:isMonster() then target = nil end
  local R = ChaosHelperRotation
  for _, slot in ipairs(Logic.slotOrder(profile.spells)) do
    local spell = spellById(slot.id)
    if spell and manaPct >= (tonumber(slot.percent) or 0) then
      local ok = ready(spell, player)
      if ok then
        local hits, dir = hitsOf(slot, spell, player, pos, entries, target)
        if Logic.slotDue(slot, manaPct, hits) then
          local tp = target and target:getPosition() or nil
          local turn = R and R.turnDirection(spell, SpellAreas, { enabled = R.autoTurnEnabled(),
            facing = player:getDirection(), best = dir, from = pos, target = tp })
          if cast(spell, 'attack') then
            if turn then g_game.turn(turn) end
            return -- one cast per tick: the next one waits for the server's answer
          end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------- the tick
local function tick()
  local player = me()
  if not player or not g_game.isOnline() or not loaded then return end
  local t = now()
  -- the server sent nothing for a while (a save): do not pile packets up for when it is back
  if g_game.getElapsedTicksSinceLastRead and g_game.getElapsedTicksSinceLastRead() > FREEZE_MS then
    frozenUntil = t + FREEZE_RESUME_MS
  end
  if t < frozenUntil then
    status.reason = 'freeze'
    return
  end
  local pos = player:getPosition()
  if not lastPos or pos.x ~= lastPos.x or pos.y ~= lastPos.y or pos.z ~= lastPos.z then
    lastPos, lastMovedAt = { x = pos.x, y = pos.y, z = pos.z }, t
  end

  local why = pausedWhy(player)
  status.reason = why
  local pz = player:isInProtectionZone()
  if pz and not pzWas then
    -- entering a protection zone drops the attack, not the settings
    helperConfig.currentLockedTargetId = 0
    if g_game.getAttackingCreature() then g_game.cancelAttack() end
  end
  pzWas = pz
  if why == 'helperoff' then
    -- the follow the helper started is let go with the switch
    if followState.ours and following() then
      followState.ours = false
      pcall(g_game.cancelFollow)
    end
    return
  end

  local function due(key)
    if t - (lastRun[key] or 0) >= EVERY[key] then
      lastRun[key] = t
      return true
    end
    return false
  end

  if due('heal') then pcall(healTick, player) end
  if due('ally') then
    local ok, err = pcall(allyTick, player, pz)
    if not ok then logOnce('ally heals', err) end
  end
  if due('follow') then
    local ok, err = pcall(followTick, player, pz)
    if not ok then logOnce('follow', err) end
  end
  if due('sell') then
    local ok, err = pcall(sellTick, player)
    if not ok then logOnce('auto sell', err) end
  end
  if due('mana') then pcall(trainingTick, player) end
  if due('haste') then pcall(hasteTick, player, pz) end
  if due('routine') then
    pcall(foodTick, player)
  end
  if due('exercise') then pcall(exerciseTick, player) end
  if not why then
    if due('target') then
      local ok, err = pcall(targetTick, player)
      if not ok then logOnce('auto target', err) end
    end
    if due('shooter') then
      local ok, err = pcall(shooterTick, player)
      if not ok then logOnce('shooter', err) end
    end
    if due('runes') then
      local ok, err = pcall(runesTick, player)
      if not ok then logOnce('attack runes', err) end
    end
  end
  if due('hud') and ChaosBotHud and ChaosBotHud.refreshBotHud then pcall(ChaosBotHud.refreshBotHud) end
  if due('status') then updateStatus() end
end

-- ---------------------------------------------------------------- game events
local function onHealthChange(player, health, maxHealth, oldHealth)
  -- a hit: heal now, not at the next tick
  if loaded and enabled() and oldHealth and health < oldHealth then
    local t = now()
    if t - (lastRun.heal or 0) >= 100 then
      lastRun.heal = t
      pcall(healTick, player)
    end
  end
end

local function refreshForCharacter()
  lists = nil
  spellCache = nil
  if helper then H.reloadUi() end
end

local function onLevelChange(player, level)
  if lastLevel and level ~= lastLevel then scheduleEvent(refreshForCharacter, 200) end
  lastLevel = level
end

local function onVocationChange()
  scheduleEvent(refreshForCharacter, 200)
end

local function onDeath()
  -- a death is a pause: the lock and the attack go, nothing is switched off
  helperConfig.currentLockedTargetId = 0
  g_game.cancelAttack()
  flushSettings()
end

local function stopCycle()
  if cycle then cycle:cancel() cycle = nil end
end

local function migrateTimerSpells()
  -- the former helper's timed casts by words become Support spells, once
  if Cfg.timersMigrated(helperConfig) or not (ChaosHelperSupportUI and ChaosHelperSupportUI.slots) then return end
  local words = Cfg.timerWords(helperConfig)
  Cfg.markTimersMigrated(helperConfig)
  if #words == 0 then
    saveSettings()
    return
  end
  local slots = ChaosHelperSupportUI.slots()
  local have = {}
  for _, s in ipairs(slots) do have[s.id] = true end
  local added = 0
  for _, w in ipairs(words) do
    local data = Spells and Spells.getSpellDataByWords and Spells.getSpellDataByWords(w) or nil
    if data and data.id and not have[data.id] and not Spl.isUtility(data) and #slots < 8 then
      slots[#slots + 1] = { id = data.id, enabled = true }
      have[data.id] = true
      added = added + 1
    end
  end
  if added > 0 then ChaosHelperSupportUI.setSlots(slots) end
  saveSettings()
end

local function online()
  lists, spellCache = nil, nil
  rotation, castTimers = nil, nil
  spellsCooldown, groupsCooldown = {}, {}
  lastRun, hasteState, lastFoodAt, frozenUntil, pzWas = {}, { misses = 0 }, nil, 0, false
  sellState, followState, allyState = Sell.newState(), Follow.newState(), Ally.newState()
  local player = me()
  lastLevel = player and player:getLevel() or nil
  if ChaosPotionGate and ChaosPotionGate.reset then ChaosPotionGate.reset() end
  loadSettings()
  H.reloadUi()
  stopCycle()
  cycle = ChaosHelperCycle.new(function(fn, ms) return scheduleEvent(fn, ms) end, tick, TICK_MS,
    function(err) logOnce('tick', err) end)
  scheduleEvent(function()
    if g_game.isOnline() then
      pcall(migrateTimerSpells)
      if ChaosBotHud and ChaosBotHud.applyBotHudConfig then pcall(ChaosBotHud.applyBotHudConfig, helperConfig.botHud) end
    end
  end, 1500)
end

local function offline()
  stopCycle()
  if loaded then flushSettings() end
  endSession()
  helperConfig.currentLockedTargetId = 0
  if helper then helper:hide() end
  if ChaosBotHud and ChaosBotHud.applyBotHudConfig then pcall(ChaosBotHud.applyBotHudConfig, { enabled = false }) end
end

-- ---------------------------------------------------------------- what other modules call
function H.show()
  if not helper then return end
  H.reloadUi()
  helper:show(true)
  helper:raise()
  helper:focus()
  showTab(currentTab)
  updateStatus()
end
show = H.show

function H.hide()
  if loaded then saveSettings() end
  if helper then helper:hide() end
end
hide = H.hide

function H.toggle()
  if not g_game.isOnline() then return end
  if helper and helper:isVisible() then H.hide() else H.show() end
end
toggle = H.toggle

-- the game interface asks the helper to take a place in a side panel; the helper is a window, so it just opens
function move()
  return nil
end

function onOpenHelperClick() H.toggle() end
function onHelperViewportChange() end

-- the "Enable/Disable Helper" key (called with a colon, so the first argument is the module)
function botStatus()
  H.setHelperEnabled(not enabled(), true)
end
toggleHelperFunctions = botStatus

function isMagicShooterActive()
  return enabled() and helperConfig.magicShooterEnabled == true
end

function isAutoTargetActive()
  return enabled() and helperConfig.autoTargetEnabled == true
end

local function tellSwitch(label, on)
  if modules.game_textmessage then
    modules.game_textmessage.displayGameMessage(on and tr('%s: On', label) or tr('%s: Off', label))
  end
end

function toggleMagicShooter()
  helperConfig.magicShooterEnabled = not helperConfig.magicShooterEnabled
  if helper then
    building = true
    W.enableMagicShooter:setChecked(helperConfig.magicShooterEnabled)
    building = false
  end
  saveSettings()
  tellSwitch(tr('Magic shooter'), helperConfig.magicShooterEnabled)
end

function toggleAutoTarget()
  helperConfig.autoTargetEnabled = not helperConfig.autoTargetEnabled
  if not helperConfig.autoTargetEnabled then helperConfig.currentLockedTargetId = 0 end
  if helper then
    building = true
    W.enableAutoTarget:setChecked(helperConfig.autoTargetEnabled)
    building = false
  end
  saveSettings()
  tellSwitch(tr('Auto target'), helperConfig.autoTargetEnabled)
end

function toggleShooterPreset()
  local nextName = Cfg.nextProfile(helperConfig, helperConfig.selectedShooterProfile)
  if not nextName then return end
  selectProfile(nextName)
  H.refreshShooter()
  saveSettings()
  if modules.game_textmessage then
    modules.game_textmessage.displayGameMessage(tr('Preset: %s', nextName))
  end
end

-- a spell dragged from the spell list onto a slot of the window (the icon's id says which: spellButtonN, attackSpellButtonN,
-- spellTrainingButton, hasteButton)
function onDropSpell(widget, words)
  local data = Spells.getSpellDataByWords(words)
  local player = me()
  if not data or not widget or not player then return end
  local spell = spellById(data.id)
  local wid = widget:getId()
  local ctx = spellCtx(player)
  local index = tonumber(wid:match('(%d+)$'))
  local function refuse()
    if modules.game_textmessage then
      modules.game_textmessage.displayFailureMessage(tr('You cannot use this spell here.'))
    end
  end
  if not spell then return refuse() end
  if wid:match('^spellButton') and index and helperConfig.spells[index + 1] then
    if not Spl.eligible('heal', spell, ctx) then return refuse() end
    helperConfig.spells[index + 1].id = spell.id
  elseif wid:match('^attackSpellButton') and index and currentProfile().spells[index + 1] then
    if not Spl.eligible('attack', spell, ctx) then return refuse() end
    currentProfile().spells[index + 1].id = spell.id
  elseif wid:match('^spellTrainingButton') then
    if not Spl.eligible('training', spell, ctx) then return refuse() end
    helperConfig.training[1].id = spell.id
  elseif wid:match('^hasteButton') then
    if not Spl.eligible('haste', spell, ctx) then return refuse() end
    helperConfig.haste[1].id = spell.id
  else
    return
  end
  H.reloadUi()
  saveSettings()
end

-- ---------------------------------------------------------------- module start and stop
function init()
  connect(LocalPlayer, { onLevelChange = onLevelChange, onVocationChange = onVocationChange,
    onHealthChange = onHealthChange })
  connect(g_game, { onGameStart = online, onGameEnd = offline, onDeath = onDeath, onSpellCooldown = onSpellCooldown,
    onSpellGroupCooldown = onSpellGroupCooldown })
  buildWindow()
  if g_game.isOnline() then online() end
end

function terminate()
  disconnect(LocalPlayer, { onLevelChange = onLevelChange, onVocationChange = onVocationChange,
    onHealthChange = onHealthChange })
  disconnect(g_game, { onGameStart = online, onGameEnd = offline, onDeath = onDeath, onSpellCooldown = onSpellCooldown,
    onSpellGroupCooldown = onSpellGroupCooldown })
  stopCycle()
  if loaded then flushSettings() end
  endSession()
  if helper then
    helper:destroy()
    helper = nil
  end
end
