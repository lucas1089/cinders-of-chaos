-- The parts of the NPC dialogue window that need no client API (tested by npctalk_logic_test.lua):
-- keywords in an NPC's reply, the coloured text with clickable keywords, which quick buttons fit the reply, the keyword
-- chips grouped (quests, trade, topics, language) with the quest words marked, the NPC's name and title, and the geometry:
-- where an NPC and the player are on the screen and where the window goes (beside the NPC, never over the character).

NpcTalkLogic = {}
local L = NpcTalkLogic

L.TALK_RANGE = 3           -- the stock NpcHandler's talkRadius: further away an NPC neither hears nor answers
L.MAX_CHIPS = 12
L.BUTTONS = { 'yes', 'no', 'trade', 'bye' }
L.COLORS = {
  npc = '#d6c9ae',         -- the reply (parchment)
  keyword = '#f6cf72',     -- a {keyword} (bright ember gold, clickable)
  player = '#8c8070',      -- what the player said (dim)
}

local function trim(s)
  return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end
L.trim = trim

-- ---------------------------------------------------------------- reply text
-- the parts of a reply: {text = ..., key = true} for every {keyword}, plain text between them; braces removed
function L.segments(text)
  text = tostring(text or '')
  local out, cursor = {}, 1
  while true do
    local s, e, word = text:find('{([^{}]*)}', cursor)
    if not s then
      if cursor <= #text then out[#out + 1] = { text = text:sub(cursor) } end
      break
    end
    if s > cursor then out[#out + 1] = { text = text:sub(cursor, s - 1) } end
    word = trim(word)
    if word ~= '' then
      out[#out + 1] = { text = word, key = true }
    end
    cursor = e + 1
  end
  -- neighbouring plain parts (an empty {} between them) are one part
  local merged = {}
  for _, part in ipairs(out) do
    local last = merged[#merged]
    if last and not last.key and not part.key then
      last.text = last.text .. part.text
    else
      merged[#merged + 1] = { text = part.text, key = part.key }
    end
  end
  return merged
end

-- the reply as the player reads it: no braces
function L.plain(text)
  local parts = {}
  for _, part in ipairs(L.segments(text)) do parts[#parts + 1] = part.text end
  return table.concat(parts)
end

-- the keywords of one or more replies, in the order they first appear, each once (case does not matter)
function L.keywords(texts)
  if type(texts) ~= 'table' then texts = { texts } end
  local out, seen = {}, {}
  for _, text in ipairs(texts) do
    for _, part in ipairs(L.segments(text)) do
      local k = part.key and part.text:lower()
      if k and not seen[k] then
        seen[k] = true
        out[#out + 1] = part.text
      end
    end
  end
  return out
end

-- {text, colour, text, colour, ...} for UIWidget:setColoredText; keywords wrapped in [text-event] so that a click on
-- one calls onTextClick(widget, word) (the engine's EVENT_TEXT_CLICK)
function L.coloredText(text, color, keyColor, clickable)
  color, keyColor = color or L.COLORS.npc, keyColor or L.COLORS.keyword
  local out, hasKeys = {}, false
  for _, part in ipairs(L.segments(text)) do
    if part.key then
      hasKeys = true
      out[#out + 1] = clickable == false and part.text or ('[text-event]' .. part.text .. '[/text-event]')
      out[#out + 1] = keyColor
    else
      out[#out + 1] = part.text
      out[#out + 1] = color
    end
  end
  if #out == 0 then out = { '', color } end
  return out, hasKeys
end

-- ---------------------------------------------------------------- what the player says
local GREETINGS = { hi = true, hello = true, hey = true, hail = true, greetings = true }
local FAREWELLS = { bye = true, farewell = true, ['good bye'] = true, goodbye = true, cya = true }

local function norm(text)
  return trim(text):lower():gsub('[%s%p]+$', '')
end

function L.isGreeting(text)
  local t = norm(text)
  return GREETINGS[t] == true or GREETINGS[t:match('^(%a+)%s') or ''] == true
end

function L.isFarewell(text)
  return FAREWELLS[norm(text)] == true
end

-- ---------------------------------------------------------------- quick buttons and keyword chips
local TRADE_WORDS = { 'trade', 'offer', 'offers', 'wares' }

local function mentions(texts, words)
  for _, text in ipairs(texts or {}) do
    local plain = ' ' .. L.plain(text):lower():gsub('[^%w]+', ' ') .. ' '
    for _, word in ipairs(words) do
      if plain:find(' ' .. word .. ' ', 1, true) then return true end
    end
  end
  return false
end

-- which of Yes / No / Trade / Bye to show: Bye always; Yes and No when the latest reply asks something (ends with a
-- question mark, or offers {yes} / {no}); Trade when the NPC spoke of a trade or its offers in this conversation
-- (shop NPCs say "ask me for a {trade}"), or the trade window is open
function L.buttons(turn, history, tradeOpen)
  turn = turn or {}
  local last = trim(L.plain(turn[#turn] or ''))
  local keys = {}
  for _, k in ipairs(L.keywords(turn)) do keys[k:lower()] = true end
  local question = last:sub(-1) == '?' or keys.yes or keys.no
  return {
    yes = question and true or false,
    no = question and true or false,
    trade = (tradeOpen or mentions(history or turn, TRADE_WORDS)) and true or false,
    bye = true,
  }
end

-- the keyword chips under the reply: the keywords of the latest turn, without those a quick button already offers
function L.chips(turn, shown, max)
  local out = {}
  for _, k in ipairs(L.keywords(turn or {})) do
    if not (shown and shown[k:lower()]) then
      out[#out + 1] = k
      if #out >= (max or L.MAX_CHIPS) then break end
    end
  end
  return out
end

-- chips laid out left to right in rows: widths -> {x, y} per chip and the height of the block
function L.flow(widths, maxWidth, chipHeight, gapX, gapY)
  gapX, gapY = gapX or 4, gapY or 4
  local out, x, y = {}, 0, 0
  for i, w in ipairs(widths) do
    w = math.min(w, maxWidth)
    if x > 0 and x + w > maxWidth then
      x, y = 0, y + chipHeight + gapY
    end
    out[i] = { x = x, y = y, width = w }
    x = x + w + gapX
  end
  return out, (#widths > 0) and (y + chipHeight) or 0
end

-- ---------------------------------------------------------------- geometry
-- the engine (UIMap / MapView) draws the visible tiles into the map widget's padding rect, less 1 px, kept at the
-- aspect of the visible dimension when keepAspect, centred; the camera tile's centre is the centre of that rect
function L.mapRect(panelRect, vis, keepAspect)
  local r = { x = panelRect.x + 1, y = panelRect.y + 1, width = panelRect.width - 2, height = panelRect.height - 2 }
  if keepAspect and vis and vis.width > 0 and vis.height > 0 and r.width > 0 and r.height > 0 then
    local scale = math.min(r.width / vis.width, r.height / vis.height)
    local w, h = math.floor(vis.width * scale), math.floor(vis.height * scale)
    r = { x = r.x + math.floor((r.width - w) / 2), y = r.y + math.floor((r.height - h) / 2), width = w, height = h }
  end
  return r
end

-- screen pixels per sprite pixel: the visible tiles fill the map rect (cut to its aspect, never letterboxed)
function L.stretch(mapRect, vis, spriteSize)
  spriteSize = spriteSize or 32
  if not vis or vis.width <= 0 or vis.height <= 0 then return 1 end
  return math.max(mapRect.width / (vis.width * spriteSize), mapRect.height / (vis.height * spriteSize))
end

-- the walk offset of a creature in sprite pixels: it stands on `to` already and is drawn back towards `from` until the
-- step is done (progress 0..1)
function L.walkOffset(from, to, progress, spriteSize)
  if not from or not to or from.z ~= to.z then return 0, 0 end
  local dx, dy = from.x - to.x, from.y - to.y
  if math.abs(dx) > 1 or math.abs(dy) > 1 then return 0, 0 end
  local left = 1 - math.max(0, math.min(1, progress or 1))
  spriteSize = spriteSize or 32
  return dx * spriteSize * left, dy * spriteSize * left
end

-- the screen centre of the tile at `pos` (plus a creature's walk offset `off`) for a camera at `cam` whose followed
-- creature is drawn at `camOff`; nil on another floor
function L.tileCenter(mapRect, stretch, spriteSize, cam, camOff, pos, off)
  if not cam or not pos or cam.z ~= pos.z then return nil end
  spriteSize = spriteSize or 32
  camOff, off = camOff or { x = 0, y = 0 }, off or { x = 0, y = 0 }
  local cx, cy = mapRect.x + mapRect.width / 2, mapRect.y + mapRect.height / 2
  return {
    x = math.floor(cx + ((pos.x - cam.x) * spriteSize + off.x - camOff.x) * stretch + 0.5),
    y = math.floor(cy + ((pos.y - cam.y) * spriteSize + off.y - camOff.y) * stretch + 0.5),
  }
end

-- the part of the map the player sees: the map rect cut by the window and the panels around it. `limits` = {left,
-- right, top, bottom}: screen coordinates the area must not cross (nil: no limit)
function L.visibleArea(mapRect, limits)
  local x1, y1 = mapRect.x, mapRect.y
  local x2, y2 = mapRect.x + mapRect.width, mapRect.y + mapRect.height
  limits = limits or {}
  if limits.left then x1 = math.max(x1, limits.left) end
  if limits.right then x2 = math.min(x2, limits.right) end
  if limits.top then y1 = math.max(y1, limits.top) end
  if limits.bottom then y2 = math.min(y2, limits.bottom) end
  return { x = x1, y = y1, width = math.max(0, x2 - x1), height = math.max(0, y2 - y1) }
end

-- the tiles to walk to for a talk: every tile within `range` of the NPC but its own, nearest to the player first (then
-- nearest to the NPC, then a fixed order)
function L.approachTiles(npc, from, range)
  range = range or L.TALK_RANGE
  local out = {}
  for dy = -range, range do
    for dx = -range, range do
      if dx ~= 0 or dy ~= 0 then
        local p = { x = npc.x + dx, y = npc.y + dy, z = npc.z }
        local d = math.max(math.abs(p.x - from.x), math.abs(p.y - from.y))
        local e = (p.x - from.x) ^ 2 + (p.y - from.y) ^ 2
        out[#out + 1] = { pos = p, d = d, e = e, n = math.max(math.abs(dx), math.abs(dy)) }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.d ~= b.d then return a.d < b.d end
    if a.e ~= b.e then return a.e < b.e end
    if a.n ~= b.n then return a.n < b.n end
    if a.pos.y ~= b.pos.y then return a.pos.y < b.pos.y end
    return a.pos.x < b.pos.x
  end)
  local tiles = {}
  for i, t in ipairs(out) do tiles[i] = t.pos end
  return tiles
end

-- Chebyshev distance on one floor (the NPC's talk radius), nil on another floor
function L.distance(a, b)
  if not a or not b or a.z ~= b.z then return nil end
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

function L.inRange(a, b, range)
  local d = L.distance(a, b)
  return d ~= nil and d <= (range or L.TALK_RANGE)
end

-- ---------------------------------------------------------------- the NPC's name and title
-- "Archivist Maelis" -> "Maelis", "Archivist"; "Osric the Chandler" -> "Osric", "Chandler"; a name that is a job only
-- ("Loot Buyer", "Keeper of Trials") stays whole with no title. Nothing is made up: the title is a word of the name.
local TITLE_FIRST = { archivist = true, cantor = true, elder = true, forgemaster = true, warden = true, widow = true,
  master = true, captain = true, sergeant = true, smith = true, sage = true, priest = true, priestess = true,
  lord = true, lady = true, sir = true, hunter = true, guard = true }

function L.splitName(name)
  name = trim(name)
  local who, title = name:match('^(%S+)%s+the%s+(.+)$')
  if who then return who, title end
  local first, rest = name:match('^(%S+)%s+(.+)$')
  if first and TITLE_FIRST[first:lower()] then return rest, first end
  return name, nil
end

-- ---------------------------------------------------------------- keyword chips, grouped
-- Quest words mark a chip; the groups come most useful first: quests, trade, topics, language.
L.QUEST_WORDS = { quest = true, quests = true, mission = true, missions = true, task = true, tasks = true, job = true,
  jobs = true, adventure = true, reward = true, rewards = true, trial = true, trials = true, oath = true,
  ascension = true, ascend = true, ascendant = true, bounty = true, errand = true, errands = true, favor = true,
  favour = true, ritual = true, vow = true, pact = true }
L.TRADE_KEYWORDS = { trade = true, offer = true, offers = true, wares = true, buy = true, sell = true, shop = true,
  goods = true, prices = true, price = true, barter = true }
L.LANGUAGE_WORDS = { portugues = true, ['portugu\195\170s'] = true, portuguese = true, english = true, ingles = true,
  ['ingl\195\170s'] = true }
L.GROUPS = { 'quest', 'trade', 'topics', 'language' }

local function wordIn(set, word)
  word = trim(word):lower()
  if set[word] then return true end
  for w in word:gmatch('[%a\128-\255]+') do
    if set[w] then return true end
  end
  return false
end

-- a quest word: the keyword itself, or one of its words ("the spell quest")
function L.isQuestWord(word)
  return wordIn(L.QUEST_WORDS, word)
end

function L.groupOf(word)
  if wordIn(L.LANGUAGE_WORDS, word) then return 'language' end
  if L.isQuestWord(word) then return 'quest' end
  if wordIn(L.TRADE_KEYWORDS, word) then return 'trade' end
  return 'topics'
end

-- the chips of a turn in groups: [{id, words = {...}}], empty groups left out, the order of the words kept in a group
function L.groups(words)
  local by = {}
  for _, w in ipairs(words or {}) do
    local g = L.groupOf(w)
    by[g] = by[g] or {}
    by[g][#by[g] + 1] = w
  end
  local out = {}
  for _, id in ipairs(L.GROUPS) do
    if by[id] then out[#out + 1] = { id = id, words = by[id] } end
  end
  return out
end

-- The chips and the group labels laid out in rows. `widthOf(word)` gives the width of a chip; with two groups or more
-- (and a `labelHeight`) every group starts on a new row under its label.
-- Returns {labels = {{id, y}}, chips = {{word, group, x, y, width}}, height}.
function L.flowGroups(groups, widthOf, maxWidth, chipHeight, gapX, gapY, labelHeight)
  gapX, gapY, labelHeight = gapX or 4, gapY or 4, labelHeight or 0
  local labelled = #groups > 1 and labelHeight > 0
  local labels, chips = {}, {}
  local y = 0
  for gi, g in ipairs(groups) do
    if gi > 1 then y = y + gapY + 2 end
    if labelled then
      labels[#labels + 1] = { id = g.id, y = y }
      y = y + labelHeight + 2
    end
    local x = 0
    for _, word in ipairs(g.words) do
      local w = math.min(widthOf(word), maxWidth)
      if x > 0 and x + w > maxWidth then x, y = 0, y + chipHeight + gapY end
      chips[#chips + 1] = { word = word, group = g.id, x = x, y = y, width = w }
      x = x + w + gapX
    end
    y = y + chipHeight
  end
  return { labels = labels, chips = chips, height = y }
end

-- A short line under the NPC's name when its name has no title: what the conversation shows it to be. 'trade' when the
-- trade window is open or it spoke of its wares, 'quests' when a keyword of the conversation is a quest word.
function L.role(history, tradeOpen)
  if tradeOpen then return 'trade' end
  for _, k in ipairs(L.keywords(history or {})) do
    if L.isQuestWord(k) then return 'quests' end
  end
  if mentions(history or {}, TRADE_WORDS) then return 'trade' end
  return nil
end

-- ---------------------------------------------------------------- where the dialogue window goes
L.WINDOW_W, L.WINDOW_H = 480, 480
L.WINDOW_MIN_W, L.WINDOW_MIN_H = 380, 340

-- the window's size for the visible part of the map `area` ({x, y, width, height})
function L.windowSize(area)
  local w = math.max(L.WINDOW_MIN_W, math.min(L.WINDOW_W, area.width - 16))
  local h = math.max(L.WINDOW_MIN_H, math.min(L.WINDOW_H, area.height - 16))
  return w, h
end

local function overlaps(x, y, w, h, r)
  return x < r.x + r.width and r.x < x + w and y < r.y + r.height and r.y < y + h
end

-- The window beside the NPC: on the side of it away from the player, else the other side, never over the player's tile or the
-- NPC's. The part of the map the player sees (`area`) comes first, then the whole screen (`screen`, optional: a small map
-- leaves no room beside the NPC, and the window may cover a side panel but not the character). After the sides: a corner of
-- the area, a corner of the screen, the middle of the area. `npc` and `player` are the screen centres of their tiles (player
-- may be nil), `tile` the size of a tile on the screen. Returns {x, y}.
function L.windowPlace(w, h, npc, player, tile, area, margin, screen)
  margin = margin or 8
  tile = math.max(8, tile or 32)
  local keep = {}
  for _, c in ipairs({ npc, player or false }) do
    if c then keep[#keep + 1] = { x = c.x - tile * 0.75, y = c.y - tile * 1.25, width = tile * 1.5, height = tile * 2 } end
  end
  local function free(x, y)
    for _, r in ipairs(keep) do if overlaps(x, y, w, h, r) then return false end end
    return true
  end
  local function limits(a)
    local minX, maxX = a.x + margin, a.x + a.width - margin - w
    local minY, maxY = a.y + margin, a.y + a.height - margin - h
    return minX, math.max(minX, maxX), minY, math.max(minY, maxY)
  end
  local function beside(a)
    local minX, maxX, minY, maxY = limits(a)
    local y = math.max(minY, math.min(maxY, math.floor(npc.y - h / 2)))
    local right = { x = math.floor(npc.x + tile), y = y }
    local left = { x = math.floor(npc.x - tile - w), y = y }
    local order = (not player or player.x <= npc.x) and { right, left } or { left, right }
    for _, c in ipairs(order) do
      if c.x >= minX and c.x <= maxX and free(c.x, c.y) then return { x = c.x, y = c.y } end
    end
  end
  -- the free corner (or the spot above or under the NPC) nearest the NPC
  local function corners(a)
    local minX, maxX, minY, maxY = limits(a)
    local midX = math.max(minX, math.min(maxX, math.floor(npc.x - w / 2)))
    local best, bestD
    for _, s in ipairs({ { minX, minY }, { maxX, minY }, { minX, maxY }, { maxX, maxY }, { midX, minY }, { midX, maxY } }) do
      if free(s[1], s[2]) then
        local d = (s[1] + w / 2 - npc.x) ^ 2 + (s[2] + h / 2 - npc.y) ^ 2
        if not bestD or d < bestD then best, bestD = { x = s[1], y = s[2] }, d end
      end
    end
    return best
  end
  local spot = beside(area) or (screen and beside(screen)) or corners(area) or (screen and corners(screen))
  if spot then return spot end
  local minX, maxX, minY, maxY = limits(area)
  return { x = math.floor((minX + maxX) / 2), y = math.floor((minY + maxY) / 2) }
end

-- ---------------------------------------------------------------- which window gets an NPC line
-- The names of two NPC lines compare equal when they differ only in case, spacing or edge punctuation.
function L.sameName(a, b)
  local function key(x) return (trim(x):lower():gsub('%s+', ' '):gsub('^%p+', ''):gsub('%p+$', '')) end
  local ka, kb = key(a), key(b)
  return ka ~= '' and ka == kb
end

local function samePos(a, b)
  return a ~= nil and b ~= nil and a.x == b.x and a.y == b.y and a.z == b.z
end
L.samePos = samePos

-- Where one line of an NPC goes. `line` = {mode, name, text, pos (where the speaker stands, when the engine says)};
-- `st` = {modes = {npcFrom, npcFromStartBlock}, enabled, suppressed, conv = {name, pos} | nil}.
--   'ignore'   not an NPC line at all (public talk, a player): the console alone
--   'console'  an NPC line the bubble does not take (the dialogue is off, another NPC's line, a farewell right after a
--              goodbye): the console as before
--   'conv'     a line of the NPC of the open conversation
--   'open'     a line of an NPC with no conversation open: the bubble opens for it when it stands in range
-- The speaker of the open conversation is known by its name or, when the name differs in some way, by its tile.
function L.routeNpcLine(line, st)
  local m = line.mode
  if m == nil or (m ~= st.modes.npcFrom and m ~= st.modes.npcFromStartBlock) then return 'ignore' end
  if not st.enabled or trim(line.name) == '' or trim(line.text) == '' then return 'console' end
  if st.conv then
    if L.sameName(st.conv.name, line.name) or samePos(st.conv.pos, line.pos) then return 'conv' end
    return 'console'
  end
  if st.suppressed then return 'console' end
  return 'open'
end

-- The console hook and the game's own talk signal both hand over every line; the second copy of a line (same speaker,
-- same words, within `window` ms of the first) is the same line.
function L.isDuplicate(last, name, text, at, window)
  return last ~= nil and last.name == name and last.text == text and at - last.at <= (window or 50)
end

return L
