-- Driver of tools/audit_equip_tooltips.py (O490): builds the REAL item tooltip (data/scripts/chaos/item_tooltip_core.lua
-- T.build) of every item of a table, against a mocked engine, and prints what its requirement chips say.
-- Run from the server/ folder: luajit tools/audit_equip_tooltips.lua DATA_DIR ITEMS_TSV   (lua5.3 works as well)
--   DATA_DIR   an installed data folder: its movements/scripts/chaos_unique_equip.lua (the stock rules, O489) and, when it is
--              there, lib/chaos_equip_rules.lua (the generated rules, O490) are what the tooltip reads
--   ITEMS_TSV  one item type per line: id, level, magic level, vocation string, weapon type, slot position, ammo type, name
--              (level, magic level and vocation string are what the engine's item type holds; the audit works them out)
-- Output, tab separated, one line per tooltip:
--   P id level magic voc           a plain copy; voc is "-" when the tooltip has no class row
--   U id level magic voc equipLevel equipVocations entryLevel
--                                  a copy of a unique (ChaosUniqueById[id]); the spec's own rule: "-" without one
--   E id message                   the tooltip code failed on this item
local dataDir, tsv = arg[1], arg[2]
if not dataDir or not tsv then
	io.stderr:write("usage: luajit tools/audit_equip_tooltips.lua DATA_DIR ITEMS_TSV\n")
	os.exit(2)
end

ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_NAME, ITEM_ATTRIBUTE_ARTICLE = 1, 2, 3
ITEM_ATTRIBUTE_ATTACK, ITEM_ATTRIBUTE_DEFENSE, ITEM_ATTRIBUTE_EXTRADEFENSE = 4, 5, 6
ITEM_ATTRIBUTE_ARMOR, ITEM_ATTRIBUTE_HITCHANCE, ITEM_ATTRIBUTE_SHOOTRANGE, ITEM_ATTRIBUTE_ATTACK_SPEED = 7, 8, 9, 10
ITEM_ATTRIBUTE_CHARGES = 11
INDEX_WHEREEVER, FLAG_NOLIMIT, RETURNVALUE_NOERROR = -1, 1, 0
SLOTP_TWO_HAND, WEAPON_SHIELD, WEAPON_AMMO = 2048, 4, 7

local TYPES, order = {}, {}
for line in io.lines(tsv) do
	local f = {}
	for field in (line .. "\t"):gmatch("([^\t]*)\t") do
		f[#f + 1] = field
	end
	local id = tonumber(f[1])
	if id then
		TYPES[id] = {level = tonumber(f[2]) or 0, magic = tonumber(f[3]) or 0, voc = f[4] or "", weaponType = tonumber(f[5]) or 0,
			slot = tonumber(f[6]) or 0, ammo = tonumber(f[7]) or 0, name = f[8] or ""}
		order[#order + 1] = id
	end
end

function ItemType(id)
	local t = TYPES[id] or {}
	return {
		getId = function() return id end,
		getClientId = function() return id + 1000 end,
		getName = function() return t.name or "" end,
		getDescription = function() return "" end,
		isContainer = function() return false end,
		isStackable = function() return false end,
		getWeaponType = function() return t.weaponType or 0 end,
		getSlotPosition = function() return t.slot or 0 end,
		getAmmoType = function() return t.ammo or 0 end,
		getArmor = function() return 0 end,
		getAttack = function() return 0 end,
		getDefense = function() return 0 end,
		getExtraDefense = function() return 0 end,
		getHitChance = function() return 0 end,
		getShootRange = function() return 0 end,
		getAttackSpeed = function() return 0 end,
		getElementDamage = function() return 0 end,
		getElementType = function() return 0 end,
		getAbilities = function() return {} end,
		getMinReqLevel = function() return t.level or 0 end,
		getMinReqMagicLevel = function() return t.magic or 0 end,
		getVocationString = function() return t.voc or "" end,
		getCharges = function() return 0 end
	}
end

local Item = {}
Item.__index = Item
local function newItem(id)
	return setmetatable({id = id, attrs = {}, custom = {}}, Item)
end
function Item:getId() return self.id end
function Item:getCount() return 1 end
function Item:getWeight() return 100 end
function Item:getName() return ItemType(self.id):getName() end
function Item:getCustomAttribute(k) return self.custom[k:lower()] end
function Item:setCustomAttribute(k, v) self.custom[k:lower()] = v end
function Item:removeCustomAttribute(k) self.custom[k:lower()] = nil return true end
function Item:hasAttribute(k) return self.attrs[k] ~= nil end
function Item:getAttribute(k) return self.attrs[k] or (k == ITEM_ATTRIBUTE_DESCRIPTION and "" or nil) end
function Item:setAttribute(k, v) self.attrs[k] = v end
function Item:removeAttribute(k) self.attrs[k] = nil end
function Item:getParent() return nil end
function Item:getActionId() return 0 end
Game = {createItem = function(id) return newItem(id) end}

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/lib/chaos_crafting.lua")
dofile("data/lib/chaos_unique_items.lua")
pcall(dofile, "data/lib/chaos_unique_specs.lua")
dofile("data/scripts/chaos/item_tooltip_core.lua")
local T = ChaosItemTooltip

local function exists(path)
	local f = io.open(path, "r")
	if f then
		f:close()
		return true
	end
	return false
end

-- the stock rules the generated movement script publishes (O489) and the generated rules (O490), as the installed
-- server has them
local script = dataDir .. "/movements/scripts/chaos_unique_equip.lua"
if exists(script) then
	dofile(script)
end
local rules = dataDir .. "/lib/chaos_equip_rules.lua"
if exists(rules) and T.setEquipRules then
	T.setEquipRules(dofile(rules))
end

local function row(tip)
	local req = tip and tip.req or {}
	return tostring(req.level or 0), tostring(req.magic or 0), req.voc or "-"
end

for _, id in ipairs(order) do
	local ok, tip = pcall(T.build, newItem(id))
	if ok then
		print(table.concat({"P", id, row(tip)}, "\t"))
	else
		print(table.concat({"E", id, (tostring(tip):gsub("[\t\r\n]", " "))}, "\t"))
	end
	local entry = ChaosUniqueById and ChaosUniqueById[id]
	if entry then
		local item = newItem(id)
		item:setCustomAttribute("chaos_unique", 1)
		local okU, tipU = pcall(T.build, item)
		if okU then
			local spec = ChaosUniqueSpecs and ChaosUniqueSpecs[id]
			local equip = spec and spec.equip
			local own, lvl = "-", "-"
			if equip then
				lvl = tostring(equip.level or 0)
				own = table.concat(equip.vocations or {}, "|")
				if own == "" then
					own = "*"
				end
			end
			print(table.concat({"U", id, row(tipU)}, "\t") .. "\t" .. lvl .. "\t" .. own .. "\t" .. tostring(entry.level or 0))
		else
			print(table.concat({"E", id, (tostring(tipU):gsub("[\t\r\n]", " "))}, "\t"))
		end
	end
end
