-- Boss passive points in the passive tree window (server: server/data/scripts/chaos/bosspoints.lua, list in
-- bosspoints_config.lua). The server sends bossPoints {got, total, label, bosses = [{id, name, label, done}]} with every
-- sendPoints; this file shows "Boss points 3/10" under the points box, with the bosses (slain or not) as its tooltip.
ChaosTreeHandlers = ChaosTreeHandlers or {}
local bossPointsState = nil

function getBossPointsState()
  return bossPointsState
end

-- the tooltip: the rule, where the kills come from (world boss events, pocket bosses, the other bosses), then every
-- boss slain or not
local function tooltipOf(data)
  local lines = {
    tr('First kill of each major boss: +1 passive point (kept through resets).'),
    tr('Where to get them:'),
    tr('- World bosses: the event every 6 hours (portals by the temples, level 300).'),
    tr('- Pocket bosses: a private copy any time, Adventure > Boss Spawns (daily charges).'),
    tr('- The Trial Warden: win your Ascension Trial (level 100).'),
    tr('- The others: their spawns in Adventure > Boss Spawns.'),
    tr('Your party counts: any kill you helped with gives the point.'),
    '',
  }
  for _, boss in ipairs(type(data.bosses) == 'table' and data.bosses or {}) do
    lines[#lines + 1] = string.format('%s %s', boss.done and '[x]' or '[  ]', tostring(boss.label or boss.name or '?'))
  end
  return table.concat(lines, '\n')
end

local function refreshBossPoints()
  local window = getTreeWindow and getTreeWindow()
  local label = window and window:recursiveGetChildById('bossPoints')
  if not label or not bossPointsState then
    return
  end
  local got, total = tonumber(bossPointsState.got) or 0, tonumber(bossPointsState.total) or 0
  label:setText(bossPointsState.label or tr('Boss points %d/%d', got, total))
  label:setColor(got >= total and total > 0 and '#7fd06a' or '#d8a03a')
  label:setTooltip(tooltipOf(bossPointsState))
  label:setVisible(total > 0)
end

ChaosTreeHandlers.bossPoints = function(data)
  if type(data) ~= 'table' then
    return
  end
  bossPointsState = data
  refreshBossPoints()
end
