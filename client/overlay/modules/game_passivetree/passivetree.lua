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


-- the vocation whose node variants (keystones) are shown; the server names it in sendNodes, because the
-- number the client's player:getVocation() returns does not follow one scheme (an Elite Knight reports 4)
local serverVocation = nil

local function getPlayerVocation()
  if serverVocation then
    return serverVocation
  end
  local player = g_game.getLocalPlayer()
  local cid = player:getVocation()
  if cid == 1 then
    return "knight"
  elseif cid == 2 then
    return "paladin"
  elseif cid == 3 then
    return "sorcerer"
  elseif cid == 4 then
    return "druid"
  elseif cid == 5 then
	return "illusionist"
  elseif cid == 6 then
	return "monk"
  end
  return nil
end

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

function isVisible()
    return window and window:isVisible()
end

function toggle()
	if modules.game_passivetree.isVisible() then
	  close()
	else
	  show()
	end
  end

function changeVocation(button)
	VocationSelected = button.getText(button):lower()

	createNodes()

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

function createNodes()
	local totalNodes = 0

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

	decoView:destroyChildren()
	nodesView:destroyChildren()

	local widget = nil

	-- for _, static in pairs(treeData.static[getPlayerVocation()]) do
	-- 	widget = g_ui.createWidget("DecorationCircle", decoView)

	-- 	widget.setMarginLeft(widget, static.x*SCALE)
	-- 	widget.setMarginTop(widget, static.y*SCALE)
	-- 	widget.setImageSource(widget, static.file)

	-- 	widget = nil
	-- end

	for _, group in pairs(treeData.groups) do
		if group.orbit ~= 0 then
			widget = g_ui.createWidget("DecorationCircle", decoView)

			widget.setMarginLeft(widget, group.x*SCALE)
			widget.setMarginTop(widget, group.y*SCALE)

			if group.bgOffsetY then
				widget.setMarginBottom(widget, group.bgOffsetY*SCALE)
			end

			widget.setImageSource(widget, "/images/passivetree/PSGroupBackground" .. group.orbit)

			if DEBUG then
				widget.setText(widget, _)
			end

			widget = nil

			if group.mastery then
				widget = g_ui.createWidget("DecorationCircle", decoView)

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
			end
		end
	end

	local NODES_MAX = 700

	for id = 1, NODES_MAX, 1 do
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

			if node.isStartNode then
				node.alloc = true
				allocNodes[node.id] = node
				widget = g_ui.createWidget("DecorationCircle", decoView)

				widget.setMarginLeft(widget, group.x*SCALE)
				widget.setMarginTop(widget, group.y*SCALE)
				widget.setImageSource(widget, icon.file)
				widget.setImageClip(widget, icon.x .. " " .. icon.y .. " " .. icon.w .. " " .. icon.h)
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

				if node.isUncommon then
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

				widget = g_ui.createWidget(nodeClass, nodesView)

				widget.setId(widget, node.id)
				widget.setMarginLeft(widget, node.x*SCALE)
				widget.setMarginTop(widget, node.y*SCALE)
				widget.setIconOffsetX(widget, widget.getIconOffsetX(widget)*SCALE)
				widget.setIconOffsetY(widget, widget.getIconOffsetY(widget)*SCALE)
				widget.setImageClip(widget, icon.x .. " " .. icon.y .. " " .. icon.w .. " " .. icon.h)
				if icon.file then -- keystone icons live in their own sheet (treedata/icons.lua)
					widget.setImageSource(widget, icon.file)
				end

				local tooltipType = 1
				
				if node.isUncommon then
					tooltipType = 2
				elseif node.isRare then
					tooltipType = 3
				elseif node.isVeryRare then
					tooltipType = 7
				elseif node.isMythic then
					tooltipType = 6
				elseif node.isDivine then
					tooltipType = 8
				end

				if DEBUG then
					widget.setText(widget, id)
				end

				local customStats = (vocationNode and vocationNode.customStats) or node.customStats
				local nodeName = (vocationNode and vocationNode.name) or node.name

				if customStats then
					local texts = getCustomStatString(customStats)
					-- keystones: the vocation's own description lines under the stats
					for _, line in ipairs((vocationNode and vocationNode.stats) or {}) do
						table.insert(texts, line)
					end

					widget.setExtendedTooltip(widget, nodeName .. ((DEBUG and " (ID: " .. id .. ")") or ""), texts, tooltipType)
				elseif node.stats then
					widget.setExtendedTooltip(widget, nodeName .. ((DEBUG and " (ID: " .. id .. ")") or ""), node.stats, tooltipType)
				end

				widget.onClick = onClickNode
			end

			nodeMap[node.id] = node
			widget = nil
			totalNodes = totalNodes + 1
		end
	end

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
			  local widget = g_ui.createWidget("Orbit" .. orbitType .. lineType, decoView)
			  widget:setId(node1.id .. "-" .. node2.id)
		
			  local avgAngle = angle1 + (arcAngle / 2)
			  local rotation = (avgAngle * 180 / m_pi) + (flip and -45 or 45)
			  widget:setRotation(rotation)
		
			  local midX = (node1.x + node2.x) / 2
			  local midY = (node1.y + node2.y) / 2
			  widget:setMarginLeft(midX * SCALE)
			  widget:setMarginTop(midY * SCALE)

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

  		local widget = g_ui.createWidget("LineConnector" .. lineType, decoView)
  		widget:setId(node1.id .. "-" .. node2.id)
  		widget:setMarginLeft(x * SCALE)
  		widget:setMarginTop(y * SCALE)
  		widget:setRotation(angle)
  		widget:setWidth(endS * 256 * SCALE)

		widget = nil

		return 
	end

	for k, node in pairs(treeData.nodes) do
		slot9 = pairs
		slot10 = node.out or {}

		for _, otherId in slot9(slot10) do
			local other = nodeMap[otherId]

			t_insert(node.linkedId, otherId)
			t_insert(other.linkedId, node.id)

			if not node.isStartNode and not other.isStartNode then
				BuildConnector(node, other)
			end
		end
	end

	return 
end

function onExtendedOpcode(protocol, code, buffer)
	if not g_game.isOnline() then
		return 
	end

	local json_status, json_data = pcall(function ()
		return json.decode(buffer)
	end)

	if not json_status then
		g_logger.error("[Passive tree Bar] JSON error: " .. data)

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
	end

	return 
end

function updateNodes(data)
	if type(data.vocation) == "string" then
		serverVocation = data.vocation
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
	createNodes()

	local nodes = data.nodes
	allocNodes = {
		nodeMap[1]
	}
	local runs = 0
    ignorePoints = true
	repeat
		for k, v in pairs(nodes) do
			local widget = nodesView:recursiveGetChildById(v) or decoView:recursiveGetChildById(v)

			if widget and onClickNode(widget) then
				table.remove(nodes, k)

				widget.blocked = true

				break
			end
		end

		runs = runs + 1
	until #nodes == 0 or 400 <= runs
    ignorePoints = false
	updateZoom()
    changesPending = false
	return 
end

ISUPDATINGLOCAL = false

function updateLocal()
	ISUPDATINGLOCAL = true
	local data = {}

	for k, v in pairs(allocNodes) do
		t_insert(data, k)
	end

	createNodes()

	local runs = 0
	allocNodes = {
		nodeMap[1]
	}
	ignorePoints = true

	repeat
		for k, v in pairs(data) do
			local widget = nodesView:recursiveGetChildById(v)

			if widget and onClickNode(widget) then
				table.remove(data, k)

				widget.blocked = true

				break
			end
		end

		runs = runs + 1
	until #data == 0 or 400 <= runs

	ISUPDATINGLOCAL = false
	ignorePoints = false

	return 
end

function onClickNode(widget)
	local nodeId = tonumber(widget.getId(widget))
	local node = nodeMap[nodeId]

	if node then
		if not node.alloc and not canAllocate(node) then
			return false
		end

		if node.alloc and not canUnAllocate(node) then
			return false
		end

		if widget.blocked and node.alloc then
			return false
		end

		if node.alloc then
			allocNodes[node.id] = nil

			if not ignorePoints then
				updatePoints(1)
			end
		else
			if not ignorePoints and pointsOwned <= 0 then
				return false
			end

			if not ignorePoints then
				updatePoints(-1)
			end

			allocNodes[node.id] = node
		end

		node.alloc = not node.alloc

		widget.setOn(widget, not widget.isOn(widget))

		slot3 = pairs
		slot4 = node.out or {}

		for _, otherId in slot3(slot4) do
			local connector = decoView:getChildById(node.id .. "-" .. otherId)
			connector = connector or decoView:getChildById(otherId .. "-" .. node.id)

			if connector then
				local other = nodeMap[otherId]

				if node.groupX == other.groupX and node.orbit == other.orbit then
					local lineType = "Normal"

					if node.alloc and other.alloc then
						lineType = "Active"
					elseif (node.alloc and not other.alloc) or (not node.alloc and other.alloc) then
						lineType = "Intermediate"
					end

					local vX = other.x - node.x
					local vY = other.y - node.y
					local dist = m_sqrt(vX*vX + vY*vY)
					local orbitType = getOrbitType(node.orbit, dist)

					connector.setStyle(connector, "Orbit" .. orbitType .. lineType)
				else
					local lineType = "Normal"

					if node.alloc and other.alloc then
						lineType = "Active"
					elseif (node.alloc and not other.alloc) or (not node.alloc and other.alloc) then
						lineType = "Intermediate"
					end

					connector.setStyle(connector, "LineConnector" .. lineType)
				end
			end
		end

		slot3 = pairs
		slot4 = node.inputs or {}

		for _, otherId in slot3(slot4) do
			local connector = decoView:getChildById(node.id .. "-" .. otherId)
			connector = connector or decoView:getChildById(otherId .. "-" .. node.id)

			if connector then
				local other = nodeMap[otherId]

				if node.groupX == other.groupX and node.orbit == other.orbit then
					local lineType = "Normal"

					if node.alloc and other.alloc then
						lineType = "Active"
					elseif (node.alloc and not other.alloc) or (not node.alloc and other.alloc) then
						lineType = "Intermediate"
					end

					local vX = other.x - node.x
					local vY = other.y - node.y
					local dist = m_sqrt(vX*vX + vY*vY)
					local orbitType = getOrbitType(node.orbit, dist)

					connector.setStyle(connector, "Orbit" .. orbitType .. lineType)
				else
					local lineType = "Normal"

					if node.alloc and other.alloc then
						lineType = "Active"
					elseif (node.alloc and not other.alloc) or (not node.alloc and other.alloc) then
						lineType = "Intermediate"
					end

					connector.setStyle(connector, "LineConnector" .. lineType)
				end
			end
		end
	end

	if not ISUPDATINGLOCAL then
		calculateStats()
	end
    changesPending = true
	return true
end

function canAllocate(node)
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

function hasPathToStart(node, visited)
	if visited[node.id] then
		return false
	end

	visited[node.id] = true
	slot2 = pairs
	slot3 = node.out or {}

	for _, otherId in slot2(slot3) do
		local other = nodeMap[otherId]

		if other and other.alloc and ((2 <= otherId and otherId <= 7) or hasPathToStart(other, visited)) then
			return true
		end
	end

	slot2 = pairs
	slot3 = node.inputs or {}

	for _, otherId in slot2(slot3) do
		local other = nodeMap[otherId]

		if other and other.alloc and ((2 <= otherId and otherId <= 7) or hasPathToStart(other, visited)) then
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
			if 2 <= otherId and otherId <= 7 then
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
			if 2 <= otherId and otherId <= 7 then
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

	if 2 <= node.id and node.id <= 7 then
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

function getSkillTreeBonuses()
	local nodes = {}

	for k, v in pairs(allocNodes) do
		table.insert(nodes, k)
	end

	local bonusTable = {}

	for k, id in pairs(nodes) do
		local node = nodeMap[id]

		if node then
			local vocationNode = node[getPlayerVocation()]
			local customStats = (vocationNode and vocationNode.customStats) or node.customStats

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

local vocationSpecials = {

	knight = {
		{
			{
				"Knights & Elite Knights: ",
				"#FFA500",
				"\nKnights & Elite Knights embody timeless \nvalor and chivalry on the battlefield.",
				"#f8f8f8"
			},
			height = 55
		}
	},
	paladin = {
        {
            {
                "Paladins & Royal Paladins: ",
                "#FFFF00",
                "\nPaladins & Royal Paladins embody noble honor \nand unwavering courage on the battlefield.",
                "#f8f8f8"
            },
            height = 55
        }
    },
	sorcerer = {
        {
            {
                "Sorcerers & Master Sorcerers: ",
                "#00FFFF",
                "\nSorcerers & Master Sorcerers command elemental forces with unparalleled mystical\nprowess.",
                "#f8f8f8"
            },
            height = 55
        }
    },
    druid = {
        {
            {
                "Druids & Elder Druids: ",
                "#32CD32",
                "\nDruids & Elder Druids embody nature's \nresilience and healing power in every battle.",
                "#f8f8f8"
            },
            height = 55
        }
    },
    illusionist = {
        {
            {
                "Illusionist & Arch Illusionist: ",
                "#800080",
                "\nIllusionists & Arch Illusionists weave \narcane illusions to confound their foes.",
                "#f8f8f8"
            },
            height = 55
        }
    },
	monk = {
		{
			{
				"Monk & Exalted Monk: ",
				"FFECA41F",
				"\nMasters of unarmed combat, Monks channel inner strength through disciplined strikes.\nTheir fists become weapons of pure focus and spiritual energy.",
				"#f8f8f8"
			},
			height = 55
		}
    }
}

function calculateStats()
	local bonuses = getSkillTreeBonuses()
	local bonusText = getCustomStatString(bonuses, true)
	local stats = window:recursiveGetChildById("stats")
	local labels = stats.recursiveGetChildById(stats, "labels")

	labels.destroyChildren(labels)

	if vocationSpecials[getPlayerVocation()] then
		for _, sp in pairs(vocationSpecials[getPlayerVocation()]) do
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

	return 
end

function destroy()
	serverVocation = nil -- the next character may have another vocation
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
	createNodes()

	if not window then
		return 
	end

	sendAction("requestPoints")
	sendAction("requestNodesUnlocked")
	window:show()
	window:raise()
	window:focus()
	updateZoom()
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

function applyPoints()
	if not changesPending then
		return
	end
	local nodes = {}

	for k, v in pairs(allocNodes) do
		table.insert(nodes, k)
	end

	sendAction("sendNodes", {
		nodes = nodes,
		preset = currentPreset
	})
    changesPending = false
	return 
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

	return 
end

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
	SCALE = SCALE * SCALE_CHANGE

	updateZoom()
end

function zoomPlus()
	if SCALE_MAX <= SCALE then
		window.zoomPlus:setEnabled(false)
		return 
	end

	window.zoomPlus:setEnabled(true)
	SCALE = SCALE / SCALE_CHANGE

	updateZoom()
end

function updateZoom()
	updateLocal()

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

-- keystone stats (nodes 621 and 624, one per vocation); effects on the server in passivetree_keystones.lua
KEYSTONE_NAMES = {
	ksCleavingArc = "Cleaving Arc", ksBulwark = "Bulwark", ksRicochet = "Ricochet", ksDeadeye = "Deadeye",
	ksArcaneEcho = "Arcane Echo", ksOverload = "Elemental Overload", ksOvergrowth = "Overgrowth", ksThorns = "Thorns",
	ksSharedPhantasm = "Shared Phantasm", ksInspiringIllusion = "Inspiring Illusion"
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