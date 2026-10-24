-- luajit helper_logic_test.lua && lua5.3 helper_logic_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'helper_logic.lua')
local L = ChaosHelperLogic
local D = L.DIR
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local function ok(c, what) eq(not not c, true, what) end

-- a beam two long to the north (the caster at the bottom)
local beam = { { 0, 1, 0 }, { 0, 1, 0 }, { 0, 3, 0 } }
local from = { x = 10, y = 10, z = 7 }
local function at(id, x, y, z) return { id = id, position = { x = x, y = y, z = z or 7 } } end
eq(L.countHits(from, D.North, beam, { at(1, 10, 9), at(2, 10, 8), at(3, 11, 9) }), 2, 'north beam')
eq(L.countHits(from, D.South, beam, { at(1, 10, 11), at(2, 10, 12) }), 2, 'south beam')
eq(L.countHits(from, D.East, beam, { at(1, 11, 10), at(2, 12, 10) }), 2, 'east beam')
eq(L.countHits(from, D.West, beam, { at(1, 9, 10), at(2, 8, 10) }), 2, 'west beam')
eq(L.countHits(from, D.North, beam, { at(1, 10, 9, 8) }), 0, 'another floor')
eq(L.countHits(from, D.North, beam, { at(1, 10, 10) }), 0, 'the caster cell does not count by default')
eq(L.countHits(from, D.North, beam, { at(1, 10, 10) }, { ranged = true }), 1, 'ranged counts the caster cell')
eq(L.countHits(from, D.SouthEast, beam, { at(1, 11, 10) }), 1, 'a diagonal facing counts as east')
eq(L.countHits(from, D.North, beam, { at(1, 10, 8) }, { sight = function() return false end }), 0, 'no sight, no hit')
eq(L.countHits(from, D.North, beam, { at(1, 10, 9) }, { sight = function() return false end }), 1, 'a neighbour needs no sight')
local dir, n = L.bestDirection(from, beam, { at(1, 10, 11), at(2, 10, 12), at(3, 10, 9) })
eq(dir, D.South, 'best facing')
eq(n, 2, 'best hits')
eq(L.bestDirection(from, beam, { at(1, 30, 30) }), nil, 'nothing to hit')

-- reach
eq(L.inReach(from, { x = 17, y = 15, z = 7 }), true, 'the corner of the window')
eq(L.inReach(from, { x = 18, y = 10, z = 7 }), false, 'too far east')
eq(L.inReach(from, { x = 10, y = 16, z = 7 }), false, 'too far south')
eq(L.inReach(from, { x = 10, y = 10, z = 8 }), false, 'another floor')

-- modes
local function m(id, x, y, h, hits) return { id = id, position = { x = x, y = y, z = 7 }, health = h, hits = hits } end
local c = { m(1, 11, 10, 100), m(2, 12, 10, 20), m(3, 11, 11, 40), m(4, 15, 10, 5) }
eq(L.pickByMode(c, from, 1).id, 1, 'A closest (tie to the lower id)')
eq(L.pickByMode(c, from, 2).id, 4, 'B farthest')
eq(L.pickByMode(c, from, 3).id, 4, 'C lowest health')
eq(L.pickByMode(c, from, 4).id, 1, 'D highest health')
eq(L.pickByMode(c, from, 6).id, 3, 'F closest, then lowest health')
eq(L.pickByMode(c, from, 7).id, 1, 'G closest, then highest health')
eq(L.pickByMode(c, from, 8).id, 4, 'H farthest, then lowest health')
eq(L.pickByMode({ m(1, 11, 10, 100, 1), m(2, 12, 10, 20, 4) }, from, 5).id, 2, 'E most hits')
eq(L.pickByMode(c, from, nil).id, 3, 'no mode: F')
eq(L.pickByMode({}, from, 1), nil, 'no candidates')

-- heal
local rows = { { id = 1, percent = 80 }, { id = 2, percent = 40 }, { id = 0, percent = 99 } }
eq(L.pickHeal(rows, { healthPct = 100 }), nil, 'full health')
eq(L.pickHeal(rows, { healthPct = 70 }), 1, 'the light heal')
eq(L.pickHeal(rows, { healthPct = 30 }), 2, 'the lowest threshold first')
eq(L.pickHeal(rows, { healthPct = 30, ready = function(id) return id ~= 2 end }), 1, 'the next one when one is not ready')

-- training, haste
eq(L.trainingDue({ id = 5, percent = 90, enabled = true }, 95), true, 'training above the percent')
eq(L.trainingDue({ id = 5, percent = 90, enabled = true }, 80), false, 'training below')
eq(L.trainingDue({ id = 5, percent = 90, enabled = false }, 95), false, 'training off')
local h = { id = 6, enabled = true }
eq(L.hasteDue(h, { hasted = false, now = 10000 }), true, 'haste due')
eq(L.hasteDue(h, { hasted = true, now = 10000 }), false, 'already hasted')
eq(L.hasteDue(h, { hasted = false, now = 10000, last = 9000 }), false, 'too soon after the last cast')
eq(L.hasteDue(h, { hasted = false, now = 12600, last = 10000 }), true, 'after the gap')
eq(L.hasteDue(h, { hasted = false, now = 10000, inProtectionZone = true }), false, 'not in a protection zone')
eq(L.hasteDue({ id = 6, enabled = true, safecast = true }, { now = 10000, inProtectionZone = true }), true, 'safe cast')

-- a haste that never shows (a spell the server no longer has) backs off instead of being said twice a second
eq(L.hasteGap(0), 2500, 'gap: no miss')
eq(L.hasteGap(1), 5000, 'gap: doubles per miss')
eq(L.hasteGap(50), L.HASTE_MAX_GAP_MS, 'gap: capped')
do
  local hs, t, casts = { misses = 0 }, 0, 0
  while t < 600000 do -- ten minutes of 500 ms ticks, never hasted
    L.hasteObserve(hs, false)
    if L.hasteDue(h, { hasted = false, now = t, last = hs.last, misses = hs.misses }) then
      L.hasteCast(hs, t)
      casts = casts + 1
    end
    t = t + 500
  end
  ok(casts <= 12, 'never hasted: at most 12 casts in 10 minutes, got ' .. casts)
  eq(L.hasteDue(h, { hasted = false, now = hs.last + 2500, last = hs.last, misses = hs.misses }), false, 'still backed off')
  L.hasteObserve(hs, true)
  eq(hs.misses, 0, 'the haste showing clears the misses')
  L.hasteObserve(hs, false)
  L.hasteCast(hs, 700000)
  eq(hs.misses, 0, 'a cast after a seen haste is no miss')
end

-- slots
eq(L.slotDue({ id = 1, percent = 50, creatures = 3 }, 60, 2), false, 'too few creatures')
eq(L.slotDue({ id = 1, percent = 50, creatures = 3 }, 60, 3), true, 'enough creatures')
eq(L.slotDue({ id = 1, percent = 50, creatures = 3 }, 40, 3), false, 'too little mana')
eq(L.slotDue({ id = 1, percent = 50, creatures = 3, forceCast = true }, 60, 0), false, 'force cast does not skip the count')
eq(L.facingToward(from, { x = 14, y = 11, z = 7 }), D.East, 'facing east')
eq(L.facingToward(from, { x = 10, y = 5, z = 7 }), D.North, 'facing north')
eq(L.facingToward(from, { x = 10, y = 10, z = 7 }), nil, 'same tile')
eq(L.facingToward(from, { x = 12, y = 12, z = 7 }), D.South, 'a tie goes vertical')
local order = L.slotOrder({ { id = 1, priority = 3 }, { id = 2, priority = 1 }, { id = 0, priority = 0 }, { id = 3, priority = 2 } })
eq(#order, 3, 'empty slots are not tried')
eq(order[1].id, 2, 'priority order')
eq(order[3].id, 1, 'priority order last')

if fails > 0 then os.exit(1) end
print('helper_logic_test: ok')
