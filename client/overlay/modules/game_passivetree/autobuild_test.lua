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
g_clock = {millis = function() return clock end}
function showTreeAllocation() shown = shown + 1 end
function sendMessageBox() boxes = boxes + 1 end
local lastBox = nil
function displayGeneralBox(title, text, buttons, ok, cancel)
  lastBox = {title = title, text = text, buttons = buttons, destroyed = false}
  lastBox.destroy = function(self) self.destroyed = true end
  return lastBox
end
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
local pickKids = {slotCombo = widget('slotCombo'), introText = widget('introText'), saveButton = widget('saveButton')}
local pickWin = widget('autoBuildSlotWindow')
function pickWin:recursiveGetChildById(id) return pickKids[id] end
function pickWin:destroy() self.destroyed = true; self.visible = false end
kids.saveSlotButton = widget('saveSlotButton')
g_ui = {loadUI = function(name)
  if name == 'autobuildslot' then pickWin.destroyed = false; return pickWin end
  return win
end}
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
advance(AutoBuildView.MIN_GAP_MS)
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
advance(AutoBuildView.MIN_GAP_MS) -- the request gap (O560)
openAutoBuild()
list()
eq(count('autobuildPreview'), 1, 'reopened: the preview is asked again')
answer('ranger_sharpshooter', 0)

-- no answer at all: asked again on the timeout, then an error instead of waiting for good
closeAutoBuild()
sent = {}
advance(AutoBuildView.MIN_GAP_MS) -- the request gap (O560)
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
advance(AutoBuildView.MIN_GAP_MS) -- the request gap (O560)
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
advance(AutoBuildView.MIN_GAP_MS) -- the request gap (O560)
openAutoBuild()
list()
H.autobuildError({message = 'That build is not for your class.', build = 'ranger_sharpshooter'})
eq(detail.text:find('not for your class', 1, true) ~= nil, true, 'the refusal is shown')
list()
eq(count('autobuildPreview'), 1, 'a refused build is not asked for again by itself')
advance(AutoBuildView.PREVIEW_TIMEOUT_MS * 4)
eq(count('autobuildPreview'), 1, 'and no timer is left')
eq(boxes, 0, 'no message box while the window is open')

-- ------------------------------------------------------------------------------------------------ quick picks (O560)
-- the owner report of 2026-11-14: switching the build quickly was slow and sometimes did not switch. Picks inside the gap
-- are coalesced (the last one is asked for), the dropdown shows the pick at once, an older answer never overwrites it.
closeAutoBuild()
sent = {}
advance(AutoBuildView.MIN_GAP_MS)
openAutoBuild()
list()
answer('ranger_sharpshooter', 5)
advance(AutoBuildView.MIN_GAP_MS)
sent = {}
local combo = kids.buildCombo
local function pickRow(id)
  for i, o in ipairs(combo.options) do
    if o.text:find(id, 1, true) then combo.onOptionChange(combo, o.text, o.data); return end
  end
  error('no row ' .. id)
end
pickRow('Mana')
eq(count('autobuildPreview'), 1, 'a pick after a quiet moment is asked at once')
local firstSeq = sent[1].data.seq
eq(type(firstSeq), 'number', 'the request carries a number')
eq(sent[1].data.build, 'focus_mana', 'the pick is asked for')
advance(20)
pickRow('Sharpshooter') -- back to the first one inside the gap
eq(count('autobuildPreview'), 1, 'a pick inside the gap waits')
eq(detail.text:find('Asking', 1, true) ~= nil, true, 'the pick shows at once, waiting for its preview')
advance(AutoBuildView.MIN_GAP_MS)
eq(count('autobuildPreview'), 2, 'the waiting pick goes out after the gap')
eq(sent[2].data.build, 'ranger_sharpshooter', 'it asks for the last pick')
eq(sent[2].data.seq > firstSeq, true, 'with a newer number')
-- the slow answer of the first request arrives after the second was sent: dropped, nothing shown
H.autobuildPreview({build = 'focus_mana', seq = firstSeq, add = {added = 9, nodes = {}}, reset = {added = 0, removed = 0, nodes = {}}})
eq(detail.text:find('Asking', 1, true) ~= nil, true, 'an older answer shows nothing')
-- even an older answer for the same build (picked again) is dropped by its number
H.autobuildPreview({build = 'ranger_sharpshooter', seq = firstSeq, add = {added = 9, nodes = {}}, reset = {added = 0, removed = 0, nodes = {}}})
eq(detail.text:find('Asking', 1, true) ~= nil, true, 'an older number of the same build shows nothing')
H.autobuildPreview({build = 'ranger_sharpshooter', seq = sent[2].data.seq, add = {added = 4, nodes = {}}, reset = {added = 0, removed = 0, nodes = {}}})
eq(detail.text:find('Asking', 1, true), nil, 'the answer to the last pick is shown')
eq(kids.applyButton.enabled, true, 'Apply on for the last pick')
-- three quick picks: fewer requests than picks, the last one asked for last
sent = {}
advance(AutoBuildView.MIN_GAP_MS)
pickRow('Mana'); advance(10); pickRow('Sharpshooter'); advance(10); pickRow('Mana')
advance(AutoBuildView.MIN_GAP_MS * 2)
eq(count('autobuildPreview') <= 2, true, 'a run of picks is not one request each')
eq(sent[#sent].data.build, 'focus_mana', 'the last pick is the last asked for')
-- a refusal of the limit names its wait: asked again by that time; the refusal of an older request is ignored
local lastSeq = sent[#sent].data.seq
sent = {}
H.autobuildError({message = 'Too fast', build = 'focus_mana', retry = true, wait = 150, seq = lastSeq - 1})
advance(2000)
eq(count('autobuildPreview'), 0, 'the refusal of an older request is ignored')
H.autobuildError({message = 'Too fast', build = 'focus_mana', retry = true, wait = 150, seq = lastSeq})
advance(150 + AutoBuildView.RETRY_MARGIN_MS)
eq(count('autobuildPreview'), 1, 'the refusal says when: asked again right then, not after 700 ms')
advance(AutoBuildView.MIN_GAP_MS)
pickRow('Sharpshooter') -- the later sections start from this pick
closeAutoBuild()

-- ------------------------------------------------------------------------------------------------ save to a loadout slot (O448)
closeAutoBuild()
sent = {}
advance(AutoBuildView.MIN_GAP_MS) -- the request gap (O560)
openAutoBuild()
list()
answer('ranger_sharpshooter', 5)
eq(kids.saveSlotButton.enabled, true, 'a build is picked: Save to a loadout slot is on')
saveToSlotAutoBuild()
eq(count('autobuildSlots'), 1, 'the button asks the server for the slots')
-- the slots: slot 2 is active (holds the live build), 4 locked, 1 and 3 can be picked, 3 holds something
local choices = {slots = {{slot = 1, empty = true}, {slot = 2, name = 'Live', active = true}, {slot = 3, name = 'Boss run'},
  {slot = 4, empty = true, locked = true}}, limit = 3, max = 8, level = 100, minLevel = 15, nextUnlock = 200}
H.autobuildSlots(choices)
eq(pickWin.visible, true, 'the picker opens')
eq(#pickKids.slotCombo.options, 2, 'the picker lists the free slots only: not the active, not the locked')
eq(pickKids.slotCombo.options[1].text, 'Slot 1 - (empty)', 'an empty slot is named empty')
eq(pickKids.slotCombo.options[2].text, 'Slot 3 - Boss run', 'a held slot shows what it holds')
eq(pickKids.introText.text:find('Sharpshooter', 1, true) ~= nil, true, 'the picker names the build')
eq(pickKids.introText.text:find('gear, runes and Paragon', 1, true) ~= nil, true, 'the picker says gear and runes stay')
eq(pickKids.introText.text:find('live tree does not change', 1, true) ~= nil, true, 'the picker says the live tree stays')
-- an empty slot: sent at once, without the confirm
sent = {}
saveSlotOk()
eq(count('autobuildSaveSlot'), 1, 'Save sends the request')
eq(sent[1].data.build, 'ranger_sharpshooter', 'the build'); eq(sent[1].data.slot, 1, 'the picked slot'); eq(sent[1].data.confirm, false, 'no confirm for an empty slot')
eq(pickWin.destroyed, true, 'the picker closes')
H.autobuildSlotSaved({message = 'Saved Sharpshooter in loadout slot 1: 32 passive nodes.', lines = {'216 more nodes of the build need more points.'}, slot = 1})
eq(detail.text:find('Saved Sharpshooter in loadout slot 1', 1, true) ~= nil, true, 'the saved message is shown')
eq(detail.text:find('216 more nodes', 1, true) ~= nil, true, 'and its extra line')
eq(detail.color, AutoBuildView.GOOD, 'in green')
-- a held slot: the player confirms, nothing is sent before
answer('ranger_sharpshooter', 5)
saveToSlotAutoBuild()
H.autobuildSlots(choices)
pickKids.slotCombo.onOptionChange(pickKids.slotCombo, 'Slot 3 - Boss run', 2)
sent = {}
lastBox = nil
saveSlotOk()
eq(count('autobuildSaveSlot'), 0, 'a held slot: nothing is sent before the answer')
eq(lastBox ~= nil and lastBox.text:find('Slot 3 holds Boss run', 1, true) ~= nil, true, 'the question names the slot and what it holds')
eq(lastBox.text:find('Sharpshooter', 1, true) ~= nil, true, 'and the build')
lastBox.buttons[2].callback()
eq(count('autobuildSaveSlot'), 0, 'Cancel sends nothing')
saveSlotOk()
lastBox.buttons[1].callback()
eq(count('autobuildSaveSlot'), 1, 'Replace sends the request')
eq(sent[1].data.slot, 3, 'the held slot'); eq(sent[1].data.confirm, true, 'with the confirm')
eq(pickWin.destroyed, true, 'the picker closes after Replace')
H.autobuildSlotSaved({message = 'Saved Sharpshooter in loadout slot 3: 32 passive nodes.', slot = 3})
-- the server asks for the confirm itself (a slot filled meanwhile): the question comes, Replace sends it again with confirm
answer('ranger_sharpshooter', 5)
saveToSlotAutoBuild()
H.autobuildSlots(choices)
sent = {}
saveSlotOk() -- slot 1, sent without the confirm
lastBox = nil
H.autobuildError({message = 'Slot 1 already holds Old. Confirm to replace its passive tree.', slot = 1, build = 'ranger_sharpshooter',
  needConfirm = true, name = 'Old'})
eq(lastBox ~= nil and lastBox.text:find('Slot 1 holds Old', 1, true) ~= nil, true, 'the server asked: the question comes')
sent = {}
lastBox.buttons[1].callback()
eq(sent[1] and sent[1].data.confirm, true, 'the answer is sent with the confirm'); eq(sent[1] and sent[1].data.slot, 1, 'for the same slot')
-- a refusal of a save: shown as the answer to the save, the preview is not touched
H.autobuildError({message = 'That loadout is active: it holds your live build. Pick another slot.', slot = 3, build = 'ranger_sharpshooter'})
eq(detail.text:find('live build. Pick another slot', 1, true) ~= nil, true, 'a refused save is shown')
eq(detail.color, '#e07060', 'in red')
eq(kids.applyButton.enabled, true, 'a refused save leaves the preview as it was')
-- no slot to pick: a line instead of a picker
pickWin.visible = false
saveToSlotAutoBuild()
H.autobuildSlots({slots = {{slot = 1, name = 'Live', active = true}, {slot = 2, empty = true, locked = true}}, limit = 1, max = 8, level = 100,
  minLevel = 15, nextUnlock = 200})
eq(pickWin.visible, false, 'no slot to pick: no picker')
eq(detail.text:find('No loadout slot is free to pick', 1, true) ~= nil and detail.text:find('level 200', 1, true) ~= nil, true, 'a line says why and when')
-- below the loadouts' level
saveToSlotAutoBuild()
H.autobuildSlots({slots = {}, limit = 5, max = 8, level = 10, minLevel = 15})
eq(detail.text:find('Loadouts open at level 15', 1, true) ~= nil, true, 'below the level: the loadouts open at level 15')
-- an answer nobody asked for opens nothing
pickWin.visible = false
H.autobuildSlots(choices)
eq(pickWin.visible, false, 'a slot list nobody asked for opens nothing')
-- closing the panel closes the picker
saveToSlotAutoBuild()
H.autobuildSlots(choices)
eq(pickWin.visible, true, 'picker open again')
closeAutoBuild()
eq(pickWin.destroyed, true, 'closing the panel closes the picker')
-- a save refused while the panel is closed is a message box
sent = {}
boxes = 0
H.autobuildError({message = 'That slot is locked.', slot = 5})
eq(boxes, 1, 'a slot answer with the panel closed is a message box')


if fails > 0 then os.exit(1) end
print('autobuild_test: ok')
