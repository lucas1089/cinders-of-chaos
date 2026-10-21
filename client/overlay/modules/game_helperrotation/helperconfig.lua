-- ChaosHelperConfig: the helper's saved settings checked on load (pure: helperconfig_test.lua; client/MANIFEST.md
-- "Helper settings checked on load").
-- Players can edit the files these come from by hand: the per-character helper.json of the helper (mods/game_helper,
-- read through ChaosHelperSave.read, base patch 0067) and the g_settings nodes of config.otml that the overlay keeps
-- per character (Auto rotation's spell choices, Auto setup's timer words). Every number that drives the automation
-- (thresholds, delays, counts, ids, priorities) is clamped to the range the helper's own controls allow, every value
-- of the wrong type falls back to its default, lists are capped, so a hand-edited file can make the helper neither
-- cast in a loop (a 0 s timer, a 1000 % threshold) nor fail. Fields this file does not know are left as they are,
-- except the settings of the options the compact helper window dropped (base patch 0105, HC.DROPPED): an old file
-- still loads, without them.
-- The base helper still runs its own fill-in of missing fields after this (helper.lua loadSettings).
ChaosHelperConfig = ChaosHelperConfig or {}
local HC = ChaosHelperConfig

HC.ID_MAX = 1000000           -- spell, item and creature ids
HC.ROWS_MAX = 10              -- spell, potion, training ... rows of the healing panel
HC.RULES_MAX = 100            -- timer, equip and magic shooter rules of one profile
HC.PROFILES_MAX = 50          -- shooter, equip and supply profiles
HC.STAMINA_MAX = 2520         -- minutes (42 hours of stamina)
HC.COOLDOWN_MAX = 86400       -- a timer rule's cooldown, in its unit (at least 1)
HC.CREATURES_MAX = 10         -- the magic shooter's "N+" / "N-" options
HC.TARGET_MODES = 8           -- autoTargetMode A..H = 1..8
HC.SPECIAL_FOOD_SLOTS = 4
HC.ABSOLUTE_MAX = 10000000    -- an equip rule on HP / MP points
HC.WORDS_MAX = 64             -- Auto setup's remembered timer words
HC.TEXT_MAX = 128
HC.VOCATIONS = { knight = 5, paladin = 4, sorcerer = 3, druid = 2, monk = 1 } -- the default priority of each
-- settings of helper options base patch 0105 removed, dropped on load: Cure Paralyze, Auto Sell Loot (a Summon Quill
-- or a summoned sell NPC, neither on this server), Quiver Refill (no quiver slot in 10.98, hidden since the start)
HC.DROPPED = { 'paralyzeCure', 'autoQuillSell', 'autoQuillSellBelowCap', 'autoQuillSellCapacity', 'quiverRefill' }
-- fields inside a kept table: Exana Vita (no spell ends the ward here) and the bot HUD's cavebot rows (no cavebot)
HC.DROPPED_FIELDS = { magicShield = { 'exanaEnabled', 'exanaHpPercent' }, botHud = { 'showCavebot', 'showWaypoints' } }

-- ---------------------------------------------------------------- value checks

-- a whole number in lo..hi: a number or a numeric string is clamped; anything else (nil, NaN, inf, a table) is the
-- default
function HC.int(v, lo, hi, default)
  local n = v
  if type(n) == 'string' then n = tonumber(n) end
  if type(n) ~= 'number' or n ~= n or n == math.huge or n == -math.huge then return default end
  n = math.floor(n)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

function HC.bool(v, default)
  if type(v) == 'boolean' then return v end
  return default
end

function HC.oneOf(v, allowed, default)
  for _, a in ipairs(allowed) do
    if v == a then return v end
  end
  return default
end

function HC.text(v, max, default)
  if type(v) ~= 'string' then return default end
  if #v > max then return v:sub(1, max) end
  return v
end

local function id(v) return HC.int(v, 0, HC.ID_MAX, 0) end

-- a list: entries that are not tables go, at most `max`, each checked by fix(entry, index) (nil drops it)
local function list(t, max, fix)
  if type(t) ~= 'table' then return nil end
  local out = {}
  for i, e in ipairs(t) do
    if #out >= max then break end
    if type(e) == 'table' then
      local v = fix(e, i)
      if v ~= nil then out[#out + 1] = v end
    end
  end
  return out
end

-- a map of profiles by name: string names, table values, at most PROFILES_MAX
local function profiles(t, fix)
  if type(t) ~= 'table' then return nil end
  local names = {}
  for k, v in pairs(t) do
    if type(k) == 'string' and #k <= HC.TEXT_MAX and type(v) == 'table' then names[#names + 1] = k end
  end
  table.sort(names)
  local out = {}
  for i = 1, math.min(#names, HC.PROFILES_MAX) do out[names[i]] = fix(t[names[i]]) end
  return out
end

-- ---------------------------------------------------------------- helper.json

local function healRow(default) return function(e)
  e.id = id(e.id)
  e.percent = HC.int(e.percent, 0, 100, default)
  return e
end end

local function vocHealing(t)
  if type(t) ~= 'table' or t[1] ~= nil then return t end -- missing or the old list format: the helper resets it
  for voc, prio in pairs(HC.VOCATIONS) do
    local v = t[voc]
    if v ~= nil then
      if type(v) ~= 'table' then
        t[voc] = nil -- the helper fills a missing vocation with its default
      else
        v.enabled = HC.bool(v.enabled, false)
        v.percent = HC.int(v.percent, 1, 100, 90)
        v.priority = HC.int(v.priority, 1, 5, prio)
      end
    end
  end
  if t.extended ~= nil then t.extended = HC.bool(t.extended, false) end
  return t
end

local function shooterRule(e)
  e.spellId = id(e.spellId)
  e.itemId = id(e.itemId)
  e.manaPercent = HC.int(e.manaPercent, 0, 100, 0)
  e.creatures = HC.int(e.creatures, 1, HC.CREATURES_MAX, 1)
  e.type = HC.oneOf(e.type, { 'spell', 'rune' }, nil)
  if e.type == nil then return nil end
  if e.countLowerThan ~= nil then e.countLowerThan = HC.bool(e.countLowerThan, false) end
  e.selfCast = HC.bool(e.selfCast, false)
  e.enabled = HC.bool(e.enabled, true)
  return e
end

local function shooterProfile(p)
  p.autoTargetMode = HC.int(p.autoTargetMode, 1, HC.TARGET_MODES, 6)
  if p.rules ~= nil then p.rules = list(p.rules, HC.RULES_MAX, shooterRule) or {} end
  -- the old format, migrated by the helper on load
  if p.spells ~= nil then
    p.spells = list(p.spells, HC.ROWS_MAX, function(e)
      e.id = id(e.id)
      e.percent = HC.int(e.percent, 0, 100, 0)
      e.creatures = HC.int(e.creatures, 1, HC.CREATURES_MAX, 1)
      e.priority = HC.int(e.priority, 1, 20, 1)
      return e
    end) or {}
  end
  if p.runes ~= nil then
    p.runes = list(p.runes, HC.ROWS_MAX, function(e)
      e.id = id(e.id)
      e.creatures = HC.int(e.creatures, 1, HC.CREATURES_MAX, 1)
      e.priority = HC.int(e.priority, 1, 20, 1)
      return e
    end) or {}
  end
  return p
end

local RESOURCES = { 'hp%', 'mp%', 'hp', 'mp' }
local OPERATORS = { '<=', '>=', '<', '>' }

local function condValue(resource, v, default)
  if resource == 'hp' or resource == 'mp' then return HC.int(v, 0, HC.ABSOLUTE_MAX, default) end
  return HC.int(v, 0, 100, default)
end

local function equipRule(e)
  e.id = HC.int(e.id, 0, HC.ID_MAX, nil)
  e.itemId = id(e.itemId)
  e.cond1Resource = HC.oneOf(e.cond1Resource, RESOURCES, 'hp%')
  e.cond1Operator = HC.oneOf(e.cond1Operator, OPERATORS, '<=')
  e.cond1Value = condValue(e.cond1Resource, e.cond1Value, 50)
  e.condLogic = HC.oneOf(e.condLogic, { 'and', 'or' }, 'and')
  e.cond2Enabled = HC.bool(e.cond2Enabled, false)
  e.cond2Resource = HC.oneOf(e.cond2Resource, RESOURCES, 'mp%')
  e.cond2Operator = HC.oneOf(e.cond2Operator, OPERATORS, '>=')
  e.cond2Value = condValue(e.cond2Resource, e.cond2Value, 20)
  e.action = HC.oneOf(e.action, { 'equip', 'unequip' }, 'equip')
  e.enabled = HC.bool(e.enabled, true)
  if e.skipItemId ~= nil then e.skipItemId = id(e.skipItemId) end
  return e
end

local function timerRule(e)
  e.type = HC.oneOf(e.type, { 'words', 'item' }, nil)
  if e.type == nil then return nil end
  e.value = HC.text(e.value, HC.TEXT_MAX, '')
  if e.itemId ~= nil then e.itemId = id(e.itemId) end
  e.cooldown = HC.int(e.cooldown, 1, HC.COOLDOWN_MAX, 1)
  e.unit = HC.oneOf(e.unit, { 'sec', 'min', 'hr' }, 'min')
  e.forceDecrease = HC.bool(e.forceDecrease, false)
  e.inPz = HC.bool(e.inPz, false)
  e.inNonPz = HC.bool(e.inNonPz, false)
  e.targetingMonster = HC.bool(e.targetingMonster, false)
  e.enabled = HC.bool(e.enabled, true)
  return e
end

-- helper.json as decoded: checked in place and returned. Not a table: returned as it is (the reader refuses it).
function HC.sanitizeHelper(c)
  if type(c) ~= 'table' then return c end
  if c.spells ~= nil then c.spells = list(c.spells, HC.ROWS_MAX, healRow(80)) end
  if c.potions ~= nil then
    c.potions = list(c.potions, HC.ROWS_MAX, function(e)
      e.id = id(e.id)
      e.percent = HC.int(e.percent, 0, 100, 50)
      e.priority = HC.int(e.priority, 0, 2, 0)
      return e
    end)
  end
  if c.training ~= nil then
    c.training = list(c.training, HC.ROWS_MAX, function(e)
      e.id = id(e.id)
      e.percent = HC.int(e.percent, 0, 100, 0)
      e.enabled = HC.bool(e.enabled, false)
      return e
    end)
  end
  if c.haste ~= nil then
    c.haste = list(c.haste, HC.ROWS_MAX, function(e)
      e.id = id(e.id)
      e.enabled = HC.bool(e.enabled, false)
      e.safecast = HC.bool(e.safecast, false)
      e.onlyWalking = HC.bool(e.onlyWalking, false)
      return e
    end)
  end
  for _, key in ipairs(HC.DROPPED) do c[key] = nil end
  for key, fields in pairs(HC.DROPPED_FIELDS) do
    if type(c[key]) == 'table' then
      for _, f in ipairs(fields) do c[key][f] = nil end
    end
  end
  if type(c.staminaFood) == 'table' then
    local s = c.staminaFood
    s.id = id(s.id)
    s.enabled = HC.bool(s.enabled, false)
    s.thresholdMinutes = HC.int(s.thresholdMinutes, 0, HC.STAMINA_MAX, 30)
  elseif c.staminaFood ~= nil then
    c.staminaFood = nil
  end
  if type(c.specialFoods) == 'table' then
    for cat, default in pairs({ hp = 80, mana = 60 }) do
      if c.specialFoods[cat] ~= nil then
        c.specialFoods[cat] = list(c.specialFoods[cat], HC.SPECIAL_FOOD_SLOTS, function(e, i)
          e.id = id(e.id)
          e.enabled = HC.bool(e.enabled, false)
          e.percent = HC.int(e.percent, 1, 100, default)
          e.priority = HC.int(e.priority, 1, HC.SPECIAL_FOOD_SLOTS, i)
          return e
        end)
      end
    end
  elseif c.specialFoods ~= nil then
    c.specialFoods = nil
  end
  c.friendhealing = vocHealing(c.friendhealing)
  c.gransiohealing = vocHealing(c.gransiohealing)
  c.masreshealing = vocHealing(c.masreshealing)
  if type(c.namedSio) == 'table' then
    c.namedSio.percent = HC.int(c.namedSio.percent, 1, 99, 90)
    c.namedSio.enabled = HC.bool(c.namedSio.enabled, false)
    c.namedSio.name = HC.text(c.namedSio.name, HC.TEXT_MAX, '')
  elseif c.namedSio ~= nil then
    c.namedSio = nil
  end
  if c.autoTargetMode ~= nil then c.autoTargetMode = HC.int(c.autoTargetMode, 1, HC.TARGET_MODES, 6) end
  if c.currentLockedTargetId ~= nil then c.currentLockedTargetId = HC.int(c.currentLockedTargetId, 0, 2 ^ 31 - 1, 0) end
  if c.shooterProfiles ~= nil then c.shooterProfiles = profiles(c.shooterProfiles, shooterProfile) end
  if c.equipProfiles ~= nil then
    c.equipProfiles = profiles(c.equipProfiles, function(p)
      p.enabled = HC.bool(p.enabled, true)
      p.rules = list(p.rules, HC.RULES_MAX, equipRule) or {}
      return p
    end)
  end
  if type(c.timerConfig) == 'table' then
    local t = c.timerConfig
    t.rules = list(t.rules, HC.RULES_MAX, timerRule) or {}
    t.ruleCounter = HC.int(t.ruleCounter, 0, HC.ID_MAX, #t.rules)
  elseif c.timerConfig ~= nil then
    c.timerConfig = nil
  end
  for _, key in ipairs({ 'selectedShooterProfile', 'selectedEquipProfile', 'selectedSupplyProfile' }) do
    if c[key] ~= nil and type(c[key]) ~= 'string' then c[key] = nil end -- the helper falls back to "Default"
  end
  for _, key in ipairs({ 'ignoreMonsterList', 'priorityMonsterList', 'targetMonsterList' }) do
    if c[key] ~= nil and type(c[key]) ~= 'string' then c[key] = nil end
  end
  return c
end

-- ---------------------------------------------------------------- the overlay's g_settings nodes (config.otml)

-- Auto rotation (autorotation_ui.lua, node chaos_helper_spells): { autoUpdate = bool, ignored = { [spell id] = true } }
function HC.spellPrefs(entry)
  local out = { autoUpdate = false, ignored = {} }
  if type(entry) ~= 'table' then return out end
  out.autoUpdate = entry.autoUpdate == true or entry.autoUpdate == 'true'
  local n = 0
  if type(entry.ignored) == 'table' then
    local keys = {}
    for k, v in pairs(entry.ignored) do
      local sid = HC.int(k, 1, HC.ID_MAX, nil)
      if sid and sid == tonumber(k) and (v == true or v == 'true') then keys[#keys + 1] = sid end
    end
    table.sort(keys)
    for _, sid in ipairs(keys) do
      if n >= 500 then break end
      out.ignored[sid] = true
      n = n + 1
    end
  end
  return out
end

-- Auto setup (autosetup_ui.lua, node chaos_helper_autosetup): { timerWords = { words, ... } }
function HC.autosetupWords(entry)
  local out = {}
  if type(entry) ~= 'table' or type(entry.timerWords) ~= 'table' then return out end
  for _, w in ipairs(entry.timerWords) do
    if #out >= HC.WORDS_MAX then break end
    if type(w) == 'string' and w ~= '' then out[#out + 1] = w:sub(1, HC.TEXT_MAX) end
  end
  return out
end

-- the helper's reader cleans what it read (helpersave.lua HS.read)
if ChaosHelperSave then ChaosHelperSave.clean = HC.sanitizeHelper end

return HC
