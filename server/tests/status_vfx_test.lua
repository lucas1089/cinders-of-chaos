-- Run from the server/ folder: luajit tests/status_vfx_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the status layer (O597; data/lib/chaos_status_vfx.lua, data/lib/chaos_status_vfx_ids.lua, data/scripts/chaos/
-- status_vfx.lua, the hook in data/lib/chaos_pack29_vfx.lua): the opcode (free), the ids file and its pair gate, masks,
-- condition rows, marks, the brief haste, what a watcher is told, batches, the hello answer, the pack 29 states handed
-- over only while the layer is live, and the glue on a mocked engine (only a client that said hello is told, only changes).
dofile("data/scripts/chaos/chaos_constants.lua")
-- no json in the plain interpreter: a stand-in that hands the table itself over
local boxes = {}
json = {
	encode = function(t) boxes[#boxes + 1] = t; return "#" .. #boxes end,
	decode = function(s) return boxes[tonumber(s:sub(2))] end,
}

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function readFile(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

-- ------------------------------------------------------------------ the opcode
eq(ChaosOpcodes.statusVfx, 165, "opcode 165")
local seen = {}
for name, v in pairs(ChaosOpcodes) do
	ok(seen[v] == nil, "opcode " .. tostring(v) .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = name
end
for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 126, 127,
		140, 144, 145, 146, 210, 212, 213, 230, 246}) do
	ok(ChaosOpcodes.statusVfx ~= v, "not an opcode of the reference server or client: " .. v)
end
local ls = io.popen("ls ../client/overlay/modules 2>/dev/null")
local others = 0
for dir in ls:lines() do
	if dir ~= "game_statusfx" then
		local ph = io.popen("ls ../client/overlay/modules/" .. dir .. "/*.lua 2>/dev/null")
		for file in ph:lines() do
			local s = readFile(file)
			if s and not file:find("_test.lua", 1, true) and (s:find("[Oo]pcode[%w_]*%s*=%s*165%f[%D]") or s:find("xtended[%w]*Opcode%(%s*165%f[%D]")) then
				others = others + 1
				print("opcode 165 in " .. file)
			end
		end
		ph:close()
	end
end
ls:close()
eq(others, 0, "no other client module on 165")
dofile("../client/overlay/modules/game_statusfx/statusfx_logic.lua")
eq(StatusFxLogic.OPCODE, 165, "the client module listens on 165")

-- ------------------------------------------------------------------ the ids file and the gate
dofile("data/lib/chaos_status_vfx_ids.lua")
local I = ChaosStatusVfxIds
eq(I.PAIR, 73, "pair 73")
eq(I.FIRST, 5143, "first id after the sibling step's block")
eq(#I.order, 14, "14 statuses")
ok(I.on == false, "off without a config.lua record")
eq(I.parsePair("a = 1\nchaosClientPair = 73 -- x\n"), 73, "pair read")
eq(I.parsePair("chaosClientPair = 72"), 72, "pair read at the start")
eq(I.parsePair("-- chaosClientPair = 99\n"), nil, "a comment is no record")
local ids = {}
for _, name in ipairs(I.order) do
	local s = I.status[name]
	ok(s ~= nil, "status " .. name)
	for _, k in ipairs({"start", "loop", "stop"}) do
		ok(s[k] >= I.FIRST and s[k] <= I.LAST and not ids[s[k]], name .. " " .. k .. " id")
		ids[s[k]] = true
		ok(s[k .. "Ms"] > 0, name .. " " .. k .. " length")
	end
end
for _, k in ipairs({"melt", "sink", "bones", "vapour", "stone"}) do
	local e = I.kill[k]
	ok(e and e.id >= I.FIRST and e.id <= I.LAST and not ids[e.id] and e.ms > 0, "kill overlay " .. k)
	ids[e.id] = true
end
-- every id has an element tag (check_spell_fx.py reads the file)
local tags = readFile("data/spells/spell_fx_elements.csv")
for id in pairs(ids) do
	ok(tags:find("\n" .. id .. ",st_", 1, true) ~= nil, "tag of effect " .. id)
end

-- ------------------------------------------------------------------ masks
dofile("data/lib/chaos_status_vfx.lua")
local S = ChaosStatusVfx
eq(S.OPCODE, ChaosOpcodes.statusVfx, "the lib's opcode is the constant")
eq(S.bits.burn, 1, "burn is bit 0")
eq(S.bits.rage, 8192, "rage is bit 13")
eq(S.maskOf({"burn", "poison", "burn", "nope"}), 1 + 8, "mask of names")
eq(table.concat(S.namesOf(1 + 8 + 8192), ","), "burn,poison,rage", "names of a mask")
ok(S.hasBit(9, 8) and not S.hasBit(9, 2), "hasBit")
for state, status in pairs(S.states) do
	ok(S.bits[status] ~= nil, "state " .. state .. " names a status")
end

-- conditions
local G = {CONDITION_FIRE = 1, CONDITION_POISON = 2, CONDITION_PARALYZE = 3, CONDITION_HASTE = 4, CONDITION_REGENERATION = 5,
	CONDITIONID_COMBAT = 9, CONDITION_DRUNK = 6, CONDITION_MANASHIELD = 7}
local rows = S.resolve(G)
eq(#rows, 7, "only the constants the engine has")
local function probeOf(set)
	return function(ctype, id) return set[ctype .. ":" .. tostring(id)] == true end
end
eq(S.conditionMask(rows, true, probeOf({["1:nil"] = true, ["5:9"] = true})), S.bits.burn + S.bits.regen, "a player's conditions")
eq(S.conditionMask(rows, true, probeOf({["5:nil"] = true})), 0, "the food regeneration is no status")
eq(S.conditionMask(rows, false, probeOf({["1:nil"] = true, ["4:nil"] = true, ["6:nil"] = true, ["3:nil"] = true})),
	S.bits.burn + S.bits.root, "a monster: no haste, no drunk")
eq(#S.resolve({CONDITION_REGENERATION = 5}), 0, "a row without its condition id never matches")

-- marks
eq(S.markMask(7, 0), 0, "no mark")
ok(S.mark(7, "stun", 1000, 100), "mark")
ok(S.mark(7, "stun", 200, 100), "a shorter mark keeps the end")
ok(not S.mark(7, "nope", 1000, 100) and not S.mark(7, "stun", 0, 100), "bad marks refused")
eq(S.markMask(7, 1000), S.bits.stun, "held")
eq(S.markMask(7, 1100), 0, "ended")
eq(S.markCount, 0, "dropped")
ok(S.markState(8, "slowed", 500, 0) and not S.markState(8, "bleeding", 500, 0), "states: slowed is root, bleeding has none")
eq(S.markMask(8, 1), S.bits.root, "the state's status")
eq(S.pruneMarks(10000), 0, "prune")
local keep = S.maxMarks
S.maxMarks = 1
ok(S.mark(1, "burn", 10, 0) and not S.mark(2, "burn", 10, 0) and S.mark(1, "curse", 10, 0), "the cap is per creature")
S.maxMarks = keep
S.pruneMarks(100)

-- brief haste
local h = S.bits.haste
eq(S.cutBrief(5, h + 1, 0), h + 1, "haste shows at first")
eq(S.cutBrief(5, h + 1, S.briefMs - 1), h + 1, "still")
eq(S.cutBrief(5, h + 1, S.briefMs), 1, "cut after the brief time")
eq(S.cutBrief(5, 1, S.briefMs + 10), 1, "gone")
eq(S.cutBrief(5, h, S.briefMs + 20), h, "a new haste shows again")
S.forget(5)
ok(S.since[5] == nil, "forget")

-- what a watcher is told
local known = {}
local c = S.changes(known, {[10] = 1, [11] = 6})
eq(table.concat(c, ","), "10,1,11,6", "first sight")
c = S.changes(known, {[10] = 1, [11] = 6})
eq(#c, 0, "nothing changed, nothing told")
c = S.changes(known, {[10] = 3})
eq(table.concat(c, ","), "10,3,11,0", "a change and a creature gone")
eq(known[11], nil, "forgotten")
c = S.changes(known, {})
eq(table.concat(c, ","), "10,0", "all gone")
ok(next(known) == nil, "empty")
local long = {}
for i = 1, S.maxPairs * 2 + 3 do
	long[#long + 1] = i; long[#long + 1] = 1
end
local parts = S.batches(long)
eq(#parts, 3, "batches")
eq(#parts[1], S.maxPairs * 2, "a full batch")
eq(#parts[3], 6, "the rest")
ok(S.maxPairs * 2 * 12 < 4000, "a full message is small (two numbers of at most 11 characters a pair)")

-- hello
eq(S.hello().on, 0, "off: the client is told so")
I.on = true
local hello = S.hello()
eq(hello.on, 1, "on")
eq(#hello.e, 42, "42 effect ids")
eq(hello.e[1], I.status.burn.start, "burn start first")
eq(hello.e[42], I.status.rage.stop, "rage stop last")
eq(#hello.ms, 42, "42 lengths")
I.on = false

-- ------------------------------------------------------------------ pack 29 hands its states over
ChaosPack29Fx = {PAIR29 = true}
ChaosVfx = {cond_stunned = {id = 800, dx = 0, dy = 0, ms = 900}, cond_burning = {id = 801, dx = 0, dy = 0, ms = 900},
	cond_bleeding = {id = 802, dx = 0, dy = 0, ms = 900}}
local sentVfx = {}
function Vfx(pos, name) sentVfx[#sentVfx + 1] = name; return true end
dofile("data/lib/chaos_pack29_vfx.lua")
local P = ChaosPack29Vfx
local mob = {getId = function() return 77 end, getPosition = function() return {x = 1, y = 1, z = 7} end}
ok(P.show(mob, "stunned"), "layer off: pack 29 shows its aura")
eq(sentVfx[1], "cond_stunned", "the old aura")
eq(S.markMask(77, P.now()), 0, "no mark while off")
I.on = true
P.resetThrottle()
sentVfx = {}
ok(P.show(mob, "stunned"), "layer on: taken")
eq(#sentVfx, 0, "no old aura")
eq(S.markMask(77, P.now()), S.bits.stun, "marked")
ok(P.hold(mob, "burning", 5000), "hold")
ok(S.hasBit(S.markMask(77, P.now() + 4000), S.bits.burn), "held for its time")
ok(P.show(mob, "bleeding"), "a state without a status keeps its aura")
eq(sentVfx[1], "cond_bleeding", "bleeding aura")
local hits = P.engineRows({COMBAT_FIREDAMAGE = 8, COMBAT_PHYSICALDAMAGE = 1}, ChaosVfx, {}, {})
local kinds = {}
for _, r in ipairs(hits) do
	if r[1] == 2 then kinds[r[2]] = true end
end
ok(kinds[1] == true and kinds[8] == nil, "engine ticks: bleeding stays, burning is the layer's")
I.on = false
hits = P.engineRows({COMBAT_FIREDAMAGE = 8}, ChaosVfx, {}, {})
ok(#hits == 1 and hits[1][1] == 2, "layer off: the burning tick aura as before")
S.forget(77)

-- ------------------------------------------------------------------ the glue on a mocked engine
local events = {}
local function reg(kind)
	return function(name)
		local e = {name = name, kind = kind}
		function e:register() events[name] = self end
		function e:interval() end
		function e:type() end
		return e
	end
end
GlobalEvent = reg("global")
CreatureEvent = reg("creature")
CONDITION_FIRE, CONDITION_PARALYZE = 1, 3
local clock = 1000
os.mtime = function() return clock end
local function creature(id, isPlayer, conds)
	local cr = {conds = conds or {}, sent = {}}
	function cr:getId() return id end
	function cr:isPlayer() return isPlayer end
	function cr:hasCondition(t) return self.conds[t] == true end
	function cr:getCondition() return nil end
	function cr:getPosition() return {x = 100, y = 100, z = 7} end
	function cr:registerEvent() end
	function cr:sendExtendedOpcode(op, buf) self.sent[#self.sent + 1] = {op = op, msg = json.decode(buf)} end
	return cr
end
local p1, p2 = creature(1, true), creature(2, true)
local rat = creature(50, false, {[CONDITION_FIRE] = true})
local players = {[1] = p1, [2] = p2}
function Player(id) return players[id] end
Game = {getSpectators = function() return {p1, p2, rat} end}
ChaosRateLimit = nil
dofile("data/scripts/chaos/status_vfx.lua")
local think, extended = events.ChaosStatusVfxScan, events.ChaosStatusVfxExtended
events.ChaosStatusVfxLogin.onLogin(p1)
events.ChaosStatusVfxLogin.onLogin(p2)
extended.onExtendedOpcode(p1, 165, json.encode({action = "hello", data = {on = 1}}))
eq(p1.sent[1].msg.action, "cfg", "hello answered")
eq(p1.sent[1].msg.data.on, 0, "pair too old: off")
think.onThink(500)
eq(#p1.sent, 1, "off: nothing told")
I.on = true
extended.onExtendedOpcode(p1, 164, json.encode({action = "hello", data = {on = 1}}))
eq(#p1.sent, 1, "another opcode is not ours")
extended.onExtendedOpcode(p1, 165, json.encode({action = "hello", data = {on = 1}}))
eq(p1.sent[2].msg.data.on, 1, "on")
think.onThink(500)
eq(#p1.sent, 3, "the first scan tells")
eq(p1.sent[3].msg.action, "s", "action s")
eq(table.concat(p1.sent[3].msg.data.l, ","), "50,1", "the burning rat")
eq(#p2.sent, 0, "a client that did not say hello gets nothing")
think.onThink(500)
eq(#p1.sent, 3, "no change, no message")
S.mark(1, "stun", 800, clock)
rat.conds = {}
think.onThink(500)
eq(table.concat(p1.sent[4].msg.data.l, ","), "1," .. S.bits.stun .. ",50,0", "a mark on the player, the rat is out")
clock = clock + 1000
think.onThink(500)
eq(table.concat(p1.sent[5].msg.data.l, ","), "1,0", "the mark ended")
extended.onExtendedOpcode(p1, 165, json.encode({action = "hello", data = {on = 0}}))
rat.conds = {[CONDITION_FIRE] = true}
local n = #p1.sent
think.onThink(500)
eq(#p1.sent, n, "stopped on the client's wish")
I.on = false

print(string.format("status_vfx_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
