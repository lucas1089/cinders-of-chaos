-- Guild Wars window: declare a war (target, frag limit, duration, gold stake), answer offers, the running wars with
-- their score and kill log, surrender; the server's war board (current wars and history); the weekly guild boss
-- (the Summoning Stone's fuel, gold and material donations, the summon, the banner, the weekly board).
-- Server: server/data/scripts/chaos/guildwar.lua + guildboss.lua, extended opcode 197 (JSON {action, data}; the state
-- comes through Chaos.sendChunked, so it is read with ProtocolGame.registerExtendedJSONOpcode).
--   server -> client  state {open, tab, guild, options, wars {pending, active, history}, board {active, history}, boss}
--                     message {ok, text} | log {id, title, score, lines}
--   client -> server  open {tab} | refresh {tab} | close | declare {target, fragLimit, hours, stake} | accept {id} |
--                     decline {id} | cancel {id} | surrender {id} | log {id} | bossGold {amount} | bossItem {key} |
--                     bossSummon
-- Menu: Social > Guild Wars (ChaosTopBar.addEntry); the guild hall's Summoning Stone opens the Guild Boss tab.

local OPCODE = 197
local TABS = {
  { key = 'wars', text = 'Wars' },
  { key = 'declare', text = 'Declare War' },
  { key = 'board', text = 'War Board' },
  { key = 'boss', text = 'Guild Boss' },
}

local window
local state
local currentTab = 'wars'
local tabButtons = {}
local warLog
local form = { target = '', fragIndex = 2, hoursIndex = 2, stake = '' }
local confirmSurrender
local handlers = {}
local reported = {}

local V = GuildWarView

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[guildwar] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

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
  local w = g_ui.createWidget('GuildWarSection', rows())
  w:setText(text)
  return w
end

local function text(t, color)
  local w = g_ui.createWidget('GuildWarText', rows())
  w:setText(t)
  if color then w:setColor(color) end
  return w
end

local function warRow(w, b1, b2)
  local r = g_ui.createWidget('GuildWarRow', rows())
  r.title:setText(V.title(w))
  r.title:setColor(V.color(w))
  r.sub:setText(V.status(w))
  r.terms:setText(tostring(w.terms or ''))
  r:setTooltip(tostring(w.terms or ''))
  for i, spec in ipairs({ b1 or false, b2 or false }) do
    local btn = r['button' .. i]
    if spec then
      btn:setText(spec.text)
      btn:setEnabled(spec.enabled ~= false)
      if spec.tooltip then btn:setTooltip(spec.tooltip) end
      btn.onClick = spec.click
    else
      btn:setVisible(false)
      btn:setWidth(0)
    end
  end
  return r
end

-- ---------------------------------------------------------------- tabs
local function fillWars(d)
  local g = d.guild
  if not g then
    text(tr('You are not in a guild. The War Board shows the wars of the server.'), '#8c8070')
    return
  end
  local canAnswer = g.canDeclare
  local pending = list(d.wars and d.wars.pending)
  local active = list(d.wars and d.wars.active)
  section(tr('Offers'))
  if #pending == 0 then text(tr('No open offers.'), '#8c8070') end
  for _, w in ipairs(pending) do
    if w.incoming then
      local needLeader = (tonumber(w.stake) or 0) > 0 and not g.canStake
      warRow(w,
        { text = tr('Accept'), enabled = canAnswer and not needLeader, click = function() send('accept', { id = w.id }) end,
          tooltip = needLeader and tr('A war with gold at stake is accepted by the guild leader.') or nil },
        { text = tr('Decline'), enabled = canAnswer, click = function() send('decline', { id = w.id }) end })
    else
      warRow(w, { text = tr('Take back'), enabled = canAnswer, click = function() send('cancel', { id = w.id }) end })
    end
  end
  section(tr('Running wars'))
  if #active == 0 then text(tr('Your guild is at peace.'), '#8c8070') end
  for _, w in ipairs(active) do
    local sure = confirmSurrender == w.id
    warRow(w,
      { text = sure and tr('Sure?') or tr('Surrender'), enabled = canAnswer, click = function()
        if confirmSurrender == w.id then
          confirmSurrender = nil
          send('surrender', { id = w.id })
        else
          confirmSurrender = w.id
          render()
        end
      end, tooltip = tr('The other guild wins the war and both stakes.') },
      { text = tr('Kill log'), click = function() send('log', { id = w.id }) end })
  end
  if warLog then
    section(tr('Kill log: %s (%s)', tostring(warLog.title or ''), tostring(warLog.score or '')))
    local lines = list(warLog.lines)
    if #lines == 0 then text(tr('No kills yet.'), '#8c8070') end
    for _, k in ipairs(lines) do text(V.killLine(k), k.counted and '#d6c9ae' or '#8c8070') end
  end
  section(tr('History'))
  local hist = list(d.wars and d.wars.history)
  if #hist == 0 then text(tr('No wars yet.'), '#8c8070') end
  for _, w in ipairs(hist) do
    warRow(w, w.status == 'ended' and { text = tr('Kill log'), click = function() send('log', { id = w.id }) end } or nil)
  end
  local o = d.options or {}
  text(tr('Counted kills: a victim of level %d or more (and at least half the killer\'s level), not from the same IP or account, the same victim once per %d minutes.',
    tonumber(o.minVictimLevel) or 0, tonumber(o.sameVictimMinutes) or 0), '#8c8070')
end

local function fillDeclare(d)
  local g = d.guild
  local o = d.options or {}
  if not g then
    text(tr('You are not in a guild.'), '#8c8070')
    return
  end
  section(tr('Declare war'))
  if not g.canDeclare then
    text(tr('Only the guild leader and the vice-leaders declare war.'), '#e05a4a')
  end
  local target = g_ui.createWidget('GuildWarFormEdit', rows())
  target.label:setText(tr('Guild'))
  target.edit:setText(form.target)
  target.edit.onTextChange = function(_, t) form.target = t end
  local frag = g_ui.createWidget('GuildWarFormCombo', rows())
  frag.label:setText(tr('Frag limit'))
  for _, n in ipairs(list(o.fragLimits)) do frag.combo:addOption(tr('%d kills', n), n) end
  pcall(function() frag.combo:setCurrentIndex(form.fragIndex) end)
  frag.combo.onOptionChange = function(c) form.fragIndex = c.currentIndex or form.fragIndex end
  local dur = g_ui.createWidget('GuildWarFormCombo', rows())
  dur.label:setText(tr('Duration'))
  for _, h in ipairs(list(o.durations)) do dur.combo:addOption(tr(V.hoursText(h)), h) end
  pcall(function() dur.combo:setCurrentIndex(form.hoursIndex) end)
  dur.combo.onOptionChange = function(c) form.hoursIndex = c.currentIndex or form.hoursIndex end
  local stake = g_ui.createWidget('GuildWarFormEdit', rows())
  stake.label:setText(tr('Gold stake per side'))
  stake.edit:setText(form.stake)
  stake.edit:setEnabled(g.canStake == true)
  stake.edit.onTextChange = function(_, t) form.stake = t end
  text(g.canStake and tr('Optional (empty = none): %s to %s gold from the guild bank (%s gold). The winner gets both stakes minus %d%%.',
    V.money(o.stakeMin), V.money(o.stakeMax), V.money(g.bank), tonumber(o.fee) or 0)
    or tr('Only the guild leader can put gold at stake.'), '#8c8070')
  local row = g_ui.createWidget('GuildWarButtonRow', rows())
  row.button:setText(tr('Declare war'))
  row.button:setEnabled(g.canDeclare == true)
  row.button.onClick = function()
    local fo, ho = frag.combo:getCurrentOption(), dur.combo:getCurrentOption()
    local req, why = V.declareRequest({ target = form.target, fragLimit = fo and fo.data, hours = ho and ho.data,
      stake = form.stake }, o)
    if not req then
      window.statusLabel:setText(why)
      window.statusLabel:setColor('#e05a4a')
      return
    end
    send('declare', req)
  end
  row.label:setText(tr('The other guild accepts or declines in game within %d hours.', tonumber(o.offerHours) or 24))
  text(tr('Wars use the guild war emblems: kills between the two guilds give no skull. They end at the frag limit, when the time is up (more kills wins, a tie is a draw) or by surrender. Season characters fight only guilds of their own realm.'),
    '#8c8070')
  if o.emblemsLive == false then
    text(tr('The war emblems show after the next login.'), '#8c8070')
  end
end

local function fillBoard(d)
  local b = d.board or {}
  section(tr('Wars now'))
  local act = list(b.active)
  if #act == 0 then text(tr('No guilds are at war.'), '#8c8070') end
  for _, w in ipairs(act) do text(V.boardLine(w), '#e8b84a') end
  section(tr('Latest wars'))
  local hist = list(b.history)
  if #hist == 0 then text(tr('No war has ended yet.'), '#8c8070') end
  for _, w in ipairs(hist) do text(V.boardLine(w)) end
  text(tr('The website shows the same board.'), '#8c8070')
end

local function fillBoss(d)
  local b = d.boss or {}
  section(tr('%s, the weekly guild boss', tostring(b.boss or '?')))
  local stateText, stateColor = V.bossState(b)
  if b.guild then
    local bar = g_ui.createWidget('GuildWarFuelBar', rows())
    bar:setPercent(V.fuelPercent(b))
    bar:setText(V.fuelText(b))
    text(stateText, stateColor)
    text(V.attemptsText(b) .. tr(' - week resets in %s', V.duration(b.resetIn)), '#8c8070')
    local summon = g_ui.createWidget('GuildWarButtonRow', rows())
    summon.button:setText(tr('Summon'))
    summon.button:setEnabled(b.canSummon == true)
    summon.button.onClick = function() send('bossSummon') end
    summon.label:setText(tr('%d in the hall now', tonumber(b.players) or 0))
    text(tr('The leader or a vice-leader summons it in the guild hall: every member in the hall (level %d+, %d to %d) comes along.',
      tonumber(b.minLevel) or 0, tonumber(b.minPlayers) or 0, tonumber(b.maxPlayers) or 0), '#8c8070')
    section(tr('Feed the Summoning Stone'))
    local gold = g_ui.createWidget('GuildWarGoldRow', rows())
    local per = b.gold and b.gold.perEmber or 0
    gold.label:setText(tr('%s gold = 1 ember (at least %s)', V.money(per), V.money(b.gold and b.gold.min)))
    gold.amount.onTextChange = function(_, t)
      gold.label:setText(tr('%d embers', V.goldEmbers(t, per)))
    end
    gold.button:setEnabled(not b.killed)
    gold.button.onClick = function()
      local n = V.parseAmount(gold.amount:getText())
      if n and n > 0 then send('bossGold', { amount = n }) end
    end
    for _, m in ipairs(list(b.materials)) do
      local r = g_ui.createWidget('GuildWarItemRow', rows())
      if (tonumber(m.clientId) or 0) > 0 then r.item:setItemId(m.clientId) end
      r.label:setText(tr('%s: %d embers each (you carry %d)', tostring(m.name or '?'), tonumber(m.embers) or 0, tonumber(m.have) or 0))
      r.button:setText(tr('Feed all'))
      r.button:setEnabled((tonumber(m.have) or 0) > 0 and not b.killed)
      r.button.onClick = function() send('bossItem', { key = m.key }) end
    end
    section(tr('Guild banner'))
    text(V.bannerText(b.banner))
    section(tr('This week\'s fuel'))
    local cs = list(b.contributors)
    if #cs == 0 then text(tr('No embers yet.'), '#8c8070') end
    for _, c in ipairs(cs) do text(V.contributorLine(c)) end
  else
    text(stateText, stateColor)
  end
  section(tr('Guild boss board this week'))
  local board = list(b.board)
  if #board == 0 then text(tr('No guild has fought it this week.'), '#8c8070') end
  for _, r in ipairs(board) do text(V.bossBoardLine(r), r.own and '#ffe7a6' or nil) end
end

local FILL = { wars = fillWars, declare = fillDeclare, board = fillBoard, boss = fillBoss }

function render()
  if not window then return end
  rows():destroyChildren()
  for key, b in pairs(tabButtons) do b:setChecked(key == currentTab) end
  if not state then return end
  local g = state.guild
  if g then
    window.header:setText(tostring(g.name or ''))
    window.subLine:setText(tr('%d of %d wars and offers. Guild bank: %s gold.', tonumber(g.wars) or 0,
      tonumber(state.options and state.options.maxWars) or 0, V.money(g.bank)))
  else
    window.header:setText(tr('Guild Wars'))
    window.subLine:setText('')
  end
  local fill = FILL[currentTab] or fillWars
  local ok, err = pcall(fill, state)
  if not ok then g_logger.error('[guildwar] ' .. tostring(err)) end
end

local function selectTab(key)
  currentTab = key
  confirmSurrender = nil
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
  if window and window:isVisible() then
    window:hide()
    send('close')
  end
end

function toggle()
  if not window then return end
  if window:isVisible() then
    hide()
    return
  end
  send('open') -- the server answers with state, which shows the window
end

function openTab(key)
  if FILL[key] then currentTab = key end
  send('open', { tab = currentTab })
end

local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' then return end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    state = data
    if data.open and data.tab and FILL[data.tab] then currentTab = data.tab end
    render()
    if data.open then show() end
  elseif msg.action == 'message' then
    window.statusLabel:setText(tostring(data.text or ''))
    window.statusLabel:setColor(data.ok and '#9fd68a' or '#e05a4a')
  elseif msg.action == 'log' then
    warLog = data
    if currentTab == 'wars' then render() end
  end
end

-- offline rendering and tests: feed a server message as if it came on the opcode
function receive(msg)
  onMessage(nil, OPCODE, type(msg) == 'string' and json.decode(msg) or msg)
end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    handlers.menu = pcall(api.addEntry, 'social', { text = 'Guild Wars', icon = 'pvp', modules = { 'game_guildwar' }, fns = { 'toggle' } })
  end
end

local function onGameStart()
  addMenu()
end

local function onGameEnd()
  if window then window:hide() end
  state, warLog, confirmSurrender = nil, nil, nil
end

function init()
  window = g_ui.displayUI('guildwar')
  window:hide()
  for _, t in ipairs(TABS) do
    local b = g_ui.createWidget('GuildWarTab', window.tabs)
    b:setText(tr(t.text))
    b.onClick = function() selectTab(t.key) end
    tabButtons[t.key] = b
  end
  handlers.opcode = safe('opcode', onMessage)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, handlers.game or {})
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  if window then window:destroy() window = nil end
  tabButtons = {}
  state, warLog = nil, nil
  handlers = {}
end
