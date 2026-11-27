-- luajit popupqueue_test.lua && lua5.3 popupqueue_test.lua (from anywhere; CI runs it from the repo root)
-- The queue logic, then the engine file on a fake engine: a level jump's popups open one at a time (F46, O772).
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'popupqueue_logic.lua')
local Q = PopupQueueLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- logic: order, settle time, blockers, same key
local s = Q.new()
eq(Q.pending(s), false, 'empty')
eq(Q.push(s, 'mentor', { n = 1 }), 'queued', 'first push waits')
Q.push(s, 'survey', { n = 2 })
eq(Q.step(s, 0, false, false), nil, 'clear screen: the settle time starts')
eq(Q.step(s, Q.SETTLE_MS - 1, false, false), nil, 'not yet settled')
local e = Q.step(s, Q.SETTLE_MS, false, false)
eq(e and e.key, 'mentor', 'first come, first open')
eq(Q.step(s, 2000, false, true), nil, 'one on screen: the next waits')
eq(Q.step(s, 2100, false, false), nil, 'closed: the settle time starts again')
eq(Q.step(s, 2100 + Q.SETTLE_MS, false, false).key, 'survey', 'then the survey')
eq(Q.step(s, 9000, false, false), nil, 'survey closed')
eq(Q.pending(s), false, 'all shown')

s = Q.new()
Q.push(s, 'a', {})
Q.step(s, 0, false, false)
eq(Q.step(s, 300, true, false), nil, 'a message box came: wait')
eq(Q.step(s, 1000, false, false), nil, 'box gone: the settle time starts again')
eq(Q.step(s, 1000 + Q.SETTLE_MS, false, false).key, 'a', 'opens after the box')

s = Q.new()
Q.push(s, 'a', { v = 1 })
Q.push(s, 'b', {})
Q.push(s, 'a', { v = 2 })
eq(#s.list, 2, 'same key: no second copy')
eq(s.list[1].v, 2, 'same key: the new opener, the old turn')
Q.remove(s, 'a')
eq(s.list[1].key, 'b', 'cancelled')
Q.step(s, 0, false, false)
Q.step(s, Q.SETTLE_MS, false, false)
eq(Q.push(s, 'b', {}), 'now', 'the popup on screen refreshes at once')
Q.clear(s)
eq(Q.pending(s), false, 'cleared at logout')

-- engine: a fake root, clock and scheduler
local now, events = 0, {}
g_clock = { millis = function() return now end }
function scheduleEvent(fn, ms) local ev = { fn = fn, at = now + ms } events[#events + 1] = ev return ev end
function removeEvent(ev) for i, x in ipairs(events) do if x == ev then table.remove(events, i) return end end end
local function advance(ms)
  local stop = now + ms
  while true do
    table.sort(events, function(a, b) return a.at < b.at end)
    local ev = events[1]
    if not ev or ev.at > stop then break end
    table.remove(events, 1)
    now = ev.at
    ev.fn()
  end
  now = stop
end
g_logger = { warning = function(m) print('warn ' .. m) end }
function connect() end
function disconnect() end
g_game = {}
modules = {}
local function widget(class)
  local w = { shown = true }
  function w:getClassName() return class end
  function w:isVisible() return self.shown end
  function w:isDestroyed() return false end
  return w
end
local children = {}
rootWidget = { getChildren = function() return children end, recursiveGetChildById = function() return nil end }

dofile(dir .. 'popupqueue.lua')
init()
local P = ChaosPopupQueue
eq(type(P), 'table', 'the global is set')

-- the level jump: the Helper's box first, then the mentor offer and the survey in the same second
local box = widget('UIMessageBox')
children[1] = box
local onScreen = {}
local function popup(name)
  return function() onScreen[name] = true end, function() return onScreen[name] == true end
end
local mo, mi = popup('mentor')
local so, si = popup('survey')
P.request('mentor', mo, mi)
P.request('survey', so, si)
local function count() local n = 0 for _ in pairs(onScreen) do n = n + 1 end return n end
advance(3000)
eq(count(), 0, 'nothing over the Helper box')
box.shown = false
advance(1000)
eq(onScreen.mentor, true, 'box closed: the mentor offer')
eq(onScreen.survey, nil, 'one at a time')
advance(5000)
eq(count(), 1, 'still one')
onScreen.mentor = nil
advance(1000)
eq(onScreen.survey, true, 'then the survey')
onScreen.survey = nil
advance(1000)
eq(P.pending(), false, 'done')
eq(#events, 0, 'no tick left running')

-- a server modal dialog holds the queue too
modules.game_modaldialog = { modalDialog = {} }
P.request('mentor', mo, mi)
advance(2000)
eq(onScreen.mentor, nil, 'waits for the modal dialog')
modules.game_modaldialog.modalDialog = nil
advance(1000)
eq(onScreen.mentor, true, 'opens after it')
terminate()
eq(rawget(_G, 'ChaosPopupQueue'), nil, 'terminate clears the global')

if fails > 0 then print(fails .. ' failure(s)') os.exit(1) end
print('popupqueue_test: OK')
