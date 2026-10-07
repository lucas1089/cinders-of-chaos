local tooltipWindow = nil
local itemSprite = nil
local itemSprite_2 = nil
local itemWeightLabel = nil
local labels = nil
local hoveredItem = nil

local BASE_WIDTH = 170
local BASE_HEIGHT = 0

local tooltipWidth = 0
local tooltipWidthBase = BASE_WIDTH
local tooltipHeight = BASE_HEIGHT
local longestString = 0

local cachedItems = {}

function init()
  connect(UIItem, {onHoverChange = onHoverChange})
  connect(g_game, {onGameEnd = resetData})

  tooltipWindow = g_ui.displayUI("item_tooltip")
  tooltipWindow:hide()
  tooltipWindow:setBackgroundColor("#00000088") -- Black with 53% opacity

  labels = tooltipWindow:getChildById("labels")
  itemWeightLabel = tooltipWindow:getChildById("itemWeightLabel")
  itemSprite = tooltipWindow:getChildById("itemSprite")
  itemSprite_2 = tooltipWindow:getChildById("itemSprite_2")
end

function terminate()
  disconnect(UIItem, {onHoverChange = onHoverChange})
  disconnect(g_game, {onGameEnd = resetData})

  if tooltipWindow then
    cachedItems = {}
    hoveredItem = nil

    itemWeightLabel = nil
    itemSprite = nil
    itemSprite_2 = nil
    labels = nil

    tooltipWindow:destroy()
    tooltipWindow = nil
  end
end

function resetData()
  cachedItems = {}
  hoveredItem = nil
  tooltipWindow:hide()
end

function deleteLastCharacter(str)
  return (str:gsub("[%z\1-\127\194-\244][\128-\191]*$", ""))
end

function removeArticle(name)
  -- Removes "a", "an", or "the" at the start of the string
  return name:gsub("^(a |an |the )", "")
end

local excludedKeywords = {
  "health:", "mana:", "fighting", "protection", "atk:", "range:", "arm:", 
  "physical", "energy", "earth", "fire", "ice", "holy", "death", "drown", 
  "poison", "def:", "drain"
}

-- Function to check if a part contains any excluded keywords
local function isExcluded(part)
  part = part:lower() -- Convert to lowercase for case-insensitive matching
  for _, keyword in ipairs(excludedKeywords) do
      if part:find(keyword) then
          return true -- Part contains an excluded keyword
      end
  end
  return false -- Part does not contain any excluded keywords
end
local Colors = {
  Default = "#ffffff",
  ItemLevel = "#abface",
  Description = "#8080ff",
  Implicit = "#ffbb22",
  Attribute = "#2266ff",
  Mirrored = "#22ffbb",
  physical = "#ff8800", -- Orange
    energy = "#0000ff",  -- Blue
    ice = "#00ffff",     -- Cyan
    positive = "#00ff00", -- Green
    negative = "#ff0000" -- Red
}


local protectionMap = {
  ["physical"] = "Physical Protection",              -- For simple "physical +X%"
  ["energy"] = "Energy Protection",
  ["earth"] = "Earth Protection",
  ["fire"] = "Fire Protection",
  ["ice"] = "Ice Protection",
  ["holy"] = "Holy Protection",
  ["death"] = "Death Protection",
  ["drown"] = "Drown Protection",
  ["poison"] = "Poison Protection",
  ["life drain"] = "Life Drain Protection",          -- For "life drain +X%"
  ["mana drain"] = "Mana Drain Protection",          -- For "mana drain +X%"
  ["protection physical"] = "Physical Protection",   -- For "protection physical +X%"
  ["protection energy"] = "Energy Protection",
  ["protection earth"] = "Earth Protection",
  ["protection fire"] = "Fire Protection",
  ["protection ice"] = "Ice Protection",
  ["protection holy"] = "Holy Protection",
  ["protection death"] = "Death Protection",
  ["protection drown"] = "Drown Protection",
  ["protection poison"] = "Poison Protection",
  ["protection life drain"] = "Life Drain Protection",
  ["protection mana drain"] = "Mana Drain Protection",
  ["all"] = "Protection All"
}

local function processProtections(message)
  -- Patterns to match different protection formats
  -- 1. Simple: "physical +5%" or "physical -5%"
  -- 2. Complex: "Protection Physical +5%" or "Life Drain Protection +5%"
  for protectionType, value in message:lower():gmatch("(%w+%s*%w*) ([+-]%d+)%%") do
      -- Trim any extra spaces and normalize the protection type
      protectionType = protectionType:gsub("^%s*(.-)%s*$", "%1") -- Remove leading/trailing spaces
      -- Map the protection type to its full name, default to unknown if not found
      local mappedName = protectionMap[protectionType] or ("Unknown Protection (" .. protectionType .. ")")
      -- Add the protection to the tooltip
      if not protection then
          addSeparator()
          protection = true
      end
      addEmpty(5)
      addString(mappedName .. ": " .. value .. "%", Colors.positive)
  end
end

local function processReflect(message)
  local reflectFound = false
  for chance, amount, damageType in message:lower():gmatch("reflect: (%d+)%% chance for (%d+)%% amount of ([a-z]+) damage") do
      local reflectText = "Reflect: " .. chance .. "% chance for " .. amount .. "% amount of " .. damageType .. " damage"
      addEmpty(5)
      addString(reflectText, Colors.positive)
      reflectFound = true
      if reflectFound then
        addSeparator()
      end

  end
end



function onItemChangesss(items)
  local texts = nil
  if items:getItem() and items:getItem():getTooltip():len() > 0 then
      local text = items:getItem():getTooltip()
      -- Regex patterns
      local name = regexMatch(text, [[^(.*?)(?: \((.*)\))?\..*]])
      local stats = regexMatch(text, [[\((.*)\).]])
      local level = regexMatch(text, "level ([0-9]*) or higher.")
      local capacity = regexMatch(text, "weighs (.*) oz.")
      local health = regexMatch(text, "health: ([0-9]+)/1 sec")
      local mana = regexMatch(text, "mana: ([0-9]+)/1 sec")
      
      if #name ~= 0 then
          local rawName = name[1][2] or name[1][1]
          addEmpty(5)
          addString(rawName, Colors.Default)
      end
      

      if #stats ~= 0 then
          local info = string.split(stats[1][2], ", ")
          local Separator = false
          addSeparator()
          for _, part in ipairs(info) do
            
            if part:lower():find("atk:") or part:lower():find("range:") then
              addEmpty(5)
              Separator = true
              addString(part, Colors.negative)
            end

            if part:lower():find("arm:") or part:lower():find("def:") then
              addEmpty(5)
              Separator = true
              addString(part, Colors.physical)
            end

            if part:lower():find("fighting") then
              if not skills and Separator then
                addSeparator()
              skills = true
              end
              addEmpty(5)
              addString(part, Colors.ice)
            end

            if part:lower():find("mana:") or part:lower():find("health:") then
              if not mana_health then
                addSeparator()
                mana_health = true
              end
              addEmpty(5)
              addString(part, Colors.ice)
            end
            

          processProtections(part)
          processReflect(part)
          
            if not isExcluded(part) then
              if not attrrrrrr and Separator then
                addSeparator()
                attrrrrrr = true
              end
              addEmpty(5)
              addString(part, Colors.Attribute)
          end
        end
      end

      local vocationList = text:match("can only be wielded properly by ([%a%s,]+)%.")
      if vocationList then
          addSeparator()
          addEmpty(5)
          addString("Usable by: " .. vocationList, Colors.Description)
      end

      local vocationLists = text:match("can only be wielded properly by ([%a%s,]+)% of")
      if vocationLists and vocationLists ~= "players" then
          addSeparator()
          addEmpty(5)
          addString("Usable by: " .. vocationLists, Colors.Description)
      end
      

    if #level ~= 0 then
        addSeparator()
        addEmpty(5)
          addString("Item " .. level[1][1], Colors.ItemLevel)
      end

	  local info = string.split(text, "oz.")
	if info[2] and #info[2] ~= 0 then
		info[2] = string.gsub(info[2], "^%s*", "") -- Remove leading spaces
		info[2] = string.gsub(info[2], "[()]", "") -- Remove parentheses only
		addSeparator()
		addEmpty(5)
		addString(info[2], Colors.physical)
	end

      if #capacity ~= 0 then
        addSeparator()
          addEmpty(10)
          local weightText = "Weight: " .. capacity[1][2] .. " oz"
          addString(weightText, Colors.Default)
      end

  end
  return
end


function onHoverChange(widget, hovered)
  local item = widget:getItem()
  if not item or widget:getId() == "containerItemWidget" or widget:isVirtual() then
    return
  end

  if hovered then
    hoveredItem = item
      protection = false
      skills = false
      mana_health = false
      attrrrrrr = false
      tooltipWidth = 0
      longestString = 0
      tooltipWidthBase = BASE_WIDTH
      tooltipHeight = BASE_HEIGHT
      tooltipWindow:setWidth(tooltipWidth)
      tooltipWindow:setHeight(tooltipHeight)
      labels:destroyChildren()
      itemSprite:setItemId(hoveredItem:getId())
      itemSprite:setItemCount(hoveredItem:getCount())
      itemSprite_2:setItemId(hoveredItem:getId())
      itemSprite_2:setItemCount(hoveredItem:getCount())
      onItemChangesss(widget)
      shrinkSeparators()
      showItemTooltip()
  else
    hoveredItem = nil
    tooltipWindow:hide()
  end
end

function addString(text, color, resize)
  local label = g_ui.createWidget("TooltipLabel", labels)
  label:setColor(color)

  if resize then
    tooltipWindow:setWidth(tooltipWidth)
    label:setTextWrap(true)
    label:setTextAutoResize(true)
    label:setText(text)
    tooltipHeight = tooltipHeight + label:getTextSize().height + 4
  else
    label:setText(text)
    local textSize = label:getTextSize()
    if longestString == 0 then
      longestString = textSize.width + itemWeightLabel:getWidth()
      tooltipWidth = tooltipWidthBase + longestString
      label:addAnchor(AnchorTop, "parent", AnchorTop)
    elseif textSize.width > longestString then
      longestString = textSize.width
      tooltipWidth = tooltipWidthBase + longestString
    end
    tooltipHeight = tooltipHeight + textSize.height
  end
end

function shrinkSeparators()
  local children = labels:getChildren()
  local m = math.max(60, math.floor(tooltipWidth / 4))
  for _, child in ipairs(children) do
    if child:getStyleName() == "TooltipSeparator" then
      child:setMarginLeft(m)
      child:setMarginRight(m)
    end
  end
end

function addSeparator()
  local sep = g_ui.createWidget("TooltipSeparator", labels)
  tooltipHeight = tooltipHeight + sep:getHeight() + sep:getMarginTop() + sep:getMarginBottom()
end

function addEmpty(height)
  local empty = g_ui.createWidget("TooltipEmpty", labels)
  empty:setHeight(height)
  tooltipHeight = tooltipHeight + height
end

function showItemTooltip()
  local mousePos = g_window.getMousePosition()
  tooltipHeight = math.max(tooltipHeight, 40)
  tooltipWindow:setWidth(tooltipWidth)
  tooltipWindow:setHeight(tooltipHeight)
  tooltipWindow:setBorderWidth(1)
	tooltipWindow:setBorderColor("white")
  
  local windowSize = g_window.getSize()
  if mousePos.x > windowSize.width / 2 then
    tooltipWindow:move(mousePos.x - (tooltipWidth + 2), math.min(windowSize.height - tooltipHeight, mousePos.y + 5))
  else
    tooltipWindow:move(mousePos.x + 5, mousePos.y + 10)
  end
  tooltipWindow:raise()
  tooltipWindow:show()
  g_effects.fadeIn(tooltipWindow, 500)
end