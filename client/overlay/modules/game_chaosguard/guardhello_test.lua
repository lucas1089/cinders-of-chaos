-- Run from the repository root: luajit client/overlay/modules/game_chaosguard/guardhello_test.lua (and lua5.3)
dofile('client/overlay/modules/game_chaosguard/guardhello.lua')
local n = 0
local function eq(a, b, m)
  n = n + 1
  if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end
end
eq(GuardHello.isOurs('game_market'), true, 'game_ module')
eq(GuardHello.isOurs('client_chaos_theme'), true, 'client_chaos module')
eq(GuardHello.isOurs('client_entergame'), false, 'stock client module')
eq(GuardHello.isOurs('zz_bot'), false, 'other')
eq(GuardHello.isOurs(nil), false, 'nil')
local mods = {
  { name = 'game_market', loaded = true }, { name = 'game_rift', loaded = false },
  { name = 'client_chaos_login', loaded = true }, { name = 'client_options', loaded = true },
}
eq(GuardHello.count(mods), 2, 'loaded ones of ours')
eq(GuardHello.count(nil), 0, 'no list')
local p = GuardHello.payload(7, mods)
eq(p.action, 'hello', 'action')
eq(p.data.build, 7, 'build')
eq(p.data.modules, 2, 'modules')
eq(GuardHello.payload(nil, {}).data.build, 0, 'old exe without getChaosClientBuild')
print('guardhello_test: ' .. n .. ' checks OK')
