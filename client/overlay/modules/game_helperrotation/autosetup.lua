-- ChaosAutoSetup: what the helper's "Auto setup" button sets for a class and level (pure; autosetup_test.lua).
-- Healing: the class heals (ChaosAutoRotation.heals) at 80 % (one heal), 60 / 80 or 50 / 65 / 80 (the strongest at
-- the lowest health); the best health potion at 50 % and the best mana potion at 40 % (casters: Mystic and
-- Necromancer lines) or 30 %. A potion counts when the class may drink it at its level (docs/CLASSES.md, "Item, spell
-- and potion lists") and the character carries it; without one the Everfull potion's look (the Health / Mana Potion,
-- every character has one) is taken. Tools: eat food on (the Everfull Ration counts) and the best haste it can cast,
-- kept up. Shooter: the class rotation (ChaosAutoRotation.select). Timers: the class's fight buffs on their
-- cooldown, only out of protection zones and while attacking a monster (up to ChaosHelperSupport.TIMER_MAX, from the
-- spell data: game_helpersupport/supportspells.lua; the hand-written S.BUFFS only when that module is missing).
-- Support spells: the rest of the class's support spells (shields, summons, a vigil ...) for the helper's Support spells
-- section, cast whenever they are off cooldown (ChaosHelperSupport.autoPlan, the same module).
-- Targeting (owner 2026-10-22): every monster ("*"), Auto Target and the shooter on, Always Chase Opponent and Follow
-- Friend off, both paused in protection zones (S.TARGETING; the fields of the helper's own config).
-- Spells always pass the caller's canCast (class, level, learned: autorotation_ui.lua's canCastFor).
ChaosAutoSetup = ChaosAutoSetup or {}
local S = ChaosAutoSetup

-- class lines by server vocation id (docs/CLASSES.md)
S.LINES = {
  [4] = 'warrior', [8] = 'warrior', [14] = 'warrior',
  [3] = 'ranger', [7] = 'ranger', [15] = 'ranger',
  [1] = 'mystic', [5] = 'mystic', [10] = 'mystic',
  [11] = 'thief', [12] = 'thief', [13] = 'thief',
  [17] = 'monk', [18] = 'monk', [19] = 'monk',
  [20] = 'necro', [21] = 'necro', [22] = 'necro',
  [23] = 'templar', [24] = 'templar', [25] = 'templar',
}
S.CASTERS = { mystic = true, necro = true }

function S.lineOf(vocId)
  return S.LINES[tonumber(vocId) or -1]
end

-- potions by client item id: the server's potions.lua lists (knight: Warrior line and Templar; paladin: Ranger,
-- Thief, Monk and Templar lines; sorcerer / druid: Mystic and Necromancer lines; the mana potions: both), strongest first per kind.
-- 266 / 268: the Health / Mana Potion; a row on one follows the Everfull flask the character carries (S.EVERFULL).
local ANY = nil -- every class drinks every potion (owner 2026-10-24); only the level gates stay
S.POTIONS = {
  health = {
    { id = 23375, level = 200, lines = ANY },  -- Supreme Health Potion
    { id = 23374, level = 130, lines = ANY }, -- Ultimate Spirit Potion (health and mana)
    { id = 7643, level = 130, lines = ANY },   -- Ultimate Health Potion
    { id = 7642, level = 80, lines = ANY },   -- Great Spirit Potion
    { id = 239, level = 80, lines = ANY },     -- Great Health Potion
    { id = 236, level = 50, lines = ANY },
    { id = 266, level = 1, lines = ANY },         -- Health Potion (a plain Everfull flask follows it)
    { id = 7876, level = 1, lines = ANY },        -- Small Health Potion
  },
  mana = {
    { id = 23373, level = 130, lines = ANY },    -- Ultimate Mana Potion
    { id = 238, level = 80, lines = ANY },       -- Great Mana Potion
    { id = 237, level = 50, lines = ANY },       -- Strong Mana Potion
    { id = 268, level = 1, lines = ANY },         -- Mana Potion (a plain Everfull flask follows it)
  },
}
S.EVERFULL = { health = 266, mana = 268 }
S.HEALTH_POTION_PERCENT = 50
S.MANA_POTION_PERCENT = { caster = 40, other = 30 }

function S.canDrink(potion, line, level)
  return (tonumber(level) or 0) >= potion.level and (potion.lines == nil or potion.lines[line] == true)
end

-- the best potion of a kind the character may drink and carries (has(id) -> true), else the Everfull's look. held: the
-- Everfull the server says the character carries (ChaosEverfullHeld.get()): it counts as carried (it lives in a closed
-- backpack as often as not), ranked as the stock potion it is as good as (ChaosHelperPotions.EVERFULL_ITEMS `rank`: the great
-- Everfull health potion as the Great Health Potion, the supreme mana potion as the Ultimate Mana Potion, the spirit potion of
-- tier 1 as the Health Potion), at its own level; a spirit flask counts for the health kind, as the stock spirit potions of
-- the list do. What is returned for a flask it wins with: the Health / Mana Potion look when the flask is a plain health or
-- mana one (S.EVERFULL: that row follows the flask through every upgrade, helper_potions.lua P.resolve), else its own look.
local function heldRank(h)
  local HP = ChaosHelperPotions
  local e = HP and h and h.look and HP.everfullOf and HP.everfullOf(h.look)
  return (e and e.rank) or (h and h.look)
end

function S.potion(kind, vocId, level, has, held)
  local line = S.lineOf(vocId)
  local carried = {} -- rank (a stock look of the list) -> the held flask of it, at the character's level
  for _, slot in ipairs({ 'health', 'mana' }) do
    local h = held and held[slot]
    if h and h.look and (tonumber(level) or 0) >= (tonumber(h.level) or 0) then carried[heldRank(h)] = h end
  end
  for _, p in ipairs(S.POTIONS[kind] or {}) do
    local h = carried[p.id]
    if h then
      return h.line == kind and S.EVERFULL[kind] or h.look
    end
    if S.canDrink(p, line, level) and has and has(p.id) then return p.id end
  end
  return S.EVERFULL[kind]
end

S.HEAL_PERCENTS = { { 80 }, { 60, 80 }, { 50, 65, 80 } }

-- heals: ChaosAutoRotation.heals' list (strongest first) -> {id, percent}, the strongest at the lowest health
function S.healSlots(heals)
  local n = math.min(#(heals or {}), 3)
  local out = {}
  for i = 1, n do out[i] = { id = heals[i].id, percent = S.HEAL_PERCENTS[n][i] } end
  return out
end

-- haste kept up: Haste (utani hur, Fleetfoot). Strong Haste (Galeborne Stride) is retired. Wildstride (12 s of 30, on top of Haste) and
-- Charge (a 5 s dash) are left out.
S.HASTES = { 6 }

function S.haste(canCast)
  for _, id in ipairs(S.HASTES) do
    if canCast and canCast(id) then return id end
  end
  return nil
end

-- timer buffs: self buffs worth keeping up in a fight (server/data/spells/README.md). Spells that cost health
-- (Crimson Covenant, Bloodrage), need a shield or minions (Aegis of Faith, Banner of Bones) or call a summon are not.
-- cooldown: the spell's in seconds; the timer waits one more.
S.BUFFS = {
  warrior = { { id = 222, words = 'vyr ira cruor', cooldown = 40 } },                 -- Red Frenzy
  ranger = { { id = 217, words = 'tor sol ghar', cooldown = 30 },                      -- Lightward
    { id = 233, words = 'tor vas vant', cooldown = 35 } },                             -- Banner Call
  mystic = { { id = 209, words = 'tor ael skar', cooldown = 25 },                      -- Ironbark Hide
    { id = 233, words = 'tor vas vant', cooldown = 35 } },
  thief = { { id = 239, words = 'vyr vex thyss', cooldown = 30 },                      -- Poison Blades
    { id = 245, words = 'vyr mynd', cooldown = 30 },                                   -- Bushido Focus (Samurai)
    { id = 233, words = 'tor vas vant', cooldown = 35 } },
  monk = { { id = 72, words = 'tor vas qhal', cooldown = 30 },                         -- Mantra of Stone (Iron Sage)
    { id = 233, words = 'tor vas vant', cooldown = 35 } },
  necro = { { id = 233, words = 'tor vas vant', cooldown = 35 } },
  templar = { { id = 250, words = 'vyr sol zel', cooldown = 30 },                      -- Zealotry (Inquisitor)
    { id = 233, words = 'tor vas vant', cooldown = 35 } },
}

local function timerRule(id, words, cooldownSec)
  return { type = 'words', value = words, cooldown = cooldownSec, unit = 'sec',
    forceDecrease = false, inPz = false, inNonPz = true, targetingMonster = true, chaosAutoSetup = id }
end

-- the timer rules (the helper's _Helper.Timer rule data) for the buffs the character can cast. support: the result of
-- ChaosHelperSupport.autoPlan (its timer list); without it the class list S.BUFFS
function S.timerRules(vocId, canCast, support)
  local out = {}
  if support then
    for _, r in ipairs(support.timer or {}) do
      out[#out + 1] = timerRule(r.id, r.words, r.cooldown)
    end
    return out
  end
  for _, b in ipairs(S.BUFFS[S.lineOf(vocId)] or {}) do
    if canCast and canCast(b.id) then
      out[#out + 1] = timerRule(b.id, b.words, b.cooldown + 1)
    end
  end
  return out
end

-- the Combat tab's targeting, as the helper's config fields (the helper's defaults have both systems off)
S.TARGETING = { autoTargetEnabled = true, magicShooterEnabled = true }
S.TARGETING_KEYS = { 'autoTargetEnabled', 'magicShooterEnabled' }

function S.targeting()
  local out = {}
  for k, v in pairs(S.TARGETING) do out[k] = v end
  return out
end

-- writes a targeting (S.targeting() or a snapshot from S.targetingOf) into the helper's config
function S.applyTargeting(cfg, t)
  if type(cfg) ~= 'table' or type(t) ~= 'table' then return cfg end
  for _, k in ipairs(S.TARGETING_KEYS) do cfg[k] = t[k] end
  return cfg
end

-- the config's current targeting (for Undo)
function S.targetingOf(cfg)
  local out = {}
  if type(cfg) ~= 'table' then return out end
  for _, k in ipairs(S.TARGETING_KEYS) do out[k] = cfg[k] end
  return out
end

-- the whole plan. p: vocId, level, canCast(id), has(clientId), held (ChaosEverfullHeld.get()), heals (ChaosAutoRotation.heals), rotation
-- (ChaosAutoRotation.select's result or nil), support (ChaosHelperSupport.autoPlan's result or nil)
function S.plan(p)
  local line = S.lineOf(p.vocId)
  local manaPercent = S.CASTERS[line] and S.MANA_POTION_PERCENT.caster or S.MANA_POTION_PERCENT.other
  return {
    line = line,
    healing = {
      spells = S.healSlots(p.heals),
      potions = {
        { id = S.potion('health', p.vocId, p.level, p.has, p.held), percent = S.HEALTH_POTION_PERCENT },
        { id = S.potion('mana', p.vocId, p.level, p.has, p.held), percent = manaPercent },
      },
    },
    tools = { autoEatFood = true, haste = S.haste(p.canCast) },
    rotation = p.rotation,
    targeting = S.targeting(),
    timers = S.timerRules(p.vocId, p.canCast, p.support),
    support = p.support and p.support.support or {},
  }
end

-- ---------------------------------------------------------------- the player's own settings
local function filled(slots)
  for _, s in ipairs(slots or {}) do
    if (tonumber(s.id) or 0) ~= 0 then return true end
  end
  return false
end

-- the tabs where the player has set something of their own that the plan would change. cur: { spells, potions
-- (helperConfig slots), haste (helperConfig.haste[1].id), rotationCustom (ChaosAutoRotation.isCustom), timers (rule
-- list), support (the Support spells rows, { {id = n}, ... }) }. A timer rule Auto setup wrote (chaosAutoSetup) is not
-- the player's; a support row is the player's unless its spell is one of the plan's.
function S.ownTabs(cur, plan)
  local tabs = {}
  if filled(cur.spells) or filled(cur.potions) then tabs[#tabs + 1] = 'healing' end
  local haste = tonumber(cur.haste) or 0
  if haste ~= 0 and plan.tools.haste and haste ~= plan.tools.haste then tabs[#tabs + 1] = 'tools' end
  if cur.rotationCustom and plan.rotation then tabs[#tabs + 1] = 'shooter' end
  for _, r in ipairs(cur.timers or {}) do
    if not r.chaosAutoSetup then tabs[#tabs + 1] = 'timers' break end
  end
  local planned = {}
  for _, id in ipairs(plan.support or {}) do planned[id] = true end
  for _, row in ipairs(cur.support or {}) do
    if not planned[row.id] then tabs[#tabs + 1] = 'support' break end
  end
  return tabs
end

-- healing slots after the plan. mode 'replace': the plan's, the rest emptied; 'add': the player's slots stay, the
-- plan's go into the empty ones (an id already there is not added twice)
function S.mergeSlots(current, planned, mode, size)
  size = size or 3
  local out = {}
  for i = 1, size do
    local c = current and current[i] or {}
    out[i] = { id = tonumber(c.id) or 0, percent = tonumber(c.percent) or 0 }
  end
  if mode == 'replace' then
    for i = 1, size do
      local p = planned[i]
      out[i] = { id = p and p.id or 0, percent = p and p.percent or out[i].percent }
    end
    return out
  end
  local have = {}
  for i = 1, size do if out[i].id ~= 0 then have[out[i].id] = true end end
  local slot = 1
  for _, p in ipairs(planned or {}) do
    if not have[p.id] then
      while slot <= size and out[slot].id ~= 0 do slot = slot + 1 end
      if slot > size then break end
      out[slot] = { id = p.id, percent = p.percent }
      have[p.id] = true
    end
  end
  return out
end

-- timer rules after the plan: 'replace' drops the player's and earlier Auto setup rules; 'add' keeps the player's and
-- adds the planned ones whose words are not there yet (earlier Auto setup rules are replaced either way)
function S.mergeTimers(current, planned, mode)
  local out, words = {}, {}
  if mode ~= 'replace' then
    for _, r in ipairs(current or {}) do
      if not r.chaosAutoSetup then
        out[#out + 1] = r
        if r.type == 'words' then words[tostring(r.value):lower()] = true end
      end
    end
  end
  for _, r in ipairs(planned or {}) do
    if not words[r.value:lower()] then out[#out + 1] = r end
  end
  return out
end

-- the haste after the plan ('add' keeps the player's own)
function S.mergeHaste(current, planned, mode)
  current = tonumber(current) or 0
  if mode == 'add' and current ~= 0 then return current end
  return planned or current
end

return ChaosAutoSetup
