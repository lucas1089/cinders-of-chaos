-- The parts of the NPC dialogue window that need no client API (tested by npctalk_logic_test.lua):
-- keywords in an NPC's reply, the coloured text with clickable keywords, which quick buttons fit the reply, the
-- conversation tooltip (wrapped with SupportsText.wrap of game_spellsupports), and the geometry: where an NPC is on
-- the screen and where the bubble goes so that its tail points at the NPC and it stays inside the map.

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

-- ---------------------------------------------------------------- the conversation tooltip
-- lines {who, text}: the last `max` of them as "Name: text", each wrapped at `width` characters
function L.transcript(lines, width, max, wrap)
  local out = {}
  local first = math.max(1, #lines - (max or 16) + 1)
  for i = first, #lines do
    local line = lines[i]
    local text = (line.who and (line.who .. ': ') or '') .. L.plain(line.text)
    out[#out + 1] = wrap and wrap(text, width or 60, '   ') or text
  end
  return table.concat(out, '\n')
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

-- the bubble's place: above the NPC with the tail's tip at `above` (the point over its name), or under it with the
-- tip at `below` (its feet) when there is no room above; always inside `area` (the map rect, less `margin`).
-- Returns {x, y, tailX, tailY, below} (tailX/tailY: the tail image's top-left).
function L.place(w, h, above, below, area, tailW, tailH, margin)
  margin = margin or 4
  tailW, tailH = tailW or 22, tailH or 12
  local overlap = 3 -- the tail's top rows cover the bubble's rim
  local minX, maxX = area.x + margin, area.x + area.width - margin - w
  local minY, maxY = area.y + margin, area.y + area.height - margin - h
  local x = math.floor(above.x - w / 2)
  x = math.max(minX, math.min(maxX, x))
  if maxX < minX then x = minX end
  local isBelow = false
  local y = above.y - tailH + overlap - h
  if y < minY then
    local yb = below.y + tailH - overlap
    if yb <= maxY then
      y, isBelow = yb, true
    elseif area.y + area.height - below.y > above.y - area.y then
      y, isBelow = yb, true -- no room on either side: the roomier side, pushed back inside the map below
    end
  end
  y = math.max(minY, math.min(math.max(minY, maxY), y))
  local tailX = math.max(x + 8, math.min(x + w - 8 - tailW, math.floor(above.x - tailW / 2)))
  local tailY = isBelow and (y - tailH + overlap) or (y + h - overlap)
  return { x = x, y = y, tailX = tailX, tailY = tailY, below = isBelow }
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

return L
