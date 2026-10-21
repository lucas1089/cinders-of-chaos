-- Names over tall looks (client/MANIFEST.md "Name over tall looks"): the pure part. info_lifts.lua (generated from
-- the pair by client/tools/sprites/gen_info_lift.py) lists per look type how many sprite pixels the name and bars of
-- a player or an NPC wearing it go up; the engine (base patch 0111) adds that to the anchor before the map's stretch.
InfoLiftCore = {}
local M = InfoLiftCore

M.MAX = 96 -- the engine's cap (Creature::setInformationLift)

-- the valid {look, lift} pairs of a generated table, sorted by look (the md5 field and bad rows left out)
function M.entries(data)
  local out = {}
  if type(data) ~= 'table' then return out end
  for look, lift in pairs(data) do
    if type(look) == 'number' and look >= 1 and look == math.floor(look) and type(lift) == 'number' and lift > 0 then
      out[#out + 1] = { look, math.min(M.MAX, math.floor(lift)) }
    end
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end

-- hand every entry to set(look, lift); returns how many
function M.apply(data, set)
  local list = M.entries(data)
  for _, e in ipairs(list) do set(e[1], e[2]) end
  return #list
end

-- the lift of one look (0 when it has none)
function M.liftOf(data, look)
  local v = type(data) == 'table' and data[look]
  return type(v) == 'number' and v > 0 and math.min(M.MAX, math.floor(v)) or 0
end

return M
