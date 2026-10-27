-- ChaosHelperPotions: the potions the helper drinks and when (pure Lua: no engine calls; tests: helper_potions_test.lua).
-- The potions of the server (server/data/scripts/chaos/potions_config.lua, potions.lua; client/MANIFEST.md "Helper"):
--   * the Everfull potions (health, mana and spirit, four tiers each, one per slot and character, never used up), each with a
--     look of its own (pair 44); a row on the stock Health / Mana Potion look (266 / 268) follows the carried one;
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

-- The Everfull potions, ONE table (server/data/scripts/chaos/potions_config.lua `everfull`; tested against it). Each has a
-- look of its own since pair 44 (client items 38645-38656, client/MANIFEST.md "Everfull potion looks"): a row on that look is
-- exactly one server item, and the dropdown lists them. slot: the flask the item takes (health | mana); line: health | mana |
-- spirit; kind: what a row of it heals (health | mana | both: the spirit flasks); level: the level it needs; rank: the look of
-- the stock potion it is as good as (Auto setup's order, autosetup.lua); roll / rollMana: the fixed part of a drink (a spirit
-- flask gives both). The server drinks it at the use of its look and checks the level itself.
P.EVERFULL_ITEMS = {
  { server = 32085, look = 38645, rank = 266,   slot = 'health', line = 'health', kind = 'health', tier = 1, level = 0,   name = 'Everfull Health Potion',          roll = { 125, 175 } },
  { server = 32261, look = 38646, rank = 239,   slot = 'health', line = 'health', kind = 'health', tier = 2, level = 80,  name = 'Everfull Great Health Potion',    roll = { 425, 575 } },
  { server = 32264, look = 38647, rank = 7643,  slot = 'health', line = 'health', kind = 'health', tier = 3, level = 130, name = 'Everfull Ultimate Health Potion', roll = { 650, 850 } },
  { server = 32267, look = 38648, rank = 23375, slot = 'health', line = 'health', kind = 'health', tier = 4, level = 200, name = 'Everfull Supreme Health Potion',  roll = { 875, 1125 } },
  { server = 32086, look = 38649, rank = 268,   slot = 'mana',   line = 'mana',   kind = 'mana',   tier = 1, level = 0,   name = 'Everfull Mana Potion',            roll = { 75, 125 } },
  { server = 32262, look = 38650, rank = 238,   slot = 'mana',   line = 'mana',   kind = 'mana',   tier = 2, level = 80,  name = 'Everfull Great Mana Potion',      roll = { 150, 250 } },
  { server = 32265, look = 38651, rank = 23373, slot = 'mana',   line = 'mana',   kind = 'mana',   tier = 3, level = 130, name = 'Everfull Ultimate Mana Potion',   roll = { 425, 575 } },
  { server = 32269, look = 38652, rank = 23373, slot = 'mana',   line = 'mana',   kind = 'mana',   tier = 4, level = 200, name = 'Everfull Supreme Mana Potion',    roll = { 575, 775 } },
  { server = 32268, look = 38653, rank = 266,   slot = 'health', line = 'spirit', kind = 'both',   tier = 1, level = 0,   name = 'Everfull Spirit Potion',          roll = { 75, 105 },  rollMana = { 45, 75 } },
  { server = 32263, look = 38654, rank = 7642,  slot = 'health', line = 'spirit', kind = 'both',   tier = 2, level = 80,  name = 'Everfull Great Spirit Potion',    roll = { 250, 350 }, rollMana = { 100, 200 } },
  { server = 32266, look = 38655, rank = 23374, slot = 'health', line = 'spirit', kind = 'both',   tier = 3, level = 130, name = 'Everfull Ultimate Spirit Potion', roll = { 420, 580 }, rollMana = { 200, 350 } },
  { server = 32270, look = 38656, rank = 23374, slot = 'health', line = 'spirit', kind = 'both',   tier = 4, level = 200, name = 'Everfull Supreme Spirit Potion',  roll = { 560, 760 }, rollMana = { 275, 475 } },
}
-- the stock looks of the first tier: a row on one of them (an old row, or one Auto setup made) follows the carried Everfull
-- of its slot (P.resolve)
P.FOLLOW = { [266] = 'health', [268] = 'mana' }

-- the percent formula (potions_config.lua amount); the fixed rolls are the rows' `roll`. ROLL: the fixed roll of a look, kept
-- for the stock looks 266 / 268 a row may still have (they follow the carried flask)
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
-- an Everfull with a look of its own is a potion of the list too (the server item id is its `server`); the dropdown offers it
for _, e in ipairs(P.EVERFULL_ITEMS) do
  if not byId[e.look] then
    local p = { id = e.look, server = e.server, kind = e.kind, name = e.name, level = e.level, everfull = true }
    P.LIST[#P.LIST + 1] = p
    byId[p.id] = p
  end
end

-- the Everfull entry that wears a look, or nil
function P.everfullOf(look)
  for _, e in ipairs(P.EVERFULL_ITEMS) do
    if e.look == look then return e end
  end
  return nil
end

-- What a row on potion `id` really drinks. A row on the Health / Mana Potion (the stock look the Everfull tier 1 wore before
-- pair 44, and the look Auto setup gives a plain flask) follows the Everfull the character carries in that slot: an upgrade replaces the item,
-- so the row would otherwise drink stock potions or nothing. held: ChaosEverfullHeld.get() ({ health = {look, tier,
-- level, line, ready}, mana = ... } or nil). Followed only when the carried one is a plain health / mana flask (a spirit
-- flask heals both pools and is chosen by a spirit row), known, ready (always true since O273, an older server may say false) and
-- allowed at `level`. The server checks the level again at the drink.
function P.resolve(id, held, level)
  id = tonumber(id)
  local slot = id and P.FOLLOW[id]
  local h = slot and type(held) == 'table' and held[slot]
  if not h or h.ready ~= true or h.line ~= slot or h.look == id then return id end
  if (tonumber(level) or 0) < (tonumber(h.level) or 0) then return id end
  local p = byId[tonumber(h.look) or -1]
  if not p or p.kind ~= slot then return id end
  return p.id
end

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
-- roll on the server) plus the percent. asMana: the mana part of a spirit flask. nil for an unknown item.
function P.expected(id, maxValue, asMana)
  local p = byId[tonumber(id) or -1]
  if not p then return nil end
  local e = P.everfullOf(p.id)
  local roll = e and ((asMana and e.rollMana) or e.roll) or P.ROLL[p.id]
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

-- Alphabetical order for a dropdown's options ({ text, data }): the option with data 0 ("(empty)") stays first, the rest by
-- the shown text, case-insensitive, an accented letter as its base letter (pt-BR names). Stable; a saved selection maps by
-- `data` (the key), never by position. Returns a new list.
local FOLD = {
  ['a'] = 'àáâãäå', ['c'] = 'ç', ['e'] = 'èéêë', ['i'] = 'ìíîï', ['n'] = 'ñ', ['o'] = 'òóôõö', ['u'] = 'ùúûü', ['y'] = 'ýÿ',
}
local foldMap = {}
for base, chars in pairs(FOLD) do
  for ch in chars:gmatch('[\192-\247][\128-\191]*') do
    foldMap[ch] = base
    foldMap[ch:upper()] = base
  end
end
local UPPER_ACCENTS = { ['À']='a',['Á']='a',['Â']='a',['Ã']='a',['Ä']='a',['Å']='a',['Ç']='c',['È']='e',['É']='e',['Ê']='e',['Ë']='e',
  ['Ì']='i',['Í']='i',['Î']='i',['Ï']='i',['Ñ']='n',['Ò']='o',['Ó']='o',['Ô']='o',['Õ']='o',['Ö']='o',['Ù']='u',['Ú']='u',['Û']='u',['Ü']='u',['Ý']='y' }
for ch, base in pairs(UPPER_ACCENTS) do foldMap[ch] = base end

function P.sortKey(text)
  local s = tostring(text or '')
  s = s:gsub('[\192-\247][\128-\191]*', function(ch) return foldMap[ch] end)
  return s:lower()
end

function P.sortOptions(options)
  local first, rest = {}, {}
  for i, o in ipairs(options or {}) do
    if o.data == 0 then first[#first + 1] = o else rest[#rest + 1] = { o = o, key = P.sortKey(o.text), i = i } end
  end
  table.sort(rest, function(a, b)
    if a.key ~= b.key then return a.key < b.key end
    return a.i < b.i
  end)
  for _, e in ipairs(rest) do first[#first + 1] = e.o end
  return first
end

-- The rows due now. rows: the healing tab's potion rows ({ id, percent, priority }); ctx = { healthPct, manaPct,
-- available(id) -> true when the potion can be used (carried or probed, and its channel is ready) }.
-- Returns the due rows of a kind sorted by the lowest threshold first, then the priority.
local function due(rows, kind, pct, available, resolve)
  local list = {}
  for i, row in ipairs(rows or {}) do
    local id = tonumber(row.id) or 0
    local kindOf = P.rowKind(row) -- of the row's own potion
    if resolve and id > 0 then id = resolve(id) or id end
    if id > 0 and kindOf == kind and pct <= (tonumber(row.percent) or 0) and (not available or available(id)) then
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
-- ctx.held / ctx.level: the carried Everfull and the level (P.resolve); the id returned is the look to use
function P.pick(rows, ctx)
  local resolve = ctx.held and function(id) return P.resolve(id, ctx.held, ctx.level) end or nil
  local health = due(rows, 'health', tonumber(ctx.healthPct) or 100, ctx.available, resolve)
  if health[1] then return health[1].id, 'health' end
  local mana = due(rows, 'mana', tonumber(ctx.manaPct) or 100, ctx.available, resolve)
  if mana[1] then return mana[1].id, 'mana' end
  return nil
end

-- is a health potion row due by the numbers alone (its potion may not be at hand)? The mana potions wait for it: one
-- health potion in need must not be passed over for a mana one (the former helper's "health potion priority")
function P.healthDue(rows, healthPct)
  return due(rows, 'health', tonumber(healthPct) or 100, nil)[1] ~= nil
end

return ChaosHelperPotions
