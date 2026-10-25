-- game_visualfx scene fade (O219): a short dip to black that eases away when the player changes floor or is moved far in
-- one step (teleport, portal, stairs, rope, a fall). The map picture changes in one frame; the dip hides the cut. No
-- engine calls here, so scenefade_test.lua can run it. Every function takes the time (ms).
SceneFadeLogic = {}
local S = SceneFadeLogic

S.CFG = {
  floorStart = 0.45,   -- darkness (0 clear, 1 black) the frame after a floor change
  floorMs = 220,       -- and how long it takes to clear
  portalStart = 0.80,  -- a far move on the same floor, or a floor change that is not one step up or down
  portalMs = 380,
  farTiles = 4,        -- a step of this many tiles or more in x or y is a teleport (a walk is 1, a push 1-3)
  maxLevel = 0.85,     -- never darker than this, whatever comes in
  steps = 48,          -- the level is rounded to 1/48, so the widget is only touched when the picture changes
  tickMs = 33,         -- the timer runs at about 30 Hz and only while a fade is up
  quietMs = 1500,      -- no fade this long after the game starts: the first map is not a jump
}

-- what a position change is: nil (a walk), 'floor' (one floor up or down, next to where it was) or 'portal'
function S.classify(newPos, oldPos)
  if type(newPos) ~= 'table' or type(oldPos) ~= 'table' then return nil end
  if not (newPos.x and oldPos.x and newPos.z and oldPos.z) then return nil end
  local dx, dy = math.abs(newPos.x - oldPos.x), math.abs(newPos.y - oldPos.y)
  local dz = math.abs(newPos.z - oldPos.z)
  local far = math.max(dx, dy) >= S.CFG.farTiles
  if dz == 0 then return far and 'portal' or nil end
  if dz == 1 and not far then return 'floor' end
  return 'portal'
end

function S.new()
  return { from = 0, t0 = 0, ms = 1, shown = 0, startedAt = -1e9 }
end

-- the game started at `now`: forget a running fade and hold new ones back for CFG.quietMs
function S.reset(state, now)
  state.from, state.t0, state.ms, state.shown = 0, now, 1, 0
  state.startedAt = now
end

local function rounded(v)
  local n = S.CFG.steps
  v = math.floor(v * n + 0.5) / n
  if v > S.CFG.maxLevel then v = S.CFG.maxLevel end
  return v
end

-- the darkness at this moment: eases out (quadratic), 0 when over
function S.level(state, now)
  if state.from <= 0 then return 0 end
  local t = (now - state.t0) / state.ms
  if t >= 1 then return 0 end
  if t < 0 then t = 0 end
  return rounded(state.from * (1 - t) * (1 - t))
end

-- a position change at `now`; true when a fade starts or gets stronger. A running fade is never made weaker or shorter.
function S.trigger(state, now, kind)
  local C = S.CFG
  if now - state.startedAt < C.quietMs then return false end
  local start, ms
  if kind == 'floor' then start, ms = C.floorStart, C.floorMs
  elseif kind == 'portal' then start, ms = C.portalStart, C.portalMs
  else return false end
  if start > C.maxLevel then start = C.maxLevel end
  local cur = S.level(state, now)
  local left = cur > 0 and (state.t0 + state.ms - now) or 0
  if cur > start then start = cur end
  if left > ms then ms = left end
  state.from, state.t0, state.ms = start, now, ms
  return true
end

-- one timer tick: the level to show, whether it differs from what the widget has, and whether the fade is over
function S.step(state, now)
  local v = S.level(state, now)
  local changed = v ~= state.shown
  state.shown = v
  return v, changed, v <= 0
end
