-- game_chaossound logic (O238; client/MANIFEST.md "Game sound"): which sound an event plays, how loud, and whether it plays
-- at all. No engine calls, so soundlogic_test.lua can run it. Every function that needs the time takes it (ms), and
-- every function that needs luck takes a random function, so the tests are exact.
--
-- The rules, in the order request() applies them:
--   1. the event has a sound set, the master switch and the event's group are on, the volume is above 0
--   2. distance: an event farther than MAX_DIST tiles from the player is skipped; nearer ones fade out with the distance
--   3. gap: one event key does not play again inside its gap (a spray of hits is one sound)
--   4. burst: at most BURST_MAX sounds start inside BURST_MS (a few more for important events), so an area spell on
--      20 monsters plays a few sounds, not 20
--   5. cap: at most MAX_ACTIVE sounds sound at once (by the length of each file); important events may use the
--      HARD_CAP above it
--   6. the variant: one of the set's files, never the one played last (no machine-gun repeat)
ChaosSoundLogic = {}
local S = ChaosSoundLogic

S.DIR = '/modules/game_chaossound/sounds/'

-- the groups the window switches
S.GROUPS = { 'combat', 'spells', 'events', 'ui' }

-- sound sets. files: the names in sounds/ (without .ogg); gain: 0..1 before volume and distance; gap: ms between two of
-- this event; ms: how long the longest file sounds (the cap counts it); prio: 0 quiet fluff .. 5 never missed.
-- The peak of every file is set in client/tools/sfx_sources.csv (hits -8 dBFS, crits -4, spells -8, heal -12, UI -19).
S.SETS = {
  hit      = { group = 'combat', files = { 'hit_1', 'hit_2', 'hit_3' }, gain = 0.55, gap = 90,  ms = 140,  prio = 1 },
  crit     = { group = 'combat', files = { 'crit_1', 'crit_2' },        gain = 0.80, gap = 150, ms = 500,  prio = 3 },
  hurt     = { group = 'combat', files = { 'hurt_1', 'hurt_2' },        gain = 0.60, gap = 350, ms = 400,  prio = 2 },
  dodge    = { group = 'combat', files = { 'dodge_1', 'dodge_2' },      gain = 0.60, gap = 300, ms = 450,  prio = 2 },
  block    = { group = 'combat', files = { 'block_1', 'block_2' },      gain = 0.70, gap = 300, ms = 350,  prio = 2 },
  kill     = { group = 'combat', files = { 'kill_1', 'kill_2' },        gain = 0.55, gap = 250, ms = 500,  prio = 3 },
  fire     = { group = 'spells', files = { 'fire_1', 'fire_2', 'fire_3' },             gain = 0.60, gap = 160, ms = 650, prio = 1 },
  ice      = { group = 'spells', files = { 'ice_1', 'ice_2', 'ice_3' },                gain = 0.60, gap = 160, ms = 210, prio = 1 },
  energy   = { group = 'spells', files = { 'energy_1', 'energy_2', 'energy_3' },       gain = 0.60, gap = 160, ms = 600, prio = 1 },
  holy     = { group = 'spells', files = { 'holy_1', 'holy_2', 'holy_3' },             gain = 0.60, gap = 160, ms = 800, prio = 1 },
  death    = { group = 'spells', files = { 'death_1', 'death_2', 'death_3' },          gain = 0.60, gap = 160, ms = 800, prio = 1 },
  earth    = { group = 'spells', files = { 'earth_1', 'earth_2', 'earth_3' },          gain = 0.60, gap = 160, ms = 600, prio = 1 },
  physical = { group = 'spells', files = { 'physical_1', 'physical_2', 'physical_3' }, gain = 0.70, gap = 160, ms = 480, prio = 1 },
  heal     = { group = 'spells', files = { 'heal_1', 'heal_2', 'heal_3' },             gain = 0.70, gap = 300, ms = 540, prio = 1 },
  levelup     = { group = 'events', files = { 'levelup' },     gain = 0.90, gap = 3000, ms = 1000, prio = 5 },
  loot_rare   = { group = 'events', files = { 'loot_rare' },   gain = 0.70, gap = 400,  ms = 850,  prio = 4 },
  loot_great  = { group = 'events', files = { 'loot_great' },  gain = 0.80, gap = 400,  ms = 850,  prio = 4 },
  loot_unique = { group = 'events', files = { 'loot_unique' }, gain = 0.90, gap = 400,  ms = 900,  prio = 4 },
  goal        = { group = 'events', files = { 'goal' },        gain = 0.80, gap = 800,  ms = 500,  prio = 4 },
  ui_open  = { group = 'ui', files = { 'ui_open' },  gain = 0.50, gap = 120, ms = 150, prio = 0 },
  ui_close = { group = 'ui', files = { 'ui_close' }, gain = 0.50, gap = 120, ms = 150, prio = 0 },
  ui_click = { group = 'ui', files = { 'ui_click' }, gain = 0.50, gap = 60,  ms = 100, prio = 0 },
}

-- the limits
S.MAX_DIST = 9        -- tiles (the biggest of the x and y distance); farther events are skipped
S.NEAR = 1            -- tiles: no fade up to here
S.MIN_FADE = 0.35     -- share of the gain left at MAX_DIST
S.BURST_MS = 400
S.BURST_MAX = 3       -- sounds that start inside BURST_MS
S.BURST_BONUS = 2     -- more for an event of prio IMPORTANT or higher
S.IMPORTANT = 3
S.MAX_ACTIVE = 6      -- sounds sounding at once
S.HARD_CAP = 8        -- an important event may go up to here
S.SECOND_MAX = 10     -- sounds that start inside one second (events below IMPORTANT)

-- ---------------------------------------------------------------- spell themes
-- game_visualfx's VisualFxLogic.EFFECT_THEME (effect id -> theme) is the one table of what an effect is made of; a theme
-- plays the sound set here. Blood, water and the rest play nothing: a stock hit puff or a splash on every blow would be noise.
S.THEME_SOUND = {
  fire = 'fire', frost = 'ice', energy = 'energy', arcane = 'energy', holy = 'holy', death = 'death', shadow = 'death',
  earth = 'earth', poison = 'earth', physical = 'physical', healing = 'heal',
}
-- effects of the player's own tile that are combat feedback, not spells: the stock block hit (3) and the dodge whoosh (416,
-- server/data/spells/effects_catalog.csv). `own`: only on the player's tile (a monster that blocks is not our block).
S.FEEDBACK_EFFECTS = {
  [3]   = { key = 'block', own = true },
  [416] = { key = 'dodge', own = true },
}

-- the event key of a magic effect id, and whether it counts only on the player's own tile; nil when it is silent.
-- themes: the table effect id -> theme (VisualFxLogic.EFFECT_THEME)
function S.effectEvent(effectId, themes)
  local id = tonumber(effectId)
  if not id then return nil end
  local fb = S.FEEDBACK_EFFECTS[id]
  if fb then return fb.key, fb.own end
  local theme = themes and themes[id]
  local key = theme and S.THEME_SOUND[theme]
  if key then return key, false end
  return nil
end

-- ---------------------------------------------------------------- damage numbers
-- Otc::MessageMode as g_map.onImpactText gets it, and the number types of the server (the same as game_visualfx and
-- game_damagescatter; base patch 0100)
S.MODE = { DAMAGE_DEALT = 21, DAMAGE_RECEIVED = 22, DAMAGE_OTHERS = 25 }
S.TYPE = { NORMAL = 0, CRITICAL = 1, CONDITION = 2 }

-- the event of a damage number: your hit landing ('hit', 'crit') or a hit you take ('hurt'); nothing for a burn or poison
-- tick, mana, energy shield, healing, experience or other players' numbers
function S.impactEvent(mode, typeId, value)
  typeId = tonumber(typeId) or 0
  if (tonumber(value) or 0) <= 0 then return nil end
  if typeId ~= S.TYPE.NORMAL and typeId ~= S.TYPE.CRITICAL then return nil end
  if mode == S.MODE.DAMAGE_DEALT then
    return typeId == S.TYPE.CRITICAL and 'crit' or 'hit'
  elseif mode == S.MODE.DAMAGE_RECEIVED then
    return 'hurt'
  end
  return nil
end

-- ---------------------------------------------------------------- kills
-- A kill is a monster that reaches 0 health while you hit it: the creature was hit by you inside KILL_WINDOW ms (a
-- damage-over-time kill a moment after your last hit counts too). Tables of id -> ms are cleaned by prune().
S.KILL_WINDOW = 2500
function S.newHits() return {} end
function S.noteHit(hits, creatureId, now)
  creatureId = tonumber(creatureId) or 0
  if creatureId > 0 then hits[creatureId] = now end
end
function S.isMyKill(hits, creatureId, now)
  local at = hits[tonumber(creatureId) or 0]
  if not at then return false end
  hits[creatureId] = nil
  return now - at <= S.KILL_WINDOW
end
function S.prune(hits, now)
  for id, at in pairs(hits) do
    if now - at > S.KILL_WINDOW then hits[id] = nil end
  end
end

-- ---------------------------------------------------------------- loot
-- rank of a rare-drop line (game_lootfilter drops[].rank: the rarity id, 100 for a unique). Rare (4) and up sound; the
-- loot filter's own rule sound (Hunt > Loot Filter) is the alert for what the player chose, so a drop it already played
-- a sound for stays silent here.
S.LOOT_RARE, S.LOOT_GREAT, S.LOOT_UNIQUE = 4, 5, 100
function S.lootEvent(drops, alerted)
  if alerted or type(drops) ~= 'table' then return nil end
  local best = 0
  for _, d in ipairs(drops) do
    local r = type(d) == 'table' and tonumber(d.rank) or 0
    if r > best then best = r end
  end
  if best >= S.LOOT_UNIQUE then return 'loot_unique' end
  if best >= S.LOOT_GREAT then return 'loot_great' end
  if best >= S.LOOT_RARE then return 'loot_rare' end
  return nil
end

-- ---------------------------------------------------------------- settings
-- saved on this computer (g_settings node chaosSound). The volume is the sound level of the game sounds; the channel gain
-- and the audio switch of the client's own sound options come on top (the engine and chaossound.lua apply them).
S.VOLUMES = { quiet = 0.35, normal = 0.7, loud = 1.0 }
S.VOLUME_ORDER = { 'quiet', 'normal', 'loud' }
S.DEFAULTS = { enabled = true, volume = 'normal', combat = true, spells = true, events = true, ui = false }

local function flag(v, default)
  if type(v) == 'boolean' then return v end
  return default
end

function S.normalize(t)
  local d = S.DEFAULTS
  t = type(t) == 'table' and t or {}
  local volume = S.VOLUMES[t.volume] and t.volume or d.volume
  return { enabled = flag(t.enabled, d.enabled), volume = volume, combat = flag(t.combat, d.combat),
    spells = flag(t.spells, d.spells), events = flag(t.events, d.events), ui = flag(t.ui, d.ui) }
end

-- ---------------------------------------------------------------- mixer
function S.newMixer()
  return { last = {}, active = {}, started = {}, variant = {} }
end

local function prune(m, now)
  local keep = {}
  for _, a in ipairs(m.active) do
    if a.at > now then keep[#keep + 1] = a end
  end
  m.active = keep
  local s = {}
  for _, t in ipairs(m.started) do
    if now - t < 1000 then s[#s + 1] = t end
  end
  m.started = s
end

-- the distance gain 0..1 for a distance in tiles, or nil when the event is too far
function S.distanceGain(dist)
  dist = tonumber(dist) or 0
  if dist > S.MAX_DIST then return nil end
  if dist <= S.NEAR then return 1 end
  local f = (dist - S.NEAR) / (S.MAX_DIST - S.NEAR)
  return 1 - (1 - S.MIN_FADE) * f
end

-- Ask the mixer for an event. now: ms. opts: dist (tiles from the player, default 0), settings (S.normalize), rand
-- (function(n) -> 1..n), volume (0..1 more, default 1: the client's channel gain). Returns path, gain; or nil, reason.
function S.request(m, key, now, opts)
  opts = opts or {}
  local set = S.SETS[key]
  if not set then return nil, 'unknown' end
  local st = opts.settings or S.normalize(nil)
  if not st.enabled or not st[set.group] then return nil, 'off' end
  local level = (S.VOLUMES[st.volume] or 0) * (tonumber(opts.volume) or 1)
  if level <= 0 then return nil, 'mute' end
  local fade = S.distanceGain(opts.dist)
  if not fade then return nil, 'far' end
  if m.last[key] and now - m.last[key] < set.gap then return nil, 'gap' end
  prune(m, now)
  local important = set.prio >= S.IMPORTANT
  local burst = 0
  for _, t in ipairs(m.started) do
    if now - t < S.BURST_MS then burst = burst + 1 end
  end
  if burst >= S.BURST_MAX + (important and S.BURST_BONUS or 0) then return nil, 'burst' end
  if not important and #m.started >= S.SECOND_MAX then return nil, 'second' end
  local cap = important and S.HARD_CAP or S.MAX_ACTIVE
  if #m.active >= cap then return nil, 'cap' end
  -- the variant: never the one before
  local n = #set.files
  local rand = opts.rand or function(k) return math.random(k) end
  local pick = 1
  if n > 1 then
    pick = rand(n - 1)
    if m.variant[key] and pick >= m.variant[key] then pick = pick + 1 end
    if pick > n then pick = n end
  end
  m.variant[key] = pick
  m.last[key] = now
  m.started[#m.started + 1] = now
  m.active[#m.active + 1] = { at = now + set.ms }
  local gain = math.max(0, math.min(1, set.gain * level * fade))
  return S.DIR .. set.files[pick] .. '.ogg', gain
end

-- ---------------------------------------------------------------- live sources
-- The engine ends a sound when its file ends. One that does not (a streamed source whose buffers failed keeps
-- re-asking for data every 100 ms and logs an error each time) would sound and log until the client closes, so every
-- source we start is tracked with a latest end (its length + REAP_SLACK) and stopped when that passes; an ended one is let go.
S.REAP_SLACK = 1500   -- ms past the length of the file
S.MAX_TRACKED = 24    -- sources held; more than the mixer allows at once, so only a stuck run reaches it

function S.track(list, src, now, ms)
  if src == nil then return end
  list[#list + 1] = { src = src, stop = now + (tonumber(ms) or 0) + S.REAP_SLACK }
  while #list > S.MAX_TRACKED do table.remove(list, 1) end
end

-- One pass over the list. A source that ended (alive(src) is false) is dropped, so the engine can free its OpenAL source
-- and buffers; one past its time is dropped and returned for the caller to stop. alive: function(src) -> boolean
-- (default: every source is alive).
function S.reap(list, now, alive)
  local out, keep = {}, {}
  for _, t in ipairs(list) do
    local live = true
    if alive then
      local ok, res = pcall(alive, t.src)
      live = not ok or res ~= false
    end
    if live then
      if now >= t.stop then out[#out + 1] = t.src else keep[#keep + 1] = t end
    end
  end
  for i = #list, 1, -1 do list[i] = nil end
  for _, t in ipairs(keep) do list[#list + 1] = t end
  return out
end

-- tiles between two positions (the biggest of the x and y distance); a different floor is out of reach
function S.distance(a, b)
  if type(a) ~= 'table' or type(b) ~= 'table' then return 0 end
  if a.z ~= b.z then return S.MAX_DIST + 1 end
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- all the file names of the sets (the tests and gen_sfx.py's csv check them)
function S.allFiles()
  local out, seen = {}, {}
  for _, set in pairs(S.SETS) do
    for _, f in ipairs(set.files) do
      if not seen[f] then seen[f] = true; out[#out + 1] = f end
    end
  end
  table.sort(out)
  return out
end
