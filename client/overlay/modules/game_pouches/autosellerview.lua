-- Auto Seller window: the logic without client API (tested by autosellerview_test.lua).
-- The server (data/scripts/chaos/autosell.lua A.state) sends the state over the pouches opcode 226, action
-- `autoseller`: {unlocked, needs, paused, tiers = {{key, name, on}}, list = {{id, name, price}}, slots, cooldown,
-- cooldownMax, last = {gold, count, at}, notice, open}. The client never decides a sale: it only shows the state and
-- sends the player's choices (sell, asrar, aslist, aspause) for the server to check.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

AutoSellerView = {}
local V = AutoSellerView

-- the five rarity choices (server autosell_core.lua TIERS), in the loot filter's rarity colours
V.TIERS = {
  { key = 'common', name = 'Common', color = '#c8c8c8' },
  { key = 'uncommon', name = 'Uncommon', color = '#5ccf5c' },
  { key = 'rare', name = 'Rare', color = '#4a90ff' },
  { key = 'epic', name = 'Epic', color = '#a35cf0' },
  { key = 'legendary', name = 'Legendary+', color = '#ffd040' },
}
V.DEFAULT_ON = { common = true, uncommon = true }

-- a rarity checkbox as wide as its text: the box and the text offset (ChaosCheckBox text-offset 22) + 2 px. The
-- fixed 72 px clipped "Common", "Uncommon" and "Legendary+" (live test 2026-10-14).
V.CHECK_TEXT_OFFSET = 22
V.ROW_SPACING = 6 -- autoseller.otui rarityRow spacing
function V.checkWidth(textWidth)
  return (tonumber(textWidth) or 0) + V.CHECK_TEXT_OFFSET + 2
end

-- the widths of a row of checkboxes with their spacing fit in rowWidth
function V.rowFits(textWidths, rowWidth)
  local total = 0
  for i, w in ipairs(textWidths) do
    total = total + V.checkWidth(w) + (i > 1 and V.ROW_SPACING or 0)
  end
  return total <= rowWidth, total
end
V.NEEDS = 'Needs the Auto Seller (Store > Convenience) or an active Chaos Pact.'

-- the state from the server with every field safe to use; missing tiers take the defaults
function V.normalize(s)
  s = type(s) == 'table' and s or {}
  local out = {
    unlocked = s.unlocked == true,
    needs = type(s.needs) == 'string' and s.needs or V.NEEDS,
    paused = s.paused == true,
    slots = math.max(0, math.floor(tonumber(s.slots) or 40)),
    cooldown = math.max(0, math.floor(tonumber(s.cooldown) or 0)),
    cooldownMax = math.max(1, math.floor(tonumber(s.cooldownMax) or 30)),
    notice = type(s.notice) == 'string' and s.notice or nil,
    open = s.open == true,
    list = {},
    tiers = {},
  }
  local on = {}
  for _, t in ipairs(type(s.tiers) == 'table' and s.tiers or {}) do
    if type(t) == 'table' and type(t.key) == 'string' then on[t.key] = t.on == true end
  end
  for i, t in ipairs(V.TIERS) do
    local v = on[t.key]
    if v == nil then v = V.DEFAULT_ON[t.key] == true end
    out.tiers[i] = { key = t.key, name = t.name, color = t.color, on = v }
  end
  for _, e in ipairs(type(s.list) == 'table' and s.list or {}) do
    if type(e) == 'table' and e.name then
      out.list[#out.list + 1] = { id = tonumber(e.id) or 0, name = tostring(e.name), price = tonumber(e.price) or 0 }
    end
  end
  if type(s.last) == 'table' and tonumber(s.last.gold) then
    out.last = { gold = math.floor(tonumber(s.last.gold)), count = math.floor(tonumber(s.last.count) or 0) }
  end
  return out
end

-- the Sell all button: its text counts the cooldown down
function V.sellText(left)
  left = math.floor(tonumber(left) or 0)
  if left > 0 then return tr('Sell all (%s s)', left) end
  return tr('Sell all')
end

function V.sellEnabled(state, left)
  return state.unlocked and (tonumber(left) or 0) <= 0
end

-- cooldown seconds left now, from the value the server sent `elapsed` seconds ago
function V.cooldownLeft(sent, elapsed)
  return math.max(0, math.floor((tonumber(sent) or 0) - (tonumber(elapsed) or 0)))
end

function V.lastSaleText(last)
  if type(last) ~= 'table' then return tr('Last sale: none yet.') end
  return tr('Last sale: %s gold (%d item%s).', V.gold(last.gold), last.count, last.count == 1 and '' or 's')
end

function V.gold(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  return (out:gsub('^,', ''))
end

-- the corpse list as one text: "rope (5), dagger (100)"
function V.listText(list, slots)
  local parts = {}
  for _, e in ipairs(list or {}) do parts[#parts + 1] = string.format('%s (%s)', e.name, V.gold(e.price)) end
  local head = string.format('%d/%d items', #parts, slots or 40)
  if #parts == 0 then return tr('%s: none. Add items an NPC buys.', head) end
  return head .. ': ' .. table.concat(parts, ', ')
end

-- the window's controls are greyed out with this tooltip when the character lacks the unlock (nil = usable)
function V.lockedTooltip(state)
  if state.unlocked then return nil end
  return state.needs or V.NEEDS
end

-- the request for one checkbox (sent as `asrar`); nil for an unknown key
function V.rarityRequest(key, on)
  for _, t in ipairs(V.TIERS) do
    if t.key == key then return { tier = key, on = on == true } end
  end
  return nil
end

-- the request of the list buttons (sent as `aslist`); nil when the name is empty
function V.listRequest(op, text)
  if op == 'clear' then return { op = 'clear' } end
  if op ~= 'add' and op ~= 'remove' then return nil end
  text = tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if text == '' then return nil end
  return { op = op, item = text:sub(1, 80) }
end
