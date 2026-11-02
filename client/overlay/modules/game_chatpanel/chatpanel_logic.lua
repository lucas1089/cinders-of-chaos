-- Pure rules of the chat panel (client/MANIFEST.md "Chat panel"; tested by chatpanel_test.lua). Global
-- ChaosChatLogic: modules/game_console reads enterAction (base patch 0056), chatpanel.lua the size rules.
ChaosChatLogic = {}
local L = ChaosChatLogic

-- the bottom area (action bars + console): width in pixels. It is centred in the game window with the orbs beside it
-- by default; the player can move it anywhere in the game area (L.layout, L.clampLift below)
L.DEFAULT_WIDTH = 760 -- about 20 action bar slots of 36 px
L.MIN_WIDTH = 420
-- extra height over the splitter's minimum for a new player: about five chat lines
L.DEFAULT_EXTRA_HEIGHT = 40
-- the bottom area never takes more than this share of the game window
L.MAX_HEIGHT_SHARE = 0.55

-- What Enter (or Shift+Enter) does in the chat. state:
--   text        the input line
--   persistent  "Chat On" (the chat stays open after a line)
--   temporary   "Chat On*" (Enter opened it; it closes after one line)
-- 'close'      empty input (spaces count as empty): leave the chat, walk again
-- 'send'       send, keep the chat open ("Chat On")
-- 'send_close' send, then close ("Chat On*")
-- 'none'       the chat is not open
function L.enterAction(state)
  state = state or {}
  local open = state.persistent == true or state.temporary == true
  if not open then return 'none' end
  local text = tostring(state.text or '')
  if not text:find('%S') then return 'close' end
  return state.persistent and 'send' or 'send_close'
end

-- width of the bottom area for a wanted width and the room there is (the room wins on a small window)
function L.clampWidth(width, available)
  available = math.max(0, math.floor(tonumber(available) or 0))
  width = math.floor(tonumber(width) or L.DEFAULT_WIDTH)
  return math.min(available, math.max(L.MIN_WIDTH, width))
end

-- the bottom splitter's right margin that leaves `width` of `available` (baseMargin: the style's own margin)
function L.marginRightFor(width, available, baseMargin)
  baseMargin = tonumber(baseMargin) or 0
  return baseMargin + math.max(0, math.floor((tonumber(available) or 0) - L.clampWidth(width, available)))
end

-- height (the splitter's bottom margin) for a wanted height: at least the minimum the action bars and the
-- console need, at most MAX_HEIGHT_SHARE of the window (but never under the minimum)
function L.clampHeight(height, minimum, windowHeight)
  minimum = math.floor(tonumber(minimum) or 0)
  local maximum = math.max(minimum, math.floor((tonumber(windowHeight) or 0) * L.MAX_HEIGHT_SHARE))
  height = math.floor(tonumber(height) or (minimum + L.DEFAULT_EXTRA_HEIGHT))
  return math.max(minimum, math.min(maximum, height))
end

-- the saved size and place of one character, or the defaults for a new one.
--   x       pixels from the game window's left edge to the chat's left edge (nil: centred, the default)
--   lift    pixels between the window's bottom edge and the group's bottom (0: on the bottom edge)
--   offset  the old place (pixels from the centred place, before x); layout turns it into x once
function L.sizeFor(saved, name)
  local entry = type(saved) == 'table' and name and saved[name] or nil
  if type(entry) ~= 'table' then return { width = L.DEFAULT_WIDTH, lift = 0 } end
  local x, offset = tonumber(entry.x), tonumber(entry.offset)
  return { width = tonumber(entry.width) or L.DEFAULT_WIDTH, height = tonumber(entry.height),
           x = x and math.floor(x) or nil, offset = (not x and offset) and math.floor(offset) or nil,
           lift = math.max(0, math.floor(tonumber(entry.lift) or 0)) }
end

-- ------------------------------------------------------------------ the group: life orb, chat panel, mana orb
-- Left to right: life orb | ORB_GAP | move grip | MOVE_GRIP_GAP | chat (action bars + console) | WIDTH_GRIP_GAP |
-- width grip | ORB_GAP | mana orb. The orbs are anchored to the chat's edges (game_shaderfx reads orbMargins), so
-- they follow it; nothing of the group overlaps. Above the chat's top-left corner: the move handle (its title).
L.GRIP = 6            -- width of both grips
L.MOVE_GRIP_GAP = 2   -- move grip <-> chat's left edge
L.WIDTH_GRIP_GAP = 13 -- chat's right edge <-> width grip (past the action bar's lock column)
L.ORB_GAP = 4         -- grip <-> orb
L.ORB_BOTTOM = 4      -- orbs over the group's bottom edge (the chat reaches it)
L.SNAP = 8            -- a move that ends this close to the centre (or the bottom edge) snaps back there
L.SPLITTER = 6        -- the height splitter above the action bars (bottomSplitter)
L.HANDLE_HEIGHT = 14  -- the move handle above the splitter

-- margins of the orbs from the chat panel (bottomSplitter) edges: life orb's right margin from its left edge, mana
-- orb's left margin from its right edge, and the bottom margin of both (lift: the group's distance from the bottom)
function L.orbMargins(lift)
  return { left = L.MOVE_GRIP_GAP + L.GRIP + L.ORB_GAP, right = L.WIDTH_GRIP_GAP + L.GRIP + L.ORB_GAP,
           bottom = L.ORB_BOTTOM + math.max(0, math.floor(tonumber(lift) or 0)) }
end

local function extras(orbSize)
  local m = L.orbMargins()
  local o = math.max(0, math.floor(tonumber(orbSize) or 0))
  return m.left + o, m.right + o
end

-- Place the group sideways. p:
--   regionLeft, regionRight  x range the group may use (the game area between the side panels)
--   windowLeft, windowWidth  the game window (the default place centres on it)
--   width                    the wanted chat width
--   x                        the chat's left edge from windowLeft; nil = centred
--   offset                   the old saved place (pixels from the centred place), used when x is nil
--   orbSize                  size of the orbs, 0 / nil without orbs
--   keepLeft                 the width grip is dragged: the chat's left edge stays where it is and only the width
--                            changes (a wider chat than the room to the right is cut, never pushed left)
-- Returns { chatLeft, chatWidth, x (clamped; nil when centred), centredLeft (the chat's left edge when centred),
-- orbs (true when the orbs fit beside the chat) }. The group stays inside the region; orbs that leave less than
-- MIN_WIDTH for the chat are left out (hidden).
function L.layout(p)
  local left = math.floor(tonumber(p.regionLeft) or 0)
  local right = math.max(left, math.floor(tonumber(p.regionRight) or left))
  local room = right - left
  local orbSize = math.max(0, math.floor(tonumber(p.orbSize) or 0))
  local orbs = orbSize > 0
  local exL, exR = extras(orbs and orbSize or 0)
  if orbs and room - exL - exR < L.MIN_WIDTH then
    orbs = false
    exL, exR = extras(0)
  end
  local maxWidth = math.max(0, room - exL - exR)
  local chatWidth = L.clampWidth(p.width, maxWidth)
  local windowLeft = math.floor(tonumber(p.windowLeft) or left)
  local windowWidth = math.floor(tonumber(p.windowWidth) or room)
  local centred = windowLeft + math.floor((windowWidth - (exL + chatWidth + exR)) / 2)
  local x = tonumber(p.x)
  local groupLeft
  if x then
    groupLeft = windowLeft + math.floor(x) - exL
  elseif tonumber(p.offset) then
    groupLeft = centred + math.floor(tonumber(p.offset))
    x = 0 -- placed by the player: kept as x from now on
  else
    groupLeft = centred
  end
  if p.keepLeft then
    groupLeft = math.max(left, groupLeft)
    local fits = math.max(0, right - groupLeft - exL - exR)
    chatWidth = math.max(math.min(L.MIN_WIDTH, maxWidth), L.clampWidth(p.width, fits))
  end
  local group = exL + chatWidth + exR
  groupLeft = math.max(left, math.min(right - group, groupLeft))
  local chatLeft = groupLeft + exL
  return { chatLeft = chatLeft, chatWidth = chatWidth, x = x and (chatLeft - windowLeft) or nil,
           centredLeft = centred + exL, orbs = orbs }
end

-- Height of the group over its bottom edge: the splitter and the chat, or an orb when that is taller.
-- chatHeight: the splitter's bottom margin without the lift (action bars + console)
function L.groupHeight(chatHeight, orbSize)
  local o = math.max(0, math.floor(tonumber(orbSize) or 0))
  local chat = math.floor(tonumber(chatHeight) or 0) + L.SPLITTER + L.HANDLE_HEIGHT
  return math.max(chat, o > 0 and (o + L.ORB_BOTTOM) or 0)
end

-- the lift (pixels over the window's bottom edge) that keeps the whole group on the screen
function L.clampLift(lift, groupHeight, windowHeight)
  local maximum = math.max(0, math.floor((tonumber(windowHeight) or 0) - (tonumber(groupHeight) or 0)))
  return math.max(0, math.min(maximum, math.floor(tonumber(lift) or 0)))
end

-- the splitter's margins for a layout. anchorLeft / anchorRight: x of the splitter's anchor lines (the left panels'
-- right edge, the right panels' left edge)
function L.splitterMargins(place, anchorLeft, anchorRight)
  return math.max(0, place.chatLeft - math.floor(anchorLeft)),
         math.max(0, math.floor(anchorRight) - (place.chatLeft + place.chatWidth))
end

-- the chat width that puts the width grip under the mouse: the left edge stays, the right edge follows the mouse
function L.widthForGrip(mouseX, chatLeft)
  local chatRight = (tonumber(mouseX) or 0) - L.WIDTH_GRIP_GAP - L.GRIP / 2
  return math.floor(chatRight - (tonumber(chatLeft) or 0) + 0.5)
end

-- the place while the group is dragged by its handle or its left grip: the place at the press plus the mouse travel
-- (start = { x, lift, mouseX, mouseY }); layout and clampLift keep it on the screen
function L.dragPlace(start, mouseX, mouseY)
  local dx = math.floor((tonumber(mouseX) or 0) - (tonumber(start.mouseX) or 0))
  local dy = math.floor((tonumber(mouseY) or 0) - (tonumber(start.mouseY) or 0))
  return (tonumber(start.x) or 0) + dx, math.max(0, (tonumber(start.lift) or 0) - dy)
end

-- at the end of a move: back to "centred" when the chat ends within SNAP of the centre, back on the bottom edge
-- when the lift is within SNAP of it. Returns x (nil: centred), lift
function L.snapPlace(place, lift)
  local x = place.x
  if x == nil or math.abs(place.chatLeft - place.centredLeft) <= L.SNAP then x = nil end
  lift = math.max(0, math.floor(tonumber(lift) or 0))
  if lift <= L.SNAP then lift = 0 end
  return x, lift
end

return ChaosChatLogic
