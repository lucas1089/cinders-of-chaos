-- Weapon coverage audit: for every class and every level band, the weapons the class can wield and obtain, with their
-- power (server/README.md "Weapon coverage"; docs/CLASSES.md). Run from the server/ folder (the libraries dofile() their
-- neighbours relative to it):
--   luajit tools/weapon_coverage.lua                 the table (plain text) and the flags
--   luajit tools/weapon_coverage.lua --md            the markdown table of server/README.md
--   luajit tools/weapon_coverage.lua --list [Class]  every weapon option, per class (or one class)
--   luajit tools/weapon_coverage.lua --check         exit 1 when a class has a band with too few weapons or only weak
--                                                     ones (tools/weapon_coverage_config.lua), or when the README table
--                                                     is out of date (CI, both interpreters)
--   luajit tools/weapon_coverage.lua --write         rewrite the README table between its two marker lines
-- lua5.3 gives the same output.
--
-- The data (all in the repo; the base server is read only by tools/survey_base_weapons.py):
--   data/items/base_weapons.csv       the stock weapons: kind, hands, level, attack, wand damage, classes (after install_all)
--   data/items/base_item_values.csv   how the stock items are got: NPC shops (buyers), monster loot, rewards
--   data/items/base_recipes.csv       the base crafting recipes (a weapon that is a product is crafted)
--   data/lib/chaos_gear_sets.lua      the equipment sets of pair 28 (+ chaos_gear_sets_items.lua): weapons, loot rows
--   data/lib/chaos_unique_items.lua   the uniques: slot, level, drop tier, monsters; chaos_unique_specs.lua: attack, equip rule
--   data/lib/chaos_fist_weapons.lua   the Monk line's fist weapons
--   data/lib/chaos_weapons800.lua     the 34 weapons above level 800 (their own monster loot rows are the source counted; the
--                                     class loot families carry them too, which this audit does not read)
--   data/monster/monsters/chaos/**    the Chaos monsters' loot (stock weapons some of them drop)
--   data/lib/chaos_archery_config.lua which launchers are bows and which crossbows
-- A weapon counts for a class when its class list holds the class and its family suits the class (config `lines`), and
-- when the player can get it: sold by an NPC, dropped (above the config's minDropChance), crafted, a reward, or a unique /
-- set piece that drops. Power = its attack (a wand: its mean damage) against the tier of its own level.

local C = {}
local floor = math.floor

function C.readFile(path)
	local f = io.open(path, "rb")
	if not f then
		error("cannot read " .. path)
	end
	local s = f:read("*a")
	f:close()
	return s
end

-- CSV with a header row and no quoted commas (the snapshot files)
function C.csv(path)
	local rows, header = {}, nil
	for line in C.readFile(path):gmatch("[^\r\n]+") do
		if not line:match("^#") then
			local cells = {}
			for cell in (line .. ","):gmatch("([^,]*),") do
				cells[#cells + 1] = cell
			end
			if not header then
				header = cells
			else
				local row = {}
				for i, name in ipairs(header) do
					row[name] = cells[i]
				end
				rows[#rows + 1] = row
			end
		end
	end
	return rows
end

local function stubEngine()
	local attrs = {ATTACK = "Attack", DEFENSE = "Defense", EXTRADEFENSE = "Extra Defense", ARMOR = "Armor",
		HITCHANCE = "Hit Chance", SHOOTRANGE = "Range", ATTACK_SPEED = "Attack Speed", NAME = "Name",
		ARTICLE = "Article", DESCRIPTION = "Description"}
	for k, v in pairs(attrs) do
		_G["ITEM_ATTRIBUTE_" .. k] = _G["ITEM_ATTRIBUTE_" .. k] or v
	end
end

-- ---------------------------------------------------------------------------------------------------------------
-- the tier
-- ---------------------------------------------------------------------------------------------------------------
function C.curve(cfg, name, level)
	local xs, ys = cfg.anchors, cfg.curves[name]
	if level <= xs[1] then
		return ys[1]
	end
	for i = 2, #xs do
		if level <= xs[i] then
			return ys[i - 1] + (ys[i] - ys[i - 1]) * (level - xs[i - 1]) / (xs[i] - xs[i - 1])
		end
	end
	return ys[#ys]
end

-- the attack (a wand: the mean damage) the equipment sets give at a level, for a kind of weapon
function C.tier(cfg, kind, hands, level)
	if kind == "wand" then
		return C.curve(cfg, "wand", level)
	elseif kind == "bow" then
		return C.curve(cfg, "bow", level)
	elseif kind == "crossbow" then
		return C.curve(cfg, "bow", level) + 3
	end
	return C.curve(cfg, "attack", level) + (hands == 2 and 3 or 0)
end

local FAMILY = {sword = "melee", axe = "melee", club = "melee", bow = "launcher", crossbow = "launcher",
	wand = "wand", throw = "throw", fist = "fist"}

-- ---------------------------------------------------------------------------------------------------------------
-- loading
-- ---------------------------------------------------------------------------------------------------------------
local function set(list)
	local s = {}
	for _, v in ipairs(list) do
		s[v] = true
	end
	return s
end

local function splitBar(s)
	local out = {}
	for part in tostring(s or ""):gmatch("[^|]+") do
		out[#out + 1] = part
	end
	return out
end

-- the class names of a line's base name ("Thief" -> Thief, Ninja, Samurai)
function C.lineClasses(cfg)
	local by = {}
	for _, l in ipairs(cfg.lines) do
		local names = {}
		for _, c in ipairs(l.classes) do
			names[#names + 1] = c.name
		end
		by[l.line] = names
	end
	return by
end

local function newWeapon(w)
	w.sources = w.sources or {}
	return w
end

-- the Chaos monsters' loot of stock ids: id -> {chance, level} (the best chance; the lowest level)
function C.chaosMonsterLoot()
	local out = {}
	local list = io.popen("cd data/monster/monsters/chaos && find . -name '*.xml' | LC_ALL=C sort")
	local paths = {}
	for path in list:lines() do
		paths[#paths + 1] = path
	end
	list:close()
	for _, path in ipairs(paths) do
		local text = C.readFile("data/monster/monsters/chaos/" .. path:gsub("^%./", ""))
		local lo, hi = text:match('<level%s+min="(%d+)"%s+max="(%d+)"')
		local level
		if lo then
			level = floor((tonumber(lo) + tonumber(hi)) / 2)
		else
			local hp = tonumber(text:match('<health%s+now="(%d+)"')) or 0
			local exp = tonumber(text:match('<monster%s[^>]*experience="(%d+)"')) or 0
			local byExp = 1.6 * math.sqrt(math.max(exp, 1))
			level = math.max(1, floor(math.max(byExp, math.min(hp / 60, byExp * 1.5)) + 0.5))
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

function C.load(cfg)
	stubEngine()
	local D = {weapons = {}, byId = {}, notes = {}}
	local lineOf = C.lineClasses(cfg)
	local allClasses = {}
	for _, l in ipairs(cfg.lines) do
		for _, c in ipairs(l.classes) do
			allClasses[#allClasses + 1] = c.name
		end
	end
	D.allClasses = allClasses

	-- stock weapons
	local names = {}
	for _, r in ipairs(C.csv("data/items/base_item_names.csv")) do
		names[tonumber(r.id)] = ((r.article ~= "" and r.article .. " ") or "") .. r.name
	end
	local values = {}
	for _, r in ipairs(C.csv("data/items/base_item_values.csv")) do
		values[tonumber(r.id)] = r
	end
	local crafted = {}
	for _, r in ipairs(C.csv("data/items/base_recipes.csv")) do
		crafted[tonumber(r.id)] = true
	end
	local chaosLoot = C.chaosMonsterLoot()
	local base = {}
	for _, r in ipairs(C.csv("data/items/base_weapons.csv")) do
		local id = tonumber(r.id)
		local classes
		if r.classes ~= "*" then
			classes = set(splitBar(r.classes))
		end
		local kind = r.kind
		local power
		if kind == "wand" then
			power = (tonumber(r.wmin) + tonumber(r.wmax)) / 2
		else
			power = tonumber(r.attack) + tonumber(r.element)
		end
		local w = newWeapon({id = id, name = names[id] or ("#" .. id), kind = kind, family = FAMILY[kind],
			hands = tonumber(r.hands), level = tonumber(r.level), power = power, classes = classes, origin = "stock",
			mana = tonumber(r.mana), charges = tonumber(r.charges)})
		local v = values[id]
		if v then
			if tonumber(v.buyers) > 0 then
				w.sources.shop = tonumber(v.buy_min)
			end
			if tonumber(v.loot_n) > 0 and tonumber(v.chance_max) >= cfg.minDropChance then
				w.sources.drop = {level = tonumber(v.loot_lv_min), chance = tonumber(v.chance_max)}
			end
			if v.reward == "1" then
				w.sources.reward = true
			end
		end
		if crafted[id] then
			-- a recipe that lists the weapon as a material only is not a way to get it: the file has products only
			w.sources.craft = true
		end
		local cm = chaosLoot[id]
		if cm and cm.chance >= cfg.minDropChance then
			local d = w.sources.drop
			if not d then
				w.sources.drop = {level = cm.level, chance = cm.chance}
			else
				d.level = math.min(d.level, cm.level)
				d.chance = math.max(d.chance, cm.chance)
			end
		end
		if w.charges > 0 then
			-- training weapons and one-shot elemental swords are used up: not a weapon to level with
			w.sources = {}
		end
		D.weapons[#D.weapons + 1] = w
		base[id] = w
	end
	D.base = base

	-- the equipment sets of pair 28
	local G = dofile("data/lib/chaos_gear_sets.lua")
	D.gearOn = G.PAIR28 == true
	local sourceLevel = {}
	for _, src in pairs(G.sources) do
		for _, group in ipairs({src.monsters or {}, src.bosses or {}}) do
			for _, m in ipairs(group) do
				sourceLevel[m[1]] = m[2]
			end
		end
	end
	local dropOf = {}
	if D.gearOn then
		for _, row in ipairs(G.lootRows()) do
			local d = dropOf[row[2]]
			local lv = sourceLevel[row[1]] or 0
			if not d then
				dropOf[row[2]] = {level = lv, chance = row[3]}
			else
				d.level = math.min(d.level, lv)
				d.chance = math.max(d.chance, row[3])
			end
		end
	end
	for _, p in ipairs(G.items.pieces) do
		local kind = p.kind
		if kind == "sword" or kind == "axe" or kind == "club" or kind == "bow" or kind == "crossbow" or kind == "wand"
			or kind == "rod" then
			local hands = (p.fit == "2" or kind == "bow" or kind == "crossbow") and 2 or 1
			local fam = kind == "rod" and "wand" or kind
			local power
			if fam == "wand" then
				power = C.curve(cfg, "wand", p.level) -- the set's mean wand damage is the curve at the piece's level
			else
				power = (p.stats.attack or 0) + (p.stats.elementFire or 0) + (p.stats.elementIce or 0)
					+ (p.stats.elementEarth or 0) + (p.stats.elementEnergy or 0) + (p.stats.elementDeath or 0)
					+ (p.stats.elementHoly or 0)
			end
			local w = newWeapon({id = p.id, name = p.name, kind = fam, rodOrWand = kind, family = FAMILY[fam], hands = hands,
				level = p.level, power = power, classes = set(p.classes), origin = "set:" .. p.set})
			local drop = dropOf[p.id]
			-- level gear (chaos_gear_sets.lua M.levelDrop): any monster hunted near the piece's level may drop it
			local ld = D.gearOn and G.levelDrop and G.levelDrop(p)
			if ld then
				if not drop then
					drop = {level = ld.level, chance = ld.chance}
				else
					drop = {level = math.min(drop.level, ld.level), chance = math.max(drop.chance, ld.chance)}
				end
			end
			if drop then
				w.sources.drop = drop
			end
			D.weapons[#D.weapons + 1] = w
		end
	end

	-- the uniques
	dofile("data/lib/chaos_item_mods.lua")
	dofile("data/lib/chaos_crafting.lua")
	dofile("data/lib/chaos_unique_items.lua")
	local archery = dofile("data/lib/chaos_archery_config.lua")
	local FAM_OF_SLOT = {sword = true, axe = true, club = true, distance = true, wand = true, weapon = true}
	for _, u in ipairs(ChaosUniqueItems) do
		if FAM_OF_SLOT[u.slot] then
			local b = base[u.id]
			local spec = ChaosUniqueSpecs[u.id] or {}
			if not b then
				D.notes[#D.notes + 1] = "unique " .. u.name .. " (" .. u.id .. ") has no stock weapon row"
			else
				local equip = spec.equip
				local classes = b.classes
				if equip and equip.lines and #equip.lines > 0 then
					local lineSet = {}
					for _, base in ipairs(equip.lines) do
						for _, c in ipairs(lineOf[base] or {}) do
							lineSet[c] = true
						end
					end
					local merged = {}
					for c in pairs(lineSet) do
						if not classes or classes[c] then
							merged[c] = true
						end
					end
					classes = merged
				end
				local atk = spec.attributes and spec.attributes.Attack
				local power
				if b.kind == "wand" then
					power = b.power
				else
					power = atk or b.power
				end
				local lvl = (equip and equip.level) or u.level or b.level
				local w = newWeapon({id = u.id, name = u.name, kind = b.kind, family = b.family, hands = b.hands, level = lvl,
					power = power, classes = classes, origin = "unique", unique = true})
				if archery.launchers[u.id] then
					w.kind = archery.launchers[u.id][1]
					w.family = "launcher"
				end
				w.sources.drop = {level = u.minMonsterLevel or lvl, chance = u.chance or 0, unique = true}
				D.weapons[#D.weapons + 1] = w
			end
		end
	end

	-- the Monk line's fist weapons (handled elsewhere; counted so the Monk rows are honest)
	dofile("data/lib/chaos_fist_weapons.lua")
	local fistDrop = {}
	for _, row in ipairs(ChaosFistWeapons.loot) do
		fistDrop[row[2]] = {level = 0, chance = row[3]}
	end
	for _, id in ipairs(ChaosFistWeapons.ids) do
		local it = ChaosFistWeapons.items[id]
		local w = newWeapon({id = id, name = it.name, kind = "fist", family = "fist", hands = 1, level = it.level,
			power = it.attack, classes = nil, origin = "fist"})
		w.sources.drop = fistDrop[id] or (it.unique and {level = it.level, chance = 1, unique = true}) or nil
		D.weapons[#D.weapons + 1] = w
	end

	-- the weapons above level 800: own monster loot rows (data/scripts/chaos/weapons800.lua) are the source counted here
	local W8 = dofile("data/lib/chaos_weapons800.lua")
	local w8Drop = {}
	for _, row in ipairs(W8.loot) do
		local d = w8Drop[row[2]]
		if not d then
			w8Drop[row[2]] = {level = 0, chance = row[3]}
		else
			d.chance = math.max(d.chance, row[3])
		end
	end
	local W8KIND = {sword2 = "sword", axe2 = "axe", club2 = "club"}
	for _, id in ipairs(W8.ids) do
		local it = W8.items[id]
		local kind = W8KIND[it.type] or (it.type == "rod" and "wand" or it.type)
		local st = it.stats
		local power
		if kind == "wand" then
			power = (st.wandMin + st.wandMax) / 2
		else
			power = (st.attack or 0) + (st.elementFire or 0) + (st.elementIce or 0) + (st.elementEarth or 0)
				+ (st.elementEnergy or 0) + (st.elementDeath or 0) + (st.elementHoly or 0)
		end
		local hands = (W8KIND[it.type] or kind == "bow" or kind == "crossbow") and 2 or 1
		local w = newWeapon({id = id, name = it.name, kind = kind, rodOrWand = it.type, family = FAMILY[kind], hands = hands,
			level = it.level, power = power, classes = set(it.classes), origin = "weapons800"})
		local d = w8Drop[id]
		if d and d.chance >= cfg.minDropChance then
			w.sources.drop = d
		end
		D.weapons[#D.weapons + 1] = w
	end

	for _, w in ipairs(D.weapons) do
		w.ratio = w.power / C.tier(cfg, w.kind, w.hands, math.max(w.level, 1))
		w.obtainable = next(w.sources) ~= nil
	end
	return D
end

-- ---------------------------------------------------------------------------------------------------------------
-- the audit
-- ---------------------------------------------------------------------------------------------------------------
function C.bandOf(cfg, level)
	for i, b in ipairs(cfg.bands) do
		if level >= b[1] and level < b[2] then
			return i
		end
	end
	return level < cfg.bands[1][1] and 1 or #cfg.bands
end

function C.suits(class, w)
	local famOk = false
	for _, f in ipairs(class.families) do
		if f == w.family then
			famOk = true
		end
	end
	if not famOk then
		return false
	end
	if class.hands2 and w.hands ~= 2 then
		return false
	end
	if class.bowOnly and w.kind ~= "bow" then
		return false
	end
	if w.classes and not w.classes[class.name] then
		return false
	end
	return true
end

-- audit.rows[i] = {line, class, cells = {{n, best, bestRatio, list}}}; weapons that are not obtainable are counted apart
function C.audit(cfg, D)
	local A = {rows = {}, unobtainable = {}, bands = cfg.bands}
	for _, w in ipairs(D.weapons) do
		if not w.obtainable and w.origin ~= "fist" then
			A.unobtainable[#A.unobtainable + 1] = w
		end
	end
	for _, l in ipairs(cfg.lines) do
		for _, class in ipairs(l.classes) do
			local row = {line = l.line, class = class.name, cells = {}}
			for i = 1, #cfg.bands do
				row.cells[i] = {n = 0, list = {}}
			end
			for _, w in ipairs(D.weapons) do
				if w.obtainable and C.suits(class, w) then
					local cell = row.cells[C.bandOf(cfg, w.level)]
					cell.n = cell.n + 1
					cell.list[#cell.list + 1] = w
					if not cell.best or w.ratio > cell.best.ratio then
						cell.best = w
					end
				end
			end
			for i, cell in ipairs(row.cells) do
				table.sort(cell.list, function(a, b)
					if a.level ~= b.level then
						return a.level < b.level
					end
					return a.id < b.id
				end)
			end
			A.rows[#A.rows + 1] = row
		end
	end
	return A
end

-- "ZERO", "ONE", "WEAK" or nil
function C.flag(cfg, cell)
	if cell.n == 0 then
		return "ZERO"
	end
	if cell.n < cfg.minOptions then
		return "ONE"
	end
	if cell.best.ratio < cfg.minPower then
		return "WEAK"
	end
	return nil
end

function C.cellText(cfg, cell)
	if cell.n == 0 then
		return "0"
	end
	return string.format("%d/%d", cell.n, floor(cell.best.ratio * 100 + 0.5))
end

local function allowed(cfg, row, bandLabel)
	if cfg.handledElsewhere[row.line] then
		return "handled elsewhere: " .. cfg.handledElsewhere[row.line]
	end
	for _, g in ipairs(cfg.knownGaps) do
		if g[1] == row.class and g[2] == bandLabel then
			return g[3]
		end
	end
	return nil
end

-- the failures --check reports: {class, band, flag, n, best}
function C.failures(cfg, A)
	local out = {}
	for _, row in ipairs(A.rows) do
		for i, cell in ipairs(row.cells) do
			local f = C.flag(cfg, cell)
			if f and not allowed(cfg, row, cfg.bands[i][3]) then
				out[#out + 1] = {class = row.class, band = cfg.bands[i][3], flag = f, n = cell.n,
					best = cell.best and cell.best.ratio}
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- output
-- ---------------------------------------------------------------------------------------------------------------
function C.markdown(cfg, A)
	local head, sep = {"Class"}, {"---"}
	for _, b in ipairs(cfg.bands) do
		head[#head + 1] = b[3]
		sep[#sep + 1] = "---:"
	end
	local lines = {"| " .. table.concat(head, " | ") .. " |", "|" .. table.concat(sep, "|") .. "|"}
	for _, row in ipairs(A.rows) do
		local cells = {row.class .. (cfg.handledElsewhere[row.line] and " *" or "")}
		for i, cell in ipairs(row.cells) do
			local t = C.cellText(cfg, cell)
			local f = C.flag(cfg, cell)
			if f and not allowed(cfg, row, cfg.bands[i][3]) then
				t = "**" .. t .. "!**"
			elseif f then
				t = t .. "!"
			end
			cells[#cells + 1] = t
		end
		lines[#lines + 1] = "| " .. table.concat(cells, " | ") .. " |"
	end
	return table.concat(lines, "\n") .. "\n"
end

function C.text(cfg, A)
	local out = {}
	local w = 12
	local head = string.format("%-" .. w .. "s", "class")
	for _, b in ipairs(cfg.bands) do
		head = head .. string.format(" %11s", b[3])
	end
	out[#out + 1] = head
	for _, row in ipairs(A.rows) do
		local s = string.format("%-" .. w .. "s", row.class)
		for i, cell in ipairs(row.cells) do
			local f = C.flag(cfg, cell)
			local t = C.cellText(cfg, cell) .. (f and ("!" .. f:sub(1, 1)) or "")
			s = s .. string.format(" %11s", t)
		end
		out[#out + 1] = s
	end
	out[#out + 1] = ""
	out[#out + 1] = "cell = obtainable weapons with a required level in the band / best power in % of the tier at the band's"
	out[#out + 1] = "own level; !Z zero, !O one option, !W best option under " .. floor(cfg.minPower * 100) .. "% of the tier"
	out[#out + 1] = "(fewer than " .. cfg.minOptions .. " options is flagged)"
	return table.concat(out, "\n") .. "\n"
end

function C.list(cfg, A, only)
	local out = {}
	for _, row in ipairs(A.rows) do
		if not only or row.class == only then
			out[#out + 1] = "== " .. row.class
			for i, cell in ipairs(row.cells) do
				out[#out + 1] = string.format("  [%s] n=%d", cfg.bands[i][3], cell.n)
				for _, w in ipairs(cell.list) do
					local src = {}
					for k in pairs(w.sources) do
						src[#src + 1] = k
					end
					table.sort(src)
					out[#out + 1] = string.format("      lv %-4d %-9s %dH %-34s power %5.1f (%3d%%) %s [%s]", w.level, w.kind, w.hands,
						w.name:sub(1, 34), w.power, floor(w.ratio * 100 + 0.5), w.origin, table.concat(src, ","))
				end
			end
		end
	end
	return table.concat(out, "\n") .. "\n"
end

-- ---------------------------------------------------------------------------------------------------------------
-- the README block
-- ---------------------------------------------------------------------------------------------------------------
C.README = "README.md"
C.BEGIN = "<!-- weapon-coverage:begin (luajit tools/weapon_coverage.lua --write) -->"
C.END = "<!-- weapon-coverage:end -->"

function C.readmeBlock(cfg, A)
	return C.BEGIN .. "\n\n" .. C.markdown(cfg, A) .. "\n" .. C.END
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
	local cfg = dofile("tools/weapon_coverage_config.lua")
	local D = C.load(cfg)
	local A = C.audit(cfg, D)
	local mode = args[1]
	if mode == "--md" then
		io.write(C.markdown(cfg, A))
	elseif mode == "--list" then
		io.write(C.list(cfg, A, args[2]))
	elseif mode == "--write" or mode == "--check" then
		local text = C.readFile(C.README)
		local new = C.readmeReplace(text, C.readmeBlock(cfg, A))
		if not new then
			io.stderr:write("server/README.md has no weapon-coverage block (markers " .. C.BEGIN .. ")\n")
			os.exit(1)
		end
		if mode == "--write" then
			local f = assert(io.open(C.README, "wb"))
			f:write(new)
			f:close()
			io.write("server/README.md weapon coverage table written\n")
			return
		end
		local bad = false
		for _, f in ipairs(C.failures(cfg, A)) do
			bad = true
			io.stderr:write(string.format("weapon coverage: %s, levels %s: %s (%d option(s)%s)\n", f.class, f.band, f.flag, f.n,
				f.best and string.format(", best %d%% of the tier", floor(f.best * 100 + 0.5)) or ""))
		end
		if new ~= text then
			bad = true
			io.stderr:write("server/README.md weapon coverage table is out of date: luajit tools/weapon_coverage.lua --write\n")
		end
		for _, n in ipairs(D.notes) do
			bad = true
			io.stderr:write("weapon coverage: " .. n .. "\n")
		end
		if bad then
			os.exit(1)
		end
		io.write("weapon coverage ok\n")
	else
		io.write(C.text(cfg, A))
		io.write(string.format("\n%d weapons, %d not obtainable\n", #D.weapons, #A.unobtainable))
		for _, n in ipairs(D.notes) do
			io.write("note: " .. n .. "\n")
		end
	end
end

if not WEAPON_COVERAGE_NO_MAIN then
	C.main(arg or {})
end

return C
