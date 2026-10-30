-- Cinders of Chaos login scene: a piece of our own world behind the login widgets (client/MANIFEST.md "Login scene").
--
-- loginscene_core.lua lays out a ruined courtyard in the ash wastes from the dark tile set (UIItem widgets: grounds,
-- borders, walls, objects) with our own monsters in it (UICreature widgets): most walk a short patrol with pauses,
-- tile to tile at the client's step time, facing where they go, in their walking frames (idle frames while they
-- stand); the rest stand and turn now and then. Warm light pools flicker over braziers, torches, glowcaps and magma, a vignette darkens the edges and a dark
-- pool sits behind the logo. Captions use the bordered Chaos fonts (ChaosTheme roles 'display' and 'outlineSmall').
-- The setting 'chaosLoginBackground' picks the background: 'scene' (default), 'art' (the login artwork, the
-- earlier look, kept as the fallback) or 'alternate' (the two crossfade every 40 s). Without the dat/spr pair the
-- artwork shows. Lua and OTUI only; login.lua calls create / relayout / tick / destroy.

LoginScene = {}

local Core = LoginSceneCore
local IMG = '/images/chaos/login/'
local SETTING = 'chaosLoginBackground'
local ALT_PERIOD, ALT_FADE = 40, 2.5
local SEED = 1666

local layer, built, shade, logoShade, caption, nameTag
local tiles = {}        -- every widget of the current build (destroyed on rebuild)
local creatures, lights = {}, {}
local stack = {}        -- walls, objects and monsters in drawing order: {w, y, k, x} (a walker's entry moves)
local clock, nameClock, nameIndex = 0, 0, 0
local opacity = 1        -- scene layer opacity now (1 = scene, 0 = artwork)
local walkEvent, walkLast, nameOwner
local WALK_MS = 25       -- the walkers move on their own timer: smooth steps for a handful of widgets
local keepRects          -- function returning screen rects (relative to the parent) to keep free

local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

local function place(w, x, y, wd, ht)
  w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  w:addAnchor(AnchorTop, 'parent', AnchorTop)
  w:setMarginLeft(math.floor(x))
  w:setMarginTop(math.floor(y))
  if wd then w:setSize({ width = math.floor(wd), height = math.floor(ht) }) end
end

local function theme()
  return modules.client_chaos_theme and modules.client_chaos_theme.ChaosTheme
end

function LoginScene.mode()
  return Core.mode(g_settings.getString(SETTING))
end

function LoginScene.setMode(mode)
  g_settings.set(SETTING, Core.mode(mode))
end

-- the dat/spr pair, loaded the way client_entergame loads it at sign in (it is not loaded before that otherwise)
local function thingsReady()
  local gt = modules.game_things
  if not gt or not gt.isLoaded then return false end
  if gt.isLoaded() then return true end
  if gt.isLoading and gt.isLoading() then return false end
  local version = 1098
  for _, s in pairs(Servers or {}) do
    if type(s) == 'table' and tonumber(s.version) then version = tonumber(s.version) break end
  end
  local ok = pcall(function()
    -- as client_entergame's ensureThingsLoaded: the version change applies the 10.98 features (game_features)
    g_game.setClientVersion(version)
    if GameInfo and GameInfo.strVersion then g_game.setStringVersion(GameInfo.strVersion) end
    g_game.setProtocolVersion(g_game.getClientProtocolVersion(version))
    gt.load()
  end)
  return ok and gt.isLoaded()
end

local function clear()
  for _, w in ipairs(tiles) do
    if alive(w) then w:destroy() end
  end
  tiles, creatures, lights, stack = {}, {}, {}, {}
  built = nil
end

local function item(id, x, y, w, h, mapX, mapY)
  local it = g_ui.createWidget('UIItem', layer)
  it:setPhantom(true)
  it:setVirtual(true)
  it:setItemId(id)
  local thing = it:getItem()
  -- the map position decides a ground's pattern (4x4 seamless tiles), as on the map
  if thing and thing.setPosition then thing:setPosition({ x = 1000 + mapX, y = 1000 + mapY, z = 7 }) end
  place(it, x, y, w, h)
  tiles[#tiles + 1] = it
  return it
end

local function light(kind, cx, cy, size)
  local img = ({ fire = 'scene_light_fire', magma = 'scene_light_magma', glowcapPurple = 'scene_light_violet',
                 glowcapTeal = 'scene_light_teal' })[kind] or 'scene_light_fire'
  local w = g_ui.createWidget('UIWidget', layer)
  w:setImageSource(IMG .. img)
  w:setImageSmooth(true)
  w:setPhantom(true)
  place(w, cx - size / 2, cy - size / 2, size, size)
  tiles[#tiles + 1] = w
  lights[#lights + 1] = { w = w, kind = kind, ph = math.random() * 6.28, sp = 2 + math.random() * 3 }
end

local function build()
  local pw, ph = layer:getWidth(), layer:getHeight()
  if pw < 100 or ph < 100 then return end
  local T = Core.tileSize(pw, ph)
  local cols, rows = math.ceil(pw / T) + 1, math.ceil(ph / T) + 1
  -- centre the grid: the extra column and row hang over the edges evenly
  local ox, oy = math.floor((pw - cols * T) / 2), math.floor((ph - rows * T) / 2)
  local keep = {}
  for _, r in ipairs(keepRects and keepRects() or {}) do
    keep[#keep + 1] = { math.floor((r.x - ox) / T) + 1, math.floor((r.y - oy) / T) + 1,
                        math.floor((r.x + r.width - ox) / T) + 1, math.floor((r.y + r.height - oy) / T) + 1 }
  end
  local key = string.format('%d:%d:%d', T, cols, rows)
  if built == key then return end
  clear()
  local s = Core.layout(cols, rows, SEED, keep)
  local function px(x) return ox + (x - 1) * T end
  local function py(y) return oy + (y - 1) * T end
  for y = 1, rows do
    for x = 1, cols do item(s.ground[y][x], px(x), py(y), T, T, x, y) end
  end
  for _, b in ipairs(s.borders) do item(b[3], px(b[1]), py(b[2]), T, T, b[1], b[2]) end
  for _, t in ipairs(s.things) do
    local x, y, w, h = px(t.x - t.w + 1), py(t.y - t.h + 1), t.w * T, t.h * T
    if t.kind == 'creature' then
      -- UICreature maps two tiles up and left of the creature's own tile onto its rect (DrawQueue::correctOutfit):
      -- a 2x2-tile rect ending on that tile draws it at the map's scale, bigger outfits reach further up and left
      x, y, w, h = px(t.x - 1), py(t.y - 1), 2 * T, 2 * T
      local c = g_ui.createWidget('UICreature', layer)
      c:setPhantom(true)
      local col = t.colors or { 0, 0, 0, 0 }
      c:setOutfit({ type = t.look, head = col[1], body = col[2], legs = col[3], feet = col[4], addons = t.addons or 0 })
      c:setDirection(t.dir)
      if t.idle == 'hover' then c:setAnimate(true) else c:setIdleAnimate(true) end
      place(c, x, y, w, h)
      tiles[#tiles + 1] = c
      stack[#stack + 1] = { w = c, y = t.y, k = 3, x = t.x }
      local rec = { w = c, t = t, next = 3 + math.random() * 8, cx = px(t.x - t.w + 1) + t.w * T / 2,
                    top = py(t.y - t.h + 1) - math.floor(T * 0.15), ox = ox, oy = oy, T = T }
      if t.path then
        -- a staggered start, so the monsters do not all set off together
        rec.walker = Core.newWalker(t.path, math.random(0, 3000), t.dir)
        rec.moving = false
        rec.entry = stack[#stack]
      end
      creatures[#creatures + 1] = rec
    else
      stack[#stack + 1] = { w = item(t.id, x, y, w, h, t.x, t.y), y = t.y, k = t.kind == 'wall' and 1 or 2, x = t.x }
    end
  end
  for _, l in ipairs(s.lights) do
    local size = (l.kind == 'fire' and 3.2 or (l.kind == 'magma' and 2.2 or 1.8)) * T
    light(l.kind, px(l.x) + T / 2, py(l.y) + T / 2, size)
  end
  -- on top of the scene: the vignette and the caption (the logo's own shade is placed by login.lua)
  shade:raise()
  if alive(logoShade) then logoShade:raise() end
  caption:setText(s.place)
  caption:raise()
  nameTag:raise()
  built = key
end

-- a walker on a new tile is drawn where a thing on that tile would be (by row, then walls, objects, monsters, then
-- column, as layout sorts them): its widget moves just before the first thing that draws after it
local function drawsBefore(a, b)
  if a.y ~= b.y then return a.y < b.y end
  if a.k ~= b.k then return a.k < b.k end
  return a.x < b.x
end
local function restack(e)
  local nextIdx, lastIdx
  for _, o in ipairs(stack) do
    if o ~= e and alive(o.w) then
      local i = layer:getChildIndex(o.w)
      if drawsBefore(e, o) then
        if not nextIdx or i < nextIdx then nextIdx = i end
      elseif not lastIdx or i > lastIdx then
        lastIdx = i
      end
    end
  end
  local j = layer:getChildIndex(e.w)
  local to
  if nextIdx then to = (j < nextIdx) and nextIdx - 1 or nextIdx
  elseif lastIdx then to = (j < lastIdx) and lastIdx or lastIdx + 1 end
  if to and to ~= j then layer:moveChildToIndex(e.w, to) end
end

-- the walkers: position (fractional tiles while stepping), facing, walking or idle frames; the name tag follows
local function walkStep()
  if not alive(layer) or opacity <= 0.001 or not layer:isVisible() then walkLast = nil return end
  local parent = layer:getParent()
  if parent and not parent:isVisible() then walkLast = nil return end
  local now = g_clock.millis()
  local dt = walkLast and math.min(200, now - walkLast) or 0
  walkLast = now
  for _, c in ipairs(creatures) do
    if c.walker and alive(c.w) then
      local x, y, dir, moving, tx, ty = c.walker.update(dt)
      local e = c.entry
      if e and (e.x ~= tx or e.y ~= ty) then
        e.x, e.y = tx, ty
        restack(e)
      end
      local T, w = c.T, c.t.w
      c.w:setMarginLeft(math.floor(c.ox + (x - 2) * T + 0.5))
      c.w:setMarginTop(math.floor(c.oy + (y - 2) * T + 0.5))
      c.cx = c.ox + (x - w) * T + w * T / 2
      c.top = c.oy + (y - w) * T - math.floor(T * 0.15)
      if dir ~= c.dir then
        c.w:setDirection(dir)
        c.dir = dir
      end
      if moving ~= c.moving then
        c.moving = moving
        if c.t.idle ~= 'hover' then
          c.w:setIdleAnimate(not moving)
          c.w:setAnimate(moving)
        end
      end
      if nameOwner == c and alive(nameTag) then
        nameTag:setMarginLeft(math.floor(c.cx - nameTag:getWidth() / 2))
        nameTag:setMarginTop(math.floor(c.top - 4))
      end
    end
  end
end

-- parent: the background widget (client_background); keep: function() -> list of {x, y, width, height} relative to it
function LoginScene.create(parent, keep)
  keepRects = keep
  if layer then return true end
  if LoginScene.mode() == 'art' or not thingsReady() then return false end
  layer = g_ui.createWidget('UIWidget', parent)
  layer:setId('chaosLoginScene')
  layer:fill('parent')
  layer:setPhantom(true)
  layer:setBackgroundColor('#0b0807')
  layer:lower()
  shade = g_ui.createWidget('UIWidget', layer)
  shade:fill('parent')
  shade:setImageSource(IMG .. 'scene_vignette')
  shade:setImageSmooth(true)
  shade:setPhantom(true)
  logoShade = g_ui.createWidget('UIWidget', layer)
  logoShade:setImageSource(IMG .. 'scene_logo_shade')
  logoShade:setImageSmooth(true)
  logoShade:setPhantom(true)
  caption = g_ui.createWidget('UILabel', layer)
  caption:setPhantom(true)
  caption:setTextAutoResize(true)
  caption:setColor('#e8c477')
  caption:addAnchor(AnchorRight, 'parent', AnchorRight)
  caption:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  caption:setMarginRight(22)
  caption:setMarginBottom(18)
  nameTag = g_ui.createWidget('UILabel', layer)
  nameTag:setPhantom(true)
  nameTag:setTextAutoResize(true)
  nameTag:setColor('#d9ccb4')
  nameTag:setOpacity(0)
  local th = theme()
  if th and th.applyFont then
    th.applyFont(caption, 'display')
    th.applyFont(nameTag, 'outlineSmall')
  end
  build()   -- or on the first tick, when the layer has its size
  walkEvent = cycleEvent(walkStep, WALK_MS)
  return true
end

function LoginScene.isActive()
  return alive(layer)
end

-- the scene's weight in the picture (1 = only the scene): login.lua dims the artwork's own glow by the rest
function LoginScene.opacity()
  return alive(layer) and opacity or 0
end

-- the logo's box (relative to the parent): a dark pool behind it so its flames read over the tiles
function LoginScene.setLogoBox(x, y, w, h)
  if not alive(logoShade) then return end
  logoShade:breakAnchors()
  place(logoShade, x - w * 0.12, y - h * 0.08, w * 1.24, h * 1.16)
end

-- the sign-in panel's box (relative to the parent): the map name stays clear of it, above its right corner when
-- the room beside it is too narrow (a phone)
local panelBox
function LoginScene.setPanelBox(x, y, w, h)
  panelBox = { x = x, y = y, w = w, h = h }
  if alive(caption) then
    local mr, mb = 22, 18
    local cw, pw = caption:getWidth(), alive(layer) and layer:getWidth() or 0
    if cw > 0 and pw > 0 and pw - mr - cw < x + w + 8 then mb = (alive(layer) and layer:getHeight() or 0) - y + 6 end
    caption:setMarginBottom(mb)
  end
end

function LoginScene.relayout()
  if alive(layer) then build() end
  if panelBox then LoginScene.setPanelBox(panelBox.x, panelBox.y, panelBox.w, panelBox.h) end
end

-- every 50 ms from login.lua's tick
function LoginScene.tick(dt)
  if not alive(layer) then return end
  if not built then build() end
  clock = clock + dt
  if LoginScene.mode() == 'alternate' then
    opacity = Core.alternateOpacity(clock, ALT_PERIOD, ALT_FADE)
  else
    opacity = 1
  end
  layer:setOpacity(opacity)
  layer:setVisible(opacity > 0.001)
  if opacity <= 0.001 then return end
  for _, l in ipairs(lights) do
    local base = l.kind == 'fire' and 0.78 or 0.62
    l.w:setOpacity(math.max(0.2, math.min(1, base + 0.14 * math.sin(clock * l.sp + l.ph)
      + 0.08 * math.sin(clock * l.sp * 2.7 + 1.1) + 0.06 * (math.random() - 0.5))))
  end
  -- standing monsters: now and then one turns (towards the courtyard or the viewer) or looks around
  for _, c in ipairs(creatures) do
    c.next = c.next - dt
    if not c.walker and c.next <= 0 and alive(c.w) then
      local d = c.t.dir
      local roll = math.random()
      if roll < 0.45 then d = Core.SOUTH elseif roll < 0.8 then d = c.t.dir else d = (c.t.dir + 2) % 4 end
      c.w:setDirection(d)
      c.next = 3 + math.random() * 9
    end
  end
  -- a name now and then over one of the monsters, in the bordered font
  nameClock = nameClock - dt
  if #creatures > 0 then
    if nameClock <= 0 then
      nameIndex = nameIndex % #creatures + 1
      local c = creatures[nameIndex]
      nameOwner = c
      nameTag:setText(c.t.name)
      nameTag:breakAnchors()
      place(nameTag, c.cx - nameTag:getWidth() / 2, c.top - 4)
      nameClock = 6
    end
    local t = 6 - nameClock
    nameTag:setOpacity(math.max(0, math.min(1, t / 0.8, (6 - t) / 0.8)) * 0.9)
  end
end

function LoginScene.destroy()
  if walkEvent then removeEvent(walkEvent) end
  walkEvent, walkLast, nameOwner = nil, nil, nil
  clear()
  for _, w in ipairs({ shade, logoShade, caption, nameTag, layer }) do
    if alive(w) then w:destroy() end
  end
  layer, shade, logoShade, caption, nameTag = nil, nil, nil, nil, nil
  opacity = 1
end
