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

-- ids with the area spells first, then the others, each group in its order; creatures follow their spell.
-- Returns ids, creatures, moved (true when the order changed)
function A.areaFirst(ids, creatures, spells)
  spells = spells or (data() and data().spells) or {}
  local outIds, outCreatures, rest, restCreatures = {}, {}, {}, {}
  for i, id in ipairs(ids) do
    if spells[id] and spells[id].area then
      outIds[#outIds + 1] = id
      outCreatures[#outCreatures + 1] = creatures[i]
    else
      rest[#rest + 1] = id
      restCreatures[#restCreatures + 1] = creatures[i]
    end
  end
  for i, id in ipairs(rest) do
    outIds[#outIds + 1] = id
    outCreatures[#outCreatures + 1] = restCreatures[i]
  end
  local moved = false
  for i = 1, #ids do
    if ids[i] ~= outIds[i] then moved = true break end
  end
  return outIds, outCreatures, moved
end

-- the rotation for a character: vocId (the server's), level, canCast(id) -> true when the character can cast the spell
-- (knows it, its class and level). Returns { level, ids, creatures, gap, changed } or nil, reason.
function A.select(vocId, level, canCast, opts)
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
  -- The simulator keeps the smallest set that holds the 2 s rhythm (one spell from level 8 to 11 for a Mystic),
  -- so the button wrote a single rule. Top it up to MAX_SPELLS with the other spells the character can cast, below
  -- the preset's: earlier presets newest first, then the later ones. Those only fire while the ones above wait;
  -- an area spell among them waits for 2 monsters (when the preset itself is complete).
  -- opts.topUp == false: the preset alone (the level-up check only looks for new spells, it never tops up)
  local spells = (data() and data().spells) or {}
  local order = {}
  if not (opts and opts.topUp == false) then
    for j = index - 1, 1, -1 do order[#order + 1] = j end
    for j = index + 1, #c.presets do order[#order + 1] = j end
  end
  local added = false
  for _, j in ipairs(order) do
    if #ids >= A.MAX_SPELLS then
      break
    end
    for _, id in ipairs(c.presets[j].spells) do
      if #ids < A.MAX_SPELLS and not seen[id] and canCast(id) then
        ids[#ids + 1] = id
        -- an area filler waits for 2 monsters, like the preset's own area spells
        creatures[#creatures + 1] = (spells[id] and spells[id].area) and 2 or 1
        seen[id] = true
        added = true
      end
    end
  end
  -- the class's attack spells no preset holds (c.extras, newest first: a weaker single hit, a chi builder; O157, owner
  -- 2026-10-24) come last, so Auto setup can use every attack spell the character can cast
  if not (opts and opts.topUp == false) then
    for _, id in ipairs(c.extras or {}) do
      if #ids >= A.MAX_SPELLS then
        break
      end
      if not seen[id] and canCast(id) then
        ids[#ids + 1] = id
        creatures[#creatures + 1] = (spells[id] and spells[id].area) and 2 or 1
        seen[id] = true
        added = true
      end
    end
  end
  if #ids == 0 then
    return nil, 'spells'
  end
  -- Owner, 2026-10-20: "o helper ainda está colocando as magias de área embaixo das de single target. elas devem ficar
  -- em cima para serem castadas". The helper casts the first rule that can fire, so a single-target spell above an
  -- area one always wins. Area spells go first (each waits for its monster count), then the single-target ones;
  -- each group keeps its order.
  local moved = false
  ids, creatures, moved = A.areaFirst(ids, creatures, spells)
  local gap = (changed or added or moved) and A.gap(ids) or preset.gap
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

-- copy of a rule list (the undo keeps the list as it was)
function A.copyRules(rules)
  local out = {}
  for i, r in ipairs(rules or {}) do
    local c = {}
    for k, v in pairs(r) do c[k] = v end
    out[i] = c
  end
  return out
end

-- "Add to my rules": the player's rules first, unchanged and in their order, then the generated ones whose spell is
-- not in the list yet. Returns the new list and how many rules were added
function A.merge(userRules, autoRules)
  local out, have = A.copyRules(userRules), {}
  for _, r in ipairs(out) do
    if r.type == 'spell' and r.spellId then have[r.spellId] = true end
  end
  local added = 0
  for _, r in ipairs(autoRules or {}) do
    if not (r.type == 'spell' and have[r.spellId]) then
      local c = {}
      for k, v in pairs(r) do c[k] = v end
      out[#out + 1] = c
      added = added + 1
      if r.spellId then have[r.spellId] = true end
    end
  end
  return out, added
end

-- A class change (the store's Vocation Change, an ascension): the shooter rules and healing slots of spells the new class
-- cannot cast stay in the Helper and the server refuses every one of them ("kept the old class's spells", owner report
-- 2026-10-17). Drops them; item rules and the player's other rules stay. classOk(spellId) -> bool (the class lists the
-- spell; the level does not matter: it will be reached). Returns the new rule list and how many rules went.
function A.dropForeignRules(rules, classOk)
  local out, dropped = {}, 0
  for _, r in ipairs(rules or {}) do
    if r.type == 'spell' and r.spellId and r.spellId > 0 and not classOk(r.spellId) then
      dropped = dropped + 1
    else
      local c = {}
      for k, v in pairs(r) do c[k] = v end
      out[#out + 1] = c
    end
  end
  return out, dropped
end

-- may the class-change cleanup keep this spell? It drops only when everything is known: the spell is in the client's
-- table and the class is a real one. spell: the table entry or nil; vocation: the player's (0 or nil: the login
-- has not told it yet); listed(spell) -> bool (the class lists it). A login, a relog after a death or a table not filled
-- yet answers 'keep': the saved lists are never cut by a temporary gap (owner 2026-10-27).
function A.classKeeps(spell, vocation, listed)
  if type(spell) ~= 'table' then return true end
  if spell.notOnServer then return false end -- fixed by the client build, not by the login: the server has no such spell
  if (tonumber(vocation) or 0) <= 0 then return true end
  return listed(spell) and true or false
end

-- the healing slots ({id, percent}): a slot of a spell the new class cannot cast is emptied (id 0). Returns how many.
function A.dropForeignHeals(slots, classOk)
  local dropped = 0
  for _, s in ipairs(slots or {}) do
    if s.id and s.id ~= 0 and not classOk(s.id) then
      s.id = 0
      dropped = dropped + 1
    end
  end
  return dropped
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

-- What a level-up does (owner, 2026-10-16: "the helper updated my spells without me asking"). The helper never
-- changes the player's spells unasked. sel: the rotation for the new level (A.select with topUp false); rules,
-- marker: the preset's rules and the ids the button wrote last; opts.autoUpdate: the player's "Auto-update my spells"
-- (off by default); opts.ignored: {[id] = true} spells the player said Ignore to. Returns action, newIds:
--   'none'    nothing new, or nothing the player has not ignored
--   'notice'  new spells: ask "New spell available ... Add to rotation?" (Add / Ignore)
--   'apply'   only with autoUpdate, and only for a rotation the button wrote (never the player's own rules)
function A.levelUpAction(sel, rules, marker, opts)
  opts = opts or {}
  if not sel then
    return 'none', {}
  end
  local current = {}
  for _, id in ipairs(A.ruleIds(rules)) do current[id] = true end
  local ignored = opts.ignored or {}
  local newIds = {}
  for _, id in ipairs(sel.ids) do
    if not current[id] and not ignored[id] then newIds[#newIds + 1] = id end
  end
  local custom = A.isCustom(rules, marker)
  if opts.autoUpdate == true and not custom and not same(A.ruleIds(rules), sel.ids) and #newIds > 0 then
    return 'apply', newIds
  end
  if #newIds > 0 then
    return 'notice', newIds
  end
  return 'none', {}
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

-- Which label the "Auto-update my spells" box can show in the room it has (the presets row, between the Set Key /
-- help icons and Rename). free: pixels of room; widths: {full, short, box} of the box with each label and bare.
-- 'full', then 'short', then 'none' (the box alone; the tooltip keeps the full text). It never overlaps.
function A.autoBoxLabel(free, widths)
  free = tonumber(free) or 0
  widths = widths or {}
  if (tonumber(widths.full) or math.huge) <= free then return 'full' end
  if (tonumber(widths.short) or math.huge) <= free then return 'short' end
  if (tonumber(widths.box) or math.huge) <= free then return 'none' end
  return 'hidden'
end
