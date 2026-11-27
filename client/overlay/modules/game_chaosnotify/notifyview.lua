-- The toast logic of game_chaosnotify without client API (tested by notifyview_test.lua): which toast type a server
-- message kind shows (server data/scripts/chaos/notifications.lua ChaosNotify.send), the height of a toast, and the
-- stack: where each shown toast sits so that several at once never overlap (pinned ones first, then by slot).

ChaosNotifyView = ChaosNotifyView or {}
local V = ChaosNotifyView

-- message kinds ({"action": kind, "message": "title: text"}) -> the toast type of notifications.lua NOTIFICATION_TYPES
V.MESSAGE_TYPES = {
  bounty = 'BOUNTY',
  newplayer = 'NEW_PLAYER',
  bestiary = 'BESTIARY',
  achievement = 'ACHIEVEMENT',
  bosspoints = 'BOSS_POINT',
  ascension = 'ASCENSION',
  market = 'MARKET',
  sale = 'SALE', -- a listing of the player sold (market.lua, orbexchange.lua): at once or "While you were away"
  seasonpass = 'SEASON_PASS',
  pact = 'PACT', -- the Chaos Pact (or the Pacto Completo) ends soon (pact.lua, O317)
  journey = 'JOURNEY',
  invasion = 'INVASION',
  -- the world events (server worldevents.lua: the Wandering Merchant's shop, Chaos Storm, Golden Hour); they came as
  -- 'invasion' and showed INVASION with crossed axes (V35, seen in a client 2026-11-27)
  worldevent = 'WORLD_EVENT',
  cursedchest = 'CURSED_CHEST', -- a Cursed Chest rises, its hordes, its loot (server cursedchest.lua, O244)
  weeklychest = 'WEEKLY_CHEST', -- the Weekly Chest opens, the bonus roll (server weeklychest.lua, O261)
  milestone = 'MILESTONE', -- a level milestone every 100 levels from 800 (server milestones.lua, O378)
  newcard = 'NEW_CARD', -- a card new to the Deck of Cards (server cards.lua, O570)
  -- server instance_limits.lua: the warnings before an instance's time runs out (the Infinity Tower's two clocks, O484) and the
  -- waiting line's turn; before 2026-11-25 they came as 'achievement' and showed ACHIEVEMENT UNLOCKED
  timeleft = 'TIME_LEFT',
  yourturn = 'YOUR_TURN'
}

function V.typeOfAction(action)
  return V.MESSAGE_TYPES[action]
end

V.BUTTON_TYPES = { PARTY_INVITE = true, CATACOMB_FREE = true }
V.HEIGHT = 110        -- a toast with up to four lines of text
V.BUTTON_HEIGHT = 140 -- a toast with Accept / Start buttons
V.GAP = 8             -- between two stacked toasts

function V.hasButtons(notificationType)
  return V.BUTTON_TYPES[notificationType] == true
end

function V.heightOf(notificationType)
  return V.hasButtons(notificationType) and V.BUTTON_HEIGHT or V.HEIGHT
end

-- The message starts TEXT_TOP below the top; under it there is room for the timer bar (or for the Accept / Start
-- buttons). A long message used to run under the bar in a fixed 110 px toast. The toast grows to fit the wrapped
-- text, up to MAX_HEIGHT; past that the text is cut and its full form goes in a tooltip.
V.TEXT_TOP = 28
V.TEXT_BOTTOM = 18        -- the timer bar and its count
V.BUTTON_TEXT_BOTTOM = 77 -- the answer buttons and the timer bar
V.MAX_HEIGHT = 260

-- textHeight: the wrapped message's height in pixels. Returns the toast height, the message label height and
-- whether the text had to be cut
function V.heightFor(notificationType, textHeight)
  local bottom = V.hasButtons(notificationType) and V.BUTTON_TEXT_BOTTOM or V.TEXT_BOTTOM
  local needed = V.TEXT_TOP + math.max(0, math.ceil(tonumber(textHeight) or 0)) + bottom
  local height = math.min(V.MAX_HEIGHT, math.max(V.heightOf(notificationType), needed))
  return height, height - V.TEXT_TOP - bottom, needed > V.MAX_HEIGHT
end

-- pinned, active: {[slot] = {type = notificationType, height = its own height or nil, ...}} (slots may have holes). Returns the list of
-- {group = 'pinned' | 'active', slot, y} from the top: pinned toasts first, each group by slot, every toast below
-- the previous one by its own height plus the gap
function V.stack(pinned, active, baseY, gap)
  gap = gap or V.GAP
  local out = {}
  local y = baseY or 0
  for _, group in ipairs({ { 'pinned', pinned or {} }, { 'active', active or {} } }) do
    local slots = {}
    for slot in pairs(group[2]) do slots[#slots + 1] = slot end
    table.sort(slots)
    for _, slot in ipairs(slots) do
      local e = group[2][slot]
      out[#out + 1] = { group = group[1], slot = slot, y = y }
      y = y + ((e and tonumber(e.height)) or V.heightOf(e and e.type)) + gap
    end
  end
  return out
end

-- the waiting queue: at most `max` toasts wait (a login can bring many at once); when it is full the oldest one
-- without buttons gives way (an invitation is kept). Returns the toast dropped, if any
V.QUEUE_MAX = 12

function V.enqueue(queue, item, max)
  max = max or V.QUEUE_MAX
  queue[#queue + 1] = item
  if #queue <= max then return nil end
  local drop = 1
  for i, q in ipairs(queue) do
    if not V.hasButtons(q.notificationType) then drop = i; break end
  end
  return table.remove(queue, drop)
end

-- F49 (O775, seen in a client): a fast hunt piled the toasts up. Per kill the server can send a bestiary stage, a bounty
-- halfway / done, a season pass challenge, a kill task, a battle pass mission, a new card and an achievement; every one
-- was its own toast of 7-10 s, three shown and twelve waiting, so the column never emptied. Now these ROUTINE toasts
-- merge: a new one joins the toast of its own type that waits in the queue (or the one shown, during its first
-- MERGE_SHOWN_MS, which then starts its time again), newest line first, at most MERGE_LINES lines and "+N more". At
-- most ROUTINE_SHOWN routine toasts are on the screen at once; the last place is kept for the rest. Every other toast
-- (a level milestone, a quest step, an ascension, an invasion, an invitation, a sale ...) is never merged, never held
-- back and goes ahead of the routine ones in the queue.
V.ROUTINE_TYPES = { BESTIARY = true, BOUNTY = true, SEASON_PASS = true, TASK_COMPLETE = true, BATTLE_PASS = true,
  NEW_CARD = true, ACHIEVEMENT = true }
V.ROUTINE_SHOWN = 2
V.MERGE_LINES = 3
V.MERGE_SHOWN_MS = 3000

function V.isRoutine(notificationType)
  return V.ROUTINE_TYPES[notificationType] == true
end

-- target takes item's message: lines newest first, the count of all merged messages, the newest monster look
function V.merge(target, item)
  target.lines = target.lines or { target.message }
  target.count = (target.count or 1) + 1
  table.insert(target.lines, 1, item.message)
  while #target.lines > V.MERGE_LINES do table.remove(target.lines) end
  if item.monsterLookType then target.monsterLookType = item.monsterLookType end
  return target
end

-- the text of a merged toast; moreFmt: "+%d more" (translated by the caller)
function V.mergedText(target, moreFmt)
  local lines = target.lines or { target.message }
  local text = table.concat(lines, '\n')
  local more = (target.count or #lines) - #lines
  if more > 0 then text = text .. '\n' .. string.format(moreFmt or '+%d more', more) end
  return text
end

-- the queue is full: the oldest routine toast gives way first, then the oldest without buttons (V.enqueue's rule)
local function trim(queue, max)
  max = max or V.QUEUE_MAX
  if #queue <= max then return nil end
  for i, q in ipairs(queue) do
    if V.isRoutine(q.notificationType) then return table.remove(queue, i) end
  end
  for i, q in ipairs(queue) do
    if not V.hasButtons(q.notificationType) then return table.remove(queue, i) end
  end
  return table.remove(queue, 1)
end

-- queue: the waiting toasts; shown: {{data = the shown toast's data, shownAt = ms}, ...}; item: the new toast; now: ms.
-- Returns how it went: 'shown', entry (merged into a shown toast: refresh it), 'queued', data (merged into a waiting
-- one) or 'new', dropped (added to the queue; dropped is the toast that gave way, if any)
function V.admit(queue, shown, item, now, max)
  local kind = item.notificationType
  if not V.isRoutine(kind) then
    local pos = #queue + 1
    for i, q in ipairs(queue) do
      if V.isRoutine(q.notificationType) then pos = i; break end
    end
    table.insert(queue, pos, item)
    return 'new', trim(queue, max)
  end
  now = tonumber(now) or 0
  for _, e in ipairs(shown or {}) do
    if e.data and e.data.notificationType == kind and now - (tonumber(e.shownAt) or 0) < V.MERGE_SHOWN_MS then
      V.merge(e.data, item)
      return 'shown', e
    end
  end
  for i = #queue, 1, -1 do
    if queue[i].notificationType == kind then
      V.merge(queue[i], item)
      return 'queued', queue[i]
    end
  end
  queue[#queue + 1] = item
  return 'new', trim(queue, max)
end

-- the queue index of the next toast to show: the first one that is not routine, or the first routine one while fewer
-- than ROUTINE_SHOWN routine toasts are shown. nil: nothing may go up now
function V.nextIndex(queue, shownRoutine)
  local roomForRoutine = (tonumber(shownRoutine) or 0) < V.ROUTINE_SHOWN
  for i, q in ipairs(queue) do
    if not V.isRoutine(q.notificationType) or roomForRoutine then return i end
  end
  return nil
end

-- O401 (owner 2026-11-04): on a phone the toasts took too much of the small screen. Only the toasts that wait for an
-- answer (a party invite, a free catacomb with its Start button) are shown there; the rest are dropped.
V.PHONE_TYPES = { PARTY_INVITE = true, CATACOMB_FREE = true }

function V.showOnPhone(notificationType)
  return V.PHONE_TYPES[notificationType] == true
end

-- V12 (seen in a client 2026-11-25): the danger window of the hunt warnings sat 40 px under the top of the map panel, but
-- the map panel can reach above the screen (a 1280 x 720 window: map at y -65), so the window began at y -25 and its
-- DANGER header was cut off. Its top is now measured from the visible top of the map (never above the game root) and
-- kept below the menu bar when that is in the way. All values are screen y; the result is the margin from the root's top.
--   rootY     the root panel's top     mapY   the map panel's top     barBottom   the menu bar's bottom (nil: none shown)
V.DANGER_GAP = 40
V.DANGER_BAR_GAP = 6

function V.dangerTop(rootY, mapY, barBottom, gap)
  rootY = tonumber(rootY) or 0
  gap = tonumber(gap) or V.DANGER_GAP
  local top = math.max(rootY, tonumber(mapY) or rootY) + gap
  if tonumber(barBottom) then
    top = math.max(top, barBottom + V.DANGER_BAR_GAP)
  end
  return top - rootY
end
