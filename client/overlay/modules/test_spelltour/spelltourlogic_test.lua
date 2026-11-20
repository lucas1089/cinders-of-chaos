-- run from the repository root: luajit client/overlay/modules/test_spelltour/spelltourlogic_test.lua  (and lua5.3)
dofile('client/overlay/modules/game_chaosspells/spelldata.lua')
dofile('client/overlay/modules/game_spellranks/forms_data.lua')
dofile('client/overlay/modules/test_spelltour/spelltourlogic.lua')
local CFG = dofile('server/data/scripts/chaos/spell_combos_config.lua')
local L = ChaosSpellTourLogic
local n, bad = 0, 0
local function check(c, what) n = n + 1; if not c then bad = bad + 1; print('FAIL ' .. what) end end
local function env(t) return function(k) return t[k] end end

-- the environment
local base = {CHAOS_SPELLTOUR = '1', CHAOS_LIVE_ACCOUNT = 'a1', CHAOS_LIVE_PASSWORD = 'p w', CHAOS_LIVE_CHARACTER = 'Live Aldric A',
  CHAOS_SPELLTOUR_CLASS = 'Elementalist'}
local function with(extra)
  local t = {}
  for k, v in pairs(base) do t[k] = v end
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end
local cfg = L.parseEnv(env(base))
check(cfg and cfg.account == 'a1' and cfg.password == 'p w' and cfg.character == 'Live Aldric A', 'armed with account, password, character')
check(cfg.class == 'elementalist' and cfg.seconds == 900, 'the class is lower-cased, the default film limit is 900 s')
local c0, why0 = L.parseEnv(env(with({CHAOS_SPELLTOUR = false})))
check(c0 == nil and why0 == 'off', 'no switch: off, whatever else is set')
check(L.parseEnv(env(with({CHAOS_SPELLTOUR = '0'}))) == nil and L.parseEnv(env(with({CHAOS_SPELLTOUR = 'yes'}))) == nil, 'only 1 arms it')
check(select(2, L.parseEnv(env(with({CHAOS_LIVE_PASSWORD = false})))):find('password', 1, true), 'no password: refused with the reason')
check(select(2, L.parseEnv(env(with({CHAOS_SPELLTOUR_CLASS = 'warrior'})))):find('class', 1, true), 'a class that is not a showcase class is refused')
check(L.parseEnv(nil) == nil and L.parseEnv(function() error('boom') end) == nil, 'no getenv or one that throws: off')
check(L.parseEnv(env(with({CHAOS_SPELLTOUR_SECONDS = '5000'}))).seconds == L.MAX_SECONDS, 'the limit stops at the maximum')
check(L.parseEnv(env(with({CHAOS_SPELLTOUR_SECONDS = '2'}))).seconds == L.MIN_SECONDS, 'and at the minimum')
check(L.parseEnv(env(with({CHAOS_SPELLTOUR_SECONDS = '120'}))).seconds == 120, 'a limit in range is kept')
check(L.pickCharacter({'A', 'Live B'}, 'live b') == 2 and L.pickCharacter({'A'}, 'zz') == 1 and L.pickCharacter({}, 'A') == nil, 'character pick')

-- the combo rows by id
local rows = {}
for _, r in ipairs(CFG.rows) do rows[r.id] = r end
for id, name in pairs(L.COMBO_NAMES) do
  check(rows[id] and rows[id].name == name, 'combo name of ' .. id .. ' equals spell_combos_config.lua')
end

-- an element of a spell after the Form picks of the combo's prep (Form II ASCEND:fire changes it)
local function elementOf(spellId, combo)
  local s = L.spell(spellId)
  local el = s and s.element
  for _, p in ipairs(combo.prep or {}) do
    if p.spell == spellId then
      local f = L.form(spellId, p.tier, p.pick)
      local e = f and f.kind:match('^[A-Z]+:(%a+)$')
      if e and e ~= 'weakest' then el = e end
    end
  end
  return el
end
local function has(list, id)
  for _, v in ipairs(list or {}) do if v == id then return true end end
  return false
end

local allKinds, allCombos = {}, {}
local rowCount = 0
for _, key in ipairs(L.CLASS_ORDER) do
  local c = L.CLASSES[key]
  check(c, 'class ' .. key)
  -- every spell used is a spell of the class's vocation, and every Form spell has its four Forms
  local function ofVoc(id)
    local s = L.spell(id)
    if not s then return false end
    for _, v in ipairs(s.vocations) do if v == c.vocation then return true end end
    return false
  end
  for _, id in ipairs(c.forms) do
    check(ofVoc(id), key .. ': Form spell ' .. id .. ' is cast by vocation ' .. c.vocation)
    for tier = 1, 2 do for pick = 1, 2 do check(L.form(id, tier, pick), key .. ': spell ' .. id .. ' has Form ' .. tier .. '/' .. pick) end end
    local s = L.spell(id)
    check(s and s.level <= 1000, key .. ': spell ' .. id .. ' is open at level 1000 (the showcase character)')
  end
  -- the Form spells and the combo spells are disjoint, except the combo's own prep (a Form's element change cannot touch a combo)
  local comboSpells = {}
  for _, combo in ipairs(c.combos) do comboSpells[combo.first], comboSpells[combo.second] = true, true end
  for _, id in ipairs(c.forms) do
    check(not comboSpells[id] or key == 'illusionist' and id == 96, key .. ': Form spell ' .. id .. ' is not a combo spell')
  end
  -- every combo is a row of the config and its spells fit the row
  for _, combo in ipairs(c.combos) do
    local row = rows[combo.id]
    check(row, key .. ': combo ' .. combo.id .. ' is a row of the config')
    check(ofVoc(combo.first) and ofVoc(combo.second), key .. ': combo ' .. combo.id .. ' spells are cast by the class')
    if row then
      rowCount = rowCount + 1
      allCombos[combo.id] = true
      if row.kind == 'reaction' then
        check(elementOf(combo.first, combo) == row.first.element, combo.id .. ': first spell element is ' .. tostring(row.first.element) .. ', got ' .. tostring(elementOf(combo.first, combo)))
        check(elementOf(combo.second, combo) == row.second.element, combo.id .. ': second spell element is ' .. tostring(row.second.element) .. ', got ' .. tostring(elementOf(combo.second, combo)))
      else
        check(has(row.first.spells, combo.first) and has(row.second.spells, combo.second), combo.id .. ': spell ids are the row\'s')
        local a, b = L.spell(combo.first), L.spell(combo.second)
        check(a and b, combo.id .. ': spells exist')
      end
      -- ranks: a class combo opens at classMinRank
      check(L.RANK >= CFG.classMinRank, 'rank 20 opens the class combos')
    end
    for _, p in ipairs(combo.prep or {}) do
      check(L.form(p.spell, p.tier, p.pick), combo.id .. ': prep Form exists')
    end
  end

  -- the timeline
  local list, length = L.timeline(key)
  check(list and #list > 10 and length > 60000, key .. ': a timeline of a few minutes')
  local prevAt, ready, phase, castsOf, ranked = -1e9, false, nil, {}, {}
  local lastCastAt, lastGroupAt = {}, {}
  for i, a in ipairs(list) do
    check(a.at >= prevAt, key .. ': actions in time order at ' .. i)
    prevAt = a.at
    if a['do'] == 'rank' then
      check(a.at < 0, key .. ': a rank is set before the ready line')
      ranked[a.spell] = true
    else
      check(a.at >= 0, key .. ': everything else is after the ready line (' .. a['do'] .. ' at ' .. a.at .. ')')
    end
  end
  -- every spell that is cast has rank 20 set before
  for _, a in ipairs(list) do
    if a['do'] == 'cast' then check(ranked[a.spell], key .. ': spell ' .. a.spell .. ' is ranked before it is cast') end
  end
  check(list[#list]['do'] == 'finish', key .. ': ends with finish')
  -- cooldowns held: a spell is not cast again before its cooldown; the group cooldown between casts too
  local lastAt = {}
  local groupAt = {}
  local picked = {}  -- spell -> {t1, t2}
  local lastPickAt = {}
  for _, a in ipairs(list) do
    if a['do'] == 'cast' then
      local s = L.spell(a.spell)
      if lastAt[a.spell] then check(a.at - lastAt[a.spell] >= s.cooldown, key .. ': ' .. s.name .. ' recast after its cooldown (' .. (a.at - lastAt[a.spell]) .. ' ms)') end
      if groupAt[s.group] then check(a.at - groupAt[s.group] >= s.groupCooldown, key .. ': group cooldown before ' .. s.name .. ' (' .. (a.at - groupAt[s.group]) .. ' ms)') end
      lastAt[a.spell], groupAt[s.group] = a.at, a.at
      castsOf[a.spell] = (castsOf[a.spell] or 0) + 1
    elseif a['do'] == 'pick' then
      -- Form II needs a Form I picked first
      picked[a.spell] = picked[a.spell] or {}
      if a.tier == 2 then check(picked[a.spell][1], key .. ': Form II of ' .. a.spell .. ' after a Form I') end
      picked[a.spell][a.tier] = a.pick
      lastPickAt[a.spell] = a.at
    end
  end
  -- a Form spell is cast five times (none, I A, I B, II A, II B)
  for _, id in ipairs(c.forms) do check(castsOf[id] and castsOf[id] >= 5, key .. ': spell ' .. id .. ' is cast with all five variants, got ' .. tostring(castsOf[id])) end
  -- the picks are in the order none, I A, I B, II A, II B, each before the cast they belong to (the caption names the same Form)
  for idx, a in ipairs(list) do
    if a['do'] == 'caption' and a.caption.kind == 'form' and a.caption.tier > 0 then
      local pk
      for j = idx + 1, #list do
        if list[j]['do'] == 'pick' then pk = list[j] break end
      end
      check(pk and pk.spell == a.caption.spell and pk.tier == a.caption.tier and pk.pick == a.caption.pick, key .. ': the pick after a Form caption is the captioned one')
      local castAt
      for j = idx + 1, #list do
        if list[j]['do'] == 'cast' then castAt = list[j].at break end
      end
      check(pk and castAt and castAt - pk.at >= L.PICK_SETTLE_MS, key .. ': the server answers the pick before the cast')
    end
  end
  -- combos: the second cast within the window, after the first, the first after its caption
  local firstAt = {}
  for _, a in ipairs(list) do
    if a['do'] == 'cast' and a.combo then
      if a.part == 1 then firstAt[a.combo] = a.at
      else
        local d = a.at - firstAt[a.combo]
        check(d >= 2000 and d <= L.COMBO_WINDOW_MS - L.COMBO_MARGIN_MS, key .. ': ' .. a.combo .. ' second cast ' .. d .. ' ms after the first (window ' .. L.COMBO_WINDOW_MS .. ')')
      end
    end
  end
  -- all combos of the class are cast
  for _, combo in ipairs(c.combos) do check(firstAt[combo.id], key .. ': combo ' .. combo.id .. ' is in the timeline') end

  local kinds, list2 = L.shows(key)
  for k in pairs(kinds) do allKinds[k] = true end
  print(('%s: %d actions, %d s, Form kinds %s; combos %s'):format(key, #list, math.floor(length / 1000), (function()
    local t = {} for k in pairs(kinds) do t[#t + 1] = k end table.sort(t) return table.concat(t, ' ') end)(), table.concat(list2, ' ')))
  check(length < 25 * 60000, key .. ': under 25 minutes')
end

-- the three classes together: every element reaction and both kinds of signature combo, and most Form kinds
for _, id in ipairs({'steam_burst', 'thermal_shock', 'overload', 'pyre_of_the_dead', 'mudslide', 'consecrated_ash'}) do
  check(allCombos[id], 'reaction ' .. id .. ' is shown')
end
check(allCombos.pinned_shot and allCombos.echoing_mend, 'a class combo and the heal combo are shown')
local kindCount = 0
for _ in pairs(allKinds) do kindCount = kindCount + 1 end
check(kindCount >= 18, 'at least 18 Form kinds are shown (' .. kindCount .. ')')
for _, k in ipairs({'PIERCE', 'SPLIT', 'DELAY', 'PULL', 'GROUND', 'ECHO', 'OVERCHARGE', 'AFTERMATH', 'TWIN', 'SEEK', 'CASCADE', 'SIPHON', 'CLEANSE', 'PULSE', 'BLOOM', 'SANCTUARY', 'RIPPLE', 'WARD'}) do
  check(allKinds[k], 'Form kind ' .. k .. ' is shown')
end
local asc = false
for k in pairs(allKinds) do if k:find('^ASCEND') then asc = true end end
check(asc, 'an element conversion Form is shown')

-- the captions (a fake tr that marks every key)
local function tr(k) return '[' .. k .. ']' end
local t0 = L.captionText({kind = 'form', spell = 204, tier = 0, pick = 0}, function(k) return k end)
check(t0 == 'Falling Pyre, no Form', 'caption with no Form: ' .. t0)
local t1 = L.captionText({kind = 'form', spell = 204, tier = 1, pick = 2}, function(k) return k end)
check(t1 == 'Falling Pyre, Form I: Delayed Burst', 'caption Form I B: ' .. t1)
local t2 = L.captionText({kind = 'form', spell = 204, tier = 2, pick = 2}, function(k) return k end)
check(t2 == 'Falling Pyre, Form II: Ice Ascension, with Form I: Delayed Burst', 'caption Form II B: ' .. t2)
local t3 = L.captionText({kind = 'combo', combo = 'steam_burst', first = 200, second = 201}, function(k) return k end)
check(t3 == 'Combo Steam Burst: Rime Bloom, then Witchfire Bolt', 'caption of a combo: ' .. t3)
local t4 = L.captionText({kind = 'prep', spell = 216, tier = 2, pick = 2, combo = 'consecrated_ash'}, function(k) return k end)
check(t4 == 'Blessed Earth: Form II, Fire Ascension, for the combo', 'caption of a prep pick: ' .. t4)
check(L.captionText({kind = 'form', spell = 204, tier = 1, pick = 1}, tr):find('%[%%s, Form I: %%s%]') == nil, 'the format key goes through tr, the result is filled')
-- the pt-BR keys exist for every format the captions use
local pt = io.open('client/overlay/modules/client_chaos_locale/pt_br.lua'):read('*a')
for _, key in ipairs({'%s, no Form', '%s, Form I: %s', '%s, Form II: %s, with Form I: %s', '%s: %s, %s, for the combo', 'Combo %s: %s, then %s', 'Form I', 'Form II'}) do
  check(pt:find('["' .. key .. '"] = "', 1, true) ~= nil, 'pt-BR has the key ' .. key)
end

print(string.format('spelltourlogic_test: %d checks, %d failures', n, bad))
if bad > 0 then os.exit(1) end
