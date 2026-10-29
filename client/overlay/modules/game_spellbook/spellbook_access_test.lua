-- luajit spellbook_access_test.lua && lua5.3 spellbook_access_test.lua (from the repository root or this folder)
-- O329: what the client says a class can learn or cast is exactly what the server lets it cast, for all 21 classes.
-- Tester report (Beastmaster, level 750): the spell pickers listed Hail of Dawn, Twin Verdict, Final Verdict and Skewering
-- Line, and the server refused each cast ("not for your class"). Cause: the pickers (ChaosSpellCore.setupPicker,
-- pickerContext) and ChaosSpellFix.allowsVocation also accepted translateVocation's fold, which maps sibling classes onto
-- one id (Beastmaster, Ranger and Deadeye -> 7, the Warrior line -> 8, Mystic and Elementalist -> 5).
--
-- Server truth: server/data/spells/chaos/spells_chaos.xml (the Chaos spells, by vocation name) and
-- server/data/spells/stock_spells.csv (the stock attack and healing spells as the installed server has them, after the 15-spell
-- cap). The vocation ids are those of server/data/XML/chaos_vocations*.xml. The fold is the real translateVocation of
-- client/base-patches/0016-chaos-vocation-ids.patch (read from the patch). Every path that decides "this class may have this
-- spell" runs with the fold: ChaosSpellCore.vocationOk / status / filterMatches (the Spellbook window and the pickers, with the
-- picker context of a player), ChaosSpellFix.allowsVocation (action bar, hotkeys, Auto setup) and ChaosHelperSpells.classOk (the
-- helper's pickers).
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local root = here .. '../../../../'
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

local function read(path)
  local f = assert(io.open(path, 'rb'), 'cannot read ' .. path)
  local s = f:read('*a')
  f:close()
  return s
end

local Core = dofile(here .. 'spellbook_core.lua')
dofile(here .. '../game_chaosspells/spellfix.lua')
dofile(here .. '../game_chaosspells/spelldata.lua')
dofile(here .. '../game_helper/helper_spells.lua')

-- ---------------------------------------------------------------- the fold: translateVocation(id) of base patch 0016
local patch = read(root .. 'client/base-patches/0016-chaos-vocation-ids.patch')
local newSide = {}
for line in (patch .. '\n'):gmatch('([^\n]*)\n') do
  local c = line:sub(1, 1)
  if c == ' ' or c == '+' then newSide[#newSide + 1] = line:sub(2) end
end
local body = table.concat(newSide, '\n')
local src = body:match('function translateVocation%(id%)\n.-\nend\n')
assert(src, 'translateVocation(id) not found in base patch 0016')
local loader = loadstring or load
local fold = assert(loader(src .. '\nreturn translateVocation', 'translateVocation'))()
eq(fold(15), fold(7), 'the fold maps the Beastmaster and the Deadeye to one id (the test is meaningful)')
eq(fold(3), fold(7), 'and the Ranger')

-- ---------------------------------------------------------------- vocation ids and the server's spell lists
local VOC = {}
local classCount = 0
local dir = root .. 'server/data/XML/'
for _, name in ipairs({ 'chaos_vocations.xml', 'chaos_vocations_monk.xml', 'chaos_vocations_necro.xml', 'chaos_vocations_templar.xml' }) do
  local text = read(dir .. name):gsub('<!%-%-.-%-%->', '')
  for id, rest in text:gmatch('<vocation%s+id="(%d+)"([^>]*)>') do
    local vname = rest:match('name="([^"]+)"')
    if vname then
      VOC[vname] = tonumber(id)
      classCount = classCount + 1
    end
  end
end
eq(classCount, 21, '21 classes in the vocation tables')

local entries = {} -- {name, words, level, vocations = {ids}, chaos = bool, id}
local function ids(names)
  local out = {}
  for _, v in ipairs(names) do
    out[#out + 1] = assert(VOC[v], 'unknown vocation name ' .. tostring(v))
  end
  return out
end

local xml = read(root .. 'server/data/spells/chaos/spells_chaos.xml'):gsub('<!%-%-.-%-%->', '')
local chaosById = {}
for attrs, inner in xml:gmatch('<instant ([^>]*)>(.-)</instant>') do
  local names = {}
  for v in inner:gmatch('<vocation%s+name="([^"]+)"') do names[#names + 1] = v end
  local e = { id = tonumber(attrs:match('spellid="(%d+)"')), name = attrs:match('name="([^"]+)"'),
    words = attrs:match('words="([^"]+)"'), level = tonumber(attrs:match('level="(%d+)"')), vocations = ids(names), chaos = true }
  chaosById[e.id] = e
  entries[#entries + 1] = e
end

-- the client's own copy of the Chaos spells must equal the server's (the generated file)
local clientById = {}
for _, s in ipairs(ChaosSpellData) do clientById[s.id] = s end
for id, e in pairs(chaosById) do
  local c = clientById[id]
  eq(c ~= nil, true, e.name .. ' (' .. id .. ') is in spelldata.lua')
  if c then
    local a, b = {}, {}
    for _, v in ipairs(c.vocations) do a[#a + 1] = v end
    for _, v in ipairs(e.vocations) do b[#b + 1] = v end
    table.sort(a); table.sort(b)
    eq(table.concat(a, ','), table.concat(b, ','), e.name .. ': the client lists the server vocations')
    eq(c.level, e.level, e.name .. ': the client level is the server level')
  end
end

local f = assert(io.open(root .. 'server/data/spells/stock_spells.csv', 'rb'))
local header = true
for line in f:lines() do
  if header then
    header = false
  else
    local c = {}
    for field in (line:gsub('\r', '') .. ','):gmatch('([^,]*),') do c[#c + 1] = field end
    local names = {}
    for v in (c[12] or ''):gmatch('[^;]+') do names[#names + 1] = v end
    entries[#entries + 1] = { id = 100000 + tonumber(c[1]), name = c[2], words = c[3], level = tonumber(c[5]), vocations = ids(names) }
  end
end
f:close()
eq(#entries > 150, true, 'the server spell lists were read (' .. #entries .. ' spells)')

-- ---------------------------------------------------------------- every path, every class
local classes = {}
for name, id in pairs(VOC) do classes[#classes + 1] = { name = name, id = id } end
table.sort(classes, function(a, b) return a.id < b.id end)

local function player(id, level)
  return { getVocation = function() return id end, getLevel = function() return level end, getMagicLevel = function() return 200 end }
end

for _, cls in ipairs(classes) do
  for _, level in ipairs({ 100, 750, 1500 }) do
    local ctx = Core.pickerContext(player(cls.id, level), fold) -- the picker's context: the fold included
    for _, e in ipairs(entries) do
      local listed = false
      for _, v in ipairs(e.vocations) do if v == cls.id then listed = true end end
      local what = cls.name .. ' / ' .. e.name .. ' (level ' .. level .. ')'
      local sp = { name = e.name, words = e.words, level = e.level, vocations = e.vocations, id = e.chaos and e.id or nil }
      -- the Spellbook window and the pickers
      eq(Core.vocationOk(sp, cls.id, fold(cls.id)), listed, what .. ': Core.vocationOk')
      local status = Core.status(sp, ctx)
      eq(status ~= 'vocation', listed, what .. ': status ' .. status)
      eq(Core.filterMatches(sp, ctx, 'vocation'), listed, what .. ': "My vocation" filter')
      if not listed then
        eq(Core.filterMatches(sp, ctx, 'soon'), false, what .. ': not in "Available soon"')
        eq(Core.filterMatches(sp, ctx, 'learned'), false, what .. ': not in "Learned"')
      elseif e.level <= level then
        eq(Core.filterMatches(sp, ctx, 'learned'), true, what .. ': learned list')
      end
      -- the action bar, hotkeys and Auto setup
      eq(ChaosSpellFix.allowsVocation(sp, cls.id, fold), listed, what .. ': ChaosSpellFix.allowsVocation')
      -- the helper's pickers
      eq(ChaosHelperSpells.classOk(sp, cls.id, fold), listed, what .. ': ChaosHelperSpells.classOk')
    end
  end
end

print('spellbook_access_test: ' .. n .. ' checks ok')
