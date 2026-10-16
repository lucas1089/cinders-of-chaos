-- Pure rules of the chat panel (client/MANIFEST.md "Chat panel"; tested by chatpanel_test.lua). Global
-- ChaosChatLogic: modules/game_console reads enterAction (base patch 0056), chatpanel.lua the size rules.
ChaosChatLogic = {}
local L = ChaosChatLogic

-- the bottom area (action bars + console): width in pixels
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

-- the saved size of one character, or the defaults for a new one
function L.sizeFor(saved, name)
  local entry = type(saved) == 'table' and name and saved[name] or nil
  if type(entry) ~= 'table' then return { width = L.DEFAULT_WIDTH } end
  return { width = tonumber(entry.width) or L.DEFAULT_WIDTH, height = tonumber(entry.height) }
end

return ChaosChatLogic
