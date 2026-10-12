local window, view, decoView, nodesView = nil
local pointsOwned = 0
CODE_SKILLTREE = 65
local DEBUG = false
local focusedNode = nil
local currentPreset = 0
local currentSelected = 0
changesPending = false
ignorePoints = false
STARTOFFSET = {
	x = 0,
	y = -200
}
LASTPOS = {
	x = 0,
	y = 0
}
local LIMIT_X = 8000
local LIMIT_Y = 7000
local SCROLL_X = -700
local SCROLL_Y = 1200
local t_insert = table.insert
local m_pi = math.pi
local m_sin = math.sin
local m_cos = math.cos
local m_tan = math.tan
local m_atan2 = math.atan2
local m_sqrt = math.sqrt
local m_max = math.max


-- the variant key of the node variants (keystones 621 / 624) shown; the server names it in sendNodes, because the
-- number the client's player:getVocation() returns does not follow one scheme (an Elite Knight reports 4)
local serverVocation = nil
-- the class (which class nodes it may take: node.classes) and its line (whose class section is shown: node.line),
-- also from sendNodes (class keys of the server: ChaosClasses.classKey / lineKey)
local serverClass, serverLine = nil, nil

-- the tree of another character (Inspect Player, viewother.lua): {name, cls, line, vocation, nodes, masteries} while it
-- is shown read-only in place of the own tree; nil otherwise
local viewing = nil
-- the chosen effect of each saved mastery node ([id] = choice), from sendNodes
local savedMasteries = {}

-- fallback before the server named them: the client reports server vocation ids (base patch 0016)
local CLASS_OF = { [4] = "warrior", [8] = "juggernaut", [14] = "berserker", [3] = "ranger", [7] = "deadeye",
  [15] = "beastmaster", [1] = "mystic", [5] = "elementalist", [10] = "illusionist", [11] = "thief", [12] = "ninja",
  [13] = "samurai", [17] = "monk", [18] = "shadowfist", [19] = "ironsage", [20] = "necromancer", [21] = "lich",
  [22] = "bonelord", [23] = "templar", [24] = "inquisitor", [25] = "sentinel" }
local LINE_OF = { warrior = "warrior", juggernaut = "warrior", berserker = "warrior", ranger = "ranger", deadeye = "ranger",
  beastmaster = "ranger", mystic = "mystic", elementalist = "mystic", illusionist = "mystic", thief = "thief", ninja = "thief",
  samurai = "thief", monk = "monk", shadowfist = "monk", ironsage = "monk", necromancer = "necromancer",
  lich = "necromancer", bonelord = "necromancer", templar = "templar", inquisitor = "templar", sentinel = "templar" }
local VARIANT_OF = { warrior = "knight", ranger = "paladin", mystic = "sorcerer", elementalist = "sorcerer" }

local function getPlayerClass()
  if viewing then
    return viewing.cls
  end
  if serverClass then
    return serverClass
  end
  local player = g_game.getLocalPlayer()
  return CLASS_OF[player and player:getVocation() or 0]
end

local function getPlayerLine()
  if viewing then
    return viewing.line
  end
  if serverLine then
    return serverLine
  end
  return LINE_OF[getPlayerClass() or ""]
end

local function getPlayerVocation()
  if viewing then
    return viewing.vocation
  end
  if serverVocation then
    return serverVocation
  end
  local class = getPlayerClass()
  return class and (VARIANT_OF[class] or class) or nil
end

-- class nodes: shown only to their line (node.line); taken only by their classes (node.classes)
-- hidden nodes (node.hidden: a stray node of the original tree) are never shown
local function nodeShown(node)
  return not node.hidden and (not node.line or node.line == getPlayerLine())
end

local function nodeAllowed(node)
  if not node.classes then
    return true
  end
  local class = getPlayerClass()
  for _, key in ipairs(node.classes) do
    if key == class then
      return true
    end
  end
  return false
end

-- the class names for "Requires: ..." on a locked node
local CLASS_NAMES = { warrior = "Warrior", juggernaut = "Juggernaut", berserker = "Berserker", ranger = "Ranger",
  deadeye = "Deadeye", beastmaster = "Beastmaster", mystic = "Mystic", elementalist = "Elementalist",
  illusionist = "Illusionist", thief = "Thief", ninja = "Ninja", samurai = "Samurai", monk = "Monk",
  shadowfist = "Shadowfist", ironsage = "Iron Sage", necromancer = "Necromancer", lich = "Lich", bonelord = "Bone Lord",
  templar = "Templar", inquisitor = "Inquisitor", sentinel = "Sentinel" }

-- radius of a class section's start medallion (treedata/icons.lua cs..., 150 x 150): its link starts there
START_RIM = 70

local orbitDist = {
	[0] = 0,
	60,
	80,
	120,
	191,
	250,
	290
}
local allocNodes = {}
local nodeMap = {}
local spare = {} -- the window's own decoView / nodesView: the first layer's panels (startBuild)
local treeData = {}

passiveButton, VocationSelected = nil


function init()
	passiveButton = modules.client_topmenu.addRightGameToggleButton('passiveButton', tr('Passive Tree'), '/images/topbuttons/passive_tree', toggle, false, 8)

	if not passiveButton then
		return
	end
	modules.game_passivetree.hide()

	connect(g_game, {
		onGameStart = create,
		onGameEnd = destroy
	})
	ProtocolGame.registerExtendedOpcode(CODE_SKILLTREE, onExtendedOpcode)

	if g_game.isOnline() then
		create()
		show()
	end

	return 
end

-- the tree window (paragon.lua puts the Paragon panel into it)
function getTreeWindow()
	return window
end

function isVisible()
    return window and window:isVisible()
end

function toggle()
	if modules.game_passivetree.isVisible() then
	  hide()
	else
	  show()
	end
  end

function changeVocation(button)
	VocationSelected = button.getText(button):lower()

	rebuildTree()

	return 
end

function terminate()
	disconnect(g_game, {
		onGameStart = create,
		onGameEnd = destroy
	})
	ProtocolGame.unregisterExtendedOpcode(CODE_SKILLTREE, onExtendedOpcode)

	if passiveButton then
		passiveButton:destroy()

		passiveButton = nil
	end

	VocationSelected = nil

	destroy()

	return 
end

function create()
	if window then
		return 
	end

	local treeX = getTreeData()

	for k, v in pairs(treeX) do
		treeData[k] = v
	end

	window = g_ui.loadUI("passivetree", modules.game_interface.getRootPanel())
	window.onMouseWheel = function (self, mousePos, mouseWheel)
		if mouseWheel == MouseWheelUp then
			zoomPlus()
		else
			zoomLess()
		end

		return 
	end

	window.pWindow.points:setText(formatShortNumber(pointsOwned) .. " points")

	view = window:recursiveGetChildById("view")
	background = window:recursiveGetChildById("background")
	decoView = window:recursiveGetChildById("decoView")
	nodesView = window:recursiveGetChildById("nodesView")

	background:setWidth(LIMIT_X)
	background:setHeight(LIMIT_Y)
	decoView:setWidth(LIMIT_X)
	decoView:setHeight(LIMIT_Y)
	nodesView:setWidth(LIMIT_X)
	nodesView:setHeight(LIMIT_Y)
	background:setMarginLeft(SCROLL_X)
	background:setMarginTop(SCROLL_Y)
	decoView:setMarginLeft(SCROLL_X)
	decoView:setMarginTop(SCROLL_Y)
	nodesView:setMarginLeft(SCROLL_X)
	nodesView:setMarginTop(SCROLL_Y)

	spare = {decoView, nodesView}
	-- the planner (planner.lua) and the search (search.lua)
	g_keyboard.bindKeyDown('Ctrl+Z', function() plannerUndo() end, window)
	g_keyboard.bindKeyDown('Ctrl+Y', function() plannerRedo() end, window)
	g_keyboard.bindKeyDown('Ctrl+F', function() focusTreeSearch() end, window)
	local searchEdit = window:recursiveGetChildById("searchEdit")
	g_keyboard.bindKeyDown('Enter', function() treeSearchNext() end, searchEdit)
	g_keyboard.bindKeyDown('Shift+Enter', function() treeSearchPrev() end, searchEdit)

	view.onDragEnter = onDragEnter
	view.onDragLeave = onDragLeave
	view.onDragMove = onDragMove

	for _, child in pairs(nodesView:getChildren()) do
		child.setHeight(child, child.getHeight(child)*SCALE)
		child.setWidth(child, child.getWidth(child)*SCALE)
		child.setImageHeight(child, child.getImageHeight(child)*SCALE)
		child.setImageWidth(child, child.getImageWidth(child)*SCALE)
		child.setIconWidth(child, child.getIconWidth(child)*SCALE)
		child.setIconHeight(child, child.getIconHeight(child)*SCALE)
	end

	for _, child in pairs(decoView:getChildren()) do
		child.setHeight(child, child.getHeight(child)*SCALE)
		child.setWidth(child, child.getWidth(child)*SCALE)
		child.setImageHeight(child, child.getImageHeight(child)*SCALE)
		child.setImageWidth(child, child.getImageWidth(child)*SCALE)
	end

	for i = 1, 1, 1 do
		local slots = window.presets.slots
		local presetItem = slots["preset" .. i]
		presetItem.onClick = function (self)
			if self.unlocked then
				window.presets.presetsSave.presetName:setText(presetItem:getText())

				currentSelected = i
			else
				return
			end

			return 
		end
	end

	hide()

	return 
end

-- Building the tree: about 620 node widgets, as many connectors and the group backgrounds (~1400 widgets) cost the
-- client roughly 0.75 s. Done in one go that stalled the whole client, and the client's cycle events (the helper's
-- 50 ms healing loop) then ran every missed cycle back to back on the same frame clock, each one casting a spell:
-- 80 to 100 packets in one second, so the server kicked the player (maxPacketsPerSecond 50).
-- So the widgets are built once per zoom level and vocation, in slices of BUILD_SLICE_MS across frames (a job list,
-- not a coroutine: the engine's C++ bindings always read the main Lua stack), and an allocation (the server's
-- sendNodes, or the one kept on zoom) is applied to the built widgets in one pass.
local BUILD_SLICE_MS = 30
local nodeWidgets = {} -- [node id] = node widget
local connectorWidgets = {} -- ["a-b"] = connector widget
local connectorStyles = {} -- [connector widget] = current style name
local builtFor = nil -- key (zoom + vocation) of the widgets in nodesView/decoView
local buildingFor = nil -- key of the build in progress
local jobs = {} -- queued work (building, then showing an allocation): each job returns true while it has work left
local jobIndex = 1
local jobEvent = nil
local queueJobs, stepJobs
local buildSliceStart = 0
local pendingAlloc = nil -- {ids = {..}, block = bool}: applied as soon as the widgets are built
local statsShown = false -- the bonus list matches the shown allocation

-- Zoom levels are cached: the widgets of each zoom level of the shown class live in their own pair of panels (a layer,
-- [treeKey] = {key, deco, nodes, nodeWidgets, connectorWidgets, connectorStyles, used}). A zoom step back to a level
-- built before only swaps the visible layer and re-applies the node states (syncLayer) instead of destroying and
-- creating ~1400 widgets again; layers of another class (a class change, an inspected tree) are dropped. Hidden panels
-- are not drawn, so a cached level costs memory only. treeStats counts the work (getTreeStats(), the measurements in
-- client/MANIFEST.md).
local layers = {}
local MAX_LAYERS = 3 -- the three zoom levels (0.7, 0.49, 0.343)
local layerClock = 0
local buildingPanels = nil -- the panels of the build in progress (destroyed if it is cancelled)
local treeStats = {builds = 0, reuses = 0, widgets = 0, lastBuildWidgets = 0, lastBuildMs = 0, lastSwitchMs = 0}

function getTreeStats()
	local count, panels = 0, {}
	for key, layer in pairs(layers) do
		count = count + 1
		panels[#panels + 1] = string.format("%s=%s/%s%s", key, layer.deco:getId(), layer.nodes:getId(), key == builtFor and "*" or "")
	end
	return {panels = table.concat(panels, " "), builds = treeStats.builds, reuses = treeStats.reuses, widgets = treeStats.widgets,
		lastBuildWidgets = treeStats.lastBuildWidgets, lastBuildMs = treeStats.lastBuildMs, lastSwitchMs = treeStats.lastSwitchMs,
		layers = count}
end

local function newTreeWidget(style, parent)
	treeStats.widgets = treeStats.widgets + 1
	return g_ui.createWidget(style, parent)
end

local function nowMs()
	return g_clock.realMillis and g_clock.realMillis() or g_clock.millis()
end

local syncBuild = false -- createNodes(): build everything in one go

local function sliceUsed()
	return not syncBuild and nowMs() - buildSliceStart >= BUILD_SLICE_MS
end

-- a job that calls fn(item) for every item of list, in order, a slice at a time
local function slicedJob(list, fn)
	local i = 1
	return function()
		while i <= #list do
			fn(list[i])
			i = i + 1
			if sliceUsed() then
				return i <= #list
			end
		end
		return false
	end
end

local function scaleNodeWidget(child)
	child.setHeight(child, child.getHeight(child)*SCALE)
	child.setWidth(child, child.getWidth(child)*SCALE)
	child.setImageHeight(child, child.getImageHeight(child)*SCALE)
	child.setImageWidth(child, child.getImageWidth(child)*SCALE)
	child.setIconWidth(child, child.getIconWidth(child)*SCALE)
	child.setIconHeight(child, child.getIconHeight(child)*SCALE)
end

local function scaleDecoWidget(child)
	child.setHeight(child, child.getHeight(child)*SCALE)
	child.setWidth(child, child.getWidth(child)*SCALE)
	child.setImageHeight(child, child.getImageHeight(child)*SCALE)
	child.setImageWidth(child, child.getImageWidth(child)*SCALE)
end

local function treeKey()
	return string.format("%.4f|%s|%s", SCALE, tostring(getPlayerVocation()), tostring(getPlayerClass()))
end

local function destroyChildrenJob(parent)
	return function()
		local children = parent:getChildren()
		for i = #children, 1, -1 do
			children[i]:destroy()
			if sliceUsed() then
				return i > 1
			end
		end
		return false
	end
end

-- the tooltip of a node widget: name, stats, the class lines; a mastery node lists its effects and marks the chosen one
-- (saved, planned, or the inspected character's)
function setNodeTooltip(widget, node)
	local vocationNode = node[getPlayerVocation()]
	local tooltipType = 1
	if node.isUncommon then
		tooltipType = 2
	elseif node.isRare or node.isMastery then
		tooltipType = 3
	elseif node.isVeryRare then
		tooltipType = 7
	elseif node.isMythic then
		tooltipType = 6
	elseif node.isDivine then
		tooltipType = 8
	end
	local customStats = (vocationNode and vocationNode.customStats) or node.customStats
	local nodeName = (vocationNode and vocationNode.name) or node.name or ""
	local title = nodeName .. ((DEBUG and " (ID: " .. node.id .. ")") or "")
	local texts
	if node.isMastery then
		texts = {}
		for _, line in ipairs(node.stats or {}) do
			table.insert(texts, line)
		end
		local chosen = getChosenMastery(node.id)
		for i, effect in ipairs(node.masteries or {}) do
			table.insert(texts, string.format("%d. %s%s: %s", i, effect.name or "", chosen == i and " (chosen)" or "",
				table.concat(getCustomStatString(effect.customStats or {}), " ")))
		end
		if node.locked then
			local names = {}
			for _, key in ipairs(node.classes or {}) do
				table.insert(names, CLASS_NAMES[key] or key)
			end
			table.insert(texts, "Requires: " .. table.concat(names, ", ") .. ".")
		end
	elseif customStats then
		texts = getCustomStatString(customStats)
		-- keystones: the class's own description lines under the stats (a class node: its own lines)
		for _, line in ipairs((vocationNode and vocationNode.stats) or ((node.classes or node.isKeystone) and node.stats) or {}) do
			table.insert(texts, line)
		end
		if node.locked then
			local names = {}
			for _, key in ipairs(node.classes) do
				table.insert(names, CLASS_NAMES[key] or key)
			end
			table.insert(texts, "Requires: " .. table.concat(names, ", ") .. ".")
		end
	elseif node.stats then
		texts = {}
		for _, line in ipairs(node.stats) do
			table.insert(texts, line)
		end
		if node.locked then
			table.insert(texts, "Your class has no keystone here.")
		end
	end
	if texts then
		widget.setExtendedTooltip(widget, title, texts, tooltipType)
	end
end

-- the jobs that build every widget of the tree at the current SCALE (sizes already scaled), in order
local function buildTree()
	local jobs = {}

	if SCALE_MAX <= SCALE then
		window.zoomPlus:setEnabled(false)
	else
		window.zoomPlus:setEnabled(true)
	end

	if SCALE <= SCALE_MIN then
		window.zoomLess:setEnabled(false)
	else
		window.zoomLess:setEnabled(true)
	end

	allocNodes = {}
	nodeWidgets = {}
	connectorWidgets = {}
	connectorStyles = {}

	t_insert(jobs, destroyChildrenJob(decoView))
	t_insert(jobs, destroyChildrenJob(nodesView))

	local widget = nil

	-- the class section's groups only when the player's line has a section
	local hasSection = false
	for _, node in pairs(treeData.nodes) do
		if node.line and node.line == getPlayerLine() then
			hasSection = true
			break
		end
	end
	local groups = {}
	for key, group in pairs(treeData.groups) do
		if not group.section or hasSection then
			t_insert(groups, {key, group})
		end
	end
	t_insert(jobs, slicedJob(groups, function(entry)
		local _, group = entry[1], entry[2]
		if group.orbit ~= 0 then
			widget = newTreeWidget("DecorationCircle", decoView)

			widget.setMarginLeft(widget, group.x*SCALE)
			widget.setMarginTop(widget, group.y*SCALE)

			if group.bgOffsetY then
				widget.setMarginBottom(widget, group.bgOffsetY*SCALE)
			end

			widget.setImageSource(widget, "/images/passivetree/PSGroupBackground" .. group.orbit)

			if DEBUG then
				widget.setText(widget, _)
			end

			scaleDecoWidget(widget)
			widget = nil

			if group.mastery then
				widget = newTreeWidget("DecorationCircle", decoView)

				widget.setMarginLeft(widget, group.x*SCALE)
				widget.setMarginTop(widget, group.y*SCALE)

				local masteryIcon = treeData.icons[group.mastery]

				widget.setImageSource(widget, masteryIcon.file)
				widget.setWidth(widget, masteryIcon.w*SCALE)
				widget.setHeight(widget, masteryIcon.h*SCALE)
				widget.setImageClip(widget, masteryIcon.x .. " " .. masteryIcon.y .. " " .. masteryIcon.w .. " " .. masteryIcon.h)

				if DEBUG then
					widget.setText(widget, _)
				end
				scaleDecoWidget(widget)
			end
		end
	end))

	local NODES_MAX = 700
	local ids = {}
	nodeMap = {}
	for id = 1, NODES_MAX, 1 do
		if treeData.nodes[id] and nodeShown(treeData.nodes[id]) then
			t_insert(ids, id)
		end
	end

	t_insert(jobs, slicedJob(ids, function(id)
		local node = treeData.nodes[id]

		if node or false then
			local group = treeData.groups[node.group]
			local vocationNode = node[getPlayerVocation()]
			local icon = treeData.icons[node.icon]

			if not node.isStartNode and vocationNode then
				icon = treeData.icons[vocationNode.icon] or icon
			end

			node.id = id
			node.linkedId = {}
			node.groupX = group
			node.locked = not nodeAllowed(node)

			if node.isStartNode then
				node.alloc = true
				node.x, node.y = group.x, group.y
				allocNodes[node.id] = node
				widget = newTreeWidget("DecorationCircle", decoView)

				widget.setMarginLeft(widget, group.x*SCALE)
				widget.setMarginTop(widget, group.y*SCALE)
				widget.setImageSource(widget, icon.file)
				widget.setImageClip(widget, icon.x .. " " .. icon.y .. " " .. icon.w .. " " .. icon.h)
				scaleDecoWidget(widget)
			else
				node.alloc = false

				if group then
					node.angle = (node.orbitIndex * m_pi) / 180
					local defaultDist = orbitDist[node.orbit]
					local customDist = node.orbitDist and node.orbitDist > 0 and node.orbitDist or 0
					local dist = customDist > 0 and customDist or defaultDist
					node.x = group.x + m_sin(node.angle) * dist
					node.y = group.y - m_cos(node.angle) * dist
				end

				local nodeClass = "CommonNode"

				if node.isMastery then
					nodeClass = "MasteryNode"
				elseif node.isUncommon then
					nodeClass = "UncommonNode"
				elseif node.isRare then
					nodeClass = "RareNode"
				elseif node.isVeryRare then
					nodeClass = "VeryRareNode"
				elseif node.isMythic then
					nodeClass = "MythicNode"
				elseif node.isDivine then
					nodeClass = "DivineNode"
				end

				widget = newTreeWidget(nodeClass, nodesView)

				widget.setId(widget, node.id)
				widget.setMarginLeft(widget, node.x*SCALE)
				widget.setMarginTop(widget, node.y*SCALE)
				widget.setIconOffsetX(widget, widget.getIconOffsetX(widget)*SCALE)
				widget.setIconOffsetY(widget, widget.getIconOffsetY(widget)*SCALE)
				widget.setImageClip(widget, icon.x .. " " .. icon.y .. " " .. icon.w .. " " .. icon.h)
				if icon.file then -- keystone icons live in their own sheet (treedata/icons.lua)
					widget.setImageSource(widget, icon.file)
				end

				if DEBUG then
					widget.setText(widget, id)
				end

				setNodeTooltip(widget, node)
				if node.locked then
					widget.setOpacity(widget, 0.45)
				end

				widget.onClick = onClickNode
				widget.onMousePress = onNodeMousePress -- respec.lua: right-click refund of a saved node
				scaleNodeWidget(widget)
				nodeWidgets[node.id] = widget
			end

			nodeMap[node.id] = node
			widget = nil
		end
	end))

	local function BuildConnector(node1, node2)
		if node1.groupX == node2.groupX and node1.orbit == node2.orbit then
			if node2.angle < node1.angle then
			  node1, node2 = node2, node1
			end

			local angle1 = node1.angle
			local angle2 = node2.angle
			local arcAngle = angle2 - angle1

			if arcAngle < 0 then
			  arcAngle = arcAngle + 2 * m_pi
			end

			local flip = false
			if arcAngle > m_pi then
			  arcAngle = 2 * m_pi - arcAngle
			  flip = true
			end

			if arcAngle < m_pi * 0.9 then
			  local lineType = "Normal"
			  if node1.alloc and node2.alloc then
				lineType = "Active"
			  elseif node1.alloc and not node2.alloc then
				lineType = "Intermediate"
			  end

			  local distX = (node2.x - node1.x) / SCALE
			  local distY = (node2.y - node1.y) / SCALE
			  local dist  = m_sqrt(distX * distX + distY * distY)

			  local orbitType = getOrbitType(node1.orbit, dist, node1.id)
			  local style = "Orbit" .. orbitType .. lineType
			  local widget = newTreeWidget(style, decoView)
			  widget:setId(node1.id .. "-" .. node2.id)
			  connectorWidgets[node1.id .. "-" .. node2.id] = widget
			  connectorStyles[widget] = style

			  local avgAngle = angle1 + (arcAngle / 2)
			  local rotation = (avgAngle * 180 / m_pi) + (flip and -45 or 45)
			  widget:setRotation(rotation)

			  local midX = (node1.x + node2.x) / 2
			  local midY = (node1.y + node2.y) / 2
			  widget:setMarginLeft(midX * SCALE)
			  widget:setMarginTop(midY * SCALE)
			  scaleDecoWidget(widget)

				widget = nil

				return
			end
		end

		local vX = (node2.x - node1.x) / SCALE
  		local vY = (node2.y - node1.y) / SCALE
  		local dist = m_sqrt(vX * vX + vY * vY)
  		local endS = dist / 256
  		local angle = (m_atan2(vY, vX) * 180 / m_pi)

  		local x = (node1.x + node2.x) / 2
  		local y = (node1.y + node2.y) / 2
  		local lineType = "Normal"
  		if node1.alloc and node2.alloc then
    		lineType = "Active"
  		elseif node1.alloc and not node2.alloc then
    		lineType = "Intermediate"
  		end

  		local style = "LineConnector" .. lineType
  		local widget = newTreeWidget(style, decoView)
  		widget:setId(node1.id .. "-" .. node2.id)
  		connectorWidgets[node1.id .. "-" .. node2.id] = widget
  		connectorStyles[widget] = style
  		widget:setMarginLeft(x * SCALE)
  		widget:setMarginTop(y * SCALE)
  		widget:setRotation(angle)
  		widget:setWidth(endS * 256 * SCALE)
  		scaleDecoWidget(widget)

		widget = nil

		return
	end

	local nodes = {}
	for _, node in pairs(treeData.nodes) do
		t_insert(nodes, node)
	end
	t_insert(jobs, slicedJob(nodes, function(node)
		if not nodeMap[node.id] then
			return -- a node not shown to this class (another line's section)
		end
		for _, otherId in pairs(node.out or {}) do
			local other = nodeMap[otherId]

			if other then
				t_insert(node.linkedId, otherId)
				t_insert(other.linkedId, node.id)

				-- the root's links are not drawn (its nodes sit on its ring); a class section's start draws its link
				local rootLink = (node.isStartNode and not node.line) or (other.isStartNode and not other.line)
				if not rootLink then
					-- a class start's link begins at the rim of its medallion, not under it
					local a, b = node, other
					if a.isStartNode or b.isStartNode then
						local st, o = a.isStartNode and a or b, a.isStartNode and b or a
						local dx, dy = o.x - st.x, o.y - st.y
						local len = m_sqrt(dx * dx + dy * dy)
						local r = START_RIM / len
						local rim = {id = st.id, x = st.x + dx * r, y = st.y + dy * r, alloc = st.alloc}
						if a.isStartNode then a = rim else b = rim end
					end
					BuildConnector(a, b)
				end
			end
		end
	end))

	return jobs
end

local function connectorOf(id1, id2)
	return connectorWidgets[id1 .. "-" .. id2] or connectorWidgets[id2 .. "-" .. id1]
end

-- restyle the connectors of a node after its (or its neighbours') allocation changed
local function refreshConnectors(node)
	for _, list in ipairs({node.out or {}, node.inputs or {}}) do
		for _, otherId in pairs(list) do
			local connector = connectorOf(node.id, otherId)

			if connector then
				local other = nodeMap[otherId]
				local lineType = "Normal"

				-- allocated on both ends: active; the allocation's edge, or a link of the plan (planner.lua): intermediate
				if node.alloc and other.alloc then
					lineType = "Active"
				elseif node.alloc or other.alloc or (node.planned and other.planned) then
					lineType = "Intermediate"
				end

				local style
				if node.groupX == other.groupX and node.orbit == other.orbit then
					local vX = other.x - node.x
					local vY = other.y - node.y
					local dist = m_sqrt(vX*vX + vY*vY)
					style = "Orbit" .. getOrbitType(node.orbit, dist) .. lineType
				else
					style = "LineConnector" .. lineType
				end

				if connectorStyles[connector] ~= style then
					connector.setStyle(connector, style)
					connectorStyles[connector] = style
				end
			end
		end
	end
end

local function hasNeighbourIn(node, set)
	for _, list in ipairs({node.out or {}, node.inputs or {}}) do
		for _, otherId in pairs(list) do
			if set[otherId] then
				return true
			end
		end
	end
	return false
end

-- Shows an allocation on the built widgets: the given ids that connect to the start node (as clicking them in order
-- would), the rest unallocated. Only the nodes whose state changes are touched: their widgets
-- and connectors are updated by jobs a slice per frame (a few hundred style changes cost ~0.25 s), the bonus list is
-- recalculated once. blocked: the shown nodes cannot be taken back (saved on the server).
local function applyAllocation(ids, blocked)
	local wanted = {}
	for _, raw in pairs(ids or {}) do
		local id = tonumber(raw)
		if id and nodeMap[id] and not nodeMap[id].isStartNode then
			wanted[id] = true
		end
	end

	local target = {}
	for id, node in pairs(nodeMap) do
		if node.isStartNode then
			target[id] = true
		end
	end

	-- a node joins once one of its own links (out or inputs, like canAllocate) is in; the links are not always
	-- listed on both ends, so repeat until nothing more joins (a pass per ring, cheap for a few hundred ids)
	local progress = true
	while progress do
		progress = false
		for id in pairs(wanted) do
			local node = nodeMap[id]
			if hasNeighbourIn(node, target) and not (node.exclude and target[node.exclude]) then
				target[id] = true
				wanted[id] = nil
				progress = true
			end
		end
	end

	local changed = {}
	allocNodes = {}
	for id, node in pairs(nodeMap) do
		local alloc = target[id] == true
		if node.alloc ~= alloc then
			node.alloc = alloc
			changed[#changed + 1] = node
		end
		if alloc then
			allocNodes[id] = node
		end
		node.blocked = (alloc and blocked) or nil
		local widget = nodeWidgets[id]
		if widget then
			widget.blocked = node.blocked
		end
	end

	queueJobs({
		slicedJob(changed, function(node)
			local widget = nodeWidgets[node.id]
			if widget and widget.isOn(widget) ~= node.alloc then
				widget.setOn(widget, node.alloc)
			end
		end),
		slicedJob(changed, refreshConnectors)
	})

	if #changed > 0 or not statsShown then
		statsShown = true
		calculateStats()
	end
	-- planner.lua: planned ids that are allocated now leave the plan; the planned marks follow the new allocation
	if plannerOnAllocation then
		plannerOnAllocation()
	end
end

local function applyPendingAllocation()
	local pending = pendingAlloc
	pendingAlloc = nil
	if pending then
		applyAllocation(pending.ids, pending.block)
	end
end

local function isBuilding()
	return jobIndex <= #jobs
end

-- runs queued jobs until the slice is used up, then continues on the next frame
function stepJobs()
	jobEvent = nil
	if not window then
		return
	end
	local queue = jobs
	buildSliceStart = nowMs()
	while jobIndex <= #queue do
		local ok, more = pcall(queue[jobIndex])
		if queue ~= jobs then
			return -- cancelled meanwhile
		end
		if not ok then
			g_logger.error("[Passive tree] building the tree failed: " .. tostring(more))
			more = false
		end
		if not more then
			jobIndex = jobIndex + 1
		end
		if sliceUsed() then
			break
		end
	end
	if jobIndex > #queue then
		jobs, jobIndex = {}, 1
	elseif not jobEvent then
		jobEvent = scheduleEvent(stepJobs, 1)
	end
end

function queueJobs(list)
	for _, job in ipairs(list) do
		jobs[#jobs + 1] = job
	end
	if not jobEvent and not syncBuild then
		jobEvent = scheduleEvent(stepJobs, 1)
	end
end

local function cancelBuild()
	if jobEvent then
		removeEvent(jobEvent)
		jobEvent = nil
	end
	jobs, jobIndex = {}, 1
	buildingFor = nil
	if buildingPanels then
		-- a build that never finished: its half-built panels are not a layer
		for _, panel in ipairs(buildingPanels) do
			panel:destroy()
		end
		buildingPanels = nil
	end
end

local function classOfKey(key)
	return tostring(key or ""):match("^[^|]*|(.*)$")
end

local function dropLayer(key)
	local layer = layers[key]
	layers[key] = nil
	if layer then
		layer.deco:destroy()
		layer.nodes:destroy()
	end
end

local function layerPanels()
	local deco = table.remove(spare, 1) or g_ui.createWidget("Panel", view)
	local nodes = table.remove(spare, 1) or g_ui.createWidget("Panel", view)
	for _, panel in ipairs({deco, nodes}) do
		panel:centerIn("parent")
		panel:setWidth(LIMIT_X)
		panel:setHeight(LIMIT_Y)
		-- where the view was dragged to (every child of the view moves together)
		panel:setMarginLeft(background:getMarginLeft())
		panel:setMarginTop(background:getMarginTop())
	end
	return deco, nodes
end

-- the widget states of the active layer from the node flags (alloc, planned, blocked) and the mastery tooltips
local function syncLayer()
	for id, node in pairs(nodeMap) do
		local widget = nodeWidgets[id]
		if widget then
			local on = node.alloc == true
			if widget:isOn() ~= on then
				widget:setOn(on)
			end
			local planned = node.planned == true and not on
			if widget:isChecked() ~= planned then
				widget:setChecked(planned)
			end
			widget.blocked = node.blocked
			if node.isMastery then
				setNodeTooltip(widget, node)
			end
		end
	end
	for _, node in pairs(nodeMap) do
		refreshConnectors(node)
	end
end

-- planner.lua and search.lua mark the new widgets (a layer was built or shown)
local function afterWidgetsReady()
	if plannerRefresh then
		plannerRefresh()
	end
	if refreshTreeSearch then
		refreshTreeSearch()
	end
end

local function startBuild(key)
	cancelBuild()
	local current = builtFor and layers[builtFor]
	if current then
		current.deco:setVisible(false)
		current.nodes:setVisible(false)
	end
	builtFor = nil
	for other in pairs(layers) do
		if classOfKey(other) ~= classOfKey(key) then
			dropLayer(other)
		end
	end
	local cached = layers[key]
	if cached then
		-- a zoom level built before: show it, no widget is created
		local started = nowMs()
		decoView, nodesView = cached.deco, cached.nodes
		nodeWidgets, connectorWidgets, connectorStyles = cached.nodeWidgets, cached.connectorWidgets, cached.connectorStyles
		layerClock = layerClock + 1
		cached.used = layerClock
		syncLayer()
		decoView:setVisible(true)
		nodesView:setVisible(true)
		builtFor = key
		treeStats.reuses = treeStats.reuses + 1
		applyPendingAllocation()
		afterWidgetsReady()
		treeStats.lastSwitchMs = nowMs() - started
		return
	end
	local count, oldest = 0, nil
	for other, layer in pairs(layers) do
		count = count + 1
		if not oldest or layer.used < layers[oldest].used then
			oldest = other
		end
	end
	if count >= MAX_LAYERS and oldest then
		dropLayer(oldest)
	end
	decoView, nodesView = layerPanels()
	buildingPanels = {decoView, nodesView}
	buildingFor = key
	statsShown = false
	decoView:setVisible(false)
	nodesView:setVisible(false)
	buildSliceStart = nowMs()
	local started, before = nowMs(), treeStats.widgets
	local list = buildTree()
	list[#list + 1] = function()
		layerClock = layerClock + 1
		layers[buildingFor] = {key = buildingFor, deco = decoView, nodes = nodesView, nodeWidgets = nodeWidgets,
			connectorWidgets = connectorWidgets, connectorStyles = connectorStyles, used = layerClock}
		buildingPanels = nil
		builtFor = buildingFor
		buildingFor = nil
		decoView:setVisible(true)
		nodesView:setVisible(true)
		treeStats.builds = treeStats.builds + 1
		treeStats.lastBuildMs = nowMs() - started
		treeStats.lastBuildWidgets = treeStats.widgets - before
		applyPendingAllocation()
		afterWidgetsReady()
		return false
	end
	queueJobs(list)
	stepJobs()
end

-- show the allocation `ids` once the widgets for the current zoom and vocation exist (built if needed, over frames)
local function showAllocation(ids, blocked)
	if not window then
		return
	end
	pendingAlloc = {ids = ids or {}, block = blocked}
	local key = treeKey()
	if buildingFor then
		if buildingFor == key then
			return -- the running build applies it
		end
	elseif builtFor == key then
		applyPendingAllocation()
		return
	end
	startBuild(key)
end

-- buildshare.lua: shows a build preview the same way sendNodes shows the saved allocation (masteries: the preview's
-- [{id, choice}]); the planner is closed while a preview is shown
local previewShown = false
function showTreeAllocation(ids, blocked, masteries)
	changesPending = false
	previewShown = true
	if plannerReset then
		plannerReset()
	end
	if masteries then
		savedMasteries = masteryMap(masteries)
	end
	showAllocation(ids, blocked)
end

function isTreePreviewShown()
	return previewShown
end

-- ------------------------------------------------------------------------------------------------ for planner.lua,
-- search.lua and viewother.lua
function masteryMap(list)
	local out = {}
	for _, m in pairs(type(list) == "table" and list or {}) do
		local id, choice = tonumber(type(m) == "table" and m.id), tonumber(type(m) == "table" and m.choice)
		if id and choice then
			out[id] = choice
		end
	end
	return out
end

function getTreeNodeMap()
	return nodeMap
end

-- the per-class node variant shown (keystones 621 / 624)
function getTreeVariant()
	return getPlayerVocation()
end

function getTreeNodeWidget(id)
	return nodeWidgets[id]
end

function getTreeAllocated()
	return allocNodes
end

function getTreeFreePoints()
	return pointsOwned
end

function isTreeBusy()
	return isBuilding() or buildingFor ~= nil
end

function isTreeReadOnly()
	return viewing ~= nil
end

function getTreeViewing()
	return viewing
end

-- the saved effect of a mastery (the inspected character's while one is shown)
function getSavedMastery(id)
	if viewing then
		return viewing.masteries[id]
	end
	return savedMasteries[id]
end

-- the effect shown for a mastery: the planned choice, else the saved one
function getChosenMastery(id)
	local planned = plannerChoice and plannerChoice(id)
	return planned or getSavedMastery(id)
end

-- a node's widget and links after its planned flag (or chosen effect) changed
function refreshTreeNode(node)
	local widget = nodeWidgets[node.id]
	if widget then
		local planned = node.planned == true and not node.alloc
		if widget:isChecked() ~= planned then
			widget:setChecked(planned)
		end
		if node.isMastery then
			setNodeTooltip(widget, node)
		end
	end
	refreshConnectors(node)
end

-- centre the view on a node (search.lua): every child of the view moves together, within the drag limits
function panTreeTo(node)
	if not view or not node or not node.x then
		return
	end
	local x = math.max(-LIMIT_X / 4, math.min(LIMIT_X / 4, -node.x * SCALE))
	local y = math.max(-LIMIT_Y / 4, math.min(LIMIT_Y / 4, -node.y * SCALE))
	for _, child in pairs(view:getChildren()) do
		child:setMarginLeft(x)
		child:setMarginTop(y)
	end
end

-- viewother.lua: show another character's tree (data = {name, cls, line, vocation, nodes, masteries}) or, with nil,
-- the own tree again (the last sendNodes that arrived meanwhile, else a fresh one)
local ownNodes = nil
function setTreeViewing(data)
	if data then
		viewing = {name = data.name, cls = data.cls, line = data.line, vocation = data.vocation, nodes = data.nodes or {},
			masteries = masteryMap(data.masteries)}
		showAllocation(viewing.nodes, true)
		return
	end
	if not viewing then
		return
	end
	viewing = nil
	if ownNodes then
		local data = ownNodes
		ownNodes = nil
		updateNodes(data)
	else
		showAllocation({}, true)
		sendAction("requestNodesUnlocked")
	end
end

local function allocatedIds()
	if pendingAlloc then
		return pendingAlloc.ids -- not shown yet (a build is running): the allocation it will show
	end
	local ids = {}
	for id, node in pairs(allocNodes) do
		if not node.isStartNode then
			ids[#ids + 1] = id
		end
	end
	return ids
end

-- build again for the current zoom and vocation, keeping the shown allocation
function rebuildTree()
	builtFor = nil
	showAllocation(allocatedIds(), true)
end

-- synchronous full build (kept for callers outside the module); the window itself builds in slices
function createNodes()
	cancelBuild()
	for key in pairs(layers) do
		dropLayer(key)
	end
	decoView, nodesView = layerPanels()
	syncBuild = true
	local ok, err = pcall(function()
		for _, job in ipairs(buildTree()) do
			while job() do
			end
		end
	end)
	syncBuild = false
	if not ok then
		error(err)
	end
	builtFor = treeKey()
	layerClock = layerClock + 1
	layers[builtFor] = {key = builtFor, deco = decoView, nodes = nodesView, nodeWidgets = nodeWidgets,
		connectorWidgets = connectorWidgets, connectorStyles = connectorStyles, used = layerClock}
	decoView:setVisible(true)
	nodesView:setVisible(true)
end

function onExtendedOpcode(protocol, code, buffer)
	if not g_game.isOnline() then
		return 
	end

	local json_status, json_data = pcall(function ()
		return json.decode(buffer)
	end)

	if not json_status then
		g_logger.error("[Passive tree Bar] JSON error: " .. tostring(buffer))

		return false
	end

	local action = json_data.action
	local data = json_data.data

	if action == "sendPoints" then
		pointsOwned = data
		updatePoints(0)
	elseif action == "sendMessage" then
		sendMessageBox(data.title, data.message)
	elseif action == "sendNodes" then
		updateNodes(data)
	elseif action == "paragonState" then
		onParagonState(data) -- paragon.lua
	elseif ChaosTreeHandlers and ChaosTreeHandlers[action] then
		ChaosTreeHandlers[action](data) -- buildshare.lua, respec.lua
	end

	return 
end

function updateNodes(data)
	if viewing then
		ownNodes = data -- shown when the inspected tree is closed
		return
	end
	previewShown = false
	savedMasteries = masteryMap(data.masteries)
	if type(data.vocation) == "string" then
		serverVocation = data.vocation
	end
	if type(data.cls) == "string" then
		serverClass = data.cls
	end
	if type(data.line) == "string" then
		serverLine = data.line
	end
	currentPreset = data.preset
	currentSelected = currentPreset

	for i = 1, #data.presetsTable, 1 do
		if i == currentPreset then
			window.presets.presetsSave.presetName:setText(data.presetsTable[i].name)
		end

		local slots = window.presets.slots
		local presetItem = slots["preset" .. i]

		presetItem.setText(presetItem, data.presetsTable[i].name)
		presetItem.setColor(presetItem, "#ffffff")

		presetItem.unlocked = true
	end

	local slotsText = #data.presetsTable .. "/6"

	window.presets.presetSlots:setColoredText({
		"Slots: ",
		"#ffffff",
		slotsText,
		"#d47b06"
	})
	-- one pass over the built widgets (built first, over a few frames, when the zoom or the vocation changed)
	changesPending = false
	showAllocation(data.nodes, true)
	return
end

ISUPDATINGLOCAL = false

-- rebuild for the current zoom, keeping the shown allocation (every shown node blocked, as before)
function updateLocal()
	showAllocation(allocatedIds(), true)
end

-- a left click on a node: the planner (planner.lua) plans the path to it, takes a planned node out, or opens the choice
-- of a mastery; nothing is sent before Apply
function onClickNode(widget)
	if isBuilding() or viewing then
		return false
	end
	local node = nodeMap[tonumber(widget.getId(widget))]
	if not node then
		return false
	end
	return plannerClick(node)
end

function canAllocate(node)
	if node.locked then
		sendMessageBox("Error Allocating node", "This node belongs to another class.")

		return false
	end

	if allocNodes[node.exclude] then
		sendMessageBox("Error Allocating node", "You can not allocate 2 big nodes of the same path")

		return false
	end

	slot1 = pairs
	slot2 = node.out or {}

	for _, otherId in slot1(slot2) do
		local other = nodeMap[otherId]

		if other and other.alloc then
			return true
		end
	end

	slot1 = pairs
	slot2 = node.inputs or {}

	for _, otherId in slot1(slot2) do
		local other = nodeMap[otherId]

		if other and other.alloc then
			return true
		end
	end

	return false
end

-- a node next to a start node (the root, or the line's class section start): it connects on its own
function isStartLink(id)
	local node = nodeMap[id]
	if not node then
		return false
	end
	for _, list in ipairs({node.out or {}, node.inputs or {}}) do
		for _, otherId in pairs(list) do
			local other = nodeMap[otherId]
			if other and other.isStartNode then
				return true
			end
		end
	end
	return false
end

function hasPathToStart(node, visited)
	if visited[node.id] then
		return false
	end

	visited[node.id] = true
	slot2 = pairs
	slot3 = node.out or {}

	for _, otherId in slot2(slot3) do
		local other = nodeMap[otherId]

		if other and other.alloc and ((isStartLink(otherId)) or hasPathToStart(other, visited)) then
			return true
		end
	end

	slot2 = pairs
	slot3 = node.inputs or {}

	for _, otherId in slot2(slot3) do
		local other = nodeMap[otherId]

		if other and other.alloc and ((isStartLink(otherId)) or hasPathToStart(other, visited)) then
			return true
		end
	end

	return false
end

function canUnAllocate(node)
	node.alloc = false
	allocNodes[node.id] = nil
	slot1 = pairs
	slot2 = node.out or {}

	for _, otherId in slot1(slot2) do
		local other = nodeMap[otherId]

		if other and other.alloc and not other.isStartNode then
			if isStartLink(otherId) then
				node.alloc = true
				allocNodes[node.id] = node

				return true
			end

			if not hasPathToStart(other, {}) then
				node.alloc = true
				allocNodes[node.id] = node

				return false
			end
		end
	end

	slot1 = pairs
	slot2 = node.inputs or {}

	for _, otherId in slot1(slot2) do
		local other = nodeMap[otherId]

		if other and other.alloc and not other.isStartNode then
			if isStartLink(otherId) then
				node.alloc = true
				allocNodes[node.id] = node

				return true
			end

			if not hasPathToStart(other, {}) then
				node.alloc = true
				allocNodes[node.id] = node

				return false
			end
		end
	end

	for id, other in pairs(allocNodes) do
		if not other.isStartNode and hasPathToStart(other, {}) then
			node.alloc = true
			allocNodes[node.id] = node

			return true
		end
	end

	if isStartLink(node.id) then
		node.alloc = true
		allocNodes[node.id] = node

		return true
	end

	node.alloc = true
	allocNodes[node.id] = node

	return false
end

function getOrbitType(orbit, dist, nodeId)
	local orbitType = orbit
	dist = math.floor(dist)

	if orbitType == 4 and dist < SCALE/120 then
		orbitType = 3
	elseif orbitType == 1 and SCALE/80 < dist then
		orbitType = 6
	elseif orbitType ~= 4 and SCALE/80 < dist then
		orbitType = 5
	end

	return orbitType
end

function onDragEnter(widget, mousePos)
	local childCount = widget.getChildCount(widget)

	for i = 1, childCount, 1 do
		local child = widget.getChildByIndex(widget, i)
		child.hotSpot = {
			x = mousePos.x - child.getMarginLeft(child),
			y = mousePos.y - child.getMarginTop(child)
		}
	end

	return true
end

function onDragLeave(widget)
	return true
end

function onDragMove(widget, mousePos, mouseMoved)
	local childCount = widget.getChildCount(widget)

	for i = 1, childCount, 1 do
		local child = widget.getChildByIndex(widget, i)
		local offsetX = mousePos.x - child.hotSpot.x
		local offsetY = mousePos.y - child.hotSpot.y

		if offsetX < -LIMIT_X/4 then
			offsetX = -LIMIT_X/4
		end

		if offsetY < -LIMIT_Y/4 then
			offsetY = -LIMIT_Y/4
		end

		if LIMIT_X/4 < offsetX then
			offsetX = LIMIT_X/4
		end

		if LIMIT_Y/4 < offsetY then
			offsetY = LIMIT_Y/4
		end

		child.setMarginLeft(child, offsetX)
		child.setMarginTop(child, offsetY)
	end

	return 
end

function toggleStats()
	local stats = window:recursiveGetChildById("stats")

	if stats.getHeight(stats) == 30 then
		stats.setHeight(stats, 400)
	else
		stats.setHeight(stats, 30)
	end

	return 
end

function onSelectSpell()
	calculateStats()

	return 
end

function onSpellLevelChange(widget, value)
	calculateStats()

	return 
end

-- the summed stats of the allocated nodes (planned: of the planner's nodes instead); a mastery gives its chosen effect
function getSkillTreeBonuses(planned)
	local nodes = {}

	if planned then
		nodes = plannerIds and plannerIds() or {}
	else
		for k, v in pairs(allocNodes) do
			table.insert(nodes, k)
		end
	end

	local bonusTable = {}

	for k, id in pairs(nodes) do
		local node = nodeMap[id]

		if node then
			local vocationNode = node[getPlayerVocation()]
			local customStats = (vocationNode and vocationNode.customStats) or node.customStats
			if node.isMastery then
				local effect = (node.masteries or {})[getChosenMastery(id) or 0]
				customStats = effect and effect.customStats or nil
			end

			if customStats then
				for name, value in pairs(customStats) do
					if not bonusTable[name] then
						bonusTable[name] = value
					else
						bonusTable[name] = bonusTable[name] + value
					end
				end
			end
		end
	end

	return bonusTable
end

-- the class text at the top of "Info & Bonuses" (by class key, the server's sendNodes `cls`): what the class plays as and
-- where its keystones are (short lines: the panel is narrow)
local function special(title, color, lines)
	return { { { title .. ":", color, "\n" .. table.concat(lines, "\n"), "#f8f8f8" }, height = 14 * (#lines + 1) + 4 } }
end

local vocationSpecials = {
	warrior = special("Warrior", "#FFA500", {"Melee, heavy armour, the most health.", "Keystones: Cleaving Arc, Bulwark.", "Ascends: Juggernaut or Berserker."}),
	juggernaut = special("Juggernaut", "#FFA500", {"The tank: taunts, damage reduction,", "shield block. Keystones: Immovable,", "Bulwark."}),
	berserker = special("Berserker", "#FFA500", {"Two-handed area damage, rage as", "health drops. Keystones: Cleaving Arc,", "Undying Rage."}),
	ranger = special("Ranger", "#FFFF00", {"Bows and crossbows. Keystones:", "Ricochet, Deadeye.", "Ascends: Deadeye or Beastmaster."}),
	deadeye = special("Deadeye", "#FFFF00", {"The top single-target damage.", "Keystones: Hunter's Focus,", "Deadeye."}),
	beastmaster = special("Beastmaster", "#FFFF00", {"Companions beside you, bow with", "arrow splash. Keystones: Ricochet,", "Pack Alpha."}),
	mystic = special("Mystic", "#00FFFF", {"Spells, wands and rods. Keystones:", "Arcane Echo, Elemental Overload.", "Ascends: Elementalist or Illusionist."}),
	elementalist = special("Elementalist", "#00FFFF", {"The top area damage. Keystones:", "Arcane Echo, Elemental Overload."}),
	illusionist = special("Illusionist", "#B070FF", {"The best healer, party attack buffs.", "Keystones: Shared Phantasm,", "Inspiring Illusion."}),
	thief = special("Thief", "#C0C0C0", {"Light blades, shurikens, stealth.", "Class section (top left): Ninja", "and Samurai paths after ascension.", "Line keystone: Blackblood Creed."}),
	ninja = special("Ninja", "#C0C0C0", {"Dual daggers, evasion, shadow.", "Class section (top left), keystone", "Living Shadow; Blackblood Creed."}),
	samurai = special("Samurai", "#C0C0C0", {"Duelist off-tank: parries, counters,", "taunts. Class section (top left),", "keystone Way of the Blade;", "Blackblood Creed."}),
	necromancer = special("Necromancer", "#7FFF9F", {"Skeletons, curses and corpses.", "Class section (top left): Lich and", "Bone Lord paths after ascension.", "Line keystone: Covenant of the Grave."}),
	lich = special("Lich", "#7FFF9F", {"Curses, rot, life drain, one shade.", "Class section (top left), keystone", "Hoarded Souls; Covenant of the Grave."}),
	bonelord = special("Bone Lord", "#7FFF9F", {"The army, the Bone Golem, a banner.", "Class section (top left), keystone", "Bone Colossus; Covenant of the Grave."}),
	monk = special("Monk", "#FFD27F", {"Unarmed strikes build chi, finishers", "spend it. Class section (top left):", "Shadowfist and Iron Sage paths.", "Line keystone: Scarred Discipline."}),
	shadowfist = special("Shadowfist", "#FFD27F", {"Single-target burst, focus crits.", "Class section (top left), keystone", "Hundred Hands; Scarred Discipline."}),
	ironsage = special("Iron Sage", "#FFD27F", {"Chi healer: Kindled Breath, Mantra,", "Chi Ward. Class section (top left),", "keystone Flowing Mercy;", "Scarred Discipline."}),
	templar = special("Templar", "#FFF4B0", {"Holy melee, shield, a defence aura.", "Class section (top left): Inquisitor", "and Sentinel paths after ascension.", "Line keystone: Penitent's Wrath."}),
	inquisitor = special("Inquisitor", "#FFF4B0", {"Holy area damage, Judgement, Zealotry.", "Class section (top left), keystone", "Divine Verdict; Penitent's Wrath."}),
	sentinel = special("Sentinel", "#FFF4B0", {"Tank-support, the strongest aura.", "Class section (top left), keystone", "Bastion; Penitent's Wrath."})
}

function calculateStats()
	local bonuses = getSkillTreeBonuses()
	local bonusText = getCustomStatString(bonuses, true)
	local stats = window:recursiveGetChildById("stats")
	local labels = stats.recursiveGetChildById(stats, "labels")

	labels.destroyChildren(labels)

	if vocationSpecials[getPlayerClass() or ""] then
		for _, sp in pairs(vocationSpecials[getPlayerClass()]) do
			local label = g_ui.createWidget("InfoLabel", labels)

			label.setColoredText(label, sp[1])
			label.setHeight(label, sp.height)
		end
	end

	label = g_ui.createWidget("InfoLabel", labels)

	label:setText("---------------- CURRENT BONUSES ----------------")

	for k, v in pairs(bonusText) do
		label = g_ui.createWidget("InfoLabel", labels)

		label:setText(v)
	end

	-- the planner's nodes (planner.lua): what Apply would add
	local plannedIds = plannerIds and plannerIds() or {}
	if #plannedIds > 0 then
		label = g_ui.createWidget("InfoLabel", labels)
		label:setText(string.format("---------------- PLANNED (%d) ----------------", #plannedIds))
		for _, v in pairs(getCustomStatString(getSkillTreeBonuses(true), true)) do
			label = g_ui.createWidget("InfoLabel", labels)
			label:setText(v)
			label:setColor("#7fd0ff")
		end
	end

	-- Paragon track (paragon.lua): the applied bonuses, added on top of the tree's by the server (not of an inspected tree)
	local paragon = not viewing and getParagonState and getParagonState()
	if paragon then
		label = g_ui.createWidget("InfoLabel", labels)
		label:setText("---------------- PARAGON ----------------")
		local lines = ParagonMath.bonusLines(paragon)
		if not paragon.unlocked then
			lines = {string.format("Unlocks at level %d.", paragon.startLevel or 1000)}
		elseif #lines == 0 then
			lines = {string.format("%d Paragon points to spend (Paragon button).", paragon.free or 0)}
		elseif (paragon.free or 0) > 0 then
			table.insert(lines, string.format("%d unspent Paragon points.", paragon.free))
		end
		for _, line in ipairs(lines) do
			label = g_ui.createWidget("InfoLabel", labels)
			label:setText(line)
		end
	end

	return 
end

function destroy()
	serverVocation = nil -- the next character may have another class
	serverClass, serverLine = nil, nil
	destroyParagon() -- paragon.lua
	destroyTrials() -- trials.lua
	cancelBuild()
	builtFor = nil
	pendingAlloc = nil
	layers, spare = {}, {} -- the panels go with the window
	viewing, savedMasteries = nil, {}
	if destroyPlanner then
		destroyPlanner() -- planner.lua
	end
	allocNodes = {}
	nodeWidgets = {}
	connectorWidgets = {}
	connectorStyles = {}
	if window then
		view = nil
		decoView = nil
		nodesView = nil
		background = nil
		treeData = {}

		window:destroy()

		window = nil
		pointsOwned = 0

		g_extendedtooltip.hide()
	end

	return 
end

function show()
	SCALE = SCALE_MAX

	if not window then
		return 
	end
	if viewing and closeOtherTree then
		closeOtherTree() -- viewother.lua: the own tree again
	end

	sendAction("requestPoints")
	sendAction("requestNodesUnlocked")
	sendAction("paragonRequest")
	window:show()
	window:raise()
	window:focus()
	-- The widgets are kept between openings: the tree shows the allocation it had (rebuilt only when the zoom went back
	-- to the default) until the server's sendNodes, which then changes only the nodes that differ. Before the first
	-- sendNodes the vocation (keystone icons) is not known, so the first build waits for it instead of building twice.
	if serverVocation then
		showAllocation(allocatedIds(), true)
	else
		scheduleEvent(function()
			if window and window:isVisible() and not builtFor and not isBuilding() then
				showAllocation({}, true)
			end
		end, 1000)
	end
	for _, child in pairs(view:getChildren()) do
		child.setMarginLeft(child, STARTOFFSET.x)
		child.setMarginTop(child, STARTOFFSET.y)
	end

	return 
end

function hide()
	if not window then
		return 
	end

	window.presets:hide()
	closeParagon()
	closeTrials()
	if closeMasteryChoice then
		closeMasteryChoice() -- planner.lua
	end
	if viewing and closeOtherTree then
		closeOtherTree() -- viewother.lua
	end
	window:hide()

	if messageBox then
		messageBox:destroy()

		messageBox = nil
	end

	return 
end

function sendAction(action, data)
	if not g_game.getFeature(GameExtendedOpcode) then
		return 
	end

	local protocolGame = g_game.getProtocolGame()

	if data == nil then
		data = {}
	end

	if protocolGame then
		protocolGame.sendExtendedJSONOpcode(protocolGame, CODE_SKILLTREE, {
			action = action,
			data = data
		})
	end

	return 
end

-- Apply: the planner's whole plan in one planApply request (planner.lua)
function applyPoints()
	if viewing then
		return
	end
	plannerApply()
end

function presets()
	if window.presets:isVisible() then
		window.presets:hide()
	else
		window.presets:show()
	end

	return 
end

function refund()
	sendAction("refund")

	return 
end

function updatePoints(value)
	pointsOwned = pointsOwned + value

	window.pWindow.points:setText(formatShortNumber(pointsOwned) .. " points")
	if plannerUpdateBar then
		plannerUpdateBar() -- planner.lua: the plan's cost against the free points
	end

	return 
end

local zoomFrom = nil -- the SCALE before the last zoom step (updateZoom)
SCALE_CHANGE = 0.70
SCALE_MAX = 0.7
SCALE_MIN = 0.4
SCALE = SCALE_MAX

function zoomLess()
	if SCALE <= SCALE_MIN then
		window.zoomLess:setEnabled(false)
		return 
	end

	window.zoomLess:setEnabled(true)
	zoomFrom = SCALE
	SCALE = SCALE * SCALE_CHANGE

	updateZoom()
end

function zoomPlus()
	if SCALE_MAX <= SCALE then
		window.zoomPlus:setEnabled(false)
		return 
	end

	window.zoomPlus:setEnabled(true)
	zoomFrom = SCALE
	SCALE = SCALE / SCALE_CHANGE

	updateZoom()
end

-- the widgets are built (and sized) for the new SCALE by updateLocal, a slice per frame (or a cached zoom level is
-- shown); the view keeps the same point of the tree in its centre
function updateZoom()
	if view and zoomFrom and zoomFrom > 0 then
		local ratio = SCALE / zoomFrom
		for _, child in pairs(view:getChildren()) do
			local x = math.max(-LIMIT_X / 4, math.min(LIMIT_X / 4, child:getMarginLeft() * ratio))
			local y = math.max(-LIMIT_Y / 4, math.min(LIMIT_Y / 4, child:getMarginTop() * ratio))
			child:setMarginLeft(x)
			child:setMarginTop(y)
		end
	end
	updateLocal()
	return 
end

function reset()
	if messageBox then
	  messageBox:destroy()
	  messageBox = nil
	end
  
	local player = g_game.getLocalPlayer()
	local level  = player and player:getLevel() or 1
	local cost   = level * 250
  
	local text = string.format(
	  "You are about to reset your passive tree for %d gold coins (Level: %d x 250 gold per level). Proceed?",
	  cost, level
	)
	if respecResetText then
	  text = respecResetText() -- respec.lua: the server's price (respecInfo)
	end
  
	local function okFunc()
	  sendAction("resetPreset", currentSelected)
	  sendAction("requestPoints")
	  messageBox:destroy()
	  messageBox = nil
	end
  
	local function cancelFunc()
	  messageBox:destroy()
	  messageBox = nil
	end
  
	messageBox = displayGeneralBox(
	  "Reset Warning",
	  text,
	  {
		{ text = tr("Ok"),     callback = okFunc },
		{ text = tr("Cancel"), callback = cancelFunc },
		anchor = AnchorHorizontalCenter
	  },
	  okFunc
	)
  end
  

function sendMessageBox(title, message)
	if messageBox then
		messageBox:destroy()

		messageBox = nil
	end

	local function okFunc()
		messageBox:destroy()

		messageBox = nil

		return 
	end

	messageBox = displayGeneralBox(title, message, {
		{
			text = tr("Ok"),
			callback = okFunc
		},
		anchor = AnchorHorizontalCenter
	}, okFunc)

	return 
end

-- keystone stats (nodes 621 and 624, one per class of the Warrior, Ranger and Mystic lines, and the keystones of the
-- class sections); effects on the server in passivetree_keystones.lua and the class scripts (class_tree.lua)
KEYSTONE_NAMES = {
	ksCleavingArc = "Cleaving Arc", ksBulwark = "Bulwark", ksRicochet = "Ricochet", ksDeadeye = "Deadeye",
	ksArcaneEcho = "Arcane Echo", ksOverload = "Elemental Overload", ksOvergrowth = "Overgrowth", ksThorns = "Thorns",
	ksSharedPhantasm = "Shared Phantasm", ksInspiringIllusion = "Inspiring Illusion",
	ksImmovable = "Immovable", ksUndyingRage = "Undying Rage", ksHuntersFocus = "Hunter's Focus", ksPackAlpha = "Pack Alpha",
	ksLivingShadow = "Living Shadow", ksWayOfTheBlade = "Way of the Blade", ksHoardedSouls = "Hoarded Souls",
	ksBoneColossus = "Bone Colossus", ksHundredHands = "Hundred Hands", ksFlowingMercy = "Flowing Mercy",
	ksDivineVerdict = "Divine Verdict", ksBastion = "Bastion",
	ksBlackbloodCreed = "Blackblood Creed", ksGraveCovenant = "Covenant of the Grave",
	ksScarredDiscipline = "Scarred Discipline", ksPenitentWrath = "Penitent's Wrath",
	-- the build archetype keystones (server archetypes_config.lua; docs/BUILDS.md)
	arPyreOath = "Pyre Oath", arSanguine = "Sanguine Covenant", arThornbound = "Thornbound Oath",
	arOpenHand = "Open Hand Creed", arContagion = "Contagion Rite", arCascade = "Cascade Edge",
	arStormstring = "Stormstring", arWinterLattice = "Winter's Lattice", arEffigy = "Effigy Covenant",
	arCinderSigil = "Sigil of Cinders", arAetherEdge = "Aether Edge", arReliquary = "Reliquary Vow",
	arSnarewright = "Snarewright's Creed", arVigils = "Covenant of Vigils", arIronTithe = "Iron Tithe",
	arHollowVessel = "Hollow Vessel"
}
-- class notables of the class sections (their effect is in the node's own tooltip lines)
CLASS_NOTABLE_NAMES = {
	ctTwinFangs = "Twin Fangs", ctFleetShadow = "Fleet Shadow", ctIronParry = "Iron Parry",
	ctSpreadingBlight = "Spreading Blight", ctLingeringRot = "Lingering Rot", ctLegion = "Legion",
	ctBannerBearer = "Banner Bearer", ctNerveStrike = "Nerve Strike", ctDeepMantra = "Deep Mantra",
	ctBurningZeal = "Burning Zeal", ctSanctuary = "Sanctuary"
}

-- withKeystones: also list the allocated keystones by name (the bonus summary; a node's tooltip has the name as title)
function getCustomStatString(t, withKeystones)
	local texts = {}

	if withKeystones then
		local names = {}
		for key, name in pairs(KEYSTONE_NAMES) do
			if t[key] then
				table.insert(names, name)
			end
		end
		table.sort(names)
		for _, name in ipairs(names) do
			table.insert(texts, "Keystone: " .. name)
		end
		names = {}
		for key, name in pairs(CLASS_NOTABLE_NAMES) do
			if t[key] then
				table.insert(names, name)
			end
		end
		table.sort(names)
		for _, name in ipairs(names) do
			table.insert(texts, "Class: " .. name)
		end
	end

	if t.strength then
		table.insert(texts, string.format("+%.1f strength.", t.strength/1))
	end

	if t.dexterity then
		table.insert(texts, string.format("+%.1f dexterity.", t.dexterity/1))
	end

	if t.spirit then
		table.insert(texts, string.format("+%.1f spirit.", t.spirit/1))
	end

	if t.wisdom then
		table.insert(texts, string.format("+%.1f wisdom.", t.wisdom/1))
	end

	if t.vitality then
		table.insert(texts, string.format("+%.1f vitality.", t.vitality/1))
	end

	if t.intelligence then
		table.insert(texts, string.format("+%.1f intelligence.", t.intelligence/1))
	end

	if t.incrementWater then
		table.insert(texts, string.format("+%.1f Water Damage.", t.incrementWater/1))
	end

	if t.incrementHoly then
		table.insert(texts, string.format("+%.1f Holy Damage.", t.incrementHoly/1))
	end

	if t.incrementPhysical then
		table.insert(texts, string.format("+%.1f Physical Damage.", t.incrementPhysical/1))
	end

	if t.incrementEarth then
		table.insert(texts, string.format("+%.1f Earth Damage.", t.incrementEarth/1))
	end

	if t.incrementFire then
		table.insert(texts, string.format("+%.1f Fire Damage.", t.incrementFire/1))
	end

	if t.incrementDeath then
		table.insert(texts, string.format("+%.1f Death Damage.", t.incrementDeath/1))
	end

	if t.incrementHealth then
		table.insert(texts, string.format("+%.1f Health Spells.", t.incrementHealth/1))
	end

	if t.incrementIce then
		table.insert(texts, string.format("+%.1f Ice Damage.", t.incrementIce/1))
	end

	if t.incrementEnergy then
		table.insert(texts, string.format("+%.1f Energy Damage.", t.incrementEnergy/1))
	end

	if t.incrementArcane then
		table.insert(texts, string.format("+%.1f Arcane Damage.", t.incrementArcane/1))
	end

	if t.incrementLifeDrain then
		table.insert(texts, string.format("+%.1f Life Drain Damage.", t.incrementLifeDrain/1))
	end

	if t.incrementManaDrain then
		table.insert(texts, string.format("+%.1f Mana Drain Damage.", t.incrementManaDrain/1))
	end

	if t.incrementDrown then
		table.insert(texts, string.format("+%.1f Drown Damage.", t.incrementDrown/1))
	end

	if t.absorbFire then
		table.insert(texts, string.format("+%.1f Fire Absorption.", t.absorbFire/1))
	end

	if t.absorbDeath then
		table.insert(texts, string.format("+%.1f Death Absorption.", t.absorbDeath/1))
	end

	if t.absorbEnergy then
		table.insert(texts, string.format("+%.1f Energy Absorption.", t.absorbEnergy/1))
	end

	if t.absorbIce then
		table.insert(texts, string.format("+%.1f Ice Absorption.", t.absorbIce/1))
	end

	if t.absorbArcane then
		table.insert(texts, string.format("+%.1f Arcane Absorption.", t.absorbArcane/1))
	end

	if t.absorbWater then
		table.insert(texts, string.format("+%.1f Water Absorption.", t.absorbWater/1))
	end

	if t.absorbPhysical then
		table.insert(texts, string.format("+%.1f Physical Absorption.", t.absorbPhysical/1))
	end

	if t.absorbDrown then
		table.insert(texts, string.format("+%.1f Drown Absorption.", t.absorbDrown/1))
	end

	if t.absorbLife then
		table.insert(texts, string.format("+%.1f Life Drain Absorption.", t.absorbLife/1))
	end

	if t.absorbMana then
		table.insert(texts, string.format("+%.1f Mana Drain Absorption.", t.absorbMana/1))
	end

	if t.absorbHoly then
		table.insert(texts, string.format("+%.1f Holy Absorption.", t.absorbHoly/1))
	end

	if t.absorbEarth then
		table.insert(texts, string.format("+%.1f Earth Absorption.", t.absorbEarth/1))
	end

	if t.experience then
		table.insert(texts, string.format("+%.1f%% Experience Gained.", t.experience * 0.1))
	end

	if t.loot then
		table.insert(texts, string.format("+%.1f%% Loot Increased.", t.loot * 0.2))
	end

	if t.rarityLoot then
		table.insert(texts, string.format("+%.1f%% Rarity Loot Increased.", t.rarityLoot * 1.0))
	end

	if t.speed then
		table.insert(texts, string.format("+%.1f Increased Speed.", t.speed / 10))
	end

	if t.swordSkill then
		table.insert(texts, string.format("+%.1f Sword Skill.", t.swordSkill/1))
	end

	if t.axeSkill then
		table.insert(texts, string.format("+%.1f Axe Skill.", t.axeSkill/1))
	end

	if t.clubSkill then
		table.insert(texts, string.format("+%.1f Club Skill.", t.clubSkill/1))
	end

	if t.distanceSkill then
		table.insert(texts, string.format("+%.1f Distance Skill.", t.distanceSkill/1))
	end

	if t.magicSkill then
		table.insert(texts, string.format("+%.1f Magic Level.", t.magicSkill/1))
	end

	if t.shieldingSkill then
		table.insert(texts, string.format("+%.1f Shielding Skill.", t.shieldingSkill/1))
	end

	if t.craftingSkill then
		table.insert(texts, string.format("+%.1f Crafting Skill.", t.craftingSkill/1))
	end

	if t.herbalistSkill then
		table.insert(texts, string.format("+%.1f Herbalist Skill.", t.herbalistSkill/1))
	end

	if t.woodcuttingSkill then
		table.insert(texts, string.format("+%.1f Woodcutting Skill.", t.woodcuttingSkill/1))
	end

	if t.miningSkill then
		table.insert(texts, string.format("+%.1f Mining Skill.", t.miningSkill/1))
	end

	if t.armorsmithSkill then
		table.insert(texts, string.format("+%.1f Armorsmith Skill.", t.armorsmithSkill/1))
	end

	if t.jewelsmithSkill then
		table.insert(texts, string.format("+%.1f Jewelsmith Skill.", t.jewelsmithSkill/1))
	end

	if t.weaponsmithSkill then
		table.insert(texts, string.format("+%.1f Weaponsmith Skill.", t.weaponsmithSkill/1))
	end

	if t.criticalHitChance then
		table.insert(texts, string.format("+%.1f Critical Hit Chance.", t.criticalHitChance/1))
	end

	if t.criticalHitAmount then
		table.insert(texts, string.format("+%.1f Critical Hit Amount.", t.criticalHitAmount/1))
	end

	if t.lifeLeechChance then
		table.insert(texts, string.format("+%.1f Life Leech Chance.", t.lifeLeechChance/1))
	end

	if t.lifeLeechAmount then
		table.insert(texts, string.format("+%.1f Life Leech Amount.", t.lifeLeechAmount/1))
	end

	if t.manaLeechChance then
		table.insert(texts, string.format("+%.1f Mana Leech Chance.", t.manaLeechChance/1))
	end

	if t.manaLeechAmount then
		table.insert(texts, string.format("+%.1f Mana Leech Amount.", t.manaLeechAmount/1))
	end

	if t.multiIncrement then
		table.insert(texts, string.format("+%.1f Increase all damage elements.", t.multiIncrement/1))
	end

	if t.absorbAllElements then
		table.insert(texts, string.format("+%.1f Absorb all Elements.", t.absorbAllElements/1))
	end


	return texts
end

return