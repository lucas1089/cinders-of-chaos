-- Trending builds of the passive tree window (O409, "Builds em alta"): the most played keystone builds of every class
-- from the server's daily snapshot (server/data/scripts/chaos/build_trends.lua). Opened from the Build Code panel.
-- Import pastes the build's code into the Build Code panel and runs its Import: the server's preview, class and respec
-- rules decide what can be applied, as for any pasted code. Texts: trendsview.lua. No character name is ever shown.
--   buildTrends {class?} -> buildTrends {class, className, at, total, classes, rows}
local function tr(s, ...) local g = (rawget(_G, 'tr') or (rawget(_G, 'ChaosLocale') or {}).tr) if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
ChaosTreeHandlers = ChaosTreeHandlers or {}
local trendsWindow = nil
local last = nil -- the last buildTrends message
local shown = {}  -- the rows on screen

local function alive()
  if trendsWindow and trendsWindow.isDestroyed and trendsWindow:isDestroyed() then
    trendsWindow = nil -- the tree window was destroyed (logout)
  end
  return trendsWindow
end

local function child(id)
  alive()
  return trendsWindow and trendsWindow:recursiveGetChildById(id)
end

local function render()
  if not alive() then
    return
  end
  local data = last or {}
  local label = child('classLabel')
  if label then
    label:setText(type(data.className) == 'string' and data.className or tr('Trending Builds'))
  end
  local info = child('info')
  if info then
    info:setText(last and TrendsView.info(data) or tr('Asking the server...'))
  end
  shown = TrendsView.rows(data)
  for i = 1, TrendsView.ROWS do
    local row, text = child('row' .. i), child('rowText' .. i)
    if row then
      row:setVisible(shown[i] ~= nil)
    end
    if text then
      text:setText(shown[i] and TrendsView.rowText(shown[i]) or '')
    end
  end
  local many = type(data.classes) == 'table' and #data.classes > 1
  for _, id in ipairs({'prevButton', 'nextButton'}) do
    local b = child(id)
    if b then
      b:setEnabled(many)
    end
  end
end

local function ask(classKey)
  sendAction('buildTrends', classKey and {class = classKey} or {})
end

function openTrends()
  local tree = getTreeWindow()
  if not tree then
    return
  end
  if not alive() then
    trendsWindow = g_ui.loadUI('trends', tree)
  end
  trendsWindow:show()
  trendsWindow:raise()
  trendsWindow:focus()
  render()
  ask(last and last.class or nil)
end

function closeTrends()
  if alive() then
    trendsWindow:hide()
  end
end

function toggleTrends()
  if alive() and trendsWindow:isVisible() then
    closeTrends()
  else
    openTrends()
  end
end

function stepTrends(dir)
  if not last or type(last.classes) ~= 'table' then
    return
  end
  ask(TrendsView.step(last.classes, last.class, dir))
end

function importTrend(index)
  local row = shown[index]
  local code = TrendsView.importCode(row)
  if not code then
    return
  end
  openBuildShare()
  local share = getTreeWindow() and getTreeWindow():recursiveGetChildById('buildShareWindow')
  local edit = share and share:recursiveGetChildById('codeEdit')
  if not edit then
    return
  end
  edit:setText(code)
  importBuild()
end

ChaosTreeHandlers.buildTrends = function(data)
  if type(data) ~= 'table' then
    return
  end
  last = data
  render()
end
