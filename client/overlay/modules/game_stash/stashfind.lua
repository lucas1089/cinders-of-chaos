-- Find my item (O412): the texts and rules of the search window, without client API (tested by stashfind_test.lua).
-- The server (data/scripts/chaos/stash.lua S.find, itemsearch_core.lua) searches; this formats its answer:
--   found {q, page, pages, total, shown, capped, items = [{loc = 'equip' | 'bag' | 'purse' | 'inbox' | 'stash', name,
--          count, cid, rarity?, unique?, slot?, path?, at?, ids?, where?, tab?, tabName?, old?, row?, item?}]}
--   found {q, error = 'short' | 'long'}
local function tr(s, ...) local g = (rawget(_G, 'tr') or (rawget(_G, 'ChaosLocale') or {}).tr) if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

StashFind = {}
local F = StashFind

F.MIN_CHARS = 2      -- stash_config.lua find.minChars
F.MAX_CHARS = 40     -- find.maxChars
F.DEBOUNCE_MS = 700  -- the request goes out this long after the last key (the server takes one every 500 ms)
F.TIMEOUT_MS = 3000  -- no answer by then: the request is taken as lost (a rate-limited one gets none)
F.HOTKEY = 'Ctrl+Shift+F' -- Ctrl+F is the base client's Toggle Fullscreen; Alt+F the Help Search

local function n(v)
  return math.floor(tonumber(v) or 0)
end

-- the query as it is sent: trimmed; nil while too short or too long
function F.query(text)
  if type(text) ~= 'string' then return nil end
  local q = text:gsub('^%s+', ''):gsub('%s+$', '')
  if #q > F.MAX_CHARS then return nil end
  if #q:gsub('%s', '') < F.MIN_CHARS then return nil end
  return q
end

F.SLOTS = { 'Head', 'Necklace', 'Backpack', 'Armor', 'Right hand', 'Left hand', 'Legs', 'Feet', 'Ring', 'Ammo' }

function F.slotName(slot)
  local name = F.SLOTS[n(slot)]
  return name and tr(name) or tr('Slot %d', n(slot))
end

-- the line under an item's name: where it is
function F.whereText(r, tabLabel)
  if type(r) ~= 'table' then return '' end
  if r.loc == 'equip' then
    return tr('Equipped: %s', F.slotName(r.slot))
  elseif r.loc == 'bag' then
    return tr('Carried: %s', tostring(r.where or F.slotName(r.slot)))
  elseif r.loc == 'purse' then
    return tr('In your purse')
  elseif r.loc == 'inbox' then
    return tr('In your inbox')
  elseif r.loc == 'stash' then
    local label = tabLabel and tabLabel({ id = r.tab, name = r.tabName, affinity = r.tabName ~= nil, old = r.old }) or tostring(r.tab)
    return tr('Stash: %s tab', label)
  end
  return ''
end

-- what a click on a result does: 'stash' (open the window at its tab), 'container' (open the bags on the way),
-- 'equip' (show the slot), 'purse' (show the purse button), 'inbox' (show the stash's Inbox button)
function F.action(r)
  if type(r) ~= 'table' then return nil end
  if r.loc == 'bag' then return 'container' end
  if r.loc == 'equip' or r.loc == 'purse' or r.loc == 'inbox' or r.loc == 'stash' then return r.loc end
  return nil
end

-- the click's hint, as the row's tooltip
function F.hint(r)
  local a = F.action(r)
  if a == 'stash' then return tr('Click: open the stash at this tab and show the item.') end
  if a == 'container' then return tr('Click: open the bags it is in and show the item.') end
  if a == 'equip' then return tr('Click: show the slot.') end
  if a == 'purse' then return tr('Click: show the purse button. Take the item out of the purse into your backpack.') end
  if a == 'inbox' then return tr('Click: open the stash. Its Inbox button moves the inbox into your stash (in a protection zone).') end
  return ''
end

-- the container steps of a carried item, as game_chaoslayout opens them: the slot's container, then each container
-- below it ({ i = slot or index, id = client id }); nil when the server's path is not whole
function F.steps(r)
  if type(r) ~= 'table' or r.loc ~= 'bag' or type(r.ids) ~= 'table' then return nil end
  local path = type(r.path) == 'table' and r.path or {}
  if #r.ids ~= #path + 1 or n(r.slot) <= 0 then return nil end
  local out = { { i = n(r.slot), id = n(r.ids[1]) } }
  for k, idx in ipairs(path) do
    out[#out + 1] = { i = n(idx), id = n(r.ids[k + 1]) }
  end
  return out
end

-- a stash entry of the window (addItems: {id, row, tab}) is the result's entry
function F.isEntry(r, data)
  if type(r) ~= 'table' or type(data) ~= 'table' or r.loc ~= 'stash' then return false end
  if r.row then return data.row == r.row end
  return data.row == nil and n(data.id) == n(r.item) and n(r.item) > 0
end

-- the status line of an answer
function F.statusText(msg)
  if type(msg) ~= 'table' then return '' end
  if msg.error == 'short' then return tr('Type at least %d letters.', F.MIN_CHARS) end
  if msg.error == 'long' then return tr('Type at most %d letters.', F.MAX_CHARS) end
  local total = n(msg.total)
  if total == 0 then return tr('No item found.') end
  if msg.capped or n(msg.shown) < total then
    return tr('%d found, the first %d listed. Type more of the name.', total, n(msg.shown))
  end
  return tr('%d found.', total)
end

function F.pageText(msg)
  if type(msg) ~= 'table' or n(msg.pages) <= 1 then return '' end
  return tr('Page %d of %d', n(msg.page), n(msg.pages))
end

-- the answer is for the query on screen (an older answer arriving late is dropped)
function F.current(msg, q)
  return type(msg) == 'table' and type(q) == 'string' and msg.q == q
end

-- the rarity colours of the item tooltip (game_chatlinks chatlinks_logic.lua RARITY_COLORS, by rarity id)
F.RARITY_COLORS = { [1] = '#c8c8c8', [2] = '#5ccf5c', [3] = '#4a90ff', [4] = '#a35cf0', [5] = '#ffd040', [10] = '#c8e8ff' }
F.NAMES = { [1] = 'Common', [2] = 'Uncommon', [3] = 'Magic', [4] = 'Rare', [5] = 'Legendary', [10] = 'Divine' }
F.NORMAL_COLOR = '#e4d8c0'
F.UNIQUE_COLOR = '#e07b24'

function F.color(r)
  if type(r) ~= 'table' then return F.NORMAL_COLOR end
  if r.unique then return F.UNIQUE_COLOR end
  return F.RARITY_COLORS[n(r.rarity)] or F.NORMAL_COLOR
end

-- "Fire Sword" / "Fire Sword (Legendary)" / "Gold Coin x77"
function F.title(r)
  if type(r) ~= 'table' then return '' end
  local name = tostring(r.name or '')
  name = name:gsub('^%l', string.upper)
  local text = name
  if n(r.count) > 1 then text = text .. ' x' .. n(r.count) end
  if r.unique then
    text = text .. ' (' .. tr('Unique') .. ')'
  elseif F.NAMES[n(r.rarity)] then
    text = text .. ' (' .. tr(F.NAMES[n(r.rarity)]) .. ')'
  end
  return text
end

return StashFind
