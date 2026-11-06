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
eq(#C.cards('frame', { src = src }), 2, 'title frame and one frame')
local have, all = C.count(sc); eq(have, 1, 'one owned shader'); eq(all, 2, 'two shaders, None not counted')

-- what a card draws
local look = C.cardLook('outfit', oc[2], temp)
eq(look.type, 129, 'outfit card look'); eq(look.addons, 1, 'owned addons'); eq(look.body, 20, 'current colours'); eq(look.mount, nil, 'no mount on an outfit card')
eq(C.cardLook('mount', mc[2], temp).type, 368, 'mount card is the mount alone'); eq(C.cardLook('mount', mc[2], temp).head, nil, 'no colours')
local wl = C.cardLook('wings', wc[2], temp); eq(wl.wings, 5, 'wings card'); eq(wl.type, 128, 'on the current outfit'); eq(wl.mount, 0, 'no mount on it')
eq(C.cardLook('aura', ac[2], temp).aura, 7, 'aura card'); eq(C.cardLook('shader', sc[2], temp).shader, 'chaos_ember_glow', 'shader card')
eq(C.cardLook('pet', pc[2], temp).type, 400, 'pet card'); eq(C.cardLook('outline', oc2[2], temp), nil, 'a text card has no look')
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
eq(C.hoverOption(temp, layers, 'chatcolor', C.cards('chatcolor', { src = src })[2], nil), nil, 'a chat colour shows nothing')
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
eq(by.shader.name, 'Ember Glow', 'shader label'); eq(by.outline.name, 'Gold Outline', 'outline name'); eq(by.outline.icon, nil, 'a text card')
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

if fails > 0 then print(fails .. ' of ' .. checks .. ' checks FAILED'); os.exit(1) end
print('customise tests OK (' .. checks .. ' checks)')
