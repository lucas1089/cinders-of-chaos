-- Pure helpers of the pets window (no UI calls): the list, the texts. Tested by petsview_test.lua (luajit / lua5.3).
-- The state comes from the server (server/data/scripts/chaos/pets.lua P.stateOf):
--   pets = [{id, species, speciesName, name, look, element, level, maxLevel, xp, into, need, pct, active, source,
--            abilities = [{key, name, kind, value, desc, unlockAt, unlocked, cooldown}]}]
--   catalog = [{key, name, look, how, owned, abilities = [name]}], active, out, rest, zone,
--   cooldowns = {summon, death, rename}, maxLevel, secondAt
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
PetsView = {}
local V = PetsView

local function num(x) return tonumber(x) or 0 end
local function list(v)
  local out = {}
  if type(v) == 'table' then for _, x in ipairs(v) do out[#out + 1] = x end end
  return out
end
-- the rows of a server list: tables with a key (an entry that is anything else is left out; opcode_fuzz_test.lua)
local function rows(v, key)
  local out = {}
  for _, x in ipairs(list(v)) do
    if type(x) == 'table' and x[key] ~= nil then out[#out + 1] = x end
  end
  return out
end

-- one entry per species: owned pets first (the server's order: highest level first), then the others in catalog order
-- entry = {key, owned, pet (or nil), name, speciesName, look, how, level, abilities (names, for locked ones)}
function V.entries(state)
  local out, seen = {}, {}
  local catalog = {}
  for _, c in ipairs(rows(state and state.catalog, 'key')) do catalog[c.key] = c end
  for _, p in ipairs(rows(state and state.pets, 'species')) do
    local c = catalog[p.species] or {}
    out[#out + 1] = { key = p.species, owned = true, pet = p, name = p.name or p.speciesName, speciesName = p.speciesName,
      look = num(p.look), how = c.how or '', level = num(p.level) }
    seen[p.species] = true
  end
  for _, c in ipairs(rows(state and state.catalog, 'key')) do
    if not seen[c.key] then
      out[#out + 1] = { key = c.key, owned = false, name = c.name, speciesName = c.name, look = num(c.look),
        how = c.how or '', level = 0, abilities = list(c.abilities) }
    end
  end
  return out
end

function V.find(entries, key)
  for i, e in ipairs(entries or {}) do
    if e.key == key then return e, i end
  end
  return nil
end

-- the entry to select: the one asked for if it still exists, else the active pet, else the first
function V.pick(entries, wanted, active)
  if wanted and V.find(entries, wanted) then return wanted end
  if active and V.find(entries, active) then return active end
  return entries[1] and entries[1].key or nil
end

-- the row: the pet's name on top; below its level and whether it is out (the species is in the detail title)
function V.rowText(e)
  return e.name
end

-- the detail title: "Soot (Ash Cat)" for a renamed pet
function V.titleText(e)
  if e.owned and e.name ~= e.speciesName then return string.format('%s (%s)', e.name, e.speciesName) end
  return e.name
end

function V.rowSub(e, state)
  if not e.owned then return tr('Not owned') end
  local s = string.format('Level %d', e.level)
  if state and state.active == e.key then
    s = s .. (state.out and ', out' or ', resting')
  end
  return s
end

function V.xpText(p)
  if not p then return '' end
  if num(p.need) <= 0 then return string.format('Level %d (max)', num(p.level)) end
  return tr('Level %d  -  %d / %d XP (%d%%)', num(p.level), num(p.into), num(p.need), num(p.pct))
end

function V.abilityLines(e, secondAt)
  local out = {}
  if e.owned and e.pet then
    for _, a in ipairs(list(e.pet.abilities)) do
      local cd = num(a.cooldown) > 0 and tr(' (every %d s at most)', num(a.cooldown)) or ''
      local kind = a.kind == 'combat' and 'combat' or 'utility'
      out[#out + 1] = {
        title = string.format('%s  [%s]', a.name or '?', kind),
        text = (a.desc or '') .. cd,
        locked = not a.unlocked,
        lockText = not a.unlocked and tr('Unlocks at pet level %d.', num(a.unlockAt)) or nil
      }
    end
  else
    for i, name in ipairs(list(e.abilities)) do
      out[#out + 1] = { title = name, text = i == 1 and tr('From level 1.') or tr('From level %d.', num(secondAt)),
        locked = true }
    end
  end
  return out
end

-- the status line under the buttons
function V.statusText(state)
  if not state then return '' end
  local parts = {}
  local cd = type(state.cooldowns) == 'table' and state.cooldowns or {}
  if num(cd.death) > 0 then
    parts[#parts + 1] = tr('Your pet is recovering from your death: %d s.', num(cd.death))
  end
  if state.active then
    if state.rest then
      parts[#parts + 1] = tostring(state.rest)
    elseif state.out then
      parts[#parts + 1] = 'Your pet is with you.'
    end
  else
    parts[#parts + 1] = 'No pet is out.'
  end
  if state.zone then
    parts[#parts + 1] = tr('Here: %s', (tostring(state.zone):gsub('^utility', 'utility abilities only'):gsub('^banned', 'no pets')))
  end
  if num(cd.summon) > 0 then
    parts[#parts + 1] = tr('Call again in %d s.', num(cd.summon))
  end
  return table.concat(parts, '  ')
end

-- which buttons: summon (owned, not the active one), dismiss (the active one), rename (owned)
function V.buttons(e, state)
  local active = state and state.active == (e and e.key)
  return {
    summon = e ~= nil and e.owned and not active,
    dismiss = e ~= nil and e.owned and active,
    rename = e ~= nil and e.owned
  }
end

-- the name typed in the rename box, trimmed; nil when empty
function V.cleanName(text)
  text = tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if text == '' then return nil end
  return text
end

-- an "xp" message from the server applied to the state (no new state is sent for every kill)
function V.applyXp(state, data)
  for _, p in ipairs(rows(state and state.pets, 'species')) do
    if p.species == data.species then
      p.level, p.xp, p.into, p.need, p.pct = data.level, data.xp, data.into, data.need, data.pct
      return true
    end
  end
  return false
end
