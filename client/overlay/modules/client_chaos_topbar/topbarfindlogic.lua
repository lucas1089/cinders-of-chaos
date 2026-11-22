-- The favourites and the search of the hub menu without client API (O718). topbar_hub.lua draws them; topbarfindlogic_test.lua
-- tests them. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- Favourites: a list of card texts (the base text, as the pins), saved per character in g_settings as "v1:Inventory|Market".
-- Search: every card of the model (all hubs, all tabs, the pin-only ones) matched by its English and pt-BR name, its line,
-- its hub and tab, its hotkey and the keywords of topbar_keywords.lua. Every word of the query must be found (accents and
-- case do not count).

ChaosTopBarFindLogic = {}
local F = ChaosTopBarFindLogic

F.MAX_FAVS = 24
F.PAGE = 8            -- cards on one page of the Favourites window (two rows of four)
F.MAX_RESULTS = 8     -- results drawn at once (two rows); the rest is named in the hint
F.MIN_QUERY = 1
F.FAV_HUB = 'favs'
F.SEARCH_HUB = 'search'
F.HOTKEY = 'Ctrl+K'   -- Ctrl+F is the passive tree's own find key

-- ---------------------------------------------------------------- favourites
function F.favsSettingKey(character)
  return 'chaosHubFavs' .. ((character and character ~= '') and ('_' .. character) or '')
end

-- "v1:A|B" -> { 'A', 'B' } (no duplicates, at most MAX_FAVS); anything else (never set) -> {}
function F.parseFavs(str)
  local list, seen = {}, {}
  if type(str) ~= 'string' or str:sub(1, 3) ~= 'v1:' then return list end
  for text in str:sub(4):gmatch('[^|]+') do
    if not seen[text] then
      seen[text] = true
      list[#list + 1] = text
      if #list >= F.MAX_FAVS then break end
    end
  end
  return list
end

function F.serializeFavs(list)
  return 'v1:' .. table.concat(list, '|')
end

function F.isFav(list, text)
  for _, t in ipairs(list) do
    if t == text then return true end
  end
  return false
end

-- toggles a favourite: a new list, true when it changed, 'full' when there is no room for one more
function F.toggleFav(list, text)
  local out, had = {}, false
  for _, t in ipairs(list) do
    if t == text then had = true else out[#out + 1] = t end
  end
  if had then return out, true end
  if #list >= F.MAX_FAVS then return list, false, 'full' end
  out[#out + 1] = text
  return out, true
end

-- the favourites as a virtual hub for the hub window: { id = 'favs', name, tabs = { { id = 'p1', name, cards } } }. The cards
-- are the ones the model has (usable now, locked included), in the order of the hubs of the tree, so the list does not
-- jump about when one is added; a favourite no longer in the model (a module gone) is skipped, not deleted. No cards: no tabs.
-- pageName(i, pages) -> the tab text.
function F.favHub(model, favs, name, pageName)
  local want = {}
  for _, t in ipairs(favs) do want[t] = true end
  local cards = {}
  local function take(c)
    if want[c.text] then
      want[c.text] = false
      cards[#cards + 1] = c
    end
  end
  for _, hub in ipairs(model.hubs) do
    for _, tab in ipairs(hub.tabs) do
      for _, c in ipairs(tab.cards) do take(c) end
    end
  end
  for _, c in ipairs(model.pinOnly or {}) do take(c) end
  local hub = { id = F.FAV_HUB, name = name, glyph = 'starsolid', tabs = {}, count = 0, new = false }
  local pages = math.ceil(#cards / F.PAGE)
  for p = 1, pages do
    local t = { id = 'p' .. p, name = pageName(p, pages), cards = {}, count = 0, new = false }
    for i = (p - 1) * F.PAGE + 1, math.min(#cards, p * F.PAGE) do t.cards[#t.cards + 1] = cards[i] end
    hub.tabs[#hub.tabs + 1] = t
  end
  return hub
end

-- ---------------------------------------------------------------- text folding
local FOLD = {
  ['\xc3\xa0'] = 'a', ['\xc3\xa1'] = 'a', ['\xc3\xa2'] = 'a', ['\xc3\xa3'] = 'a', ['\xc3\xa4'] = 'a',
  ['\xc3\xa7'] = 'c', ['\xc3\xa8'] = 'e', ['\xc3\xa9'] = 'e', ['\xc3\xaa'] = 'e', ['\xc3\xab'] = 'e',
  ['\xc3\xac'] = 'i', ['\xc3\xad'] = 'i', ['\xc3\xae'] = 'i', ['\xc3\xaf'] = 'i', ['\xc3\xb1'] = 'n',
  ['\xc3\xb2'] = 'o', ['\xc3\xb3'] = 'o', ['\xc3\xb4'] = 'o', ['\xc3\xb5'] = 'o', ['\xc3\xb6'] = 'o',
  ['\xc3\xb9'] = 'u', ['\xc3\xba'] = 'u', ['\xc3\xbb'] = 'u', ['\xc3\xbc'] = 'u',
  ['\xc3\x80'] = 'a', ['\xc3\x81'] = 'a', ['\xc3\x82'] = 'a', ['\xc3\x83'] = 'a', ['\xc3\x84'] = 'a',
  ['\xc3\x87'] = 'c', ['\xc3\x88'] = 'e', ['\xc3\x89'] = 'e', ['\xc3\x8a'] = 'e', ['\xc3\x8b'] = 'e',
  ['\xc3\x8c'] = 'i', ['\xc3\x8d'] = 'i', ['\xc3\x8e'] = 'i', ['\xc3\x8f'] = 'i', ['\xc3\x91'] = 'n',
  ['\xc3\x92'] = 'o', ['\xc3\x93'] = 'o', ['\xc3\x94'] = 'o', ['\xc3\x95'] = 'o', ['\xc3\x96'] = 'o',
  ['\xc3\x99'] = 'u', ['\xc3\x9a'] = 'u', ['\xc3\x9b'] = 'u', ['\xc3\x9c'] = 'u',
}

-- lower case, accents off, anything that is not a letter or digit becomes one space
function F.fold(text)
  text = tostring(text or '')
  text = text:gsub('\xc3[\x80-\xbf]', function(ch) return FOLD[ch] or ' ' end)
  text = text:lower():gsub('[^%w]+', ' ')
  text = text:gsub('^%s+', '')
  text = text:gsub('%s+$', '')
  return text
end

-- the words of a query (folded); an empty list when the query has fewer than MIN_QUERY letters
function F.words(query)
  local out = {}
  for w in F.fold(query):gmatch('%S+') do out[#out + 1] = w end
  if #table.concat(out) < F.MIN_QUERY then return {} end
  return out
end

-- ---------------------------------------------------------------- search
local function tried(tr, key)
  local ok, v = pcall(tr, key)
  return ok and type(v) == 'string' and v or key
end

-- fields of a card, folded: name (English and shown), line, hub and tab, keywords, hotkey
local function fields(card, hub, tab, ctx)
  local tr = ctx.tr
  local kw = (ctx.keywords or {})[card.text] or ''
  local desc = ((ctx.cards and ctx.cards.CARDS and ctx.cards.CARDS[card.text]) or {})[2] or card.desc or ''
  local where = ''
  if hub then where = hub.name .. ' ' .. tried(tr, 'hub.' .. hub.id) end
  if hub and tab then where = where .. ' ' .. tab.name .. ' ' .. tried(tr, 'tab.' .. hub.id .. '.' .. tab.id) end
  return {
    name = F.fold(card.text .. ' ' .. tried(tr, card.text)),
    line = F.fold(desc .. ' ' .. (desc ~= '' and tried(tr, desc) or '')),
    where = F.fold(where),
    kw = F.fold(kw),
    key = F.fold(card.key or ''),
  }
end

local function wordStart(hay, w)
  return (' ' .. hay):find(' ' .. w, 1, true) ~= nil
end

-- the score of one word against the fields: 0 = not found. A name beats a keyword beats a line beats the place.
local function wordScore(f, w)
  if wordStart(f.name, w) then return 100 end
  if f.name:find(w, 1, true) then return 80 end
  if wordStart(f.kw, w) then return 60 end
  if f.kw:find(w, 1, true) then return 45 end
  if wordStart(f.line, w) then return 30 end
  if wordStart(f.key, w) then return 25 end
  if f.line:find(w, 1, true) then return 20 end
  if wordStart(f.where, w) then return 15 end
  return 0
end

-- all the matches of a query: a list of { card, hub, tab, score } best first, the tree order for equal scores, and how
-- many there are in all (the list is cut to `limit` when one is given).
-- model: ChaosTopBarHubLogic.build(...); ctx = { tr = function, keywords = { text -> words }, cards = ChaosTopBarCards }.
function F.search(model, query, ctx, limit)
  local ws = F.words(query)
  if #ws == 0 then return {}, 0 end
  local found, order = {}, 0
  local function try(card, hub, tab)
    order = order + 1
    local f = fields(card, hub, tab, ctx)
    local total = 0
    for _, w in ipairs(ws) do
      local s = wordScore(f, w)
      if s == 0 then return end
      total = total + s
    end
    found[#found + 1] = { card = card, hub = hub, tab = tab, score = total, order = order }
  end
  for _, hub in ipairs(model.hubs) do
    for _, tab in ipairs(hub.tabs) do
      for _, c in ipairs(tab.cards) do try(c, hub, tab) end
    end
  end
  for _, c in ipairs(model.pinOnly or {}) do try(c, nil, nil) end
  table.sort(found, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.order < b.order
  end)
  local n = #found
  if limit and n > limit then
    local cut = {}
    for i = 1, limit do cut[i] = found[i] end
    found = cut
  end
  return found, n
end

return F
