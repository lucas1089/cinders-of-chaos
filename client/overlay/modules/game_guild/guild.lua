-- Guild window: guild level and XP bar, perks, members' contribution, guild bank, guild hall (status, rent, upgrades
-- with buttons for the leader and vice-leaders), guild depot with its log, and the weekly "Top guild" board.
-- Server: server/data/scripts/chaos/guild.lua + guild_hall.lua, extended opcode 252 (JSON {action, data}).
--   server -> client  state {open, tab, guild, perks = {now, list}, members, hall, depot, log, top}
--                     none {open, text}          (not in a guild)
--                     message {ok, text}         (result of an action, shown under the list)
--                     openModule {name}          (the hall's crafting bench opens game_crafting)
--   client -> server  open {tab} | refresh {tab} | deposit {amount} | withdraw {amount} | buyHall {from} |
--                     upgrade {key} | payRent | take {id} | scroll
-- The top menu (Social -> Guild) calls toggle().

local OPCODE = 252
local TABS = {
  { key = 'overview', text = 'Overview' },
  { key = 'members', text = 'Members' },
  { key = 'hall', text = 'Guild Hall' },
  { key = 'depot', text = 'Depot' },
  { key = 'top', text = 'Top Guilds' },
}

local window
local state
local currentTab = 'overview'
local tabButtons = {}

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    data = data or {}
    data.tab = data.tab or currentTab
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data }))
  end
end

local function list(value)
  local out = {}
  if type(value) == 'table' then
    for _, v in ipairs(value) do out[#out + 1] = v end
  end
  return out
end

-- ---------------------------------------------------------------- rows
local function rows() return window.rowList end

local function section(text)
  local w = g_ui.createWidget('GuildSection', rows())
  w:setText(text)
  return w
end

local function text(t, color)
  local w = g_ui.createWidget('GuildText', rows())
  w:setText(t)
  if color then w:setColor(color) end
  return w
end

local function buttonRow(label, buttonText, enabled, onClick, right, tooltip, color)
  local w = g_ui.createWidget('GuildButtonRow', rows())
  w.label:setText(label)
  if color then w.label:setColor(color) end
  w.right:setText(right or '')
  if buttonText then
    w.button:setText(buttonText)
    w.button:setEnabled(enabled and true or false)
    if tooltip and tooltip ~= '' then w.button:setTooltip(tooltip) end
    w.button.onClick = onClick
  else
    w.button:setVisible(false)
    w.button:setWidth(0)
  end
  return w
end

-- ---------------------------------------------------------------- tabs
local function fillOverview(d)
  local g = d.guild or {}
  section(tr('Perks for online members'))
  text(GuildMath.perksNow(d.perks and d.perks.now), '#9fd68a')
  for _, p in ipairs(list(d.perks and d.perks.list)) do
    text(string.format('%s %d: %s', tr('Level'), tonumber(p.level) or 0, tostring(p.text or '')), p.active and '#d6c9ae' or '#6b6258')
  end
  if g.scroll then
    buttonRow(tr('Guild hall scroll (one a day)'), tr('Take'), not g.scrollTaken, function() send('scroll') end,
      g.scrollTaken and tr('taken today') or '')
  end
  section(tr('Guild bank: %s gold', GuildMath.money(g.bank)))
  local bank = g_ui.createWidget('GuildBankRow', rows())
  bank.amount:setText('')
  bank.deposit.onClick = function()
    local n = GuildMath.parseAmount(bank.amount:getText())
    if n then send('deposit', { amount = n }) end
  end
  bank.withdraw:setEnabled(g.canWithdraw == true)
  bank.withdraw:setTooltip(g.canWithdraw and '' or tr('Only the guild leader can withdraw.'))
  bank.withdraw.onClick = function()
    local n = GuildMath.parseAmount(bank.amount:getText())
    if n then send('withdraw', { amount = n }) end
  end
  text(tr('Deposits come from your carried gold, then your bank balance (at least %s). Withdrawals go to the leader\'s bank balance.',
    GuildMath.money(g.minDeposit)), '#8c8070')
  if modules.game_guildwar then -- wars and the weekly guild boss have their own window (game_guildwar, opcode 197)
    buttonRow(tr('Guild wars and the weekly guild boss'), tr('Open'), true, function() modules.game_guildwar.openTab('wars') end)
  end
  section(tr('Guild log'))
  local log = list(d.log)
  if #log == 0 then text(tr('Nothing yet.'), '#8c8070') end
  for _, line in ipairs(log) do text(tostring(line)) end
end

local function fillMembers(d)
  section(tr('Contribution (guild XP)'))
  local members = list(d.members)
  if #members == 0 then text(tr('No members.'), '#8c8070') end
  for _, m in ipairs(members) do
    buttonRow(GuildMath.memberText(m), nil, false, nil, GuildMath.memberPoints(m), nil, m.online and '#9fd68a' or nil)
  end
  text('Guild XP comes from experience (a 1 percent share, capped per day), bounties, rifts, world bosses, invasions and the guild siege.', '#8c8070')
end

local function fillHall(d)
  local h = d.hall or {}
  if not h.owned then
    section(tr('Guild hall'))
    text(tr('A guild hall costs %s gold and needs guild level %d. The guild leader buys it.', GuildMath.money(h.cost), tonumber(h.level) or 0))
    buttonRow(tr('Pay from the guild bank'), tr('Buy'), h.canBuyBank, function() send('buyHall', { from = 'bank' }) end, nil, h.reason)
    buttonRow(tr('Pay with your own gold'), tr('Buy'), h.canBuySelf, function() send('buyHall', { from = 'self' }) end, nil, h.reasonSelf)
    if h.reason and h.reason ~= '' then text(h.reason, '#8c8070') end
    return
  end
  section(tr('Guild hall (slot %d)', tonumber(h.slot) or 0))
  text(GuildMath.rentText(h), GuildMath.rentColor(h))
  buttonRow(tr('Weekly rent from the guild bank'), tr('Pay rent'), h.canManage, function() send('payRent') end,
    GuildMath.money(h.rent) .. ' gold', h.canManage and '' or tr('Leader and vice-leaders only.'))
  text(tr('Enter through the portal next to the temple. Unpaid rent locks the upgrades; nothing is deleted.'), '#8c8070')
  section(tr('Upgrades'))
  for _, u in ipairs(list(h.upgrades)) do
    local maxed = (tonumber(u.tier) or 0) >= (tonumber(u.max) or 1)
    local row = buttonRow(GuildMath.upgradeText(u), maxed and nil or tr('Buy'), h.canManage and u.canBuy,
      function() send('upgrade', { key = u.key }) end, nil, u.reason, maxed and (u.active and '#9fd68a' or '#e05a4a') or nil)
    row:setTooltip(tostring(u.info or ''))
  end
  if #list(h.hub) > 0 then
    section(tr('Teleport hub'))
    text(table.concat(list(h.hub), ', '))
  end
end

local function fillDepot(d)
  local dep = d.depot or {}
  if not dep.owned then
    section(tr('Guild depot'))
    text(tr('Your guild hall has no guild depot yet (a hall upgrade).'), '#8c8070')
    return
  end
  section(tr('Guild depot (%d / %d)%s', tonumber(dep.used) or 0, tonumber(dep.capacity) or 0, dep.active and '' or tr(' - LOCKED')))
  text(tr('Drop an item on the large trunk in your guild hall to store it. Take items back here (in the hall).'), '#8c8070')
  local items = list(dep.items)
  if #items == 0 then text(tr('Empty.'), '#8c8070') end
  for _, it in ipairs(items) do
    local w = g_ui.createWidget('GuildItemRow', rows())
    if (tonumber(it.clientId) or 0) > 0 then w.item:setItemId(it.clientId) end
    if (tonumber(it.count) or 1) > 1 then w.item:setItemCount(it.count) end
    w.label:setText(string.format('%d x %s', tonumber(it.count) or 1, tostring(it.name or '?')))
    w.button:setEnabled(dep.active == true)
    w.button.onClick = function() send('take', { id = it.id }) end
  end
  section(tr('Depot log'))
  local log = list(dep.log)
  if #log == 0 then text(tr('Nothing yet.'), '#8c8070') end
  for _, line in ipairs(log) do text(tostring(line)) end
end

local function fillTop(d)
  local top = d.top or {}
  section(tr('Top guilds this week (resets in %s)', GuildMath.duration(top.resetIn)))
  local r = list(top.rows)
  if #r == 0 then text(tr('No guild earned guild XP this week yet.'), '#8c8070') end
  for _, t in ipairs(r) do
    buttonRow(GuildMath.topText(t), nil, false, nil, GuildMath.money(t.points) .. ' GXP', nil, t.own and '#ffe7a6' or nil)
  end
  if top.lastWinner and top.lastWinner ~= '' then
    text(tr('Top guild of last week: %s', top.lastWinner), '#f6cf72')
  end
end

local FILL = { overview = fillOverview, members = fillMembers, hall = fillHall, depot = fillDepot, top = fillTop }

local function render()
  if not window then return end
  rows():destroyChildren()
  for key, b in pairs(tabButtons) do b:setChecked(key == currentTab) end
  if not state then return end
  local g = state.guild or {}
  window.guildName:setText(tostring(g.name or ''))
  window.levelLabel:setText(GuildMath.levelText(g))
  window.xpBar:setPercent(GuildMath.percent(g))
  window.xpBar:setText(GuildMath.xpText(g))
  window.subLine:setText(tr('You: %s. This week: %s GXP%s.', tostring(g.rankName or ''), GuildMath.money(g.weekPoints),
    (tonumber(g.weekRank) or 0) > 0 and tr(', rank %d of the guilds', g.weekRank) or ''))
  local fill = FILL[currentTab] or fillOverview
  local ok, err = pcall(fill, state)
  if not ok then g_logger.error('[guild] ' .. tostring(err)) end
end

local function selectTab(key)
  currentTab = key
  render()
  send('refresh')
end

-- ---------------------------------------------------------------- window
function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
end

function hide()
  if window then window:hide() end
end

function toggle()
  if not window then return end
  if window:isVisible() then
    hide()
    return
  end
  send('open') -- the server answers with state, which shows the window
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then
    g_logger.error('[guild] invalid JSON: ' .. tostring(msg))
    return
  end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    -- the parts the window indexes are tables, or left out (game_chaosguard/opcode_fuzz_test.lua)
    for _, k in ipairs({ 'guild', 'perks' }) do
      if type(data[k]) ~= 'table' then data[k] = nil end
    end
    state = data
    if data.open and data.tab and FILL[data.tab] then currentTab = data.tab end
    render()
    if data.open then show() end
  elseif msg.action == 'none' then
    state = nil
    render()
    window.guildName:setText(tr('No guild'))
    window.levelLabel:setText('')
    window.xpBar:setPercent(0)
    window.xpBar:setText('')
    window.subLine:setText('')
    window.statusLabel:setText(tostring(data.text or ''))
    if data.open then show() end
  elseif msg.action == 'message' then
    window.statusLabel:setText(tostring(data.text or ''))
    window.statusLabel:setColor(data.ok and '#9fd68a' or '#e05a4a')
  elseif msg.action == 'openModule' then
    local mod = type(data.name) == 'string' and modules[data.name]
    if mod and mod.toggle then
      pcall(mod.toggle)
    end
  end
end

local function onGameEnd()
  hide()
  state = nil
end

function init()
  window = g_ui.displayUI('guild')
  window:hide()
  for _, t in ipairs(TABS) do
    local b = g_ui.createWidget('GuildTab', window.tabs)
    b:setText(tr(t.text))
    b.onClick = function() selectTab(t.key) end
    tabButtons[t.key] = b
  end
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if window then window:destroy() window = nil end
  tabButtons = {}
  state = nil
end
