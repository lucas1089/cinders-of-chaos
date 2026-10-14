-- The helper's "Auto rotation" button (the glue; the choice is autorotation.lua, the data autorotation_data.lua).
--
-- The helper (mods/game_helper, the base client) is not changed: this module finds its Targeting & Spell Rules panel
-- (magicShooterPanel) once the helper window exists, adds the button at its top right and fills the helper through the
-- helper's own tables and functions (modules.game_helper: _Helper.getShooterProfile, magicShooter.updateRulesList,
-- _Helper.MagicShooter.rebuildCache, _Helper.getHelperConfig, onLoadHelperData, _Helper.saveSettings).
-- A click: the character's class (server vocation id), level and the spells it can cast (the helper's spell entries,
-- which game_chaosspells/spellfix.lua lines up with the server) pick the rotation; the shooter's rules become those
-- spells in priority order (an area spell waits for 2 monsters when the rest keeps the 2 s rhythm on a lone target);
-- the healing tab gets the class's heals when it is empty. A custom rotation or a filled healing tab is only replaced
-- after a yes. A level-up refreshes a rotation this button set (and that the player did not change since).

ChaosAutoRotationUI = ChaosAutoRotationUI or {}
local U = ChaosAutoRotationUI
local A = ChaosAutoRotation

U.BUTTON_ID = 'chaosAutoRotationButton'
local pollEvent = nil
local box = nil

local function helper()
  local m = modules.game_helper
  return m and m._Helper, m
end

local function spellEntry(id)
  local H = helper()
  if H and H.getSpellDataById then
    local ok, s = pcall(H.getSpellDataById, id)
    if ok and s then
      return s
    end
  end
  if Spells and Spells.getSpellDataById then
    return Spells.getSpellDataById(id)
  end
  return nil
end

local function nameOf(id)
  local s = spellEntry(id)
  if s and s.words and Spells and Spells.getSpellNameByWords then
    local ok, n = pcall(Spells.getSpellNameByWords, s.words)
    if ok and n then
      return n
    end
  end
  local d = ChaosAutoRotationData and ChaosAutoRotationData.spells[id]
  return (s and s.name) or (d and d.name) or tostring(id)
end

local function wordsOf(id)
  local s = spellEntry(id)
  local d = ChaosAutoRotationData and ChaosAutoRotationData.spells[id]
  return (s and s.words) or (d and d.words) or ''
end

-- the character can cast the spell: the server has it, the class is listed, the level is met, the player knows it
local function canCastFor(player)
  local H = helper()
  local voc, level = player:getVocation(), player:getLevel()
  return function(id)
    local s = spellEntry(id)
    if not s or s.notOnServer then
      return false
    end
    if type(s.vocations) == 'table' and #s.vocations > 0 and not table.contains(s.vocations, voc) then
      return false
    end
    if (tonumber(s.level) or 0) > level then
      return false
    end
    if H and H.playerHasSpell and not H.playerHasSpell(player, id) then
      return false
    end
    return true
  end
end

local function closeBox()
  if box then
    box:destroy()
    box = nil
  end
end

local function ask(title, text, onYes, onNo)
  closeBox()
  local yes = function() closeBox() onYes() end
  local no = function() closeBox() if onNo then onNo() end end
  box = displayGeneralBox(tr(title), tr(text), { { text = tr('Yes'), callback = yes }, { text = tr('No'), callback = no },
    anchor = AnchorHorizontalCenter }, yes, no)
end

local function say(text)
  if modules.game_textmessage and modules.game_textmessage.displayGameMessage then
    modules.game_textmessage.displayGameMessage(text)
  end
end

local function applyRotation(profile, sel)
  local H, M = helper()
  profile.rules = A.rules(sel, nameOf, wordsOf)
  profile[A.MARKER] = A.ruleIds(profile.rules)
  if M.magicShooter and M.magicShooter.updateRulesList then
    pcall(M.magicShooter.updateRulesList)
  end
  if H.MagicShooter and H.MagicShooter.rebuildCache then
    pcall(H.MagicShooter.rebuildCache)
  end
end

local function applyHeals(heals)
  local H, M = helper()
  local cfg = H.getHelperConfig and H.getHelperConfig()
  if not cfg or not cfg.spells then
    return false
  end
  for i = 1, #cfg.spells do
    local h = heals[i]
    cfg.spells[i].id = h and h.id or 0
    cfg.spells[i].percent = h and h.percent or 80
  end
  -- the helper's loader draws the healing slots from helperConfig and rebuilds its heal cache
  if M.onLoadHelperData then
    H._suppressMessages = true -- its status lines are for the login
    pcall(M.onLoadHelperData)
    H._suppressMessages = false
  end
  return true
end

local function save()
  local H = helper()
  if H and H.saveSettings then
    pcall(H.saveSettings)
  end
end

-- fill the shooter (and the healing tab); `quiet`: a level-up refresh, no dialog
function U.run(quiet)
  local H = helper()
  local player = g_game.getLocalPlayer()
  if not (H and player and H.getShooterProfile) then
    return false
  end
  local canCast = canCastFor(player)
  local sel, why = A.select(player:getVocation(), player:getLevel(), canCast)
  if not sel then
    if not quiet then
      say(why == 'class' and tr('Auto rotation: no rotation for this class.') or
        tr('Auto rotation: no attack spell at this level yet.'))
    end
    return false
  end
  local profile = H.getShooterProfile()
  if not profile then
    return false
  end
  local heals = A.heals(player:getVocation(), player:getLevel(), canCast)
  local function finish(withHeals)
    applyRotation(profile, sel)
    if withHeals and #heals > 0 then
      applyHeals(heals)
    end
    save()
    local text = A.message(sel, nameOf)
    g_logger.info('[auto rotation] ' .. text)
    if quiet then
      say(text)
    else
      -- the helper window covers the game screen's message line: a small box over it
      closeBox()
      local ok = function() closeBox() end
      box = displayGeneralBox(tr('Auto rotation'), text, { { text = tr('Ok'), callback = ok },
        anchor = AnchorHorizontalCenter }, ok, ok)
    end
  end
  local function healsThenFinish()
    local cfg = H.getHelperConfig and H.getHelperConfig()
    if quiet or #heals == 0 or not cfg then
      finish(false)
    elseif A.healingEmpty(cfg.spells) then
      finish(true)
    else
      ask('Auto rotation', 'The healing tab already has spells.\nReplace them with the class heals?',
        function() finish(true) end, function() finish(false) end)
    end
  end
  if quiet then
    if A.isCustom(profile.rules, profile[A.MARKER]) or A.same(A.ruleIds(profile.rules), sel.ids) then
      return false
    end
    finish(false)
    return true
  end
  if A.isCustom(profile.rules, profile[A.MARKER]) then
    ask('Auto rotation', 'This preset has your own rotation.\nReplace it with the class rotation?', healsThenFinish)
  else
    healsThenFinish()
  end
  return true
end

local function addButton()
  local root = g_ui.getRootWidget()
  local win = root and root:recursiveGetChildById('helperWindow')
  local panel = win and win:recursiveGetChildById('magicShooterPanel')
  if not panel then
    return false
  end
  if panel:getChildById(U.BUTTON_ID) then
    return true
  end
  local b = g_ui.createWidget('Button', panel)
  b:setId(U.BUTTON_ID)
  b:setText(tr('Auto rotation'))
  b:setTooltip(tr('Fill the spell rules with the best rotation of your class and level (at most 5 attack spells,\n' ..
    'one ready every 2 s) and an empty healing tab with your heals. Click again after a level-up.'))
  b:setWidth(96)
  b:setHeight(20)
  b:addAnchor(AnchorTop, 'parent', AnchorTop)
  b:addAnchor(AnchorRight, 'parent', AnchorRight)
  b:setMarginTop(2)
  b:setMarginRight(10)
  b.onClick = function() U.run(false) end
  return true
end

local function poll()
  if g_game.isOnline() then
    addButton()
  end
  pollEvent = scheduleEvent(poll, 2000)
end

local function onLevelChange(localPlayer, level, levelPercent, oldLevel)
  if oldLevel and level > oldLevel then
    U.run(true) -- says "Rotation set: ..." when the set changed
  end
end

function U.init()
  connect(LocalPlayer, { onLevelChange = onLevelChange })
  poll()
end

function U.terminate()
  disconnect(LocalPlayer, { onLevelChange = onLevelChange })
  if pollEvent then
    removeEvent(pollEvent)
    pollEvent = nil
  end
  closeBox()
  local root = g_ui.getRootWidget()
  local b = root and root:recursiveGetChildById(U.BUTTON_ID)
  if b then
    b:destroy()
  end
end
