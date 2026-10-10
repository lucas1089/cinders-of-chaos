-- Pure helpers of the Leaderboards window (no client API), tested by tabrows_test.lua.
-- The board and class tabs are laid out in as few rows as fit, each tab at least as wide as its label in the
-- font it is drawn with (the Chaos fonts or the stock Verdana: the widths are measured, not guessed).
TabRows = {}

local function pack(widths, cap, gap)
  local rows, row, used = {}, {}, 0
  for i, w in ipairs(widths) do
    local need = (#row > 0 and gap or 0) + w
    if #row > 0 and used + need > cap then
      rows[#rows + 1] = row
      row, used = {}, 0
      need = w
    end
    row[#row + 1] = i
    used = used + need
  end
  if #row > 0 then rows[#rows + 1] = row end
  return rows
end

-- widths: the natural width of each tab (label + padding), in order. avail: the width of the row. gap: px between
-- tabs. maxWidth (optional): no tab grows past it. Returns rows = { { {index, width}, ... }, ... }: the tabs in order,
-- split into the fewest rows that fit, balanced (the rows about as full as each other), each row's spare room shared
-- among its tabs. A tab wider than the row gets the whole row.
function TabRows.layout(widths, avail, gap, maxWidth)
  gap = gap or 0
  avail = math.max(1, math.floor(avail or 1))
  local ws = {}
  for i, w in ipairs(widths or {}) do ws[i] = math.min(avail, math.max(1, math.ceil(tonumber(w) or 1))) end
  if #ws == 0 then return {} end
  local count = #pack(ws, avail, gap)
  -- the narrowest cap that still packs into that many rows balances them
  local lo, hi = 1, avail
  for _, w in ipairs(ws) do lo = math.max(lo, w) end
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if #pack(ws, mid, gap) <= count then hi = mid else lo = mid + 1 end
  end
  local out = {}
  for _, idx in ipairs(pack(ws, lo, gap)) do
    local used = gap * (#idx - 1)
    for _, i in ipairs(idx) do used = used + ws[i] end
    local spare = avail - used
    local row = {}
    for k, i in ipairs(idx) do
      -- share the spare room evenly, the first tabs take the odd pixels
      local extra = math.floor(spare / #idx) + ((k <= spare % #idx) and 1 or 0)
      local w = ws[i] + extra
      if maxWidth and w > maxWidth then w = math.max(ws[i], maxWidth) end
      row[#row + 1] = { index = i, width = w }
    end
    out[#out + 1] = row
  end
  return out
end

-- a board value in its format: "time" (seconds, the Cinderheart's fastest kills) as m:ss, else nil
function TabRows.valueText(value, format)
  if format ~= 'time' then return nil end
  local s = math.max(0, math.floor(tonumber(value) or 0))
  return string.format('%d:%02d', math.floor(s / 60), s % 60)
end
