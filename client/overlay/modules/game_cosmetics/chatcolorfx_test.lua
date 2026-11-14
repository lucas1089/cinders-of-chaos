-- luajit chatcolorfx_test.lua && lua5.3 chatcolorfx_test.lua  (any folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'chatcolorfx.lua')
local F = ChatColorFx
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end
local function read(p) local f = assert(io.open(p, 'rb')) local t = f:read('*a') f:close() return t end

-- every chat colour of the server has a look
local cfg = read(dir .. '../../../../server/data/scripts/chaos/cosmetics_config.lua')
local colors, count = {}, 0
for key, color in cfg:gmatch('key = "(chat_[%w_]+)", kind = "chatcolor".-color = "(#%x%x%x%x%x%x)"') do
  count = count + 1
  colors[key] = color
  local s = F.styleOf(color)
  eq(s ~= nil, true, 'a look for ' .. key)
  eq(s.key, key, 'the look is named after its cosmetic ' .. key)
end
eq(count, 17, 'the 17 chat colours of the server')
local styleCount = 0
for _ in pairs(F.STYLES) do styleCount = styleCount + 1 end
eq(styleCount, 17, 'no look without a cosmetic')
eq(F.styleOf('#FF9A4A') ~= nil, true, 'any case') eq(F.styleOf('#ff9a4a80') ~= nil, true, 'a colour with alpha')
eq(F.styleOf('#123456'), nil, 'an unknown colour stays flat') eq(F.styleOf(nil), nil, 'nil') eq(F.styleOf(12), nil, 'not text')
eq(F.static(F.styleOf('#7fc8ff')), '#7fc8ff', 'the static fallback is the server colour')
eq(F.static(nil), nil, 'no look no static')

-- moving, distinct and smooth
local name = 'Ashwalker'
local sigs = {}
for key, color in pairs(colors) do
  local s = F.styleOf(color)
  local sig, changed, maxJump = {}, false, 0
  local prev
  for step = 0, 80 do
    local t = step * 0.1
    local line = {}
    for i = 1, #name do line[#line + 1] = F.colorAt(s, i, #name, t) end
    local joined = table.concat(line, ',')
    if prev and prev ~= joined then changed = true end
    -- no jump: a letter's colour moves at most 120 of 765 between two frames of 100 ms
    if prev then
      local pl = {}
      for c in prev:gmatch('[^,]+') do pl[#pl + 1] = c end
      for i = 1, #name do
        local a, b = F.rgb(pl[i]), F.rgb(line[i])
        local d = math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) + math.abs(a[3] - b[3])
        if d > maxJump then maxJump = d end
      end
    end
    prev = joined
    if step % 4 == 0 then sig[#sig + 1] = joined end
  end
  eq(changed, true, key .. ' moves')
  eq(maxJump <= 330, true, key .. ' does not flicker (biggest step ' .. maxJump .. ')')
  sigs[key] = table.concat(sig, '|')
  -- the colours stay readable: no letter darker than a third of the base
  for step = 0, 40 do
    for i = 1, #name do
      local c = F.rgb(F.colorAt(s, i, #name, step * 0.25))
      eq(c[1] + c[2] + c[3] >= 150, true, key .. ' stays readable')
    end
  end
end
local seen = {}
for key, sig in pairs(sigs) do eq(seen[sig], nil, key .. ' differs from ' .. tostring(seen[sig])) seen[sig] = key end

-- the parts
local s = F.styleOf('#ff9a4a')
local p = F.nameParts('Abc', s, 0)
eq(#p % 2, 0, 'parts come in pairs')
local text = {}
for i = 1, #p, 2 do text[#text + 1] = p[i] end
eq(table.concat(text), 'Abc', 'the parts say the name')
eq(F.colorAt(s, 1, 3, 1.0) ~= F.colorAt(s, 1, 3, 0), true, 'time moves a letter')
-- a coloured line: only the name range changes, the text stays whole
local line = { '12:00 Ash [30]: ', '#f0f000', 'hello', 'white' }
local r = F.recolor(line, 7, 9, s, 0.3)
local all = {}
for i = 1, #r, 2 do all[#all + 1] = r[i] end
eq(table.concat(all), '12:00 Ash [30]: hello', 'text kept')
eq(r[2], '#f0f000', 'before the name: the line colour') eq(r[#r], 'white', 'after: the message colour')
local r2 = F.recolor(line, 7, 9, s, 0.3)
eq(table.concat(r), table.concat(r2), 'same time, same colours')
for i = 2, #r, 2 do eq(r[i] == 'white' or r[i]:match('^#%x%x%x%x%x%x$') ~= nil, true, 'a valid colour') end
for i = 2, #r - 2, 2 do eq(r[i] ~= r[i + 2], true, 'neighbouring parts differ (merged)') end
print('chatcolorfx_test: ' .. n .. ' checks OK')
