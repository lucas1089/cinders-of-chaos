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

-- "Teeming: +30% monster packs" (name and text of a modifier; either alone when the other is missing)
function RiftMath.modLine(m)
  if type(m) ~= 'table' then return '' end
  local name, text = tostring(m.name or ''), tostring(m.text or '')
  if name ~= '' and text ~= '' then return name .. ': ' .. text end
  return name ~= '' and name or text
end

-- colour of the clock: gold, orange under a minute, red under 20 s
function RiftMath.clockColor(left)
  if left <= 20 then return '#ff4030' end
  if left <= 60 then return '#ff9a30' end
  return '#f4d27a'
end

return RiftMath
