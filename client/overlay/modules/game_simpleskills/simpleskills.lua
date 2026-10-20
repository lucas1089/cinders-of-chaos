-- The skills window with one "Melee" row (rules: simpleskills_logic.lua; server/README.md "One melee skill").
-- The base module game_skills fills the rows skillId0 .. skillId6 (fist, club, sword, axe, distance, shielding, fishing)
-- from the game; this module runs after its handlers: it hides the club and axe rows (and the fist row but for the
-- Monk line), turns the sword row into "Melee" with the best of the three, renames the distance row "Ranged" and the
-- magic level row "Magic / Wand". terminate puts everything back.

local L = ChaosSimpleSkills

local ROW = { fist = 'skillId0', club = 'skillId1', sword = 'skillId2', axe = 'skillId3', distance = 'skillId4' }
local labels = {}  -- row id -> the text it had before
local hiddenNow = {}

local function window()
  local skills = modules.game_skills
  local w = skills and rawget(skills, 'skillsWindow')
  return w
end

local function row(id)
  local w = window()
  return w and w:recursiveGetChildById(id) or nil
end

-- the widget that holds a row's name (the first child that is not the value or the percent bar)
local function nameLabel(r)
  for _, child in ipairs(r:getChildren()) do
    local id = child:getId()
    if id ~= 'value' and id ~= 'percent' and child.setText then
      return child
    end
  end
  return nil
end

local function rename(rowId, text)
  local r = row(rowId)
  local label = r and nameLabel(r)
  if not label then
    return
  end
  if labels[rowId] == nil then
    labels[rowId] = label:getText()
  end
  if label:getText() ~= text then
    label:setText(text)
  end
end

local function restoreNames()
  for rowId, text in pairs(labels) do
    local r = row(rowId)
    local label = r and nameLabel(r)
    if label then
      label:setText(text)
    end
  end
  labels = {}
end

local function setHidden(name, hidden)
  local r = row(ROW[name])
  if r and r:isVisible() ~= not hidden then
    r:setVisible(not hidden)
  end
end

local function localPlayer()
  return g_game.getLocalPlayer()
end

local function skillOf(player, name)
  local id = L.SKILL[name]
  return { level = player:getSkillLevel(id), base = player:getSkillBaseLevel(id), percent = player:getSkillLevelPercent(id) }
end

local function fitWindow()
  local skills = modules.game_skills
  local w = window()
  if w and skills and type(rawget(skills, 'getContentPanelHeight')) == 'function' then
    w:setContentMaximumHeight(math.max(125, skills.getContentPanelHeight() + 6))
  end
end

local function refresh()
  local player = localPlayer()
  if not player or not window() then
    return
  end
  local voc = player:getVocation()
  local hidden = {}
  for _, name in ipairs(L.hidden(voc)) do
    hidden[name] = true
    setHidden(name, true)
  end
  if not hidden.fist then
    setHidden('fist', false)
  end
  rename(ROW.sword, tr('Melee'))
  rename(ROW.distance, tr('Ranged'))
  local magic = row('magiclevel')
  local magicName = magic and nameLabel(magic)
  if magicName then
    if labels.magiclevel == nil then
      labels.magiclevel = magicName:getText()
    end
    magicName:setText(tr('Magic / Wand'))
  end

  local best = L.melee({ sword = skillOf(player, 'sword'), club = skillOf(player, 'club'), axe = skillOf(player, 'axe') })
  local r = row(ROW.sword)
  if r then
    local value = r:getChildById('value')
    if value then
      value:setText(formatShortNumber and formatShortNumber(best.level) or tostring(best.level))
      value:setColor(best.level > best.base and '#44ad25' or '#bbbbbb')
    end
    local bar = r:getChildById('percent')
    if bar then
      bar:setPercent(best.percent)
      bar:setTooltip(tr('%s: %d\n%d%% to the next level', tr('Melee'), best.level, best.percent))
    end
    r:setTooltip(tr('Swords, axes and clubs share one skill: the best of the three.'))
  end
  fitWindow()
end

local function onSkillChange(localPlayerRef, id)
  if id >= 0 and id <= 4 then
    refresh()
  end
end

local function onGameStart()
  scheduleEvent(refresh, 100) -- after the base module has filled the rows
end

function init()
  connect(LocalPlayer, { onSkillChange = onSkillChange, onBaseSkillChange = onSkillChange })
  connect(g_game, { onGameStart = onGameStart })
  if g_game.isOnline() then
    refresh()
  end
end

function terminate()
  disconnect(LocalPlayer, { onSkillChange = onSkillChange, onBaseSkillChange = onSkillChange })
  disconnect(g_game, { onGameStart = onGameStart })
  for _, name in ipairs({ 'fist', 'club', 'axe' }) do
    setHidden(name, false)
  end
  restoreNames()
  fitWindow()
end
