-- The helper's "Auto rotation" button: the selection logic (pure Lua: no engine calls; tests: autorotation_test.lua).
-- The glue (the button, the dialogs, filling the helper) is autorotation_ui.lua.
--
-- Owner, 2026-10-14: "Faça todas as classes terem até 5 magias na rotação e nunca ficarem 2s sem uma" and "Coloque no
-- helper também um botão para configuração automática de rotação". server/tools/rotation_sim.py simulates every
-- class and writes autorotation_data.lua (ChaosAutoRotationData): for each class, at every level where it gets a new
-- attack spell, the best rotation of at most 5 attack spells (priority order, longest time between two casts <= 2 s)
-- and the class's heals. Here a character's class, level and the spells it can cast pick its rotation; a spell it
-- cannot cast is replaced by the next one of an earlier preset, and the gap of the result is simulated again.

ChaosAutoRotation = ChaosAutoRotation or {}
local A = ChaosAutoRotation

A.MAX_SPELLS = 5
A.GAP_LIMIT = 2.0
A.HORIZON = 120          -- seconds the gap check simulates
A.HEAL_PERCENTS = { 45, 65, 85 } -- the healing tab's slots: the strongest heal at the lowest health
A.MARKER = 'chaosAutoRotation'  -- the shooter profile key that remembers the spell ids the button set last

local function data()
  return ChaosAutoRotationData
end

function A.classOf(vocId)
  local d = data()
  return d and d.classes and d.classes[vocId] or nil
end

-- the preset of the highest level at or below `level`, and its index
function A.presetFor(vocId, level)
  local c = A.classOf(vocId)
  if not c then
    return nil
  end
  local best, index = nil, nil
  for i, p in ipairs(c.presets) do
    if p.level <= (level or 0) then
      best, index = p, i
    end
  end
  return best, index
end

-- the longest time between two casts of a priority rotation (ids in priority order), in seconds: the spell
-- cooldowns, the cast spell's group cooldown on the attack group, secondary groups and cast times, from a fresh start.
-- The Monk finishers' chi is not counted (Ashen Fist, cooldown 2 s, is in every Monk set).
function A.gap(ids, spells)
  spells = spells or (data() and data().spells) or {}
  local list = {}
  for _, id in ipairs(ids) do
    local s = spells[id]
    if s then
      list[#list + 1] = s
    end
  end
  if #list == 0 then
    return A.HORIZON
  end
  local ready, group = {}, { attack = 0 }
  for i = 1, #list do
    ready[i] = 0
  end
  local t, last, gap = 0, nil, 0
  while t < A.HORIZON do
    local pick, soonest = nil, nil
    for i, s in ipairs(list) do
      local at = math.max(ready[i], group.attack, (s.secondaryGroup ~= '' and group[s.secondaryGroup]) or 0)
      if at <= t + 1e-9 then
        pick = i
        break
      end
      soonest = soonest and math.min(soonest, at) or at
    end
    if not pick then
      t = soonest or A.HORIZON
    else
      local s = list[pick]
      if last and t - last > gap then
        gap = t - last
      end
      last = t
      ready[pick] = t + s.cooldown / 1000
      local hold = math.max(s.groupCooldown, s.cast or 0) / 1000
      group.attack = t + hold
      if s.secondaryGroup ~= '' then
        group[s.secondaryGroup] = t + s.secondaryCooldown / 1000
      end
      t = t + math.max(hold, 0.001)
    end
  end
  return math.floor(gap * 100 + 0.5) / 100
end

-- the rotation for a character: vocId (the server's), level, canCast(id) -> true when the character can cast the spell
-- (knows it, its class and level). Returns { level, ids, creatures, gap, changed } or nil, reason.
function A.select(vocId, level, canCast)
  local c = A.classOf(vocId)
  if not c then
    return nil, 'class'
  end
  local preset, index = A.presetFor(vocId, level)
  if not preset then
    return nil, 'level'
  end
  canCast = canCast or function() return true end
  local ids, creatures, seen, changed = {}, {}, {}, false
  for i, id in ipairs(preset.spells) do
    if canCast(id) then
      ids[#ids + 1] = id
      creatures[#creatures + 1] = preset.creatures and preset.creatures[i] or 1
      seen[id] = true
    else
      changed = true
    end
  end
  -- a spell the character cannot cast: fill from the earlier presets (newest first), one monster each
  for j = index - 1, 1, -1 do
    if #ids >= A.MAX_SPELLS or not changed then
      break
    end
    for _, id in ipairs(c.presets[j].spells) do
      if #ids < A.MAX_SPELLS and not seen[id] and canCast(id) then
        ids[#ids + 1] = id
        creatures[#creatures + 1] = 1
        seen[id] = true
      end
    end
  end
  if #ids == 0 then
    return nil, 'spells'
  end
  local gap = changed and A.gap(ids) or preset.gap
  if changed then
    -- an area spell may not wait for 2 monsters any more: the rest has to keep the gap on a lone target
    for i = 1, #creatures do
      creatures[i] = 1
    end
  end
  return { level = preset.level, ids = ids, creatures = creatures, gap = gap, changed = changed }
end

-- the helper's shooter rules (magic_shooter_panel.lua getFormData) of a selection; nameOf(id), wordsOf(id)
function A.rules(sel, nameOf, wordsOf)
  local out = {}
  for i, id in ipairs(sel.ids) do
    out[#out + 1] = {
      type = 'spell', spellId = id, itemId = 0, name = nameOf and nameOf(id) or tostring(id),
      words = wordsOf and wordsOf(id) or '', manaPercent = 0, healthPercent = 0, extraDelay = 0,
      creatures = sel.creatures[i] or 1, harmonyThreshold = 0, selfCast = false, castIfTrapped = false,
      countLowerThan = false, extendedArea = false, extendedArea2 = false, forceOnTarget = false,
      rangedMonsterNames = '', hpMin = 0, hpMax = 0, enabled = true
    }
  end
  return out
end

-- the spell ids of a rule list (spells only, in order)
function A.ruleIds(rules)
  local ids = {}
  for _, r in ipairs(rules or {}) do
    if r.type == 'spell' and r.spellId and r.spellId > 0 then
      ids[#ids + 1] = r.spellId
    end
  end
  return ids
end

local function same(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end
A.same = same

-- a rotation the player set up: rules that are not empty and not the set this button wrote last (marker)
function A.isCustom(rules, marker)
  if not rules or #rules == 0 then
    return false
  end
  for _, r in ipairs(rules) do
    if r.type ~= 'spell' then
      return true
    end
  end
  return not (type(marker) == 'table' and same(A.ruleIds(rules), marker))
end

-- the healing tab's slots for the class: up to 3 heals it can cast, the strongest (highest level) at the lowest health
function A.heals(vocId, level, canCast)
  local c = A.classOf(vocId)
  local out = {}
  for _, h in ipairs(c and c.heals or {}) do
    if #out < #A.HEAL_PERCENTS and h.level <= (level or 0) and (not canCast or canCast(h.id)) then
      out[#out + 1] = { id = h.id, percent = A.HEAL_PERCENTS[#out + 1] }
    end
  end
  return out
end

function A.healingEmpty(slots)
  for _, s in ipairs(slots or {}) do
    if s.id and s.id ~= 0 then
      return false
    end
  end
  return true
end

-- "Rotation set: A > B > C (max gap 2.0 s)"
function A.message(sel, nameOf)
  local names = {}
  for _, id in ipairs(sel.ids) do
    names[#names + 1] = nameOf and nameOf(id) or tostring(id)
  end
  return string.format('Rotation set: %s (max gap %.1f s)', table.concat(names, ' > '), sel.gap)
end
