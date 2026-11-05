-- Marks over the heads of NPCs (O415): a gold "!" over an NPC that has a quest this character can start, a gold "?" over
-- one it has a step to turn in or report to, a grey "!" over one with a quest that waits for a level. The server
-- (poi.lua, action npcmarks of extended opcode 153) names the NPCs; this file matches them by name against the NPCs on
-- screen and puts one small image over each, above its name. Pure overlay: a phantom widget per marked NPC in view on
-- the map panel, placed every frame from the camera and the walk offsets (npcmarkmath.lua, the same maths as the NPC
-- dialogue's bubble), so it follows the NPC and the camera while either walks, is hidden on another floor and when the
-- NPC leaves the screen, and costs nothing while no marked NPC is in view. Switched by the setting `npcmarks` of the map
-- marker settings (mapmarkers.lua setNpcMarks).
NpcMarks = {}
local N = NpcMarks
local M = NpcMarkMath

local state = {}      -- NPC name (lower case) -> mark kind, from the server
local creatures = {}  -- creature id -> {name, creature}: the NPCs the client knows
local widgets = {}    -- creature id -> widget
local tracks = {}     -- creature id -> {pos, from}: the last step of a creature (its walk offset)
local enabled = true
local tickEvent

local DIRS = { ['0,-1'] = 0, ['1,0'] = 1, ['0,1'] = 2, ['-1,0'] = 3, ['1,-1'] = 4, ['1,1'] = 5, ['-1,1'] = 6, ['-1,-1'] = 7 }

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function mapPanel()
  local gi = modules.game_interface
  return gi and gi.getMapPanel and gi.getMapPanel()
end

local function destroyWidget(id)
  local w = widgets[id]
  if alive(w) then w:destroy() end
  widgets[id] = nil
end

local function hideAll()
  for _, w in pairs(widgets) do
    if alive(w) then w:hide() end
  end
end

local function clearWidgets()
  for id in pairs(widgets) do destroyWidget(id) end
end

-- ---------------------------------------------------------------- walk offsets
local function trackOf(creature)
  local id = creature:getId()
  local pos = creature:getPosition()
  local t = tracks[id]
  if not t then
    t = { pos = pos }
    tracks[id] = t
  elseif pos and t.pos and (pos.x ~= t.pos.x or pos.y ~= t.pos.y or pos.z ~= t.pos.z) then
    t.from, t.pos = t.pos, pos
  end
  return t
end

local function walkOffset(creature, spriteSize)
  local t = trackOf(creature)
  if not t.from or not creature:isWalking() then return { x = 0, y = 0 } end
  local dir = DIRS[(t.pos.x - t.from.x) .. ',' .. (t.pos.y - t.from.y)]
  if not dir then return { x = 0, y = 0 } end
  local duration = creature:getStepDuration(false, dir)
  local progress = duration and duration > 0 and creature:getWalkTicksElapsed() / duration or 1
  local x, y = M.walkOffset(t.from, t.pos, progress, spriteSize)
  return { x = x, y = y }
end

-- ---------------------------------------------------------------- the widgets
local function widgetFor(id, mark, map)
  local w = widgets[id]
  if not alive(w) then
    w = g_ui.createWidget('NpcMark', map)
    widgets[id] = w
    w.mark = nil
  end
  if w.mark ~= mark then
    w.mark = mark
    w:setImageSource(M.image(mark))
  end
  return w
end

local function tick()
  tickEvent = nil
  if not enabled or not g_game.isOnline() then
    hideAll()
    return
  end
  local map = mapPanel()
  local player = g_game.getLocalPlayer()
  local list = M.wanted(state, creatures)
  if not map or not player or #list == 0 then
    hideAll()
    -- nothing to follow now: appearing creatures and server messages start the tick again
    return
  end
  local spriteSize = (g_sprites and g_sprites.spriteSize and g_sprites.spriteSize()) or 32
  local vis = map:getVisibleDimension()
  local panelRect = map.getPaddingRect and map:getPaddingRect() or map:getRect()
  local keep = map.isKeepAspectRatioEnabled and map:isKeepAspectRatioEnabled()
  local rect = M.mapRect(panelRect, vis, keep, spriteSize)
  local stretch = M.stretch(rect, vis, spriteSize)
  local cam = map:getCameraPosition() or player:getPosition()
  local camOff = walkOffset(player, spriteSize)
  local shown = {}
  for _, e in ipairs(list) do
    local entry = creatures[e.id]
    local c = entry and entry.creature
    local drawn = false
    if c and not c:isRemoved() then
      local center = M.tileCenter(rect, stretch, spriteSize, cam, camOff, c:getPosition(), walkOffset(c, spriteSize))
      if center then
        local dispY = 8
        local okType, thingType = pcall(g_things.getThingType, (c:getOutfit() or {}).type or 0, ThingCategoryCreature)
        if okType and thingType and thingType.getDisplacementY then dispY = thingType:getDisplacementY() end
        local lift = c.getInformationLift and c:getInformationLift() or 0
        local x, y, w, h = M.place(rect, stretch, spriteSize, center, dispY, lift, 2)
        if x then
          local widget = widgetFor(e.id, e.mark, map)
          widget:setSize({ width = w, height = h })
          widget:setPosition({ x = x, y = y })
          widget:show()
          widget:raise()
          drawn = true
        end
      end
    end
    shown[e.id] = drawn
    if not drawn and alive(widgets[e.id]) then widgets[e.id]:hide() end
  end
  -- a widget of an NPC that lost its mark or is gone
  for id in pairs(widgets) do
    if shown[id] == nil then destroyWidget(id) end
  end
  tickEvent = scheduleEvent(tick, M.TICK_MS)
end

local function wake()
  if enabled and not tickEvent then tickEvent = scheduleEvent(tick, 0) end
end

-- ---------------------------------------------------------------- the NPCs of the screen
local function onAppear(creature)
  if not creature:isNpc() then return end
  creatures[creature:getId()] = { name = creature:getName() or '', creature = creature }
  wake()
end

local function onDisappear(creature)
  local id = creature:getId()
  if creatures[id] then
    creatures[id] = nil
    tracks[id] = nil
    destroyWidget(id)
  end
end

local function scan()
  local player = g_game.getLocalPlayer()
  if not player then return end
  for _, c in ipairs(g_map.getSpectators(player:getPosition(), false) or {}) do
    if c:isNpc() then creatures[c:getId()] = { name = c:getName() or '', creature = c } end
  end
end

-- ---------------------------------------------------------------- the server and the settings
-- action npcmarks {full, set = [{n, m}], clear = [n]}
function N.onMessage(data)
  M.apply(state, M.parse(data))
  if enabled then
    scan()
    wake()
  end
end

function N.setEnabled(on)
  enabled = on == true
  if enabled then
    scan()
    wake()
  else
    if tickEvent then removeEvent(tickEvent) tickEvent = nil end
    clearWidgets()
  end
end

function N.reset()
  state, creatures, tracks = {}, {}, {}
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  clearWidgets()
end

function N.init(on)
  enabled = on ~= false
  connect(Creature, { onAppear = onAppear, onDisappear = onDisappear })
end

function N.terminate()
  disconnect(Creature, { onAppear = onAppear, onDisappear = onDisappear })
  N.reset()
end

-- for tests and the live check: what is marked and drawn
function N.debugState()
  local marks, shown = {}, 0
  for k, v in pairs(state) do marks[#marks + 1] = k .. '=' .. v end
  table.sort(marks)
  for _, w in pairs(widgets) do if alive(w) and w:isVisible() then shown = shown + 1 end end
  local n = 0
  for _ in pairs(creatures) do n = n + 1 end
  return { marks = table.concat(marks, ' '), npcs = n, shown = shown, enabled = enabled }
end
