-- ChaosHelperSpellInfo: the data the helper's spell lists show for a spell (pure Lua: no engine calls; tests:
-- spellinfo_logic_test.lua, run with luajit and lua5.3).
-- The helper's spell pickers (healing, shooter, mana training, haste) list a spell as "Name   120 mana | AOE circle 3 | 4 s"
-- and show the full data in a tooltip on hover: mana, single target or area (with the shape and size), cooldown and group
-- cooldown, range, level, element, kind. The client's spell entry (game_chaosspells/spelldata.lua, written by
-- client/tools/gen_spell_data.py) carries:
--   mana / manaPercent, level, exhaustion (the spell's own cooldown in ms), group ({[group] = group cooldown ms}), range,
--   needTarget, directional, area (the gamelib matrix of a wave or beam), areaShape (single | self | circle | around |
--   wave | line), areaSize (radius, length or depth), areaWidth (tiles across a wave), element.
-- A stock spell has fewer of them; a field the entry lacks is left out without a word.
-- Text goes through the `tr` given (the client's tr in the game; a stub in the test). The pt-BR texts are in
-- client_chaos_locale/pt_br.lua.
ChaosHelperSpellInfo = ChaosHelperSpellInfo or {}
local I = ChaosHelperSpellInfo

I.SEP = ' | ' -- between the parts of a row (ASCII: the client fonts draw cp1252)

local function translate(tr)
  if type(tr) == 'function' then return tr end
  local g = rawget(_G, 'tr')
  if type(g) == 'function' then return g end
  return function(text, ...)
    if select('#', ...) > 0 then return string.format(text, ...) end
    return text
  end
end

local function num(v)
  v = tonumber(v)
  if v and v > 0 then return v end
  return nil
end

-- seconds of a millisecond cooldown: "4 s", "2.5 s"
function I.seconds(ms)
  ms = num(ms)
  if not ms then return nil end
  local s = ms / 1000
  local text = (s == math.floor(s)) and string.format('%d', s) or string.format('%.1f', s)
  return text .. ' s'
end

-- the spell's own cooldown in ms
function I.cooldownMs(spell)
  return num(spell.exhaustion) or num(spell.cooldown)
end

-- the group cooldown in ms: the entry's group table value, else groupCooldown
function I.groupCooldownMs(spell)
  local g = spell.group
  if type(g) == 'table' then
    local best
    for k, v in pairs(g) do
      if type(k) == 'number' and num(v) and (not best or k < best.k) then best = { k = k, v = v } end
    end
    if best then return best.v end
  end
  return num(spell.groupCooldown)
end

-- the kind of the spell by its group: attack (1, 4), healing (2), support (anything else); nil without a group
function I.kind(spell)
  local g = spell.group
  local has = {}
  if type(g) == 'table' then
    for k, v in pairs(g) do
      if type(k) == 'number' and v ~= false then has[k] = true end
    end
  elseif type(g) == 'number' then
    has[g] = true
  else
    return nil
  end
  if has[2] then return 'healing' end
  if has[1] or has[4] then return 'attack' end
  return 'support'
end

local function areaCells(matrix)
  local n = 0
  if type(matrix) ~= 'table' then return 0 end
  for _, row in pairs(matrix) do
    if type(row) == 'table' then
      for _, c in pairs(row) do
        if c == 1 or c == 3 then n = n + 1 end
      end
    end
  end
  return n
end

-- Where the spell hits. Returns kind ('single' | 'area' | 'self' | nil when the entry says nothing) and the area label
-- ("circle 3", "around 1", "line 6", "wave 3x3"; "" when the shape or size is not known)
function I.area(spell, tr)
  tr = translate(tr)
  if type(spell) ~= 'table' then return nil, '' end
  local shape = spell.areaShape
  local size, width = num(spell.areaSize), num(spell.areaWidth)
  if shape == 'circle' then
    return 'area', size and (tr('circle') .. ' ' .. size) or tr('circle')
  elseif shape == 'around' then
    return 'area', size and (tr('around') .. ' ' .. size) or tr('around')
  elseif shape == 'line' then
    return 'area', size and (tr('line') .. ' ' .. size) or tr('line')
  elseif shape == 'wave' then
    if size and width then return 'area', tr('wave') .. ' ' .. size .. 'x' .. width end
    return 'area', size and (tr('wave') .. ' ' .. size) or tr('wave')
  elseif shape == 'single' then
    return 'single', ''
  elseif shape == 'self' then
    return 'self', ''
  end
  -- a stock entry: the gamelib matrix of a wave or beam, else the target it needs
  if spell.directional or areaCells(spell.area) > 1 then
    return 'area', spell.directional and tr('wave') or ''
  end
  if spell.needTarget or num(spell.range) then return 'single', '' end
  return nil, ''
end

local function manaText(spell, tr)
  local pct = num(spell.manaPercent)
  if pct then return pct .. '%' end
  local mana = num(spell.mana)
  return mana and tostring(mana) or nil
end

-- "120 mana | AOE circle 3 | 4 s": the parts the entry has, in that order
function I.compact(spell, tr)
  tr = translate(tr)
  if type(spell) ~= 'table' then return '' end
  local parts = {}
  local mana = manaText(spell, tr)
  if mana then parts[#parts + 1] = tr('%s mana', mana) end
  local kind, label = I.area(spell, tr)
  if kind == 'single' then
    parts[#parts + 1] = tr('Single target')
  elseif kind == 'area' then
    parts[#parts + 1] = (tr('AOE') .. (label ~= '' and (' ' .. label) or ''))
  elseif kind == 'self' then
    parts[#parts + 1] = tr('Self')
  end
  local cd = I.seconds(I.cooldownMs(spell))
  if cd then parts[#parts + 1] = cd end
  return table.concat(parts, I.SEP)
end

-- the list row: the name, then the compact data (just the name when the entry has none)
function I.optionText(name, spell, tr)
  local info = I.compact(spell, tr)
  if info == '' then return name end
  return name .. '   ' .. info
end

local function elementText(element, tr)
  if element == 'fire' then return tr('Fire') end
  if element == 'ice' then return tr('Ice') end
  if element == 'earth' then return tr('Earth') end
  if element == 'energy' then return tr('Energy') end
  if element == 'holy' then return tr('Holy') end
  if element == 'death' then return tr('Death') end
  if element == 'physical' then return tr('Physical') end
  return nil
end

local function kindText(kind, tr)
  if kind == 'attack' then return tr('Attack') end
  if kind == 'healing' then return tr('Healing') end
  if kind == 'support' then return tr('Support') end
  return nil
end

-- the tooltip lines below the name: { "Mana: 120", "Target: Area (circle 3)", "Cooldown: 4 s", ... }, only what is known
function I.lines(spell, tr)
  tr = translate(tr)
  local out = {}
  if type(spell) ~= 'table' then return out end
  local function add(label, value)
    if value and value ~= '' then out[#out + 1] = label .. ': ' .. value end
  end
  local mana = manaText(spell, tr)
  if mana then
    -- a share of the maximum mana says so
    out[#out + 1] = tr('Mana') .. ': ' .. mana .. ((num(spell.manaPercent) and not num(spell.mana)) and (' ' .. tr('of your maximum')) or '')
  end
  local kind, label = I.area(spell, tr)
  if kind == 'single' then
    add(tr('Target'), tr('Single target'))
  elseif kind == 'area' then
    add(tr('Target'), tr('Area') .. (label ~= '' and (' (' .. label .. ')') or ''))
  elseif kind == 'self' then
    add(tr('Target'), tr('Self'))
  end
  add(tr('Cooldown'), I.seconds(I.cooldownMs(spell)))
  local gcd = I.groupCooldownMs(spell)
  if gcd then out[#out + 1] = tr('Group cooldown: %s', I.seconds(gcd)) end
  local range = num(spell.range)
  if range then add(tr('Spell range'), tr('%d tiles', range)) end
  add(tr('Level'), num(spell.level) and tostring(num(spell.level)) or nil)
  add(tr('Element'), elementText(spell.element, tr))
  add(tr('Group'), kindText(I.kind(spell), tr))
  return out
end

-- the whole tooltip: "Spell: Name\nWords: words" then the lines
function I.tooltip(spell, tr)
  tr = translate(tr)
  if type(spell) ~= 'table' then return '' end
  local text = tr('Spell: %s\nWords: %s', spell.name or '', spell.words or '')
  local lines = I.lines(spell, tr)
  if #lines > 0 then text = text .. '\n' .. table.concat(lines, '\n') end
  return text
end

return ChaosHelperSpellInfo
