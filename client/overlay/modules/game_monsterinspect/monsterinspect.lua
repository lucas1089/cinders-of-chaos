-- Inspect Monster window (O721). Opened from the right-click menu of a monster ("Inspect", pt-BR "Inspecionar", next to
-- Look) and by Shift + left click on a monster. Server: server/data/scripts/chaos/monster_inspect.lua, extended opcode 166
-- (JSON {action, data}); the rows are built by monsterinspect_logic.lua from what the server sends, nothing is guessed here.
--   client -> server  inspect {cid}
--   server -> client  result {...}   denied {code}
-- Look (Shift + right click, the menu entry) stays what it was; the Shift + left click is the only click this changes, and
-- only on a monster: a player, an NPC, an item and every other click go to the base handler (game_interface
-- processMouseAction, wrapped the way game_rightclickequip does).

local OPCODE = 166
local L = MonsterInspectLogic

local window
local lastCid
local hooked = false
local original, wrapped
local chunkParts = {}

local function safe(name, fn)
  local reported = false
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported then
        reported = true
        g_logger.warning('[monsterinspect] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function setStatus(text, color)
  if not window then return end
  window.statusLabel:setText(text or '')
  window.statusLabel:setColor(color or L.COLORS.dim)
end

-- ---------------------------------------------------------------- drawing a result
local function clearList()
  window.listPanel.list:destroyChildren()
end

local function fillList(sections)
  local list = window.listPanel.list
  list:destroyChildren()
  for _, section in ipairs(sections) do
    local head = g_ui.createWidget('MonsterInspectSection', list)
    head.title:setText(section.title)
    for _, r in ipairs(section.rows) do
      if r.note then
        local w = g_ui.createWidget('MonsterInspectNote', list)
        w:setText(r.note)
        w:setColor(r.color)
      else
        local w = g_ui.createWidget('MonsterInspectRow', list)
        w.name:setText(r.label)
        w.name:setColor(L.COLORS.text)
        w.value:setText(r.value or '')
        w.value:setColor(r.color)
        if r.tip then w:setTooltip(r.tip) end
      end
    end
  end
end

local function setHeader(d)
  local h = L.header(d)
  window.headPanel.monsterName:setText(h.name)
  window.headPanel.levelLine:setText(h.level or '')
  window.headPanel.flagsLine:setText(h.flags or '')
  window.headPanel.healthBar:setPercent(h.pct)
  window.headPanel.healthBar:setText(h.health)
  window.headPanel.healthBar:setBackgroundColor(h.color)
  local o = type(d.outfit) == 'table' and d.outfit or {}
  window.headPanel.creature:setOutfit({ type = o.lookType or 0, head = o.lookHead, body = o.lookBody, legs = o.lookLegs,
    feet = o.lookFeet, addons = o.lookAddons })
end

local function showResult(d)
  if lastCid and tonumber(d.cid) ~= lastCid then return end -- an answer to an earlier request
  setHeader(d)
  fillList(L.sections(d))
  setStatus('', nil)
end

local function showDenied(d)
  clearList()
  setStatus(L.deniedText(d.code), L.COLORS.red)
end

local function onExtendedOpcode(protocol, opcode, buffer)
  buffer = L.joinPart(chunkParts, buffer)
  if not buffer or not window then return end
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' or type(msg.data) ~= 'table' then return end
  if msg.action == 'result' then
    showResult(msg.data)
  elseif msg.action == 'denied' then
    showDenied(msg.data)
  end
end

-- ---------------------------------------------------------------- window and requests
function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
end

function hide()
  if window then window:hide() end
end

function refresh()
  if lastCid then send('inspect', { cid = lastCid }) setStatus(tr('Inspecting...'), L.COLORS.dim) end
end

function inspectCreature(creature)
  if not window or not L.isMonster(creature) then return false end
  lastCid = creature:getId()
  chunkParts = {}
  setStatus(tr('Inspecting...'), L.COLORS.dim)
  window.headPanel.monsterName:setText(creature:getName())
  window.headPanel.levelLine:setText('')
  window.headPanel.flagsLine:setText('')
  window.headPanel.healthBar:setPercent(0)
  window.headPanel.healthBar:setText('')
  clearList()
  show()
  send('inspect', { cid = lastCid })
  return true
end

-- ---------------------------------------------------------------- the menu entry and the click
local function addMenuEntry()
  local gi = modules.game_interface
  if hooked or not gi or not gi.addMenuHook then return end
  gi.addMenuHook('chaosInspectMonster', tr('Inspect'),
    function(menuPosition, lookThing, useThing, creatureThing) inspectCreature(creatureThing) end,
    function(menuPosition, lookThing, useThing, creatureThing) return L.isMonster(creatureThing) end)
  hooked = true
end

-- the base handler's arguments: (tile, menuPosition, mouseButton, autoWalkPos, lookThing, useThing, creatureThing, ...)
local function inspectClick(mouseButton, creatureThing)
  local mods = { ctrl = g_keyboard.isCtrlPressed(), shift = g_keyboard.isShiftPressed(), alt = g_keyboard.isAltPressed() }
  if not L.shouldInspectClick(mouseButton, MouseLeftButton, mods, creatureThing) then return false end
  return inspectCreature(creatureThing)
end

local function wrapClicks()
  local gi = modules.game_interface
  if wrapped or not gi or not gi.processMouseAction then return end
  original = gi.processMouseAction
  local check = safe('click', inspectClick)
  wrapped = function(tile, menuPosition, mouseButton, ...)
    local creatureThing = select(4, ...)
    if check(mouseButton, creatureThing) then return true end
    return original(tile, menuPosition, mouseButton, ...)
  end
  gi.processMouseAction = wrapped
end

local function onGameEnd()
  hide()
  lastCid = nil
  chunkParts = {}
end

function init()
  window = g_ui.displayUI('monsterinspect')
  window:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE, safe('opcode', onExtendedOpcode))
  connect(g_game, { onGameEnd = onGameEnd })
  addMenuEntry()
  wrapClicks()
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  local gi = modules.game_interface
  if hooked and gi and gi.removeMenuHook then gi.removeMenuHook('chaosInspectMonster') end
  hooked = false
  if gi and wrapped and gi.processMouseAction == wrapped then gi.processMouseAction = original end
  wrapped, original = nil, nil
  if window then
    window:destroy()
    window = nil
  end
end
