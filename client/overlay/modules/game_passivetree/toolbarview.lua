-- Toolbar maths of the passive tree window (no client API, tested by toolbarview_test.lua). passivetree.lua
-- layoutTreeToolbar sizes the action buttons and fits the Primary / Secondary line with these.
TreeToolbar = {}
local T = TreeToolbar

T.ELLIPSIS = '...'

-- n buttons of one width in a row of `total` pixels: `side` free at both ends, `gap` between two buttons, at most `max`
-- wide (then the row is centred). Returns {width, left}: left is the first button's offset from the row's left edge.
function T.row(total, n, gap, side, max)
  total, n, gap, side = tonumber(total) or 0, tonumber(n) or 0, tonumber(gap) or 0, tonumber(side) or 0
  if n <= 0 then
    return {width = 0, left = side}
  end
  local width = math.floor(math.max(0, total - 2 * side - gap * (n - 1)) / n)
  if max and width > max then
    width = max
  end
  local used = width * n + gap * (n - 1)
  return {width = width, left = math.max(side, math.floor((total - used) / 2))}
end

-- the first `bytes` bytes of text, not cutting a UTF-8 character in two (a cp1252 text loses at most one more character)
local function prefix(text, bytes)
  while bytes > 0 and bytes < #text do
    local b = text:byte(bytes + 1)
    if b < 0x80 or b >= 0xC0 then
      break
    end
    bytes = bytes - 1
  end
  return text:sub(1, bytes)
end

local function trimEnd(s)
  return (s:gsub('[%s,;:]+$', ''))
end

-- text cut to fit maxWidth pixels (measure(s) -> pixels), with "..." when cut. Returns the text and whether it was cut.
function T.fit(text, maxWidth, measure)
  text = tostring(text or '')
  if text == '' or measure(text) <= maxWidth then
    return text, false
  end
  local lo, hi = 0, #text - 1 -- the longest prefix that fits with the ellipsis
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if measure(trimEnd(prefix(text, mid)) .. T.ELLIPSIS) <= maxWidth then
      lo = mid
    else
      hi = mid - 1
    end
  end
  local cut = trimEnd(prefix(text, lo))
  return cut .. T.ELLIPSIS, true
end

return T
