-- luajit panelroom_test.lua && lua5.3 panelroom_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'panelroom_logic.lua')
local R = ChaosPanelRoom
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local function win(id, height, min, kind, extra)
  local w = { id = id, height = height, min = min, kind = kind or 'container', resizable = true }
  for k, v in pairs(extra or {}) do w[k] = v end
  return w
end
local function panel(id, height, windows, reserved) return { id = id, height = height, windows = windows, reserved = reserved } end
-- the heights a plan leaves: the sum of the panel's windows after the shrinks
local function after(p, plan)
  local sum = 0
  local to = {}
  for _, s in ipairs(plan.shrinks) do to[s.window] = s.to end
  for i, w in ipairs(p.windows) do sum = sum + (to[i] or w.height) end
  return sum
end
local function check_invariants(panels, plan, new, what)
  if not plan then return end
  local p = panels[plan.panel]
  eq(p.reserved and true or false, false, what .. ': never the reserved panel')
  for _, s in ipairs(plan.shrinks) do
    local w = p.windows[s.window]
    eq(s.to >= w.min, true, what .. ': never below the minimum (' .. s.id .. ')')
    eq(s.to < s.from, true, what .. ': a shrink shrinks (' .. s.id .. ')')
    eq(not (w.protected or w.minimized or w.resizable == false), true, what .. ': a fixed window is left alone (' .. s.id .. ')')
  end
end

-- 1) it fits: nothing shrinks, the base order holds
local panels = { panel('right1', 600, { win('container1', 200, 60), win('container2', 200, 60) }), panel('left1', 600, {}) }
local plan = R.plan(panels, { height = 150, min = 60 })
eq(plan.action, 'fit', 'fits: action') eq(plan.panel, 1, 'fits: the first panel in the base order') eq(#plan.shrinks, 0, 'fits: no shrink')
eq(plan.height, 150, 'fits: the whole height')
-- its minimum fits, its height does not: the base rule takes it, at the room left
panels = { panel('right1', 600, { win('container1', 250, 60), win('container2', 250, 60) }) }
plan = R.plan(panels, { height = 150, min = 60 })
eq(plan.action, 'fit', 'minimum fits: action') eq(plan.height, 100, 'minimum fits: the room left') eq(#plan.shrinks, 0, 'minimum fits: no shrink')
-- a later panel with room is used before anything shrinks
panels = { panel('right1', 600, { win('container1', 300, 60), win('container2', 300, 60) }), panel('left1', 600, { win('container3', 100, 60) }) }
plan = R.plan(panels, { height = 150, min = 60 })
eq(plan.action, 'fit', 'second panel: action') eq(plan.panel, 2, 'second panel: the one with room')

-- 2) fits after shrinking one container (the chest of the owner's screenshot: both panels full, one big bag open)
panels = { panel('right1', 600, { win('container1', 400, 60), win('container2', 200, 60) }) }
plan = R.plan(panels, { height = 150, min = 60 })
eq(plan.action, 'shrink', 'one container: action') eq(plan.panel, 1, 'one container: panel') eq(#plan.shrinks, 1, 'one container: one shrink')
eq(plan.shrinks[1].id, 'container1', 'one container: the biggest')
eq(plan.shrinks[1].from, 400, 'one container: from') eq(plan.shrinks[1].to, 340, 'one container: only as far as needed')
eq(after(panels[1], plan) + plan.height, 600, 'one container: the panel is exactly full')
eq(plan.height, 60, 'one container: the new window gets its minimum')
check_invariants(panels, plan, { height = 150, min = 60 }, 'one container')

-- 2b) fits after shrinking several: the biggest first, each to its minimum, the last one partly
panels = { panel('right1', 600, { win('container1', 200, 100), win('container2', 150, 100), win('container3', 250, 100) }) }
plan = R.plan(panels, { height = 250, min = 200 })
eq(plan.action, 'shrink', 'several: action') eq(#plan.shrinks, 2, 'several: two windows shrink')
eq(plan.shrinks[1].id, 'container3', 'several: the biggest first') eq(plan.shrinks[1].to, 100, 'several: to its minimum')
eq(plan.shrinks[2].id, 'container1', 'several: then the next biggest') eq(plan.shrinks[2].to, 150, 'several: the last one partly')
eq(after(panels[1], plan) + plan.height, 600, 'several: the panel is exactly full')
check_invariants(panels, plan, { height = 250, min = 200 }, 'several')

-- containers before other windows, however big the others are
panels = { panel('right1', 600, { win('skills', 300, 100, 'mini'), win('container1', 150, 100), win('container2', 150, 100) }) }
plan = R.plan(panels, { height = 150, min = 100 })
eq(plan.action, 'shrink', 'order: action') eq(plan.shrinks[1].id, 'container1', 'order: a container first') eq(#plan.shrinks, 2, 'order: the other container too')
eq(plan.shrinks[2].id, 'container2', 'order: both containers before the mini window')
-- when the containers cannot give enough the other resizable windows do
panels = { panel('right1', 600, { win('skills', 300, 100, 'mini'), win('container1', 150, 100), win('container2', 150, 100) }) }
plan = R.plan(panels, { height = 300, min = 300 })
eq(plan.action, 'shrink', 'mini windows: action') eq(#plan.shrinks, 3, 'mini windows: all three shrink')
eq(plan.shrinks[3].id, 'skills', 'mini windows: after the containers')
eq(after(panels[1], plan) + plan.height, 600, 'mini windows: exactly full')
check_invariants(panels, plan, { height = 300, min = 300 }, 'mini windows')

-- fixed windows are not touched: minimized, not resizable, protected
panels = { panel('right1', 700, { win('container1', 200, 60, 'container', { minimized = true }), win('buttons', 150, 0, 'mini'),
  win('inventoryWindow', 150, 80, 'mini', { protected = true }), win('container2', 200, 60) }) }
plan = R.plan(panels, { height = 150, min = 100 })
eq(plan.action, 'shrink', 'fixed: action') eq(#plan.shrinks, 1, 'fixed: one shrink') eq(plan.shrinks[1].id, 'container2', 'fixed: only the free one')
eq(plan.shrinks[1].to, 100, 'fixed: by the room needed') eq(after(panels[1], plan) + plan.height, 700, 'fixed: exactly full')
check_invariants(panels, plan, { height = 150, min = 100 }, 'fixed')

-- 3) nothing can shrink: forced, in the panel with the most room, the window at its minimum
panels = { panel('right1', 600, { win('container1', 300, 300), win('container2', 300, 300) }) }
plan = R.plan(panels, { height = 150, min = 60 })
eq(plan.action, 'force', 'nothing shrinks: action') eq(plan.panel, 1, 'nothing shrinks: the panel') eq(#plan.shrinks, 0, 'nothing shrinks: no shrink')
eq(plan.height, 60, 'nothing shrinks: the window keeps its minimum height')
-- forced after shrinking all it can
panels = { panel('right1', 300, { win('container1', 200, 120), win('container2', 200, 120) }) }
plan = R.plan(panels, { height = 150, min = 150 })
eq(plan.action, 'force', 'all at minimum: action') eq(#plan.shrinks, 2, 'all at minimum: both shrink') eq(plan.shrinks[1].to, 120, 'all at minimum: to the minimum')
eq(plan.shrinks[2].to, 120, 'all at minimum: the other too')
check_invariants(panels, plan, { height = 150, min = 150 }, 'all at minimum')
-- nothing is ever closed: the plan has no close action and the windows keep their count
eq(plan.close, nil, 'no close in the plan')

-- two panels: the shrink goes to the panel with the most room, not the first
panels = { panel('right1', 600, { win('container1', 300, 200), win('container2', 300, 200) }),
           panel('left1', 600, { win('container3', 300, 100), win('container4', 300, 100) }) }
plan = R.plan(panels, { height = 150, min = 100 })
eq(plan.action, 'shrink', 'two panels: action') eq(plan.panel, 2, 'two panels: the panel with the most room')
eq(plan.shrinks[1].id, 'container3', 'two panels: its biggest (the first one on a tie)') eq(plan.shrinks[1].to, 200, 'two panels: shrunk by the 100 needed')
-- the same room: the first panel keeps it
panels = { panel('right1', 600, { win('container1', 600, 100) }), panel('left1', 600, { win('container3', 600, 100) }) }
plan = R.plan(panels, { height = 150, min = 100 })
eq(plan.panel, 1, 'two panels: a tie goes to the first')
-- forced goes where the overflow is smallest
panels = { panel('right1', 300, { win('container1', 300, 290) }), panel('left1', 300, { win('container2', 300, 200) }) }
plan = R.plan(panels, { height = 250, min = 250 })
eq(plan.action, 'force', 'two panels forced: action') eq(plan.panel, 2, 'two panels forced: the least overflow')

-- the minimap reservation panel is skipped as today, even when empty
panels = { panel('reserve', 800, {}, true), panel('right1', 600, { win('container1', 300, 60) }) }
plan = R.plan(panels, { height = 150, min = 60 })
eq(plan.action, 'fit', 'reservation: action') eq(plan.panel, 2, 'reservation: skipped')
panels = { panel('reserve', 800, {}, true), panel('right1', 300, { win('container1', 300, 60) }) }
plan = R.plan(panels, { height = 150, min = 60 })
eq(plan.action, 'shrink', 'reservation, full panel: shrinks the real one') eq(plan.panel, 2, 'reservation, full panel: panel')
eq(R.plan({ panel('reserve', 800, {}, true) }, { height = 150, min = 60 }), nil, 'only a reservation: no plan')
eq(R.plan({}, { height = 150, min = 60 }), nil, 'no panel: no plan')

-- odd input: no minimum known, text numbers, a window taller than its panel
plan = R.plan({ panel('right1', 600, { win('container1', 500, 60) }) }, { height = 150 })
eq(plan.action, 'shrink', 'no minimum: the height is the need') eq(plan.shrinks[1].to, 450, 'no minimum: shrink by the height')
plan = R.plan({ panel('right1', 100, { win('container1', 300, 60) }) }, { height = 80, min = 40 })
eq(plan.action, 'shrink', 'overfull panel: action') eq(plan.shrinks[1].to, 60, 'overfull panel: the deficit counts the overflow')

if fails > 0 then print('panelroom_test: ' .. fails .. ' failure(s)') os.exit(1) end
print('panelroom_test: ok')
