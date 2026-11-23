-- The footprint preview (O712): the figure walks east in place and the floor runs by under it, as the map does when the
-- camera follows a walker. The marks are laid by the in-game rules (game_cosmeticfx cosmeticfxlogic.lua, passed in as `CF`:
-- one pair of feet a step, CF.stepMarks, the feet of the look from foot_marks.lua, alternating feet, CF.markOpacity fading
-- by age and rank, at most mode.maxPer on the floor; an effect footprint plays its effect once a step on the tile the
-- walker left, CF.fxPlan, at most CF.FX_MAX_PER_CREATURE alive), so the preview is what the map draws, not a copy of it.
-- Pure (tested by footwalk_test.lua with luajit and lua5.3); lookpreview.lua draws what it returns.
--
-- Time t is ms of the walk. The walker takes a step every S ms (W.stepMs) and its world position is t / S tiles; the screen
-- shows the figure fixed on its tile and everything else moved back by that, so a mark of step k lies, in sprite px at 1x
-- from the creature tile's top left, at  k * 32 + (the mark's place in its step) - t / S * 32.

FootWalk = {}
local W = FootWalk

W.STEP_MS = 420        -- a calm walk: the trail stays on the stage a few steps (a hunter at normal speed steps in ~250-350)
W.STEP_MAX_MS = 650    -- a long effect slows the walk down to this at most
W.WARM_MS = 4000       -- the walk has gone on this long when the preview starts: the trail is laid, not growing from nothing
W.FACING = 1           -- east (CF.facing(1, 0))

local function num(v) return tonumber(v) or 0 end

-- the step time: W.STEP_MS, longer when an effect footprint lives longer than FX_MAX_PER_CREATURE steps (the map refuses the
-- effect of a step when its walker already has that many alive; the preview slows down instead, so every step shows one)
function W.stepMs(CF, e)
  local ms = W.STEP_MS
  if type(e) == 'table' then
    ms = math.max(ms, math.ceil(CF.fxLife(e) / CF.FX_MAX_PER_CREATURE))
  end
  return math.min(ms, W.STEP_MAX_MS)
end

-- the rotation of an east step (what game_cosmeticfx gives the marks)
function W.rotation(CF)
  return CF.stepRotation({ x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 })
end

-- the feet (x, y in sprite px at 1x from the creature tile's top left) of an outfit walking east: foot_marks.lua's, as in game
function W.feet(CF, footMarks, outfit)
  return CF.feetOf(footMarks, CF.footThing(outfit), W.FACING)
end

-- The marks on the floor at time t, oldest first: {x, y, side, age, opacity, rank} with x, y the CENTRE of the mark in
-- sprite px at 1x from the creature tile's top left (x already moved back by the walk), side 0 / 1 (left / right foot).
-- mode = CF.MODES[CF.MODE]; fx, fy = W.feet; S = the step time.
function W.marks(CF, mode, fx, fy, S, t)
  local out = {}
  local k1 = math.floor(t / S)
  local k0 = math.max(0, k1 - math.ceil(mode.life / S) - 1)
  for k = k0, k1 do
    -- parity: which foot comes first; a step of one mark flips it, a step of two keeps it (CF.stepMarks)
    local list = CF.stepMarks(1, 0, fx, fy, (k * #mode.at) % 2, mode)
    for _, mk in ipairs(list) do
      local born = (k + mk.at) * S
      local age = t - born
      if age >= 0 and age < mode.life then
        out[#out + 1] = { owner = 1, born = born, age = age, side = mk.side,
          x = (k + mk.tx) * CF.TILE_PX + mk.px - t / S * CF.TILE_PX, y = mk.ty * CF.TILE_PX + mk.py }
      end
    end
  end
  -- the walker keeps its newest mode.maxPer marks (CF.evictions drops the oldest of an owner past that, whatever their age)
  while #out > mode.maxPer do table.remove(out, 1) end
  local ranks = CF.ranks(out)
  local live = {}
  for i, m in ipairs(out) do
    m.rank = ranks[i]
    m.opacity = CF.markOpacity(m.age, m.rank, mode)
    if m.opacity then live[#live + 1] = m end
  end
  return live
end

-- The effects of an effect footprint playing at time t: {k, ox, oy, ms, dur}: the step, the tile of the effect in tiles from the
-- creature tile (the tile the walker left plus the effect's own dx, dy, moved back by the walk), the ms it has played and its
-- length. e = {id, dx, dy, ms}; dur = its length in ms (e.ms, or the frames of the thing when the server sent none).
function W.effects(CF, e, dur, S, t)
  local out = {}
  if type(e) ~= 'table' or num(dur) <= 0 then return out end
  local life = math.max(num(dur), 1)
  local k1 = math.floor(t / S)
  local k0 = math.max(0, k1 - math.ceil((life + S) / S) - 1)
  for k = k0, k1 do
    local plan = CF.fxPlan({ x = k, y = 0, z = 0 }, e, S)
    local start = k * S + plan.delay
    local ms = t - start
    if ms >= 0 and ms < life then
      out[#out + 1] = { k = k, ox = plan.pos.x - t / S, oy = plan.pos.y, ms = ms, dur = life }
    end
  end
  return out
end

-- Stage pixels. L = a layout with tileX, tileY (the creature tile's top left), scale and T (P.walkLayout / P.fxLayout).
-- A mark of W.marks: {x, y (the centre), size, rotation, opacity, side} on the stage; size = CF.markSize at the stage's tile
-- (the map draws a mark 0.67 x 48 / 64 of a tile wide at any zoom).
function W.place(CF, mode, L, m)
  local size = CF.markSize(L.T, mode.kind)
  local s = L.scale
  return { x = math.floor(L.tileX + m.x * s - size / 2 + 0.5), y = math.floor(L.tileY + m.y * s - size / 2 + 0.5),
    size = size, opacity = m.opacity, side = m.side, rank = m.rank }
end

-- the picture of a mark: a foot picture per side, or the pair picture of a mode that draws one (as game_cosmeticfx putMark)
function W.picture(CF, mode, art, side)
  return mode.kind == 'pair' and CF.printPath(art) or CF.markPath(art, side)
end

-- One frame of the walk, all the numbers lookpreview.lua draws: {marks = {{x, y, size, opacity, side}}, rotation, effects = {...}}
-- opt = LookPreviewCore.walkOf(...) ({art} or {fx = {id, dx, dy, ms, dur}}); now = the preview's own ms; feet = {x, y}.
function W.frame(CF, opt, L, feet, now)
  local mode = CF.MODES[CF.MODE]
  local e = opt.fx
  local S = W.stepMs(CF, e)
  local t = num(now) + W.WARM_MS
  local out = { stepMs = S, marks = {}, effects = {}, rotation = W.rotation(CF), mode = mode }
  if e then
    out.effects = W.effects(CF, e, e.dur or e.ms, S, t)
  elseif opt.art then
    for _, m in ipairs(W.marks(CF, mode, feet[1], feet[2], S, t)) do
      out.marks[#out.marks + 1] = W.place(CF, mode, L, m)
    end
  end
  return out
end

return W
