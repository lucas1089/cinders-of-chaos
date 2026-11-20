-- Spell awakening, the pure rules (O686 phase 7; docs/SPELL_UPGRADES.md section 3; server/README.md "Spell awakening (O686 phase 7)").
-- No engine call here: the Seal counters and what each source gives, the slot costs, the awaken decision with its refusal reasons, the dormant
-- slots, the awakened.csv table (parse and checks), the signature kinds and what each plans for a cast, and the value model (how much of
-- the spell's damage a signature adds). Numbers: spell_awakening_config.lua; the engine: spell_awakening.lua; tests:
-- server/tests/spell_awakening_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- A signature is one or more parts joined by `+` in the `kind` column of data/spells/awakened.csv. Each part is a shape of effect with its
-- own numbers, written as `PART.key=number` in the `over` column:
--   PULSE   a ring that stays and pulses: pulses, pct (of the cast's hit, per target), secs (it lasts), minHit (enemies a pulse must hit to
--           return mana), mana (share of max mana), radius (sqm). On a heal spell it heals the allies in it.
--   LINE    a line of len sqm from the caster through the target hits every enemy in it for pct of the cast's hit
--   MARK    marks every enemy the cast hit for secs; the next single target spell of the player on a marked enemy hits pct harder, once
--   RINGS   rings of the cast's own area one after another: rings, pct each, around the caster for an around spell, else the target
--   ECHO    the cast's hits again after delay ms for pct
--   SHIELD  a shield of pct of max health for secs on the caster (a heal spell: on each ally it healed); a damage spell needs minHit enemies hit
--   CDCUT   each kill within window s of the cast cuts cut s of the spell's cooldown, at most cap s in all
--   LEECH   the caster is healed pct of the damage the cast dealt
--   REFLECT a heal reflected to every ally within radius sqm of the healed one for pct
-- Damage kinds are PULSE LINE MARK RINGS ECHO SHIELD CDCUT LEECH; heal kinds PULSE REFLECT SHIELD ECHO CDCUT.

ChaosSpellAwakeningCore = ChaosSpellAwakeningCore or {}
local A = ChaosSpellAwakeningCore
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local function num(v, default)
	v = tonumber(v)
	if not v or v ~= v then
		return default
	end
	return v
end

A.damageKinds = {"PULSE", "LINE", "MARK", "RINGS", "ECHO", "SHIELD", "CDCUT", "LEECH"}
A.healKinds = {"PULSE", "REFLECT", "SHIELD", "ECHO", "CDCUT"}
-- the parts that deal damage or heal (capped together), the parts that are utility (counted by `worth`)
A.outputKinds = {PULSE = true, LINE = true, RINGS = true, ECHO = true, REFLECT = true}

-- the numbers of each part with their defaults (the legal keys of `over`)
A.numbers = {
	PULSE = {pulses = 3, pct = 0.4, secs = 6, minHit = 3, mana = 0.03, radius = 3},
	LINE = {len = 6, pct = 1.0},
	MARK = {secs = 6, pct = 0.5},
	RINGS = {rings = 3, pct = 0.1},
	ECHO = {pct = 0.5, delay = 1500},
	SHIELD = {pct = 0.03, secs = 4, minHit = 1},
	CDCUT = {cut = 1, window = 8, cap = 5},
	LEECH = {pct = 0.1},
	REFLECT = {pct = 0.5, radius = 4},
}

local function legal(list, kind)
	for _, k in ipairs(list) do
		if k == kind then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------- the Seals
-- Seals a source gives one character. waystone info: {tier, first}; rift info: {tier (the shown tier), climbed}; pinnacle: {}
function A.gain(cfg, source, info)
	info = info or {}
	local s = cfg.sources[source]
	if not s then
		return 0
	end
	if source == "waystone" then
		if num(info.tier, 0) < s.minTier then
			return 0
		end
		return s.perClear + (info.first and s.firstClear or 0)
	elseif source == "rift" then
		if num(info.tier, 0) < s.minTier then
			return 0
		end
		return s.perRun + (info.climbed and s.climb or 0)
	elseif source == "pinnacle" then
		return s.perKill
	end
	return 0
end

-- a held count after adding n, held at 0..cap
function A.add(held, n, cap)
	return max(0, min(cap, floor(num(held, 0)) + floor(num(n, 0))))
end

-- the cost of slot 1..maxSlots, {waystone, rift, pinnacle}
function A.slotCost(cfg, slot)
	local s = cfg.slots[floor(num(slot, 0))]
	if not s then
		return nil
	end
	return {waystone = s.waystone, rift = s.rift, pinnacle = s.pinnacle}
end

-- hours of the ideal top content of slot 1..3 (design 3.2): waystone / clears an hour + rift / runs an hour; the Pinnacle Seals come along
function A.hours(cfg, slot)
	local s = cfg.slots[slot]
	return s.waystone / cfg.rates.waystonePerHour + s.rift / cfg.rates.riftPerHour
end

-- hours the Pinnacle Seals of a slot take at the rate of kills
function A.pinnacleHours(cfg, slot)
	return cfg.slots[slot].pinnacle / cfg.rates.pinnacleSealsPerHour
end

-- ---------------------------------------------------------------- the slots
-- the lowest free slot of `slots` (a list of spell ids, 0 or nil for a free one), nil when all are taken
function A.freeSlot(cfg, slots)
	for i = 1, cfg.maxSlots do
		if not slots[i] or slots[i] == 0 then
			return i
		end
	end
	return nil
end

function A.held(cfg, slots)
	local n = 0
	for i = 1, cfg.maxSlots do
		if slots[i] and slots[i] > 0 then
			n = n + 1
		end
	end
	return n
end

-- the slots to free: the awakened spell the character no longer knows is dormant and gives its slot back at once (design 1.6); the Seals
-- spent are not returned. known: set of spell ids the character has learned. Returns a list of {slot, spell}
function A.dormantSlots(cfg, slots, known)
	local out = {}
	for i = 1, cfg.maxSlots do
		local id = slots[i]
		if id and id > 0 and not known[id] then
			out[#out + 1] = {slot = i, spell = id}
		end
	end
	return out
end

-- ---------------------------------------------------------------- the decision
-- st: {on, entry (the spell has a row in awakened.csv), known, rank, f1, f2 (the Form picks, 0 = none), awakened (bit 9), slots, seals = {waystone, rift, pinnacle}}
-- slot: the slot asked for (nil: the lowest free one). Returns {ok, why, slot, cost, need} with why in
-- off | spell | unknown | rank | forms | already | slot | seals | ok
function A.decide(cfg, rankMax, st, slot)
	if not st.on then
		return {ok = false, why = "off"}
	end
	if not st.entry then
		return {ok = false, why = "spell"}
	end
	if not st.known then
		return {ok = false, why = "unknown"}
	end
	if num(st.rank, 0) < rankMax then
		return {ok = false, why = "rank", rank = st.rank, need = rankMax}
	end
	if num(st.f1, 0) == 0 or num(st.f2, 0) == 0 then
		return {ok = false, why = "forms"}
	end
	if st.awakened then
		return {ok = false, why = "already"}
	end
	local free = A.freeSlot(cfg, st.slots or {})
	if not free then
		return {ok = false, why = "slot"}
	end
	slot = slot and floor(num(slot, 0)) or free
	if slot ~= free then
		return {ok = false, why = "slot", slot = free}
	end
	local cost = A.slotCost(cfg, slot)
	local need = {}
	local short = false
	for _, key in ipairs({"waystone", "rift", "pinnacle"}) do
		local have = num((st.seals or {})[key], 0)
		if have < cost[key] then
			need[key] = cost[key] - have
			short = true
		end
	end
	if short then
		return {ok = false, why = "seals", slot = slot, cost = cost, need = need}
	end
	return {ok = true, why = "ok", slot = slot, cost = cost}
end

-- the Seals left after paying a cost
function A.pay(seals, cost)
	return {waystone = seals.waystone - cost.waystone, rift = seals.rift - cost.rift, pinnacle = seals.pinnacle - cost.pinnacle}
end

-- the factor of an awakened spell's hit or heal: 1 + bonus; against a player at the PvP share of the rank (spell_ranks_config.lua pvp.rank)
function A.factor(cfg, pvp, pvpShare)
	if pvp then
		return 1 + cfg.bonus * num(pvpShare, 0.5)
	end
	return 1 + cfg.bonus
end

-- ---------------------------------------------------------------- awakened.csv
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
A.fields = fields

-- "LINE.len=6;MARK.pct=0.5" -> {LINE = {len = 6}, MARK = {pct = 0.5}}, or nil and a message
function A.parseOver(text)
	local out = {}
	if text == nil or text == "" then
		return out
	end
	for item in tostring(text):gmatch("[^;]+") do
		local part, key, val = item:match("^(%u+)%.(%w+)=(-?[%d.]+)$")
		if not part then
			return nil, "bad override " .. item
		end
		out[part] = out[part] or {}
		out[part][key] = tonumber(val)
	end
	return out
end

-- the parts of a kind text with their numbers: {{kind = "LINE", n = {len = 6, pct = 1.0}}, ...}, or nil and a message
function A.parts(kindText, over)
	local parts = {}
	for kind in tostring(kindText):gmatch("[^+]+") do
		local base = A.numbers[kind]
		if not base then
			return nil, "unknown kind " .. kind
		end
		local n = {}
		for k, v in pairs(base) do
			n[k] = v
		end
		for k, v in pairs(over[kind] or {}) do
			if n[k] == nil then
				return nil, kind .. " has no number " .. k
			end
			n[k] = v
		end
		parts[#parts + 1] = {kind = kind, n = n}
	end
	for part in pairs(over) do
		local found = false
		for _, p in ipairs(parts) do
			found = found or p.kind == part
		end
		if not found then
			return nil, "override of " .. part .. " which the kind does not have"
		end
	end
	return parts
end

-- the text of awakened.csv -> {[spell id] = spec}, or nil and a message. spec: {id, spell, heal, element, shape, cooldownMs, kind, parts, nameEn, namePt}
function A.parse(text)
	local rows, header = {}, nil
	for line in tostring(text or ""):gmatch("[^\r\n]+") do
		local f = fields(line)
		if not header then
			header = {}
			for i, name in ipairs(f) do
				header[name] = i
			end
			for _, need in ipairs({"id", "spell", "role", "element", "shape", "cooldown", "kind", "over", "name_en", "name_pt"}) do
				if not header[need] then
					return nil, "awakened.csv: no column " .. need
				end
			end
		else
			local r = {}
			for name, i in pairs(header) do
				r[name] = f[i] or ""
			end
			local id = tonumber(r.id)
			if not id or rows[id] then
				return nil, "awakened.csv: bad or repeated id in " .. line
			end
			local over, err = A.parseOver(r.over)
			if not over then
				return nil, "awakened.csv " .. r.id .. ": " .. err
			end
			local parts, perr = A.parts(r.kind, over)
			if not parts then
				return nil, "awakened.csv " .. r.id .. ": " .. perr
			end
			rows[id] = {id = id, spell = r.spell, heal = r.role == "heal", element = r.element ~= "" and r.element or nil, shape = r.shape,
				cooldownMs = floor(num(r.cooldown, 0) * 1000), kind = r.kind, parts = parts, nameEn = r.name_en, namePt = r.name_pt}
		end
	end
	return rows
end

-- ---------------------------------------------------------------- the value model
local function typicalTargets(cfg, spec)
	if spec.heal then
		return 1
	end
	return cfg.signature.targets[spec.shape] or 1
end

-- {output, utility}: the damage or heal the parts deal as a share of the cast's own, and the utility counted in damage
function A.raw(spec, cfg)
	local sg = cfg.signature
	local T = typicalTargets(cfg, spec)
	local out, util = 0, 0
	for _, p in ipairs(spec.parts) do
		local k, n = p.kind, p.n
		if k == "PULSE" then
			if spec.heal then
				out = out + n.pulses * n.pct * sg.allies
			else
				out = out + n.pulses * n.pct * max(T, sg.ringReach) / T
			end
		elseif k == "LINE" then
			out = out + n.pct * min(sg.lineReach, n.len * sg.lineDensity) / T
		elseif k == "RINGS" then
			out = out + n.rings * n.pct
		elseif k == "ECHO" then
			out = out + n.pct
		elseif k == "REFLECT" then
			out = out + n.pct * sg.allies
		elseif k == "MARK" then
			util = util + n.pct * sg.worth.markShare * sg.worth.mark
		elseif k == "SHIELD" then
			util = util + n.pct * sg.worth.shield
		elseif k == "CDCUT" then
			local cd = max(1, spec.cooldownMs / 1000)
			util = util + min(n.cap, n.cut * sg.kills) / cd * sg.worth.cooldown
		elseif k == "LEECH" then
			util = util + n.pct * sg.worth.leech
		end
	end
	return out, util
end

-- the share of the spell's own damage the signature adds on a typical cast
function A.value(spec, cfg)
	local sg = cfg.signature
	local out, util = A.raw(spec, cfg)
	return min(out, sg.capShare) * sg.use + util
end

-- ---------------------------------------------------------------- the checks
-- the problems of a parsed table against the config (empty when sound). names: also check against `known` (set of spell ids of forms.csv)
function A.problems(rows, cfg, known)
	local bad = {}
	local names, namesPt = {}, {}
	local ids = {}
	for id in pairs(rows) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local s = rows[id]
		local what = string.format("%d %s", id, tostring(s.spell))
		local legalList = s.heal and A.healKinds or A.damageKinds
		local seen = {}
		for _, p in ipairs(s.parts) do
			if not legal(legalList, p.kind) then
				bad[#bad + 1] = what .. ": " .. p.kind .. " is not a " .. (s.heal and "heal" or "damage") .. " kind"
			end
			if seen[p.kind] then
				bad[#bad + 1] = what .. ": " .. p.kind .. " twice"
			end
			seen[p.kind] = true
		end
		if s.nameEn == "" or s.namePt == "" then
			bad[#bad + 1] = what .. ": a name in both languages is required"
		end
		if names[s.nameEn] then
			bad[#bad + 1] = what .. ": the name " .. s.nameEn .. " is used twice"
		end
		if namesPt[s.namePt] then
			bad[#bad + 1] = what .. ": the pt-BR name " .. s.namePt .. " is used twice"
		end
		names[s.nameEn], namesPt[s.namePt] = true, true
		if s.nameEn == s.spell then
			bad[#bad + 1] = what .. ": the awakened name must differ from the spell's"
		end
		if not cfg.signature.targets[s.shape] then
			bad[#bad + 1] = what .. ": shape " .. tostring(s.shape)
		end
		local v = A.value(s, cfg)
		local band = cfg.signature.band
		if v < band.min - 1e-9 or v > band.max + 1e-9 then
			bad[#bad + 1] = string.format("%s: the signature is worth %.1f%% of the spell, the band is %.0f%% to %.0f%%", what, v * 100,
				band.min * 100, band.max * 100)
		end
		for _, p in ipairs(s.parts) do
			if p.kind == "SHIELD" and p.n.pct > cfg.signature.shieldMax + 1e-9 then
				bad[#bad + 1] = what .. ": a shield over " .. cfg.signature.shieldMax * 100 .. "% of max health"
			end
			if p.kind == "MARK" and p.n.secs > cfg.signature.markMaxSecs then
				bad[#bad + 1] = what .. ": a mark over " .. cfg.signature.markMaxSecs .. " s"
			end
		end
		if known and not known[id] then
			bad[#bad + 1] = what .. ": not a spell of forms.csv"
		end
	end
	if known then
		for id in pairs(known) do
			if not rows[id] then
				bad[#bad + 1] = tostring(id) .. ": a spell with Forms has no awakened row"
			end
		end
	end
	return bad
end

-- the problems of the config itself
function A.check(cfg)
	local bad = {}
	if cfg.maxSlots ~= #cfg.slots then
		bad[#bad + 1] = "maxSlots and the slot table differ"
	end
	local prev
	for i, s in ipairs(cfg.slots) do
		if prev and (s.waystone <= prev.waystone or s.rift <= prev.rift or s.pinnacle <= prev.pinnacle) then
			bad[#bad + 1] = "slot " .. i .. " does not cost more than slot " .. (i - 1)
		end
		prev = s
	end
	for i, h in ipairs(cfg.hours) do
		local d = A.hours(cfg, i)
		if abs(d - h) > 0.1 then
			bad[#bad + 1] = string.format("slot %d takes %.1f hours of the ideal top content, the table says %s", i, d, tostring(h))
		end
	end
	if cfg.bonus <= 0 or cfg.signature.band.min >= cfg.signature.band.max then
		bad[#bad + 1] = "bonus or band"
	end
	return bad
end

-- ---------------------------------------------------------------- the signature of one cast
-- cast: {heal, pvp, spellId, base (the cast's mean hit or heal), total (the cast's own damage or heal in all), main = {id, pos},
--   caster = {id, pos}, foes = {{id, pos}} (enemies near the main target), lineFoes = {{id, pos}} (enemies in the line from the caster through
--   the main target, the main one left out), hits = {{id, pos, amount}} (what the cast hit), allies = {{id, pos, maxHealth}} (allies near the
--   healed one, the healed one left out), healed = {{id, pos, maxHealth, amount}}}
-- Returns {actions = {...}, planned, limit, scaled}: the output of all actions is held to the cap (signature.capShare of the cast's own
-- damage); nothing at all in PvP (spell_ranks_config.lua pvp.awakening = false is read by the engine, which passes cast.pvp)
function A.plan(spec, cast, cfg)
	local out = {actions = {}, planned = 0, limit = 0, scaled = 1}
	if not spec or cast.pvp then
		return out
	end
	local sg = cfg.signature
	local base = max(1, floor(num(cast.base, 0)))
	local foes = cast.foes or {}
	local nFoes = max(1, min(#foes, sg.maxTargets))
	local actions = {}
	local output = 0
	for _, p in ipairs(spec.parts) do
		local k, n = p.kind, p.n
		if k == "PULSE" then
			local amount = max(1, floor(base * n.pct))
			local targets = spec.heal and max(1, #(cast.allies or {}) + 1) or nFoes
			targets = min(targets, sg.maxTargets)
			actions[#actions + 1] = {op = "pulse", heal = spec.heal, pos = cast.main and cast.main.pos, radius = n.radius or sg.ringRadius,
				pulses = n.pulses, everyMs = floor(n.secs * 1000 / max(1, n.pulses)), amount = amount, minHit = n.minHit, mana = n.mana}
			output = output + amount * n.pulses * targets
		elseif k == "LINE" and not spec.heal then
			local list = {}
			for i, f in ipairs(cast.lineFoes or {}) do
				if i > sg.maxTargets then
					break
				end
				list[#list + 1] = f
			end
			if #list > 0 then
				local amount = max(1, floor(base * n.pct))
				actions[#actions + 1] = {op = "line", targets = list, amount = amount, len = n.len}
				output = output + amount * #list
			end
		elseif k == "MARK" and not spec.heal then
			local ids = {}
			for _, h in ipairs(cast.hits or {}) do
				ids[#ids + 1] = h.id
			end
			for _, f in ipairs(cast.lineFoes or {}) do
				ids[#ids + 1] = f.id
			end
			while #ids > sg.maxTargets do
				table.remove(ids)
			end
			if #ids > 0 then
				actions[#actions + 1] = {op = "mark", ids = ids, secs = min(n.secs, sg.markMaxSecs), pct = n.pct}
			end
		elseif k == "RINGS" and not spec.heal then
			local center = (spec.shape == "around" or spec.shape == "self") and cast.caster and cast.caster.pos or (cast.main and cast.main.pos)
			local amount = max(1, floor(base * n.pct))
			local rings = min(n.rings, sg.maxRings)
			actions[#actions + 1] = {op = "rings", pos = center, radius = sg.ringRadius, rings = rings, stepMs = 450, amount = amount}
			output = output + amount * rings * nFoes
		elseif k == "ECHO" then
			local hits = {}
			for i, h in ipairs(cast.hits or {}) do
				if i > sg.maxTargets then
					break
				end
				hits[#hits + 1] = {id = h.id, amount = max(1, floor(num(h.amount, 0) * n.pct))}
				output = output + hits[#hits].amount
			end
			if #hits > 0 then
				actions[#actions + 1] = {op = "echo", heal = spec.heal, delay = n.delay, hits = hits}
			end
		elseif k == "SHIELD" then
			local ids = {}
			if spec.heal then
				for i, h in ipairs(cast.healed or {}) do
					if i > sg.maxTargets then
						break
					end
					ids[#ids + 1] = {id = h.id, amount = max(1, floor(num(h.maxHealth, 0) * min(n.pct, sg.shieldMax)))}
				end
			elseif #(cast.hits or {}) >= n.minHit and cast.caster then
				-- the caster's maximum health is read by the engine (amount 0 = pct of it)
				ids[1] = {id = cast.caster.id, pct = min(n.pct, sg.shieldMax)}
			end
			if #ids > 0 then
				actions[#actions + 1] = {op = "shield", targets = ids, secs = n.secs}
			end
		elseif k == "CDCUT" then
			actions[#actions + 1] = {op = "cdcut", spellId = cast.spellId, window = n.window, cut = n.cut, cap = n.cap}
		elseif k == "LEECH" and not spec.heal then
			local amount = floor(num(cast.total, 0) * n.pct)
			if amount > 0 then
				actions[#actions + 1] = {op = "leech", amount = amount}
			end
		elseif k == "REFLECT" and spec.heal then
			local main = (cast.healed or {})[1]
			local amount = max(1, floor(num(main and main.amount, base) * n.pct))
			local list = {}
			for i, a in ipairs(cast.allies or {}) do
				if i > sg.maxTargets then
					break
				end
				list[#list + 1] = a
			end
			if #list > 0 then
				actions[#actions + 1] = {op = "reflect", targets = list, amount = amount, radius = n.radius}
				output = output + amount * #list
			end
		end
	end
	local limit = floor(num(cast.total, 0) * sg.capShare)
	out.planned, out.limit = output, limit
	if output > limit and output > 0 then
		local f = limit / output
		out.scaled = f
		for _, a in ipairs(actions) do
			if a.amount and a.op ~= "leech" then
				a.amount = max(1, floor(a.amount * f))
			end
			if a.hits then
				for _, h in ipairs(a.hits) do
					h.amount = max(1, floor(h.amount * f))
				end
			end
		end
	end
	out.actions = actions
	return out
end

-- the enemies on the line that leaves `from` through `through` for `len` sqm (the eight directions, as the Forms' line): foes = {{id, pos}};
-- the main target (mainId) is left out. Returns the foes in the order of the line
function A.lineFoes(from, through, len, foes, mainId)
	local dx = through.x > from.x and 1 or (through.x < from.x and -1 or 0)
	local dy = through.y > from.y and 1 or (through.y < from.y and -1 or 0)
	local out = {}
	if dx == 0 and dy == 0 then
		return out
	end
	for step = 1, floor(num(len, 0)) do
		local x, y = from.x + dx * step, from.y + dy * step
		for _, f in ipairs(foes) do
			if f.pos.x == x and f.pos.y == y and f.pos.z == from.z and f.id ~= mainId then
				out[#out + 1] = f
			end
		end
	end
	return out
end

-- the longest line of a spec (0 when it has none)
function A.lineLength(spec)
	local n = 0
	for _, p in ipairs(spec.parts) do
		if p.kind == "LINE" then
			n = max(n, p.n.len)
		end
	end
	return n
end

-- the largest radius a spec's heal parts reach around the healed one (0 when none)
function A.allyRadius(spec)
	local n = 0
	for _, p in ipairs(spec.parts) do
		if p.kind == "REFLECT" then
			n = max(n, p.n.radius)
		elseif p.kind == "PULSE" and spec.heal then
			n = max(n, p.n.radius)
		end
	end
	return n
end

-- the cooldown left after one kill in the window of a cut: `used` seconds are cut already; returns the seconds to cut now and the new total
function A.cut(cut, cap, used)
	local take = max(0, min(cut, cap - used))
	return take, used + take
end

-- the mark a hit meets: a mark {untilMs, pct}: returns the factor and whether the mark is spent. A mark is spent by the next hit of a spell that
-- may spend it (single target spells), once
function A.markFactor(mark, nowMs, singleSpell)
	if not mark or mark.untilMs < nowMs then
		return 1, mark ~= nil
	end
	if not singleSpell then
		return 1, false
	end
	return 1 + mark.pct, true
end

return A
