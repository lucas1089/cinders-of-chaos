-- luajit client/overlay/modules/game_chaosshaders/outfitshaderlist_test.lua (and lua5.3), from the repo root
dofile('client/overlay/modules/game_chaosshaders/outfitshaderlist.lua')
local L = OutfitShaderList

local n = 0
local function eq(a, b, m)
  n = n + 1
  if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end
end
local function read(path)
  local f = assert(io.open(path, 'rb'))
  local t = f:read('*a')
  f:close()
  return t
end

-- the server's list as the engine hands it to Lua: {id, name} pairs
local server = {
  { 21, 'chaos_void_flicker' }, { 11, 'red_energizer' }, { 19, 'chaos_ember_glow' },
  { 11, 'red_energizer' },                -- repeated
  { 0, 'zero_id' }, { 30, '' }, { 31 }, 'junk', { 'x', 'y' },
  { 40, string.rep('a', 65) },            -- too long
  { 99, 'some_new_shader' },              -- not in the table: a readable name
}
local e = L.entries(server)
eq(#e, 4, 'four valid shaders')
eq(e[1].label, 'Blood Pulse', 'sorted by label 1')
eq(e[2].label, 'Ember Glow', 'sorted by label 2')
eq(e[3].label, 'Some New Shader', 'sorted by label 3')
eq(e[4].label, 'Void Flicker', 'sorted by label 4')
eq(e[2].id, 19, 'id kept') eq(e[2].name, 'chaos_ember_glow', 'name kept')
eq(#L.entries(nil), 0, 'no list') eq(#L.entries({}), 0, 'empty list')
eq(#L.entries({ { id = 5, name = 'blue Dortmond' } }), 1, 'keyed entries too')
eq(L.entries({ { id = 5, name = 'blue Dortmond' } })[1].label, 'Azure Waves', 'a name with a space')
local many = {}
for i = 1, 300 do many[i] = { i, 's' .. i } end
eq(#L.entries(many), L.MAX, 'at most the packet count')

-- labels
eq(L.label('chaos_blood_pulse'), 'Heartblood', 'chaos label')
eq(L.label('chaos_unknown_thing'), 'Unknown Thing', 'chaos prefix dropped')
eq(L.label('yellow _energizer'), 'Golden Pulse', 'base name with a space')
eq(L.label(''), 'None', 'empty') eq(L.label(nil), 'None', 'nil')

-- what is sent back: only an owned shader, else none (the server would refuse the whole outfit change)
eq(L.outgoing(e, 'chaos_ember_glow'), 'chaos_ember_glow', 'owned is sent')
eq(L.outgoing(e, 'chaos_frost_rime'), '', 'not owned is dropped')
eq(L.outgoing(e, ''), '', 'none stays none')
eq(L.outgoing(e, nil), '', 'nil is none')
eq(L.outgoing({}, 'red_energizer'), '', 'nothing owned')
eq(L.text(e, 'red_energizer'), 'Blood Pulse', 'row text')
eq(L.text(e, 'chaos_frost_rime'), 'None', 'row text for a shader not owned')

-- the selection list: None first, then the owned ones; the search filters by label or name
local rows = L.rows(e)
eq(#rows, 5, 'none + 4') eq(rows[1].name, '', 'none first') eq(rows[1].label, 'None', 'none label')
eq(rows[2].name, 'red_energizer', 'then sorted')
rows = L.rows(e, '  void ')
eq(#rows, 1, 'search by label') eq(rows[1].name, 'chaos_void_flicker', 'found')
eq(#L.rows(e, 'ENERGIZER'), 1, 'search by name, any case')
eq(#L.rows(e, '%a'), 0, 'plain text search')
eq(#L.rows({}), 1, 'nothing owned: just None')

-- every label matches the server's names: the store (by shaders.xml id), the exclusives, the Chaos shaders
local shop = read('server/data/scripts/chaos/shop_config.lua')
local byId, storeCount = {}, 0
for _, v in pairs(L.LABELS) do
  eq(byId[v.id], nil, 'one label per id ' .. v.id)
  byId[v.id] = v.label
end
for id, name in shop:gmatch('{kind = "shader", id = (%d+), cost = %d+, name = "([^"]+)"') do
  eq(byId[tonumber(id)], name, 'store shader ' .. id)
  storeCount = storeCount + 1
end
eq(storeCount >= 16, true, 'store shaders read')
local function checkNamed(text, what)
  local c = 0
  for shader, name in text:gmatch('shader = "([%w_]+)"[^\n]*\n[^\n]-name = "([^"]+)"') do
    eq(L.LABELS[shader] and L.LABELS[shader].label, name, what .. ' ' .. shader)
    c = c + 1
  end
  return c
end
eq(checkNamed(read('server/data/scripts/chaos/exclusives_config.lua'), 'exclusive'), 2, 'exclusive shaders read')
eq(checkNamed(read('server/data/scripts/chaos/cosmetics_config.lua'), 'chaos shader'), 6, 'chaos shaders read')
eq(checkNamed(read('server/data/scripts/chaos/seasonpass_config.lua'), 'season pass shader'), 2, 'season pass shaders read')
for id, shader in read('server/data/scripts/chaos/seasonpass_config.lua'):gmatch('kind = "shader", id = (%d+), shader = "([%w_]+)"') do
  eq(L.LABELS[shader].id, tonumber(id), 'season pass shader id ' .. shader)
end
local ids = read('server/data/scripts/chaos/cosmetics_config.lua')
for id, shader in ids:gmatch('shaderId = (%d+), shader = "([%w_]+)"') do
  eq(L.LABELS[shader].id, tonumber(id), 'chaos shader id ' .. shader)
end

-- every labelled name is registered by game_chaosshaders (so it draws in the list and on the character)
local reg = read('client/overlay/modules/game_chaosshaders/chaosshaders.lua')
for name in pairs(L.LABELS) do
  local quoted = '"' .. name .. '"'
  eq(reg:find(quoted, 1, true) ~= nil, true, 'registered ' .. name)
end

-- the outfit window patch uses this module and lists the shaders
local patch = read('client/base-patches/0045-outfit-window-shaders.patch')
eq(patch:find('OutfitShaderList', 1, true) ~= nil, true, 'patch uses the list')
eq(patch:find('shaderCheck', 1, true) ~= nil, true, 'patch adds the Shader row')

print('outfitshaderlist_test: ' .. n .. ' checks OK')
