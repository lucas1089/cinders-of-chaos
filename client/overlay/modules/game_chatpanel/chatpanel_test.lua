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
eq(L.sizeFor({ A = { width = 600, offset = -120.4 } }, 'A').offset, -121, 'old saved offset (whole pixels)')
eq(L.sizeFor({ A = { width = 600, x = 300, offset = 50 } }, 'A').offset, nil, 'x wins over an old offset')
eq(L.sizeFor({ A = { width = 600, x = 300.7 } }, 'A').x, 300, 'saved x')
eq(L.sizeFor({ A = { width = 600 } }, 'A').x, nil, 'no x: centred')
eq(L.sizeFor({ A = { width = 600, lift = 220 } }, 'A').lift, 220, 'saved lift')
eq(L.sizeFor({ A = { width = 600, lift = -5 } }, 'A').lift, 0, 'lift never under the bottom edge')
eq(L.sizeFor(nil, 'A').lift, 0, 'new character on the bottom edge')

-- the group: life orb + chat + mana orb, centred in the window by default
local m = L.orbMargins()
eq(m.left, L.MOVE_GRIP_GAP + L.GRIP + L.ORB_GAP, 'life orb clears the move grip')
eq(m.right, L.WIDTH_GRIP_GAP + L.GRIP + L.ORB_GAP, 'mana orb clears the width grip')
eq(m.bottom, L.ORB_BOTTOM, 'orbs on the bottom edge')
eq(L.orbMargins(200).bottom, L.ORB_BOTTOM + 200, 'orbs follow a lifted chat')
local function place(t)
  return L.layout({ regionLeft = t.rl or 0, regionRight = t.rr or 1920, windowLeft = 0, windowWidth = t.ww or 1920,
    width = t.w or 760, x = t.x, offset = t.off, orbSize = t.orb or 0, keepLeft = t.keep })
end
local function groupOf(p, orb)
  local o = p.orbs and orb or 0
  return p.chatLeft - m.left - o, p.chatLeft + p.chatWidth + m.right + o
end
local p = place({ orb = 150 })
local gl, gr = groupOf(p, 150)
eq(p.chatWidth, 760, 'centred: wanted width')
eq(p.orbs, true, 'orbs fit')
eq(p.x, nil, 'centred by default')
eq(p.chatLeft, p.centredLeft, 'centred place reported')
eq(math.abs((gl + gr) - 1920) <= 1, true, 'group centred in the window')
eq(p.chatLeft - 0 >= m.left + 150, true, 'room for the life orb on the left')
p = place({ orb = 150, ww = 2560, rr = 2560 })
gl, gr = groupOf(p, 150)
eq(math.abs((gl + gr) - 2560) <= 1, true, 're-centres on a wider window')
-- placed by the player: kept as the chat's left edge, clamped to the region
p = place({ orb = 150, x = 900 })
eq(p.chatLeft, 900, 'x is the left edge')
eq(p.x, 900, 'x kept')
p = place({ orb = 150, x = 5000 })
gl, gr = groupOf(p, 150)
eq(gr, 1920, 'clamped at the right edge (mana orb inside the window)')
eq(p.x < 5000, true, 'the stored x is the clamped one')
p = place({ orb = 150, x = -5000, rl = 300 })
gl = groupOf(p, 150)
eq(gl, 300, 'clamped at the left panels (life orb inside the region)')
-- an old saved offset becomes x
p = place({ orb = 150, off = 200 })
eq(p.x ~= nil, true, 'old offset turns into x')
eq(p.chatLeft, place({ orb = 150 }).chatLeft + 200, 'old offset: moved right from the centre')
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
p = place({ orb = 76, x = 400 })
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

-- the width grip (owner video 2026-11-02: dragging it right made the chat grow to the left): the left edge stays,
-- the right edge follows the mouse
for _, case in ipairs({ { x = 300, orb = 150 }, { x = 900, orb = 150 }, { x = 200, orb = 0 } }) do
  local before = place({ w = 600, x = case.x, orb = case.orb })
  for _, mouse in ipairs({ before.chatLeft + 700, before.chatLeft + 900, before.chatLeft + 500 }) do
    local w = L.widthForGrip(mouse, before.chatLeft)
    local after = place({ w = w, x = before.x, orb = case.orb, keep = true })
    eq(after.chatLeft, before.chatLeft, 'resize keeps the left edge (x ' .. case.x .. ', mouse ' .. mouse .. ')')
    local gripX = after.chatLeft + after.chatWidth + L.WIDTH_GRIP_GAP + L.GRIP / 2
    local orbRoom = 1920 - (after.chatLeft + after.chatWidth + m.right + (after.orbs and case.orb or 0))
    eq(math.abs(gripX - mouse) <= 1 or orbRoom == 0, true, 'grip under the mouse or at the screen edge')
  end
end
-- dragged far past the right edge: the chat stops at the screen edge, its left edge does not move
do
  local before = place({ w = 600, x = 900, orb = 150 })
  local after = place({ w = L.widthForGrip(5000, before.chatLeft), x = before.x, orb = 150, keep = true })
  eq(after.chatLeft, 900, 'past the screen edge: left edge stays')
  local _, right = groupOf(after, 150)
  eq(right, 1920, 'past the screen edge: the mana orb ends on the edge')
  -- without keepLeft (a window resize) the same width would push the group left: the old behaviour
  local pushed = place({ w = L.widthForGrip(5000, before.chatLeft), x = before.x, orb = 150 })
  eq(pushed.chatLeft < 900, true, 'only a resize drag keeps the left edge')
end
-- a chat that sits at the right edge and is narrower than the minimum room there keeps its minimum width
do
  local before = place({ w = 420, x = 5000, orb = 150 })
  local after = place({ w = 100, x = before.x, orb = 150, keep = true })
  eq(after.chatWidth, L.MIN_WIDTH, 'resize never under the minimum')
end

-- moving: anywhere on the screen, the group stays on it
local sx, slift = L.dragPlace({ x = 500, lift = 0, mouseX = 600, mouseY = 900 }, 700, 600)
eq(sx, 600, 'move: x follows the mouse')
eq(slift, 300, 'move: dragging up lifts the chat')
sx, slift = L.dragPlace({ x = 500, lift = 100, mouseX = 600, mouseY = 900 }, 600, 1200)
eq(slift, 0, 'move: never under the bottom edge')
eq(L.groupHeight(200, 0), 200 + L.SPLITTER + L.HANDLE_HEIGHT, 'group height: chat, splitter, handle')
eq(L.groupHeight(50, 150), 150 + L.ORB_BOTTOM, 'group height: an orb taller than a small chat')
eq(L.clampLift(5000, 300, 1080), 780, 'lift keeps the group on the screen')
eq(L.clampLift(-20, 300, 1080), 0, 'lift not under the bottom edge')
eq(L.clampLift(400, 1200, 1080), 0, 'a group taller than the window stays on the bottom edge')
-- the end of a move snaps back to the centre and the bottom edge when close
local centredLeft = place({ orb = 150 }).chatLeft
local near = place({ orb = 150, x = centredLeft + 6 })
local x, lift = L.snapPlace(near, 5)
eq(x, nil, 'snap: back to centred')
eq(lift, 0, 'snap: back on the bottom edge')
local far = place({ orb = 150, x = centredLeft + 200 })
x, lift = L.snapPlace(far, 300)
eq(x, centredLeft + 200, 'no snap far from the centre')
eq(lift, 300, 'no snap far from the bottom edge')

-- O558: the grips and the handle belong to the classic layout on a computer only
eq(L.gripsShown(false, false), true, 'classic on a computer: grips')
eq(L.gripsShown(true, false), false, 'action bar layout: no grips (the handle floated at the bottom-left)')
eq(L.gripsShown(false, true), false, 'phone: no grips')
eq(L.gripsShown(nil, nil), true, 'unknown mode reads classic')
eq(L.HANDLE_WIDTH, 64, 'handle art width')

if fails > 0 then os.exit(1) end
print('chatpanel tests OK')
