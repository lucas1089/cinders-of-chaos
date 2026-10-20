-- game_itemrarity: single source of truth for item rarity visuals.
--
-- Every rarity is one row in the RARITY table below (name, label color, and an
-- optional "metal" shader style). Everything else derives from it, so adding a
-- rarity = adding one row.
--
-- How the client knows an item's rarity:
--   1. the item's custom attributes (ChaosItemAttr below). A server with engine
--      patch 0003 (server/src-patches) announces feature GameItemCustomAttributes
--      (126) at login and sends, after every item, u16 count + {u16 key, u64 value}
--      entries; the engine stores them on the item (item:getCustomAttribute(key)).
--   2. fallback for servers without it: an uppercase "[NAME]" tag in the item
--      description (item:getTooltip()), e.g. "[MYTHIC] Sword".
-- Inventory and container slots get a frame in the rarity colour (uniques in the
-- unique colour) from the attribute (onItemChange of every UIItem).

-- Keys of the item custom attributes. Same numbers as ChaosItemAttrKey in the
-- engine (server/src-patches/0003-item-custom-attributes.patch, key 8: 0019) and Chaos.itemAttr
-- in server/data/scripts/chaos/chaos_constants.lua (server/tests/item_tooltip_test.lua
-- checks all three).
ChaosItemAttr = {
	RARITY = 1, -- 1 Common, 2 Uncommon, 3 Magic, 4 Rare, 5 Legendary, 10 Divine (an old item: 1..15, see RARITY below)
	LEVEL = 2, -- item level
	LOCKED = 3, -- 1 = locked
	UNIQUE = 4, -- 1 = unique item
	SOCKETS = 5, -- socket count
	ID = 6, -- per-item id (tooltip cache key)
	VERSION = 7, -- changes whenever the item changes (tooltip cache key)
	APPEARANCE = 8, -- transmog: client id of the look drawn instead of the item's own (server patch 0019, client 0030)
}

local FEATURE_ITEM_ATTRIBUTES = 126 -- GameItemCustomAttributes (gamelib const.lua)

-- ===========================================================================
-- Rarity data
-- ===========================================================================

local NONE_COLOR = "#ffffff"

-- Rarity-shader visibility is split into three independent Graphics options so
-- players can trim FPS per surface. Each gates a different place the shader draws;
-- items with the shader suppressed still show their colored rarity square/frame.
--   container : items inside bags/backpacks/depot (gated in uiitem.lua onItemChange)
--   inventory : equipped inventory slots          (gated in uiitem.lua onItemChange)
--   world     : loose/ground items on the map     (drives the C++ g_game flag below)
local containerShadersEnabled = true
local inventoryShadersEnabled = true
local worldShadersEnabled     = true

-- sprite = simple per-rarity item shader (outline glow) applied to the item's
-- sprite everywhere (UI + world). Lower tiers use this; higher tiers use `metal`.
--
-- metal = MU-Online-style look using the shared item_divine / ui_divine_* shaders,
-- tinted per rarity via the widget color:
--   itemShader  : GPU shader applied to the sprite
--   spriteWhite : keep the sprite white (extended/padded shader bakes the tint in)
--   strength    : 0..1, how strongly the effect overrides the item's own colors
--                 (baked into the tint's alpha channel = u_Color.a; frame opacity)
--   tint        : hex multiplied into sprite / smoke / frame
--   textBase/Hi : base and highlight colors of the rarity-name font shimmer
--   label       : color of the rarity-name label
-- the seven rarities of the server (server/data/lib/chaos_rarity.lua): Common, Uncommon, Magic, Rare, Legendary, Divine
-- and Unique (the unique flag, UNIQUE_COLOR). An item carries one of the ids 1, 2, 3, 4, 5, 10; an item saved before the
-- seven rarities may carry 6 .. 9 (they became Legendary) or 11 .. 15 (Divine), so those ids are rows too: the same row as
-- the rarity they became. RARITY_IDS lists the ids of today, in order, for the lists the player picks from. Colours as the
-- loot filter's.
local COMMON = { name = "Common", color = "#c8c8c8" }
local UNCOMMON = { name = "Uncommon", color = "#5ccf5c" }
local MAGIC = { name = "Magic", color = "#4a90ff" }
local RARE = { name = "Rare", color = "#a35cf0" }
local LEGENDARY = { name = "Legendary", color = "#ffd040" }
local DIVINE = { name = "Divine", color = "#c8e8ff",
	metal = { -- cyan, big outline glow
		itemShader = "item_metal_cyan", spriteWhite = true, strength = 0.5,
		tint = "#22e5ff", textBase = "#79e6ff", textHi = "#e8ffff", label = "#8ff2ff",
	},
}
local RARITY = {
	[1] = COMMON, [2] = UNCOMMON, [3] = MAGIC, [4] = RARE,
	[5] = LEGENDARY, [6] = LEGENDARY, [7] = LEGENDARY, [8] = LEGENDARY, [9] = LEGENDARY,
	[10] = DIVINE, [11] = DIVINE, [12] = DIVINE, [13] = DIVINE, [14] = DIVINE, [15] = DIVINE,
}
local RARITY_IDS = { 1, 2, 3, 4, 5, 10 }
local UNIQUE_COLOR = "#e07b24"
local FRAME_IMAGES = { "/modules/game_lootfilter/images/lf_frame", "/modules/game_itemrarity/images/frame" }

-- Uppercase "[NAME]" tag -> id, derived from RARITY (for parsing descriptions).
-- Older servers tagged six rarities with other names; they map to the nearest.
local TAG_TO_ID = { STRANGE = 1, EPIC = 4, EXOTIC = 5, MYTHIC = 5, CHAOS = 5, ETERNAL = 5, PHANTASMAL = 10, CELESTIAL = 10,
	COSMIC = 10, ABYSSAL = 10, TRANSCENDENT = 10 }
for _, id in ipairs(RARITY_IDS) do
	TAG_TO_ID[RARITY[id].name:upper()] = id
end

-- ===========================================================================
-- Detection
-- ===========================================================================

-- Value of an item custom attribute (0 when missing or when the server does not
-- send them).
function getItemAttribute(item, key)
	if not item or not item.getCustomAttribute then
		return 0
	end
	local ok, v = pcall(item.getCustomAttribute, item, key)
	return ok and tonumber(v) or 0
end

-- true when this connection carries item custom attributes
function hasItemAttributes()
	return g_game ~= nil and g_game.getFeature ~= nil and g_game.getFeature(FEATURE_ITEM_ATTRIBUTES) == true
end

-- the id of today's rarity an id stands for: 6 .. 9 -> 5 (Legendary), 11 .. 15 -> 10 (Divine); 0 for anything unknown
function getRarityCanonId(rarityId)
	local r = RARITY[rarityId]
	if not r then
		return 0
	end
	for _, id in ipairs(RARITY_IDS) do
		if RARITY[id] == r then
			return id
		end
	end
	return 0
end

-- the ids of the six rarities an item can carry, in order (Unique is the unique flag): for lists the player picks from
function getRarityIds()
	local out = {}
	for i, id in ipairs(RARITY_IDS) do
		out[i] = id
	end
	return out
end

-- Rarity id of an item (0 = none): the custom attribute, else the "[NAME]" tag
-- the server prepends to the item description (any other bracketed uppercase
-- tag is ignored).
function getItemRarityId(item)
	if not item then
		return 0
	end
	local r = getItemAttribute(item, ChaosItemAttr.RARITY)
	if r > 0 then
		return getRarityCanonId(r)
	end
	if hasItemAttributes() then
		return 0 -- the server sends attributes: no attribute = no rarity
	end
	local ok, text = pcall(function() return item:getTooltip() end)
	if not ok or type(text) ~= "string" then
		return 0
	end
	for tag in text:gmatch("%[(%u+)%]") do
		local id = TAG_TO_ID[tag]
		if id then
			return id
		end
	end
	return 0
end

function isUniqueItem(item)
	return getItemAttribute(item, ChaosItemAttr.UNIQUE) > 0
end

-- the name in the player's language (client_chaos_locale: Comum, Incomum, Mágica, Rara, Lendária, Divina)
local function localName(name)
	local t = rawget(_G, "tr")
	return t and t(name) or name
end

function getRarityName(rarityId)
	local r = RARITY[rarityId]
	return r and localName(r.name) or nil
end

function getRarityColor(rarityId)
	local r = RARITY[rarityId]
	return r and r.color or nil
end

function getUniqueColor()
	return UNIQUE_COLOR
end

-- ===========================================================================
-- Per-rarity lookups (by id or by item)
-- ===========================================================================

function getRarityImageById(rarityId)
	local r = RARITY[rarityId]
	return r and r.image or ''
end

-- Rarity frame image for an item, or for an explicit id.
function getImageRarity(item, rarityId)
	if rarityId then
		return getRarityImageById(rarityId)
	end
	if not item then
		return ""
	end
	return getRarityImageById(getItemRarityId(item))
end

-- Rarity label color for an item or an explicit id. Returns "0" when there is no
-- rarity (so callers can skip), and NONE_COLOR only for an explicit id of 0.
function getDescriptionRarityColor(item, rarityId)
	if not item and not rarityId then
		return "0"
	end
	local fromItem = (rarityId == nil)
	if fromItem then
		rarityId = getItemRarityId(item)
	end
	local r = RARITY[rarityId]
	if r then
		return r.color
	end
	if not fromItem and rarityId == 0 then
		return NONE_COLOR
	end
	return "0"
end

-- ===========================================================================
-- "Metal" rarity style (Divine, ...): the shared shader family, tinted per rarity
-- ===========================================================================

-- The metal style table for a rarity, or nil if it isn't a metal rarity.
function getRarityStyle(rarityId)
	local r = RARITY[rarityId]
	return r and r.metal
end

-- Tint with the effect strength baked into the alpha ("#rrggbbaa"); the sprite
-- shader reads it as effect strength and the frame image uses it as opacity.
-- nil if the rarity has no metal style.
function getMetalTint(rarityId)
	local m = getRarityStyle(rarityId)
	if not m then
		return nil
	end
	local a = math.floor((m.strength or 1.0) * 255 + 0.5)
	return m.tint .. string.format("%02x", a)
end

-- ===========================================================================
-- Sprite shaders driven by rarity
-- ===========================================================================

-- Sprite shader for a rarity: the outline shader (1-4) or the metal shader (5-6).
-- Used by the tooltip preview sprite; the server drives the same shader on the
-- in-world/inventory item via RARITY_ITEM_SHADER (special_item_attributes.lua).
function getRaritySpriteShader(rarityId)
	local r = RARITY[rarityId]
	if not r then return "" end
	if r.metal then return r.metal.itemShader end
	return r.sprite or ""
end

-- Graphics option accessors, one per surface. setRarityWorldShadersEnabled also
-- flips the C++ world flag (g_game) so ground/loose items stop drawing the rarity
-- shader instantly; container/inventory widgets refresh via the callers
-- (inventory/containers reload).
function getRarityContainerShadersEnabled()
	return containerShadersEnabled
end

function getRarityInventoryShadersEnabled()
	return inventoryShadersEnabled
end

function getRarityWorldShadersEnabled()
	return worldShadersEnabled
end

function setRarityContainerShadersEnabled(enabled)
	containerShadersEnabled = enabled and true or false
end

function setRarityInventoryShadersEnabled(enabled)
	inventoryShadersEnabled = enabled and true or false
end

function setRarityWorldShadersEnabled(enabled)
	worldShadersEnabled = enabled and true or false
	if g_game.setRarityShaderEnabled then
		g_game.setRarityShaderEnabled(worldShadersEnabled)
	end
end

-- Back-compat shim for the old single toggle (container + world together); the
-- inventory surface is new. Kept so any external caller keeps working.
function getRarityShadersEnabled()
	return containerShadersEnabled
end

function setRarityShadersEnabled(enabled)
	setRarityContainerShadersEnabled(enabled)
	setRarityWorldShadersEnabled(enabled)
end

-- Legacy no-op kept for external callers (item rarity sprite shaders are handled
-- via getRarityStyle / getRaritySpriteShader now).
function getItemRarityShader(item, rarityId)
	return ""
end

-- Optional rarity frame/border applied directly to an item widget, driven by the
-- client 'rarityType' option (0 = off, 2 = frame, 3 = corner).
function setRarity(itemWidget, color)
	local optionalType = modules.client_options.getOption('rarityType')
	if (optionalType > 1) and (color ~= "0") then
		if optionalType == 2 then
			itemWidget:setImageSource("/images/ui/frame")
		elseif optionalType == 3 then
			itemWidget:setImageSource("/images/ui/corner")
		end
		itemWidget:setImageColor(color)
	else
		itemWidget:setImageSource("/images/ui/no-border")
		itemWidget:setImageColor("#ffffff")
	end
end

-- ===========================================================================
-- Prismatic item animation (real item widgets in inventory/containers)
-- ---------------------------------------------------------------------------
-- Rarities in PRISMATIC_RARITIES get an always-on flowing rainbow on the sprite
-- (setColor) and its rarity frame (colorFrame image), everywhere the item is
-- drawn. Empty right now (the Strange test was reverted; Divine uses the metal
-- look). uiitem.lua calls the register/unregister API; add an id here to enable.
-- ===========================================================================

local PRISMATIC_RARITIES = {}
local PRISMATIC_TICK = 40         -- ms per frame (~25fps)
local PRISMATIC_SCROLL_SPEED = 7  -- hue degrees per tick
local PRISMATIC_SPRITE_S, PRISMATIC_SPRITE_V = 0.55, 1.00 -- item tint (soft)
local PRISMATIC_FRAME_S, PRISMATIC_FRAME_V   = 0.90, 1.00 -- frame tint (vivid)

local prismaticWidgets = {} -- set: [UIItem widget] = true
local prismaticPhase = 0
local prismaticEvent = nil

function isPrismaticRarity(rarityId)
	return rarityId ~= nil and PRISMATIC_RARITIES[rarityId] == true
end

-- HSV (h in degrees, s/v in 0..1) -> "#rrggbb"
local function hsvToHex(h, s, v)
	h = h % 360
	if h < 0 then h = h + 360 end
	local c = v * s
	local x = c * (1 - math.abs((h / 60) % 2 - 1))
	local m = v - c
	local r, g, b = 0, 0, 0
	if h < 60 then r, g, b = c, x, 0
	elseif h < 120 then r, g, b = x, c, 0
	elseif h < 180 then r, g, b = 0, c, x
	elseif h < 240 then r, g, b = 0, x, c
	elseif h < 300 then r, g, b = x, 0, c
	else r, g, b = c, 0, x end
	return string.format("#%02x%02x%02x",
		math.floor((r + m) * 255 + 0.5),
		math.floor((g + m) * 255 + 0.5),
		math.floor((b + m) * 255 + 0.5))
end

local function prismaticTick()
	prismaticPhase = (prismaticPhase + PRISMATIC_SCROLL_SPEED) % 360
	local spriteColor = hsvToHex(prismaticPhase, PRISMATIC_SPRITE_S, PRISMATIC_SPRITE_V)
	local frameColor  = hsvToHex(prismaticPhase, PRISMATIC_FRAME_S, PRISMATIC_FRAME_V)
	local any = false
	for w in pairs(prismaticWidgets) do
		if not w or w:isDestroyed() then
			prismaticWidgets[w] = nil
		else
			any = true
			w:setColor(spriteColor)
			local cf = w.colorFrame
			if cf and not cf:isDestroyed() and cf:isVisible() then
				cf:setImageColor(frameColor)
			end
		end
	end
	prismaticEvent = any and scheduleEvent(prismaticTick, PRISMATIC_TICK) or nil
end

-- Start the flowing rainbow on a real item widget (idempotent).
function registerPrismaticItem(widget)
	if not widget or prismaticWidgets[widget] then
		return
	end
	prismaticWidgets[widget] = true
	if not prismaticEvent then
		prismaticTick()
	end
end

-- Stop the effect on a widget and reset its sprite/frame tint back to white.
function unregisterPrismaticItem(widget)
	if not widget or not prismaticWidgets[widget] then
		return
	end
	prismaticWidgets[widget] = nil
	if not widget:isDestroyed() then
		widget:setColor("#ffffff")
		local cf = widget.colorFrame
		if cf and not cf:isDestroyed() then
			cf:setImageColor("#ffffff")
		end
	end
end

-- ===========================================================================
-- Diagnostics
-- ===========================================================================

-- Console (Ctrl+T) helper: lists ground items and their per-item shader. Ground
-- items carry no client rarity, so the world rainbow is server-driven (the
-- server sends "item_prismatic" as the item shader; the map renderer animates it).
function debugGroundRarity()
	if not g_game.isOnline() then
		g_logger.info("[rarity] not online")
		return
	end
	local total, withShader = 0, 0
	for _, tile in ipairs(g_map.getTiles(-1) or {}) do
		for _, item in ipairs(tile:getItems() or {}) do
			total = total + 1
			local sh = item:getShader() or ""
			if sh ~= "" then
				withShader = withShader + 1
				g_logger.info(string.format("[rarity] id=%d shader='%s'", item:getId(), sh))
			end
		end
	end
	g_logger.info(string.format("[rarity] scanned %d ground items, %d with a shader", total, withShader))
end

-- ===========================================================================
-- Soft rarity outline (client base patch 0044: Item.setRarityOutline*)
-- ---------------------------------------------------------------------------
-- The engine draws a soft glow in the rarity colour around dropped items on the
-- map and around items in inventory and container slots; this module hands it
-- the colours (the RARITY table above, uniques in UNIQUE_COLOR) and the two
-- Graphics options (rarityOutlineMap, rarityOutlineSlots). Common items get no
-- outline (minRarity); Legendary and up breathe (pulseFrom). A client without the
-- patch has no Item.setRarityOutlineColor: nothing happens.
-- ===========================================================================

local OUTLINE = { width = 3, minRarity = 2, pulseFrom = 5, pulseMs = 2200, alpha = 225, uniqueSlot = 16 }
local outlineMap, outlineSlots = true, true

-- "#rrggbb" -> r, g, b (nil for anything else)
function rarityHexToRgb(hex)
	if type(hex) ~= "string" then
		return nil
	end
	local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)$")
	if not r then
		return nil
	end
	return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

-- what the engine is told: {colors = {{slot, r, g, b, a}, ...} (rarity ids 1..15, then 16 = unique), width,
-- minRarity, pulseFrom, pulseMs}
function getRarityOutlinePlan()
	local plan = { colors = {}, width = OUTLINE.width, minRarity = OUTLINE.minRarity, pulseFrom = OUTLINE.pulseFrom,
		pulseMs = OUTLINE.pulseMs }
	for id = 1, 15 do
		local r, g, b = rarityHexToRgb(RARITY[id] and RARITY[id].color)
		if r then
			plan.colors[#plan.colors + 1] = { id, r, g, b, OUTLINE.alpha }
		end
	end
	local r, g, b = rarityHexToRgb(UNIQUE_COLOR)
	plan.colors[#plan.colors + 1] = { OUTLINE.uniqueSlot, r, g, b, OUTLINE.alpha }
	return plan
end

-- hand the plan and the two options to the engine (api = the client's Item class); false without patch 0044
function applyRarityOutline(api, onMap, inSlots)
	if type(api) ~= "table" and type(api) ~= "userdata" then
		return false
	end
	if not api.setRarityOutlineColor or not api.setRarityOutlineStyle or not api.setRarityOutlineEnabled then
		return false
	end
	local plan = getRarityOutlinePlan()
	for _, c in ipairs(plan.colors) do
		api.setRarityOutlineColor(c[1], c[2], c[3], c[4], c[5])
	end
	api.setRarityOutlineStyle(plan.width, plan.minRarity, plan.pulseFrom, plan.pulseMs)
	api.setRarityOutlineEnabled(onMap and true or false, inSlots and true or false)
	return true
end

local function engineItem()
	return rawget(_G, "Item")
end

-- Graphics options (client_settings dataset.lua, base patch 0044): which = "map" | "slots"
function onOutlineOption(which, value)
	if which == "map" then
		outlineMap = value ~= false
	elseif which == "slots" then
		outlineSlots = value ~= false
	end
	local api = engineItem()
	if api and api.setRarityOutlineEnabled then
		api.setRarityOutlineEnabled(outlineMap, outlineSlots)
	end
end

function getRarityOutlineOptions()
	return outlineMap, outlineSlots
end

local function readOutlineOptions()
	local settings = modules and modules.client_settings
	if settings and settings.getOption then
		local ok, v = pcall(settings.getOption, "rarityOutlineMap")
		if ok and v ~= nil then outlineMap = v ~= false end
		ok, v = pcall(settings.getOption, "rarityOutlineSlots")
		if ok and v ~= nil then outlineSlots = v ~= false end
	end
end

-- ===========================================================================
-- Rarity frames on item slots (from the item custom attributes)
-- ===========================================================================

local frameImage = nil
local function getFrameImage()
	if frameImage == nil then
		frameImage = FRAME_IMAGES[#FRAME_IMAGES]
		for _, path in ipairs(FRAME_IMAGES) do
			if not g_resources or not g_resources.fileExists or g_resources.fileExists(path .. ".png") then
				frameImage = path
				break
			end
		end
	end
	return frameImage
end

-- frame colour of an item: unique colour, rarity colour, or nil
function getItemFrameColor(item)
	if not item then
		return nil
	end
	if isUniqueItem(item) then
		return UNIQUE_COLOR
	end
	return getRarityColor(getItemRarityId(item))
end

-- draw (or hide) the rarity frame of an item widget. widget.irColor tells other
-- modules (the loot filter) that the slot already has a rarity frame.
function updateRarityFrame(widget)
	if not widget or widget:isDestroyed() then
		return
	end
	local item = widget:getItem()
	local color = getItemFrameColor(item)
	local frame = widget:getChildById("irFrame")
	-- the UI shaders (game_shaderfx, base patch 0044): greyscale for a locked item, the shine on legendary frames
	local fx = modules and modules.game_shaderfx
	if fx and fx.onSlotItem then
		pcall(fx.onSlotItem, widget, item)
	end
	if not color then
		if frame then
			frame:hide()
			if fx and fx.onRarityFrame then
				pcall(fx.onRarityFrame, frame, 0, false)
			end
		end
		widget.irColor = nil
		return
	end
	if not frame then
		frame = g_ui.createWidget("UIWidget", widget)
		frame:setId("irFrame")
		frame:setPhantom(true)
		frame:setFocusable(false)
		frame:fill("parent")
		frame:setImageSource(getFrameImage())
	end
	frame:setImageColor(color)
	frame:show()
	if fx and fx.onRarityFrame then
		pcall(fx.onRarityFrame, frame, getItemRarityId(item), isUniqueItem(item))
	end
	widget.irColor = color
	local lf = widget:getChildById("lfFrame") -- one frame per slot: the loot filter's goes
	if lf then
		lf:hide()
	end
end

local function onItemChange(widget)
	if hasItemAttributes() then
		updateRarityFrame(widget)
	elseif widget.irColor then
		updateRarityFrame(widget)
	end
end

local function refreshContainers()
	for _, container in pairs(g_game.getContainers() or {}) do
		local panel = container.itemsPanel
		if panel and not panel:isDestroyed() then
			for _, child in ipairs(panel:getChildren()) do
				if child.getItem then
					updateRarityFrame(child)
				end
			end
		end
	end
end

-- inventory slots: game_inventory's slot style has its own onItemChange, which hides the UIItem class hook, so
-- the slot is framed after game_inventory has put the item in (next event)
local function inventoryWidget(slot)
	local inv = modules.game_inventory
	local panel = inv and inv.getInventoryPanel and inv.getInventoryPanel()
	return panel and panel:getChildById("slot" .. slot) or nil
end

local function onInventoryChange(player, slot, item)
	addEvent(function()
		local widget = inventoryWidget(slot)
		if widget and (hasItemAttributes() or widget.irColor) then
			updateRarityFrame(widget)
		end
	end)
end

local function refreshInventory()
	for slot = 1, 10 do
		local widget = inventoryWidget(slot)
		if widget then
			updateRarityFrame(widget)
		end
	end
end

-- the feature is announced by the server at every login; a later login to a
-- server that does not announce it must not read attributes it never sends
local function onGameEnd()
	if g_game.disableFeature then
		g_game.disableFeature(FEATURE_ITEM_ATTRIBUTES)
	end
end

function init()
	readOutlineOptions()
	applyRarityOutline(engineItem(), outlineMap, outlineSlots)
	connect(UIItem, { onItemChange = onItemChange })
	connect(g_game, { onGameEnd = onGameEnd })
	connect(LocalPlayer, { onInventoryChange = onInventoryChange })
	if g_game.isOnline() then
		refreshContainers()
		refreshInventory()
	end
	return true
end

function terminate()
	disconnect(UIItem, { onItemChange = onItemChange })
	disconnect(g_game, { onGameEnd = onGameEnd })
	disconnect(LocalPlayer, { onInventoryChange = onInventoryChange })
	if prismaticEvent then
		removeEvent(prismaticEvent)
		prismaticEvent = nil
	end
	prismaticWidgets = {}
	return true
end
