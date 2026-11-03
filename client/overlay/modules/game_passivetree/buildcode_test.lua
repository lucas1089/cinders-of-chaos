-- luajit buildcode_test.lua && lua5.3 buildcode_test.lua (CI runs every client module test from the repo root)
-- ChaosBuildCode (O391): the shared vectors of docs/build_code_vectors.txt (the website's PHP codec reads the same
-- file), every one-character typo refused, the list cleaning of encode, and the tree part checked against the
-- server's own tree code reader (server/data/scripts/chaos/buildshare_core.lua).
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'buildcode.lua')
dofile(dir .. '../../../../server/data/scripts/chaos/buildshare_core.lua')
local C, B = ChaosBuildCode, ChaosBuildShare
local fails, count = 0, 0
local function eq(a, b, what)
  count = count + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(cond, what) eq(cond and true or false, true, what) end

local function split(s, sep)
  local out = {}
  for part in (s .. sep):gmatch('(.-)' .. sep:gsub('%p', '%%%0')) do out[#out + 1] = part end
  return out
end

-- the parts of a text form an encoder takes (class, level, tree, spells, gear)
local function parse(desc)
  local card = {}
  if desc == '' then return card end
  for _, kv in ipairs(split(desc, ';')) do
    local k, v = kv:match('^([^=]+)=(.*)$')
    if k == 'class' or k == 'tree' then card[k] = v
    elseif k == 'level' then card.level = tonumber(v)
    elseif k == 'spells' then
      card.spells = {}
      for _, id in ipairs(split(v, ',')) do card.spells[#card.spells + 1] = tonumber(id) end
    elseif k == 'gear' then
      card.gear = {}
      for _, g in ipairs(split(v, ',')) do
        local s, id = g:match('^(%d+):(%d+)$')
        card.gear[#card.gear + 1] = {slot = tonumber(s), id = tonumber(id)}
      end
    end
  end
  return card
end

-- ------------------------------------------------------------------------------------------------ shared vectors
local f = assert(io.open(dir .. '../../../../docs/build_code_vectors.txt', 'r'))
local okLines, badLines, sample = 0, 0, nil
for line in f:lines() do
  if line ~= '' and line:sub(1, 1) ~= '#' then
    local parts = split(line, '|')
    if parts[1] == 'ok' then
      okLines = okLines + 1
      local name, desc, code = parts[2], parts[3], parts[4]
      local card, err = C.decode(code)
      ok(card ~= nil, name .. ': decodes (' .. tostring(err) .. ')')
      if card then
        eq(C.describe(card), desc, name .. ': text form')
        if not desc:find('skipped=', 1, true) then
          eq(C.encode(parse(desc)), code, name .. ': encode gives the same code')
        end
        local t = card.treeInfo
        if t and not t.newer then
          -- the server reads the same nodes, Paragon points and mastery choices from the tree part
          local build = B.decode(card.tree)
          ok(build ~= nil, name .. ': the server reads the tree part')
          if build then
            eq(table.concat(build.nodes, ','), table.concat(t.nodes, ','), name .. ': same nodes as the server')
            eq(build.classId, t.line, name .. ': same class line as the server')
            for _, k in ipairs(B.PARAGON_KEYS) do
              eq((build.paragon or {})[k], t.paragon[k], name .. ': Paragon ' .. k)
            end
            for id, choice in pairs(build.masteries or {}) do
              eq(t.masteries[id], choice, name .. ': mastery ' .. id)
            end
          end
        end
        if name == 'deadeye 600' then sample = code end
      end
    elseif parts[1] == 'bad' then
      badLines = badLines + 1
      local card, err = C.decode(parts[3])
      ok(card == nil, 'bad ' .. parts[3] .. ' refused')
      eq(err, parts[2], 'bad ' .. parts[3] .. ': kind')
    end
  end
end
f:close()
ok(okLines >= 8 and badLines >= 15, 'vectors read: ' .. okLines .. ' ok, ' .. badLines .. ' bad')

-- ------------------------------------------------------------------------------------------------ typos
ok(sample ~= nil, 'the sample code')
local ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
local passed, tried = 0, 0
for i = 5, #sample do
  for k = 1, #ALPHABET, 7 do
    local ch = ALPHABET:sub(k, k)
    if ch ~= sample:sub(i, i) then
      tried = tried + 1
      if C.decode(sample:sub(1, i - 1) .. ch .. sample:sub(i + 1)) then passed = passed + 1 end
    end
  end
end
eq(passed, 0, 'every one-character change refused (' .. tried .. ' tried)')
eq(C.decode(sample:sub(1, -2)), nil, 'a truncated code')
eq(C.decode('  ' .. sample .. '\n') ~= nil, true, 'spaces around are ignored')

-- ------------------------------------------------------------------------------------------------ encode cleaning
local many = {}
for i = 1, 20 do many[i] = 100 + i end
many[#many + 1] = 101 -- a duplicate
local card = C.decode(C.encode({spells = many}))
eq(#card.spells, C.MAX_SPELLS, 'spells capped')
eq(card.spells[1], 101, 'spell order kept')
card = C.decode(C.encode({spells = {5, 5, 0, -1, 70000, 'x', 6}}))
eq(table.concat(card.spells, ','), '5,6', 'bad and repeated spell ids dropped')
card = C.decode(C.encode({gear = {{slot = 10, id = 9}, {slot = 3, id = 8}, {slot = 1, id = 7}, {12, 6}, {slot = 4, id = 0}}}))
eq(#card.gear, 2, 'the backpack, an unknown slot and an empty id dropped')
eq(card.gear[1].slot, 1, 'gear sorted by slot')
eq(card.gear[2].id, 9, 'gear id')
eq(select(2, C.encode({class = 'paladin'})), 'class', 'an unknown class')
eq(select(2, C.encode({level = 0})), 'level', 'level 0')
eq(select(2, C.encode({level = 70000})), 'level', 'level too high')
eq(select(2, C.encode({tree = 'CB6-AwCRDq5'})), 'tree', 'a damaged tree code')
eq(select(2, C.encode({tree = 'CC1-AQABAUcNGQ'})), 'tree', 'a full code is not a tree code')
eq(select(2, C.encode(nil)), 'format', 'no card')
eq(C.extract('look: [build ' .. sample .. '] nice'), sample, 'extract from a chat line')
eq(C.extract('[build CB6-AwCRDq4]'), nil, 'a tree code is not a full code')
ok(C.isCode(sample) and not C.isCode('hello'), 'isCode')

-- ------------------------------------------------------------------------------------------------ tables
local keys, vocs = {}, {}
for i, c in ipairs(C.CLASSES) do
  ok(not keys[c[1]], 'class key once: ' .. c[1])
  ok(not vocs[c[2]], 'vocation once: ' .. c[2])
  keys[c[1]], vocs[c[2]] = true, true
  eq(C.classIndex(c[1]), i, 'classIndex ' .. c[1])
  eq(C.classOfVocation(c[2]), c[1], 'classOfVocation ' .. c[2])
  eq(C.vocationOf(c[1]), c[2], 'vocationOf ' .. c[1])
end
eq(#C.CLASSES, 21, '21 classes')
eq(C.classOfVocation(2), nil, 'a retired vocation has no class key')
eq(table.concat(C.PARAGON_KEYS, ','), table.concat(B.PARAGON_KEYS, ','), 'Paragon keys as the server')
eq(C.TREE_LAYOUT_MAX, B.VERSION, 'the tree layouts this codec reads end at the server\'s tree code version')
ok(B.READS[C.TREE_LAYOUT_MAX], 'the server reads that version')

print(string.format('buildcode_test: %d checks, %d failed', count, fails))
if fails > 0 then os.exit(1) end
