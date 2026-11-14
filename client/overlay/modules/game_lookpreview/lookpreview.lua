-- The shared look preview panel (client/MANIFEST.md "Look preview"). A window gives it a fixed column and calls
--   local pv = modules.game_lookpreview.create(placeholder)    -- nil when the module or the placeholder is missing
--   pv:setOption(opt)      the row picked (LookPreviewCore option; nil: the character as worn)
--   pv:setHover(opt)       the row under the mouse, shown until pv:clearHover()
--   pv:setTry(opt, ms)     a look kept on the character for ms milliseconds (the store's TRY ON); pv:clearTry()
--   pv:setOwnOutfit(o)     draw this outfit as "own" instead of the local player's (nil: back to the player's)
--   pv:refresh()           redraw (the player's outfit changed)
--   pv:destroy()
-- Effects (option {kind = 'effects', play} of LookPreviewCore.fromPlayRow: spell skins, kill effects) play in a loop
-- on the stage around the creature, from the client's own sprites (see "the effect stage" below); a footprint option
-- with its art draws a few prints behind the walking creature, which stays where the look alone puts it (O496). A loot
-- label, a chat colour and a name plate frame option draw a sample of it on the stage (O497, "samples" below).
--   modules.game_lookpreview.effectIcon(widget, spec, size)   a list icon: the effect's best frame, cropped and fitted
--   modules.game_lookpreview.fitCard(creatureWidget, outfit, w, h)   a list card's look facing south, filling the card
--   modules.game_lookpreview.sampleWidget(holder, opt, w, h, size)   a loot label / chat colour / plate frame sample centred
--                       in a card's holder widget ('card': a grid card, 'compact': the Equipped now picture); false without one
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
-- measures a look the anchors do not know from its tiles). Read once per id.
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

local function anchorOf(id)
  local _, anchors = charselect()
  return anchors and P.anchorFrom(anchors[id]) or nil
end

-- the lift of a winged character (Outfit::draw with the feature GameWingOffset)
local function wingLift()
  local ok, on = pcall(function() return GameWingOffset and g_game.getFeature(GameWingOffset) end)
  return (ok and on) and 6 or 0
end

-- the x shift base patch 0193 gives the wings of an outfit (centred on the body), facing south; 0 without it
local function wingShift(outfit)
  local m = modules.client_chaos_wingfit
  if not (m and m.WingFit) or num(outfit.wings) <= 0 then return 0 end
  local ok, s = pcall(m.WingFit.shift, outfit, wingLift())
  return ok and tonumber(s) or 0
end

-- the shift {x, y} base patch 0200 gives a head accessory worn on this body (the piece was fitted to look 128), facing
-- south, in sprite px at 1x; nil without the patch or its table (the module client_chaos_wingfit hands it over as
-- WingFit.headShift(outfit) or HeadFit.shift(outfit): whichever exists is asked, nothing else is assumed)
local function auraShift(outfit)
  if num(outfit.aura) <= 0 then return nil end
  local m = modules.client_chaos_wingfit
  if not m then return nil end
  local fn = (m.WingFit and m.WingFit.headShift) or (m.HeadFit and m.HeadFit.shift)
  if type(fn) ~= 'function' then return nil end
  local ok, x, y = pcall(fn, outfit)
  if not ok then return nil end
  if type(x) == 'table' then return { x = tonumber(x.x) or 0, y = tonumber(x.y) or 0 } end
  if tonumber(x) then return { x = tonumber(x), y = tonumber(y) or 0 } end
  return nil
end

local function figureOf(outfit)
  local Core, anchors = charselect()
  local mounted = num(outfit.mount) > 0
  local fig
  if Core and type(Core.figure) == 'function' then
    local body = mounted and { type = outfit.mount, wings = outfit.wings, aura = outfit.aura } or outfit
    local ok, f = pcall(Core.figure, anchors or {}, body, thingInfo, wingLift(), wingShift(outfit))
    if ok then fig = f end
  end
  return P.fitFigure(fig, mounted)
end

-- the box of everything the engine draws of an outfit (LookPreviewCore.lookBox), for the panel's centring
local function boxOf(outfit)
  local ok, b = pcall(P.lookBox, outfit, anchorOf, thingInfo, wingLift(), wingShift(outfit), auraShift(outfit))
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
  -- a cape is drawn from the back (O562)
  creatureWidget:setDirection(P.shownDirection(outfit, P.SOUTH, false))
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

-- ---------------------------------------------------------------- samples (engine side)
-- LookPreviewCore "samples" has the data and the places. The widgets are the ones the game draws the real thing with:
-- a UILabel with the ground label's font, border and colours, a UILabel with setColoredText (the console line as
-- game_cosmetics colours it), a UILabel on the 9-slice plate art (as base patch 0022 draws the name plate), a UIItem of
-- the loot bag (as client_chaos_login loginscene.lua draws items). The styles are LookPreviewGroundLabel, LookPreviewChatLine and
-- LookPreviewPlate (lookpreview.otui).
local function playerName()
  local me = g_game.isOnline() and g_game.getLocalPlayer() or nil
  local ok, name = pcall(function() return me and me:getName() end)
  return ok and type(name) == 'string' and name or ''
end

local function anchorTopLeft(w)
  w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  w:addAnchor(AnchorTop, 'parent', AnchorTop)
end

-- the widget of a LookPreviewCore.sampleSpec inside `parent`, sized by its text (text-auto-resize); nil when the art of a
-- plate frame is not in this client
-- A label's size comes from its text, now: a UILabel with text-auto-resize reports its old size until the next layout
-- pass, so the centring that read getWidth() / getHeight() right after setText put the text off-centre in the box
-- (O562). The size is set from the measured text and the padding, the text is centred in it.
local function fitLabel(l, padX, padY, minW)
  pcall(l.setTextAutoResize, l, false)
  local ts = l:getTextSize()
  local w = math.max(minW or 0, ts.width + 2 * padX)
  local h = ts.height + 2 * padY
  l:setSize({ width = w, height = h })
  pcall(l.setTextAlign, l, AlignCenter)
  return l
end

-- Animated chat colours on the samples (O562): the name of a chat sample takes the look of its colour
-- (game_cosmetics ChatColorFx, the same look the console draws) and a timer repaints the live ones. Without the module,
-- or an engine that refuses, the flat colour stays.
local chatLive, chatEvent = {}, nil

local function chatFx()
  local m = modules.game_cosmetics
  return m and m.ChatColorFx or nil
end

local function chatTick()
  local F = chatFx()
  local now = (g_clock and g_clock.millis and g_clock.millis() or 0) / 1000
  local n = 0
  for w, e in pairs(chatLive) do
    local ok, dead = pcall(function() return w:isDestroyed() end)
    if not ok or dead then
      chatLive[w] = nil
    else
      n = n + 1
      if F and w:isVisible() then
        local parts = F.recolor(e.parts, e.first, e.last, e.style, now)
        if not pcall(w.setColoredText, w, parts) then chatLive[w] = nil end
      end
    end
  end
  if n == 0 and chatEvent then
    removeEvent(chatEvent)
    chatEvent = nil
  end
end

local function animateChat(l, spec)
  local F = chatFx()
  local first = spec.parts[1]
  local style = F and type(spec.parts[2]) == 'string' and F.styleOf(spec.parts[2]) or nil
  if not style or type(first) ~= 'string' or first == '' or type(cycleEvent) ~= 'function' then return end
  chatLive[l] = { parts = spec.parts, first = 1, last = #first, style = style }
  if not chatEvent then chatEvent = cycleEvent(chatTick, F.FRAME_MS) end
end

local function buildSampleWidget(parent, spec)
  if spec.kind == 'lootlabel' then
    local l = g_ui.createWidget('LookPreviewGroundLabel', parent)
    l:setText(spec.text)
    l:setColor(spec.color)
    local GLL = modules.game_groundlabels and modules.game_groundlabels.GroundLabelsLogic
    local plate = GLL and type(GLL.plateFor) == 'function' and GLL.plateFor(spec.bg) or nil
    if plate and g_resources.fileExists(plate.path .. '.png') then
      l:setBorderWidth(0)
      l:setImageSource(plate.path)
      l:setImageBorder(plate.border)
      l:setBackgroundColor('#00000000')
      return fitLabel(l, 8, 5, 40)
    end
    l:setBorderColor(spec.border)
    l:setBackgroundColor(spec.bg)
    return fitLabel(l, 6, 4, 40)
  elseif spec.kind == 'chatcolor' then
    local l = g_ui.createWidget('LookPreviewChatLine', parent)
    l:setColoredText(spec.parts)
    l:setBackgroundColor(spec.bg)
    fitLabel(l, 6, 3, 0)
    animateChat(l, spec)
    return l
  elseif spec.kind == 'plate' then
    if not g_resources.fileExists(spec.path .. '.png') then return nil end
    local l = g_ui.createWidget('LookPreviewPlate', parent)
    l:setImageSource(spec.path)
    l:setImageBorder(spec.border)
    l:setText(spec.text)
    l:setColor(spec.color)
    return fitLabel(l, 9, 4, 0)
  end
  return nil
end

-- a sample centred in a card's holder widget (w x h px); size 'card' or 'compact' (LookPreviewCore.sampleSpec)
function sampleWidget(holder, opt, w, h, size)
  if not alive(holder) then return false end
  holder:destroyChildren()
  local sm = P.sampleOf(opt)
  local spec = sm and P.sampleSpec(sm, playerName(), size or 'card')
  local widget = spec and buildSampleWidget(holder, spec)
  if not widget then
    holder:setVisible(false)
    return false
  end
  widget:setPhantom(true)
  widget:setMarginLeft(math.max(0, math.floor((w - widget:getWidth()) / 2)))
  widget:setMarginTop(math.max(0, math.floor((h - widget:getHeight()) / 2)))
  holder:setVisible(true)
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
  -- the troll: alone in a kill scene, facing the player in a spell scene; none in a rare-loot scene (a loot bag instead)
  local tw = targetWidget(self)
  if tw and scene.loot then
    tw:setVisible(false)
  elseif tw then
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
  local boxes = { target = fx.scene.loot and P.LOOT_BOX or boxOf({ type = P.TROLL }) }
  if fx.scene.caster then boxes.caster = self.box end
  return P.fxExtent(fx.play, fx.sizeOf, fx.scene, boxes)
end

-- the prints of a footprint option, under the creature (game_cosmeticfx's own pictures). `prints` are the stage places
-- of LookPreviewCore.stepPrints; the widgets are tagged so a ground effect in the same layer is left alone
local STEP_ID = 'footstep'
local function clearSteps(st)
  for _, c in ipairs(st.fxUnder:getChildren()) do
    if c:getId() == STEP_ID then c:destroy() end
  end
end

function Preview:drawSteps(art, prints)
  local st = self.widget.stage
  clearSteps(st)
  if not prints then return end
  for _, f in ipairs(prints) do
    local w = g_ui.createWidget('UIWidget', st.fxUnder)
    w:setId(STEP_ID)
    w:setPhantom(true)
    w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    w:addAnchor(AnchorTop, 'parent', AnchorTop)
    w:setImageSource('/modules/game_cosmeticfx/images/prints/' .. art)
    w:setSize({ width = f.size, height = f.size })
    w:setMarginLeft(f.x)
    w:setMarginTop(f.y)
    w:setRotation(f.rotation)
    w:setOpacity(f.opacity)
  end
end

-- a rare-loot effect's scene (O564): the loot bag on its tile, under the effect (the fxUnder layer), tagged so a ground
-- effect in the same layer is left alone
local BAG_ID = 'lootbag'
function Preview:drawLootBag(L)
  local st = self.widget.stage
  for _, c in ipairs(st.fxUnder:getChildren()) do
    if c:getId() == BAG_ID then c:destroy() end
  end
  local scene = self.fx and self.fx.scene
  if not (scene and scene.loot) then return end
  local bag = g_ui.createWidget('UIItem', st.fxUnder)
  bag:setId(BAG_ID)
  bag:setPhantom(true)
  bag:setVirtual(true)
  bag:setItemId(P.LOOT_BAG)
  bag:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  bag:addAnchor(AnchorTop, 'parent', AnchorTop)
  bag:setSize({ width = L.T, height = L.T })
  bag:setMarginLeft(L.tileX + scene.target.x * L.T)
  bag:setMarginTop(L.tileY + scene.target.y * L.T)
end

-- the stage's sample (a loot label over a loot bag beside the feet, a chat line near the head, a name plate over it):
-- the character stays where the layout put it, the sample goes where LookPreviewCore.labelPlace / linePlace say
function Preview:drawSample(L, W, H)
  local st = self.widget.stage
  local holder = st.sample
  holder:destroyChildren()
  local sm = self.sample
  if not sm or (self.fx and self.fx.scene.kill) then return end
  local spec = P.sampleSpec(sm, playerName(), 'stage')
  if not spec then return end
  if spec.kind == 'lootlabel' then
    local bag = g_ui.createWidget('UIItem', holder) -- first: the label is drawn over it
    bag:setPhantom(true)
    bag:setVirtual(true)
    bag:setItemId(P.LOOT_BAG)
    anchorTopLeft(bag)
    local label = buildSampleWidget(holder, spec)
    local at = P.labelPlace(L, self.box, W, H, label:getWidth(), label:getHeight())
    bag:setSize({ width = at.bag.size, height = at.bag.size })
    bag:setMarginLeft(at.bag.x)
    bag:setMarginTop(at.bag.y)
    label:setPhantom(true)
    label:setMarginLeft(at.label.x)
    label:setMarginTop(at.label.y)
    return
  end
  local widget = buildSampleWidget(holder, spec)
  if not widget then
    -- no plate art in this client: the note says so
    st.note:setText(tr(P.UNSHOWN.nameplate))
    st.note:setVisible(true)
    return
  end
  widget:setPhantom(true)
  local at = P.linePlace(L, self.box, W, H, widget:getWidth(), widget:getHeight(), spec.kind == 'chatcolor')
  widget:setMarginLeft(at.x)
  widget:setMarginTop(at.y)
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
  if next(live) == nil then return end -- no preview panel open
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
  local prints
  if self.fx then
    -- effects: every creature on its tile, at the scale where the scene fits (as the map draws them), the scene
    -- centred in the stage. A bundle that also has prints keeps room for them on the left
    local x0, y0, x1, y1 = self:fxExtent()
    if self.steps then x0 = math.min(x0, -3) end
    L = P.fxLayout(W, H, x0, y0, x1, y1)
    local scene = self.fx.scene
    if scene.kill then
      cw:setVisible(false)
    else
      cw:setVisible(true)
      place(cw, P.creatureRect(L, scene.caster))
      if self.steps then prints = P.stepPrints(L, self.box, W, H) end
    end
    local tw = targetWidget(self)
    if tw then place(tw, P.creatureRect(L, scene.target)) end
    floor:setVisible(false)
  else
    -- the look alone, and a footprint too (O496: the prints go behind the character, it does not move): always 2x,
    -- the box of everything drawn centred in the stage
    L = self.steps and P.stepsLayout(self.box, W, H) or P.layout(self.box, W, H)
    prints = L.prints
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
  if self.steps then self:drawSteps(self.steps, prints) end
  self:drawLootBag(L)
  self:drawSample(L, W, H)
end

function Preview:refresh()
  if not alive(self.widget) then return end
  local opt = self.hover or self.try or self.opt
  local outfit, outline, note = P.compose(self:mode(), self.own or localOutfit(), opt, shaderKnown)
  local cw = self.widget.stage.creature
  local ok = pcall(cw.setOutfit, cw, outfit)
  if not ok then
    g_logger.warning('[lookpreview] setOutfit refused the look ' .. tostring(outfit.type))
    pcall(cw.setOutfit, cw, { type = outfit.type, mount = outfit.mount })
  end
  cw:setDirection(self:face(outfit))
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
      -- a spell scene: the player faces the troll (a kill and a rare-loot scene: south)
      if not self.fx.scene.kill and not self.fx.scene.loot then self.dir = P.EAST end
    else
      if self.fx and not self.fx.scene.kill then self.dir = P.SOUTH end -- back from a spell or rare-loot scene
      self:stopFx()
    end
    cw:setDirection(self:face(outfit))
  end
  self.sample = P.sampleOf(opt)
  local steps = P.footprintArt(opt)
  if steps ~= self.steps then
    self.steps = steps
    if not steps then self.widget.stage.fxUnder:destroyChildren() end
    self.dir = steps and 1 or P.SOUTH -- walking east, the prints behind
    cw:setDirection(self:face(outfit))
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
  self:clearTry(true)
  self:refresh()
end

-- A look kept on the character for `ms` milliseconds whatever the mouse does (the store's TRY ON button): it shows
-- over the picked row and ends by itself, or at the next setOption. Nothing is bought or granted.
function Preview:setTry(opt, ms)
  if opt == nil then return self:clearTry() end
  self.try = opt
  self.tryToken = (self.tryToken or 0) + 1
  local token = self.tryToken
  self:refresh()
  if type(scheduleEvent) == 'function' then
    scheduleEvent(function()
      if self.tryToken == token and self.widget then self:clearTry() end
    end, tonumber(ms) or 10000)
  end
end

function Preview:clearTry(silent)
  if self.try == nil then return end
  self.try = nil
  self.tryToken = (self.tryToken or 0) + 1 -- the pending end of an earlier try does nothing
  if not silent then self:refresh() end
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

-- the direction to draw `outfit` facing: a cape is shown from the back (O562, LookPreviewCore.face), but a spell scene
-- or footprints keep the direction they set
function Preview:face(outfit)
  if self.fxPlay or self.steps then return self.dir end
  return P.face(self, outfit)
end

function Preview:turn(step)
  P.turnBy(self, self.outfit, step)
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
  if not settings.auto or next(live) == nil then return end
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
  -- g_ui.getHoveredWidget is not bound in our engine: ChaosAltHelp.hovered finds the widget under the mouse
  local A = rawget(_G, 'ChaosAltHelp')
  local hoveredWidget = A and A.hovered and A.hovered() or nil
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
  if chatEvent then removeEvent(chatEvent) end
  chatEvent, chatLive = nil, {}
  things = {}
  creatureThings = {}
  stopOutfitWindow()
  for h in pairs(live) do h:destroy() end
  live = {}
end
