-- Pure helpers of the Party Finder window (no client API), tested by partyfinderview_test.lua.
-- Rows come from the server (server/data/scripts/chaos/party_finder_core.lua K.row / K.list); times are seconds counted
-- from the moment the list arrived, so the window counts down by itself between two pushes.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
PartyFinderView = {}
local V = PartyFinderView

V.ROLE_ORDER = { 'tank', 'healer', 'dps' }
V.ROLE_LETTER = { tank = 'T', healer = 'H', dps = 'D' }
V.ROLE_NAME = { tank = 'Tank', healer = 'Healer', dps = 'DPS' }
V.ROLE_COLOR = { tank = '#7fb8e8', healer = '#6fd8a8', dps = '#e8846a' }
V.COLORS = {
  open = '#2a2128',
  text = '#d6c9ae',
  dim = '#8c8070',
  gold = '#f6cf72',
  error = '#e05a3a',
  ok = '#6fd86f',
}

local function num(v) return tonumber(v) or 0 end

-- the role names and colours the server sent (init.roles), on top of the defaults
function V.setRoles(roles)
  for _, r in ipairs(roles or {}) do
    if type(r) == 'table' and r.k then
      V.ROLE_NAME[r.k] = r.n or V.ROLE_NAME[r.k] or r.k
      V.ROLE_COLOR[r.k] = r.c or V.ROLE_COLOR[r.k]
      V.ROLE_LETTER[r.k] = V.ROLE_LETTER[r.k] or tostring(r.n or r.k):sub(1, 1):upper()
    end
  end
end

function V.roleName(role) return V.ROLE_NAME[role] or tostring(role or '?') end
function V.roleColor(role) return V.ROLE_COLOR[role] or V.COLORS.text end
function V.roleLetter(role) return V.ROLE_LETTER[role] or '?' end

-- 3725 -> "1h 02m", 125 -> "2m", 45 -> "45s"
function V.timeLeft(seconds)
  seconds = math.max(0, math.floor(num(seconds)))
  local h, m = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
  if h > 0 then return string.format('%dh %02dm', h, m) end
  if m > 0 then return string.format('%dm', m) end
  return string.format('%ds', seconds)
end

function V.ago(seconds)
  seconds = math.max(0, math.floor(num(seconds)))
  if seconds < 60 then return tr('just now') end
  if seconds < 3600 then return tr('%dm ago', math.floor(seconds / 60)) end
  return tr('%dh ago', math.floor(seconds / 3600))
end

function V.badgeText(n)
  n = math.floor(num(n))
  if n <= 0 then return '' end
  if n > 9 then return '9+' end
  return tostring(n)
end

-- the slots of a row: the members first (leader, party, listing members, in that order), then the open slots by role
-- -> list of {role, filled, name, level, voc, st}
function V.slots(row)
  local out = {}
  if type(row) ~= 'table' then return out end
  for _, m in ipairs(row.comp or {}) do
    out[#out + 1] = { role = m.r, filled = true, name = m.n, level = m.lv, voc = m.vn, st = m.st, mt = m.mt }
  end
  for _, r in ipairs(V.ROLE_ORDER) do
    for _ = 1, num(row.open and row.open[r]) do
      out[#out + 1] = { role = r, filled = false }
    end
  end
  return out
end

function V.openTotal(row)
  local total = 0
  for _, r in ipairs(V.ROLE_ORDER) do total = total + num(row and row.open and row.open[r]) end
  return total
end

-- "Needs 1 Healer, 2 DPS" or "Full"
function V.openText(row)
  local parts = {}
  for _, r in ipairs(V.ROLE_ORDER) do
    local n = num(row and row.open and row.open[r])
    if n > 0 then parts[#parts + 1] = string.format('%d %s', n, V.roleName(r)) end
  end
  if #parts == 0 then return 'Full' end
  return 'Needs ' .. table.concat(parts, ', ')
end

-- "Brannoc, level 400 Juggernaut (Tank)" lines of the composition, for the row tooltip
function V.compTooltip(row)
  local lines = {}
  for _, s in ipairs(V.slots(row)) do
    if s.filled then
      local mark = ''
      if s.st == 'leader' then mark = ' - leader'
      elseif s.st == 'invited' then mark = ' - invited' end
      if V.mentorTag(s.mt) then mark = mark .. ' - ' .. V.mentorTag(s.mt) end
      lines[#lines + 1] = string.format('%s, level %d %s (%s)%s', tostring(s.name or '?'), num(s.level),
        tostring(s.voc or ''), V.roleName(s.role), mark)
    else
      lines[#lines + 1] = string.format('Open: %s', V.roleName(s.role))
    end
  end
  return table.concat(lines, '\n')
end

-- the roles of `my` (what the viewer's class fills) that are open in the row
function V.applyRoles(row, my)
  local out = {}
  for _, r in ipairs(my or {}) do
    if num(row and row.open and row.open[r]) > 0 then out[#out + 1] = r end
  end
  return out
end

-- can the viewer apply? -> true | false, reason text (the server checks again)
function V.canApply(row, my, level)
  if type(row) ~= 'table' then return false, 'Gone' end
  if row.mine then return false, tr('Your group') end
  if row.ap then return false, 'Applied' end
  if num(level) < num(row.ml) then return false, string.format('Level %d+', num(row.ml)) end
  if #V.applyRoles(row, my) == 0 then return false, tr('No open role for you') end
  return true
end

-- the rows the filters keep: f = {a = activity key or '', role = role key or '', fits = bool}, `level` the viewer's.
-- Own listing first, then the ones applied to, then the rest in the server's order (newest first).
function V.filter(rows, f, level)
  f = f or {}
  local mine, applied, rest = {}, {}, {}
  for _, row in ipairs(rows or {}) do
    local keep = true
    if not row.mine then
      if f.a and f.a ~= '' and row.a ~= f.a then keep = false end
      if keep and f.role and f.role ~= '' and num(row.open and row.open[f.role]) <= 0 and row.ap ~= f.role then keep = false end
      if keep and f.fits and num(level) < num(row.ml) then keep = false end
    end
    if keep then
      if row.mine then mine[#mine + 1] = row
      elseif row.ap then applied[#applied + 1] = row
      else rest[#rest + 1] = row end
    end
  end
  local out = {}
  for _, list in ipairs({ mine, applied, rest }) do
    for _, row in ipairs(list) do out[#out + 1] = row end
  end
  return out
end

-- the mentor tag of a character (server mentor.lua ChaosMentor.tagOf): "mentor" / "seeking"
V.MENTOR_TAG = { mentor = 'Mentoring', seeking = 'Looking for mentor' }
function V.mentorTag(mt) return V.MENTOR_TAG[mt or ''] end

-- the sub line of a row: "Brannoc - Lv 300+ - 52m left"
function V.subLine(row, elapsed)
  local parts = { tostring(row.ld or '?') }
  if V.mentorTag(row.mt) then parts[#parts + 1] = V.mentorTag(row.mt) end
  if num(row.ml) > 1 then parts[#parts + 1] = string.format('Lv %d+', num(row.ml)) end
  parts[#parts + 1] = V.timeLeft(num(row.left) - num(elapsed)) .. ' left'
  if row.season then parts[#parts + 1] = 'Season' end
  return table.concat(parts, '  -  ')
end

function V.activityOf(acts, key)
  for _, a in ipairs(acts or {}) do
    if a.k == key then return a end
  end
  return nil
end

-- which part of the form an activity uses: 'range' | 'targets' | 'title' | 'none'
function V.formKind(act)
  if type(act) ~= 'table' then return 'none' end
  if act.range then return 'range' end
  if act.targets and #act.targets > 0 then return 'targets' end
  if act.title then return 'title' end
  return 'none'
end

local function int(v)
  local n = tonumber(v)
  if not n or n ~= n then return nil end
  return math.floor(n)
end

-- the post input from the form's values (texts and combo data); clamps ranges into the activity's bounds
-- f = {a, lo, hi, t, title, tank, healer, dps, minLevel, note, exp, role, auto}
function V.postInput(acts, f)
  local act = V.activityOf(acts, f.a)
  local input = { a = f.a, role = f.role, exp = int(f.exp), note = tostring(f.note or ''), auto = f.auto and true or false,
    want = { tank = int(f.tank) or 0, healer = int(f.healer) or 0, dps = int(f.dps) or 0 },
    minLevel = math.max(1, int(f.minLevel) or 1) }
  local kind = V.formKind(act)
  if kind == 'range' then
    local lo = int(f.lo) or act.range.min
    local hi = int(f.hi) or lo
    lo = math.max(act.range.min, math.min(act.range.max, lo))
    hi = math.max(lo, math.min(act.range.max, hi))
    input.lo, input.hi = lo, hi
  elseif kind == 'targets' then
    input.t = int(f.t) or 0
  elseif kind == 'title' then
    input.title = tostring(f.title or '')
  end
  return input
end

-- the size and wanted caps of an activity (server K.buildActivities: max, per; a raid holds 15), with the init limits
-- (lim.party, lim.perRole) for a server that does not send them -> {max, per = {tank, healer, dps}}
function V.limits(act, lim)
  lim = type(lim) == 'table' and lim or {}
  local out = { max = math.floor(num(act and act.max) > 0 and num(act.max) or (num(lim.party) > 0 and num(lim.party) or 10)), per = {} }
  for _, r in ipairs(V.ROLE_ORDER) do
    local n = act and act.per and tonumber(act.per[r])
    out.per[r] = math.floor(n or (num(lim.perRole) > 0 and num(lim.perRole) or 6))
  end
  return out
end

-- the grid of n slot boxes, at most maxCols wide, rows balanced (15 -> 8 + 7, 10 -> one row) -> cols, rows
function V.slotGrid(n, maxCols)
  n, maxCols = math.max(1, math.floor(num(n))), math.max(1, math.floor(num(maxCols) > 0 and num(maxCols) or 10))
  local rows = math.ceil(n / maxCols)
  return math.ceil(n / rows), rows
end

-- the total size of the group the form describes (leader + wanted)
function V.formSize(f)
  return 1 + (int(f.tank) or 0) + (int(f.healer) or 0) + (int(f.dps) or 0)
end

-- "Queued as DPS (any activity) - 2m" for the quick-join line
function V.queueText(q, acts, elapsed)
  if type(q) ~= 'table' then return '' end
  local act = q.a and V.activityOf(acts, q.a)
  local what = act and act.n or tr('any activity')
  local since = num(q.since) + num(elapsed)
  return tr('Queued as %s (%s) - %s', V.roleName(q.r), what, since < 60 and tr('just now') or V.timeLeft(since))
end

-- the applicant line: "Seris  Lv 350 Illusionist"
function V.applicantLine(app)
  local tag = V.mentorTag(app.mt)
  return string.format('%s  Lv %d %s', tostring(app.n or '?'), num(app.lv), tostring(app.vn or '')) .. (tag and ('  (' .. tag .. ')') or '')
end
