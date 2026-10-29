-- luajit sidepanelfit_logic_test.lua && lua5.3 sidepanelfit_logic_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'sidepanelfit_logic.lua')
local L = SidePanelFitLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(L.visibleCount(nil), 0, 'no children')
eq(L.visibleCount({ { visible = false }, { visible = true }, { visible = true } }), 2, 'two shown')

-- option off: nothing to do
local p = L.plan({ optionOn = false, height = 0, visible = 0 })
eq(p.height, nil, 'off: no height'); eq(p.opaque, false, 'off: not opaque')

-- option just on, nothing visible: the 200 px gap closes
p = L.plan({ optionOn = true, height = 200, visible = 0 })
eq(p.height, 0, 'empty: collapses'); eq(p.opaque, false, 'empty: not opaque')
-- already collapsed: no change
p = L.plan({ optionOn = true, height = 0, visible = 0 })
eq(p.height, nil, 'empty and collapsed: nothing')

-- a window arrives: back to the remembered height, normal background
p = L.plan({ optionOn = true, height = 0, remembered = 320, visible = 1 })
eq(p.height, 320, 'window: remembered height'); eq(p.opaque, true, 'window: opaque')
p = L.plan({ optionOn = true, height = 0, visible = 1 })
eq(p.height, 200, 'window: default height')
p = L.plan({ optionOn = true, height = 0, remembered = 10, visible = 1 })
eq(p.height, 200, 'window: a tiny remembered height is ignored')

-- a window stays: the size the player chose is remembered, never changed
p = L.plan({ optionOn = true, height = 300, visible = 2 })
eq(p.height, nil, 'shown: height kept'); eq(p.remember, 300, 'shown: remembered')
p = L.plan({ optionOn = true, height = 300, visible = 2, dragging = true })
eq(p.remember, nil, 'dragging: not remembered')

-- dragging a window over an empty panel opens a drop strip, which stays while the drag lasts
p = L.plan({ optionOn = true, height = 0, visible = 0, dragging = true })
eq(p.height, L.DROP_HEIGHT, 'drag: drop strip'); eq(p.opaque, true, 'drag: opaque')
p = L.plan({ optionOn = true, height = 80, visible = 0, dragging = true })
eq(p.height, nil, 'drag: strip kept')
p = L.plan({ optionOn = true, height = 80, visible = 0, dragging = false })
eq(p.height, 0, 'drag ended: strip closes')

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('sidepanelfit_logic_test: OK')
