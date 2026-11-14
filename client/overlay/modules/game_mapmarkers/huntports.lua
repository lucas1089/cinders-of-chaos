-- Hunt teleport markers on the minimap and the full map (O568; owner 2026-11-14: "put a marker on the map where the
-- hunts' teleports are, so I know where to go back"). The rules are in huntportmath.lua (huntportmath_test.lua); this
-- file keeps the list the server sent (poi.lua action huntports of extended opcode 153, once after the hello), the
-- character's own state, and draws one small widget per marker in the minimap marker layer that mapmarkers.lua owns
-- (it calls HuntPorts.draw from its own place()):
--   * every hall teleport into a hunt (a plain gate), the one the character last used or came out of gold and pulsing
--   * the way out of each hunt the character has entered (a plain door), the one of the hunt it stands in blue and pulsing
-- The state (last, used) comes from the character's own steps (HuntPortMath.track) and is kept per character in the
-- g_settings node 'huntPorts'; the hunt it stands in is never saved. Hover: the hunt, its levels, what the marker is.
-- Switched by the setting `huntports` of the map marker settings (mapmarkers.lua setHuntPorts). No engine patch.
HuntPorts = {}
local H = HuntPorts
local M = HuntPortMath

local ports = {}       -- the clean list from the server
local state = M.newState()
local charName         -- the character the state belongs to
local pool = {}
local pulsing = {}     -- the widgets of the highlighted markers drawn now
local pulseEvent
local enabled = true
local lastPos

local function alive(w)
  return w and not w:isDestroyed()
end

local function myName()
  local p = g_game.getLocalPlayer()
  return p and p:getName() or nil
end

local function stopPulse()
  if pulseEvent then removeEvent(pulseEvent) pulseEvent = nil end
end

local function pulse()
  local o = M.pulse(g_clock.millis())
  for _, w in ipairs(pulsing) do
    if alive(w) then w:setOpacity(o) end
  end
end

local function startPulse()
  if pulseEvent then return end
  pulseEvent = cycleEvent(pulse, M.PULSE_TICK_MS)
end

local function widget(i, layer)
  local w = pool[i]
  if not alive(w) then
    w = g_ui.createWidget('MapMarkerHuntPort', layer)
    pool[i] = w
  end
  return w
end

local function save()
  if not charName then return end
  g_settings.setNode('huntPorts', M.save(g_settings.getNode('huntPorts'), charName, state))
end

-- ---------------------------------------------------------------- drawing
-- env = {minimap, layer, cam, rect, scale, hits}: the minimap widget, the marker layer, the camera, the drawn part of the
-- minimap, its scale (pixels a tile) and the hit list for the hover text; returns how many widgets are shown
function H.draw(env)
  pulsing = {}
  local shown = 0
  if enabled and #ports > 0 then
    local b = MapMarkerMath.viewBounds(env.cam, env.rect.width, env.rect.height, env.scale, 1)
    for _, m in ipairs(M.markers(ports, state, b, env.scale, 120)) do
      local pt = env.minimap:getTilePoint({ x = m.x, y = m.y, z = env.cam.z })
      if pt and pt.x >= env.rect.x and pt.y >= env.rect.y and pt.x < env.rect.x + env.rect.width
          and pt.y < env.rect.y + env.rect.height then
        shown = shown + 1
        local w = widget(shown, env.layer)
        local size = M.size(m.highlighted)
        if w.image ~= m.image then
          w:setImageSource(M.ICONS .. m.image)
          w.image = m.image
        end
        w:setSize({ width = size, height = size })
        local x, y = pt.x - math.floor(size / 2), pt.y - math.floor(size / 2)
        w:setPosition({ x = x, y = y })
        w:setOpacity(1)
        w:show()
        w:raise()
        if m.highlighted then pulsing[#pulsing + 1] = w end
        env.hits[#env.hits + 1] = { rect = { x = x, y = y, width = size, height = size }, text = m.text }
      end
    end
  end
  for i = shown + 1, #pool do
    if alive(pool[i]) then pool[i]:hide() end
  end
  if #pulsing > 0 then startPulse() pulse() else stopPulse() end
  return shown
end

-- ---------------------------------------------------------------- the server, the steps, the settings
-- action huntports {ports = [...]}
function H.onMessage(data)
  ports = M.parse(data)
  M.track(state, ports, nil, lastPos or (g_game.getLocalPlayer() and g_game.getLocalPlayer():getPosition()))
end

-- the character's position changed; true when the markers should be drawn again
function H.onMove(prev, cur)
  lastPos = cur
  if #ports == 0 then return false end
  local changed = M.track(state, ports, prev, cur)
  if changed then save() end
  return changed
end

function H.onGameStart()
  charName = myName()
  state = M.load(g_settings.getNode('huntPorts'), charName)
  local p = g_game.getLocalPlayer()
  lastPos = p and p:getPosition() or nil
end

function H.onGameEnd()
  save()
  ports, state, charName, lastPos = {}, M.newState(), nil, nil
  pulsing = {}
  stopPulse()
  for _, w in pairs(pool) do
    if alive(w) then w:destroy() end
  end
  pool = {}
end

function H.setEnabled(on)
  enabled = on == true
  if not enabled then
    pulsing = {}
    stopPulse()
  end
end

function H.init(on)
  enabled = on ~= false
end

function H.terminate()
  H.onGameEnd()
end

-- for tests and the live check: what the client knows and shows
function H.debugState()
  local shown = 0
  for _, w in pairs(pool) do
    if alive(w) and w:isVisible() then shown = shown + 1 end
  end
  local used = 0
  for _ in pairs(state.used) do used = used + 1 end
  return { ports = #ports, last = state.last, here = state.here, used = used, shown = shown, enabled = enabled }
end
