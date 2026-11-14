-- The hub menu without client API (O550): turns the tree (topbar_tree.lua), the cards (topbar_cards.lua) and the usable
-- entries into the hubs, tabs and cards the bar and the hub window draw. chaos_topbar.lua and topbar_hub.lua use it;
-- topbarhublogic_test.lua tests it. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- An item is one usable entry as chaos_topbar.lua sees it: { text = the shown entry text (it may end in " (3)", the
-- Party Finder's count), category = the id the entry was added to, icon = its old topbutton name, key = its hotkey,
-- status = 'open' | 'locked' (a hidden one is not passed), level = the level of a locked one, isNew = bool }.

ChaosTopBarHubLogic = {}
local H = ChaosTopBarHubLogic

H.MAX_PINS = 3
H.DEFAULT_PINS = {}
H.RIGHT_HUB = 'system'     -- the hub that sits alone at the right end of the bar (owner 2026-11-14: where the Store pin was)
H.CARDS_PER_ROW = 4
H.STYLES = { hubs = true, text = true }
H.DEFAULT_STYLE = 'hubs'

-- 'Party Finder (3)' -> 'Party Finder', 3 ; 'Bank' -> 'Bank', nil
function H.baseText(text)
  text = tostring(text or '')
  local base, n = text:match('^(.-)%s*%((%d+)%)$')
  if base and base ~= '' then return base, tonumber(n) end
  return text, nil
end

-- the hub id that holds an old category id (nil for an id nobody knows)
function H.hubOfCategory(tree, categoryId)
  return tree.CATEGORY_HUB[categoryId]
end

function H.hubKey(hubId) return 'hub.' .. hubId end
function H.tabKey(hubId, tabId) return 'tab.' .. hubId .. '.' .. tabId end

-- the shown name of a hub or tab: tr(key) when the language has it, else the English name (the key is returned as it is
-- when there is no translation)
function H.shown(trFn, key, name)
  local ok, v = pcall(trFn, key)
  if ok and type(v) == 'string' and v ~= '' and v ~= key then return v end
  return name
end

-- text -> { hub = hub, tab = tab, slot = i } for every card of the tree
function H.index(tree)
  local byText = {}
  for _, hub in ipairs(tree.HUBS) do
    for _, tab in ipairs(hub.tabs) do
      for i, text in ipairs(tab.cards) do
        byText[text] = { hub = hub, tab = tab, slot = i }
      end
    end
  end
  return byText
end

local function lastTab(hub)
  return hub.tabs[#hub.tabs]
end

-- the model: { hubs = { { id, name, glyph, new, count, tabs = { { id, name, new, count, cards = { card } } } } } }
-- card = { text (the base text, the unlock and run key), shown (the entry text as given), glyph, desc, key, locked (a
-- level) or nil, new, count (number or nil), points (a number the card's module counts, shown as a square badge; nil
-- or 0 = none), extra (not in the tree) }
-- Hidden: dropped and text-only entries, the admin entries unless opts.admin, empty tabs and empty hubs.
function H.build(tree, cards, items, opts)
  opts = opts or {}
  local byText = H.index(tree)
  local placed = {}          -- hub id -> tab id -> list of { slot, card }
  local extras = {}          -- hub id -> list of cards
  local function put(hub, tab, slot, card)
    placed[hub.id] = placed[hub.id] or {}
    placed[hub.id][tab.id] = placed[hub.id][tab.id] or {}
    local list = placed[hub.id][tab.id]
    for _, r in ipairs(list) do
      if r.slot == slot then return end
    end
    list[#list + 1] = { slot = slot, card = card }
  end
  for _, item in ipairs(items or {}) do
    local base, count = H.baseText(item.text)
    local skip = tree.DROPPED[base] or tree.TEXT_ONLY[base]
      or (item.category == 'admin' and not opts.admin)
      or (item.status ~= 'open' and item.status ~= 'locked')
    if not skip then
      local slotText = tree.SHARED[base] or base
      local at = byText[slotText]
      local c = {
        text = base, shown = item.text, key = item.key, count = count,
        locked = item.status == 'locked' and (item.level or 0) or nil,
        new = item.status == 'open' and item.isNew == true,
        points = item.status == 'open' and (item.points == '!' and '!'
          or ((tonumber(item.points) or 0) > 0 and math.floor(tonumber(item.points)) or nil)) or nil,
      }
      if at then
        local def = cards.CARDS[slotText] or {}
        c.glyph, c.desc = def[1] or cards.FALLBACK_GLYPH, def[2] or ''
        put(at.hub, at.tab, at.slot, c)
      else
        local hubId = tree.CATEGORY_HUB[item.category] or 'system'
        c.glyph = cards.ICON_GLYPH[item.icon or ''] or cards.FALLBACK_GLYPH
        c.desc = ''
        c.extra = true
        extras[hubId] = extras[hubId] or {}
        extras[hubId][#extras[hubId] + 1] = c
      end
    end
  end
  local model = { hubs = {} }
  for _, hub in ipairs(tree.HUBS) do
    local out = { id = hub.id, name = hub.name, glyph = hub.glyph, new = false, count = 0, tabs = {} }
    for _, tab in ipairs(hub.tabs) do
      local list = (placed[hub.id] or {})[tab.id] or {}
      table.sort(list, function(a, b) return a.slot < b.slot end)
      local t = { id = tab.id, name = tab.name, new = false, count = 0, cards = {} }
      for _, r in ipairs(list) do t.cards[#t.cards + 1] = r.card end
      if tab == lastTab(hub) then
        for _, c in ipairs(extras[hub.id] or {}) do t.cards[#t.cards + 1] = c end
      end
      for _, c in ipairs(t.cards) do
        if c.new then t.new = true end
        t.count = t.count + (c.count or 0)
      end
      if #t.cards > 0 then
        out.tabs[#out.tabs + 1] = t
        if t.new then out.new = true end
        out.count = out.count + t.count
      end
    end
    if #out.tabs > 0 then model.hubs[#model.hubs + 1] = out end
  end
  return model
end

function H.findHub(model, hubId)
  for i, hub in ipairs(model.hubs) do
    if hub.id == hubId then return hub, i end
  end
  return nil
end

-- a card of the model by its base text: card, hub, tab
function H.findCard(model, text)
  for _, hub in ipairs(model.hubs) do
    for _, tab in ipairs(hub.tabs) do
      for _, c in ipairs(tab.cards) do
        if c.text == text then return c, hub, tab end
      end
    end
  end
  return nil
end

-- ---------------------------------------------------------------- the remembered tab
-- g_settings keys are per character: chaosHubTab_<hub>_<character>; on the login screen there is no character
function H.tabSettingKey(hubId, character)
  return 'chaosHubTab_' .. hubId .. ((character and character ~= '') and ('_' .. character) or '')
end

function H.pinsSettingKey(character)
  return 'chaosHubPins' .. ((character and character ~= '') and ('_' .. character) or '')
end

-- the index of the tab to show: the saved one when it is still there, else the first
function H.pickTab(hub, savedId)
  if savedId then
    for i, tab in ipairs(hub.tabs) do
      if tab.id == savedId then return i end
    end
  end
  return 1
end

-- ---------------------------------------------------------------- pins
-- stored as "v1:Store|Market"; an empty string means never set (the default pin), "v1:" means the player cleared them
function H.parsePins(str)
  if type(str) ~= 'string' or str:sub(1, 3) ~= 'v1:' then return nil end
  local list = {}
  for text in str:sub(4):gmatch('[^|]+') do
    list[#list + 1] = text
    if #list >= H.MAX_PINS then break end
  end
  return list
end

function H.serializePins(list)
  return 'v1:' .. table.concat(list, '|')
end

function H.pinsOrDefault(str)
  local list = H.parsePins(str)
  if list then return list end
  local copy = {}
  for i, t in ipairs(H.DEFAULT_PINS) do copy[i] = t end
  return copy
end

-- toggles a pin: a new list, true when it changed, and 'full' when the bar has no room for one more
function H.togglePin(list, text)
  local out = {}
  local had = false
  for _, t in ipairs(list) do
    if t == text then had = true else out[#out + 1] = t end
  end
  if had then return out, true end
  if #list >= H.MAX_PINS then return list, false, 'full' end
  out[#out + 1] = text
  return out, true
end

function H.isPinned(list, text)
  for _, t in ipairs(list) do
    if t == text then return true end
  end
  return false
end

-- the cards the bar shows pinned, in pin order: the ones the model has (usable now), locked ones included
function H.pinnedCards(model, pins)
  local out = {}
  for _, text in ipairs(pins) do
    local card = H.findCard(model, text)
    if card then out[#out + 1] = card end
  end
  return out
end

-- ---------------------------------------------------------------- the style option
function H.normalizeStyle(value)
  if H.STYLES[value] then return value end
  return H.DEFAULT_STYLE
end

-- 'hubs' or 'text': text when the player chose it, when the icon art is missing, or after the hub code raised an error
function H.resolveStyle(setting, artOk, failed)
  if failed or not artOk then return 'text' end
  return H.normalizeStyle(setting)
end

-- how many rows of cards a tab needs (the window is sized for the busiest tab)
function H.rowsOf(tab)
  return math.ceil(#tab.cards / H.CARDS_PER_ROW)
end

-- ---------------------------------------------------------------- the card grid
H.CARD_W, H.CARD_H, H.CARD_GAP = 182, 68, 6

-- where card number i (1 based) of a tab sits in the cards panel: x, y of its top left corner (cardH: 68, a phone 76)
function H.cardPos(i, cardH)
  local col = (i - 1) % H.CARDS_PER_ROW
  local row = math.floor((i - 1) / H.CARDS_PER_ROW)
  return col * (H.CARD_W + H.CARD_GAP), row * ((cardH or H.CARD_H) + H.CARD_GAP)
end

-- a text cut to fit maxW pixels: measure(text) -> width; the cut ends in ".." when it was cut
function H.fit(text, maxW, measure)
  text = tostring(text or '')
  if measure(text) <= maxW then return text end
  local cut = text
  while #cut > 1 do
    cut = cut:sub(1, #cut - 1)
    local try = cut:gsub('%s+$', '') .. '..'
    if measure(try) <= maxW then return try end
  end
  return cut
end

-- the bar, left to right: the hubs (all but the right one), a divider and the pinned cards, a divider and the right hub
-- (System). A divider is drawn only when something comes before it. Items: { kind = 'hub', hub = hub } | { kind = 'divider' }
-- | { kind = 'pin', card = card }.
function H.barItems(model, pinCards)
  local items, rightHub = {}, nil
  for _, hub in ipairs(model.hubs) do
    if hub.id == H.RIGHT_HUB then rightHub = hub else items[#items + 1] = { kind = 'hub', hub = hub } end
  end
  if #pinCards > 0 then
    if #items > 0 then items[#items + 1] = { kind = 'divider' } end
    for _, card in ipairs(pinCards) do items[#items + 1] = { kind = 'pin', card = card } end
  end
  if rightHub then
    if #items > 0 then items[#items + 1] = { kind = 'divider' } end
    items[#items + 1] = { kind = 'hub', hub = rightHub }
  end
  return items
end

H.DIVIDER_W = 5   -- 1 px line and 2 px margins each side

-- the bar's width for these items: 4 px between children and 16 px of frame
function H.barWidth(items, badge)
  badge = badge or 32
  local w = 16
  for i, it in ipairs(items) do
    w = w + (it.kind == 'divider' and H.DIVIDER_W or badge) + (i > 1 and 4 or 0)
  end
  return w
end

return H
