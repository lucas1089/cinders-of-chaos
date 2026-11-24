-- luajit awakelogic_test.lua && lua5.3 awakelogic_test.lua (CI runs it from the repo root, which also lets it hold the data to the server's
-- spell_awakening_config.lua / awakened.csv and the templates to pt_br.lua)
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local A = dofile(here .. 'awakelogic.lua')
dofile(here .. 'awakened_data.lua')
local D = ChaosAwakenedData
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end
local function has(s, part, m) n = n + 1 if not tostring(s):find(part, 1, true) then error((m or '') .. ': "' .. tostring(s) .. '" lacks "' .. part .. '"', 2) end end
local function near(a, b, m) n = n + 1 if math.abs(a - b) > 1e-9 then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

eq(ChaosAwakeLogic, A, 'global')
eq(A.MAX_SLOTS, 3, 'three slots')

-- the state message
local st = A.cleanState({ on = true, v = 1, seals = { 41, 2, 0 }, slots = { 206, 0, 0 }, costs = { { 40, 36, 16 }, { 70, 60, 28 }, { 100, 90, 40 } }, held = 1, bonus = 0.1 })
eq(st.on, true, 'on') eq(st.seals[1], 41, 'Waystone Seals') eq(st.seals[2], 2, 'Rift Seals') eq(st.seals[3], 0, 'Pinnacle Seals')
eq(st.slots[1], 206, 'slot 1') eq(st.slots[2], 0, 'slot 2 free') eq(st.held, 1, 'held counted') eq(st.costs[2][2], 60, 'cost of slot 2')
near(st.bonus, 0.1, 'bonus')
eq(A.cleanState(nil), nil, 'no state') eq(A.cleanState('x'), nil, 'junk state')
eq(A.cleanState({ seals = {} }).on, false, 'no on flag: off')
local junk = A.cleanState({ on = true, seals = { -3, 'x' }, slots = { 'a', -1, 5 }, costs = 'x' })
eq(junk.seals[1], 0, 'a negative count reads as 0') eq(junk.seals[2], 0, 'junk reads as 0') eq(junk.slots[1], 0, 'junk slot') eq(junk.slots[3], 5, 'a slot')
eq(junk.held, 1, 'one held') eq(junk.costs[1][1], 0, 'junk costs read as 0')
eq(A.isOn(nil), false, 'no state: off') eq(A.isOn(st), true, 'on')

-- the answer
local a = A.cleanAnswer({ ok = true, why = 'ok', spell = 206, slot = 1, name = 'Cataclysm of Cinders', namePt = 'Cataclismo de Cinzas', cost = { waystone = 40, rift = 36, pinnacle = 16 } })
eq(a.ok, true, 'ok') eq(a.slot, 1, 'slot') eq(a.name, 'Cataclysm of Cinders', 'name') eq(a.cost[1], 40, 'cost keyed by kind')
local b = A.cleanAnswer({ ok = false, why = 'seals', spell = 206, slot = 1, need = { waystone = 1, rift = 0, pinnacle = 0 } })
eq(b.need[1], 1, 'need') eq(b.ok, false, 'not ok')
eq(A.cleanAnswer(nil), nil, 'junk answer')
local code, good = A.whyCode(a) eq(code, 'ok', 'ok code') eq(good, true, 'good')
for _, why in ipairs(A.WHY_FAIL) do
  code, good = A.whyCode({ ok = false, why = why }) eq(code, why, 'code ' .. why) eq(good, false, 'bad ' .. why)
end
code = A.whyCode({ ok = false, why = 'whatever' }) eq(code, 'other', 'unknown reason')
eq((A.whyCode(nil)), 'other', 'no answer')

-- slots
eq(A.slotOf(st, 206), 1, 'awakened in slot 1') eq(A.slotOf(st, 218), nil, 'not awakened') eq(A.slotOf(nil, 206), nil, 'no state')
eq(A.lowestFree(st), 2, 'the lowest free slot')
eq(A.lowestFree(A.cleanState({ on = true, slots = { 1, 2, 3 } })), nil, 'all taken')
eq(A.lowestFree(A.cleanState({ on = true, slots = { 0, 2, 0 } })), 1, 'a freed slot 1')

-- the data
eq(D.rank, 20, 'rank 20') eq(D.maxSlots, 3, 'three slots') near(D.bonus, 0.1, '+10%')
eq(D.slots[1][1], 40, 'slot 1 Waystone') eq(D.slots[3][3], 40, 'slot 3 Pinnacle')
local count = 0
for id, e in pairs(D.spells) do count = count + 1 end
eq(count, 149, '149 spells')
eq(A.nameOf(D, 206), 'Cataclysm of Cinders', 'English name') eq(A.nameOf(D, 206, true), 'Cataclismo de Cinzas', 'pt-BR name')
eq(A.nameOf(D, 9999), nil, 'no entry') eq(A.nameOf(nil, 206), nil, 'no data')
eq(A.shownName(D, st, 206, false), 'Cataclysm of Cinders', 'the Spellbook shows the awakened name') eq(A.shownName(D, st, 218, false), nil, 'a spell that is not awakened keeps its name')
eq(A.shownName(D, A.cleanState({ on = false, slots = { 206, 0, 0 } }), 206, false), nil, 'switch off: no new name')

-- the check
local data = D
local function chk(over, rank, f1, f2, id)
  local s = A.cleanState({ on = true, seals = { 200, 200, 200 }, slots = { 0, 0, 0 }, costs = D.slots })
  for k, v in pairs(over or {}) do s[k] = v end
  return A.check(s, data, id or 206, rank == nil and 20 or rank, f1 == nil and 1 or f1, f2 == nil and 2 or f2)
end
eq(chk().ok, true, 'open') eq(chk().slot, 1, 'slot 1') eq(chk().cost[1], 40, 'for 40')
eq(chk({ on = false }).why, 'off', 'off')
eq(chk(nil, 20, 1, 1, 9999).why, 'spell', 'no row')
eq(chk(nil, 19).why, 'rank', 'rank 19') eq(chk(nil, 19).rank, 20, 'needs 20')
eq(chk(nil, 20, 0, 1).why, 'forms', 'no Form I') eq(chk(nil, 20, 1, 0).why, 'forms', 'no Form II')
eq(chk({ slots = { 206, 0, 0 } }).why, 'already', 'already awakened')
eq(chk({ slots = { 1, 2, 3 } }).why, 'slot', 'no free slot')
local r = chk({ slots = { 1, 0, 0 }, seals = { 69, 60, 28 } })
eq(r.why, 'seals', 'short of Seals') eq(r.slot, 2, 'slot 2') eq(r.need[1], 1, 'one Waystone Seal short') eq(r.need[2], 0, 'no Rift Seal short')
r = chk({ slots = { 1, 2, 0 } }) eq(r.ok, true, 'slot 3') eq(r.cost[3], 40, 'slot 3 costs 40 Pinnacle Seals')
-- the server's costs are what the UI shows: from the state, not from the data
r = chk({ costs = { { 1, 1, 1 }, { 2, 2, 2 }, { 3, 3, 3 } } }) eq(r.cost[1], 1, 'the state wins')

-- the sentences
local function plainTr(s, ...) return string.format(s, ...) end
local s = A.sentences(D.spells[206], plainTr)
eq(#s, 1, 'Doomtide: one part') has(s[1], 'A ring stays 6 s and pulses 3 times for 40% of the hit.', 'the ring') has(s[1], 'A pulse that hits 3 or more enemies returns 3% mana.', 'with the mana')
s = A.sentences(D.spells[218], plainTr)
eq(#s, 2, 'Final Verdict: two parts') has(s[1], 'a line of 6 sqm', 'the line') has(s[2], 'Marks each enemy it hits for 6 s', 'the mark') has(s[2], '50% harder', 'the crit')
s = A.sentences(D.spells[148], plainTr)
has(s[1], 'Sends 3 rings', 'the rings') has(s[2], 'Each kill in the next 8 s cuts 1 s of its cooldown, at most 5 s.', 'the cut')
s = A.sentences(D.spells[96], plainTr)
has(s[1], 'reflects to every ally within 4 sqm for 50%', 'the reflect') has(s[2], 'shield of 3% of its max health for 4 s', 'the heal shield')
eq(#A.sentences(nil, plainTr), 0, 'no entry') eq(#A.sentences({}, plainTr), 0, 'no parts')
-- a decimal comma writer
local comma = function(v) return (string.format('%.4g', v):gsub('%.', ',')) end
has(A.sentences({ heal = false, parts = { { 'ECHO', { pct = 0.125, delay = 1500 } } } }, plainTr, comma)[1], '1,5 s for 12,5%', 'pt-BR writes the comma')
-- every kind of every spell gives a sentence with no leftover format
local kinds = {}
for id, e in pairs(D.spells) do
  local list = A.sentences(e, plainTr)
  eq(#list, #e.parts, 'one sentence for each part of ' .. id)
  for _, text in ipairs(list) do
    eq(text:find('%%[sd]') == nil, true, 'no format left in ' .. id)
    eq(text:find('nil', 1, true) == nil, true, 'no nil in ' .. id)
  end
  for _, p in ipairs(e.parts) do kinds[p[1]] = true end
end
for _, k in ipairs({ 'PULSE', 'LINE', 'MARK', 'RINGS', 'ECHO', 'SHIELD', 'CDCUT', 'LEECH', 'REFLECT' }) do eq(kinds[k], true, 'the kind ' .. k .. ' is used') end

-- the files hold: the config of the server (when run from the repo root), the templates in pt_br.lua
local function slurp(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local text = f:read('*a')
  f:close()
  return text
end
local cfg = slurp('server/data/scripts/chaos/spell_awakening_config.lua')
if cfg then
  local costs = {}
  for w, r, p in cfg:gmatch('{waystone = (%d+), rift = (%d+), pinnacle = (%d+)}') do costs[#costs + 1] = { tonumber(w), tonumber(r), tonumber(p) } end
  eq(#costs, 3, 'the server has three slots')
  for i = 1, 3 do for k = 1, 3 do eq(D.slots[i][k], costs[i][k], 'slot ' .. i .. ' cost ' .. k .. ' is the server\'s') end end
  near(D.bonus, tonumber(cfg:match('bonus = ([%d.]+)')), 'the bonus is the server\'s')
  local ranks = slurp('server/data/scripts/chaos/spell_ranks_config.lua')
  eq(D.rank, tonumber(ranks:match('maxRank = (%d+)')), 'the rank is the server\'s')
  eq(D.maxSlots, tonumber(cfg:match('maxSlots = (%d+)')), 'the slot count is the server\'s')
  -- the names are awakened.csv's
  local csv = slurp('server/data/spells/awakened.csv')
  local rows = 0
  for line in csv:gmatch('[^\r\n]+') do
    local id, en, pt = line:match('^(%d+),[^,]*,%a+,%a*,%a+,[%d.]+,[%u+]+,[^,]*,([^,]*),([^,]*)$')
    if id then
      rows = rows + 1
      eq(D.spells[tonumber(id)].en, en, 'the English name of ' .. id) eq(D.spells[tonumber(id)].pt, pt, 'the pt-BR name of ' .. id)
    end
  end
  eq(rows, 149, 'awakened.csv rows read')
end
local pt = slurp('client/overlay/modules/client_chaos_locale/pt_br.lua')
if pt then
  for key, template in pairs(A.TEMPLATES) do
    local found = false
    for k in pt:gmatch('%["([^\n]-)"%]%s*=%s*"[^\n]*",') do
      if k == template then found = true break end
    end
    eq(found, true, 'pt_br.lua has the template ' .. key)
  end
end

-- O752: the level gates of the slots and of the spell
do
  local s3 = A.cleanState({ on = true, seals = { 999, 999, 999 }, slots = { 0, 0, 0 }, costs = { { 40, 36, 16 }, { 70, 60, 28 }, { 100, 90, 40 } } })
  local id
  for k in pairs(D.spells or D) do if type(k) == 'number' then id = k break end end
  if id and A.entry(D, id) then
    local c = A.check(s3, D, id, 20, 1, 1, { level = 1799, slot = { 1800, 1950, 2250 }, spell = 0 })
    eq(c.why, 'slotlevel', 'slot 1 under its level') eq(c.level, 1800, 'names the level')
    c = A.check(s3, D, id, 20, 1, 1, { level = 2400, slot = { 1800, 1950, 2250 }, spell = 2500 })
    eq(c.why, 'level', 'the spell under its level') eq(c.level, 2500, 'names it')
    eq(A.check(s3, D, id, 20, 1, 1, { level = 2500, slot = { 1800 }, spell = 2500 }).ok, true, 'at the level')
    eq(A.check(s3, D, id, 20, 1, 1).ok, true, 'no gates given: as before')
  end
  eq(A.cleanAnswer({ ok = false, why = 'slotlevel', slot = 1, level = 1800 }).level, 1800, 'the answer keeps the level')
end

print('awakelogic_test: ' .. n .. ' checks OK')
