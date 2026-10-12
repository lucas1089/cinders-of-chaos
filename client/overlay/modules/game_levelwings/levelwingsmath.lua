-- Pure helpers of the level-up wings (game_levelwings): the frame timing, the draw layer, the size on the map, the
-- settings rule and the message check. No client API here; tested by levelwingsmath_test.lua (luajit and lua5.3).

LevelWingsMath = {}
local M = LevelWingsMath

M.FRAMES = 12          -- images/wings_01.png .. wings_12.png (client/tools/gen_levelwings_art.py)
M.FRAME_MS = 55        -- the opening: 12 x 55 ms = 660 ms
M.FADE_IN_MS = 120     -- from transparent while the first frames show
M.HOLD_UNTIL_MS = 1150 -- the open wings stay at full strength until here
M.TOTAL_MS = 1800      -- then fade out; gone at this time
M.BASE_W, M.BASE_H = 96, 80 -- image size at a 32 px tile (the files are 2x)
M.MAX_ACTIVE = 12      -- at most this many wings on screen at once (the oldest gives way)

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- what to show elapsed ms after the start: frame (1..FRAMES), opacity (0..1), done (true when it is over)
function M.at(elapsed)
  elapsed = tonumber(elapsed) or 0
  if elapsed < 0 then elapsed = 0 end
  if elapsed >= M.TOTAL_MS then
    return M.FRAMES, 0, true
  end
  local frame = clamp(math.floor(elapsed / M.FRAME_MS) + 1, 1, M.FRAMES)
  local opacity
  if elapsed < M.FADE_IN_MS then
    opacity = 0.25 + 0.75 * elapsed / M.FADE_IN_MS
  elseif elapsed <= M.HOLD_UNTIL_MS then
    opacity = 1
  else
    opacity = 1 - (elapsed - M.HOLD_UNTIL_MS) / (M.TOTAL_MS - M.HOLD_UNTIL_MS)
  end
  return frame, clamp(opacity, 0, 1), false
end

function M.framePath(frame)
  return string.format('/modules/game_levelwings/images/wings_%02d', clamp(tonumber(frame) or 1, 1, M.FRAMES))
end

-- the wings are behind the character, except when it faces north (its back to the viewer): then in front.
-- Directions: 0 north, 1 east, 2 south, 3 west, 4..7 diagonals (NE, SE, SW, NW).
function M.layerFor(direction)
  if direction == 0 or direction == 4 or direction == 7 then
    return 'top'
  end
  return 'bottom'
end

-- the widget size for the current sprite size (32, or 64 and more with HD scaling) and the creature's draw scale
function M.sizeFor(spriteSize, drawScale)
  local k = (tonumber(spriteSize) or 32) / 32
  local s = tonumber(drawScale) or 1
  if s <= 0 then s = 1 end
  return math.floor(M.BASE_W * k * s + 0.5), math.floor(M.BASE_H * k * s + 0.5)
end

-- the two settings: own character and other characters; nil (no settings module) counts as on
function M.wanted(isLocal, ownOn, othersOn)
  if isLocal then
    return ownOn ~= false
  end
  return othersOn ~= false
end

-- the creature id of a server message {action = 'play', data = {id, lv, n}}, or nil
function M.playId(msg)
  if type(msg) ~= 'table' or msg.action ~= 'play' or type(msg.data) ~= 'table' then
    return nil
  end
  local id = tonumber(msg.data.id)
  if not id or id <= 0 or id ~= math.floor(id) then
    return nil
  end
  return id
end

-- which entry gives way when a new one would exceed MAX_ACTIVE: the id that started first, or nil when there is room
function M.evict(active, now)
  local n, oldestId, oldestStart = 0, nil, nil
  for id, entry in pairs(active) do
    n = n + 1
    if not oldestStart or entry.start < oldestStart or (entry.start == oldestStart and id < oldestId) then
      oldestId, oldestStart = id, entry.start
    end
  end
  if n < M.MAX_ACTIVE then
    return nil
  end
  return oldestId
end

return M
