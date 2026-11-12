-- game_hdsprites, the reader of the overlay index (data/hd/index.txt, made by client/tools/sprites/gen_hd_overlay.py).
-- The engine reads the same file itself (src/client/chaoshdoverlay.h, base patch 0196); this reader follows the same rules so
-- the module can say how many sprites the overlay holds and a test can hold the shipped file to them. Tested by
-- hdindex_test.lua (luajit and lua5.3).
HdIndex = {}
local I = HdIndex

I.HEADER = 'chaos-hd-overlay 1'
I.BASE = 32
I.MAX_SCALE = 8

local function number(s, max, base)
  if type(s) ~= 'string' or #s == 0 or #s > 12 or not s:match(base == 16 and '^%x+$' or '^%d+$') then return nil end
  local n = tonumber(s, base)
  if not n or n > max then return nil end
  return n
end

local function validName(name)
  return #name > 0 and #name <= 120 and name:sub(1, 1) ~= '.' and not name:find('[/\\:%c]')
end

-- text -> { atlases = { 'hd_2x_0.png', ... }, sprites = { [id] = { atlas, x, y, scale, crc } },
--           slots = { ['category:thing:index'] = { sprite, atlas, x, y, scale } }, count = sprites, slotCount = slots }, or nil, 'line N: why'
function I.parse(text)
  local out = { atlases = {}, sprites = {}, slots = {}, count = 0, slotCount = 0 }
  local header = false
  local lineNo = 0
  for line in (text .. '\n'):gmatch('(.-)\r?\n') do
    lineNo = lineNo + 1
    if line ~= '' and line:sub(1, 1) ~= '#' then
      local w = {}
      for token in line:gmatch('%S+') do w[#w + 1] = token end
      local function fail(why) return nil, 'line ' .. lineNo .. ': ' .. why end
      if not header then
        if #w ~= 2 or w[1] ~= 'chaos-hd-overlay' or w[2] ~= '1' then return fail('not a chaos-hd-overlay 1 file') end
        header = true
      elseif w[1] == 'atlas' then
        if #w ~= 3 or number(w[2], 4096, 10) ~= #out.atlases or not validName(w[3]) then return fail('bad atlas line') end
        out.atlases[#out.atlases + 1] = w[3]
      elseif w[1] == 'sprite' then
        local id = #w == 7 and number(w[2], 4294967295, 10)
        local atlas = id and number(w[3], 65535, 10)
        local x = atlas and number(w[4], 65535, 10)
        local y = x and number(w[5], 65535, 10)
        local scale = y and number(w[6], I.MAX_SCALE, 10)
        local crc = scale and #w[7] == 8 and number(w[7], 4294967295, 16)
        if not crc or id == 0 or scale < 1 then return fail('bad sprite line') end
        if atlas >= #out.atlases then return fail('sprite names an atlas that is not declared') end
        if not out.sprites[id] then out.count = out.count + 1 end
        out.sprites[id] = { atlas = atlas, x = x, y = y, scale = scale, crc = crc }
      elseif w[1] == 'slot' then
        local cat = #w == 9 and number(w[2], 3, 10)
        local thing = cat and number(w[3], 65535, 10)
        local index = thing and number(w[4], 65535, 10)
        local sprite = index and number(w[5], 4294967295, 10)
        local atlas = sprite and number(w[6], 65535, 10)
        local x = atlas and number(w[7], 65535, 10)
        local y = x and number(w[8], 65535, 10)
        local scale = y and number(w[9], I.MAX_SCALE, 10)
        if not scale or thing == 0 or scale < 1 then return fail('bad slot line') end
        if atlas >= #out.atlases then return fail('slot names an atlas that is not declared') end
        local key = cat .. ':' .. thing .. ':' .. index
        if not out.slots[key] then out.slotCount = out.slotCount + 1 end
        out.slots[key] = { sprite = sprite, atlas = atlas, x = x, y = y, scale = scale }
      else
        return fail("unknown record '" .. w[1] .. "'")
      end
    end
  end
  if not header then return nil, 'empty index' end
  return out
end

-- the sprite ids of the index, sorted
function I.ids(index)
  local ids = {}
  for id in pairs(index.sprites) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

-- the file names a client needs next to the index (every atlas some sprite uses)
function I.usedAtlases(index)
  local used, list = {}, {}
  for _, e in pairs(index.sprites) do used[e.atlas] = true end
  for _, e in pairs(index.slots) do used[e.atlas] = true end
  for i, name in ipairs(index.atlases) do
    if used[i - 1] then list[#list + 1] = name end
  end
  return list
end
