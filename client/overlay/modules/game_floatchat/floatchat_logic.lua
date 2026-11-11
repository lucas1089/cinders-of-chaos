-- Pure rules of the floating chat window (client/MANIFEST.md "Floating chat and central hotbar (O414)";
-- floatchat_test.lua): size and place with their limits, the hide / show state machine, the unread count, the fade,
-- the opacity, the header menus and the saved settings. Global FloatChatLogic.
FloatChatLogic = {}
local L = FloatChatLogic

-- ------------------------------------------------------------------ geometry (checked against the art by tools/gen_hotbar_art.py)
L.BORDER = 10          -- nine-slice border of chat_border.png
L.HEADER_H = 24
L.DEFAULT_W = 380
L.DEFAULT_H = 150
L.MIN_W = 260
L.MIN_H = 96
L.MAX_SHARE = 0.6      -- of the game window, each way
L.MARGIN = 8           -- from the window's edges by default
L.BAR_GAP = 6          -- above the hotbar when the default place would sit on it
L.NODE = 'chaos_floatchat'

-- ------------------------------------------------------------------ opacity and fade
L.OPACITY_MIN = 40
L.OPACITY_MAX = 100
L.OPACITY_DEFAULT = 75   -- body alpha about 75%
L.FADE_DEFAULT = 8       -- seconds without news before the fade
L.FADE_MIN, L.FADE_MAX = 3, 60
L.FADE_MS = 600          -- the fade itself

local function num(v)
  v = tonumber(v)
  if v and v == v and v ~= math.huge and v ~= -math.huge then return v end
  return nil
end

function L.clampOpacity(v)
  v = num(v) or L.OPACITY_DEFAULT
  return math.max(L.OPACITY_MIN, math.min(L.OPACITY_MAX, math.floor(v + 0.5)))
end

function L.clampFadeSeconds(v)
  v = num(v) or L.FADE_DEFAULT
  return math.max(L.FADE_MIN, math.min(L.FADE_MAX, math.floor(v + 0.5)))
end

-- alpha byte (0..255) of the body colour for an opacity percent
function L.bodyAlpha(opacity)
  return math.floor(L.clampOpacity(opacity) / 100 * 255 + 0.5)
end

-- The opacity percent to draw at `now` (ms). Fade off, hover, a recent message or typing: the set opacity. Otherwise it
-- sinks to OPACITY_MIN over FADE_MS after fadeSeconds without activity.
function L.fadedOpacity(opacity, o)
  local base = L.clampOpacity(opacity)
  if not o or not o.fade or o.hovered or o.typing or o.hidden then return base end
  local idle = (num(o.now) or 0) - (num(o.activity) or 0) - L.clampFadeSeconds(o.fadeSeconds) * 1000
  if idle <= 0 then return base end
  local k = math.min(1, idle / L.FADE_MS)
  return base - (base - math.min(base, L.OPACITY_MIN)) * k
end

-- ------------------------------------------------------------------ size and place
-- the biggest size the window allows
function L.maxSize(area)
  return math.max(L.MIN_W, math.floor((num(area.width) or 0) * L.MAX_SHARE)),
         math.max(L.MIN_H, math.floor((num(area.height) or 0) * L.MAX_SHARE))
end

-- A rect {x, y, width, height} kept inside `area` {x, y, width, height}: the size between MIN and the share of the
-- area (never more than the area), the whole rect on screen.
function L.clampRect(rect, area)
  local ax, ay = math.floor(num(area.x) or 0), math.floor(num(area.y) or 0)
  local aw, ah = math.floor(num(area.width) or 0), math.floor(num(area.height) or 0)
  local maxW, maxH = L.maxSize(area)
  local w = math.max(L.MIN_W, math.min(maxW, math.floor(num(rect.width) or L.DEFAULT_W)))
  local h = math.max(L.MIN_H, math.min(maxH, math.floor(num(rect.height) or L.DEFAULT_H)))
  w, h = math.min(w, math.max(0, aw)), math.min(h, math.max(0, ah))
  local x = math.max(ax, math.min(ax + aw - w, math.floor(num(rect.x) or ax)))
  local y = math.max(ay, math.min(ay + ah - h, math.floor(num(rect.y) or (ay + ah - h))))
  return { x = x, y = y, width = w, height = h }
end

local function overlaps(a, b)
  return a and b and a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height
end

-- The first place: bottom-left of `area`, above `avoid` (the hotbar's rect) when it would sit on it.
function L.defaultRect(area, avoid, width, height)
  local r = L.clampRect({ width = width or L.DEFAULT_W, height = height or L.DEFAULT_H,
                          x = (num(area.x) or 0) + L.MARGIN, y = math.huge }, area)
  r.y = math.max(num(area.y) or 0, (num(area.y) or 0) + (num(area.height) or 0) - r.height - L.MARGIN)
  if avoid and overlaps(r, avoid) then
    r.y = math.max(num(area.y) or 0, avoid.y - L.BAR_GAP - r.height)
  end
  return r
end

-- The rect to show: the saved one clamped to the area, the default without one. saved: settings from settingsFor.
function L.place(saved, area, avoid)
  if saved and saved.x and saved.y then
    return L.clampRect({ x = saved.x, y = saved.y, width = saved.width, height = saved.height }, area)
  end
  return L.defaultRect(area, avoid, saved and saved.width, saved and saved.height)
end

-- the size while the corner grip is dragged: the size at the press plus the mouse travel
function L.resizeBy(start, mouseX, mouseY, area)
  local r = L.clampRect({ x = start.x, y = start.y,
                          width = start.width + ((num(mouseX) or 0) - (num(start.mouseX) or 0)),
                          height = start.height + ((num(mouseY) or 0) - (num(start.mouseY) or 0)) }, area)
  return r
end

-- the rect while the header is dragged
function L.moveBy(start, mouseX, mouseY, area)
  return L.clampRect({ x = start.x + ((num(mouseX) or 0) - (num(start.mouseX) or 0)),
                       y = start.y + ((num(mouseY) or 0) - (num(start.mouseY) or 0)),
                       width = start.width, height = start.height }, area)
end

-- ------------------------------------------------------------------ the drag state machine (O498)
-- One drag of the window: { active, kind = 'move' | 'resize', start, moved }. The glue (floatchat.lua) feeds it the
-- mouse; the rules live here so they are tested without an engine.
--   * Only a press on the header or the grip begins a drag, and only with the left button. A press on a button of the
--     header (Channels, Private, X, gear) never does: the engine hands a button's release to the button alone (the
--     base UIButton:onMouseRelease returns isPressed(), which stops the release from reaching the header), so a drag
--     begun there was never ended and the window followed the pointer for good (owner 2026-11-11).
--   * A drag ends on ANY release, when a move arrives with the left button no longer down, when the client window
--     lost focus, on hide and on logout (dragCancel).
L.DRAG_TARGETS = { header = 'move', grip = 'resize' }

-- classes whose press keeps to themselves: a press on one never moves the window
L.BUTTON_CLASSES = { UIButton = true, UICheckBox = true, UIComboBox = true, UITextEdit = true, UIScrollBar = true }

function L.isButtonClass(name)
  return L.BUTTON_CLASSES[name] == true
end

-- 'header' or 'grip' (a place that drags), or 'button' for a press on a button: what the press landed on
function L.dragTarget(place, className)
  if L.isButtonClass(className) then return 'button' end
  return place
end

function L.dragNew()
  return { active = false, kind = nil, start = nil, moved = false }
end

-- a press: the new state. A press that cannot begin a drag also ends one left over from before (a press means the
-- earlier button went up without anyone hearing of it)
function L.dragPress(s, target, isLeft, rect, mouseX, mouseY)
  local kind = isLeft and L.DRAG_TARGETS[target] or nil
  if not kind then return L.dragNew() end
  return { active = true, kind = kind, moved = false,
           start = { x = rect.x, y = rect.y, width = rect.width, height = rect.height,
                     mouseX = num(mouseX) or 0, mouseY = num(mouseY) or 0 } }
end

-- a mouse move. env: { leftDown (the left button is down now), focused (the client window has focus), hidden }.
-- Returns state, rect (the new rect to apply, or nil), ended (true when this move ended an active drag)
function L.dragMove(s, mouseX, mouseY, area, env)
  if not s or not s.active then return s or L.dragNew(), nil, false end
  env = env or {}
  if env.leftDown == false or env.focused == false or env.hidden == true then
    return L.dragNew(), nil, true
  end
  local r
  if s.kind == 'move' then r = L.moveBy(s.start, mouseX, mouseY, area) else r = L.resizeBy(s.start, mouseX, mouseY, area) end
  return { active = true, kind = s.kind, start = s.start, moved = true }, r, false
end

-- a release anywhere, or a cancel (hide, logout, focus lost): returns state, wasActive, moved
function L.dragEnd(s)
  if not s or not s.active then return L.dragNew(), false, false end
  return L.dragNew(), true, s.moved == true
end

-- a poll tick: should an active drag be dropped (button up behind our back, client window out of focus)
function L.dragStale(s, env)
  if not s or not s.active then return false end
  env = env or {}
  return env.leftDown == false or env.focused == false or env.hidden == true
end

-- a click in the chat window (the left button went up over it) while the chat input is on gives the keys back to
-- the input: wasDown (a poll ago), isDown (now), inside (the pointer is over the window), typing (input enabled)
function L.refocusAfterClick(wasDown, isDown, inside, typing)
  return wasDown == true and isDown == false and inside == true and typing == true
end

-- ------------------------------------------------------------------ hide / show
-- state: { hidden, typing, peek (shown only because Enter was pressed), unread, activity }
-- options: { showOnType (default true), hideOnSend (default true) }
function L.new(hidden, now)
  return { hidden = hidden == true, typing = false, peek = false, unread = 0, activity = num(now) or 0 }
end

local function copy(s)
  return { hidden = s.hidden, typing = s.typing, peek = s.peek, unread = s.unread, activity = s.activity }
end

L.UNREAD_MAX = 99

-- events: 'toggle', 'show', 'hide', 'typing_on' (Enter opened the chat input), 'typing_off' (the input closed: a line
-- was sent, or an empty Enter / Escape), 'message' (a line arrived), 'touch' (hover or a click)
function L.step(state, event, o, now)
  o = o or {}
  local s = copy(state)
  local showOnType = o.showOnType ~= false
  local hideOnSend = o.hideOnSend ~= false
  if event == 'toggle' then
    if s.hidden then event = 'show' else event = 'hide' end
  end
  if event == 'show' then
    s.hidden, s.peek, s.unread, s.activity = false, false, 0, num(now) or s.activity
  elseif event == 'hide' then
    s.hidden, s.peek = true, false
  elseif event == 'typing_on' then
    s.typing = true
    if s.hidden and showOnType then s.hidden, s.peek, s.unread = false, true, 0 end
    s.activity = num(now) or s.activity
  elseif event == 'typing_off' then
    s.typing = false
    if s.peek and hideOnSend then s.hidden = true end
    s.peek = false
  elseif event == 'message' then
    if s.hidden then s.unread = math.min(L.UNREAD_MAX, s.unread + 1) else s.activity = num(now) or s.activity end
  elseif event == 'touch' then
    s.activity = num(now) or s.activity
  end
  return s
end

-- text of the unread badge ("" for none, "99+" past the cap)
function L.badge(count)
  count = math.max(0, math.floor(num(count) or 0))
  if count == 0 then return '' end
  if count > L.UNREAD_MAX then return L.UNREAD_MAX .. '+' end
  return tostring(count)
end

-- ------------------------------------------------------------------ the header menus
L.SYSTEM_TABS = { ['Default'] = true, ['Server Log'] = true, ['Loot'] = true, ['Local Chat'] = true, ['NPCs'] = true }

-- 'channel' or 'private' for a console tab: a tab with a channel id is a channel; one without that is not a system
-- tab is a private chat with a player
function L.classify(name, channelId)
  if channelId ~= nil then return 'channel' end
  if L.SYSTEM_TABS[name] then return 'channel' end
  return 'private'
end

-- Entries of the two menus from the open tabs. tabs: list of { name, channelId, unread (number), current (bool) }.
-- Returns { channels = list, private = list, channelsUnread, privateUnread } where an entry is { name, unread, current }.
function L.menus(tabs)
  local out = { channels = {}, private = {}, channelsUnread = 0, privateUnread = 0 }
  for _, t in ipairs(tabs or {}) do
    if type(t) == 'table' and type(t.name) == 'string' then
      local unread = math.max(0, math.floor(num(t.unread) or 0))
      local e = { name = t.name, unread = unread, current = t.current == true }
      if L.classify(t.name, t.channelId) == 'private' then
        out.private[#out.private + 1] = e
        out.privateUnread = out.privateUnread + unread
      else
        out.channels[#out.channels + 1] = e
        out.channelsUnread = out.channelsUnread + unread
      end
    end
  end
  return out
end

-- ------------------------------------------------------------------ settings
-- the saved settings of one character (g_settings node L.NODE) with every value clamped
function L.settingsFor(saved, name)
  local e = type(saved) == 'table' and name and saved[name] or nil
  if type(e) ~= 'table' then e = {} end
  local function bool(v, default)
    if v == nil then return default end
    return v == true or v == 'true' or v == 1
  end
  local x, y = num(e.x), num(e.y)
  return { x = x and math.floor(x) or nil, y = (x and y) and math.floor(y) or nil,
           width = math.max(L.MIN_W, math.floor(num(e.width) or L.DEFAULT_W)),
           height = math.max(L.MIN_H, math.floor(num(e.height) or L.DEFAULT_H)),
           hidden = bool(e.hidden, false), opacity = L.clampOpacity(e.opacity),
           fade = bool(e.fade, false), fadeSeconds = L.clampFadeSeconds(e.fadeSeconds),
           hideOnSend = bool(e.hideOnSend, true) }
end

function L.store(saved, name, s)
  saved = type(saved) == 'table' and saved or {}
  if not name then return saved end
  saved[name] = { x = s.x, y = s.y, width = s.width, height = s.height, hidden = s.hidden == true,
                  opacity = L.clampOpacity(s.opacity), fade = s.fade == true,
                  fadeSeconds = L.clampFadeSeconds(s.fadeSeconds), hideOnSend = s.hideOnSend ~= false }
  return saved
end

return FloatChatLogic
