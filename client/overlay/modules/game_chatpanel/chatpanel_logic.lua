-- Pure rules of the chat panel (client/MANIFEST.md "Chat panel"; tested by chatpanel_test.lua). Global
-- ChaosChatLogic: modules/game_console reads enterAction (base patch 0056), chatpanel.lua the size rules.
ChaosChatLogic = {}
local L = ChaosChatLogic

-- the bottom area (action bars + console): width in pixels. It is centred in the game window with the orbs beside it
-- by default; the player can move it sideways (L.layout below)
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

-- the saved size and place of one character, or the defaults for a new one. offset: pixels from the centred place
-- (nil: centred, the default)
function L.sizeFor(saved, name)
  local entry = type(saved) == 'table' and name and saved[name] or nil
  if type(entry) ~= 'table' then return { width = L.DEFAULT_WIDTH } end
  local offset = tonumber(entry.offset)
  return { width = tonumber(entry.width) or L.DEFAULT_WIDTH, height = tonumber(entry.height),
           offset = offset and math.floor(offset) or nil }
end

-- ------------------------------------------------------------------ the group: life orb, chat panel, mana orb
-- Left to right: life orb | ORB_GAP | move grip | MOVE_GRIP_GAP | chat (action bars + console) | WIDTH_GRIP_GAP |
-- width grip | ORB_GAP | mana orb. The orbs are anchored to the chat's edges (game_shaderfx reads orbMargins), so
-- they follow it; nothing of the group overlaps.
L.GRIP = 6            -- width of both grips
L.MOVE_GRIP_GAP = 2   -- move grip <-> chat's left edge
L.WIDTH_GRIP_GAP = 13 -- chat's right edge <-> width grip (past the action bar's lock column)
L.ORB_GAP = 4         -- grip <-> orb
L.ORB_BOTTOM = 4      -- orbs over the window's bottom edge (the chat reaches it)
L.SNAP = 8            -- a drag that ends this close to the centre snaps back to "centred"

-- margins of the orbs from the chat panel (bottomSplitter) edges: life orb's right margin from its left edge, mana
-- orb's left margin from its right edge, and the bottom margin of both
function L.orbMargins()
  return { left = L.MOVE_GRIP_GAP + L.GRIP + L.ORB_GAP, right = L.WIDTH_GRIP_GAP + L.GRIP + L.ORB_GAP,
           bottom = L.ORB_BOTTOM }
end

local function extras(orbSize)
  local m = L.orbMargins()
  local o = math.max(0, math.floor(tonumber(orbSize) or 0))
  return m.left + o, m.right + o
end

-- Place the group. p:
--   regionLeft, regionRight  x range the bottom area may use (between the side panels)
--   windowLeft, windowWidth  the game window (the group centres on it)
--   width                    the wanted chat width
--   offset                   pixels from the centred place, nil = centred
--   orbSize                  size of the orbs, 0 / nil without orbs
-- Returns { chatLeft, chatWidth, offset (clamped; nil when centred), orbs (true when the orbs fit beside the chat) }.
-- The group stays inside the region; orbs that leave less than MIN_WIDTH for the chat are left out (hidden).
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
  local chatWidth = L.clampWidth(p.width, math.max(0, room - exL - exR))
  local group = exL + chatWidth + exR
  local windowLeft = math.floor(tonumber(p.windowLeft) or left)
  local windowWidth = math.floor(tonumber(p.windowWidth) or room)
  local centred = windowLeft + math.floor((windowWidth - group) / 2)
  local offset = p.offset and math.floor(tonumber(p.offset) or 0) or nil
  local groupLeft = centred + (offset or 0)
  groupLeft = math.max(left, math.min(right - group, groupLeft))
  if offset then
    offset = groupLeft - centred
    if math.abs(offset) <= L.SNAP then offset = nil end
  end
  return { chatLeft = groupLeft + exL, chatWidth = chatWidth, offset = offset, orbs = orbs }
end

-- the splitter's margins for a layout. anchorLeft / anchorRight: x of the splitter's anchor lines (the left panels'
-- right edge, the right panels' left edge)
function L.splitterMargins(place, anchorLeft, anchorRight)
  return math.max(0, place.chatLeft - math.floor(anchorLeft)),
         math.max(0, math.floor(anchorRight) - (place.chatLeft + place.chatWidth))
end

-- the chat width that puts the width grip under the mouse. The group is centred (plus offset), so a wider chat also
-- moves its left edge: chatRight = centre + offset + (exL + width - exR) / 2. orbSize: the orbs shown (0 when not)
function L.widthForGrip(mouseX, windowLeft, windowWidth, offset, orbSize)
  local exL, exR = extras(orbSize)
  local centre = (tonumber(windowLeft) or 0) + (tonumber(windowWidth) or 0) / 2
  local chatRight = (tonumber(mouseX) or 0) - L.WIDTH_GRIP_GAP - L.GRIP / 2
  return math.floor(2 * (chatRight - centre - (tonumber(offset) or 0)) - exL + exR + 0.5)
end

-- the offset while the move grip is dragged: the offset at the press plus the mouse travel (layout clamps it)
function L.dragOffset(startOffset, startX, mouseX)
  return (tonumber(startOffset) or 0) + math.floor((tonumber(mouseX) or 0) - (tonumber(startX) or 0))
end

return ChaosChatLogic
