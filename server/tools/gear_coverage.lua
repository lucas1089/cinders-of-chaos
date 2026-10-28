-- Gear coverage audit: for every class, every armour slot and every level band, the pieces the class can wear and get
-- (server/README.md "Gear coverage"; the sibling of tools/weapon_coverage.lua, which audits weapons, wands, rods and fist
-- weapons). Run from the server/ folder:
--   luajit tools/gear_coverage.lua                  the table (plain text) and the flags
--   luajit tools/gear_coverage.lua --md             the markdown tables of server/README.md
--   luajit tools/gear_coverage.lua --list SLOT [Class]  every option of a slot, by band
--   luajit tools/gear_coverage.lua --derive         the class loot anchors that equalize the weapon drops (data/lib/chaos_class_loot.lua)
--   luajit tools/gear_coverage.lua --fairness [--detail]  how much of the gear a band's monsters drop each class can use
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
-- fairness: the weapons the monsters of a hunting band drop, per 1000 kills, that each class can use (owner, 2026-10-28:
-- "monk weapons are very rare to drop, they must all be equal"). Every real source of a weapon drop is counted:
--   stock   the stock loot tables of the bounty pool monsters (tools/loot_bands_data.lua), weapons only
--   set     the loot rows of the equipment sets (data/lib/chaos_gear_sets.lua M.lootRows) on those monsters
--   level   the sets' level gear (M.rollLevelGear: from hunting level 700, any monster; a piece the killer's class wears
--           weighs classWeight times as much)
--   class   the class loot rows (data/lib/chaos_class_loot.lua): bows, crossbows, wands, rods
--   melee, fist, throw   the same file's rows for the melee, the Monk line's fist and the Thief line's throwing weapons
--   fist    the Monk line's fist weapons (data/lib/chaos_fist_weapons.lua loot, data/scripts/chaos/fist_weapons.lua)
-- A weapon counts for a class when the class can wield it (the weapon audit's families and class lists), its power is at
-- least cfg.fairPower of the weapon audit's curve at the band, and its required level is within cfg.fairWindow of the
-- band (a club of level 25 is no drop at hunting level 300). The bands the monsters of the pool do not reach (hunting
-- level above the highest base monster, 657) are scaled monsters: they drop the sets' level gear only (the class rows
-- are keyed to the pool level of the monster type), counted for 1000 kills of a normal monster.
-- ---------------------------------------------------------------------------------------------------------------
C.SOURCES = {"stock", "set", "level", "class", "fist"}

-- the loadouts an item belongs to (cfg.loadouts names them per class): melee by hands, fist, bow, crossbow, wand and rod.
-- A stock wand or rod is told apart by its class list like the sets do: a wand is one the Elementalist wields, a rod one it
-- does not (the Illusionist's).
local function loadoutKeys(spec)
	if spec.family == "melee" then
		return {spec.hands == 2 and "melee2h" or "melee1h"}
	elseif spec.family == "fist" then
		return {"fist"}
	elseif spec.family == "throw" then
		return {"throw"}
	elseif spec.family == "launcher" then
		return {spec.kind == "crossbow" and "crossbow" or "bow"}
	elseif spec.family == "wand" then
		if spec.exact then
			return {spec.kind == "rod" and "rod" or "wand"}
		end
		local keys = {}
		if not spec.classes or spec.classes.Elementalist then
			keys[#keys + 1] = "wand"
		end
		if not spec.classes or not spec.classes.Elementalist then
			keys[#keys + 1] = "rod"
		end
		return keys
	end
	return {}
end
C.loadoutKeys = loadoutKeys

function C.fairness(cfg, wcfg, opt)
	opt = opt or {}
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
	-- loadouts[class name][key] = true
	local has, keyList, seenKey = {}, {}, {}
	for _, g in ipairs(cfg.loadouts) do
		for _, name in ipairs(g.classes) do
			has[name] = has[name] or {}
			for _, key in ipairs(g.keys) do
				has[name][key] = true
				if not seenKey[key] then
					seenKey[key] = true
					keyList[#keyList + 1] = key
				end
			end
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
	-- the rows by monster name: class loot (the pool, by hunting level), the sets' loot and the fist weapons' loot
	dofile("data/scripts/chaos/pace_core.lua")
	local pcfg = dofile("data/scripts/chaos/pace_config.lua")
	local pool = dofile("data/scripts/chaos/bounty_pool.lua")
	local levelOf = function(e) return (ChaosPaceCore.entryLevel(pcfg, e)) end
	local G = dofile("data/lib/chaos_gear_sets.lua")
	dofile("data/lib/chaos_fist_weapons.lua")
	local FIST = ChaosFistWeapons
	local CL = opt.classLoot or dofile("data/lib/chaos_class_loot.lua")
	local extra = {}
	local function addExtra(name, row)
		extra[name] = extra[name] or {}
		table.insert(extra[name], row)
	end
	for _, row in ipairs(CL.lootRows(pool, levelOf)) do
		local r = weapons[row[2]]
		if r then
			addExtra(row[1], {r = r, chance = row[3], source = "class"})
		elseif FIST.items[row[2]] then
			addExtra(row[1], {fist = FIST.items[row[2]], id = row[2], chance = row[3], source = "class"})
		end
	end
	if G.PAIR28 then
		for _, row in ipairs(G.lootRows()) do
			local p = G.piece(row[2])
			if p then
				addExtra(row[1], {piece = p, chance = row[3], source = "set"})
			end
		end
	end
	for _, row in ipairs(FIST.loot) do
		local it = FIST.items[row[2]]
		if it then
			addExtra(row[1], {fist = it, id = row[2], chance = row[3], source = "fist"})
		end
	end
	local SET_FAMILY = {sword = "melee", axe = "melee", club = "melee", bow = "launcher", crossbow = "launcher",
		wand = "wand", rod = "wand"}
	-- a drop as the weapon audit sees it: family, kind, hands, class list, power, required level
	local function specOf(e)
		if e.r then
			local r = e.r
			local cs
			if r.classes ~= "*" then
				cs = {}
				for c in r.classes:gmatch("[^|]+") do
					cs[c] = true
				end
			end
			return {id = tonumber(r.id), family = FAMILY[r.kind], kind = r.kind, hands = tonumber(r.hands), classes = cs,
				level = tonumber(r.level), power = r.kind == "wand" and (tonumber(r.wmin) + tonumber(r.wmax)) / 2 or tonumber(r.attack) + tonumber(r.element)}
		elseif e.piece then
			local piece = e.piece
			local fam = SET_FAMILY[piece.kind]
			if not fam then
				return nil
			end
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
			local cs
			if #piece.classes > 0 then
				cs = {}
				for _, c in ipairs(piece.classes) do
					cs[c] = true
				end
			end
			return {family = fam, kind = piece.kind, exact = true,
				hands = (piece.fit == "2" or piece.kind == "bow" or piece.kind == "crossbow") and 2 or 1, classes = cs,
				level = piece.level, power = power}
		end
		return {id = e.id, family = "fist", kind = "fist", hands = 1, level = e.fist.level, power = e.fist.attack}
	end
	local agg = {}
	for _, e in ipairs(edges) do
		agg[e] = {w = 0, all = 0, cell = {}, by = {}}
	end
	-- power and level of a drop against the band: its power is at least cfg.fairPower of the curve and its required level
	-- is in the window around the band, or the class loot picks it for a monster of the band (above the highest base the
	-- rule takes the best ones, L.eligible)
	local eligibleIds = {}
	local function picked(key, edge, id)
		local ck = key .. ":" .. edge
		if not eligibleIds[ck] then
			eligibleIds[ck] = {}
			for _, b in ipairs(CL.eligible and CL.bases[key] and CL.eligible(key, edge, CL.config) or {}) do
				eligibleIds[ck][b[1]] = true
			end
		end
		return eligibleIds[ck][id]
	end
	local function relevant(edge, spec)
		local tier = W.tier(wcfg, spec.kind == "fist" and "sword" or spec.kind, spec.hands, edge)
		local win = cfg.fairWindow
		if spec.power < cfg.fairPower * tier then
			return false
		end
		if spec.level <= edge + win.above and spec.level >= edge - win.below then
			return true
		end
		for _, key in ipairs(loadoutKeys(spec)) do
			if spec.id and picked(key, edge, spec.id) then
				return true
			end
		end
		return false
	end
	local function add(a, class, key, source, p)
		a.cell[class] = a.cell[class] or {}
		a.cell[class][key] = (a.cell[class][key] or 0) + p
		a.by[class] = a.by[class] or {}
		a.by[class][key] = a.by[class][key] or {}
		a.by[class][key][source] = (a.by[class][key][source] or 0) + p
	end
	local function credit(a, edge, spec, p, source)
		a.all = a.all + p
		if not relevant(edge, spec) then
			return
		end
		local keys = loadoutKeys(spec)
		for _, class in ipairs(classes) do
			if W.suits(class, spec) then
				for _, key in ipairs(keys) do
					if has[class.name] and has[class.name][key] then
						add(a, class.name, key, source, p)
					end
				end
			end
		end
	end
	local sawEdge = {}
	for _, m in ipairs(bands) do
		local edge = edgeOf(m.level)
		if edge then
			sawEdge[edge] = true
			local a = agg[edge]
			a.w = a.w + m.spawns
			for _, entry in ipairs(m.loot) do
				local r = weapons[entry[1]]
				if r and entry[4] == "gear" and tonumber(r.charges) == 0 then
					credit(a, edge, specOf({r = r}), entry[2] / 100000 * m.spawns, "stock")
				end
			end
			for _, e in ipairs(extra[m.name] or {}) do
				local spec = specOf(e)
				if spec then
					credit(a, edge, spec, e.chance / 100000 * m.spawns, e.source)
				end
			end
		end
	end
	-- level gear: a kill at hunting level `edge` rolls one weapon of the sets near it (the killer's class weighs more)
	local o = G.config.open
	for _, edge in ipairs(edges) do
		local a = agg[edge]
		if not sawEdge[edge] then
			a.w = 1000
		end
		-- the class weapons of a scaled hunt (CL.rollScaled): per family the class wields, the chance spread over the bases
		local sc = CL.config and CL.config.scaled
		if sc and edge >= sc.minLevel and not sawEdge[edge] then
			for _, class in ipairs(classes) do
				for _, kind in ipairs(CL.classKinds and CL.classKinds[class.name] or {}) do
					local list = CL.eligible(kind, edge, CL.config)
					local chance = CL.scaledChanceAt(kind, edge, CL.config) / 100000
					for _, b in ipairs(list) do
						local r = weapons[b[1]]
						local spec
						if r then
							spec = specOf({r = r})
						elseif FIST.items[b[1]] then
							spec = specOf({fist = FIST.items[b[1]], id = b[1]})
						end
						if spec and has[class.name] and has[class.name][kind] and W.suits(class, spec) and relevant(edge, spec) then
							add(a, class.name, kind, "class", chance / #list * a.w)
						end
					end
				end
			end
		end
		local near = G.PAIR28 and G.levelPieces(edge) or {}
		if #near > 0 then
			local chance = G.levelChance("normal") / 100000
			for _, class in ipairs(classes) do
				local total = 0
				local wear = {}
				for i, piece in ipairs(near) do
					local wears = #piece.classes == 0
					for _, c in ipairs(piece.classes) do
						wears = wears or c == class.name
					end
					wear[i] = wears
					total = total + (wears and o.classWeight or 1)
				end
				for i, piece in ipairs(near) do
					local spec = SET_FAMILY[piece.kind] and specOf({piece = piece})
					if spec and wear[i] and relevant(edge, spec) and W.suits(class, spec) then
						local p = chance * (o.classWeight / total) * a.w
						for _, key in ipairs(loadoutKeys(spec)) do
							if has[class.name] and has[class.name][key] then
								add(a, class.name, key, "level", p)
							end
						end
					end
				end
			end
		end
	end
	local out = {edges = edges, classes = classes, agg = agg, keys = keyList, has = has, cells = {}, fails = {}}
	for _, edge in ipairs(edges) do
		local a = agg[edge]
		local hi, lo = 0, math.huge
		for _, c in ipairs(classes) do
			for key in pairs(has[c.name] or {}) do
				local v = ((a.cell[c.name] or {})[key] or 0) / a.w * 1000
				hi, lo = math.max(hi, v), math.min(lo, v)
			end
		end
		a.max, a.min = hi, lo
		a.ratio = hi > 0 and lo / hi or 0
	end
	for _, c in ipairs(classes) do
		for _, key in ipairs(keyList) do
			if has[c.name][key] then
				local row = {class = c.name, key = key, cells = {}, by = {}}
				for i, edge in ipairs(edges) do
					local a = agg[edge]
					row.cells[i] = ((a.cell[c.name] or {})[key] or 0) / a.w * 1000
					row.by[i] = {}
					for src, v in pairs(((a.by[c.name] or {})[key]) or {}) do
						row.by[i][src] = v / a.w * 1000
					end
					if a.max > 0 and row.cells[i] < cfg.fairRatio * a.max then
						out.fails[#out.fails + 1] = {class = c.name, key = key, edge = edge, rate = row.cells[i], best = a.max,
							ratio = row.cells[i] / a.max}
					end
				end
				out.cells[#out.cells + 1] = row
			end
		end
	end
	return out
end

function C.fairnessText(F, detail)
	local head = string.format("%-26s", "usable weapons per 1000")
	for _, e in ipairs(F.edges) do
		head = head .. string.format("%9d", e)
	end
	local out = {head}
	for _, row in ipairs(F.cells) do
		local s = string.format("%-16s%-10s", row.class, row.key)
		for _, v in ipairs(row.cells) do
			s = s .. string.format("%9.1f", v)
		end
		out[#out + 1] = s
		if detail then
			for _, src in ipairs({"stock", "set", "level", "class", "fist"}) do
				local line, any = string.format("    %-22s", src), false
				for i = 1, #F.edges do
					local v = row.by[i][src] or 0
					any = any or v > 0
					line = line .. string.format("%9.1f", v)
				end
				if any then
					out[#out + 1] = line
				end
			end
		end
	end
	local all = string.format("%-26s", "all weapons dropped")
	for _, e in ipairs(F.edges) do
		all = all .. string.format("%9.1f", F.agg[e].all / F.agg[e].w * 1000)
	end
	out[#out + 1] = all
	for _, name in ipairs({"max", "min"}) do
		local line = string.format("%-26s", name .. " of the cells")
		for _, e in ipairs(F.edges) do
			line = line .. string.format("%9.1f", F.agg[e][name])
		end
		out[#out + 1] = line
	end
	local ratio = string.format("%-26s", "least / most")
	for _, e in ipairs(F.edges) do
		ratio = ratio .. string.format("%9.2f", F.agg[e].ratio)
	end
	out[#out + 1] = ratio
	return table.concat(out, "\n") .. "\n"
end

-- the anchors of data/lib/chaos_class_loot.lua config.chance that give every loadout cfg.fairTarget usable weapons per
-- 1000 kills in the fitted bands. The model is run with the rows of the anchors tried; each round scales an anchor by
-- what the loadout's weakest class still misses of the target (the class part of a cell is linear in the anchor).
function C.derive(cfg, wcfg)
	local CL = dofile("data/lib/chaos_class_loot.lua")
	local kinds = {"melee1h", "melee2h", "fist", "bow", "crossbow", "wand", "rod"}
	local fit = cfg.fairFit
	local fitScaled = cfg.fairFitScaled
	local chance, scaled = {}, {}
	for _, kind in ipairs(kinds) do
		chance[kind], scaled[kind] = {}, {}
		for _, edge in ipairs(fit) do
			chance[kind][#chance[kind] + 1] = {edge, 3000}
		end
		for _, edge in ipairs(fitScaled) do
			scaled[kind][#scaled[kind] + 1] = {edge, 3000}
		end
	end
	local function run()
		local config = {}
		for k, v in pairs(CL.config) do
			config[k] = v
		end
		config.chance, config.scaled = {}, {}
		for k, v in pairs(CL.config.chance) do
			config.chance[k] = v
		end
		for k, v in pairs(CL.config.scaled) do
			config.scaled[k] = v
		end
		config.scaled.chance = {}
		for k, v in pairs(CL.config.scaled.chance) do
			config.scaled.chance[k] = v
		end
		for _, kind in ipairs(kinds) do
			config.chance[kind] = chance[kind]
			config.scaled.chance[kind] = scaled[kind]
		end
		local mod = setmetatable({config = config, lootRows = function(pool, levelOf) return CL.lootRows(pool, levelOf, config) end},
			{__index = CL})
		return C.fairness(cfg, wcfg, {classLoot = mod})
	end
	local groups = {{edges = fit, store = chance}, {edges = fitScaled, store = scaled}}
	for _ = 1, 12 do
		local F = run()
		for _, g in ipairs(groups) do
			local need = {}
			for _, row in ipairs(F.cells) do
				for i, edge in ipairs(F.edges) do
					for k, fitEdge in ipairs(g.edges) do
						if edge == fitEdge and row.by[i].class and row.by[i].class > 0 then
							local other = row.cells[i] - row.by[i].class
							local want = (cfg.fairTarget[edge] - other) / row.by[i].class
							local key = row.key .. ":" .. k
							need[key] = need[key] and math.max(need[key], want) or want
						end
					end
				end
			end
			for _, kind in ipairs(kinds) do
				for k = 1, #g.edges do
					local n = need[kind .. ":" .. k]
					if n then
						g.store[kind][k][2] = math.max(0, g.store[kind][k][2] * n)
					end
				end
			end
		end
	end
	local out = {}
	for gi, g in ipairs(groups) do
		out[#out + 1] = gi == 1 and "chance" or "scaled.chance"
		for _, kind in ipairs(kinds) do
			local pts = {}
			for _, a in ipairs(g.store[kind]) do
				pts[#pts + 1] = string.format("{%d, %d}", a[1], math.floor(a[2] + 0.5))
			end
			out[#out + 1] = string.format("%s = {%s},", kind, table.concat(pts, ", "))
		end
	end
	return table.concat(out, "\n") .. "\n", groups
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
		io.write(C.fairnessText(C.fairness(cfg, wcfg), args[2] == "--detail"))
	elseif mode == "--derive" then
		io.write((C.derive(cfg, wcfg)))
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
			io.stderr:write(string.format("gear coverage: %s finds %.1f usable weapons per 1000 kills at hunting level %d; the best class %.1f (%.2f of it, least %.2f)\n",
				f.class, f.rate, f.edge, f.best, f.ratio, cfg.fairRatio))
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
