-- spelltourlogic.lua: the pure part of the test-only spell showcase tour (test_spelltour, spells-video.yml, O692, server/README.md "Spell
-- showcase video (O692)"). Which environment arms it, the script of each showcase class (the spells whose Forms are shown, the combos), the
-- timeline of timed actions built from it with the real cooldowns of spelldata.lua, and the on-screen captions. No engine calls: the glue
-- (spelltour.lua) runs the actions at their times.
--
-- The three classes cover the Form kinds and every combo of docs/SPELL_UPGRADES.md 4.2 that a class can cast:
--   elementalist  fire, ice, energy and death spells: Steam Burst, Thermal Shock, Overload, Pyre of the Dead
--   deadeye       holy line and the Snare Trap: Pinned Shot (class combo) and Consecrated Ash (fire by Blessed Earth's Fire Ascension, then holy)
--   illusionist   earth, ice and heals: Mudslide and Echoing Mend (heal combo)
-- Plain Lua 5.1 / LuaJIT / 5.3; no globals but ChaosSpellTourLogic (it reads ChaosSpellData and ChaosFormsData when they are loaded).
ChaosSpellTourLogic = {}
local L = ChaosSpellTourLogic

L.ENV_ON = 'CHAOS_SPELLTOUR'
L.ENV_ACCOUNT = 'CHAOS_LIVE_ACCOUNT'
L.ENV_PASSWORD = 'CHAOS_LIVE_PASSWORD'
L.ENV_CHARACTER = 'CHAOS_LIVE_CHARACTER'
L.ENV_CLASS = 'CHAOS_SPELLTOUR_CLASS'      -- elementalist | deadeye | illusionist
L.ENV_SECONDS = 'CHAOS_SPELLTOUR_SECONDS'  -- the longest the film of one class is, from the ready line

L.DEFAULT_SECONDS, L.MIN_SECONDS, L.MAX_SECONDS = 900, 30, 1800
L.OPCODE = 168                 -- ChaosOpcodes.spellRanks: the Forms answer `pick` {spell, tier, pick}
L.RANK = 20                    -- the rank every shown spell is set to (`/spellrank ID 20`): Form I at 10, Form II at 20
L.RANK_SAY = '/spellrank '
L.WINDOW = {width = 1280, height = 720}  -- the window the client fills on the virtual screen of spells_video.sh (an even size)

-- the timeline (ms)
L.RANK_GAP_MS = 800        -- between two staff commands of the set-up
L.GRACE_MS = 2500          -- after the ready line the recording needs a moment to begin
L.CAPTION_LEAD_MS = 1300   -- the caption is up this long before the cast
L.PICK_SETTLE_MS = 900     -- a Form pick is answered by the server before the cast
L.SLACK_MS = 600           -- on top of a cooldown (the server's clocks are its own)
L.AFTER_MS = 2800          -- the effect plays this long before the next caption
L.COMBO_GAP_MS = 2400      -- the second cast of a combo after the first (the group cooldown is 2000 ms, the window of the combo 4000 ms)
L.COMBO_WINDOW_MS = 4000   -- spell_combos_config.lua window.windowMs
L.COMBO_MARGIN_MS = 600    -- the second cast lands at least this far inside the window
L.END_MS = 4000            -- the last effect stays on screen

-- Forms shown per class (spells that are not part of a combo, so a Form's element change cannot touch one) and the combos. A combo is
-- {id = row of spell_combos_config.lua, first, second spell ids, prep = {{spell, tier, pick}} Form picks of the combo's first spell}.
L.CLASSES = {
  elementalist = {
    vocation = 5, title = 'Elementalist',
    forms = {204, 205, 206},   -- Falling Pyre, Frozen Crypt, Doomtide
    combos = {
      {id = 'steam_burst', first = 200, second = 201},      -- Rime Bloom (ice), then Witchfire Bolt (fire)
      {id = 'thermal_shock', first = 201, second = 200},    -- fire, then ice
      {id = 'overload', first = 202, second = 201},         -- Forked Storm (energy), then fire
      {id = 'pyre_of_the_dead', first = 203, second = 201}, -- Crimson Covenant (death), then fire
    },
  },
  deadeye = {
    vocation = 7, title = 'Deadeye',
    forms = {214, 149, 218},   -- Dawnpiercer, Moonshard Rain, Final Verdict
    combos = {
      -- Blessed Earth with Form I Gravity Pull and Form II Fire Ascension is a fire hit, then Sunspear is holy
      {id = 'consecrated_ash', first = 216, second = 19, prep = {{spell = 216, tier = 1, pick = 2}, {spell = 216, tier = 2, pick = 2}}},
      {id = 'pinned_shot', first = 99, second = 19},        -- Snare Trap, then Sunspear (class combo)
    },
  },
  illusionist = {
    vocation = 10, title = 'Illusionist',
    forms = {96, 208, 228, 24},  -- Mirror Mend, Purifying Wellspring, Shattered Psyche, Phantom Needles
    combos = {
      {id = 'mudslide', first = 213, second = 38},          -- Primordial Squall (earth), then Mirror Shards (ice)
      {id = 'echoing_mend', first = 96, second = 97},       -- Mirror Mend, then Lucid Reverie (heal combo)
    },
  },
}
L.CLASS_ORDER = {'elementalist', 'deadeye', 'illusionist'}

local function trim(s)
  return (tostring(s):gsub('^%s+', ''):gsub('%s+$', ''))
end

-- config from the environment; nil, reason when it is not armed or incomplete. getenv is os.getenv or a fake.
function L.parseEnv(getenv)
  if type(getenv) ~= 'function' then return nil, 'no environment' end
  local function get(name)
    local ok, v = pcall(getenv, name)
    if ok and type(v) == 'string' and v ~= '' then return v end
    return nil
  end
  if get(L.ENV_ON) ~= '1' then return nil, 'off' end
  local account, password = get(L.ENV_ACCOUNT), get(L.ENV_PASSWORD)
  if not account or not password then return nil, 'the environment names no account and password' end
  local class = get(L.ENV_CLASS) and trim(get(L.ENV_CLASS)):lower()
  if not class or not L.CLASSES[class] then return nil, 'the environment names no showcase class (elementalist, deadeye or illusionist)' end
  local seconds = tonumber(get(L.ENV_SECONDS))
  seconds = seconds and math.max(L.MIN_SECONDS, math.min(L.MAX_SECONDS, math.floor(seconds))) or L.DEFAULT_SECONDS
  return {account = account, password = password, character = get(L.ENV_CHARACTER), class = class, seconds = seconds}
end

-- the index of the character to enter: the one named character, else the first; nil when the list is empty
function L.pickCharacter(names, wanted)
  if type(names) ~= 'table' or #names == 0 then return nil end
  if wanted then
    for i, n in ipairs(names) do
      if tostring(n):lower() == tostring(wanted):lower() then return i end
    end
  end
  return 1
end

-- ---------------------------------------------------------------- the data (spelldata.lua, forms_data.lua)
local spellIndex, indexedFrom
function L.spell(id)
  local data = rawget(_G, 'ChaosSpellData')
  if type(data) ~= 'table' then return nil end
  if indexedFrom ~= data then
    spellIndex, indexedFrom = {}, data
    for _, s in ipairs(data) do spellIndex[s.id] = s end
  end
  return spellIndex[id]
end

-- the Form of a spell: {kind, name} of tier 1 / 2, pick 1 / 2 (forms_data.lua), nil when it has none
function L.form(spellId, tier, pick)
  local fd = rawget(_G, 'ChaosFormsData')
  local row = fd and fd.spells and fd.spells[spellId]
  local f = row and row.forms and row.forms[tier] and row.forms[tier][pick]
  if not f then return nil end
  return {kind = f[1], name = f[2]}
end

-- the spell ids the set-up gives rank 20: every shown spell, the combos' two spells
function L.rankedSpells(class)
  local c = L.CLASSES[class]
  local out, seen = {}, {}
  local function add(id)
    if id and not seen[id] then seen[id] = true; out[#out + 1] = id end
  end
  for _, id in ipairs(c.forms) do add(id) end
  for _, combo in ipairs(c.combos) do add(combo.first); add(combo.second) end
  return out
end

-- the Form variants of a spell in the order they are picked: none, I A, I B (a change of the last pick is free for 30 minutes), II A, II B
-- (Form II needs a Form I; the first pick of a tier is free). Form II is shown with the Form I that is picked last (I B).
L.VARIANTS = {{tier = 0, pick = 0}, {tier = 1, pick = 1}, {tier = 1, pick = 2}, {tier = 2, pick = 1}, {tier = 2, pick = 2}}
L.FORM1_WITH_FORM2 = 2

-- ---------------------------------------------------------------- the timeline
-- readiness of the cooldowns: S = {ready = {id -> ms}, group = {group -> ms}}
local function readyAt(S, id)
  local s = L.spell(id)
  local t = S.ready[id] or 0
  if s then t = math.max(t, S.group[s.group or 0] or 0) end
  return t
end

local function cast(S, id, at)
  local s = L.spell(id)
  if not s then return end
  S.ready[id] = at + (s.cooldown or 0) + L.SLACK_MS
  local g = s.group or 0
  S.group[g] = math.max(S.group[g] or 0, at + (s.groupCooldown or 2000) + L.SLACK_MS)
end

-- the actions of one class: {at = ms from the ready line, ['do'] = 'rank' | 'pick' | 'caption' | 'cast' | 'phase' | 'finish', ...}. The
-- set-up actions (`rank`) come before the ready line and have negative times. Returns the list and the length (ms from the ready line).
function L.timeline(class)
  local c = L.CLASSES[class]
  if not c then return nil, 'unknown class ' .. tostring(class) end
  local out = {}
  local function add(a) out[#out + 1] = a; return a end
  -- the set-up: ranks, before the ready line
  local ranked = L.rankedSpells(class)
  local t = -(#ranked * L.RANK_GAP_MS + L.RANK_GAP_MS)
  for _, id in ipairs(ranked) do
    add({at = t, ['do'] = 'rank', spell = id})
    t = t + L.RANK_GAP_MS
  end
  t = L.GRACE_MS
  local S = {ready = {}, group = {}}

  -- one cast with its caption: the caption comes CAPTION_LEAD_MS before it, the pick (when there is one) with the caption
  local function castOne(id, caption, pick)
    local at = math.max(t + L.CAPTION_LEAD_MS, readyAt(S, id))
    if pick then at = math.max(at, t + L.PICK_SETTLE_MS + 300) end
    add({at = at - L.CAPTION_LEAD_MS, ['do'] = 'caption', caption = caption})
    if pick then add({at = at - L.CAPTION_LEAD_MS + 100, ['do'] = 'pick', spell = pick.spell, tier = pick.tier, pick = pick.pick}) end
    add({at = at, ['do'] = 'cast', spell = id})
    cast(S, id, at)
    t = at + L.AFTER_MS
  end

  add({at = t, ['do'] = 'phase', name = 'forms'})
  for _, id in ipairs(c.forms) do
    for _, v in ipairs(L.VARIANTS) do
      castOne(id, {kind = 'form', spell = id, tier = v.tier, pick = v.pick}, v.tier > 0 and {spell = id, tier = v.tier, pick = v.pick} or nil)
    end
  end

  t = t + 1000
  add({at = t, ['do'] = 'phase', name = 'combos'})
  for _, combo in ipairs(c.combos) do
    for _, p in ipairs(combo.prep or {}) do
      -- a Form pick the combo needs (its own caption, no cast)
      add({at = t, ['do'] = 'caption', caption = {kind = 'prep', spell = p.spell, tier = p.tier, pick = p.pick, combo = combo.id}})
      add({at = t + 100, ['do'] = 'pick', spell = p.spell, tier = p.tier, pick = p.pick})
      t = t + L.PICK_SETTLE_MS + 700
    end
    -- the first cast; the second follows after COMBO_GAP_MS and must be ready by then (else the first waits)
    local a = math.max(t + L.CAPTION_LEAD_MS, readyAt(S, combo.first))
    local b = math.max(a + L.COMBO_GAP_MS, readyAt(S, combo.second))
    local latest = L.COMBO_WINDOW_MS - L.COMBO_MARGIN_MS
    if b - a > latest then
      a = b - latest
    end
    add({at = a - L.CAPTION_LEAD_MS, ['do'] = 'caption', caption = {kind = 'combo', combo = combo.id, first = combo.first, second = combo.second}})
    add({at = a, ['do'] = 'cast', spell = combo.first, combo = combo.id, part = 1})
    cast(S, combo.first, a)
    add({at = b, ['do'] = 'cast', spell = combo.second, combo = combo.id, part = 2})
    cast(S, combo.second, b)
    t = b + L.AFTER_MS
  end

  t = t + L.END_MS
  add({at = t, ['do'] = 'finish'})
  -- a stable order: by time, then as added
  for i, a in ipairs(out) do a.n = i end
  table.sort(out, function(x, y)
    if x.at ~= y.at then return x.at < y.at end
    return x.n < y.n
  end)
  return out, t
end

-- ---------------------------------------------------------------- the captions (pt-BR through tr(), spell names stay as the game writes them)
-- cap = {kind = 'form', spell, tier 0 | 1 | 2, pick} | {kind = 'prep', spell, tier, pick, combo} | {kind = 'combo', combo, first, second}
-- translate = tr or a fake. Returns the text.
function L.captionText(cap, translate)
  local tr = translate or function(k) return k end
  local function name(id)
    local s = L.spell(id)
    return s and s.name or ('#' .. tostring(id))
  end
  local function formName(spell, tier, pick)
    local f = L.form(spell, tier, pick)
    return f and tr(f.name) or '?'
  end
  if cap.kind == 'form' then
    if cap.tier == 0 then return string.format(tr('%s, no Form'), name(cap.spell)) end
    if cap.tier == 1 then
      return string.format(tr('%s, Form I: %s'), name(cap.spell), formName(cap.spell, 1, cap.pick))
    end
    return string.format(tr('%s, Form II: %s, with Form I: %s'), name(cap.spell), formName(cap.spell, 2, cap.pick),
      formName(cap.spell, 1, L.FORM1_WITH_FORM2))
  end
  if cap.kind == 'prep' then
    local tierText = cap.tier == 2 and tr('Form II') or tr('Form I')
    return string.format(tr('%s: %s, %s, for the combo'), name(cap.spell), tierText, formName(cap.spell, cap.tier, cap.pick))
  end
  if cap.kind == 'combo' then
    return string.format(tr('Combo %s: %s, then %s'), tr(L.comboName(cap.combo)), name(cap.first), name(cap.second))
  end
  return ''
end

-- the English name of a combo row (the key of its pt-BR text); spell_combos_config.lua `name`, kept equal by the test
L.COMBO_NAMES = {
  steam_burst = 'Steam Burst', thermal_shock = 'Thermal Shock', overload = 'Overload', pyre_of_the_dead = 'Pyre of the Dead',
  mudslide = 'Mudslide', consecrated_ash = 'Consecrated Ash', pinned_shot = 'Pinned Shot', meat_grinder = 'Meat Grinder',
  anvil_chain = 'Anvil Chain', backstab = 'Backstab', rotting_curse = 'Rotting Curse', psychic_shatter = 'Psychic Shatter',
  echoing_mend = 'Echoing Mend',
}
function L.comboName(id)
  return L.COMBO_NAMES[id] or tostring(id)
end

-- what a class shows: the set of Form kinds and the list of combo ids (a summary for the log and the report)
function L.shows(class)
  local c = L.CLASSES[class]
  local kinds, list = {}, {}
  for _, id in ipairs(c.forms) do
    for tier = 1, 2 do
      for pick = 1, 2 do
        local f = L.form(id, tier, pick)
        if f then kinds[f.kind] = true end
      end
    end
  end
  for _, combo in ipairs(c.combos) do list[#list + 1] = combo.id end
  return kinds, list
end

return L
