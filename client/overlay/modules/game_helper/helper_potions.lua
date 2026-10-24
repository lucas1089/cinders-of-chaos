-- ChaosHelperPotions: the potions the helper drinks and when (pure Lua: no engine calls; tests: helper_potions_test.lua).
-- The potions of the server (server/data/scripts/chaos/potions_config.lua, potions.lua; client/MANIFEST.md "Helper"):
--   * the Everfull Health and Mana Potions (server ids 32085 and 32086, one per character, never used up). The client sees
--     them under the look of the stock Health Potion (266) and Mana Potion (268), so those are the ids the helper uses;
--   * the stock potions the NPCs sell (strong, great, ultimate, supreme, spirit), each with its level. Every class drinks
--     every potion (owner 2026-10-24, server/tools/patch_open_potions.py), so the dropdown offers all of them to everyone;
--     the server still refuses a potion below its level. Tested against the Apothecary's table (helper_potions_test.lua).
-- A potion heals a fixed roll plus a percent of the drinker's maximum health or mana (potions_config.lua amount: base 3 %,
-- +0.01 % per level the potion needs, at most 10 %), so the rows show what a potion gives at the current maximum.
-- Which potion goes out: the health potions first (a health potion due holds the mana potions back), in the order of the
-- row's percent (the lowest threshold first), then the mana potions; one potion per tick, and only when its cooldown channel
-- (the server's potion channel, ChaosHelperTimers 'potion') and the potion gate (ChaosPotionGate, a potion in a closed
-- backpack) allow it. Runes do not exist here: the NPCs sell them and the helper does not use them.
ChaosHelperPotions = ChaosHelperPotions or {}
local P = ChaosHelperPotions

P.EVERFULL = { health = 266, mana = 268 }             -- the client looks of the server items 32085 and 32086
P.EVERFULL_SERVER = { health = 32085, mana = 32086 }

-- the potions_config.lua numbers of the Everfull flasks (the fixed rolls) and the percent formula
P.ROLL = { [266] = { 125, 175 }, [268] = { 75, 125 } }
P.PERCENT = { base = 3, perLevel = 0.01, cap = 10 }

-- Every class drinks every potion (owner 2026-10-24; server/tools/patch_open_potions.py); only the level gates stay.
-- id: the 10.98 client id; server: the item id of the server (apothecary_config.lua, tested against it)
-- kind: 'health' | 'mana' | 'both' (the spirit potions give both; the row's priority says which one it is for)
P.LIST = {
  { id = 23375, server = 26031, kind = 'health', name = 'Supreme Health Potion', level = 200 },
  { id = 23374, server = 26030, kind = 'both', name = 'Ultimate Spirit Potion', level = 130 },
  { id = 7643, server = 8473, kind = 'health', name = 'Ultimate Health Potion', level = 130 },
  { id = 7642, server = 8472, kind = 'both', name = 'Great Spirit Potion', level = 80 },
  { id = 239, server = 7591, kind = 'health', name = 'Great Health Potion', level = 80 },
  { id = 236, server = 7588, kind = 'health', name = 'Strong Health Potion', level = 50 },
  { id = 266, server = 7618, kind = 'health', name = 'Health Potion', level = 1 },
  { id = 7876, server = 8704, kind = 'health', name = 'Small Health Potion', level = 1 },
  { id = 23373, server = 26029, kind = 'mana', name = 'Ultimate Mana Potion', level = 130 },
  { id = 238, server = 7590, kind = 'mana', name = 'Great Mana Potion', level = 80 },
  { id = 237, server = 7589, kind = 'mana', name = 'Strong Mana Potion', level = 50 },
  { id = 268, server = 7620, kind = 'mana', name = 'Mana Potion', level = 1 },
}

local byId = {}
for _, p in ipairs(P.LIST) do byId[p.id] = p end

function P.info(id)
  return byId[tonumber(id) or -1]
end

function P.isPotion(id)
  return byId[tonumber(id) or -1] ~= nil
end

function P.isHealth(id)
  local p = byId[tonumber(id) or -1]
  return p ~= nil and p.kind == 'health'
end

function P.isMana(id)
  local p = byId[tonumber(id) or -1]
  return p ~= nil and p.kind == 'mana'
end

function P.isBoth(id)
  local p = byId[tonumber(id) or -1]
  return p ~= nil and p.kind == 'both'
end

-- What a row heals: the kind the row's potion works for. A spirit potion follows the row's priority (1 health, 2 mana;
-- unset: health). Returns 'health', 'mana' or nil (an unknown item).
function P.rowKind(row)
  local p = row and byId[tonumber(row.id) or -1]
  if not p then return nil end
  if p.kind == 'both' then
    return (tonumber(row.priority) == 2) and 'mana' or 'health'
  end
  return p.kind
end

-- the percent of the maximum a potion that needs `level` heals
function P.percentOf(level)
  local pc = P.PERCENT
  local v = pc.base + pc.perLevel * (tonumber(level) or 0)
  if v > pc.cap then v = pc.cap end
  return v
end

-- about what one potion gives at a maximum (health or mana): the fixed roll (the Everfull flasks; the others have their own
-- roll on the server) plus the percent. nil for an unknown item.
function P.expected(id, maxValue)
  local p = byId[tonumber(id) or -1]
  if not p then return nil end
  local roll = P.ROLL[p.id]
  local fixed = roll and (roll[1] + roll[2]) / 2 or 0
  return math.floor(fixed + (tonumber(maxValue) or 0) * P.percentOf(p.level) / 100 + 0.5)
end

-- may the character drink the potion at this level (the Everfull flasks: everyone; no class limits any more)
function P.canDrink(potion, line, level)
  if type(potion) == 'number' then potion = byId[potion] end
  if not potion then return false end
  return (tonumber(level) or 0) >= potion.level
end

-- every potion of the list, strongest first as in P.LIST (the class line and the level are not asked: see the header)
function P.offered()
  local out = {}
  for _, p in ipairs(P.LIST) do out[#out + 1] = p end
  return out
end

-- The dropdown of the potion rows (the same for every class and level): the health potions, then the mana potions, then the spirit
-- potions (one entry for health and one for mana each), the strongest first in each group. Returns { { name, key, kind } }
-- where key is what the row stores (see helper.lua potionKey: the id, or id:1 / id:2 for a spirit potion's health / mana).
function P.options()
  local groups = { health = {}, mana = {}, both = {} }
  for i, p in ipairs(P.offered()) do
    local g = groups[p.kind]
    g[#g + 1] = { potion = p, index = i }
  end
  local out = {}
  for _, kind in ipairs({ 'health', 'mana', 'both' }) do
    local g = groups[kind]
    table.sort(g, function(a, b)
      if a.potion.level ~= b.potion.level then return a.potion.level > b.potion.level end
      return a.index < b.index
    end)
    for _, e in ipairs(g) do
      local p = e.potion
      if kind == 'both' then
        out[#out + 1] = { potion = p, name = p.name, key = p.id .. ':1', kind = 'health' }
        out[#out + 1] = { potion = p, name = p.name, key = p.id .. ':2', kind = 'mana' }
      else
        out[#out + 1] = { potion = p, name = p.name, key = tostring(p.id), kind = kind }
      end
    end
  end
  return out
end

-- The rows due now. rows: the healing tab's potion rows ({ id, percent, priority }); ctx = { healthPct, manaPct,
-- available(id) -> true when the potion can be used (carried or probed, and its channel is ready) }.
-- Returns the due rows of a kind sorted by the lowest threshold first, then the priority.
local function due(rows, kind, pct, available)
  local list = {}
  for i, row in ipairs(rows or {}) do
    local id = tonumber(row.id) or 0
    if id > 0 and P.rowKind(row) == kind and pct <= (tonumber(row.percent) or 0) and (not available or available(id)) then
      list[#list + 1] = { id = id, percent = tonumber(row.percent) or 0, priority = tonumber(row.priority) or 0, index = i }
    end
  end
  table.sort(list, function(a, b)
    if a.percent ~= b.percent then return a.percent < b.percent end
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.index < b.index
  end)
  return list
end
P.due = due

-- the potion to drink now, or nil: health before mana. Returns the item id and 'health' | 'mana'.
function P.pick(rows, ctx)
  local health = due(rows, 'health', tonumber(ctx.healthPct) or 100, ctx.available)
  if health[1] then return health[1].id, 'health' end
  local mana = due(rows, 'mana', tonumber(ctx.manaPct) or 100, ctx.available)
  if mana[1] then return mana[1].id, 'mana' end
  return nil
end

-- is a health potion row due by the numbers alone (its potion may not be at hand)? The mana potions wait for it: one
-- health potion in need must not be passed over for a mana one (the former helper's "health potion priority")
function P.healthDue(rows, healthPct)
  return due(rows, 'health', tonumber(healthPct) or 100, nil)[1] ~= nil
end

return ChaosHelperPotions
