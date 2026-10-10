-- Cast bar: a bar over the character while a cast-time spell is cast (server data/lib/chaos_casting.lua, scripts
-- casting.lua, extended opcode 231) and while the Town Portal channels (game_townportal hands its bar here). It fills on
-- the client's clock from the time the server gave; the server alone decides when the cast completes or is interrupted
-- (start / end). An interrupted cast turns red with the reason for a moment. Smaller bars over other players in view
-- show their casts (other / otherEnd). Clicking your own bar asks the server to cancel the cast (the mana and cooldown
-- come back, as when moving). Pure parts: castbarmath.lua (castbarmath_test.lua).

local OPCODE = 231
local TICK_MS = 50
local SHOW_RESULT_MS = 900
local LOST_END_MS = 3000
local M = CastbarMath

local mine        -- { widget, name, ms, start, serial, kind = 'spell' | 'portal', endAt, result }
local others = {} -- creature id -> { widget, name, ms, start, endAt }
local tickEvent

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function mapPanel()
  local gi = modules.game_interface
  return gi and gi.getMapPanel and gi.getMapPanel()
end

local function destroyBar(entry)
  if entry and alive(entry.widget) then entry.widget:destroy() end
end

local function makeBar(style)
  local map = mapPanel()
  if not map then return nil end
  local w = g_ui.createWidget(style, map)
  return w
end

local function placeBar(w, dx, dy, lift)
  local map = mapPanel()
  if not map or not alive(w) then return false end
  local rect = map:getRect()
  local vd = map:getVisibleDimension()
  local keep = map.isKeepAspectRatioEnabled and map:isKeepAspectRatioEnabled()
  local x, y = M.place(rect, vd, keep, dx, dy, w:getWidth(), w:getHeight(), lift)
  if not x then return false end
  w:setPosition({ x = x, y = y })
  return true
end

local function tick()
  tickEvent = nil
  if not g_game.isOnline() then return end
  local now = g_clock.millis()
  local busy = false
  if mine then
    busy = true
    local w = mine.widget
    if not mine.endAt and now - mine.start > mine.ms + LOST_END_MS then
      endLocal('done') -- the end never came (a lost message): do not leave the bar on screen
    end
    if mine.endAt then
      if now >= mine.endAt then
        destroyBar(mine)
        mine = nil
      end
    elseif alive(w) then
      local elapsed = now - mine.start
      w.bar:setPercent(math.floor(M.progress(mine.start, mine.ms, now) * 100))
      w.bar:setText(M.label(mine.name, mine.ms, elapsed))
    end
    if mine and alive(mine.widget) then
      -- above the character's name and health bar
      if not placeBar(mine.widget, 0, 0, 1.35) then mine.widget:hide() else mine.widget:show() end
    end
  end
  local player = g_game.getLocalPlayer()
  local ppos = player and player:getPosition()
  for cid, o in pairs(others) do
    busy = true
    local c = g_map.getCreatureById(cid)
    local cpos = c and c:getPosition()
    if (o.endAt and now >= o.endAt) or not c or not ppos or not cpos or cpos.z ~= ppos.z or now - o.start > o.ms + 3000 then
      destroyBar(o)
      others[cid] = nil
    elseif alive(o.widget) then
      if not o.endAt then o.widget.bar:setPercent(math.floor(M.progress(o.start, o.ms, now) * 100)) end
      if placeBar(o.widget, cpos.x - ppos.x, cpos.y - ppos.y, 1.2) then o.widget:show() else o.widget:hide() end
    end
  end
  if busy then tickEvent = scheduleEvent(tick, TICK_MS) end
end

local function ensureTick()
  if not tickEvent then tickEvent = scheduleEvent(tick, 0) end
end

-- ---------------------------------------------------------------- own bar (also used by game_townportal)
function startLocal(name, ms, kind, serial)
  destroyBar(mine)
  local w = makeBar('CastBar')
  if not w then return end
  w.bar:setBackgroundColor(kind == 'portal' and M.COLOR.portal or M.COLOR.casting)
  w.bar:setPercent(0)
  w.onClick = function()
    if mine and mine.kind == 'spell' and not mine.endAt then
      local protocol = g_game.getProtocolGame()
      if protocol then protocol:sendExtendedOpcode(OPCODE, json.encode({ action = 'cancel' })) end
    end
  end
  mine = { widget = w, name = name, ms = ms, start = g_clock.millis(), serial = serial, kind = kind or 'spell' }
  w:raise()
  ensureTick()
  tick()
end

function endLocal(result, serial, kind)
  if not mine or mine.endAt or (serial and mine.serial and serial ~= mine.serial) or (kind and mine.kind ~= kind) then return end
  local w = mine.widget
  mine.endAt = g_clock.millis() + (result == 'done' and 250 or SHOW_RESULT_MS)
  mine.result = result
  if alive(w) then
    if result == 'done' then
      w.bar:setPercent(100)
      w.bar:setBackgroundColor(M.COLOR.done)
      w.bar:setText(mine.name)
    else
      w.bar:setPercent(100)
      w.bar:setBackgroundColor(M.COLOR.interrupted)
      w.bar:setText(M.resultText(result))
    end
  end
  ensureTick()
end

function isCasting()
  return mine ~= nil and mine.endAt == nil
end

-- ---------------------------------------------------------------- other players
local function startOther(cid, name, ms)
  destroyBar(others[cid])
  local w = makeBar('OtherCastBar')
  if not w then return end
  w.bar:setText(name)
  w.bar:setPercent(0)
  w:hide()
  others[cid] = { widget = w, name = name, ms = ms, start = g_clock.millis() }
  ensureTick()
end

local function endOther(cid, result)
  local o = others[cid]
  if not o then return end
  o.endAt = g_clock.millis() + (result == 'done' and 200 or 600)
  if alive(o.widget) then
    o.widget.bar:setPercent(100)
    if result ~= 'done' then o.widget.bar:setBackgroundColor(M.COLOR.interrupted) end
  end
end

-- ---------------------------------------------------------------- protocol
local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, raw = pcall(json.decode, buffer)
  local msg = ok and M.parse(raw) or nil
  if not msg then return end
  if msg.action == 'start' then
    startLocal(msg.name, msg.ms, 'spell', msg.serial)
  elseif msg.action == 'end' then
    endLocal(msg.result, msg.serial)
  elseif msg.action == 'other' then
    startOther(msg.cid, msg.name, msg.ms)
  elseif msg.action == 'otherEnd' then
    endOther(msg.cid, msg.result)
  end
end

local function clearAll()
  destroyBar(mine)
  mine = nil
  for cid, o in pairs(others) do destroyBar(o) end
  others = {}
  if tickEvent then removeEvent(tickEvent) end
  tickEvent = nil
end

function init()
  g_ui.importStyle('castbar')
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = clearAll })
end

function terminate()
  disconnect(g_game, { onGameEnd = clearAll })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  clearAll()
end
