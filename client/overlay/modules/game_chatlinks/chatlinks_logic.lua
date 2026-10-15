-- Item links in chat, the logic without client API (tested by chatlinks_logic_test.lua).
-- A link in a message is   [Item Name]{<r><id>}   (r = rarity as a hex digit or u for a unique, id = 9 characters a-z 0-9), made by the
-- server (extended opcode 249, server/data/scripts/chaos/itemlink.lua + itemlink_core.lua: same format). Other clients
-- show the text as it is; this one shows "[Item Name]" in the rarity colour and the tooltip of the snapshot on hover.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

ChatLinksLogic = {}
local L = ChatLinksLogic

L.OPCODE = 249
L.MAX_LINKS = 3 -- links in one message
L.MAX_TEXT = 250 -- characters of a message with its links written out (the protocol allows 255)
L.TTL = 600 -- seconds a snapshot lives on the server
L.ASK_INTERVAL = 2 -- seconds before the same link is asked again
L.GONE_TTL = 60 -- seconds an "expired" answer is believed
L.MAX_STORE = 120 -- snapshots kept

-- the rarity colours of the item tooltip (game_itemtooltip tooltiplogic.lua RARITY_COLORS: the test compares them)
L.RARITY_COLORS = { '#c8c8c8', '#5ccf5c', '#4a90ff', '#a35cf0', '#ffd040', '#f5b13a', '#ff5a5a', '#e02424', '#ff8a70',
  '#c8e8ff', '#9ad8ff', '#e4f2ff', '#b878ff', '#9a4ce0', '#e070ff' }
L.NORMAL_COLOR = '#e4d8c0'
L.UNIQUE_COLOR = '#e07b24' -- the unique orange of the tooltip

function L.colorOf(rarity, unique)
  if unique then return L.UNIQUE_COLOR end
  return L.RARITY_COLORS[tonumber(rarity) or 0] or L.NORMAL_COLOR
end

function L.validId(id)
  return type(id) == 'string' and #id == 9 and id:match('^[a-z0-9]+$') ~= nil
end

-- the links of a text: { { name, id, rarity, first, last } } (byte positions of "[Name]{...}"), in order. Links past
-- MAX_LINKS are not returned (they stay plain text).
function L.parse(text)
  local out = {}
  if type(text) ~= 'string' then return out end
  local pos = 1
  while #out < L.MAX_LINKS do
    local s, e, name, r, id = text:find('%[([^%[%]{}%c]+)%]{([%xu])(%w%w%w%w%w%w%w%w%w)}', pos)
    if not s then break end
    if L.validId(id) then
      out[#out + 1] = { name = name, id = id, rarity = tonumber(r, 16) or 0, unique = r == 'u', first = s, last = e }
    end
    pos = e + 1
  end
  return out
end

-- the text as it is shown or copied: "[Item Name]" without the marker
function L.plain(text)
  if type(text) ~= 'string' or not text:find('{', 1, true) then return text end
  return (text:gsub('(%[[^%[%]{}%c]+%]){[%xu]%w%w%w%w%w%w%w%w%w}', function(name, _)
    return name
  end))
end

-- the text split for a coloured label: { text = shown text, parts = {text, color, text, color, ...}, ranges = {{first,
-- last, id, name, rarity}} } with first (inclusive) and last (exclusive) as 0-based character positions of the shown text
function L.pieces(text, baseColor)
  local links = L.parse(text)
  local parts, ranges, shown = {}, {}, {}
  local shownLen = 0
  local cursor = 1
  local function add(s, color)
    if s ~= '' then
      parts[#parts + 1] = s
      parts[#parts + 1] = color
      shown[#shown + 1] = s
      shownLen = shownLen + #s
    end
  end
  for _, k in ipairs(links) do
    add(text:sub(cursor, k.first - 1), baseColor)
    local label = '[' .. k.name .. ']'
    ranges[#ranges + 1] = { first = shownLen, last = shownLen + #label, id = k.id, name = k.name, rarity = k.rarity,
      unique = k.unique }
    add(label, L.colorOf(k.rarity, k.unique))
    cursor = k.last + 1
  end
  add(text:sub(cursor), baseColor)
  return { text = table.concat(shown), parts = parts, ranges = ranges }
end

-- the range under a character index of the label (the index of the label's click / hover events is 0-based)
function L.rangeAt(ranges, index)
  index = tonumber(index)
  if not ranges or not index then return nil end
  for _, r in ipairs(ranges) do
    if index >= r.first and index < r.last then return r end
  end
  return nil
end

-- ---------------------------------------------------------------- chips in the chat input
-- A chip is the "[Item Name]" the player sees in the input; chips = { { name, token } } holds what it becomes.

-- chips that are still in the text (the player may have deleted one)
function L.liveChips(text, chips)
  local out, from = {}, 1
  for _, c in ipairs(chips or {}) do
    local s, e = (text or ''):find('[' .. c.name .. ']', from, true)
    if s then
      out[#out + 1] = c
      from = e + 1
    end
  end
  return out
end

-- the text with each chip replaced by its token, in order; returns text, number of chips written out
function L.expand(text, chips)
  text = text or ''
  local out, from, used = {}, 1, 0
  for _, c in ipairs(chips or {}) do
    local s, e = text:find('[' .. c.name .. ']', from, true)
    if s then
      out[#out + 1] = text:sub(from, s - 1)
      out[#out + 1] = c.token
      from = e + 1
      used = used + 1
    end
  end
  out[#out + 1] = text:sub(from)
  return table.concat(out), used
end

-- length of the text once the chips and one more are written out
function L.projectedLength(text, chips, extra)
  local expanded = L.expand(text, chips)
  return #expanded + (extra and #extra.token or 0) - (extra and #extra.name + 2 or 0)
end

-- may one more chip go in? returns true, or false and the reason
function L.canAdd(text, chips, extra)
  local live = L.liveChips(text, chips)
  if #live >= L.MAX_LINKS then
    return false, tr('You can link up to %d items in one message.', L.MAX_LINKS)
  end
  if L.projectedLength(text, live, extra) + 1 > L.MAX_TEXT then
    return false, tr('The message is too long for another item link.')
  end
  return true
end

-- ---------------------------------------------------------------- where a link may be sent
-- tab = { name, id, private, npc, loot, spell, serverLog } -> ctx for the server, or nil and the reason
function L.contextOf(tab, helpAllowed)
  tab = tab or {}
  if tab.npc then return nil, tr('Items cannot be linked in NPC conversations.') end
  if tab.loot or tab.spell then return nil, tr('Items cannot be linked in this channel.') end
  if tab.private then return { kind = 'private' } end
  if tab.serverLog then return { kind = 'say' } end
  if tab.local_ then return { kind = 'say' } end
  local id = tonumber(tab.id)
  if id == 7 and not helpAllowed then
    return nil, tr('Item links are not allowed in the Help channel.')
  end
  return { kind = 'channel', id = id }
end

-- a message that goes to a tab where links are not allowed loses the markers (the names stay)
function L.scrub(text, allowed)
  if allowed then return text end
  return L.plain(text)
end

-- ---------------------------------------------------------------- positions
function L.linkable(pos)
  return type(pos) == 'table' and tonumber(pos.x) == 0xFFFF and tonumber(pos.y) ~= nil
end

function L.iidText(iid)
  if type(iid) == 'string' and iid:match('^%d+$') then return iid end
  return string.format('%.0f', tonumber(iid) or 0)
end

-- ---------------------------------------------------------------- snapshots received
function L.newStore()
  return { entries = {}, order = {}, asked = {} }
end

-- a snapshot or an "expired" answer ({gone = true})
function L.put(store, id, entry, now)
  if not store.entries[id] then store.order[#store.order + 1] = id end
  entry.at = now
  store.entries[id] = entry
  while #store.order > L.MAX_STORE do
    store.entries[table.remove(store.order, 1)] = nil
  end
end

-- the entry when it is still good: a snapshot for the time it lives, an expired answer for GONE_TTL
function L.get(store, id, now)
  local e = store.entries[id]
  if not e then return nil end
  local life = e.gone and L.GONE_TTL or L.TTL
  if now - e.at >= life then
    store.entries[id] = nil
    return nil
  end
  return e
end

-- true once per ASK_INTERVAL and id (records the time)
function L.shouldAsk(store, id, now)
  local last = store.asked[id]
  if last and now - last < L.ASK_INTERVAL then return false end
  store.asked[id] = now
  return true
end

-- the dim line under a tooltip of a link
function L.footer(owner, entry, now)
  local left = math.max(0, (tonumber(entry.left) or L.TTL) - (now - (entry.at or now)))
  local minutes = math.ceil(left / 60)
  return tr('Linked by %s - %d min left', owner or '?', math.max(minutes, 0))
end
