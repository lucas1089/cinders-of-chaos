-- Animated chat name colours (O562): pure logic, no client API (chatcolorfx_test.lua runs it under luajit and lua5.3).
-- A chat colour cosmetic is a hex colour on the server (cosmetics_config.lua, kind "chatcolor"); this file gives each of
-- the 17 an animated look of its own that is drawn from that colour, per character of the name, from the time:
--   flow     a palette of 2-3 colours that runs along the name
--   shimmer  the base colour with a bright band sweeping across it
--   pulse    the whole name breathing between the base and a bright tone (a glow)
--   wave     two colours that swap along the name in a slow wave, each letter a step apart
--   chase    a dark band chasing across the base colour (steel, ink)
--   sparkle  the base colour with a single letter twinkling white now and then
-- Every look is smooth in time (sines, no random jumps), so a name never flickers. The static fallback is the base
-- colour itself: ChatColorFx.static(style), what the console drew before and still draws where the engine cannot
-- animate (setColoredText missing or a client that turned the animation off).
ChatColorFx = {}
local F = ChatColorFx

F.FRAME_MS = 100 -- how often a drawn name is repainted
F.MAX_LIVE = 24  -- console lines animated at once (the newest)

local floor, sin, abs, max, min = math.floor, math.sin, math.abs, math.max, math.min
local TAU = 2 * math.pi

local function hex(c)
  c = tostring(c):lower()
  local r, g, b = c:match('^#(%x%x)(%x%x)(%x%x)')
  if not r then return nil end
  return { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) }
end
F.rgb = hex

local function toHex(c)
  return string.format('#%02x%02x%02x', floor(max(0, min(255, c[1])) + 0.5), floor(max(0, min(255, c[2])) + 0.5),
    floor(max(0, min(255, c[3])) + 0.5))
end

local function mix(a, b, k)
  k = max(0, min(1, k))
  return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
end

-- a palette sampled at p (0..1, wrapping): colours evenly spaced, linear between them
local function palette(cols, p)
  p = p % 1
  local n = #cols
  local x = p * n
  local i = floor(x)
  return mix(cols[i % n + 1], cols[(i + 1) % n + 1], x - i)
end

-- ---------------------------------------------------------------- the looks, by the server's colour (lowercase hex)
-- {fx, colours (hex), speed (cycles per second), width (letters one cycle spans)}
F.STYLES = {
  ['#ff9a4a'] = { key = 'chat_cinder', fx = 'flow', cols = { '#ff9a4a', '#d8401c', '#ffd070' }, speed = 0.45, span = 9 },
  ['#7fc8ff'] = { key = 'chat_frost', fx = 'shimmer', cols = { '#7fc8ff', '#f4fbff' }, speed = 0.50, span = 12 },
  ['#7ee08a'] = { key = 'chat_verdant', fx = 'wave', cols = { '#3fae5a', '#b8ff9c' }, speed = 0.40, span = 8 },
  ['#c49cff'] = { key = 'chat_amethyst', fx = 'flow', cols = { '#c49cff', '#ff7ad8', '#7a8cff' }, speed = 0.35, span = 10 },
  ['#ff8fb0'] = { key = 'chat_rose', fx = 'pulse', cols = { '#d4527c', '#ffd0e0' }, speed = 0.55, span = 6 },
  ['#f0cf6a'] = { key = 'chat_veteran', fx = 'shimmer', cols = { '#d9a62e', '#fff2b8' }, speed = 0.40, span = 14 },
  ['#b8c4d4'] = { key = 'chat_gladiator', fx = 'chase', cols = { '#d4dde8', '#6c7a8c' }, speed = 0.60, span = 10 },
  ['#ff6a4a'] = { key = 'chat_infernal', fx = 'flow', cols = { '#ff3a1a', '#ff9a2a', '#ffe070', '#ff3a1a' }, speed = 0.70, span = 7 },
  ['#ffd98a'] = { key = 'chat_candlelight', fx = 'pulse', cols = { '#c8902c', '#fff0b0' }, speed = 0.30, span = 5 },
  ['#e8925a'] = { key = 'chat_marchember', fx = 'wave', cols = { '#a8481c', '#ffb878' }, speed = 0.50, span = 6 },
  ['#cfc4b4'] = { key = 'chat_ashen', fx = 'sparkle', cols = { '#a89c8c', '#fffaf0' }, speed = 0.30, span = 7 },
  ['#5cc8c0'] = { key = 'chat_chronicler', fx = 'chase', cols = { '#7ff0e4', '#1e7c78' }, speed = 0.35, span = 12 },
  ['#e8a070'] = { key = 'chat_huntsman', fx = 'chase', cols = { '#f0b080', '#8c4c24' }, speed = 0.55, span = 8 },
  ['#e8848c'] = { key = 'chat_bloodsteel', fx = 'wave', cols = { '#a82838', '#ffb0b8' }, speed = 0.45, span = 7 },
  ['#e8d890'] = { key = 'chat_lantern', fx = 'shimmer', cols = { '#d8c070', '#ffffe0' }, speed = 0.30, span = 10 },
  ['#f2d27a'] = { key = 'chat_collector', fx = 'flow', cols = { '#f2d27a', '#fff6d8', '#c8a040', '#7fe0d0' }, speed = 0.30, span = 12 },
  ['#e0664a'] = { key = 'chat_pactbound', fx = 'pulse', cols = { '#b02a1c', '#ff9a70' }, speed = 0.65, span = 6 },
}

local cache = {}
-- the look of a colour the server sent (any case), or nil: a colour with no look stays flat
function F.styleOf(color)
  if type(color) ~= 'string' then return nil end
  local key = color:lower():sub(1, 7)
  local s = F.STYLES[key]
  if not s then return nil end
  if not cache[key] then
    local cols = {}
    for i, c in ipairs(s.cols) do cols[i] = hex(c) end
    cache[key] = { key = s.key, fx = s.fx, cols = cols, base = key, speed = s.speed, span = s.span }
  end
  return cache[key]
end

function F.static(style)
  return style and style.base or nil
end

-- ---------------------------------------------------------------- the colour of letter i of n at time t (seconds)
function F.colorAt(style, i, n, t)
  local c = style.cols
  local ph = (t or 0) * style.speed
  local pos = (i - 1) / style.span
  local fx = style.fx
  local out
  if fx == 'flow' then
    out = palette(c, pos - ph)
  elseif fx == 'shimmer' then
    -- a band about 3 letters wide travelling over the base colour, once per cycle and resting between sweeps
    local center = ((ph % 1.6) * 1.0) * (n + 6) - 3
    local d = abs((i - 1) - center)
    out = mix(c[1], c[2], max(0, 1 - d / 3) ^ 1.5 * 0.95 + 0.04 * (0.5 + 0.5 * sin(TAU * (ph + pos))))
  elseif fx == 'pulse' then
    local k = 0.5 + 0.5 * sin(TAU * ph)
    k = k * k * (3 - 2 * k)
    out = mix(c[1], c[2], k * (0.85 + 0.15 * sin(TAU * pos)))
  elseif fx == 'wave' then
    out = mix(c[1], c[2], 0.5 + 0.5 * sin(TAU * (ph - pos)))
  elseif fx == 'chase' then
    local center = (ph % 1) * (n + 4) - 2
    local d = abs((i - 1) - center)
    out = mix(c[1], c[2], max(0, 1 - d / 2.5) * 0.9)
  else -- sparkle: one letter at a time twinkles
    local slot = floor(ph * 2)
    local lit = (slot * 7 + 3) % max(1, n) + 1
    local u = (ph * 2) % 1
    local k = (i == lit) and max(0, sin(math.pi * u)) ^ 2 or 0
    out = mix(c[1], c[2], k)
  end
  return toHex(out)
end

-- the name as coloured parts {text, colour, ...}: a run of letters with the same colour is one part
function F.nameParts(name, style, t)
  local parts = {}
  local n = #name
  local cur, buf = nil, {}
  local function flush()
    if cur then
      parts[#parts + 1] = table.concat(buf)
      parts[#parts + 1] = cur
    end
    buf = {}
  end
  for i = 1, n do
    local c = F.colorAt(style, i, n, t)
    if c ~= cur then
      flush()
      cur = c
    end
    buf[#buf + 1] = name:sub(i, i)
  end
  flush()
  return parts
end

-- CosmeticsLogic.recolor with a look instead of one colour: the bytes first..last of a coloured line take the look at
-- time t. parts = {text, colour, ...}. The result differs from the static line only in the colours of that range.
function F.recolor(parts, first, last, style, t)
  local out = {}
  local pos = 0
  local len = last - first + 1
  local function push(s, c)
    if s == '' then return end
    if out[#out] == c and #out >= 2 then
      out[#out - 1] = out[#out - 1] .. s
    else
      out[#out + 1] = s
      out[#out + 1] = c
    end
  end
  for i = 1, #parts - 1, 2 do
    local s, c = parts[i], parts[i + 1]
    for k = 1, #s do
      local at = pos + k
      if at >= first and at <= last then
        push(s:sub(k, k), F.colorAt(style, at - first + 1, len, t))
      else
        push(s:sub(k, k), c)
      end
    end
    pos = pos + #s
  end
  return out
end
