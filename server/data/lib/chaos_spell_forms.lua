-- ChaosSpellForms: the read API of the spell Forms (O686 phase 4) for every Lua state (the spell scripts, the revscripts, the
-- probes). The Form table is data/spells/forms.csv; a character's picks are bits 5-8 of the packed state of the spell
-- (data/lib/chaos_spell_ranks.lua, docs/SPELL_UPGRADES.md 7.1). Everything answers "no Form" while spell_ranks_config.lua `enabled` is
-- false, below the rank of the tier (10 / 20) and for a spell with no pick. The writer (picks, change price, the hit hooks) is
-- data/scripts/chaos/spell_forms.lua; the rules are spell_forms_core.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosSpellFormsCore or not ChaosSpellFormsCore.plan then
	dofile("data/scripts/chaos/spell_forms_core.lua")
end
if not ChaosSpellRanksCore or not ChaosSpellRanksCore.power then
	dofile("data/scripts/chaos/spell_ranks_core.lua")
end
if not ChaosSpellRanksConfig then
	ChaosSpellRanksConfig = dofile("data/scripts/chaos/spell_ranks_config.lua")
end

ChaosSpellForms = ChaosSpellForms or {}
local M = ChaosSpellForms
local F = ChaosSpellFormsCore
local P = ChaosSpellRanksCore

local function cfg()
	return ChaosSpellRanksConfig
end

-- ---------------------------------------------------------------- the table (forms.csv)
-- one CSV line into fields (quotes allowed)
local function fields(line)
	local out, i, n = {}, 1, #line
	while i <= n + 1 do
		local c = line:sub(i, i)
		if c == '"' then
			local j, buf = i + 1, {}
			while j <= n do
				local d = line:sub(j, j)
				if d == '"' then
					if line:sub(j + 1, j + 1) == '"' then
						buf[#buf + 1] = '"'
						j = j + 2
					else
						break
					end
				else
					buf[#buf + 1] = d
					j = j + 1
				end
			end
			out[#out + 1] = table.concat(buf)
			i = j + 2
		else
			local j = line:find(",", i, true) or (n + 1)
			out[#out + 1] = line:sub(i, j - 1)
			i = j + 1
		end
	end
	return out
end
M.fields = fields

-- the text of forms.csv -> {[spell id] = {id, name, heal, element, [1] = {[1] = row, [2] = row}, [2] = {...}}}, or nil and a message
function M.parse(text)
	local rows, header = {}, nil
	for line in tostring(text or ""):gmatch("[^\r\n]+") do
		local f = fields(line)
		if not header then
			header = {}
			for i, name in ipairs(f) do
				header[name] = i
			end
			for _, need in ipairs({"id", "spell", "tier", "pick", "role", "element", "kind", "over", "name_en", "name_pt"}) do
				if not header[need] then
					return nil, "forms.csv: no column " .. need
				end
			end
		else
			local r = {}
			for name, i in pairs(header) do
				r[name] = f[i]
			end
			local id = tonumber(r.id)
			local tier = r.tier == "II" and 2 or (r.tier == "I" and 1 or nil)
			local pick = tonumber(r.pick)
			if not id or not tier or (pick ~= 1 and pick ~= 2) then
				return nil, "forms.csv: bad row " .. line
			end
			local s = rows[id]
			if not s then
				s = {id = id, name = r.spell, heal = r.role == "heal", element = (r.element ~= "" and r.element) or nil, [1] = {}, [2] = {}}
				rows[id] = s
			end
			local spec = F.specOf(r)
			spec.nameEn, spec.namePt, spec.row = r.name_en, r.name_pt, r
			s[tier][pick] = spec
		end
	end
	return rows
end

function M.table()
	if M.rows == nil then
		M.rows = false
		local f = io and io.open and io.open("data/spells/forms.csv", "r")
		if f then
			local text = f:read("*a")
			f:close()
			local rows = M.parse(text)
			M.rows = rows or false
		end
	end
	return M.rows or {}
end

-- for tests: install a table
function M.setTable(rows)
	M.rows = rows or false
end

function M.entry(spellId)
	return M.table()[tonumber(spellId) or -1]
end

function M.element(spellId)
	local e = M.entry(spellId)
	return e and e.element or nil
end

-- ---------------------------------------------------------------- the character's picks
local function enabled()
	return cfg().enabled == true
end
M.enabled = enabled

-- rank, Form I pick, Form II pick of a spell for a player
function M.state(player, spellId)
	spellId = tonumber(spellId)
	local st = cfg().storage
	if not player or not spellId or spellId < 0 or spellId > st.maxSpellId then
		return 0, 0, 0
	end
	local rank, f1, f2 = P.unpack(player:getStorageValue(st.rankBase + spellId))
	return math.min(rank, cfg().maxRank), f1, f2
end

-- the Forms that act now: a list of specs (Form I then Form II); empty while the switch is off, below the rank, with no pick
function M.active(player, spellId)
	local out = {}
	if not enabled() then
		return out
	end
	local e = M.entry(spellId)
	if not e then
		return out
	end
	local rank, f1, f2 = M.state(player, spellId)
	local fc = cfg().forms
	if rank >= fc.rank1 and f1 >= 1 and e[1][f1] then
		out[#out + 1] = e[1][f1]
		if rank >= fc.rank2 and f2 >= 1 and e[2][f2] then
			out[#out + 1] = e[2][f2]
		end
	end
	return out
end

-- does the player hold a Form that acts on any spell? (cheap: false while off)
function M.any(player)
	if not enabled() then
		return false
	end
	local rows = M.table()
	for id in pairs(rows) do
		local rank, f1 = M.state(player, id)
		if rank >= cfg().forms.rank1 and f1 >= 1 then
			return true
		end
	end
	return false
end

-- resistances of a monster by element: a function element -> percent (0 for a player, a creature with no list)
local resCache = {}
function M.resistFn(creature)
	if not creature or not creature.isMonster or not creature:isMonster() then
		return function() return 0 end
	end
	local chaos = rawget(_G, "Chaos")
	local name = tostring(chaos and chaos.monsterTypeName and chaos.monsterTypeName(creature) or creature:getName()):lower()
	local r = resCache[name]
	if r == nil then
		r = false
		local ok, list = pcall(function()
			local t = creature:getType()
			return t and t:getElementList()
		end)
		if ok and type(list) == "table" then
			r = list
		end
		resCache[name] = r
	end
	return function(el)
		local ct = M.combatTypes[el] and rawget(_G, M.combatTypes[el])
		return r and ct and r[ct] or 0
	end
end

-- the resistances ASCEND:weakest reads at the effects of a cast: those of the player's target (the probe sets its own)
M.resistOf = M.resistOf or function(player)
	local target = player and player.getTarget and player:getTarget()
	return M.resistFn(target)
end

-- the element a spell's hits take with its Forms: the conversion of the last Form that has one, else nil (no change)
function M.conversion(specs, resist)
	local el
	for _, spec in ipairs(specs) do
		if spec.kind == "SHIFT" or spec.kind == "ASCEND" then
			el = spec.element
			if el == "weakest" then
				el = F.weakest(resist)
			end
		end
	end
	return el
end

-- ---------------------------------------------------------------- effects (design 2.3: a conversion sends effects of E only)
-- the effect a spell's own sends become under a conversion: ChaosVfx names tagged E in spell_fx_elements.csv, by element. A list: the
-- first one the live client pair has (a pack's ids file is only loaded while its pair is live)
M.swapNames = {
	physical = {"earth_spikes", "p50_dust_burst_with_spark_4426", "donor_physical_hit_209"},
	fire = {"fire_explosion", "blast_fire3", "donor_fire_hit_465"},
	ice = {"frost_bastion", "blast_ice", "mfx_ice"},
	energy = {"blast_lightning", "donor_energy_hit_233", "lf_bolt_a", "big_shock_lightning_7"},
	earth = {"blast_poison", "donor_earth_field_505", "big_nova_poison_7", "mega_venom_wasps"},
	holy = {"holy_hit", "dome_blast_holy", "p50_gold_spark_4467"},
	death = {"shadow_eruption", "bone_burst", "p50_purple_spark_4575"},
}
-- the Form's own effects (extra hits, grounds, bursts, statuses) by element and role: ChaosVfx or ChaosFx names tagged E, first one live
M.fxNames = {
	physical = {hit = {"earth_spikes"}, burst = {"ground_slam"}, ground = {"earth_spikes"}, status = {"blood_splash"}},
	fire = {hit = {"fire_explosion"}, burst = {"fire_nova"}, ground = {"fire_nova"}, status = {"fire_nova"}},
	ice = {hit = {"frost_bastion"}, burst = {"frost_burst"}, ground = {"frost_ripple"}, status = {"ice_crystal"}},
	energy = {hit = {"blast_lightning", "donor_energy_hit_233", "lf_bolt_a", "big_shock_lightning_7"}},
	earth = {hit = {"blast_poison", "donor_earth_field_505", "big_nova_poison_7"}, burst = {"poison_burst"}, ground = {"poison_ring"},
		status = {"poison_flame"}},
	holy = {hit = {"holy_hit"}, burst = {"holy_smite"}, ground = {"holy_spiral"}, status = {"holy_spiral"}},
	death = {hit = {"shadow_eruption"}, burst = {"blood_nova"}, ground = {"blood_nova"}, status = {"blood_nova"}},
}
-- the missile of a Form's jump (chain, seek, spread), by element
M.missiles = {
	physical = "CONST_ANI_THROWINGKNIFE", fire = "CONST_ANI_FIRE", ice = "CONST_ANI_ICE", energy = "CONST_ANI_ENERGY",
	earth = "CONST_ANI_EARTH", holy = "CONST_ANI_HOLY", death = "CONST_ANI_DEATH",
}
-- the combat type of an element (set by the engine file when it needs it; the names are the engine's constants)
M.combatTypes = {
	physical = "COMBAT_PHYSICALDAMAGE", fire = "COMBAT_FIREDAMAGE", ice = "COMBAT_ICEDAMAGE", energy = "COMBAT_ENERGYDAMAGE",
	earth = "COMBAT_EARTHDAMAGE", holy = "COMBAT_HOLYDAMAGE", death = "COMBAT_DEATHDAMAGE",
}

local function loadFxLibs()
	if M.fxLoaded then
		return
	end
	M.fxLoaded = true
	if not rawget(_G, "ChaosVfx") then
		pcall(dofile, "data/lib/chaos_vfx.lua")
	end
end

-- the first name of a list the live pair has: its name and where it lives ("vfx" ChaosVfx, "fx" ChaosFx), or nil
local function resolve(list)
	local V, fx = rawget(_G, "ChaosVfx"), rawget(_G, "ChaosFx")
	for _, name in ipairs(list or {}) do
		if V and V[name] then
			return name, "vfx"
		end
		if fx and fx[name] then
			return name, "fx"
		end
	end
	return nil
end
M.resolve = resolve

-- send the effect of an element and role at a position. Names the pair lacks send nothing.
function M.sendFx(pos, element, role)
	loadFxLibs()
	local names = M.fxNames[element or "physical"] or M.fxNames.physical
	local list = names[role or "hit"] or names.hit or M.swapNames[element or "physical"]
	local name, where = resolve(list)
	if not name then
		return false
	end
	if where == "vfx" and rawget(_G, "Vfx") and Vfx(pos, name, true) then
		return true
	end
	local fx = rawget(_G, "ChaosFx")
	if fx and fx[name] and pos and pos.sendMagicEffect then
		pos:sendMagicEffect(fx[name])
		return true
	end
	return false
end

-- the spell side's layer (data/spells/chaos/_common.lua pass()): while player `pid` casts `spellId` with a conversion Form, every
-- effect name of the spell becomes the element's name, so the cast sends effects of that element only. nil: no swap.
function M.swapFor(pid, spellId, kind, name)
	if not enabled() or type(name) ~= "string" or not rawget(_G, "Player") or kind == "missile" or kind == "dir" then
		return nil
	end
	local player = Player(pid)
	if not player then
		return nil
	end
	local specs = M.active(player, spellId)
	if #specs == 0 then
		return nil
	end
	local el = M.conversion(specs, M.resistOf and M.resistOf(player) or nil)
	if not el then
		return nil
	end
	loadFxLibs()
	local alt = resolve(M.swapNames[el])
	local V = rawget(_G, "ChaosVfx")
	if alt and V and V[alt] and alt ~= name then
		return alt
	end
	return nil
end

-- the conversion element of the cast running now (the spell side's context), nil when none
function M.castConversion(creature)
	if not enabled() then
		return nil
	end
	local W = rawget(_G, "ChaosSupportsSpell")
	if not W or not W.cast or not rawget(_G, "Player") then
		return nil
	end
	local pid, spellId = W.cast()
	if not pid then
		return nil
	end
	local player = Player(pid)
	if not player then
		return nil
	end
	local specs = M.active(player, spellId)
	if #specs == 0 then
		return nil
	end
	return M.conversion(specs, M.resistOf and M.resistOf(player) or nil)
end

-- the stock effect id of an element for the plain Fx() path (ChaosFx names tagged with the element; energy has no plain one)
M.plainFx = {physical = "shockwave", fire = "fire_nova", ice = "frost_burst", earth = "poison_burst", holy = "holy_spiral", death = "blood_nova"}

function M.plainFxId(el)
	local name = el and M.plainFx[el]
	local fx = rawget(_G, "ChaosFx")
	if name and fx and fx[name] then
		return fx[name]
	end
	if el == "energy" then
		local V = rawget(_G, "ChaosVfx")
		local e = V and V.donor_energy_hit_233
		if e and e.dx == 0 and e.dy == 0 then
			return e.id
		end
	end
	return nil
end

-- wrap Combat:setParameter / Combat:execute once (the spell state): while a conversion Form's cast runs, the combat's own area effect and
-- missile are those of the element, and the element's effect is sent on the target
function M.installCombat()
	local C = rawget(_G, "Combat")
	if M.combatInstalled or type(C) ~= "table" or type(C.execute) ~= "function" or type(C.setParameter) ~= "function" then
		return false
	end
	M.combatInstalled = true
	local params = setmetatable({}, {__mode = "k"})
	local rawSet, rawExec = C.setParameter, C.execute
	C.setParameter = function(self, key, value)
		local p = params[self]
		if not p then
			p = {}
			params[self] = p
		end
		if key ~= nil then -- O686 phase 8: a stock monster spell passes a constant this engine lacks (nil): the engine's own call takes it, a table does not
			p[key] = value
		end
		return rawSet(self, key, value)
	end
	C.execute = function(self, creature, variant)
		local el = M.castConversion(creature)
		-- O711: an awakened cast (client pair 76) sends the kit effect and projectile (data/lib/chaos_awakened_look.lua), nil otherwise
		local AL = rawget(_G, "ChaosAwakenedLook")
		local look = AL and AL.forCast and AL.forCast()
		if not el and not look then
			return rawExec(self, creature, variant)
		end
		local p = params[self] or {}
		local effectKey, aniKey = rawget(_G, "COMBAT_PARAM_EFFECT"), rawget(_G, "COMBAT_PARAM_DISTANCEEFFECT")
		if effectKey then
			rawSet(self, effectKey, rawget(_G, "CONST_ME_NONE") or 0)
		end
		local ani = look and look.missile or rawget(_G, el and M.missiles[el] or "")
		if aniKey and p[aniKey] and ani then
			rawSet(self, aniKey, ani)
		end
		local ok, res = pcall(rawExec, self, creature, variant)
		if effectKey and p[effectKey] ~= nil then
			rawSet(self, effectKey, p[effectKey])
		end
		if aniKey and p[aniKey] ~= nil then
			rawSet(self, aniKey, p[aniKey])
		end
		if not ok then
			error(res, 0)
		end
		if res then
			local pos
			if type(variant) == "table" then
				pos = variant.pos
				if not pos and variant.number and variant.number > 0 and rawget(_G, "Creature") then
					local c = Creature(variant.number)
					pos = c and c:getPosition()
				end
			end
			pos = pos or (creature and creature:getPosition())
			if pos and look then
				look.send(pos)
			elseif pos then
				M.sendFx(pos, el, "hit")
			end
		end
		return res
	end
	return true
end

-- what the probe runs after the spell's own cast: the effects the Forms of the spell send themselves (tools/ci/spell_fx_probe.lua)
function M.fxProbe(player, spellId, pos)
	local specs = M.active(player, spellId)
	local el = M.conversion(specs, M.resistOf and M.resistOf(player) or nil) or M.element(spellId) or "physical"
	for _, spec in ipairs(specs) do
		local roles = {hit = true}
		if spec.kind == "GROUND" or spec.kind == "SANCTUARY" then
			roles.ground = true
		elseif spec.kind == "SHIFT" or spec.kind == "ASCEND" or spec.kind == "REND" or spec.kind == "SPREAD" then
			roles.status = true
		elseif spec.kind == "AFTERMATH" or spec.kind == "DELAY" or spec.kind == "OVERCHARGE" then
			roles.burst = true
		end
		for role in pairs(roles) do
			M.sendFx(pos, el, role)
		end
	end
end

return M
