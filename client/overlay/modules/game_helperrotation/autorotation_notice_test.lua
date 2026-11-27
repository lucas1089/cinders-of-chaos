-- luajit autorotation_notice_test.lua && lua5.3 autorotation_notice_test.lua (from anywhere; CI runs it from the repo root)
-- The Helper's "New spell available" box waits in the popup queue (F47, O773): at a level jump it opened at once over
-- the mentor offer, which the queue had already put on screen. The engine file autorotation_ui.lua runs on a fake
-- engine with the real queue (client_chaos_popupqueue) and a stub of the choice (ChaosAutoRotation).
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- fake clock and scheduler
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
g_logger = { warning = function(m) print('warn ' .. m) end, info = function() end }
function connect() end
function disconnect() end
function tr(s, ...) if select('#', ...) > 0 then return string.format(s, ...) end return s end
AnchorHorizontalCenter = 'hcenter'
g_ui = { getRootWidget = function() return nil end }

-- the root: message boxes are its children
local children = {}
rootWidget = { getChildren = function() return children end, recursiveGetChildById = function() return nil end }
local boxes = 0
function displayGeneralBox(title, text, buttons, onEnter, onEscape)
  boxes = boxes + 1
  local b = { title = title, text = text, buttons = buttons, shown = true, destroyed = false }
  function b:getClassName() return 'UIMessageBox' end
  function b:isVisible() return self.shown end
  function b:isDestroyed() return self.destroyed end
  function b:destroy()
    self.destroyed = true
    for i, c in ipairs(children) do if c == self then table.remove(children, i) break end end
  end
  children[#children + 1] = b
  return b
end
local function openBox()
  for _, c in ipairs(children) do if c.title == 'New spell available' and not c.destroyed then return c end end
end

-- the player, the Helper and the settings
local player = { getVocation = function() return 15 end, getLevel = function() return 120 end,
  getName = function() return 'Tester' end }
g_game = { getLocalPlayer = function() return player end, isOnline = function() return false end }
local settings = {}
g_settings = { getNode = function(k) return settings[k] end, setNode = function(k, v) settings[k] = v end }
ChaosHelperConfig = { spellPrefs = function(p) p = p or {} return { autoUpdate = p.autoUpdate, ignored = p.ignored or {} } end }
local profile = { rules = {} }
modules = { game_helper = { _Helper = { getShooterProfile = function() return profile end } } }

-- the choice: a level-up that brings spell 101 asks
ChaosAutoRotation = {
  MARKER = 'chaosAuto',
  select = function() return {} end,
  levelUpAction = function() return 'notice', { 101 } end,
  variantName = function() return nil end,
}
ChaosAutoRotationData = { spells = { [101] = { name = 'Ember Lash', words = 'ember lash' } } }

dofile(dir .. 'autorotation_ui.lua')
local U = ChaosAutoRotationUI

-- no queue loaded: the box opens at once (the old way, for a client without the module)
eq(U.onLevelUp(), 'notice', 'a new spell asks')
eq(openBox() ~= nil, true, 'without the queue: at once')
eq(openBox().text, 'New spell available: Ember Lash.\nAdd to rotation?', 'the text')
openBox().buttons[2].callback() -- Ignore
eq(openBox(), nil, 'Ignore closes it')

-- the queue loaded; the mentor offer of the same level jump is on screen first
dofile(dir .. '../client_chaos_popupqueue/popupqueue_logic.lua')
dofile(dir .. '../client_chaos_popupqueue/popupqueue.lua')
init()
local P = ChaosPopupQueue
local mentorOn = false
P.request('mentorOffer', function() mentorOn = true end, function() return mentorOn end)
advance(1000)
eq(mentorOn, true, 'the mentor offer is on screen')
local surveyOn = false
boxes = 0
U.onLevelUp()
P.request('survey', function() surveyOn = true end, function() return surveyOn end)
eq(boxes, 0, 'the box does not open over the mentor offer')
advance(5000)
eq(openBox(), nil, 'still waiting')
-- a second level-up before its turn: one box, the newer text
U.onLevelUp()
mentorOn = false
advance(1000)
eq(openBox() ~= nil, true, 'mentor offer closed: the box')
eq(boxes, 1, 'one box for both level-ups')
eq(surveyOn, false, 'the survey waits for the box')
eq(U.noticeShown(), true, 'the queue sees the box')
openBox().buttons[2].callback() -- Ignore
eq(openBox(), nil, 'the answer closes it')
eq(U.noticeShown(), false, 'and the queue sees it gone')
advance(1000)
eq(surveyOn, true, 'then the survey')
surveyOn = false
advance(1000)
eq(P.pending(), false, 'queue empty')

-- logout before its turn: the queue forgets it
mentorOn = true
P.request('mentorOffer', function() end, function() return mentorOn end)
U.onLevelUp()
U.terminate()
mentorOn = false
advance(2000)
eq(openBox(), nil, 'the module unloaded: no box later')
terminate()

if fails > 0 then print(fails .. ' failure(s)') os.exit(1) end
print('autorotation_notice_test: OK')
