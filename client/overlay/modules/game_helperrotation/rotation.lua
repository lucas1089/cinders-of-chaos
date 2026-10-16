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
R.CAST_MS = { [206] = 1500, [213] = 1500, [219] = 1000, [225] = 1000 }

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
