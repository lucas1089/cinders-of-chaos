-- game_itemrarity: single source of truth for item rarity visuals.
--
-- Every rarity is one row in the RARITY table below (name, label color, frame
-- image, and an optional "metal" shader style). Everything else derives from it,
-- so adding a rarity = adding one row.
--
-- How the client knows an item's rarity: the server (item.cpp getDescription)
-- prefixes the item name with an uppercase "[NAME]" tag, e.g. "[MYTHIC] Sword".
-- item:getTooltip() returns that description, and we read the tag from it.

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
local RARITY = {
	[1] = { name = "Strange",   color = "#c4cebc", image = "/images/ui/rarity_square_strange",   sprite = "item_outline_strange" },
	[2] = { name = "Rare",      color = "#1e963e", image = "/images/ui/rarity_square_rare",      sprite = "item_outline_rare" },
	[3] = { name = "Epic",      color = "#e32121", image = "/images/ui/rarity_square_epic",      sprite = "item_outline_epic" },
	[4] = { name = "Legendary", color = "#f6fa07", image = "/images/ui/rarity_square_legendary", sprite = "item_outline_legendary" },
	[5] = { name = "Mythic",    color = "#a30ff6", image = "/images/ui/rarity_square_mythic",
		metal = { -- purple, parallel-waves glow
			itemShader = "item_metal_purple", spriteWhite = true, strength = 0.5,
			tint = "#a30ff6", textBase = "#c98bff", textHi = "#f0e0ff", label = "#d5a5ff",
		},
	},
	[6] = { name = "Divine",    color = "#22e5ff", image = "/images/ui/rarity_square_blue",
		metal = { -- cyan, big outline glow
			itemShader = "item_metal_cyan", spriteWhite = true, strength = 0.5,
			tint = "#22e5ff", textBase = "#79e6ff", textHi = "#e8ffff", label = "#8ff2ff",
		},
	},
}

-- Uppercase "[NAME]" tag -> id, derived from RARITY (for parsing descriptions).
local TAG_TO_ID = {}
for id, r in pairs(RARITY) do
	TAG_TO_ID[r.name:upper()] = id
end

-- ===========================================================================
-- Detection
-- ===========================================================================

-- Rarity id of an item (0 = none). Reads the "[NAME]" tag the server prepends
-- to the item description; ignores any other bracketed uppercase tags.
function getItemRarityId(item)
	if not item then
		return 0
	end
	for tag in item:getTooltip():gmatch("%[(%u+)%]") do
		local id = TAG_TO_ID[tag]
		if id then
			return id
		end
	end
	return 0
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

function init()
	return true
end

function terminate()
	if prismaticEvent then
		removeEvent(prismaticEvent)
		prismaticEvent = nil
	end
	prismaticWidgets = {}
	return true
end
