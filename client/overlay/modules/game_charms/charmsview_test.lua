-- luajit charmsview_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'charmsview.lua')
local V = CharmsView
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end
local function has(text, part, m) n = n + 1 if not tostring(text):find(part, 1, true) then error((m or '') .. ': ' .. tostring(text), 2) end end

-- a 5x4 grid: base cells open (columns 1-3 of rows 1-2) and the level 200 cells (4-5 of rows 1-2)
local cells = {}
for y = 1, 4 do
  for x = 1, 5 do
    local open = y <= 2
    cells[#cells + 1] = { x = x, y = y, open = open or nil, why = not open and 'Reach level 400' or nil }
  end
end
local s = {
  cols = 5, rows = 4, cells = cells, max = 20, shards = 7, level = 250,
  placed = {
    { id = 11, x = 1, y = 1, w = 2, h = 2, name = 'Radiant Grand Charm', rarity = 'Radiant', ilvl = 100, color = '#f2c94c',
      mods = { { k = 'dmg_undead', v = 9, t = 'Damage to Undead +9%' }, { k = 'goldfind', v = 6, t = 'Gold Find +6%' } },
      icon = 'dmg_undead', active = true },
    { id = 12, x = 4, y = 1, w = 1, h = 2, name = "Gravewarden's Seal", rarity = 'Unique', ilvl = 80, unique = 'gravewarden',
      mods = { { k = 'dmg_undead', v = 6, t = 'Damage to Undead +6%' } }, signature = 'Last Ember: ...', icon = 'gravewarden', active = false },
  },
  bag = { { ref = 's3.0', sid = 32303, iid = '77', w = 2, h = 1, name = 'Faint Wide Charm', rarity = 'Faint', ilvl = 40,
    mods = { { k = 'orbfind', v = 2, t = 'Orb Find +2%' } }, icon = 'orbfind', salvage = 4, reforge = 12 } },
  groups = { { text = 'Open from the start', open = true, cells = 6 }, { text = 'Reach level 400', open = false, cells = 3 } },
  totals = { { k = 'dmg_undead', v = 15, cap = 15, t = 'Damage to Undead +15%' }, { k = 'goldfind', v = 6, cap = 10, t = 'Gold Find +6%' } }
}

-- geometry
local step = V.CELL + V.GAP
eq(select(1, V.cellAt(s, 0, 0)), 1, 'cell 1')
eq(select(2, V.cellAt(s, step * 2 + 5, step + 1)), 2, 'cell row 2')
eq(V.cellAt(s, step * 5 + 1, 0), nil, 'outside right')
eq(V.cellAt(s, -1, 0), nil, 'outside left')
local r = V.rect(2, 3, 2, 1)
eq(r.x, step, 'rect x'); eq(r.y, step * 2, 'rect y'); eq(r.width, step * 2 - V.GAP, 'rect w'); eq(r.height, V.CELL, 'rect h')
eq(#V.footprint(2, 2, 1, 1), 4, 'footprint')
local ax, ay = V.anchor(s, step * 3 + 3, step + 3, 2, 2)
eq(ax, 3, 'anchor centres a 2x2 on the mouse x'); eq(ay, 1, 'anchor y')

-- rules
local ok, why = V.check(s, 1, 1, 3, 1)
eq(ok, true, 'free cell')
ok, why = V.check(s, 2, 1, 1, 1)
eq(ok, false, 'overlap'); has(why, 'in the way', 'overlap text')
ok, why = V.check(s, 1, 1, 3, 3)
has(why, 'locked', 'locked'); has(why, 'level 400', 'locked reason')
ok, why = V.check(s, 2, 1, 5, 2)
has(why, 'inside the grid', 'edge')
eq((V.check(s, 1, 2, 4, 1, 12)), true, 'moving onto its own cells')
eq((V.check(s, 1, 2, 3, 1, 12)), true, 'moving next to it')

-- preview and drops
local p = V.preview(s, { kind = 'bag', w = 2, h = 1, ref = 's3.0' }, step * 2 + 2, step + 2)
eq(p.x, 2, 'preview x'); eq(p.y, 2, 'preview y'); eq(p.ok, false, 'preview over the grand charm'); eq(#p.cells, 2, 'preview cells')
p = V.preview(s, { kind = 'bag', w = 2, h = 1 }, step * 4 + 40, step * 3 + 2)
eq(#p.cells, 1, 'preview clipped to the grid')
local a = V.dropAction(s, { kind = 'bag', ref = 's3.0', sid = 32303, iid = '77', w = 2, h = 1 }, 'grid', step * 2 + 2, 2)
eq(a and a.action, nil, 'drop on the occupied 3,1 + 4,1')
a = V.dropAction(s, { kind = 'bag', ref = 's3.0', sid = 32303, iid = '77', w = 1, h = 1 }, 'grid', step * 2 + 2, 2)
eq(a.action, 'place', 'place'); eq(a.data.x, 3, 'place x'); eq(a.data.ref, 's3.0', 'place ref'); eq(a.data.iid, '77', 'place iid')
a = V.dropAction(s, { kind = 'placed', id = 12, w = 1, h = 2, x = 4, y = 1 }, 'grid', step * 4 + 2, step + 2)
eq(a.action, 'move', 'move'); eq(a.data.x, 5, 'move x'); eq(a.data.y, 1, 'move y (a 1x2 grabbed at its lower half)')
eq(V.dropAction(s, { kind = 'placed', id = 12, w = 1, h = 2, x = 4, y = 1 }, 'grid', step * 3 + 2, step + 2), nil, 'same place: nothing')
a = V.dropAction(s, { kind = 'placed', id = 12 }, 'bag')
eq(a.action, 'take', 'take'); eq(a.data.id, 12, 'take id')
eq(V.dropAction(s, { kind = 'bag' }, 'bag'), nil, 'bag to bag')
local none, reason = V.dropAction(s, { kind = 'bag', w = 1, h = 1 }, 'grid', 2, step * 3 + 2)
eq(none, nil, 'locked drop'); has(reason, 'locked', 'locked drop reason')

-- texts
local t = V.tooltip(s.placed[1], true)
has(t, 'Radiant Grand Charm', 'tip name'); has(t, 'item level 100, 2x2', 'tip line'); has(t, 'Gold Find +6%', 'tip mod')
has(t, 'take it out', 'tip placed hint')
t = V.tooltip(s.placed[2], true)
has(t, 'Last Ember', 'tip signature'); has(t, 'Inactive', 'tip inactive')
t = V.tooltip(s.bag[1], false)
has(t, 'salvage: 4 shards', 'tip salvage'); has(t, 'reforge: 12 shards', 'tip reforge'); has(t, 'onto the grid', 'tip bag hint')
local lines = V.totalsLines(s)
has(lines[1].text, '(cap)', 'capped total'); eq(lines[1].color, V.COLORS.warn, 'capped colour')
eq(lines[2].text, 'Gold Find +6%', 'total line')
eq(V.totalsLines({}).n, nil, 'empty totals'); has(V.totalsLines({})[1].text, 'No charm', 'empty text')
local ul = V.unlockLines(s)
has(ul[1].text, '[open]', 'open group'); has(ul[2].text, '[locked] Reach level 400: 3 cells', 'locked group')
has(V.header(s), '10 of 20 cells open', 'header cells'); has(V.header(s), '2 charms placed', 'header placed')
has(V.header(s), '7 charm shards', 'header shards')
eq(V.iconPath(nil), '/images/game/charms/charm', 'default icon')
eq(V.bagEntry(s, 's3.0').sid, 32303, 'bag entry'); eq(V.placedEntry(s, 12).unique, 'gravewarden', 'placed entry')

print('charmsview_test: ' .. n .. ' checks passed')
