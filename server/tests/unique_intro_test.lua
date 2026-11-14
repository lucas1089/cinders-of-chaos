-- Run from the server/ folder: luajit tests/unique_intro_test.lua (and lua5.3; CI runs both)
-- O467: the one-time line a character reads when it finds its first unique (unique_intro_core.lua, unique_intro_config.lua,
-- unique_intro.lua on a mocked player), the pt-BR texts of the tooltip line of a unique's power, and that every place that
-- hands a player a unique calls ChaosUniqueIntro.found.
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	checks = checks + 1
	if not v then
		error(m or "assertion failed", 2)
	end
end

local K = dofile("data/scripts/chaos/unique_intro_core.lua")
local cfg = dofile("data/scripts/chaos/unique_intro_config.lua")

-- ---------------------------------------------------------------- the rule
ok(K.due(cfg, nil), "unset: due")
ok(K.due(cfg, -1), "-1: due")
ok(K.due(cfg, 0), "0: due")
ok(not K.due(cfg, 1), "shown: not due")
ok(not K.due(cfg, K.SHOWN), "the shown value is not due")
ok(not K.due({enabled = false}, nil), "off: never")
ok(not K.due(nil, nil), "no config: never")
eq(cfg.storage, 7103090, "the storage key of the README block 7103090 - 7103099")

-- the storage key is free: no other config or constant of the server uses it
local function readFile(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end
do
	local hits = 0
	for _, path in ipairs({"data/scripts/chaos/chaos_constants.lua", "data/scripts/chaos/retention_loot_config.lua"}) do
		for _ in readFile(path):gmatch("7103090") do
			hits = hits + 1
		end
	end
	eq(hits, 0, "no other file holds 7103090")
end

-- ---------------------------------------------------------------- the glue on a mocked player
MESSAGE_EVENT_ADVANCE = 19
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/unique_intro.lua")
local I = ChaosI18n

local seq = 0
local function player(lang)
	seq = seq + 1
	local p = {id = seq, storage = {}, sent = {}}
	function p:getId() return self.id end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:sendTextMessage(t, text) self.sent[#self.sent + 1] = {t, text} end
	Chaos.setLang(p, lang)
	return p
end

local en = player("en")
ok(ChaosUniqueIntro.found(en), "the first call shows the line")
eq(#en.sent, 1, "one message")
eq(en.sent[1][1], MESSAGE_EVENT_ADVANCE, "on the path of the first-unique message")
eq(en.sent[1][2], cfg.text, "in English")
eq(en.storage[cfg.storage], K.SHOWN, "and remembers it")
ok(not ChaosUniqueIntro.found(en), "the second call does nothing")
eq(#en.sent, 1, "still one message")
ok(not ChaosUniqueIntro.found(nil), "no player: nothing")

local pt = player("pt-BR")
ChaosUniqueIntro.found(pt)
eq(#pt.sent, 1, "pt-BR: one message")
ok(pt.sent[1][2] ~= cfg.text, "pt-BR: not the English text")
ok(pt.sent[1][2]:find("Codex", 1, true), "pt-BR: names the Codex")

-- ---------------------------------------------------------------- the texts of the tooltip line, both languages
local S = I.strings["pt-BR"]
for _, key in ipairs({"Works for your class.", "Works for every class.", "Cannot use: not for your class.", "Active.",
		"Asleep: %s is stronger.", "Asleep: only %d unique powers work at once.", cfg.text}) do
	ok(S[key] and S[key] ~= key, "pt-BR text of: " .. key)
	local _, ec = key:gsub("%%[sd]", "")
	local _, pc = S[key]:gsub("%%[sd]", "")
	eq(pc, ec, "same % conversions: " .. key)
end

-- ---------------------------------------------------------------- every place that hands a unique over calls it
for _, path in ipairs({"loot.lua", "retention_loot.lua", "itemsets.lua", "conquest.lua", "raid.lua", "uber.lua", "worldboss.lua",
		"pocketboss.lua", "invasion.lua"}) do
	ok(readFile("data/scripts/chaos/" .. path):find("ChaosUniqueIntro.found", 1, true), path .. " calls ChaosUniqueIntro.found")
end

print("unique_intro_test: " .. checks .. " checks ok")
