-- luajit floatchat_test.lua && lua5.3 floatchat_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'floatchat_logic.lua')
dofile(dir .. '../client_chaos_settings/settingslist.lua')
local L = FloatChatLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- opacity: 40..100, body alpha about 75% by default
eq(L.clampOpacity(10), 40, 'opacity floor')
eq(L.clampOpacity(300), 100, 'opacity cap')
eq(L.clampOpacity(nil), 75, 'opacity default')
eq(L.clampOpacity('60'), 60, 'opacity from a string')
eq(L.bodyAlpha(75), 191, 'alpha of 75%')
eq(L.bodyAlpha(100), 255, 'alpha of 100%')
eq(L.bodyAlpha(0), 102, 'alpha floor is 40%')

-- clamp: size limits, whole rect on screen
local area = { x = 0, y = 0, width = 1000, height = 600 }
local r = L.clampRect({ x = -50, y = -50, width = 50, height = 50 }, area)
eq(r.x, 0, 'x on screen'); eq(r.y, 0, 'y on screen'); eq(r.width, L.MIN_W, 'min width'); eq(r.height, L.MIN_H, 'min height')
r = L.clampRect({ x = 900, y = 590, width = 380, height = 150 }, area)
eq(r.x + r.width, 1000, 'right edge kept'); eq(r.y + r.height, 600, 'bottom edge kept')
r = L.clampRect({ x = 0, y = 0, width = 5000, height = 5000 }, area)
eq(r.width, 600, 'max width is 60% of the window'); eq(r.height, 360, 'max height is 60%')
r = L.clampRect({ x = 0, y = 0, width = 380, height = 150 }, { x = 0, y = 0, width = 200, height = 80 })
eq(r.width, 200, 'never wider than a tiny area'); eq(r.height, 80, 'never taller than a tiny area')

-- default place: bottom-left; above the bar when it would sit on it
r = L.defaultRect(area, nil)
eq(r.x, 8, 'default x'); eq(r.y, 600 - 150 - 8, 'default y'); eq(r.width, 380, 'default width')
local bar = { x = 100, y = 480, width = 800, height = 110 }
r = L.defaultRect(area, bar)
eq(r.y + r.height + L.BAR_GAP, 480, 'default place sits above the bar')
local farBar = { x = 600, y = 480, width = 300, height = 110 }
eq(L.defaultRect(area, farBar).y, 442, 'a bar beside it changes nothing')
-- saved place wins, clamped
local s = L.settingsFor({ A = { x = 5000, y = 5000, width = 380, height = 150 } }, 'A')
r = L.place(s, area, bar)
eq(r.x + r.width, 1000, 'saved place clamped to the window')
eq(L.place(L.settingsFor(nil, 'A'), area, bar).y + 150 + 6, 480, 'no saved place: default')

-- drag and resize
local start = { x = 100, y = 300, width = 380, height = 150, mouseX = 120, mouseY = 310 }
r = L.moveBy(start, 220, 260, area)
eq(r.x, 200, 'move x'); eq(r.y, 250, 'move y')
-- all the way left: the wide area starts at the screen edge (x = 0), the map's area at the left panels' edge (180)
r = L.moveBy(start, -900, 310, area)
eq(r.x, 0, 'dragged far left: the screen edge')
r = L.moveBy(start, -900, 310, { x = 180, y = 0, width = 820, height = 600 })
eq(r.x, 180, 'a narrower area keeps the chat right of it')
eq(L.place(L.settingsFor({ A = { x = 0, y = 300, width = 380, height = 150 } }, 'A'), area, nil).x, 0, 'a saved x of 0 stays 0')
r = L.resizeBy(start, 220, 410, area)
eq(r.width, 480, 'resize width'); eq(r.height, 250, 'resize height')
r = L.resizeBy(start, -400, -400, area)
eq(r.width, L.MIN_W, 'resize stops at the minimum')

-- hide / show state machine
local st = L.new(false, 0)
st = L.step(st, 'toggle', nil, 10)
eq(st.hidden, true, 'toggle hides')
st = L.step(st, 'message', nil, 20)
st = L.step(st, 'message', nil, 30)
eq(st.unread, 2, 'unread counts while hidden')
eq(L.badge(st.unread), '2', 'badge text')
st = L.step(st, 'toggle', nil, 40)
eq(st.hidden, false, 'toggle shows'); eq(st.unread, 0, 'showing clears unread')
st = L.step(st, 'message', nil, 50)
eq(st.unread, 0, 'no unread while shown'); eq(st.activity, 50, 'activity follows a message')
-- Enter shows a hidden chat and hides it again after sending
st = L.step(L.new(true, 0), 'typing_on', {}, 100)
eq(st.hidden, false, 'Enter shows the hidden chat'); eq(st.peek, true, 'it was peeked'); eq(st.typing, true, 'typing')
st = L.step(st, 'typing_off', {}, 200)
eq(st.hidden, true, 'sent: hidden again'); eq(st.peek, false, 'no peek left')
-- option off: stays shown
st = L.step(L.new(true, 0), 'typing_on', { hideOnSend = false }, 100)
st = L.step(st, 'typing_off', { hideOnSend = false }, 200)
eq(st.hidden, false, 'hideOnSend off keeps it shown')
-- a chat shown by the player stays shown after typing
st = L.step(L.new(false, 0), 'typing_on', {}, 100)
st = L.step(st, 'typing_off', {}, 200)
eq(st.hidden, false, 'a shown chat stays shown')
-- toggling during the peek makes it a normal show (it stays after the line)
st = L.step(L.new(true, 0), 'typing_on', {}, 100)
st = L.step(st, 'show', {}, 110)
st = L.step(st, 'typing_off', {}, 200)
eq(st.hidden, false, 'shown by the button while typing stays shown')
-- showOnType off: Enter does not show it
st = L.step(L.new(true, 0), 'typing_on', { showOnType = false }, 100)
eq(st.hidden, true, 'showOnType off: still hidden')
-- the unread count caps
st = L.new(true, 0)
for _ = 1, 150 do st = L.step(st, 'message', nil, 1) end
eq(st.unread, 99, 'unread cap'); eq(L.badge(st.unread), '99', 'badge at the cap')
eq(L.badge(120), '99+', 'badge past the cap'); eq(L.badge(0), '', 'no badge at 0')
eq(L.step(st, 'hide', nil, 2).hidden, true, 'hide stays hidden')

-- fade: off by default, floor after the idle time, hover and typing bring it back
local o = { fade = true, fadeSeconds = 8, activity = 0, now = 5000 }
eq(L.fadedOpacity(75, o), 75, 'before the idle time')
o.now = 8000 + 300
eq(L.fadedOpacity(75, o) < 75, true, 'fading')
eq(L.fadedOpacity(75, o) > 40, true, 'fading, not at the floor yet')
o.now = 20000
eq(L.fadedOpacity(75, o), 40, 'at the floor')
o.hovered = true
eq(L.fadedOpacity(75, o), 75, 'hover brings it back')
o.hovered, o.typing = false, true
eq(L.fadedOpacity(75, o), 75, 'typing brings it back')
o.typing = false
o.fade = false
eq(L.fadedOpacity(75, o), 75, 'fade off')
eq(L.fadedOpacity(40, { fade = true, activity = 0, now = 99999 }), 40, 'already at the floor')
eq(L.clampFadeSeconds(1), 3, 'fade seconds floor'); eq(L.clampFadeSeconds(500), 60, 'fade seconds cap')

-- menus
eq(L.classify('Default', nil), 'channel', 'Default is a channel')
eq(L.classify('Loot', nil), 'channel', 'Loot is a channel')
eq(L.classify('Trade', 5), 'channel', 'a channel id')
eq(L.classify('Vexa', nil), 'private', 'a player name is private')
local menus = L.menus({ { name = 'Default', unread = 0, current = true }, { name = 'Trade', channelId = 5, unread = 3 },
                        { name = 'Vexa', unread = 2 }, { name = 'Mira', unread = 1 }, { bad = true } })
eq(#menus.channels, 2, 'two channels'); eq(#menus.private, 2, 'two private chats')
eq(menus.channelsUnread, 3, 'channel unread'); eq(menus.privateUnread, 3, 'private unread')
eq(menus.channels[1].current, true, 'current tab flagged')
eq(#L.menus(nil).channels, 0, 'no tabs')

-- settings: defaults, clamps, g_settings round trip
local d = L.settingsFor(nil, 'A')
eq(d.hidden, false, 'default shown'); eq(d.opacity, 75, 'default opacity'); eq(d.fade, false, 'fade off by default')
eq(d.hideOnSend, true, 'hide after sending on by default'); eq(d.x, nil, 'no place yet'); eq(d.width, 380, 'default width')
local node = L.store(nil, 'A', { x = 20, y = 300, width = 400, height = 160, hidden = true, opacity = 55, fade = true,
                                  fadeSeconds = 12, hideOnSend = false })
local back = L.settingsFor(ChaosSettings.roundTrip(node), 'A')
eq(back.x, 20, 'x kept'); eq(back.y, 300, 'y kept'); eq(back.width, 400, 'width kept'); eq(back.hidden, true, 'hidden kept')
eq(back.opacity, 55, 'opacity kept'); eq(back.fade, true, 'fade kept'); eq(back.fadeSeconds, 12, 'fade seconds kept')
eq(back.hideOnSend, false, 'hideOnSend kept')
eq(L.settingsFor(ChaosSettings.roundTrip(node), 'B').hidden, false, 'another character is untouched')
eq(L.settingsFor({ A = { opacity = 5, width = 5, height = 5 } }, 'A').opacity, 40, 'saved opacity clamped')
eq(L.settingsFor({ A = { width = 5 } }, 'A').width, L.MIN_W, 'saved width clamped')
eq(L.settingsFor({ A = { x = 5 } }, 'A').y, nil, 'a place needs x and y')

-- drag state machine (O498): ends on any release, on a move with the button up, on focus loss, hide and logout;
-- a press on a button or a tab never begins a window drag
local rect = { x = 100, y = 200, width = 380, height = 150 }
local big = { x = 0, y = 0, width = 1000, height = 600 }
local d = L.dragNew()
eq(d.active, false, 'no drag at first')
d = L.dragPress(d, 'header', true, rect, 150, 210)
eq(d.active, true, 'a header press begins a move'); eq(d.kind, 'move', 'header drags move')
local d2, r2, ended = L.dragMove(d, 170, 230, big, { leftDown = true, focused = true })
eq(d2.active, true, 'still dragging while the button is down'); eq(r2.x, 120, 'moved 20 right'); eq(r2.y, 220, 'moved 20 down')
eq(ended, false, 'a plain move does not end it')
local d3, was, moved = L.dragEnd(d2)
eq(d3.active, false, 'release ends the drag'); eq(was, true, 'release reports an active drag'); eq(moved, true, 'and that it moved')
local _, was2, moved2 = L.dragEnd(L.dragNew())
eq(was2, false, 'release without a drag: nothing'); eq(moved2, false, 'release without a drag: not moved')
local _, was3, moved3 = L.dragEnd(d)
eq(was3, true, 'release of a click is a drag end'); eq(moved3, false, 'a click without a move is not saved')

-- the grip resizes
local g = L.dragPress(L.dragNew(), 'grip', true, rect, 400, 340)
eq(g.kind, 'resize', 'grip drags resize')
local _, gr = L.dragMove(g, 440, 360, big, { leftDown = true })
eq(gr.width, 420, 'grew 40 wide'); eq(gr.height, 170, 'grew 20 tall')

-- a press that cannot begin a drag
eq(L.dragPress(L.dragNew(), 'button', true, rect, 1, 1).active, false, 'a press on a header button never drags')
eq(L.dragPress(L.dragNew(), 'tab', true, rect, 1, 1).active, false, 'a press on a tab never drags')
eq(L.dragPress(L.dragNew(), 'header', false, rect, 1, 1).active, false, 'only the left button drags')
eq(L.dragPress(d, 'button', true, rect, 1, 1).active, false, 'a press on a button also drops a stale drag')
eq(L.dragPress(d, 'header', false, rect, 1, 1).active, false, 'a right press drops a stale drag')
eq(L.dragTarget('header', 'UIButton'), 'button', 'a UIButton under the header is a button')
eq(L.dragTarget('header', 'UIWidget'), 'header', 'a plain widget is the header')
eq(L.dragTarget('header', nil), 'header', 'an unknown class is the header')
eq(L.dragTarget('grip', 'UIWidget'), 'grip', 'the grip stays the grip')

-- the stuck case of the owner report: press on the header, the release never reaches us; the next move has the button up
local stuck, sr, send = L.dragMove(d, 400, 400, big, { leftDown = false, focused = true })
eq(stuck.active, false, 'a move with the button up ends the drag'); eq(sr, nil, 'and moves nothing'); eq(send, true, 'and says it ended')
local fl = L.dragMove(d, 400, 400, big, { leftDown = true, focused = false })
eq(fl.active, false, 'focus loss ends the drag')
local hd = L.dragMove(d, 400, 400, big, { leftDown = true, focused = true, hidden = true })
eq(hd.active, false, 'hiding ends the drag')
local idle, ir, iend = L.dragMove(L.dragNew(), 5, 5, big, { leftDown = false })
eq(idle.active, false, 'a move without a drag stays idle'); eq(ir, nil, 'a move without a drag moves nothing'); eq(iend, false, 'and ends nothing')
eq(L.dragStale(d, { leftDown = false }), true, 'poll: button up is stale')
eq(L.dragStale(d, { leftDown = true, focused = false }), true, 'poll: window out of focus is stale')
eq(L.dragStale(d, { leftDown = true, focused = true }), false, 'poll: a live drag is not stale')
eq(L.dragStale(L.dragNew(), { leftDown = false }), false, 'poll: no drag is never stale')
eq(L.dragStale(nil, nil), false, 'poll: nil state')
local nd = L.dragMove(nil, 1, 1, big, {})
eq(nd.active, false, 'nil state in a move')
eq(L.dragEnd(nil).active, false, 'nil state in an end')

-- a click in the window with the chat input on gives the keys back to it
eq(L.refocusAfterClick(true, false, true, true), true, 'release over the window, input on: refocus')
eq(L.refocusAfterClick(true, false, true, false), false, 'input off: nothing to focus')
eq(L.refocusAfterClick(true, false, false, true), false, 'release elsewhere: not ours')
eq(L.refocusAfterClick(false, false, true, true), false, 'no click: nothing')
eq(L.refocusAfterClick(true, true, true, true), false, 'button still down')

if fails == 0 then print('floatchat_test: ok') end
os.exit(fails == 0 and 0 or 1)
