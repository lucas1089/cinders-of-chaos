-- Pure helpers of the level-up wings (game_levelwings): the frame timing, the view and draw layer of a direction, the
-- size and place on the map, the settings rule and the message check. No client API here; tested by levelwingsmath_test.lua (luajit and lua5.3).

LevelWingsMath = {}
local M = LevelWingsMath

M.FRAMES = 12          -- per view (client/tools/gen_levelwings_art.py): images/wings_01..12 (the front pair),
                       -- wings_east_01..12 and wings_west_01..12 (the side pair)
M.FRAME_MS = 55        -- the opening: 12 x 55 ms = 660 ms
M.FADE_IN_MS = 120     -- from transparent while the first frames show
M.HOLD_UNTIL_MS = 1150 -- the open wings stay at full strength until here
M.TOTAL_MS = 1800      -- then fade out; gone at this time
M.BASE_W, M.BASE_H = 96, 80 -- image size at a 32 px tile (the files are 2x)
M.MAX_ACTIVE = 12      -- at most this many wings on screen at once (the oldest gives way)

-- where the wings sit (owner, 2026-10-16: they opened off-centre, left of and below a level 10 Mystic). The engine
-- centres a creature widget on the tile centre moved up and left by the outfit's displacement, or on the tile centre
-- when the displacement is negative (the big imported looks): that is the middle of a 32 px sprite, not of the body
-- of a 64 or 96 px look (2x2: 7 px left of it and 13 px too low; the 3x3 Archmage: 22 px too low). The art's wing
-- roots are ROOT_Y above the image centre (client/tools/gen_levelwings_art.py ROOT); they go on the shoulders, SHOULDER
-- of the way down the body from its top to its feet.
M.SHOULDER = 0.3
M.ROOT_Y = -6
-- a look the anchor table does not know (a newer pair): a usual 2x2 body, {centre x, ground row, top, left, right}
M.DEFAULT_ANCHOR = {16, 20, -24, -10, 22}
-- the side views (2026-10-20, owner: "the level-up wings don't turn sideways"). The anchors are measured on the south
-- frame only, so the shoulder blades of a look facing east or west are found from it. The side art's root (the near
-- wing's shoulder) is on the image's centre column, ROOT_Y above the centre like the front roots; it goes SIDE_X
-- pixels (1x) across from the front pair's place, at the same height. Measured on pair 30 (dat 81567924: the 60
-- class looks and the stock outfits 128-143, the body without what it holds, at the shoulder row): the side body
-- sits a little left of the front one (every sprite leans up and left), its back is its left edge facing east and
-- its right edge facing west, and the root goes in from the back edge to the shoulder blades.
M.SIDE_X = { east = -6, west = 2 }

local function round(v)
  return math.floor(v + 0.5)
end

-- the engine's centre of a creature widget, in pixels at 1x relative to the top left of the creature's tile
function M.widgetCentre(dx, dy)
  dx, dy = tonumber(dx) or 0, tonumber(dy) or 0
  if dx < 0 or dy < 0 then
    return 16, 16
  end
  return 16 - dx, 16 - dy
end

-- how far to move the wing image from the widget centre (pixels at the current scale): anchor = the look's row of the
-- character select's outfit anchors ({cx, ground, top, ...}: 1x pixels relative to the tile, displacement applied),
-- dx, dy = the look's displacement (signed), scale = sprite size / 32 times the creature's draw scale
-- view: 'south' (also nil), 'north', 'east' or 'west' (M.viewFor); a side view moves the root onto the back
function M.offsetFor(anchor, dx, dy, scale, view)
  local a = type(anchor) == 'table' and anchor[1] and anchor[2] and anchor[3] and anchor or M.DEFAULT_ANCHOR
  local k = tonumber(scale) or 1
  if k <= 0 then k = 1 end
  local wx, wy = M.widgetCentre(dx, dy)
  local shoulder = a[3] + M.SHOULDER * (a[2] - a[3])
  -- across: the middle of the visible box (left, right) at the shoulders; the feet centre (cx) of an oblique look is
  -- right of its shoulders, its body leans up and left
  local x = (a[4] and a[5]) and (a[4] + a[5]) / 2 or a[1]
  x = x + (M.SIDE_X[view] or 0)
  return round((x - wx) * k), round((shoulder - M.ROOT_Y - wy) * k)
end

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

-- the frame set of a view: the front pair facing south or north, a side pair facing east or west
M.SETS = { south = 'wings_', north = 'wings_', east = 'wings_east_', west = 'wings_west_' }

function M.framePath(frame, view)
  return string.format('/modules/game_levelwings/images/%s%02d', M.SETS[view] or M.SETS.south,
    clamp(tonumber(frame) or 1, 1, M.FRAMES))
end

-- the view of a creature's direction: 0 north, 1 east, 2 south, 3 west, 4..7 diagonals (NE, SE, SW, NW). A creature
-- has no diagonal frames: a diagonal shows the front pair (north-east and north-west its back, south-east and
-- south-west its front); unknown counts as south.
local VIEWS = { [0] = 'north', [1] = 'east', [2] = 'south', [3] = 'west',
  [4] = 'north', [5] = 'south', [6] = 'south', [7] = 'north' }

function M.viewFor(direction)
  return VIEWS[direction] or 'south'
end

-- the wings are behind the character, except when it faces north (its back to the viewer): then in front. Facing
-- east or west the side pair is behind it too (the body hides the far wing and the near wing's root).
function M.layerFor(direction)
  if M.viewFor(direction) == 'north' then
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
