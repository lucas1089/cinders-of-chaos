m_BattlepassFunctions = {}
m_BattlepassList = {}

m_BattlepassFunctions.GameServerBattlepassItems = 97
m_BattlepassFunctions.GameServerParseBattlepassItems = 39

m_BattlepassFunctions.BATTLEPASS_REWARD_ITEM = 1
m_BattlepassFunctions.BATTLEPASS_REWARD_OUTFIT = 2
m_BattlepassFunctions.BATTLEPASS_REWARD_MOUNT = 3
m_BattlepassFunctions.BATTLEPASS_REWARD_WINGS = 4
m_BattlepassFunctions.BATTLEPASS_REWARD_PREMIUM = 5

m_BattlepassFunctions.BATTLEPASS_QUEST_NONE = 0
m_BattlepassFunctions.BATTLEPASS_QUEST_KILL_MONSTER = 1
m_BattlepassFunctions.BATTLEPASS_QUEST_KILL_MONSTERS = 2
m_BattlepassFunctions.BATTLEPASS_QUEST_KILL_BOSS = 3
m_BattlepassFunctions.BATTLEPASS_QUEST_GET_LEVEL = 4
m_BattlepassFunctions.BATTLEPASS_QUEST_CRAFT_ITEM = 5

m_BattlepassFunctions.MONSTER_NONE = 0
m_BattlepassFunctions.MONSTER_FIRST = 1
m_BattlepassFunctions.MONSTER_UNDERWATER = m_BattlepassFunctions.MONSTER_FIRST
m_BattlepassFunctions.MONSTER_ANIMAL = 2
m_BattlepassFunctions.MONSTER_UNDEAD = 3
m_BattlepassFunctions.MONSTER_HUMAN = 4
m_BattlepassFunctions.MONSTER_SERPENT = 5
m_BattlepassFunctions.MONSTER_DRAKEN = 6
m_BattlepassFunctions.MONSTER_LIZARD = 7
m_BattlepassFunctions.MONSTER_DRAGON = 8
m_BattlepassFunctions.MONSTER_BOSS = 9
m_BattlepassFunctions.MONSTER_MUTATED = 10
m_BattlepassFunctions.MONSTER_DJINN = 11
m_BattlepassFunctions.MONSTER_BONELORD = 12
m_BattlepassFunctions.MONSTER_MINOTAUR = 13
m_BattlepassFunctions.MONSTER_TROLL = 14
m_BattlepassFunctions.MONSTER_ORC = 15
m_BattlepassFunctions.MONSTER_GOBLIN = 16
m_BattlepassFunctions.MONSTER_GIANT = 17
m_BattlepassFunctions.MONSTER_ELF = 18
m_BattlepassFunctions.MONSTER_DWARF = 19
m_BattlepassFunctions.MONSTER_GEO_ELEMENTAL = 20
m_BattlepassFunctions.MONSTER_PYRO_ELEMENTAL = 21
m_BattlepassFunctions.MONSTER_CRYO_ELEMENTAL = 22
m_BattlepassFunctions.MONSTER_ELECTRO_ELEMENTAL = 23
m_BattlepassFunctions.MONSTER_DEMON = 24
m_BattlepassFunctions.MONSTER_ARACHNID = 25
m_BattlepassFunctions.MONSTER_WIZARD = 26

m_BattlepassFunctions.QUEST_DAILY = 1
m_BattlepassFunctions.QUEST_FIRST = m_BattlepassFunctions.QUEST_DAILY
m_BattlepassFunctions.QUEST_WEEKLY = 2
m_BattlepassFunctions.QUEST_SPECIAL = 3
m_BattlepassFunctions.QUEST_LAST = m_BattlepassFunctions.QUEST_SPECIAL

m_BattlepassFunctions.experience = 0
m_BattlepassFunctions.level = 0

ITEM_RARITY_NONE = 0
ITEM_RARITY_COMMON = 1
ITEM_RARITY_RARE = 2
ITEM_RARITY_EPIC = 3
ITEM_RARITY_LEGENDARY = 4
ITEM_RARITY_BRUTAL = 5

m_BattlepassFunctions.questCategoryTitles = {
	[m_BattlepassFunctions.QUEST_DAILY] = tr("Daily Quests"),
	[m_BattlepassFunctions.QUEST_WEEKLY] = tr("Weekly Quests"),
	[m_BattlepassFunctions.QUEST_SPECIAL] = tr("Special Quests")
}

m_BattlepassFunctions.messages = {
	[0] = "You already have premium battlepass. The purchase has been cancelled.",
	[1] = "You do not have enough premium points to buy the premium battlepass.",
	[2] = "Premium battlepass has been bought. Battlepass Points have been taken from your account.",
	[3] = "Quest has been shuffled. Battlepass Points have been taken from your account.",
	[4] = "You do not have enough premium points to shuffle this quest.",

	[50] = "Do you want to upgrade your battlepass to premium for 100 Battlepass Points?\nIf you buy premium you should know that if you have already completed levels, you will not be able to obtain premium rewards for levels already completed.",
	[51] = "Do you want to shuffle this quest for 10 Battlepass Points?",

	[100] = "Current status: Free battlepass",
	[101] = "Current status: Premium battlepass"
}

m_BattlepassFunctions.battlepassrewards = {}

function onLoad()
	connect(g_game, { 
		onGameEnd = onBattlepassGameEnd,
		onGameStart = onBattlepassGameStart
	})
	
	if g_game.isOnline() then
		onBattlepassGameStart()
	end
	
	m_BattlepassFunctions.registerProtocol()
end

function onUnload()
	disconnect(g_game, {
		onGameEnd = onBattlepassGameEnd,
		onGameStart = onBattlepassGameStart
	})
	
	onBattlepassGameEnd()
	m_BattlepassFunctions.unregisterProtocol()
end

function onBattlepassGameStart()
	m_BattlepassFunctions.button = modules.client_topmenu.addRightGameToggleButton("battlepassButton", tr("Battlepass"), "/images/topbuttons/battlepass", m_BattlepassFunctions.open, false, 4)
end

function onBattlepassGameEnd()
	m_BattlepassFunctions.destroy()

	if m_BattlepassFunctions.button then
		m_BattlepassFunctions.button:destroy()
		m_BattlepassFunctions.button = nil
	end
end

m_BattlepassFunctions.getExperiencePerLevel = function(level)
	return 500 + ((level / 2) * (2000 + ((level - 1) * 100)))
end

m_BattlepassFunctions.registerProtocol = function()
	ProtocolGame.registerOpcode(m_BattlepassFunctions.GameServerParseBattlepassItems, m_BattlepassFunctions.parseBattlepassItems)
end

m_BattlepassFunctions.unregisterProtocol = function()
	ProtocolGame.unregisterOpcode(m_BattlepassFunctions.GameServerParseBattlepassItems, m_BattlepassFunctions.parseBattlepassItems)
end

m_BattlepassFunctions.send = function(id, widget)
	if not g_game.isOnline() then
		return false
	end

	local msg = OutputMessage.create()
	msg:addU8(m_BattlepassFunctions.GameServerBattlepassItems)
	msg:addU8(id)
	--[[
		0 - open battlepass window
		1 - close battlepass window
		2 - complete the quest
		3 - shuffle the quest
		4 - buy premium battlepass
	]]--

	if id == 0 then
		if #m_BattlepassFunctions.battlepassrewards > 0 then
			msg:addU8(0)
		else
			msg:addU8(1)
		end
	elseif id == 2 or id == 3 then
		msg:addU16(widget.id)
	end

	g_game.getProtocolGame():send(msg)
end

m_BattlepassFunctions.addSeparator = function(id)
	local widget = g_ui.createWidget("BattlePassQuestLabel", m_BattlepassList.questsPanel)
	widget:setText(m_BattlepassFunctions.questCategoryTitles[id])
end

m_BattlepassFunctions.completeQuest = function(widget)
	m_BattlepassFunctions.send(2, widget)
end

m_BattlepassFunctions.shuffleQuest = function(widget)
	m_BattlepassFunctions.destroyHover()

	m_BattlepassList.window:setEnabled(false)
	m_BattlepassList.hover = g_ui.displayUI("premium_notification")
	m_BattlepassList.hover:getChildById("description"):setText(m_BattlepassFunctions.messages[51])
	m_BattlepassList.hover.data = { id = 1, widget = widget }
end

m_BattlepassFunctions.acceptPremiumNotification = function(widget)
	if m_BattlepassList.hover.data.id == 0 then
		-- Buy premium battlepass
		m_BattlepassFunctions.send(4)
	elseif m_BattlepassList.hover.data.id == 1 then
		-- Shuffle quest
		m_BattlepassFunctions.send(3, m_BattlepassList.hover.data.widget)
	end
	
	m_BattlepassFunctions.destroyHover()
end

m_BattlepassFunctions.updateCooldown = function(id, widget, amount, amountMax, cooldown)
	if amount < amountMax then
		return false
	end

	if not widget then
		widget = m_BattlepassFunctions.getQuestWidget(id)
		if not widget then
			return false
		end
	end

	local backgroundWidget = widget:getChildById("background")
	local shuffleButton = widget:getChildById("shuffle")
	local completedButton = widget:getChildById("completed")
	if cooldown == 0 then
		-- Quest is completed, but the rewards are not taken yet
		completedButton:setEnabled(true)
		shuffleButton:setEnabled(false)
		return
	elseif cooldown == 1 then
		-- If the cooldown is set to 1 then it means the quest is from special quests poll and cannot be repeated
		widget:setEnabled(false)
		backgroundWidget:show()
		backgroundWidget:setText(tr("COMPLETED"))
		return
	end

	shuffleButton:setEnabled(false)
	backgroundWidget:show()
	
	local temp = os.date("*t", os.time() + (cooldown / 1000))
	if temp.hour < 10 then
		temp.hour = "0" .. temp.hour
	end

	if temp.min < 10 then
		temp.min = "0" .. temp.min
	end

	backgroundWidget:setText(temp.hour .. ":" .. temp.min .. "\n" .. temp.day .. "/" .. temp.month .. "/" .. temp.year)
end

m_BattlepassFunctions.updatePremiumStatus = function()
	if m_BattlepassFunctions.hasPremium then
		m_BattlepassList.battlepassStatus:setText(m_BattlepassFunctions.messages[101])
		m_BattlepassList.battlepassStatus:setOn(true)
	else
		m_BattlepassList.battlepassStatus:setText(m_BattlepassFunctions.messages[100])
		m_BattlepassList.battlepassStatus:setOn(false)
	end
end

m_BattlepassFunctions.updateExperience = function()
	local nextLevelExperience = m_BattlepassFunctions.getExperiencePerLevel(m_BattlepassFunctions.level)
	local percentValue = 0
	if m_BattlepassFunctions.level > 0 then
		local prevLevelExperience = m_BattlepassFunctions.getExperiencePerLevel(m_BattlepassFunctions.level - 1)
		percentValue = (m_BattlepassFunctions.experience - prevLevelExperience) / (nextLevelExperience - prevLevelExperience)
	else
		percentValue = m_BattlepassFunctions.experience / nextLevelExperience
	end

	local width = math.ceil(m_BattlepassList.progressBar:getWidth() * percentValue)
	m_BattlepassList.bar:setWidth(width)
	m_BattlepassList.bar:setImageClip("0 0 " .. width .. " 32")
	m_BattlepassList.progressLabel:setText(m_BattlepassFunctions.experience .. " / " .. nextLevelExperience)
	m_BattlepassList.progressLevel:setText(m_BattlepassFunctions.level)
	
	m_BattlepassList.currentId = 1
	m_BattlepassList.event = scheduleEvent(function() m_BattlepassFunctions.slide(percentValue) end, 5)
end

m_BattlepassFunctions.updateProgressBar = function(widget, amount, amountMax)
	local questProgressBar = widget:getChildById("questProgressBar")
	local bar = questProgressBar:getChildById("bar")
	local width = math.ceil((questProgressBar:getWidth() - 4) * amount / amountMax)
	bar:setWidth(width)
	bar:setImageClip("0 0 " .. width .. " 26")
	questProgressBar:getChildById("label"):setText(amount .. " / " .. amountMax)
end

m_BattlepassFunctions.getQuestWidget = function(id)
  if not m_BattlepassList.questsPanel then
    return false
  end
  local widget = m_BattlepassList.questsPanel:getChildById(id)
  if not widget then
    g_logger.error("Battlepass:updateQuest - the widget with id " .. id .. " cannot be found")
    return false
  end
  return widget
end


m_BattlepassFunctions.updateQuest = function(id, amount)
	local widget = m_BattlepassFunctions.getQuestWidget(id)
	if not widget then
		return false
	end

	m_BattlepassFunctions.updateProgressBar(widget, amount, widget.amount)
	return amount >= widget.amount and widget or false
end

m_BattlepassFunctions.updateDescription = function(widget, questId, amount, value, experience)
	local questName = widget:getChildById("questName")
	local questDescription = widget:getChildById("questDescription")
	local questPoints = widget:getChildById("questPoints")
	questPoints:setText(experience)

	if questId == m_BattlepassFunctions.BATTLEPASS_QUEST_KILL_MONSTER then
		questName:setText("Monster Hunter: " .. value)
		questDescription:setText("Kill " .. value .. " " .. amount .. " times in total")
	elseif questId == m_BattlepassFunctions.BATTLEPASS_QUEST_KILL_MONSTERS then
		questName:setText("Species Killer: " .. value:upper())
		questDescription:setText("Kill " .. amount .. " " .. value .. " of any kind")
	elseif questId == m_BattlepassFunctions.BATTLEPASS_QUEST_KILL_BOSS then
		questName:setText("Boss Slayer: " .. value)
		if value == "" then
			if amount > 1 then
				questDescription:setText("Kill " .. amount .. " bosses of any kind")
			else
				questDescription:setText("Kill a boss of any kind")
			end
		else
			if amount > 1 then
				questDescription:setText("Kill " .. amount .. " bosses called " .. value)
			else
				questDescription:setText("Kill a boss called " .. value)
			end
		end
	elseif questId == m_BattlepassFunctions.BATTLEPASS_QUEST_GET_LEVEL then
		questName:setText("Experience Gatherer")
		questDescription:setText("Advance in your experience level " .. amount .. " times")
	-- elseif questId == m_BattlepassFunctions.BATTLEPASS_QUEST_GET_ITEM then
	-- 	questName:setText("Item\"s Collector: " .. value:upper())
	-- 	questDescription:setText("Get items with " .. value .. " quality level " .. amount .. " times in total")
	end
end

m_BattlepassFunctions.addQuest = function(id, questType, questId, amount, amountMax, experience, cooldown, value, shuffled)
	local widget = g_ui.createWidget("BattlePassQuestEntry", m_BattlepassList.questsPanel)
	if questType == m_BattlepassFunctions.QUEST_SPECIAL or shuffled then
		widget:getChildById("shuffle"):hide()
	end

	widget.id = id
	widget.amount = amountMax
	widget.questType = questType
	widget.value = value
	widget:setId(id)
	m_BattlepassFunctions.updateProgressBar(widget, amount, amountMax)
	m_BattlepassFunctions.updateCooldown(id, widget, amount, amountMax, cooldown)
	m_BattlepassFunctions.updateDescription(widget, questId, amountMax, value, experience)
end

m_BattlepassFunctions.resetQuest = function(oldId, questId, id, amount, experience, value)
	local widget = m_BattlepassFunctions.getQuestWidget(oldId)
	if not widget then
		return false
	end
	
	widget.id = id
	widget.amount = amount
	widget.value = value
	widget:setId(id)
	widget:getChildById("shuffle"):hide()
	m_BattlepassFunctions.updateProgressBar(widget, 0, amount)
	m_BattlepassFunctions.updateCooldown(id, widget, 0, amount, 0)
	m_BattlepassFunctions.updateDescription(widget, questId, amount, value, experience)
end

m_BattlepassFunctions.parseValue = function(msg)
	if msg:getU8() == 1 then
		-- quest has a value such as monster"s name or class id
		if msg:getU8() == 1 then
			-- the value is a string
			return msg:getString()
		else
			-- otherwise it is integer
			return msg:getU16()
		end
	end

	return nil
end

m_BattlepassFunctions.parseBattlepassItems = function(protocol, msg)
	local id = msg:getU8()
	if id == 0 then
		-- load all battlepass quests, happens when player opens the battlepass window
		m_BattlepassFunctions.experience = msg:getU32()
		m_BattlepassFunctions.level = msg:getU16()
		m_BattlepassFunctions.hasPremium = msg:getU8() ~= 0
		m_BattlepassFunctions.updateExperience()
		m_BattlepassFunctions.updatePremiumStatus()
		
		local questsTypeSize = msg:getU8()
		for i = 1, questsTypeSize do
			-- add separator ("Daily", "Weekly" and "Special")
			local questType = msg:getU8()
			m_BattlepassFunctions.addSeparator(questType)

			local questsIdSize = msg:getU8()
			for j = 1, questsIdSize do
				local questId = msg:getU8()
				local shuffled = msg:getU8() == 1
				local id = msg:getU16()
				local amount = msg:getU32()
				local amountMax = msg:getU32()
				local experience = msg:getU32()
				local cooldown = msg:getU32()
				local value = m_BattlepassFunctions.parseValue(msg)
				m_BattlepassFunctions.addQuest(id, questType, questId, amount, amountMax, experience, cooldown, value, shuffled)
			end
		end

		local updateBattlepassLevels = msg:getU8()
		if updateBattlepassLevels == 1 then
			local battlepassLevels = msg:getU16()
			for i = 1, battlepassLevels do
				local battlepassLevel = msg:getU16()
				
				local freeReward = {}
				local freeRewardAmount = msg:getU8()
				for j = 1, freeRewardAmount do
					local rewardType = msg:getU8()
					local rewardId = msg:getU16()
					local amount = msg:getU16()
					if rewardType == m_BattlepassFunctions.BATTLEPASS_REWARD_ITEM then
						table.insert(freeReward, {itemId = rewardId, amount = amount})
					elseif rewardType == m_BattlepassFunctions.BATTLEPASS_REWARD_OUTFIT then
						table.insert(freeReward, {outfitId = rewardId, amount = amount})
					elseif rewardType == m_BattlepassFunctions.BATTLEPASS_REWARD_MOUNT then
						table.insert(freeReward, {mountId = rewardId})
					elseif rewardType == m_BattlepassFunctions.BATTLEPASS_REWARD_WINGS then
						table.insert(freeReward, {wingsId = rewardId})
					elseif rewardType == m_BattlepassFunctions.BATTLEPASS_REWARD_PREMIUM then
						table.insert(freeReward, {premium = rewardId})
					end
				end

				local premiumReward = {}
				local premiumRewardAmount = msg:getU8()
				for j = 1, premiumRewardAmount do
					local rewardType = msg:getU8()
					local rewardId = msg:getU16()
					local amount = msg:getU16()
					if rewardType == m_BattlepassFunctions.BATTLEPASS_REWARD_ITEM then
						table.insert(premiumReward, {itemId = rewardId, amount = amount})
					elseif rewardType == m_BattlepassFunctions.BATTLEPASS_REWARD_OUTFIT then
						table.insert(premiumReward, {outfitId = rewardId, amount = amount})
					elseif rewardType == m_BattlepassFunctions.BATTLEPASS_REWARD_MOUNT then
						table.insert(premiumReward, {mountId = rewardId})
					elseif rewardType == m_BattlepassFunctions.BATTLEPASS_REWARD_WINGS then
						table.insert(premiumReward, {wingsId = rewardId})
					elseif rewardType == m_BattlepassFunctions.BATTLEPASS_REWARD_PREMIUM then
						table.insert(premiumReward, {premium = rewardId})
					end
				end

				m_BattlepassFunctions.battlepassrewards[battlepassLevel] = {
					freeReward = freeReward,
					premiumReward = premiumReward
				}
			end
		end
		
		if m_BattlepassList.window then
			for i = 1, #m_BattlepassFunctions.battlepassrewards do
				local v = m_BattlepassFunctions.battlepassrewards[i]
				local widget = g_ui.createWidget("BattlePassRewardContainer", m_BattlepassList.rewardsWindow)
				widget:getChildById("id"):setText(i)
				widget:setId(i)

				m_BattlepassFunctions.addRewards(widget:getChildById("freeReward"), v.freeReward)
				m_BattlepassFunctions.addRewards(widget:getChildById("premiumReward"), v.premiumReward)
				if not m_BattlepassFunctions.hasPremium then
					widget:getChildById("premiumReward"):getChildById("premiumBackground"):show()
				end
			end
		end
	elseif id == 1 then
		-- update quests progress
		local questsSize = msg:getU8()
		for i = 1, questsSize do
			local questId = msg:getU8()
			local questType = msg:getU8()
			local id = msg:getU16()
			local amount = msg:getU32()
			local value = m_BattlepassFunctions.parseValue(msg)
			local widget = m_BattlepassFunctions.updateQuest(id, amount)
			if widget then
				m_BattlepassFunctions.updateCooldown(id, widget, amount, widget.amount, msg:getU32())
			end
		end
	elseif id == 2 then
		-- update experience, level and completed quest
		local id = msg:getU16()
		m_BattlepassFunctions.experience = msg:getU32()
		m_BattlepassFunctions.level = msg:getU16()

		m_BattlepassFunctions.updateExperience()
		m_BattlepassFunctions.updateCooldown(id, nil, 0, 0, msg:getU32())
	elseif id == 3 then
		-- update single quest after shuffle
		local oldId = msg:getU16()
		local questId = msg:getU8()
		local id = msg:getU16()
		local amount = msg:getU32()
		local experience = msg:getU32()
		local value = m_BattlepassFunctions.parseValue(msg)
		
		m_BattlepassFunctions.resetQuest(oldId, questId, id, amount, experience, value)
	elseif id == 4 then
		-- update premium battlepass
		if m_BattlepassList.hover then
			m_BattlepassList.hover:destroy()
		end

		local messageId = msg:getU8()
		m_BattlepassFunctions.hasPremium = msg:getU8() == 1
		m_BattlepassFunctions.updatePremiumStatus()
		m_BattlepassList.hover = g_ui.displayUI("info_notification")
		m_BattlepassList.hover:getChildById("description"):setText(m_BattlepassFunctions.messages[messageId])
		
		if messageId == 2 then
			for _, widget in pairs(m_BattlepassList.rewardsWindow:getChildren()) do
				widget:getChildById("premiumReward"):getChildById("premiumBackground"):hide()
				if widget.sent then
					widget:getChildById("premiumReward"):getChildById("background"):show()
				end
			end
		end
	end
end

m_BattlepassFunctions.stopEvent = function()
	if m_BattlepassList.event then
		m_BattlepassList.event:cancel()
		m_BattlepassList.event = nil
	end
end

m_BattlepassFunctions.destroyHover = function()
	if m_BattlepassList.hover then
		m_BattlepassList.hover:destroy()
		m_BattlepassList.hover = nil

		if m_BattlepassList.window then
			m_BattlepassList.window:setEnabled(true)
		end
	end
end

m_BattlepassFunctions.destroy = function()
	m_BattlepassFunctions.destroyHover()
	m_BattlepassFunctions.stopEvent()
	if m_BattlepassList.window then
		m_BattlepassList.window:destroy()
	end

	m_BattlepassList = {}

	if m_BattlepassFunctions.button then
		m_BattlepassFunctions.button:setOn(false)
	end
end

m_BattlepassFunctions.slide = function(percentValue)
	if not m_BattlepassList.window then
		return false
	end
	
	local widget = m_BattlepassList.rewardsWindow:getChildById(m_BattlepassList.currentId)
	local progressBar = widget:getChildById("progressBar")
	local bar = progressBar:getChildById("bar")
	local progressBarWidth = progressBar:getWidth()
	local barWidth = bar:getWidth()
	bar:setWidth(math.min(progressBarWidth, barWidth + 4))

	if barWidth == 1 then
		bar:show()
	end
	
	local incremented = barWidth == progressBarWidth
	if incremented then
		m_BattlepassList.currentId = m_BattlepassList.currentId + 1
	end

	if m_BattlepassList.currentId <= m_BattlepassFunctions.level then
		m_BattlepassList.event = scheduleEvent(function() m_BattlepassFunctions.slide(percentValue) end, 5)
		widget.sent = true
		widget:getChildById("freeReward"):getChildById("background"):show()
		if m_BattlepassFunctions.hasPremium then
			widget:getChildById("premiumReward"):getChildById("background"):show()
		end
	elseif incremented or (barWidth + 4) < (progressBarWidth * percentValue) then
		m_BattlepassList.event = scheduleEvent(function() m_BattlepassFunctions.slide(percentValue) end, 5)
	end
end

m_BattlepassFunctions.addRewards = function(widget, rewards)
	local itemsPanel = widget:getChildById("rewards")
	local outfitPanel = widget:getChildById("outfit")
	local premiumPanel = widget:getChildById("premium")

	local rewardType, rewardId, rewardAmount
	for i = 1, #rewards do
		local v = rewards[i]
		if v.itemId then
			local item = g_ui.createWidget("BattlePassItem", itemsPanel)
			item:setItemId(v.itemId)
			item:setItemCount(v.amount)
			rewardType = m_BattlepassFunctions.BATTLEPASS_REWARD_ITEM
		elseif v.outfitId then
			rewardId = v.outfitId
			rewardAmount = v.amount
			rewardType = m_BattlepassFunctions.BATTLEPASS_REWARD_OUTFIT
		elseif v.mountId then
			rewardId = v.mountId
			rewardType = m_BattlepassFunctions.BATTLEPASS_REWARD_MOUNT
		elseif v.wingsId then
			rewardId = v.wingsId
			rewardType = m_BattlepassFunctions.BATTLEPASS_REWARD_WINGS
		elseif v.premium then
			rewardId = v.premium
			rewardType = m_BattlepassFunctions.BATTLEPASS_REWARD_PREMIUM
		end
	end

	if rewardType == m_BattlepassFunctions.BATTLEPASS_REWARD_ITEM then
		outfitPanel:hide()
		premiumPanel:hide()
		if #rewards > 2 then
			itemsPanel:setSize({width = 70, height = 70})
		elseif #rewards == 2 then
			itemsPanel:setSize({width = 36, height = 70})
		else
			itemsPanel:setSize({width = 36, height = 36})
		end
	elseif rewardType == m_BattlepassFunctions.BATTLEPASS_REWARD_OUTFIT or rewardType == m_BattlepassFunctions.BATTLEPASS_REWARD_MOUNT or rewardType == m_BattlepassFunctions.BATTLEPASS_REWARD_WINGS then
		itemsPanel:hide()
		premiumPanel:hide()

		local tmpCreature = outfitPanel:getCreature()
		if not tmpCreature then
			tmpCreature = Creature.create()
		end
		
		tmpCreature:setOutfit({type = rewardId, addons = rewardAmount or 0})
		outfitPanel:setCreature(tmpCreature)
	elseif rewardType == m_BattlepassFunctions.BATTLEPASS_REWARD_PREMIUM then
		itemsPanel:hide()
		outfitPanel:hide()
		premiumPanel:setTooltip(tr("%d days of the Lord Status", rewardId))
	else
		itemsPanel:hide()
		outfitPanel:hide()
		premiumPanel:hide()
	end
end

m_BattlepassFunctions.buyPremium = function()
	m_BattlepassFunctions.destroyHover()

	m_BattlepassList.window:setEnabled(false)
	m_BattlepassList.hover = g_ui.displayUI("premium_notification")
	m_BattlepassList.hover:getChildById("description"):setText(m_BattlepassFunctions.messages[50])
	m_BattlepassList.hover.data = { id = 0 }
end

m_BattlepassFunctions.open = function()
	if m_BattlepassList.window then
		m_BattlepassFunctions.destroy()
		m_BattlepassFunctions.send(1)
	else
		m_BattlepassFunctions.stopEvent()
		m_BattlepassList.window = g_ui.displayUI("game_battlepass")

		m_BattlepassList.infoPanel = m_BattlepassList.window:getChildById("infoPanel")
		m_BattlepassList.rewardsWindow = m_BattlepassList.infoPanel:getChildById("rewards")

		m_BattlepassList.questsPanel = m_BattlepassList.window:getChildById("questsPanel")
		m_BattlepassList.battlepassStatus = m_BattlepassList.window:getChildById("battlepassStatus")

		m_BattlepassList.levelPanel = m_BattlepassList.window:getChildById("levelPanel")
		m_BattlepassList.progressLevel = m_BattlepassList.levelPanel:getChildById("level")
		m_BattlepassList.progressBar = m_BattlepassList.levelPanel:getChildById("progressBar")
		m_BattlepassList.bar = m_BattlepassList.progressBar:getChildById("bar")
		m_BattlepassList.progressLabel = m_BattlepassList.progressBar:getChildById("label")

		m_BattlepassFunctions.send(0)
		if m_BattlepassFunctions.button then
			m_BattlepassFunctions.button:setOn(true)
		end
	end
end
