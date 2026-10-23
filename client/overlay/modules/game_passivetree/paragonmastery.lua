-- Paragon Mastery window (O146): ranks bought with spare Paragon points, and the exchange of free passive tree points.
-- The server (server/data/scripts/chaos/paragon.lua) owns the rules; this window shows paragonState.mastery / .exchange
-- and sends paragonMastery {key, n} and paragonConvert {n}. Maths in paragonmasterymath.lua (tested).
local masteryWindow = nil
local convertBox = nil

local function refresh()
  if not masteryWindow then
    return
  end
  local s = getParagonState and getParagonState()
  if not s or not s.mastery then
    return
  end
  masteryWindow.summary:setColoredText({
    'Available: ', '#d6c9ae', tostring(s.free or 0), '#f6cf72',
    '     Total: ', '#d6c9ae', tostring(s.total or 0), '#f6cf72'
  })
  for _, row in ipairs(s.mastery.rows or {}) do
    local widget = masteryWindow.rows:getChildById('mastery_' .. row.key)
    if widget then
      widget.masteryRanks:setText(tostring(row.ranks or 0))
      widget.masteryValue:setText(ParagonMath.masteryValueText(row))
      widget.masteryNext:setText(tr('%s next rank', ParagonMath.masteryNextText(row)))
      for n, id in pairs({[1] = 'buy1Button', [10] = 'buy10Button', [100] = 'buy100Button'}) do
        widget[id]:setEnabled(ParagonMath.masteryBuy(s, row, n) >= n)
      end
    end
  end
  local can = ParagonMath.exchangeable(s)
  masteryWindow.exchangeButton:setEnabled(can > 0)
  masteryWindow.exchangeLabel:setText(tr('Free passive tree points: %d. Each one becomes %d Paragon point(s), for good. Already exchanged: %d.',
    can, (s.exchange and s.exchange.ratio) or 1, (s.exchange and s.exchange.converted) or 0))
end

local function build()
  local s = getParagonState and getParagonState()
  masteryWindow.rows:destroyChildren()
  for _, row in ipairs((s and s.mastery and s.mastery.rows) or {}) do
    local widget = g_ui.createWidget('ParagonMasteryRow', masteryWindow.rows)
    widget:setId('mastery_' .. row.key)
    widget.masteryName:setText(row.name)
    widget:setTooltip(row.desc or row.name)
    for n, id in pairs({[1] = 'buy1Button', [10] = 'buy10Button', [100] = 'buy100Button'}) do
      widget[id].onClick = function()
        sendAction('paragonMastery', {key = row.key, n = n})
      end
    end
  end
  masteryWindow.builtFor = s and s.mastery and #s.mastery.rows or 0
end

function refreshParagonMastery()
  if masteryWindow and masteryWindow:isVisible() then
    local s = getParagonState and getParagonState()
    if s and s.mastery and (not masteryWindow.builtFor or masteryWindow.builtFor == 0) then
      build()
    end
    refresh()
  end
end

function openParagonMastery()
  local tree = getTreeWindow()
  if not tree then
    return
  end
  if not masteryWindow then
    masteryWindow = g_ui.loadUI('paragonmastery', tree)
  end
  masteryWindow:show()
  masteryWindow:raise()
  masteryWindow:focus()
  local s = getParagonState and getParagonState()
  if s and s.mastery and (not masteryWindow.builtFor or masteryWindow.builtFor == 0) then
    build()
  end
  refresh()
  sendAction('paragonRequest')
end

function closeParagonMastery()
  if masteryWindow then
    masteryWindow:hide()
  end
  if convertBox then
    convertBox:destroy()
    convertBox = nil
  end
end

function toggleParagonMastery()
  if masteryWindow and masteryWindow:isVisible() then
    closeParagonMastery()
  else
    openParagonMastery()
  end
end

function exchangeTreePoints()
  local s = getParagonState and getParagonState()
  local n = ParagonMath.exchangeable(s)
  if n <= 0 then
    return
  end
  if convertBox then
    convertBox:destroy()
    convertBox = nil
  end
  local function close()
    if convertBox then
      convertBox:destroy()
      convertBox = nil
    end
  end
  local function ok()
    sendAction('paragonConvert', {n = n})
    close()
  end
  convertBox = displayGeneralBox(tr('Exchange tree points'), tr(
    'Turn %d free passive tree points into %d Paragon points? This cannot be undone: the points stay Paragon points. Proceed?',
    n, ParagonMath.exchangeGain(s, n)), {
      {text = tr('Ok'), callback = ok},
      {text = tr('Cancel'), callback = close},
      anchor = AnchorHorizontalCenter
    }, ok, close)
end

function destroyParagonMastery()
  closeParagonMastery()
  if masteryWindow then
    masteryWindow:destroy()
    masteryWindow = nil
  end
end
