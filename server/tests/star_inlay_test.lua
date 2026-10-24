-- Run from the server/ folder: luajit tests/star_inlay_test.lua (and lua5.3; CI runs both)
-- O181 (beta, 2026-10-24: "are the Star Extractor and the Common Three Stars Inlay Stone working?"). The base star system
-- (customs/tier_system) works end to end; this test drives it with the two fixes of tools/patch_star_inlay.py:
--   * tools/patch_star_inlay.py on short fixtures of the stock scripts and items.xml (written here): the patch applies, is
--     idempotent, parses in this interpreter, and the items.xml descriptions name the five sets;
--   * the patched stone script and extractor script run on a mocked engine (Action, Player, Item): a stone on an empty-star
--     piece with a rolled Chaos description keeps that text and adds one "Refined by" line, a stone on a plain piece
--     without text still gets the tier line, the extractor gives the stone back and removes the "Refined by" line,
--     a worn piece is refused by both and nothing is used up;
--   * star_inlay_core.lua: worn positions, the text helpers, the pt-BR refusal (i18n_strings.lua).

local checks, fails = 0, 0
local function ok(cond, label)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	ok(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

local function writeFile(path, text)
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
end
local function readFile(path)
	local f = assert(io.open(path, "rb"))
	local t = f:read("*a")
	f:close()
	return t
end

-- ---------------------------------------------------------------- the core
local K = dofile("data/scripts/chaos/star_inlay_core.lua")
ITEM_ATTRIBUTE_DESCRIPTION = 4

ok(K.isWorn({x = 65535, y = 1, z = 0}), "slot 1 (head) is worn")
ok(K.isWorn({x = 65535, y = 10, z = 0}), "slot 10 is worn")
ok(K.isWorn({x = 65535, y = 13, z = 0}), "slot 13 (badge) is worn")
ok(not K.isWorn({x = 65535, y = 64, z = 0}), "a container position (64 and up) is not worn")
ok(not K.isWorn({x = 65535, y = 0, z = 0}), "y 0 is not a slot")
ok(not K.isWorn({x = 32100, y = 32200, z = 7}), "a map position is not worn")
ok(not K.isWorn(nil), "no position is not worn")

eq(K.stripRefined("Item Level: 80\nRefined by Aria."), "Item Level: 80", "the line goes, the text stays")
eq(K.stripRefined("Refined by Aria."), "", "a text that is only the line")
eq(K.stripRefined("Tier I ( 1 Star )\nRefined by Mr. Aria Jones.\n"), "Tier I ( 1 Star )\n", "a name with a dot and a space")
eq(K.stripRefined("plain"), "plain", "no line, no change")
eq(K.refine("", "Tier I ( 2 Star )", "Aria"), "Tier I ( 2 Star )\nRefined by Aria.", "no own text: the tier line")
eq(K.refine("Item Level: 80. Quality: +5%", "Tier I ( 2 Star )", "Aria"),
	"Item Level: 80. Quality: +5%\nRefined by Aria.", "an own text stays")
eq(K.refine("Item Level: 80\nRefined by Bo.", "x", "Aria"), "Item Level: 80\nRefined by Aria.", "one line only")
eq(K.refine(nil, nil, "Aria"), "Refined by Aria.", "nothing at all")

-- ---------------------------------------------------------------- the patch tool on fixtures
local root = os.tmpname()
os.remove(root)
local data = root .. "/data"
os.execute("mkdir -p '" .. data .. "/scripts/customs/tier_system' '" .. data .. "/items'")

-- stock text, short: the table of the stock file is cut to two entries; every other line is the stock line
local UPGRADE = [[
print(">> Stars Upgrade System Loaded")

local upgradeTable = {
    [27134] = {
        [27113] = {transformId = 26813},
    },
}

local upgradeAction = Action()

function upgradeAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
    if not target:isItem() then
        player:sendCancelMessage('You must select an item.')
        player:getPosition():sendMagicEffect(CONST_ME_POFF)
        return true
    end

    local targetId = target.itemid
    local itemId = item.itemid

    local upgradeData = upgradeTable[itemId] and upgradeTable[itemId][targetId]

    if upgradeData then
        target:transform(upgradeData.transformId)
        player:sendTextMessage(MESSAGE_INFO_DESCR, "Successfully inlaid one common star.")
        target:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, ItemType(target:getId()):getDescription().."\nRefined by "..player:getName()..".")
        player:getPosition():sendMagicEffect(210)
        item:remove(1)
        playSound(player, "success.ogg")
    else
        player:sendCancelMessage('This item cannot be upgraded.')
    end

    return true
end

upgradeAction:id(27134, 27135)
upgradeAction:register()
]]
local EXTRACTOR = [[
local extractionTable = {
        [26813] = {transformId = 27113, addItem = 27134},
    }

    local starExtractor = Action()

    function starExtractor.onUse(player, item, fromPosition, target, toPosition, isHotkey)
        if not target:isItem() then
            player:sendCancelMessage('You must select an item.')
            player:getPosition():sendMagicEffect(CONST_ME_POFF)
            return true
        end

        local targetId = target.itemid
        local extractionData = extractionTable[targetId]

        if extractionData then
            target:transform(extractionData.transformId)
            player:addItem(extractionData.addItem, 1)
            player:sendTextMessage(MESSAGE_INFO_DESCR, "Successfully extracted.")
            player:getPosition():sendMagicEffect(211)
            item:remove(1)
            playSound(player, "inlay_star.ogg")
        else
            player:sendCancelMessage('Extraction not defined for this item.')
        end

        return true
    end

    starExtractor:id(27149)
    starExtractor:register()
]]
local ITEMS = [[
<?xml version="1.0" encoding="UTF-8"?>
<items>
	<item id="27133" name="Star Inlay Stone">
		<attribute key="weight" value="95" />
		<attribute key="description" value="Use this stone on certain equipment to inlay 3 stars." />
	</item>
	<item id="27134" name="Common Star Inlay Stone">
		<attribute key="weight" value="95" />
		<attribute key="description" value="Use this stone on certain equipment to inlay 1 Common Star." />
	</item>
	<item id="27149" name="Star Extractor">
		<attribute key="weight" value="225" />
		<attribute key="description" value="Use this extractor on star-encrusted equipment to extract them." />
	</item>
</items>
]]
local tier = data .. "/scripts/customs/tier_system/"
writeFile(tier .. "upgrade_system_tiers.lua", UPGRADE)
writeFile(tier .. "star_extractor.lua", EXTRACTOR)
writeFile(data .. "/items/items.xml", ITEMS)

local function run(extra)
	local h = io.popen("python3 -I tools/patch_star_inlay.py '" .. data .. "' " .. (extra or "") .. " 2>&1")
	local out = h:read("*a")
	h:close()
	return out
end

local chk = run("--check")
ok(chk:find("still to patch", 1, true) ~= nil, "--check finds work: " .. chk)
eq(readFile(tier .. "upgrade_system_tiers.lua"), UPGRADE, "--check writes nothing")
local dry = run("--dry-run")
eq(readFile(tier .. "star_extractor.lua"), EXTRACTOR, "--dry-run writes nothing")

local out1 = run()
ok(out1:find("the stone keeps the item text", 1, true) ~= nil and out1:find("a worn piece is refused", 1, true) ~= nil
	and out1:find("27149 described", 1, true) ~= nil, "first run reports its work: " .. out1)
local upgrade = readFile(tier .. "upgrade_system_tiers.lua")
local extractor = readFile(tier .. "star_extractor.lua")
local items = readFile(data .. "/items/items.xml")
ok(upgrade:find("StarInlay.refineItem(target, ItemType(target:getId()):getDescription(), player:getName())", 1, true) ~= nil,
	"the stone calls refineItem")
ok(upgrade:find('.."\\nRefined by "', 1, true) == nil, "the stock overwrite is gone")
ok(upgrade:find("if StarInlay.isWorn(toPosition) then", 1, true) ~= nil, "the stone refuses a worn piece")
ok(extractor:find("StarInlay.unrefineItem(target)", 1, true) ~= nil, "the extractor removes the line")
ok(extractor:find("        if StarInlay.isWorn(toPosition) then", 1, true) ~= nil, "the extractor refuses a worn piece (indent kept)")
ok(upgrade:sub(1, 12) == "local StarIn" and extractor:sub(1, 12) == "local StarIn", "both load the core first")
ok(items:find("Skeletal, Netherwave, Ironwrath, Blightwoven or Ashborne", 1, true) ~= nil, "items.xml names the five sets")
ok(items:find('inlay 3 stars. Works on a plain', 1, true) ~= nil, "the stock sentence stays in front")
ok(items:find("not worn", 1, true) ~= nil, "items.xml says not worn")
ok((loadstring or load)(upgrade) ~= nil and (loadstring or load)(extractor) ~= nil, "the patched scripts parse")

local out2 = run()
ok(out2:find("described", 1, true) == nil and out2:find("refused", 1, true) == nil, "second run: nothing to do: " .. out2)
eq(readFile(tier .. "upgrade_system_tiers.lua"), upgrade, "second run keeps the stone script")
eq(readFile(tier .. "star_extractor.lua"), extractor, "second run keeps the extractor script")
eq(readFile(data .. "/items/items.xml"), items, "second run keeps items.xml")
eq(run("--check"):find("still to patch", 1, true), nil, "--check is clean after the patch")

-- a base script that changed: the tool says so and writes nothing
writeFile(tier .. "upgrade_system_tiers.lua", "print('changed')\n")
ok(run():find("was not found", 1, true) ~= nil, "a changed base script is reported")
eq(readFile(tier .. "upgrade_system_tiers.lua"), "print('changed')\n", "and left alone")
writeFile(tier .. "upgrade_system_tiers.lua", upgrade)

-- ---------------------------------------------------------------- the patched scripts on a mocked engine
local actions = {}
function Action()
	local a = {}
	function a:id(...) self.ids = {...} end
	function a:register() actions[#actions + 1] = self end
	return a
end
CONST_ME_POFF, MESSAGE_INFO_DESCR = 3, 22
local typeDesc = {[26813] = "Tier I ( 1 Star )", [27113] = "No Tier ( Empty Stars )"}
function ItemType(id)
	return {getDescription = function() return typeDesc[id] or "" end}
end
local sounds = 0
function playSound() sounds = sounds + 1 end

local function newItem(id, desc, count)
	local it = {itemid = id, count = count or 1, attrs = {}, removed = 0}
	if desc then it.attrs[ITEM_ATTRIBUTE_DESCRIPTION] = desc end
	function it:isItem() return true end
	function it:getId() return self.itemid end
	function it:transform(newId) self.itemid = newId end
	function it:getAttribute(k) return self.attrs[k] or "" end -- the engine answers an empty string
	function it:setAttribute(k, v) self.attrs[k] = v end
	function it:removeAttribute(k) self.attrs[k] = nil end
	function it:remove(n) self.removed = self.removed + n end
	return it
end
local function newPlayer()
	local p = {name = "Aria", cancels = {}, texts = {}, added = {}}
	function p:getName() return self.name end
	function p:getPosition() return {sendMagicEffect = function() end} end
	function p:sendCancelMessage(t) self.cancels[#self.cancels + 1] = t end
	function p:sendTextMessage(_, t) self.texts[#self.texts + 1] = t end
	function p:addItem(id, n) self.added[#self.added + 1] = {id, n} end
	return p
end

assert((loadstring or load)(upgrade, "upgrade"))()
assert((loadstring or load)(extractor, "extractor"))()
eq(#actions, 2, "two actions registered")
local stone, extract = actions[1], actions[2]
ok(type(stone.onUse) == "function" and type(extract.onUse) == "function", "both have onUse")

local bag = {x = 65535, y = 65, z = 0}
local worn = {x = 65535, y = 1, z = 0}

-- 1. a stone on an empty-star piece that carries a rolled Chaos description (item level, modifiers)
do
	local p, st = newPlayer(), newItem(27134, nil, 5)
	local piece = newItem(27113, "Item Level: 120. Quality: +4%. +6% Critical Hit Chance")
	eq(stone.onUse(p, st, bag, piece, bag, false), true, "the stone is used")
	eq(piece.itemid, 26813, "the piece is now the 1-star variant")
	eq(piece.attrs[ITEM_ATTRIBUTE_DESCRIPTION], "Item Level: 120. Quality: +4%. +6% Critical Hit Chance\nRefined by Aria.",
		"the rolled text stays, one line added")
	eq(st.removed, 1, "one stone used up")
	eq(#p.cancels, 0, "no refusal")
	-- a second stone cannot be used on the same variant: the stock table has no entry for it
	local st2 = newItem(27134)
	stone.onUse(p, st2, bag, piece, bag, false)
	eq(st2.removed, 0, "a stone on a star variant is not used up")
	eq(p.cancels[#p.cancels], "This item cannot be upgraded.", "stock refusal kept")
end

-- 2. a stone on a piece without an own text: the tier line of the type, as the stock script wrote it
do
	local p, st = newPlayer(), newItem(27134)
	local piece = newItem(27113)
	stone.onUse(p, st, bag, piece, bag, false)
	eq(piece.attrs[ITEM_ATTRIBUTE_DESCRIPTION], "Tier I ( 1 Star )\nRefined by Aria.", "no own text: the tier line")
end

-- 3. the extractor: the stone comes back, the empty-star piece loses the line and keeps the rolled text
do
	local p, ex = newPlayer(), newItem(27149)
	local piece = newItem(26813, "Item Level: 120. Quality: +4%\nRefined by Aria.")
	eq(extract.onUse(p, ex, bag, piece, bag, false), true, "the extractor is used")
	eq(piece.itemid, 27113, "the piece is empty again")
	eq(piece.attrs[ITEM_ATTRIBUTE_DESCRIPTION], "Item Level: 120. Quality: +4%", "the line is gone, the text stays")
	eq(#p.added, 1, "one item given back")
	eq(p.added[1][1], 27134, "the stone of that tier and star count")
	eq(ex.removed, 1, "the extractor is used up")
end

-- 4. the extractor on a piece whose description was only the line: no attribute is left
do
	local p, ex = newPlayer(), newItem(27149)
	local piece = newItem(26813, "Tier I ( 1 Star )\nRefined by Aria.")
	piece.attrs[ITEM_ATTRIBUTE_DESCRIPTION] = "Refined by Aria."
	extract.onUse(p, ex, bag, piece, bag, false)
	eq(piece.attrs[ITEM_ATTRIBUTE_DESCRIPTION], nil, "only the line: the attribute goes")
	-- and a piece that never had a description attribute is not given one
	local plain = newItem(26813)
	extract.onUse(p, newItem(27149), bag, plain, bag, false)
	eq(plain.attrs[ITEM_ATTRIBUTE_DESCRIPTION], nil, "no attribute stays none")
end

-- 5. a worn piece: both refuse, nothing changes, nothing is used up
do
	local p, st, ex = newPlayer(), newItem(27134), newItem(27149)
	local empty, starred = newItem(27113, "Item Level: 9"), newItem(26813, "Item Level: 9\nRefined by Aria.")
	stone.onUse(p, st, bag, empty, worn, false)
	extract.onUse(p, ex, bag, starred, worn, false)
	eq(empty.itemid, 27113, "the worn empty piece is not changed")
	eq(starred.itemid, 26813, "the worn star piece is not changed")
	eq(empty.attrs[ITEM_ATTRIBUTE_DESCRIPTION], "Item Level: 9", "the worn piece keeps its text")
	eq(st.removed + ex.removed, 0, "nothing is used up")
	eq(#p.added, 0, "no stone given back")
	eq(#p.cancels, 2, "two refusals")
	eq(p.cancels[1], K.WORN_TEXT, "the refusal text (English without Chaos.t)")
end

-- 6. not an item: the stock refusal comes first
do
	local p = newPlayer()
	local notItem = {isItem = function() return false end}
	stone.onUse(p, newItem(27134), bag, notItem, bag, false)
	eq(p.cancels[1], "You must select an item.", "the stock 'select an item' refusal")
end

-- 7. the refusal in the player's language
do
	local strings = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
	ok(strings[K.WORN_TEXT] ~= nil and strings[K.WORN_TEXT] ~= K.WORN_TEXT, "i18n_strings.lua has the pt-BR refusal")
	Chaos = {t = function(_, key) return strings[key] or key end}
	local p = newPlayer()
	K.refuseWorn(p)
	eq(p.cancels[1], strings[K.WORN_TEXT], "Chaos.t answers in pt-BR")
	Chaos = nil
end

os.execute("rm -rf '" .. root .. "'")
print(string.format("star_inlay_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
