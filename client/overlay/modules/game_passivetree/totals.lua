-- Totals of the passive tree window (O146): raw against effective stat values (soft caps) and the critical chance and
-- damage including gear. Server: passivetree_totals.lua (statTotals); lines: totalsview.lua.
ChaosTreeHandlers = ChaosTreeHandlers or {}
local totals = nil
local pendingRequest = nil

function getTreeTotals()
  return totals
end

-- the lines of the totals section as {text, color}
function treeTotalsLines()
  return TotalsView.lines(totals)
end

-- ask the server for fresh totals; `delay` (ms) lets a save or Paragon change land first (the server answers once per 300 ms)
function requestTreeTotals(delay)
  if pendingRequest then
    return
  end
  pendingRequest = scheduleEvent(function()
    pendingRequest = nil
    sendAction('statTotals')
  end, delay or 0)
end

ChaosTreeHandlers.statTotals = function(data)
  if type(data) ~= 'table' then
    return
  end
  totals = data
  local tree = getTreeWindow and getTreeWindow()
  if tree and tree:isVisible() then
    calculateStats()
  end
end

function destroyTreeTotals()
  totals = nil
  if pendingRequest then
    removeEvent(pendingRequest)
    pendingRequest = nil
  end
end
