-- luajit client/overlay/modules/game_lookpreview/footwalk_test.lua (and lua5.3), from the repo root
-- The footprint walk preview (O712) on its numbers: no engine, the in-game rules of game_cosmeticfx and the real feet table.
dofile('client/overlay/modules/game_cosmeticfx/cosmeticfxlogic.lua')
dofile('client/overlay/modules/game_cosmeticfx/foot_marks.lua')
dofile('client/overlay/modules/game_lookpreview/lookpreview_core.lua')
dofile('client/overlay/modules/game_lookpreview/footwalk.lua')
local CF, W, P, FM = CosmeticFxLogic, FootWalk, LookPreviewCore, CosmeticFootMarks

local n = 0
local function eq(a, b, m)
  n = n + 1
  if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end
end
local function near(a, b, m, tol)
  n = n + 1
  if math.abs(a - b) > (tol or 1e-6) then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end
end
local function slurp(path) local fh = assert(io.open(path, 'rb')) local t = fh:read('*a') fh:close() return t end

local MODES = { 'feet', 'soft', 'pairs' }
local function withMode(mode, fn)
  local old = CF.MODE
  CF.MODE = mode
  fn(CF.MODES[mode])
  CF.MODE = old
end

-- ---------------------------------------------------------------- the step time
eq(W.stepMs(CF, nil), W.STEP_MS, 'a drawn footprint: the calm walk')
eq(W.stepMs(CF, { id = 5334, dx = 0, dy = 0, ms = 800 }), W.STEP_MS, 'a short effect keeps it')
eq(W.stepMs(CF, { id = 5343, dx = 0, dy = 0, ms = 1500 }), 600, 'a long effect slows it: 3 alive at most')
eq(W.stepMs(CF, { id = 1, dx = 0, dy = 0, ms = 9000 }), W.STEP_MAX_MS, 'never slower than the cap')
eq(W.rotation(CF), 90, 'walking east')
eq(CF.facing(1, 0), W.FACING, 'east is the facing the feet are read for')

-- every effect footprint of the server (O649): the map would admit one effect every step at this walk (CF.fxAdmit), so
-- the preview shows one on every step and never a gap
local ids = slurp('server/data/lib/chaos_footprint_fx_ids.lua')
local count = 0
for name, id, dx, dy, ms in ids:gmatch('(fp_[%w_]+)%s*=%s*{id = (%d+), dx = (%-?%d+), dy = (%-?%d+), ms = (%d+)') do
  count = count + 1
  local e = { id = tonumber(id), dx = tonumber(dx), dy = tonumber(dy), ms = tonumber(ms) }
  local S = W.stepMs(CF, e)
  local active = {}
  local refused = 0
  for k = 0, 60 do
    local plan = CF.fxPlan({ x = k, y = 0, z = 0 }, e, S)
    local at = k * S + plan.delay
    local ok, live = CF.fxAdmit(active, 1, at)
    active = live
    if ok then active[#active + 1] = { owner = 1, untilMs = at + CF.fxLife(e) } else refused = refused + 1 end
  end
  eq(refused, 0, name .. ' is admitted every step at ' .. S .. ' ms')
  -- at most FX_MAX_PER_CREATURE playing at any moment, and the walk shows one that plays
  local most, showing = 0, 0
  for t = 0, 8000, 20 do
    local list = W.effects(CF, e, e.ms, S, t)
    most = math.max(most, #list)
    if #list > 0 then showing = showing + 1 end
  end
  eq(most <= CF.FX_MAX_PER_CREATURE, true, name .. ' at most ' .. CF.FX_MAX_PER_CREATURE .. ' at once')
  eq(showing > 0, true, name .. ' plays')
end
eq(count, 20, 'the 20 effect footprints of pair 75')

-- ---------------------------------------------------------------- the marks
-- the real feet of the plain look 128 walking east, as the map reads them
local fx, fy = W.feet(CF, FM, { type = 128 })
local ex, ey = CF.feetOf(FM, 128, CF.facing(1, 0))
eq(fx .. ',' .. fy, ex .. ',' .. ey, 'the feet are the ones the map uses')
local mfx, mfy = W.feet(CF, FM, { type = 128, mount = 1338 })
local mex, mey = CF.feetOf(FM, 1338, 1)
eq(mfx .. ',' .. mfy, mex .. ',' .. mey, 'a rider\'s feet are the mount\'s')
eq(select(1, W.feet(CF, nil, { type = 9999 })), CF.FEET_FALLBACK[1], 'no table: the fallback feet')

for _, name in ipairs(MODES) do
  withMode(name, function(mode)
    local S = W.stepMs(CF, nil)
    for _, t in ipairs({ 0, 1, 137, 999, 4000, 4210, 60000, 123457 }) do
      local list = W.marks(CF, mode, fx, fy, S, t)
      local tag = name .. ' t=' .. t
      eq(#list <= mode.maxPer, true, 'at most maxPer marks: ' .. tag)
      local lastBorn, lastOp = -1, nil
      for i, m in ipairs(list) do
        eq(m.age >= 0 and m.age < mode.life, true, 'a live mark: ' .. tag)
        eq(m.opacity > 0 and m.opacity <= mode.alpha, true, 'opacity within the mode: ' .. tag)
        eq(m.born > lastBorn, true, 'oldest first: ' .. tag) lastBorn = m.born
        -- the foot lands under the walker: its place at birth is the feet point of the walker (before the lateral shift)
        near(m.x + (m.age / S) * CF.TILE_PX, fx, 'the foot landed at the walker feet point: ' .. tag, 1e-6)
        if mode.lateral then
          near(math.abs(m.y - fy), CF.LATERAL, 'a foot sits ' .. CF.LATERAL .. ' px beside the line: ' .. tag)
          eq(m.side == 1, m.y > fy, 'the right foot is south of an east walk: ' .. tag)
        else
          near(m.y, fy, 'a pair picture on the line: ' .. tag)
        end
        eq(m.x <= fx + 1e-6, true, 'at most at the feet: ' .. tag)
        if i > 1 then eq(m.x > list[i - 1].x, true, 'older marks lie further back: ' .. tag) end
      end
      -- the newest is the strongest of a mode that ranks (opacity falls with age and rank)
      if mode.rankFade > 0 and #list >= 2 then
        eq(list[#list].opacity > list[1].opacity, true, 'the newest is stronger: ' .. tag)
      end
    end
    -- a steady walk looks the same two steps later (the feet alternate with period 2): marks move by one tile in the floor frame, same count, same opacities
    local a, b = W.marks(CF, mode, fx, fy, S, 5000), W.marks(CF, mode, fx, fy, S, 5000 + 2 * S)
    eq(#a, #b, name .. ': the same marks two steps later (the feet alternate with period 2)')
    for i = 1, #a do
      near(a[i].x, b[i].x, name .. ': same place two steps later (the feet alternate with period 2)', 1e-6)
      near(a[i].opacity, b[i].opacity, name .. ': same opacity two steps later (the feet alternate with period 2)', 1e-6)
      eq(a[i].side, b[i].side, name .. ': same foot')
    end
    -- feet alternate over the whole trail (a step of two marks: left, right, left, right)
    if #mode.at == 2 then
      for i = 2, #a do eq(a[i].side ~= a[i - 1].side, true, name .. ': feet alternate') end
    end
    -- the trail does not jump: 20 ms later every mark has moved back by 20 / S tiles and none appeared out of nowhere
    local c, d = W.marks(CF, mode, fx, fy, S, 7000), W.marks(CF, mode, fx, fy, S, 7020)
    for i = 1, #c do
      local found
      for _, m in ipairs(d) do if m.born == c[i].born then found = m end end
      if found then near(found.x, c[i].x - 20 / S * CF.TILE_PX, name .. ': moves back with the floor', 1e-6) end
    end
    eq(#d <= mode.maxPer, true, name .. ': no more marks after a step')
  end)
end

-- the mark cap is the walker's newest marks (CF.evictions drops the oldest of an owner past maxPer)
withMode('feet', function(mode)
  local prints, owner = {}, 1
  for k = 0, 30 do
    for j = 1, #mode.at do
      for _, i in ipairs(CF.evictions(prints, owner, 1, mode.maxPer)) do prints[i] = false end
      local keep = {}
      for _, p in ipairs(prints) do if p then keep[#keep + 1] = p end end
      prints = keep
      prints[#prints + 1] = { owner = owner, born = (k + mode.at[j]) * W.STEP_MS }
    end
  end
  local t = 30 * W.STEP_MS + W.STEP_MS * 0.99
  local mine = W.marks(CF, mode, fx, fy, W.STEP_MS, t)
  local want = {}
  for _, p in ipairs(prints) do if t - p.born < mode.life then want[#want + 1] = p.born end end
  eq(#mine, #want, 'the same marks the map keeps')
  for i = 1, #mine do near(mine[i].born, want[i], 'the same mark ' .. i, 1e-6) end
end)

-- a walk that has just begun shows no mark of the future and the warm start has laid a trail
withMode('feet', function(mode)
  eq(#W.marks(CF, mode, fx, fy, W.STEP_MS, 0), 0, 'time 0: nothing yet')
  local f = W.frame(CF, { art = 'ash' }, { tileX = 100, tileY = 50, scale = 2, T = 64 }, { fx, fy }, 0)
  eq(#f.marks > 0, true, 'the preview starts with a trail laid')
end)

-- ---------------------------------------------------------------- on the stage
local L = { tileX = 140, tileY = 60, scale = 2, T = 64 }
withMode('feet', function(mode)
  local f = W.frame(CF, { art = 'ash' }, L, { fx, fy }, 1234)
  eq(f.rotation, 90, 'the marks turn east')
  eq(f.stepMs, W.STEP_MS, 'a drawn footprint walks at the calm pace')
  eq(#f.effects, 0, 'no effect')
  local size = CF.markSize(L.T, mode.kind)
  eq(size, 32, 'a foot mark is half a 64 px tile wide')
  local feetX, feetY = L.tileX + fx * L.scale, L.tileY + fy * L.scale
  for i, m in ipairs(f.marks) do
    eq(m.size, size, 'mark size ' .. i)
    local cx, cy = m.x + size / 2, m.y + size / 2
    eq(cx <= feetX + (mode.at[#mode.at]) * 64 + 1, true, 'behind the feet ' .. i)
    eq(math.abs(cy - feetY) <= CF.LATERAL * L.scale + 1, true, 'on the floor line under the feet ' .. i)
  end
  -- the spacing of one step: the two feet are (at2 - at1) of a tile apart (half a tile at 2x: 32 px)
  local last = f.marks[#f.marks]
  local prev = f.marks[#f.marks - 1]
  near(math.abs((last.x + size / 2) - (prev.x + size / 2)), (mode.at[2] - mode.at[1]) * 64, 'the feet of a step are half a tile apart', 1.01)
  eq(W.picture(CF, mode, 'ash', 0), '/modules/game_cosmeticfx/images/marks/ash_l', 'the left foot picture')
  eq(W.picture(CF, mode, 'ash', 1), '/modules/game_cosmeticfx/images/marks/ash_r', 'the right foot picture')
end)
withMode('pairs', function(mode)
  eq(W.picture(CF, mode, 'ash', 1), '/modules/game_cosmeticfx/images/prints/ash', 'a pair mode draws the pair picture')
end)

-- every drawn footprint of the server has its foot pictures: the preview shows its own art
local cfg = slurp('server/data/scripts/chaos/cosmetics_config.lua')
local list = cfg:match('prints = {([^}]*)}')
local arts = 0
for art in list:gmatch('"([%w_]+)"') do
  arts = arts + 1
  for _, side in ipairs({ '_l', '_r' }) do
    local fh = io.open('client/overlay/modules/game_cosmeticfx/images/marks/' .. art .. side .. '.png', 'rb')
    eq(fh ~= nil, true, art .. side .. ' exists')
    if fh then fh:close() end
  end
end
eq(arts, 14, 'the 14 drawn footprints')

-- ---------------------------------------------------------------- the effects
local e = { id = 5340, dx = 0, dy = 0, ms = 1100 }
local S = W.stepMs(CF, e)
local seen = {}
for t = 3000, 3000 + 6 * S, 10 do
  for _, a in ipairs(W.effects(CF, e, 1100, S, t)) do
    eq(a.ms >= 0 and a.ms < 1100, true, 'within its play')
    eq(a.oy, 0, 'on the walker\'s row')
    -- the tile the walker left: step k, moved back by the walk
    near(a.ox, a.k - t / S, 'the tile of step k, run back by the floor', 1e-9)
    -- it starts FX_AT of the step in, when the walker is leaving the tile (CF.fxPlan)
    near(a.ms, t - (a.k + CF.FX_AT) * S, 'starts ' .. CF.FX_AT .. ' of a step in', 1.01)
    seen[a.k] = true
  end
end
local ks = 0
for _ in pairs(seen) do ks = ks + 1 end
eq(ks >= 6, true, 'one effect every step')
-- the effect's own offset moves its tile (the bottom right tile of an effect is drawn on the tile + dx, dy)
local o = W.effects(CF, { id = 5, dx = 1, dy = 2, ms = 600 }, 600, 420, 2000)[1]
near(o.ox, o.k + 1 - 2000 / 420, 'dx moves the tile') eq(o.oy, 2, 'dy moves the tile')
eq(#W.effects(CF, e, 0, S, 3000), 0, 'an effect of no length plays nothing')
eq(#W.effects(CF, nil, 100, S, 3000), 0, 'no effect')
-- the frame of an effect footprint carries its effects and no marks
local ff = W.frame(CF, { fx = { id = 5340, dx = 0, dy = 0, ms = 1100, dur = 1100 } }, L, { fx, fy }, 500)
eq(#ff.marks, 0, 'an effect footprint draws no marks') eq(ff.stepMs, W.stepMs(CF, { id = 5340, ms = 1100 }), 'its own pace')
local any = false
for t = 0, 3000, 25 do
  if #W.frame(CF, { fx = { id = 5340, dx = 0, dy = 0, ms = 1100, dur = 1100 } }, L, { fx, fy }, t).effects > 0 then any = true end
end
eq(any, true, 'an effect plays within three seconds')

print('footwalk_test: ' .. n .. ' checks OK')
