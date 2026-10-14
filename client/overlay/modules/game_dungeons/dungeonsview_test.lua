-- luajit dungeonsview_test.lua && lua5.3 dungeonsview_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'dungeonsview.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local V = DungeonsView

-- no `health` (a base dungeon or an older server): the texts of dungeons.otui
local f = io.open(dir .. 'dungeons.otui', 'r')
local otui = f:read('*a')
f:close()
local panels = {}
for t in otui:gmatch("DifficultyInfo%s+!text:%s*tr%('([^']*)'%)") do
  panels[#panels + 1] = (t:gsub('\\n', '\n'))
end
eq(#panels, 6, 'six panels in dungeons.otui')
for d = 1, 6 do
  eq(V.panelText(d, nil), panels[d], 'default text ' .. d)
  eq(V.DEFAULT[d], panels[d], 'default key ' .. d)
end
eq(V.panelText(6, nil):match('1300%%') ~= nil, true, 'old table at 6')

-- the Vault / generated dungeons: their own curves (server dungeons_difficulty.lua D.healthCurves)
local own = { monsters = { 100, 105, 110, 115, 120, 125 }, boss = { 100, 125, 150, 175, 200, 225 } }
eq(V.panelText(1, own), 'Monster Health 100%\nBoss Health 100%\nMonster Damage 100%', 'own curve 1')
eq(V.panelText(2, own), 'Monster Health 105%\nBoss Health 125%\nMonster Damage 130%\nBonus XP +75%\nGold Drop +75%',
  'own curve 2')
eq(V.panelText(6, own),
  'Monster Health 125%\nBoss Health 225%\nMonster Damage 600%\nBonus XP +400%\nGold Drop +400%\nLoot Chance +60%',
  'own curve 6')
eq(V.panelText(6, own):find('1300', 1, true), nil, 'no 1300% with own curves')
eq(V.panelText(9, own), V.panelText(6, own), 'difficulty clamped')
eq(V.panelText(0, own), V.panelText(1, own), 'difficulty clamped up')

-- bad payloads fall back to the table, never an error
eq(V.panelText(3, 'x'), panels[3], 'string health')
eq(V.panelText(3, {}), panels[3], 'empty health')
eq(V.panelText(3, { monsters = {}, boss = {} }), panels[3], 'empty curves')
eq(V.panelText(3, { monsters = { 1, 2, 'a' }, boss = own.boss }), panels[3], 'not a number')
eq(V.panelText(3, { monsters = { 1, 2, 0 / 0 }, boss = own.boss }), panels[3], 'NaN')
eq(V.panelText(3, { monsters = { 1, 2, 1e300 }, boss = own.boss }), panels[3], 'huge')
eq(V.panelText(3, { monsters = own.monsters, boss = 5 }), panels[3], 'boss not a table')
eq(V.panelText(2.7, own), V.panelText(2, own), 'fractional difficulty')
eq(V.panelText('x', own), V.panelText(1, own), 'difficulty not a number')
local m, b = V.healthOf(own, 4)
eq(m, 115, 'healthOf monsters')
eq(b, 175, 'healthOf boss')

-- banners: own art for the Vault and 6-9, the old names, the fallback
local present = {}
for _, n in pairs(V.BANNERS) do present['/images/dungeons/' .. n .. '.png'] = true end
local function exists(p) return present[p] == true end
eq(V.bannerFor('The Pyre Throne', exists), '/images/dungeons/PyreThrone', 'pyre throne')
eq(V.bannerFor('The Hollow Vault', exists), '/images/dungeons/HollowVault', 'vault')
eq(V.bannerFor('The Marrow Crypts', exists), '/images/dungeons/MarrowCrypts', 'marrow')
eq(V.bannerFor('The Iron Crucible', exists), '/images/dungeons/IronCrucible', 'crucible')
eq(V.bannerFor('The Fallen Sanctum', exists), '/images/dungeons/FallenSanctum', 'sanctum')
eq(V.bannerFor('Rootmaw', exists), '/images/dungeons/Rootkraken', 'rootmaw')
eq(V.bannerFor('Something New', exists), '/images/dungeons/Underworld', 'fallback')
eq(V.bannerFor(nil, exists), '/images/dungeons/Underworld', 'nil title')
-- every banner the table names is in the overlay
local images = dir .. '../../data/images/dungeons/'
for title, n in pairs(V.BANNERS) do
  local h = io.open(images .. n .. '.png', 'rb')
  eq(h ~= nil, true, 'banner file for ' .. title)
  if h then h:close() end
end

if fails > 0 then print(fails .. ' failure(s)'); os.exit(1) end
print('dungeonsview tests passed')
