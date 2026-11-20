-- luajit combologic_test.lua && lua5.3 combologic_test.lua (CI runs it from the repo root, which also lets it hold the ids, kinds and
-- pt-BR names to the server's spell_combos_config.lua and client_chaos_locale/pt_br.lua)
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local C = dofile(here .. 'combologic.lua')
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

eq(ChaosComboLogic, C, 'global')

-- the message
local c = C.clean({ id = 'steam_burst', n = 'Steam Burst', x = 1000, y = 1002, z = 7 })
eq(c.id, 'steam_burst', 'id') eq(c.name, 'Steam Burst', 'name') eq(c.kind, 'reaction', 'kind') eq(c.color, 143, 'colour')
eq(c.pos.x, 1000, 'x') eq(c.pos.y, 1002, 'y') eq(c.pos.z, 7, 'z')
eq(c.sound, '/modules/game_spellranks/sounds/combo_a.ogg', 'a reaction plays the high chime')
eq(C.clean({ id = 'meat_grinder', x = 5, y = 6, z = 7 }).sound, '/modules/game_spellranks/sounds/combo_b.ogg', 'a signature combo plays the low chime')
eq(C.clean({ id = 'meat_grinder', x = 5, y = 6, z = 7 }).name, 'Meat Grinder', 'no name in the message: made from the id')
eq(C.clean({ id = 'meat_grinder', n = 7, x = 5, y = 6, z = 7 }).name, 'Meat Grinder', 'a name that is no text: made from the id')
local unknown = C.clean({ id = 'new_combo', n = 'New Combo', x = 5, y = 6, z = 7 })
eq(unknown.kind, 'signature', 'an unknown combo is a signature') eq(unknown.color, C.DEFAULT_COLOR, 'and white')
eq(C.clean({ id = 'steam_burst', x = 5.9, y = '6', z = 7 }).pos.x, 5, 'a number is whole')
eq(C.clean({ id = 'steam_burst', x = 5, y = '6', z = 7 }).pos.y, 6, 'a number as text is read')

-- junk
eq(C.clean(nil), nil, 'nil') eq(C.clean('x'), nil, 'a string') eq(C.clean({}), nil, 'empty')
eq(C.clean({ id = 5, x = 1, y = 1, z = 7 }), nil, 'id not text')
eq(C.clean({ id = 'Steam Burst', x = 1, y = 1, z = 7 }), nil, 'id with a space or capitals')
eq(C.clean({ id = '', x = 1, y = 1, z = 7 }), nil, 'empty id')
eq(C.clean({ id = string.rep('a', 41), x = 1, y = 1, z = 7 }), nil, 'a very long id')
eq(C.clean({ id = 'steam_burst', x = 1, y = 1 }), nil, 'no floor')
eq(C.clean({ id = 'steam_burst', x = 1, y = 1, z = 16 }), nil, 'floor 16')
eq(C.clean({ id = 'steam_burst', x = -1, y = 1, z = 7 }), nil, 'negative x')
eq(C.clean({ id = 'steam_burst', x = 0 / 0, y = 1, z = 7 }), nil, 'nan x')
eq(C.clean({ id = 'steam_burst', x = math.huge, y = 1, z = 7 }), nil, 'huge x')
eq(C.clean({ id = 'steam_burst', n = string.rep('x', 41), x = 1, y = 1, z = 7 }).name, 'Steam Burst', 'a long name is replaced')

-- the label text goes through the translator, and falls back to the English name
eq(C.labelText(c, function(s) return 'T:' .. s end), 'T:Steam Burst', 'translated')
eq(C.labelText(c, nil), 'Steam Burst', 'no translator')
eq(C.labelText(c, function() return nil end), 'Steam Burst', 'a translator that answers nothing')
eq(C.labelText(c, function() return '' end), 'Steam Burst', 'a translator that answers an empty text')

-- the flood gate
local gate = C.newGate()
eq(C.allow(gate, c, 1000), true, 'the first label shows')
eq(C.allow(gate, c, 1100), false, 'another within 200 ms: no')
local other = C.clean({ id = 'overload', x = 1000, y = 1002, z = 7 })
eq(C.allow(gate, other, 1250), true, 'another combo 250 ms later: yes')
eq(C.allow(gate, c, 1600), false, 'the same combo on the same tile within 800 ms: no')
eq(C.allow(gate, c, 1801), true, 'after 800 ms: yes')
local moved = C.clean({ id = 'steam_burst', x = 1001, y = 1002, z = 7 })
eq(C.allow(gate, moved, 2100), true, 'the same combo on another tile: yes')
for i = 1, 50 do C.allow(gate, C.clean({ id = 'steam_burst', x = i, y = 1, z = 7 }), 10000 + i * 1000) end
local count = 0
for _ in pairs(gate.seen) do count = count + 1 end
eq(count <= 2, true, 'old entries are forgotten')

-- run from the repo root: the ids, the kinds and the pt-BR names equal the server's rows and the locale file
local f = io.open('server/data/scripts/chaos/spell_combos_config.lua', 'r')
if f then
  f:close()
  local cfg = dofile('server/data/scripts/chaos/spell_combos_config.lua')
  local pt = io.open('client/overlay/modules/client_chaos_locale/pt_br.lua', 'rb'):read('*a')
  local rows = 0
  for _, row in ipairs(cfg.rows) do
    rows = rows + 1
    local mine = C.COMBOS[row.id]
    eq(mine ~= nil, true, row.id .. ' is known to the client')
    eq(mine.kind, row.kind == 'reaction' and 'reaction' or 'signature', row.id .. ' kind')
    eq(pt:find('["' .. row.name .. '"] = "' .. row.pt .. '"', 1, true) ~= nil, true, row.id .. ' has its pt-BR text')
  end
  local known = 0
  for _ in pairs(C.COMBOS) do known = known + 1 end
  eq(known, rows, 'the client knows exactly the rows of the server')
end

print('combologic_test: ' .. n .. ' checks OK')
