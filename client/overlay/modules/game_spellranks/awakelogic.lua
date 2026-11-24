-- Pure logic of the spell awakening client (O686 phase 7): no UI calls, tested by awakelogic_test.lua (client loop).
-- Server: server/data/scripts/chaos/spell_awakening.lua, extended opcode 168 (JSON {action, data}).
--   client -> server  awaken {spell, slot}      (slot 1..3: the lowest free one; the server refuses another)
--   server -> client  awakened {on, v, seals = [waystone, rift, pinnacle], slots = [spell id or 0, x3], costs = [[w, r, p] x3], held, bonus}
--                     awaken {ok, why, spell, slot, name, namePt, cost = {waystone, rift, pinnacle}, need = {waystone, rift, pinnacle}}
-- The names and the signature effect of each spell: awakened_data.lua (generated from server/data/spells/awakened.csv by
-- server/tools/gen_awakened_data.lua). The signature is written as a sentence out of the parts of its kind (A.sentences), the English
-- templates are tr() keys with their pt-BR in client_chaos_locale/pt_br.lua. Design: docs/SPELL_UPGRADES.md section 3.
-- Plain Lua 5.1 / LuaJIT / 5.3, no globals but ChaosAwakeLogic.

ChaosAwakeLogic = ChaosAwakeLogic or {}
local A = ChaosAwakeLogic

A.MAX_SLOTS = 3
A.MAX_RANK = 20

-- every reason the server answers (the UI has one tr() text for each, awakelogic_test.lua lists them)
A.WHY_FAIL = { 'off', 'spell', 'unknown', 'rank', 'forms', 'already', 'slot', 'slotlevel', 'level', 'seals' }

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
local function triple(t)
  if type(t) ~= 'table' then return { 0, 0, 0 } end
  return { math.max(0, int(t[1] or t.waystone, 0)), math.max(0, int(t[2] or t.rift, 0)), math.max(0, int(t[3] or t.pinnacle, 0)) }
end

-- {on, seals = {w, r, p}, slots = {id x3}, costs = {{w, r, p} x3}, held, bonus}; nil for junk
function A.cleanState(data)
  if type(data) ~= 'table' then return nil end
  local out = { on = data.on == true, seals = triple(data.seals), slots = {}, costs = {}, held = 0, bonus = math.max(0, num(data.bonus, 0.1)) }
  for i = 1, A.MAX_SLOTS do
    local id = type(data.slots) == 'table' and int(data.slots[i], 0) or 0
    out.slots[i] = id > 0 and id or 0
    if out.slots[i] > 0 then out.held = out.held + 1 end
    out.costs[i] = triple(type(data.costs) == 'table' and data.costs[i] or nil)
  end
  return out
end

-- the answer of an awaken request: {ok, why, spell, slot, name, namePt, cost, need}; nil for junk
function A.cleanAnswer(data)
  if type(data) ~= 'table' then return nil end
  return {
    ok = data.ok == true, why = type(data.why) == 'string' and data.why or '', spell = int(data.spell, 0), slot = int(data.slot, 0),
    name = type(data.name) == 'string' and data.name or '', namePt = type(data.namePt) == 'string' and data.namePt or '',
    cost = triple(data.cost), need = triple(data.need), rank = int(data.rank, 0), level = math.max(0, int(data.level, 0)),
  }
end

-- the answer's reason: a failure the client words, or `ok`; unknown reasons say 'other'
function A.whyCode(res)
  if type(res) ~= 'table' then return 'other', false end
  if res.ok then return 'ok', true end
  for _, w in ipairs(A.WHY_FAIL) do if w == res.why then return w, false end end
  return 'other', false
end

-- ---------------------------------------------------------------- the switch and the state
function A.isOn(state)
  return type(state) == 'table' and state.on == true
end

-- the slot (1..3) a spell is awakened in, nil when it is not
function A.slotOf(state, id)
  id = int(id, nil)
  if not id or not A.isOn(state) then return nil end
  for i = 1, A.MAX_SLOTS do
    if state.slots[i] == id then return i end
  end
  return nil
end

-- the lowest free slot, nil when all are taken
function A.lowestFree(state)
  if type(state) ~= 'table' then return nil end
  for i = 1, A.MAX_SLOTS do
    if state.slots[i] == 0 then return i end
  end
  return nil
end

-- ---------------------------------------------------------------- the data
function A.entry(data, id)
  id = int(id, nil)
  if not id or type(data) ~= 'table' or type(data.spells) ~= 'table' then return nil end
  local e = data.spells[id]
  return type(e) == 'table' and e or nil
end

-- the awakened name of a spell in the language: English, or pt-BR (`pt` true)
function A.nameOf(data, id, pt)
  local e = A.entry(data, id)
  if not e then return nil end
  local name = pt and e.pt or e.en
  return (name and name ~= '') and name or e.en
end

-- the name the Spellbook shows for a spell: the awakened one while it is awakened, else nil
function A.shownName(data, state, id, pt)
  if not A.slotOf(state, id) then return nil end
  return A.nameOf(data, id, pt)
end

-- ---------------------------------------------------------------- what an awakening needs (the server decides again)
-- rank, f1, f2: the spell's rank and Form picks the client knows. Returns {ok, why, slot, cost, need, level}
-- why: off | spell | rank | forms | already | slot | slotlevel | level | seals | ok (the server also refuses `unknown`: a spell the
-- character no longer knows). O752: gates = {level = the character's, slot = {levels of the slots}, spell = the spell's awakening level}
-- (ranklogic.lua L.slotGate / L.awakenGate; nil: no gate known)
function A.check(state, data, id, rank, f1, f2, gates)
  if not A.isOn(state) then return { ok = false, why = 'off' } end
  if not A.entry(data, id) then return { ok = false, why = 'spell' } end
  if int(rank, 0) < A.MAX_RANK then return { ok = false, why = 'rank', rank = A.MAX_RANK } end
  if int(f1, 0) == 0 or int(f2, 0) == 0 then return { ok = false, why = 'forms' } end
  if A.slotOf(state, id) then return { ok = false, why = 'already' } end
  local slot = A.lowestFree(state)
  if not slot then return { ok = false, why = 'slot' } end
  if type(gates) == 'table' then
    local level = int(gates.level, 0)
    local need = type(gates.slot) == 'table' and int(gates.slot[slot], 0) or 0
    if level < need then return { ok = false, why = 'slotlevel', slot = slot, level = need } end
    if level < int(gates.spell, 0) then return { ok = false, why = 'level', slot = slot, level = int(gates.spell, 0) } end
  end
  local cost = state.costs[slot]
  local need, short = { 0, 0, 0 }, false
  for i = 1, 3 do
    if state.seals[i] < cost[i] then
      need[i] = cost[i] - state.seals[i]
      short = true
    end
  end
  if short then return { ok = false, why = 'seals', slot = slot, cost = cost, need = need } end
  return { ok = true, why = 'ok', slot = slot, cost = cost }
end

-- ---------------------------------------------------------------- the sentences of a signature
-- `fmt`: a number as the language writes it (a plain number text in English; pt-BR writes the comma)
local function plain(v)
  if v == math.floor(v) then return string.format('%d', v) end
  return string.format('%.4g', v)
end

local function pct(v, fmt)
  local p = math.floor(v * 1000 + 0.5) / 10
  return (fmt or plain)(p)
end

-- the English templates (tr keys): the pt-BR of each is in pt_br.lua
A.TEMPLATES = {
  pulse = 'A ring stays %s s and pulses %d times for %s%% of the hit.',
  pulseMana = 'A ring stays %s s and pulses %d times for %s%% of the hit. A pulse that hits %d or more enemies returns %s%% mana.',
  pulseHeal = 'A ring stays %s s and heals the allies in it %d times for %s%% of the heal.',
  line = 'The hit becomes a line of %d sqm that strikes every enemy in it for %s%%.',
  mark = 'Marks each enemy it hits for %s s: the next single target spell on it hits %s%% harder, once.',
  rings = 'Sends %d rings of its area, each for %s%%.',
  echo = 'The hit repeats after %s s for %s%%.',
  echoHeal = 'The heal repeats after %s s for %s%%.',
  shield = 'Gives you a shield of %s%% of your max health for %s s.',
  shieldMin = 'Gives you a shield of %s%% of your max health for %s s when it hits %d or more enemies.',
  shieldHeal = 'Each ally it heals gets a shield of %s%% of its max health for %s s.',
  cdcut = 'Each kill in the next %s s cuts %s s of its cooldown, at most %s s.',
  leech = 'Heals you for %s%% of the damage it deals.',
  reflect = 'The heal reflects to every ally within %d sqm for %s%%.',
}

-- the sentences of one spell's signature: a list of texts, one a part. `tr`: the translator (tr(template, ...)), `fmt`: the number writer
function A.sentences(entry, tr, fmt)
  local out = {}
  if type(entry) ~= 'table' or type(entry.parts) ~= 'table' then return out end
  tr = tr or function(s, ...) return string.format(s, ...) end
  fmt = fmt or plain
  local T = A.TEMPLATES
  for _, part in ipairs(entry.parts) do
    local kind, n = part[1], part[2] or {}
    if kind == 'PULSE' then
      if entry.heal then
        out[#out + 1] = tr(T.pulseHeal, fmt(n.secs or 0), int(n.pulses, 0), pct(n.pct or 0, fmt))
      elseif (n.mana or 0) > 0 then
        out[#out + 1] = tr(T.pulseMana, fmt(n.secs or 0), int(n.pulses, 0), pct(n.pct or 0, fmt), int(n.minHit, 1), pct(n.mana, fmt))
      else
        out[#out + 1] = tr(T.pulse, fmt(n.secs or 0), int(n.pulses, 0), pct(n.pct or 0, fmt))
      end
    elseif kind == 'LINE' then
      out[#out + 1] = tr(T.line, int(n.len, 0), pct(n.pct or 0, fmt))
    elseif kind == 'MARK' then
      out[#out + 1] = tr(T.mark, fmt(n.secs or 0), pct(n.pct or 0, fmt))
    elseif kind == 'RINGS' then
      out[#out + 1] = tr(T.rings, int(n.rings, 0), pct(n.pct or 0, fmt))
    elseif kind == 'ECHO' then
      out[#out + 1] = tr(entry.heal and T.echoHeal or T.echo, fmt((n.delay or 0) / 1000), pct(n.pct or 0, fmt))
    elseif kind == 'SHIELD' then
      if entry.heal then
        out[#out + 1] = tr(T.shieldHeal, pct(n.pct or 0, fmt), fmt(n.secs or 0))
      elseif (n.minHit or 1) > 1 then
        out[#out + 1] = tr(T.shieldMin, pct(n.pct or 0, fmt), fmt(n.secs or 0), int(n.minHit, 1))
      else
        out[#out + 1] = tr(T.shield, pct(n.pct or 0, fmt), fmt(n.secs or 0))
      end
    elseif kind == 'CDCUT' then
      out[#out + 1] = tr(T.cdcut, fmt(n.window or 0), fmt(n.cut or 0), fmt(n.cap or 0))
    elseif kind == 'LEECH' then
      out[#out + 1] = tr(T.leech, pct(n.pct or 0, fmt))
    elseif kind == 'REFLECT' then
      out[#out + 1] = tr(T.reflect, int(n.radius, 0), pct(n.pct or 0, fmt))
    end
  end
  return out
end

return A
