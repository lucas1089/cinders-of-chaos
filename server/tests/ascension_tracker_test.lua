-- Run from the server/ folder: luajit tests/ascension_tracker_test.lua (CI runs luajit and lua5.3)
-- Ascension tracker: the rows (ascension_tracker_core.lua) and the engine file (ascension_tracker.lua) on a mocked engine.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function check(c, m) if not c then error(m, 2) end end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/ascension_quest_core.lua")
dofile("data/scripts/chaos/ascension_tracker_core.lua")
local K, Q = ChaosAscensionTrackerCore, ChaosAscensionQuestCore
local min = Chaos.classes.ascension.minLevel
local need = Q.cfg().proof.needed

-- visibility
eq(#K.rows({vocId = 4, level = min - 1, stage = 0, proof = 0}), 0, "below the level")
eq(#K.rows({vocId = 4, level = min, stage = 0, proof = 0}), 4, "at the level")
eq(#K.rows({vocId = 14, level = 300, stage = 4, proof = 0}), 0, "ascended")
eq(#K.rows({vocId = 0, level = 300, stage = 0, proof = 0}), 0, "no line")
eq(#K.rows({vocId = 2, level = 300, stage = 0, proof = 0}), 0, "retired id")

-- stages
local r = K.rows({vocId = 4, level = 200, stage = -1, proof = -1})
eq(r[1].key, "calling"); eq(r[1].progress, 0); eq(r[1].state, "open"); eq(r[2].target, need); eq(r[2].progress, 0, "-1 storage")
r = K.rows({vocId = 4, level = 200, stage = 1, proof = 4})
eq(r[1].state, "done"); eq(r[2].progress, 4); eq(r[2].state, "open"); eq(r[3].state, "open")
r = K.rows({vocId = 4, level = 200, stage = 1, proof = 99})
eq(r[2].progress, need, "capped")
r = K.rows({vocId = 4, level = 200, stage = 2, proof = 0})
eq(r[2].state, "done", "proof done at stage 2"); eq(r[3].state, "open")
r = K.rows({vocId = 4, level = 200, stage = 3, proof = 0})
eq(r[3].state, "done"); eq(r[4].state, "open", "choice open")
r = K.rows({vocId = 4, level = 200, stage = 4, proof = 0})
eq(r[4].state, "open", "vocation changed back: choose again"); eq(r[1].state, "done")
for _, row in ipairs(r) do assert(row.title ~= "" and row.target >= 1) end

-- texts in both languages
local pt = K.rows({vocId = 4, level = 200, stage = 0, proof = 0}, "pt-BR")
local en = K.rows({vocId = 4, level = 200, stage = 0, proof = 0}, "en")
for i = 1, 4 do assert(pt[i].title ~= en[i].title, "pt-BR title " .. i) end
eq(pt[3].title, "Vença a Prova de Ascensão")

-- signature
assert(K.sig(en, "en") ~= K.sig(pt, "pt-BR"), "language in the signature")
assert(K.sig(en, "en") ~= K.sig(K.rows({vocId = 4, level = 200, stage = 1, proof = 0}, "en"), "en"))
eq(K.sig(en, "en"), K.sig(K.rows({vocId = 4, level = 200, stage = 0, proof = 5}, "en"), "en"), "proof ignored before the Calling")

-- the engine file on a mocked engine
local events, globals, sent = {}, {}, {}
function CreatureEvent(name) local o = {}; function o:type() end; function o:register() events[name] = o end; return o end
function GlobalEvent(name) local o = {}; function o:interval() end; function o:register() globals[name] = o end; return o end
Chaos.send = function(p, op, action, data) sent[#sent + 1] = {op = op, action = action, data = data} end
Chaos.decode = function(b) return b end
Chaos.lang = function() return "en" end
local st = Q.cfg().storage
local function newPlayer(id, voc, level)
	local p = {id = id, voc = voc, level = level, store = {}}
	function p:getId() return self.id end
	function p:getLevel() return self.level end
	function p:getVocation() return {getId = function() return self.voc end} end
	function p:getStorageValue(k) return self.store[k] or -1 end
	function p:registerEvent() end
	return p
end
local p = newPlayer(1, 4, 50)
local players = {p}
Game = {getPlayers = function() return players end}
dofile("data/scripts/chaos/ascension_tracker.lua")
local A = ChaosAscensionTracker
local sweep = globals.ChaosAscensionTrackerThink
events.ChaosAscensionTrackerLogin.onLogin(p)
sweep.onThink(3000)
eq(#sent, 0, "nothing sent below the level")
p.level = min
sweep.onThink(3000)
eq(#sent, 1, "sent when it can start"); eq(sent[1].op, 178, "goals opcode"); eq(sent[1].action, "ascension"); eq(#sent[1].data.rows, 4)
sweep.onThink(3000)
eq(#sent, 1, "unchanged: not sent again")
p.store[st.stage] = 1; p.store[st.proof] = 3
sweep.onThink(3000)
eq(#sent, 2, "sent on change"); eq(sent[2].data.rows[2].progress, 3)
p.voc = 14 -- ascended
sweep.onThink(3000)
eq(#sent, 3, "hide sent"); eq(#sent[3].data.rows, 0)
sweep.onThink(3000)
eq(#sent, 3, "hidden stays quiet")
-- the client asks for the tracker again: resend
p.voc = 4
-- goals.lua, the one handler of opcode 178, clears the signature on "tracker"
local gsrc = io.open("data/scripts/chaos/goals.lua"):read("*a")
check(gsrc:find("ChaosAscensionTracker.sent[player:getId()] = nil", 1, true), "goals.lua resets on tracker")
A.sent[p:getId()] = nil
sweep.onThink(3000)
eq(#sent, 4, "resent on request")
check(events.ChaosAscensionTrackerExtended == nil, "no second handler on opcode 178")
events.ChaosAscensionTrackerLogout.onLogout(p)
eq(A.sent[1], nil, "logout clears")
print("ascension_tracker_test ok")
