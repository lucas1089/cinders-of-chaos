-- Customise Character extras: the rules without client API (tested by outfitextrascore_test.lua with luajit and lua5.3).
-- The Customise Character window (base module game_outfit) picks the outfit, mount, aura, shader and preset. The other
-- cosmetics a character owns were only reachable elsewhere: wings (the outfit packet's wings list, which the stock
-- window has no row for), outlines, footprints, kill effects, loot label accents, chat name colours, the spell effect
-- skin of the character's class line (all Character > Cosmetics, server cosmetics.lua), the name plate frame (Info &
-- Services > Services, server shop.lua) and the pet (Character > Pets). Each is one dropdown here.
-- Sources, all optional (a source that has not answered yet leaves its dropdown off):
--   cosmetics  the server's cosmetics state {line, lineName, rows = [{id, kind, name, owned, selected, line}]}
--   wings      {stock = [{look, name}] (the outfit packet's owned wings), wardrobe = [{l, n, o}] (the catalogue), current}
--   services   the Services state {frames = [name], activeFrame}
--   pets       the pets state {pets = [{species, name, speciesName, level}], active, out}
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

OutfitExtrasCore = {}
local E = OutfitExtrasCore

-- the dropdowns, in window order (two columns, left to right then down)
E.KEYS = { 'wings', 'outline', 'footprint', 'killfx', 'lootbeam', 'chatcolor', 'spellskin', 'frame', 'pet' }
E.COSMETIC_KINDS = { outline = true, footprint = true, killfx = true, lootbeam = true, chatcolor = true, spellskin = true }

function E.label(key)
  if key == 'wings' then return tr('Wings')
  elseif key == 'outline' then return tr('Outline')
  elseif key == 'footprint' then return tr('Footprints')
  elseif key == 'killfx' then return tr('Kill effect')
  elseif key == 'lootbeam' then return tr('Loot label')
  elseif key == 'chatcolor' then return tr('Chat colour')
  elseif key == 'spellskin' then return tr('Spell effect')
  elseif key == 'frame' then return tr('Name plate frame')
  elseif key == 'pet' then return tr('Pet')
  end
  return key
end

local function num(v) return tonumber(v) or 0 end

local function capital(s)
  s = tostring(s or '')
  return s:sub(1, 1):upper() .. s:sub(2)
end

-- ---------------------------------------------------------------- one dropdown per source
-- cosmetic kinds: the default, then the rows of the kind the account owns (spell skins: of the character's line only)
function E.cosmeticRow(state, kind)
  if type(state) ~= 'table' or type(state.rows) ~= 'table' then return nil end
  local options = { { text = tr('Default'), value = 0 } }
  local current, locked = 0, 0
  for _, r in ipairs(state.rows) do
    if type(r) == 'table' and r.kind == kind and (kind ~= 'spellskin' or r.line == state.line) then
      if r.owned == true then
        options[#options + 1] = { text = tostring(r.name or r.key or r.id), value = num(r.id) }
        if r.selected then current = num(r.id) end
      else
        locked = locked + 1
      end
    end
  end
  return { key = kind, options = options, current = current, locked = locked, line = kind == 'spellskin' and state.line or nil }
end

-- wings: none, then the owned ones of the outfit packet; the catalogue only counts what is still locked
function E.wingsRow(src)
  if type(src) ~= 'table' then return nil end
  local options = { { text = tr('None'), value = 0 } }
  local have = {}
  for _, w in ipairs(type(src.stock) == 'table' and src.stock or {}) do
    if type(w) == 'table' and num(w[1]) > 0 and not have[num(w[1])] then
      have[num(w[1])] = true
      options[#options + 1] = { text = tostring(w[2] or w[1]), value = num(w[1]) }
    end
  end
  local locked = 0
  for _, c in ipairs(type(src.wardrobe) == 'table' and src.wardrobe or {}) do
    if type(c) == 'table' and num(c.l) > 0 and not have[num(c.l)] then locked = locked + 1 end
  end
  local current = num(src.current)
  if not have[current] then current = 0 end
  return { key = 'wings', options = options, current = current, locked = locked }
end

-- name plate frame: the title's own, then the frames the character owns
function E.frameRow(services)
  if type(services) ~= 'table' then return nil end
  local options = { { text = tr('Title frame'), value = '' } }
  for _, f in ipairs(type(services.frames) == 'table' and services.frames or {}) do
    if type(f) == 'string' and f ~= '' then options[#options + 1] = { text = capital(f), value = f } end
  end
  local current = type(services.activeFrame) == 'string' and services.activeFrame or ''
  local known = false
  for _, o in ipairs(options) do if o.value == current then known = true end end
  if not known then current = '' end
  return { key = 'frame', options = options, current = current, locked = 0 }
end

-- pet: none (dismissed), then the pets the character owns, with their level
function E.petRow(state)
  if type(state) ~= 'table' or type(state.pets) ~= 'table' then return nil end
  local options = { { text = tr('None'), value = '' } }
  local known = {}
  for _, p in ipairs(state.pets) do
    if type(p) == 'table' and type(p.species) == 'string' and p.species ~= '' then
      known[p.species] = true
      local name = tostring(p.name or p.speciesName or p.species)
      options[#options + 1] = { text = p.level and tr('%s (level %d)', name, num(p.level)) or name, value = p.species }
    end
  end
  local current = type(state.active) == 'string' and known[state.active] and state.active or ''
  local locked = 0
  for _, c in ipairs(type(state.catalog) == 'table' and state.catalog or {}) do
    if type(c) == 'table' and c.owned ~= true and not known[c.key] then locked = locked + 1 end
  end
  return { key = 'pet', options = options, current = current, locked = locked }
end

-- all dropdowns that have their data: a list of {key, label, options, current, locked, line?} in window order
function E.rows(src)
  src = src or {}
  local out = {}
  for _, key in ipairs(E.KEYS) do
    local row
    if key == 'wings' then row = E.wingsRow(src.wings)
    elseif key == 'frame' then row = E.frameRow(src.services)
    elseif key == 'pet' then row = E.petRow(src.pets)
    else row = E.cosmeticRow(src.cosmetics, key) end
    if row then
      row.label = E.label(key)
      out[#out + 1] = row
    end
  end
  return out
end

-- the index (1-based) of the option with this value, or nil
function E.indexOf(row, value)
  for i, o in ipairs(type(row) == 'table' and row.options or {}) do
    if o.value == value then return i end
  end
  return nil
end

-- tooltip of a dropdown: what is locked
function E.tooltip(row)
  if type(row) ~= 'table' or (row.locked or 0) <= 0 then return nil end
  return tr('%d more not unlocked yet. See Character > Cosmetics and the Store.', row.locked)
end

-- ---------------------------------------------------------------- Ok
-- rows = E.rows(...) as shown; chosen = {[key] = value} of the dropdowns the player changed. Returns the actions, in
-- order, for the keys whose choice differs from the shown one. Wings are not here: they travel with the outfit.
--   {act = 'cosmetic', kind, id, line}   {act = 'frame', value}   {act = 'pet', value}
function E.plan(rows, chosen)
  local actions = {}
  if type(chosen) ~= 'table' then return actions end
  for _, row in ipairs(type(rows) == 'table' and rows or {}) do
    local value = chosen[row.key]
    if value ~= nil and value ~= row.current and row.key ~= 'wings' and E.indexOf(row, value) then
      if E.COSMETIC_KINDS[row.key] then
        actions[#actions + 1] = { act = 'cosmetic', kind = row.key, id = value, line = row.line }
      elseif row.key == 'frame' then
        actions[#actions + 1] = { act = 'frame', value = value }
      elseif row.key == 'pet' then
        actions[#actions + 1] = { act = 'pet', value = value }
      end
    end
  end
  return actions
end

-- how many dropdown rows the window needs (two columns)
function E.lineCount(rows)
  return math.ceil(#(rows or {}) / 2)
end
