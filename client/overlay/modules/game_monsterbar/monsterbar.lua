-- game_monsterbar: top-of-map health bar for the creature you are attacking, and the boss cast bar under it (the next
-- boss mechanic and its timer, action "mech" on the same opcode; monsterbarmech.lua).
-- The tier comes from the server (monster_tiers.lua, opcode 125); until the answer arrives the
-- bar looks like a normal monster's. It sits at the top of the part of the game view on screen
-- (monsterbarmath.lua): in the extended view the map panel starts above the window.

local OPCODE = 125
local S = MonsterBarStyle
local FILL_W = 344 -- the socket (monsterbar.otui, gen_monsterbar_art.py)
local TRAIL_TICK = 30 -- ms

local window, current
local mechWindow, mechCast, mechEvent -- the boss cast bar (monsterbarmech.lua): its widget, the cast, its redraw
local MECH_W = 344
local MECH_TICK = 50 -- ms
local tierOf, modsOf, roleOf, levelOf, labelOf = {}, {}, {}, {}, {}
local trail, trailEvent, lastPercent -- the damage trail and the health it last saw

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function themeFont(widget, role)
  local theme = modules.client_chaos_theme and modules.client_chaos_theme.ChaosTheme
  if theme and theme.applyFont then theme.applyFont(widget, role) end
end

local function setWidthClip(widget, px)
  widget:setVisible(px > 0)
  if px > 0 then
    widget:setWidth(px)
    widget:setImageClip({ x = 0, y = 0, width = px, height = widget:getHeight() })
  end
end

local NAME_MAX = 300 -- widest name plate (the level plate goes left of it, all inside the 420 px bar)

local function textWidth(label)
  return label.getTextSize and label:getTextSize().width or label:getWidth()
end

local PLATE_PAD = 28 -- the plate's 9-slice borders and a little air around the text

-- the width of `text` in `label`'s font (the label keeps the text it ends with)
local function measureWith(label)
  return function(text)
    label:setText(text)
    return textWidth(label)
  end
end

local function fitPlate(plate, label, minW, maxW)
  local w = textWidth(label) + PLATE_PAD
  plate:setWidth(math.max(minW, math.min(maxW, w)))
end

local function setMods(mods)
  local box = window:getChildById('mods')
  box:destroyChildren()
  for _, name in ipairs(type(mods) == 'table' and mods or {}) do
    local image, tip = S.mod(name)
    local chip = g_ui.createWidget('MonsterBarModChip', box)
    chip:setImageSource(image)
    chip:setTooltip(tip)
  end
  box:setVisible(box:getChildCount() > 0)
end

-- the whole bar for `info` = { name, tier, role, label, level, mods } (also used by preview())
local function paintInfo(info)
  local key = S.key(info.tier, info.role)
  local st = S.STYLES[key]
  local img = S.images(key)
  window:getChildById('frame'):setImageSource(img.frame)
  window:getChildById('fill'):setImageSource(img.fill)
  local name = window:getChildById('name')
  -- a long title drops its tag (the frame tells the tier); a name too long for the plate is cut with '...'
  name:setText(S.fitTitle(key, info.label, info.name, measureWith(name), NAME_MAX - PLATE_PAD))
  name:setColor(st.name)
  local plate = window:getChildById('namePlate')
  plate:setImageSource(img.plaque)
  fitPlate(plate, name, 120, NAME_MAX)
  local levelText = S.levelText(info.level)
  local levelPlate, level = window:getChildById('levelPlate'), window:getChildById('level')
  levelPlate:setVisible(levelText ~= nil)
  level:setVisible(levelText ~= nil)
  if levelText then
    level:setText(levelText)
    levelPlate:setImageSource(img.plaque)
    fitPlate(levelPlate, level, 44, 80)
  end
  setMods(info.mods)
end

local function paint(creature)
  if not window or creature ~= current then
    return
  end
  local id = creature:getId()
  paintInfo({ name = creature:getName(), tier = tierOf[id] or 'normal', role = roleOf[id], label = labelOf[id],
    level = levelOf[id], mods = modsOf[id] })
end

local function drawHealth(percent)
  setWidthClip(window:getChildById('fill'), S.fillWidth(percent, FILL_W))
  setWidthClip(window:getChildById('trail'), S.fillWidth(trail and trail.value or percent, FILL_W))
  window:getChildById('percent'):setText(S.percentText(percent))
end

local function stopTrail()
  if trailEvent then
    removeEvent(trailEvent)
    trailEvent = nil
  end
end

-- the damage trail shrinks toward the health (MonsterBarStyle.trailStep) while the bar shows
local function runTrail()
  if trailEvent then
    return
  end
  trailEvent = cycleEvent(function()
    if not window or not current or not trail then
      stopTrail()
      return
    end
    local health = current:getHealthPercent()
    local moving
    trail, moving = S.trailStep(trail, health, TRAIL_TICK)
    setWidthClip(window:getChildById('trail'), S.fillWidth(trail.value, FILL_W))
    if not moving then
      stopTrail()
    end
  end, TRAIL_TICK)
end

-- bosses are drawn this much bigger than ordinary monsters (needs base patch 0020, Creature:setDrawScale)
local BOSS_SCALE = 1.5

-- in-world label: modifiers on a line above the name, name (and the engine's small bar) coloured by tier
local function labelCreature(creature, tier, mods, role)
  if not creature then
    return
  end
  if creature.setDrawScale then
    creature:setDrawScale((tier == 'boss' or role == 'omen') and BOSS_SCALE or 1)
  end
  local st = S.STYLES[S.key(tier, role)]
  if not st.world then
    return
  end
  creature:setInformationColor(st.world)
  if mods and #mods > 0 then
    -- two modifiers per line keeps the label about as wide as the monster's name
    local lines = {}
    for i = 1, #mods, 2 do
      lines[#lines + 1] = mods[i + 1] and (mods[i] .. ' - ' .. mods[i + 1]) or mods[i]
    end
    -- the bordered Chaos font: on grass, blood or spell effects the thin coloured text was hard to read (beta 2026-10-20)
    creature:setTitle(table.concat(lines, '\n'), 'chaos-outline-11px', st.world)
  end
end

-- at the top of the part of the game view that is on screen (MonsterBarMath.place)
local function place()
  local gi = modules.game_interface
  local mapPanel = window and window:getParent()
  local root = gi and gi.getRootPanel and gi.getRootPanel()
  if not mapPanel or not root then
    return
  end
  local limits = MonsterBarMath.screenLimits(root:getRect(), function(id)
    local w = root:getChildById(id)
    if w and w:isVisible() and w:getWidth() > 0 and w:getHeight() > 0 then
      return w:getRect()
    end
  end)
  local avoid = {}
  local plate = rootWidget:recursiveGetChildById('chaosHud') -- the character plate (game_chaoshud)
  if plate and plate:isVisible() then
    avoid[#avoid + 1] = plate:getRect()
  end
  local top, offset = MonsterBarMath.place(mapPanel:getRect(), limits, window:getWidth(), window:getHeight(), nil, avoid)
  if window:getMarginTop() ~= top then
    window:setMarginTop(top)
  end
  if window:getMarginLeft() ~= offset then
    window:setMarginLeft(offset)
  end
end

-- the map panel moves and resizes with the window, the extended view and the side panels: place again a frame later
local placeEvent
local function schedulePlace()
  if placeEvent then
    return
  end
  placeEvent = scheduleEvent(function()
    placeEvent = nil
    if window and window:isVisible() then
      place()
    end
  end, 50)
end

local function updateHealth(creature, percent)
  if not window or creature ~= current then
    return
  end
  trail = S.trailHit(trail, lastPercent or percent, percent)
  lastPercent = percent
  drawHealth(percent)
  if trail.value > percent then
    runTrail()
  end
  if percent <= 0 then
    window:hide()
    stopTrail()
  end
end

local function onAttackingCreatureChange(creature)
  current = nil
  stopTrail()
  if not window then
    return
  end
  if not creature or not creature:isMonster() then
    window:hide()
    return
  end
  current = creature
  local percent = creature:getHealthPercent()
  trail, lastPercent = { value = percent, hold = 0 }, percent
  paint(creature)
  drawHealth(percent)
  place()
  window:show()
  if not tierOf[creature:getId()] then
    send('query', { cid = creature:getId() })
  end
end

-- the boss cast bar: under the monster bar while it shows, else in its place
local function placeMech()
  if not mechWindow then
    return
  end
  if window then
    place() -- the monster bar's margins for the current view, also while it is hidden (no target yet)
  end
  local top, left = MonsterBarMech.margins(window and window:isVisible(), window and window:getMarginTop() or 44,
    window and window:getMarginLeft() or 0)
  mechWindow:setMarginTop(top)
  mechWindow:setMarginLeft(left)
end

local function stopMech()
  if mechEvent then
    removeEvent(mechEvent)
    mechEvent = nil
  end
end

local function drawMech()
  if not mechWindow then
    return
  end
  local now = g_clock.millis()
  local st = MonsterBarMech.state(mechCast, now)
  if not st.visible then
    mechWindow:hide()
    mechCast = nil
    stopMech()
    return
  end
  local fill = mechWindow:getChildById('fill')
  fill:setWidth(math.max(0, MonsterBarMech.fillWidth(mechCast, now, MECH_W - 2)))
  fill:setBackgroundColor(MonsterBarMech.COLORS[mechCast.kind])
  mechWindow:getChildById('text'):setText(MonsterBarMech.text(mechCast, now))
  placeMech()
  mechWindow:show()
end

local function onMech(data)
  local cast = MonsterBarMech.start(data, g_clock.millis())
  if not cast then
    return
  end
  mechCast = MonsterBarMech.pick(mechCast, cast, g_clock.millis())
  drawMech()
  if not mechEvent then
    mechEvent = cycleEvent(drawMech, MECH_TICK)
  end
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if ok and type(msg) == 'table' and msg.action == 'mech' and type(msg.data) == 'table' then
    onMech(msg.data)
    return
  end
  if not ok or type(msg) ~= 'table' or msg.action ~= 'info' or type(msg.data) ~= 'table' then
    return
  end
  local d = msg.data
  tierOf[d.cid] = d.tier
  modsOf[d.cid] = d.mods
  roleOf[d.cid] = d.role
  labelOf[d.cid] = d.label
  levelOf[d.cid] = d.level or levelOf[d.cid]
  labelCreature(g_map.getCreatureById(d.cid), d.tier, d.mods, d.role)
  if current and current:getId() == d.cid then
    paint(current)
  end
end

local function onAppear(creature)
  local id = creature:getId()
  if tierOf[id] then
    labelCreature(creature, tierOf[id], modsOf[id], roleOf[id])
  end
end

local function onDisappear(creature)
  -- tier info stays cached (a monster that walks out of view and back keeps its label)
  if creature == current then
    current = nil
    if window then
      window:hide()
    end
  end
end

local function onGameEnd()
  tierOf, modsOf, roleOf, levelOf, labelOf = {}, {}, {}, {}, {}
  current = nil
  stopTrail()
  stopMech()
  mechCast = nil
  if mechWindow then
    mechWindow:hide()
  end
  if window then
    window:hide()
  end
end

function init()
  window = g_ui.loadUI('monsterbar', modules.game_interface.getMapPanel())
  mechWindow = g_ui.loadUI('monsterbarmech', modules.game_interface.getMapPanel())
  themeFont(window:getChildById('name'), 'heading')
  themeFont(window:getChildById('level'), 'heading')
  connect(modules.game_interface.getMapPanel(), { onGeometryChange = schedulePlace })
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onAttackingCreatureChange = onAttackingCreatureChange, onGameEnd = onGameEnd })
  connect(Creature, { onHealthPercentChange = updateHealth, onAppear = onAppear, onDisappear = onDisappear })
end

function terminate()
  disconnect(g_game, { onAttackingCreatureChange = onAttackingCreatureChange, onGameEnd = onGameEnd })
  disconnect(Creature, { onHealthPercentChange = updateHealth, onAppear = onAppear, onDisappear = onDisappear })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  stopTrail()
  stopMech()
  if mechWindow then
    mechWindow:destroy()
    mechWindow = nil
  end
  if placeEvent then
    removeEvent(placeEvent)
    placeEvent = nil
  end
  if window then
    local mapPanel = window:getParent()
    if mapPanel then
      disconnect(mapPanel, { onGeometryChange = schedulePlace })
    end
    window:destroy()
    window = nil
  end
end

-- the bar with made-up data, for screenshots and checks from a terminal (no target needed):
-- preview({ name = 'Dragon', tier = 'legendary', level = 245, mods = { 'Blazing' }, percent = 70, trail = 85 })
function preview(info)
  if not window then
    return
  end
  if not info then
    window:hide()
    return
  end
  stopTrail()
  current = nil
  paintInfo(info)
  trail, lastPercent = { value = info.trail or info.percent or 100, hold = 0 }, info.percent or 100
  drawHealth(info.percent or 100)
  place()
  window:show()
end

-- the cast bar with made-up data, for screenshots: previewMech({ boss = 'Kaelgor', label = 'Meteor Rain', ms = 2500,
-- kind = 'telegraph' }); nil hides it
function previewMech(data)
  if not data then
    mechCast = nil
    if mechWindow then mechWindow:hide() end
    stopMech()
    return
  end
  onMech(data)
end
