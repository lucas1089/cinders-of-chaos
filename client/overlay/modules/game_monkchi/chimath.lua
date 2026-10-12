-- Pure helpers of the Monk chi HUD (no engine calls, unit tested by chimath_test.lua).
ChiMath = {}

-- Monk line vocation ids (server ids; the client maps the class byte back to them, base patch 0016)
ChiMath.MONK_VOCATIONS = { [17] = true, [18] = true, [19] = true }

-- "chi:<chi>:<max>:<decaySec>" -> {chi, max, decay}, or nil for anything else. max 0 means: hide the HUD.
function ChiMath.parse(buffer)
  if type(buffer) ~= 'string' then return nil end
  local chi, max, decay = buffer:match('^chi:(%d+):(%d+):(%d+)$')
  if not chi then return nil end
  chi, max, decay = tonumber(chi), tonumber(max), tonumber(decay)
  if chi > max then chi = max end
  return { chi = chi, max = max, decay = decay }
end

-- chi shown at `now` (seconds) for a state received at `receivedAt`: the server drops chi that was not touched for
-- `decay` seconds, so the HUD empties itself at the same time
function ChiMath.shown(state, receivedAt, now)
  if not state or state.max <= 0 then return 0 end
  if state.decay > 0 and (now - receivedAt) >= state.decay then return 0 end
  return state.chi
end

-- the look of pip i (1-based): 'full', 'empty' or 'hidden' (pips beyond max)
function ChiMath.pip(i, chi, max)
  if i > (max or 0) then return 'hidden' end
  return i <= (chi or 0) and 'full' or 'empty'
end

-- seconds until the chi fades (nil when nothing fades)
function ChiMath.fadeIn(state, receivedAt, now)
  if not state or state.chi <= 0 or state.decay <= 0 then return nil end
  return math.max(0, state.decay - (now - receivedAt))
end

function ChiMath.isMonk(vocationId)
  return ChiMath.MONK_VOCATIONS[tonumber(vocationId) or 0] == true
end

return ChiMath
