-- Gear coverage audit: for every class, every armour slot and every level band, the pieces the class can wear and get
-- (server/README.md "Gear coverage"; the sibling of tools/weapon_coverage.lua, which audits weapons, wands, rods and fist
-- weapons). Run from the server/ folder:
--   luajit tools/gear_coverage.lua                  the table (plain text) and the flags
--   luajit tools/gear_coverage.lua --md             the markdown tables of server/README.md
--   luajit tools/gear_coverage.lua --list SLOT [Class]  every option of a slot, by band
--   luajit tools/gear_coverage.lua --fairness       how much of the gear a band's monsters drop each class can use
--   luajit tools/gear_coverage.lua --check          exit 1 when a class has a slot with too few options in a band, or only
--                                                    weak ones, or the README tables are out of date (CI, both interpreters)
--   luajit tools/gear_coverage.lua --write          rewrite the README tables between their marker lines
-- lua5.3 gives the same output.
--
-- The data (all in the repo; the base server is read only by the survey tools):
--   data/items/base_item_values.csv    the stock equipment: slot, required level, shops, monster loot (lowest monster, best chance)
--   data/items/base_recipes.csv        the base crafting recipes (a product is crafted)
--   data/lib/chaos_gear_sets*.lua      the equipment sets of pair 28: every piece with its stats, class list and loot rows
--   data/lib/chaos_unique_items.lua    the uniques: slot, level, tier, chance (chaos_unique_specs.lua: armour, equip rule)
--   data/scripts/chaos/gamble_config.lua  the Gambler's pool: the bases he sells from their level
--   data/lib/chaos_archery_config.lua  the quivers
--   data/monster/monsters/chaos/**     the Chaos monsters' loot of stock ids
-- The stock items carry no armour value in the snapshot (the base server is not in the repo): a stock piece counts as an
-- option at its level, power unknown. A set piece or a unique is judged against the sets' armour curve of the class's weight
-- (heavy, medium, cloth) at the level of the piece. A stock piece wearable by everybody is assumed to be wearable by
-- every class (the snapshot has no vocation lists); the shield, the spellbook and the quiver have their own class groups.

WEAPON_COVERAGE_NO_MAIN = true
local W = dofile("tools/weapon_coverage.lua")
local floor = math.floor

local C = {}

local function set(list)
	local s = {}
	for _, v in ipairs(list) do
		s[v] = true
	end
	return s
end

-- ---------------------------------------------------------------------------------------------------------------
-- the tier: the sets' armour of a slot and weight at a level
-- ---------------------------------------------------------------------------------------------------------------
-- points[slot][weight] = {{level, value}} sorted, the best value at each level
local function buildCurves(G, cfg)
	local pts = {}
	local function add(slot, weight, level, value)
		pts[slot] = pts[slot] or {}
		pts[slot][weight] = pts[slot][weight] or {}
		local t = pts[slot][weight]
		for _, p in ipairs(t) do
			if p[1] == level then
				p[2] = math.max(p[2], value)
				return
			end
		end
		t[#t + 1] = {level, value}
	end
	local SLOT = {helmet = "helmet", armor = "armor", legs = "legs", boots = "boots", shield = "shield",
		spellbook = "book"}
	for _, p in ipairs(G.items.pieces) do
		local slot = SLOT[p.kind]
		if slot then
			local v = (slot == "shield" or slot == "book") and (p.stats.defense or 0) or (p.stats.armor or 0)
			local fit = p.fit or ""
			local weights = {H = {"heavy"}, M = {"medium"}, C = {"cloth"}}
			for _, w in ipairs(weights[fit] or {"heavy", "medium", "cloth"}) do
				add(slot, w, p.level, v)
			end
		end
	end
	for _, bySlot in pairs(pts) do
		for _, t in pairs(bySlot) do
			table.sort(t, function(a, b)
				return a[1] < b[1]
			end)
		end
	end
	return pts
end

function C.tier(curves, slot, weight, level)
	local t = curves[slot] and (curves[slot][weight] or curves[slot].heavy)
	if not t or #t == 0 then
		return nil
	end
	if level <= t[1][1] then
		return t[1][2]
	end
	for i = 2, #t do
		if level <= t[i][1] then
			return t[i - 1][2] + (t[i][2] - t[i - 1][2]) * (level - t[i - 1][1]) / (t[i][1] - t[i - 1][1])
		end
	end
	return t[#t][2]
end

-- ---------------------------------------------------------------------------------------------------------------
-- loading
-- ---------------------------------------------------------------------------------------------------------------
local STOCK_SLOT = {head = "helmet", body = "armor", legs = "legs", feet = "boots", shield = "shield", necklace = "amulet",
	ring = "ring"}
local UNIQUE_SLOT = {head = "helmet", body = "armor", legs = "legs", feet = "boots", shield = "shield", necklace = "amulet",
	ring = "ring"}
local SET_SLOT = {helmet = "helmet", armor = "armor", legs = "legs", boots = "boots", shield = "shield",
	spellbook = "book", amulet = "amulet", ring = "ring"}

-- The level a character hunts a monster at (the pace layer's rule, pace_core.lua P.entryLevel): a level-scaled monster at its
-- own level, a base monster at baseLevelMult x its "fair hunt" level. The snapshot of the stock loot keeps only the lowest
-- monster level of an item, without the flag, so a level up to maxBaseRaw (the highest base monster of the bounty pool) counts
-- as a base monster's.
function C.huntOfRaw(cfg, raw)
	if raw <= cfg.maxBaseRaw then
		return raw * cfg.baseLevelMult
	end
	return raw
end

-- name (lower case) -> hunting level, from the bounty pool
function C.huntPool()
	dofile("data/scripts/chaos/pace_core.lua")
	local P = ChaosPaceCore
	local pcfg = dofile("data/scripts/chaos/pace_config.lua")
	local out = {}
	for _, e in ipairs(dofile("data/scripts/chaos/bounty_pool.lua").hunt) do
		out[e.name:lower()] = (P.entryLevel(pcfg, e))
	end
	return out
end

-- the hunting level of a monster of a set's source list: the pool's, else the level the list gives (a boss or a monster of
-- its own level)
function C.huntOfName(hunt, name, given)
	return hunt[name:lower()] or given
end

-- the Chaos monsters' loot of stock ids: id -> {chance, level}, the level it is hunted at (the lowest; the best chance)
function C.chaosMonsterLoot(cfg)
	local out = {}
	local list = io.popen("cd data/monster/monsters/chaos && find . -name '*.xml' | LC_ALL=C sort")
	local paths = {}
	for path in list:lines() do
		paths[#paths + 1] = path
	end
	list:close()
	for _, path in ipairs(paths) do
		local text = W.readFile("data/monster/monsters/chaos/" .. path:gsub("^%./", ""))
		local lo, hi = text:match('<level%s+min="(%d+)"%s+max="(%d+)"')
		local level
		if lo then
			level = floor((tonumber(lo) + tonumber(hi)) / 2)
		else
			local hp = tonumber(text:match('<health%s+now="(%d+)"')) or 0
			local exp = tonumber(text:match('<monster%s[^>]*experience="(%d+)"')) or 0
			local byExp = 1.6 * math.sqrt(math.max(exp, 1))
			level = math.max(1, floor(math.max(byExp, math.min(hp / 60, byExp * 1.5)) + 0.5)) * cfg.baseLevelMult
		end
		local block = text:match("<loot>(.-)</loot>") or ""
		for tag in block:gmatch("<item%s[^>]*>") do
			local id, chance = tonumber(tag:match('%f[%w]id="(%d+)"')), tonumber(tag:match('chance="(%d+)"'))
			if id and chance then
				local e = out[id] or {chance = 0, level = level}
				e.chance = math.max(e.chance, chance)
				e.level = math.min(e.level, level)
				out[id] = e
			end
		end
	end
	return out
end

local function allClassNames(wcfg)
	local out = {}
	for _, l in ipairs(wcfg.lines) do
		for _, c in ipairs(l.classes) do
			out[#out + 1] = c.name
		end
	end
	return out
end

function C.load(cfg, wcfg)
	-- the unique specs are keyed by the engine's attribute constants: names stand in for them (as the weapon audit)
	for k, v in pairs({ATTACK = "Attack", DEFENSE = "Defense", EXTRADEFENSE = "Extra Defense", ARMOR = "Armor",
		HITCHANCE = "Hit Chance", SHOOTRANGE = "Range", ATTACK_SPEED = "Attack Speed", NAME = "Name", ARTICLE = "Article",
		DESCRIPTION = "Description"}) do
		_G["ITEM_ATTRIBUTE_" .. k] = _G["ITEM_ATTRIBUTE_" .. k] or v
	end
	local D = {items = {}, byId = {}}
	local everyone = allClassNames(wcfg)
	local lineOf = W.lineClasses(wcfg)
	local books = set(cfg.books)
	local archery = dofile("data/lib/chaos_archery_config.lua")
	local quivers = archery.quivers
	local chaosLoot = C.chaosMonsterLoot(cfg)
	local hunt = C.huntPool()
	local G = dofile("data/lib/chaos_gear_sets.lua")
	D.curves = buildCurves(G, cfg)

	-- the Gambler's pool: id -> the lowest level it is offered from
	local gamble = dofile("data/scripts/chaos/gamble_config.lua")
	local pool = {}
	for _, list in pairs(gamble.pool) do
		for _, e in ipairs(list) do
			pool[e[1]] = math.min(pool[e[1]] or 1e9, e[2])
		end
	end

	local function newItem(t)
		t.sources = t.sources or {}
		D.items[#D.items + 1] = t
		return t
	end

	-- the stock equipment
	local crafted = {}
	for _, r in ipairs(W.csv("data/items/base_recipes.csv")) do
		crafted[tonumber(r.id)] = true
	end
	local names = {}
	for _, r in ipairs(W.csv("data/items/base_item_names.csv")) do
		names[tonumber(r.id)] = ((r.article ~= "" and r.article .. " ") or "") .. r.name
	end
	for _, r in ipairs(W.csv("data/items/base_item_values.csv")) do
		local id = tonumber(r.id)
		local slot = r.cat == "equip" and STOCK_SLOT[r.slot]
		if not slot and quivers[id] then
			slot = "shield" -- the quivers are supplies in the snapshot (they were containers); now off-hand gear
		end
		if slot then
			if slot == "shield" then
				if quivers[id] then
					slot = "quiver"
				elseif books[id] then
					slot = "book"
				end
			end
			local it = newItem({id = id, name = names[id] or ("#" .. id), slot = slot, level = tonumber(r.level), origin = "stock"})
			if quivers[id] then
				it.level = quivers[id][1]
			end
			if tonumber(r.buyers) > 0 then
				it.sources.shop = {access = 0}
			end
			if tonumber(r.loot_n) > 0 and tonumber(r.chance_max) >= cfg.minDropChance then
				it.sources.drop = {access = C.huntOfRaw(cfg, tonumber(r.loot_lv_min)), chance = tonumber(r.chance_max)}
			end
			if r.reward == "1" then
				it.sources.reward = {access = 0}
			end
			if crafted[id] then
				it.sources.craft = {access = 0}
			end
			local cm = chaosLoot[id]
			if cm and cm.chance >= cfg.minDropChance then
				local d = it.sources.drop
				local access = cm.level
				if not d then
					it.sources.drop = {access = access, chance = cm.chance}
				else
					d.access = math.min(d.access, access)
					d.chance = math.max(d.chance, cm.chance)
				end
			end
			if pool[id] and cfg.gambleCounts then
				it.sources.gamble = {access = pool[id]}
			end
			D.byId[id] = it
		end
	end
	-- a quiver the snapshot has no row for (nothing drops it): the Gambler is its way
	for id, q in pairs(quivers) do
		if not D.byId[id] then
			local it = newItem({id = id, name = names[id] or ("#" .. id), slot = "quiver", level = q[1], origin = "stock"})
			if pool[id] and cfg.gambleCounts then
				it.sources.gamble = {access = pool[id]}
			end
			D.byId[id] = it
		end
	end

	-- the class loot rows (data/lib/chaos_class_loot.lua) and the jewelry rows (data/lib/chaos_jewelry.lua): added to the
	-- monster types at startup, so the base tables' snapshot does not hold them
	local poolFile = dofile("data/scripts/chaos/bounty_pool.lua")
	local pcfg = dofile("data/scripts/chaos/pace_config.lua")
	local levelByName = {}
	for _, group in ipairs({poolFile.hunt or {}, poolFile.bosses or {}}) do
		for _, e in ipairs(group) do
			levelByName[e.name] = (ChaosPaceCore.entryLevel(pcfg, e))
		end
	end
	local function levelOfEntry(e)
		return levelByName[e.name] or (ChaosPaceCore.entryLevel(pcfg, e))
	end
	local extra = {}
	for _, lib in ipairs({dofile("data/lib/chaos_class_loot.lua"), dofile("data/lib/chaos_jewelry.lua")}) do
		for _, row in ipairs(lib.lootRows(poolFile, levelOfEntry)) do
			local it = D.byId[row[2]]
			if it and row[3] >= cfg.minDropChance then
				local lv = levelByName[row[1]] or 0
				local d = it.sources.drop
				if not d then
					it.sources.drop = {access = lv, chance = row[3]}
				else
					d.access = math.min(d.access, lv)
					d.chance = math.max(d.chance, row[3])
				end
				extra[#extra + 1] = row
			end
		end
	end

	-- the equipment sets
	D.gearOn = G.PAIR28 == true
	local sourceLevel = {}
	for _, src in pairs(G.sources) do
		for _, group in ipairs({src.monsters or {}, src.bosses or {}}) do
			for _, m in ipairs(group) do
				sourceLevel[m[1]] = C.huntOfName(hunt, m[1], m[2])
			end
		end
	end
	local dropOf = {}
	if D.gearOn then
		for _, row in ipairs(G.lootRows()) do
			local d = dropOf[row[2]]
			local lv = sourceLevel[row[1]] or 0
			if not d then
				dropOf[row[2]] = {access = lv, chance = row[3]}
			else
				d.access = math.min(d.access, lv)
				d.chance = math.max(d.chance, row[3])
			end
		end
	end
	for _, p in ipairs(G.items.pieces) do
		local slot = SET_SLOT[p.kind]
		if slot then
			local classes
			if #p.classes > 0 then
				classes = set(p.classes)
			end
			local it = newItem({id = p.id, name = p.name, slot = slot, level = p.level, classes = classes,
				origin = "set:" .. p.set})
			local weight = ({H = "heavy", M = "medium", C = "cloth"})[p.fit or ""]
			local value = (slot == "shield" or slot == "book") and (p.stats.defense or 0) or (p.stats.armor or 0)
			if slot ~= "amulet" and slot ~= "ring" then
				it.power = value
				it.weight = weight
			end
			local d = dropOf[p.id]
			-- level gear (chaos_gear_sets.lua M.levelDrop): any monster hunted near the piece's level may drop it
			local ld = D.gearOn and G.levelDrop and G.levelDrop(p)
			if ld then
				if not d then
					d = {access = ld.level, chance = ld.chance}
				else
					d = {access = math.min(d.access, ld.level), chance = math.max(d.chance, ld.chance)}
				end
			end
			if d and d.chance >= cfg.minDropChance then
				it.sources.drop = d
			end
		end
	end

	-- the uniques
	dofile("data/lib/chaos_item_mods.lua")
	dofile("data/lib/chaos_crafting.lua")
	dofile("data/lib/chaos_unique_items.lua")
	local lootCfg = dofile("data/scripts/chaos/loot_config.lua")
	local rank = lootCfg.unique.tierMult
	for _, u in ipairs(ChaosUniqueItems) do
		local slot = UNIQUE_SLOT[u.slot]
		if u.slot == "shield" and quivers[u.id] then
			slot = "quiver"
		elseif u.slot == "shield" and books[u.id] then
			slot = "book"
		end
		if slot then
			local spec = ChaosUniqueSpecs[u.id] or {}
			local equip = spec.equip
			local classes
			if equip and equip.lines and #equip.lines > 0 then
				classes = {}
				for _, base in ipairs(equip.lines) do
					for _, c in ipairs(lineOf[base] or {}) do
						classes[c] = true
					end
				end
			end
			local level = (equip and equip.level) or u.level or 0
			local attrs = spec.attributes or {}
			local power
			if slot == "shield" or slot == "book" then
				power = attrs.Defense
			elseif slot ~= "amulet" and slot ~= "ring" and slot ~= "quiver" then
				power = attrs.Armor
			end
			local it = newItem({id = u.id, name = u.name, slot = slot, level = level, classes = classes, power = power,
				origin = "unique", unique = true, anyHand = (slot == "shield" or slot == "book") and classes ~= nil})
			local mult = rank[u.minTier] or 1
			it.sources.drop = {access = u.minMonsterLevel or level, chance = u.chance * mult * 10, unique = true}
		end
	end
	D.everyone = everyone
	return D
end

-- ---------------------------------------------------------------------------------------------------------------
-- the audit
-- ---------------------------------------------------------------------------------------------------------------
local function weightOf(cfg, class)
	for w, list in pairs(cfg.weight) do
		for _, c in ipairs(list) do
			if c == class then
				return w
			end
		end
	end
	return "heavy"
end

-- the class names that wear a slot's items
function C.wearers(cfg, wcfg, slotCfg)
	if slotCfg.who then
		return set(cfg.who[slotCfg.who])
	end
	local s = {}
	for _, c in ipairs(allClassNames(wcfg)) do
		s[c] = true
	end
	return s
end

-- the level an item is reached at: its required level, or the access level of its easiest source when that is higher
function C.level(it)
	local best
	for _, s in pairs(it.sources) do
		if not best or s.access < best then
			best = s.access
		end
	end
	if not best then
		return nil
	end
	return math.max(it.level, best)
end

function C.audit(cfg, wcfg, D)
	local A = {rows = {}, unobtainable = {}, bands = wcfg.bands}
	for _, it in ipairs(D.items) do
		it.reach = C.level(it)
		if not it.reach then
			A.unobtainable[#A.unobtainable + 1] = it
		end
	end
	for _, slotCfg in ipairs(cfg.slots) do
		local wearers = C.wearers(cfg, wcfg, slotCfg)
		for _, l in ipairs(wcfg.lines) do
			for _, class in ipairs(l.classes) do
				if wearers[class.name] then
					local row = {slot = slotCfg.key, label = slotCfg.label, class = class.name, line = l.line, cells = {}}
					for i = 1, #wcfg.bands do
						row.cells[i] = {n = 0, good = 0, list = {}}
					end
					local weight = weightOf(cfg, class.name)
					for _, it in ipairs(D.items) do
						local fits = it.slot == slotCfg.key
						if not fits and it.anyHand and (it.slot == "shield" or it.slot == "book") and
							(slotCfg.key == "shield" or slotCfg.key == "book") then
							fits = true
						end
						if fits and it.reach and (not it.classes or it.classes[class.name]) then
							-- a set piece of another weight is not worn by this class (its class list says so)
							local cell = row.cells[W.bandOf(wcfg, it.reach)]
							local ratio
							if it.power then
								local tier = C.tier(D.curves, it.slot, weight, math.max(it.level, 1))
								ratio = tier and tier > 0 and it.power / tier or nil
							end
							cell.n = cell.n + 1
							if not ratio or ratio >= cfg.minPower then
								cell.good = cell.good + 1
							end
							cell.list[#cell.list + 1] = {item = it, ratio = ratio}
							if ratio and (not cell.best or ratio > cell.best) then
								cell.best = ratio
							end
						end
					end
					for _, cell in ipairs(row.cells) do
						table.sort(cell.list, function(a, b)
							if a.item.level ~= b.item.level then
								return a.item.level < b.item.level
							end
							return a.item.id < b.item.id
						end)
					end
					A.rows[#A.rows + 1] = row
				end
			end
		end
	end
	return A
end

function C.flag(cfg, slotCfg, cell)
	if cell.n == 0 then
		return "ZERO"
	end
	if cell.good < slotCfg.min then
		return cell.n < slotCfg.min and "FEW" or "WEAK"
	end
	return nil
end

local function slotCfgOf(cfg, key)
	for _, s in ipairs(cfg.slots) do
		if s.key == key then
			return s
		end
	end
end

local function allowed(cfg, row, label)
	for _, g in ipairs(cfg.knownGaps) do
		if g[1] == row.slot and g[2] == row.class and g[3] == label then
			return g[4]
		end
	end
	return nil
end

function C.failures(cfg, wcfg, A)
	local out = {}
	for _, row in ipairs(A.rows) do
		local sc = slotCfgOf(cfg, row.slot)
		for i, cell in ipairs(row.cells) do
			local f = C.flag(cfg, sc, cell)
			if f and not allowed(cfg, row, wcfg.bands[i][3]) then
				out[#out + 1] = {slot = row.slot, class = row.class, band = wcfg.bands[i][3], flag = f, n = cell.n, good = cell.good}
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- output
-- ---------------------------------------------------------------------------------------------------------------
function C.cellText(cell)
	if cell.n == 0 then
		return "0"
	end
	if cell.best then
		return string.format("%d/%d", cell.n, floor(cell.best * 100 + 0.5))
	end
	return tostring(cell.n)
end

-- rows with the same cells in a slot are one row ("Warrior, Juggernaut")
local function merged(cfg, wcfg, A)
	local out = {}
	local key
	local last
	for _, row in ipairs(A.rows) do
		local parts = {}
		for i, cell in ipairs(row.cells) do
			local sc = slotCfgOf(cfg, row.slot)
			local f = C.flag(cfg, sc, cell)
			local t = C.cellText(cell)
			if f and not allowed(cfg, row, wcfg.bands[i][3]) then
				t = "**" .. t .. "!**"
			elseif f then
				t = t .. "!"
			end
			parts[#parts + 1] = t
		end
		local sig = row.slot .. "|" .. table.concat(parts, "|")
		local found
		for _, o in ipairs(out) do
			if o.sig == sig then
				found = o
				break
			end
		end
		if found then
			found.classes[#found.classes + 1] = row.class
		else
			out[#out + 1] = {sig = sig, slot = row.slot, label = row.label, classes = {row.class}, parts = parts}
		end
	end
	return out
end

function C.markdown(cfg, wcfg, A)
	local head, sep = {"Slot", "Classes"}, {"---", "---"}
	for _, b in ipairs(wcfg.bands) do
		head[#head + 1] = b[3]
		sep[#sep + 1] = "---:"
	end
	local lines = {"| " .. table.concat(head, " | ") .. " |", "|" .. table.concat(sep, "|") .. "|"}
	for _, m in ipairs(merged(cfg, wcfg, A)) do
		local cls = table.concat(m.classes, ", ")
		if #m.classes == 21 then
			cls = "all 21"
		end
		lines[#lines + 1] = "| " .. m.label .. " | " .. cls .. " | " .. table.concat(m.parts, " | ") .. " |"
	end
	return table.concat(lines, "\n") .. "\n"
end

function C.text(cfg, wcfg, A)
	local out = {}
	local head = string.format("%-9s %-34s", "slot", "classes")
	for _, b in ipairs(wcfg.bands) do
		head = head .. string.format(" %9s", b[3])
	end
	out[#out + 1] = head
	for _, m in ipairs(merged(cfg, wcfg, A)) do
		local cls = table.concat(m.classes, ",")
		if #m.classes == 21 then
			cls = "all 21"
		end
		local s = string.format("%-9s %-34s", m.label, cls:sub(1, 34))
		for _, p in ipairs(m.parts) do
			s = s .. string.format(" %9s", (p:gsub("%*%*", "")))
		end
		out[#out + 1] = s
	end
	out[#out + 1] = ""
	out[#out + 1] = "cell = options (a piece worn by the class, reachable in the band) / best known power in % of the sets' curve;"
	out[#out + 1] = "! = fewer than the slot's minimum of options at full strength (" .. floor(cfg.minPower * 100) .. "% of the curve; stock power unknown counts)"
	return table.concat(out, "\n") .. "\n"
end

function C.list(cfg, wcfg, A, slot, only)
	local out = {}
	for _, row in ipairs(A.rows) do
		if row.slot == slot and (not only or row.class == only) then
			out[#out + 1] = "== " .. row.label .. ": " .. row.class
			for i, cell in ipairs(row.cells) do
				out[#out + 1] = string.format("  [%s] n=%d", wcfg.bands[i][3], cell.n)
				for _, e in ipairs(cell.list) do
					local src = {}
					for k in pairs(e.item.sources) do
						src[#src + 1] = k
					end
					table.sort(src)
					out[#out + 1] = string.format("      lv %-4d (reach %-4d) %-30s %s %s [%s]", e.item.level, e.item.reach,
						e.item.name:sub(1, 30), e.ratio and string.format("%3d%%", floor(e.ratio * 100 + 0.5)) or "  - ",
						e.item.origin, table.concat(src, ","))
				end
			end
		end
	end
	return table.concat(out, "\n") .. "\n"
end

-- ---------------------------------------------------------------------------------------------------------------
-- fairness: the weapons the monsters of a hunting band drop, per 1000 kills, that each class can use. The stock tables
-- (tools/loot_bands_data.lua) plus the class loot rows (data/lib/chaos_class_loot.lua). A weapon counts when its power
-- is at least cfg.fairPower of the weapon audit's curve at the band.
-- ---------------------------------------------------------------------------------------------------------------
function C.fairness(cfg, wcfg)
	local bands = dofile("tools/loot_bands_data.lua")
	local weapons = {}
	for _, r in ipairs(W.csv("data/items/base_weapons.csv")) do
		weapons[tonumber(r.id)] = r
	end
	local FAMILY = {sword = "melee", axe = "melee", club = "melee", bow = "launcher", crossbow = "launcher", wand = "wand", throw = "throw"}
	local classes = {}
	for _, l in ipairs(wcfg.lines) do
		for _, c in ipairs(l.classes) do
			classes[#classes + 1] = c
		end
	end
	local edges = cfg.fairEdges
	local function edgeOf(level)
		local best
		for _, e in ipairs(edges) do
			if level >= e * 0.85 and level <= e * 1.15 then
				best = e
			end
		end
		return best
	end
	-- the class rows by monster name
	dofile("data/scripts/chaos/pace_core.lua")
	local pcfg = dofile("data/scripts/chaos/pace_config.lua")
	local pool = dofile("data/scripts/chaos/bounty_pool.lua")
	local levelOf = function(e) return (ChaosPaceCore.entryLevel(pcfg, e)) end
	local extra = {}
	for _, row in ipairs(dofile("data/lib/chaos_class_loot.lua").lootRows(pool, levelOf)) do
		extra[row[1]] = extra[row[1]] or {}
		table.insert(extra[row[1]], {row[2], row[3], 1, "gear", 0})
	end
	local agg = {}
	for _, e in ipairs(edges) do
		agg[e] = {w = 0, all = 0, rate = {}}
	end
	-- level gear (data/lib/chaos_gear_sets.lua M.rollLevelGear): a kill at the monster's level drops one weapon of the
	-- sets near it with the chance per piece below (the classes of the piece, its power against the tier of the edge)
	local G = dofile("data/lib/chaos_gear_sets.lua")
	local SET_FAMILY = {sword = "melee", axe = "melee", club = "melee", bow = "launcher", crossbow = "launcher",
		wand = "wand", rod = "wand"}
	for _, m in ipairs(bands) do
		local edge = edgeOf(m.level)
		if edge then
			local a = agg[edge]
			a.w = a.w + m.spawns
			local near = G.PAIR28 and G.levelPieces(m.level) or {}
			for _, piece in ipairs(near) do
				local fam = SET_FAMILY[piece.kind]
				if fam then
					local p = G.levelChance("normal") / #near / 100000 * m.spawns
					local hands = (piece.fit == "2" or piece.kind == "bow" or piece.kind == "crossbow") and 2 or 1
					local power
					if fam == "wand" then
						power = W.curve(wcfg, "wand", piece.level)
					else
						power = 0
						for k, v in pairs(piece.stats) do
							if k == "attack" or k:match("^element") then
								power = power + v
							end
						end
					end
					local tier = W.tier(wcfg, piece.kind == "rod" and "wand" or piece.kind, hands, edge)
					local cs = {}
					for _, c in ipairs(piece.classes) do
						cs[c] = true
					end
					a.all = a.all + p
					for _, class in ipairs(classes) do
						if W.suits(class, {family = fam, kind = piece.kind == "rod" and "wand" or piece.kind, hands = hands,
							classes = #piece.classes > 0 and cs or nil}) and power >= cfg.fairPower * tier then
							a.rate[class.name] = (a.rate[class.name] or 0) + p
						end
					end
				end
			end
			for _, list in ipairs({m.loot, extra[m.name] or {}}) do
				for _, entry in ipairs(list) do
					local r = weapons[entry[1]]
					if r and entry[4] == "gear" and tonumber(r.charges) == 0 then
						local p = entry[2] / 100000 * m.spawns
						local power = r.kind == "wand" and (tonumber(r.wmin) + tonumber(r.wmax)) / 2 or
							tonumber(r.attack) + tonumber(r.element)
						local tier = W.tier(wcfg, r.kind, tonumber(r.hands), edge)
						local cs
						if r.classes ~= "*" then
							cs = {}
							for c in r.classes:gmatch("[^|]+") do
								cs[c] = true
							end
						end
						a.all = a.all + p
						for _, class in ipairs(classes) do
							if W.suits(class, {family = FAMILY[r.kind], kind = r.kind, hands = tonumber(r.hands), classes = cs}) and
								power >= cfg.fairPower * tier then
								a.rate[class.name] = (a.rate[class.name] or 0) + p
							end
						end
					end
				end
			end
		end
	end
	local out = {edges = edges, classes = classes, agg = agg, rows = {}, fails = {}}
	for _, edge in ipairs(edges) do
		local a = agg[edge]
		local rates = {}
		for _, c in ipairs(classes) do
			rates[#rates + 1] = a.rate[c.name] or 0
		end
		table.sort(rates)
		a.mean = rates[math.ceil(#rates / 2)] -- the median class
	end
	for _, c in ipairs(classes) do
		local row = {class = c.name, cells = {}}
		for i, edge in ipairs(edges) do
			local a = agg[edge]
			local rate = (a.rate[c.name] or 0) / a.w * 1000
			row.cells[i] = rate
			if (a.rate[c.name] or 0) < cfg.fairShare * a.mean then
				out.fails[#out.fails + 1] = {class = c.name, edge = edge, rate = rate, mean = a.mean / a.w * 1000}
			end
		end
		out.rows[#out.rows + 1] = row
	end
	return out
end

function C.fairnessText(F)
	local out = {string.format("%-14s", "per 1000 kills") .. string.rep("", 0)}
	local head = string.format("%-14s", "usable weapons")
	for _, e in ipairs(F.edges) do
		head = head .. string.format("%9d", e)
	end
	out[1] = head
	local all = string.format("%-14s", "all weapons")
	for _, e in ipairs(F.edges) do
		all = all .. string.format("%9.1f", F.agg[e].all / F.agg[e].w * 1000)
	end
	out[#out + 1] = all
	for _, row in ipairs(F.rows) do
		local s = string.format("%-14s", row.class)
		for _, v in ipairs(row.cells) do
			s = s .. string.format("%9.1f", v)
		end
		out[#out + 1] = s
	end
	return table.concat(out, "\n") .. "\n"
end

-- ---------------------------------------------------------------------------------------------------------------
-- the README blocks
-- ---------------------------------------------------------------------------------------------------------------
C.README = "README.md"
C.BEGIN = "<!-- gear-coverage:begin (luajit tools/gear_coverage.lua --write) -->"
C.END = "<!-- gear-coverage:end -->"

function C.readmeBlock(cfg, wcfg, A)
	return C.BEGIN .. "\n\n" .. C.markdown(cfg, wcfg, A) .. "\n" .. C.END
end

local function plainFind(s, needle, init)
	return s:find(needle, init or 1, true)
end

function C.readmeReplace(text, block)
	local a = plainFind(text, C.BEGIN)
	local _, bEnd = plainFind(text, C.END, a or 1)
	if not a or not bEnd then
		return nil
	end
	return text:sub(1, a - 1) .. block .. text:sub(bEnd + 1)
end

function C.main(args)
	local cfg = dofile("tools/gear_coverage_config.lua")
	local wcfg = dofile("tools/weapon_coverage_config.lua")
	local D = C.load(cfg, wcfg)
	local A = C.audit(cfg, wcfg, D)
	local mode = args[1]
	if mode == "--md" then
		io.write(C.markdown(cfg, wcfg, A))
	elseif mode == "--fairness" then
		io.write(C.fairnessText(C.fairness(cfg, wcfg)))
	elseif mode == "--list" then
		io.write(C.list(cfg, wcfg, A, args[2] or "armor", args[3]))
	elseif mode == "--write" or mode == "--check" then
		local text = W.readFile(C.README)
		local new = C.readmeReplace(text, C.readmeBlock(cfg, wcfg, A))
		if not new then
			io.stderr:write("server/README.md has no gear-coverage block (markers " .. C.BEGIN .. ")\n")
			os.exit(1)
		end
		if mode == "--write" then
			local f = assert(io.open(C.README, "wb"))
			f:write(new)
			f:close()
			io.write("server/README.md gear coverage table written\n")
			return
		end
		local bad = false
		for _, f in ipairs(C.failures(cfg, wcfg, A)) do
			bad = true
			io.stderr:write(string.format("gear coverage: %s, %s, levels %s: %s (%d option(s), %d at full strength)\n",
				f.slot, f.class, f.band, f.flag, f.n, f.good))
		end
		for _, f in ipairs(C.fairness(cfg, wcfg).fails) do
			bad = true
			io.stderr:write(string.format("gear coverage: %s finds %.1f usable weapons per 1000 kills at hunting level %d; the median class %.1f (least share %.2f)\n",
				f.class, f.rate, f.edge, f.mean, cfg.fairShare))
		end
		if new ~= text then
			bad = true
			io.stderr:write("server/README.md gear coverage table is out of date: luajit tools/gear_coverage.lua --write\n")
		end
		if bad then
			os.exit(1)
		end
		io.write("gear coverage ok\n")
	else
		io.write(C.text(cfg, wcfg, A))
		io.write(string.format("\n%d items, %d not obtainable\n", #D.items, #A.unobtainable))
	end
end

if not GEAR_COVERAGE_NO_MAIN then
	C.main(arg or {})
end

return C
