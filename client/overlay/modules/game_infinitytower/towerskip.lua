-- Pure part of the "Next floor now" button of game_infinitytower (towerskip_test.lua): what the button shows for the
-- state the server pushes (opcode 214, action "state": inRun, canSkip, floor, nextBoss, isLeader). The server decides
-- (infinitytower_run.lua ChaosTowerRun.skip); the button only follows its flag.
TowerSkip = {}
local M = TowerSkip

M.HOTKEY = 'Ctrl+Shift+N'
M.MIN_PRESS_MS = 1000 -- the client does not send two presses closer than this (the server limits as well)

-- { visible, enabled, key, tip } ; key and tip are tr() keys (the caller translates them)
function M.view(state)
  if type(state) ~= 'table' or not state.inRun then
    return { visible = false, enabled = false, key = 'Next floor now', tip = 'Start the next floor at once instead of waiting.' }
  end
  if state.canSkip then
    return { visible = true, enabled = true, key = 'Next floor now', tip = 'Start the next floor at once instead of waiting.' }
  end
  local tip = 'Available when the floor is cleared.'
  if state.isLeader == false then
    tip = 'Only the run leader can call the next floor.'
  elseif state.nextBoss then
    tip = 'A boss floor is next: it starts by itself.'
  end
  return { visible = true, enabled = false, key = 'Next floor now', tip = tip }
end

-- may a press be sent now? (true when the button is enabled and the last press is old enough)
function M.canPress(state, nowMs, lastMs)
  if not M.view(state).enabled then return false end
  return lastMs == nil or (nowMs - lastMs) >= M.MIN_PRESS_MS
end

M.AUTO_GAP_MS = 2000 -- the server lets a run skip once every 2 s: auto never sends closer than this

-- Auto "Next floor now": send one skip for a state that arrives with inRun and canSkip while the box is ticked.
-- `lastSentAt` is the clock (ms) of the last skip sent, nil if none. The caller calls it once per state pushed, so a
-- refusal (the server pushes canSkip false) ends the attempt and the client waits for the next allowed state.
-- Boss floors are not special-cased: the server sends canSkip false there.
function M.shouldAutoSkip(state, autoOn, lastSentAt, now)
  if not autoOn then return false end
  if type(state) ~= 'table' or not state.inRun or not state.canSkip then return false end
  if lastSentAt ~= nil and (now - lastSentAt) < M.AUTO_GAP_MS then return false end
  return true
end

-- The tower panel (O274): { floor = {key, n}, cleared = {key, n}, monsters = {key, left, total} | nil,
-- timer = {key, secs} | nil, boss = bool }. `elapsedMs` is the time since the state arrived: the countdowns run on the
-- client's clock from the seconds the server sent.
function M.panel(state, elapsedMs)
  if type(state) ~= 'table' or not state.inRun then return nil end
  local out = { boss = state.boss == true }
  local floorNo = tonumber(state.floor) or 0
  if floorNo <= 0 then
    out.floor = { key = 'Get ready', n = 0 }
  else
    out.floor = { key = out.boss and 'Floor %d (boss)' or 'Floor %d', n = floorNo }
  end
  out.cleared = { key = 'Floors cleared: %d', n = tonumber(state.cleared) or 0 }
  local el = math.max(0, tonumber(elapsedMs) or 0) / 1000
  if state.waiting then
    local left = math.max(0, math.ceil((tonumber(state.nextIn) or 0) - el))
    out.timer = { key = 'Next floor in %ds', secs = left }
  else
    out.monsters = { key = 'Monsters left: %d of %d', left = tonumber(state.remaining) or 0, total = tonumber(state.total) or 0 }
    if state.floorLeft then
      out.timer = { key = 'Floor time left: %s', secs = math.max(0, math.ceil(state.floorLeft - el)) }
    end
  end
  return out
end

-- 125 -> "2:05"
function M.clock(secs)
  secs = math.max(0, math.floor(tonumber(secs) or 0))
  return string.format('%d:%02d', math.floor(secs / 60), secs % 60)
end
