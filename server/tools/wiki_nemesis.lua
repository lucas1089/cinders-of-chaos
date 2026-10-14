-- The website wiki's Nemesis entry (Events tab), built from data/scripts/chaos/nemesis_config.lua so the numbers never
-- drift. Loaded by tools/gen_wiki_data.lua (W.eventEntries):
--   out[#out + 1] = dofile("tools/wiki_nemesis.lua")(cfg("nemesis_config"), COLORS.event)
-- Entry format: the Codex's ({id, name, sub, color, group, sections = {{h, p, cols, w, rows}}}). English, like every
-- reference entry (the wiki page around it is in both languages; the guides carry the pt-BR text).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible; the same bytes under both.

local floor = math.floor

local function hours(s)
	local h = s / 3600
	if h == floor(h) then
		return string.format("%d h", h)
	end
	return string.format("%d min", floor(s / 60))
end

local function money(v)
	local s = tostring(floor(v))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

return function(c, color)
	local b, l, a, r = c.birth, c.level, c.appear, c.rewards
	local traitRows = {}
	for _, t in ipairs(c.traits) do
		traitRows[#traitRows + 1] = {t.name, t.desc}
	end
	local epithets = {}
	for i, e in ipairs(c.epithets.en) do
		epithets[i] = string.format(e, "Varek")
	end
	return {
		id = "event:nemesis", name = "Nemesis", color = color, group = "nemesis",
		sub = "A monster that kills you may come back for you, by name.",
		sections = {
			{h = "Birth", p = {
				string.format("When a regular monster kills a character of level %d or more, there is a %d%% chance it becomes that character's Nemesis. Bosses, summons, treasure goblins and the monsters of events and instances never do, and neither does a death with a player involved.",
					b.minLevel, b.chance),
				string.format("One Nemesis per character. After one ends, no new one for %s. Above %d active Nemeses on the server the chance falls, down to none at %d.",
					hours(b.cooldownSeconds), b.softCap, b.serverCap)}},
			{h = "The Nemesis", p = {
				string.format("It gets a name and an epithet that names you (\"Varkh, %s\" for a character called Varek), a level %d-%d%% above the monster that killed you, a black skull, a blood-red glow and one trait.",
					epithets[1], l.bumpMin, l.bumpMax),
				string.format("While you hunt its kind, or monsters near its level, each kill has a %d%% chance to call it: \"You feel a familiar hatred watching you...\" It appears a few tiles away, at most every %s, and fades after %d minutes if you do not finish it.",
					a.chance, hours(a.cooldownSeconds), floor(a.lifetimeSeconds / 60)),
				"It only appears for you, only hurts you and your party, and only you and your party can hurt it.",
				string.format("If it kills you again it grows: +%d%% level, a second trait and a new epithet (%s), up to %d kills. A Nemesis you have not met for %d days loses your trail.",
					l.growthPct, table.concat(epithets, ", ", 2), l.maxKills, c.expireDays)}},
			{h = "Traits", cols = {"Trait", "Effect"}, w = {30, 70}, rows = traitRows},
			{h = "Rewards", p = {
				string.format("Slay it yourself: a trophy with its name engraved (once per Nemesis, cannot be sold or traded), the title %s and a loot bonus in its corpse (at most once every %s).",
					r.titles.avenger, hours(r.avenge.cooldownSeconds)),
				string.format("A party member slays it: the Nemesis Hunter bounty of %s gold plus %d per level to their bank (at most once every %s, never for your own account or connection, never for a Nemesis younger than %d minutes). After %d of them, the title %s.",
					money(r.bounty.goldBase), r.bounty.goldPerLevel, hours(r.bounty.cooldownSeconds),
					floor(r.bounty.minAgeSeconds / 60), r.titles.hunterMin, r.titles.hunter),
				"Hardcore characters can have a Nemesis too; their reward is the trophy."}}
		}
	}
end
