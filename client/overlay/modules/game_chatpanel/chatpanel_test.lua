-- luajit chatpanel_test.lua && lua5.3 chatpanel_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'chatpanel_logic.lua')
local L = ChaosChatLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- Enter / Shift+Enter
eq(L.enterAction({ text = '', temporary = true }), 'close', 'empty Chat On* closes')
eq(L.enterAction({ text = '', persistent = true }), 'close', 'empty Chat On closes')
eq(L.enterAction({ text = '   ', persistent = true }), 'close', 'spaces count as empty')
eq(L.enterAction({ text = 'hi', temporary = true }), 'send_close', 'Chat On* sends then closes')
eq(L.enterAction({ text = 'hi', persistent = true }), 'send', 'Chat On sends and stays')
eq(L.enterAction({ text = 'hi', persistent = true, temporary = true }), 'send', 'persistent wins')
eq(L.enterAction({ text = '' }), 'none', 'chat not open')
eq(L.enterAction(nil), 'none', 'no state')

-- width: the default on a big window, the room on a small one, never under the minimum otherwise
eq(L.clampWidth(nil, 1700), L.DEFAULT_WIDTH, 'default width')
eq(L.clampWidth(5000, 1700), 1700, 'not wider than the room')
eq(L.clampWidth(100, 1700), L.MIN_WIDTH, 'minimum width')
eq(L.clampWidth(760, 500), 500, 'small window')
eq(L.clampWidth(760, 300), 300, 'tiny window: the room wins over the minimum')
eq(L.marginRightFor(760, 1700, 1), 1 + 940, 'margin leaves the width')
eq(L.marginRightFor(760, 600, 1), 1, 'no margin when it does not fit')

-- height: the splitter minimum, a share of the window at most
eq(L.clampHeight(nil, 150, 1340), 150 + L.DEFAULT_EXTRA_HEIGHT, 'new character: minimum + a few lines')
eq(L.clampHeight(100, 150, 1340), 150, 'not under the minimum')
eq(L.clampHeight(2000, 150, 1340), math.floor(1340 * L.MAX_HEIGHT_SHARE), 'not over the share')
eq(L.clampHeight(400, 150, 200), 150, 'a tiny window keeps the minimum')

-- saved sizes per character
local saved = { Alice = { width = 600, height = 180 } }
eq(L.sizeFor(saved, 'Alice').width, 600, 'saved width')
eq(L.sizeFor(saved, 'Alice').height, 180, 'saved height')
eq(L.sizeFor(saved, 'Bob').width, L.DEFAULT_WIDTH, 'new character width')
eq(L.sizeFor(saved, 'Bob').height, nil, 'new character height: default')
eq(L.sizeFor(nil, 'Bob').width, L.DEFAULT_WIDTH, 'nothing saved')

-- saved place
eq(L.sizeFor({ A = { width = 600, offset = -120.4 } }, 'A').offset, -121, 'saved offset (whole pixels)')
eq(L.sizeFor({ A = { width = 600 } }, 'A').offset, nil, 'no offset: centred')

-- the group: life orb + chat + mana orb, centred in the window by default
local m = L.orbMargins()
eq(m.left, L.MOVE_GRIP_GAP + L.GRIP + L.ORB_GAP, 'life orb clears the move grip')
eq(m.right, L.WIDTH_GRIP_GAP + L.GRIP + L.ORB_GAP, 'mana orb clears the width grip')
local function place(t)
  return L.layout({ regionLeft = t.rl or 0, regionRight = t.rr or 1920, windowLeft = 0, windowWidth = t.ww or 1920,
    width = t.w or 760, offset = t.off, orbSize = t.orb or 0 })
end
local function groupOf(p, orb)
  local o = p.orbs and orb or 0
  return p.chatLeft - m.left - o, p.chatLeft + p.chatWidth + m.right + o
end
local p = place({ orb = 150 })
local gl, gr = groupOf(p, 150)
eq(p.chatWidth, 760, 'centred: wanted width')
eq(p.orbs, true, 'orbs fit')
eq(p.offset, nil, 'centred by default')
eq(math.abs((gl + gr) - 1920) <= 1, true, 'group centred in the window')
-- the chat's own centre is shifted by the uneven grips only, never by the orbs (they are the same size)
eq(p.chatLeft - 0 >= m.left + 150, true, 'room for the life orb on the left')
p = place({ orb = 150, ww = 2560, rr = 2560 })
gl, gr = groupOf(p, 150)
eq(math.abs((gl + gr) - 2560) <= 1, true, 're-centres on a wider window')
-- moved by the player, kept as an offset from the centre, clamped to the region
p = place({ orb = 150, off = 200 })
eq(p.offset, 200, 'offset kept')
gl, gr = groupOf(p, 150)
eq(math.abs((gl + gr) - 1920 - 400) <= 1, true, 'group moved right by the offset')
p = place({ orb = 150, off = 5000 })
gl, gr = groupOf(p, 150)
eq(gr, 1920, 'clamped at the right edge (mana orb inside the window)')
eq(p.offset < 5000, true, 'the stored offset is the clamped one')
p = place({ orb = 150, off = -5000, rl = 300 })
gl = groupOf(p, 150)
eq(gl, 300, 'clamped at the left panels (life orb inside the region)')
eq(place({ orb = 150, off = 6 }).offset, nil, 'a drag ending near the centre snaps back to centred')
eq(place({ orb = 150, off = -8 }).offset, nil, 'snap both ways')
-- small windows: the orbs give way before the chat goes under its minimum; the chat then takes the room
p = place({ orb = 190, rr = 820, ww = 820 })
eq(p.orbs, false, 'orbs left out on a narrow window')
eq(p.chatWidth, 760, 'without the orbs the chat keeps its width')
p = place({ orb = 190, rr = 700, ww = 700 })
eq(p.chatWidth, 700 - m.left - m.right, 'a tiny window: the chat takes the room left')
p = place({ orb = 0 })
eq(p.orbs, false, 'orbs off')
gl, gr = groupOf(p, 0)
eq(math.abs((gl + gr) - 1920) <= 1, true, 'without orbs the chat with its grips is centred')
-- nothing overlaps: life orb | move grip | chat | width grip | mana orb
p = place({ orb = 76, off = -300 })
local lifeRight = p.chatLeft - m.left
local moveGripLeft = p.chatLeft - L.MOVE_GRIP_GAP - L.GRIP
eq(lifeRight + L.ORB_GAP, moveGripLeft, 'life orb ends ORB_GAP before the move grip')
local widthGripRight = p.chatLeft + p.chatWidth + L.WIDTH_GRIP_GAP + L.GRIP
local manaLeft = p.chatLeft + p.chatWidth + m.right
eq(widthGripRight + L.ORB_GAP, manaLeft, 'mana orb starts ORB_GAP after the width grip')
-- splitter margins
local ml, mr = L.splitterMargins({ chatLeft = 500, chatWidth = 760 }, 100, 1800)
eq(ml, 400, 'left margin from the left panels')
eq(mr, 540, 'right margin from the right panels')
-- dragging
eq(L.dragOffset(nil, 400, 460), 60, 'move: mouse travel from centred')
eq(L.dragOffset(-50, 400, 380), -70, 'move: adds to the offset')
for _, case in ipairs({ { off = nil, orb = 150 }, { off = 120, orb = 150 }, { off = -80, orb = 0 } }) do
  local w = 900
  local q = place({ w = w, off = case.off, orb = case.orb })
  local gripX = q.chatLeft + q.chatWidth + L.WIDTH_GRIP_GAP + L.GRIP / 2
  eq(math.abs(L.widthForGrip(gripX, 0, 1920, case.off, q.orbs and case.orb or 0) - w) <= 1, true,
     'width grip under the mouse gives the width back (offset ' .. tostring(case.off) .. ')')
end

if fails > 0 then os.exit(1) end
print('chatpanel tests OK')
