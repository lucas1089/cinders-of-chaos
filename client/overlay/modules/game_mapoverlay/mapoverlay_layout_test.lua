-- luajit mapoverlay_layout_test.lua && lua5.3 mapoverlay_layout_test.lua
-- The overlay is click-through: every widget of it drawn over the game map must be phantom, so clicks, drags, hover
-- and the wheel reach the map. Only the control strip (and its buttons) takes the mouse.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local f = assert(io.open(dir .. 'mapoverlay.otui', 'r'))
local text = f:read('*a')
f:close()
local fails = 0
local function fail(msg) print('FAIL ' .. msg) fails = fails + 1 end

-- split the .otui into top-level styles: name -> list of { indent, line }
local styles, order, current = {}, {}, nil
for line in (text .. '\n'):gmatch('([^\n]*)\n') do
  if not line:match('^%s*//') and line:match('%S') then
    local name = line:match('^([%w_]+)%s*<')
    if name then
      current = {}
      styles[name] = current
      order[#order + 1] = name
    elseif current then
      current[#current + 1] = { indent = #line:match('^(%s*)'), text = line:match('^%s*(.-)%s*$') }
    end
  end
end

-- the top-level properties of a style, and its child blocks (an indented type line plus its properties)
local function props(lines, from, indent)
  local p, i = {}, from
  while i <= #lines and lines[i].indent >= indent do
    if lines[i].indent == indent then
      local k, v = lines[i].text:match('^([%w%-%.]+):%s*(.-)$')
      if k then p[k] = v end
    end
    i = i + 1
  end
  return p
end
local function children(lines)
  local out = {}
  for i, l in ipairs(lines) do
    if l.indent == 2 and not l.text:find(':') then
      out[#out + 1] = { type = l.text, props = props(lines, i + 1, 4) }
    end
  end
  return out
end

local function mustBePhantom(name)
  local s = styles[name]
  if not s then fail('style ' .. name .. ' missing') return end
  if props(s, 1, 2).phantom ~= 'true' then fail(name .. ' is not phantom') end
  if props(s, 1, 2).focusable ~= 'false' then fail(name .. ' is focusable') end
  for _, c in ipairs(children(s)) do
    if c.props.phantom ~= 'true' then fail(name .. ' child ' .. c.type .. ' (' .. tostring(c.props.id) .. ') is not phantom') end
  end
end

-- everything drawn over the game map: the overlay, its minimap and mark layer, the marks (the self mark too) and "You"
mustBePhantom('MapOverlay')
mustBePhantom('MapOverlayMark')
mustBePhantom('MapOverlayYou')
local kids = children(styles.MapOverlay or {})
local ids = {}
for _, c in ipairs(kids) do ids[c.props.id or '?'] = c.type end
if ids.map ~= 'UIMinimap' then fail('MapOverlay has no UIMinimap "map"') end
if not ids.marks then fail('MapOverlay has no "marks" layer') end

-- the strip is the one clickable part: it must stay small (a corner of the view, not the map area)
local strip = styles.MapOverlayStrip
if not strip then
  fail('MapOverlayStrip missing')
else
  local w, h = (props(strip, 1, 2).size or ''):match('^(%d+)%s+(%d+)$')
  if not w or tonumber(w) > 360 or tonumber(h) > 48 then fail('the control strip is too big: ' .. tostring(props(strip, 1, 2).size)) end
end

-- the Lua creates the overlay widgets only from these styles (no plain clickable widget over the map)
local lf = assert(io.open(dir .. 'mapoverlay.lua', 'r'))
local lua = lf:read('*a')
lf:close()
for style in lua:gmatch("g_ui%.createWidget%('([%w_]+)'") do
  if style ~= 'MapOverlaySettings' and style ~= 'MapOverlayStrip' and style ~= 'MapOverlay'
    and style ~= 'MapOverlayMark' and style ~= 'MapOverlayYou' then
    fail('unexpected widget style created over the map: ' .. style)
  end
end
if lua:find('setPhantom%(false%)') then fail('mapoverlay.lua turns a widget non-phantom') end

if fails > 0 then error(fails .. ' failure(s)') end
print('mapoverlay_layout_test: ok')
