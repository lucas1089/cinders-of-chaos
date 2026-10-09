-- Pure helpers of the bestiary window and the task tracker (no UI calls): filtering, paging and texts.
-- Tested by bestiaryview_test.lua (luajit / lua5.3). List rows come from the server (bestiary.lua "list"):
--   [1] id, [2] name, [3] category key, [4] difficulty key, [5] hunting level, [6] kills, [7] stage 0-4,
--   [8] lookType (0 below stage 1)
BestiaryView = {}
local V = BestiaryView

V.ALL = 'all'
V.STAGE_COLORS = { [0] = '#6b6258', [1] = '#d6c9ae', [2] = '#5a8fff', [3] = '#b070ff', [4] = '#f6cf72' }
V.KIND_TEXT = { hunt = 'HUNT', family = 'FAMILY' }

local function num(x) return tonumber(x) or 0 end

function V.row(r)
  return { id = num(r[1]), name = tostring(r[2] or '?'), cat = r[3], diff = r[4], level = num(r[5]), kills = num(r[6]),
    stage = num(r[7]), look = num(r[8]) }
end

-- rows of a category ('all' = every row) whose name contains `query` (case-insensitive, plain text); knownOnly hides
-- undiscovered entries. Keeps the server's order (category, level, name).
function V.filter(rows, cat, query, knownOnly)
  local out = {}
  local q = tostring(query or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
  for _, r in ipairs(rows or {}) do
    if (cat == nil or cat == V.ALL or r.cat == cat) and (not knownOnly or r.stage >= 1)
        and (q == '' or r.name:lower():find(q, 1, true)) then
      out[#out + 1] = r
    end
  end
  return out
end

-- page `page` (1-based, clamped) of `size` rows: the rows, the page, the number of pages
function V.page(list, page, size)
  local pages = math.max(1, math.ceil(#list / size))
  page = math.max(1, math.min(num(page), pages))
  local out = {}
  for i = (page - 1) * size + 1, math.min(#list, page * size) do
    out[#out + 1] = list[i]
  end
  return out, page, pages
end

function V.stageName(stage, names)
  if num(stage) <= 0 then return 'Undiscovered' end
  return (names and names[num(stage)]) or ('Stage ' .. num(stage))
end

-- "Kills 30 / 250" (towards the next stage) or "Kills 1200" (complete)
function V.killText(kills, nextAt)
  if nextAt and num(nextAt) > 0 then
    return string.format('Kills %d / %d', num(kills), num(nextAt))
  end
  return string.format('Kills %d', num(kills))
end

-- progress to the next stage in percent (100 when complete): from the previous threshold to the next one
function V.stagePercent(kills, th)
  kills = num(kills)
  local prev = 0
  for _, k in ipairs(th or {}) do
    if kills < num(k) then
      return math.floor((kills - prev) * 100 / math.max(1, num(k) - prev))
    end
    prev = num(k)
  end
  return 100
end

local function pctText(p)
  p = num(p)
  if p == math.floor(p) then return string.format('%d%%', p) end
  return string.format('%.1f%%', p)
end
V.pctText = pctText

-- {name, pct} rows (positive = takes less damage) -> "fire -20%, energy +10%" as damage taken
function V.elementsText(list)
  local parts = {}
  for _, e in ipairs(list or {}) do
    local taken = -num(e.pct)
    parts[#parts + 1] = string.format('%s %s%s', tostring(e.name), taken > 0 and '+' or '', pctText(taken))
  end
  return table.concat(parts, ', ')
end

function V.chanceText(c)
  c = num(c)
  if c >= 10 then return string.format('%d%%', math.floor(c + 0.5)) end
  if c >= 1 then return string.format('%.1f%%', c) end
  return string.format('%.2f%%', c)
end

local function short(n)
  n = num(n)
  if n >= 1000000 then
    local v = n / 1000000
    return (v == math.floor(v) and string.format('%dM', v) or string.format('%.1fM', v))
  elseif n >= 1000 then
    local v = n / 1000
    return (v == math.floor(v) and string.format('%dk', v) or string.format('%.1fk', v))
  end
  return tostring(math.floor(n))
end
V.short = short

-- {gold, chaos, divine, exp, points} -> "4k gold, 1 Chaos Orb, 12k exp, 5 points"
function V.rewardText(r)
  r = type(r) == 'table' and r or {}
  local parts = {}
  if num(r.gold) > 0 then parts[#parts + 1] = short(r.gold) .. ' gold' end
  if num(r.chaos) > 0 then parts[#parts + 1] = num(r.chaos) .. ' Chaos Orb' .. (num(r.chaos) > 1 and 's' or '') end
  if num(r.divine) > 0 then parts[#parts + 1] = num(r.divine) .. ' Divine Orb' .. (num(r.divine) > 1 and 's' or '') end
  if num(r.exp) > 0 then parts[#parts + 1] = short(r.exp) .. ' exp' end
  if num(r.points) > 0 then parts[#parts + 1] = num(r.points) .. ' points' end
  return table.concat(parts, ', ')
end

-- the same, shorter (task rows): "30k gold, 1 Chaos, 14.3k exp, 16 points"
function V.rewardShort(r)
  r = type(r) == 'table' and r or {}
  local parts = {}
  if num(r.gold) > 0 then parts[#parts + 1] = short(r.gold) .. ' gold' end
  if num(r.chaos) > 0 then parts[#parts + 1] = num(r.chaos) .. ' Chaos' end
  if num(r.divine) > 0 then parts[#parts + 1] = num(r.divine) .. ' Divine' end
  if num(r.exp) > 0 then parts[#parts + 1] = short(r.exp) .. ' exp' end
  if num(r.points) > 0 then parts[#parts + 1] = num(r.points) .. ' points' end
  return table.concat(parts, ', ')
end

-- a task or an offer {kind, label, required, lo, hi} -> "Kill 150 Dragons." / "Kill 270 Dragons of level 40-120."
function V.taskText(t)
  local n = num(t.required)
  if t.kind == 'family' then
    return string.format('Kill %d %s of level %d-%d.', n, tostring(t.label), num(t.lo), num(t.hi))
  end
  return string.format('Kill %d %s.', n, V.plural(tostring(t.label), n))
end

function V.plural(name, count)
  if count == 1 then return name end
  local lower = name:lower()
  if lower:match('s$') then return name end
  if lower:match('[^aeiou]y$') then return name:sub(1, -2) .. 'ies' end
  if lower:match('x$') or lower:match('ch$') or lower:match('sh$') then return name .. 'es' end
  if lower:match('man$') then return name:sub(1, -3) .. 'en' end
  return name .. 's'
end

-- tracker row {k = task|bounty, label, p, r} -> "Dragon 12/150", the percent and whether it is done
function V.trackerLine(row)
  local p, r = num(row.p), math.max(1, num(row.r))
  return string.format('%s %d/%d', tostring(row.label or '?'), p, r), math.floor(math.min(p, r) * 100 / r), p >= r
end

-- the limits line of the tasks tab
function V.limitsText(t)
  t = type(t) == 'table' and t or {}
  return string.format('Active %d / %d   Today %d / %d   This week %d / %d', num(t.active), num(t.maxActive),
    num(t.doneDay), num(t.dailyLimit), num(t.doneWeek), num(t.weeklyLimit))
end

-- why no task can be accepted now (the server checks the same), or nil
function V.acceptBlock(t)
  t = type(t) == 'table' and t or {}
  local active = num(t.active)
  if active >= num(t.maxActive) then
    return string.format('You hold %d kill tasks: the most at once.', active)
  elseif num(t.doneDay) + active >= num(t.dailyLimit) then
    return string.format('At most %d kill tasks a day (completed and held).', num(t.dailyLimit))
  elseif num(t.doneWeek) + active >= num(t.weeklyLimit) then
    return string.format('At most %d kill tasks a week (completed and held).', num(t.weeklyLimit))
  end
  return nil
end

function V.clock(seconds)
  seconds = math.max(0, math.floor(num(seconds)))
  return string.format('%dh %02dm', math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
end

return V
