-- City portals: what makes them recognisable (server/README.md "City portals"). Every portal placed through
-- cityportals.lua shows its kind's effect every `pulseMs`, and looking at it adds its name and what it does, in the
-- player's language (Chaos.t; pt-BR in i18n_strings.lua). The portals themselves: hideout.lua, guild_hall.lua,
-- npc_booths.lua.
if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosCityPortals then
	dofile("data/scripts/chaos/cityportals.lua")
end
local X = ChaosCityPortals
local C = ChaosCityPortalsCore

local pulse = GlobalEvent("ChaosCityPortalsPulse")
function pulse.onThink(interval)
	local cfg = C.cfg()
	for key, p in pairs(X.placed) do
		local pos = Position(p.x, p.y, p.z)
		local tile = Tile(pos)
		local it = tile and tile:getItemById(p.item)
		if it and it:getActionId() == p.aid then
			local k = cfg.kinds[p.kind]
			local effect = k and rawget(_G, k.effect or "") or CONST_ME_TELEPORT
			pos:sendMagicEffect(effect)
		else
			X.placed[key] = nil -- gone (the next placement check puts it back)
		end
	end
	return true
end
pulse:interval(C.cfg().pulseMs)
pulse:register()

-- the look text: "You see a magic forcefield.\nHideout Portal: Step in to ..."
local look = EventCallback
look.onLook = function(self, thing, position, distance, description)
	if thing and thing.isItem and thing:isItem() then
		local kind = X.kindOf(thing:getActionId())
		if kind then
			local pos = thing.getPosition and thing:getPosition() or position
			local text = C.lookText(C.cfg(), kind, function(s) return Chaos.t(self, s) end,
				X.titleOf(thing:getActionId(), pos))
			if text then
				description = (description or "") .. "\n" .. text
			end
		end
	end
	return description
end
look:register(111)
