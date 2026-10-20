-- luajit rotation_test.lua && lua5.3 rotation_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'rotation.lua')
local R = ChaosHelperRotation
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(c, what) eq(not not c, true, what) end

-- groups in both forms
eq(table.concat(R.groupList({ [1] = 2000, [8] = 30000 }), ','), '1,8', 'group table')
eq(table.concat(R.groupList(2), ','), '2', 'rune group number')
eq(#R.groupList(nil), 0, 'no groups')

-- confirm, hold, refuse, back off
local st = R.new()
eq(R.blocked(st, 10, { [1] = 2000 }, 0), nil, 'free')
R.cast(st, 10, { [1] = 2000 }, 0)
eq(R.blocked(st, 10, { [1] = 2000 }, 50), 'pending', 'own cast waits')
eq(R.blocked(st, 11, { [1] = 2000 }, 50), 'group', 'group held')
eq(R.blocked(st, 12, { [3] = 2000 }, 50), nil, 'other group free')
eq(R.blocked(st, 11, { [1] = 2000 }, 50, false), nil, 'healing does not hold the group')
R.confirmSpell(st, 10, 80)
eq(st.rtt, 80, 'round trip measured')
eq(R.blocked(st, 11, { [1] = 2000 }, 90), nil, 'free after the answer')
R.cast(st, 11, { [1] = 2000 }, 100)
eq(R.blocked(st, 20, { [1] = 2000 }, 100 + 2 * 80 + 99), 'group', 'held for two round trips')
eq(R.blocked(st, 20, { [1] = 2000 }, 100 + 2 * 80 + 100), nil, 'then the group is free again')
-- no answer: refused, 2 s back-off, doubled, capped
eq(R.blocked(st, 11, { [1] = 2000 }, 1299), 'pending', 'still waiting')
eq(R.blocked(st, 11, { [1] = 2000 }, 1300), 'backoff', 'refused after 1.2 s')
eq(st.backoff[11], 3300, 'first back-off 2 s')
eq(R.blocked(st, 11, { [1] = 2000 }, 3300), nil, 'free after the back-off')
R.cast(st, 11, { [1] = 2000 }, 3300)
R.expire(st, 4500)
eq(st.backoff[11], 4500 + 4000, 'second refusal 4 s')
for i = 1, 5 do
  R.cast(st, 11, { [1] = 2000 }, 10000 * i)
  R.expire(st, 10000 * i + 1200)
end
eq(st.backoff[11] - (50000 + 1200), 16000, 'back-off capped at 16 s')
R.confirmSpell(st, 11, 60000)
eq(st.backoff[11], nil, 'an answer ends the back-off')
eq(st.fails[11], nil, 'and the count')
-- a group packet confirms the casts of that group
R.cast(st, 30, { [2] = 1000 }, 70000)
R.confirmGroup(st, 2, 70100)
eq(st.pending[30], nil, 'group packet confirms')
-- a slow line: the confirm window grows with the round trip
local slow = R.new()
slow.rtt = 900
R.cast(slow, 5, { [1] = 2000 }, 0)
eq(R.blocked(slow, 5, { [1] = 2000 }, 1300), 'pending', '3 round trips on a slow line')
eq(R.blocked(slow, 6, { [1] = 2000 }, 1199), 'group', 'hold capped at 1.2 s')
eq(R.blocked(slow, 6, { [1] = 2000 }, 1200), nil, 'hold ends at 1.2 s')

-- castable: level, mana, spells the server does not have
ok(R.castable({ level = 300, mana = 160 }, 300, 160), 'level and mana met')
eq(R.castable({ level = 300, mana = 160 }, 299, 5000), false, 'level too low')
-- a Monk finisher waits for its chi (game_monkchi); unknown chi (no HUD state) does not block
eq(R.castable({ id = 64, level = 30, mana = 80 }, 300, 5000, 3), false, 'Sundering Palm at 3 chi waits')
eq(R.castable({ id = 64, level = 30, mana = 80 }, 300, 5000, 4), true, 'Sundering Palm at 4 chi')
eq(R.castable({ id = 66, level = 40, mana = 100 }, 300, 5000, 1), true, 'Kindled Breath at 1 chi')
eq(R.castable({ id = 66, level = 40, mana = 100 }, 300, 5000, 0), false, 'Kindled Breath without chi')
eq(R.castable({ id = 64, level = 30, mana = 80 }, 300, 5000), true, 'chi unknown: the server decides')
eq(R.castable({ id = 63, level = 15, mana = 30 }, 300, 5000, 0), true, 'Ashen Fist needs no chi')
eq(R.castable({ level = 30, mana = 160 }, 400, 159), false, 'mana too low')
eq(R.castable({ level = 1, mana = 0, notOnServer = true }, 400, 100), false, 'not on the server')
ok(R.castable({ level = 30, mana = 10 }, 0, 100), 'level unknown')

-- self area: attack, no target, no range, no area table
ok(R.isSelfArea({ group = { [1] = 2000 }, range = 0, needTarget = false }), 'Reaping Gyre')
eq(R.isSelfArea({ group = { [1] = 2000 }, range = 5, needTarget = true }), false, 'Witchfire Bolt')
eq(R.isSelfArea({ group = { [1] = 2000 }, range = 0, area = {} }), false, 'stock wave')
eq(R.isSelfArea({ group = { [3] = 2000 }, range = 0 }), false, 'support')
local mons = { { position = { x = 102, y = 100, z = 7 }, hasSightClear = true },
  { position = { x = 105, y = 100, z = 7 }, hasSightClear = true },
  { position = { x = 101, y = 101, z = 6 }, hasSightClear = true },
  { position = { x = 99, y = 99, z = 7 }, hasSightClear = false } }
eq(R.countNear(mons, { x = 100, y = 100, z = 7 }, 3), 1, 'monsters near, same floor, in sight')
eq(R.countNear({}, { x = 100, y = 100, z = 7 }, 3), 0, 'none')

-- cast-time spells: nothing else while one charges
local ch = R.new()
R.cast(ch, 225, { [1] = 2000 }, 1000)
eq(R.channeling(ch, 1000 + 1000 + 1199), true, 'Colossus Fall charges (1 s + hold)')
eq(R.channeling(ch, 1000 + 1000 + 1200), false, 'then not')
R.cast(ch, 220, { [1] = 2000 }, 9000)
eq(R.channeling(ch, 9001), false, 'an instant does not charge')
-- the list against the server scripts (ChaosCasting.spell{ spellId = ..., ms = ... }), when the repo is there
local root = dir .. '../../../../server/data/spells/chaos/'
local okPopen, pipe = pcall(io.popen, 'grep -rl "ChaosCasting.spell" "' .. root .. '" 2>/dev/null')
if okPopen and pipe then
  local found = 0
  for path in pipe:lines() do
    local f = io.open(path)
    local text = f and f:read('*a') or ''
    if f then f:close() end
    local id, ms = text:match('spellId%s*=%s*(%d+)%s*,%s*ms%s*=%s*(%d+)')
    if id then
      found = found + 1
      eq(R.CAST_MS[tonumber(id)], tonumber(ms), 'cast time of spell ' .. id .. ' (' .. path:match('[^/]+$') .. ')')
    end
  end
  pipe:close()
  if found > 0 then
    local n = 0
    for _ in pairs(R.CAST_MS) do n = n + 1 end
    eq(n, found, 'every cast-time spell of the server is listed')
  end
end

-- A rotation against a server model: the shooter's loop (priority order, client cooldowns from the server's packets,
-- the 200 ms pre-cooldown) every 50 ms, the server answering after a round trip. Spell 1 is above the character's level
-- on the server, but the client does not know (level 0 in its entry, like the stock ascension entries had).
local function simulate(useRotation, rtt, stallAt, stallMs)
  local spells = {
    { id = 1, group = { [1] = 2000 }, cd = 10000, serverLevel = 999 },
    { id = 2, group = { [1] = 2000 }, cd = 6000 },
    { id = 3, group = { [1] = 2000 }, cd = 4000 },
    { id = 4, group = { [3] = 2000 }, cd = 20000 },
  }
  local level = 500
  local clientSpell, clientGroup = {}, {}
  local serverSpell, serverGroup = {}, {}
  local inbox = {} -- {at, kind, id, ms}
  local rot = R.new()
  local log = { sent = 0, exhausted = 0, refused = 0, ok = {}, sendTimes = {} }
  local function receive(now)
    local keep = {}
    for _, m in ipairs(inbox) do
      if m.at <= now then
        if m.kind == 'spell' then
          clientSpell[m.id] = now + m.ms
          R.confirmSpell(rot, m.id, now)
        else
          clientGroup[m.id] = now + m.ms
          R.confirmGroup(rot, m.id, now)
        end
      else
        keep[#keep + 1] = m
      end
    end
    inbox = keep
  end
  local function serverCast(s, t)
    log.sent = log.sent + 1
    log.sendTimes[#log.sendTimes + 1] = t
    local arrive = t + rtt / 2
    if s.serverLevel and level < s.serverLevel then
      log.refused = log.refused + 1
      return
    end
    if (serverSpell[s.id] or 0) > arrive then
      log.exhausted = log.exhausted + 1
      return
    end
    for g in pairs(s.group) do
      if (serverGroup[g] or 0) > arrive then
        log.exhausted = log.exhausted + 1
        return
      end
    end
    serverSpell[s.id] = arrive + s.cd
    inbox[#inbox + 1] = { at = arrive + rtt / 2, kind = 'spell', id = s.id, ms = s.cd }
    for g, ms in pairs(s.group) do
      serverGroup[g] = arrive + ms
      inbox[#inbox + 1] = { at = arrive + rtt / 2, kind = 'group', id = g, ms = ms }
    end
    log.ok[s.id] = (log.ok[s.id] or 0) + 1
  end
  local now = 0
  while now < 120000 do
    if stallAt and now >= stallAt and now < stallAt + stallMs then
      now = stallAt + stallMs -- the client froze: one tick after it (base-patch 0026: no replay of missed cycles)
    end
    receive(now)
    for _, s in ipairs(spells) do
      local busy = (clientSpell[s.id] or 0) >= now
      for g in pairs(s.group) do
        busy = busy or (clientGroup[g] or 0) >= now
      end
      if not busy and (not useRotation or not R.blocked(rot, s.id, s.group, now)) then
        serverCast(s, now)
        if useRotation then
          R.cast(rot, s.id, s.group, now)
        end
        clientSpell[s.id] = now + 200
        for g in pairs(s.group) do
          clientGroup[g] = now + 200
        end
      end
    end
    now = now + 50
  end
  return log
end

local old = simulate(false, 100)
eq(old.ok[2] or 0, 0, 'old helper: stuck on the refused spell, spell 2 never cast')
eq(old.ok[3] or 0, 0, 'old helper: spell 3 never cast')
ok(old.refused > 400, 'old helper: the refused spell five times a second (' .. old.refused .. ')')

local new = simulate(true, 100)
ok((new.ok[2] or 0) >= 15, 'rotation goes on: spell 2 cast ' .. tostring(new.ok[2]))
ok((new.ok[3] or 0) >= 15, 'rotation goes on: spell 3 cast ' .. tostring(new.ok[3]))
ok((new.ok[4] or 0) >= 5, 'support spell on its cooldown ' .. tostring(new.ok[4]))
eq(new.exhausted, 0, 'no "You are exhausted" at 100 ms')
ok(new.refused <= 12, 'the refused spell backs off (' .. new.refused .. ' tries in 2 minutes)')

-- a 400 ms round trip: the old 200 ms pre-cooldown ran out before the server's answer
local oldSlow = simulate(false, 400)
local newSlow = simulate(true, 400)
ok(oldSlow.exhausted > 0, 'old helper on a 400 ms line: exhausted ' .. oldSlow.exhausted)
eq(newSlow.exhausted, 0, 'no "You are exhausted" at 400 ms')
ok((newSlow.ok[2] or 0) >= 10, 'rotation goes on at 400 ms')

-- a 2.5 s client stall: no burst afterwards, the rotation goes on
local stalled = simulate(true, 100, 30000, 2500)
local burst = 0
for i = 2, #stalled.sendTimes do
  if stalled.sendTimes[i] - stalled.sendTimes[i - 1] < 50 then
    burst = burst + 1
  end
end
ok(burst <= 40, 'no burst of casts (two groups may fire in one tick): ' .. burst)
eq(stalled.exhausted, 0, 'no exhausted after a stall')
ok((stalled.ok[2] or 0) >= 15, 'rotation goes on after a stall')

-- a spell held for a long time writes one line to the client log (and a free spell none)
do
  local lines = {}
  local oldLog = R.log
  R.log = function(text) lines[#lines + 1] = text end
  local st = R.new()
  for t = 0, 4900, 100 do
    st.backoff[9] = 999999
    R.blocked(st, 9, { [1] = 2000 }, t)
  end
  eq(#lines, 0, 'no stuck line before 5 s')
  R.blocked(st, 9, { [1] = 2000 }, 5000)
  eq(#lines, 1, 'one stuck line at 5 s')
  ok(lines[1]:find('spell 9 held') and lines[1]:find('backoff'), 'the line names the spell and the reason: ' .. tostring(lines[1]))
  for t = 5100, 14900, 100 do
    st.backoff[9] = 999999
    R.blocked(st, 9, { [1] = 2000 }, t)
  end
  eq(#lines, 1, 'no second line within 10 s')
  R.blocked(st, 9, { [1] = 2000 }, 15000)
  eq(#lines, 2, 'a second line after 10 s')
  st.backoff[9] = nil
  eq(R.blocked(st, 9, { [1] = 2000 }, 15100), nil, 'free again')
  eq(st.held[9], nil, 'a free spell clears the watch')
  R.log = oldLog
end

-- auto turn (base patch 0080): wave and beam spells face the target
do
  local N, E, S, W = R.DIR.North, R.DIR.East, R.DIR.South, R.DIR.West
  local WAVE5, BEAM7, CIRCLE = { 'w' }, { 'b' }, { 'c' }
  local areas = { AREA_SQUAREWAVE5 = WAVE5, AREA_BEAM7 = BEAM7, AREA_CIRCLE3X3 = CIRCLE }
  local wave = { id = 240, directional = true, area = WAVE5, needTarget = false }
  local sweep = { id = 271, area = WAVE5, needTarget = false }            -- Lesser Front Sweep: the area, no flag
  local circle = { id = 5, area = CIRCLE, needTarget = false }
  local bolt = { id = 6, directional = true, needTarget = true }
  ok(R.isDirectional(wave, areas), 'a flagged wave is directional')
  ok(R.isDirectional(sweep, areas), 'a wave area without the flag is directional')
  ok(not R.isDirectional(circle, areas), 'a circle is not')
  ok(not R.isDirectional(bolt, areas), 'a spell aimed by its target is not')
  ok(not R.isDirectional(sweep, nil), 'no area table: only the flag counts')
  ok(not R.isDirectional(nil, areas), 'no spell')
  ok(R.isDirectional({ area = BEAM7 }, areas), 'a beam area is directional')
  local from = { x = 100, y = 100, z = 7 }
  local function turn(spell, facing, target, best, enabled)
    return R.turnDirection(spell, areas, { enabled = enabled, facing = facing, from = from, target = target, best = best })
  end
  eq(turn(wave, N, { x = 105, y = 100, z = 7 }, nil, true), E, 'target to the east: face east')
  eq(turn(wave, N, { x = 95, y = 101, z = 7 }, nil, true), W, 'target to the west')
  eq(turn(wave, E, { x = 100, y = 104, z = 7 }, nil, true), S, 'target to the south')
  eq(turn(wave, S, { x = 99, y = 96, z = 7 }, nil, true), N, 'target to the north')
  eq(turn(wave, E, { x = 105, y = 101, z = 7 }, nil, true), nil, 'already facing the target: no turn')
  eq(turn(wave, 5, { x = 105, y = 100, z = 7 }, nil, true), E, 'a diagonal facing is turned to a cardinal one')
  eq(turn(wave, N, { x = 103, y = 103, z = 7 }, nil, true), S, 'exact diagonal, facing neither side: vertical')
  eq(turn(wave, E, { x = 103, y = 103, z = 7 }, nil, true), nil, 'exact diagonal, facing one side: kept')
  eq(turn(wave, N, nil, W, true), W, 'no target: the facing with most monsters')
  eq(turn(wave, W, nil, W, true), nil, 'no target, already that way')
  eq(turn(wave, N, nil, nil, true), nil, 'no target and no count: nothing to turn to')
  eq(turn(wave, N, { x = 105, y = 100, z = 8 }, S, true), S, 'target on another floor: the counted facing')
  eq(turn(wave, N, { x = 100, y = 100, z = 7 }, E, true), E, 'target on our tile: the counted facing')
  eq(turn(wave, N, { x = 105, y = 100, z = 7 }, nil, false), nil, 'option off: never turns')
  eq(turn(wave, N, { x = 105, y = 100, z = 7 }, nil, nil), E, 'option unset in ctx: on')
  eq(turn(circle, N, { x = 105, y = 100, z = 7 }, E, true), nil, 'a circle spell never turns')
  eq(turn(bolt, N, { x = 105, y = 100, z = 7 }, E, true), nil, 'a targeted bolt never turns')
  eq(R.turnDirection(wave, areas, nil), nil, 'no context')
  -- the option: default on, kept in the settings
  local store = {}
  local settings = {
    exists = function(k) return store[k] ~= nil end,
    getBoolean = function(k) return store[k] end,
    set = function(k, v) store[k] = v end,
    save = function() store.saved = true end,
  }
  ok(R.autoTurnEnabled(settings), 'default on')
  ok(R.autoTurnEnabled(nil) == true, 'no settings object: on')
  R.setAutoTurn(false, settings)
  eq(R.autoTurnEnabled(settings), false, 'switched off')
  ok(store.saved, 'saved to disk')
  R.setAutoTurn(true, settings)
  eq(R.autoTurnEnabled(settings), true, 'switched on again')
  -- the generated Chaos entry of a direction="1" spell is directional with the beam area of its script
  dofile(dir .. '../game_chaosspells/spelldata.lua')
  local line
  for _, sp in ipairs(ChaosSpellData) do
    if sp.name == 'Skewering Line' then line = sp end
  end
  ok(line and line.directional == true, 'Skewering Line is generated directional')
  eq(line and line.areaName, 'AREA_BEAM7', 'Skewering Line: the beam area of its script')
  local n = 0
  for _, sp in ipairs(ChaosSpellData) do
    if sp.directional then n = n + 1 end
  end
  eq(n, 1, 'one Chaos spell is directional (server direction="1")')
  -- the base patch calls it before the words go out
  local f = io.open(dir .. '../../../base-patches/0080-helper-auto-turn.patch', 'r')
  ok(f, 'patch 0080 exists')
  if f then
    local patch = f:read('*a'); f:close()
    ok(patch:find('ChaosHelperRotation.turnDirection', 1, true), 'patch 0080 asks turnDirection')
    ok(patch:find('g_game.turn(chaosTurn)', 1, true), 'patch 0080 turns before g_game.talk')
  end
end

if fails > 0 then os.exit(1) end
print('helper rotation tests OK')
