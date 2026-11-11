-- ChaosSpellHelp: the plain lines a spell tooltip shows while Alt is held (O372): what the spell is for, where it hits,
-- its element and its cooldowns. Pure Lua (spellhelp_test.lua). Used by the spellbook rows (game_spellbook) and the
-- helper's spell pickers of Auto setup (game_helper); the Alt poll is client_chaos_theme althelp.lua.
-- Two spell shapes are read, a field the entry lacks gives no line:
--   * the spellbook's server entry (server spellbook.lua): type (damage | heal | buff | summon | conjure | utility),
--     target (single | area | self | front), element, group ('attack' | 'healing' | 'support'), cooldown and
--     groupCooldown in ms;
--   * the client entry (spelldata.lua, gen_spell_data.py): group (a number or {[group] = ms}), groupCooldown,
--     cooldown or exhaustion in ms, areaShape (single | self | circle | around | line | wave), needTarget, element.
-- Every text is a literal tr() key (check_locales.py sees its pt-BR).
ChaosSpellHelp = {}
local H = ChaosSpellHelp
-- the module is sandboxed: other modules read it from _G
_G.ChaosSpellHelp = H

local function translate(tr)
  if type(tr) == 'function' then return tr end
  local g = (rawget(_G, 'tr') or (rawget(_G, 'ChaosLocale') or {}).tr)
  if type(g) == 'function' then return g end
  return function(s, ...)
    if select('#', ...) > 0 then return string.format(s, ...) end
    return s
  end
end

local function num(v)
  v = tonumber(v)
  if v and v > 0 then return v end
  return nil
end

-- "4 s", "2.5 s"
function H.seconds(ms)
  ms = num(ms)
  if not ms then return nil end
  local s = ms / 1000
  return ((s == math.floor(s)) and string.format('%d', s) or string.format('%.1f', s)) .. ' s'
end

-- what the spell is for: damage | heal | buff | summon | conjure | utility (nil: not known)
function H.kind(spell)
  local t = type(spell.type) == 'string' and spell.type:lower() or nil
  if t == 'damage' or t == 'heal' or t == 'buff' or t == 'summon' or t == 'conjure' or t == 'utility' then return t end
  local g = spell.group
  if type(g) == 'string' then
    g = g:lower()
    if g == 'attack' then return 'damage' end
    if g == 'healing' then return 'heal' end
    if g == 'support' then return 'buff' end
    return nil
  end
  local has = {}
  if type(g) == 'number' then
    has[g] = true
  elseif type(g) == 'table' then
    for k, v in pairs(g) do
      if type(k) == 'number' and v ~= false then has[k] = true end
    end
  else
    return nil
  end
  if has[2] then return 'heal' end
  if has[1] or has[4] then return 'damage' end
  if next(has) then return 'buff' end
  return nil
end

-- where it hits: single | area | front | around | self (nil: not known)
function H.where(spell)
  local t = type(spell.target) == 'string' and spell.target:lower() or nil
  if t == 'single' or t == 'area' or t == 'self' or t == 'front' then return t end
  local shape = spell.areaShape
  if shape == 'single' or shape == 'self' or shape == 'around' then return shape end
  if shape == 'circle' then return 'area' end
  if shape == 'line' or shape == 'wave' then return 'front' end
  if spell.needTarget then return 'single' end
  return nil
end

local function groupMs(spell)
  local g = spell.group
  if type(g) == 'table' then
    local best
    for k, v in pairs(g) do
      if type(k) == 'number' and num(v) and (not best or k < best.k) then best = { k = k, v = num(v) } end
    end
    if best then return best.v end
  end
  return num(spell.groupCooldown)
end

local function elementName(e, tr)
  if e == 'fire' then return tr('Fire') end
  if e == 'ice' then return tr('Ice') end
  if e == 'earth' then return tr('Earth') end
  if e == 'energy' then return tr('Energy') end
  if e == 'holy' then return tr('Holy') end
  if e == 'death' then return tr('Death') end
  if e == 'physical' then return tr('Physical') end
  if e == 'arcane' then return tr('Arcane') end
  if e == 'water' then return tr('Water') end
  return nil
end

-- the help lines of a spell (empty for anything else)
function H.lines(spell, tr)
  tr = translate(tr)
  local out = {}
  if type(spell) ~= 'table' then return out end
  local kind = H.kind(spell)
  if kind == 'damage' then
    out[#out + 1] = tr('Attack: deals damage to monsters.')
  elseif kind == 'heal' then
    out[#out + 1] = tr('Healing: gives you health back.')
  elseif kind == 'buff' then
    out[#out + 1] = tr('Support: makes you stronger or faster for a while.')
  elseif kind == 'summon' then
    out[#out + 1] = tr('Summon: calls creatures that fight for you.')
  elseif kind == 'conjure' then
    out[#out + 1] = tr('Conjure: makes items such as runes or ammunition.')
  elseif kind == 'utility' then
    out[#out + 1] = tr('Utility: helps you travel, see or find things.')
  end
  local where = H.where(spell)
  if where == 'single' then
    out[#out + 1] = tr('Single target: hits the creature you attack.')
  elseif where == 'area' then
    out[#out + 1] = tr('Area: hits every monster in its area.')
  elseif where == 'around' then
    out[#out + 1] = tr('Around you: hits every monster next to you.')
  elseif where == 'front' then
    out[#out + 1] = tr('In front: hits the tiles in front of you, turn to aim it.')
  elseif where == 'self' then
    out[#out + 1] = tr('Self: works on you.')
  end
  local element = elementName(type(spell.element) == 'string' and spell.element:lower() or nil, tr)
  if element and kind ~= 'heal' and kind ~= 'buff' then
    out[#out + 1] = tr('%s: monsters weak to it take more, monsters strong against it take less.', element)
  end
  local cd = H.seconds(num(spell.cooldown) or num(spell.exhaustion))
  if cd then out[#out + 1] = tr('Cooldown: you can cast it again after %s.', cd) end
  local gcd = H.seconds(groupMs(spell))
  if gcd then
    if kind == 'damage' then
      out[#out + 1] = tr('Attack group: your other attack spells wait %s after it.', gcd)
    elseif kind == 'heal' then
      out[#out + 1] = tr('Healing group: your other healing spells wait %s after it.', gcd)
    else
      out[#out + 1] = tr('Group cooldown: the other spells of its group wait %s after it.', gcd)
    end
  end
  return out
end

-- the hint line of a spell tooltip without Alt
function H.hint(tr)
  tr = translate(tr)
  return tr('Hold Alt for what this spell does.')
end

-- a whole tooltip: the short text, then the help lines with Alt or the hint without (ChaosAltHelp.lines rule)
function H.tooltip(short, spell, altDown, tr)
  local lines = H.lines(spell, tr)
  if #lines == 0 then return short end
  if altDown then return short .. '\n' .. table.concat(lines, '\n') end
  return short .. '\n' .. H.hint(tr)
end

return ChaosSpellHelp
