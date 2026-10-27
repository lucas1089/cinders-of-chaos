-- Pure rules of the card borders (cardborder.lua draws them; cardborder_test.lua tests them under luajit and lua5.3).
-- The server (cards.lua) sends the ids of the cards that are on; the client cannot see action ids. A card gets a border
-- only while it sits in a deck container: lit when its id is in the set, dim otherwise. Before the first message of the
-- server (an older server never sends one) nothing is drawn, so no border says "off" by mistake.

CardBorderLogic = {}
local L = CardBorderLogic

L.WIDTH = 2
L.STYLE = {
  on = { color = '#7fe05a', width = L.WIDTH },   -- a clear green
  off = { color = '#6a3a3a', width = L.WIDTH },  -- dim red-grey
}

local function set(list)
  local out = {}
  if type(list) == 'table' then
    for _, v in ipairs(list) do
      local n = tonumber(v)
      if n then out[n] = true end
    end
  end
  return out
end

local function sameSet(a, b)
  for k in pairs(a) do if not b[k] then return false end end
  for k in pairs(b) do if not a[k] then return false end end
  return true
end

function L.new()
  return { known = false, on = {}, cards = {}, decks = {} }
end

-- take a "state" message {on, cards, decks}; true when something that is drawn changed
function L.apply(state, data)
  data = type(data) == 'table' and data or {}
  local on, cards, decks = set(data.on), set(data.cards), set(data.decks)
  local changed = not state.known or not sameSet(on, state.on) or not sameSet(cards, state.cards)
    or not sameSet(decks, state.decks)
  state.known, state.on, state.cards, state.decks = true, on, cards, decks
  return changed
end

-- forget everything (logout)
function L.reset(state)
  state.known, state.on, state.cards, state.decks = false, {}, {}, {}
end

function L.isDeck(state, itemId)
  return state.decks[tonumber(itemId) or -1] == true
end

-- 'on' | 'off' for a card item in a deck container; nil for anything else
function L.kind(state, deckId, itemId)
  if not state.known or not L.isDeck(state, deckId) then return nil end
  local id = tonumber(itemId)
  if not id or not state.cards[id] then return nil end
  return state.on[id] and 'on' or 'off'
end

-- a window needs a redraw when it is a deck, or when it drew card borders before and must wipe them
function L.needsPass(isDeck, drawn)
  return (isDeck and true or false) or (drawn and true or false)
end

-- the style of a kind (nil for none)
function L.style(kind)
  return L.STYLE[kind]
end

-- the item ids of a deck's slots (1-based list, 0 or nil = empty) -> the kind of each slot (false = no border)
function L.plan(state, deckId, itemIds, count)
  local out = {}
  for i = 1, count or #itemIds do
    out[i] = L.kind(state, deckId, itemIds[i]) or false
  end
  return out
end

return L
