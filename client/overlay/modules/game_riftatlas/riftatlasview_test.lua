-- luajit riftatlasview_test.lua && lua5.3 riftatlasview_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'riftatlasview.lua')
local fails, checks = 0, 0
local function ok(c, what)
  checks = checks + 1
  if not c then print('FAIL ' .. what); fails = fails + 1 end
end
local function eq(a, b, what) ok(a == b, what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)) end
local V = RiftAtlasView

-- a small tree in the server's format: start 1, a chain 2-3, a ring 4 (to 1 and 2), a notable 5 on 3, keystones 6 and 7
local tree = {
  start = 1, keystoneMax = 1, max = 10,
  branches = { { k = 'abyss', n = 'Abyssal Rift', th = 'Abyssal Rift', d = 'north', c = '#9a6ae8' } },
  grid = { themes = { 'Abyssal Rift', 'Obsidian Hall' }, tiers = 3, omens = { { k = 'storm', n = 'Stormcall', b = 'Thalcyra' } },
    points = { cell = 1, flawless = 1, swift = 1, omen = 2 }, swift = 300 },
  nodes = {
    { i = 1, n = 'Heart', k = 'start', x = 0, y = 0, c = 0, l = {}, t = {}, g = 'start' },
    { i = 2, n = 'Tear', k = 'small', x = 0, y = -90, c = 1, l = { 1 }, t = { '+3% monster packs' }, g = 'density' },
    { i = 3, n = 'Tear', k = 'small', x = 0, y = -170, c = 1, l = { 2 }, t = { '+3% monster packs' }, g = 'density' },
    { i = 4, n = 'Strain', k = 'small', x = 90, y = 0, c = 1, l = { 1, 2 }, t = {}, g = 'reward' },
    { i = 5, n = 'Abyssal Attunement', k = 'notable', b = 'Abyssal Rift', x = 0, y = -260, c = 2, l = { 3 }, t = {}, g = 'theme' },
    { i = 6, n = 'Lone Ember', k = 'keystone', b = 'Abyssal Rift', x = 0, y = -360, c = 3, l = { 5 }, t = { 'One life.' }, g = 'ks_ember' },
    { i = 7, n = 'Other', k = 'keystone', x = 90, y = 90, c = 3, l = { 4 }, t = {}, g = 'ks_crown' },
    { i = 8, n = 'Broken', k = 'small', x = 200, y = 0, c = 1, l = { 99, 8 }, t = {}, g = 'nope' },
  },
}
local ix = V.index(tree)
eq(#ix.list, 8, 'nodes indexed')
ok(ix.adj[2][4] and ix.adj[4][2], 'links are symmetric')
ok(ix.adj[8] and next(ix.adj[8]) == nil, 'unknown and self links dropped')
eq(#ix.pairs, 7, 'each link once: 1-2 2-3 1-4 2-4 3-5 5-6 4-7')

-- allocation rules
local alloc = {}
eq(V.canAllocate(ix, alloc, 2, 5, 1), true, 'next to the start')
eq(select(2, V.canAllocate(ix, alloc, 3, 5, 1)), 'path', 'not connected')
eq(select(2, V.canAllocate(ix, alloc, 2, 0, 1)), 'points', 'no points')
eq(select(2, V.canAllocate(ix, alloc, 1, 5, 1)), 'unknown', 'the start')
eq(V.status(ix, alloc, 1, 5, 1), 'start', 'start status')
eq(V.status(ix, alloc, 2, 5, 1), 'avail', 'available')
eq(V.status(ix, alloc, 2, 0, 1), 'reach', 'reachable without points')
eq(V.status(ix, alloc, 3, 5, 1), 'locked', 'locked')
alloc = { [2] = true, [3] = true, [5] = true, [6] = true, [4] = true }
eq(V.status(ix, alloc, 6, 5, 1), 'alloc', 'allocated')
eq(select(2, V.canAllocate(ix, alloc, 7, 5, 1)), 'keystone', 'second keystone refused')
eq(V.status(ix, alloc, 7, 5, 1), 'reach', 'keystone limit shows as reachable')
eq(select(2, V.canRefund(ix, alloc, 3)), 'path', 'refund of a bridge refused')
eq(V.canRefund(ix, alloc, 6), true, 'refund of a leaf')
eq(alloc[6], true, 'canRefund leaves the allocation alone')
-- 2 is a bridge for 3, but 4 is a leaf (1-4 and 2-4 both reach the start)
eq(V.canRefund(ix, alloc, 4), true, 'ring node refund')
eq(select(2, V.canRefund(ix, alloc, 2)), 'path', '3 hangs on 2')
eq(select(2, V.canRefund(ix, alloc, 7)), 'not held', 'not held')
eq(V.linkState(ix, alloc, 1, 2), 'Active', 'link both held (start counts)')
eq(V.linkState(ix, alloc, 4, 7), 'Intermediate', 'link one end held')
eq(V.linkState(ix, {}, 2, 3), 'Normal', 'link none held')

-- sets
local st = { alloc = { 2, 3 }, done = { 'c1.1', 'f1', 'ostorm' }, points = 4, earned = 6, spent = 2, max = 10,
  refund = { gold = 250000, orbs = 1 }, orb = 'Orb of Upheaval' }
local a = V.allocSet(st)
ok(a[2] and a[3] and not a[1], 'alloc set')
local d = V.doneSet(st)
ok(d['c1.1'] and d['ostorm'], 'done set')
eq(next(V.allocSet(nil)), nil, 'nil state')

-- art
eq(V.iconSet(ix, ix.byId[5]), 'abyss', 'branch sheet')
eq(V.iconSet(ix, ix.byId[2]), 'core', 'core sheet')
eq(V.glyphOf(ix, ix.byId[5]), 'theme_abyss', 'theme glyph')
eq(V.iconClip('density'), '0 0 64 64', 'first cell')
eq(V.iconClip('ks_hourglass'), (#V.GLYPHS - 1) * 64 .. ' 0 64 64', 'last cell')
eq(V.iconClip('nope'), '0 0 64 64', 'unknown glyph')
local f = V.frame('small', 'alloc', 27)
eq(f.source, '/images/passivetree/common_active', 'small allocated frame')
eq(f.w, 56, 'frame size at zoom 1')
eq(V.frame('notable', 'avail', 38).source, '/images/passivetree/NotableFrameCanAllocate', 'notable frame')
eq(V.frame('keystone', 'locked', 30).w, 72, 'keystone frame scaled with the node')
eq(V.frame('start', 'start', 50), nil, 'start has no frame')

-- view
ok(V.nodeSize('small', 0.3) < V.nodeSize('small', 1.0), 'smaller when zoomed out')
eq(V.nodeSize('small', 1.0), 27, 'full size at zoom 1')
ok(V.nodeSize('small', 0.3) >= 8, 'never tiny')
local w = V.world(ix)
eq(w.w, 200 + 2 * V.MARGIN, 'world width')
local px, py = V.clampPan(5000, -5000, 1, w, 200, 200)
ok(px > 0 and px < 5000 and py < 0 and py > -5000, 'pan clamped')
local cx, cy = V.clampPan(10, 10, 1, w, 200, 200)
eq(cx, 10, 'pan inside kept x')
local ex = V.clampPan(5000, 0, 1, w, 200, 200)
eq(ex, w.w / 2 - 100, 'the map edge stops at the view edge')
eq(V.clampPan(50, 0, 0.3, w, 600, 500), 0, 'a small map stays centred')
eq(V.zoomStep(1, -1), 1, 'zoom floor')
eq(V.zoomStep(#V.ZOOMS, 1), #V.ZOOMS, 'zoom ceiling')
eq(V.zoomStep(2, 1), 3, 'zoom in')
local x, y = V.place(w, ix.byId[2], 0.5)
eq(x, math.floor((0 - w.cx) * 0.5 + 0.5), 'place x')
eq(y, math.floor((-90 - w.cy) * 0.5 + 0.5), 'place y')
local g = V.linkGeometry(w, ix.byId[1], ix.byId[4], 1)
eq(g.len, 90, 'link length')
eq(g.angle, 0, 'link angle east')
local g2 = V.linkGeometry(w, ix.byId[1], ix.byId[2], 1)
eq(math.floor(g2.angle + 0.5), -90, 'link angle north')
local tx, ty = V.panTo(w, ix.byId[1], 1)
local sx, sy = V.place(w, ix.byId[1], 1)
eq(tx, -sx, 'pan to x')
eq(ty, -sy, 'pan to y')

-- text
eq(V.kindLine(ix.byId[5]), 'Notable, 2 points', 'kind line')
eq(V.kindLine(ix.byId[2]), 'Node, 1 point', 'kind line small')
ok(V.tooltip(ix.byId[6], 'alloc'):find('Allocated'), 'tooltip allocated')
ok(V.tooltip(ix.byId[2], 'avail'):find('%+3%% monster packs'), 'tooltip lines')
eq(V.short(250000), '250k', 'short k')
eq(V.short(1500000), '1.5M', 'short M')
eq(V.short(2000000), '2M', 'short whole M')
eq(V.short(900), '900', 'short small')
eq(V.pointsLine(st), '4', 'points')
eq(V.earnedLine(st), 'Earned 6 / 10, spent 2', 'earned')
local rg, ro = V.refundLabels(st)
eq(rg, 'Refund 250k', 'refund gold label')
eq(ro, 'Refund 1 orb', 'refund orb label')
ok(V.reasonText('points'):find('Not enough'), 'reason text')

-- grid
local rows = V.gridRows(tree, d)
eq(#rows, 2 + 2 + 1, 'two themes, flawless, swift, omens')
eq(rows[1].label, 'Abyss', 'short theme name')
eq(rows[1].color, '#9a6ae8', 'branch colour')
eq(#rows[1].cells, 3, 'tiers')
ok(rows[1].cells[1].done and not rows[1].cells[2].done, 'cell done')
ok(rows[3].cells[1].done, 'flawless 1 done')
ok(rows[4].cells[1].tip:find('5:00'), 'swift time in the tip (an older server: one time)')
-- per-tier Swift times (they grow with the rift's map size and tier); a missing tier falls back to grid.swift
eq(V.swiftSeconds(tree.grid, 2), 300, 'swift seconds: one time')
tree.grid.swiftTiers = { 315, 285.0 }
rows = V.gridRows(tree, d)
ok(rows[4].cells[1].tip:find('sealed within 5:15', 1, true), 'tier 1: its own time')
ok(rows[4].cells[2].tip:find('sealed within 4:45', 1, true), 'tier 2: its own time')
ok(rows[4].cells[3].tip:find('sealed within 5:00', 1, true), 'tier 3: no own time, the one time')
eq(V.swiftSeconds(tree.grid, 2), 285, 'swift seconds: whole seconds')
eq(V.swiftSeconds(nil, 1), 0, 'swift seconds: no grid')
tree.grid.swiftTiers = nil
rows = V.gridRows(tree, d)
ok(rows[5].cells[1].done and rows[5].cells[1].name == 'Stormcall', 'omen done')
local dn, tn = V.gridCount(rows)
eq(dn, 3, 'grid done')
eq(tn, 2 * 3 + 3 + 3 + 1, 'grid total')
eq(#V.gridRows(nil, {}), 0, 'no tree')

-- the real tree of the server, when the repository is there: every glyph has a cell, every node a frame
local ok1, cfgOrErr = pcall(dofile, dir .. '../../../../server/data/scripts/chaos/atlas_config.lua')
if ok1 then
  local rcfg = dofile(dir .. '../../../../server/data/scripts/chaos/rift_config.lua')
  dofile(dir .. '../../../../server/data/scripts/chaos/atlas_core.lua')
  dofile(dir .. '../../../../server/data/scripts/chaos/rift_core.lua') -- the Swift times come from the rift model
  local real = ChaosAtlasCore.treePayload(cfgOrErr, rcfg)
  local rix = V.index(real)
  eq(#rix.list, #cfgOrErr.nodes, 'real tree indexed')
  local known = {}
  for _, gl in ipairs(V.GLYPHS) do known[gl] = true end
  for _, n in ipairs(rix.list) do
    if n.k ~= 'start' then
      ok(known[V.glyphOf(rix, n)], 'glyph has a cell: ' .. tostring(V.glyphOf(rix, n)) .. ' (node ' .. n.i .. ')')
      ok(V.frame(n.k, 'avail', V.nodeSize(n.k, 0.5)) ~= nil, 'frame for ' .. n.k)
    end
  end
  for _, b in ipairs(real.branches) do
    ok(rix.setOf[b.th] ~= nil, 'branch sheet ' .. b.k)
  end
  local rr = V.gridRows(real, {})
  eq(#rr, 4 + 2 + 1, 'real grid rows')
  local _, total = V.gridCount(rr)
  eq(total, 93, 'real grid cells')
  -- the Swift row shows the server's time of each tier, and it grows from the small maps to the big ones
  local sw = rr[4 + 2]
  eq(sw.kind, 'swift', 'real swift row')
  for t = 1, 15 do
    local secs = real.grid.swiftTiers[t]
    ok(sw.cells[t].tip:find(string.format('sealed within %d:%02d', math.floor(secs / 60), secs % 60), 1, true),
      'real swift tip tier ' .. t)
  end
  ok(real.grid.swiftTiers[15] > real.grid.swiftTiers[1], 'tier 15 gets more time than tier 1')
end

-- the Waystone Atlas: the grid comes as rows, each cell at its tier's column
local wtree = { grid = { tiers = 15, rows = {
  { label = 'Map I', color = '#d6c9ae', cells = { { k = 'm1.1', n = 'Drowned Grotto, Tier I', c = 1, p = 1, co = '#7fc86a' },
    { k = 'm5.6', n = 'Thornfield, Tier VI', c = 6, p = 1, co = '#e8b84a' } } },
  { label = 'Rare', color = '#f6cf72', cells = { { k = 'r1', n = 'Rare, Tier I', c = 1, p = 1 } } } } } }
local wr = V.gridRows(wtree, { ['m5.6'] = true })
eq(#wr, 2, 'waystone rows')
eq(wr[1].cells[2].col, 6, 'cell column')
eq(wr[1].cells[2].color, '#e8b84a', 'cell band colour')
ok(wr[1].cells[2].done and not wr[1].cells[1].done, 'waystone cell done')
ok(wr[1].cells[2].tip:find('Thornfield, Tier VI: done (+1)', 1, true), 'waystone tip')
eq(select(2, V.gridCount(wr)), 3, 'waystone grid total')

local okW = pcall(dofile, dir .. '../../../../server/data/scripts/chaos/waystone_atlas_config.lua')
if okW then
  local wcfg = dofile(dir .. '../../../../server/data/scripts/chaos/waystone_atlas_config.lua')
  local tcfg = dofile(dir .. '../../../../server/data/scripts/chaos/waystone_tiers_config.lua')
  local S = dir .. '../../../../server/data/scripts/chaos/'
  if not (ChaosAtlasCore and ChaosAtlasCore.canAllocate) then dofile(S .. 'atlas_core.lua') end
  local WC = dofile(S .. 'waystone_atlas_core.lua')
  local real = WC.treePayload(wcfg, tcfg)
  local wix = V.index(real)
  eq(#wix.list, 81, 'waystone tree indexed')
  local known = {}
  for _, gl in ipairs(V.GLYPHS) do known[gl] = true end
  for _, n in ipairs(wix.list) do
    if n.k ~= 'start' then
      ok(known[V.glyphOf(wix, n)] ~= nil, 'waystone glyph ' .. tostring(n.g) .. ' of ' .. n.n)
    end
  end
  for _, b in ipairs(real.branches) do
    ok(wix.setOf[b.th] ~= nil, 'waystone branch sheet ' .. b.k)
  end
  local rr = V.gridRows(real, {})
  eq(#rr, 5, 'real waystone rows')
  eq(select(2, V.gridCount(rr)), 75, 'real waystone cells')
  for _, r in ipairs(rr) do
    for _, c in ipairs(r.cells) do
      ok(c.col >= 1 and c.col <= 15, 'column of ' .. c.key)
    end
  end
end

print(string.format('riftatlasview_test: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
