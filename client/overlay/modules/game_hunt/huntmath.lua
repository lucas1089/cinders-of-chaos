-- Pure helpers of the hunt tracker window (no client API), tested by huntmath_test.lua.
HuntMath = {}

-- the base server's rarity names and our colours (same list as game_lootfilter and lootfilter_core.lua)
HuntMath.RARITY = {
  { name = 'Common', color = '#c8c8c8' }, { name = 'Uncommon', color = '#5ccf5c' }, { name = 'Rare', color = '#4a90ff' },
  { name = 'Epic', color = '#a35cf0' }, { name = 'Legendary', color = '#ffd040' }, { name = 'Exotic', color = '#f5b13a' },
  { name = 'Mythic', color = '#ff5a5a' }, { name = 'Chaos', color = '#e02424' }, { name = 'Eternal', color = '#ff8a70' },
  { name = 'Divine', color = '#c8e8ff' }, { name = 'Phantasmal', color = '#9ad8ff' }, { name = 'Celestial', color = '#e4f2ff' },
  { name = 'Cosmic', color = '#b878ff' }, { name = 'Abyssal', color = '#9a4ce0' }, { name = 'Transcendent', color = '#e070ff' },
}
HuntMath.UNIQUE_COLOR = '#e07b24'
HuntMath.ORB_COLOR = '#4fd8d0'
HuntMath.TEXT_COLOR = '#d6c9ae'
HuntMath.GAIN_COLOR = '#7ccf5c'
HuntMath.LOSS_COLOR = '#e03a1e'

-- 3725 -> "1h 02m 05s", 65 -> "1m 05s", 9 -> "9s"; days past 24 h
function HuntMath.duration(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  local d = math.floor(seconds / 86400)
  local h = math.floor((seconds % 86400) / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  if d > 0 then return string.format('%dd %02dh %02dm', d, h, m) end
  if h > 0 then return string.format('%dh %02dm %02ds', h, m, s) end
  if m > 0 then return string.format('%dm %02ds', m, s) end
  return string.format('%ds', s)
end

-- 1234 -> "1.2k", 2500000 -> "2.5M", 3200000000 -> "3.2B"; keeps the sign (the units of client_chaos_numbers;
-- with the display scale a level-1000 session is in the billions)
function HuntMath.short(n)
  n = tonumber(n) or 0
  local sign = n < 0 and '-' or ''
  n = math.abs(n)
  local units = { { 1e12, 'T' }, { 1e9, 'B' }, { 1e6, 'M' }, { 1e3, 'k' } }
  for _, u in ipairs(units) do
    if n >= u[1] then
      local v = math.floor(n / u[1] * 10) / 10
      local text = (v == math.floor(v)) and string.format('%d', v) or string.format('%.1f', v)
      return sign .. text .. u[2]
    end
  end
  return sign .. string.format('%d', math.floor(n))
end

-- 1234567 -> "1,234,567"
function HuntMath.exact(n)
  n = math.floor(tonumber(n) or 0)
  local sign = n < 0 and '-' or ''
  local s = tostring(math.abs(n))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  if out:sub(1, 1) == ',' then out = out:sub(2) end
  return sign .. out
end

-- session seconds shown now: the server's value, plus the time since it arrived while the session runs
function HuntMath.elapsed(sent, paused, receivedAt, now)
  sent = tonumber(sent) or 0
  if paused then return sent end
  return sent + math.max(0, (now or 0) - (receivedAt or 0))
end

-- the "next level" value: the time to the next level at the current rate ("-" without a rate); the experience left
-- goes in its tooltip
function HuntMath.nextLevel(ttl)
  ttl = tonumber(ttl) or -1
  if ttl < 0 then return '-' end
  return HuntMath.duration(ttl)
end

function HuntMath.profitColor(n)
  n = tonumber(n) or 0
  if n > 0 then return HuntMath.GAIN_COLOR end
  if n < 0 then return HuntMath.LOSS_COLOR end
  return HuntMath.TEXT_COLOR
end

local function cap(s)
  s = tostring(s or '?')
  return (s:gsub('^%l', string.upper))
end

-- label and colour of an item row: "[Legendary] Magic Sword", "[Unique] Soulreaper", "Orb of Upheaval"
function HuntMath.itemLabel(name, rarity, unique, orb)
  rarity = tonumber(rarity) or 0
  if unique == 1 or unique == true then return '[Unique] ' .. cap(name), HuntMath.UNIQUE_COLOR end
  local r = HuntMath.RARITY[rarity]
  if r then return '[' .. r.name .. '] ' .. cap(name), r.color end
  if orb == 1 or orb == true then return cap(name), HuntMath.ORB_COLOR end
  return cap(name), HuntMath.TEXT_COLOR
end

-- wire rows (arrays, see server hunt_core.lua H.state) -> tables
function HuntMath.lootRows(list)
  local out = {}
  for _, r in ipairs(type(list) == 'table' and list or {}) do
    if type(r) == 'table' then
      out[#out + 1] = { id = tonumber(r[1]) or 0, count = tonumber(r[2]) or 0, value = tonumber(r[3]) or 0,
        name = tostring(r[4] or '?'), rarity = tonumber(r[5]) or 0, unique = r[6] == 1, orb = r[7] == 1 }
    end
  end
  return out
end

function HuntMath.supplyRows(list)
  local out = {}
  for _, r in ipairs(type(list) == 'table' and list or {}) do
    if type(r) == 'table' then
      out[#out + 1] = { id = tonumber(r[1]) or 0, count = tonumber(r[2]) or 0, value = tonumber(r[3]) or 0,
        name = tostring(r[4] or '?') }
    end
  end
  return out
end

function HuntMath.specialRows(list)
  local out = {}
  for _, r in ipairs(type(list) == 'table' and list or {}) do
    if type(r) == 'table' then
      out[#out + 1] = { id = tonumber(r[1]) or 0, count = tonumber(r[2]) or 0, value = 0, name = tostring(r[3] or '?'),
        rarity = tonumber(r[4]) or 0, unique = r[5] == 1, orb = r[6] == 1 }
    end
  end
  return out
end

function HuntMath.killRows(list, total)
  local out = {}
  total = tonumber(total) or 0
  for _, r in ipairs(type(list) == 'table' and list or {}) do
    if type(r) == 'table' then
      local n = tonumber(r[2]) or 0
      out[#out + 1] = { name = tostring(r[1] or '?'), count = n,
        percent = total > 0 and math.floor(n * 100 / total + 0.5) or 0 }
    end
  end
  return out
end

-- plain-text summary for the clipboard
function HuntMath.summary(st, seconds)
  st = st or {}
  local lines = {
    'Hunt session: ' .. HuntMath.duration(seconds or st.t),
    'Experience: ' .. HuntMath.exact(st.xp) .. ' (' .. HuntMath.exact(st.xph) .. '/h)',
    'Loot: ' .. HuntMath.exact(st.lv) .. ' gold (' .. HuntMath.exact(st.lvh) .. '/h)',
    'Supplies: ' .. HuntMath.exact(st.sv) .. ' gold',
    'Profit: ' .. HuntMath.exact(st.pf) .. ' gold (' .. HuntMath.exact(st.pfh) .. '/h)',
    'Kills: ' .. HuntMath.exact(st.kc),
  }
  for _, k in ipairs(HuntMath.killRows(st.k, st.kc)) do
    lines[#lines + 1] = '  ' .. k.count .. 'x ' .. k.name
  end
  return table.concat(lines, '\n')
end
