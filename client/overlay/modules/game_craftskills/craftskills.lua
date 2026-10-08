-- Profession skills in the skills window.
-- The server sends seven profession skills after fishing in the skills packet; the client reads them
-- when the 1098 profile enables GameChaosCraftingSkills (base patch 0012) and calls
-- g_game.onCraftingSkill(index, level, base, percent) for each, index 0..6 in this order:
local NAMES = { 'Crafting', 'Woodcutting', 'Mining', 'Herbalist', 'Armorsmith', 'Weaponsmith', 'Jewelsmith' }

local rows = {}     -- index -> row widget
local widgets = {}  -- everything we added, to remove on unload
local values = {}   -- index -> {level, base, percent}

local function contentsPanel()
  local skills = modules.game_skills
  local window = skills and rawget(skills, 'skillsWindow')
  return window, window and window:recursiveGetChildById('contentsPanel')
end

local function fitWindow()
  local skills = modules.game_skills
  local window = contentsPanel()
  if window and skills and type(rawget(skills, 'getContentPanelHeight')) == 'function' then
    window:setContentMaximumHeight(math.max(125, skills.getContentPanelHeight() + 6))
  end
end

local function paint(index)
  local row, v = rows[index], values[index]
  if not row or not v then
    return
  end
  local value = row:getChildById('value')
  value:setText(tostring(v.level))
  if v.level > v.base then
    value:setColor('#44ad25')
    row:setTooltip(string.format('%s: %d (base %d)\n%d%% to the next level', NAMES[index + 1], v.level, v.base, v.percent))
  else
    value:setColor('#c0c0c0')
    row:setTooltip(string.format('%s: %d\n%d%% to the next level', NAMES[index + 1], v.level, v.percent))
  end
  row:getChildById('percent'):setPercent(v.percent)
end

local function build()
  local window, panel = contentsPanel()
  if not panel or #widgets > 0 then
    return
  end
  local separator = g_ui.createWidget('HorizontalSeparator', panel)
  separator:setId('craftSeparator')
  separator:setMarginTop(7)
  separator:setMarginBottom(5)
  widgets[#widgets + 1] = separator

  local title = g_ui.createWidget('SkillButton', panel)
  title:setId('craftTitle')
  title:setHeight(15)
  local titleLabel = g_ui.createWidget('SkillNameLabel', title)
  titleLabel:setText(tr('Professions'))
  titleLabel:setColor('#e8b84a')
  widgets[#widgets + 1] = title

  for i, name in ipairs(NAMES) do
    local row = g_ui.createWidget('SkillButton', panel)
    row:setId('craftSkill' .. (i - 1))
    row:setMarginTop(5)
    local label = g_ui.createWidget('SkillNameLabel', row)
    label:setText(tr(name))
    local value = g_ui.createWidget('SkillValueLabel', row)
    value:setText('0')
    local bar = g_ui.createWidget('SkillPercentPanel', row)
    bar:setPercent(0)
    rows[i - 1] = row
    widgets[#widgets + 1] = row
    paint(i - 1)
  end
  fitWindow()
end

local function onCraftingSkill(index, level, base, percent)
  values[index] = { level = level, base = base, percent = percent }
  if not rows[index] then
    build()
  end
  paint(index)
end

local function onGameEnd()
  values = {}
end

function init()
  -- pushFront: signalcall stops at the first handler that returns a value
  connect(g_game, { onCraftingSkill = onCraftingSkill, onGameEnd = onGameEnd }, true)
  build()
end

function terminate()
  disconnect(g_game, { onCraftingSkill = onCraftingSkill, onGameEnd = onGameEnd })
  for _, w in ipairs(widgets) do
    if not w:isDestroyed() then
      w:destroy()
    end
  end
  widgets, rows = {}, {}
  fitWindow()
end
