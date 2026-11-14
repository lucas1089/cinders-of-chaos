-- luajit npctalk_test.lua && lua5.3 npctalk_test.lua   (CI runs every client *_test.lua from the repo root)
-- The glue of npctalk.lua against a mocked client: a greeting opens the dialogue window beside the NPC (not over the player),
-- the NPC's lines reach the log through the console hook and the talk signal, the chips and the title follow, a chip says its
-- word, Bye and Esc end the conversation, and unloading puts the hooks back. The widgets are the real npctalk.otui.
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

dofile(here .. '../game_npctradewindow/tradefake.lua')
local fake = TradeFake.install(here .. 'npctalk.otui')
local Widget, new = fake.Widget, fake.new
function Widget:setOutfit(o) self.outfit = o end
function Widget:setSize(s) self.size = s end
function Widget:getWidth() return self.size and self.size.width or 480 end
function Widget:getHeight() return self.size and self.size.height or 480 end
function Widget:getPaddingLeft() return 16 end
function Widget:getPaddingRight() return 16 end
function Widget:setPosition(p) self.position = p end
function Widget:setMarginRight(v) self.margins.right = v end
function Widget:setMarginBottom(v) self.margins.bottom = v end
function Widget:setEventListener() end
function Widget:setColoredText(t) self.colored = t end
function Widget:clearText() self.text = '' end
function Widget:getMaximum() return self.scroll.max end
function Widget:raise() self.raised = true end
function Widget:focus() self.focused = true end
function Widget:getRect() return { x = 0, y = 0, width = 1280, height = 720 } end
function Widget:getChildById(id) for _, k in ipairs(self.kids) do if k.id == id then return k end end end

-- ---------------------------------------------------------------- the fake client
local warnings, sent, keys, events = {}, {}, {}, {}
g_logger = { warning = function(m) warnings[#warnings + 1] = m end }
MS = 100000
g_clock = { millis = function() return MS end }
function scheduleEvent(fn) events[#events + 1] = fn return #events end
function cycleEvent(fn) events.tick = fn return 'tick' end
function removeEvent(e) if e == 'tick' then events.tick = nil end end
g_keyboard = { bindKeyPress = function(key, fn, w) keys[w] = keys[w] or {} keys[w][key] = fn end,
  bindKeyDown = function(key, fn, w) keys[w] = keys[w] or {} keys[w][key] = fn end,
  unbindKeyDown = function() end }
g_mouse = { pushCursor = function() end, popCursor = function() end }
g_settings = { getNode = function() return {} end, setNode = function() end }
EVENT_TEXT_CLICK, EVENT_TEXT_HOVER = 1, 2
KeyboardFocusReason = 1
MessageModes = { NpcFrom = 20, NpcFromStartBlock = 21, NpcTo = 22 }
NPC_NAME_CHAT = 'NPCs'
ThingCategoryCreature = 1
connect, disconnect = function() end, function() end

local function pos(x, y) return { x = x, y = y, z = 7 } end
local ppos = pos(1000, 1000)
local player = { getId = function() return 1 end, getPosition = function() return ppos end, getLevel = function() return 5 end, isAutoWalking = function() return false end,
  isWalking = function() return false end, stopAutoWalk = function() end }
local function creature(id, name, at)
  return { __userdata = true, id = id, name = name, at = at, getId = function(self) return self.id end,
    getName = function(self) return self.name end, getPosition = function(self) return self.at end,
    isNpc = function() return true end, isCreature = function() return true end, isRemoved = function() return false end,
    isWalking = function() return false end, getOutfit = function() return { type = 130 } end }
end
local maelis = creature(11, 'Archivist Maelis', pos(1002, 1000))
g_game = {
  isOnline = function() return true end, getLocalPlayer = function() return player end,
  talk = function(t) sent[#sent + 1] = { 'say', t } end,
  talkPrivate = function(mode, who, t) sent[#sent + 1] = { 'private', t } end,
  use = function() sent[#sent + 1] = { 'use' } end, getCharacterName = function() return 'Ash' end,
}
local texts = {}
g_map = { getSpectators = function() return { maelis } end, addThing = function(t, p) texts[#texts + 1] = t end,
  getTile = function() return nil end }
g_things = { getThingType = function() return { getWidth = function() return 1 end, getHeight = function() return 1 end,
  getDisplacementY = function() return 0 end } end }

local root = new('root')
TradeFake.root = root
function root:getX() return 0 end
function root:getY() return 0 end
local map = { getVisibleDimension = function() return { width = 15, height = 11 } end,
  getPaddingRect = function() return { x = 100, y = 50, width = 482, height = 354 } end,
  isKeepAspectRatioEnabled = function() return true end, getCameraPosition = function() return ppos end }
local trade = { isTrading = function() return false end, closeNpcTrade = function() sent[#sent + 1] = { 'closeTrade' } end,
  tryHandleNpcDialogMessage = function() return false end, onNpcPlayerTalk = function() end, onNpcConversationAttempt = function() end,
  endNpcConversation = function() end, closeNpcDialog = function() end, setNpcDialogWindowEnabled = function() end }
local baseHook = trade.tryHandleNpcDialogMessage
local gi = { getRootPanel = function() return root end, getMapPanel = function() return map end,
  talkToNpc = function() end }
local baseTalk = gi.talkToNpc
modules = { game_interface = gi, game_npctrade = trade, game_console = {} }

dofile(here .. 'npctalk_logic.lua')
dofile(here .. 'npctalkview.lua')
local env = setmetatable({ type = function(v) if type(v) == 'table' and v.__userdata then return 'userdata' end return type(v) end },
  { __index = _G })
assert(loadfile(here .. 'npctalk.lua', 't', env))()
env.init()

local win
for _, k in ipairs(root.kids) do if k.id == 'npcTalkWindow' then win = k end end
eq(win ~= nil, true, 'the window is made on the game view'); eq(win.visible, false, 'hidden until a conversation')
eq(trade.tryHandleNpcDialogMessage ~= baseHook, true, 'the console hook is ours'); eq(gi.talkToNpc ~= baseTalk, true, 'Talk is ours')
local function find(id) return win:recursiveGetChildById(id) end

-- Talk: the NPC is two tiles away, in range: "hi" goes out and the window opens
gi.talkToNpc(maelis)
if #warnings > 0 then error(warnings[1]) end
eq(sent[#sent][1], 'say', 'hi is said'); eq(sent[#sent][2], 'hi', 'in the default channel')
eq(win.visible, true, 'the window opens'); eq(find('npcName').text, 'Maelis', 'the NPC name without its title')
eq(find('npcTitle').text, 'Archivist', 'its title'); eq(find('portrait').outfit.type, 130, 'its outfit')
eq(#find('textScroll').kids, 2, 'the log: what the player said, and the waiting note')
eq(find('textScroll').kids[1].text, 'You: hi', 'You: hi')
-- the window is beside the NPC and not over the player or the NPC
local p, w, h = win.position, win.size.width, win.size.height
eq(w, 464, 'the width: the 480 px map less its margins'); eq(h, 340, 'the height: at least the minimum'); eq(p ~= nil, true, 'a place')
local function covers(c) return p.x < c.x + 24 and c.x - 24 < p.x + w and p.y < c.y + 24 and c.y - 40 < p.y + h end
-- the map rect is 480 x 352 at x 101 y 51; the camera tile centre is (341, 227): the NPC two tiles east. The map is too
-- small to hold the window beside the NPC: it goes where the screen has room, over a side panel if need be
eq(covers({ x = 341, y = 227 }), false, 'not over the player'); eq(covers({ x = 405, y = 227 }), false, 'not over the NPC')
-- the NPC answers
local reply = 'Ash on your boots, Ash. I keep the {ledger}. Ask me for {tales}. (Diga {portugues} para conversar em portugues.)'
local handled = trade.tryHandleNpcDialogMessage('Archivist Maelis', nil, MessageModes.NpcFrom, reply)
eq(handled, true, 'the window takes the line (the console leaves it out)')
local log = find('textScroll').kids
eq(#log, 2, 'the log: the player and the NPC'); eq(log[2].style, 'NpcTalkNpcLine', 'the NPC line'); eq(log[1].style, 'NpcTalkPlayerLine', 'the player line')
local chipWords = {}
for _, k in ipairs(find('chips').kids) do if k.word then chipWords[#chipWords + 1] = k.word end end
eq(table.concat(chipWords, ','), 'ledger,tales,portugues', 'the chips of the reply, the pt-BR switch last')
eq(find('status').text, '', 'the hint comes with the tick')
-- a chip says its word
for _, k in ipairs(find('chips').kids) do if k.word == 'portugues' then k.onClick() end end
eq(sent[#sent][1], 'private', 'a keyword goes out as private NPC talk'); eq(sent[#sent][2], 'portugues', 'the word')
eq(find('textScroll').kids[#find('textScroll').kids - 1].text, 'You: portugues', 'and it is in the log')
-- the same line twice (the console hook and the talk signal) is one line
handled = trade.tryHandleNpcDialogMessage('Archivist Maelis', nil, MessageModes.NpcFrom, 'Certo. Vamos falar em {portugues}.')
local lines = #find('textScroll').kids
trade.tryHandleNpcDialogMessage('Archivist Maelis', nil, MessageModes.NpcFrom, 'Certo. Vamos falar em {portugues}.')
eq(#find('textScroll').kids, lines, 'a repeated line within 50 ms is the same line')
-- the player types
find('input').text = 'what is the ledger'
find('sayButton').onClick(); eq(sent[#sent][2], 'what is the ledger', 'the typed text')
-- Enter in the input says it too
find('input').text = 'lore'
keys[find('input')].Enter(); eq(sent[#sent][2], 'lore', 'Enter says the text')
-- the tick: status and range
events.tick()
eq(win.visible, true, 'in range: still open')
MS = MS + 5000
events.tick()
eq(find('status').text, 'No answer yet.', 'no answer for a while: said so')
-- walking away closes it
ppos.x = 1010
events.tick()
eq(win.visible, false, 'out of range: closed'); ppos.x = 1000
-- Talk again, then Bye
MS = MS + 5000
gi.talkToNpc(maelis)
eq(win.visible, true, 'opened again'); eq(win.position ~= nil, true, 'placed again')
find('byeButton').onClick()
eq(sent[#sent][1], 'private', 'bye is private talk'); eq(sent[#sent][2], 'bye', 'bye')
eq(win.visible, false, 'the window closes'); eq(#find('textScroll').kids, 0, 'and its log is emptied')
-- Esc ends a conversation too
MS = MS + 5000
gi.talkToNpc(maelis)
eq(keys[win].Escape(), true, 'Esc is taken while the window is open'); eq(win.visible, false, 'and closes it')
eq(keys[win].Escape(), false, 'Esc with no conversation is left alone')
-- the dialogue off in the options: no window, the talk stays in the console
modules.client_settings = { getOption = function() return true end }
MS = MS + 5000
gi.talkToNpc(maelis)
eq(win.visible, false, 'the option "Disable NPC Dialog Window" keeps the window shut')
eq(trade.tryHandleNpcDialogMessage('Archivist Maelis', nil, MessageModes.NpcFrom, 'Hello {friend}.'), false, 'and the line stays in the console')
modules.client_settings = nil
-- unloading
env.terminate()
eq(trade.tryHandleNpcDialogMessage, baseHook, 'the console hook is the base\'s again'); eq(gi.talkToNpc, baseTalk, 'Talk too')
eq(win.destroyed, true, 'the window is gone')
eq(#warnings, 0, 'nothing was logged: ' .. tostring(warnings[1]))

print(string.format('npctalk_test: %d checks OK', n))
