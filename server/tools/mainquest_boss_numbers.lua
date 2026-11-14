-- mainquest_boss_numbers.lua: Vael's attack table (data/scripts/chaos/mainquest_boss_config.lua, O554) as JSON for
-- tools/mainquest_boss_model.py. Run from server/: luajit tools/mainquest_boss_numbers.lua
-- Prints {"enabled", "minWindMs", "reactionMs", "gapMs", "every": [..], "enrage": {..}, "dodge": {..}, "attacks": [{"key", "windMs",
-- "phases": [..], "parts": [{"kind", "share"}]}]}. Lua 5.1 / LuaJIT and 5.3. No engine calls.
local c = dofile("data/scripts/chaos/mainquest_boss_config.lua")

local function list(t)
	local out = {}
	for i, v in ipairs(t) do
		out[i] = tostring(v)
	end
	return "[" .. table.concat(out, ", ") .. "]"
end

local attacks = {}
for _, a in ipairs(c.attacks) do
	local parts = {}
	for i, p in ipairs(a.parts) do
		parts[i] = string.format('{"kind": "%s", "share": %s}', p.kind, tostring(p.share))
	end
	attacks[#attacks + 1] = string.format('{"key": "%s", "windMs": %d, "phases": %s, "parts": [%s]}', a.key, a.windMs, list(a.phases),
		table.concat(parts, ", "))
end
print(string.format(
	'{"enabled": %s, "minWindMs": %d, "reactionMs": %d, "gapMs": %d, "every": %s, "enrage": {"cadenceMult": %s, "damageMult": %s}, ' ..
	'"dodge": {"typical": %s, "poor": %s}, "attacks": [%s]}',
	tostring(c.enabled == true), c.minWindMs, c.reactionMs, c.gapMs, list(c.every), tostring(c.enrage.cadenceMult),
	tostring(c.enrage.damageMult), tostring(c.dodge.typical), tostring(c.dodge.poor), table.concat(attacks, ", ")))
