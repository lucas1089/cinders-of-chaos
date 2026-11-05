-- luajit layoutmode_test.lua && lua5.3 layoutmode_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'layoutmode_logic.lua')
dofile(dir .. '../client_chaos_settings/settingslist.lua')
local M = ChaosLayoutMode
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- a new character gets the action bar layout, a known one keeps the classic layout, a pick wins, phones are classic
eq(M.resolve(nil, 'Vexa', false, false), 'action', 'new character: action')
eq(M.resolve(nil, 'Vexa', true, false), 'classic', 'known character keeps classic')
eq(M.resolve({ Vexa = { mode = 'action' } }, 'Vexa', true, false), 'action', 'a pick wins over known')
eq(M.resolve({ Vexa = { mode = 'classic' } }, 'Vexa', false, false), 'classic', 'a classic pick on a new character')
eq(M.resolve({ Vexa = { mode = 'junk' } }, 'Vexa', false, false), 'action', 'a bad mode is no pick')
eq(M.resolve({ Vexa = { mode = 'action' } }, 'Vexa', false, true), 'classic', 'phones are always classic')
eq(M.resolve({ Other = { mode = 'classic' } }, 'Vexa', false, false), 'action', 'another character pick does not count')
eq(M.resolve(nil, nil, false, false), 'action', 'no name: default')

-- store keeps the other characters and ignores a bad mode
local node = M.store(nil, 'A', 'action')
node = M.store(node, 'B', 'classic')
eq(node.A.mode, 'action', 'stored A')
eq(node.B.mode, 'classic', 'stored B')
eq(M.store(node, 'A', 'wat').A.mode, 'action', 'bad mode leaves it')
eq(M.store(node, nil, 'action'), node, 'no name leaves it')

-- survives g_settings (keys and values come back as the engine gives them)
local back = ChaosSettings.roundTrip(node)
eq(M.resolve(back, 'B', false, false), 'classic', 'B after a round trip')
eq(M.resolve(back, 'A', true, false), 'action', 'A after a round trip')

-- known: an entry of any older layout node
local nodes = { chaos_chatpanel = { Old = { width = 700 } }, chaos_view = { Zoomer = { zoom = 3 } } }
local function read(n) return nodes[n] end
eq(M.isKnown(read, 'Old'), true, 'chat panel entry is known')
eq(M.isKnown(read, 'Zoomer'), true, 'view entry is known')
eq(M.isKnown(read, 'Fresh'), false, 'no entry: new')
eq(M.isKnown(read, nil), false, 'no name')
eq(M.isKnown(function() return nil end, 'Old'), false, 'empty settings')
eq(M.isAction('action'), true, 'isAction')
eq(M.isAction('classic'), false, 'isAction classic')

if fails == 0 then print('layoutmode_test: ok') end
os.exit(fails == 0 and 0 or 1)
