-- luajit shop_ui_test.lua && lua5.3 shop_ui_test.lua
-- shop.lua (O556) on a fake engine: the window opens on the home page (weekly strip, starter packs, bundles), the rail,
-- the chips of a group, cards and the details pane, owned / not affordable states, Buy with its confirmation (the
-- payload the server gets), the search with its filter chips, the history, openCategory. The widget ids and styles
-- the fake builds are the ones shop.otui defines (checked against the file below).
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ---------------------------------------------------------------- the ids and styles of shop.otui
local otui = assert(io.open(dir .. 'shop.otui', 'r')):read('*a')
local function hasId(id) return otui:find('id: ' .. id .. '\n', 1, true) ~= nil end
local function hasStyle(name) return otui:find('\n' .. name .. ' <', 1, true) ~= nil end

-- ---------------------------------------------------------------- the fake engine
local Widget = {}
Widget.__index = function(t, k)
  if Widget[k] then return Widget[k] end
  if type(k) == 'string' and k:match('^[sg]et%u') or type(k) == 'string' and k:match('^is%u') then
    return function() return nil end
  end
  return nil
end
local function newWidget(style, parent)
  local w = setmetatable({ style = style, children = {}, props = {}, parent = parent }, Widget)
  if parent then parent.children[#parent.children + 1] = w end
  return w
end
function Widget:setText(t) self.props.text = t end
function Widget:getText() return self.props.text or '' end
function Widget:setVisible(v) self.props.visible = v and true or false end
function Widget:isVisible() return self.props.visible ~= false end
function Widget:show() self.props.visible = true end
function Widget:hide() self.props.visible = false end
function Widget:setEnabled(v) self.props.enabled = v and true or false end
function Widget:isEnabled() return self.props.enabled ~= false end
function Widget:setChecked(v) self.props.checked = v and true or false end
function Widget:isChecked() return self.props.checked == true end
function Widget:setHeight(h) self.props.height = h end
function Widget:getHeight() return self.props.height or 40 end
function Widget:getWidth() return self.props.width or 548 end
function Widget:setColor(c) self.props.color = c end
function Widget:setTooltip(t) self.props.tooltip = t end
function Widget:setId(id) self.id = id end
function Widget:getId() return self.id end
function Widget:isDestroyed() return self.destroyed == true end
function Widget:getChildren() return self.children end
function Widget:getChildCount() return #self.children end
function Widget:getLastChild() return self.children[#self.children] end
function Widget:destroyChildren(child)
  for i, c in ipairs(self.children) do
    if c == child then c.destroyed = true; table.remove(self.children, i) return end
  end
end
function Widget:setImageSource(s) self.props.image = s end
function Widget:destroy() self.destroyed = true end
function Widget:raise() end
function Widget:focus() end
function Widget:recursiveGetChildById(id)
  for _, c in ipairs(self.children) do
    if c.id == id then return c end
    local r = c:recursiveGetChildById(id)
    if r then return r end
  end
  return nil
end

-- the window: every id of shop.otui the code reaches
local WINDOW_IDS = { 'infoPanel', 'points', 'buy', 'searchText', 'rail', 'detailPanel', 'lookPreview', 'dTitle', 'dTags',
  'dCoin', 'dPrice', 'dOld', 'dDesc', 'dNote', 'tryButton', 'giftButton', 'buyButton', 'mainPanel', 'adPanel', 'ad',
  'pathLabel', 'pathCount', 'chips', 'offers', 'offersScrollBar', 'home', 'homeScrollBar', 'emptyLabel',
  'pageControls', 'pageLabel', 'prevPage', 'nextPage' }
for _, id in ipairs(WINDOW_IDS) do eq(hasId(id), true, 'shop.otui defines id ' .. id) end
for _, st in ipairs({ 'ShopRail', 'ShopRailItem', 'ShopRailCreature', 'ShopRailImage', 'ShopChip', 'ShopCard', 'ShopCardItem',
  'ShopCardCreature', 'ShopCardImage', 'ShopSection' }) do eq(hasStyle(st), true, 'shop.otui defines style ' .. st) end

-- the children each style has (ids of shop.otui)
local STYLE_CHILDREN = {
  ShopRail = { 'bar', 'art', 'name', 'count' }, ShopCard = { 'art', 'title', 'sub', 'coin', 'price', 'oldPrice', 'badge' },
  ShopSection = { 'title', 'note', 'seeAll', 'grid' },
}
local STYLE_EXTRA = { Item = 'item', Creature = 'creature', Image = 'image' }
local function createWidget(style, parent)
  local w = newWidget(style, parent)
  local base = style:match('^ShopRail') and 'ShopRail' or style:match('^ShopCard') and 'ShopCard' or style
  for _, id in ipairs(STYLE_CHILDREN[base] or {}) do
    w[id] = newWidget(id, w); w[id].id = id
  end
  local extra = style:match('^ShopRail(%a+)$') or style:match('^ShopCard(%a+)$')
  if extra and STYLE_EXTRA[extra] then
    local id = STYLE_EXTRA[extra]
    w[id] = newWidget(id, w); w[id].id = id
  end
  return w
end

local sent, scheduled, boxes = {}, {}, {}
local window
local now = 1000
_G.g_ui = {
  displayUI = function(name)
    local w = newWidget(name, nil)
    if name == 'shop' then
      window = w
      for _, id in ipairs(WINDOW_IDS) do local c = newWidget(id, w); c.id = id end
      w.infoPanel = w:recursiveGetChildById('infoPanel')
    else
      w.coinsAmount = newWidget('coinsAmount', w); w.recipient = newWidget('recipient', w)
    end
    return w
  end,
  createWidget = createWidget,
}
_G.g_game = {
  getFeature = function() return true end,
  isOnline = function() return false end,
  getProtocolGame = function()
    return { sendExtendedJSONOpcode = function(_, code, payload) sent[#sent + 1] = payload end }
  end,
}
_G.GameExtendedOpcode = 1
_G.ProtocolGame = { registerExtendedJSONOpcode = function() end, unregisterExtendedJSONOpcode = function() end }
_G.g_clock = { seconds = function() return now end, millis = function() return now * 1000 end }
_G.g_logger = { warning = function() end, error = function(m) print('LOGGED ERROR: ' .. tostring(m)) fails = fails + 1 end }
_G.g_resources = { fileExists = function() return false end }
_G.g_app = { isMobile = function() return false end }
_G.g_platform = { openUrl = function() end }
_G.HTTP = { downloadImage = function() end }
_G.MouseLeftButton = 1
_G.AnchorHorizontalCenter = 1
_G.connect = function() end
_G.disconnect = function() end
_G.scheduleEvent = function(fn, ms) scheduled[#scheduled + 1] = { fn = fn, ms = ms } return #scheduled end
_G.addEvent = function(fn) fn() end
_G.removeEvent = function() end
_G.tr = function(fmt, ...) if select('#', ...) > 0 then return string.format(fmt, ...) end return fmt end
_G.formatShortNumber = function(n) n = tonumber(n) or 0 if n >= 1000 then return string.format('%.1fk', n / 1000) end return tostring(n) end
_G.comma_value = function(n) return tostring(n) end
_G.table.equal = function(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= 'table' then return a == b end
  for k, v in pairs(a) do if not table.equal(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
_G.displayGeneralBox = function(title, msg, buttons)
  local box = newWidget('box', nil)
  boxes[#boxes + 1] = { title = title, msg = msg, buttons = buttons }
  return box
end
_G.displayInfoBox = function() return newWidget('info', nil) end
_G.destroyPay, _G.hidePay, _G.onPayAction = function() end, function() end, function() end
local topButton = newWidget('button', nil)
_G.modules = { client_topmenu = { addRightGameToggleButton = function() return topButton end } }

dofile(dir .. 'shoptree.lua')
dofile(dir .. 'shopview.lua')
dofile(dir .. 'rotation.lua')
dofile(dir .. 'shopicon.lua')
dofile(dir .. 'tryon.lua')
dofile(dir .. 'shop.lua')

-- ---------------------------------------------------------------- the server's data
local function feed(action, data, status)
  onExtendedJSONOpcode(nil, 218, { action = action, data = data, status = status })
end
local function item(title, cost, extra)
  local o = { type = 'item', item = 2160, count = 1, title = title, description = title .. ' text', cost = cost }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end
local cats = {
  { name = 'Starter', size = 2, type = 'item', item = 8472, pages = 1 },
  { name = 'This week', size = 5, endsIn = 90000, type = 'item', item = 2160, pages = 1 },
  { name = 'Bundles', size = 6, type = 'item', item = 7290, pages = 1 },
  { name = 'Potions', size = 4, parent = 'Consumables', type = 'item', item = 7590, pages = 1 },
  { name = 'Outfits', size = 25, parent = 'Cosmetics', type = 'outfit', outfit = { type = 128, rotating = true }, pages = 3 },
  { name = 'Wings', size = 21, parent = 'Cosmetics', type = 'outfit', outfit = { type = 128 }, pages = 3 },
  { name = 'Crafting', size = 3, type = 'item', item = 32256, pages = 1 },
}
local groups = {
  { name = 'Consumables', size = 4, type = 'item', item = 7590 },
  { name = 'Cosmetics', size = 46, type = 'outfit', outfit = { type = 128 } },
}
local function id(name) return window:recursiveGetChildById(name) end
local function sentActions()
  local out = {}
  for _, s in ipairs(sent) do out[#out + 1] = s.action end
  return table.concat(out, ',')
end

createShop()
eq(window ~= nil, true, 'the window is made')
toggle() -- opens: init
eq(sent[#sent].action, 'init', 'opening asks the server for the list')
feed('category_groups', groups)
feed('categories', cats, { points = 150, buyUrl = '' })

-- the home page
eq(#id('rail'):getChildren(), 7, 'rail: Home, Starter, This week, Bundles, Consumables, Cosmetics, Crafting')
eq(id('rail'):getChildren()[1].name:getText(), 'Home', 'Home first')
eq(id('rail'):getChildren()[1]:isChecked(), true, 'Home is open')
eq(id('home'):isVisible(), true, 'the home page shows')
eq(id('offers'):isVisible(), false, 'not the cards')
eq(id('points'):getText(), '150', 'the balance')
local n = 0
for _, s in ipairs(sent) do if s.action == 'get_page' then n = n + 1 end end
eq(n, 3, 'the pages of the weekly offers, the starter packs and the bundles are asked for')
eq(id('chips'):getHeight(), 0, 'no chips on the home page')
-- the weekly timer on its rail entry and its strip
eq(id('rail'):getChildren()[3].count:getText(), '1d 01h', 'the weekly entry shows its timer')
-- the pages arrive
local weekly = {}
for i = 1, 5 do weekly[i] = item('Week ' .. i, 10 * i, i == 1 and { tags = { 'Featured' }, oldCost = 12, cost = 10 } or nil) end
feed('category_page', { category = 2, page = 1, offers = weekly })
feed('category_page', { category = 3, page = 1, offers = { item('Frostborn Set', 400, { tags = { 'New' } }), item('Infernal Set', 500) } })
feed('category_page', { category = 1, page = 1, offers = { item('Novice Pack', 20), item('Adventurer Pack', 90) } })
local sections = id('home'):getChildren()
eq(#sections, 3, 'three sections on the home page')
eq(sections[1].title:getText(), 'This week', 'the weekly strip on top')
eq(sections[1].props.image, '/images/chaos/panel_highlight', 'highlighted')
eq(sections[1].note:getText(), 'Ends in 1d 01h', 'with its timer')
eq(#sections[1].grid:getChildren(), 5, 'the five weekly offers')
eq(sections[1].grid:getChildren()[1].oldPrice:isVisible(), true, 'an old price shows')
eq(sections[1].grid:getChildren()[1].badge:getText(), '-17%', 'a sale badge from the two prices')
eq(sections[2].title:getText(), 'Starter', 'starter packs after the weekly strip')
eq(sections[3].title:getText(), 'Bundles', 'bundles last')
eq(sections[3].seeAll:isVisible(), true, 'See all (the category holds more than shown)')
eq(sections[3].seeAll:getText(), 'See all (6)', 'with the count')
eq(sections[3].grid:getChildren()[1].badge:getText(), 'New', 'a new badge')
eq(sections[1].grid:getHeight(), 2 * 68 + 6, 'five cards in three columns: two rows')

-- pick a card on the home page
local card = sections[1].grid:getChildren()[2]
card.onMousePress(card, nil, 1)
eq(card:isChecked(), true, 'the picked card is marked')
eq(id('dTitle'):getText(), 'Week 2', 'its name in the details')
eq(id('buyButton'):isVisible(), true, 'Buy is there')
eq(id('buyButton'):isEnabled(), true, 'and on (150 coins, price 20)')
eq(id('dNote'):getText(), '', 'no note')
eq(id('lookPreview'):isVisible(), false, 'an item has no look: the preview column stays shut')

-- a card the coins do not reach
local dear = sections[3].grid:getChildren()[2]
dear.onMousePress(dear, nil, 1)
eq(id('buyButton'):isEnabled(), false, 'Buy off: 500 coins against 150')
eq(id('dNote'):getText(), 'Not enough Chaos Coins. You need 350 more.', 'the coins short')
eq(dear.price.props.color, '#e03a1e', 'the card price is red')
-- the balance grows: the card and the pane follow
feed('message', { title = 'Thanks', msg = 'coins' }, { points = 900 })
eq(id('buyButton'):isEnabled(), true, 'Buy on with 900 coins')
eq(dear.price.props.color, '#f6cf72', 'the price is gold again')
eq(id('dNote'):getText(), '', 'note gone')

-- Buy: a confirmation, then the payload
local before = #sent
dear.onDoubleClick(dear)
for _, s in ipairs(scheduled) do if s.ms == 50 then s.fn() end end
eq(#boxes >= 1, true, 'a confirmation box asks')
eq(boxes[#boxes].msg, 'Do you want to buy Infernal Set for 500 Chaos Coins?', 'with the name and the price')
boxes[#boxes].buttons[1].callback()
local buy = sent[#sent]
eq(buy.action, 'buy', 'the buy action')
eq(buy.data.category .. ':' .. buy.data.page .. ':' .. buy.data.offer, '3:1:2', 'where the server has the offer')
eq(buy.data.title .. ':' .. buy.data.cost, 'Infernal Set:500', 'the title and the price shown')
eq(#sent, before + 1, 'one request')

-- the rail: Cosmetics opens its first subcategory with chips
sent = {}
local cosmetics = id('rail'):getChildren()[6]
eq(cosmetics.railKey, 'g:Cosmetics', 'the rail key of a group')
cosmetics.onMousePress(cosmetics, nil, 1)
eq(sentActions(), 'get_page', 'a page is asked for')
eq(sent[1].data.category, 5, 'the first subcategory')
eq(cosmetics:isChecked(), true, 'Cosmetics is open')
eq(id('rail'):getChildren()[1]:isChecked(), false, 'Home is not')
eq(#id('chips'):getChildren(), 2, 'two chips')
eq(id('chips'):getChildren()[1].props.text, 'Outfits (25)', 'name and count')
eq(id('chips'):getChildren()[1]:isChecked(), true, 'the open subcategory is checked')
eq(id('chips'):getHeight(), 22, 'one chip row')
eq(id('pathLabel'):getText(), 'Cosmetics > Outfits', 'the path')
eq(id('pathCount'):getText(), '25 offers', 'the subtle count')
eq(id('pageControls'):isVisible(), true, 'three pages: the pager')
eq(id('pageLabel'):getText(), '1 / 3', 'page 1 of 3')
eq(id('prevPage'):isEnabled(), false, 'no page before the first')
-- its page arrives
local outfits = {}
for i = 1, 10 do outfits[i] = { type = 'outfit', outfit = { type = 128 }, title = 'Outfit ' .. i, description = 'd', cost = 100, gift = true,
  owned = (i == 2) or nil } end
feed('category_page', { category = 5, page = 1, offers = outfits })
eq(id('offers'):isVisible(), true, 'the cards show')
eq(#id('offers'):getChildren(), 10, 'ten cards')
-- an owned card
local owned = id('offers'):getChildren()[2]
owned.onMousePress(owned, nil, 1)
eq(id('buyButton'):isEnabled(), false, 'owned: Buy off')
eq(id('dNote'):getText(), 'You already own this.', 'owned note')
eq(owned.badge:getText(), 'Owned', 'owned badge')
eq(id('giftButton'):isVisible(), true, 'Gift stays for a giftable offer')
local c1 = id('offers'):getChildren()[1]
c1.onMousePress(c1, nil, 1)
eq(owned:isChecked(), false, 'only one card is picked')
eq(id('giftButton'):isEnabled(), true, 'Gift on')
-- next page
sent = {}
id('nextPage').onClick()
eq(sent[1].data.page, 2, 'the next page')
-- another chip
id('chips'):getChildren()[2].onClick()
eq(sent[2].data.category, 6, 'the other subcategory')
eq(id('pathLabel'):getText(), 'Cosmetics > Wings', 'the path follows')

-- a top category has no chips
local crafting = id('rail'):getChildren()[7]
crafting.onMousePress(crafting, nil, 1)
eq(#id('chips'):getChildren(), 0, 'no chips for a top category')
eq(id('chips'):getHeight(), 0, 'no room for them')
eq(id('pageControls'):isVisible(), false, 'one page: no pager')

-- the search with its filter chips
sent = {}
id('searchText').props.text = 'set'
onSearchChange()
local ev = scheduled[#scheduled]
eq(ev.ms, 400, 'the search waits for the typing to stop')
ev.fn()
eq(sent[#sent].action, 'search', 'the server looks')
feed('search_results', { text = 'set', offers = {
  item('Frostborn Set', 400, { at = { category = 3, page = 1, offer = 1 }, path = { 'Bundles' } }),
  item('Set of Wings', 100, { at = { category = 6, page = 1, offer = 2 }, path = { 'Cosmetics', 'Wings' } }),
  item('Set of Auras', 100, { at = { category = 6, page = 1, offer = 3 }, path = { 'Cosmetics', 'Wings' } }),
} })
eq(#id('offers'):getChildren(), 3, 'three results')
eq(#id('chips'):getChildren(), 3, 'All, Bundles, Cosmetics')
eq(id('chips'):getChildren()[1].props.text, 'All (3)', 'All with the total')
eq(id('rail'):getChildren()[6]:isChecked(), false, 'no rail entry is open in a search')
eq(id('pathLabel'):getText(), 'Search "set": 3 offers', 'the path says so')
id('chips'):getChildren()[3].onClick() -- Cosmetics
eq(#id('offers'):getChildren(), 2, 'the group filter')
eq(id('chips'):getChildren()[3]:isChecked(), true, 'the chip is on')
local hit = id('offers'):getChildren()[1]
hit.onMousePress(hit, nil, 1)
eq(id('buyButton'):isVisible(), true, 'a result can be bought')
eq(id('dDesc'):getText(), 'Cosmetics > Wings: Set of Wings text', 'with where it is')
-- nothing found
feed('search_results', { text = 'set', offers = {} })
eq(#id('offers'):getChildren(), 0, 'no cards')
eq(id('emptyLabel'):isVisible(), true, 'the page says so')
-- the search cleared: back to a category
id('searchText').props.text = ''
onSearchChange()
eq(id('emptyLabel'):isVisible(), false, 'the empty note is gone')
eq(id('rail'):getChildren()[7]:isChecked(), true, 'the category before the search is open again')

-- the history: lines without buttons
sent = {}
showHistory()
eq(sent[1].action, 'history', 'the server is asked')
feed('history', { { type = 'item', item = 29856, count = 1, cost = 40, title = 'Frostborn Set',
  description = 'Bought on 2026-11-14 12:30 for 40 Chaos Coins.' } })
eq(#id('offers'):getChildren(), 1, 'one line')
local line = id('offers'):getChildren()[1]
eq(line.sub:getText(), '2026-11-14 12:30', 'the date')
eq(line.badge:getText(), 'Bought', 'the badge')
line.onMousePress(line, nil, 1)
eq(id('buyButton'):isVisible(), false, 'a history line has no Buy')
eq(id('pathLabel'):getText(), 'Transaction history', 'the path')
line.onDoubleClick(line)
eq(#boxes, 1, 'a double click on a history line asks nothing')

-- the home page again from the rail, and a category opened from another module
sent = {}
local home = id('rail'):getChildren()[1]
home.onMousePress(home, nil, 1)
eq(id('home'):isVisible(), true, 'Home again')
eq(#id('home'):getChildren(), 3, 'its sections are built from the pages that are here')
openCategory('Potions')
eq(sent[#sent].data.category, 4, 'openCategory shows that category')
eq(id('rail'):getChildren()[5]:isChecked(), true, 'in its group')

-- closing and opening again: the home page, not the last category
hide()
toggle()
feed('category_groups', groups)
feed('categories', cats, { points = 900 })
eq(id('home'):isVisible(), true, 'opening again: the home page')
-- a refresh while a category is open keeps it (a purchase)
local pot = id('rail'):getChildren()[5]
pot.onMousePress(pot, nil, 1)
feed('categories', cats)
eq(id('home'):isVisible(), false, 'a refresh keeps the category')
eq(id('pathLabel'):getText(), 'Consumables > Potions', 'the same one')
-- an old server: no weekly, no starter, no bundles, no groups: no home entry, the first category opens
hide()
toggle()
feed('category_groups', {})
feed('categories', { { name = 'Wings', size = 3, type = 'item', item = 1, pages = 1 }, { name = 'Auras', size = 2, type = 'item', item = 2, pages = 1 } })
eq(#id('rail'):getChildren(), 2, 'a flat server: two entries, no Home')
eq(id('home'):isVisible(), false, 'no home page')
eq(id('pathLabel'):getText(), 'Wings', 'the first category')

if fails > 0 then print(fails .. ' of ' .. checks .. ' checks FAILED') os.exit(1) end
print('shop_ui_test: ' .. checks .. ' checks OK')
