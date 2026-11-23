-- Inspect Monster window, the pure part (O721). Server: server/data/scripts/chaos/monster_inspect.lua, extended opcode 166
-- (JSON {action, data}); the window is monsterinspect.lua. Nothing here guesses a monster fact: every number comes from
-- the server's `result`, this file only turns it into the rows of the window (and decides which click inspects).
--   client -> server  inspect {cid}
--   server -> client  result {cid, name, level, tier, flags = [{key, name?}], outfit, health = {cur, max, pct, hidden},
--                              family = {cat, race, diff}, mods = [{key, name, text}], exp = {base, tier, rate, total, bonus,
--                              rank}, resist = {elements = [{name, pct}], immune, conditions}, armour = {armor, defense,
--                              class, spell, weapon}, attacks = [{name, kind, element, chance, interval, min, max, range}],
--                              abilities = [{kind, name, ...}], speed = {base, now}, loot = {total, bands, rows, locked,
--                              tierText}, uniques = [{name, cid, boss, set}], areas = [{text, count}], bestiary = {kills,
--                              stage, th, next}}
--                     denied {code}   notfound | range | rate | bad | hidden
--   a big result comes in parts "S..", "P..", "E.." (Chaos.sendChunked), joined by L.joinPart
local function tr(s, ...) local g = (rawget(_G, 'tr') or (rawget(_G, 'ChaosLocale') or {}).tr) if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

MonsterInspectLogic = {}
local L = MonsterInspectLogic

L.OPCODE = 166
L.COLORS = { text = '#d6c9ae', dim = '#8c8070', gold = '#f6cf72', accent = '#7fc4d6', red = '#e03a1e', good = '#5ccf5c',
  orange = '#e8903a' }

-- ---------------------------------------------------------------- numbers and words
local function lnum(text) local c = rawget(_G, 'ChaosLocale') if c and c.localize then return c.localize(text) end return text end
function L.numberText(n)
  n = math.floor(tonumber(n) or 0)
  local s = tostring(n)
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return lnum(out)
end

-- a decimal with at most one digit: 2.0 -> "2", 2.5 -> "2.5" (the locale writes the comma in pt-BR)
local function decimal(n)
  local text = string.format('%.1f', n):gsub('%.0$', '')
  return lnum(text)
end

local function percent(n)
  return string.format('%d%%', math.floor(tonumber(n) or 0))
end

local function num(v) return tonumber(v) ~= nil end

-- the texts the server names by key: kept in tables built where they are shown, so each key is a literal tr() argument
local function words()
  return {
    flag = { elite = tr('Elite'), boss = tr('Boss'), guardian = tr('Rift guardian'), omen = tr('Omen guardian'),
      summon = tr('Summon') },
    element = { physical = tr('Physical'), energy = tr('Energy'), earth = tr('Earth'), fire = tr('Fire'),
      ['life drain'] = tr('Life drain'), ['mana drain'] = tr('Mana drain'), drown = tr('Drowning'), ice = tr('Ice'),
      holy = tr('Holy'), death = tr('Death') },
    condition = { poison = tr('Poison'), burning = tr('Burning'), shock = tr('Shock'), bleeding = tr('Bleeding'),
      paralysis = tr('Paralysis'), drunk = tr('Drunk'), invisibility = tr('Invisibility'),
      ['outfit change'] = tr('Outfit change') },
    kind = { melee = tr('Melee'), ranged = tr('Ranged'), spell = tr('Spell') },
    band = { ['Common'] = tr('Common'), ['Uncommon'] = tr('Uncommon'), ['Rare'] = tr('Rare'), ['Very rare'] = tr('Very rare') },
    class = { normal = tr('Normal'), elite = tr('Elite'), boss = tr('Boss') },
    stage = { [0] = tr('Unknown'), tr('Discovered'), tr('Studied'), tr('Mastered'), tr('Completed') },
    diff = { harmless = tr('Harmless'), easy = tr('Easy'), medium = tr('Medium'), hard = tr('Hard'),
      challenging = tr('Challenging'), deadly = tr('Deadly'), boss = tr('Boss') },
    race = { venom = tr('Venom'), blood = tr('Blood'), undead = tr('Undead'), fire = tr('Fire'), energy = tr('Energy') },
    mod = {
      blazing = tr('Its hits can set you on fire.'), chilling = tr('Its hits can slow you down.'),
      venomous = tr('Its hits can poison you.'), shocking = tr('Its hits can shock you.'),
      vampiric = tr('It heals itself with a part of the damage it deals.'), berserker = tr('It hits much harder below half health.'),
      brutal = tr('It hits harder.'), stoneskin = tr('It takes less damage.'),
      reflective = tr('It throws part of the damage back at you.'), regenerating = tr('It slowly heals itself.'),
      swift = tr('It moves faster.'), explosive = tr('It explodes when it dies.'), juggernaut = tr('It has much more health.'),
      emberforged = tr('It resists fire and burns.'), frostforged = tr('It resists ice and chills.'),
      stormforged = tr('It resists energy and shocks.'), plated = tr('It resists physical damage.'),
      resistant = tr('It resists one more element.'), ruthless = tr('Its attacks ignore a part of your armour.'),
      bulwark = tr('It blocks some hits outright.')
    },
    tierLoot = {
      ['1 extra loot roll'] = tr('1 extra loot roll'),
      ['1 extra loot roll, gear of Magic quality or better'] = tr('1 extra loot roll, gear of Magic quality or better'),
      ['2 extra loot rolls, gear of Rare quality or better'] = tr('2 extra loot rolls, gear of Rare quality or better')
    },
    defence = { healing = tr('Heals itself'), speed = tr('Hastes itself'), invisible = tr('Turns invisible'),
      outfit = tr('Changes its look'), drunk = tr('Makes you drunk') },
    flagRow = { ['runs'] = tr('Runs away when hurt'), ['pushes items'] = tr('Pushes items'),
      ['pushes creatures'] = tr('Pushes creatures'), ['hides its health'] = tr('Hides its health') },
    denied = {
      notfound = tr('That monster is not there any more.'), range = tr('That monster is too far away or out of sight.'),
      rate = tr('You are inspecting too fast. Wait a moment.'), bad = tr('Nothing to inspect.'),
      hidden = tr('That monster cannot be inspected.')
    }
  }
end

-- the server's key through a table of words; an unknown key shows as sent (and goes through tr like any run-time key)
local function word(map, key)
  if map[key] ~= nil then return map[key] end
  return tr(tostring(key))
end

local function titled(text)
  text = tostring(text or '')
  return (text:gsub('^%l', string.upper))
end

-- ---------------------------------------------------------------- chunks
-- the parts of a chunked message (Chaos.sendChunked: "S" first part, "P" middle parts, "E" last part; a message that fits
-- comes whole, starting with "{"). Returns the whole text when it is complete, else nil. parts: a table kept per opcode.
function L.joinPart(parts, buffer)
  if type(buffer) ~= 'string' or buffer == '' then return nil end
  local kind, rest = buffer:sub(1, 1), buffer:sub(2)
  if kind == 'S' then
    parts.buf = { rest }
    return nil
  elseif kind == 'P' then
    if parts.buf then parts.buf[#parts.buf + 1] = rest end
    return nil
  elseif kind == 'E' then
    if not parts.buf then return nil end
    parts.buf[#parts.buf + 1] = rest
    local whole = table.concat(parts.buf)
    parts.buf = nil
    return whole
  end
  return buffer
end

-- ---------------------------------------------------------------- clicks
-- a creature the window can inspect: a monster (never a player or an NPC), read through the creature's own methods
function L.isMonster(creature)
  if type(creature) ~= 'table' then return false end
  if creature.isMonster then return creature:isMonster() == true end
  if creature.isPlayer and creature:isPlayer() then return false end
  if creature.isNpc and creature:isNpc() then return false end
  return creature.getId ~= nil
end

-- Shift + left click on a monster opens the window; every other click (Shift + right, Ctrl, Alt, a player, an item) is
-- the base client's. leftButton: the engine's MouseLeftButton; mods: {ctrl, shift, alt} of the keyboard now
function L.shouldInspectClick(mouseButton, leftButton, mods, creature)
  if mouseButton == nil or mouseButton ~= leftButton or type(mods) ~= 'table' then return false end
  if not mods.shift or mods.ctrl or mods.alt then return false end
  return L.isMonster(creature)
end

-- ---------------------------------------------------------------- the header
function L.healthText(h)
  if type(h) ~= 'table' then return '' end
  if h.hidden or not num(h.cur) then return string.format('%s: %s', tr('Health'), percent(h.pct)) end
  return string.format('%s: %s / %s (%s)', tr('Health'), L.numberText(h.cur), L.numberText(h.max), percent(h.pct))
end

function L.healthColor(h)
  local pct = type(h) == 'table' and tonumber(h.pct) or 100
  if pct > 60 then return L.COLORS.good end
  if pct > 30 then return L.COLORS.gold end
  return L.COLORS.red
end

-- { name, level, flags, health, pct, color }: the lines of the header band (a line is nil when there is nothing to say)
function L.header(d)
  local W = words()
  local out = { name = tostring(d.name or ''), pct = math.max(0, math.min(100, tonumber(d.health and d.health.pct) or 0)) }
  if num(d.level) then out.level = string.format('%s %d', tr('Level'), tonumber(d.level)) end
  local flags = {}
  for _, f in ipairs(type(d.flags) == 'table' and d.flags or {}) do
    if f.key == 'tier' then
      flags[#flags + 1] = word({}, tostring(f.name or ''))
    else
      flags[#flags + 1] = word(W.flag, f.key)
    end
  end
  if #flags > 0 then out.flags = table.concat(flags, ', ') end
  out.health = L.healthText(d.health)
  out.color = L.healthColor(d.health)
  return out
end

-- ---------------------------------------------------------------- the sections
local function row(label, value, color, tip)
  return { label = label, value = value, color = color or L.COLORS.gold, tip = tip }
end

local function note(text, color)
  return { note = tostring(text), color = color or L.COLORS.dim }
end

local function seconds(ms)
  return decimal((tonumber(ms) or 0) / 1000)
end

local function attackRow(a, W)
  local label = tostring(a.name or '')
  if a.kind == 'melee' then label = word(W.kind, 'melee') else label = titled(label) end
  local bits = {}
  if a.element and a.kind ~= 'melee' then bits[#bits + 1] = word(W.element, a.element) end
  if num(a.range) and tonumber(a.range) > 1 then bits[#bits + 1] = string.format(tr('range %d'), tonumber(a.range)) end
  if #bits > 0 then label = label .. ' (' .. table.concat(bits, ', ') .. ')' end
  local value = ''
  if num(a.max) and tonumber(a.max) > 0 then
    value = string.format('%s - %s', L.numberText(a.min), L.numberText(a.max))
  end
  local tipBits = {}
  if num(a.chance) then tipBits[#tipBits + 1] = string.format(tr('%d%% chance per turn'), tonumber(a.chance)) end
  if num(a.interval) then tipBits[#tipBits + 1] = string.format(tr('every %s s'), seconds(a.interval)) end
  return row(label, value, L.COLORS.text, #tipBits > 0 and table.concat(tipBits, ', ') or nil)
end

local function abilityRow(a, W)
  if a.kind == 'defence' then
    local label = word(W.defence, a.name)
    local value = ''
    if a.name == 'healing' and num(a.max) then
      value = string.format('%s - %s', L.numberText(a.min), L.numberText(a.max))
    elseif a.name == 'speed' and num(a.value) then
      value = string.format('%+d', tonumber(a.value))
      if num(a.seconds) then value = value .. ' / ' .. string.format(tr('%d s'), tonumber(a.seconds)) end
    elseif num(a.seconds) then
      value = string.format(tr('%d s'), tonumber(a.seconds))
    end
    return row(label, value, L.COLORS.text, num(a.chance) and string.format(tr('%d%% chance per turn'), tonumber(a.chance)) or nil)
  elseif a.kind == 'summon' then
    local label = tr('Summons')
    if num(a.count) then label = string.format(tr('Summons (up to %d)'), tonumber(a.count)) end
    return row(label, tostring(a.name or ''), L.COLORS.text)
  end
  local label = word(W.flagRow, a.name)
  local value = (a.name == 'runs' and num(a.value)) and string.format(tr('below %d%% health'), tonumber(a.value)) or ''
  return row(label, value, L.COLORS.text)
end

-- the sections of the window: [{ title, rows = [{label, value, color, tip} | {note, color}] }]; empty sections are left out
function L.sections(d)
  local W = words()
  local C = L.COLORS
  local sections = {}
  local function add(title, rows)
    if #rows > 0 then sections[#sections + 1] = { title = title, rows = rows } end
  end

  local overview = {}
  if type(d.family) == 'table' then
    if d.family.cat then overview[#overview + 1] = row(tr('Family'), tostring(d.family.cat)) end
    if d.family.race then overview[#overview + 1] = row(tr('Type'), word(W.race, d.family.race)) end
    if d.family.diff then overview[#overview + 1] = row(tr('Difficulty'), word(W.diff, d.family.diff)) end
  end
  if type(d.speed) == 'table' and num(d.speed.base) then
    local v = L.numberText(d.speed.base)
    if num(d.speed.now) and tonumber(d.speed.now) ~= tonumber(d.speed.base) then
      v = string.format('%s (%s %s)', v, tr('now'), L.numberText(d.speed.now))
    end
    overview[#overview + 1] = row(tr('Speed'), v)
  end
  add(tr('Overview'), overview)

  local exp = {}
  if type(d.exp) == 'table' and num(d.exp.total) then
    exp[#exp + 1] = row(tr('Experience'), L.numberText(d.exp.total), C.gold, tr('What one kill gives before party sharing and your own bonuses.'))
    if num(d.exp.base) then exp[#exp + 1] = row(tr('Base'), L.numberText(d.exp.base), C.text) end
    if num(d.exp.tier) then exp[#exp + 1] = row(tr('Rank factor'), 'x' .. decimal(tonumber(d.exp.tier)), C.text) end
    if num(d.exp.rate) then exp[#exp + 1] = row(tr('Your experience stage'), 'x' .. decimal(tonumber(d.exp.rate)), C.text) end
    if num(d.exp.bonus) then exp[#exp + 1] = row(tr('Bestiary entry bonus'), '+' .. percent(d.exp.bonus), C.good) end
    if num(d.exp.rank) then exp[#exp + 1] = row(tr('Bestiary rank bonus'), '+' .. percent(d.exp.rank), C.good) end
  end
  add(tr('Experience'), exp)

  local mods = {}
  for _, m in ipairs(type(d.mods) == 'table' and d.mods or {}) do
    mods[#mods + 1] = row(tostring(m.name or ''), '', C.orange)
    local text = m.key and W.mod[m.key]
    if text then mods[#mods + 1] = note(text) end
  end
  add(tr('Modifiers'), mods)

  local resist = {}
  local r = type(d.resist) == 'table' and d.resist or {}
  for _, e in ipairs(type(r.elements) == 'table' and r.elements or {}) do
    local pct = tonumber(e.pct) or 0
    resist[#resist + 1] = row(word(W.element, e.name), (pct > 0 and '+' or '') .. percent(pct) .. (pct > 0 and ' ' .. tr('less damage') or ' ' .. tr('more damage')),
      pct > 0 and C.accent or C.red)
  end
  local function list(map, items)
    local out = {}
    for _, key in ipairs(type(items) == 'table' and items or {}) do out[#out + 1] = word(map, key) end
    return table.concat(out, ', ')
  end
  if type(r.immune) == 'table' and #r.immune > 0 then
    resist[#resist + 1] = row(tr('Immune to'), list(W.element, r.immune), C.red)
  end
  if type(r.conditions) == 'table' and #r.conditions > 0 then
    resist[#resist + 1] = row(tr('Cannot be affected by'), list(W.condition, r.conditions), C.red)
  end
  if #resist == 0 and type(d.resist) == 'table' then resist[1] = note(tr('No resistances and no weaknesses.')) end
  add(tr('Resistances'), resist)

  local defence = {}
  local a = type(d.armour) == 'table' and d.armour or {}
  if num(a.armor) then defence[#defence + 1] = row(tr('Armour'), L.numberText(a.armor), C.text, tr('The flat value of the monster file: it takes this off every hit.')) end
  if num(a.defense) then defence[#defence + 1] = row(tr('Defence'), L.numberText(a.defense), C.text) end
  if a.class then defence[#defence + 1] = row(tr('Armour class'), word(W.class, a.class), C.text) end
  if num(a.spell) then defence[#defence + 1] = row(tr('Blocks of a typical spell hit'), percent(a.spell), C.text, tr('Of a hit of the median class at this monster\'s level.')) end
  if num(a.weapon) then defence[#defence + 1] = row(tr('Blocks of a typical weapon hit'), percent(a.weapon), C.text) end
  add(tr('Defence'), defence)

  local attacks = {}
  for _, at in ipairs(type(d.attacks) == 'table' and d.attacks or {}) do attacks[#attacks + 1] = attackRow(at, W) end
  if #attacks > 0 then attacks[#attacks + 1] = note(tr('Damage ranges are before your armour and resistances.')) end
  add(tr('Attacks'), attacks)

  local abilities = {}
  for _, ab in ipairs(type(d.abilities) == 'table' and d.abilities or {}) do abilities[#abilities + 1] = abilityRow(ab, W) end
  add(tr('Abilities'), abilities)

  local loot = {}
  local lt = type(d.loot) == 'table' and d.loot or nil
  if lt then
    if num(lt.total) and tonumber(lt.total) > 0 then
      local bands = {}
      for _, b in ipairs(type(lt.bands) == 'table' and lt.bands or {}) do
        if tonumber(b.n) and tonumber(b.n) > 0 then bands[#bands + 1] = string.format('%s %d', word(W.band, b.key), tonumber(b.n)) end
      end
      loot[#loot + 1] = row(tr('Items in its loot table'), tostring(math.floor(tonumber(lt.total))), C.text)
      if #bands > 0 then loot[#loot + 1] = note(table.concat(bands, ', ')) end
    end
    if lt.tierText then loot[#loot + 1] = note(word(W.tierLoot, lt.tierText)) end
    for _, it in ipairs(type(lt.rows) == 'table' and lt.rows or {}) do
      local chance = tonumber(it.chance) or 0
      local text = chance >= 10 and string.format('%d%%', math.floor(chance + 0.5)) or lnum(string.format('%.2f%%', chance))
      if (tonumber(it.max) or 1) > 1 then text = string.format(tr('%s (max %d)'), text, tonumber(it.max)) end
      local color = chance >= 10 and C.text or (chance >= 1 and C.accent or C.gold)
      local r2 = row(tostring(it.name or ''), text, color, word(W.band, it.band))
      r2.item = tonumber(it.cid)
      loot[#loot + 1] = r2
    end
    if num(lt.locked) then
      loot[#loot + 1] = note(string.format(tr('Study this monster in the Bestiary to see more of its loot (stage %d).'), tonumber(lt.locked)), C.dim)
    end
  end
  add(tr('Loot'), loot)

  local uniques = {}
  for _, u in ipairs(type(d.uniques) == 'table' and d.uniques or {}) do
    local label = tostring(u.name or '')
    if u.set then label = label .. ' (' .. tr('set piece') .. ')' elseif u.boss then label = label .. ' (' .. tr('boss only') .. ')' end
    local r3 = row(label, '', C.gold)
    r3.item = tonumber(u.cid)
    uniques[#uniques + 1] = r3
  end
  add(tr('Unique items and set pieces'), uniques)

  local areas = {}
  for _, ar in ipairs(type(d.areas) == 'table' and d.areas or {}) do
    areas[#areas + 1] = row(tostring(ar.text or ''), num(ar.count) and string.format(tr('%d spawns'), tonumber(ar.count)) or '', C.text)
  end
  if #areas == 0 and type(d.bestiary) == 'table' then
    areas[1] = note(tr('Study this monster in the Bestiary to learn where it lives.'))
  end
  add(tr('Where it lives'), areas)

  local b = d.bestiary
  if type(b) == 'table' then
    local rows = { row(tr('Bestiary stage'), word(W.stage, tonumber(b.stage) or 0), C.gold),
      row(tr('Your kills'), L.numberText(b.kills), C.text) }
    if num(b.next) then rows[#rows + 1] = row(tr('Kills for the next stage'), L.numberText(b.next), C.text) end
    add(tr('Your Bestiary progress'), rows)
  end
  return sections
end

-- the text of a refusal (denied {code})
function L.deniedText(code)
  local W = words()
  return W.denied[code] or W.denied.notfound
end

return L
