-- founder.lua: the Founder Pack's name plate title (O322). Rules: founder_core.lua; data: founder_config.lua; the sale itself is
-- the store (shop.lua: a bundle per tier with a sale window, one per account) and the pieces are exclusives
-- (exclusives.lua, source "founder"). Overview: server/README.md "Founder Pack".
--
-- The title is held while the account owns the tier's first exclusive, which only the pack gives, so it needs no table of
-- its own and survives a reload. The Grand Founder Pack also brings the plate frame `founder` (an exclusive of kind frame).
-- titles.lua builds its tables when it loads (possibly after this file): the source is put in at load, at startup and at every
-- login. Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosFounderCore then
	dofile("data/scripts/chaos/founder_core.lua")
end

ChaosFounderConfig = dofile("data/scripts/chaos/founder_config.lua")
ChaosFounder = ChaosFounder or {}
local M = ChaosFounder
local F = ChaosFounderCore
local cfg = ChaosFounderConfig
M.core, M.config = F, cfg

local function source(player)
	local X = ChaosExclusives
	if not (X and X.owns) then
		return nil
	end
	local accountId = player:getAccountId()
	local out = F.titles(cfg, function(key)
		return X.owns(accountId, key)
	end)
	return #out > 0 and out or nil
end
M.titleSource = source

function M.ensureHooks()
	if ChaosTitles and ChaosTitles.register then
		ChaosTitles.register("founder", source)
	end
end
M.ensureHooks()

local login = CreatureEvent("ChaosFounderLogin")
function login.onLogin(player)
	M.ensureHooks()
	return true
end
login:register()

local startup = GlobalEvent("ChaosFounderStartup")
function startup.onStartup()
	M.ensureHooks()
	local okX, exclusives = pcall(dofile, "data/scripts/chaos/exclusives_config.lua")
	local okP, pact = pcall(dofile, "data/scripts/chaos/pact_config.lua")
	local limits = dofile("data/scripts/chaos/store_balance_config.lua").founder
	for _, p in ipairs(F.validate(cfg, {exclusives = okX and exclusives or nil, limits = limits,
		pactPrice = okP and pact.store.pact.offers[1].cost or nil})) do
		print("[Warning - Chaos founder] " .. p)
	end
	return true
end
startup:register()
