-- Profession refining recipes for the base crafting books (O395; server/README.md "Professions", "Feeding the base
-- crafting (O395)"). The base crafting script's books (data/scripts/customs/crafting/<book>.lua) end with a loader block
-- written by server/tools/install_professions.py that calls
--     ChaosProfessionRecipes.addRecipes(Crafting.<book>, "<book>")
-- The recipes come from professions_config.lua `refine` (professions_core.lua K.recipes), so a change of the config
-- needs no new install. A book that has them already is left alone (a /reload adds nothing twice).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible; ItemType is used for the product's name when the engine has it.

if not ChaosProfessionsCore or not ChaosProfessionsCore.recipes then
	dofile("data/scripts/chaos/professions_core.lua")
end

ChaosProfessionRecipes = ChaosProfessionRecipes or {}
local R = ChaosProfessionRecipes

function R.config()
	if not R.cfg then
		R.cfg = (Chaos and Chaos.professionsConfig) or dofile("data/scripts/chaos/professions_config.lua")
	end
	return R.cfg
end

local function nameOf(id)
	if not ItemType then
		return nil
	end
	local ok, name = pcall(function()
		return ItemType(id):getName()
	end)
	return ok and name or nil
end

function R.recipes(book)
	local cfg = R.config()
	local K = ChaosProfessionsCore
	return K.recipes(cfg, K.index(cfg), book, nameOf)
end

-- appends the book's refining recipes to its list; returns how many were added (0 when they are there already)
function R.addRecipes(list, book)
	if type(list) ~= "table" then
		return 0
	end
	for _, craft in ipairs(list) do
		if type(craft) == "table" and craft.chaosProfession then
			return 0
		end
	end
	local n = 0
	for _, craft in ipairs(R.recipes(book)) do
		list[#list + 1] = craft
		n = n + 1
	end
	return n
end

-- the books that get recipes (install_professions.py writes a loader into each)
function R.books()
	local out, seen = {}, {}
	for _, r in ipairs(R.config().refine or {}) do
		if not seen[r.book] then
			seen[r.book] = true
			out[#out + 1] = r.book
		end
	end
	return out
end

return R
