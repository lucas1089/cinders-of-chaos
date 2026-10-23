-- Writes data/items/card_descriptions.csv: the item description of every card (what it gives, plus how to use it), from
-- data/scripts/chaos/cards_config.lua and cards_core.lua. tools/patch_badges.py puts these into the base items.xml.
-- Run from the server/ folder:
--   luajit tools/gen_card_descriptions.lua            writes the file
--   lua5.3 tools/gen_card_descriptions.lua --check    exits 1 when the file on disk is out of date (CI)
-- Lua 5.1 / LuaJIT and 5.3.
local OUT = "data/items/card_descriptions.csv"

dofile("data/scripts/chaos/cards_core.lua")
local K = ChaosCardsCore

local ids = {}
for id in pairs(K.config.cards) do
	ids[#ids + 1] = id
end
table.sort(ids)

local lines = {"id,description"}
for _, id in ipairs(ids) do
	local text = K.description(nil, id)
	assert(not text:find('"', 1, true), "a quote in the description of " .. id)
	lines[#lines + 1] = string.format('%d,"%s"', id, text)
end
local body = table.concat(lines, "\n") .. "\n"

if arg and arg[1] == "--check" then
	local fh = io.open(OUT, "rb")
	local disk = fh and fh:read("*a")
	if fh then
		fh:close()
	end
	if disk ~= body then
		io.stderr:write(OUT .. " is out of date: run luajit tools/gen_card_descriptions.lua\n")
		os.exit(1)
	end
	print("gen_card_descriptions: " .. OUT .. " is up to date (" .. #ids .. " cards)")
	return
end

local fh = assert(io.open(OUT, "wb"))
fh:write(body)
fh:close()
print("gen_card_descriptions: wrote " .. OUT .. " (" .. #ids .. " cards)")
