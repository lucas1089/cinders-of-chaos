-- luajit npctalkview_test.lua && lua5.3 npctalkview_test.lua   (CI runs every client *_test.lua from the repo root)
-- npctalkview.lua on a fake widget engine (the fake of game_npctradewindow/tradefake.lua) built from the REAL npctalk.otui: a
-- lookup of an id the file lacks raises here as it does in the client. It plays the NPC header, the log with its two voices,
-- the clickable keywords, the grouped chips with the quest marks, the quick buttons, the input and the callbacks.
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

dofile(here .. '../game_npctradewindow/tradefake.lua')
local fake = TradeFake.install(here .. 'npctalk.otui')
local Widget, new = fake.Widget, fake.new
function Widget:setOutfit(o) self.outfit = o end
function Widget:setSize(s) self.size = s end
function Widget:setMarginRight(v) self.margins.right = v end
function Widget:setMarginBottom(v) self.margins.bottom = v end
function Widget:setEventListener(e) self.listeners = self.listeners or {} self.listeners[e] = true end
function Widget:setColoredText(t) self.colored = t end
function Widget:clearText() self.text = '' end
function Widget:getMaximum() return self.scroll.max end
function Widget:focus() self.focused = true end
local events = {}
function scheduleEvent(fn, ms) events[#events + 1] = fn return #events end
local cursors = {}
g_mouse = { pushCursor = function(c) cursors[#cursors + 1] = c end, popCursor = function() cursors[#cursors] = nil end }
EVENT_TEXT_CLICK, EVENT_TEXT_HOVER = 1, 2
KeyboardFocusReason = 1

dofile(here .. 'npctalk_logic.lua')
dofile(here .. 'npctalkview.lua')
local V, L = NpcTalkView, NpcTalkLogic

-- ---------------------------------------------------------------- the ids the code looks up are in the file
local node = fake.styles.NpcTalkWindow
eq(node ~= nil, true, 'the window style is in the file')
local win = fake.windowOf('NpcTalkWindow')
for _, id in ipairs(V.IDS) do eq(win:recursiveGetChildById(id) ~= nil, true, 'npctalk.otui has ' .. id) end
for _, s in ipairs({ 'NpcTalkNpcLine', 'NpcTalkPlayerLine', 'NpcTalkNote', 'NpcTalkChip', 'NpcTalkQuestChip', 'NpcTalkGroupLabel' }) do
  eq(fake.styles[s] ~= nil, true, 'style ' .. s)
end
-- no dead id in the window: everything it names is looked up
local used = {}
for _, id in ipairs(V.IDS) do used[id] = true end
local function walk(w)
  for _, k in ipairs(w.kids) do
    if k.id then eq(used[k.id], true, 'a widget id nothing looks up: ' .. k.id) end
    walk(k)
  end
end
walk(win)

local view = V.new(win)
local fired = {}
for _, name in ipairs({ 'say', 'bye', 'options', 'close', 'word' }) do view.on[name] = function(...) fired[#fired + 1] = { name, ... } end end
local ui = view.ui

-- the NPC
view:setNpc({ name = 'Maelis', title = 'Archivist', outfit = { type = 128 }, big = false })
eq(ui.npcName.text, 'Maelis', 'the name'); eq(ui.npcTitle.text, 'Archivist', 'the title')
eq(ui.portrait.outfit.type, 128, 'the portrait draws the NPC\'s own outfit')
eq(ui.portrait.size.width, 80, 'a big portrait for a 1x1 outfit'); eq(ui.portrait.margins.right, 0, 'no shift')
view:setNpc({ name = 'Wyrm', big = true })
eq(ui.portrait.size.width, 128, 'a 2x2 outfit is drawn larger'); eq(ui.portrait.margins.bottom, -8, 'and shifted to its figure')
eq(ui.npcTitle.text, '', 'no title: empty line')
view:setStatus('Click a gold word to say it.'); eq(view:status(), 'Click a gold word to say it.', 'the hint')

-- the log: the NPC in parchment with gold keywords, the player apart
local entries = {
  { side = 'player', who = 'You', text = 'hi' },
  { side = 'npc', who = 'Maelis', text = 'Ash on your boots. I keep the {ledger}. Ask me for {tales}.' },
}
view:renderLog(entries, false)
eq(#ui.textScroll.kids, 2, 'one label a line')
local mine, hers = ui.textScroll.kids[1], ui.textScroll.kids[2]
eq(mine.style, 'NpcTalkPlayerLine', 'the player has a style of his own'); eq(mine.text, 'You: hi', 'You: hi')
eq(hers.style, 'NpcTalkNpcLine', 'the NPC another')
eq(hers.colored[1], 'Maelis: ', 'the speaker first'); eq(hers.colored[2], '#e8b84a', 'in gold')
eq(hers.colored[3], 'Ash on your boots. I keep the ', 'then the words'); eq(hers.colored[4], L.COLORS.npc, 'in parchment')
eq(hers.colored[5], '[text-event]ledger[/text-event]', 'a keyword is a link'); eq(hers.colored[6], L.COLORS.keyword, 'in bright gold')
eq(hers.listeners[EVENT_TEXT_CLICK], true, 'a line with keywords listens for clicks')
hers.onTextClick(hers, 'ledger'); eq(fired[#fired][1], 'word', 'a click on a gold word'); eq(fired[#fired][2], 'ledger', 'says it')
hers.onTextHoverChange(hers, nil, true); eq(cursors[1], 'pointer', 'the pointer cursor over a word')
hers.onTextHoverChange(hers, nil, false); eq(#cursors, 0, 'and back')
hers.onTextHoverChange(hers, nil, true); hers.onDestroy(hers); eq(#cursors, 0, 'a destroyed label gives the cursor back')
view:renderLog({ { side = 'npc', who = 'Dove', text = 'No keywords here.' } }, false)
eq(ui.textScroll.kids[1].listeners, nil, 'no keywords: no click listener')
view:renderLog({ { side = 'player', who = 'You', text = 'hi' } }, true)
eq(#ui.textScroll.kids, 2, 'waiting adds a note'); eq(ui.textScroll.kids[2].text, '...', 'the note')
eq(#events > 0, true, 'the log scrolls to its end after a moment')
ui.textScrollBar.scroll.max = 90
events[#events]()
eq(ui.textScrollBar.scroll.value, 90, 'at the end')

-- the chips, grouped, quests marked
local groups = L.groups({ 'ledger', 'tales', 'quest', 'trade', 'portugues' })
view:setChips(groups)
eq(#ui.chips.kids, 5 + 4, 'five chips and a label for each of the four groups')
local labels, chips = {}, {}
for _, k in ipairs(ui.chips.kids) do
  if k.style == 'NpcTalkGroupLabel' then labels[#labels + 1] = k.text else chips[#chips + 1] = k end
end
eq(labels[1], 'Quests', 'quests first'); eq(labels[2], 'Trade', 'then trade'); eq(labels[3], 'Topics', 'topics'); eq(labels[4], 'Language', 'language last')
eq(chips[1].style, 'NpcTalkQuestChip', 'a quest chip is marked'); eq(chips[1].text, '! quest', 'with a "!"')
eq(chips[3].style, 'NpcTalkChip', 'a topic is plain'); eq(chips[3].text, 'ledger', 'the word')
chips[3].onClick(); eq(fired[#fired][1], 'word', 'a chip click'); eq(fired[#fired][2], 'ledger', 'says the word')
local h = view:layoutChips(430)
eq(h > 0, true, 'the chips have a height'); eq(ui.chips.height, h, 'on the panel'); eq(ui.chips.margins.bottom, 6, 'a gap under the chips')
eq(chips[1].margins.top, 14, 'the first chip under its label')
view:setChips(L.groups({ 'lore', 'story' }))
eq(#ui.chips.kids, 2, 'one group: no label')
eq(view:layoutChips(430), 22, 'one row')
view:setChips({})
eq(view:layoutChips(430), 0, 'no chips: no height')
-- a long word never leaves the row
view:setChips(L.groups({ string.rep('x', 200) }))
view:layoutChips(100)
eq(ui.chips.kids[1].width, 100, 'capped to the row')

-- the quick buttons
view:setButtons({ yes = true, no = true, trade = false })
eq(ui.yes.visible, true, 'yes'); eq(ui.trade.visible, false, 'trade hidden'); eq(ui.quickButtons.height, 24, 'the row is there')
view:setQuickWidth(430); eq(ui.yes.width, 110, 'a button is at most 110 wide')
view:setButtons({ yes = false, no = false, trade = false })
eq(ui.quickButtons.height, 0, 'no buttons: no row')
ui.yes.onClick(); eq(fired[#fired][1], 'say', 'a quick button says its word'); eq(fired[#fired][2], 'yes', 'yes')

-- the input
ui.input.text = 'tell me more'
ui.sayButton.onClick(); eq(fired[#fired][1], 'say', 'Say'); eq(fired[#fired][2], 'tell me more', 'sends the text'); eq(ui.input.text, '', 'and clears the field')
ui.byeButton.onClick(); eq(fired[#fired][1], 'bye', 'Bye')
ui.closeButton.onClick(); eq(fired[#fired][1], 'close', 'the x')
ui.optionsButton.onClick(); eq(fired[#fired][1], 'options', 'the menu')
view:focusInput(); eq(ui.input.focused, true, 'the input is focused')
view:clearInput()

print(string.format('npctalkview_test: %d checks OK', n))
