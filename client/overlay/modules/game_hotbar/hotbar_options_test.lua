-- luajit hotbar_options_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
-- The "Layout options" button of the Options window (owner 2026-11-09 and 2026-11-14: it sat on top of the left menu). The
-- left menu panel of the base Options window is a plain panel whose entries are chained by anchors, so a button added to it
-- must carry its own anchors, and they must be the panel's bottom and left edges (never its top).
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

local Widget = {}
Widget.__index = function(t, k)
  if Widget[k] then return Widget[k] end
  if k:match('^set') then return function() end end
  return nil
end
local function new(parent)
  return setmetatable({ anchors = {}, kids = {}, parent = parent, destroyed = false }, Widget)
end
function Widget:isDestroyed() return self.destroyed end
function Widget:addAnchor(edge, target, targetEdge) self.anchors[#self.anchors + 1] = { edge, target, targetEdge } end
function Widget:setId(id) self.id = id end
function Widget:setText(t) self.text = t end
function Widget:setWidth(v) self.width = v end
function Widget:setHeight(v) self.height = v end
function Widget:setMarginBottom(v) self.marginBottom = v end
function Widget:setMarginLeft(v) self.marginLeft = v end

AnchorTop, AnchorBottom, AnchorLeft = 1, 2, 3
tr = function(k) return k end
g_app = { isMobile = function() return false end }
local menu = new()
local win = new()
win.options = menu
modules = { client_settings = { optionsWindow = win } }
g_ui = { createWidget = function(style, parent) local w = new(parent) w.style = style parent.kids[#parent.kids + 1] = w return w end }
HotbarLogic, FloatChatLogic = {}, {}

dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'hotbar_options.lua')
ChaosLayoutOptions.addOptionsButton()
local b = win.chaosLayoutButton
eq(b ~= nil, true, 'the button exists')
eq(b.parent, menu, 'it sits in the left menu panel')
local edges = {}
for _, a in ipairs(b.anchors) do edges[a[1]] = a end
eq(edges[AnchorTop], nil, 'never anchored to the top of the panel (that is where Controls is)')
eq(edges[AnchorBottom] ~= nil and edges[AnchorBottom][2], 'parent', 'anchored to the bottom of the panel')
eq(edges[AnchorLeft] ~= nil and edges[AnchorLeft][2], 'parent', 'and to its left edge')
eq(b.width <= 115, true, 'no wider than a menu entry'); eq(b.marginBottom > 0, true, 'a margin above the panel edge')
ChaosLayoutOptions.addOptionsButton()
eq(#menu.kids, 1, 'a second call adds no second button')

print('hotbar_options_test: ' .. n .. ' checks ok')
