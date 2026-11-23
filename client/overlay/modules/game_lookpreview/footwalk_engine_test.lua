-- luajit client/overlay/modules/game_lookpreview/footwalk_engine_test.lua (and lua5.3), from the repo root
-- The engine part of the footprint preview (lookpreview.lua, O712) on a fake engine: what the panel puts on its stage for a
-- drawn footprint and an effect footprint (the figure walking east in place, the marks of the walker's feet turned east with
-- the picture of their art, the floor running by, the effect on the tile left), that it moves with the clock, that it is gone
-- when another option is picked, and that a client without game_cosmeticfx gets the note and no walk.
dofile('client/overlay/modules/game_cosmeticfx/cosmeticfxlogic.lua')
dofile('client/overlay/modules/game_cosmeticfx/foot_marks.lua')
dofile('client/overlay/modules/game_lookpreview/lookpreview_core.lua')
dofile('client/overlay/modules/game_lookpreview/footwalk.lua')
local CF, FM, P = CosmeticFxLogic, CosmeticFootMarks, LookPreviewCore

local n = 0
local function eq(a, b, m)
  n = n + 1
  if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end
end

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

-- every effect is a 1 x 1 thing of 4 frames; a creature thing is read for nothing
local FRAMES = 4
g_things = {
  getThingType = function(id, cat)
    if cat ~= ThingCategoryEffect then return nil end
    local sprites = {}
    for i = 1, FRAMES do sprites[i] = id * 10 + i end
    local t = {}
    local vals = { getSprites = sprites, getWidth = 1, getHeight = 1, getLayers = 1, getNumPatternX = 1, getNumPatternY = 1,
      getNumPatternZ = 1, getAnimationPhases = FRAMES, getDisplacementX = 0, getDisplacementY = 0 }
    for k, v in pairs(vals) do t[k] = function() return v end end
    return t
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

local withCosmeticFx = true
modules = setmetatable({}, { __index = function(_, k)
  if k == 'game_cosmeticfx' and withCosmeticFx then
    return { CosmeticFxLogic = CF, CosmeticFootMarks = FM }
  end
  return nil
end })

-- the panel's file: it defines globals (create ...), so it loads into its own environment over this one
local env = setmetatable({}, { __index = _G })
local chunk = assert(loadfile('client/overlay/modules/game_lookpreview/lookpreview.lua', 't', env))
chunk()
env.init()
local tick = cycles[#cycles]
eq(type(tick), 'function', 'the effects timer is registered')

local parent = new('window')
local panel = env.create(parent, {})
local stage = panel.widget.stage
local function under(id)
  local out = {}
  for _, c in ipairs(stage.fxUnder.children) do if c.id == id then out[#out + 1] = c end end
  return out
end
local function run(ms, step)
  for _ = 1, math.floor(ms / (step or 40)) do
    now = now + (step or 40)
    tick()
  end
end

-- ---------------------------------------------------------------- a drawn footprint
panel:setOption({ kind = 'footprint', art = 'ash' })
local cw = stage.creature
eq(cw.direction, P.EAST, 'the figure walks east')
eq(cw.animate, true, 'it walks') eq(cw.static, true, 'in place')
eq(stage.floor.visible, true, 'the floor shadow stays')
local L = panel.layout
local LL = P.layout(panel.box, STAGE_W, STAGE_H)
eq(L.scale, 2, 'at the preview zoom 2x')
eq(cw.margins[1] .. ',' .. cw.margins[2] .. ',' .. cw.size.width, LL.x .. ',' .. LL.y .. ',' .. LL.size, 'the figure is where the look alone puts it, centred')
eq(stage.note.visible, false, 'no note: the stage draws the footprint')
run(80)
local marks = under('footstep')
eq(#marks > 0 and #marks <= CF.MODES[CF.MODE].maxPer, true, 'the trail of the walker is on the floor: ' .. #marks)
local seenL, seenR = false, false
for _, m in ipairs(marks) do
  eq(m.rotation, 90, 'turned east')
  eq(m.image == '/modules/game_cosmeticfx/images/marks/ash_l' or m.image == '/modules/game_cosmeticfx/images/marks/ash_r', true, 'its own foot picture: ' .. tostring(m.image))
  if m.image:find('_l$') then seenL = true else seenR = true end
  eq(m.size.width, 32, 'a foot mark is half a tile at 2x')
  eq(m.opacity > 0 and m.opacity <= 0.9, true, 'faded as the map fades it')
end
eq(seenL and seenR, true, 'both feet')
local before = {}
for i, m in ipairs(marks) do before[i] = m.margins[1] end
run(120)
local moved = false
for i, m in ipairs(under('footstep')) do if before[i] and m.margins[1] < before[i] then moved = true end end
eq(moved, true, 'the floor runs by: marks move back with the clock')
local feetX = L.tileX + CF.feetOf(FM, 128, 1) * L.scale
for _, m in ipairs(under('footstep')) do
  if m.visible then eq(m.margins[1] + m.size.width / 2 <= feetX + 64 * 0.7 + 1, true, 'behind the feet') end
end
-- the marks keep to the pool: many seconds later there are not more widgets
run(20000)
eq(#under('footstep') <= CF.MODES[CF.MODE].maxPer, true, 'a pool of the walker\'s marks, no leak')

-- another art: its own picture
panel:setOption({ kind = 'footprint', art = 'rime' })
run(80)
local rime = under('footstep')
eq(#rime > 0, true, 'the new trail')
for _, m in ipairs(rime) do eq(m.image:find('rime_', 1, true) ~= nil, true, 'rime feet: ' .. tostring(m.image)) end
-- hovering the same art again keeps the walk (no restart)
local first = rime[1]
panel:setOption({ kind = 'footprint', art = 'rime' })
eq(under('footstep')[1], first, 'the same walk is not rebuilt')

-- ---------------------------------------------------------------- an effect footprint
local heart = P.fromPlayRow({ kind = 'footprint', play = { { b = { id = 5334, dx = 0, dy = 0, ms = 800, n = 'vfx_fp_heart' } } } })
panel:setOption(heart)
eq(#under('footstep'), 0, 'no marks: the effect is the footprint')
eq(cw.direction, P.EAST, 'the figure walks east')
eq(panel.fx, nil, 'no spell scene (no troll, no loop)')
local sawEffect, positions = false, {}
for _ = 1, 150 do
  run(40)
  for _, h in ipairs(under('footfx')) do
    for _, t in ipairs(h.children) do
      if h.visible and t.visible and t.sprite then
        sawEffect = true
        eq(t.sprite > 5334 * 10 and t.sprite <= 5334 * 10 + FRAMES, true, 'a frame of the footprint effect')
        positions[#positions + 1] = t.margins[1]
      end
    end
  end
end
eq(sawEffect, true, 'the effect plays on the floor')
eq(#under('footfx') <= CF.FX_MAX_PER_CREATURE, true, 'at most three effects alive')
local lo, hi = math.huge, -math.huge
for _, x in ipairs(positions) do lo, hi = math.min(lo, x), math.max(hi, x) end
eq(hi - lo > 40, true, 'the effects are left behind: they run back along the floor')

-- ---------------------------------------------------------------- leaving the footprint
panel:setOption({ kind = 'outfit', look = 128, addons = 3 })
eq(#under('footstep') + #under('footfx'), 0, 'nothing of the walk stays')
eq(cw.direction, P.SOUTH, 'the figure faces south again')
run(200)
eq(#under('footstep') + #under('footfx'), 0, 'and the clock draws nothing more')

-- a spell skin is still a scene (the troll, the loop)
panel:setOption({ kind = 'effects', play = { { b = { id = 5400, ms = 600, n = 'vfx_x' } } } })
eq(panel.fx ~= nil, true, 'a spell skin still plays its scene')

-- ---------------------------------------------------------------- a client without game_cosmeticfx
withCosmeticFx = false
panel:setOption({ kind = 'footprint', art = 'ash' })
eq(panel.walk, nil, 'no rules, no walk')
eq(stage.note.visible, true, 'the note says what a footprint is') eq(stage.note.text, P.UNSHOWN.footprint, 'the note text')
run(120)
eq(#under('footstep'), 0, 'nothing drawn')

print('footwalk_engine_test: ' .. n .. ' checks OK')
