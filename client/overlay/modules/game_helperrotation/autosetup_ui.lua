-- The helper's "Auto setup" button, beside Helper Status at the bottom of the helper window (the choice is
-- autosetup.lua; client/MANIFEST.md "Helper Auto setup"). One click: healing (class heals, the best potions), tools
-- (eat food, haste kept up), the shooter (the class rotation, as Auto rotation), the timers (the class's fight buffs,
-- staggered so their first casts do not collide) and the Support spells tab (game_helpersupport: shields, summons, a
-- vigil), for the character's class and level, only with spells it can cast and potions it may drink. Where the player has set
-- something of their own, one question for the whole setup: Replace / Add / Cancel. Undo (in the result box and on
-- the button's right-click) puts every tab back as it was. The helper itself is not changed: its tables and
-- functions are used (modules.game_helper: _Helper.getHelperConfig, getShooterProfile, Timer, saveSettings,
-- onLoadHelperData, timerPanel).
ChaosAutoSetupUI = ChaosAutoSetupUI or {}
local W = ChaosAutoSetupUI
local A, S, U = ChaosAutoRotation, ChaosAutoSetup, ChaosAutoRotationUI

W.BUTTON_ID = 'chaosAutoSetupButton'
W.undo = nil
local SETTINGS_NODE = 'chaos_helper_autosetup' -- [character] = { timerWords = { words, ... } } (rules it wrote)
local box = nil

local function support() return ChaosHelperSupportUI end

local function helper()
  local m = modules.game_helper
  return m and m._Helper, m
end

local function closeBox()
  if box then box:destroy() box = nil end
end

local function charName()
  local p = g_game.getLocalPlayer()
  return p and p:getName()
end

-- the timer rules Auto setup wrote are remembered by their words (the helper's save keeps only its own fields)
local function ownWords()
  local node = g_settings.getNode(SETTINGS_NODE)
  local e = type(node) == 'table' and charName() and node[charName()] or nil
  local set = {}
  -- config.otml can be edited by hand: strings only, a capped list (ChaosHelperConfig.autosetupWords)
  for _, w in ipairs(ChaosHelperConfig.autosetupWords(e)) do set[w:lower()] = true end
  return set
end

local function rememberWords(rules)
  local name = charName()
  if not name then return end
  local node = g_settings.getNode(SETTINGS_NODE)
  if type(node) ~= 'table' then node = {} end
  local words = {}
  for _, r in ipairs(rules) do if r.chaosAutoSetup then words[#words + 1] = r.value end end
  node[name] = { timerWords = words }
  g_settings.setNode(SETTINGS_NODE, node)
  if g_settings.save then g_settings.save() end
end

local function timerRules(H)
  local mine = ownWords()
  local out = {}
  for _, r in ipairs(H.Timer and H.Timer.getRules() or {}) do
    local c = {}
    for k, v in pairs(r) do c[k] = v end
    if c.type == 'words' and mine[tostring(c.value):lower()] then c.chaosAutoSetup = true end
    out[#out + 1] = c
  end
  return out
end

local function copySlots(slots)
  local out = {}
  for i, s in ipairs(slots or {}) do
    out[i] = {}
    for k, v in pairs(s) do out[i][k] = v end
  end
  return out
end

local function writeSlots(target, slots)
  for i, s in ipairs(slots) do
    if target[i] then
      target[i].id = s.id
      target[i].percent = s.percent
    end
  end
end

local function setTimers(H, rules)
  if not H.Timer then return end
  H.Timer.clearRules()
  for _, r in ipairs(rules) do
    local _, rule = H.Timer.addRule(r)
    if rule then
      rule.enabled = r.enabled ~= false
      rule.chaosAutoSetup = r.chaosAutoSetup
    end
  end
end

-- redraw the helper's tabs from its config (the loader also reloads the timers from helperConfig.timerConfig)
local function refresh(H, M, cfg)
  if H.Timer and H.Timer.saveConfig then cfg.timerConfig = H.Timer.saveConfig() end
  if M.onLoadHelperData then
    H._suppressMessages = true
    pcall(M.onLoadHelperData)
    H._suppressMessages = false
  end
  local tp = M.timerPanel
  if tp then
    if tp.rebuildRulesList then pcall(tp.rebuildRulesList) end
    if tp.syncEnableTimer then pcall(tp.syncEnableTimer) end
  end
  U.refreshShooter()
  U.save()
end

-- the first casts of the rules Auto setup wrote go out STAGGER ms apart (the first at once): the support spells share
-- one group cooldown on the server and a timer rule does not wait for an answer, so rules that fell due together would
-- lose all but one cast for a whole cooldown. The loader drops lastExecuted, so this runs after the refresh.
local function stagger(H, rules)
  if not (H.Timer and H.Timer.getRules and H.Timer.cooldownToMs and g_clock) then return end
  local now = g_clock.millis()
  local step = ChaosHelperSupport and ChaosHelperSupport.TIMER_STAGGER_MS or 2500
  local n = 0
  for _, planned in ipairs(rules) do
    if planned.chaosAutoSetup then
      for _, live in ipairs(H.Timer.getRules()) do
        if live.type == 'words' and tostring(live.value):lower() == tostring(planned.value):lower() then
          if n > 0 then live.lastExecuted = now - H.Timer.cooldownToMs(live.cooldown, live.unit) + n * step end
          n = n + 1
          break
        end
      end
    end
  end
end

local function snapshot(H, cfg, profile)
  local sup = support()
  return {
    support = sup and sup.slots(), supportOn = sup and sup.enabled(),
    spells = copySlots(cfg.spells), potions = copySlots(cfg.potions), haste = copySlots(cfg.haste),
    autoEatFood = cfg.autoEatFood, rules = profile and A.copyRules(profile.rules), marker = profile and profile[A.MARKER],
    profile = profile, timers = timerRules(H), timerOn = H.Timer and H.Timer.isEnabled and H.Timer.isEnabled(),
  }
end

function W.undoSetup()
  local u = W.undo
  local H, M = helper()
  local cfg = H and H.getHelperConfig and H.getHelperConfig()
  if not u or not cfg then return false end
  writeSlots(cfg.spells, u.spells)
  writeSlots(cfg.potions, u.potions)
  for i, h in ipairs(u.haste) do if cfg.haste[i] then cfg.haste[i].id, cfg.haste[i].enabled = h.id, h.enabled end end
  cfg.autoEatFood = u.autoEatFood
  if u.profile then
    u.profile.rules = u.rules
    u.profile[A.MARKER] = u.marker
  end
  setTimers(H, u.timers)
  rememberWords(u.timers)
  if u.support and support() then support().setSlots(u.support, u.supportOn) end
  if H.Timer and H.Timer.isEnabled and H.Timer.isEnabled() ~= u.timerOn then H.Timer.toggle() end
  W.undo = nil
  refresh(H, M, cfg)
  return true
end

local function apply(ctx, mode)
  local H, M, cfg, plan, profile = ctx.H, ctx.M, ctx.cfg, ctx.plan, ctx.profile
  W.undo = snapshot(H, cfg, profile)
  -- healing
  writeSlots(cfg.spells, S.mergeSlots(cfg.spells, plan.healing.spells, mode, #cfg.spells))
  writeSlots(cfg.potions, S.mergeSlots(cfg.potions, plan.healing.potions, mode, #cfg.potions))
  -- tools
  cfg.autoEatFood = true
  if cfg.haste and cfg.haste[1] then
    cfg.haste[1].id = S.mergeHaste(cfg.haste[1].id, plan.tools.haste, mode)
    if (tonumber(cfg.haste[1].id) or 0) ~= 0 then cfg.haste[1].enabled = true end
  end
  -- shooter
  if profile and plan.rotation then
    U.applyRotation(profile, plan.rotation, (mode == 'add' and A.isCustom(profile.rules, profile[A.MARKER])) and 'add'
      or 'replace')
  end
  -- timers
  local rules = S.mergeTimers(timerRules(H), plan.timers, mode)
  setTimers(H, rules)
  rememberWords(rules)
  if #rules > 0 and H.Timer and H.Timer.isEnabled and not H.Timer.isEnabled() then H.Timer.toggle() end
  refresh(H, M, cfg)
  stagger(H, rules)
  -- support spells
  local sup = support()
  if sup then
    sup.setSlots(ChaosHelperSupport.mergeSlots(sup.slots(), plan.support, mode), true)
  end

  local lines = { tr('Auto setup done for %s, level %d.'):format(ctx.className, ctx.level) }
  lines[#lines + 1] = tr('Healing: %d spells, %d potions.'):format(#plan.healing.spells, #plan.healing.potions)
  lines[#lines + 1] = plan.tools.haste and tr('Tools: eat food, haste %s.'):format(U.nameOf(plan.tools.haste))
    or tr('Tools: eat food.')
  lines[#lines + 1] = plan.rotation and tr('Shooter: %d attack spells.'):format(#plan.rotation.ids)
    or tr('Shooter: no attack spell at this level yet.')
  lines[#lines + 1] = tr('Timers: %d buffs.'):format(#plan.timers)
  if support() then lines[#lines + 1] = tr('Support spells: %d.'):format(#plan.support) end
  closeBox()
  local ok = function() closeBox() end
  local undo = function() closeBox() W.undoSetup() end
  box = displayGeneralBox(tr('Auto setup'), table.concat(lines, '\n'), { { text = tr('Ok'), callback = ok },
    { text = tr('Undo'), callback = undo }, anchor = AnchorHorizontalCenter }, ok, ok)
end

local TAB_NAMES = { healing = 'Healing', tools = 'Tools', shooter = 'Shooter', timers = 'Timers', support = 'Support spells' }

function W.run()
  local H, M = helper()
  local player = g_game.getLocalPlayer()
  local cfg = H and H.getHelperConfig and H.getHelperConfig()
  if not (H and M and player and cfg and cfg.spells and cfg.potions) then return false end
  local voc, level = player:getVocation(), player:getLevel()
  if not S.lineOf(voc) then
    displayInfoBox(tr('Auto setup'), tr('Auto setup has no recommendations for this class.'))
    return false
  end
  local canCast = U.canCastFor(player)
  local has = function(id)
    local ok, n = pcall(player.getInventoryCount, player, id, 0)
    return ok and (tonumber(n) or 0) > 0
  end
  local plan = S.plan({ vocId = voc, level = level, canCast = canCast, has = has,
    heals = A.heals(voc, level, canCast), rotation = (A.select(voc, level, canCast, { topUp = true })),
    support = support() and support().plan() })
  local profile = H.getShooterProfile and H.getShooterProfile()
  local c = A.classOf(voc)
  local ctx = { H = H, M = M, cfg = cfg, plan = plan, profile = profile, level = level,
    className = c and c.name or tostring(voc) }
  local cur = { spells = cfg.spells, potions = cfg.potions, haste = cfg.haste and cfg.haste[1] and cfg.haste[1].id,
    rotationCustom = profile and A.isCustom(profile.rules, profile[A.MARKER]), timers = timerRules(H),
    support = support() and support().slots() or {} }
  local tabs = S.ownTabs(cur, plan)
  if #tabs == 0 then
    apply(ctx, 'replace')
    return true
  end
  local names = {}
  for _, t in ipairs(tabs) do names[#names + 1] = tr(TAB_NAMES[t]) end
  closeBox()
  local add = function() closeBox() apply(ctx, 'add') end
  local replace = function() closeBox() apply(ctx, 'replace') end
  local cancel = function() closeBox() end
  box = displayGeneralBox(tr('Auto setup'),
    tr('You have your own settings in: %s.\nAdd the recommended ones to yours, or replace yours?\n(Undo puts everything back.)')
      :format(table.concat(names, ', ')),
    { { text = tr('Add'), callback = add }, { text = tr('Replace'), callback = replace },
      { text = tr('Cancel'), callback = cancel }, anchor = AnchorHorizontalCenter }, add, cancel)
  return true
end

-- the button, right after Helper Status (and its Set Key button) at the bottom of the helper window
function W.addButton()
  local root = g_ui.getRootWidget()
  local win = root and root:recursiveGetChildById('helperWindow')
  local key = win and win:recursiveGetChildById('setKeyHelperButton')
  local parent = key and key:getParent()
  if not parent then return false end
  if parent:getChildById(W.BUTTON_ID) then return true end
  local b = g_ui.createWidget('Button', parent)
  b:setId(W.BUTTON_ID)
  b:setText(tr('Auto setup'))
  b:setTooltip(tr('Set up healing, tools, shooter, timers and support spells for your class and level in one click\n' ..
    '(only spells you can cast and potions you may drink). Right-click: undo the last Auto setup.'))
  b:setHeight(17)
  b:setTextHorizontalAutoResize(true)
  b:addAnchor(AnchorVerticalCenter, 'setKeyHelperButton', AnchorVerticalCenter)
  b:addAnchor(AnchorLeft, 'setKeyHelperButton', AnchorRight)
  b:setMarginLeft(10)
  b.onClick = function() W.run() end
  b.onMouseRelease = function(self, pos, button)
    if button == MouseRightButton then
      if not W.undoSetup() then displayInfoBox(tr('Auto setup'), tr('Nothing to undo.')) end
      return true
    end
  end
  return true
end

function W.terminate()
  closeBox()
  local root = g_ui.getRootWidget()
  local b = root and root:recursiveGetChildById(W.BUTTON_ID)
  if b then b:destroy() end
end
