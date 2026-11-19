-- loottourlogic.lua: the pure part of the test-only loot explosion tour (test_loottour, loot-video.yml, O676).
-- Which environment arms it and the step timeline after the game is entered. No engine calls.
ChaosLootTourLogic = {}
local L = ChaosLootTourLogic

L.ENV_ON = 'CHAOS_LOOTTOUR'
L.ENV_ACCOUNT = 'CHAOS_LIVE_ACCOUNT'
L.ENV_PASSWORD = 'CHAOS_LIVE_PASSWORD'
L.ENV_CHARACTER = 'CHAOS_LIVE_CHARACTER'
L.EXPLODE_SAY = '!tester explode run'

-- milliseconds after the "ready" line, which is when the workflow starts the recording (it needs about a second to
-- begin, so the first step waits GRACE_MS). The video is about 20 s long.
L.GRACE_MS = 3000
L.EXPLODE_GAP_MS = 6000    -- between the two explosions
L.SETTLE_MS = 5500         -- the loot lies there, labels and beams show, before Loot all
L.PICKUP_MS = 4500         -- the backpack fills, the items are gone, before the exit
L.WINDOW = {width = 1280, height = 720}  -- the window the client fills on the virtual screen of loot_video.sh (an even size)
L.WATCHDOG_MS =10 * 60000 -- the client leaves by itself when a step never came (the workflow cuts it first)

-- config from the environment; nil, reason when it is not armed or incomplete. getenv is os.getenv or a fake.
function L.parseEnv(getenv)
  if type(getenv) ~= 'function' then return nil, 'no environment' end
  local function get(name)
    local ok, v = pcall(getenv, name)
    if ok and type(v) == 'string' and v ~= '' then return v end
    return nil
  end
  if get(L.ENV_ON) ~= '1' then return nil, 'off' end
  local account, password = get(L.ENV_ACCOUNT), get(L.ENV_PASSWORD)
  if not account or not password then return nil, 'the environment names no account and password' end
  return {account = account, password = password, character = get(L.ENV_CHARACTER)}
end

-- the steps after the game is entered, in order: {at = ms from ready, do = 'say' | 'lootall' | 'exit', text}
function L.timeline()
  local t = L.GRACE_MS
  local out = {{at = t, ['do'] = 'say', text = L.EXPLODE_SAY}}
  t = t + L.EXPLODE_GAP_MS
  out[#out + 1] = {at = t, ['do'] = 'say', text = L.EXPLODE_SAY}
  t = t + L.SETTLE_MS
  out[#out + 1] = {at = t, ['do'] = 'lootall'}
  t = t + L.PICKUP_MS
  out[#out + 1] = {at = t, ['do'] = 'exit'}
  return out
end

-- total length of the tour from the ready line to the exit
function L.duration()
  local tl = L.timeline()
  return tl[#tl].at
end

-- the index of the character to enter: the one named character, else the first; nil when the list is empty
function L.pickCharacter(names, wanted)
  if type(names) ~= 'table' or #names == 0 then return nil end
  if wanted then
    for i, n in ipairs(names) do
      if tostring(n):lower() == tostring(wanted):lower() then return i end
    end
  end
  return 1
end

return L
