-- Automatic screenshots of the Chaos events (O411; client/MANIFEST.md "Automatic screenshots"): the rules without
-- client API, tested by shots_core_test.lua; shots.lua connects them.
-- The base client's Options > Misc. > Screenshot page has the switches ("Enable Auto Screenshots", one box per event,
-- "Only Capture Game Window"), but its events come only from the server's take-screenshot packet (0x75), which this
-- server never sends, so none of them fired. Each Chaos event here reads the box of the base event it matches:
--   level up        Level Up               (screenshotLevelUp, on by default)
--   valuable loot   Valuable Loot          (screenshotValuableLoot, off): a Legendary, Divine or unique drop of your kill
--   boss kill       Boss Defeated          (screenshotBossDefeated, off): a boss-tier monster you fought dies
--   achievement     Achievement            (screenshotAchievement, on)
--   new record      New Record             (screenshotRecord, on; the box is base patch 0186)

ChaosShotsCore = ChaosShotsCore or {}
local C = ChaosShotsCore

C.DELAY_MS = 300            -- after the event, so its effect (level wings, loot beam, toast) is in the picture
C.SAME_EVENT_MS = 3000      -- the same event again this soon is one picture (several levels from one kill)
C.FOLDER = 'screenshots'    -- in the client's write folder, as the base's manual screenshots
C.MASTER_KEY = 'autoScreenshot'
C.MAP_ONLY_KEY = 'gameWindowScreen'

C.EVENTS = {
  level = { key = 'screenshotLevelUp', default = true, label = 'Level Up', file = 'levelup', rank = 2 },
  loot = { key = 'screenshotValuableLoot', default = false, label = 'Valuable Loot', file = 'loot', rank = 3 },
  boss = { key = 'screenshotBossDefeated', default = false, label = 'Boss Defeated', file = 'boss', rank = 4 },
  achievement = { key = 'screenshotAchievement', default = true, label = 'Achievement', file = 'achievement', rank = 1 },
  record = { key = 'screenshotRecord', default = true, label = 'New Record', file = 'record', rank = 5 },
}

-- loot ranks (server lootfilter.lua drops[].rank: the rarity id, 100 for a unique): Legendary 5, Divine 10, unique 100
C.LOOT_MIN_RANK = 5
-- the server's personal record line (records.lua "New record: %s: %s (was %s)" and its pt-BR text)
C.RECORD_PREFIXES = { 'New record: ', 'Novo recorde: ' }
C.BOSS_TIER = 'boss'
C.ENGAGED_MS = 120000       -- a boss you attacked this recently counts as yours when it dies

-- is the event wanted? get(key) reads an option (nil when the client has no such option: its default is used)
function C.wants(event, get, isMobile)
  local e = C.EVENTS[event]
  if not e or isMobile then return false end
  local function opt(key, default)
    local v = get and get(key)
    if type(v) == 'boolean' then return v end
    return default
  end
  return opt(C.MASTER_KEY, true) and opt(e.key, e.default)
end

function C.newState()
  return { pending = nil, last = {} }
end

-- an event at time now: 'shoot' (start the delay), 'merged' (a picture is already coming: it names the higher event),
-- 'repeat' (the same event a moment ago)
function C.request(state, event, now)
  local last = state.last[event]
  if last and now - last < C.SAME_EVENT_MS then return 'repeat' end
  state.last[event] = now
  if state.pending then
    local cur = C.EVENTS[state.pending]
    local new = C.EVENTS[event]
    if new and cur and new.rank > cur.rank then state.pending = event end
    return 'merged'
  end
  state.pending = event
  return 'shoot'
end

-- the picture is taken: the event it is named after
function C.taken(state)
  local e = state.pending
  state.pending = nil
  return e
end

local function clean(s)
  return (tostring(s or ''):gsub('[^%w%-]', '_'))
end

-- "screenshots/<name>_<level>_<event>_<date>.png"; streamer mode leaves the name out. exists(path) -> bool picks a
-- free name ("..._1.png").
function C.fileName(event, charName, level, dateText, streamer, exists)
  local e = C.EVENTS[event]
  local parts = {}
  if not streamer and charName and charName ~= '' then parts[#parts + 1] = clean(charName) end
  parts[#parts + 1] = tostring(math.floor(tonumber(level) or 0))
  parts[#parts + 1] = e and e.file or clean(event)
  parts[#parts + 1] = clean(dateText)
  local base = C.FOLDER .. '/' .. table.concat(parts, '_')
  local name = base .. '.png'
  local n = 0
  while exists and exists(name) and n < 1000 do
    n = n + 1
    name = base .. '_' .. n .. '.png'
  end
  return name
end

-- the toast: the folder; in streamer mode only the folder's own name (the full path can show the computer's user name)
function C.toastText(folderPath, streamer, translate)
  translate = translate or function(s, ...) return string.format(s, ...) end
  local where = (streamer or not folderPath or folderPath == '') and C.FOLDER or folderPath
  return translate('Screenshot saved in %s', where)
end

-- a kill's drops from the loot filter (opcode 238 "kill": drops = [{text, color, rank}])
function C.valuableLoot(drops)
  if type(drops) ~= 'table' then return false end
  for _, d in ipairs(drops) do
    local r = type(d) == 'table' and tonumber(d.rank) or 0
    if r and r >= C.LOOT_MIN_RANK then return true end
  end
  return false
end

function C.isRecordMessage(text)
  if type(text) ~= 'string' then return false end
  for _, p in ipairs(C.RECORD_PREFIXES) do
    if text:sub(1, #p) == p then return true end
  end
  return false
end

function C.isLevelUp(newLevel, oldLevel)
  newLevel, oldLevel = tonumber(newLevel), tonumber(oldLevel)
  return newLevel ~= nil and oldLevel ~= nil and oldLevel > 0 and newLevel > oldLevel
end

-- a monster died (health 0): a boss you attacked within ENGAGED_MS
function C.isBossKill(tier, percent, engagedAt, now)
  if tier ~= C.BOSS_TIER or (tonumber(percent) or 1) > 0 then return false end
  return engagedAt ~= nil and now - engagedAt <= C.ENGAGED_MS
end

return C
