-- Paragon panel of the passive tree window. The server (server/data/scripts/chaos/paragon.lua) owns the rules and
-- validates everything; this panel shows its paragonState and sends the allocation:
--   paragonRequest -> paragonState, paragonApply {alloc = {statKey = points}} -> paragonState, paragonReset
-- Maths in paragonmath.lua. The window, its +/- rows and the locked state are in paragon.otui (ornate skin styles).
local paragonWindow = nil
local paragonState = nil
local paragonPending = {}
local resetBox = nil

function getParagonState()
  return paragonState
end

local function statRows()
  local list = {}
  if not paragonWindow then
    return list
  end
  for _, category in ipairs((paragonState and paragonState.categories) or {}) do
    for _, stat in ipairs(category.stats or {}) do
      local row = paragonWindow:recursiveGetChildById('stat_' .. stat.key)
      if row then
        table.insert(list, {row = row, stat = stat})
      end
    end
  end
  return list
end

local function refreshParagon()
  if not paragonWindow or not paragonState then
    return
  end
  local s = paragonState
  local locked = not s.unlocked
  paragonWindow.categories:setVisible(not locked)
  paragonWindow.lockedPanel:setVisible(locked)
  paragonWindow.applyButton:setEnabled(not locked and ParagonMath.pendingSum(paragonPending) > 0)
  paragonWindow.resetButton:setEnabled(not locked and (s.spent or 0) > 0)
  paragonWindow.resetButton:setTooltip(tr('Refund every Paragon point for %d gold (level x 250).', s.resetCost or 0))
  if locked then
    paragonWindow.summary:setText(tr('Level %d', s.level or 0))
    paragonWindow.lockedPanel.lockedTitle:setText(tr('Unlocks at level %d', s.startLevel or 1000))
    paragonWindow.lockedPanel.lockedText:setText(tr(
      'Every level above %d gives one Paragon point for small, capped bonuses: damage, health, speed, gold and item find.',
      s.startLevel or 1000))
    return
  end
  local pending = ParagonMath.pendingSum(paragonPending)
  paragonWindow.summary:setColoredText({
    'Available: ', '#d6c9ae', tostring(ParagonMath.free(s, paragonPending)), '#f6cf72',
    '     Spent: ', '#d6c9ae', tostring((s.spent or 0) + pending) .. (pending > 0 and (' (+' .. pending .. ')') or ''), '#f6cf72',
    '     Total: ', '#d6c9ae', tostring(s.total or 0), '#f6cf72'
  })
  for _, entry in ipairs(statRows()) do
    local row, stat = entry.row, entry.stat
    local points = ParagonMath.points(stat, paragonPending)
    local isPending = ParagonMath.canRemove(paragonPending, stat)
    row.statPoints:setText(points .. '/' .. stat.maxPoints)
    row.statPoints:setColor(isPending and '#f6cf72' or '#d6c9ae')
    row.statValue:setText(ParagonMath.valueText(stat, points))
    row.statValue:setColor(points >= stat.maxPoints and '#e8b84a' or (isPending and '#f6cf72' or '#d6c9ae'))
    row.plusButton:setEnabled(ParagonMath.canAdd(s, paragonPending, stat))
    row.minusButton:setEnabled(isPending)
  end
end

local function buildRows()
  local container = paragonWindow.categories
  container:destroyChildren()
  for _, category in ipairs((paragonState and paragonState.categories) or {}) do
    local panel = g_ui.createWidget('ParagonCategory', container)
    panel:setId('cat_' .. category.key)
    panel.catTitle:setText(category.name)
    for _, stat in ipairs(category.stats or {}) do
      local row = g_ui.createWidget('ParagonStatRow', panel.catRows)
      row:setId('stat_' .. stat.key)
      row.statKey = stat.key
      row.statName:setText(stat.name)
      local tip = tr('%s\n+%s%% per point, up to +%s%% (%d points).', stat.desc or stat.name,
        ParagonMath.fmt(stat.perPoint), ParagonMath.fmt(stat.perPoint * stat.maxPoints), stat.maxPoints)
      row:setTooltip(tip)
      row.statName:setTooltip(tip)
      row.plusButton.onClick = function()
        local cur = findStat(row.statKey)
        if cur then
          ParagonMath.add(paragonState, paragonPending, cur, g_keyboard.isShiftPressed() and 5 or 1)
          refreshParagon()
        end
      end
      row.minusButton.onClick = function()
        local cur = findStat(row.statKey)
        if cur then
          ParagonMath.remove(paragonPending, cur, g_keyboard.isShiftPressed() and 5 or 1)
          refreshParagon()
        end
      end
    end
  end
  paragonWindow.builtFor = paragonState and #(paragonState.categories or {}) or 0
end

function findStat(key)
  for _, category in ipairs((paragonState and paragonState.categories) or {}) do
    for _, stat in ipairs(category.stats or {}) do
      if stat.key == key then
        return stat
      end
    end
  end
  return nil
end

-- server -> client paragonState
function onParagonState(data)
  if type(data) ~= 'table' then
    return
  end
  paragonState = data
  paragonPending = {}
  if paragonWindow then
    if not paragonWindow.builtFor or paragonWindow.builtFor == 0 then
      buildRows()
    end
    refreshParagon()
  end
  local tree = getTreeWindow()
  if tree and tree:isVisible() then
    calculateStats()
  end
end

function openParagon()
  local tree = getTreeWindow()
  if not tree then
    return
  end
  if not paragonWindow then
    paragonWindow = g_ui.loadUI('paragon', tree)
  end
  if paragonState and (not paragonWindow.builtFor or paragonWindow.builtFor == 0) then
    buildRows()
  end
  paragonWindow:show()
  paragonWindow:raise()
  paragonWindow:focus()
  refreshParagon()
  sendAction('paragonRequest')
end

function closeParagon()
  if paragonWindow then
    paragonWindow:hide()
  end
  paragonPending = {}
  if resetBox then
    resetBox:destroy()
    resetBox = nil
  end
end

function toggleParagon()
  if paragonWindow and paragonWindow:isVisible() then
    closeParagon()
  else
    openParagon()
  end
end

function applyParagon()
  if not paragonState or ParagonMath.pendingSum(paragonPending) <= 0 then
    return
  end
  sendAction('paragonApply', {alloc = ParagonMath.alloc(paragonState, paragonPending)})
end

function resetParagon()
  if not paragonState or (paragonState.spent or 0) <= 0 then
    return
  end
  if resetBox then
    resetBox:destroy()
    resetBox = nil
  end
  local function close()
    if resetBox then
      resetBox:destroy()
      resetBox = nil
    end
  end
  local function ok()
    sendAction('paragonReset')
    close()
  end
  local cost = paragonState.resetCost or 0 -- the server's price (respec.lua)
  resetBox = displayGeneralBox(tr('Reset Paragon'), tr('Refund all %d Paragon points for %s? Proceed?',
    paragonState.spent or 0, cost > 0 and (tr('%s gold coins', formatGold(cost))) or tr('free')), {
      {text = tr('Ok'), callback = ok},
      {text = tr('Cancel'), callback = close},
      anchor = AnchorHorizontalCenter
    }, ok, close)
end

function destroyParagon()
  closeParagon()
  if paragonWindow then
    paragonWindow:destroy()
    paragonWindow = nil
  end
  paragonState = nil
  paragonPending = {}
end
