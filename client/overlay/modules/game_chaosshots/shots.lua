-- game_chaosshots: automatic screenshots of the Chaos moments (O411; client/MANIFEST.md "Automatic screenshots").
-- The switches are the base client's Options > Misc. > Screenshot page (shots_core.lua says which box each event reads);
-- the picture is taken the way the base takes its own (g_app.doScreenshot, or g_app.doMapScreenshot with "Only Capture
-- Game Window"), 0.3 s after the event, into "screenshots" of the client's write folder, and a toast names the folder.
-- Where each event comes from:
--   level up       LocalPlayer.onLevelChange to a higher level (not the level set at login)
--   valuable loot  game_lootfilter hands each kill's drops here (onLootKill): a Legendary, Divine or unique drop
--   boss kill      Creature.onHealthPercentChange to 0 on a monster game_monsterbar knows as a boss (tierInfo) that you
--                  attacked in the last 2 minutes
--   achievement    game_achievements hands the server's "unlock" here (onAchievement)
--   new record     the server's "New record: ..." line (records.lua) in g_game.onTextMessage
-- Nothing is hidden for the picture: cinema mode (client_chaos_streamer, Ctrl+Shift+H) hides the interface if wanted,
-- and streamer mode already hides private message text; with streamer mode on the file name leaves the character name
-- out and the toast shows only the folder's name. Phones: off (the write folder of the Android app is private to it).

local C = ChaosShotsCore

local state = C.newState()
local shotEvent
local engaged = {}        -- creature id -> when you last attacked it (g_clock.millis)
local handlers = {}

local function now()
  return g_clock and g_clock.millis and g_clock.millis() or 0
end

local function option(key)
  local cs = modules and modules.client_settings
  local go = cs and rawget(cs, 'GameOptions')
  if go and go.getDataSet and go:getDataSet(key) then
    local ok, v = pcall(go.getOption, go, key)
    if ok then return v end
  end
  return nil
end

local function isMobile()
  return g_app and g_app.isMobile and g_app.isMobile() or false
end

local function streamerOn()
  return ChaosStreamer ~= nil and ChaosStreamer.isOn ~= nil and ChaosStreamer.isOn()
end

local function folderPath()
  local wd = g_resources and g_resources.getWriteDir and g_resources.getWriteDir() or ''
  if wd ~= '' and not wd:match('[/\\]$') then wd = wd .. '/' end
  return wd .. C.FOLDER
end

local function toast(text)
  local notify = modules and modules.game_chaosnotify
  if notify and notify.addNotification then
    local ok = pcall(notify.addNotification, 'SCREENSHOT', text)
    if ok then return end
  end
  local tm = modules and modules.game_textmessage
  if tm and tm.displayStatusMessage then pcall(tm.displayStatusMessage, text) end
end

local function shoot()
  shotEvent = nil
  local event = C.taken(state)
  if not event or not g_game.isOnline() then return end
  local player = g_game.getLocalPlayer()
  if not player then return end
  if g_resources.directoryExists and not g_resources.directoryExists(C.FOLDER) then
    pcall(g_resources.makeDir, C.FOLDER)
  end
  local streamer = streamerOn()
  local file = C.fileName(event, player:getName(), player:getLevel(), os.date('%Y-%m-%d_%H-%M-%S'), streamer,
    function(p) return g_resources.fileExists(p) end)
  local fn = option(C.MAP_ONLY_KEY) == true and g_app.doMapScreenshot or g_app.doScreenshot
  if not fn then return end
  local ok, err = pcall(fn, file)
  if not ok then
    g_logger.warning('[chaosshots] ' .. tostring(err))
    return
  end
  toast(C.toastText(folderPath(), streamer, tr))
end

-- any event: shot 0.3 s later when its box is ticked (one picture for a burst of events)
local function fire(event)
  if not g_game.isOnline() or not C.wants(event, option, isMobile()) then return end
  local what = C.request(state, event, now())
  if what == 'shoot' then
    if shotEvent then removeEvent(shotEvent) end
    shotEvent = scheduleEvent(shoot, C.DELAY_MS)
  end
end

-- ---------------------------------------------------------------- hooks other modules call
-- game_lootfilter: a kill's drops (the loot filter's "kill" message)
function onLootKill(data)
  if type(data) == 'table' and C.valuableLoot(data.drops) then fire('loot') end
end

-- game_achievements: the server's "unlock"
function onAchievement(data)
  fire('achievement')
end

-- for checks from the terminal: modules.game_chaosshots.test('boss')
function test(event)
  fire(event or 'level')
end

-- ---------------------------------------------------------------- engine events
local function onLevelChange(player, level, percent, oldLevel)
  if C.isLevelUp(level, oldLevel) then fire('level') end
end

local function onTextMessage(mode, text)
  if C.isRecordMessage(text) then fire('record') end
end

local function onAttackingCreatureChange(creature)
  if not creature then return end
  local t = now()
  engaged[creature:getId()] = t
  for id, at in pairs(engaged) do
    if t - at > C.ENGAGED_MS then engaged[id] = nil end
  end
end

local function onHealthPercentChange(creature, percent)
  if (tonumber(percent) or 1) > 0 or not creature or not creature.isMonster or not creature:isMonster() then return end
  local id = creature:getId()
  local at = engaged[id]
  if not at then return end
  local mb = modules and modules.game_monsterbar
  local tier = mb and mb.tierInfo and mb.tierInfo(id)
  if C.isBossKill(tier, percent, at, now()) then
    engaged[id] = nil
    fire('boss')
  end
end

local function onGameEnd()
  engaged = {}
  state = C.newState()
  if shotEvent then removeEvent(shotEvent) shotEvent = nil end
end

function init()
  handlers.player = { onLevelChange = onLevelChange }
  handlers.creature = { onHealthPercentChange = onHealthPercentChange }
  handlers.game = { onTextMessage = onTextMessage, onAttackingCreatureChange = onAttackingCreatureChange,
    onGameEnd = onGameEnd }
  connect(LocalPlayer, handlers.player)
  connect(Creature, handlers.creature)
  connect(g_game, handlers.game)
end

function terminate()
  disconnect(LocalPlayer, handlers.player)
  disconnect(Creature, handlers.creature)
  disconnect(g_game, handlers.game)
  onGameEnd()
end
