-- Paragon panel maths (no client API, tested by paragonmath_test.lua).
-- `state` is the server's paragonState: {unlocked, total, spent, free, categories = [{stats = [{key, perPoint,
-- maxPoints, points}]}]}; `pending` is {statKey = points added in the panel and not applied yet}.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
ParagonMath = {}

function ParagonMath.pendingSum(pending)
  local n = 0
  for _, v in pairs(pending or {}) do
    n = n + v
  end
  return n
end

function ParagonMath.free(state, pending)
  return math.max(0, ((state and state.free) or 0) - ParagonMath.pendingSum(pending))
end

-- points a stat would have after applying
function ParagonMath.points(stat, pending)
  return (stat.points or 0) + ((pending and pending[stat.key]) or 0)
end

function ParagonMath.canAdd(state, pending, stat)
  return state ~= nil and state.unlocked == true and ParagonMath.free(state, pending) > 0
    and ParagonMath.points(stat, pending) < stat.maxPoints
end

function ParagonMath.canRemove(pending, stat)
  return ((pending and pending[stat.key]) or 0) > 0
end

-- add up to n points (limited by the free points and the stat's room); returns how many were added
function ParagonMath.add(state, pending, stat, n)
  if not ParagonMath.canAdd(state, pending, stat) then
    return 0
  end
  local room = stat.maxPoints - ParagonMath.points(stat, pending)
  local k = math.min(n or 1, room, ParagonMath.free(state, pending))
  pending[stat.key] = (pending[stat.key] or 0) + k
  return k
end

-- remove up to n pending points (applied points only go with a reset); returns how many were removed
function ParagonMath.remove(pending, stat, n)
  local have = (pending and pending[stat.key]) or 0
  local k = math.min(n or 1, have)
  if k <= 0 then
    return 0
  end
  pending[stat.key] = have - k > 0 and have - k or nil
  return k
end

-- the absolute allocation sent with paragonApply ({} when nothing is pending)
function ParagonMath.alloc(state, pending)
  local out = {}
  for _, category in ipairs((state and state.categories) or {}) do
    for _, stat in ipairs(category.stats or {}) do
      if ((pending and pending[stat.key]) or 0) > 0 then
        out[stat.key] = ParagonMath.points(stat, pending)
      end
    end
  end
  return out
end

-- 0.25 -> "0.25", 1.5 -> "1.5", 20 -> "20"
function ParagonMath.fmt(v)
  local s = string.format("%.2f", v or 0)
  s = s:gsub("0+$", ""):gsub("%.$", "")
  return s
end

function ParagonMath.value(stat, points)
  return stat.perPoint * math.max(0, math.min(points or 0, stat.maxPoints))
end

-- "+1.5% / 20%"
function ParagonMath.valueText(stat, points)
  return "+" .. ParagonMath.fmt(ParagonMath.value(stat, points)) .. "% / " .. ParagonMath.fmt(stat.perPoint * stat.maxPoints) .. "%"
end

-- lines of the "Info & Bonuses" list: the applied Paragon bonuses
function ParagonMath.bonusLines(state)
  local lines = {}
  for _, category in ipairs((state and state.categories) or {}) do
    for _, stat in ipairs(category.stats or {}) do
      if (stat.points or 0) > 0 then
        table.insert(lines, tr("+%s%% %s (Paragon).", ParagonMath.fmt(ParagonMath.value(stat, stat.points)), stat.name))
      end
    end
  end
  return lines
end
