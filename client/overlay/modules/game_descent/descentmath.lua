-- Pure helpers of the Ember Descent window, HUD and boon cards (no client API), tested by descentmath_test.lua.
DescentMath = {}
local M = DescentMath

M.COLORS = {
  text = '#d6c9ae', dim = '#8c8070', gold = '#e8b84a', bright = '#f6cf72', good = '#7fd07f', bad = '#ff6040',
  curse = '#e03a1e', ember = '#ff9a3c'
}

-- room type -> name and colour on the HUD
M.ROOMS = {
  combat = { name = 'Combat', color = '#d6c9ae' },
  elite = { name = 'Elite', color = '#c79bff' },
  treasure = { name = 'Treasure', color = '#f6cf72' },
  shrine = { name = 'Shrine', color = '#7fd0c0' },
  merchant = { name = 'Merchant', color = '#9fd89f' },
  boss = { name = 'Boss', color = '#ff6040' }
}

local ROMAN = { 'I', 'II', 'III', 'IV', 'V' }

-- 75 -> "1:15"; nil and negative -> "0:00"
function M.clock(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  return string.format('%d:%02d', math.floor(seconds / 60), seconds % 60)
end

-- seconds left now, from the value the server sent and the time since it arrived
function M.left(sent, receivedAt, now)
  return math.max(0, (tonumber(sent) or 0) - math.max(0, (now or 0) - (receivedAt or 0)))
end

-- 1234567 -> "1,234,567"
function M.number(n)
  n = math.floor(tonumber(n) or 0)
  local s = tostring(math.abs(n))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  if out:sub(1, 1) == ',' then out = out:sub(2) end
  return (n < 0 and '-' or '') .. out
end

function M.roomName(kind)
  local r = M.ROOMS[kind]
  return r and r.name or tostring(kind or '')
end

function M.roomColor(kind)
  local r = M.ROOMS[kind]
  return r and r.color or M.COLORS.text
end

-- "Room 3 / 10 - Elite"
function M.roomLine(d)
  if type(d) ~= 'table' then return '' end
  return string.format('Room %d / %d - %s', tonumber(d.room) or 0, tonumber(d.rooms) or 0, M.roomName(d.type))
end

-- rooms cleared in percent (the progress bar)
function M.progress(d)
  local rooms = tonumber(d and d.rooms) or 0
  if rooms <= 0 then return 0 end
  return math.min(100, math.floor((tonumber(d.depth) or 0) * 100 / rooms))
end

-- what the room asks of the player now
function M.stateLine(d)
  if type(d) ~= 'table' then return '' end
  local s = d.state
  if s == 'choose' then return 'Room cleared: choose a boon.' end
  if s == 'travel' then return 'The next door opens...' end
  if s == 'done' then return 'The descent is over.' end
  if s == 'rest' then
    if d.ready then return 'Waiting for the party...' end
    if d.type == 'shrine' then return 'Use the altar (health for a boon), then Continue.' end
    if d.type == 'merchant' then return 'Spend your embers at the stand, then Continue.' end
    return 'Continue when you are ready.'
  end
  if d.type == 'boss' then
    return d.bossName and (tostring(d.bossName) .. ' awaits.') or 'The last hall.'
  end
  local left = tonumber(d.monsters) or 0
  local waves = tonumber(d.waves) or 0
  if waves > 0 then
    return string.format('Wave %d / %d - %d monster%s left', math.max(1, tonumber(d.wave) or 0), waves, left,
      left == 1 and '' or 's')
  end
  return string.format('%d monster%s left', left, left == 1 and '' or 's')
end

-- "Embers 120   Rewards +25%"
function M.embersLine(d)
  if type(d) ~= 'table' then return '' end
  local text = 'Embers ' .. M.number(d.embers)
  if (tonumber(d.reward) or 0) > 0 then
    text = text .. string.format('   Rewards +%d%%', tonumber(d.reward))
  end
  if (tonumber(d.ward) or 0) > 0 then
    text = text .. '   Ward ' .. M.number(d.ward)
  end
  return text
end

-- the icon of a boon / curse key ("" for a key that is not a plain name)
function M.icon(key, curse)
  key = tostring(key or '')
  if not key:match('^[%w_]+$') then return '' end
  return '/images/game/buffs/descent_' .. (curse and 'c_' or 'b_') .. key
end

-- "Stack 2 of 3", "" for a boon that does not stack
function M.stacksText(stacks, max)
  stacks, max = tonumber(stacks) or 0, tonumber(max) or 1
  if max <= 1 then return '' end
  return string.format('Stack %d of %d', stacks, max)
end

-- the tooltip of a held boon {n, d, s, m} or curse {n, d, r}
function M.tooltip(b, curse)
  if type(b) ~= 'table' then return '' end
  local head = tostring(b.n or '')
  if curse then
    return head .. ' (curse)\n' .. tostring(b.d or '') .. ((tonumber(b.r) or 0) > 0 and
      string.format('\nRewards +%d%%', tonumber(b.r)) or '')
  end
  local roman = (tonumber(b.m) or 1) > 1 and ROMAN[tonumber(b.s) or 1] or nil
  return head .. (roman and (' ' .. roman) or '') .. '\n' .. tostring(b.d or '')
end

-- the card's title: a boon already held shows the rank it becomes ("Ember Edge II")
function M.cardTitle(c)
  if type(c) ~= 'table' then return '' end
  local next = (tonumber(c.s) or 0) + 1
  if (tonumber(c.m) or 1) > 1 and next > 1 then
    return tostring(c.n or '') .. ' ' .. (ROMAN[next] or tostring(next))
  end
  return tostring(c.n or '')
end

function M.cardNote(c)
  if type(c) ~= 'table' then return '' end
  local have, max = tonumber(c.s) or 0, tonumber(c.m) or 1
  if max <= 1 then return 'Unique boon' end
  if have == 0 then return string.format('New (stacks to %d)', max) end
  return string.format('Held %d of %d', have, max)
end

-- the x of each of `count` cards of width w with gap between them, centred in `width`
function M.cardLayout(count, w, gap, width)
  local xs = {}
  count = math.max(0, math.floor(tonumber(count) or 0))
  local total = count * w + math.max(0, count - 1) * gap
  local x = math.floor((width - total) / 2)
  for i = 1, count do
    xs[i] = x + (i - 1) * (w + gap)
  end
  return xs
end

-- "Take the curse too: Frailty - You take 20% more damage. (+25% rewards, +30 embers)"
function M.curseLine(c)
  if type(c) ~= 'table' then return '' end
  local extra = {}
  if (tonumber(c.r) or 0) > 0 then extra[#extra + 1] = string.format('+%d%% rewards', tonumber(c.r)) end
  if (tonumber(c.e) or 0) > 0 then extra[#extra + 1] = string.format('+%d embers', tonumber(c.e)) end
  return string.format('%s - %s%s', tostring(c.n or ''), tostring(c.d or ''),
    #extra > 0 and (' (' .. table.concat(extra, ', ') .. ')') or '')
end

-- a ware of the merchant: can it be bought and the button text
function M.ware(w, embers)
  if type(w) ~= 'table' then return { can = false, text = '' } end
  local price = tonumber(w.p) or 0
  if w.off then return { can = false, text = 'Not needed', price = price } end
  local can = (tonumber(embers) or 0) >= price
  return { can = can, text = string.format('%d embers', price), price = price }
end

-- the entry window: free runs, sigils, records
function M.infoLines(info)
  if type(info) ~= 'table' then return {} end
  local lines = {}
  local function add(text, color) lines[#lines + 1] = { text = text, color = color or M.COLORS.text } end
  add(string.format('%d-%d rooms, %d minutes, up to %d players. Level %d+.', tonumber(info.rooms and info.rooms[1]) or 8,
    tonumber(info.rooms and info.rooms[2]) or 12, math.floor((tonumber(info.timeLimit) or 0) / 60),
    tonumber(info.maxPlayers) or 4, tonumber(info.minLevel) or 0), M.COLORS.dim)
  if info.freeDaily then
    add('Free descent today: ready', M.COLORS.good)
  else
    add('Free descent today: used (next in ' .. M.hours(info.nextDaily) .. ')', M.COLORS.dim)
  end
  add(info.freeWeekly and 'Free weekly descent: ready' or 'Free weekly descent: used this week',
    info.freeWeekly and M.COLORS.good or M.COLORS.dim)
  add(string.format('%s: %d carried', tostring(info.craft and info.craft.name or 'Ember Sigils'),
    tonumber(info.sigils) or 0), (tonumber(info.sigils) or 0) > 0 and M.COLORS.bright or M.COLORS.dim)
  add(string.format('Best depth: %d%s   Runs: %d   Clears: %d', tonumber(info.best) or 0,
    info.bestClear and ' (conquered)' or '', tonumber(info.runs) or 0, tonumber(info.clears) or 0), M.COLORS.gold)
  add(string.format('This week (seed %s): best depth %d', tostring(info.weekSeed or '?'), tonumber(info.weekBest) or 0),
    M.COLORS.gold)
  return lines
end

-- "4:05 h" style countdown for the next free run: hours and minutes
function M.hours(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  return string.format('%d:%02d h', math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

-- can a sigil be forged, and the line that says what it costs
function M.craft(info)
  local c = type(info) == 'table' and info.craft or nil
  if type(c) ~= 'table' then return { can = false, text = '' } end
  local shards, gold = tonumber(c.shards) or 0, tonumber(c.gold) or 0
  local hs, hg = tonumber(c.haveShards) or 0, tonumber(c.haveGold) or 0
  return { can = hs >= shards and hg >= gold,
    text = string.format('Forge: %d rune shards (%d) and %s gold (%s)', shards, hs, M.number(gold), M.number(hg)) }
end

-- which entry buttons work: {normal, weekly} each {can, text}
function M.entryButtons(info)
  if type(info) ~= 'table' then return { normal = { can = false }, weekly = { can = false } } end
  local sig = tonumber(info.sigils) or 0
  local lvl = (tonumber(info.level) or 0) >= (tonumber(info.minLevel) or 0)
  local function one(free, label)
    if info.inRun then return { can = false, text = label } end
    if not lvl then return { can = false, text = label } end
    if free then return { can = true, text = label .. ' (free)' } end
    if sig > 0 then return { can = true, text = label .. ' (1 sigil)' } end
    return { can = false, text = label }
  end
  return { normal = one(info.freeDaily, 'Descend'), weekly = one(info.freeWeekly, 'Weekly Descent') }
end

M.RESULTS = {
  cleared = { title = 'The Descent is conquered!', color = '#7fd07f' },
  fallen = { title = 'You fell in the Descent.', color = '#ff6040' },
  time = { title = 'The embers burned out.', color = '#ff9a30' },
  left = { title = 'You left the Descent.', color = '#8c8070' },
  logout = { title = 'You left the Descent.', color = '#8c8070' },
  shutdown = { title = 'The Descent closed for a restart.', color = '#8c8070' }
}

-- the end of a run: title, colour and the reward lines
function M.endLines(d)
  if type(d) ~= 'table' then return { title = '', color = M.COLORS.text, lines = {} } end
  local r = M.RESULTS[d.result] or { title = tostring(d.text or ''), color = M.COLORS.text }
  local lines = { string.format('Depth %d of %d%s', tonumber(d.depth) or 0, tonumber(d.rooms) or 0,
    d.weekly and ' (weekly)' or '') }
  if (tonumber(d.gold) or 0) > 0 then lines[#lines + 1] = M.number(d.gold) .. ' gold to your bank' end
  for _, it in ipairs(type(d.items) == 'table' and d.items or {}) do
    lines[#lines + 1] = (it.unique and 'Unique: ' or '') .. ((tonumber(it.count) or 1) > 1 and (it.count .. ' ') or '')
      .. tostring(it.name or '')
  end
  if d.title then lines[#lines + 1] = 'New title: ' .. tostring(d.title) end
  return { title = r.title, color = r.color, lines = lines }
end

-- the party under the HUD: "Name 80%" or "Name (out)"
function M.partyLine(p)
  if type(p) ~= 'table' then return '' end
  if not p.alive then return tostring(p.name or '?') .. ' (out)' end
  return string.format('%s %d%%', tostring(p.name or '?'), tonumber(p.hp) or 0)
end

return M
