-- Guild siege: HUD over the map during a siege and the sign-up window.
-- Server: server/data/scripts/chaos/siege.lua, extended opcode 233 (JSON {action, data}).
--   server -> client  hud {phase = gather|match|ending, left, bracket, brackets, teams = [{name, score, kills, color, side,
--                          own, members}], holder, holderColor, contested, you = {kills, deaths, points},
--                          result = {winner, standings} (when ending)}       sent every second to players inside
--                     hide {}                                                   the player left the siege / it is over
--                     info {open, phase, whenText, inSeconds, signupsOpen, signups = [{name, own}], capacity, guild,
--                           rank, signed, members, canJoin, joinReason, canLeave, champions = [{name, untilText}],
--                           status, rules = [text]}
--   client -> server  open | join | leave
-- The top menu (Adventure > Guild Siege) calls toggle().

local OPCODE = 233

local hud
local window
local info
local infoAt = 0
local tickEvent

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function list(value)
  local out = {}
  if type(value) == 'table' then
    for _, v in ipairs(value) do out[#out + 1] = v end
  end
  return out
end

local function short(n)
  n = tonumber(n) or 0
  if formatShortNumber then return formatShortNumber(n) end
  return tostring(n)
end

-- ---------------------------------------------------------------- HUD
local function updateHud(data)
  if not hud then return end
  hud:setVisible(true)
  hud.title:setText(SiegeMath.title(data))
  if data.phase == 'ending' then
    hud.clock:setText(tr('Final score'))
  else
    hud.clock:setText(SiegeMath.clock(data.left))
  end
  local text, color = SiegeMath.holder(data)
  hud.holder:setText(text)
  hud.holder:setColor(color)
  hud.teams:destroyChildren()
  for _, t in ipairs(SiegeMath.sorted(data.teams)) do
    local row = g_ui.createWidget('SiegeTeamRow', hud.teams)
    row.swatch:setBackgroundColor(t.color or '#8c8070')
    row.name:setText(tostring(t.name or '?') .. ((tonumber(t.members) or 0) > 0 and (' (' .. t.members .. ')') or ''))
    row.name:setColor(t.own and '#ffe7a6' or '#e8dcc2')
    row.kills:setText(tostring(tonumber(t.kills) or 0) .. ' K')
    row.score:setText(short(t.score))
  end
  hud.you:setText(SiegeMath.youText(data.you))
  hud.you:setVisible(data.you ~= nil)
end

local function hideHud()
  if hud then hud:setVisible(false) end
end

-- ---------------------------------------------------------------- window
local function fillList(panel, lines, empty, color)
  panel:destroyChildren()
  if #lines == 0 then
    local l = g_ui.createWidget('SiegeListLabel', panel)
    l:setText(empty)
    l:setColor('#8c8070')
    return
  end
  for _, line in ipairs(lines) do
    local l = g_ui.createWidget('SiegeListLabel', panel)
    l:setText(line.text)
    if line.color then l:setColor(line.color) elseif color then l:setColor(color) end
  end
end

local function tick()
  tickEvent = nil
  if not window or not info or not window:isVisible() then return end
  local left = (tonumber(info.inSeconds) or 0) - (g_clock.seconds() - infoAt)
  if info.phase == 'idle' then
    window.countdown:setText(tr('Starts in %s', SiegeMath.countdown(left)))
  else
    window.countdown:setText(tr('Running'))
  end
  tickEvent = scheduleEvent(tick, 1000)
end

local function updateWindow(data)
  info = data
  infoAt = g_clock.seconds()
  window.nextLabel:setText(tr('Next siege: %s (server time)', data.whenText or '?'))
  window.status:setText(data.status or '')
  if data.guild and data.guild ~= '' then
    local members = tonumber(data.members) or 0
    window.guildPanel.guildLabel:setText(tr('%s - %d member%s%s', data.guild, members, members == 1 and '' or 's',
      data.signed and tr(', signed up') or ''))
  else
    window.guildPanel.guildLabel:setText(tr('You are not in a guild.'))
  end
  window.guildPanel.guildReason:setText((not data.canJoin and not data.signed) and (data.joinReason or '') or
    (data.signed and tr('Members enter through the portals next to the temples when it starts.') or ''))
  window.guildPanel.joinButton:setEnabled(data.canJoin == true)
  window.guildPanel.joinButton:setTooltip(data.canJoin and '' or (data.joinReason or ''))
  window.guildPanel.leaveButton:setEnabled(data.canLeave == true)
  local signups = {}
  for i, s in ipairs(list(data.signups)) do
    if type(s) ~= 'table' then s = {} end
    signups[#signups + 1] = { text = i .. '. ' .. tostring(s.name), color = s.own and '#ffe7a6' or nil }
  end
  window.signupsHeader:setText(tr('Signed up (%d / %d)', #signups, tonumber(data.capacity) or 0))
  fillList(window.signups, signups, tr('No guild yet.'))
  local champs = {}
  for _, c in ipairs(list(data.champions)) do
    if type(c) ~= 'table' then c = {} end
    champs[#champs + 1] = { text = tostring(c.name) .. ' - ' .. tr('until %s', c.untilText or '?'), color = '#f6cf72' }
  end
  fillList(window.champions, champs, tr('No champions this week.'))
  local rules = {}
  for _, r in ipairs(list(data.rules)) do rules[#rules + 1] = { text = '- ' .. tostring(r) } end
  fillList(window.rules, rules, '')
  if tickEvent then removeEvent(tickEvent) end
  tick()
end

function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  if info then tick() end
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
  send('open') -- the server answers with info, which shows the window
end

function join() send('join') end
function leave() send('leave') end

-- ---------------------------------------------------------------- protocol
local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then
    g_logger.error('[siege] invalid JSON: ' .. tostring(msg))
    return
  end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'hud' then
    updateHud(data)
  elseif msg.action == 'hide' then
    hideHud()
  elseif msg.action == 'info' then
    updateWindow(data)
    if data.open then show() end
  end
end

local function onGameEnd()
  hide()
  hideHud()
  info = nil
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
end

function init()
  window = g_ui.displayUI('siege')
  window:hide()
  -- in the game root panel (the map panel itself reaches above the visible area), centred on the map
  hud = g_ui.loadUI('siegehud', modules.game_interface.getRootPanel())
  if hud then hud:setVisible(false) end
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  if hud then hud:destroy() hud = nil end
  if window then window:destroy() window = nil end
  info = nil
end
