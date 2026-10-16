-- The helper's "Auto rotation" button (the glue; the choice is autorotation.lua, the data autorotation_data.lua).
--
-- The helper (mods/game_helper, the base client) is not changed: this module finds its Targeting & Spell Rules panel
-- (magicShooterPanel) once the helper window exists, adds the button at its top right and fills the helper through the
-- helper's own tables and functions (modules.game_helper: _Helper.getShooterProfile, magicShooter.updateRulesList,
-- _Helper.MagicShooter.rebuildCache, _Helper.getHelperConfig, onLoadHelperData, _Helper.saveSettings).
-- A click: the character's class (server vocation id), level and the spells it can cast (the helper's spell entries,
-- which game_chaosspells/spellfix.lua lines up with the server) pick the rotation; the shooter's rules become those
-- spells in priority order (an area spell waits for 2 monsters when the rest keeps the 2 s rhythm on a lone target);
-- the healing tab gets the class's heals when it is empty. When the preset has the player's own rules the button asks:
-- "Add to my rules" (the default: their rules stay on top, the class spells not in the list yet go below) or "Replace".
-- The list before the click is kept for "Undo" (the button beside it and the result box) for the session. A filled
-- healing tab is only replaced after a yes.
-- The helper never changes the spells unasked (owner, 2026-10-16). A level-up that brings a new attack spell asks
-- "New spell available: X. Add to rotation?" (Add / Ignore; an ignored spell is not asked again for this character).
-- Only with "Auto-update my spells" checked (off by default, kept per character) does a level-up update a rotation
-- this button wrote, and never the player's own rules. The rule is ChaosAutoRotation.levelUpAction.

ChaosAutoRotationUI = ChaosAutoRotationUI or {}
local U = ChaosAutoRotationUI
local A = ChaosAutoRotation

U.BUTTON_ID = 'chaosAutoRotationButton'
U.UNDO_ID = 'chaosAutoRotationUndo'
U.undo = nil -- {profile, rules, marker}: the list before the last click
U.AUTO_ID = 'chaosAutoUpdateSpells'
local SETTINGS_NODE = 'chaos_helper_spells' -- [character] = {autoUpdate = bool, ignored = {[id] = true}}
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

local function refreshUndoButton()
  local root = g_ui.getRootWidget()
  local b = root and root:recursiveGetChildById(U.UNDO_ID)
  if b then b:setVisible(U.undo ~= nil) end
end

local function refreshShooter()
  local H, M = helper()
  if M.magicShooter and M.magicShooter.updateRulesList then
    pcall(M.magicShooter.updateRulesList)
  end
  if H.MagicShooter and H.MagicShooter.rebuildCache then
    pcall(H.MagicShooter.rebuildCache)
  end
end

-- mode 'add': the player's rules stay, the class spells not in the list are appended; 'replace': the class rotation
local function applyRotation(profile, sel, mode)
  U.undo = { profile = profile, rules = A.copyRules(profile.rules), marker = profile[A.MARKER] }
  local auto = A.rules(sel, nameOf, wordsOf)
  if mode == 'add' and profile.rules and #profile.rules > 0 then
    profile.rules = A.merge(profile.rules, auto)
    profile[A.MARKER] = nil -- the list holds the player's rules: the next click asks again
  else
    profile.rules = auto
    profile[A.MARKER] = A.ruleIds(profile.rules)
  end
  refreshUndoButton()
  refreshShooter()
end

local function save()
  local H = helper()
  if H and H.saveSettings then
    pcall(H.saveSettings)
  end
end

-- puts the list back as it was before the last Auto rotation click
function U.undoRotation()
  local u = U.undo
  if not u or not u.profile then return false end
  u.profile.rules = u.rules
  u.profile[A.MARKER] = u.marker
  U.undo = nil
  refreshUndoButton()
  refreshShooter()
  save()
  return true
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

-- this character's spell choices: "Auto-update my spells" and the spells it said Ignore to
local function prefs()
  local player = g_game.getLocalPlayer()
  local name = player and player:getName()
  local node = g_settings.getNode(SETTINGS_NODE) or {}
  local p = name and node[name] or {}
  return { autoUpdate = p.autoUpdate == true, ignored = type(p.ignored) == 'table' and p.ignored or {} }, name, node
end

local function savePrefs(p)
  local _, name, node = prefs()
  if not name then return end
  local ignored = {}
  for id, v in pairs(p.ignored or {}) do if v then ignored[tonumber(id) or id] = true end end
  node[name] = { autoUpdate = p.autoUpdate == true, ignored = ignored }
  g_settings.setNode(SETTINGS_NODE, node)
  if g_settings.save then g_settings.save() end -- on disk now: a crash or a death screen close keeps it
end

function U.isAutoUpdate()
  return prefs().autoUpdate
end

function U.setAutoUpdate(on)
  local p = prefs()
  p.autoUpdate = on == true
  savePrefs(p)
end

-- fill the shooter (and the healing tab) when the player clicks Auto rotation; `quiet` is only used by the level-up
-- path with "Auto-update my spells" on
function U.run(quiet)
  local H = helper()
  local player = g_game.getLocalPlayer()
  if not (H and player and H.getShooterProfile) then
    return false
  end
  local canCast = canCastFor(player)
  -- the top-up to 5 spells only on a click; the opt-in level-up update keeps the class preset
  local sel, why = A.select(player:getVocation(), player:getLevel(), canCast, { topUp = not quiet })
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
  local mode = 'replace'
  local function finish(withHeals)
    applyRotation(profile, sel, mode)
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
      local undo = function() closeBox() U.undoRotation() end
      box = displayGeneralBox(tr('Auto rotation'), text, { { text = tr('Ok'), callback = ok },
        { text = tr('Undo'), callback = undo }, anchor = AnchorHorizontalCenter }, ok, ok)
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
    -- never drop the player's rules unasked: Enter adds, Escape cancels
    closeBox()
    local add = function() closeBox() mode = 'add' healsThenFinish() end
    local replace = function() closeBox() mode = 'replace' healsThenFinish() end
    local cancel = function() closeBox() end
    box = displayGeneralBox(tr('Auto rotation'),
      tr('This preset has your own rules.\nAdd the class spells below them, or replace them?\n(Undo puts the list back.)'),
      { { text = tr('Add to my rules'), callback = add }, { text = tr('Replace'), callback = replace },
        { text = tr('Cancel'), callback = cancel }, anchor = AnchorHorizontalCenter }, add, cancel)
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
  b:setHeight(20)
  b:setTextHorizontalAutoResize(true)
  b:addAnchor(AnchorTop, 'parent', AnchorTop)
  b:addAnchor(AnchorRight, 'parent', AnchorRight)
  b:setMarginTop(2)
  b:setMarginRight(10)
  b.onClick = function() U.run(false) end
  local u = g_ui.createWidget('Button', panel)
  u:setId(U.UNDO_ID)
  u:setText(tr('Undo'))
  u:setTooltip(tr('Put back the spell rules as they were before the last Auto rotation'))
  u:setHeight(20)
  u:setTextHorizontalAutoResize(true)
  u:addAnchor(AnchorTop, 'parent', AnchorTop)
  u:addAnchor(AnchorRight, U.BUTTON_ID, AnchorLeft)
  u:setMarginTop(2)
  u:setMarginRight(4)
  u.onClick = function() U.undoRotation() end
  u:setVisible(U.undo ~= nil)
  -- the box sits on the presets row, left of Rename (in the title row it covered "RULES" of the centred title)
  local presets = panel:recursiveGetChildById('presetsSection')
  local rename = presets and presets:getChildById('renameButton')
  local c = g_ui.createWidget('CheckBox', presets or panel)
  c:setId(U.AUTO_ID)
  c:setTooltip(tr('Auto-update my spells') .. '\n' ..
    tr('After a level-up, update a rotation that Auto rotation wrote with the new spells.\n' ..
    'Off: a new spell is only offered (Add / Ignore). Your own rules are never changed.'))
  c:setTextHorizontalAutoResize(true)
  c:setHeight(16)
  if rename then
    c:addAnchor(AnchorVerticalCenter, 'renameButton', AnchorVerticalCenter)
    c:addAnchor(AnchorRight, 'renameButton', AnchorLeft)
    c:setMarginRight(10)
  else
    c:addAnchor(AnchorTop, U.BUTTON_ID, AnchorBottom)
    c:addAnchor(AnchorRight, 'parent', AnchorRight)
    c:setMarginTop(4)
    c:setMarginRight(10)
  end
  c:setChecked(U.isAutoUpdate())
  c.onCheckChange = function(self, checked) U.setAutoUpdate(checked) end
  if presets then
    connect(presets, { onGeometryChange = function() U.fitAutoBox() end })
  end
  U.fitAutoBox()
  return true
end

-- the label that fits between the row's left widgets (Presets:, Set Key, help icon) and Rename
function U.fitAutoBox()
  local root = g_ui.getRootWidget()
  local c = root and root:recursiveGetChildById(U.AUTO_ID)
  local presets = c and c:getParent()
  local rename = presets and presets:getChildById('renameButton')
  if not c or not rename then return end
  local leftEdge = presets:getX()
  for _, id in ipairs({ 'presetsLabel', 'setKeyPresetButton', 'presetHelpIcon' }) do
    local w = presets:getChildById(id)
    if w and w:isVisible() then leftEdge = math.max(leftEdge, w:getX() + w:getWidth()) end
  end
  local free = rename:getX() - c:getMarginRight() - leftEdge - 10
  local function widthWith(text)
    c:setText(text)
    return c:getWidth()
  end
  local full, short = tr('Auto-update my spells'), tr('Auto-update')
  local BOX = 16 -- the box image alone
  local widths = { full = widthWith(full), short = widthWith(short), box = BOX }
  local pick = ChaosAutoRotation.autoBoxLabel(free, widths)
  c:setText(pick == 'full' and full or pick == 'short' and short or '')
  if pick == 'none' then c:setWidth(BOX) end
  c:setVisible(pick ~= 'hidden')
end

-- for autosetup_ui.lua (the "Auto setup" button reuses the rotation and the spell checks)
U.canCastFor = canCastFor
U.applyRotation = applyRotation
U.refreshShooter = refreshShooter
U.save = save
U.nameOf = nameOf

local function poll()
  if g_game.isOnline() then
    addButton()
    if ChaosAutoSetupUI and ChaosAutoSetupUI.addButton then ChaosAutoSetupUI.addButton() end
  end
  pollEvent = scheduleEvent(poll, 2000)
end

-- a level-up: never a silent change. New attack spells: a notice with Add / Ignore; "Auto-update my spells" on and a
-- rotation the button wrote: updated, with a message (and Undo)
function U.onLevelUp()
  local H = helper()
  local player = g_game.getLocalPlayer()
  if not (H and player and H.getShooterProfile) then return 'none' end
  local profile = H.getShooterProfile()
  if not profile then return 'none' end
  local sel = A.select(player:getVocation(), player:getLevel(), canCastFor(player), { topUp = false })
  local p = prefs()
  local action, newIds = A.levelUpAction(sel, profile.rules, profile[A.MARKER], p)
  if action == 'apply' then
    U.run(true)
  elseif action == 'notice' then
    local names = {}
    for _, id in ipairs(newIds) do names[#names + 1] = nameOf(id) end
    local list = table.concat(names, ', ')
    closeBox()
    local add = function()
      closeBox()
      local auto = A.rules(sel, nameOf, wordsOf)
      local wanted = {}
      for _, id in ipairs(newIds) do wanted[id] = true end
      local picked = {}
      for _, r in ipairs(auto) do if wanted[r.spellId] then picked[#picked + 1] = r end end
      U.undo = { profile = profile, rules = A.copyRules(profile.rules), marker = profile[A.MARKER] }
      local custom = A.isCustom(profile.rules, profile[A.MARKER])
      profile.rules = A.merge(profile.rules, picked)
      profile[A.MARKER] = (not custom) and A.ruleIds(profile.rules) or nil
      refreshUndoButton()
      refreshShooter()
      save()
    end
    local ignore = function()
      closeBox()
      local q = prefs()
      for _, id in ipairs(newIds) do q.ignored[id] = true end
      savePrefs(q)
    end
    box = displayGeneralBox(tr('New spell available'), tr('New spell available: %s.\nAdd to rotation?', list),
      { { text = tr('Add'), callback = add }, { text = tr('Ignore'), callback = ignore },
        anchor = AnchorHorizontalCenter }, add, ignore)
  end
  return action
end

local function onLevelChange(localPlayer, level, levelPercent, oldLevel)
  -- oldLevel 0: the login's first level packet (also after a death), not a level-up
  if oldLevel and oldLevel > 0 and level > oldLevel then
    U.onLevelUp()
  end
end

-- the undo belongs to this character's session
local function onGameEnd()
  U.undo = nil
end

-- the server's answer to a potion probe (ChaosPotionGate, base patch 0070): nothing to use -> the potion waits
local function onTextMessage(mode, text)
  if ChaosPotionGate then ChaosPotionGate.onText(ChaosPotionGate.session, text, g_clock.millis()) end
end

function U.init()
  connect(LocalPlayer, { onLevelChange = onLevelChange })
  connect(g_game, { onGameEnd = onGameEnd, onTextMessage = onTextMessage })
  poll()
end

function U.terminate()
  disconnect(LocalPlayer, { onLevelChange = onLevelChange })
  disconnect(g_game, { onGameEnd = onGameEnd, onTextMessage = onTextMessage })
  if pollEvent then
    removeEvent(pollEvent)
    pollEvent = nil
  end
  closeBox()
  if ChaosAutoSetupUI and ChaosAutoSetupUI.terminate then ChaosAutoSetupUI.terminate() end
  local root = g_ui.getRootWidget()
  for _, id in ipairs({ U.AUTO_ID, U.UNDO_ID, U.BUTTON_ID }) do
    local b = root and root:recursiveGetChildById(id)
    if b then
      b:destroy()
    end
  end
end
