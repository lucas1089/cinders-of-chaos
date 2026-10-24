-- ChaosHelperSpells: which spells the helper offers and casts (pure Lua: no engine calls; tests: helper_spells_test.lua).
-- The helper's pickers (healing, shooter, mana training, haste) and its drag-and-drop list the spells of the client's table
-- (SpellInfo.Default after game_chaosspells: the Chaos spells, the stock spells under their Chaos names and words). A spell
-- is offered when
--   * the server has it (not notOnServer) and it has words to say;
--   * the character's class lists it (the server vocation ids 1 to 25, ChaosSpellFix.allowsVocation, which also accepts the
--     folded id of the stock entries) and the level is reached;
--   * it is not a utility the helper never casts by itself: the lanterns, the ghost rope, the town portal, the dash and the
--     toggles (ChaosHelperSupport.NEVER_IDS / NEVER_WORDS / NEVER_NAMES, game_helpersupport; the vigils stay in the Support tab);
--   * it needs no typed name (a parameter: the rune and party spells of the stock table);
--   * its kind fits the picker: an attack spell (attack or special group) for the shooter, a healing spell (group 2, no
--     target) for the healing and the mana training rows, the haste spells for Auto Haste.
-- There are no conjure spells or runes: the server removed them, and the stock conjure entries are not offered.
ChaosHelperSpells = ChaosHelperSpells or {}
local S = ChaosHelperSpells

S.HASTE_IDS = { 39, 6 }              -- Strong Haste, Haste (the strongest first; ChaosAutoSetup.HASTES)
S.TOGGLE_IDS = { [179] = true, [255] = true, [161] = true, [162] = true } -- the vigils: the Support tab
S.DASH_IDS = { [254] = true, [232] = true }                               -- Town Portal, Flickerdash
S.MAX_LEVEL = 100000

local function lower(s)
  return tostring(s or ''):lower()
end

-- the spell's groups as a sorted list: the client table's {[group] = cooldown} or a number or a list
function S.groupList(spell)
  local out = {}
  local g = type(spell) == 'table' and spell.group or nil
  if type(g) == 'table' then
    for k, v in pairs(g) do
      if type(k) == 'number' and v ~= false then
        out[#out + 1] = k
      elseif type(v) == 'number' and type(k) == 'number' then
        out[#out + 1] = v
      end
    end
  elseif type(g) == 'number' then
    out[1] = g
  end
  table.sort(out)
  return out
end

-- the cooldown channel of a spell (the server's: heal, attack, support): healing (2) -> heal, attack (1) or special (4) ->
-- attack, anything else -> support. The same rule as ChaosHelperTimers.castChannel (tested against it when loaded).
function S.channel(spell)
  local has = {}
  for _, g in ipairs(S.groupList(spell)) do has[g] = true end
  if has[2] then return 'heal' end
  if has[1] or has[4] then return 'attack' end
  return 'support'
end

-- the helper never casts this by itself: a utility (lanterns, rope, town portal, ...), a dash or a toggle
function S.isUtility(spell)
  if type(spell) ~= 'table' then return false end
  if S.DASH_IDS[spell.id] or S.TOGGLE_IDS[spell.id] then return true end
  local support = rawget(_G, 'ChaosHelperSupport')
  if support and support.isUtility then return support.isUtility(spell) end
  return false
end

-- a spell that needs a target to be cast on (a creature in range) rather than a place or itself
function S.targeted(spell)
  return type(spell) == 'table' and (tonumber(spell.range) or 0) > 0 or false
end

-- does the class list the spell (server vocation id or its folded id)
function S.classOk(spell, vocation, translate)
  local fix = rawget(_G, 'ChaosSpellFix')
  if fix and fix.allowsVocation then
    return fix.allowsVocation(spell, vocation, translate)
  end
  if type(spell) ~= 'table' or spell.notOnServer then return false end
  local list = spell.vocations
  if type(list) ~= 'table' then return true end
  local folded = translate and translate(vocation) or nil
  for _, v in ipairs(list) do
    if v == vocation or (folded ~= nil and folded ~= 0 and v == folded) then return true end
  end
  return false
end

-- the common rules. ctx = { vocation = server vocation id, level = n, translate = fn, known = fn(id) -> bool (optional:
-- the character has learnt it, allowParameter: a spell that takes a typed name is fine (the heal-others spells of
-- helper_ally.lua, which put a cleaned name after the words)) }. Returns true, or false and the reason.
function S.castable(spell, ctx)
  ctx = ctx or {}
  if type(spell) ~= 'table' or type(spell.id) ~= 'number' or spell.id <= 0 then return false, 'entry' end
  if spell.notOnServer then return false, 'server' end
  if type(spell.words) ~= 'string' or spell.words == '' then return false, 'words' end
  if spell.type ~= nil and spell.type ~= 'Instant' then return false, 'type' end -- no runes, no conjuring
  if spell.parameter and not ctx.allowParameter then return false, 'parameter' end
  if S.isUtility(spell) then return false, 'utility' end
  if not S.classOk(spell, ctx.vocation, ctx.translate) then return false, 'class' end
  if (tonumber(spell.level) or 0) > (tonumber(ctx.level) or 0) then return false, 'level' end
  if ctx.known and not ctx.known(spell.id) then return false, 'unknown' end
  return true
end

-- may the spell stand in a picker of this kind: 'attack' | 'heal' | 'training' | 'haste'
function S.eligible(kind, spell, ctx)
  local ok, why = S.castable(spell, ctx)
  if not ok then return false, why end
  if kind == 'attack' then
    if S.channel(spell) ~= 'attack' then return false, 'kind' end
    return true
  elseif kind == 'heal' then
    if S.channel(spell) ~= 'heal' or spell.needTarget then return false, 'kind' end
    return true
  elseif kind == 'training' then
    -- a spell cast to use mana: any self spell of the healing or support channel that costs mana and needs no target
    if spell.needTarget or S.targeted(spell) or S.channel(spell) == 'attack' then return false, 'kind' end
    if (tonumber(spell.mana) or 0) <= 0 and not spell.manaPercent then return false, 'kind' end
    for _, id in ipairs(S.HASTE_IDS) do
      if id == spell.id then return false, 'kind' end
    end
    return true
  elseif kind == 'haste' then
    for _, id in ipairs(S.HASTE_IDS) do
      if id == spell.id then return true end
    end
    return false, 'kind'
  end
  return false, 'kind'
end

-- the offered spells of a kind from the client's table (a map name -> entry, or a list), sorted by name:
-- { { name, spell }, ... }
function S.list(kind, spells, ctx)
  local out = {}
  local seen = {}
  local function add(name, spell)
    -- the table's key is the name of an entry that has none (the utility check by name needs it)
    if type(spell) == 'table' and type(spell.name) ~= 'string' and type(name) == 'string' then spell.name = name end
    if type(spell) == 'table' and not seen[spell.id] and S.eligible(kind, spell, ctx) then
      seen[spell.id] = true
      out[#out + 1] = { name = spell.name or name, spell = spell }
    end
  end
  for k, v in pairs(spells or {}) do
    if type(k) == 'number' then add(v and v.name, v) else add(k, v) end
  end
  table.sort(out, function(a, b)
    local an, bn = lower(a.name), lower(b.name)
    if an ~= bn then return an < bn end
    return a.spell.id < b.spell.id
  end)
  return out
end

-- the strongest haste the character can cast (S.HASTE_IDS order); spellOf(id) -> entry
function S.bestHaste(spellOf, ctx)
  for _, id in ipairs(S.HASTE_IDS) do
    local s = spellOf(id)
    if s and S.eligible('haste', s, ctx) then return id end
  end
  return nil
end

-- a spell's own cooldown in ms (the longest of its own and its groups'), for the "ready" check against a spell the
-- server has not answered yet
function S.cooldownMs(spell)
  local own = tonumber(spell.exhaustion) or tonumber(spell.cooldown) or 0
  return own
end

return ChaosHelperSpells
