-- collection_config.lua: the collection score (collection.lua, collection_core.lua). Plain table, no engine calls
-- (server/tests/collection_test.lua reads it with plain Lua). See server/README.md "Collection score".
--
-- Every cosmetic an account owns gives collection points: outfits and addons, mounts, wings, auras, shaders, name plate
-- frames, chat colours, kill / level-up / rare-loot effects, emotes, footprints, outlines, loot label accents, spell
-- skins and titles. Nothing is listed by hand: a store item is worth its price (one point per `pricePerPoint` coins,
-- from shop_config.lua), an item no offer sells is worth the points of its rarity (`sourcePoints`, `exclusivePoints`).
-- Milestones grant purely visual rewards, once, and keep them: a title (ChaosTitles, the name plate), a name plate frame
-- (the title's frame), a footstep trail and a chat colour (cosmetics of source "collection" in cosmetics_config.lua).
-- Never power. The rewards themselves are never counted in the score.

return {
	opcode = 225, -- the cosmetics opcode (ChaosOpcodes.cosmetics): `state` carries `score`, the action `score` asks for it
	table = "chaos_collection", -- one row per account and entry (server/sql/chaos_collection.sql)
	pricePerPoint = 50, -- a sold item: ceil(price / pricePerPoint) points
	minPoints = 1,
	-- an item that is not sold: by where it comes from (cosmetics_config.lua `source`)
	sourcePoints = {achievement = 4, pvp = 6, candlemarks = 4, pact = 3, boss = 10, gm = 0, collection = 0},
	exclusivePoints = 10, -- a wardrobe item or plate frame that no offer sells (exclusives_config.lua)
	-- titles: each title the account has held counts, up to `titleMax` of them
	titlePoints = 2,
	titleMax = 10,
	-- a character that has the whole wardrobe by its group (staff) counts none of it
	staffCountsWardrobe = false,
	syncDelayMs = 2500, -- the sweep after a login or a purchase
	-- The milestones, lowest first. rewards: {kind = "title", text, frame?} (text 24 characters at most, frame a plate
	-- frame of nameplate_core.lua N.FRAMES) or {kind = "cosmetic", key} (a cosmetics_config.lua cosmetic of source
	-- "collection" whose `collection` is this milestone's points).
	milestones = {
		{key = "collector", points = 20, rewards = {{kind = "title", text = "Collector"}}},
		{key = "trail", points = 60, rewards = {{kind = "cosmetic", key = "foot_collector"}}},
		{key = "curator", points = 120, rewards = {{kind = "title", text = "Curator"}}},
		{key = "gold", points = 220, rewards = {{kind = "cosmetic", key = "chat_collector"}}},
		{key = "connoisseur", points = 400, rewards = {{kind = "title", text = "Connoisseur", frame = "gallery"}}},
		{key = "grand", points = 700, rewards = {{kind = "title", text = "Grand Collector", frame = "gallery"}}},
		{key = "sovereign", points = 1200, rewards = {{kind = "title", text = "Hoard Sovereign", frame = "gallery"}}}
	}
}
