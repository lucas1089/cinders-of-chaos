-- Region music (O408; client/MANIFEST.md "Region music"): the rules, no engine calls (tested by musiclogic_test.lua).
-- Which track fits where the player is, when a change of place is real (hysteresis), the volume curve and the saved
-- settings. chaosmusic.lua reads the client and plays.
ChaosMusicLogic = {}
local M = ChaosMusicLogic

M.DIR = '/modules/game_chaosmusic/music/'
-- region -> file (client/tools/gen_music.py writes them; music_sources.csv lists them)
M.TRACKS = {
  login = 'music_login',
  town = 'music_town',
  hunt = 'music_hunt',
  dungeon = 'music_dungeon',
  boss = 'music_boss',
  arena = 'music_arena',
}
M.REGIONS = { 'login', 'town', 'hunt', 'dungeon', 'boss', 'arena' }

M.CROSSFADE = 2.5     -- seconds: the old track fades out while the new one fades in
M.FIRST_FADE = 1.5    -- seconds: the first track after silence
M.MUTE_FADE = 1.0     -- seconds: fade out when the music is switched off or the window is hidden
M.MIN_HOLD_MS = 3000  -- no new switch while the last cross-fade runs
M.BOSS_RANGE = 8      -- tiles: a hurt boss this near counts as a fight
M.TOWN_RANGE = 18     -- tiles: a temple, depot or bank this near (same floor) is town
M.DUNGEON_RANGE = 14  -- tiles: a dungeon entrance this near
M.TICK_MS = 500

-- activity modules: while their HUD shows (getState().hud), the player is inside. First match wins; the boss track
-- still wins over these (a boss in a rift or a dungeon)
M.ACTIVITIES = {
  { module = 'game_arena', region = 'arena' },
  { module = 'game_battleground', region = 'arena' },
  { module = 'game_siege', region = 'arena' },
  { module = 'game_pvpzone', region = 'arena' },
  { module = 'game_invasion', region = 'arena' },
  { module = 'game_rift', region = 'dungeon' },
  { module = 'game_dungeons', region = 'dungeon' },
  { module = 'game_infinitytower', region = 'dungeon' },
  { module = 'game_descent', region = 'dungeon' },
  { module = 'game_raid', region = 'dungeon' },
}

-- point of interest kinds (game_mapmarkers, server poi_config.lua) that say where the player is
M.TOWN_KINDS = { temple = true, depot = true, bank = true }
M.DUNGEON_KINDS = { dungeon = true }

-- ---------------------------------------------------------------- settings
M.DEFAULTS = { enabled = true, volume = 50, background = false }

function M.normalize(t)
  t = type(t) == 'table' and t or {}
  local out = {}
  out.enabled = t.enabled ~= false
  local v = tonumber(t.volume)
  if not v or v ~= v then v = M.DEFAULTS.volume end
  out.volume = math.max(0, math.min(100, math.floor(v + 0.5)))
  out.background = t.background == true
  return out
end

-- 0..1: the slider (0..100) on a curve that sounds even (half way is about -9 dB)
function M.gain(settings)
  if not settings or not settings.enabled then return 0 end
  local v = (tonumber(settings.volume) or 0) / 100
  if v <= 0 then return 0 end
  return math.min(1, v ^ 1.5)
end

function M.file(region)
  local name = M.TRACKS[region]
  return name and (M.DIR .. name .. '.ogg') or nil
end

-- ---------------------------------------------------------------- where the player is
local function near(a, b, range)
  return a and b and a.z == b.z and math.abs(a.x - b.x) <= range and math.abs(a.y - b.y) <= range
end

-- 'town' / 'dungeon' from the points of interest near pos, or nil. pois: game_mapmarkers marks {k, x, y, z}
function M.poiRegion(pos, pois)
  if not pos or type(pois) ~= 'table' then return nil end
  local dungeon = false
  for _, p in ipairs(pois) do
    if type(p) == 'table' then
      if M.TOWN_KINDS[p.k] and near(pos, p, M.TOWN_RANGE) then return 'town' end
      if M.DUNGEON_KINDS[p.k] and near(pos, p, M.DUNGEON_RANGE) then dungeon = true end
    end
  end
  return dungeon and 'dungeon' or nil
end

-- the region of an activity module whose HUD shows, or nil. states: {[module] = getState() result}
function M.activityRegion(states)
  if type(states) ~= 'table' then return nil end
  for _, a in ipairs(M.ACTIVITIES) do
    local st = states[a.module]
    if type(st) == 'table' and st.hud == true then return a.region end
  end
  return nil
end

-- a boss fight: the target is a boss (game_monsterbar tier) or a boss near the player is hurt.
-- target: {tier, health} or nil; bosses: {{pos, health}} of the boss-tier creatures in view
function M.bossEngaged(target, bosses, pos)
  if type(target) == 'table' and target.tier == 'boss' and (tonumber(target.health) or 0) > 0 then return true end
  if type(bosses) ~= 'table' then return false end
  for _, b in ipairs(bosses) do
    local h = tonumber(b.health) or 100
    if h > 0 and h < 100 and near(pos, b.pos, M.BOSS_RANGE) then return true end
  end
  return false
end

-- snap: {online, boss, activity, pz, pos, pois} -> the region the music should be
function M.wanted(snap)
  if type(snap) ~= 'table' or not snap.online then return 'login' end
  if snap.boss then return 'boss' end
  if snap.activity then return snap.activity end
  if snap.pz then return 'town' end
  return M.poiRegion(snap.pos, snap.pois) or 'hunt'
end

-- ---------------------------------------------------------------- hysteresis
-- ms the wanted region must hold before the music follows: a short step out of town keeps the town track, a boss
-- starts its track at once and keeps it a while after the fight
function M.delay(from, to)
  if from == nil or from == 'login' or to == 'login' then return 0 end
  if to == 'boss' then return 0 end
  if from == 'boss' then return 10000 end
  if from == 'town' then return 8000 end
  if to == 'town' then return 3000 end
  if to == 'arena' or to == 'dungeon' then return 1000 end
  return 4000
end

function M.newState()
  return { current = nil, pending = nil, since = 0, switchedAt = -math.huge }
end

-- one tick: returns the region to play and true when it changed
function M.step(st, wanted, now)
  if wanted == st.current then
    st.pending = nil
    return st.current, false
  end
  if st.pending ~= wanted then
    st.pending, st.since = wanted, now
  end
  local login = st.current == nil or st.current == 'login' or wanted == 'login'
  if not login and now - st.switchedAt < M.MIN_HOLD_MS then return st.current, false end
  if now - st.since >= M.delay(st.current, wanted) then
    st.current, st.pending, st.switchedAt = wanted, nil, now
    return wanted, true
  end
  return st.current, false
end

-- ---------------------------------------------------------------- silence
-- why nothing plays now, or nil when the music should sound
-- env: {enabled, gain, audio (client switch), visible (window), focused, background (mute when not focused), file}
function M.silentReason(env)
  if not env.enabled then return 'off' end
  if (env.gain or 0) <= 0 then return 'volume' end
  if env.audio == false then return 'audio' end
  if env.visible == false then return 'hidden' end
  if env.background and env.focused == false then return 'unfocused' end
  if env.file == false then return 'file' end
  return nil
end
