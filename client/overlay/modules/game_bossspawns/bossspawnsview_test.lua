-- luajit bossspawnsview_test.lua && lua5.3 bossspawnsview_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'bossspawnsview.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local V = BossSpawnsView

eq(V.left(100, 10, 15), 95, 'left')
eq(V.left(3, 10, 20), 0, 'left not negative')
eq(V.countdown(93784), '1d 2h', 'days')
eq(V.countdown(4980), '1h 23m', 'hours')
eq(V.countdown(125), '2m 05s', 'minutes')
eq(V.countdown(9), '9s', 'seconds')
eq(V.countdown(nil), '0s', 'nil')
eq(V.ago(30), 'just now', 'ago now')
eq(V.ago(720), '12m ago', 'ago minutes')
eq(V.ago(3 * 3600 + 5), '3h ago', 'ago hours')
eq(V.ago(2 * 86400), '2d ago', 'ago days')

local text, color = V.status({ st = 'alive' }, 0)
eq(text, 'Alive', 'alive')
eq(color, V.COLORS.alive, 'alive colour')
eq((V.status({ st = 'alive', alive = 3 }, 0)), 'Alive (3)', 'alive count')
eq((V.status({ st = 'respawn', ['in'] = 3600 }, 600)), 'Respawns in 50m 00s', 'respawn counts down')
eq((V.status({ st = 'respawn', ['in'] = 60 }, 61)), 'Respawn due', 'respawn over')
eq((V.status({ st = 'due' }, 0)), 'Respawn due', 'due')
eq((V.status({ st = 'scheduled', ['in'] = 7200 }, 0)), 'In 2h 00m', 'scheduled')
eq((V.status({ st = 'scheduled', ['in'] = 5 }, 10)), 'Starting', 'scheduled reached')
eq((V.status({ st = 'random' }, 0)), 'Random', 'random')
eq((V.status({ st = 'ondemand' }, 0)), 'On demand', 'on demand')
eq((V.status({ st = 'cooldown', ['in'] = 90 }, 0)), 'Your cooldown 1m 30s', 'cooldown')
eq((V.status({ st = 'cooldown', ['in'] = 90 }, 100)), 'Ready', 'cooldown over')
eq((V.status({ st = 'unknown' }, 0)), 'Not seen yet', 'unknown')
eq((V.status(nil, 0)), 'Not seen yet', 'nil row')

eq(V.statusSub({ st = 'scheduled', at = 'Wed 19:30', ago = 10 }, 0), 'Wed 19:30', 'far time first')
eq(V.statusSub({ st = 'random', ago = 600, by = 'Hero' }, 120), 'Slain 12m ago by Hero', 'last kill ages')
eq(V.statusSub({ st = 'ondemand', tx = 'Rift Key' }, 0), 'Rift Key', 'how')
eq(V.statusSub({ st = 'random', tx = 'a long rule text', sh = 'About every 1d' }, 0), 'About every 1d', 'short form first')
eq(V.statusSub({ st = 'alive' }, 0), '', 'nothing')
eq(V.levelText({ lv = 300 }), 'Level 300+', 'level')
eq(V.levelText({ lv = 150, party = 2 }), 'Level 150+, party of 2', 'party')
eq(V.levelText({}), '', 'no level')
eq(V.coords({ x = 1, y = 2, z = 3 }), '1, 2, 3', 'coords')
eq(V.coords(nil), '', 'no coords')
eq(V.where({ p = { x = 1, y = 2, z = 3 }, ln = 'x' }), '1, 2, 3', 'where: coords first')
eq(V.where({ ln = 'Portals at every temple' }), 'Portals at every temple', 'where: note')
eq(V.where(nil), '', 'where: nothing')
eq(V.tooltip({ n = 'Ferumbras', tx = 'Random raid', ago = 60, by = 'Hero', kills = 2, p = { x = 1, y = 2, z = 3 } }, 0),
  'Ferumbras\nRandom raid\nLast kill: 1m ago by Hero (2 kills)\nPosition: 1, 2, 3', 'tooltip')

local data = {
  cats = { { k = 'world', n = 'World Bosses' }, { k = 'raid', n = 'Raid Bosses' }, { k = 'empty', n = 'Nothing' } },
  rows = {
    { k = 'a', c = 'world', n = 'Kaelgor', st = 'alive' },
    { k = 'b', c = 'world', n = 'Skaldra', st = 'scheduled' },
    { k = 'c', c = 'raid', n = 'Ferumbras', loc = 'Liberty Bay', st = 'random' },
    { k = 'd', c = 'nope', n = 'Lost' },
  },
}
local groups = V.group(data)
eq(#groups, 2, 'empty category left out')
eq(groups[1].cat.k, 'world', 'server order')
eq(#groups[1].rows, 2, 'rows of a category')
eq(V.header(groups[1], false), '- World Bosses (2) - 1 alive', 'header')
eq(V.header(groups[2], true), '+ Raid Bosses (1)', 'collapsed header')
groups = V.group(data, 'liberty')
eq(#groups, 1, 'filter by place')
eq(groups[1].rows[1].n, 'Ferumbras', 'filtered row')
groups = V.group(data, 'SKAL')
eq(V.header(groups[1], false), '- World Bosses (1 of 2)', 'filtered header')
eq(#V.group(nil), 0, 'no data')

if fails > 0 then print(fails .. ' failure(s)') os.exit(1) end
print('bossspawnsview_test: OK')
