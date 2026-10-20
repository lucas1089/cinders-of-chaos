-- luajit autobuild_test.lua && lua5.3 autobuild_test.lua (from this folder or the repo root). autobuild.lua against a
-- mocked client: the owner's report (2026-10-20) of a window stuck at "Asking the server for a preview..." with Apply
-- and Reset and apply off. Every way of showing a build must ask for its preview, and every wait must end.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'autobuildview.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ------------------------------------------------------------------------------------------------ the mocked client
local sent, events, clock, boxes, shown = {}, {}, 0, 0, 0
function sendAction(action, data) sent[#sent + 1] = {action = action, data = data} end
function scheduleEvent(fn, ms) local e = {fn = fn, at = clock + ms}; events[#events + 1] = e; return e end
function removeEvent(e) if e then e.removed = true end end
local function advance(ms)
  clock = clock + ms
  for _, e in ipairs(events) do
    if not e.removed and e.at <= clock then e.removed = true; e.fn() end
  end
end
function showTreeAllocation() shown = shown + 1 end
function sendMessageBox() boxes = boxes + 1 end
function displayGeneralBox() return {destroy = function() end} end
AnchorHorizontalCenter = 1
function tr(s, ...) if select('#', ...) > 0 then return string.format(s, ...) end return s end

local function widget(id)
  local w = {id = id, text = '', color = nil, enabled = true, visible = true, options = {}}
  function w:setText(t) self.text = t end
  function w:setColor(c) self.color = c end
  function w:setEnabled(v) self.enabled = v end
  function w:isDestroyed() return false end
  function w:isVisible() return self.visible end
  function w:show() self.visible = true end
  function w:hide() self.visible = false end
  function w:raise() end
  function w:focus() end
  function w:clearOptions() self.options = {} end
  function w:addOption(text, data) self.options[#self.options + 1] = {text = text, data = data} end
  function w:setCurrentIndex(i) self.current = i end
  return w
end
local win = widget('autoBuildWindow')
local kids = {detailText = widget('detailText'), applyButton = widget('applyButton'), resetButton = widget('resetButton'),
  buildCombo = widget('buildCombo')}
function win:recursiveGetChildById(id) return kids[id] end
g_ui = {loadUI = function() return win end}
function getTreeWindow() return {} end

dofile(dir .. 'autobuild.lua')
local H = ChaosTreeHandlers

local function count(action)
  local n = 0
  for _, s in ipairs(sent) do if s.action == action then n = n + 1 end end
  return n
end
local function list()
  local builds = {{id = 'ranger_sharpshooter', name = 'Sharpshooter', text = 'Damage first.', points = 248, fit = 'primary'}}
  H.autobuildList({group = 'role', builds = builds, owned = 32, held = 32, free = 0, cap = 248})
  H.autobuildList({group = 'focus', builds = {{id = 'focus_mana', name = 'Mana', points = 150}}, owned = 32, held = 32, free = 0})
end
local function answer(build, added)
  H.autobuildPreview({build = build, add = {added = added, nodes = {}}, reset = {added = 0, removed = 0, nodes = {}}})
end
local detail = kids.detailText

-- the first opening: the list asks for the first build's preview once (the list comes twice)
openAutoBuild()
eq(count('autobuildList'), 1, 'open: the list is asked for')
list()
eq(count('autobuildPreview'), 1, 'first list: one preview asked')
answer('ranger_sharpshooter', 5)
eq(detail.text:find('Asking', 1, true), nil, 'preview shown')
eq(kids.applyButton.enabled, true, 'Apply on')

-- Apply: the new list must ask for the preview of the new tree (it did not: stuck at "Asking...")
sent = {}
H.autobuildApplied({message = 'Auto build: 5 nodes added, 32 in all.'})
list()
eq(count('autobuildPreview'), 1, 'after an Apply: the preview is asked again')
eq(detail.text:find('5 nodes added', 1, true) ~= nil, true, 'the applied message stays while waiting')
answer('ranger_sharpshooter', 0)
eq(detail.text:find('Asking', 1, true), nil, 'after an Apply: preview shown')
eq(kids.applyButton.enabled, false, 'nothing left to add: Apply off')

-- closing and opening the window again: asked again (it was not)
closeAutoBuild()
sent = {}
openAutoBuild()
list()
eq(count('autobuildPreview'), 1, 'reopened: the preview is asked again')
answer('ranger_sharpshooter', 0)

-- no answer at all: asked again on the timeout, then an error instead of waiting for good
closeAutoBuild()
sent = {}
openAutoBuild()
list()
eq(count('autobuildPreview'), 1, 'asked')
for _ = 2, AutoBuildView.MAX_TRIES do
  advance(AutoBuildView.PREVIEW_TIMEOUT_MS)
end
eq(count('autobuildPreview'), AutoBuildView.MAX_TRIES, 'asked again on each timeout')
advance(AutoBuildView.PREVIEW_TIMEOUT_MS)
eq(count('autobuildPreview'), AutoBuildView.MAX_TRIES, 'not more than MAX_TRIES')
eq(detail.text:find('did not answer', 1, true) ~= nil, true, 'the timeout shows an error')
eq(detail.color, '#e07060', 'in red')
eq(detail.text:find('Asking', 1, true), nil, 'no longer "Asking..."')
-- a late answer still shows the preview and clears the error
answer('ranger_sharpshooter', 3)
eq(detail.text:find('did not answer', 1, true), nil, 'late answer: the error goes')
eq(kids.applyButton.enabled, true, 'late answer: Apply on')

-- "too fast" from the server: asked again after a moment, no error shown
closeAutoBuild()
sent = {}
openAutoBuild()
list()
H.autobuildError({message = 'Too fast', build = 'ranger_sharpshooter', retry = true})
eq(detail.text:find('Too fast', 1, true), nil, 'too fast is not shown')
advance(AutoBuildView.RETRY_DELAY_MS)
eq(count('autobuildPreview'), 2, 'too fast: asked again')
answer('ranger_sharpshooter', 1)
eq(kids.applyButton.enabled, true, 'too fast, then the answer')

-- a refusal ends the wait with its text; the build is not asked for again by the next list
closeAutoBuild()
sent = {}
openAutoBuild()
list()
H.autobuildError({message = 'That build is not for your class.', build = 'ranger_sharpshooter'})
eq(detail.text:find('not for your class', 1, true) ~= nil, true, 'the refusal is shown')
list()
eq(count('autobuildPreview'), 1, 'a refused build is not asked for again by itself')
advance(AutoBuildView.PREVIEW_TIMEOUT_MS * 4)
eq(count('autobuildPreview'), 1, 'and no timer is left')
eq(boxes, 0, 'no message box while the window is open')

if fails > 0 then os.exit(1) end
print('autobuild_test: ok')
