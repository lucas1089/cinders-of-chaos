-- Run from the server/ folder: lua5.3 tests/spellbook_player_text_test.lua (CI runs it with luajit and lua5.3).
-- The Spellbook shows players the first comment block of a Chaos spell script as its description
-- (spellbook.lua Book.analyzeScript). This test reads every spell script of data/spells/chaos/ and fails when that
-- text carries developer notes: file names, config keys, owner notes, dates, roadmap ids, cooldown history, comparisons
-- to stock spells. Put such notes on comment lines AFTER the description (the description ends at the first line that
-- ends in a full stop or "!", or after 3 comment lines). Plain player facts in parentheses are fine.
-- Files that start with "_" are helper libraries of the spell scripts, not spells: the Spellbook never reads them.

-- the engine API the Spellbook file touches when it loads
function CreatureEvent() local o = {}; function o:register() end; function o:type() end; return o end
function TalkAction() local o = {}; function o:separator() end; function o:register() end; return o end
Vocation = setmetatable({}, {__call = function() end})
ItemType = setmetatable({}, {__call = function() return {getName = function() return "item" end, getClientId = function() return 1 end} end})
json = {encode = function() return "" end}
MESSAGE_STATUS_CONSOLE_BLUE = 4

dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.send = function() end
Chaos.decode = function(b) return b end
dofile("data/scripts/chaos/spellbook.lua")
local B = ChaosSpellbook

-- markers of developer text: {label, Lua pattern, matched against the lower-cased text unless raw is true}
local MARKERS = {
	{".lua", "%.lua", false},
	{"data/", "data/", false},
	{"cfg.", "cfg%.", false},
	{"_config", "_config", false},
	{"Chaos<Name> (a module table)", "Chaos%u", true},
	{"owner", "owner", false},
	{"O<digits> (roadmap id)", "%f[%w]O%d+%f[%W]", true},
	{"a date (20xx-)", "20%d%d%-", true},
	{"README", "readme", false},
	{"stock ", "stock ", false},
	{"ladder (cooldown history)", "ladder", false},
	{"sibling (spell family notes)", "sibling", false}
}

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end

local scripts = {}
local pipe = io.popen("find data/spells/chaos -name '*.lua' | sort")
for path in pipe:lines() do
	if not path:match("/_[^/]*$") then
		scripts[#scripts + 1] = path
	end
end
pipe:close()
check(#scripts > 100, "found the Chaos spell scripts (" .. #scripts .. ")")

for _, path in ipairs(scripts) do
	local f = assert(io.open(path, "rb"))
	local src = f:read("*a")
	f:close()
	local info = B.analyzeScript(src)
	local text = info.description
	check(text and text ~= "", path .. ": the first comment block is '-- <Name>: <description>'")
	if text then
		local lower = text:lower()
		for _, m in ipairs(MARKERS) do
			local hay = m[3] and text or lower
			check(not hay:find(m[2]), path .. ": description has developer text '" .. m[1] .. "': " .. text)
		end
		check(#text <= 600, path .. ": description is " .. #text .. " bytes (keep it under 600)")
	end
end

-- the guard itself: the old Town Portal text is caught
do
	local bad = B.analyzeScript("-- Town Portal: a portal home; all rules are in data/scripts/chaos/townportal.lua.\n").description
	local hit = false
	for _, m in ipairs(MARKERS) do
		if (m[3] and bad or bad:lower()):find(m[2]) then
			hit = true
		end
	end
	check(hit, "guard: a description with a file name is caught")
end

print(string.format("spellbook_player_text_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
