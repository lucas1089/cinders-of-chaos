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
  invasion = 'INVASION'
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
