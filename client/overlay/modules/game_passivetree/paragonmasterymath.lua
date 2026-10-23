-- Paragon Mastery maths (O146), no client API, tested by paragonmasterymath_test.lua. Extends ParagonMath (paragonmath.lua).
-- The endless sink for Paragon points: `state.mastery = {maxRanks, rows = [{key, name, desc, ranks, value, next}]}`,
-- `state.exchange = {ratio, treeFree, converted}` (server/data/scripts/chaos/paragon.lua). A rank costs one free Paragon
-- point; the server owns the rules and validates every request.
ParagonMath = ParagonMath or {}
local M = ParagonMath

-- 3 decimals, trailing zeros dropped: 0.0167 -> "0.017"
function M.fmt3(v)
  local s = string.format("%.3f", v or 0)
  s = s:gsub("0+$", ""):gsub("%.$", "")
  return s
end

-- ranks one click buys: n, limited by the free points and the room under the rank limit (0 when locked)
function M.masteryBuy(state, row, n)
  if not state or state.unlocked ~= true or not state.mastery or not row then
    return 0
  end
  local room = (state.mastery.maxRanks or 0) - (row.ranks or 0)
  return math.max(0, math.min(n or 1, room, state.free or 0))
end

-- "+11.67%"
function M.masteryValueText(row)
  return "+" .. M.fmt(row.value) .. "%"
end

-- "+0.017%"
function M.masteryNextText(row)
  return "+" .. M.fmt3(row.next) .. "%"
end

-- free tree points that can be exchanged (0 when the exchange is not offered)
function M.exchangeable(state)
  local x = state and state.unlocked and state.exchange
  return x and math.max(0, math.floor(x.treeFree or 0)) or 0
end

-- Paragon points an exchange of n tree points gives
function M.exchangeGain(state, n)
  local x = state and state.exchange
  return math.max(0, math.floor(n or 0)) * ((x and x.ratio) or 1)
end

-- lines of the "Info & Bonuses" list for the masteries with ranks
function M.masteryLines(state)
  local lines = {}
  for _, row in ipairs((state and state.mastery and state.mastery.rows) or {}) do
    if (row.ranks or 0) > 0 then
      table.insert(lines, string.format("+%s%% %s (%d ranks).", M.fmt(row.value), row.name, row.ranks))
    end
  end
  return lines
end
