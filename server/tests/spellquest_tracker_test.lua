-- Run from the server/ folder: luajit tests/spellquest_tracker_test.lua (CI runs luajit and lua5.3)
-- Line spell quest tracker: the rows (spellquest_tracker_core.lua) and the engine file (spellquest_tracker.lua) on a mocked engine.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function check(c, m) if not c then error(m, 2) end end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/spellquest_core.lua")
dofile("data/scripts/chaos/spellquest_tracker_core.lua")
local K, Q = ChaosSpellQuestTrackerCore, ChaosSpellQuestCore
local JUGG, DEAD = 8, 7
local function qs(a, b, c) return {a or {}, b or {}, c or {}} end

-- visibility
eq(#K.rows({vocId = JUGG, level = 499, q = qs()}), 0, "below the level")
eq(#K.rows({vocId = JUGG, level = 500, q = qs()}), 4, "at the level")
eq(#K.rows({vocId = 0, level = 900, q = qs()}), 0, "no line")
eq(#K.rows({vocId = 2, level = 900, q = qs()}), 0, "retired id")
eq(#K.rows({vocId = JUGG, level = 1500, q = qs({step = 3, mask = 1}, {step = 3, mask = 1}, {step = 3, mask = 1})}), 0, "every quest done")
eq(#K.rows({vocId = JUGG, level = 700, q = qs({step = 3, mask = 1})}), 0, "quest 2 needs level 800: hidden")
eq(#K.rows({vocId = JUGG, level = 800, q = qs({step = 3, mask = 1})}), 4, "quest 2 at level 800")
eq(#K.rows({vocId = DEAD, level = 800, q = qs({step = 3, mask = 1})}), 4, "another line: quest 1 again")
Q.cfg().enabled = false; eq(#K.rows({vocId = JUGG, level = 900, q = qs()}), 0, "switched off"); Q.cfg().enabled = true

-- steps
local r = K.rows({vocId = JUGG, level = 600, q = qs({step = -1, kills = -1, fragments = -1})})
eq(r[1].key, "talk"); eq(r[1].progress, 0); eq(r[1].state, "open"); eq(r[2].key, "kills"); eq(r[2].target, 400); eq(r[2].progress, 0, "-1 storage")
eq(r[3].key, "fragments"); eq(r[3].target, 20); eq(r[4].key, "trial")
check(r[1].title:find("Keepfall") and r[1].title:find("Archivist Ysolde"), r[1].title)
check(r[2].title:find("level 500"), r[2].title)
r = K.rows({vocId = JUGG, level = 600, q = qs({step = 1, kills = 150, fragments = 7})})
eq(r[1].state, "done"); eq(r[2].progress, 150); eq(r[2].state, "open"); eq(r[3].progress, 7)
r = K.rows({vocId = JUGG, level = 600, q = qs({step = 1, kills = 9999, fragments = 99})})
eq(r[2].progress, 400, "capped"); eq(r[3].progress, 20); eq(r[2].state, "done")
r = K.rows({vocId = JUGG, level = 600, q = qs({step = 2, kills = 0, fragments = 0})})
eq(r[2].state, "done", "the hunt is done at step 2"); eq(r[3].state, "done"); eq(r[4].state, "open", "the trial is open")
r = K.rows({vocId = 14, level = 1250, q = qs({step = 3, mask = 1}, {step = 3, mask = 1}, {step = 1, kills = 10})})
eq(r[2].target, 1000, "quest 3"); eq(r[2].progress, 10); check(r[2].title:find("level 1200"), r[2].title); check(r[1].title:find("Judgment of Iron"), r[1].title)
for _, row in ipairs(r) do check(row.title ~= "" and row.target >= 1, "row shape") end
-- the Ranger's quest 2 names the Ranger spell
r = K.rows({vocId = DEAD, level = 900, q = qs({step = 3, mask = 2}, {step = 0})})
check(r[1].title:find("Unblinking Gaze"), r[1].title)

-- texts in both languages
local pt = K.rows({vocId = JUGG, level = 600, q = qs()}, "pt-BR")
local en = K.rows({vocId = JUGG, level = 600, q = qs()}, "en")
for i = 1, 4 do check(pt[i].title ~= en[i].title, "pt-BR title " .. i) end
eq(pt[4].title, "Vença a prova da Arquivista")
check(pt[2].title:find("nível 500"), pt[2].title)
-- signature
check(K.sig(en, "en") ~= K.sig(pt, "pt-BR"), "language in the signature")
check(K.sig(en, "en") ~= K.sig(K.rows({vocId = JUGG, level = 600, q = qs({step = 1, kills = 5})}, "en"), "en"), "progress in the signature")
check(K.sig(en, "en") ~= K.sig(K.rows({vocId = DEAD, level = 600, q = qs()}, "en"), "en"), "the spell in the signature")

-- the engine file on a mocked engine
local events, globals, sent = {}, {}, {}
function CreatureEvent(name) local o = {}; function o:type() end; function o:register() events[name] = o end; return o end
function GlobalEvent(name) local o = {}; function o:interval() end; function o:register() globals[name] = o end; return o end
Chaos.send = function(p, op, action, data) sent[#sent + 1] = {op = op, action = action, data = data} end
Chaos.lang = function() return "en" end
local function newPlayer(id, voc, level)
	local p = {id = id, voc = voc, level = level, store = {}}
	function p:getId() return self.id end
	function p:getLevel() return self.level end
	function p:getVocation() return {getId = function() return self.voc end} end
	function p:getStorageValue(k) return self.store[k] or -1 end
	function p:registerEvent() end
	return p
end
local p = newPlayer(1, JUGG, 300)
local players = {p}
Game = {getPlayers = function() return players end}
dofile("data/scripts/chaos/spellquest_tracker.lua")
local A = ChaosSpellQuestTracker
local sweep = globals.ChaosSpellQuestTrackerThink
events.ChaosSpellQuestTrackerLogin.onLogin(p)
sweep.onThink(3000)
eq(#sent, 0, "nothing sent below the level")
p.level = 500
sweep.onThink(3000)
eq(#sent, 1, "sent when it can start"); eq(sent[1].op, 178, "goals opcode"); eq(sent[1].action, "spellquest"); eq(#sent[1].data.rows, 4)
sweep.onThink(3000)
eq(#sent, 1, "unchanged: not sent again")
local k = Q.keys(1)
p.store[k.step] = 1; p.store[k.kills] = 42
sweep.onThink(3000)
eq(#sent, 2, "sent on change"); eq(sent[2].data.rows[2].progress, 42)
p.store[k.step] = 3; p.store[k.lines] = 1; p.level = 700 -- quest 1 done, quest 2 not yet reachable
sweep.onThink(3000)
eq(#sent, 3, "hide sent"); eq(#sent[3].data.rows, 0)
sweep.onThink(3000)
eq(#sent, 3, "hidden stays quiet")
-- goals.lua, the one handler of opcode 178, clears the signature on "tracker"
local gsrc = io.open("data/scripts/chaos/goals.lua"):read("*a")
check(gsrc:find("ChaosSpellQuestTracker.sent[player:getId()] = nil", 1, true), "goals.lua resets on tracker")
A.sent[p:getId()] = nil
p.level = 800
sweep.onThink(3000)
eq(#sent, 4, "resent on request, quest 2 now")
check(events.ChaosSpellQuestTrackerExtended == nil, "no second handler on opcode 178")
events.ChaosSpellQuestTrackerLogout.onLogout(p)
eq(A.sent[1], nil, "logout clears")
print("spellquest_tracker_test ok")
