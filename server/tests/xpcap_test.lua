-- Run from the server/ folder: luajit tests/xpcap_test.lua (and lua5.3; CI runs both)
-- The global experience cap (xpcap_core.lua, xpcap_config.lua, xpcap.lua): the base of a kill (raw experience x the
-- monster level factor x the stage x the tier), the clamp, and xpcap.lua in a mocked onGainExperience chain sorted by
-- index like the engine's: the stacked bonuses are cut to cap x base, the dungeon difficulty (90), the rift cap (100)
-- and the hunt tracker (1000) run after it, the recorder stands in for a missing rawExp, other sources pass.

local checks, fails = 0, 0
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

-- ---------------------------------------------------------------- core
local X = dofile("data/scripts/chaos/xpcap_core.lua")
local cfg = dofile("data/scripts/chaos/xpcap_config.lua")
eq(cfg.cap, 4.0, "default cap")
ok(cfg.index > 50 and cfg.index < 90, "after the admin event (50), before the dungeon difficulty (90) and the rift cap (100)")
ok(cfg.recordIndex < 0, "the recorder runs before every bonus (lowest index 0)")
eq(X.levelFactor(0), 1, "no level: 1")
eq(X.levelFactor(20), 1, "level 20: 0.6 -> 1 (never lowers)")
eq(X.levelFactor(100), 3, "level 100: x3")
eq(X.base(1000, 0, 5, 1), 5000, "base: raw x stage")
eq(X.base(1000, 200, 5, 10), 1000 * 6 * 5 * 10, "base: raw x level factor x stage x tier")
eq(X.base(nil, 0, 5, 1), 0, "no raw: 0")
eq(X.clamp(30000, 5000, 4), 20000, "above the cap: cut to 4x")
eq(X.clamp(15000, 5000, 4), 15000, "below the cap: unchanged")
eq(X.clamp(15000, 0, 4), 15000, "unknown base: unchanged")
eq(X.clamp(15000, 5000, nil), 15000, "no cap: unchanged")
eq(X.clamp(0, 5000, 4), 0, "nothing stays nothing")
eq(X.clamp(10, 0.1, 4), 1, "a tiny base still allows 1")

-- ---------------------------------------------------------------- the chain (mocked engine)
local chain = {}
EventCallback = setmetatable({}, {
	__newindex = function(t, k, v) rawset(t, "_pending", v) end,
	__index = function(t, k)
		if k == "register" then
			return function(self, index)
				chain[#chain + 1] = {fn = rawget(self, "_pending"), index = index or 0, order = #chain}
				rawset(self, "_pending", nil)
				table.sort(chain, function(a, b)
					if a.index ~= b.index then
						return a.index < b.index
					end
					return a.order < b.order
				end)
			end
		end
	end
})
local STAGE = 5
Game = {getExperienceStage = function() return STAGE end}
ChaosTiers = {magic = {xp = 2}, rare = {xp = 4}, legendary = {xp = 10}}
local tierOf = {}
function ChaosTierOf(m) return tierOf[m] end

-- the bonuses of the audit, each its own callback at index 0 (registered before xpcap.lua, like the real files)
local function bonus(mult, index)
	local cb = EventCallback
	cb.onGainExperience = function(p, s, exp, raw) return math.floor(exp * mult) end
	cb:register(index)
end
local tierCb = EventCallback
tierCb.onGainExperience = function(p, s, exp, raw)
	local t = tierOf[s]
	return t and math.floor(exp * ChaosTiers[t].xp) or exp
end
tierCb:register()
for _, m in ipairs({1.5, 1.1, 1.25, 1.25, 1.10, 1.495, 1.5, 1.1, 1.33, 1.15, 2.0, 1.06, 1.05, 1.05, 1.10}) do
	bonus(m)
end
local adminOn = false
local admin = EventCallback
admin.onGainExperience = function(p, s, exp) return adminOn and exp * 2 or exp end
admin:register(50)
local dungeonMult = 1
local dungeon = EventCallback
dungeon.onGainExperience = function(p, s, exp) return math.floor(exp * dungeonMult) end
dungeon:register(90)
local given
local hunt = EventCallback
hunt.onGainExperience = function(p, s, exp) given = exp; return exp end
hunt:register(1000)

dofile("data/scripts/chaos/xpcap.lua")
eq(chain[1].index, -1000, "the recorder is first")

local player = {getId = function() return 7 end, getLevel = function() return 300 end}
local function monster(level)
	return {isMonster = function() return true end, getMonsterLevel = function() return level or 0 end}
end
-- the engine's dispatch: exp is updated by each callback, rawExp is passed unchanged
local function gain(source, exp, rawExp)
	for _, cb in ipairs(chain) do
		exp = cb.fn(player, source, exp, rawExp) or exp
	end
	return exp
end

-- a plain kill: raw 1000, stage 5, potion x2 before the chain (base player.lua) -> enters at 10000
local m = monster(0)
local out = gain(m, 10000, 1000)
eq(out, 20000, "~55x of bonuses capped at 4 x 5000")
eq(given, 20000, "the hunt tracker sees the capped value")
-- the admin double_exp event counts under the cap
adminOn = true
eq(gain(m, 10000, 1000), 20000, "admin double_exp: still capped")
adminOn = false
-- a monster of level 200 (x6) and a legendary tier (x10): those are the kill, not bonuses
tierOf[m] = "legendary"
m.getMonsterLevel = function() return 200 end
eq(gain(m, 1000 * 6 * STAGE, 1000), 1000 * 6 * STAGE * 10 * 4, "level and tier are in the base")
tierOf[m] = nil
-- the dungeon difficulty multiplies after the cap
dungeonMult = 5
m = monster(0)
eq(gain(m, 5000, 1000), 20000 * 5, "the dungeon difficulty runs after the cap")
dungeonMult = 1
-- below the cap: untouched (the chain without the index-0 bonuses)
local saved = chain
chain = {}
for _, cb in ipairs(saved) do
	if cb.index ~= 0 then
		chain[#chain + 1] = cb
	end
end
eq(gain(m, 5000, 1000), 5000, "no bonus: unchanged")
eq(gain(m, 19999, 1000), 19999, "just below the cap: unchanged")
-- no rawExp: the experience as it entered the chain stands in
eq(gain(m, 5000, nil), 5000, "no rawExp, no bonus: unchanged")
chain = saved
eq(gain(m, 5000, nil), 20000, "no rawExp: 4 x the entering experience")
-- a player source (PvP) is not touched
local pvp = {isMonster = function() return false end}
ok(gain(pvp, 5000, 1000) > 20000, "not a monster: no cap")
-- disabled
ChaosXpCapConfig.enabled = false
ok(gain(m, 10000, 1000) > 20000, "disabled: no cap")
ChaosXpCapConfig.enabled = true

print(string.format("xpcap_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
