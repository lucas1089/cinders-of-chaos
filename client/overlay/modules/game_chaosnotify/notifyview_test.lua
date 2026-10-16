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

print(string.format('notifyview_test: %d checks, %d failed', n, fails))
if fails > 0 then os.exit(1) end
