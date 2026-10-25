-- client_chaos_uifade (O223): timing and rules of the window fade. No engine calls here, so uifade_test.lua can run it.
-- A window fades in over CFG.inMs (ease-out) and out over CFG.outMs (a little faster: closing must feel instant). Every
-- function takes the time (ms) as an argument. A fade always starts from the opacity the window has now, so a window
-- opened or closed in the middle of the other fade turns round without a jump, and takes only the time that is left.
UiFadeLogic = {}
local S = UiFadeLogic

S.CFG = {
  inMs = 140,      -- open: 0 -> 1
  outMs = 100,     -- close: 1 -> 0
  minMs = 30,      -- a turn round that has only a sliver left takes at least this
  tickMs = 16,     -- the timer runs at about 60 Hz and only while a fade is up
  steps = 40,      -- the opacity is rounded to 1/40, so the widget is only touched when the picture changes
  minW = 140,      -- smaller than this is a tooltip or a small popup, not a window: no fade
  minH = 80,
}

-- may this window fade? info: on (option), className, topLevel (child of the root or of the game root panel),
-- phantom, noFade (a window sets `chaosNoFade = true` to opt out), w, h (pixels)
function S.eligible(info)
  if type(info) ~= 'table' then return false end
  if info.on ~= true then return false end
  if info.className ~= 'UIWindow' then return false end   -- UIMiniWindow (side panels) and other kinds have their own show
  if info.topLevel ~= true then return false end
  if info.phantom == true or info.noFade == true then return false end
  local w, h = tonumber(info.w), tonumber(info.h)
  if not w or not h then return false end
  return w >= S.CFG.minW and h >= S.CFG.minH
end

local function clamp01(v)
  if v ~= v then return 0 end
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

local function rounded(v)
  local n = S.CFG.steps
  return math.floor(clamp01(v) * n + 0.5) / n
end

-- start a fade. kind 'in' (to 1) or 'out' (to 0); `from` is the opacity now (default 0 for 'in', 1 for 'out').
function S.begin(kind, now, from)
  local C = S.CFG
  local isIn = kind == 'in'
  from = clamp01(tonumber(from) or (isIn and 0 or 1))
  local span = isIn and (1 - from) or from        -- how much of the full range is left to cover
  local ms = (isIn and C.inMs or C.outMs) * span
  if ms < C.minMs then ms = C.minMs end
  return { kind = isIn and 'in' or 'out', t0 = now, ms = ms, from = from, shown = nil }
end

-- the opacity at `now` and whether the fade is over. `changed` is false when the rounded value is the one last given.
function S.step(st, now)
  local t = (now - st.t0) / st.ms
  if t ~= t or t < 0 then t = 0 end
  local to = st.kind == 'in' and 1 or 0
  if t >= 1 then
    local changed = st.shown ~= to
    st.shown = to
    return to, true, changed
  end
  local e
  if st.kind == 'in' then
    e = 1 - (1 - t) * (1 - t) * (1 - t)      -- ease-out cubic: quick start, soft landing
  else
    e = t * t * 0.5 + t * 0.5                  -- between linear and ease-in
  end
  local v = rounded(st.from + (to - st.from) * e)
  local changed = v ~= st.shown
  st.shown = v
  return v, false, changed
end
