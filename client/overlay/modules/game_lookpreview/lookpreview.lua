-- The shared look preview panel (client/MANIFEST.md "Look preview"). A window gives it a fixed column and calls
--   local pv = modules.game_lookpreview.create(placeholder)    -- nil when the module or the placeholder is missing
--   pv:setOption(opt)      the row picked (LookPreviewCore option; nil: the character as worn)
--   pv:setHover(opt)       the row under the mouse, shown until pv:clearHover()
--   pv:setOwnOutfit(o)     draw this outfit as "own" instead of the local player's (nil: back to the player's)
--   pv:refresh()           redraw (the player's outfit changed)
--   pv:destroy()
-- Effects (option {kind = 'effects', play} of LookPreviewCore.fromPlayRow: spell skins, kill effects) play in a loop
-- on the stage around the creature, from the client's own sprites (see "the effect stage" below); a footprint option
-- with its art draws a few prints behind the walking creature.
--   modules.game_lookpreview.effectIcon(widget, spec, size)   a list icon: the effect's best frame, cropped and fitted
--   modules.game_lookpreview.fitCard(creatureWidget, outfit, w, h)   a list card's look facing south, filling the card
-- The look is drawn by the engine on a UICreature, the same way the map draws it: outfit, addons, colours, mount,
-- wings and aura are outfit fields, the outfit shader is the outfit's shader name (game_chaosshaders registers them),
-- the outline is game_cosmeticfx.applyOutline on the preview's creature (base patch 0038). Always 2x, the box of
-- everything drawn centred (LookPreviewCore.lookBox: the pixel bounds of CharSelectAnchors, else the thing's tiles
-- and displacement). Spell skins play on a scene of the player and a troll, kill effects on a troll that dies.
-- The controls (turn, slow turn, walk, simple figure) are one setting for every panel (g_settings node below).
-- The base Outfit window gets a panel too: see "the Outfit window" at the end.

local P = LookPreviewCore
local SETTINGS_NODE = 'chaosLookPreview'
local settings = { auto = false, walk = false, simple = false, compare = false }
local live = {}            -- open panels: handle -> true
local autoEvent

local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

local function num(v) return tonumber(v) or 0 end

local function loadSettings()
  local node = g_settings.getNode(SETTINGS_NODE)
  if type(node) == 'table' then
    settings.auto = node.auto == true
    settings.walk = node.walk == true
    settings.simple = node.simple == true
    settings.compare = node.compare == true
  end
end

local function saveSettings()
  g_settings.setNode(SETTINGS_NODE, { auto = settings.auto, walk = settings.walk, simple = settings.simple,
    compare = settings.compare })
end

-- ---------------------------------------------------------------- engine helpers
local function charselect()
  local m = modules.client_chaos_charselect
  if not m then return nil, nil end
  return m.CharSelectCore, m.CharSelectAnchors
end

-- the client's thing data of a creature thing: size, displacement, patterns and sprite ids (LookPreviewCore.lookBox
-- measures a look the anchors do not know from its tiles; canRide reads its pattern z). Read once per id.
local creatureThings = {}
local function thingInfo(id)
  id = num(id)
  if id <= 0 then return nil end
  local cached = creatureThings[id]
  if cached ~= nil then return cached or nil end
  local info = false
  local ok, t = pcall(function() return g_things.getThingType(id, ThingCategoryCreature) end)
  if ok and t then
    local function get(m) local okm, v = pcall(t[m], t) return okm and v or nil end
    local sprites = get('getSprites')
    info = { w = get('getWidth'), h = get('getHeight'), dx = get('getDisplacementX'), dy = get('getDisplacementY'),
      layers = get('getLayers'), px = get('getNumPatternX'), py = get('getNumPatternY'), pz = get('getNumPatternZ'),
      phases = get('getAnimationPhases'), sprites = type(sprites) == 'table' and sprites or nil }
  end
  creatureThings[id] = info
  return info or nil
end

-- can this look ride (Outfit::draw draws a mount only under a rider with the mounted pattern)
local function canRide(lookType)
  local info = thingInfo(lookType)
  if not info or info.pz == nil then return true end
  return num(info.pz) >= 2
end

local function anchorOf(id)
  local _, anchors = charselect()
  return anchors and P.anchorFrom(anchors[id]) or nil
end

-- the lift of a winged character (Outfit::draw with the feature GameWingOffset)
local function wingLift()
  local ok, on = pcall(function() return GameWingOffset and g_game.getFeature(GameWingOffset) end)
  return (ok and on) and 6 or 0
end

local function figureOf(outfit)
  local Core, anchors = charselect()
  local mounted = num(outfit.mount) > 0
  local fig
  if Core and type(Core.figure) == 'function' then
    local body = mounted and { type = outfit.mount, wings = outfit.wings, aura = outfit.aura } or outfit
    local ok, f = pcall(Core.figure, anchors or {}, body, thingInfo, wingLift())
    if ok then fig = f end
  end
  return P.fitFigure(fig, mounted)
end

-- the box of everything the engine draws of an outfit (LookPreviewCore.lookBox), for the panel's centring
local function boxOf(outfit)
  local ok, b = pcall(P.lookBox, outfit, anchorOf, thingInfo, wingLift())
  return ok and b or P.copy(P.FALLBACK_BOX)
end

-- is an outfit shader registered (the engine draws nothing for an unknown name)
local function shaderKnown(name)
  local asked = false
  if g_shaders and type(g_shaders.getShader) == 'function' then
    local ok, s = pcall(g_shaders.getShader, name)
    if ok then
      if s ~= nil then return true end
      asked = true
    end
  end
  -- the engine does not know the name (or cannot be asked): the store's own list of registered names decides, so a
  -- shader the client registers under another handle is not left off the preview
  local m = modules.game_chaosshaders
  local L = m and m.OutfitShaderList
  if L and type(L.LABELS) == 'table' then return L.LABELS[name] ~= nil end
  return not asked
end

local function cosmeticfx()
  local m = modules.game_cosmeticfx
  return m and type(m.applyOutline) == 'function' and m or nil
end

local function localOutfit()
  local me = g_game.isOnline() and g_game.getLocalPlayer() or nil
  return me and me:getOutfit() or nil
end

-- ---------------------------------------------------------------- list cards
-- The Outfit window's list buttons (base patch 0060): the look facing south, zoomed to fill the card's picture part
-- (w x h px from the card's top-left), feet and body placed from the sprite anchors like the panel's figure.
function fitCard(creatureWidget, outfit, w, h)
  if not alive(creatureWidget) or type(outfit) ~= 'table' then return false end
  local L = P.cardLayout(figureOf(outfit), w, h)
  pcall(creatureWidget.setCenter, creatureWidget, false)
  creatureWidget:breakAnchors()
  creatureWidget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  creatureWidget:addAnchor(AnchorTop, 'parent', AnchorTop)
  creatureWidget:setMarginLeft(L.x)
  creatureWidget:setMarginTop(L.y)
  creatureWidget:setMarginBottom(0)
  creatureWidget:setMarginRight(0)
  creatureWidget:setSize({ width = L.size, height = L.size })
  creatureWidget:setDirection(P.SOUTH)
  return true
end

-- ---------------------------------------------------------------- the panel
local Preview = {}
Preview.__index = Preview

-- ---------------------------------------------------------------- the effect stage (engine side)
-- LookPreviewCore "the effect stage" has the maths. A thing type is read once (size, patterns, frames, sprite ids);
-- each playing step is a holder widget of UISprite tiles in the stage's under or over layer, its sprites set per
-- frame (a sprite id is set only when it changes: UISprite makes a texture of it).
local FX_TICK_MS = 40
local fxEvent
local things = {}

local function readThing(id, missile)
  local key = (missile and 'm' or 'e') .. tostring(id)
  if things[key] ~= nil then return things[key] or nil end
  local info = false
  local ok, t = pcall(function()
    return g_things.getThingType(id, missile and ThingCategoryMissile or ThingCategoryEffect)
  end)
  if ok and t then
    local function get(m, d)
      local okm, v = pcall(t[m], t)
      return okm and v ~= nil and v or d
    end
    local sprites = get('getSprites', {})
    if type(sprites) == 'table' and #sprites > 0 then
      info = { w = get('getWidth', 1), h = get('getHeight', 1), layers = get('getLayers', 1),
        px = get('getNumPatternX', 1), py = get('getNumPatternY', 1), pz = get('getNumPatternZ', 1),
        phases = get('getAnimationPhases', 1), dispX = get('getDisplacementX', 0), dispY = get('getDisplacementY', 0),
        sprites = sprites }
    end
  end
  things[key] = info
  return info or nil
end

local function specInfo(spec)
  return type(spec) == 'table' and readThing(num(spec.id), spec.m ~= nil) or nil
end

-- drawn under the creatures in the game (base patch 0055 through game_groundfx): the same here
local function isGround(id)
  if g_map and type(g_map.isGroundEffect) == 'function' then
    local ok, on = pcall(g_map.isGroundEffect, id)
    if ok then return on == true end
  end
  local m = modules.game_groundfx
  local G = m and m.GroundFx
  return G and type(G.isGround) == 'function' and G.isGround(id) == true or false
end

local function spriteWidget(parent)
  local ok, w = pcall(g_ui.createWidget, 'UISprite', parent)
  if not ok or not w then return nil end
  w:setPhantom(true)
  w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  w:addAnchor(AnchorTop, 'parent', AnchorTop)
  return w
end

-- a list icon (a generated picture of game_cosmetics when there is one, else the best frame from the sprites)
function effectIcon(widget, spec, size, imageDir)
  if not widget or widget:isDestroyed() or type(spec) ~= 'table' then return false end
  widget:destroyChildren()
  size = size or 32
  if imageDir and type(spec.n) == 'string' and spec.n:match('^[%w_]+$') then
    local path = imageDir .. '/' .. spec.n
    if g_resources.fileExists(path .. '.png') then
      widget:setImageSource(path)
      return true
    end
  end
  local info = specInfo(spec)
  local L = info and P.iconLayout(info, size)
  if not L then return false end
  for _, t in ipairs(L.tiles) do
    local sw = spriteWidget(widget)
    if sw then
      sw:setMarginLeft(t.x)
      sw:setMarginTop(t.y)
      sw:setSize({ width = math.ceil(L.tile), height = math.ceil(L.tile) })
      sw:setSpriteId(t.sprite)
    end
  end
  return true
end

-- the troll of a scene (LookPreviewCore "the scene"): the stage's second creature
local function targetWidget(self)
  return alive(self.widget) and self.widget.stage.target or nil
end

function Preview:stopFx()
  self.fx = nil
  if not alive(self.widget) then return end
  local st = self.widget.stage
  st.fxUnder:destroyChildren()
  st.fxOver:destroyChildren()
  st.fxLabel:setVisible(false)
  local tw = targetWidget(self)
  if tw then tw:setVisible(false) end
  st.creature:setVisible(true)
  st.creature:setOpacity(1)
end

function Preview:startFx(opt)
  self:stopFx()
  local play = opt.play
  local function phasesOf(spec)
    local info = specInfo(spec)
    return info and info.phases or 1
  end
  local function sizeOf(spec)
    local info = specInfo(spec)
    return info and info.w or 1, info and info.h or 1, info and info.dispX or 0, info and info.dispY or 0
  end
  local hasStock = false
  for _, step in ipairs(play) do
    if type(step) == 'table' and type(step.a) == 'table' then hasStock = true end
  end
  local side = (settings.compare and hasStock) and 'both' or 'b'
  local scene = P.sceneOf(opt)
  self.fx = { timeline = P.timeline(play, side, phasesOf, scene), holders = {}, started = g_clock.millis(),
    hasStock = hasStock, scene = scene, play = play, sizeOf = sizeOf }
  -- the troll: alone in a kill scene, facing the player in a spell scene
  local tw = targetWidget(self)
  if tw then
    pcall(tw.setOutfit, tw, { type = P.TROLL })
    tw:setDirection(scene.kill and P.SOUTH or P.WEST)
    tw:setAnimate(false)
    pcall(tw.setIdleAnimate, tw, true)
    tw:setOpacity(1)
    tw:setVisible(true)
  end
end

-- the scene's extent (in tiles) with the boxes of its creatures
function Preview:fxExtent()
  local fx = self.fx
  local boxes = { target = boxOf({ type = P.TROLL }) }
  if fx.scene.caster then boxes.caster = self.box end
  return P.fxExtent(fx.play, fx.sizeOf, fx.scene, boxes)
end

-- the prints of a footprint option, under the creature (game_cosmeticfx's own pictures)
function Preview:drawSteps(art)
  local st = self.widget.stage
  st.fxUnder:destroyChildren()
  local L = self.layout
  if not L or not L.T then return end
  for _, f in ipairs(P.footsteps()) do
    local w = g_ui.createWidget('UIWidget', st.fxUnder)
    w:setPhantom(true)
    w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    w:addAnchor(AnchorTop, 'parent', AnchorTop)
    w:setImageSource('/modules/game_cosmeticfx/images/prints/' .. art)
    local size = math.floor(L.T * 0.6)
    w:setSize({ width = size, height = size })
    w:setMarginLeft(math.floor(L.tileX + (f.x + 0.2) * L.T))
    w:setMarginTop(math.floor(L.tileY + (0.2 + f.y) * L.T))
    w:setRotation(f.rotation)
    w:setOpacity(f.opacity)
  end
end

local function holderFor(self, idx, item)
  local h = self.fx.holders[idx]
  if h and alive(h.widget) then return h end
  local spec = item.spec
  local info = specInfo(spec)
  if not info then return nil end
  local st = self.widget.stage
  local layer = (not spec.m and isGround(num(spec.id))) and st.fxUnder or st.fxOver
  local holder = g_ui.createWidget('UIWidget', layer)
  holder:setPhantom(true)
  holder:fill('parent')
  h = { widget = holder, info = info, tiles = {} }
  for hh = 0, math.max(1, num(info.h)) - 1 do
    for ww = 0, math.max(1, num(info.w)) - 1 do
      local sw = spriteWidget(holder)
      if sw then h.tiles[#h.tiles + 1] = { w = ww, h = hh, widget = sw, sprite = -1 } end
    end
  end
  self.fx.holders[idx] = h
  return h
end

function Preview:fxTick()
  if not self.fx or not alive(self.widget) or not self.layout or not self.layout.T then return end
  local L = self.layout
  local now = g_clock.millis() - self.fx.started
  local playing = {}
  local label
  for _, a in ipairs(P.activeAt(self.fx.timeline, now)) do
    local idx
    for i, it in ipairs(self.fx.timeline.items) do
      if it == a.item then idx = i break end
    end
    local h = idx and holderFor(self, idx, a.item)
    if h then
      playing[idx] = true
      label = a.item.side
      local ox, oy, pxp, pyp = P.itemPlace(a, self.fx.scene)
      local info = h.info
      local phase = a.item.spec.m and 0 or P.phaseAt(a.ms, a.item.dur, info.phases)
      if a.item.spec.m then phase = math.floor(a.ms / 75) % math.max(1, num(info.phases)) end
      if not a.item.spec.m then
        -- an effect's pattern follows its tile (Effect::draw: position % patterns); the stage's tile is (0, 0)
        pxp, pyp = 0, 0
      end
      for _, t in ipairs(h.tiles) do
        local id = P.spriteAt(info, t.w, t.h, 0, pxp % math.max(1, num(info.px)), pyp % math.max(1, num(info.py)), 0, phase)
        if id ~= t.sprite then
          t.sprite = id
          if id > 0 then t.widget:setSpriteId(id) end
        end
        t.widget:setVisible(id > 0)
        local x, y = P.tilePixel(L, ox, oy, t.w, t.h, info.dispX, info.dispY)
        t.widget:setMarginLeft(x)
        t.widget:setMarginTop(y)
        t.widget:setSize({ width = L.T, height = L.T })
      end
      h.widget:setVisible(true)
    end
  end
  for idx, h in pairs(self.fx.holders) do
    if not playing[idx] and alive(h.widget) then h.widget:setVisible(false) end
  end
  -- the troll of a kill scene dies with the effect and stands again when the loop starts over
  local tw = targetWidget(self)
  if tw and self.fx.scene.kill then tw:setOpacity(P.targetAlpha(self.fx.timeline, now)) end
  local cap = self.widget.stage.fxLabel
  local showCap = settings.compare and self.fx.hasStock and label ~= nil
  cap:setVisible(showCap)
  if showCap then cap:setText(label == 'a' and tr('Default effects') or tr('With this skin')) end
end

local function fxTickAll()
  for h in pairs(live) do
    if alive(h.widget) then
      if h.fx and h.widget:isVisible() then
        local ok, err = pcall(h.fxTick, h)
        if not ok then
          g_logger.warning('[lookpreview] effects: ' .. tostring(err))
          h:stopFx()
        end
      end
    else
      live[h] = nil
    end
  end
end

function Preview:mode()
  return (settings.simple and P.hasWearer(self.hover or self.opt)) and 'simple' or 'own'
end

function Preview:syncControls()
  local c = self.widget.controls
  self.syncing = true
  c.autoTurn:setChecked(settings.auto)
  c.walk:setChecked(settings.walk)
  c.simple:setChecked(settings.simple)
  c.simple:setEnabled(P.hasWearer(self.hover or self.opt))
  c.compare:setChecked(settings.compare)
  c.compare:setVisible(self.fx ~= nil and self.fx.hasStock == true)
  self.syncing = false
end

function Preview:animate()
  local cw = self.widget.stage.creature
  -- walking in place as the Outfit window's Movement box does it (setStaticWalking), else the idle animation; a
  -- footprint always walks (its prints are behind it)
  local walk = settings.walk or self.steps ~= nil
  cw:setAnimate(walk)
  pcall(cw.setIdleAnimate, cw, not walk)
  pcall(cw.setStaticWalking, cw, walk)
end

local function place(widget, x, y, size)
  widget:setMarginLeft(x)
  widget:setMarginTop(y)
  widget:setSize({ width = size, height = size })
end

function Preview:relayout()
  if not alive(self.widget) or not self.box then return end
  local stage = self.widget.stage
  local W, H = stage:getWidth(), stage:getHeight()
  if W < 20 or H < 20 then return end
  local L
  local cw = stage.creature
  local floor = stage.floor
  if self.fx or self.steps then
    -- effects and prints: every creature on its tile, at the scale where the scene fits (as the map draws them),
    -- the scene centred in the stage
    local x0, y0, x1, y1
    if self.fx then
      x0, y0, x1, y1 = self:fxExtent()
    else
      local b = self.box
      x0, y0, x1, y1 = b.left / 32, b.top / 32, b.right / 32, b.bottom / 32
    end
    if self.steps then x0 = math.min(x0, -3) end
    L = P.fxLayout(W, H, x0, y0, x1, y1)
    local scene = self.fx and self.fx.scene
    if scene and scene.kill then
      cw:setVisible(false)
    else
      cw:setVisible(true)
      place(cw, P.creatureRect(L, scene and scene.caster))
    end
    local tw = targetWidget(self)
    if tw and scene then place(tw, P.creatureRect(L, scene.target)) end
    floor:setVisible(false)
  else
    -- the look alone: always 2x, the box of everything drawn centred in the stage
    L = P.layout(self.box, W, H)
    cw:setVisible(true)
    place(cw, L.x, L.y, L.size)
    -- a soft shadow on the ground under the feet (the character select's art, drawn at the same scale)
    local x, y, w, h = P.shadowRect(L, self.box)
    floor:breakAnchors()
    floor:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    floor:addAnchor(AnchorTop, 'parent', AnchorTop)
    floor:setMarginLeft(x)
    floor:setMarginTop(y)
    floor:setSize({ width = w, height = h })
    floor:setVisible(true)
  end
  self.layout = L
  self.widget.controls.zoomLabel:setText(L.scale .. 'x')
  if self.steps then self:drawSteps(self.steps) end
end

function Preview:refresh()
  if not alive(self.widget) then return end
  local opt = self.hover or self.opt
  local outfit, outline, note = P.compose(self:mode(), self.own or localOutfit(), opt, shaderKnown, canRide)
  local cw = self.widget.stage.creature
  local ok = pcall(cw.setOutfit, cw, outfit)
  if not ok then
    g_logger.warning('[lookpreview] setOutfit refused the look ' .. tostring(outfit.type))
    pcall(cw.setOutfit, cw, { type = outfit.type, mount = outfit.mount })
  end
  cw:setDirection(self.dir)
  self:animate()
  -- the outline: on the preview's own creature (an engine without 0038 has none: say so, no picture in its place)
  local c = cw:getCreature()
  if c and type(c.clearOutline) == 'function' then pcall(c.clearOutline, c) end
  if outline then
    local fx = cosmeticfx()
    local drawn = fx and c and fx.applyOutline(c, outline.art, outline.pulse) == true
    if not drawn then note = note or P.NO_OUTLINE end
  end
  local label = self.widget.stage.note
  label:setVisible(note ~= nil)
  if note then label:setText(tr(note)) end
  -- effects and footprints on the stage
  -- (an effects option itself, or a store bundle's part with effects)
  local fxOpt = P.effectsOf(opt)
  local fxKey = fxOpt and fxOpt.play or nil
  if fxKey ~= self.fxPlay or (self.fx and self.fx.compare ~= settings.compare) then
    self.fxPlay = fxKey
    if fxKey then
      self:startFx(fxOpt)
      self.fx.compare = settings.compare
      -- a spell scene: the player faces the troll
      if not self.fx.scene.kill then self.dir = P.EAST end
    else
      if self.fx and not self.fx.scene.kill then self.dir = P.SOUTH end -- back from a spell scene
      self:stopFx()
    end
    cw:setDirection(self.dir)
  end
  local steps = P.footprintArt(opt)
  if steps ~= self.steps then
    self.steps = steps
    if not steps then self.widget.stage.fxUnder:destroyChildren() end
    self.dir = steps and 1 or P.SOUTH -- walking east, the prints behind
    cw:setDirection(self.dir)
    self:animate()
  end
  self.outfit = outfit
  self.box = boxOf(outfit)
  self:syncControls()
  self:relayout()
end

function Preview:setOption(opt)
  self.opt = opt
  self.hover = nil
  self:refresh()
end

function Preview:setHover(opt)
  if opt == nil then return self:clearHover() end
  self.hover = opt
  self:refresh()
end

function Preview:clearHover()
  if self.hover == nil then return end
  self.hover = nil
  self:refresh()
end

function Preview:setOwnOutfit(o)
  self.own = type(o) == 'table' and P.copy(o) or nil
  self:refresh()
end

function Preview:turn(step)
  self.dir = P.turn(self.dir, step)
  if alive(self.widget) then self.widget.stage.creature:setDirection(self.dir) end
end

function Preview:destroy()
  live[self] = nil
  self.fx = nil
  if alive(self.widget) then self.widget:destroy() end
  self.widget = nil
end

local function refreshAll(controlsOnly)
  for h in pairs(live) do
    if alive(h.widget) then
      if controlsOnly then
        h:syncControls()
        h:animate()
      else
        h:refresh()
      end
    else
      live[h] = nil
    end
  end
end

local function onSetting(h, key, checked)
  if h.syncing or settings[key] == checked then return end
  settings[key] = checked
  saveSettings()
  refreshAll(key ~= 'simple' and key ~= 'compare')
end

-- a panel filling `parent` (a fixed column the window keeps for it)
function create(parent, opts)
  if not alive(parent) then return nil end
  local w = g_ui.createWidget('LookPreviewPanel', parent)
  w:fill('parent')
  local h = setmetatable({ widget = w, dir = P.SOUTH, opts = opts or {} }, Preview)
  local c = w.controls
  c.turnLeft.onClick = function() h:turn(-1) end
  c.turnRight.onClick = function() h:turn(1) end
  c.autoTurn.onCheckChange = function(_, v) onSetting(h, 'auto', v) end
  c.walk.onCheckChange = function(_, v) onSetting(h, 'walk', v) end
  c.simple.onCheckChange = function(_, v) onSetting(h, 'simple', v) end
  c.compare.onCheckChange = function(_, v) onSetting(h, 'compare', v) end
  w.stage.onGeometryChange = function() h:relayout() end
  live[h] = true
  h:refresh()
  return h
end

-- the slow turn: every open, visible panel one step clockwise
local function autoTick()
  if not settings.auto then return end
  for h in pairs(live) do
    if alive(h.widget) then
      if h.widget:isVisible() and h.widget:getParent() and h.widget:getParent():isVisible() then h:turn(1) end
    else
      live[h] = nil
    end
  end
end

-- the own character changed its outfit (the server confirmed a change): panels drawing it redraw
local function onOutfitChange(creature)
  if creature and creature.isLocalPlayer and creature:isLocalPlayer() then
    for h in pairs(live) do
      if h.own == nil then h:refresh() end
    end
  end
end

-- ---------------------------------------------------------------- the Outfit window (base module game_outfit)
-- The base window keeps its state in locals, so the panel follows what the window shows: its own preview creature
-- (preview.previewoutfit.creature), the row checked (appearance.*Check) and the list button focused or under the
-- mouse (ScrollBar.selectionList). It is read every OUTFIT_POLL_MS while the window is open; nothing is written to
-- the window but its width and the right margins of the children the widening moved (LookPreviewCore.dockFixes).
local OUTFIT_POLL_MS = 120
local PANEL_W, PANEL_GAP = 200, 8
local ROWS = { 'outfitCheck', 'mountCheck', 'auraCheck', 'shaderCheck', 'familiarCheck' }
local outfitPv, outfitWin, outfitEvent, lastLook, lastSig

local function findOutfitWindow()
  for _, w in ipairs(g_ui.getRootWidget():getChildren()) do
    local pv = w.preview and w.preview.previewoutfit
    if w.appearance and w.ScrollBar and pv and pv.creature then return w end
  end
  return nil
end

local function outfitOf(widget)
  if not widget then return nil end
  local ok, o = pcall(widget.getOutfit, widget)
  return ok and type(o) == 'table' and o or nil
end

-- the list button holding `w` (the hovered widget can be its name or its creature)
local function buttonOf(list, w)
  while w and w ~= list do
    if w:getParent() == list then return w end
    w = w:getParent()
  end
  return nil
end

local function stopOutfitWindow()
  if outfitEvent then removeEvent(outfitEvent) end
  outfitEvent = nil
  if outfitPv then outfitPv:destroy() end
  outfitPv, outfitWin, lastLook, lastSig = nil, nil, nil, nil
end

local function pollOutfitWindow()
  if not alive(outfitWin) or not outfitPv or not alive(outfitPv.widget) then return stopOutfitWindow() end
  local row
  for _, id in ipairs(ROWS) do
    local c = outfitWin.appearance:recursiveGetChildById(id)
    if c and c:isVisible() and c:isChecked() then row = id break end
  end
  local list = outfitWin.ScrollBar.selectionList
  local shown = outfitOf(outfitWin.preview.previewoutfit.creature)
  local focused = list and list:getFocusedChild()
  -- g_ui.getHoveredWidget is not in every engine build: without it the hover marker is simply not shown
  local hoveredWidget = g_ui.getHoveredWidget and g_ui.getHoveredWidget() or nil
  local hovered = list and buttonOf(list, hoveredWidget)
  local focusedOutfit = focused and focused.outfit and outfitOf(focused.outfit)
  local hoverOutfit = hovered and hovered.outfit and outfitOf(hovered.outfit)
  local sig = table.concat({ tostring(row), P.key(shown), P.key(focusedOutfit), P.key(hoverOutfit) }, '|')
  if sig == lastSig then return end
  lastSig = sig
  local own, opt
  own, opt, lastLook = P.outfitWindowState(row, shown, focusedOutfit, lastLook)
  outfitPv.own = own and P.copy(own) or nil
  outfitPv.opt = opt
  outfitPv.hover = hovered ~= focused and P.fromOutfitButton(row, hoverOutfit) or nil
  outfitPv:refresh()
end

-- widen the window by the panel's column and put the moved children back (rounds until nothing moves)
local function rectsOf(w)
  local t = {}
  for _, c in ipairs(w:getChildren()) do
    local r = c:getRect()
    t[c:getId()] = { x = r.x, width = r.width, widget = c }
  end
  return t
end

local function dockOutfitWindow(w)
  local before = rectsOf(w)
  w:setWidth(w:getWidth() + PANEL_W + PANEL_GAP)
  for _ = 1, P.DOCK_ROUNDS do
    w:getLayout():update()
    local fixes = P.dockFixes(before, rectsOf(w))
    if next(fixes) == nil then break end
    for id, d in pairs(fixes) do
      local c = before[id].widget
      c:setMarginRight(c:getMarginRight() + d)
    end
  end
  local column = g_ui.createWidget('UIWidget', w)
  column:setId('lookPreviewColumn')
  column:addAnchor(AnchorTop, 'parent', AnchorTop)
  column:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  column:addAnchor(AnchorRight, 'parent', AnchorRight)
  column:setWidth(PANEL_W)
  return column
end

local function attachOutfitWindow()
  local w = findOutfitWindow()
  if not w or w == outfitWin or w:getChildById('lookPreviewColumn') then return end
  stopOutfitWindow()
  local ok, column = pcall(dockOutfitWindow, w)
  if not ok then
    g_logger.warning('[lookpreview] outfit window: ' .. tostring(column))
    return
  end
  outfitWin = w
  outfitPv = create(column)
  if outfitPv then
    pollOutfitWindow()
    outfitEvent = cycleEvent(function()
      local okp, err = pcall(pollOutfitWindow)
      if not okp then
        g_logger.warning('[lookpreview] outfit window: ' .. tostring(err))
        stopOutfitWindow()
      end
    end, OUTFIT_POLL_MS)
  end
end

-- game_outfit builds its window in its own onOpenOutfitWindow handler: look for it right after
local function onOpenOutfitWindow()
  scheduleEvent(attachOutfitWindow, 30)
end

-- ---------------------------------------------------------------- module
function init()
  loadSettings()
  g_ui.importStyle('lookpreview')
  autoEvent = cycleEvent(autoTick, P.AUTO_MS)
  fxEvent = cycleEvent(fxTickAll, FX_TICK_MS)
  connect(g_game, { onOpenOutfitWindow = onOpenOutfitWindow })
  connect(Creature, { onOutfitChange = onOutfitChange })
end

function terminate()
  disconnect(g_game, { onOpenOutfitWindow = onOpenOutfitWindow })
  disconnect(Creature, { onOutfitChange = onOutfitChange })
  if autoEvent then removeEvent(autoEvent) end
  autoEvent = nil
  if fxEvent then removeEvent(fxEvent) end
  fxEvent = nil
  things = {}
  creatureThings = {}
  stopOutfitWindow()
  for h in pairs(live) do h:destroy() end
  live = {}
end
