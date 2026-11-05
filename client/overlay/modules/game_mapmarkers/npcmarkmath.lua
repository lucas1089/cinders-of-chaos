-- Pure helpers of the marks over NPC heads (O415; no client API), tested by npcmarkmath_test.lua.
-- The server (poi.lua action npcmarks) says which NPC, by name, has a quest for this character: new (a gold "!": a quest
-- to start), ready (a gold "?": a step to turn in or report here), locked (a grey "!": a quest that waits for a level).
-- npcmarks.lua draws one small image over each such NPC in view. The screen maths is the same as the NPC dialogue's
-- (game_npctalk): the visible tiles fill the map widget, a walking creature is drawn back toward the tile it left.
NpcMarkMath = {}
local M = NpcMarkMath

M.ICONS = '/images/chaos/mapmarkers/'
M.MARKS = { new = 'npcmark_new', ready = 'npcmark_ready', locked = 'npcmark_locked' }
M.WIDTH, M.HEIGHT = 16, 24   -- the art (client/tools/gen_mapmarker_art.py)
M.TICK_MS = 33               -- how often the marks follow the NPCs and the camera while any is in view
M.MAX = 40                   -- marks the client keeps

local function lower(s)
  return tostring(s or ''):lower()
end

-- the image of a mark kind, or nil for an unknown one
function M.image(mark)
  local name = M.MARKS[mark]
  return name and (M.ICONS .. name) or nil
end

-- a server message {full, set = [{n, m}], clear = [name]} -> a clean one (unknown marks and junk dropped)
function M.parse(data)
  local out = { full = false, set = {}, clear = {} }
  if type(data) ~= 'table' then return out end
  out.full = data.full == true
  for _, e in ipairs(type(data.set) == 'table' and data.set or {}) do
    if type(e) == 'table' and type(e.n) == 'string' and e.n ~= '' and M.MARKS[e.m] then
      out.set[#out.set + 1] = { n = e.n, m = e.m }
    end
  end
  for _, n in ipairs(type(data.clear) == 'table' and data.clear or {}) do
    if type(n) == 'string' and n ~= '' then out.clear[#out.clear + 1] = n end
  end
  return out
end

-- the marks by NPC name (lower case) -> mark kind; a full message starts again, a difference changes what it names.
-- Returns the number of marks kept (at most M.MAX: later ones are ignored).
function M.apply(state, msg)
  if msg.full then
    for k in pairs(state) do state[k] = nil end
  end
  for _, n in ipairs(msg.clear) do state[lower(n)] = nil end
  local count = 0
  for _ in pairs(state) do count = count + 1 end
  for _, e in ipairs(msg.set) do
    local key = lower(e.n)
    if state[key] == nil then
      if count >= M.MAX then break end
      count = count + 1
    end
    state[key] = e.m
  end
  return count
end

-- the mark kind of an NPC by its name, or nil
function M.markFor(state, name)
  return state[lower(name)]
end

-- ---------------------------------------------------------------- where it goes on the screen
-- screen pixels per sprite pixel: the visible tiles fill the map rect (cut to its aspect, never letterboxed)
function M.stretch(mapRect, vis, spriteSize)
  spriteSize = spriteSize or 32
  if not vis or vis.width <= 0 or vis.height <= 0 then return 1 end
  return math.max(mapRect.width / (vis.width * spriteSize), mapRect.height / (vis.height * spriteSize))
end

-- the map widget's drawn part: with the aspect kept, the visible tiles fill a centred rect of the widget
function M.mapRect(panelRect, vis, keepAspect, spriteSize)
  spriteSize = spriteSize or 32
  if not keepAspect or not vis or vis.width <= 0 or vis.height <= 0 then return panelRect end
  local scale = math.min(panelRect.width / (vis.width * spriteSize), panelRect.height / (vis.height * spriteSize))
  local w, h = math.floor(vis.width * spriteSize * scale), math.floor(vis.height * spriteSize * scale)
  return { x = panelRect.x + math.floor((panelRect.width - w) / 2), y = panelRect.y + math.floor((panelRect.height - h) / 2),
    width = w, height = h }
end

-- a creature's walk offset in sprite pixels: it stands on `to` already and is drawn back toward `from` until the step is
-- done (progress 0..1)
function M.walkOffset(from, to, progress, spriteSize)
  if not from or not to or from.z ~= to.z then return 0, 0 end
  local dx, dy = from.x - to.x, from.y - to.y
  if math.abs(dx) > 1 or math.abs(dy) > 1 then return 0, 0 end
  local left = 1 - math.max(0, math.min(1, progress or 1))
  spriteSize = spriteSize or 32
  return dx * spriteSize * left, dy * spriteSize * left
end

-- the screen centre of the tile at `pos` (plus the creature's walk offset `off`) for a camera at `cam` whose followed
-- creature is drawn at `camOff`; nil on another floor
function M.tileCenter(mapRect, stretch, spriteSize, cam, camOff, pos, off)
  if not cam or not pos or cam.z ~= pos.z then return nil end
  spriteSize = spriteSize or 32
  camOff, off = camOff or { x = 0, y = 0 }, off or { x = 0, y = 0 }
  local cx, cy = mapRect.x + mapRect.width / 2, mapRect.y + mapRect.height / 2
  return {
    x = math.floor(cx + ((pos.x - cam.x) * spriteSize + off.x - camOff.x) * stretch + 0.5),
    y = math.floor(cy + ((pos.y - cam.y) * spriteSize + off.y - camOff.y) * stretch + 0.5),
  }
end

-- the mark's size on screen: its art times the map's stretch, kept between 3/4 and 2 times so it stays readable
function M.size(stretch)
  local s = math.max(0.75, math.min(2, stretch or 1))
  return math.floor(M.WIDTH * s + 0.5), math.floor(M.HEIGHT * s + 0.5)
end

-- the top left of the mark over a creature: its bottom edge `gap` pixels over the top of the NPC's name. The name is
-- drawn about 16 px above the head point (sprite / 2 + the look's displacement + 2, plus the lift of a tall look,
-- client_chaos_infolift; the same point the NPC dialogue's bubble points at). Returns x, y, w, h, or nil when
-- the mark is wholly outside the map rect.
function M.place(mapRect, stretch, spriteSize, center, dispY, lift, gap)
  spriteSize = spriteSize or 32
  local w, h = M.size(stretch)
  local head = center.y - math.floor((spriteSize / 2 + (dispY or 8) + 2 + (lift or 0)) * stretch)
  local nameTop = head - 16
  local x = center.x - math.floor(w / 2)
  local y = nameTop - (gap or 2) - h
  if x + w < mapRect.x or x > mapRect.x + mapRect.width or y + h < mapRect.y or y > mapRect.y + mapRect.height then
    return nil
  end
  return x, y, w, h
end

-- which tracked creatures get a widget: {id = {name, ...}} + the marks by name -> list of {id, mark}, ordered by id
function M.wanted(state, creatures)
  local out = {}
  for id, c in pairs(creatures) do
    local mark = M.markFor(state, c.name)
    if mark then out[#out + 1] = { id = id, mark = mark } end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end
