-- Pure helpers of the achievements window (no UI calls): filtering, ordering and texts.
-- Tested by achievementsview_test.lua (luajit / lua5.3). Rows come from the server (achievements_core.lua K.view):
--   i id, n name, d description, c category, p points, h hidden (1), u unlock time (0 = locked), v value, t target,
--   ti title, r reward text
AchievementsView = {}
local V = AchievementsView

V.ALL = 'all'
V.RECENT = 'recent'

local function num(x) return tonumber(x) or 0 end

function V.isUnlocked(row) return num(row.u) > 0 end
function V.isHiddenLocked(row) return num(row.h) == 1 and not V.isUnlocked(row) end

-- rows of one category ('all' = every row), in the server's order; unlocked first when unlockedFirst
function V.filter(rows, cat, unlockedFirst)
  local out = {}
  for i, r in ipairs(rows or {}) do
    if cat == V.ALL or cat == nil or r.c == cat or (cat == V.RECENT and V.isUnlocked(r)) then
      out[#out + 1] = { row = r, pos = i }
    end
  end
  table.sort(out, function(a, b)
    if cat == V.RECENT then
      if num(a.row.u) ~= num(b.row.u) then return num(a.row.u) > num(b.row.u) end
    elseif unlockedFirst then
      local ua, ub = V.isUnlocked(a.row), V.isUnlocked(b.row)
      if ua ~= ub then return ua end
    end
    return a.pos < b.pos
  end)
  local res = {}
  for i, e in ipairs(out) do res[i] = e.row end
  return res
end

-- 0..100
function V.percent(row)
  if V.isUnlocked(row) then return 100 end
  local t = num(row.t)
  if t <= 0 then return 0 end
  return math.max(0, math.min(100, math.floor(num(row.v) * 100 / t)))
end

local function group(n)
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  return (out:gsub('^,', ''))
end
V.group = group

function V.progressText(row)
  if V.isHiddenLocked(row) then return '???' end
  if V.isUnlocked(row) then return 'Unlocked' end
  return group(num(row.v)) .. ' / ' .. group(num(row.t))
end

-- "2026-10-08" from an os.time value (server time)
function V.dateText(at)
  at = num(at)
  if at <= 0 then return '' end
  return os.date('%Y-%m-%d', at)
end

-- the extra line under a row: title and reward
function V.extraText(row)
  local parts = {}
  if row.ti and row.ti ~= '' then parts[#parts + 1] = 'Title: ' .. row.ti end
  if row.r and row.r ~= '' then parts[#parts + 1] = 'Reward: ' .. row.r end
  return table.concat(parts, '   -   ')
end

function V.categoryLabel(cat)
  return string.format('%s  %d/%d', cat.name or cat.key or '?', num(cat.done), num(cat.total))
end

function V.summaryText(state)
  return string.format('Points: %d   -   Account: %d   -   Unlocked: %d / %d', num(state.points), num(state.accountPoints),
    num(state.unlocked), num(state.total))
end

-- what the title selector sends to the server for a choice ("auto", "none" or the title's text)
function V.titleParam(choice)
  if choice == 'auto' or choice == 'none' then return choice end
  return tostring(choice)
end

return V
