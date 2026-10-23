-- ChaosHelperRunes: the runes the helper uses and when (pure Lua: no engine calls; tests: helper_runes_test.lua).
-- Runes are items the NPCs sell and the crafting tables make (server/README.md "Rune supply": no spell conjures a rune any
-- more); the player carries them and the helper uses them by item id on a creature, like the former helper did:
--   * healing runes (Mending, Grand Mending) on yourself by health percent, or on a party member or friend
--     (helper_ally.lua), each on the server's healing rune channel (ChaosHelperTimers 'healRune');
--   * attack runes on the target: the rune is used when enough monsters would be hit and the target's health is in the
--     range of the row, on the attack rune channel ('attackRune'). Only the damage runes are offered; fields, walls,
--     bombs, summons, the paralyze rune, Beastbond and the like are never used by the helper.
-- The ids are the CLIENT item ids (what getInventoryCount and the use packet take, like the potions of helper_potions.lua).
-- The server's ids (data/lib/chaos_rune_supply.lua) are the client ids minus 887 for the stock runes; the three added runes
-- have their own looks. The test reads the server file and checks the names and the offset.
-- No rune has a level requirement on this server (add_vocations.py gives every rune level 1) and the magic level and class
-- of a rune live in the server's spells.xml, which the client does not have: the helper only offers what the class may use
-- when the client knows it (the stock list of Dawnshard), and the server's refusal ends in a back-off (ChaosPotionGate).
ChaosHelperRunes = ChaosHelperRunes or {}
local R = ChaosHelperRunes

R.SERVER_OFFSET = 887
R.AREA_REACH = 6            -- a single-target rune counts the monsters this close to the player (like the shooter)
R.MIN_GAP_MS = 1000         -- the least time between two runes of the same row on top of the channel's own timer

-- kind 'heal' | 'attack'; radius: the rune hits the target and the cells this far around it (0: only the target)
R.LIST = {
  { id = 3152, server = 2265, name = 'Mending Rune', kind = 'heal', radius = 0 },
  { id = 3160, server = 2273, name = 'Grand Mending Rune', kind = 'heal', radius = 0 },
  { id = 21352, server = 23723, name = 'Faint Dart Rune', kind = 'attack', radius = 0 },
  { id = 3174, server = 2287, name = 'Hexdart Rune', kind = 'attack', radius = 0 },
  { id = 3198, server = 2311, name = 'Greater Hexdart Rune', kind = 'attack', radius = 0 },
  { id = 3182, server = 2295, name = 'Dawnshard Rune', kind = 'attack', radius = 0, vocations = { 3, 7 } },
  { id = 3155, server = 2268, name = "Reaper's Rune", kind = 'attack', radius = 0 },
  { id = 3195, server = 2308, name = 'Soulpyre Rune', kind = 'attack', radius = 0 },
  { id = 3158, server = 2271, name = 'Rimespike Rune', kind = 'attack', radius = 0 },
  { id = 3179, server = 2292, name = 'Stonefang Rune', kind = 'attack', radius = 0 },
  { id = 3189, server = 2302, name = 'Cinder Orb Rune', kind = 'attack', radius = 1 },
  { id = 3200, server = 2313, name = 'Concussion Rune', kind = 'attack', radius = 1 },
  { id = 3191, server = 2304, name = 'Searing Orb Rune', kind = 'attack', radius = 3 },
  { id = 3161, server = 2274, name = 'Frostfall Rune', kind = 'attack', radius = 3 },
  { id = 3175, server = 2288, name = 'Rockfall Rune', kind = 'attack', radius = 3 },
  { id = 3202, server = 2315, name = 'Stormcall Rune', kind = 'attack', radius = 3 },
  { id = 21351, server = 23722, name = 'Pebblestorm Rune', kind = 'attack', radius = 3 },
}

local byId = {}
for _, r in ipairs(R.LIST) do byId[r.id] = r end

function R.info(id)
  return byId[tonumber(id) or -1]
end

function R.isHeal(id)
  local r = byId[tonumber(id) or -1]
  return r ~= nil and r.kind == 'heal'
end

function R.isAttack(id)
  local r = byId[tonumber(id) or -1]
  return r ~= nil and r.kind == 'attack'
end

-- the runes the class may use, a list of records in the order of R.LIST. classOk(rune) -> true when the class lists it
-- (optional: without it every rune counts).
function R.offered(kind, classOk)
  local out = {}
  for _, r in ipairs(R.LIST) do
    if r.kind == kind and (not r.vocations or not classOk or classOk(r)) then out[#out + 1] = r end
  end
  return out
end

-- ---------------------------------------------------------------- healing runes (self or an ally)
-- The healing rune to use now, or nil. rows: { { id, percent } }; ctx = { healthPct, available(id) -> true when the rune can
-- be used (carried or probed, and its channel is ready) }. The lowest threshold goes first.
function R.pickHeal(rows, ctx)
  local list = {}
  for i, r in ipairs(rows or {}) do
    local id = tonumber(r.id) or 0
    if R.isHeal(id) and (tonumber(ctx.healthPct) or 100) <= (tonumber(r.percent) or 0)
        and (not ctx.available or ctx.available(id)) then
      list[#list + 1] = { id = id, percent = tonumber(r.percent) or 0, i = i }
    end
  end
  table.sort(list, function(a, b)
    if a.percent ~= b.percent then return a.percent < b.percent end
    return a.i < b.i
  end)
  return list[1] and list[1].id or nil
end

-- is a healing rune row due by the numbers alone (the rune may not be at hand)? Self comes first: the ally heals wait for it.
function R.healDue(rows, healthPct)
  return R.pickHeal(rows, { healthPct = healthPct }) ~= nil
end

-- ---------------------------------------------------------------- attack runes
-- The monsters a rune on `target` would hit: the target itself and every monster within the rune's radius of it. A rune
-- without an area counts the monsters near the player (R.AREA_REACH), like the shooter's single-target spells.
-- entries: { { position, health (percent), creature } } (the monsters in the window); targetPos: the target's position.
-- hpOk(entry) -> false drops a monster that does not fit the row's health range.
function R.hits(rune, entries, from, targetPos, hpOk)
  local n = 0
  local radius = rune and tonumber(rune.radius) or 0
  for _, e in ipairs(entries or {}) do
    local p = e.position
    if p and p.z == from.z and (not hpOk or hpOk(e)) then
      if radius > 0 then
        if targetPos and math.max(math.abs(p.x - targetPos.x), math.abs(p.y - targetPos.y)) <= radius then n = n + 1 end
      elseif math.max(math.abs(p.x - from.x), math.abs(p.y - from.y)) <= R.AREA_REACH then
        n = n + 1
      end
    end
  end
  return n
end

-- the health range of a row: hpMin 0 and hpMax 0 mean no limit (the former helper's rune rules)
function R.healthFits(row, healthPct)
  local lo, hi = tonumber(row.hpMin) or 0, tonumber(row.hpMax) or 0
  local h = tonumber(healthPct) or 100
  if h < lo then return false end
  if hi > 0 and h > hi then return false end
  return true
end

-- the rows in the order they are tried (priority, then position)
function R.order(rows)
  local list = {}
  for i, r in ipairs(rows or {}) do
    if type(r) == 'table' and R.isAttack(r.id) then list[#list + 1] = { r = r, i = i } end
  end
  table.sort(list, function(a, b)
    local pa, pb = tonumber(a.r.priority) or a.i, tonumber(b.r.priority) or b.i
    if pa ~= pb then return pa < pb end
    return a.i < b.i
  end)
  local out = {}
  for _, e in ipairs(list) do out[#out + 1] = e.r end
  return out
end

-- The attack rune to use now: returns the row, or nil. ctx = {
--   target = { position, health }  (nil: no target, no rune),
--   from = the player's position,
--   entries = the monsters in the window,
--   inRange(targetPos) -> true when the target can be hit (reach and line of sight),
--   available(id) -> true when the rune is carried (or probed) and its channel is ready }
function R.pickAttack(rows, ctx)
  local target = ctx.target
  if not target or not target.position then return nil end
  if ctx.inRange and not ctx.inRange(target.position) then return nil end
  for _, row in ipairs(R.order(rows)) do
    local rune = byId[tonumber(row.id) or -1]
    if rune and R.healthFits(row, target.health) and (not ctx.available or ctx.available(rune.id)) then
      local hits = R.hits(rune, ctx.entries, ctx.from, target.position, function(e)
        return R.healthFits(row, e.health)
      end)
      if hits >= (tonumber(row.creatures) or 1) then return row end
    end
  end
  return nil
end

return ChaosHelperRunes
