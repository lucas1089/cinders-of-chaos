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

-- content height of a verticalBox: shown children with their margins, plus padding
local kids = { { visible = true, height = 120, marginTop = 2 }, { visible = false, height = 300 },
  { visible = true, height = 90, marginBottom = 3 } }
eq(L.contentHeight(kids, { top = 1, bottom = 1 }), 217, 'content: shown only, margins, padding')
eq(L.contentHeight(kids, nil, 4), 219, 'content: spacing between shown')
eq(L.contentHeight({ { visible = false, height = 50 } }, { top = 2, bottom = 2 }), 0, 'content: nothing shown')

-- limit: the resize maximum, and room left below
eq(L.limit(nil), L.MAX_HEIGHT, 'limit: no parent')
eq(L.limit(1080), L.MAX_HEIGHT, 'limit: tall screen')
eq(L.limit(600), 450, 'limit: room kept below')

-- setting not readable: nothing is touched
local p = L.plan({ optionOn = nil, height = 300, children = 2, visible = 2, content = 200 })
eq(p.height, nil, 'unknown: no height'); eq(p.evict, false, 'unknown: no evict')

-- option off, the owner's case: the login put the saved height and windows back (map view, inventory, skills over a
-- gap); the windows go to the side panel and the panel closes
p = L.plan({ optionOn = false, height = 500, children = 3, visible = 3, content = 410 })
eq(p.evict, true, 'off: windows moved out'); eq(p.height, 0, 'off: height 0'); eq(p.opaque, false, 'off: not opaque')
p = L.plan({ optionOn = false, height = 0, children = 1, visible = 0, content = 0 })
eq(p.evict, true, 'off: a closed window is moved out too'); eq(p.height, nil, 'off: already 0')
p = L.plan({ optionOn = false, height = 0, children = 0, visible = 0 })
eq(p.evict, false, 'off and empty: nothing'); eq(p.height, nil, 'off and empty: no height')

-- option on, nothing visible: the 200 px gap closes
p = L.plan({ optionOn = true, height = 200, children = 0, visible = 0, content = 0 })
eq(p.height, 0, 'empty: collapses'); eq(p.opaque, false, 'empty: not opaque'); eq(p.evict, false, 'on: never evicts')
p = L.plan({ optionOn = true, height = 0, visible = 0 })
eq(p.height, nil, 'empty and collapsed: nothing')

-- option on with windows: as high as they are, no gap under the last one
p = L.plan({ optionOn = true, height = 500, children = 3, visible = 3, content = 410, limit = 800 })
eq(p.height, 410, 'shown: fits the windows'); eq(p.opaque, true, 'shown: opaque')
p = L.plan({ optionOn = true, height = 410, children = 3, visible = 3, content = 410, limit = 800 })
eq(p.height, nil, 'shown: already fits')
p = L.plan({ optionOn = true, height = 0, children = 1, visible = 1, content = 150, limit = 800 })
eq(p.height, 150, 'window arrives: its height')
p = L.plan({ optionOn = true, height = 200, children = 2, visible = 2, content = 300, limit = 800 })
eq(p.height, 300, 'a window grew: the panel grows')
p = L.plan({ optionOn = true, height = 400, children = 4, visible = 4, content = 1200, limit = 800 })
eq(p.height, 800, 'too tall: capped (the base moves the overflow out)')
p = L.plan({ optionOn = true, height = 500, children = 2, visible = 2, content = 300, limit = 800, dragging = true })
eq(p.height, nil, 'dragging: height kept')

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
