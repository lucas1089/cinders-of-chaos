-- Pure helpers of the rift HUD (no client API), tested by riftmath_test.lua.
RiftMath = {}

-- 75 -> "1:15", 3600 -> "60:00"; negative and nil -> "0:00"
function RiftMath.clock(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  return string.format('%d:%02d', math.floor(seconds / 60), seconds % 60)
end

-- seconds left now, from the value the server sent and the time since it arrived
function RiftMath.left(sent, receivedAt, now)
  return math.max(0, (tonumber(sent) or 0) - math.max(0, (now or 0) - (receivedAt or 0)))
end

-- progress towards the guardian in percent (0..100); 100 once it appeared
function RiftMath.bossPercent(killed, bossAt, boss)
  if boss == 'alive' or boss == 'dead' then return 100 end
  bossAt = tonumber(bossAt) or 0
  if bossAt <= 0 then return 100 end
  return math.min(100, math.floor((tonumber(killed) or 0) * 100 / bossAt))
end

function RiftMath.bossLine(d)
  if d.omen and d.boss == 'waiting' then
    return 'The guardian ' .. tostring(d.bossName or '') .. ' is coming...'
  end
  if d.boss == 'alive' then
    return 'The guardian ' .. tostring(d.bossName or '') .. ' is here!'
  elseif d.boss == 'dead' then
    return 'The guardian is slain.'
  end
  local need = math.max(0, (tonumber(d.bossAt) or 0) - (tonumber(d.killed) or 0))
  return string.format('Guardian in %d kill%s', need, need == 1 and '' or 's')
end

-- "+20% quantity, +10% experience" (empty when there is no bonus)
function RiftMath.bonusLine(b)
  if type(b) ~= 'table' then return '' end
  local parts = {}
  for _, k in ipairs({ 'quantity', 'rarity', 'experience' }) do
    local v = tonumber(b[k]) or 0
    if v > 0 then parts[#parts + 1] = string.format('+%d%% %s', v, k) end
  end
  return table.concat(parts, ', ')
end

local ROMAN = { 'I', 'II', 'III', 'IV', 'V' }

-- 4 -> "IV" (modifier tiers I-V; '' for none)
function RiftMath.roman(t)
  t = tonumber(t)
  return t and ROMAN[t] or ''
end

-- "Teeming III: +30% monster packs" (name with the modifier tier, and the text; either alone when the other is missing)
function RiftMath.modLine(m)
  if type(m) ~= 'table' then return '' end
  local name, text = tostring(m.name or ''), tostring(m.text or '')
  local roman = RiftMath.roman(m.tier)
  if name ~= '' and roman ~= '' then name = name .. ' ' .. roman end
  if name ~= '' and text ~= '' then return name .. ': ' .. text end
  return name ~= '' and name or text
end

-- the colour of a modifier line: gold for a boon, violet for a suffix (players and area), nil (the label's) for a prefix
function RiftMath.modColor(m)
  if type(m) ~= 'table' then return nil end
  if m.boon then return '#e8c060' end
  if m.side == 'suffix' then return '#c9a6ff' end
  return nil
end

-- "Lives: 2 / 4" (shared lives of the run; '' when the server sent none)
function RiftMath.livesLine(lives, max)
  lives, max = tonumber(lives), tonumber(max)
  if not lives then return '' end
  if max and max > 0 then return string.format('Lives: %d / %d', lives, max) end
  return string.format('Lives: %d', lives)
end

-- colour of the lives line: red at the last life, orange below half, else pale green
function RiftMath.livesColor(lives, max)
  lives, max = tonumber(lives) or 0, tonumber(max) or 0
  if lives <= 1 then return '#ff4030' end
  if max > 0 and lives * 2 < max then return '#ff9a30' end
  return '#9fd89f'
end

-- the Rift Atlas's Swift line of a running rift: swift = the tier's Swift time (seconds, from the server), limit = the
-- run's limit, left = seconds left now. Returns the text and its colour: '' when there is no Swift time (an Omen
-- arena, an older server); blue with the time to spare while it can still be made, grey once it is missed.
function RiftMath.swiftLine(swift, limit, left)
  swift, limit, left = tonumber(swift), tonumber(limit), tonumber(left)
  if not swift or swift <= 0 or not limit then return '', nil end
  local elapsed = math.max(0, limit - (left or 0))
  if elapsed <= swift then
    return string.format('Swift: seal within %s (%s to spare)', RiftMath.clock(swift), RiftMath.clock(swift - elapsed)),
      '#7fb8e8'
  end
  return string.format('Swift: missed (%s)', RiftMath.clock(swift)), '#8c8070'
end

-- colour of the clock: gold, orange under a minute, red under 20 s
function RiftMath.clockColor(left)
  if left <= 20 then return '#ff4030' end
  if left <= 60 then return '#ff9a30' end
  return '#f4d27a'
end

return RiftMath
