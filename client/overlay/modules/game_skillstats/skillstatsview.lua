-- The combat stat rows below the skill bars of the Skills window (view rules; widget code: skillstats.lua; tests:
-- skillstatsview_test.lua). The base module has the rows from a newer protocol and kept them at 0, because a 10.98 server
-- never sends their packet. The Chaos server sends the numbers on extended opcode 119 (data/scripts/chaos/combat_stats.lua):
--   stats {damage?, attack?, defense, armor, mitigation}   mitigation is a share 0 .. 1
-- What each row shows:
--   no message yet (an older server, or before the first one)  "-" in the five rows
--   a number                                                   the number, short (15.3k), green when above 0
--   damage / attack absent (a wand, a rod, bare hands)         the row is hidden: those hit by magic level and spells
--   mantra                                                     always hidden: the game has no Mantra stat, its elemental
--                                                              protection has a row of its own per element
-- Pure Lua, no client calls except an optional short-number function passed in.

ChaosSkillStatsView = ChaosSkillStatsView or {}
local V = ChaosSkillStatsView

V.ROWS = { 'damage', 'attack', 'defense', 'armor', 'mitigation', 'mantra' }
V.GREEN = '#44ad25'
V.GREY = '#bbbbbb'

local function finite(v)
  return type(v) == 'number' and v == v and v > -math.huge and v < math.huge
end

-- a whole number from a message field, or nil
function V.number(v)
  v = tonumber(v)
  if not finite(v) then return nil end
  return math.floor(v + 0.5)
end

function V.percent(share)
  share = tonumber(share)
  if not finite(share) then return nil end
  if share < 0 then share = 0 elseif share > 1 then share = 1 end
  return share
end

local function plain(n)
  return tostring(n)
end

-- data = the stats message's data, or nil while none came. short = formatShortNumber or nil.
-- Returns { [row] = { visible = bool, text = string, color = string } } for every row of V.ROWS.
function V.build(data, short)
  short = short or plain
  local out = { mantra = { visible = false, text = '-', color = V.GREY } }
  local function row(name, n, formatter)
    if n == nil then
      out[name] = { visible = true, text = '-', color = V.GREY }
    else
      out[name] = { visible = true, text = formatter(n), color = n > 0 and V.GREEN or V.GREY }
    end
  end
  if type(data) ~= 'table' then
    for _, name in ipairs({ 'damage', 'attack', 'defense', 'armor', 'mitigation' }) do
      row(name, nil)
    end
    return out
  end
  local damage, attack = V.number(data.damage), V.number(data.attack)
  if damage and damage > 0 then
    row('damage', damage, short)
  else
    out.damage = { visible = false, text = '-', color = V.GREY }
  end
  if attack and attack > 0 then
    row('attack', attack, short)
  else
    out.attack = { visible = false, text = '-', color = V.GREY }
  end
  row('defense', V.number(data.defense), short)
  row('armor', V.number(data.armor), short)
  local share = V.percent(data.mitigation)
  if share == nil then
    row('mitigation', nil)
  else
    out.mitigation = { visible = true, text = string.format('+%.1f%%', share * 100), color = share > 0 and V.GREEN or V.GREY }
  end
  return out
end

-- Row names too long for the narrow Skills column (V31, seen in a client 2026-11-27: "Damage/Healing" ran into its
-- number and "Offline Training" into its 12:00). A row whose full name and value do not fit side by side shows the short
-- name; the full name goes to the tooltip. row id -> { value label id, short name }.
V.SHORT_NAMES = {
  damageHealing = { value = 'damageHealingLabel', short = 'Dmg/Heal' },
  offlineTraining = { value = 'value', short = 'Offline' },
}
V.NAME_GAP = 4 -- pixels kept free between the name and the number

-- the name, the value and their margins fit inside the row (widths in pixels); a row not laid out yet (0) is left alone
function V.nameFits(nameWidth, valueWidth, rowWidth, margins)
  rowWidth = tonumber(rowWidth) or 0
  if rowWidth <= 0 then return true end
  return (tonumber(nameWidth) or 0) + (tonumber(valueWidth) or 0) + (tonumber(margins) or 0) + V.NAME_GAP <= rowWidth
end
