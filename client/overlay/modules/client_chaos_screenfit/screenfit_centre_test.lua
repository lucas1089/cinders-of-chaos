-- luajit screenfit_centre_test.lua && lua5.3 screenfit_centre_test.lua (CI runs it from the repo root)
-- O572: the real screenfit.lua hooks on a fake engine, with every window the hub menu opens. The windows are read from
-- the .otui files of every module the hub registers (the CATEGORIES list of chaos_topbar.lua and every module that calls
-- api.addEntry): id, size and anchors of each window block, resolved through the style chain. Each is made, shown, laid
-- out the way the engine does (anchors place it, no anchors leave it at 0,0) and the queued events run. A window with no
-- anchors must end up centred in the game screen below the menu bar; a window the style places must stay valid (never the
-- top left); a window the player dragged is never moved again.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local MOD = dir .. '../'
dofile(dir .. 'screenfit_logic.lua')
dofile(dir .. 'centre_logic.lua')
local C = WindowCentreLogic

local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local function readFile(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local s = f:read('*a')
  f:close()
  return s
end

local function lines(cmd)
  local out = {}
  local p = io.popen(cmd)
  if not p then return out end
  for l in p:lines() do out[#out + 1] = l end
  p:close()
  return out
end

-- ---------------------------------------------------------------- the hub's modules
local function hubModules()
  local mods = {}
  local top = readFile(MOD .. 'client_chaos_topbar/chaos_topbar.lua') or ''
  local a = top:find('local CATEGORIES', 1, true)
  local b = top:find('local CATEGORY_ALIAS', 1, true)
  for name in top:sub(a, b):gmatch("'([%w_]+)'") do
    if name:find('^game_') or name:find('^client_') then mods[name] = true end
  end
  for _, path in ipairs(lines("grep -rl 'api.addEntry,' '" .. MOD .. "' --include=*.lua")) do
    if not path:find('_test%.lua$') and not path:find('/client_chaos_topbar/') then
      mods[path:match('/([%w_]+)/[^/]+$')] = true
    end
  end
  return mods
end

-- ---------------------------------------------------------------- .otui windows
local function parseOtui(text, decl, windows, file)
  local cur
  local function flush() if cur then windows[#windows + 1] = cur end end
  for line in (text .. '\n'):gmatch('([^\n]*)\n') do
    line = line:gsub('\r$', '')
    if line:find('^%s*//') or line:find('^%s*$') then
      -- comment or blank
    elseif not line:find('^%s') then
      flush()
      local name, base = line:match('^(%w+)%s*<%s*(%w+)%s*$')
      if name then
        cur = { name = name, base = base, props = {}, file = file, style = true }
        decl[name] = cur
      else
        name = line:match('^(%w+)%s*$')
        cur = name and { name = name, base = nil, cls = name, props = {}, file = file, style = false } or nil
      end
    elseif cur and line:find('^  %S') then
      local k, v = line:match('^  ([%w%.%-&!]+):%s*(.-)%s*$')
      if k then cur.props[k] = v end
    end
  end
  flush()
end

local function chain(decl, name)
  local out, seen = {}, {}
  while name and decl[name] and not seen[name] do
    seen[name] = true
    out[#out + 1] = name
    name = decl[name].base
  end
  out[#out + 1] = name
  return out
end

local function isWindowClass(decl, name)
  for _, n in ipairs(chain(decl, name)) do
    if n == 'UIWindow' or n == 'MainWindow' or n == 'Window' then return true end
  end
  return false
end

local function resolve(decl, w)
  local props = {}
  local ch = chain(decl, w.style and w.base or w.cls)
  for i = #ch, 1, -1 do
    local d = decl[ch[i]]
    if d then for k, v in pairs(d.props) do props[k] = v end end
  end
  for k, v in pairs(w.props) do props[k] = v end
  local width, height = 236, 207   -- the ChaosWindow default
  local sw, sh = (props.size or ''):match('^(%d+)%s+(%d+)')
  if sw then width, height = tonumber(sw), tonumber(sh) end
  if props.width and tonumber(props.width) then width = tonumber(props.width) end
  if props.height and tonumber(props.height) then height = tonumber(props.height) end
  local anchors = {}
  for k in pairs(props) do
    local a = k:match('^anchors%.(%w+)$')
    if a then anchors[a] = true end
  end
  return { width = width, height = height, anchors = anchors, margin = props.margin }
end

local function hubWindows()
  local mods = hubModules()
  local decl, all = {}, {}
  -- every style of every module first (a window style may come from another module's theme file)
  local files = lines("find '" .. MOD .. "' -name '*.otui'")
  table.sort(files)
  for _, path in ipairs(files) do
    local text = readFile(path)
    local found = {}
    parseOtui(text, decl, {}, path)
    parseOtui(text, {}, found, path)
    for _, w in ipairs(found) do w.module = path:match('/([%w_]+)/[^/]+$') all[#all + 1] = w end
  end
  local out = {}
  for _, w in ipairs(all) do
    local cls = w.style and w.base or w.cls
    if mods[w.module] and isWindowClass(decl, cls) and not (w.style and w.props.virtual == 'true') then
      local r = resolve(decl, w)
      r.id = w.props.id or w.name
      r.module = w.module
      r.style = w.style
      out[#out + 1] = r
    end
  end
  return out, mods
end

-- ---------------------------------------------------------------- the fake engine
local queue = {}
function addEvent(fn) queue[#queue + 1] = fn end
local function flush()
  local n = 0
  while #queue > 0 and n < 100 do
    local fn = table.remove(queue, 1)
    fn()
    n = n + 1
  end
end

local ROOT_W, ROOT_H, BAR_H = 1280, 720, 38
local root, bar
local online = false

local Widget = {}
Widget.__index = Widget
function Widget:getRect() return { x = self.x, y = self.y, width = self.w, height = self.h } end
function Widget:getWidth() return self.w end
function Widget:getHeight() return self.h end
function Widget:getId() return self.id end
function Widget:getParent() return self.parent end
function Widget:getPaddingRect() return self:getRect() end
function Widget:isDestroyed() return false end
function Widget:isVisible() return self.visible end
function Widget:getClassName() return self.class end
function Widget:getChildren() return self.children or {} end
function Widget:recursiveGetChildById(id) return id == 'chaosMenuBar' and bar or nil end
function Widget:breakAnchors() self.anchored = false end
function Widget:setPosition(p)
  local old = self:getRect()
  self.x, self.y = p.x, p.y
  if self.onGeometryChange then self:onGeometryChange(old, self:getRect()) end
end

-- the engine's anchor layout, as far as the windows here use it
local function layout(w)
  if not w.anchored then return end
  local a, x, y = w.anchors, 0, 0
  if a.fill then w.x, w.y, w.w, w.h = 0, 0, ROOT_W, ROOT_H return end
  if a.centerIn then x, y = math.floor((ROOT_W - w.w) / 2), math.floor((ROOT_H - w.h) / 2)
  else
    if a.horizontalCenter then x = math.floor((ROOT_W - w.w) / 2) elseif a.right then x = ROOT_W - w.w end
    if a.verticalCenter then y = math.floor((ROOT_H - w.h) / 2) elseif a.bottom then y = ROOT_H - w.h end
  end
  w.x, w.y = x, y
end

local UIWindow = { onDragMove = function(self, pos, moved) self.dragged = true end }
UIWindow.__index = UIWindow

local function newWindow(spec)
  local w = setmetatable({ id = spec.id, class = 'UIWindow', w = spec.width, h = spec.height, x = 0, y = 0,
    visible = false, parent = root, anchors = spec.anchors, anchored = next(spec.anchors) ~= nil }, Widget)
  -- a widget takes its class methods when it is made
  setmetatable(w, { __index = function(t, k) local v = Widget[k] if v ~= nil then return v end return UIWindow[k] end })
  return w
end

local function show(w)
  w.visible = true
  local old = w:getRect()
  layout(w)
  if w.onVisibilityChange then w:onVisibilityChange(true) end
  if w.onGeometryChange then w:onGeometryChange(old, w:getRect()) end
  flush()
end

local function hide(w)
  w.visible = false
  if w.onVisibilityChange then w:onVisibilityChange(false) end
end

local function setup(w, h, isOnline)
  ROOT_W, ROOT_H = w, h
  online = isOnline
  root = setmetatable({ x = 0, y = 0, w = w, h = h, visible = true, class = 'UIWidget', children = {} }, Widget)
  bar = setmetatable({ x = 346, y = 0, w = 588, h = BAR_H, visible = true, class = 'UIWidget', parent = root }, Widget)
end

-- the real hooks
UIWindow.onVisibilityChange = nil
setup(1280, 720, false)
g_ui = { getRootWidget = function() return root end }
g_game = { isOnline = function() return online end }
g_app = { isMobile = function() return false end }
modules = { game_interface = { getMapPanel = function()
  return setmetatable({ x = 200, y = 0, w = ROOT_W - 400, h = ROOT_H, visible = true, class = 'UIWidget' }, Widget)
end } }
_G.UIWindow = UIWindow
dofile(dir .. 'screenfit.lua')
init()

-- ---------------------------------------------------------------- the windows of the hub
local wins, mods = hubWindows()
local nmods = 0
for _ in pairs(mods) do nmods = nmods + 1 end
eq(nmods >= 60, true, 'the hub registers many modules (read ' .. nmods .. ')')
eq(#wins >= 60, true, 'the hub opens many windows (read ' .. #wins .. ')')

-- windows that the style places on purpose (an anchor other than centerIn); they must still never sit at the top left
local function check(spec, rw, rh, isOnline)
  setup(rw, rh, isOnline)
  local w = newWindow(spec)
  show(w)
  local r = w:getRect()
  local tag = spec.module .. '/' .. tostring(spec.id) .. ' at ' .. rw .. 'x' .. rh
  local bounds = C.usableArea({ x = 0, y = 0, width = rw, height = rh }, BAR_H)
  if spec.anchors.fill then
    eq(r.x == 0 and r.y == 0, true, tag .. ': a fill window covers the screen')
    return w
  end
  local fits = spec.width < bounds.width or spec.height < bounds.height   -- a window over the whole screen starts at its edge
  if spec.id ~= 'chaosPerfWindow' and fits then   -- the HUD that sits in the corner on purpose (KEEP_PLACE of screenfit.lua)
    eq(C.atOrigin({ x = r.x, y = r.y }, bounds), false, tag .. ': not at the top left (' .. r.x .. ',' .. r.y .. ')')
  end
  if next(spec.anchors) == nil then
    -- no anchors: centred in the map panel (the whole screen when offline), below the bar
    local map = isOnline and { x = 200, y = 0, width = rw - 400, height = rh } or nil
    local want = C.openPosition({ pos = { x = 0, y = 0 }, size = { width = spec.width, height = spec.height },
      root = { x = 0, y = 0, width = rw, height = rh }, barBottom = BAR_H, map = map })
    eq(want ~= nil, true, tag .. ': a rule exists for it')
    if want then
      eq(r.x, want.x, tag .. ': centred x'); eq(r.y, want.y, tag .. ': centred y')
      if spec.width < bounds.width and spec.height < bounds.height then
        eq(r.y >= BAR_H, true, tag .. ': below the menu bar')
      end
    end
  end
  return w
end

local unanchored = 0
local sizes = { { 1280, 720 }, { 960, 540 } }
local seen = {}
for _, spec in ipairs(wins) do
  if next(spec.anchors) == nil then unanchored = unanchored + 1 end
  for _, s in ipairs(sizes) do
    for _, on in ipairs({ false, true }) do
      check(spec, s[1], s[2], on)
    end
  end
  seen[spec.id] = true
end
eq(unanchored >= 5, true, 'some hub windows have no anchors, that is the bug case (' .. unanchored .. ')')
eq(seen.forgeWindow, true, 'the forge window is walked')

-- the forge as an example: 900x536 centred in a 1280x720 screen below the bar
setup(1280, 720, false)
local forge = newWindow({ id = 'forgeWindow', width = 900, height = 536, anchors = {} })
show(forge)
eq(forge.x, 190, 'forge x'); eq(forge.y, 38 + math.floor((682 - 536) / 2), 'forge y')
-- closed and opened again: the place is kept
hide(forge); show(forge)
eq(forge.x, 190, 'reopened: same x'); eq(forge.y, 38 + math.floor((682 - 536) / 2), 'reopened: same y')

-- the player drags it: never recentred, also not when it is dropped at the corner and reopened
local moved = newWindow({ id = 'dragWindow', width = 400, height = 300, anchors = {} })
show(moved)
moved:onDragMove({ x = 0, y = 0 }, { x = 1, y = 1 })
moved:setPosition({ x = 0, y = 0 })
hide(moved); show(moved)
eq(moved.x == 0 and moved.y == 0, true, 'a dragged window stays where the player left it')

-- a window the player moved before is not touched on a later opening: a valid place is kept
local placed = newWindow({ id = 'placedWindow', width = 400, height = 300, anchors = {} })
placed.x, placed.y = 77, 150
show(placed)
eq(placed.x == 77 and placed.y == 150, true, 'a valid place is kept')

-- a window larger than the screen keeps the title in view
setup(960, 540, false)
local huge = newWindow({ id = 'hugeWindow', width = 1100, height = 700, anchors = {} })
show(huge)
eq(huge.x <= 0 and huge.y <= BAR_H, true, 'an oversized window starts at the edge')

-- the HUD that is anchored to the top left on purpose is left alone
setup(1280, 720, false)
local perf = newWindow({ id = 'chaosPerfWindow', width = 300, height = 200, anchors = { top = true, left = true } })
show(perf)
eq(perf.x == 0 and perf.y == 0, true, 'the perf window keeps its corner')

-- a phone: no centring, the $mobile rules lay windows out
g_app = { isMobile = function() return true end }
setup(960, 540, false)
local phone = newWindow({ id = 'phoneWindow', width = 400, height = 300, anchors = {} })
show(phone)
eq(phone.x == 0 and phone.y == 0, true, 'a phone window is left to its $mobile rules')

if fails > 0 then error(fails .. ' failure(s) of ' .. checks .. ' checks') end
print('screenfit_centre_test: OK (' .. checks .. ' checks, ' .. #wins .. ' hub windows)')
