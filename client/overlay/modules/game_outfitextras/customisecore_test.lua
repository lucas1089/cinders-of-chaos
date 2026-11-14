-- luajit customisecore_test.lua && lua5.3 customisecore_test.lua   (any directory; run from the repo root in CI)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'outfitextrascore.lua')
dofile(dir .. 'customisecore.lua')
local C, E = CustomiseCore, OutfitExtrasCore
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- the data of a character
local cosmetics = { line = 'ember', lineName = 'Ember', rows = {
  { id = 11, kind = 'outline', name = 'Gold Outline', owned = true, selected = true, art = 'gold', pulse = true },
  { id = 12, kind = 'outline', name = 'Void Outline', owned = true, art = 'void' },
  { id = 13, kind = 'outline', name = 'Storm Outline', owned = false, how = 'Store' },
  { id = 21, kind = 'footprint', name = 'Ember Prints', owned = true, art = 'ember' },
  { id = 31, kind = 'spellskin', name = 'Blue Flame', owned = true, line = 'ember', play = { { n = 'flame' } } },
  { id = 33, kind = 'spellskin', name = 'Red Flame', owned = true, selected = true, line = 'ember', play = { { n = 'red' } } },
  { id = 51, kind = 'killfx', name = 'Soul Burst', owned = true, play = { { n = 'burst' } } },
  { id = 41, kind = 'chatcolor', name = 'Ash', owned = true },
} }
local lists = {
  outfit = { { 128, 'Citizen', 3 }, { 129, 'Hunter', 1 }, { 130, 'Mage', 0, locked = true, how = 'Store' } },
  mount = { { 368, 'Widow Queen' }, { 370, 'Racing Bird', locked = true, how = 'Free' } },
  aura = { { 7, 0, 7, 'Ember Ring' }, { 8, 0, 8, 'Frost Ring', locked = true } },
  shader = { { id = 19, name = 'chaos_ember_glow', label = 'Ember Glow' }, { id = 20, name = 'chaos_frost_rime', label = 'Frost Rime', locked = true } },
}
local src = { cosmetics = cosmetics,
  wings = { stock = { { 5, 'Gold Wings' }, { 6, 'Ash Wings' } }, wardrobe = { { l = 7, n = 'Storm Wings', s = 'Store' } }, current = 6 },
  services = { frames = { 'frost' }, activeFrame = 'frost' },
  pets = { pets = { { species = 'ashwolf', name = 'Fang', level = 4, look = 400 } }, active = 'ashwolf',
    catalog = { { key = 'ashwolf', owned = true }, { key = 'emberfox', name = 'Ember Fox', how = 'Boss', look = 401 } } } }
local temp = { type = 128, head = 10, body = 20, legs = 30, feet = 40, addons = 1, mount = 368, wings = 6, aura = 0, shader = 'chaos_ember_glow' }
local rows = E.rows(src)

-- the categories and the strip
eq(#C.SLOTS, 13, 'thirteen strip cards'); eq(C.SLOTS[1], 'outfit', 'outfit first'); eq(C.SLOTS[13], 'pet', 'pet last')
local inSlots = {}
for _, k in ipairs(C.SLOTS) do inSlots[k] = true end
for _, k in ipairs(E.KEYS) do eq(inSlots[k], true, 'every extras row has a slot: ' .. k) end
for _, k in ipairs({ 'outfit', 'mount', 'wings', 'aura', 'shader' }) do eq(inSlots[k], true, 'look slot ' .. k) end
eq(C.label('outfit'), 'Outfit', 'label'); eq(C.label('frame'), 'Plate frame', 'extras label'); eq(C.tabLabel('primary'), 'Primary', 'tab label')
eq(C.fieldOf('head'), 'head', 'head field'); eq(C.fieldOf('primary'), 'body', 'primary is the body'); eq(C.fieldOf('secondary'), 'legs', 'secondary is the legs')
eq(C.fieldOf('detail'), 'feet', 'detail is the feet'); eq(C.fieldOf('x'), nil, 'unknown tab')

-- colours
local r, g, b = C.colorOf(0); eq(r + g + b, 765, 'index 0 is white')
r, g, b = C.colorOf(114); eq(r, 36, 'index 114 is dark grey'); eq(r == g and g == b, true, 'greys are grey')
local prev = 256
for i = 0, 6 do local x = C.colorOf(i * 19); eq(x < prev, true, 'grey ramp falls ' .. i); prev = x end
r, g, b = C.colorOf(4 * 19 + 18); eq(r, 255, 'last hue of a full row is red'); eq(g, 0, 'no green'); eq(b, 0, 'no blue')
eq(C.colorHex(0), '#ffffff', 'hex'); eq(C.colorHex(4 * 19 + 18), '#ff0000', 'hex red')
eq(C.colorHex(-5), '#ffffff', 'out of range falls back to 0'); eq(C.colorHex(133), '#ffffff', 'out of range high')
local seen, distinct = {}, 0
for i = 0, 132 do local h = C.colorHex(i); if not seen[h] then seen[h] = true; distinct = distinct + 1 end end
eq(distinct > 100, true, 'the palette has many colours')
eq(C.setColor(temp, 'head', 77).head, 77, 'head set'); eq(C.setColor(temp, 'detail', 999).feet, 132, 'clamped'); eq(temp.head, 10, 'the old outfit is kept')
eq(C.setColor(temp, 'nope', 5).head, 10, 'unknown tab changes nothing')

-- addons
eq(C.addonOwned(3, 1), true, 'addon 1 of 3'); eq(C.addonOwned(3, 2), true, 'addon 2 of 3'); eq(C.addonOwned(1, 2), false, 'addon 2 of 1')
eq(C.setAddon(temp, 2, true).addons, 3, 'addon 2 on'); eq(C.setAddon(temp, 1, false).addons, 0, 'addon 1 off'); eq(C.setAddon(temp, 1, true).addons, 1, 'already on')

-- cards of the look categories
local oc = C.cards('outfit', { lists = lists })
eq(#oc, 3, 'three outfits, no None card'); eq(oc[1].value, 128, 'owned first'); eq(oc[3].locked, true, 'locked last'); eq(oc[3].how, 'Store', 'source kept')
eq(oc[1].addons, 3, 'addon mask kept')
eq(#C.cards('outfit', { lists = lists, onlyMine = true }), 2, 'only mine drops the locked outfit')
eq(#C.cards('outfit', { lists = lists, search = ' HUNT ' }), 1, 'search is plain text in any case')
local mc = C.cards('mount', { lists = lists })
eq(#mc, 3, 'None and two mounts'); eq(mc[1].none, true, 'None first'); eq(mc[1].value, 0, 'mount none is 0')
eq(#C.cards('mount', { lists = lists, search = 'widow' }), 1, 'a search drops the None card'); eq(C.cards('mount', { lists = lists, search = 'widow' })[1].value, 368, 'found')
local ac = C.cards('aura', { lists = lists })
eq(ac[2].value, 7, 'the aura value is its client id'); eq(ac[2].text, 'Ember Ring', 'aura name'); eq(ac[3].locked, true, 'locked aura')
local sc = C.cards('shader', { lists = lists })
eq(sc[1].value, '', 'shader none is empty text'); eq(sc[2].value, 'chaos_ember_glow', 'shader value is the name'); eq(sc[2].text, 'Ember Glow', 'shader label')
eq(C.cards('outfit', {}), nil, 'no list yet: no cards'); eq(C.cards('mount', { lists = {} }), nil, 'no mount list yet')
-- cards of the extras
local wc = C.cards('wings', { src = src })
eq(#wc, 4, 'None, two owned wings, one locked'); eq(wc[1].none, true, 'wings none'); eq(wc[4].locked, true, 'locked wings'); eq(wc[4].how, 'Store', 'wings source')
local oc2 = C.cards('outline', { src = src })
eq(#oc2, 4, 'default, two owned, one locked outline'); eq(oc2[2].row.art, 'gold', 'the outline card carries its row'); eq(oc2[1].none, true, 'default is none')
eq(#C.cards('outline', { src = src, onlyMine = true }), 3, 'only mine, outlines'); eq(#C.cards('outline', { src = src, search = 'void' }), 1, 'search, outlines')
local pc = C.cards('pet', { src = src })
eq(#pc, 3, 'none, owned and locked pet'); eq(pc[2].look, 400, 'pet look'); eq(pc[3].look, 401, 'locked pet look'); eq(pc[1].value, '', 'pet none is empty text')
eq(C.cards('pet', { src = {} }), nil, 'no pet data yet')
eq(#C.cards('frame', { src = src }), 1 + #E.FRAME_CATALOG, 'title frame, the owned frame and the rest of the catalogue')
local fc = C.cards('frame', { src = src })
eq(fc[3].locked, true, 'a frame not owned is a locked card') eq(fc[3].how ~= nil, true, 'with how to get it')
local have, all = C.count(fc)
eq(all > 1, true, 'the title counts more than 0 of 0')
local have, all = C.count(sc); eq(have, 1, 'one owned shader'); eq(all, 2, 'two shaders, None not counted')

-- what a card draws
local look = C.cardLook('outfit', oc[2], temp)
eq(look.type, 129, 'outfit card look'); eq(look.addons, 1, 'owned addons'); eq(look.body, 20, 'current colours'); eq(look.mount, nil, 'no mount on an outfit card')
eq(C.cardLook('mount', mc[2], temp).type, 368, 'mount card is the mount alone'); eq(C.cardLook('mount', mc[2], temp).head, nil, 'no colours')
local wl = C.cardLook('wings', wc[2], temp); eq(wl.wings, 5, 'wings card'); eq(wl.type, 128, 'on the current outfit'); eq(wl.mount, 0, 'no mount on it')
eq(C.cardLook('aura', ac[2], temp).aura, 7, 'aura card'); eq(C.cardLook('shader', sc[2], temp).shader, 'chaos_ember_glow', 'shader card')
eq(C.cardLook('pet', pc[2], temp).type, 400, 'pet card'); 
-- an Outline card draws the bare figure with its outline on the tile's creature (O562: the tiles were empty squares)
local ol2 = C.cardLook('outline', oc2[2], temp)
eq(ol2.type, 128, 'outline card: the outfit being edited') eq(ol2.head, 10, 'its colours') eq(ol2.mount, 0, 'no mount') eq(ol2.wings, 0, 'no wings')
eq(ol2.aura, 0, 'no aura') eq(ol2.shader, '', 'no shader')
eq(C.cardOutline('outline', oc2[2]).art, 'gold', 'the outline art of the card') eq(C.cardOutline('outline', oc2[2]).pulse, true, 'pulse')
eq(C.cardOutline('outline', oc2[3]).art, 'void', 'second card') eq(C.cardOutline('outline', oc2[3]).pulse, false, 'no pulse')
eq(C.cardLook('outline', oc2[1], temp).type, 128, 'Default: the same figure') eq(C.cardOutline('outline', oc2[1]), nil, 'Default: no outline')
eq(C.cardOutline('footprint', oc2[2]), nil, 'other categories draw none') eq(C.cardOutline('outline', nil), nil, 'no card')
eq(C.cardOutline('outline', { value = 5, text = 'x', row = { kind = 'outline', id = 5 } }), nil, 'a row without art draws none')
eq(C.cardLook('mount', { none = true, value = 0 }, temp), nil, 'None of the others draws nothing')
eq(C.cardLook('mount', mc[1], temp), nil, 'None draws nothing')

-- applying a card
local o = C.applyCard(temp, 'outfit', oc[2]); eq(o.type, 129, 'look applied'); eq(o.addons, 1, 'addon kept (owned for both)')
o = C.applyCard({ type = 128, addons = 3 }, 'outfit', oc[2]); eq(o.addons, 1, 'addon 2 dropped: the new look does not own it')
o = C.applyCard(temp, 'mount', mc[1]); eq(o.mount, 0, 'None mount'); eq(temp.mount, 368, 'the old outfit is kept')
eq(C.applyCard(temp, 'wings', wc[2]).wings, 5, 'wings'); eq(C.applyCard(temp, 'aura', ac[2]).aura, 7, 'aura'); eq(C.applyCard(temp, 'shader', sc[1]).shader, '', 'shader none')
eq(C.applyCard(temp, 'outline', oc2[2]).type, 128, 'an extras card leaves the outfit')

-- layers
local layers = C.layerDefaults(temp, rows)
eq(layers.outfit, true, 'outfit layer on'); eq(layers.mount, true, 'mount worn'); eq(layers.wings, true, 'wings worn'); eq(layers.aura, false, 'no aura')
eq(layers.shader, true, 'shader worn'); eq(layers.outline, true, 'outline worn'); eq(layers.pet, true, 'pet out')
local none = C.layerDefaults({}, {}); eq(none.mount, false, 'bare outfit: no mount'); eq(none.outline, false, 'no rows: no outline layer'); eq(none.pet, false, 'no pet')
local pl = C.pickLayers({ mount = false }, 'mount', mc[2]); eq(pl.mount, true, 'a pick turns its layer on')
pl = C.pickLayers({ mount = true }, 'mount', mc[1]); eq(pl.mount, false, 'None turns it off')
pl = C.pickLayers({ outfit = true }, 'outfit', oc[1]); eq(pl.outfit, true, 'the outfit layer is the preview\'s own')
eq(C.pickLayers({ pet = false }, 'frame', nil).pet, false, 'a category without a layer')

-- the preview outfit
local sh = C.shown(temp, { outfit = true, mount = true, wings = true, aura = true, shader = true })
eq(sh.mount, 368, 'everything on'); eq(sh.wings, 6, 'wings on'); eq(sh.shader, 'chaos_ember_glow', 'shader on')
sh = C.shown(temp, { outfit = true, mount = false, wings = false, aura = false, shader = false })
eq(sh.mount, 0, 'mount hidden'); eq(sh.wings, 0, 'wings hidden'); eq(sh.shader, '', 'shader hidden'); eq(sh.type, 128, 'outfit kept'); eq(temp.mount, 368, 'the edited outfit is untouched')
sh = C.shown(temp, { outfit = false, mount = true, wings = true })
eq(sh.type, 128, 'plain figure'); eq(sh.head, 76, 'plain figure colours'); eq(sh.addons, 0, 'no addons on the plain figure'); eq(sh.mount, 368, 'extras stay on the plain figure')
eq(C.shown(temp, nil).mount, 368, 'no layers table: all shown')

-- values in use, what Ok sends
local vals = C.values(temp, rows, { outline = 12 }, layers)
eq(vals.outfit, 128, 'outfit value'); eq(vals.mount, 368, 'mount value'); eq(vals.outline, 12, 'picked outline'); eq(vals.pet, 'ashwolf', 'current pet'); eq(vals.wings, 6, 'wings from the outfit')
eq(vals.spellskin, 33, 'current skin'); eq(vals.frame, 'frost', 'current frame')
vals = C.values(temp, rows, {}, { mount = false, outline = false, pet = false, wings = false })
eq(vals.mount, 0, 'mount layer off'); eq(vals.outline, 0, 'outline layer off'); eq(vals.pet, '', 'pet layer off'); eq(vals.wings, 0, 'wings layer off')
local eff = C.effective(rows, { spellskin = 31 }, { outline = false, pet = false })
eq(eff.spellskin, 31, 'picks kept'); eq(eff.outline, 0, 'outline layer off sends the default'); eq(eff.pet, '', 'pet layer off dismisses')
local acts = E.plan(rows, eff)
eq(#acts, 3, 'skin, outline off and pet away'); eq(acts[1].kind, 'outline', 'outline first (window order)'); eq(acts[1].id, 0, 'default outline')
eq(acts[3].act, 'pet', 'pet action'); eq(acts[3].value, '', 'dismiss')
eq(#E.plan(rows, C.effective(rows, {}, layers)), 0, 'nothing changed, nothing sent')
local sent = C.outfitToSend(temp, { mount = false, wings = true, aura = true, shader = true }, function(s) return s == 'chaos_ember_glow' and s or '' end)
eq(sent.mount, 0, 'mount layer off is not sent'); eq(sent.wings, 6, 'wings sent'); eq(sent.shader, 'chaos_ember_glow', 'owned shader sent'); eq(temp.mount, 368, 'the edit is untouched')
eq(C.outfitToSend(temp, { shader = false }, nil).shader, '', 'shader layer off'); eq(C.outfitToSend({ type = 1 }, {}, nil).shader, '', 'no shader field')
eq(C.outfitToSend({ shader = 'gone' }, {}, function() return '' end).shader, '', 'a shader the list lacks is dropped')
eq(C.isCurrent('mount', mc[2], { mount = 368 }), true, 'current card'); eq(C.isCurrent('mount', mc[3], { mount = 368 }), false, 'other card')
eq(C.isCurrent('mount', mc[1], { mount = 0 }), true, 'None is current when no mount'); eq(C.isCurrent('mount', mc[1], {}), false, 'no value')

-- the preview option
local ol = C.outlineOption(rows, { outline = 11 }, layers)
eq(ol.kind, 'outline', 'outline option'); eq(ol.art, 'gold', 'its art'); eq(ol.pulse, true, 'pulse')
eq(C.outlineOption(rows, { outline = 11 }, { outline = false }), nil, 'layer off: no outline')
eq(C.outlineOption(rows, { outline = 0 }, layers), nil, 'default outline'); eq(C.outlineOption(rows, { outline = 999 }, layers), nil, 'unknown outline')
eq(C.outlineOption({}, { outline = 11 }, layers), nil, 'no rows yet')
local h = C.hoverOption(temp, { outfit = true, mount = true, wings = true }, 'wings', wc[2], nil)
eq(h.kind, 'look', 'a look card hovers as a look'); eq(h.outfit.wings, 5, 'hovered wings on the outfit')
h = C.hoverOption(temp, { outfit = true, wings = false }, 'wings', wc[2], nil); eq(h.outfit.wings, 5, 'a hidden layer shows while hovered')
h = C.hoverOption(temp, { outfit = false, mount = true }, 'outfit', oc[2], ol); eq(h.kind, 'bundle', 'with an outline: a bundle'); eq(h.parts[1].outfit.type, 129, 'the hovered outfit shows'); eq(h.parts[2].art, 'gold', 'outline kept')
h = C.hoverOption(temp, { outfit = false }, 'mount', mc[3], nil); eq(h.outfit.type, 129 == 0 and 0 or 128, 'a mount hovered on the real outfit, not the plain figure')
eq(C.hoverOption(temp, layers, 'outline', oc2[3], nil).kind, 'bundle', 'outline hover: the outfit with the outline')
eq(C.hoverOption(temp, layers, 'outline', oc2[3], nil).parts[2].art, 'void', 'its art')
eq(C.hoverOption(temp, layers, 'outline', oc2[1], nil), nil, 'default outline: nothing to show')
local fh = C.hoverOption(temp, layers, 'footprint', C.cards('footprint', { src = src })[2], nil); eq(fh.kind, 'footprint', 'prints'); eq(fh.art, 'ember', 'print art')
local sk = C.hoverOption(temp, layers, 'spellskin', C.cards('spellskin', { src = src })[2], nil); eq(sk.kind, 'effects', 'spell skin plays'); eq(sk.killfx, nil, 'on the figure')
local kf = C.hoverOption(temp, layers, 'killfx', C.cards('killfx', { src = src })[2], nil); eq(kf.killfx, true, 'kill effect on a troll')
-- O497: a chat colour card shows a sample of the colour (it showed nothing before: no picture, nothing on the stage)
local ccard = C.cards('chatcolor', { src = src })[2]
local chh = C.hoverOption(temp, layers, 'chatcolor', ccard, nil)
eq(chh.kind, 'chatcolor', 'a chat colour hovers as a sample'); eq(chh.color, nil, 'this row has no colour: the stock one')
local ph = C.hoverOption(temp, layers, 'pet', pc[2], nil); eq(ph.kind, 'subject', 'a pet is drawn alone'); eq(ph.look, 400, 'its look')
eq(C.hoverOption(temp, layers, 'mount', nil, nil), nil, 'no card')

-- Equipped now
local strip = C.stripRows({ temp = temp, lists = lists, src = src, rows = rows, chosen = {}, layers = layers })
eq(#strip, 13, 'one row per slot')
local by = {}
for _, s in ipairs(strip) do by[s.key] = s end
eq(by.outfit.name, 'Citizen', 'outfit name'); eq(by.outfit.icon.kind, 'outfit', 'outfit icon'); eq(by.outfit.icon.outfit.type, 128, 'outfit icon look')
eq(by.mount.name, 'Widow Queen', 'mount name'); eq(by.mount.icon.outfit.type, 368, 'mount icon is the mount')
eq(by.wings.name, 'Ash Wings', 'wings name'); eq(by.wings.icon.outfit.wings, 6, 'wings icon')
eq(by.aura.name, '-', 'no aura'); eq(by.aura.empty, true, 'aura is empty'); eq(by.aura.icon, nil, 'no icon')
eq(by.shader.name, 'Ember Glow', 'shader label'); eq(by.outline.name, 'Gold Outline', 'outline name'); eq(by.outline.icon.kind, 'outfit', 'outline strip card: the figure') eq(by.outline.icon.outline.art, 'gold', 'with the outline')
eq(by.spellskin.name, 'Red Flame', 'skin name'); eq(by.spellskin.icon.kind, 'play', 'skin icon is its effect'); eq(by.killfx.name, '-', 'no kill effect')
eq(by.footprint.name, '-', 'no footprints'); eq(by.frame.name, 'Frost', 'frame name'); eq(by.pet.name, 'Fang (level 4)', 'pet name'); eq(by.pet.icon.outfit.type, 400, 'pet icon')
eq(by.outfit.label, 'Outfit', 'label'); eq(by.frame.label, 'Plate frame', 'frame label')
strip = C.stripRows({ temp = temp, lists = lists, src = src, rows = rows, chosen = { footprint = 21, killfx = 51 }, layers = { mount = false, outline = false, pet = false, wings = true, shader = true } })
by = {}
for _, s in ipairs(strip) do by[s.key] = s end
eq(by.mount.name, '-', 'mount layer off: empty'); eq(by.outline.name, '-', 'outline layer off'); eq(by.pet.name, '-', 'pet layer off')
eq(by.footprint.name, 'Ember Prints', 'a pick shows at once'); eq(by.footprint.icon.kind, 'print', 'print icon'); eq(by.footprint.icon.art, 'ember', 'print art'); eq(by.killfx.icon.kind, 'play', 'kill effect icon')
strip = C.stripRows({ temp = temp, lists = {}, src = {}, rows = {}, chosen = {}, layers = layers })
by = {}
for _, s in ipairs(strip) do by[s.key] = s end
eq(by.outfit.name, '128', 'the look id when the list has not come'); eq(by.pet.loading, true, 'no pet data: loading'); eq(by.mount.name, '368', 'mount id until the list comes')
eq(#C.stripRows(nil), 13, 'no context still has the slots')

-- ---------------------------------------------------------------- samples (O497)
dofile(dir .. '../game_lookpreview/lookpreview_core.lua')
local P = LookPreviewCore
local sdata = dofile(dir .. '../../../../server/data/scripts/chaos/cosmetics_config.lua')
-- which sample a card of each kind gets, from the row the server sent
local row = { id = 201, kind = 'lootbeam', name = 'Ember Labels', owned = true, accent = '#461809f0' }
local sc1 = C.sampleOption('lootbeam', { value = 201, row = row })
eq(sc1.kind, 'lootlabel', 'loot label card'); eq(sc1.accent, '#461809f0', 'its accent from the row')
eq(P.sampleOf(sc1).bg, '#461809f0', 'drawn on that background')
eq(P.sampleOf(C.sampleOption('lootbeam', { value = 0, none = true, text = 'Default' })).stock, true, 'the Default loot label is the stock one')
local sc2 = C.sampleOption('chatcolor', { value = 301, row = { kind = 'chatcolor', color = '#ff9a4a' } })
eq(sc2.kind, 'chatcolor', 'chat colour card'); eq(sc2.color, '#ff9a4a', 'its colour from the row')
eq(P.sampleOf(C.sampleOption('chatcolor', { value = 0, none = true })).color, P.CHAT_TEXT, 'the Default chat colour is the stock one')
local sc3 = C.sampleOption('frame', { value = 'frost', text = 'Frost' })
eq(sc3.kind, 'nameplate', 'plate frame card'); eq(sc3.frame, 'frost', 'its frame'); eq(C.sampleOption('frame', { value = '', none = true }).frame, 'default', 'Title frame: the stock plate')
for _, k in ipairs({ 'outfit', 'mount', 'wings', 'aura', 'shader', 'outline', 'spellskin', 'killfx', 'footprint', 'pet' }) do
  eq(C.sampleOption(k, { value = 1, row = row }), nil, 'no sample for ' .. k)
end
eq(C.sampleOption('lootbeam', nil), nil, 'no card')
-- the real cards of the test character
local lootRow = { key = 'lootbeam', options = { { text = 'Default', value = 0 }, { text = 'Ember Labels', value = 201, row = row } }, current = 0 }
local chatRows = E.rows(src)
local frameRow
for _, r in ipairs(chatRows) do if r.key == 'frame' then frameRow = r end end
local ch = C.cards('frame', { src = src })
eq(ch[1].none, true, 'the Title frame card is the first'); eq(C.sampleOption('frame', ch[2]).frame, 'frost', 'a frame card from the services list')
local lh = C.hoverOption(temp, layers, 'lootbeam', { value = 201, row = row, text = 'Ember Labels' }, nil)
eq(lh.kind, 'lootlabel', 'hover: a loot label sample'); eq(lh.accent, '#461809f0', 'its accent')
local fhv = C.hoverOption(temp, layers, 'frame', ch[2], nil); eq(fhv.kind, 'nameplate', 'hover: a plate frame sample'); eq(fhv.frame, 'frost', 'frost')
-- the outline in use stays on the figure while a sample is pointed at
local olOpt = { kind = 'outline', art = 'gold', pulse = true }
local hb = C.hoverOption(temp, layers, 'lootbeam', { value = 201, row = row }, olOpt)
eq(hb.kind, 'bundle', 'with an outline: a bundle'); eq(hb.parts[1].art, 'gold', 'the outline kept'); eq(P.sampleOf(hb).kind, 'lootlabel', 'and the sample')
local pp, pl = P.compose('own', temp, hb)
eq(pl.art, 'gold', 'the outline reaches the engine call'); eq(pp.type, 128, 'the character as worn')
-- what the stage keeps while nothing is under the mouse: the value in use of the category looked at
local crows = { lootRow, { key = 'chatcolor', options = { { text = 'Default', value = 0 }, { text = 'Cinder', value = 301, row = { color = '#ff9a4a' } } }, current = 0 },
  { key = 'outline', options = { { text = 'Default', value = 0 }, { text = 'Gold', value = 11, row = { id = 11, kind = 'outline', art = 'gold' } } }, current = 0 } }
local rest = C.restOption('lootbeam', crows, { lootbeam = 201, outline = 0 }, {})
eq(rest.kind, 'lootlabel', 'a picked loot label stays on the stage'); eq(rest.accent, '#461809f0', 'with its accent')
rest = C.restOption('chatcolor', crows, { chatcolor = 301 }, {}); eq(rest.color, '#ff9a4a', 'a picked chat colour stays')
rest = C.restOption('lootbeam', crows, { lootbeam = 0 }, {}); eq(P.sampleOf(rest).stock, true, 'nothing picked: the stock label')
rest = C.restOption('outfit', crows, { lootbeam = 201 }, {}); eq(rest, nil, 'another category: no sample')
rest = C.restOption('lootbeam', crows, { lootbeam = 201, outline = 11 }, {})
eq(rest.kind, 'bundle', 'the outline in use and the sample'); eq(rest.parts[1].art, 'gold', 'outline first'); eq(rest.parts[2].kind, 'lootlabel', 'sample second')
rest = C.restOption('outfit', crows, { outline = 11 }, {}); eq(rest.art, 'gold', 'the outline alone as before')
eq(C.restOption('lootbeam', {}, { lootbeam = 201 }, {}), nil, 'no rows yet: nothing')
eq(C.restOption('lootbeam', crows, { lootbeam = 999 }, {}), nil, 'a value the row does not have: nothing')
-- Equipped now: the same sample next to the name
local sstrip = C.stripRows({ temp = temp, lists = lists, src = { cosmetics = { rows = {
  { id = 201, kind = 'lootbeam', name = 'Ember Labels', owned = true, selected = true, accent = '#461809f0' },
  { id = 301, kind = 'chatcolor', name = 'Cinder', owned = true, selected = true, color = '#ff9a4a' } } }, services = { frames = { 'frost' }, activeFrame = 'frost' } },
  rows = E.rows({ cosmetics = { rows = {
    { id = 201, kind = 'lootbeam', name = 'Ember Labels', owned = true, selected = true, accent = '#461809f0' },
    { id = 301, kind = 'chatcolor', name = 'Cinder', owned = true, selected = true, color = '#ff9a4a' } } }, services = { frames = { 'frost' }, activeFrame = 'frost' } }),
  chosen = {}, layers = layers })
local sby = {}
for _, r in ipairs(sstrip) do sby[r.key] = r end
eq(sby.lootbeam.name, 'Ember Labels', 'loot label name'); eq(sby.lootbeam.icon.kind, 'sample', 'loot label tile: a sample'); eq(sby.lootbeam.icon.option.accent, '#461809f0', 'its accent')
eq(sby.chatcolor.icon.kind, 'sample', 'chat colour tile: a sample'); eq(sby.chatcolor.icon.option.color, '#ff9a4a', 'its colour')
eq(sby.frame.icon.kind, 'sample', 'plate frame tile: a sample'); eq(sby.frame.icon.option.frame, 'frost', 'its frame')
eq(by.lootbeam.icon, nil, 'nothing worn: no sample on the empty tile'); eq(by.chatcolor.empty, true, 'chat colour empty')
-- the locked cards stay dimmed but readable
eq(C.cardOpacity('chatcolor', { locked = true }, 0.45), 0.7, 'a locked sample card is dimmed less') eq(C.cardOpacity('lootbeam', { locked = true }, 0.45), 0.7, 'loot label too')
eq(C.cardOpacity('chatcolor', { locked = true }, 0.9), 0.9, 'never dimmer than the base rule gives')
eq(C.cardOpacity('chatcolor', {}, 0.45), nil, 'an owned card: untouched'); eq(C.cardOpacity('outfit', { locked = true }, 0.45), nil, 'other categories keep the rule')
local unl = io.open(dir .. '../game_unlocks/unlocks_core.lua', 'rb'):read('*a')
eq(unl:find('U.LOCKED_OPACITY = 0.45', 1, true) ~= nil, true, 'the base locked opacity this relies on')
-- every real row of the server: its colours parse, and a locked card's sample keeps 3:1
local function rgb(h) return tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16), #h == 9 and tonumber(h:sub(8, 9), 16) / 255 or 1 end
local function lin(c) c = c / 255 if c <= 0.03928 then return c / 12.92 end return ((c + 0.055) / 1.055) ^ 2.4 end
local function lum(t) return 0.2126 * lin(t[1]) + 0.7152 * lin(t[2]) + 0.0722 * lin(t[3]) end
local function over(h, under, k) local r, g, b, a = rgb(h) local ur, ug, ub = rgb(under) k = a * k return { r * k + ur * (1 - k), g * k + ug * (1 - k), b * k + ub * (1 - k) } end
local function ratio(a, b) local l1, l2 = lum(a), lum(b) if l1 < l2 then l1, l2 = l2, l1 end return (l1 + 0.05) / (l2 + 0.05) end
local PANEL, nLoot, nChat, worst = '#141110', 0, 0, 99
for _, c in ipairs(sdata.cosmetics) do
  if c.kind == 'lootbeam' or c.kind == 'chatcolor' then
    local card = { value = c.id, text = c.name, row = c, locked = true }
    local o = C.sampleOption(c.kind == 'lootbeam' and 'lootbeam' or 'chatcolor', card)
    local smp = P.sampleOf(o)
    local op = C.cardOpacity(c.kind, card, 0.45)
    local r
    if c.kind == 'lootbeam' then
      nLoot = nLoot + 1
      eq(smp.kind, 'lootlabel', 'row ' .. c.key) eq(smp.stock, false, 'row ' .. c.key .. ' has its own accent') eq(smp.bg, c.accent, 'accent parsed: ' .. c.key)
      r = ratio(over(P.LABEL_RARITY, PANEL, op), over(smp.bg, PANEL, op))
    else
      nChat = nChat + 1
      eq(smp.kind, 'chatcolor', 'row ' .. c.key) eq(smp.stock, false, 'row ' .. c.key .. ' has its own colour') eq(smp.color, c.color, 'colour parsed: ' .. c.key)
      r = ratio(over(smp.color, PANEL, op), over(P.CHAT_BG, PANEL, op))
    end
    worst = math.min(worst, r)
    eq(r >= 3.0, true, 'a locked sample stays readable: ' .. c.key .. ' ' .. string.format('%.2f', r))
  end
end
eq(nLoot >= 5 and nChat >= 6, true, 'the server has loot label and chat colour rows: ' .. nLoot .. ' ' .. nChat)

-- dissolve kill effects (O563): the row's mode and tint reach the hover option and the tile picture
local drow = { id = 61, kind = 'killfx', name = 'Windswept', owned = true, play = { { n = 'puff' } }, dissolve = 'sand', tint = 4 }
local dh = C.hoverOption(temp, layers, 'killfx', { value = 61, text = 'Windswept', row = drow }, nil)
eq(dh.kind, 'effects', 'a dissolve kill effect plays as effects') eq(dh.killfx, true, 'on a dying monster')
eq(dh.dissolve.m, 'sand', 'hover option: mode') eq(dh.dissolve.t, 4, 'hover option: tint')
eq(C.dissolveIcon(drow), '/modules/game_killdissolve/images/sand_4', 'tile picture path')
eq(C.dissolveIcon({ kind = 'killfx', play = { { n = 'x' } } }), nil, 'a plain kill effect has no dissolve picture')
eq(C.dissolveIcon({ kind = 'spellskin', dissolve = 'sand' }), nil, 'only kill effects dissolve')
eq(C.dissolveIcon({ kind = 'killfx', dissolve = '../x' }), nil, 'a bad mode name is no path')
eq(C.dissolveOf({ kind = 'killfx', dissolve = 'ash', tint = 99 }).t, 7, 'tint capped')
eq(C.dissolveOf({ kind = 'killfx', dissolve = 'ash', tint = -2 }).t, 0, 'tint floor')
eq(C.hoverOption(temp, layers, 'killfx', { value = 51, text = 'Soul Burst', row = cosmetics.rows[7] }, nil).dissolve, nil, 'a plain kill effect hovers without a dissolve')

if fails > 0 then print(fails .. ' of ' .. checks .. ' checks FAILED'); os.exit(1) end
print('customise tests OK (' .. checks .. ' checks)')
