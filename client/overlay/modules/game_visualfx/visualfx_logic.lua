-- game_visualfx logic (client/MANIFEST.md "Visual effects"): the hit flash, the screen shake and the option values, with no
-- engine calls so visualfx_test.lua can run it. Every function takes the time (ms) and, where it needs luck, a random
-- function, so the tests are exact.
VisualFxLogic = {}
local L = VisualFxLogic

-- the options (client_settings dataset.lua, Options > Graphics "Visual effects"); all on by default
L.OPTIONS = { 'hitFlash', 'screenShake', 'creatureShadow', 'screenGrade' }
L.DEFAULTS = { hitFlash = true, screenShake = true, creatureShadow = true, screenGrade = true }

-- an option value from the settings: a boolean is kept, anything else (nil, junk, an older settings file) is the default
function L.optionOn(name, value)
  if type(value) == 'boolean' then return value end
  return L.DEFAULTS[name] == true
end

-- ---------------------------------------------------------------- hit flash
-- Otc::MessageMode of this client as g_map.onImpactText gets it (same as game_damagescatter's L.MODE)
L.MODE = { DAMAGE_DEALT = 21, DAMAGE_RECEIVED = 22, DAMAGE_OTHERS = 25 }
-- number types of the server (ChaosImpactType): only plain and critical hits flash, a damage-over-time tick does not
-- (it would flicker the creature for the whole burn)
L.TYPE = { NORMAL = 0, CRITICAL = 1 }
L.FLASH = {
  ms = 80,          -- a plain hit
  critMs = 110,     -- a critical hit
  gap = 140,        -- the same creature does not flash again inside this many ms (a spray of hits is one flash)
  maxActive = 8,    -- flashes alive at once on the map: the shader draw is a little dearer than the plain one
  white = 'chaos_hit_white',  -- creatures the player hits, and the others' fights
  red = 'chaos_hit_red',      -- the player is hit
}

function L.newFlasher()
  return { last = {}, ends = {}, n = 0 }
end

local function isDamageMode(mode)
  return mode == L.MODE.DAMAGE_DEALT or mode == L.MODE.DAMAGE_RECEIVED or mode == L.MODE.DAMAGE_OTHERS
end

-- Whether a damage number makes its creature flash. Returns the outfit shader and the milliseconds, or nil.
-- `state` is L.newFlasher(); `mine` tells that the creature is the local player.
function L.flashPlan(state, now, creatureId, mode, typeId, value, mine)
  if not isDamageMode(mode) then return nil end
  typeId = tonumber(typeId) or 0
  if typeId ~= L.TYPE.NORMAL and typeId ~= L.TYPE.CRITICAL then return nil end
  if not creatureId or creatureId == 0 then return nil end
  if (tonumber(value) or 0) <= 0 then return nil end
  local F = L.FLASH
  local last = state.last[creatureId]
  if last and now - last < F.gap then return nil end
  -- drop the flashes that are over, then the cap
  local alive = 0
  for id, at in pairs(state.ends) do
    if at <= now then state.ends[id] = nil else alive = alive + 1 end
  end
  if alive >= F.maxActive then return nil end
  local ms = typeId == L.TYPE.CRITICAL and F.critMs or F.ms
  state.last[creatureId] = now
  state.ends[creatureId] = now + ms
  -- the memory of old creatures does not grow for ever
  state.n = state.n + 1
  if state.n >= 64 then
    state.n = 0
    for id, at in pairs(state.last) do
      if now - at > 2000 then state.last[id] = nil end
    end
  end
  return mine and F.red or F.white, ms
end

-- ---------------------------------------------------------------- screen shake
-- Only the local player's hits shake the view, and only the big ones: a critical hit of at least 3% of the maximum
-- health, or any hit of at least 15% (percent is x100 as the server sends it: 10000 = 100%). A few pixels, short.
L.SHAKE = {
  maxPx = 4,         -- the cap, in 1x sprite pixels (the engine scales it to the sprite size)
  ms = 180,          -- how long it lasts; the strength falls off to nothing
  gap = 300,         -- after a shake, the next one may start this many ms after the last start (a shake that runs is only
                     -- restarted by a stronger hit)
  bigPercent = 1500,
  critPercent = 300,
}

-- the strength (pixels) a received hit asks for, 0 for none
function L.shakeAmp(typeId, percent)
  local S = L.SHAKE
  percent = tonumber(percent) or 0
  typeId = tonumber(typeId) or 0
  if percent <= 0 then return 0 end
  local big = percent >= S.bigPercent
  local crit = typeId == L.TYPE.CRITICAL and percent >= S.critPercent
  if not big and not crit then return 0 end
  local amp = percent >= 5000 and 4 or percent >= 3000 and 3 or 2
  if amp > S.maxPx then amp = S.maxPx end
  return amp
end

function L.newShake()
  return { startAt = 0, endAt = 0, amp = 0, lastAt = -1e9 }
end

-- starts (or strengthens) a shake; true when it started
function L.shakeStart(state, now, amp)
  if not amp or amp <= 0 then return false end
  local S = L.SHAKE
  if amp > S.maxPx then amp = S.maxPx end
  local running = now < state.endAt
  if running and amp <= L.shakeNow(state, now) then return false end
  if not running and now - state.lastAt < S.gap then return false end
  state.startAt, state.endAt, state.amp, state.lastAt = now, now + S.ms, amp, now
  return true
end

-- the strength at this moment (a whole number of pixels, falling off), 0 when over
function L.shakeNow(state, now)
  if now >= state.endAt then return 0 end
  local S = L.SHAKE
  local left = (state.endAt - now) / S.ms
  local mag = math.ceil(state.amp * left)
  if mag > S.maxPx then mag = S.maxPx end
  return mag
end

-- the pixel shift of this frame and whether the shake is over; `rnd()` is a number in [0, 1)
function L.shakeOffset(state, now, rnd)
  local mag = L.shakeNow(state, now)
  if mag <= 0 then return 0, 0, true end
  local function pick()
    local v = math.floor(rnd() * (2 * mag + 1)) - mag
    if v > mag then v = mag elseif v < -mag then v = -mag end
    return v
  end
  local x = pick()
  -- at least one pixel on one axis, so a frame is never a no-op while the shake runs
  local y = pick()
  if x == 0 and y == 0 then x = (rnd() < 0.5) and -mag or mag end
  return x, y, false
end
