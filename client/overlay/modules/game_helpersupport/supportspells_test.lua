-- luajit supportspells_test.lua && lua5.3 supportspells_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'supportspells.lua')
dofile(dir .. '../game_chaosspells/spelldata.lua')
local H = ChaosHelperSupport
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(c, what) eq(not not c, true, what) end

-- the client's spell entries as game_chaosspells builds them from the generated data
local entries, byId = {}, {}
for _, s in ipairs(ChaosSpellData) do
  local e = { id = s.id, name = s.name, words = s.words, level = s.level, mana = s.mana, group = { [s.group] = s.groupCooldown },
    exhaustion = s.cooldown, needTarget = s.needTarget, parameter = false, vocations = s.vocations }
  entries[#entries + 1] = e
  byId[e.id] = e
end
local function add(e) entries[#entries + 1] = e byId[e.id] = e end
add({ id = 44, name = 'Ward of the Mind', words = 'utamo vita', level = 14, mana = 50, group = { [3] = 2000 }, exhaustion = 14000, vocations = { 1, 5 } })
add({ id = 10, name = 'Light', words = 'utevo lux', level = 8, mana = 20, group = { [3] = 2000 }, exhaustion = 2000, vocations = { 1 } })
add({ id = 9, name = 'Summon Creature', words = 'utevo res', level = 25, mana = 0, group = { [3] = 2000 }, exhaustion = 2000, parameter = true, vocations = { 1 } })
add({ id = 264, name = 'Avatar', words = 'uteta res eq', level = 0, mana = 800, group = { [3] = 2000 }, exhaustion = 7200000, special = true, vocations = { 8 } })
add({ id = 900, name = 'Future Ward', words = 'tor new', level = 10, mana = 50, group = { [3] = 2000 }, exhaustion = 20000, vocations = { 1 } })
add({ id = 901, name = 'Future Strike', words = 'kah new', level = 10, mana = 50, group = { [1] = 2000 }, exhaustion = 4000, vocations = { 1 } })

local function canCastFor(voc, level)
  return function(id)
    local s = byId[id]
    if not s then return false end
    local listed = false
    for _, v in ipairs(s.vocations) do if v == voc then listed = true end end
    return listed and s.level <= level
  end
end

-- ---------------------------------------------------------------- what is eligible
ok(H.eligible(byId[234]), 'Soulward: a support spell')
ok(not H.eligible(byId[201]), 'an attack spell is not')
ok(not H.eligible(byId[901]), 'an attack group spell is not')
eq(select(2, H.eligible(byId[10])), 'utility', 'Light: a utility')
eq(select(2, H.eligible(byId[9])), 'target', 'Summon Creature: it needs a typed name')
eq(select(2, H.eligible(byId[254])), 'utility', 'Town Portal: never')
eq(select(2, H.eligible(byId[232])), 'utility', 'Flickerdash: never')
ok(H.eligible(byId[162]), 'Vigil of Clarity: eligible')
ok(H.eligible(byId[900]), 'a support spell added later is eligible by its data')
ok(H.isSupportGroup({ [3] = 2000 }), 'group 3')
ok(H.isSupportGroup({ [3] = 10000, [2] = 10000 }), 'Hawkeye: support and healing group')
ok(not H.isSupportGroup({ [1] = 2000, [3] = 100 }), 'attack and support: an attack')
ok(not H.isSupportGroup({ [2] = 1000 }), 'a heal')
ok(H.isSupportGroup(3), 'a group number')

-- ---------------------------------------------------------------- the Auto setup plan
local function ids(list) local t = {} for i, v in ipairs(list) do t[i] = type(v) == 'table' and v.id or v end return t end
local function has(list, id) for _, v in ipairs(ids(list)) do if v == id then return true end end return false end
local p = H.autoPlan(entries, canCastFor(14, 200))   -- Berserker
ok(has(p.timer, 222), 'Berserker: Red Frenzy in the Timer section')
ok(has(p.timer, 233), 'Berserker: Banner Call in the Timer section')
ok(has(p.timer, 223) == false, 'Berserker: Iron Bellow is not his (Juggernaut line)')
ok(not has(p.timer, 247) and not has(p.support, 247), 'Bloodrage costs health: not set up')
ok(has(p.support, 162), 'Berserker: the Vigil of Clarity in the support section')
ok(has(p.support, 234), 'Berserker: Soulward in the support section')
ok(not has(p.support, 161) and not has(p.support, 179) and not has(p.support, 255), 'only one vigil is set up')
ok(not has(p.support, 254) and not has(p.support, 232), 'no teleport, no dash')
eq(p.support[1], 162, 'the vigil first')
eq(p.support[2], 234, 'then the shield')
local red
for _, r in ipairs(p.timer) do if r.id == 222 then red = r end end
eq(red.words, 'vyr ira cruor', 'timer rule: the words')
eq(red.cooldown, 41, 'timer rule: cooldown 40 s + 1')
local bk
for _, r in ipairs(p.timer) do if r.id == 245 then bk = r end end
p = H.autoPlan(entries, canCastFor(13, 200))       -- Samurai
for _, r in ipairs(p.timer) do if r.id == 245 then bk = r end end
eq(bk and bk.cooldown, 31, 'Bushido Focus: its 30 s effect and 30 s cooldown + 1')
ok(#p.timer >= 3, 'Samurai: at least three timer rules (was 3 at most)')

p = H.autoPlan(entries, canCastFor(22, 200))       -- Bone Lord
ok(has(p.support, 180) and has(p.support, 186) and has(p.support, 187), 'Bone Lord: his minions and the banner')
ok(has(p.support, 192) and has(p.support, 193) and has(p.support, 176), 'Bone Lord: the three summon spells')
ok(#p.support <= H.SUPPORT_MAX, 'Bone Lord: within the section')
p = H.autoPlan(entries, canCastFor(20, 200))       -- Necromancer
ok(has(p.support, 180) and has(p.support, 192) and has(p.support, 193) and has(p.support, 176), 'Necromancer 200: Raise Dead and the three summons')
ok(not has(p.support, 186) and not has(p.support, 187), 'Necromancer: no golem, no banner')
p = H.autoPlan(entries, canCastFor(20, 10))
ok(has(p.support, 192) and not has(p.support, 193) and not has(p.support, 176) and not has(p.support, 180), 'Necromancer 10: only the warrior')
p = H.autoPlan(entries, canCastFor(20, 14))
ok(has(p.support, 192) and has(p.support, 193) and not has(p.support, 176), 'Necromancer 14: warrior and archer')
p = H.autoPlan(entries, canCastFor(10, 200))       -- Illusionist
ok(has(p.support, 211), 'Illusionist: Moonfang Pack')
p = H.autoPlan(entries, canCastFor(1, 200))        -- Mystic
ok(has(p.support, 900), 'a support spell added later is set up by default')
ok(not has(p.support, 901), 'but never an attack spell')
p = H.autoPlan(entries, canCastFor(8, 300))
ok(not has(p.support, 264), 'a 2 h avatar is left out')
p = H.autoPlan(entries, canCastFor(14, 1))
eq(#p.support, 0, 'level 1: nothing to cast')
eq(#p.timer, 0, 'level 1: no timer rule')

-- the limits
local many, mb = {}, {}
for i = 1, 20 do
  many[#many + 1] = { id = 700 + i, name = 'S' .. i, words = 'tor s' .. i, level = 1, mana = 1, group = { [3] = 2000 }, exhaustion = 10000, vocations = { 1 } }
end
for i = 1, 10 do
  H.KINDS[800 + i] = { auto = 'timer', dur = 5 }
  many[#many + 1] = { id = 800 + i, name = 'T' .. i, words = 'vyr t' .. i, level = 1, mana = 1, group = { [3] = 2000 }, exhaustion = 10000, vocations = { 1 } }
end
p = H.autoPlan(many, function() return true end)
eq(#p.support, H.SUPPORT_MAX, 'the support section stops at its limit')
eq(#p.timer, H.TIMER_MAX, 'the timer stops at its limit')
ok(H.TIMER_MAX > 3 and H.SUPPORT_MAX >= 8, 'the limits are above the old 3')
for i = 1, 10 do H.KINDS[800 + i] = nil end

-- ---------------------------------------------------------------- the saved list
local c = H.sanitize(nil)
eq(c.enabled, true, 'default: on')
eq(c.reserve, 20, 'default: reserve 20 %')
eq(#c.slots, 0, 'default: no rows')
c = H.sanitize({ enabled = false, reserve = 33, slots = { { id = 234 }, { id = 234 }, { id = 0 }, 'x', { id = 162, enabled = false } } })
eq(c.enabled, false, 'saved: off')
eq(c.reserve, 20, 'an unknown reserve falls back')
eq(#c.slots, 2, 'twice, empty and wrong rows dropped')
eq(c.slots[2].enabled, false, 'a row can be off')
c = H.sanitize({ reserve = 40, slots = { { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 }, { id = 5 }, { id = 6 }, { id = 7 }, { id = 8 }, { id = 9 } } })
eq(c.reserve, 40, 'reserve 40 kept')
eq(#c.slots, H.SUPPORT_MAX, 'more rows than the section holds are cut')
-- hand-edited config.otml: wrong types and odd numbers fall back
c = H.sanitize({ enabled = 'yes', reserve = '1e9', slots = { { id = 2.5 }, { id = 'abc' }, { id = 1e12 }, { id = '77' } } })
eq(c.enabled, true, 'enabled not a boolean: default')
eq(c.reserve, 20, 'reserve out of the list: default')
eq(#c.slots, 1, 'fraction, text and huge ids dropped')
eq(c.slots[1].id, 77, 'a numeric text id kept')
local m = H.mergeSlots({ { id = 5, enabled = false }, { id = 6 } }, { 6, 7 }, 'add')
eq(#m, 3, 'add: the player\'s rows stay, one new')
eq(m[1].enabled, false, 'add: the player\'s row keeps its switch')
eq(m[3].id, 7, 'add: new below')
m = H.mergeSlots({ { id = 5 } }, { 6, 7 }, 'replace')
eq(#m, 2, 'replace: the plan only')
eq(m[1].id, 6, 'replace: in plan order')
local full = {}
for i = 1, H.SUPPORT_MAX do full[i] = { id = i } end
eq(#H.mergeSlots(full, { 99 }, 'add'), H.SUPPORT_MAX, 'add: no room, nothing lost')

-- ---------------------------------------------------------------- the cycle
local now = 100000
local function world(over)
  local w = { casts = {}, cooldown = {}, bar = nil, blocked = {}, rate = true, attacking = true, channeling = false,
    inPz = false, helperOn = true, online = true, mana = 1000, maxMana = 1000, party = false, summons = {}, cap = 3 }
  for k, v in pairs(over or {}) do w[k] = v end
  w.ctx = function()
    return { now = now, online = w.online, helperOn = w.helperOn, inPz = w.inPz, mana = w.mana, maxMana = w.maxMana,
      attacking = w.attacking, channeling = w.channeling,
      spellOf = function(id) return byId[id] end,
      castable = function(s) return s.level <= 300 end,
      onCooldown = function(s) return (w.cooldown[s.id] or 0) > now end,
      buffActive = function(names)
        if w.bar == nil then return nil end
        for _, n in ipairs(names) do if w.bar[n] then return true end end
        return false
      end,
      blocked = function(s) return w.blocked[s.id] end,
      inParty = function() return w.party end,
      summonCount = function(name)
        if w.summons == false then return nil end
        local own, want = 0, {}
        for _, n in ipairs(type(name) == 'table' and name or { name }) do want[n] = true end
        for _, n in ipairs(w.summons) do if want[n] then own = own + 1 end end
        return #w.summons, own
      end,
      summonCap = function() return w.cap end,
      allowed = function(s) if w.rate then w.casts[#w.casts + 1] = s.id return true end return false end }
  end
  return w
end
local function cfgOf(list, reserve)
  local slots = {}
  for i, id in ipairs(list) do slots[i] = { id = id, enabled = true } end
  return { enabled = true, reserve = reserve or 20, slots = slots }
end

-- a shield with a buff bar: cast when off, not while it shows, again when it ends
local st, w = H.newState(), world({ bar = {} })
local cfg = cfgOf({ 234 })
local s = H.pick(st, cfg, w.ctx())
eq(s and s.id, 234, 'off cooldown, buff not active: cast')
H.noteCast(st, s, now)
now = now + 100
eq(H.pick(st, cfg, w.ctx()), nil, 'just cast: wait for the answer')
eq(st.status[234], 'wait', 'status: wait')
now = now + 3000
w.bar = { ['soulward'] = true }
eq(H.pick(st, cfg, w.ctx()), nil, 'the bar shows the buff: not again')
eq(st.status[234], 'active', 'status: active')
w.bar = {}
w.cooldown[234] = now + 5000
eq(H.pick(st, cfg, w.ctx()), nil, 'buff over but on cooldown: wait for the cooldown')
eq(st.status[234], 'cooldown', 'status: cooldown')
now = now + 6000
s = H.pick(st, cfg, w.ctx())
eq(s and s.id, 234, 'off the cooldown and the buff over: cast again')

-- no buff bar data: the spell's own duration
st, w = H.newState(), world({ bar = nil })
cfg = cfgOf({ 234 })
H.noteCast(st, byId[234], now)
now = now + 5000
eq(H.pick(st, cfg, w.ctx()), nil, 'no bar: 15 s effect still running')
eq(st.status[234], 'active', 'no bar: active by its duration')
now = now + 11000
eq((H.pick(st, cfg, w.ctx()) or {}).id, 234, 'no bar: the effect ran out, cast again')

-- no bar and no duration: not again before RECAST_MIN_MS (owner beta 2026-10-20: "keeps casting nonstop"; it was cast
-- every time it came off cooldown)
st, w = H.newState(), world({ bar = nil })
cfg = cfgOf({ 900 })
H.noteCast(st, byId[900], now)
now = now + 3000
eq(H.pick(st, cfg, w.ctx()), nil, 'unknown duration: not again as soon as it is off cooldown')
eq(st.status[900], 'active', 'status: on (by the recast gap)')
now = now + H.RECAST_MIN_MS
eq((H.pick(st, cfg, w.ctx()) or {}).id, 900, 'unknown duration: again after the recast gap')

-- the bar has data but never shows this spell's effect (a summon, an instant effect, a stock buff named "Spell Buff"):
-- its "not shown" does not count; the duration or the recast gap decide
st, w = H.newState(), world({ bar = {} })
cfg = cfgOf({ 900 })
eq((H.pick(st, cfg, w.ctx()) or {}).id, 900, 'never cast: the first cast goes out')
H.noteCast(st, byId[900], now)
now = now + 10000
eq(H.pick(st, cfg, w.ctx()), nil, 'the bar never showed it: no recast every cooldown')
now = now + H.RECAST_MIN_MS
eq((H.pick(st, cfg, w.ctx()) or {}).id, 900, 'after the recast gap: again')
-- the party buffs (dur 60, the bar calls them "Spell Buff"): their duration
st, w = H.newState(), world({ bar = {}, party = true })
byId[129] = byId[129] or { id = 129, name = 'Enchant Party', words = 'utori mas sio', level = 32, mana = 120, group = { [3] = 2000 }, exhaustion = 2000, vocations = { 1 } }
cfg = cfgOf({ 129 })
H.noteCast(st, byId[129], now)
now = now + 30000
eq(H.pick(st, cfg, w.ctx()), nil, 'a party buff the bar does not name: its 60 s duration')
now = now + 31000
eq((H.pick(st, cfg, w.ctx()) or {}).id, 129, 'after its duration: again')
-- a buff the bar has shown: the bar decides again
st, w = H.newState(), world({ bar = { ['soulward'] = true } })
cfg = cfgOf({ 234 })
eq(H.pick(st, cfg, w.ctx()), nil, 'shown: on')
H.noteCast(st, byId[234], now - 20000)
w.bar = {}
eq((H.pick(st, cfg, w.ctx()) or {}).id, 234, 'shown before, gone now: cast')

-- summons with known creatures (Bone Golem, Wild Bond): a recast only calls them back and heals them
ok(H.info(byId[186]).minions ~= nil and H.info(byId[248]).minions ~= nil, 'Bone Golem and Wild Bond know their creatures')
eq(H.keepCount(H.info(byId[248]), 100), 1, 'Wild Bond keeps 1 companion')
eq(H.keepCount(H.info(byId[248]), 400), 2, 'and 2 from level 400')
st, w = H.newState(), world({ bar = {}, summons = {} })
cfg = cfgOf({ 248 })
local function lvl(ctx, l) ctx.level = l return ctx end
eq((H.pick(st, cfg, lvl(w.ctx(), 150)) or {}).id, 248, 'no companion out: Wild Bond')
H.noteCast(st, byId[248], now)
w.summons = { 'War Wolf' }
now = now + 60000
eq(H.pick(st, cfg, lvl(w.ctx(), 150)), nil, 'the companion is out: no recast every 10 s')
eq(st.status[248], 'have', 'status: already out')
eq((H.pick(st, cfg, lvl(w.ctx(), 450)) or {}).id, 248, 'level 400: room for the second one')
w.summons = {}
eq((H.pick(st, cfg, lvl(w.ctx(), 150)) or {}).id, 248, 'the companion died: Wild Bond again')
st, w = H.newState(), world({ bar = {}, summons = { 'Risen Skeleton', 'Bone Golem' } })
cfg = cfgOf({ 186 })
eq(H.pick(st, cfg, lvl(w.ctx(), 200)), nil, 'the golem is out: no Bone Golem')
w.summons = { 'Risen Skeleton' }
eq((H.pick(st, cfg, lvl(w.ctx(), 200)) or {}).id, 186, 'no golem out: Bone Golem')
w.summons = false
H.noteCast(st, byId[186], now)
now = now + 40000
eq(H.pick(st, cfg, lvl(w.ctx(), 200)), nil, 'no summon count: the recast gap, not every cooldown')

-- the server refuses it again and again (no cooldown answer: ChaosHelperRotation counts the refusals)
st, w = H.newState(), world({ bar = { ['soulward'] = true } })
cfg = cfgOf({ 234 })
local refusals = 0
local function withRefusals(ctx) ctx.refusals = function() return refusals end return ctx end
H.pick(st, cfg, withRefusals(w.ctx()))      -- the bar has shown Soulward: it decides
w.bar = {}
H.noteCast(st, byId[234], now - 5000)
refusals = 2
eq((H.pick(st, cfg, withRefusals(w.ctx())) or {}).id, 234, 'two refusals: the rotation back-off alone')
refusals = 3
eq(H.pick(st, cfg, withRefusals(w.ctx())), nil, 'three refusals in a row: it rests')
eq(st.status[234], 'backoff', 'status: refused, waiting')
now = now + H.REFUSED_HOLD_MS
eq((H.pick(st, cfg, withRefusals(w.ctx())) or {}).id, 234, 'after the rest: one more try')
refusals = 0

-- a vigil is a switch
st, w = H.newState(), world({ bar = nil })
cfg = cfgOf({ 162 })
eq(H.pick(st, cfg, w.ctx()), nil, 'vigil without bar data: never cast (a second cast turns it off)')
eq(st.status[162], 'nobar', 'status: nobar')
w.bar = {}
s = H.pick(st, cfg, w.ctx())
eq(s and s.id, 162, 'vigil with bar data and not active: cast')
H.noteCast(st, s, now)
now = now + 4000
eq(H.pick(st, cfg, w.ctx()), nil, 'vigil: the bar is slow, no second cast within the settle time')
now = now + 3000
w.bar = { ['vigil of clarity'] = true }
eq(H.pick(st, cfg, w.ctx()), nil, 'vigil active: left alone')
-- a vigil the bar has not shown after the cast (refused, or the bar is late): no second cast, which would turn it off
st, w = H.newState(), world({ bar = {} })
cfg = cfgOf({ 162 })
H.noteCast(st, byId[162], now)
now = now + 10000
eq(H.pick(st, cfg, w.ctx()), nil, 'vigil cast, the bar never showed it: no toggling on and off')

-- the player switches the vigil off by hand (player report 2026-10-22: Vigil of Clarity came back right away)
st, w = H.newState(), world({ bar = { ['vigil of clarity'] = true } })
cfg = cfgOf({ 162 })
eq(H.pick(st, cfg, w.ctx()), nil, 'vigil on: left alone')
now = now + 20000
w.bar = {}
eq(H.pick(st, cfg, w.ctx()), nil, 'switched off by the player: not cast again')
eq(st.status[162], 'useroff', 'status: you switched it off')
local unticked = H.takeUserOff(st, cfg)
eq(#unticked, 1, 'the row is unticked')
eq(cfg.slots[1].enabled, false, 'the saved row is off (no recast after a relog)')
eq(#H.takeUserOff(st, cfg), 0, 'unticked once')
now = now + 60000
eq(H.pick(st, cfg, w.ctx()), nil, 'still off a minute later')
eq(st.status[162], 'off', 'status: off')
-- the player switches it on again by hand: the helper keeps it up once more (a ticked row)
cfg.slots[1].enabled = true
w.bar = { ['vigil of clarity'] = true }
eq(H.pick(st, cfg, w.ctx()), nil, 'on again: left alone')
ok(not st.userOff[162], 'switched on by the player: no longer marked')
-- our own cast that the bar shows late is not the player's: on, then the bar lags off within the settle time
st, w = H.newState(), world({ bar = {} })
cfg = cfgOf({ 162 })
s = H.pick(st, cfg, w.ctx())
eq(s and s.id, 162, 'off: cast')
H.noteCast(st, s, now)
w.bar = { ['vigil of clarity'] = true }
now = now + 1000
H.pick(st, cfg, w.ctx())
w.bar = {}
now = now + 1000
H.pick(st, cfg, w.ctx())
ok(not st.userOff[162], 'a flicker within our settle time is not a hand switch')
eq(#H.takeUserOff(st, cfg), 0, 'nothing unticked')
-- the bar is gone (no data) and back: no hand switch read from a missing bar
st, w = H.newState(), world({ bar = { ['vigil of clarity'] = true } })
cfg = cfgOf({ 162 })
H.pick(st, cfg, w.ctx())
w.bar = nil
now = now + 20000
H.pick(st, cfg, w.ctx())
ok(not st.userOff[162], 'no bar data: nothing read')
H.reset(st)
ok(st.userOff and next(st.userOff) == nil, 'reset clears the marks')

-- a vigil that dropped a moment ago is not unticked yet (death drops every buff just before the health packet)
st, w = H.newState(), world({ bar = { ['vigil of clarity'] = true } })
cfg = cfgOf({ 162 })
H.pick(st, cfg, w.ctx())
now = now + 20000
w.bar = {}
H.pick(st, cfg, w.ctx())
eq(#H.takeUserOff(st, cfg, now + 500), 0, 'dropped 0.5 s ago: not unticked yet')
eq(cfg.slots[1].enabled, true, 'the row stays ticked')
H.reset(st) -- the death: the caller resets
eq(#H.takeUserOff(st, cfg, now + 5000), 0, 'after the reset: nothing unticked')
eq(cfg.slots[1].enabled, true, 'the vigil row survives the death')
st, w = H.newState(), world({ bar = { ['vigil of clarity'] = true } })
H.pick(st, cfg, w.ctx())
w.bar = {}
H.pick(st, cfg, w.ctx())
eq(#H.takeUserOff(st, cfg, now + H.USEROFF_CONFIRM_MS), 1, 'switched off 2 s ago, still alive: unticked')

-- the utility spells under their Chaos words (owner 2026-10-22: Lantern and Ghost Rope went into Support)
H.addRenamedWords({ ['utevo vis lux'] = { name = 'Radiant Lantern', words = 'vael zhul lyss' },
  ['exani tera'] = { name = 'Ghost Rope', words = 'ash gor' }, ['utamo vita'] = { name = 'Ward', words = 'tor ael' } })
local lantern = { id = 75, name = 'Radiant Lantern', words = 'vael zhul lyss', group = { [3] = 2000 } }
local rope = { id = 76, name = 'Ghost Rope', words = 'Ash Gor', group = { [3] = 2000 } }
local ward = { id = 44, name = 'Ward of the Mind', words = 'tor ael', group = { [3] = 2000 } }
local okL, whyL = H.eligible(lantern)
ok(not okL and whyL == 'utility', 'Radiant Lantern by its Chaos words: left out')
ok(not H.eligible(rope), 'Ghost Rope (any case): left out')
ok(H.eligible(ward), 'a renamed support spell that is no utility stays')
local spells = { [75] = lantern, [76] = rope, [44] = ward }
-- by name too (owner 2026-10-23: Greater Lantern, Ghost Rope and Lantern still in Support): every stock utility's Chaos
-- name is in NEVER_NAMES, and a saved utility row is never cast
for w in pairs(H.NEVER_STOCK) do
  local e = ChaosSpellNames[w]
  if e then ok(H.NEVER_NAMES[e.name:lower()], 'utility by name: ' .. e.name) end
end
local glantern = { id = 11, name = 'Greater Lantern', words = 'unknown words', group = { [3] = 2000 }, level = 13, mana = 60 }
eq(select(2, H.eligible(glantern)), 'utility', 'Greater Lantern left out by its name alone')
eq(H.why(H.newState(), { enabled = true, reserve = 0, slots = {} }, { id = 11, enabled = true },
  { now = 0, spellOf = function() return glantern end }), 'utility', 'a saved Greater Lantern row is never cast')

local kept, dropped = H.dropUtilities({ { id = 44, enabled = true }, { id = 75, enabled = true }, { id = 76, enabled = false },
  { id = 999, enabled = true } }, function(id) return spells[id] end)
eq(dropped, 2, 'a saved list loses Lantern and Ghost Rope')
eq(#kept .. ':' .. kept[1].id .. ':' .. kept[2].id, '2:44:999', 'the rest stays in order (an unknown id too)')

-- the safeguards
st, w = H.newState(), world({ bar = {}, inPz = true })
cfg = cfgOf({ 234 })
eq(H.pick(st, cfg, w.ctx()), nil, 'protection zone: no cast')
w.inPz = false
w.helperOn = false
eq(H.pick(st, cfg, w.ctx()), nil, 'helper off: no cast')
w.helperOn = true
w.online = false
eq(H.pick(st, cfg, w.ctx()), nil, 'offline: no cast')
w.online = true
cfg.enabled = false
eq(H.pick(st, cfg, w.ctx()), nil, 'section off: no cast')
cfg.enabled = true
w.channeling = true
eq(H.pick(st, cfg, w.ctx()), nil, 'the attack rotation charges a spell: wait')
eq(st.status[234], 'casting', 'status: casting')
w.channeling = false
w.blocked[234] = 'backoff'
eq(H.pick(st, cfg, w.ctx()), nil, 'refused lately: backed off')
eq(st.status[234], 'backoff', 'status: backoff')
w.blocked[234] = nil
w.rate = false
eq(H.pick(st, cfg, w.ctx()), nil, 'rate guard says no')
eq(st.status[234], 'rate', 'status: rate')
w.rate = true
s = H.pick(st, cfg, w.ctx())
eq(s and s.id, 234, 'all clear: cast')
-- mana
w.mana, w.maxMana = 60, 1000    -- Soulward costs 90 (150 until the mana cut of 2026-10-22)
eq(H.pick(st, cfg, w.ctx()), nil, 'not enough mana')
eq(st.status[234], 'mana', 'status: mana')
w.mana = 240                     -- 240 - 90 = 15 % < 20 % reserve
eq(H.pick(st, cfg, w.ctx()), nil, 'the cast would eat the reserve')
eq(st.status[234], 'reserve', 'status: reserve')
cfg.reserve = 10
s = H.pick(st, cfg, w.ctx())
eq(s and s.id, 234, 'reserve 10 %: allowed')
w.mana = 150
cfg.reserve = 0
eq((H.pick(st, cfg, w.ctx()) or {}).id, 234, 'reserve 0: down to the last point')
-- a free spell never waits for mana
w.mana = 0
cfg = cfgOf({ 162 }, 50)
w.bar = {}
eq((H.pick(st, cfg, w.ctx()) or {}).id, 162, 'a spell without mana cost ignores the reserve')

-- fight-only and party spells
st, w = H.newState(), world({ bar = {}, attacking = false })
cfg = cfgOf({ 180 })
eq(H.pick(st, cfg, w.ctx()), nil, 'a summon waits for a fight')
eq(st.status[180], 'nofight', 'status: nofight')
w.attacking = true
s = H.pick(st, cfg, w.ctx())
eq(s and s.id, 180, 'fighting: summon')
H.noteCast(st, s, now)
now = now + 5000
eq(H.pick(st, cfg, w.ctx()), nil, 'the summon is not repeated within its gap')
now = now + 6000
eq((H.pick(st, cfg, w.ctx()) or {}).id, 180, 'after the gap: again')
-- the capped summons (the next one kills the oldest): Raise Dead and the Risen Warrior / Archer / Mage are cast only below the cap
ok(H.info(byId[192]).capped and H.info(byId[193]).capped and H.info(byId[176]).capped and H.info(byId[180]).capped, 'the necromancer summons are capped')
eq(H.info(byId[192]).minion, 'Risen Warrior', 'Raise Bone Warrior counts its Risen Warrior')
eq(H.summonCap(20), 3, 'Necromancer: 3'); eq(H.summonCap(21), 1, 'Lich: 1'); eq(H.summonCap(22, 100), 6, 'Bone Lord: 6')
eq(H.summonCap(22, 400), 7, 'Bone Lord 400: 7'); eq(H.summonCap(4), 3, 'any other class: the default 3')
st, w = H.newState(), world({ bar = {}, summons = {} })
cfg = cfgOf({ 192, 193, 176, 180 })
now = now + 100000
s = H.pick(st, cfg, w.ctx())
eq(s and s.id, 192, 'nothing out: the warrior first')
eq(st.status[193], 'queued', 'the archer is next')
w.summons = { 'Risen Warrior' }
H.noteCast(st, byId[192], now)
now = now + 20000
s = H.pick(st, cfg, w.ctx())
eq(st.status[192], 'have', 'a warrior is out: not another one')
eq(s and s.id, 193, 'then the archer')
w.summons = { 'Risen Warrior', 'Risen Archer' }
H.noteCast(st, s, now)
now = now + 20000
eq((H.pick(st, cfg, w.ctx()) or {}).id, 176, 'then the mage')
w.summons = { 'Risen Warrior', 'Risen Archer', 'Risen Mage' }
H.noteCast(st, byId[176], now)
now = now + 20000
eq(H.pick(st, cfg, w.ctx()), nil, 'three out: nothing is cast (the next summon would kill the oldest)')
eq(st.status[192], 'full', 'status: full'); eq(st.status[180], 'full', 'Raise Dead too')
w.summons = { 'Risen Skeleton', 'Risen Skeleton', 'Risen Archer' }
eq(H.pick(st, cfg, w.ctx()), nil, 'three of any kind: full')
w.summons = { 'Risen Skeleton', 'Risen Skeleton' }
now = now + 20000
s = H.pick(st, cfg, w.ctx())
ok(s ~= nil, 'two out: room for one')
w.cap = 1; w.summons = { 'Lich Shade' }
now = now + 20000
eq(H.pick(st, cfg, w.ctx()), nil, 'a Lich with its shade out casts no summon')
w.cap = 6; w.summons = { 'Risen Skeleton', 'Risen Skeleton', 'Risen Skeleton', 'Risen Skeleton' }
now = now + 20000
ok(H.pick(st, cfg, w.ctx()) ~= nil, 'a Bone Lord with four out has room')
w.summons = false
now = now + 20000
eq(H.pick(st, cfg, w.ctx()), nil, 'no summon count: no blind cast')
eq(st.status[192], 'nocount', 'status: nocount')

st, w = H.newState(), world({ bar = {} })
cfg = cfgOf({ 129 })
byId[129] = byId[129] or { id = 129, name = 'Enchant Party', words = 'utori mas sio', level = 32, mana = 120, group = { [3] = 2000 }, exhaustion = 2000, vocations = { 1 } }
eq(H.pick(st, cfg, w.ctx()), nil, 'a party buff without a party')
eq(st.status[129], 'noparty', 'status: noparty')
w.party = true
eq((H.pick(st, cfg, w.ctx()) or {}).id, 129, 'in a party: cast')

-- order and one cast per turn
st, w = H.newState(), world({ bar = {} })
cfg = cfgOf({ 234, 162 })
s = H.pick(st, cfg, w.ctx())
eq(s and s.id, 234, 'the first row that may go out goes first')
eq(st.status[162], 'queued', 'the next waits its turn')
eq(#w.casts, 1, 'one cast recorded in the rate guard')
cfg.slots[1].enabled = false
s = H.pick(st, cfg, w.ctx())
eq(s and s.id, 162, 'a row that is off is skipped')
eq(st.status[234], 'off', 'status: off')
cfg = cfgOf({ 12345 })
eq(H.pick(st, cfg, w.ctx()), nil, 'an unknown spell id is skipped')
eq(st.status[12345], 'unknown', 'status: unknown')
w.cooldown[162] = now + 1000
cfg = cfgOf({ 162, 234 })
s = H.pick(st, cfg, w.ctx())
eq(s and s.id, 234, 'a row on cooldown does not hold the ones below')

-- stock spell with the bar's own name
st, w = H.newState(), world({ bar = { ['magic shield'] = true } })
cfg = cfgOf({ 44 })
eq(H.pick(st, cfg, w.ctx()), nil, 'Ward of the Mind: the bar names it Magic Shield')
eq(st.status[44], 'active', 'status: active by the bar\'s name')

if fails > 0 then error(fails .. ' failure(s)') end
print('supportspells_test: OK')
