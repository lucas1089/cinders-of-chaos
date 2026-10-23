-- Rift Atlas window: the rift progression tree. Server: server/data/scripts/chaos/atlas.lua, extended opcode 210
-- (JSON {action, data}; the tree arrives through Chaos.sendChunked, joined by ProtocolGame.registerExtendedJSONOpcode).
--   client -> server  open {tree} | alloc {id} | refund {id, pay = gold|orb} | reset {pay}
--   server -> client  tree {...} (once per login) | state {...} | credit {cells, points}
-- Payload fields: riftatlasview.lua. Opened from Adventure > Rift Atlas and from the button of the rift HUD (game_rift).
-- Waystone mode: the same window shows the Waystone Atlas (server waystone_atlas.lua, extended opcode 159, the same
-- protocol; the grid comes as rows). Each mode keeps its own tree and state; Adventure > Waystone Atlas opens it.

local OPCODES = { rift = 210, waystone = 159 }
local TITLES = { rift = 'Rift Atlas', waystone = 'Waystone Atlas' }
-- what each content pays (server content_rewards_config.lua; the numbers are in the server README), shown under the map
local function rewardText(m)
  if m == 'waystone' then
    return tr('Waystones pay in gear: Rare or better set pieces from the kills, a boss table of Legendary pieces, uniques, new waystones and the waystone orbs. A higher tier and more modifiers pay more.')
  end
  return tr('Rifts pay in crafting currency: orbs from the kills (Upheaval, Fate, the waystone orbs), a burst from the guardian, and a stronger key when you seal a rift. Low rifts are a fast step for a high level character.')
end
local V = RiftAtlasView

local mode = 'rift'
local stash = { rift = {}, waystone = {} }

local window
local tree, ix, world
local state, alloc, done = nil, {}, {}
local zoomIndex = V.DEFAULT_ZOOM
local panX, panY = 0, 0
local selected
local nodeWidgets, linkWidgets = {}, {}
local selectRing
local dragFrom
local handlers = {}
local reported = {}
local box

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[riftatlas] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODES[mode], json.encode({ action = action, data = data or {} }))
  end
end

local function zoomValue() return V.ZOOMS[zoomIndex] end

local function closeBox()
  if box then box:destroy() box = nil end
end

local function confirm(title, text, buttons)
  closeBox()
  if not displayGeneralBox then
    if buttons[1] then buttons[1].callback() end
    return
  end
  local list = { anchor = AnchorHorizontalCenter }
  for _, b in ipairs(buttons) do
    list[#list + 1] = { text = b.text, callback = function() closeBox() b.callback() end }
  end
  local cancel = function() closeBox() end
  box = displayGeneralBox(title, text, list, buttons[1] and list[1].callback or cancel, cancel)
end

local function setStatus(text, color)
  if not window then return end
  window.statusLabel:setText(text or '')
  window.statusLabel:setColor(color or '#8c8070')
end

-- ---------------------------------------------------------------- the map
local function points() return state and tonumber(state.points) or 0 end
local function keystoneMax() return tree and tonumber(tree.keystoneMax) or 1 end

local function applyCanvas()
  if not window or not world then return end
  local z = zoomValue()
  local map = window.map
  panX, panY = V.clampPan(panX, panY, z, world, map:getWidth(), map:getHeight())
  local canvas = window.map.canvas
  canvas:setWidth(math.floor(world.w * z))
  canvas:setHeight(math.floor(world.h * z))
  canvas:setMarginLeft(panX)
  canvas:setMarginTop(panY)
end

local function styleNode(id)
  local w = nodeWidgets[id]
  local node = ix.byId[id]
  if not w or not node then return end
  local st = V.status(ix, alloc, id, points(), keystoneMax())
  w:setTooltip(V.tooltip(node, st))
  if node.k == 'start' then return end
  local f = V.frame(node.k, st, w:getWidth())
  w:setIcon(f.source)
  w:setIconSize({ width = f.w, height = f.h })
  w:setIconOffset({ x = -math.floor((f.w - w:getWidth()) / 2), y = -math.floor((f.h - w:getHeight()) / 2) })
  if st == 'alloc' or st == 'avail' then
    w:setImageColor('#ffffff')
    w:setOpacity(1)
  elseif st == 'reach' then
    w:setImageColor('#9a9090')
    w:setOpacity(1)
  else
    w:setImageColor('#6f6f6f')
    w:setOpacity(0.85)
  end
end

local function styleLinks()
  for key, entry in pairs(linkWidgets) do
    local want = 'RiftAtlasLink' .. V.linkState(ix, alloc, entry.a, entry.b)
    if entry.style ~= want then
      local old = entry.widget
      local g = entry.geo
      local w = g_ui.createWidget(want, window.map.canvas.links)
      w:setWidth(math.max(1, g.len))
      w:setHeight(entry.h)
      w:setMarginLeft(g.x)
      w:setMarginTop(g.y)
      w:setRotation(g.angle)
      old:destroy()
      entry.widget, entry.style = w, want
    end
  end
end

local function placeSelect()
  if not selectRing then return end
  local w = selected and nodeWidgets[selected]
  if not w then
    selectRing:setVisible(false)
    return
  end
  local s = w:getWidth() + 10
  selectRing:setSize({ width = s, height = s })
  selectRing:setMarginLeft(w:getMarginLeft())
  selectRing:setMarginTop(w:getMarginTop())
  selectRing:setVisible(true)
  selectRing:raise()
end

local updatePanel

local function pick(id)
  selected = id
  placeSelect()
  updatePanel()
end

local function buildMap()
  if not window or not ix then return end
  local canvas = window.map.canvas
  canvas.links:destroyChildren()
  canvas.nodes:destroyChildren()
  nodeWidgets, linkWidgets, selectRing = {}, {}, nil
  local z = zoomValue()
  world = V.world(ix)
  applyCanvas()
  local h = math.max(4, math.floor(12 * (0.45 + 0.55 * z) + 0.5))
  for _, p in ipairs(ix.pairs) do
    local a, b = ix.byId[p[1]], ix.byId[p[2]]
    local g = V.linkGeometry(world, a, b, z)
    local style = 'RiftAtlasLink' .. V.linkState(ix, alloc, a.i, b.i)
    local w = g_ui.createWidget(style, canvas.links)
    w:setWidth(math.max(1, g.len))
    w:setHeight(h)
    w:setMarginLeft(g.x)
    w:setMarginTop(g.y)
    w:setRotation(g.angle)
    linkWidgets[p[1] .. '-' .. p[2]] = { widget = w, style = style, a = a.i, b = b.i, geo = g, h = h }
  end
  for _, node in ipairs(ix.list) do
    local w = g_ui.createWidget('RiftAtlasNode', canvas.nodes)
    local s = V.nodeSize(node.k, z)
    w:setSize({ width = s, height = s })
    local x, y = V.place(world, node, z)
    w:setMarginLeft(x)
    w:setMarginTop(y)
    if node.k == 'start' then
      w:setImageSource('/images/riftatlas/start')
    else
      w:setImageSource('/images/riftatlas/icons_' .. V.iconSet(ix, node))
      w:setImageClip(V.iconClip(V.glyphOf(ix, node)))
    end
    local id = node.i
    w.onClick = function() pick(id) return true end
    w.onDoubleClick = function()
      pick(id)
      allocateSelected()
      return true
    end
    nodeWidgets[id] = w
    styleNode(id)
  end
  selectRing = g_ui.createWidget('RiftAtlasSelect', canvas.nodes)
  selectRing:setVisible(false)
  placeSelect()
end

-- ---------------------------------------------------------------- the side panel
local function cellColor(row, cell)
  if not cell.done then return '#241e24' end
  return cell.color or row.color
end

local function buildGrid()
  if not window or not tree then return end
  local grid = window.grid
  grid:destroyChildren()
  local rows = V.gridRows(tree, done)
  local d, t = V.gridCount(rows)
  window.gridTitle:setText(tr('Completion grid: %d / %d', d, t))
  local x0, step, y = 60, 14, 14
  -- tier numbers
  for tier = 1, tonumber(tree.grid and tree.grid.tiers) or 15 do
    if tier == 1 or tier % 5 == 0 then
      local l = g_ui.createWidget('RiftAtlasGridLabel', grid)
      l:addAnchor(AnchorTop, 'parent', AnchorTop)
      l:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      l:setMarginLeft(x0 + (tier - 1) * step + (tier >= 10 and -2 or 2))
      l:setText(tostring(tier))
    end
  end
  for _, row in ipairs(rows) do
    local label = g_ui.createWidget('RiftAtlasGridLabel', grid)
    label:addAnchor(AnchorTop, 'parent', AnchorTop)
    label:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    label:setMarginTop(y)
    label:setText(row.label)
    label:setColor(row.color)
    for i, cell in ipairs(row.cells) do
      local c = g_ui.createWidget('RiftAtlasCell', grid)
      c:addAnchor(AnchorTop, 'parent', AnchorTop)
      c:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      c:setMarginTop(y + 1)
      if row.kind == 'omen' then
        c:setWidth(70)
        c:setHeight(15)
        c:setMarginLeft(x0 + (i - 1) * 72)
        c:setText(cell.name)
        c:setFont('verdana-11px-antialised')
        c:setColor(cell.done and '#0d0b0e' or '#8c8070')
      else
        c:setMarginLeft(x0 + ((cell.col or i) - 1) * step)
      end
      c:setBackgroundColor(cellColor(row, cell))
      c:setTooltip(cell.tip)
    end
    y = y + 18
  end
end

local function buildTotals()
  if not window then return end
  local list = window.totals
  list:destroyChildren()
  local lines = state and state.totals or {}
  if #lines == 0 then
    g_ui.createWidget('RiftAtlasTotal', list):setText(mode == 'waystone'
      and tr('Nothing allocated yet. Kill map bosses in waystone runs to earn points, then pick nodes on the map.')
      or tr('Nothing allocated yet. Seal rifts to earn points, then pick nodes on the map.'))
    return
  end
  for _, text in ipairs(lines) do
    local l = g_ui.createWidget('RiftAtlasTotal', list)
    l:setText('- ' .. tostring(text))
    if tostring(text):find(':') and not tostring(text):find('^%+') then l:setColor('#f6cf72') end
  end
end

updatePanel = function()
  if not window then return end
  local p = window.nodePanel
  local node = selected and ix and ix.byId[selected]
  local goldText, orbText = V.refundLabels(state)
  p.refundGold:setText(goldText)
  p.refundOrb:setText(orbText)
  local r = state and state.refund or {}
  p.refundGold:setTooltip(tr('Refund this node for %d gold (carried first, then the bank).', tonumber(r.gold) or 0))
  p.refundOrb:setTooltip(tr('Refund this node for %d %s.', tonumber(r.orbs) or 1, tostring(state and state.orb or 'orb')))
  if not node then
    p.nodeName:setText(tr('No node selected'))
    p.nodeKind:setText('')
    p.nodeText:setText(tr('Click a node on the map to see what it does.'))
    p.nodeStatus:setText('')
    p.allocButton:setEnabled(false)
    p.refundGold:setEnabled(false)
    p.refundOrb:setEnabled(false)
    return
  end
  p.nodeName:setText(tostring(node.n))
  p.nodeName:setColor(node.k == 'keystone' and '#ff8a5a' or (node.k == 'notable' and '#f6cf72' or '#d6c9ae'))
  p.nodeKind:setText(V.kindLine(node))
  p.nodeText:setText(table.concat(node.t or {}, '\n'))
  local okA, whyA = V.canAllocate(ix, alloc, node.i, points(), keystoneMax())
  local okR, whyR = V.canRefund(ix, alloc, node.i)
  local st = V.status(ix, alloc, node.i, points(), keystoneMax())
  if st == 'start' then
    p.nodeStatus:setText('')
  elseif alloc[node.i] then
    p.nodeStatus:setText(okR and tr('Allocated.') or tr('Allocated. Other nodes depend on it.'))
  else
    p.nodeStatus:setText(okA and tr('Can be allocated.') or V.reasonText(whyA))
  end
  p.allocButton:setEnabled(okA and true or false)
  p.refundGold:setEnabled(okR and true or false)
  p.refundOrb:setEnabled(okR and true or false)
end

local function render()
  if not window or not state then return end
  window.pointsPlate.pointsValue:setText(V.pointsLine(state))
  window.earnedLabel:setText(V.earnedLine(state))
  window.resetButton:setEnabled(next(alloc) ~= nil)
  for id in pairs(nodeWidgets) do styleNode(id) end
  styleLinks()
  buildGrid()
  buildTotals()
  updatePanel()
end

-- ---------------------------------------------------------------- actions (called from the .otui)
function allocateSelected()
  if not selected or not ix then return end
  local node = ix.byId[selected]
  if not node or not V.canAllocate(ix, alloc, node.i, points(), keystoneMax()) then return end
  local id = node.i
  if node.k == 'keystone' then
    confirm(tr('Allocate a keystone'), tr('%s\n\n%s\n\nYou can hold only %d keystone at a time. Allocate it?', node.n,
      table.concat(node.t or {}, '\n'), keystoneMax()),
      { { text = tr('Allocate'), callback = function() send('alloc', { id = id }) end }, { text = tr('Cancel'), callback = function() end } })
    return
  end
  send('alloc', { id = id })
end

function refundSelected(pay)
  if not selected or not ix or not V.canRefund(ix, alloc, selected) then return end
  local node = ix.byId[selected]
  local r = state and state.refund or {}
  local price = pay == 'orb' and string.format('%d %s', tonumber(r.orbs) or 1, tostring(state and state.orb or 'orb'))
    or string.format('%s gold', V.short(r.gold))
  local id = selected
  confirm(tr('Refund a node'), tr('Refund %s for %s? The point comes back.', node.n, price),
    { { text = tr('Refund'), callback = function() send('refund', { id = id, pay = pay }) end },
      { text = tr('Cancel'), callback = function() end } })
end

function resetAll()
  if not state or next(alloc) == nil then return end
  local r = state.reset or {}
  confirm(tr('Reset the atlas'), tr('Refund every node of your atlas for %s gold or %d %s?', V.short(r.gold), tonumber(r.orbs) or 0,
    tostring(state.orb or 'orbs')),
    { { text = tr('Pay gold'), callback = function() send('reset', { pay = 'gold' }) end },
      { text = tr('Pay orbs'), callback = function() send('reset', { pay = 'orb' }) end },
      { text = tr('Cancel'), callback = function() end } })
end

function zoom(dir)
  if not ix then return end
  local old = zoomValue()
  zoomIndex = V.zoomStep(zoomIndex, dir)
  local z = zoomValue()
  panX, panY = panX * z / old, panY * z / old
  buildMap()
end

function center()
  if not ix then return end
  panX, panY = V.panTo(world or V.world(ix), ix.byId[ix.start] or { x = 0, y = 0 }, zoomValue())
  applyCanvas()
end

-- ---------------------------------------------------------------- messages
local function onTree(d)
  tree = d
  ix = V.index(tree)
  world = V.world(ix)
  center()
  buildMap()
  render()
end

local function onState(d)
  state = d
  alloc = V.allocSet(state)
  done = V.doneSet(state)
  if d.msg and d.msg ~= '' then
    setStatus(tostring(d.msg), '#f6cf72')
  end
  render()
end

local function onCredit(d)
  local cells = type(d.cells) == 'table' and d.cells or {}
  setStatus(tr('Completed: %s (+%d)', table.concat(cells, ', '), tonumber(d.points) or 0), '#7fd07f')
end

-- a message for the mode not on screen: kept for when that mode is shown
local function stashMessage(m, msg)
  local s = stash[m]
  if msg.action == 'tree' then
    s.tree = msg.data
    s.ix = V.index(msg.data)
    s.world = V.world(s.ix)
    s.panX, s.panY = V.panTo(s.world, s.ix.byId[s.ix.start] or { x = 0, y = 0 }, zoomValue())
  elseif msg.action == 'state' then
    s.state = msg.data
    s.alloc = V.allocSet(msg.data)
    s.done = V.doneSet(msg.data)
  end
end

local function onMessage(protocol, opcode, msg)
  if type(msg) ~= 'table' or type(msg.data) ~= 'table' then return end
  local m = opcode == OPCODES.waystone and 'waystone' or 'rift'
  if m ~= mode then
    stashMessage(m, msg)
    return
  end
  if msg.action == 'tree' then
    onTree(msg.data)
  elseif msg.action == 'state' then
    onState(msg.data)
  elseif msg.action == 'credit' then
    onCredit(msg.data)
  end
end

-- ---------------------------------------------------------------- window
function hide()
  closeBox()
  if window then window:hide() end
end

local function clearMap()
  if not window then return end
  window.map.canvas.links:destroyChildren()
  window.map.canvas.nodes:destroyChildren()
  window.grid:destroyChildren()
  window.totals:destroyChildren()
  nodeWidgets, linkWidgets, selectRing = {}, {}, nil
end

-- show the other atlas in the window: the current one goes to its stash, the other comes back with its map position
local function switchMode(m)
  if not OPCODES[m] then return end
  if window then
    window:setText(tr(TITLES[m]))
    window.rewardNote:setText(rewardText(m))
  end
  if m == mode then return end
  closeBox()
  stash[mode] = { tree = tree, ix = ix, world = world, state = state, alloc = alloc, done = done, selected = selected,
    panX = panX, panY = panY }
  mode = m
  local s = stash[m] or {}
  tree, ix, world, state = s.tree, s.ix, s.world, s.state
  alloc, done, selected = s.alloc or {}, s.done or {}, s.selected
  panX, panY = s.panX or 0, s.panY or 0
  clearMap()
  if window then window.gridTitle:setText('') window.earnedLabel:setText('') window.pointsPlate.pointsValue:setText('') end
  if ix then
    buildMap()
    render()
  else
    updatePanel()
  end
end

function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  setStatus('')
  send('open', { tree = tree == nil })
end

-- Adventure > Rift Atlas / Waystone Atlas: open that atlas, close the window when it already shows it
local function toggleMode(m)
  if window and window:isVisible() and mode == m then
    hide()
    return
  end
  switchMode(m)
  show()
end

function toggle() toggleMode('rift') end
function toggleWaystone() toggleMode('waystone') end
function showRift() switchMode('rift') show() end
function showWaystone() switchMode('waystone') show() end
function getMode() return mode end

-- for other modules and tests
function getState()
  return { nodes = ix and #ix.list or 0, points = points(), visible = window and window:isVisible() or false,
    zoom = zoomValue(), selected = selected, mode = mode }
end

-- offline renders and tests: feed a server message as if it came over the opcode
function inject(msg, m)
  onMessage(nil, OPCODES[m or mode] or OPCODES.rift, msg)
end

-- select a node and bring it to the middle of the map
function selectNode(id)
  id = tonumber(id)
  if not ix or not ix.byId[id] then return end
  panX, panY = V.panTo(world or V.world(ix), ix.byId[id], zoomValue())
  applyCanvas()
  pick(id)
end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    handlers.menu = pcall(api.addEntry, 'adventure',
      { text = 'Rift Atlas', icon = 'dungeons', modules = { 'game_riftatlas' }, fns = { 'toggle' } })
    pcall(api.addEntry, 'adventure',
      { text = 'Waystone Atlas', icon = 'dungeons', modules = { 'game_riftatlas' }, fns = { 'toggleWaystone' } })
  end
end

local function onGameStart()
  tree, ix, world, state, alloc, done, selected = nil, nil, nil, nil, {}, {}, nil
  stash = { rift = {}, waystone = {} }
  clearMap()
  addMenu()
end

local function onGameEnd()
  hide()
end

local function setupDrag()
  local map = window.map
  map.onDragEnter = function(_, pos)
    dragFrom = { x = pos.x, y = pos.y, px = panX, py = panY }
    return true
  end
  map.onDragMove = function(_, pos)
    if not dragFrom then return false end
    panX = dragFrom.px + pos.x - dragFrom.x
    panY = dragFrom.py + pos.y - dragFrom.y
    applyCanvas()
    return true
  end
  map.onDragLeave = function()
    dragFrom = nil
    return true
  end
  map.onMouseWheel = function(_, _, dir)
    zoom(dir == MouseWheelUp and 1 or -1)
    return true
  end
end

function init()
  local ok, ui = pcall(g_ui.displayUI, 'riftatlas')
  if ok and ui then
    window = ui
    window:hide()
    window.rewardNote:setText(rewardText(mode))
    setupDrag()
    updatePanel()
  else
    g_logger.warning('[riftatlas] window not loaded: ' .. tostring(ui))
  end
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  for _, op in pairs(OPCODES) do
    ProtocolGame.registerExtendedJSONOpcode(op, safe('opcode', onMessage))
  end
  connect(g_game, handlers.game)
  addMenu()
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, handlers.game)
  for _, op in pairs(OPCODES) do
    pcall(ProtocolGame.unregisterExtendedJSONOpcode, op)
  end
  closeBox()
  if window then window:destroy() window = nil end
  tree, ix, state, handlers = nil, nil, nil, {}
  stash = { rift = {}, waystone = {} }
  nodeWidgets, linkWidgets = {}, {}
end
