-- luajit client/overlay/modules/game_hideout/hideoutlogic_test.lua (and lua5.3), from the repo root
dofile('client/overlay/modules/game_hideout/hideoutlogic.lua')
local HL = HideoutLogic

local n = 0
local function eq(a, b, m)
  n = n + 1
  if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end
end
local function ok(v, m) eq(not not v, true, m) end

-- a state as the server sends it (hideout_core.lua K.catalogueView / K.layoutView)
local layout = { w = 15, h = 11, arrival = { 8, 10 }, reserved = {
  { 8, 10, 'arrival' }, { 8, 11, 'exit' }, { 2, 1, 'depot' }, { 4, 1, 'stash' }, { 13, 1, 'dummy1' }, { 14, 1, 'dummy2' },
  { 1, 1, 'light1' }, { 15, 1, 'light2' }, { 1, 11, 'light3' }, { 15, 11, 'light4' } } }
local catalogue = {
  { key = 'throne', name = 'Ashen Throne', cat = 'furniture', layer = 'object', owned = true, max = 2, placed = 0,
    source = 'default', rots = { { { 0, 0, 101 } }, { { 0, 0, 102 } }, { { 0, 0, 103 } }, { { 0, 0, 104 } } } },
  { key = 'table', name = 'Stone Table', cat = 'furniture', layer = 'object', block = true, owned = true, max = 20, placed = 0,
    source = 'default', rots = { { { 0, 0, 201 } } } },
  { key = 'rug', name = 'Crimson Rug', cat = 'rug', layer = 'floor', owned = true, max = 20, placed = 0, source = 'default',
    rots = { { { 0, 0, 301 } } } },
  { key = 'tapestry', name = 'Crimson Tapestry', cat = 'wall', layer = 'wall', owned = true, max = 4, placed = 0,
    source = 'default', rots = { { { 0, 0, 401 } } }, wallW = { { 0, 0, 402 } } },
  { key = 'gargoyle', name = 'Gargoyle', cat = 'statue', layer = 'object', block = true, owned = false, max = 4, placed = 0,
    source = 'store', how = 'Store: 200 Chaos Coins', price = 200, rots = { { { 0, 0, 501 } } } },
  { key = 'bench', name = 'Bench', cat = 'furniture', layer = 'object', block = true, owned = true, max = 4, placed = 0,
    source = 'default', rots = { { { 0, 0, 601 }, { 1, 0, 602 } }, { { 0, 0, 603 }, { 0, 1, 604 } } } },
  { key = 'trophy', name = 'Sovereign\'s Monument', cat = 'trophy', layer = 'object', block = true, owned = false, max = 1,
    placed = 0, source = 'trophy', how = 'A trophy of your own kills', rots = { { { 0, 0, 701 } } } },
}
local function newState()
  return { layout = layout, catalogue = catalogue, placed = {}, hideout = { count = 0, max = 24, themeName = 'Ashen Crypt' },
    inside = { owner = 1, isOwner = true, origin = { x = 12288, y = 12288, z = 7 } } }
end

-- filters
local rows = HL.filter(catalogue, {})
eq(#rows, #catalogue, 'no filter')
ok(rows[1].owned and not rows[#rows].owned, 'unlocked first')
eq(rows[1].name, 'Ashen Throne', 'then by name')
eq(#HL.filter(catalogue, { cat = 'furniture' }), 3, 'by kind')
eq(#HL.filter(catalogue, { source = 'store' }), 1, 'by source')
eq(#HL.filter(catalogue, { source = 'trophy' }), 1, 'trophies')
eq(#HL.filter(catalogue, { ownedOnly = true }), 5, 'unlocked only')
eq(#HL.filter(catalogue, { search = '  CRIMSON ' }), 2, 'search ignores case and spaces')
eq(#HL.filter(catalogue, { cat = 'all', source = 'all', search = '' }), #catalogue, 'all')
-- texts
eq(HL.subText(catalogue[5]), 'Locked - Store: 200 Chaos Coins', 'lock reason')
eq(HL.subText(catalogue[1]), '0 / 2 placed', 'count')
eq(HL.countText({ themeName = 'Ember Forge', count = 3, max = 30 }), 'Ember Forge - 3 / 30 decorations', 'counter')
eq(HL.permName({ { id = 0, name = 'Private' }, { id = 3, name = 'Public' } }, 3), 'Public', 'permission name')
ok(HL.visitLine({ name = 'Ana', theme = 'Ashen Crypt', why = 'friend', likes = 2 }):find('VIP', 1, true), 'visit line')
-- may place
local s = newState()
ok(HL.canPlace(catalogue[1], s.hideout, s.inside), 'can place')
local okP, why = HL.canPlace(catalogue[5], s.hideout, s.inside)
ok(not okP and why:find('Locked', 1, true), 'locked')
okP, why = HL.canPlace(catalogue[1], s.hideout, { isOwner = false })
ok(not okP and why:find('Enter your hideout', 1, true), 'only inside your own')
okP = HL.canPlace(catalogue[1], { count = 24, max = 24 }, s.inside)
ok(not okP, 'full hideout')
okP = HL.canPlace({ owned = true, placed = 2, max = 2 }, s.hideout, s.inside)
ok(not okP, 'per decoration limit')
-- rotation
eq(HL.rotCount(catalogue[1]), 4, 'four rotations')
eq(HL.nextRot(catalogue[1], 4), 1, 'wraps forward')
eq(HL.nextRot(catalogue[1], 1, -1), 4, 'wraps back')
eq(HL.rotCount(catalogue[4]), 1, 'walls do not rotate')
eq(HL.parts(catalogue[1], 3)[1][3], 103, 'rotation parts')
eq(HL.parts(catalogue[4], 1, 'w')[1][3], 402, 'west wall id')
eq(HL.parts(catalogue[4], 1, 'n')[1][3], 401, 'north wall id')
-- positions
local o = s.inside.origin
local gx, gy = HL.toGrid(o, layout, { x = 12288 + 5, y = 12288 + 3, z = 7 })
eq(gx, 5, 'grid x') eq(gy, 3, 'grid y')
eq(HL.toGrid(o, layout, { x = 12288 + 5, y = 12288 + 3, z = 6 }), nil, 'other floor')
eq(HL.toGrid(o, layout, { x = 12288 + 17, y = 12288, z = 7 }), nil, 'outside')
eq(HL.toGrid(o, layout, { x = 12287, y = 12288, z = 7 }), nil, 'west of the room')
local w = HL.toWorld(o, 5, 3)
eq(w.x, 12293, 'world x') eq(w.z, 7, 'world z')
eq(HL.wallSide(layout, 4, 0), 'n', 'north wall')
eq(HL.wallSide(layout, 0, 4), 'w', 'west wall')
eq(HL.wallSide(layout, 0, 0), nil, 'corner')
eq(HL.wallSide(layout, 16, 4), nil, 'east wall')

-- the placement check (mirrors hideout_core.lua K.placeProblem)
ok(HL.check(s, catalogue[1], 5, 5, 1), 'free tile')
local okC
okC, why = HL.check(s, catalogue[1], 8, 10, 1)
ok(not okC and why:find('kept free', 1, true), 'arrival tile')
okC = HL.check(s, catalogue[1], 0, 5, 1)
ok(not okC, 'not in a wall')
okC = HL.check(s, catalogue[1], 16, 5, 1)
ok(not okC, 'not east of the room')
s.placed = { { id = 1, key = 'throne', x = 5, y = 5, r = 1 } }
okC, why = HL.check(s, catalogue[2], 5, 5, 1)
ok(not okC and why:find('stands', 1, true), 'one object per tile')
ok(HL.check(s, catalogue[3], 5, 5, 1), 'a rug under the throne')
ok(HL.check(s, catalogue[1], 5, 5, 1, 1), 'moving onto its own tile')
s.placed[2] = { id = 2, key = 'rug', x = 6, y = 6, r = 1 }
okC = HL.check(s, catalogue[3], 6, 6, 1)
ok(not okC, 'one rug per tile')
-- walls
ok(HL.check(s, catalogue[4], 4, 0, 1), 'north wall')
ok(HL.check(s, catalogue[4], 0, 4, 1), 'west wall')
okC = HL.check(s, catalogue[4], 4, 4, 1)
ok(not okC, 'not on the floor')
s.placed[3] = { id = 3, key = 'tapestry', x = 4, y = 0, r = 1 }
okC = HL.check(s, catalogue[4], 4, 0, 1)
ok(not okC, 'one per wall tile')
-- multi-tile and rotation
okC = HL.check(s, catalogue[6], 15, 5, 1)
ok(not okC, 'second tile outside')
ok(HL.check(s, catalogue[6], 15, 5, 2), 'rotated it fits')
okC = HL.check(s, catalogue[6], 4, 5, 1)
ok(not okC, 'second tile on the throne')
-- limits
s.placed = { { id = 1, key = 'throne', x = 5, y = 5 }, { id = 2, key = 'throne', x = 6, y = 5 } }
okC, why = HL.check(s, catalogue[1], 7, 5, 1)
ok(not okC and why:find('At most 2', 1, true), 'per decoration limit')
s.hideout.max = 2
okC, why = HL.check(s, catalogue[3], 9, 5, 1)
ok(not okC and why:find('full', 1, true), 'the hideout is full')
s.hideout.max = 24
-- the path: walling off the depot (2,1) is refused at the last tile
s.placed = { { id = 1, key = 'table', x = 1, y = 2 }, { id = 2, key = 'table', x = 2, y = 2 }, { id = 3, key = 'table', x = 3, y = 2 } }
okC, why = HL.check(s, catalogue[2], 3, 1, 1)
ok(not okC and why:find('depot', 1, true), 'the depot stays reachable: ' .. tostring(why))
ok(HL.check(s, catalogue[3], 3, 1, 1), 'a rug does not block')
-- a line across the room
s.placed = {}
local refused = 0
for x = 1, 15 do
  if HL.check(s, catalogue[2], x, 9, 1) then
    s.placed[#s.placed + 1] = { id = x, key = 'table', x = x, y = 9 }
  else
    refused = refused + 1
  end
end
eq(refused, 1, 'one tile of the line stays open')
local reach = HL.reachOk(layout, {})
ok(reach, 'the empty room reaches everything')

print('hideoutlogic_test: ' .. n .. ' checks OK')
