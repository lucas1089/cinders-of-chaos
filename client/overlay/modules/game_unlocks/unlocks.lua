-- Unlocks: the shared owned / locked list behaviour (client/MANIFEST.md "Owned and locked lists"); the rule is
-- unlocks_core.lua. Used by the Customise Character window (base module game_outfit, base patch 0058) and by
-- game_cosmetics. API (modules.game_unlocks):
--   UnlocksCore                        the rule (display, filter, isLocked, tooltip, lockedParts, ...)
--   wardrobe()                         the last wardrobe catalogue of the server (nil before it came)
--   setWardrobe(data)                  game_cosmetics hands the server's "wardrobe" answer here (opcode 225)
--   requestWardrobe()                  ask the server for it (on the cosmetics opcode)
--   styleEntry(widget, entry)          grey a locked entry's widget, set its tooltip, widget.locked
--   onlyMine(list) / setOnlyMine(list, on)    the "Only mine" box of a list, kept per character
--   bindOnlyMine(checkBox, list, onChange)    a checkbox wired to that setting
-- When a new catalogue comes, modules.game_outfit.onUnlocksChanged() is called (base patch 0058) so an open window
-- redraws its list.

local U = UnlocksCore
local OPCODE = 225 -- ChaosOpcodes.cosmetics: the server's wardrobe.lua answers the action "wardrobe"
local SETTINGS_NODE = 'chaosOnlyMine'
local data
local requested = 0

local function character()
  local me = g_game.isOnline() and g_game.getLocalPlayer() or nil
  return me and me:getName() or ''
end

function wardrobe()
  return data
end

function requestWardrobe()
  local protocol = g_game.getProtocolGame()
  if not protocol then return end
  -- the window opens on a server packet; one request per second at most
  local now = g_clock.millis()
  if now - requested < 1000 then return end
  requested = now
  protocol:sendExtendedOpcode(OPCODE, json.encode({ action = 'wardrobe', data = {} }))
end

function setWardrobe(msg)
  local w = U.readWardrobe(msg)
  if not w then return end
  data = w
  local outfit = modules.game_outfit
  if outfit and type(outfit.onUnlocksChanged) == 'function' then
    local ok, err = pcall(outfit.onUnlocksChanged)
    if not ok then g_logger.warning('[unlocks] outfit window: ' .. tostring(err)) end
  end
end

-- ---------------------------------------------------------------- widgets
function styleEntry(widget, entry)
  if not widget or widget:isDestroyed() then return end
  local locked = U.isLocked(entry)
  widget.locked = locked or nil
  widget:setOpacity(locked and U.LOCKED_OPACITY or 1)
  local tip = U.tooltip(entry)
  if tip then widget:setTooltip(tip) else widget:removeTooltip() end
end

-- ---------------------------------------------------------------- "Only mine"
function onlyMine(list)
  return U.onlyMine(g_settings.getNode(SETTINGS_NODE), character(), list)
end

function setOnlyMine(list, on)
  g_settings.setNode(SETTINGS_NODE, U.setOnlyMine(g_settings.getNode(SETTINGS_NODE), character(), list, on))
end

function bindOnlyMine(box, list, onChange)
  if not box then return end
  box.onCheckChange = nil
  box:setChecked(onlyMine(list))
  box.onCheckChange = function(_, checked)
    setOnlyMine(list, checked)
    if onChange then onChange(checked) end
  end
end

-- ---------------------------------------------------------------- module
local function onGameStart()
  data = nil
  requested = 0
  scheduleEvent(function()
    if g_game.isOnline() then requestWardrobe() end
  end, 800)
end

local function onGameEnd()
  data = nil
end

-- owned things can change between two openings (a store purchase, a boss drop): ask again each time
local function onOpenOutfitWindow()
  requestWardrobe()
end

function init()
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd, onOpenOutfitWindow = onOpenOutfitWindow })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd, onOpenOutfitWindow = onOpenOutfitWindow })
  data = nil
end
