-- luajit client/overlay/modules/game_lookpreview/lookpreview_datload_test.lua (and lua5.3), from the repo root
-- O782: the look preview reads no thing type before the dat is loaded. game_outfitextras builds its preview at module
-- load, before game_things loads the dat at the login screen; the engine then had only its null type and logged
-- "invalid thing type client id 128 in category 1" (the neutral look 128) once per start, and the panel kept the null
-- type's numbers for look 128 the whole session. Here: no getThingType while g_things.isDatLoaded() is false, and the
-- first refresh after the load reads the real thing of the look (and of an effect) once.
dofile('client/overlay/modules/game_lookpreview/lookpreview_core.lua')
local P = LookPreviewCore

local n = 0
local function eq(a, b, m)
  n = n + 1
  if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end
end

-- ---------------------------------------------------------------- the fake engine

-- ---------------------------------------------------------------- the fake engine
local now = 5000
g_clock = { millis = function() return now end }
g_logger = { warning = function(t) error('WARN ' .. t, 2) end, info = function() end }
g_settings = { getNode = function() return nil end, setNode = function() end }
g_game = { isOnline = function() return false end }
g_shaders = nil
Creature, LocalPlayer = {}, {}
function connect() end
function disconnect() end
local cycles = {}
function cycleEvent(fn) cycles[#cycles + 1] = fn return fn end
function removeEvent() end
function scheduleEvent() return {} end
function tr(s) return s end
AnchorLeft, AnchorTop = 1, 2
ThingCategoryEffect, ThingCategoryMissile, ThingCategoryCreature = 7, 8, 9

-- the dat: not loaded at module load; every call is counted by category and id
local datLoaded = false
local asked = {}
local function askedOf(cat, id) return asked[tostring(cat) .. ':' .. tostring(id)] or 0 end
local function thing(w, h, frames, base)
  local sprites = {}
  for i = 1, frames * w * h do sprites[i] = base + i end
  local t = {}
  local vals = { getSprites = sprites, getWidth = w, getHeight = h, getLayers = 2, getNumPatternX = 4, getNumPatternY = 1,
    getNumPatternZ = 1, getAnimationPhases = frames, getDisplacementX = 8, getDisplacementY = 8, getId = 0 }
  for k, v in pairs(vals) do t[k] = function() return v end end
  return t
end
g_things = {
  isDatLoaded = function() return datLoaded end,
  getThingType = function(id, cat)
    local key = tostring(cat) .. ':' .. tostring(id)
    asked[key] = (asked[key] or 0) + 1
    if not datLoaded then return thing(1, 1, 1, 0) end -- the engine's null type (and its error line)
    if cat == ThingCategoryCreature then return thing(2, 2, 3, id * 100) end
    return thing(1, 1, 4, id * 10)
  end,
}

local METHODS = {}
local function new(class, parent, fields)
  local w = { class = class, children = {}, parent = parent, kids = {}, margins = { 0, 0 }, size = { width = 0, height = 0 },
    visible = true, destroyed = false, opacity = 1 }
  for k, v in pairs(fields or {}) do w[k] = v end
  setmetatable(w, { __index = function(_, k) return METHODS[k] end })
  if parent then parent.children[#parent.children + 1] = w end
  return w
end
function METHODS.setId(w, id) w.id = id end
function METHODS.getId(w) return w.id end
function METHODS.getChildren(w) local out = {} for i, c in ipairs(w.children) do out[i] = c end return out end
function METHODS.destroy(w)
  w.destroyed = true
  if w.parent then
    for i, c in ipairs(w.parent.children) do if c == w then table.remove(w.parent.children, i) break end end
  end
end
function METHODS.destroyChildren(w) for _, c in ipairs(METHODS.getChildren(w)) do c:destroy() end end
function METHODS.isDestroyed(w) return w.destroyed end
function METHODS.isVisible(w) return w.visible end
function METHODS.setVisible(w, v) w.visible = v end
function METHODS.getParent(w) return w.parent end
function METHODS.getWidth(w) return w.size.width end
function METHODS.getHeight(w) return w.size.height end
function METHODS.setSize(w, s) w.size = { width = s.width, height = s.height } end
function METHODS.setMarginLeft(w, v) w.margins[1] = v end
function METHODS.setMarginTop(w, v) w.margins[2] = v end
function METHODS.setOpacity(w, v) w.opacity = v end
function METHODS.setImageSource(w, v) w.image = v end
function METHODS.setImageSmooth() end
function METHODS.setImageColor(w, v) w.tint = v end
function METHODS.setRotation(w, v) w.rotation = v end
function METHODS.setPhantom() end
function METHODS.addAnchor() end
function METHODS.breakAnchors() end
function METHODS.fill() end
function METHODS.setSpriteId(w, v) w.sprite = v end
function METHODS.setText(w, v) w.text = v end
function METHODS.setChecked() end
function METHODS.setEnabled() end
function METHODS.setOutfit(w, o) w.outfit = o end
function METHODS.setDirection(w, d) w.direction = d end
function METHODS.setAnimate(w, v) w.animate = v end
function METHODS.setIdleAnimate(w, v) w.idle = v end
function METHODS.setStaticWalking(w, v) w.static = v end
function METHODS.getCreature() return nil end

local STAGE_W, STAGE_H = 318, 211
g_ui = {
  importStyle = function() end,
  createWidget = function(class, parent)
    if class == 'LookPreviewPanel' then
      local panel = new(class, parent)
      local stage = new('stage', panel, { size = { width = STAGE_W, height = STAGE_H } })
      panel.stage = stage
      for _, k in ipairs({ 'floor', 'fxUnder', 'creature', 'target', 'fxOver', 'sample', 'fxLabel', 'note' }) do
        stage[k] = new(k, stage)
        stage[k].id = k
      end
      panel.controls = new('controls', panel)
      for _, k in ipairs({ 'turnLeft', 'turnRight', 'zoomLabel', 'autoTurn', 'walk', 'simple', 'compare' }) do
        panel.controls[k] = new(k, panel.controls)
      end
      return panel
    end
    return new(class, parent)
  end,
}
modules = setmetatable({}, { __index = function() return nil end })

local env = setmetatable({}, { __index = _G })
local chunk = assert(loadfile('client/overlay/modules/game_lookpreview/lookpreview.lua', 't', env))
chunk()
env.init()

local function creatureAsks()
  local total = 0
  for key, v in pairs(asked) do
    if key:find('^' .. tostring(ThingCategoryCreature) .. ':') then total = total + v end
  end
  return total
end

-- module load: game_outfitextras makes its panel before the dat is there
local parent = new('window')
local panel = env.create(parent, {})
eq(panel ~= nil, true, 'the panel is made before the dat loads')
eq(creatureAsks(), 0, 'no creature thing type is asked before the dat loads (the log line of look 128)')
eq(askedOf(ThingCategoryCreature, P.NEUTRAL.type), 0, 'the neutral look 128 is not asked')
panel:refresh()
eq(creatureAsks(), 0, 'a refresh before the load asks nothing either')
panel:setOption({ kind = 'effects', play = { { b = { id = 42, ms = 600, n = 'vfx_x' } } } })
eq(askedOf(ThingCategoryEffect, 42), 0, 'no effect thing type before the load')
panel:setOption(nil)
eq(panel.box ~= nil, true, 'the box falls back to the look 128 numbers before the load')

-- the dat loads (login screen): the next refresh reads the look, once, and keeps it
datLoaded = true
panel:refresh()
eq(askedOf(ThingCategoryCreature, P.NEUTRAL.type) >= 1, true, 'after the load the neutral look is read')
local once = askedOf(ThingCategoryCreature, P.NEUTRAL.type)
panel:refresh()
eq(askedOf(ThingCategoryCreature, P.NEUTRAL.type), once, 'read once per id, then kept')
panel:setOption({ kind = 'effects', play = { { b = { id = 42, ms = 600, n = 'vfx_x' } } } })
eq(askedOf(ThingCategoryEffect, 42) >= 1, true, 'an effect thing is read after the load')

-- an engine without isDatLoaded (an older build) reads as before
g_things.isDatLoaded = nil
datLoaded = true
env.terminate()
asked = {}
env.init()
local p2 = env.create(new('window'), {})
eq(askedOf(ThingCategoryCreature, P.NEUTRAL.type) >= 1, true, 'no isDatLoaded: the thing is read as before')
p2:destroy()

print('lookpreview_datload_test: ' .. n .. ' checks passed')
