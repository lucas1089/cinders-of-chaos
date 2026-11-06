-- Customise Character (O421): the rules of the one-window layout, without client API (tested by customisecore_test.lua
-- with luajit and lua5.3; OutfitExtrasCore is loaded first). The window (outfitextras.lua) has a large preview with layer
-- checkboxes, a card grid per category with a search box, the colour palette and an Equipped now strip. This file holds:
--   the category list and the strip slots (what the client and the server already support),
--   the cards of a category (outfit, mount, wings, aura, shader from the outfit packet and the wardrobe catalogue; the
--   other cosmetics from OutfitExtrasCore), the search filter and "Only mine",
--   the Equipped now rows from the outfit being edited and the cosmetics state,
--   layer visibility turned into the outfit and the option the look preview draws, and into what Ok sends,
--   the colour palette (the 7 x 19 outfit colours) and the addon bits.
-- Layers left out because nothing in the client or the server backs them: health bar, mana bar, ornament and title (the
-- name plate frame is the nearest thing to an ornament and is the Plate frame category).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

CustomiseCore = {}
local C = CustomiseCore
local E = OutfitExtrasCore

local function num(v) return tonumber(v) or 0 end

local function copy(t)
  local o = {}
  for k, v in pairs(type(t) == 'table' and t or {}) do o[k] = v end
  return o
end
C.copy = copy

-- ---------------------------------------------------------------- the lists
C.LOOK_KEYS = { outfit = true, mount = true, wings = true, aura = true, shader = true }
-- the cards of the Equipped now strip, in order (the grid shows the one clicked)
C.SLOTS = { 'outfit', 'mount', 'wings', 'aura', 'shader', 'outline', 'spellskin', 'killfx', 'footprint', 'lootbeam',
  'chatcolor', 'frame', 'pet' }
-- the layer checkboxes under the preview. 'outfit' only shows or hides the outfit in the preview (the plain figure
-- stands in); the others are worn or not: unchecked, Ok sends none of it. Animated is the preview's own Walk box.
C.LAYERS = { 'outfit', 'mount', 'wings', 'aura', 'shader', 'outline', 'pet' }
C.LAYER_SET = { outfit = true, mount = true, wings = true, aura = true, shader = true, outline = true, pet = true }
-- the colour tabs and the outfit field each paints
C.TABS = { { key = 'head', field = 'head' }, { key = 'primary', field = 'body' }, { key = 'secondary', field = 'legs' },
  { key = 'detail', field = 'feet' } }
C.COLORS = 133 -- 7 rows x 19 columns, index = row * 19 + column
C.COLUMNS = 19

function C.label(key)
  if key == 'outfit' then return tr('Outfit')
  elseif key == 'mount' then return tr('Mount')
  elseif key == 'aura' then return tr('Aura')
  elseif key == 'shader' then return tr('Shader')
  end
  return E.label(key)
end

function C.tabLabel(key)
  if key == 'head' then return tr('Head')
  elseif key == 'primary' then return tr('Primary')
  elseif key == 'secondary' then return tr('Secondary')
  elseif key == 'detail' then return tr('Detail')
  end
  return key
end

function C.fieldOf(tab)
  for _, t in ipairs(C.TABS) do
    if t.key == tab then return t.field end
  end
  return nil
end

-- the value that means "none" for a category
function C.defaultValue(key)
  if key == 'shader' or key == 'frame' or key == 'pet' then return '' end
  return 0
end

-- ---------------------------------------------------------------- colours
-- the outfit colour table of the engine (Outfit::getColor): 19 hues by 7 steps; column 0 is the grey ramp
local STEPS = {
  [0] = { 0.25, 1.0 }, { 0.25, 0.75 }, { 0.5, 0.75 }, { 0.667, 0.75 }, { 1.0, 1.0 }, { 1.0, 0.75 }, { 1.0, 0.5 },
}
function C.colorOf(index)
  index = math.floor(num(index))
  if index < 0 or index >= C.COLORS then index = 0 end
  local h, s, v
  if index % 19 ~= 0 then
    h = (index % 19) / 18
    local st = STEPS[math.floor(index / 19)]
    s, v = st[1], st[2]
  else
    h, s, v = 0, 0, 1 - math.floor(index / 19) / 7
  end
  if v == 0 then return 0, 0, 0 end
  if s == 0 then
    local g = math.floor(v * 255)
    return g, g, g
  end
  local r, g, b
  if h < 1 / 6 then
    r = v; b = v * (1 - s); g = b + (v - b) * h * 6
  elseif h < 2 / 6 then
    g = v; b = v * (1 - s); r = g - (v - b) * (h * 6 - 1)
  elseif h < 3 / 6 then
    g = v; r = v * (1 - s); b = r + (v - r) * (h * 6 - 2)
  elseif h < 4 / 6 then
    b = v; r = v * (1 - s); g = b - (v - r) * (h * 6 - 3)
  elseif h < 5 / 6 then
    b = v; g = v * (1 - s); r = g + (v - g) * (h * 6 - 4)
  else
    r = v; g = v * (1 - s); b = r - (v - g) * (h * 6 - 5)
  end
  return math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
end

function C.colorHex(index)
  local r, g, b = C.colorOf(index)
  return string.format('#%02x%02x%02x', r, g, b)
end

-- the outfit with one colour part set (clamped to the table)
function C.setColor(temp, tab, index)
  local field = C.fieldOf(tab)
  local o = copy(temp)
  if field then o[field] = math.max(0, math.min(C.COLORS - 1, math.floor(num(index)))) end
  return o
end

-- ---------------------------------------------------------------- addons
-- the outfit list entry's third value is the bit mask of the addons the character owns for it
function C.addonOwned(bits, addon) return math.floor(math.floor(num(bits)) / addon) % 2 == 1 end

function C.setAddon(temp, addon, on)
  local o = copy(temp)
  local have = math.floor(num(o.addons))
  local has = math.floor(have / addon) % 2 == 1
  if on and not has then have = have + addon elseif not on and has then have = have - addon end
  o.addons = have
  return o
end

-- ---------------------------------------------------------------- the cards of a category
-- ctx = { lists = {outfit, mount, aura, shader (the window's lists with the locked ones, UnlocksCore.display)},
--         src = OutfitExtrasCore sources, onlyMine = bool, search = text }
-- a card: {value, text, locked?, how?, none?, addons? (outfit), row? (cosmetic), look? (pet)}

-- one entry of the packet's lists as a card (outfit {look, name, addons}, mount {look, name}, aura {id, category,
-- clientId, name}, shader {id, name, label}); nil for the ones without a value
local function entryCard(kind, e)
  if type(e) ~= 'table' then return nil end
  local c
  if kind == 'outfit' then
    c = { value = num(e[1]), text = tostring(e[2] or e[1]), addons = num(e[3]) }
  elseif kind == 'mount' then
    c = { value = num(e[1]), text = tostring(e[2] or e[1]) }
  elseif kind == 'aura' then
    c = { value = num(e[3] or e[1]), text = tostring(e[4] or e[2] or e[3] or e[1]) }
  elseif kind == 'shader' then
    if type(e.name) ~= 'string' or e.name == '' then return nil end
    c = { value = e.name, text = tostring(e.label or e.name) }
  end
  if not c or c.value == 0 or c.value == '' then return nil end
  c.locked = e.locked == true or nil
  c.how = e.how
  return c
end

function C.lookCards(kind, list)
  local out = {}
  for _, e in ipairs(type(list) == 'table' and list or {}) do
    local c = entryCard(kind, e)
    if c then out[#out + 1] = c end
  end
  return out
end

-- owned cards first, then the locked ones; onlyMine drops the locked ones
local function ordered(cards, onlyMine)
  local mine, locked = {}, {}
  for _, c in ipairs(cards) do
    if c.locked then locked[#locked + 1] = c else mine[#mine + 1] = c end
  end
  if not onlyMine then
    for _, c in ipairs(locked) do mine[#mine + 1] = c end
  end
  return mine
end

-- the search filter: the cards whose text holds the words (plain text, any case, surrounding blanks ignored)
function C.search(cards, query)
  local q = type(query) == 'string' and query:lower():gsub('^%s+', ''):gsub('%s+$', '') or ''
  if q == '' then return cards end
  local out = {}
  for _, c in ipairs(cards) do
    if tostring(c.text):lower():find(q, 1, true) then out[#out + 1] = c end
  end
  return out
end

-- the cards of a category, or nil while its data has not come yet
function C.cards(key, ctx)
  ctx = ctx or {}
  local query = type(ctx.search) == 'string' and ctx.search or ''
  if key == 'outfit' or key == 'mount' or key == 'aura' or key == 'shader' then
    local list = type(ctx.lists) == 'table' and ctx.lists[key] or nil
    if type(list) ~= 'table' then return nil end
    local cards = ordered(C.lookCards(key, list), ctx.onlyMine)
    cards = C.search(cards, query)
    if key ~= 'outfit' and C.search({ { text = tr('None') } }, query)[1] then
      table.insert(cards, 1, { value = C.defaultValue(key), text = tr('None'), none = true })
    end
    return cards
  end
  local choices = E.choices(ctx.src, key, ctx.onlyMine, query)
  if not choices then return nil end
  local out = {}
  for _, ch in ipairs(choices) do
    out[#out + 1] = { value = ch.value, text = ch.text, locked = ch.locked, how = ch.how, row = ch.row, look = ch.look,
      none = ch.value == C.defaultValue(key) or nil }
  end
  return out
end

-- how many a category holds (owned, all), for the title line
function C.count(cards)
  local have = 0
  for _, c in ipairs(cards or {}) do
    if not c.locked and not c.none then have = have + 1 end
  end
  local all = 0
  for _, c in ipairs(cards or {}) do
    if not c.none then all = all + 1 end
  end
  return have, all
end

-- ---------------------------------------------------------------- the outfit a card draws
-- the look a card of the grid or the strip draws (nil: no picture, a text card): outfit cards the look with the
-- addons owned, mounts the mount alone, wings / aura / shader the outfit being edited with that part, pets alone
function C.cardLook(key, card, temp)
  if type(card) ~= 'table' or card.none then return nil end
  temp = type(temp) == 'table' and temp or {}
  if key == 'outfit' then
    local o = { type = num(card.value), head = num(temp.head), body = num(temp.body), legs = num(temp.legs),
      feet = num(temp.feet), addons = card.addons or num(temp.addons) }
    return o
  elseif key == 'mount' then
    return { type = num(card.value) }
  elseif key == 'wings' or key == 'aura' or key == 'shader' then
    local o = { type = num(temp.type), head = num(temp.head), body = num(temp.body), legs = num(temp.legs),
      feet = num(temp.feet), addons = num(temp.addons), mount = 0, wings = 0, aura = 0, shader = '' }
    o[key] = card.value
    return o
  elseif key == 'pet' then
    return num(card.look) > 0 and { type = num(card.look) } or nil
  end
  return nil
end

-- the outfit being edited with a card applied (the card's value in its field; an outfit keeps only the addons both
-- the old selection and the new look allow)
function C.applyCard(temp, key, card)
  local o = copy(temp)
  if type(card) ~= 'table' then return o end
  if key == 'outfit' then
    o.type = num(card.value)
    if card.addons ~= nil then
      local keep = 0
      for _, a in ipairs({ 1, 2 }) do
        if C.addonOwned(o.addons, a) and C.addonOwned(card.addons, a) then keep = keep + a end
      end
      o.addons = keep
    end
  elseif key == 'mount' or key == 'wings' or key == 'aura' then
    o[key] = num(card.value)
  elseif key == 'shader' then
    o.shader = type(card.value) == 'string' and card.value or ''
  end
  return o
end

-- ---------------------------------------------------------------- layers
-- the layers at the start: what the character wears now (extras: what the cosmetics and pet states say)
function C.layerDefaults(temp, rows)
  temp = type(temp) == 'table' and temp or {}
  local layers = { outfit = true, mount = num(temp.mount) > 0, wings = num(temp.wings) > 0, aura = num(temp.aura) > 0,
    shader = type(temp.shader) == 'string' and temp.shader ~= '', outline = false, pet = false }
  for _, r in ipairs(type(rows) == 'table' and rows or {}) do
    if r.key == 'outline' then layers.outline = r.current ~= 0 end
    if r.key == 'pet' then layers.pet = r.current ~= '' end
  end
  return layers
end

-- a pick turns its layer on, picking "none" turns it off (the outfit layer is the preview's own)
function C.pickLayers(layers, key, card)
  local out = copy(layers)
  if C.LAYER_SET[key] and key ~= 'outfit' and type(card) == 'table' then out[key] = not card.none end
  return out
end

-- the outfit the preview draws: layers off are left out; no outfit layer = the plain figure the preview uses
C.NEUTRAL = { type = 128, head = 76, body = 57, legs = 76, feet = 95, addons = 0 }
function C.shown(temp, layers)
  layers = layers or {}
  local o = copy(temp)
  if layers.outfit == false then
    for k, v in pairs(C.NEUTRAL) do o[k] = v end
  end
  if layers.mount == false then o.mount = 0 end
  if layers.wings == false then o.wings = 0 end
  if layers.aura == false then o.aura = 0 end
  if layers.shader == false then o.shader = '' end
  return o
end

-- ---------------------------------------------------------------- the values in use
-- key -> the value worn once Ok is pressed: the outfit's fields (a layer off is none), the extras as picked, else as
-- they are now; the extras' layers (outline, pet) off are none
function C.values(temp, rows, chosen, layers)
  temp = type(temp) == 'table' and temp or {}
  chosen = type(chosen) == 'table' and chosen or {}
  layers = layers or {}
  local v = {
    outfit = num(temp.type),
    mount = layers.mount == false and 0 or num(temp.mount),
    wings = layers.wings == false and 0 or num(temp.wings),
    aura = layers.aura == false and 0 or num(temp.aura),
    shader = (layers.shader == false or type(temp.shader) ~= 'string') and '' or temp.shader,
  }
  for _, r in ipairs(type(rows) == 'table' and rows or {}) do
    if r.key ~= 'wings' then
      local x = chosen[r.key]
      if x == nil then x = r.current end
      if (r.key == 'outline' or r.key == 'pet') and layers[r.key] == false then x = C.defaultValue(r.key) end
      v[r.key] = x
    end
  end
  return v
end

-- the choices Ok sends through OutfitExtrasCore.plan: the picks, and a layer left off sends its default
function C.effective(rows, chosen, layers)
  local out = copy(chosen)
  layers = layers or {}
  if layers.outline == false then out.outline = C.defaultValue('outline') end
  if layers.pet == false then out.pet = C.defaultValue('pet') end
  return out
end

-- the outfit for g_game.changeOutfit: layers off are none; the shader goes through the window's outgoing check
function C.outfitToSend(temp, layers, outgoingShader)
  layers = layers or {}
  local o = copy(temp)
  if layers.mount == false then o.mount = 0 end
  if layers.wings == false then o.wings = 0 end
  if layers.aura == false then o.aura = 0 end
  if layers.shader == false or type(o.shader) ~= 'string' then o.shader = '' end
  if type(outgoingShader) == 'function' then o.shader = outgoingShader(o.shader) end
  return o
end

-- is this card the one in use (the grid marks it)
function C.isCurrent(key, card, values)
  if type(card) ~= 'table' or type(values) ~= 'table' then return false end
  local cur = values[key]
  if cur == nil then return false end
  return card.value == cur
end

-- ---------------------------------------------------------------- the preview
local function rowOption(row, value)
  for _, o in ipairs(type(row) == 'table' and row.options or {}) do
    if o.value == value then return o end
  end
  return nil
end

-- the option for the cosmetic row of a card (a cosmetics state row): the outline, the prints, the effects played
local function cosmeticOption(r)
  if type(r) ~= 'table' then return nil end
  if r.kind == 'outline' then
    return num(r.id) ~= 0 and type(r.art) == 'string' and r.art ~= '' and { kind = 'outline', art = r.art, pulse = r.pulse == true } or nil
  elseif r.kind == 'footprint' then
    return num(r.id) ~= 0 and type(r.art) == 'string' and r.art ~= '' and { kind = 'footprint', art = r.art } or nil
  elseif (r.kind == 'spellskin' or r.kind == 'killfx') and type(r.play) == 'table' and #r.play > 0 then
    return { kind = 'effects', play = r.play, killfx = r.kind == 'killfx' or nil }
  end
  return nil
end

-- the outline the preview draws for what is in use (the outline layer on, a chosen or worn outline with art)
function C.outlineOption(rows, values, layers)
  if type(layers) == 'table' and layers.outline == false then return nil end
  local want = type(values) == 'table' and values.outline or nil
  if want == nil or want == 0 then return nil end
  for _, r in ipairs(type(rows) == 'table' and rows or {}) do
    if r.key == 'outline' then
      local o = rowOption(r, want)
      return o and cosmeticOption(o.row) or nil
    end
  end
  return nil
end

-- the option of a card under the mouse: the outfit with that card on it (its layer shown, the outline kept), or the
-- effect the card plays; nil when the card shows nothing (chat colours, loot labels, frames)
function C.hoverOption(temp, layers, key, card, outline)
  if type(card) ~= 'table' then return nil end
  if C.LOOK_KEYS[key] then
    local shownLayers = copy(layers)
    shownLayers[key] = true
    shownLayers.outfit = shownLayers.outfit ~= false or key == 'outfit'
    local o = C.shown(C.applyCard(temp, key, card), shownLayers)
    local look = { kind = 'look', outfit = o }
    if outline then return { kind = 'bundle', parts = { look, outline } } end
    return look
  end
  if key == 'pet' then
    return num(card.look) > 0 and { kind = 'subject', look = num(card.look) } or nil
  end
  local opt = cosmeticOption(card.row)
  if not opt then return nil end
  if opt.kind == 'outline' then
    return { kind = 'bundle', parts = { { kind = 'look', outfit = C.shown(temp, layers) }, opt } }
  end
  return opt
end

-- ---------------------------------------------------------------- Equipped now
-- ctx = { temp, lists, src, rows (OutfitExtrasCore.rows), chosen, layers }
-- returns one row per slot: {key, label, name, empty, icon, loading}; name is the choice's text or "-"
--   icon = {kind = 'outfit', outfit} | {kind = 'play', row} | {kind = 'print', art} | nil
function C.stripRows(ctx)
  ctx = ctx or {}
  local temp = type(ctx.temp) == 'table' and ctx.temp or {}
  local vals = C.values(temp, ctx.rows, ctx.chosen, ctx.layers)
  local byKey = {}
  for _, r in ipairs(type(ctx.rows) == 'table' and ctx.rows or {}) do byKey[r.key] = r end
  local out = {}
  for _, key in ipairs(C.SLOTS) do
    local row = { key = key, label = C.label(key), name = '-', empty = true }
    local value = vals[key]
    local card
    if key == 'outfit' or key == 'mount' or key == 'aura' or key == 'shader' then
      for _, c in ipairs(C.lookCards(key, type(ctx.lists) == 'table' and ctx.lists[key] or nil)) do
        if c.value == value then card = c break end
      end
      -- worn but not in the list (the list has not come yet): its id
      if not card and value ~= nil and value ~= C.defaultValue(key) then card = { value = value, text = tostring(value) } end
      if card and key == 'outfit' then card.addons = num(temp.addons) end
    elseif key == 'wings' then
      local w = byKey.wings
      local opt = w and rowOption(w, value)
      if opt and value ~= 0 then card = { value = value, text = opt.text } end
    else
      local r = byKey[key]
      if not r then
        row.loading = true
      else
        local opt = rowOption(r, value)
        if opt and value ~= C.defaultValue(key) then
          card = { value = value, text = opt.text, row = opt.row, look = opt.look }
        end
      end
    end
    if card then
      row.name, row.empty = card.text, false
      local look = C.cardLook(key, card, temp)
      if look then
        row.icon = { kind = 'outfit', outfit = look }
      elseif card.row and (key == 'spellskin' or key == 'killfx') and type(card.row.play) == 'table' then
        row.icon = { kind = 'play', row = card.row }
      elseif card.row and key == 'footprint' and type(card.row.art) == 'string' then
        row.icon = { kind = 'print', art = card.row.art }
      end
    end
    out[#out + 1] = row
  end
  return out
end
