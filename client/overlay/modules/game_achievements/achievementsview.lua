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
    if type(r) ~= 'table' then
      -- not a row: left out
    elseif cat == V.ALL or cat == nil or r.c == cat or (cat == V.RECENT and V.isUnlocked(r)) then
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

-- ---------------------------------------------------------------- reward track
-- track = the server's "track" message (cosmetics_core.lua trackView): ap account points; steps [{p, n, k, d, c, a, o}]
-- (the point milestones, lowest first); cats [{key, cn, dn, t, ti, n, k, d, c, a, o, x}] (category completion).
V.TRACK = 'track'

local KIND_NAMES = { killfx = 'Kill effect', lootbeam = 'Loot label accent', chatcolor = 'Chat name colour',
  spellskin = 'Spell effect skin' }
function V.kindName(kind) return KIND_NAMES[kind or ''] or 'Cosmetic' end

local function steps(track)
  local out = {}
  for _, s in ipairs(type(track) == 'table' and type(track.steps) == 'table' and track.steps or {}) do
    if type(s) == 'table' then out[#out + 1] = s end -- a step that is no table is left out
  end
  return out
end

-- the next milestone (not reached yet) and the points of the one before it (0 at the start); nil when all are reached
function V.trackNext(track)
  local ap, prev = num(track and track.ap), 0
  for _, s in ipairs(steps(track)) do
    if ap < num(s.p) then return s, prev end
    prev = num(s.p)
  end
  return nil, prev
end

-- how many milestones the account has reached
function V.trackReached(track)
  local n, ap = 0, num(track and track.ap)
  for _, s in ipairs(steps(track)) do
    if ap >= num(s.p) then n = n + 1 end
  end
  return n
end

-- 0..100 from the previous milestone to the next one (100 when every one is reached)
function V.trackPercent(track)
  local nxt, prev = V.trackNext(track)
  if not nxt then return 100 end
  local span = num(nxt.p) - prev
  if span <= 0 then return 0 end
  return math.max(0, math.min(100, math.floor((num(track.ap) - prev) * 100 / span)))
end

function V.trackText(track)
  local nxt = V.trackNext(track)
  local ap = num(track and track.ap)
  if not nxt then
    return string.format('%s account points  -  every reward unlocked (%d)', group(ap), #steps(track))
  end
  return string.format('%s / %s account points  -  next: %s (%s)', group(ap), group(num(nxt.p)), nxt.n or '?',
    V.kindName(nxt.k))
end

-- the preview tooltip of a reward (a milestone or a category's); ap = the account's points
function V.rewardTooltip(r, ap)
  local lines = { string.format('%s  -  %s', r.n or '?', V.kindName(r.k)) }
  if r.d and r.d ~= '' then lines[#lines + 1] = r.d end
  if r.c then lines[#lines + 1] = 'Colour: ' .. r.c end
  if r.a then lines[#lines + 1] = 'Label background: ' .. r.a:sub(1, 7) end
  if r.p then
    if num(ap) >= num(r.p) then
      lines[#lines + 1] = string.format('Reached at %s account points.', group(num(r.p)))
    else
      lines[#lines + 1] = string.format('Unlocks at %s account points (%s to go).', group(num(r.p)), group(num(r.p) - num(ap)))
    end
  end
  if r.ti then lines[#lines + 1] = 'Title: ' .. r.ti end
  lines[#lines + 1] = r.o and 'Owned: choose it in Character > Cosmetics.' or 'Earned by playing, never sold.'
  return table.concat(lines, '\n')
end

-- the completion reward of a category for its tooltip, or nil
function V.categoryReward(track, key)
  for _, c in ipairs(type(track) == 'table' and type(track.cats) == 'table' and track.cats or {}) do
    if c.key == key then
      return string.format('Complete all %d: title %s + %s (%s)%s', num(c.t), c.ti or '?', c.n or '?', V.kindName(c.k),
        num(c.x) == 1 and '  -  done' or '')
    end
  end
  return nil
end

-- a reward's description without the "how to get it" tail (the row shows that already)
function V.shortDesc(d)
  d = tostring(d or '')
  d = d:gsub('%s+Reward track: [%d,]+ points%.$', '')
  d = d:gsub('%s+Complete [^.]+%.$', '')
  return d
end

-- the rows of the "Reward track" view: milestones, then category completions. Each:
--   {name, right, desc, extra, percent, progress, done, color, accent, tip} (color / accent: the preview of a chat colour
--   or a label accent)
function V.trackRows(track)
  local out = {}
  local ap = num(track and track.ap)
  for _, s in ipairs(steps(track)) do
    local done = ap >= num(s.p)
    out[#out + 1] = { name = s.n or '?', right = group(num(s.p)) .. ' pts', desc = V.shortDesc(s.d),
      extra = V.kindName(s.k) .. (s.o and '  -  owned' or ''), done = done, color = s.c, accent = s.a,
      percent = done and 100 or math.floor(math.min(ap, num(s.p)) * 100 / math.max(1, num(s.p))),
      progress = done and 'Unlocked' or (group(ap) .. ' / ' .. group(num(s.p)) .. ' account points'),
      tip = V.rewardTooltip(s, ap) }
  end
  for _, c in ipairs(type(track) == 'table' and type(track.cats) == 'table' and track.cats or {}) do
    local done = num(c.x) == 1
    out[#out + 1] = { name = string.format('%s: %s', c.cn or c.key or '?', c.n or '?'), right = 'Category',
      desc = V.shortDesc(c.d), extra = 'Title: ' .. (c.ti or '?') .. '   -   ' .. V.kindName(c.k) .. (c.o and '  -  owned' or ''),
      done = done, color = c.c, accent = c.a, percent = num(c.t) > 0 and math.floor(math.min(num(c.dn), num(c.t)) * 100 / num(c.t)) or 0,
      progress = done and 'Complete' or (group(num(c.dn)) .. ' / ' .. group(num(c.t)) .. ' achievements'),
      tip = V.rewardTooltip(c, ap) }
  end
  return out
end

-- what the title selector sends to the server for a choice ("auto", "none" or the title's text)
function V.titleParam(choice)
  if choice == 'auto' or choice == 'none' then return choice end
  return tostring(choice)
end

return V
