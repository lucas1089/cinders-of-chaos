-- The pages of the Ashen Chronicle and the Capital Memorial for the Codex's Lore tab and the website wiki (the wiki takes
-- the Lore tab from the Codex): one page per chapter of every arc (the story in English, the goals and what the chapter
-- changes, then the story in Brazilian Portuguese), an overview of the Chronicle and a page about the Memorial. Pure:
-- reads data/scripts/chaos/chronicle_text.lua, chronicle_config.lua and memorial_config.lua; run from the server/ folder.
--   local CP = dofile("tools/chronicle_pages.lua"); CP.entries(color) -> Codex entries (format: client game_codex/codex.lua)
-- tools/gen_codex_data.lua appends them to the Lore tab (kind "chronicle"); tests: server/tests/chronicle_test.lua.
-- No clock, no random, no pairs() order: the output only changes when the data does. Lua 5.1 / LuaJIT and Lua 5.3.

local CP = {}

CP.KIND = {key = "chronicle", en = "The Ashen Chronicle", pt = "A Crônica das Cinzas"}
CP.SOURCES = {"data/scripts/chaos/chronicle_text.lua", "data/scripts/chaos/chronicle_config.lua",
	"data/scripts/chaos/memorial_config.lua"}

local function fmt(n)
	n = math.floor(tonumber(n) or 0)
	local s = tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return s
end

local function goalRows(cfg, K, ch)
	local rows = {}
	for _, g in ipairs(ch.goals) do
		rows[#rows + 1] = {K.goalLabel(cfg, g), fmt(g.target)}
	end
	return rows
end

local function worldLines(cfg, K, ch)
	local lines = {}
	local w = ch.world or {}
	for _, key in ipairs(w.open or {}) do
		local a = K.areaByKey(cfg, key)
		lines[#lines + 1] = string.format("%s opens (level %d and above): its gate appears in the world.", a and a.name or key,
			a and a.minLevel or 1)
	end
	local town = w.town or {}
	if town.add and #town.add > 0 then
		lines[#lines + 1] = "The capital changes around its temple."
	end
	if town.remove and #town.remove > 0 then
		lines[#lines + 1] = "Earlier scars of the capital are cleared away."
	end
	lines[#lines + 1] = "The Chronicler's words move on, the realm hears a broadcast, and the top contributors are recorded at the season's end."
	return lines
end

-- every page, in reading order. color: the Lore tab's colour
function CP.entries(color)
	local TXT = dofile("data/scripts/chaos/chronicle_text.lua")
	local cfg = dofile("data/scripts/chaos/chronicle_config.lua")
	local mcfg = dofile("data/scripts/chaos/memorial_config.lua")
	dofile("data/scripts/chaos/chronicle_core.lua")
	local K = ChaosChronicleCore
	local out = {}
	local function add(e)
		e.color = color
		e.sub = e.sub or CP.KIND.en
		e.group = CP.KIND.key
		e.f = {group = CP.KIND.key}
		out[#out + 1] = e
	end
	-- the arcs in season order
	local seasons = {}
	for id in pairs(cfg.arcs or {}) do
		seasons[#seasons + 1] = id
	end
	table.sort(seasons)
	for _, id in ipairs(seasons) do
		local arcKey = cfg.arcs[id]
		local arc = TXT.arcs[arcKey]
		local chs = K.chapters(cfg, arcKey)
		if arc then
			local list = {}
			for ci, ch in ipairs(arc.chapters) do
				list[#list + 1] = {ch.title.en, fmt(#chs[ci].goals) .. (#chs[ci].goals == 1 and " goal" or " goals")}
			end
			add({id = "lore:chronicle_" .. arcKey, name = arc.title.en, sections = {
				{h = "The Ashen Chronicle", p = {arc.intro.en,
					"One chapter is open at a time. The whole realm writes it: every world boss slain, rift sealed, Omen and " ..
					"Ascended Omen defeated, Ashen Sepulchre cleared, character reaching a level and world event won counts " ..
					"for the chapter whose goal it is. When every goal is met the chapter is written and the world changes. " ..
					"Adventure > Chronicle shows the bars, your part and the top contributors."}},
				{h = "Chapters", cols = {"Chapter", "Goals"}, w = {70, 30}, rows = list},
				{h = "At the season's end", p = {"The Chronicler records the top contributors of every chapter: the client's " ..
					"Record tab and the website's Chronicle page keep them. The next season starts a new book, and the world " ..
					"changes of this one are taken back."}},
				{h = "Em portugu\195\170s", p = {arc.title.pt, arc.intro.pt}}}})
			for ci, ch in ipairs(arc.chapters) do
				local secs = {
					{h = "The story", p = ch.text.en},
					{h = "Goals of the realm", cols = {"Goal", "Target"}, w = {75, 25}, rows = goalRows(cfg, K, chs[ci])},
					{h = "When it is written", p = {ch.world.en}},
					{h = "What changes", p = worldLines(cfg, K, chs[ci])},
					{h = "Em portugu\195\170s", p = (function()
						local p = {ch.title.pt}
						for _, line in ipairs(ch.text.pt) do
							p[#p + 1] = line
						end
						p[#p + 1] = ch.world.pt
						return p
					end)()}
				}
				add({id = "lore:chronicle_" .. arcKey .. "_" .. ci, name = ch.title.en, sub = arc.title.en, sections = secs})
			end
		end
	end
	add({id = "lore:memorial", name = "The Ember Memorial", sub = "The Capital Memorial", sections = {
		{h = "The Memorial", p = {"A plaza in the capital keeps the season: guardian statues for its realm firsts, statues " ..
			"for its records and memorial stones for the heroes who fell in Hardcore. Look at one to read it. A stone in the " ..
			"middle says what is remembered; when there are more names than statues, they turn every " ..
			fmt(math.floor((mcfg.rotateSeconds or 600) / 60)) .. " minutes.",
			"Every name is there by its player's choice (Adventure > Chronicle > Memorial): records and realm firsts are " ..
			"shown unless you turn them off, a Hardcore fall only after your yes, asked at the next login after the fall. " ..
			"You can change it any time. Each season starts a new Memorial; the website keeps the past ones."}},
		{h = "Em portugu\195\170s", p = {"Uma praça na capital guarda a temporada: estátuas de guardião para as primeiras " ..
			"vitórias do reino, estátuas para os recordes e pedras memoriais para os heróis que caíram no Hardcore. Cada nome " ..
			"está lá por escolha do jogador: recordes e primeiras vitórias aparecem, a menos que você desligue; uma queda no " ..
			"Hardcore só depois do seu sim. Você pode mudar quando quiser."}}}})
	return out
end

return CP
