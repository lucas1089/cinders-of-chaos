-- Run from the repo root: luajit client/overlay/modules/game_chaosnotify/notifyview_test.lua (also lua5.3)
-- The toast logic of game_chaosnotify (notifyview.lua): message kinds to toast types (the new "sale" kind), toast
-- heights, the stack (several toasts and toasts with buttons never overlap, pinned first, holes in the slots) and the
-- capped waiting queue.
local here = (arg and arg[0] or ''):match('^(.*)/[^/]*$') or '.'
dofile(here .. '/notifyview.lua')
local V = ChaosNotifyView
local fails, n = 0, 0
local function eq(a, b, name)
  n = n + 1
  if a ~= b then fails = fails + 1; print('FAIL ' .. name .. ': got ' .. tostring(a) .. ', want ' .. tostring(b)) end
end

-- ------------------------------------------------------------------ kinds
eq(V.typeOfAction('sale'), 'SALE', 'sale kind')
eq(V.typeOfAction('achievement'), 'ACHIEVEMENT', 'achievement kind')
eq(V.typeOfAction('market'), 'MARKET', 'market kind')
eq(V.typeOfAction('pact'), 'PACT', 'pact kind (the Chaos Pact expiry warning)')
eq(V.typeOfAction('cursedchest'), 'CURSED_CHEST', 'cursedchest kind (the Cursed Chest toasts, O244)')
eq(V.typeOfAction('worldevent'), 'WORLD_EVENT', 'worldevent kind: the merchant is no invasion (V35)')
eq(V.typeOfAction('weeklychest'), 'WEEKLY_CHEST', 'weeklychest kind (the Weekly Chest toasts, O261)')
eq(V.typeOfAction('milestone'), 'MILESTONE', 'milestone kind (the level milestone toast, O378)')
eq(V.typeOfAction('newcard'), 'NEW_CARD', 'newcard kind (the Deck of Cards toast, O570)')
eq(V.typeOfAction('timeleft'), 'TIME_LEFT', 'timeleft kind (instance time warnings, not ACHIEVEMENT)')
eq(V.typeOfAction('yourturn'), 'YOUR_TURN', 'yourturn kind (the waiting line)')
eq(V.typeOfAction('partyInvite'), nil, 'not a message kind')
-- every kind the server's ChaosNotify.send accepts has a toast type here
local src = io.open(here .. '/../../../../server/data/scripts/chaos/notifications.lua')
if src then
  local text = src:read('*a')
  src:close()
  local kinds = text:match('local SEND_KINDS = (%b{})')
  for kind in (kinds or ''):gmatch('([%a_]+) = true') do
    eq(V.typeOfAction(kind) ~= nil, true, 'server kind ' .. kind .. ' has a toast type')
  end
end
-- and every toast type named here exists in notifications.lua
local cl = io.open(here .. '/notifications.lua')
if cl then
  local text = cl:read('*a')
  cl:close()
  for kind, t in pairs(V.MESSAGE_TYPES) do
    eq(text:find('\n    ' .. t .. ' = {', 1, true) ~= nil, true, 'type ' .. t .. ' defined')
    eq(text:find('\n        ' .. kind .. ' = function', 1, true) ~= nil, true, 'handler for ' .. kind)
  end
end

-- ------------------------------------------------------------------ heights
eq(V.heightOf('SALE'), 110, 'a message toast')
eq(V.heightOf('PARTY_INVITE'), 140, 'a toast with buttons')
eq(V.hasButtons('CATACOMB_FREE'), true, 'catacomb has buttons')
eq(V.hasButtons('ACHIEVEMENT'), false, 'achievement has none')

-- ------------------------------------------------------------------ the stack
local function overlaps(list, heights)
  for i = 2, #list do
    if list[i].y < list[i - 1].y + heights[i - 1] then return true end
  end
  return false
end
local s = V.stack({}, { [1] = { type = 'SALE' }, [2] = { type = 'ACHIEVEMENT' }, [3] = { type = 'MARKET' } }, 70)
eq(#s, 3, 'three toasts')
eq(s[1].y .. '/' .. s[2].y .. '/' .. s[3].y, '70/188/306', 'stacked by height + gap')
eq(overlaps(s, { 110, 110, 110 }), false, 'no overlap')
-- an invitation (140) above a sale: the sale moves down by 148, not by a fixed step
local inv = V.stack({}, { [1] = { type = 'PARTY_INVITE' }, [2] = { type = 'SALE' } }, 70)
eq(inv[2].y, 70 + 140 + 8, 'below the taller toast')
eq(overlaps(inv, { 140, 110 }), false, 'no overlap with a button toast')
-- holes and order: slot 3 and slot 1 shown, slot 2 gone; pinned ones first
local mix = V.stack({ [2] = { type = 'GM_BROADCAST' } }, { [3] = { type = 'SALE' }, [1] = { type = 'CATACOMB_FREE' } }, 0)
eq(mix[1].group .. mix[1].slot .. ',' .. mix[2].group .. mix[2].slot .. ',' .. mix[3].group .. mix[3].slot,
  'pinned2,active1,active3', 'pinned first, then by slot')
eq(mix[2].y .. '/' .. mix[3].y, '118/266', 'positions')
eq(overlaps(mix, { 110, 140, 110 }), false, 'no overlap with holes')
eq(#V.stack(nil, nil, 0), 0, 'nothing shown')

-- ------------------------------------------------------------------ the queue
local q = {}
for i = 1, V.QUEUE_MAX do eq(V.enqueue(q, { notificationType = 'SALE', message = 'm' .. i }), nil, 'queued ' .. i) end
local inviteQ = { { notificationType = 'PARTY_INVITE', message = 'join' } }
for i = 1, V.QUEUE_MAX do V.enqueue(inviteQ, { notificationType = 'ACHIEVEMENT', message = 'a' .. i }) end
eq(#inviteQ, V.QUEUE_MAX, 'capped')
eq(inviteQ[1].message, 'join', 'the invitation is kept')
eq(inviteQ[2].message, 'a2', 'the oldest message toast gave way')
local dropped = V.enqueue(q, { notificationType = 'SALE', message = 'new' })
eq(dropped and dropped.message, 'm1', 'the oldest dropped')
eq(#q, V.QUEUE_MAX, 'still capped')
eq(q[#q].message, 'new', 'the newest kept')

-- ------------------------------------------------------------------ height from the wrapped text
local h, lh, cut = V.heightFor('INVASION', 13 * 4)
eq(h .. '/' .. lh .. '/' .. tostring(cut), '110/64/false', 'four lines keep the base toast')
h, lh, cut = V.heightFor('INVASION', 13 * 6)
eq(h .. '/' .. lh .. '/' .. tostring(cut), (28 + 78 + 18) .. '/78/false', 'six lines grow the toast')
eq(h - lh - V.TEXT_TOP >= V.TEXT_BOTTOM, true, 'the timer bar stays below the text')
h, lh, cut = V.heightFor('NEW_PLAYER', 13 * 30)
eq(h .. '/' .. tostring(cut), V.MAX_HEIGHT .. '/true', 'a very long text is capped (tooltip)')
eq(lh, V.MAX_HEIGHT - V.TEXT_TOP - V.TEXT_BOTTOM, 'capped label height')
h, lh = V.heightFor('PARTY_INVITE', 13 * 2)
eq(h .. '/' .. lh, '140/35', 'button toast keeps its base')
h, lh = V.heightFor('PARTY_INVITE', 13 * 5)
eq(h, 28 + 65 + 77, 'button toast grows over its buttons')
-- a grown toast pushes the next one down by its own height
local grown = V.stack({}, { [1] = { type = 'INVASION', height = 160 }, [2] = { type = 'SALE' } }, 0)
eq(grown[2].y, 160 + 8, 'stacked below the grown toast')

-- O401: phones show only the toasts that need an answer
eq(V.showOnPhone('PARTY_INVITE'), true, 'phone keeps party invites')
eq(V.showOnPhone('CATACOMB_FREE'), true, 'phone keeps the catacomb start')
eq(V.showOnPhone('SALE'), false, 'phone drops a sale toast')
eq(V.showOnPhone('GM_BROADCAST'), false, 'phone drops a broadcast toast')
eq(V.showOnPhone(nil), false, 'phone drops an unknown toast')

-- V12: the danger window starts on the screen, below the menu bar
eq(V.dangerTop(0, -65, nil), 40, 'a map above the screen: 40 under the root top, not y -25')
eq(V.dangerTop(0, 30, nil), 70, 'a map below the root top: 40 under the map top')
eq(V.dangerTop(0, -65, 44), 50, 'the menu bar is in the way: 6 under its bottom')
eq(V.dangerTop(0, 30, 20), 70, 'a menu bar above the spot changes nothing')
eq(V.dangerTop(100, 50, nil), 40, 'the margin is from the root top')
eq(V.dangerTop(0, nil, nil), 40, 'no map: 40 under the root top')

-- ------------------------------------------------------------------ F49: kill progress toasts merge, two places at most
local function toast(t, m) return { notificationType = t, message = m } end
-- a fast hunt: 30 kills in 15 s, each kill a bestiary stage, every third a bounty, every fifth a season pass line, a
-- level milestone and a quest step among them; nothing is shown yet (the client takes them up as places free)
local queue, shownList = {}, {}
for k = 1, 30 do
  V.admit(queue, shownList, toast('BESTIARY', 'Bestiary ' .. k), k * 500)
  if k % 3 == 0 then V.admit(queue, shownList, toast('BOUNTY', 'Bounty ' .. k), k * 500) end
  if k % 5 == 0 then V.admit(queue, shownList, toast('SEASON_PASS', 'Pass ' .. k), k * 500) end
  if k == 12 then V.admit(queue, shownList, toast('MILESTONE', 'Level 900'), k * 500) end
  if k == 20 then V.admit(queue, shownList, toast('JOURNEY', 'Quest step: the Ash Gate'), k * 500) end
end
eq(#queue, 5, 'a fast hunt leaves five toasts, one per routine type plus the two important ones')
eq(queue[1].notificationType .. ',' .. queue[2].notificationType, 'MILESTONE,JOURNEY', 'the important toasts go first')
eq(queue[3].notificationType, 'BESTIARY', 'then the routine ones in the order they came')
eq(queue[3].count, 30, 'thirty bestiary lines in one toast')
eq(#queue[3].lines, V.MERGE_LINES, 'at most three lines')
eq(queue[3].lines[1], 'Bestiary 30', 'newest line first')
eq(V.mergedText(queue[3], '+%d more'), 'Bestiary 30\nBestiary 29\nBestiary 28\n+27 more', 'merged text')
eq(V.mergedText(toast('BOUNTY', 'one')), 'one', 'a single toast keeps its text')
local q4 = queue[4]
eq(q4.notificationType .. '/' .. q4.count, 'BOUNTY/10', 'ten bounty lines')
-- the next to show: important first, then routine while fewer than two routine toasts are up
eq(V.nextIndex(queue, 0), 1, 'the milestone first')
eq(V.nextIndex({ toast('BESTIARY', 'a'), toast('MILESTONE', 'b') }, 2), 2, 'two routine up: the milestone passes the routine one')
eq(V.nextIndex({ toast('BESTIARY', 'a') }, 2), nil, 'two routine up: the routine one waits')
eq(V.nextIndex({ toast('BESTIARY', 'a') }, 1), 1, 'one routine up: it goes')
eq(V.nextIndex({}, 0), nil, 'empty queue')
-- merging into a shown toast during its first seconds, a new toast after
local shownBest = { data = toast('BESTIARY', 'first'), shownAt = 1000 }
local q2 = {}
local how, target = V.admit(q2, { shownBest }, toast('BESTIARY', 'second'), 2500)
eq(how, 'shown', 'merged into the shown toast in its first seconds')
eq(target, shownBest, 'the shown entry')
eq(V.mergedText(shownBest.data), 'second\nfirst', 'the shown toast reads both')
how = V.admit(q2, { shownBest }, toast('BESTIARY', 'third'), 1000 + V.MERGE_SHOWN_MS)
eq(how, 'new', 'after the merge window a new toast waits')
how, target = V.admit(q2, { shownBest }, toast('BESTIARY', 'fourth'), 9000)
eq(how .. '/' .. target.count, 'queued/2', 'and takes the next lines')
-- important toasts are never merged
local q3 = {}
V.admit(q3, {}, toast('MILESTONE', 'Level 800'), 0)
how = V.admit(q3, {}, toast('MILESTONE', 'Level 900'), 0)
eq(how .. '/' .. #q3, 'new/2', 'two milestones stay two toasts')
how = V.admit(q3, { { data = toast('JOURNEY', 'step 1'), shownAt = 0 } }, toast('JOURNEY', 'step 2'), 100)
eq(how .. '/' .. #q3, 'new/3', 'a quest step is never merged into the shown one')
eq(V.isRoutine('PARTY_INVITE') or V.isRoutine('MILESTONE') or V.isRoutine('JOURNEY') or V.isRoutine('ASCENSION'), false,
  'invitations, milestones, quest steps and ascension are not routine')
-- a full queue: a routine toast gives way before an important one, an invitation never
local full = { toast('PARTY_INVITE', 'join') }
for i = 1, V.QUEUE_MAX - 2 do full[#full + 1] = toast('SALE', 's' .. i) end
full[#full + 1] = toast('BESTIARY', 'b')
local _, dropped2 = V.admit(full, {}, toast('MARKET', 'm'), 0)
eq(dropped2 and dropped2.message, 'b', 'the routine toast gives way first')
eq(full[1].message, 'join', 'the invitation stays')
_, dropped2 = V.admit(full, {}, toast('MARKET', 'm2'), 0)
eq(dropped2 and dropped2.message, 's1', 'then the oldest without buttons')
-- every routine type is a toast type of notifications.lua
local cl2 = io.open(here .. '/notifications.lua')
if cl2 then
  local text = cl2:read('*a')
  cl2:close()
  for t in pairs(V.ROUTINE_TYPES) do
    eq(text:find('\n    ' .. t .. ' = {', 1, true) ~= nil, true, 'routine type ' .. t .. ' defined')
  end
end

print(string.format('notifyview_test: %d checks, %d failed', n, fails))
if fails > 0 then os.exit(1) end
