-- The helper's Support spells tab and its cast cycle (the glue; the rules are supportspells.lua, tested there).
--
-- The helper (mods/game_helper, the base client) is not changed: this module adds a tab button to its tab bar and a
-- panel beside its own panels (found once the helper window exists, polled like the Auto setup button), and casts with
-- g_game.talk through the helper's own checks (modules.game_helper: _Helper.isHelperAutomaticFunctionsEnabled,
-- getSpellDataById, isSpellOnCooldown, getRotation, safeDoThing, canUseByServerVoc, playerHasSpell). The rows are saved
-- per character in the g_settings node SETTINGS_NODE. Auto setup (game_helperrotation/autosetup_ui.lua) fills the rows
-- through U.setSlots / U.slots / U.plan.
ChaosHelperSupportUI = ChaosHelperSupportUI or {}
local U = ChaosHelperSupportUI
local S = ChaosHelperSupport

U.TAB_ID = 'chaosSupportTab'
U.PANEL_ID = 'chaosSupportPanel'
local SETTINGS_NODE = 'chaos_helper_support' -- [character] = { enabled, reserve, slots = { {id, enabled}, ... } }
local PANEL_IDS = { 'healingPanel', 'toolsPanelContainer', 'shooterPanel', 'equipPanelContainer', 'cavebotPanel',
  'timerPanelContainer', 'scriptingPanel', 'settingsPanel' }
local TAB_IDS = { 'healingMenu', 'toolsMenu', 'shooterMenu', 'equipMenu', 'timerMenu', 'settingsFolderMenu' }

local cfg = S.defaultConfig()
local cfgFor = nil           -- the character the config was loaded for
local state = S.newState()
local timers = nil           -- the support channel's rate guard (ChaosHelperTimers)
local cycle, pollEvent = nil, nil
local building = false       -- the rows are being filled: no change events
local overall = ''           -- why nothing is cast now (the status line)

-- the status words of the rows and the panel (tr keys; pt-BR in client_chaos_locale/pt_br.lua)
local ROW_TEXT = {
  cast = 'Casting', queued = 'Next', wait = 'Waiting for the server', active = 'On', cooldown = 'On cooldown',
  mana = 'Not enough mana', reserve = 'Keeping the mana reserve', nofight = 'Waits for a fight',
  noparty = 'Needs a party', level = 'Cannot cast it yet', backoff = 'Refused, waiting', pending = 'Waiting for the answer',
  group = 'Waiting for another spell', rate = 'Rate limit', casting = 'An attack spell is charging', off = 'Off',
  unknown = 'Spell not found', nobar = 'Needs the Buff Bar',
  full = 'Summons at the limit', have = 'Already out', nocount = 'Cannot count summons',
}
local OVERALL_TEXT = {
  pz = 'Paused: protection zone', helperoff = 'The helper is off', disabled = 'Support spells are off',
  offline = '',
}

local function helper()
  local m = modules.game_helper
  return m and m._Helper, m
end

local function root() return g_ui.getRootWidget() end

local function charName()
  local p = g_game.getLocalPlayer()
  return p and p:getName()
end

-- ---------------------------------------------------------------- the saved list
local function load()
  local name = charName()
  if not name then return false end
  if cfgFor == name then return true end
  local node = g_settings.getNode(SETTINGS_NODE)
  cfg = S.sanitize(type(node) == 'table' and node[name] or nil) -- checked: config.otml can be edited by hand
  cfgFor = name
  state = S.newState()
  return true
end

local function save()
  local name = charName()
  if not name or cfgFor ~= name then return end
  local node = g_settings.getNode(SETTINGS_NODE)
  if type(node) ~= 'table' then node = {} end
  local slots = {}
  for i, s in ipairs(cfg.slots) do slots[i] = { id = s.id, enabled = s.enabled } end
  node[name] = { enabled = cfg.enabled, reserve = cfg.reserve, slots = slots }
  g_settings.setNode(SETTINGS_NODE, node)
  if g_settings.save then g_settings.save() end -- on disk now: a crash or a death screen close keeps it
end

function U.slots()
  load()
  local out = {}
  for i, s in ipairs(cfg.slots) do out[i] = { id = s.id, enabled = s.enabled } end
  return out
end

function U.enabled() load() return cfg.enabled end

-- Auto setup: the rows and (nil: unchanged) the switch
function U.setSlots(slots, enabled)
  load()
  cfg = S.sanitize({ enabled = enabled == nil and cfg.enabled or enabled, reserve = cfg.reserve, slots = slots })
  state = S.newState()
  save()
  U.rebuild()
end

-- ---------------------------------------------------------------- the spell table
local function spellList()
  if Spells and Spells.getSpellList then return Spells.getSpellList() end
  return {}
end

local function spellEntry(id)
  local H = helper()
  if H and H.getSpellDataById then
    local ok, s = pcall(H.getSpellDataById, id)
    if ok and s then return s end
  end
  if Spells and Spells.getSpellDataById then return Spells.getSpellDataById(id) end
  return nil
end

local function canCast()
  local player = g_game.getLocalPlayer()
  if not player then return function() return false end end
  if ChaosAutoRotationUI and ChaosAutoRotationUI.canCastFor then return ChaosAutoRotationUI.canCastFor(player) end
  return function(id) local s = spellEntry(id) return s ~= nil and not s.notOnServer end
end

-- Auto setup: what goes where for the character (S.autoPlan over the client's spell table)
function U.plan()
  return S.autoPlan(spellList(), canCast())
end

-- the dropdown's spells: the eligible ones the character can cast, plus the ones already in the list
local function options()
  local list, seen = {}, {}
  for _, c in ipairs(S.candidates(spellList(), canCast())) do
    list[#list + 1] = { id = c.spell.id, name = c.spell.name }
    seen[c.spell.id] = true
  end
  for _, s in ipairs(cfg.slots) do
    if not seen[s.id] then
      local e = spellEntry(s.id)
      list[#list + 1] = { id = s.id, name = e and e.name or tostring(s.id) }
      seen[s.id] = true
    end
  end
  return list
end

-- ---------------------------------------------------------------- the cast
local function castChecks()
  local H = helper()
  local player = g_game.getLocalPlayer()
  local R = ChaosHelperRotation
  local rotation = H and H.getRotation and H.getRotation() or nil
  local now = g_clock.millis()
  if ChaosHelperTimers and ChaosHelperTimers.new then timers = timers or ChaosHelperTimers.new() end
  local bb = modules.game_buffbar
  local level = player:getLevel()
  local allowedToCast = canCast()
  local target = g_game.getAttackingCreature()
  local castbar = modules.game_castbar
  return {
    now = now,
    online = true,
    helperOn = H and H.isHelperAutomaticFunctionsEnabled and H.isHelperAutomaticFunctionsEnabled() or false,
    inPz = player:isInProtectionZone(),
    mana = player:getMana(), maxMana = player:getMaxMana(),
    attacking = target ~= nil and target:isMonster(),
    channeling = (rotation and R and R.channeling(rotation, now)) or
      (castbar and castbar.isCasting and castbar.isCasting() or false),
    spellOf = spellEntry,
    castable = function(spell)
      if not allowedToCast(spell.id) then return false end
      return not R or R.castable(spell, level, nil)
    end,
    onCooldown = function(spell) return H and H.isSpellOnCooldown and H.isSpellOnCooldown(spell) or false end,
    buffActive = function(names)
      local set = bb and bb.activeBuffs and bb.activeBuffs() or nil
      if set == nil then return nil end
      for _, n in ipairs(names) do if set[n] then return true end end
      return false
    end,
    blocked = function(spell)
      if not (rotation and R) then return nil end
      return R.blockedWhy(rotation, spell.id, spell.group, now)
    end,
    -- the character's own summons: creatures whose master is the player (all, and those named `name`, a name or a list
    -- of names); nil when the client cannot tell (no master id), so a capped summon is not cast blind
    summonCount = function(name)
      if not (player.getId and g_map and g_map.getSpectators) then return nil end
      local id, total, own = player:getId(), 0, 0
      local want = {}
      for _, n in ipairs(type(name) == 'table' and name or { name }) do want[tostring(n):lower()] = true end
      for _, c in ipairs(g_map.getSpectators(player:getPosition(), false) or {}) do
        if c.getMasterId and c:getMasterId() == id then
          total = total + 1
          if want[tostring(c:getName()):lower()] then own = own + 1 end
        end
      end
      return total, own
    end,
    level = level,
    -- the server's refusals of this spell in a row (ChaosHelperRotation: casts it never answered with a cooldown)
    refusals = function(spell)
      return rotation and rotation.fails and rotation.fails[spell.id] or 0
    end,
    summonCap = function()
      return S.summonCap(player:getVocation(), level)
    end,
    inParty = function()
      local ok, shield = pcall(player.getShield, player)
      return ok and type(shield) == 'number' and shield >= ShieldBlue and shield ~= ShieldGray
    end,
    allowed = function(spell, t)
      if not (timers and ChaosHelperTimers) then return true end
      return ChaosHelperTimers.castAllowed(timers, 'support', spell.words, t)
    end,
  }, rotation
end

local function tick()
  if not g_game.isOnline() then overall = '' return end
  if not load() then return end
  if #cfg.slots == 0 or not cfg.enabled then
    state.status = {}
    overall = cfg.enabled and '' or 'disabled'
    return
  end
  local ctx, rotation = castChecks()
  local spell, why = S.pick(state, cfg, ctx)
  overall = spell and '' or (why ~= 'idle' and why or '')
  if not spell then return end
  local H = helper()
  if H and H.safeDoThing then H.safeDoThing(false) end
  g_game.talk(spell.words)
  if H and H.safeDoThing then H.safeDoThing(true) end
  if rotation and ChaosHelperRotation then ChaosHelperRotation.cast(rotation, spell.id, spell.group, ctx.now) end
  S.noteCast(state, spell, ctx.now)
end

-- ---------------------------------------------------------------- the panel
local function panel() local r = root() return r and r:recursiveGetChildById(U.PANEL_ID) end
local function tab() local r = root() return r and r:recursiveGetChildById(U.TAB_ID) end

local function rowsOf(p)
  local rows = p:recursiveGetChildById('rows')
  local list = {}
  for i = 1, S.SUPPORT_MAX do list[i] = rows:getChildById('row' .. i) end
  return list
end

-- the rows' choices -> cfg.slots (an empty row leaves the list; a spell twice keeps its first row)
local function readRows()
  local p = panel()
  if not p then return end
  local slots, seen = {}, {}
  for _, row in ipairs(rowsOf(p)) do
    local opt = row:getChildById('spell'):getCurrentOption()
    local id = opt and tonumber(opt.data) or 0
    if id and id > 0 and not seen[id] then
      seen[id] = true
      slots[#slots + 1] = { id = id, enabled = row:getChildById('enable'):isChecked() }
    end
  end
  cfg.slots = slots
end

local function changed()
  if building then return end
  readRows()
  state = S.newState()
  save()
  U.rebuild()
end

function U.refreshStatus()
  local p = panel()
  if not p or not p:isVisible() then return end
  local rows = rowsOf(p)
  for i, row in ipairs(rows) do
    local slot = cfg.slots[i]
    local label = row:getChildById('status')
    local st = slot and state.status[slot.id]
    if not slot then
      label:setText('')
    elseif st and ROW_TEXT[st] and cfg.enabled then
      label:setText(tr(ROW_TEXT[st]))
    else
      label:setText('')
    end
  end
  local line = p:recursiveGetChildById('statusLine')
  local text = OVERALL_TEXT[overall]
  if text and text ~= '' then
    line:setText(tr(text))
  elseif #cfg.slots == 0 then
    line:setText(tr('The list is empty. Pick spells in the rows, or press Fill for my class.'))
  elseif modules.game_buffbar and modules.game_buffbar.activeBuffs and modules.game_buffbar.activeBuffs() == nil then
    line:setText(tr('The Buff Bar is off: buffs are timed by their duration, vigils are not cast.'))
  else
    line:setText('')
  end
end

-- fills the rows from cfg (and the dropdowns from the character's spells)
function U.rebuild()
  local p = panel()
  if not p or not load() then return end
  building = true
  local opts = options()
  local rows = rowsOf(p)
  for i, row in ipairs(rows) do
    local combo = row:getChildById('spell')
    combo:clearOptions()
    combo:addOption(tr('(empty)'), 0, true)
    for _, o in ipairs(opts) do combo:addOption(o.name, o.id, true) end
    local slot = cfg.slots[i]
    combo:setCurrentOptionByData(slot and slot.id or 0, true)
    row:getChildById('enable'):setChecked(slot == nil or slot.enabled)
    row:getChildById('enable'):setEnabled(slot ~= nil)
  end
  p:recursiveGetChildById('enableAll'):setChecked(cfg.enabled)
  local reserve = p:recursiveGetChildById('reserve')
  reserve:setCurrentOptionByData(cfg.reserve, true)
  building = false
  U.refreshStatus()
end

local function buildPanel(parent)
  local p = g_ui.createWidget('ChaosSupportPanel', parent)
  if not p then return nil end
  p:setId(U.PANEL_ID)
  local rows = p:recursiveGetChildById('rows')
  local previous = nil
  for i = 1, S.SUPPORT_MAX do
    local row = g_ui.createWidget('ChaosSupportRow', rows)
    row:setId('row' .. i)
    row:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    row:addAnchor(AnchorRight, 'parent', AnchorRight)
    if previous then row:addAnchor(AnchorTop, previous:getId(), AnchorBottom) else row:addAnchor(AnchorTop, 'parent', AnchorTop) end
    previous = row
    row:getChildById('number'):setText(tostring(i))
    row:getChildById('spell').onOptionChange = function() changed() end
    row:getChildById('enable').onCheckChange = function() changed() end
  end
  local reserve = p:recursiveGetChildById('reserve')
  for _, v in ipairs(S.RESERVES) do reserve:addOption(v .. ' %', v, true) end
  reserve.onOptionChange = function(self, text, data)
    if building then return end
    cfg.reserve = tonumber(data) or S.DEFAULT_RESERVE
    save()
  end
  p:recursiveGetChildById('enableAll').onCheckChange = function(self, checked)
    if building then return end
    cfg.enabled = checked
    save()
    U.refreshStatus()
  end
  p:recursiveGetChildById('fill').onClick = function() U.fillForClass() end
  p:recursiveGetChildById('clear').onClick = function()
    cfg.slots = {}
    state = S.newState()
    save()
    U.rebuild()
  end
  return p
end

function U.fillForClass()
  load()
  local plan = U.plan()
  cfg.slots = S.mergeSlots(cfg.slots, plan.support, 'add')
  state = S.newState()
  save()
  U.rebuild()
end

local function showPanel()
  local r = root()
  local p, t = panel(), tab()
  if not (r and p and t) then return end
  for _, id in ipairs(PANEL_IDS) do
    local w = r:recursiveGetChildById(id)
    if w then w:hide() end
  end
  local bar = t:getParent()
  for _, id in ipairs(TAB_IDS) do
    local b = bar:getChildById(id)
    if b then b:setChecked(false) end
  end
  t:setChecked(true)
  -- the panel opens even when filling the rows fails (logged once)
  local ok, err = pcall(U.rebuild)
  if not ok and not U.loggedRebuildError then
    U.loggedRebuildError = true
    g_logger.error('[helper support] ' .. tostring(err))
  end
  p:show(true)
  p:raise()
end

local function hidePanel()
  local p, t = panel(), tab()
  if p then p:hide() end
  if t then t:setChecked(false) end
end

-- Owner beta, 2026-10-20: "The helper's Support tab does not open." The styles were imported in U.init, and this
-- module loads at autoload priority 100, before client_styles (loaded with the `client` module after the 100-499
-- modules) defines Panel, Label, CheckBox, ComboBox and Button. The import stopped at ChaosSupportRow < Panel ("base
-- style 'Panel', is not defined"): only ChaosSupportTab < UIButton existed, so the tab was made, the panel was not
-- (createWidget gave nil), and every later poll saw the tab and returned. The styles are now imported here, once the
-- helper window (a mod, loaded after client_styles) exists, and the tab is only made with its panel.
local stylesReady = false
local function importStyles()
  if stylesReady then return true end
  if g_ui.getStyle and not g_ui.getStyle('Panel') then return false end -- client_styles not loaded yet: next poll
  g_ui.importStyle('supportspells')
  if g_ui.getStyle then
    stylesReady = g_ui.getStyle('ChaosSupportPanel') ~= nil and g_ui.getStyle('ChaosSupportRow') ~= nil
  else
    stylesReady = true
  end
  return stylesReady
end
U.importStyles = importStyles

-- the helper sizes its tab buttons to fill the bar (fitHelperWindow, on show and on a resize); a tab added later is
-- refitted at once, else it can lie past the bar's right edge, where no click reaches it
local function refit()
  local m = modules.game_helper
  if m and m.onHelperViewportChange then pcall(m.onHelperViewportChange) end
end

-- the tab button after the helper's last tab, the panel where the Timer panel is; any other tab hides ours
function U.addTab()
  local r = root()
  local win = r and r:recursiveGetChildById('helperWindow')
  local bar = win and win:recursiveGetChildById('optionsTabBar')
  local anchorTab = bar and bar:getChildById('settingsFolderMenu')
  local timerPanel = win and win:recursiveGetChildById('timerPanelContainer')
  if not (bar and anchorTab and timerPanel) then return false end
  local oldTab = bar:getChildById(U.TAB_ID)
  if oldTab and panel() then return true end
  if oldTab then oldTab:destroy() end -- a tab without its panel (an earlier try that failed half way)
  if not importStyles() then return false end
  local parent = timerPanel:getParent()
  local p = buildPanel(parent)
  if not p then return false end
  local t = g_ui.createWidget('ChaosSupportTab', bar)
  if not t then
    p:destroy()
    return false
  end
  t:setId(U.TAB_ID)
  t:addAnchor(AnchorLeft, 'settingsFolderMenu', AnchorRight)
  t:getChildById('caption'):setText(tr('Support'))
  t:setTooltip(tr('Support spells: the helper casts them by itself when they are off cooldown'))
  t.onClick = function() showPanel() end
  p:addAnchor(AnchorTop, 'optionsTabBar', AnchorBottom)
  p:addAnchor(AnchorLeft, 'helperSidebar', AnchorRight)
  p:addAnchor(AnchorRight, 'parent', AnchorRight)
  p:addAnchor(AnchorBottom, 'separator', AnchorTop)
  p:setMarginLeft(8)
  p:setMarginTop(8)
  p:setMarginBottom(8)
  for _, id in ipairs(TAB_IDS) do
    local b = bar:getChildById(id)
    if b and not b.chaosSupportWrapped then
      b.chaosSupportWrapped = true
      local old = b.onCheckChange
      b.onCheckChange = function(self, checked, ...)
        if checked then hidePanel() end
        if old then return old(self, checked, ...) end
      end
    end
  end
  refit()
  U.rebuild()
  return true
end

local function poll()
  if g_game.isOnline() then
    local ok, err = pcall(U.addTab)
    if not ok and not U.loggedError then
      U.loggedError = true
      g_logger.error('[helper support] ' .. tostring(err))
    end
    local p = panel()
    if p and p:isVisible() then U.refreshStatus() end
  end
  pollEvent = scheduleEvent(poll, 1000)
end

local function onGameStart()
  cfgFor = nil
  state = S.newState()
  timers = nil
  if ChaosHelperTimers and ChaosHelperTimers.new then timers = ChaosHelperTimers.new() end
  load()
  U.rebuild()
end

local function onGameEnd()
  cfgFor = nil
  state = S.newState()
  overall = ''
end

-- a level-up can open new spells for the dropdowns
local function onLevelChange(localPlayer, level, levelPercent, oldLevel)
  if oldLevel and oldLevel > 0 and level > oldLevel then scheduleEvent(function() U.rebuild() end, 500) end
end

function U.init()
  -- the styles: importStyles(), from the first poll that finds the helper window (see there)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  connect(LocalPlayer, { onLevelChange = onLevelChange })
  cycle = cycleEvent(tick, S.CYCLE_MS)
  if g_game.isOnline() then onGameStart() end
  poll()
end

function U.terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  disconnect(LocalPlayer, { onLevelChange = onLevelChange })
  if cycle then removeEvent(cycle) cycle = nil end
  if pollEvent then removeEvent(pollEvent) pollEvent = nil end
  local p, t = panel(), tab()
  if p then p:destroy() end
  if t then t:destroy() end
end
