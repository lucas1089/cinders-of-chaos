-- Streamer mode and cinema mode (O411; client/MANIFEST.md "Streamer and cinema modes"): the rules without client API,
-- tested by streamer_core_test.lua. streamer.lua and cinema.lua connect them to the client.
--   streamer mode  private message text hidden (chat and screen), the sender too with the sub-option, the character
--                  name out of the window title, the login fields' text hidden, the other characters of the list
--                  masked, IP addresses in server messages masked, the own name over the character off (sub-option)
--   cinema mode    every panel and window around the map hidden, the map over the whole window, then all back

StreamerCore = StreamerCore or {}
local C = StreamerCore

-- the options (client_settings dataset.lua, base patch 0186), saved in g_settings under these keys; all off by default
C.KEYS = { 'streamerMode', 'streamerHideSender', 'streamerHideOwnName', 'cinemaHideOthers' }
C.DEFAULTS = { streamerMode = false, streamerHideSender = false, streamerHideOwnName = false, cinemaHideOthers = false }

C.HOTKEY_STREAMER = 'Ctrl+Shift+S'
C.HOTKEY_CINEMA = 'Ctrl+Shift+H'

-- Creature.setInfoHide bits (base patch 0186)
C.HIDE_OWN_NAME = 1
C.HIDE_OTHER_PLAYERS = 2

-- the sender shown with streamerHideSender: brackets are not allowed in a character name, so no player has it
C.HIDDEN_SENDER = '[hidden]'
C.IP_MASK = '***.***.***.***'

local function id(s) return s end

-- the options from raw values (g_settings reads: booleans, or nil when never saved)
function C.normalize(raw)
  local out = {}
  for _, k in ipairs(C.KEYS) do
    local v = type(raw) == 'table' and raw[k] or nil
    if type(v) == 'boolean' then out[k] = v else out[k] = C.DEFAULTS[k] end
  end
  return out
end

-- an incoming private message from a player (MessageModes.PrivateFrom); a gamemaster's private message stays readable
function C.isPrivateIncoming(mode, modes)
  return type(modes) == 'table' and mode ~= nil and mode == modes.PrivateFrom
end

-- name and text of a talk line as the chat and the screen show it. Returns name, text, masked.
function C.maskTalk(opts, name, mode, text, modes, translate)
  translate = translate or id
  if not (opts and opts.streamerMode) or not C.isPrivateIncoming(mode, modes) then
    return name, text, false
  end
  local shownName = name
  if opts.streamerHideSender then shownName = translate(C.HIDDEN_SENDER) end
  return shownName, translate('(private message hidden: streamer mode)'), true
end

-- the window title: only the client's name while streamer mode is on (the base adds " - <character>" at login)
function C.title(requested, appName, opts)
  if opts and opts.streamerMode then return appName or '' end
  return requested
end

-- a character's name in a list: the chosen one stays, the others are masked while streamer mode is on
function C.listName(name, isSelected, opts, translate)
  translate = translate or id
  if not (opts and opts.streamerMode) or isSelected then return name end
  return translate('Hidden character')
end

-- IPv4 addresses (with an optional :port) in a text, masked while streamer mode is on
function C.maskIps(text, opts)
  if type(text) ~= 'string' or not (opts and opts.streamerMode) then return text end
  local out = text:gsub('%f[%d]%d+%.%d+%.%d+%.%d+%f[%D]', function(ip)
    for part in ip:gmatch('%d+') do
      if #part > 3 or tonumber(part) > 255 then return ip end
    end
    return C.IP_MASK
  end)
  out = out:gsub('(' .. C.IP_MASK:gsub('%p', '%%%0') .. '):%d+', '%1')
  return out
end

-- the mask for Creature.setInfoHide: the own name in streamer mode (sub-option), other players in cinema mode (sub-option)
function C.infoHideMask(opts, cinemaOn)
  local mask = 0
  if opts and opts.streamerMode and opts.streamerHideOwnName then mask = mask + C.HIDE_OWN_NAME end
  if cinemaOn and opts and opts.cinemaHideOthers then mask = mask + C.HIDE_OTHER_PLAYERS end
  return mask
end

-- the value a hotkey toggle writes: the other one
function C.toggled(opts, key)
  return not (opts and opts[key] == true)
end

-- ---------------------------------------------------------------- cinema
-- Which widgets to hide. chain: the widgets from the map up to (not including) the root, each with its siblings:
-- { { widget = w, siblings = { {widget, visible}, ... } }, ... } and the map's own children (mapChildren, the HUD on the
-- map). Every visible widget that is not on the chain is hidden. Returns the list of widgets, in order.
function C.cinemaPick(chain, mapChildren)
  local out, onChain = {}, {}
  for _, level in ipairs(chain or {}) do onChain[level.widget] = true end
  for _, level in ipairs(chain or {}) do
    for _, s in ipairs(level.siblings or {}) do
      if s.visible and not onChain[s.widget] then out[#out + 1] = s.widget end
    end
  end
  for _, c in ipairs(mapChildren or {}) do
    if c.visible then out[#out + 1] = c.widget end
  end
  return out
end

-- add the widgets of `found` not yet in `hidden` (a widget that showed up during cinema mode); returns the new ones
function C.addNew(hidden, found)
  local seen, added = {}, {}
  for _, w in ipairs(hidden) do seen[w] = true end
  for _, w in ipairs(found or {}) do
    if not seen[w] then
      seen[w] = true
      hidden[#hidden + 1] = w
      added[#added + 1] = w
    end
  end
  return added
end

return C
