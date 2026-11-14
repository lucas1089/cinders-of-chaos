-- Deck of Cards window: every card the character looted, with filters, sort, the cards that are on and the set bonus. Server:
-- server/data/scripts/chaos/cards.lua, extended opcode 173 (JSON {action, data}); rules of the window: carddecklogic.lua.
--   server -> client  cards {cards, max}   the list of the 76 cards (once per sync, joined from parts by registerExtendedJSONOpcode)
--                     state {unlocked, own, new, on, ...}   copies, the "new" marks, the cards on, the set line
--   client -> server  sync | toggle {id} | seen {ids} or {all = true} | open
-- The top menu (Hero > Build > Deck of Cards) calls toggle(); its card shows how many cards are new (getNewCount).

local L = CardDeckLogic
local OPCODE = L.OPCODE

local window
local cards = {}          -- the static list (L.cleanCards)
local state               -- the last state of the server
local rows = {}           -- L.rows(cards, state)
local shown = {}          -- the rows on show, in order
local selected            -- the card id under the cursor / clicked
local filters = {}        -- set, rarity, element, owned, mine, search
local sortMode = 'number'
local cells = {}          -- card id -> widget
local lastNew = -1
local combos = {}         -- id -> options

local function send(action, extra)
  local protocol = g_game.getProtocolGame()
  if not protocol then return end
  local msg = { action = action }
  for k, v in pairs(extra or {}) do msg[k] = v end
  protocol:sendExtendedOpcode(OPCODE, json.encode(msg))
end

-- the hub menu card shows this number (client_chaos_topbar CARD_POINTS)
function getNewCount()
  return L.newCount(state)
end

local function refreshBar()
  local n = L.newCount(state)
  if n == lastNew then return end
  lastNew = n
  local top = modules and modules.client_chaos_topbar
  if top and top.ChaosTopBar and top.ChaosTopBar.refresh then pcall(top.ChaosTopBar.refresh) end
end

local function findRow(id)
  for _, r in ipairs(rows) do
    if r.id == id then return r end
  end
  return nil
end

-- ---------------------------------------------------------------- side panel
local function showSide()
  if not window then return end
  local p = window.sidePanel
  local on = L.activeRows(rows)
  local max = L.maxOn(state)
  p.activeTitle:setText(tr('Cards on (%d of %d)', #on, max))
  p.activeList:destroyChildren()
  for i = 1, max do
    local w = g_ui.createWidget('CardActiveRow', p.activeList)
    local r = on[i]
    if r then
      w:setText(r.name)
      w:setColor(L.RARITY_COLOR[r.rarity] or '#d6c9ae')
      w.onClick = function() selected = r.id; showSide() end
    else
      w:setText(tr('(empty slot)'))
      w:setColor('#6b6258')
    end
  end
  local locked = state and state.unlocked ~= true
  p.setLabel:setText(locked and tostring(state.quest or '') or tostring(state and state.set or ''))
  local r = selected and findRow(selected) or nil
  p.nameLabel:setText(r and r.name or '')
  p.subLabel:setText(r and (r.rarity .. (r.line ~= '' and ('  -  ' .. r.line) or '')) or '')
  p.textLabel:setText(r and (r.text .. '\n' .. (r.owned and tr('Copies: %d', r.count) or tr('Not owned yet'))) or tr('Point at a card to read it.'))
  local b = L.toggleButton(r, state)
  p.toggleButton:setText(b.label)
  p.toggleButton:setEnabled(b.enabled)
  p.whyLabel:setText(b.why or '')
end

-- ---------------------------------------------------------------- cards
local function markSeen(id)
  local r = findRow(id)
  if not r or not r.new then return end
  r.new = false
  if state and type(state.new) == 'table' then
    for i, v in ipairs(state.new) do
      if tonumber(v) == id then table.remove(state.new, i) break end
    end
  end
  local cell = cells[id]
  if cell then cell.newMark:setVisible(false) end
  send('seen', { ids = { id } })
  refreshBar()
end

local function decorate(cell, r)
  cell:setItemId(r.cid)
  cell:setBorderColor(L.borderColor(r))
  cell:setOpacity(r.owned and 1 or 0.35)
  cell.count:setText(r.count > 1 and ('x' .. r.count) or '')
  cell.count:setVisible(r.count > 1)
  cell.newMark:setVisible(r.new)
  cell:setTooltip(L.detail(r))
end

local function showGrid()
  if not window then return end
  rows = L.rows(cards, state)
  local className = state and state.class or ''
  shown = L.sort(L.filter(rows, filters, className), sortMode)
  local grid = window.gridFrame.cardGrid
  grid:destroyChildren()
  cells = {}
  for _, r in ipairs(shown) do
    local cell = g_ui.createWidget('CardCell', grid)
    decorate(cell, r)
    local id = r.id
    cell.onClick = function()
      selected = id
      markSeen(id)
      showSide()
      cell:focus()
    end
    cell.onHoverChange = function(_, hovered)
      if hovered then
        selected = id
        showSide()
      end
    end
    cells[id] = cell
  end
  window.gridFrame.emptyLabel:setVisible(#shown == 0)
  window.statusLabel:setText(L.summary(rows, L.maxOn(state)))
  window.markButton:setEnabled(L.newCount(state) > 0)
  if state and state.unlocked ~= true then
    window.hintLabel:setText(tostring(state.quest or ''))
    window.hintLabel:setColor('#e8a84a')
  else
    window.hintLabel:setText(tr('Cards go into the Deck by themselves. Click a card to turn it on or off with the button.'))
    window.hintLabel:setColor('#a89c86')
  end
  showSide()
end

-- ---------------------------------------------------------------- actions (buttons in carddeck.otui)
function toggleSelected()
  if selected then send('toggle', { id = selected }) end
end

function markAllSeen()
  if state and L.newCount(state) > 0 then
    state.new = {}
    send('seen', { all = true })
    showGrid()
    refreshBar()
  end
end

-- ---------------------------------------------------------------- protocol
local function onExtendedOpcode(protocol, opcode, buffer)
  local msg = buffer
  if type(buffer) == 'string' then
    local ok, decoded = pcall(json.decode, buffer)
    if not ok then return end
    msg = decoded
  end
  if type(msg) ~= 'table' then return end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'cards' then
    cards = L.cleanCards(data)
    showGrid()
  elseif msg.action == 'state' then
    state = data
    showGrid()
    refreshBar()
  end
end

-- ---------------------------------------------------------------- filters
local function setupCombo(id, kind, onChange)
  local combo = window[id]
  local options = L.options(kind)
  combos[id] = options
  combo:clearOptions()
  for _, o in ipairs(options) do combo:addOption(o[2]) end
  combo.onOptionChange = function(_, text) onChange(L.valueOf(options, text)) end
end

local function setupFilters()
  setupCombo('setCombo', 'set', function(v) filters.set = v; showGrid() end)
  setupCombo('rarityCombo', 'rarity', function(v) filters.rarity = v; showGrid() end)
  setupCombo('elementCombo', 'element', function(v) filters.element = v; showGrid() end)
  setupCombo('ownedCombo', 'owned', function(v) filters.owned = v; showGrid() end)
  setupCombo('classCombo', 'class', function(v) filters.mine = v == true; showGrid() end)
  setupCombo('sortCombo', 'sort', function(v) sortMode = v or 'number'; showGrid() end)
  window.searchEdit.onTextChange = function(_, text) filters.search = text; showGrid() end
end

-- ---------------------------------------------------------------- window
function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  send('sync')
  send('open')
end

function hide()
  if window then window:hide() end
end

function toggle()
  if not window then return end
  if window:isVisible() then hide() else show() end
end

local function onGameStart()
  scheduleEvent(function() if g_game.isOnline() then send('sync') end end, 1500)
end

local function onGameEnd()
  if window then window:hide() end
  cards, state, rows, shown, selected, cells, lastNew = {}, nil, {}, {}, nil, {}, -1
  if window then window.gridFrame.cardGrid:destroyChildren() end
end

function init()
  window = g_ui.displayUI('carddeck')
  window:hide()
  setupFilters()
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if window then
    window:destroy()
    window = nil
  end
  cards, state, rows, shown, cells = {}, nil, {}, {}, {}
end
