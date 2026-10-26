-- Drop feed option (game_dropfeed), the logic without client API (tested by dropfeed_logic_test.lua).
-- The server (server/data/scripts/chaos/retention_loot.lua, extended opcode 229 beside the Records) posts a line for each
-- legendary, divine or unique drop of a player in the Default tab and in the channel "Drops". This option says which
-- kinds this client gets; the client sends it at login and when it changes, the server filters:
--   client -> server  feedopt {mode = "off" | "unique" | "legendary"}
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

DropFeedLogic = {}
local L = DropFeedLogic

L.OPCODE = 229
L.SETTINGS_NODE = 'chaosDropFeed'
L.MODES = { 'off', 'unique', 'legendary' } -- the order of the drop-down
L.DEFAULT = 'legendary'

function L.valid(mode)
  for _, m in ipairs(L.MODES) do
    if m == mode then return true end
  end
  return false
end

-- the settings node as it is stored ({mode = "..."} or anything): a known mode, else the default
function L.normalize(node)
  local mode = type(node) == 'table' and node.mode or nil
  return { mode = L.valid(mode) and mode or L.DEFAULT }
end

function L.modeNames()
  return {
    off = tr('Off'),
    unique = tr('Unique and Divine only'),
    legendary = tr('Legendary and better'),
  }
end

-- the index (1 ..) of a mode in the drop-down
function L.indexOf(mode)
  for i, m in ipairs(L.MODES) do
    if m == mode then return i end
  end
  return #L.MODES
end

-- the packet for the server: JSON text of {action, data}; encode = json.encode
function L.packet(mode, encode)
  if not L.valid(mode) then mode = L.DEFAULT end
  return encode({ action = 'feedopt', data = { mode = mode } })
end
