-- Pure part of game_monsterbar's boss cast bar (monsterbarmech_test.lua): the next boss mechanic and its timer.
-- The server (boss_mechanics.lua, raid.lua) sends on the monster bar's opcode 125:
--   {action = "mech", data = {cid, boss, label, ms, kind}}
-- kind: telegraph (a marked area hits after ms), channel (kill the totem before ms), soak (stand in the circle), los
-- (hide behind a pillar), interrupted (ms 0: the cast was stopped). The bar shows "Boss: Label" and the seconds left,
-- filling up to the hit; it stays a moment after the hit or the interrupt, then hides.
MonsterBarMech = {}
local M = MonsterBarMech

M.HOLD_MS = 600 -- the bar stays this long after the hit (or the interrupt) so the end can be read

M.COLORS = {
  telegraph = '#c0392b', -- danger: get out of the marks
  channel = '#8e44ad', -- interrupt: kill the totem
  soak = '#2e9e5b', -- stand in the circle
  los = '#2a6fb0', -- hide behind a pillar
  interrupted = '#7d7176'
}

M.HINTS = {
  telegraph = 'move out',
  channel = 'kill the totem',
  soak = 'stand in the circle',
  los = 'hide behind a pillar',
  interrupted = 'interrupted'
}

-- a new cast from a payload at `now` (ms); nil for a payload that is not a cast
function M.start(data, now)
  if type(data) ~= 'table' or type(data.label) ~= 'string' or tonumber(data.ms) == nil then
    return nil
  end
  local kind = M.COLORS[data.kind] and data.kind or 'telegraph'
  local ms = math.max(0, math.floor(tonumber(data.ms)))
  return { cid = tonumber(data.cid), boss = type(data.boss) == 'string' and data.boss or nil, label = data.label,
    kind = kind, startAt = now, endAt = now + ms, ms = ms }
end

-- the state at `now`: progress 0..1, seconds left (one decimal), visible, done
function M.state(cast, now)
  if not cast then
    return { visible = false }
  end
  local left = math.max(0, cast.endAt - now)
  local progress = cast.ms > 0 and math.min(1, (now - cast.startAt) / cast.ms) or 1
  local visible = now <= cast.endAt + M.HOLD_MS
  return { visible = visible, progress = progress, left = left, done = left <= 0 }
end

-- the bar's text: "Kaelgor: Meteor Rain 2.4s", "... - move out" while it runs
function M.text(cast, now)
  local st = M.state(cast, now)
  if not st.visible then
    return ''
  end
  local head = cast.boss and (cast.boss .. ': ' .. cast.label) or cast.label
  if cast.kind == 'interrupted' then
    return head .. ' - interrupted!'
  end
  if st.done then
    return head
  end
  return string.format('%s %.1fs - %s', head, math.floor(st.left / 100 + 0.5) / 10, M.HINTS[cast.kind])
end

-- the fill width of a bar `width` px wide
function M.fillWidth(cast, now, width)
  local st = M.state(cast, now)
  if not st.visible then
    return 0
  end
  if cast.kind == 'interrupted' then
    return width
  end
  return math.floor(width * st.progress + 0.5)
end

-- which cast to show: the newest one still visible; an "interrupted" payload replaces the running cast of its boss
function M.pick(current, incoming, now)
  if not incoming then
    return current
  end
  if incoming.kind == 'interrupted' and current and current.cid == incoming.cid then
    incoming.label = current.label
  end
  return incoming
end
