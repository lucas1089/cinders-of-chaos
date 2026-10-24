-- The helper's Support spells tab and its cast cycle (the glue; the rules are supportspells.lua, tested there).
--
-- The helper (modules/game_helper) has a Support tab with an empty host panel (supportHost). This module builds its panel
-- into that host (found once the helper window exists, polled), and casts with g_game.talk through the helper's own checks
-- (modules.game_helper: _Helper.isHelperAutomaticFunctionsEnabled, getSpellDataById, isSpellOnCooldown, getRotation,
-- safeDoThing, canUseByServerVoc, playerHasSpell). The rows are saved per character in the g_settings node SETTINGS_NODE.
-- Auto setup (game_helperrotation/autosetup_ui.lua) fills the rows through U.setSlots / U.slots / U.plan.
ChaosHelperSupportUI = ChaosHelperSupportUI or {}
local U = ChaosHelperSupportUI
local S = ChaosHelperSupport

U.HOST_ID = 'supportHost'
U.PANEL_ID = 'chaosSupportPanel'
local SETTINGS_NODE = 'chaos_helper_support' -- [character] = { enabled, reserve, slots = { {id, enabled}, ... } }
local cfg = S.defaultConfig()
local cfgFor = nil           -- the character the config was loaded for
local state = S.newState()
local timers = nil           -- the support channel's rate guard (ChaosHelperTimers)
local cycle, pollEvent = nil, nil
local building = false       -- the rows are being filled: no change events
local overall = ''           -- why nothing is cast now (the status line)
local userOffNote = false    -- the player switched a vigil off: the status line says its row was unticked

-- the status words of the rows and the panel (tr keys; pt-BR in client_chaos_locale/pt_br.lua)
local ROW_TEXT = {
  cast = 'Casting', queued = 'Next', wait = 'Waiting for the server', active = 'On', cooldown = 'On cooldown',
  mana = 'Not enough mana', reserve = 'Keeping the mana reserve', nofight = 'Waits for a fight',
  noparty = 'Needs a party', level = 'Cannot cast it yet', backoff = 'Refused, waiting', pending = 'Waiting for the answer',
  group = 'Waiting for another spell', rate = 'Rate limit', casting = 'An attack spell is charging', off = 'Off',
  unknown = 'Spell not found', nobar = 'Needs the Buff Bar', useroff = 'You switched it off',
  full = 'Summons at the limit', have = 'Already out', nocount = 'Cannot count summons',
}
local OVERALL_TEXT = {
  pz = 'Paused: protection zone', helperoff = 'The helper is off', disabled = 'Support spells are off',
  useroff = 'You switched a vigil off: its row is unticked. Tick it to let the helper keep it on.',
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
local function spellEntry(id)
  local H = helper()
  if H and H.getSpellDataById then
    local ok, s = pcall(H.getSpellDataById, id)
    if ok and s then return s end
  end
  if Spells and Spells.getSpellDataById then return Spells.getSpellDataById(id) end
  return nil
end

local save
local function load()
  local name = charName()
  if not name then return false end
  if cfgFor == name then return true end
  local node = g_settings.getNode(SETTINGS_NODE)
  cfg = S.sanitize(type(node) == 'table' and node[name] or nil) -- checked: config.otml can be edited by hand
  cfgFor = name
  state = S.newState()
  userOffNote = false
  -- rows that can never work again leave the list: utilities (Lantern, Ghost Rope...), retired spells (Galeborne Stride)
  -- and ids that are attack spells now (S.deadReason)
  local slots, dropped = S.dropUtilities(cfg.slots, spellEntry)
  if dropped > 0 then
    cfg.slots = slots
    save()
  end
  return true
end

save = function()
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
  slots = S.dropUtilities(slots, spellEntry) -- a utility never gets in, whoever asks (Auto setup, 'add' mode)
  cfg = S.sanitize({ enabled = enabled == nil and cfg.enabled or enabled, reserve = cfg.reserve, slots = slots })
  state = S.newState()
  save()
  U.rebuild()
end

-- ---------------------------------------------------------------- the spell table
local function spellList()
  -- the client's table is a map name -> entry; S.entries gives every entry its name (the key) and drops nothing
  local list = Spells and Spells.getSpellList and Spells.getSpellList() or nil
  if type(list) ~= 'table' or next(list) == nil then list = SpellInfo and SpellInfo.Default or {} end
  return S.entries(list)
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
  -- dead (the death screen): every buff drops at once, which read as the player switching the vigils off (their rows
  -- were unticked and saved, owner 2026-10-22: "after dying the list is gone"). Nothing is cast or tracked until the
  -- next login (onGameStart starts a new state).
  local me = g_game.getLocalPlayer()
  if not me or (me.isDead and me:isDead()) or (tonumber(me:getHealth()) or 1) <= 0 then
    S.reset(state)
    overall = ''
    return
  end
  if #cfg.slots == 0 or not cfg.enabled then
    state.status = {}
    overall = cfg.enabled and '' or 'disabled'
    return
  end
  local ctx, rotation = castChecks()
  local spell, why = S.pick(state, cfg, ctx)
  overall = spell and '' or (why ~= 'idle' and why or '')
  -- a vigil the player switched off by hand: its row is unticked and saved (no recast now or after a relog)
  if #S.takeUserOff(state, cfg, ctx.now) > 0 then
    save()
    U.rebuild()
    userOffNote = true
  end
  if userOffNote and overall == '' then overall = 'useroff' end
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
local function host() local r = root() return r and r:recursiveGetChildById(U.HOST_ID) end

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
      -- a spell just picked in an empty row (its box is greyed) starts ticked
      local box = row:getChildById('enable')
      slots[#slots + 1] = { id = id, enabled = (not box:isEnabled()) or box:isChecked() }
    end
  end
  cfg.slots = slots
end

local function changed()
  if building then return end
  readRows()
  state = S.newState()
  userOffNote = false
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
    -- an empty row's box is unticked and greyed (a ticked box that ignores clicks read as broken, owner 2026-10-21);
    -- picking a spell in the row ticks it
    row:getChildById('enable'):setChecked(slot ~= nil and slot.enabled)
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

-- the panel fills the Support tab's host; the helper shows or hides the host with its tab
function U.addTab()
  local h = host()
  if not h then return false end
  if panel() then return true end
  if not importStyles() then return false end
  local p = buildPanel(h)
  if not p then return false end
  p:addAnchor(AnchorTop, 'parent', AnchorTop)
  p:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  p:addAnchor(AnchorRight, 'parent', AnchorRight)
  p:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  p:show()
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
  local p = panel()
  if p then p:destroy() end
end
