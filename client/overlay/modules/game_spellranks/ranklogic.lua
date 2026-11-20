-- Pure logic of the spell upgrades client (O686 phase 5): no UI calls, tested by ranklogic_test.lua (client loop).
-- Server: server/data/scripts/chaos/spell_ranks.lua and spell_forms.lua, extended opcode 168 (JSON {action, data}).
--   client -> server  open {}                     (the state and the Form picks; rate limited by the server to one per 2 s)
--                     pick {spell, tier, pick}    (tier 1 or 2, pick 1 or 2)
--   server -> client  state {on, v, s = [[spell id, rank, SP into the rank, SP the next rank costs (0 at the top)], ...]}
--                     forms {v, f = [[spell id, Form I pick, Form II pick], ...]}   (picks 0 / 1 / 2, only spells with a pick)
--                     pick {ok, why, price, spell, tier, pick, f1, f2}
--                     rank {...}  one spell changed (same entry as a state row, or {s = [...]}); sent at a rank-up since phase 6
--                     combo {id, n, x, y, z}  a spell combo fired (combologic.lua)
-- The switch: spell_ranks_config.lua `enabled`. `state.on` false, no state at all, or a pick answered `off` means the
-- switch is off: the client shows nothing new (ChaosRankLogic.isOn). Design: docs/SPELL_UPGRADES.md sections 1.5, 2.4, 6.
-- Plain Lua 5.1 / LuaJIT / 5.3, no globals but ChaosRankLogic.

ChaosRankLogic = ChaosRankLogic or {}
local L = ChaosRankLogic

L.OPCODE = 168
L.MAX_RANK = 20

-- what a rank gives (spell_ranks_config.lua `effects`; ranklogic_test.lua holds the two equal when run from the repo root)
L.EFFECTS = {
  damage = { power = 0.9, cooldownPerStep = 2, mana = 1.0 },
  heal = { power = 0.6, cooldownPerStep = 3, mana = 1.25 },
}
L.CD_RANKS = { 4, 8, 12, 16, 20 }

-- the pick rules when forms_data.lua is not there (the same numbers, spell_ranks_config.lua `forms`)
L.DEFAULT_PICK = { rank1 = 10, rank2 = 20, minPrice = 10000, perLevel = 150, freeSeconds = 1800 }

-- every answer of `pick` the client words (the UI has one tr() text for each, ranklogic_test.lua lists them)
L.WHY_FAIL = { 'off', 'spell', 'rank', 'form1', 'gold', 'tier', 'pick' }
L.WHY_OK = { 'first', 'same', 'window', 'paid' }

local function num(v, d)
  v = tonumber(v)
  if v == nil or v ~= v then return d end
  return v
end

local function int(v, d)
  v = num(v, d)
  if v == nil then return d end
  return math.floor(v)
end

-- ---------------------------------------------------------------- messages of the server
-- {on, ranks = {[spell id] = {rank, into, cost}}}; nil for junk
function L.cleanState(data)
  if type(data) ~= 'table' then return nil end
  local out = { on = data.on == true, ranks = {} }
  if type(data.s) == 'table' then
    for _, row in ipairs(data.s) do
      local e = L.cleanRow(row)
      if e then out.ranks[e.id] = e end
    end
  end
  return out
end

-- one row [id, rank, into, cost] (or {id =, rank =, into =, cost =}) -> {id, rank, into, cost}
function L.cleanRow(row)
  if type(row) ~= 'table' then return nil end
  local id = int(row[1] or row.id or row.spell, nil)
  if not id or id <= 0 then return nil end
  local rank = math.max(0, math.min(L.MAX_RANK, int(row[2] or row.rank, 0)))
  local into = math.max(0, num(row[3] or row.into, 0))
  local cost = math.max(0, num(row[4] or row.cost, 0))
  if rank >= L.MAX_RANK then cost, into = 0, 0 end
  return { id = id, rank = rank, into = into, cost = cost }
end

-- a `rank` message: one row, a list of rows, or {s = rows}; the rows are merged into `ranks` (nil: nothing)
function L.applyRank(ranks, data)
  if type(data) ~= 'table' or type(ranks) ~= 'table' then return 0 end
  local rows
  if type(data.s) == 'table' then
    rows = data.s
  elseif type(data[1]) == 'table' then
    rows = data
  else
    rows = { data }
  end
  local n = 0
  for _, row in ipairs(rows) do
    local e = L.cleanRow(row)
    if e then ranks[e.id] = e; n = n + 1 end
  end
  return n
end

-- {[spell id] = {f1, f2}} from a `forms` message
function L.cleanForms(data)
  local out = {}
  if type(data) ~= 'table' or type(data.f) ~= 'table' then return out end
  for _, row in ipairs(data.f) do
    if type(row) == 'table' then
      local id = int(row[1], nil)
      if id and id > 0 then
        out[id] = { f1 = math.max(0, math.min(2, int(row[2], 0))), f2 = math.max(0, math.min(2, int(row[3], 0))) }
      end
    end
  end
  return out
end

-- the answer of a pick: {ok, why, price, spell, tier, pick, f1, f2}; nil for junk
function L.cleanPick(data)
  if type(data) ~= 'table' then return nil end
  return {
    ok = data.ok == true, why = type(data.why) == 'string' and data.why or '', price = math.max(0, int(data.price, 0)),
    spell = int(data.spell, 0), tier = int(data.tier, 0), pick = int(data.pick, 0),
    f1 = int(data.f1, nil), f2 = int(data.f2, nil),
  }
end

-- the picks after an answer: an accepted pick sets the tier's pick (f1 / f2 of the answer win when present)
function L.applyPick(picks, res)
  if type(picks) ~= 'table' or type(res) ~= 'table' or not res.ok or res.spell <= 0 then return end
  local e = picks[res.spell] or { f1 = 0, f2 = 0 }
  if res.f1 ~= nil then e.f1 = res.f1 elseif res.tier == 1 then e.f1 = res.pick end
  if res.f2 ~= nil then e.f2 = res.f2 elseif res.tier == 2 then e.f2 = res.pick end
  picks[res.spell] = e
end

-- the answer's reason: 'ok' kinds and failures are kept apart so the UI knows the colour; unknown reasons say 'other'
function L.whyCode(res)
  if type(res) ~= 'table' then return 'other', false end
  local why = res.why
  if res.ok then
    for _, w in ipairs(L.WHY_OK) do if w == why then return why, true end end
    return 'first', true
  end
  for _, w in ipairs(L.WHY_FAIL) do if w == why then return why, false end end
  return 'other', false
end

-- ---------------------------------------------------------------- the switch
-- off: no state yet, or the state says so, or a pick was answered `off`
function L.isOn(state)
  return type(state) == 'table' and state.on == true
end

-- ---------------------------------------------------------------- ranks
function L.rankEntry(state, id)
  id = int(id, nil)
  if not id or not L.isOn(state) then return nil end
  return state.ranks[id]
end

function L.rank(state, id)
  local e = L.rankEntry(state, id)
  return e and e.rank or 0
end

-- 0..1 of the way to the next rank (1 at the top)
function L.fraction(e)
  if not e then return 0 end
  if e.rank >= L.MAX_RANK then return 1 end
  if e.cost <= 0 then return 0 end
  return math.max(0, math.min(1, e.into / e.cost))
end

-- SP still to earn for the next rank (0 at the top)
function L.spToGo(e)
  if not e or e.rank >= L.MAX_RANK then return 0 end
  return math.max(0, e.cost - e.into)
end

-- percent shown on a row's thin bar: whole 0..100, at least 1 when there is progress
function L.rowPercent(e)
  if not e or e.rank >= L.MAX_RANK then return e and 100 or 0 end
  local f = L.fraction(e)
  if f <= 0 then return 0 end
  return math.max(1, math.min(100, math.floor(f * 100 + 0.5)))
end

local function effectsOf(isHeal)
  return isHeal and L.EFFECTS.heal or L.EFFECTS.damage
end

-- cooldown steps reached at a rank (0..5)
function L.cdSteps(rank)
  local n = 0
  for _, r in ipairs(L.CD_RANKS) do if rank >= r then n = n + 1 end end
  return n
end

-- what a rank holds in all: {power percent, cooldown percent cut, mana percent cut}
function L.totals(rank, isHeal)
  rank = math.max(0, math.min(L.MAX_RANK, int(rank, 0)))
  local e = effectsOf(isHeal)
  return { power = rank * e.power, cooldown = L.cdSteps(rank) * e.cooldownPerStep, mana = rank * e.mana }
end

-- what reaching `rank` adds over the rank before it
function L.gives(rank, isHeal)
  rank = math.max(1, math.min(L.MAX_RANK, int(rank, 1)))
  local a, b = L.totals(rank - 1, isHeal), L.totals(rank, isHeal)
  return { power = b.power - a.power, cooldown = b.cooldown - a.cooldown, mana = b.mana - a.mana }
end

-- ---------------------------------------------------------------- forms_data.lua
-- the base kind of a table key: "ASCEND:death" -> "ASCEND"
function L.baseKind(key)
  return (tostring(key or ''):match('^([^:]+)')) or ''
end

function L.pickRules(data)
  local p = type(data) == 'table' and type(data.pick) == 'table' and data.pick or {}
  local d = L.DEFAULT_PICK
  return {
    rank1 = int(p.rank1, d.rank1), rank2 = int(p.rank2, d.rank2), minPrice = int(p.minPrice, d.minPrice),
    perLevel = int(p.perLevel, d.perLevel), freeSeconds = int(p.freeSeconds, d.freeSeconds),
  }
end

-- the spell's Forms: {heal, element, tiers = {[1] = {{kind, name, text}, {..}}, [2] = {..}}} or nil (a spell with no Forms)
function L.formsFor(data, id)
  id = int(id, nil)
  local spell = id and type(data) == 'table' and type(data.spells) == 'table' and data.spells[id] or nil
  if type(spell) ~= 'table' or type(spell.forms) ~= 'table' then return nil end
  local out = { heal = spell.heal == true, element = spell.element, name = spell.name, tiers = {} }
  for tier = 1, 2 do
    local list = {}
    local row = spell.forms[tier]
    if type(row) ~= 'table' then return nil end
    for pick = 1, 2 do
      local f = row[pick]
      if type(f) ~= 'table' then return nil end
      local kind = L.baseKind(f[1])
      local k = type(data.kinds) == 'table' and data.kinds[kind] or nil
      list[pick] = { kind = tostring(f[1]), name = tostring(f[2] or kind), text = type(k) == 'table' and tostring(k.text or '') or '' }
    end
    out.tiers[tier] = list
  end
  return out
end

-- what one tier of a spell is for the character: {rankNeeded, locked, needForm1, picked}
function L.tierState(rules, rank, f1, f2, tier)
  local needed = tier == 1 and rules.rank1 or rules.rank2
  local picked = tier == 1 and (f1 or 0) or (f2 or 0)
  local locked = rank < needed
  return { rankNeeded = needed, locked = locked, needForm1 = (not locked) and tier == 2 and (f1 or 0) == 0, picked = picked }
end

-- gold of a paid change: max(minPrice, perLevel x level)
function L.price(rules, level)
  return math.max(rules.minPrice, rules.perLevel * math.max(0, int(level, 0)))
end

-- A click on a pick button: what will happen, from what the client knows. `last` = {spell, tier, at} of the last pick
-- made in this session (the server keeps the free window across logins; a window the client does not know shows as a
-- paid change and the server's answer says what was charged), `now` os.time().
-- Returns {kind = 'locked' | 'form1' | 'same' | 'first' | 'window' | 'paid', price}
function L.quote(rules, spellId, tier, pick, rank, f1, f2, level, last, now)
  local st = L.tierState(rules, rank, f1, f2, tier)
  if st.locked then return { kind = 'locked', price = 0 } end
  if st.needForm1 then return { kind = 'form1', price = 0 } end
  if st.picked == pick then return { kind = 'same', price = 0 } end
  if st.picked == 0 then return { kind = 'first', price = 0 } end
  if L.windowLeft(rules, spellId, tier, last, now) then return { kind = 'window', price = 0 } end
  return { kind = 'paid', price = L.price(rules, level) }
end

-- seconds of the free change window left on this tier of this spell, nil when there is none (the server: a change at
-- most freeSeconds after the last pick is free, so 0 seconds left still counts)
function L.windowLeft(rules, spellId, tier, last, now)
  if type(last) ~= 'table' or last.spell ~= spellId or last.tier ~= tier then return nil end
  local left = rules.freeSeconds - (num(now, 0) - num(last.at, -1e12))
  return left >= 0 and math.floor(left) or nil
end

-- the number the hub's Spellbook card shows: spells with a Form that can be picked now (Form I at rank 10 with no pick,
-- or Form II at rank 20 with Form I picked and no Form II pick). 0 while the switch is off.
function L.pickableCount(state, picks, data)
  if not L.isOn(state) then return 0 end
  local rules = L.pickRules(data)
  local n = 0
  for id, e in pairs(state.ranks) do
    if L.formsFor(data, id) then
      local p = type(picks) == 'table' and picks[id] or nil
      local f1, f2 = p and p.f1 or 0, p and p.f2 or 0
      local a, b = L.tierState(rules, e.rank, f1, f2, 1), L.tierState(rules, e.rank, f1, f2, 2)
      if (not a.locked and a.picked == 0) or (not b.locked and not b.needForm1 and b.picked == 0) then
        n = n + 1
      end
    end
  end
  return n
end

-- a spell the Upgrades tab has something to say about: it has Forms or ranks
function L.isRankable(state, data, id)
  return L.formsFor(data, id) ~= nil or L.rankEntry(state, id) ~= nil
end

return L
