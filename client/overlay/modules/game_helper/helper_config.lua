-- ChaosHelperCfg: the helper's saved settings (pure Lua: no engine calls; tests: helper_config_test.lua).
-- The config is the per-character helper.json of the helper (stable folder /characterdata/characters/<name>/helper.json,
-- read and written through ChaosHelperSave). Its shape:
--   spells    3 healing rows { id, percent }            potions   3 rows { id, percent, priority }
--   training  { { id, percent, enabled } }              haste     { { id, enabled, safecast } }
--   shooterProfiles[name] = { spells = 5 slots { id, percent, creatures, priority, forceCast, selfCast }, autoTargetMode }
--   selectedShooterProfile, autoTargetMode (1..8 = A..H, default 6 = F), autoEatFood, magicShooterEnabled,
--   autoTargetEnabled, helperAutomaticFunctionsEnabled, exercise { id, enabled }, botHud { enabled, size, show* }
-- A file written by the helper this one replaced (rules instead of slots, timers, equipment, ...) loads too: the shooter
-- rules become slots (at most 5 attack spells; the runes of that helper do not exist here), everything this helper does
-- not use stays in the file as it was, so nothing is lost on disk (C.migrate).
-- Every number is clamped and every wrong type falls back to its default (a hand-edited file cannot drive the casts out of
-- range); ChaosHelperConfig.sanitizeHelper (game_helperrotation) runs first when the file is read.
ChaosHelperCfg = ChaosHelperCfg or {}
local C = ChaosHelperCfg

C.VERSION = 1
C.SPELL_ROWS = 3
C.POTION_ROWS = 3
C.SHOOTER_SLOTS = 5
C.CREATURES_MAX = 8          -- the "N+" options of a slot
C.MODE_DEFAULT = 6           -- F: the closest monster, the lowest health first
C.MODE_MAX = 8
C.MODE_KEYS = { 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H' }
C.NAME_MAX = 12
C.PROFILES_MAX = 20
C.ID_MAX = 1000000
C.SLOT_PERCENT_MIN, C.SLOT_PERCENT_MAX = 0, 99
C.TRAINING_PERCENTS = { 50, 60, 70, 80, 90, 100 }
C.HUD_SIZES = { 'Compact', 'Normal', 'Wide' }
C.HUD_SECTIONS = { 'showTargeting', 'showHaste', 'showPlayer', 'showHealing' }

local function int(v, lo, hi, default)
  if type(v) == 'string' then v = tonumber(v) end
  if type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge then return default end
  v = math.floor(v)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end
C.int = int

local function bool(v, default)
  if type(v) == 'boolean' then return v end
  return default
end

local function copy(t)
  if type(t) ~= 'table' then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end
C.copy = copy

-- ---------------------------------------------------------------- defaults
function C.newSlot(priority)
  return { id = 0, percent = 0, creatures = 1, priority = priority or 1, forceCast = false, selfCast = false }
end

function C.newProfile()
  local spells = {}
  for i = 1, C.SHOOTER_SLOTS do spells[i] = C.newSlot(i) end
  return { spells = spells, autoTargetMode = C.MODE_DEFAULT }
end

function C.defaults()
  local spells, potions = {}, {}
  for i = 1, C.SPELL_ROWS do spells[i] = { id = 0, percent = 80 } end
  for i = 1, C.POTION_ROWS do potions[i] = { id = 0, percent = 50, priority = 0 } end
  return {
    version = C.VERSION,
    spells = spells,
    potions = potions,
    training = { { id = 0, percent = 100, enabled = false } },
    haste = { { id = 0, enabled = false, safecast = false } },
    exercise = { id = 0, enabled = false },
    shooterProfiles = { Default = C.newProfile() },
    selectedShooterProfile = 'Default',
    autoEatFood = false,
    magicShooterEnabled = false,
    autoTargetEnabled = false,
    autoTargetMode = C.MODE_DEFAULT,
    helperAutomaticFunctionsEnabled = true,
    botHud = { enabled = false, size = 'Normal', showTargeting = true, showHaste = true, showPlayer = true,
      showHealing = true },
  }
end

-- ---------------------------------------------------------------- rows
local function row(e, id, percent, default)
  if type(e) ~= 'table' then e = {} end
  e.id = int(e.id, 0, C.ID_MAX, 0)
  e.percent = int(e.percent, 0, 100, percent)
  for k, v in pairs(default or {}) do
    if e[k] == nil then e[k] = v end
  end
  return e
end

local function rowsOf(list, n, make)
  local out = {}
  if type(list) ~= 'table' then list = {} end
  for i = 1, n do out[i] = make(list[i]) end
  return out
end

local function slot(e, i)
  if type(e) ~= 'table' then e = {} end
  local out = C.newSlot(i)
  for k, v in pairs(e) do out[k] = v end
  out.id = int(e.id, 0, C.ID_MAX, 0)
  out.percent = int(e.percent, C.SLOT_PERCENT_MIN, C.SLOT_PERCENT_MAX, 0)
  out.creatures = int(e.creatures, 1, C.CREATURES_MAX, 1)
  out.priority = int(e.priority, 1, C.SHOOTER_SLOTS * 2, i)
  out.forceCast = bool(e.forceCast, false)
  out.selfCast = bool(e.selfCast, false)
  return out
end

-- ---------------------------------------------------------------- rules <-> slots (Auto rotation, Auto setup)
-- The Auto rotation module (game_helperrotation) speaks in rules: { type = 'spell', spellId, creatures, manaPercent,
-- selfCast, forceOnTarget, ... } in priority order. The shooter has five slots.
-- lookup(id) -> { name, words } (optional).
function C.slotsToRules(slots, lookup)
  local out = {}
  local list = {}
  for i, s in ipairs(slots or {}) do
    if (tonumber(s.id) or 0) > 0 then list[#list + 1] = { s = s, i = i } end
  end
  table.sort(list, function(a, b)
    local pa, pb = tonumber(a.s.priority) or a.i, tonumber(b.s.priority) or b.i
    if pa ~= pb then return pa < pb end
    return a.i < b.i
  end)
  for _, e in ipairs(list) do
    local s = e.s
    local info = lookup and lookup(s.id) or nil
    out[#out + 1] = {
      type = 'spell', spellId = s.id, itemId = 0, name = info and info.name or tostring(s.id),
      words = info and info.words or '', manaPercent = tonumber(s.percent) or 0, healthPercent = 0, extraDelay = 0,
      creatures = tonumber(s.creatures) or 1, harmonyThreshold = 0, selfCast = s.selfCast == true,
      castIfTrapped = false, countLowerThan = false, extendedArea = false, extendedArea2 = false,
      forceOnTarget = s.forceCast == true, rangedMonsterNames = '', hpMin = 0, hpMax = 0, enabled = true,
    }
  end
  return out
end

-- rules -> the five slots (priority = the order). Returns the slots and how many rules did not fit (runes, disabled
-- rules and rules past the fifth are not carried).
function C.rulesToSlots(rules)
  local slots, dropped = {}, 0
  for _, r in ipairs(rules or {}) do
    local ok = type(r) == 'table' and r.type == 'spell' and (tonumber(r.spellId) or 0) > 0 and r.enabled ~= false
    if ok and #slots < C.SHOOTER_SLOTS then
      slots[#slots + 1] = slot({ id = r.spellId, percent = r.manaPercent, creatures = r.creatures,
        forceCast = r.forceOnTarget, selfCast = r.selfCast }, #slots + 1)
    else
      dropped = dropped + 1
    end
  end
  for i = #slots + 1, C.SHOOTER_SLOTS do slots[i] = C.newSlot(i) end
  return slots, dropped
end

-- A shooter profile seen as { rules = ..., <marker> = ... } (the form autorotation_ui.lua works with): reading `rules`
-- gives the slots as rules, writing `rules` sets the slots; any other key is the profile's own (the Auto rotation marker).
function C.rotationView(profile, lookup)
  return setmetatable({}, {
    __index = function(_, k)
      if k == 'rules' then return C.slotsToRules(profile.spells, lookup) end
      return profile[k]
    end,
    __newindex = function(_, k, v)
      if k == 'rules' then
        profile.spells = (C.rulesToSlots(v))
      else
        profile[k] = v
      end
    end,
  })
end

-- ---------------------------------------------------------------- preset names
-- ok, reason (a tr key) for a new name; `exists(name)` tells a name in use
function C.nameProblem(name, exists)
  if type(name) ~= 'string' or name == '' then return 'The name cannot be empty.' end
  if #name > C.NAME_MAX then return 'The name cannot be longer than 12 characters.' end
  if name:find('[^%w _%-]') then return 'The name can only have letters, digits, spaces, - and _.' end
  if exists and exists(name) then return 'There is already a preset with this name.' end
  return nil
end

function C.profileCount(cfg)
  local n = 0
  for _ in pairs(cfg.shooterProfiles or {}) do n = n + 1 end
  return n
end

-- the preset names in a fixed order (alphabetical), for the combo box and the hotkey that cycles them
function C.profileNames(cfg)
  local names = {}
  for name in pairs(cfg.shooterProfiles or {}) do names[#names + 1] = name end
  table.sort(names)
  return names
end

-- the preset after `current` in that order
function C.nextProfile(cfg, current)
  local names = C.profileNames(cfg)
  if #names == 0 then return nil end
  for i, name in ipairs(names) do
    if name == current then return names[i % #names + 1] end
  end
  return names[1]
end

-- ---------------------------------------------------------------- sanitize / migrate
local function profile(p)
  if type(p) ~= 'table' then return C.newProfile() end
  -- the former helper kept rules: carry the spell rules into the slots (once), keep the original list aside
  if type(p.rules) == 'table' and not p.spellsFromRules and not C.isSlotList(p.spells) then
    local slots = C.rulesToSlots(p.rules)
    p.legacyRules = p.legacyRules or p.rules
    p.spells = slots
    p.spellsFromRules = true
  end
  p.rules = nil
  p.runes = nil
  p.spells = rowsOf(p.spells, C.SHOOTER_SLOTS, function(e) return e end)
  for i = 1, C.SHOOTER_SLOTS do p.spells[i] = slot(p.spells[i], i) end
  p.autoTargetMode = int(p.autoTargetMode, 1, C.MODE_MAX, C.MODE_DEFAULT)
  return p
end

-- a list that already is the slot form (entries with id / percent, no spellId)
function C.isSlotList(list)
  if type(list) ~= 'table' or #list == 0 then return false end
  for _, e in ipairs(list) do
    if type(e) ~= 'table' or e.spellId ~= nil then return false end
  end
  return true
end

local function hud(h)
  local d = C.defaults().botHud
  if type(h) ~= 'table' then return d end
  h.enabled = bool(h.enabled, false)
  local size = h.size
  local ok = false
  for _, s in ipairs(C.HUD_SIZES) do if s == size then ok = true end end
  h.size = ok and size or d.size
  for _, k in ipairs(C.HUD_SECTIONS) do h[k] = bool(h[k], true) end
  -- the sections of the former HUD this helper has no rows for
  h.showEquipment, h.showTimers, h.showAutomation, h.showCavebot, h.showWaypoints = nil, nil, nil, nil, nil
  return h
end

-- the config as decoded (any age): fixed in place and returned. Not a table: the defaults.
function C.sanitize(c)
  if type(c) ~= 'table' then return C.defaults() end
  local d = C.defaults()
  c.version = C.VERSION
  c.spells = rowsOf(c.spells, C.SPELL_ROWS, function(e) return row(e, 0, 80) end)
  for _, e in ipairs(c.spells) do
    if e.percent == 0 then e.percent = 80 end
  end
  c.potions = rowsOf(c.potions, C.POTION_ROWS, function(e)
    local r = row(e, 0, 50)
    if r.percent == 0 then r.percent = 50 end
    r.priority = int(r.priority, 0, 2, 0)
    return r
  end)
  c.training = rowsOf(c.training, 1, function(e)
    local r = row(e, 0, 100)
    r.enabled = bool(r.enabled, false)
    if r.percent == 0 then r.percent = 100 end
    return r
  end)
  c.haste = rowsOf(c.haste, 1, function(e)
    local r = row(e, 0, 0)
    r.enabled = bool(r.enabled, false)
    r.safecast = bool(r.safecast, false)
    return r
  end)
  if type(c.exercise) ~= 'table' then c.exercise = d.exercise end
  c.exercise.id = int(c.exercise.id, 0, C.ID_MAX, 0)
  c.exercise.enabled = bool(c.exercise.enabled, false)
  -- the profiles
  local profiles, n = {}, 0
  if type(c.shooterProfiles) == 'table' then
    local names = {}
    for name, p in pairs(c.shooterProfiles) do
      if type(name) == 'string' and name ~= '' and #name <= 64 and type(p) == 'table' then names[#names + 1] = name end
    end
    table.sort(names)
    for _, name in ipairs(names) do
      if n >= C.PROFILES_MAX then break end
      profiles[name] = profile(c.shooterProfiles[name])
      n = n + 1
    end
  end
  if n == 0 then profiles = d.shooterProfiles end
  c.shooterProfiles = profiles
  if type(c.selectedShooterProfile) ~= 'string' or not profiles[c.selectedShooterProfile] then
    c.selectedShooterProfile = profiles.Default and 'Default' or C.profileNames(c)[1]
  end
  c.autoTargetMode = int(c.autoTargetMode, 1, C.MODE_MAX, C.MODE_DEFAULT)
  c.autoEatFood = bool(c.autoEatFood, false)
  c.magicShooterEnabled = bool(c.magicShooterEnabled, false)
  c.autoTargetEnabled = bool(c.autoTargetEnabled, false)
  c.helperAutomaticFunctionsEnabled = bool(c.helperAutomaticFunctionsEnabled, true)
  c.currentLockedTargetId = 0 -- runtime only
  c.magicShooterOnHold = nil
  c.botHud = hud(c.botHud)
  return c
end

-- the words of the former helper's timer rules (type 'words', enabled) that Auto setup did not write: the player's own
-- timed casts. helper.lua turns them into Support spells once (C.timersMigrated marks it done).
function C.timerWords(c)
  local out, seen = {}, {}
  local t = type(c) == 'table' and c.timerConfig
  if type(t) ~= 'table' or type(t.rules) ~= 'table' then return out end
  for _, r in ipairs(t.rules) do
    if type(r) == 'table' and r.type == 'words' and r.enabled ~= false and type(r.value) == 'string' and r.value ~= '' then
      local w = r.value:lower()
      if not seen[w] then
        seen[w] = true
        out[#out + 1] = w
      end
    end
  end
  return out
end

function C.timersMigrated(c)
  return type(c) == 'table' and c.migrated ~= nil and c.migrated.timers == true
end

function C.markTimersMigrated(c)
  if type(c.migrated) ~= 'table' then c.migrated = {} end
  c.migrated.timers = true
end

return ChaosHelperCfg
