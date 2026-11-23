-- Run from the repo root: luajit client/overlay/modules/game_chaosguard/integrity_test.lua (and lua5.3)
-- The module digests and the known-tool messages of the bot detection (integrity.lua; the Python twin client/tools/gen_module_hashes.py
-- makes the official list with the same rule, client/tools/gen_module_hashes_test.py holds both to one vector).
dofile('client/overlay/modules/game_chaosguard/integrity.lua')
local n = 0
local function eq(a, b, m)
  n = n + 1
  if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end
end

-- ---------------------------------------------------------------- which files count and their key
local k, rest = Integrity.split('/modules/game_market/market.lua')
eq(k, 'game_market', 'a module file: the folder name'); eq(rest, 'market.lua', 'the path inside the module')
k, rest = Integrity.split('/mods/game_helper/ui/main.otui')
eq(k, 'mods/game_helper', 'a mods file: the key has mods/ before it'); eq(rest, 'ui/main.otui', 'a deeper path')
eq(Integrity.split('/modules/game_market/icon.png'), nil, 'a picture is no code')
eq(Integrity.split('/modules/loose.lua'), nil, 'a file directly in modules/ has no module')
eq(Integrity.split('/data/things/1098/Tibia.dat'), nil, 'a data file is not a module')
eq(Integrity.split('/other/x/y.lua'), nil, 'another root')
eq(Integrity.split(nil), nil, 'no path')
eq(Integrity.split('/modules/game_a/Z.LUA') ~= nil, true, 'extensions in any case')

-- ---------------------------------------------------------------- the digest rule, with a stand-in for SHA-256
-- the stand-in keeps the text, so the test can read exactly what is hashed
local function sha(text) return 'H<' .. text .. '>' end
local files = {
  '/modules/game_b/b2.lua', '/modules/game_b/b1.lua', '/modules/game_a/a.otui', '/modules/game_a/icon.png',
  '/mods/game_helper/x.json', '/data/x.lua',
}
local hashes = { ['/modules/game_b/b2.lua'] = 'BBBB2', ['/modules/game_b/b1.lua'] = 'ABCD1', ['/modules/game_a/a.otui'] = 'AAAA',
  ['/mods/game_helper/x.json'] = 'eeee' }
local d = Integrity.digests(files, function(p) return hashes[p] end, sha)
eq(d.game_a, 'H<a.otui:aaaa\n>', 'hashes are lower case, one line a file')
eq(d.game_b, 'H<b1.lua:abcd1\nb2.lua:bbbb2\n>', 'files sorted by path')
eq(d['mods/game_helper'], 'H<x.json:eeee\n>', 'a mods module')
local count = 0
for _ in pairs(d) do count = count + 1 end
eq(count, 3, 'the picture and the data file add nothing')
-- a file that cannot be read is left out, not hashed as empty
hashes['/modules/game_b/b2.lua'] = nil
eq(Integrity.digests(files, function(p) return hashes[p] end, sha).game_b, 'H<b1.lua:abcd1\n>', 'an unreadable file is skipped')
-- the order the files arrive in does not matter
local rev = {}
for i = #files, 1, -1 do rev[#rev + 1] = files[i] end
hashes['/modules/game_b/b2.lua'] = 'BBBB2'
eq(Integrity.digests(rev, function(p) return hashes[p] end, sha).game_b, d.game_b, 'order independent')

-- ---------------------------------------------------------------- the messages
local big = {}
for i = 1, 130 do big[string.format('game_m%03d', i)] = 'd' .. i end
big[('x'):rep(70)] = 'too long a key'
local chunks = Integrity.chunks(big, 7)
eq(#chunks, 3, '130 entries in chunks of 60'); eq(chunks[1].i, 1, 'chunk number'); eq(chunks[3].i, 3, 'last chunk'); eq(chunks[2].n, 3, 'the count')
eq(chunks[1].b, 7, 'the build'); eq(#chunks[1].m, 60, 'a full chunk'); eq(#chunks[3].m, 10, 'the rest')
eq(chunks[1].m[1][1], 'game_m001', 'sorted by key'); eq(chunks[1].m[1][2], 'd1', 'key and digest')
local total = 0
for _, c in ipairs(chunks) do
  for _, e in ipairs(c.m) do
    total = total + 1
    eq(#e[1] <= 64, true, 'no key over 64 characters')
  end
end
eq(total, 130, 'the long key was dropped')
eq(#Integrity.chunks({}, 7), 1, 'no module still sends one (empty) chunk'); eq(#Integrity.chunks({}, 7)[1].m, 0, 'empty')
local msg = Integrity.integrityMessage(chunks[1])
eq(msg.action, 'integrity', 'action'); eq(msg.data, chunks[1], 'data')

-- ---------------------------------------------------------------- known tools
eq(Integrity.toolSpec({ { 'cave1', '0123456789ABCDEF' }, { 'rumo', 'fedcba9876543210' } }), 'cave1:0123456789abcdef,rumo:fedcba9876543210', 'the spec')
eq(Integrity.toolSpec({ { 'ab', '0123456789abcdef' }, { 'good', 'short' }, { 'bad code', '0123456789abcdef' }, { 5, 6 }, 'x' }), '', 'bad entries are dropped')
eq(Integrity.toolSpec(nil), '', 'no list'); eq(Integrity.toolSpec('text'), '', 'not a list')
local many = {}
for i = 1, 300 do many[i] = { 'tool' .. i, '0123456789abcdef' } end
local _, commas = Integrity.toolSpec(many):gsub(',', '')
eq(commas, 199, 'at most 200 entries')
local codes = Integrity.toolCodes('rumo,cave1,cave1,x,bad code,,toolverylongcodenamehere')
eq(#codes, 2, 'only valid, distinct codes'); eq(codes[1], 'cave1', 'sorted'); eq(codes[2], 'rumo', 'second')
eq(#Integrity.toolCodes(''), 0, 'nothing found'); eq(#Integrity.toolCodes(nil), 0, 'no answer'); eq(#Integrity.toolCodes(5), 0, 'not a string')
local ten = {}
for i = 1, 12 do ten[i] = 'code' .. string.char(96 + i) end
eq(#Integrity.toolCodes(table.concat(ten, ',')), 8, 'at most 8 codes')
local tm = Integrity.toolMessage({ 'cave1' })
eq(tm.action, 'tools', 'tools action'); eq(tm.data.c[1], 'cave1', 'the codes')
print('integrity_test: ' .. n .. ' checks ok')
