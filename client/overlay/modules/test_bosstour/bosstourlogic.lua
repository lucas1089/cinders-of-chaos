-- bosstourlogic.lua: the pure part of the test-only boss fight tour (test_bosstour, boss-video.yml, O689).
-- Which environment arms it, how the staff command `/instances pinnacle` is read (the fight's open / won / over signal), the state machine
-- that decides what the spectator says and when the tour ends. No engine calls: the glue (bosstour.lua) feeds it the server's text lines and a
-- sample of what the client sees, and runs the actions it returns.
ChaosBossTourLogic = {}
local L = ChaosBossTourLogic

L.ENV_ON = 'CHAOS_BOSSTOUR'
L.ENV_ACCOUNT = 'CHAOS_LIVE_ACCOUNT'
L.ENV_PASSWORD = 'CHAOS_LIVE_PASSWORD'
L.ENV_CHARACTER = 'CHAOS_LIVE_CHARACTER'
L.ENV_FOLLOW = 'CHAOS_BOSSTOUR_FOLLOW'     -- the names of the party, comma separated: the spectator goes to one of them
L.ENV_BOSS = 'CHAOS_BOSSTOUR_BOSS'         -- a part of the boss's name (the pinnacle run line of /instances names it)
L.ENV_SECONDS = 'CHAOS_BOSSTOUR_SECONDS'   -- the longest the fight is filmed, from the ready line
L.ENV_WAIT = 'CHAOS_BOSSTOUR_WAIT'         -- the longest the spectator waits for the fight to open (the bots gear up first)

L.DEFAULT_BOSS = 'Malgrath'
L.DEFAULT_SECONDS, L.MIN_SECONDS, L.MAX_SECONDS = 480, 30, 900
L.DEFAULT_WAIT, L.MIN_WAIT, L.MAX_WAIT = 7200, 60, 14400

L.GHOST_SAY = '/ghost'                     -- stock staff command: the spectator is not seen and no monster takes it for a target
L.POLL_SAY = '/instances pinnacle'         -- staff command of instance_limits.lua: one line per running pinnacle fight, then a count
L.GOTO_SAY = '/goto '                      -- stock staff command with a player's name

L.POLL_MS = 3000          -- between two asks of the instance list
L.GOTO_RETRY_MS = 6000    -- between two jumps to a party member
L.FOLLOW_GAP_MS = 4000    -- no party member in sight this long: jump to the next one
L.FOLLOW_NEAR = 6         -- tiles: a member this close is "in sight" (the screen shows 7 and 5 tiles each way)
L.OUTRO_WIN_MS = 9000     -- the boss fell: the spoils and the cheer stay on screen this long
L.OUTRO_END_MS = 6000     -- the fight ended without a kill: the empty arena and the boss stay on screen this long
L.WINDOW = {width = 1280, height = 720}  -- the window the client fills on the virtual screen of boss_video.sh (an even size)

-- the arena grid of pinnacle_config.lua (grid = {origin, cols, slots, spacing}): every arena slot, antechamber included, lies in it. A test holds
-- these numbers to the config.
L.GRID = {x = 11520, y = 10112, z = 7, cols = 4, slots = 8, spacing = 48}

function L.inArena(pos)
  if type(pos) ~= 'table' then return false end
  local g = L.GRID
  local rows = math.ceil(g.slots / g.cols)
  return pos.z == g.z and pos.x >= g.x and pos.x < g.x + g.cols * g.spacing and pos.y >= g.y and pos.y < g.y + rows * g.spacing
end

local function trim(s)
  return (tostring(s):gsub('^%s+', ''):gsub('%s+$', ''))
end

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
  local follow = {}
  for part in (get(L.ENV_FOLLOW) or ''):gmatch('[^,]+') do
    local name = trim(part)
    if name ~= '' then follow[#follow + 1] = name end
  end
  if #follow == 0 then return nil, 'the environment names no party member to follow' end
  local function number(name, default, lo, hi)
    local v = tonumber(get(name))
    if not v then return default end
    return math.max(lo, math.min(hi, math.floor(v)))
  end
  return {
    account = account, password = password, character = get(L.ENV_CHARACTER), follow = follow,
    boss = get(L.ENV_BOSS) or L.DEFAULT_BOSS,
    seconds = number(L.ENV_SECONDS, L.DEFAULT_SECONDS, L.MIN_SECONDS, L.MAX_SECONDS),
    waitSeconds = number(L.ENV_WAIT, L.DEFAULT_WAIT, L.MIN_WAIT, L.MAX_WAIT),
  }
end

-- one text line of the server. The answer of `/instances pinnacle` is one line per running fight,
--   "pinnacle 7, Ascended Malgrath, slot 3, running, 19:58 left, 5 player(s)"   (state: running, success; a failed fight is gone at once)
-- and then a summary, "0 instance(s) running of pinnacle. /instances close ..." (a translation keeps the word "instance(s)" in its stem).
-- -> {kind = 'run', id, boss, slot, state} | {kind = 'summary'} | nil for any other line
function L.parseInstanceLine(text)
  if type(text) ~= 'string' then return nil end
  local id, rest = text:match('^pinnacle (%d+), (.*)$')
  if id then
    local boss, slot, state = rest:match('^(.-), slot (%d+), (%a+)')
    if boss then return {kind = 'run', id = tonumber(id), boss = boss, slot = tonumber(slot), state = state:lower()} end
    return {kind = 'run', id = tonumber(id), boss = rest, slot = 0, state = '?'}
  end
  local low = text:lower()
  if low:find('^%d+ instance%(s%)') or low:find('^%d+ inst.-ncia') then return {kind = 'summary'} end
  return nil
end

function L.bossMatches(cfg, name)
  return type(name) == 'string' and name:lower():find(tostring(cfg.boss):lower(), 1, true) ~= nil
end

function L.new(cfg, now)
  return {cfg = cfg, phase = 'wait', t0 = now, polls = 0, answered = 0, pollAt = nil, run = nil, runPoll = -1, sawRun = false,
          lastState = nil, gotoAt = nil, farAt = nil, idx = 0, fightAt = nil, endAt = nil, endWhy = nil, done = false}
end

-- feed every text line of the server in; returns the parsed line (or nil)
function L.onText(S, text)
  local p = L.parseInstanceLine(text)
  if not p then return nil end
  if p.kind == 'run' then
    if L.bossMatches(S.cfg, p.boss) then
      S.run, S.runPoll, S.sawRun, S.lastState = p, S.polls, true, p.state
    end
  else
    S.answered = S.polls
    if S.runPoll ~= S.polls then S.run = nil end   -- this answer named no fight of the boss: there is none (any more)
  end
  return p
end

local function nextName(S)
  S.idx = S.idx % #S.cfg.follow + 1
  return S.cfg.follow[S.idx]
end

local function finish(S, out, why, ok)
  S.done = true
  out[#out + 1] = {finish = why, ok = ok}
end

-- one look every second or so. s = {now = ms, pos = {x, y, z} or nil, nearest = tiles to the nearest party member in sight, or nil}
-- -> a list of actions: {say = text}, {log = text}, {finish = reason, ok = true | false}
function L.step(S, s)
  local out = {}
  if S.done then return out end
  local now, cfg = s.now, S.cfg
  if S.pollAt == nil or (now - S.pollAt >= L.POLL_MS and (S.answered >= S.polls or now - S.pollAt >= 3 * L.POLL_MS)) then
    S.polls, S.pollAt = S.polls + 1, now
    out[#out + 1] = {say = L.POLL_SAY}
  end
  local inside = L.inArena(s.pos)
  if S.phase == 'wait' then
    if inside then
      S.phase, S.fightAt = 'fight', now
      out[#out + 1] = {log = 'ready'}
    elseif S.run and S.run.state == 'running' then
      if S.gotoAt == nil or now - S.gotoAt >= L.GOTO_RETRY_MS then
        S.gotoAt = now
        out[#out + 1] = {say = L.GOTO_SAY .. nextName(S)}
      end
    elseif S.sawRun and S.run == nil then
      finish(S, out, 'the fight was over before the spectator arrived', false)
    elseif now - S.t0 >= cfg.waitSeconds * 1000 then
      finish(S, out, 'no fight opened in ' .. cfg.waitSeconds .. ' s', false)
    end
    return out
  end
  -- fight
  if now - S.fightAt >= cfg.seconds * 1000 then
    finish(S, out, 'time limit', true)
    return out
  end
  if S.endAt then
    if now >= S.endAt then finish(S, out, S.endWhy, true) end
    return out
  end
  if S.run and S.run.state == 'success' then
    S.endAt, S.endWhy = now + L.OUTRO_WIN_MS, 'boss dead'
    out[#out + 1] = {log = 'fight state success'}
    return out
  end
  if S.run == nil and S.sawRun then
    S.endAt, S.endWhy = now + L.OUTRO_END_MS, (S.lastState == 'success') and 'boss dead' or 'fight over, no kill (the party fell or the clock ran out)'
    out[#out + 1] = {log = 'fight state gone (last ' .. tostring(S.lastState) .. ')'}
    return out
  end
  if S.run and S.run.state ~= 'running' then
    S.endAt, S.endWhy = now + L.OUTRO_END_MS, 'fight over, no kill (' .. tostring(S.run.state) .. ')'
    out[#out + 1] = {log = 'fight state ' .. tostring(S.run.state)}
    return out
  end
  -- follow the party: a member in sight keeps the camera; none for FOLLOW_GAP_MS (or the spectator stands outside the arena: it followed a bot
  -- that was carried out) jumps to the next name
  local near = inside and s.nearest or nil
  if near ~= nil and near <= L.FOLLOW_NEAR then
    S.farAt = nil
  else
    S.farAt = S.farAt or now
    if now - S.farAt >= L.FOLLOW_GAP_MS and (S.gotoAt == nil or now - S.gotoAt >= L.GOTO_RETRY_MS) then
      S.gotoAt, S.farAt = now, nil
      out[#out + 1] = {say = L.GOTO_SAY .. nextName(S)}
    end
  end
  return out
end

-- the length of a tour in the best case, for the workflow's own limit: the ready line to the end of the time limit
function L.maxTourSeconds(cfg)
  return cfg.seconds + math.ceil(L.OUTRO_WIN_MS / 1000)
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
