-- The helper's cast bookkeeping (pure Lua: no engine calls; tests: rotation_test.lua). Base patch 0052 calls it from
-- mods/game_helper (magic shooter, healing) as the global ChaosHelperRotation.
--
-- The helper decided a spell was "cast" the moment it sent the words, put a 200 ms cooldown on the spell and its groups
-- and moved on. Two things went wrong with that on our server:
--   * a cast the server refused (level, mana it counts differently, no target, a corpse or chi it needs, a cooldown the
--     client did not know) sends no cooldown back, so 200 ms later the same spell went out again, for ever: a spell
--     with a higher priority the character could not cast took every turn of its group and the rotation stood still
--     ("You do not have enough level." five times a second);
--   * with a round trip over 200 ms the pre-cooldown ran out before the server's cooldown came back and the next spell
--     of the group went out into the group cooldown ("You are exhausted.").
-- Here a cast waits for the server's answer: the server's cooldown packet for the spell (or one of its groups) confirms
-- it. Until then the spell is not sent again, and its groups are held for about two round trips (measured from the
-- confirmations). No answer within confirmMs (at least 3 round trips) means refused: that spell backs off (2 s, 4 s,
-- 8 s, at most 16 s) and the rest of the rotation goes on. A confirmation ends the back-off at once.

ChaosHelperRotation = ChaosHelperRotation or {}
local R = ChaosHelperRotation

R.defaults = {
  confirmMs = 1200,     -- no answer after this long: refused (raised to 3 round trips on a slow line)
  holdMinMs = 250,      -- a cast holds its groups at least this long ...
  holdMaxMs = 1200,     -- ... and at most this long while it waits for the answer
  backoffMs = 2000,     -- first back-off of a refused spell, doubled per refusal in a row
  backoffMaxMs = 16000,
  selfAreaRadius = 3,   -- a self-centred attack spell without an area table needs a monster this close
  channelHealBelow = 50 -- unused since base patch 0062: a heal never waits for a charging cast (it does not interrupt it)
}

-- Cast-time spells (server data/lib/chaos_casting.lua: ChaosCasting.spell in the spell script, its spellId and ms; the
-- test reads the scripts and checks this list). Another attack spell or rune cast meanwhile interrupts the cast and the
-- server gives the cooldown back: the shooter's next spell cut Colossus Fall off every time, and with its cooldown
-- refunded it took every turn of the attack group again. A heal or a support spell does not interrupt it (server
-- README "Cooldown channels", base patch 0062).
R.CAST_MS = { [206] = 1500, [213] = 1500, [219] = 1000, [225] = 1000, [146] = 2000 }

local function groupList(groups)
  local list = {}
  if type(groups) == "table" then
    for k, v in pairs(groups) do
      if type(k) == "number" and type(v) ~= "boolean" then
        list[#list + 1] = k -- {[group] = cooldown} (the spell table's form)
      elseif v == true then
        list[#list + 1] = k -- a set
      end
    end
  elseif type(groups) == "number" then
    list[1] = groups
  end
  table.sort(list)
  return list
end
R.groupList = groupList

function R.new(cfg)
  local c = {}
  for k, v in pairs(R.defaults) do
    c[k] = (cfg and cfg[k] ~= nil) and cfg[k] or v
  end
  return { cfg = c, pending = {}, fails = {}, backoff = {}, settled = {}, rtt = nil, refused = 0, confirmed = 0 }
end

local function confirmWindow(st)
  local w = st.cfg.confirmMs
  if st.rtt and st.rtt * 3 > w then
    w = st.rtt * 3
  end
  return w
end

local function holdWindow(st)
  local h = st.rtt and (2 * st.rtt + 100) or st.cfg.holdMaxMs
  if h < st.cfg.holdMinMs then
    h = st.cfg.holdMinMs
  end
  if h > st.cfg.holdMaxMs then
    h = st.cfg.holdMaxMs
  end
  return h
end

-- unanswered casts older than the confirm window were refused: back off that spell
function R.expire(st, now)
  local window = confirmWindow(st)
  local refused = nil
  for id, p in pairs(st.pending) do
    if now - p.at >= window then
      st.pending[id] = nil
      local n = (st.fails[id] or 0) + 1
      st.fails[id] = n
      local b = st.cfg.backoffMs * 2 ^ (n - 1)
      if b > st.cfg.backoffMaxMs then
        b = st.cfg.backoffMaxMs
      end
      st.backoff[id] = now + b
      st.refused = st.refused + 1
      refused = refused or {}
      refused[#refused + 1] = id
    end
  end
  return refused
end

-- why `id` may not go out now: "backoff" (refused lately), "pending" (its own cast waits for the answer), "group" (another
-- cast of one of its groups waits for the answer); nil: free. holdGroups = false skips the group rule (healing: a
-- refused big heal must not keep the small one back).
function R.blocked(st, id, groups, now, holdGroups)
  local why = R.blockedWhy(st, id, groups, now, holdGroups)
  R.watch(st, id, why, now)
  return why
end

function R.blockedWhy(st, id, groups, now, holdGroups)
  R.expire(st, now)
  local b = st.backoff[id]
  if b then
    if b > now then
      return "backoff"
    end
    st.backoff[id] = nil
  end
  if st.pending[id] then
    return "pending"
  end
  if holdGroups ~= false then
    local hold = holdWindow(st)
    local mine = groupList(groups)
    for other, p in pairs(st.pending) do
      if other ~= id and now - p.at < hold then
        for _, g in ipairs(mine) do
          if p.groups[g] then
            return "group"
          end
        end
      end
    end
  end
  return nil
end

-- A spell held for a long time (a rotation that seems to use only its first spell): after R.STUCK_MS in a row, one line
-- in the client log says why (backoff: the server refused it, pending: no answer yet, group: another cast of its
-- group waits for an answer), at most one line per spell per R.STUCK_LOG_MS. R.log is replaced in the tests.
R.STUCK_MS = 5000
R.STUCK_LOG_MS = 10000
R.log = function(text)
  if g_logger and g_logger.info then
    g_logger.info(text)
  end
end

function R.watch(st, id, why, now)
  st.held = st.held or {}
  if not why then
    st.held[id] = nil
    return
  end
  local h = st.held[id]
  if not h or h.why ~= why then
    h = { since = now, why = why, logged = nil }
    st.held[id] = h
  end
  if now - h.since >= R.STUCK_MS and (not h.logged or now - h.logged >= R.STUCK_LOG_MS) then
    h.logged = now
    local fails = st.fails and st.fails[id] or 0
    R.log(string.format("[helper] spell %s held %.1f s: %s (refused %d times in a row, round trip %s ms)",
      tostring(id), (now - h.since) / 1000, why, fails, st.rtt and tostring(st.rtt) or "?"))
  end
end

function R.cast(st, id, groups, now)
  local set = {}
  for _, g in ipairs(groupList(groups)) do
    set[g] = true
  end
  st.pending[id] = { at = now, groups = set }
  if R.CAST_MS[id] then
    st.channelUntil = now + R.CAST_MS[id] + holdWindow(st)
  end
end

-- a cast-time spell of ours is still charging (the server's cast bar, game_castbar, says so too once it arrives)
function R.channeling(st, now)
  return st.channelUntil ~= nil and now < st.channelUntil
end

local function settle(st, id, now)
  local p = st.pending[id]
  if p then
    local d = now - p.at
    if d >= 0 then
      st.rtt = st.rtt and math.floor(st.rtt * 0.75 + d * 0.25) or d
    end
    st.confirmed = st.confirmed + 1
    for g in pairs(p.groups) do
      if not st.settled[g] or st.settled[g] < p.at then
        st.settled[g] = p.at
      end
    end
  end
  st.pending[id] = nil
  st.fails[id] = nil
  st.backoff[id] = nil
end

-- the server's cooldown packet for a spell: its cast went through
function R.confirmSpell(st, id, now)
  settle(st, id, now)
end

-- the server's group cooldown packet: it answers one cast, the latest one of that group (a refused cast before it
-- gets no packet of its own); none when the spell packet of that cast came first and already settled it
function R.confirmGroup(st, group, now)
  local window = confirmWindow(st)
  local latest, at = nil, nil
  for id, p in pairs(st.pending) do
    if p.groups[group] and now - p.at < window and (not at or p.at > at) then
      latest, at = id, p.at
    end
  end
  if latest and not (st.settled[group] and st.settled[group] >= at) then
    settle(st, latest, now)
  end
end

-- the Monk line's finishers spend all chi and the server refuses them without any (game_monkchi tells the chi): the
-- attack finishers wait for 4 (the measured rotation, server/tools/rotation_sim.py), Kindled Breath and Chi Ward for 1.
-- A refused finisher cost the next spell a confirm window (about 0.3 s over the 2 s rhythm, rotation live check).
R.FINISHER_CHI = { [64] = 4, [65] = 4, [69] = 4, [71] = 4, [66] = 1, [70] = 1 }

function R.currentChi()
  local m = modules and modules.game_monkchi
  if m and m.currentChi then
    local ok, chi = pcall(m.currentChi)
    if ok then
      return chi
    end
  end
  return nil
end

-- a spell the client can tell it cannot cast: level and mana (the server's numbers, game_chaosspells/spellfix.lua), the
-- entries of spells the server does not have and a Monk finisher without its chi (chi: the known chi, nil = unknown)
function R.castable(spell, level, mana, chi)
  if not spell or spell.notOnServer then
    return false
  end
  local chiNeed = spell.id and R.FINISHER_CHI[spell.id]
  if chiNeed then
    if chi == nil then
      chi = R.currentChi()
    end
    if chi ~= nil and chi < chiNeed then
      return false
    end
  end
  local need = tonumber(spell.level) or 0
  if need > 0 and level and level > 0 and level < need then
    return false
  end
  local cost = tonumber(spell.mana) or 0
  if cost > 0 and mana and mana < cost then
    return false
  end
  return true
end

-- an attack spell centred on the caster that the client has no area for (the Chaos spells: Reaping Gyre, Blightswarm,
-- Doomtide, ...): the shooter counted it as hitting one monster even with none around and cast it into empty air
function R.isSelfArea(spell)
  if not spell or spell.area or spell.needTarget then
    return false
  end
  if (tonumber(spell.range) or 0) > 0 then
    return false
  end
  return type(spell.group) == "table" and spell.group[1] ~= nil
end

-- monsters (entries {position = {x, y, z}, hasSightClear = bool}) within radius of pos on its floor and in sight
function R.countNear(entries, pos, radius)
  local n = 0
  for _, e in ipairs(entries or {}) do
    local p = e.position
    if p and p.z == pos.z and e.hasSightClear ~= false and
        math.max(math.abs(p.x - pos.x), math.abs(p.y - pos.y)) <= radius then
      n = n + 1
    end
  end
  return n
end

-- ------------------------------------------------------------------------------------------------ auto turn
-- A wave or beam spell hits along the caster's facing. The shooter counted monsters for the best facing but only turned
-- for the one stock spell flagged aimAtTarget, so every other wave / beam (Great Fire Wave, Energy Beam, Ice Wave, the
-- Warrior's sweeps, Skewering Line, ...) went out wherever the character happened to look (owner report 2026-10-17:
-- "turn on auto turn to use wave spells"). Base patch 0080 asks R.turnDirection before the words go out: with a target the
-- character faces it, without one the facing with most monsters (the shooter's own count). Option "Auto turn" (default on)
-- in the Targeting & Spell Rules panel, kept in g_settings under R.AUTOTURN_KEY.
R.AUTOTURN_KEY = "chaosHelperAutoTurn"
R.DIR = { North = 0, East = 1, South = 2, West = 3 } -- the client's Directions

local function settingsOf(settings)
  return settings or rawget(_G, "g_settings")
end

-- the option: on unless the player switched it off
function R.autoTurnEnabled(settings)
  local s = settingsOf(settings)
  if not s then
    return true
  end
  local okHas, has = pcall(s.exists, R.AUTOTURN_KEY)
  if not (okHas and has) then
    return true
  end
  local ok, v = pcall(s.getBoolean, R.AUTOTURN_KEY)
  if not ok then
    return true
  end
  return v ~= false
end

function R.setAutoTurn(on, settings)
  local s = settingsOf(settings)
  if s then
    pcall(s.set, R.AUTOTURN_KEY, on == true)
    if s.save then
      pcall(s.save)
    end
  end
end

-- a spell that hits along the caster's facing: flagged directional (the stock wave and beam entries, the generated Chaos
-- entries of a direction="1" spell) or with one of the gamelib's wave / beam areas (SpellAreas: the *WAVE* and *BEAM*
-- keys; Lesser Front Sweep has the area but no flag). A spell that needs a target is aimed by that target, not by facing.
function R.isDirectional(spell, areas)
  if type(spell) ~= "table" or spell.needTarget then
    return false
  end
  if spell.directional == true then
    return true
  end
  if type(areas) == "table" and type(spell.area) == "table" then
    for name, area in pairs(areas) do
      if area == spell.area and type(name) == "string" and (name:find("WAVE", 1, true) or name:find("BEAM", 1, true)) then
        return true
      end
    end
  end
  return false
end

-- the cardinal facing from one position toward another (nil: same tile or another floor). A diagonal keeps the current
-- facing when it is one of the two sides (a wave covers both), else the vertical one.
function R.dirToward(from, to, facing)
  if type(from) ~= "table" or type(to) ~= "table" or from.z ~= to.z then
    return nil
  end
  local dx, dy = to.x - from.x, to.y - from.y
  if dx == 0 and dy == 0 then
    return nil
  end
  local horizontal = dx > 0 and R.DIR.East or R.DIR.West
  local vertical = dy > 0 and R.DIR.South or R.DIR.North
  if dx == 0 then
    return vertical
  elseif dy == 0 then
    return horizontal
  end
  if math.abs(dx) > math.abs(dy) then
    return horizontal
  elseif math.abs(dy) > math.abs(dx) then
    return vertical
  end
  if facing == horizontal or facing == vertical then
    return facing
  end
  return vertical
end

-- The facing to turn to before casting `spell`, or nil (leave it): the option is off, the spell is not directional, the
-- character already faces that way.
--   ctx.enabled  the option (R.autoTurnEnabled())     ctx.facing  the character's direction (0..3, diagonals 4..7)
--   ctx.from     the character's position             ctx.target  the attacked creature's position (nil: none)
--   ctx.best     the facing with most monsters (the shooter's count), used without a target
function R.turnDirection(spell, areas, ctx)
  if not ctx or ctx.enabled == false or not R.isDirectional(spell, areas) then
    return nil
  end
  local want = ctx.target and R.dirToward(ctx.from, ctx.target, ctx.facing) or nil
  if want == nil then
    want = ctx.best
  end
  if want == nil or want == ctx.facing then
    return nil
  end
  return want
end
