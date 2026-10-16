-- Unlocks: the one rule every appearance list follows (client/MANIFEST.md "Owned and locked lists"); no client API,
-- unlocks_core_test.lua runs it under LuaJIT and Lua 5.3.
-- Every list of the Customise Character window (outfits, mounts, auras, shaders, presets) and of the Cosmetics window
-- (spell effects, kill effects, loot labels, chat colours, footprints, outlines, the Collection) shows everything the
-- game has. What the character does not own is greyed out, cannot be used (the window's Use / Ok stays disabled, and
-- the server refuses it anyway), and its tooltip says where it comes from. An "Only mine" box hides the locked
-- entries; its state is kept per character and per list.
-- The outfit window's own packet lists only what is owned; the rest comes from the server's wardrobe catalogue
-- (server wardrobe.lua, cosmetics opcode 225, action "wardrobe"): per kind {l = look, n = name, o = 1 owned,
-- a = owned addons, s = source}; shaders {n = shader name, o, s}.

UnlocksCore = UnlocksCore or {}
local U = UnlocksCore

local function tr(s, ...)
  local g = rawget(_G, 'tr')
  if g then return g(s, ...) end
  if select('#', ...) > 0 then return string.format(s, ...) end
  return s
end

local function num(v) return tonumber(v) or 0 end

U.LISTS = { 'outfit', 'mount', 'aura', 'shader', 'preset', 'wings',
  'spellskin', 'killfx', 'lootbeam', 'chatcolor', 'footprint', 'outline', 'collection' }
U.LOCKED_OPACITY = 0.45

-- ---------------------------------------------------------------- one entry
-- An entry of any list is "locked" when its `locked` field is true (outfit window entries made here) or, for a
-- Cosmetics row, when `owned` is not true. The default row of a Cosmetics tab (id 0) is never locked.
function U.isLocked(e)
  if type(e) ~= 'table' then return false end
  if e.locked ~= nil then return e.locked == true end
  if e.id == 0 then return false end
  if e.owned ~= nil or e.kind ~= nil then return e.owned ~= true end
  return false
end

function U.canUse(e)
  return type(e) == 'table' and not U.isLocked(e)
end

-- the tooltip of an entry: where a locked one comes from, or that it is owned (and where from, when known)
function U.tooltip(e)
  if type(e) ~= 'table' then return nil end
  local how = e.how
  if type(how) ~= 'string' or how == '' then how = nil end
  if U.isLocked(e) then
    return how and (tr('Not unlocked yet.') .. '\n' .. tr('How to get it: %s', tr(how))) or tr('Not unlocked yet.')
  end
  return how and (tr('Unlocked.') .. '\n' .. tr(how)) or nil
end

-- ---------------------------------------------------------------- filtering and order
-- owned entries first, then the locked ones, each in their order; onlyMine drops the locked ones
function U.filter(list, onlyMine)
  local mine, locked = {}, {}
  for _, e in ipairs(type(list) == 'table' and list or {}) do
    if U.isLocked(e) then locked[#locked + 1] = e else mine[#mine + 1] = e end
  end
  if not onlyMine then
    for _, e in ipairs(locked) do mine[#mine + 1] = e end
  end
  return mine
end

-- counts for a status line: owned, all
function U.count(list)
  local have, all = 0, 0
  for _, e in ipairs(type(list) == 'table' and list or {}) do
    all = all + 1
    if not U.isLocked(e) then have = have + 1 end
  end
  return have, all
end

-- ---------------------------------------------------------------- the outfit window's lists
-- The stock lists are tuples: outfit {look, name, addons, ...}, mount {look, name, offer}, aura {id, category,
-- clientId, name}; shaders are game_chaosshaders rows {id, name, label}. display(kind, stock, catalogue) returns the
-- stock entries (owned, with the catalogue's source as `how`) followed by every catalogue entry the stock list does
-- not hold, as a tuple of the same shape with locked = true. A catalogue entry the stock list lacks is locked even if
-- the catalogue says owned: the window's packet is what the engine lets the character wear.
local KEY = {
  outfit = function(e) return num(e[1]) end,
  mount = function(e) return num(e[1]) end,
  aura = function(e) return num(e[3] or e[1]) end,
  wings = function(e) return num(e[1]) end,
  shader = function(e) return e.name end,
}

local MAKE = {
  outfit = function(c) return { c.l, c.n, 0 } end,
  mount = function(c) return { c.l, c.n, 0 } end,
  aura = function(c) return { c.l, 0, c.l, c.n } end,
  wings = function(c) return { c.l, c.n } end,
  shader = function(c) return { id = 0, name = c.n, label = c.label or c.n } end,
}

local function catKey(kind, c)
  if kind == 'shader' then return c.n end
  return num(c.l)
end

function U.display(kind, stock, catalogue, label)
  local key, make = KEY[kind], MAKE[kind]
  local out, have = {}, {}
  if not key then return type(stock) == 'table' and stock or {} end
  local src = {}
  for _, c in ipairs(type(catalogue) == 'table' and catalogue or {}) do
    if type(c) == 'table' then src[catKey(kind, c)] = c end
  end
  for _, e in ipairs(type(stock) == 'table' and stock or {}) do
    if type(e) == 'table' then
      local k = key(e)
      have[k] = true
      local c = src[k]
      if c and c.s and e.how == nil then e.how = c.s end
      out[#out + 1] = e
    end
  end
  for _, c in ipairs(type(catalogue) == 'table' and catalogue or {}) do
    local k = type(c) == 'table' and catKey(kind, c) or nil
    if k and k ~= 0 and k ~= '' and not have[k] then
      have[k] = true
      local e = make({ l = c.l, n = c.n, label = kind == 'shader' and label and label(c.n) or nil })
      e.locked = true
      e.how = c.s
      out[#out + 1] = e
    end
  end
  return out
end

-- the parts of an outfit the character cannot wear: a list of kinds (empty = Ok may be pressed).
-- outfit = the window's choice {type, mount, aura, shader}; locked = {outfit = {[look] = true}, mount = ..., aura =
-- {[clientId] = true}, shader = {[name] = true}}; opts.mounted / opts.aura: is the mount / aura part in use
function U.lockedParts(outfit, locked, opts)
  local out = {}
  if type(outfit) ~= 'table' then return out end
  locked = locked or {}
  opts = opts or {}
  local function hit(kind, k) return locked[kind] and k ~= nil and locked[kind][k] == true end
  if hit('outfit', num(outfit.type)) then out[#out + 1] = 'outfit' end
  if opts.mounted ~= false and num(outfit.mount) > 0 and hit('mount', num(outfit.mount)) then out[#out + 1] = 'mount' end
  if opts.aura ~= false and num(outfit.aura) > 0 and hit('aura', num(outfit.aura)) then out[#out + 1] = 'aura' end
  if type(outfit.shader) == 'string' and outfit.shader ~= '' and hit('shader', outfit.shader) then out[#out + 1] = 'shader' end
  return out
end

-- the locked sets of a catalogue (the keys lockedParts reads), from display lists {kind = list}
function U.lockedSets(lists)
  local sets = {}
  for kind, list in pairs(type(lists) == 'table' and lists or {}) do
    local key = KEY[kind]
    sets[kind] = {}
    for _, e in ipairs(list) do
      if key and U.isLocked(e) then sets[kind][key(e)] = true end
    end
  end
  return sets
end

-- a preset (a saved outfit) is locked when one of its parts is
function U.presetLocked(outfit, sets)
  return #U.lockedParts(outfit, sets) > 0
end

-- ---------------------------------------------------------------- the wardrobe message
-- a server "wardrobe" answer -> {outfit, mount, wings, aura, shader} lists (bad parts dropped), or nil
function U.readWardrobe(data)
  if type(data) ~= 'table' then return nil end
  local out = { sex = data.sex, hash = data.hash }
  for _, kind in ipairs({ 'outfit', 'mount', 'wings', 'aura', 'shader' }) do
    out[kind] = {}
    for _, c in ipairs(type(data[kind]) == 'table' and data[kind] or {}) do
      if type(c) == 'table' and (kind == 'shader' and type(c.n) == 'string' or num(c.l) > 0) then
        out[kind][#out[kind] + 1] = { l = num(c.l), n = type(c.n) == 'string' and c.n or '', o = c.o == 1 or c.o == true,
          a = c.a, s = type(c.s) == 'string' and c.s or nil }
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------- the "Only mine" setting
-- one settings node for every list: {[character] = {[list] = true}}; returns the new node (a copy)
function U.setOnlyMine(node, character, list, on)
  local out = {}
  for k, v in pairs(type(node) == 'table' and node or {}) do
    if type(v) == 'table' then
      local c = {}
      for kk, vv in pairs(v) do c[kk] = vv end
      out[k] = c
    end
  end
  if type(character) ~= 'string' or character == '' or type(list) ~= 'string' then return out end
  out[character] = out[character] or {}
  out[character][list] = on and true or nil
  if next(out[character]) == nil then out[character] = nil end
  return out
end

function U.onlyMine(node, character, list)
  local c = type(node) == 'table' and node[character] or nil
  return type(c) == 'table' and c[list] == true
end

return U
