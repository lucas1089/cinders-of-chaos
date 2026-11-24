-- Spell ranks and Forms in the Spellbook (O686 phase 5). Server: spell_ranks.lua / spell_forms.lua, extended opcode 168; the
-- rules and the message shapes are ranklogic.lua (tested), the Forms are forms_data.lua (generated, phase 4).
-- Behind the server's switch (spell_ranks_config.lua `enabled`): while the server sends no state, or state.on is false, every
-- function here answers "nothing" and the Spellbook shows nothing new (no bars, no Upgrades button, no hub badge).
--
-- What the Spellbook (game_spellbook) uses:
--   isOn()                      the switch
--   rowInfo(spellId)            {rank, percent, tip} for the thin bar and the rank number of a row, nil when off / no rank
--   canShowTab(spell)           the Upgrades button shows for this spell
--   fill(panel, spell)          draws the Upgrades tab into the SpellUpgrades widget of the details panel
--   ask(force)                  asks the server for the state (on opening the Spellbook), at most every few seconds
-- The hub menu's Spellbook card shows getPickableCount() (client_chaos_topbar CARD_POINTS): the spells with a Form to pick.
-- Awakening (phase 7): the Upgrades tab has a second view of the spell, switched by a button next to the rank: the Seals, the three slots with
-- their costs, the awakened name with the sentences of its signature effect, and the Awaken button with its confirm box (awakelogic.lua,
-- awakened_data.lua; server spell_awakening.lua). awakenedName(spellId) is what the Spellbook shows as the spell's name while it is awakened.
-- Combos (phase 6): the server's `combo {id, n, x, y, z}` becomes a short label over the target (the engine's animated text, in the
-- colour of the combo) and one of two chimes (sounds/combo_a.ogg for an element reaction, combo_b.ogg for a signature combo, from
-- tools/gen_combo_sounds.py). The rules and the throttle are combologic.lua (tested). A rank-up arrives as a `rank` message, so the
-- timer below only asks again now and then, as a fallback.

local L = ChaosRankLogic
local CL = ChaosComboLogic
local AL = ChaosAwakeLogic
local OPCODE = L.OPCODE

local ASK_GAP = 5          -- seconds between two asks from the client (the server allows one per 2 s)
local POLL_SECONDS = 300   -- while the switch is on: a fallback only, the server pushes a `rank` message at every rank-up (phase 6)
local START_DELAY = 6000   -- ms after login before the first ask

local awake                -- AL.cleanState of the last `awakened` (the Seals and the slots), nil before it
local view = 'forms'      -- the Upgrades tab shows the Forms or the Awakening of the spell
local onAwakenClick       -- a click on the Awaken button (below)
local state                -- L.cleanState of the last `state`, nil before it (or the switch is off)
local picks = {}           -- spell id -> {f1, f2}
local lastPick             -- {spell, tier, at}: the last pick of this session (its free change window)
local panel                -- the SpellUpgrades widget filled last
local shownSpell           -- its spell
local shownId
local message              -- {text, good, id} of the last pick answer, shown under the spell it was for
local askedAt = -100
local pollEvent, startEvent
local lastBadge = -1
local onPickClick      -- a click on a Form button (below)
local comboGate = CL.newGate()
local soundWarned = false

local GOLD, DIM, GOOD, BAD = '#e8b84a', '#8c8070', '#4fd07f', '#e03a1e'
local CELL_ON, CELL_OFF = '#e8b84a', '#1a1416'

-- ---------------------------------------------------------------- small helpers
local function now() return os.time() end

local function clock() return g_clock and g_clock.seconds and g_clock.seconds() or 0 end

-- 1234567 as the language writes it (ChaosLocale: 1.234.567 in pt-BR)
local function gold(n)
  n = math.floor(tonumber(n) or 0)
  local c = rawget(_G, 'ChaosLocale')
  if c and c.int then return c.int(n) end
  return tostring(n)
end

-- a decimal as the language writes it: 0.9 -> "0,9" in pt-BR
local function decimal(v, fmt)
  local text = string.format(fmt or '%.4g', v)
  local c = rawget(_G, 'ChaosLocale')
  if c and c.localize then return c.localize(text) end
  return text
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if not protocol then return false end
  protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data }))
  return true
end

local function playerLevel()
  local p = g_game.getLocalPlayer and g_game.getLocalPlayer()
  return p and p.getLevel and p:getLevel() or 0
end

local function rules()
  return L.pickRules(rawget(_G, 'ChaosFormsData'))
end

-- ---------------------------------------------------------------- what the Spellbook and the hub ask
function isOn()
  return L.isOn(state)
end

-- O752: the level of a spell from the Spellbook's list (nil when the list has not come yet: then no level gate is counted)
local function learnOf(id)
  local book = modules and modules.game_spellbook
  if book and book.spellLevel then
    local ok, v = pcall(book.spellLevel, id)
    if ok then return v end
  end
  return nil
end

function getPickableCount()
  return L.pickableCount(state, picks, rawget(_G, 'ChaosFormsData'), playerLevel(), learnOf)
end

-- O752: the next spell path milestone of the character's class: short, long text (nil when none is known)
function nextMilestone()
  if not L.isOn(state) then return nil end
  return L.milestoneText(state.ms, playerLevel(), tr)
end

function canShowTab(spell)
  local id = spell and tonumber(spell.id)
  return id ~= nil and L.isOn(state) and L.isRankable(state, rawget(_G, 'ChaosFormsData'), id)
end

-- the row of the Spellbook: {rank, percent, tip}
function rowInfo(spellId)
  local e = L.rankEntry(state, spellId)
  if not e or e.rank <= 0 and e.into <= 0 then return nil end
  local tip
  if e.rank >= L.MAX_RANK then
    tip = tr('Rank %d of %d (top rank)', e.rank, L.MAX_RANK)
  else
    tip = tr('Rank %d of %d: %s of %s SP to the next rank', e.rank, L.MAX_RANK, decimal(e.into, '%.2f'), decimal(e.cost, '%.2f'))
  end
  return { rank = e.rank, percent = L.rowPercent(e), tip = tip }
end

-- is the game's language pt-BR (the awakened names are in the data in both languages)
local function isPt()
  local c = rawget(_G, 'ChaosLocale')
  return c ~= nil and c.lang == 'pt-BR'
end

-- the name the Spellbook shows for a spell while it is awakened (nil when it is not, or while the switch is off)
function awakenedName(spellId)
  if not L.isOn(state) then return nil end
  return AL.shownName(rawget(_G, 'ChaosAwakenedData'), awake, spellId, isPt())
end

local function refreshBadge()
  local n = getPickableCount()
  if n == lastBadge then return end
  lastBadge = n
  local top = modules and modules.client_chaos_topbar
  if top and top.ChaosTopBar and top.ChaosTopBar.refresh then pcall(top.ChaosTopBar.refresh) end
end

-- ---------------------------------------------------------------- combos (phase 6)
-- the label over the target: the engine's animated text, the same path as the damage numbers (no new engine call). false when the client
-- has no such text (the label is skipped, the chime still plays)
local function drawLabel(c, text)
  if not (AnimatedText and AnimatedText.create and g_map and g_map.addAnimatedText) then return false end
  local ok, err = pcall(function()
    local t = AnimatedText.create()
    t:setText(text)
    t:setColor(c.color)
    g_map.addAnimatedText(t, c.pos)
  end)
  if not ok and g_logger then g_logger.warning('[spellranks] combo label: ' .. tostring(err)) end
  return ok
end

-- one of the two chimes on the Effect channel (as the loot filter plays its rule sounds; needs base patch 0032, else silence)
local function playCombo(file)
  if not g_sounds then
    if not soundWarned and g_logger then
      soundWarned = true
      g_logger.warning('[spellranks] this client has no sound support (g_sounds): combo chimes are not played')
    end
    return false
  end
  if g_resources and g_resources.fileExists then
    local ok, there = pcall(g_resources.fileExists, file)
    if ok and not there then return false end
  end
  local channel = g_sounds.getChannel and SoundChannels and g_sounds.getChannel(SoundChannels.Effect)
  local ok
  if channel then
    ok = pcall(channel.play, channel, file, 0, 1.0)
  else
    ok = pcall(g_sounds.play, file, 0, 1.0)
  end
  return ok
end

-- a `combo` message: label and chime. The server only sends it while the switch is on, so no state is needed. true when it showed.
function showCombo(data)
  local c = CL.clean(data)
  if not c then return false end
  local ms = g_clock and g_clock.millis and g_clock.millis() or 0
  if not CL.allow(comboGate, c, ms) then return false end
  drawLabel(c, CL.labelText(c, tr))
  playCombo(c.sound)
  return true
end

-- ---------------------------------------------------------------- the Upgrades tab
local FORM_ONLY = { 'effects', 'sep1', 'form1Title', 'form1a', 'form1b', 'form1aText', 'form1bText', 'form2Title', 'form2a', 'form2b',
  'form2aText', 'form2bText' }
local AWAKE_ONLY = { 'awakeTitle', 'awakeSeals', 'awakeSlots', 'awakeText', 'awakeDo' }
local FORM_IDS = {
  { 'form1a', 'form1b', 'form1aText', 'form1bText', 'form1Title' },
  { 'form2a', 'form2b', 'form2aText', 'form2bText', 'form2Title' },
}
local COMMON_IDS = { 'rankTitle', 'spText', 'rankBar', 'strip', 'note', 'message' }

local function effectParts(t)
  local parts = {}
  if t.power > 0 then parts[#parts + 1] = tr('+%s%% power', decimal(t.power)) end
  if t.cooldown > 0 then parts[#parts + 1] = tr('-%s%% cooldown', decimal(t.cooldown)) end
  if t.mana > 0 then parts[#parts + 1] = tr('-%s%% mana cost', decimal(t.mana)) end
  return table.concat(parts, ', ')
end

local function buildCells(p)
  if p.cellsBuilt then return end
  p.cellsBuilt = true
  for i = 1, L.MAX_RANK do
    local c = g_ui.createWidget('SpellRankCell', p.strip)
    if i > 1 then c:setMarginLeft(1) end
  end
end

local function setFormButton(btn, text, tooltip, picked, usable)
  btn:setText(picked and ('> ' .. text) or text)
  btn:setColor(picked and GOOD or '#d6c9ae')
  btn:setTooltip(tooltip)
  btn:setEnabled(usable)
end

-- what the Awakening view of a spell says when it cannot be awakened yet (the server decides again, awakelogic.lua A.check)
local function awakeWhy(code, chk)
  if code == 'off' then return tr('Spell upgrades are not on yet.') end
  if code == 'spell' then return tr('This spell cannot be awakened.') end
  if code == 'unknown' then return tr('You do not know this spell.') end
  if code == 'rank' then return tr('The spell needs rank %d to awaken.', AL.MAX_RANK) end
  if code == 'forms' then return tr('Pick both Forms of the spell first.') end
  if code == 'already' then return tr('This spell is awakened.') end
  if code == 'slot' then return tr('All three slots are taken.') end
  if code == 'slotlevel' then return tr('Awakening slot %d opens at level %d.', chk and chk.slot or 0, chk and chk.level or 0) end
  if code == 'level' then return tr('This spell can be awakened from level %d.', chk and chk.level or 0) end
  if code == 'seals' then
    local n = chk and chk.need or { 0, 0, 0 }
    return tr('Not enough Seals: %d Waystone, %d Rift and %d Pinnacle more.', n[1], n[2], n[3])
  end
  return tr('The server did not accept that awakening.')
end

-- the Awakening view of the tab: the name, the Seals, the slots, the signature and the button
local function renderAwake(p, id, rank, pk, entry)
  local data = rawget(_G, 'ChaosAwakenedData')
  local pt = isPt()
  local name = AL.nameOf(data, id, pt)
  local slot = AL.slotOf(awake, id)
  p.awakeTitle:setText(slot and tr('Awakened: %s', name) or tr('Awakens as: %s', name))
  p.awakeTitle:setColor(slot and GOOD or GOLD)
  local s = awake.seals
  p.awakeSeals:setText(tr('Seals: %d Waystone, %d Rift, %d Pinnacle', s[1], s[2], s[3]))
  p.awakeSeals:setTooltip(tr('Waystone Seals come from cleared waystone maps of tier XVI to XXV, one more for the first clear of a tier. Rift Seals come from Greater Rift runs that end at tier 16 or higher, one more when the run climbs. Pinnacle Seals come from Ascended boss kills, 2 for each member of the party.'))
  local lines = {}
  for i = 1, AL.MAX_SLOTS do
    local held = awake.slots[i]
    if held > 0 then
      lines[#lines + 1] = tr('Slot %d: %s', i, AL.nameOf(data, held, pt) or '?')
    else
      local c = awake.costs[i]
      lines[#lines + 1] = tr('Slot %d: free, %d Waystone, %d Rift, %d Pinnacle Seals', i, c[1], c[2], c[3])
    end
  end
  p.awakeSlots:setText(table.concat(lines, '\n'))
  local parts = AL.sentences(entry, tr, decimal)
  parts[#parts + 1] = tr('An awakened spell hits or heals %s%% more. In PvP the signature effect is off and the bonus is halved.',
    decimal((awake.bonus or 0.1) * 100))
  p.awakeText:setText(table.concat(parts, ' '))
  p.awakeText:setTooltip(table.concat(parts, '\n'))
  local learn = shownSpell and tonumber(shownSpell.level) or nil
  local gates = state and state.ms and { level = playerLevel(), slot = state.ms.sl, spell = learn and L.awakenGate(state.ms, learn) or 0 } or nil
  local chk = AL.check(awake, data, id, rank, pk.f1, pk.f2, gates)
  p.awakeDo:setText(tr('Awaken'))
  p.awakeDo:setEnabled(chk.ok)
  p.awakeDo:setTooltip(chk.ok and tr('Awaken this spell: %d Waystone, %d Rift and %d Pinnacle Seals', chk.cost[1], chk.cost[2], chk.cost[3])
    or awakeWhy(chk.why, chk))
  p.awakeDo.onClick = function() onAwakenClick(chk) end
  p.note:setText(tr('Awakened spells: %d of %d. A spell awakens at rank %d with both Forms picked.', awake.held, AL.MAX_SLOTS, AL.MAX_RANK))
end

local function render()
  local p = panel
  if not p or not shownId then return end
  local data = rawget(_G, 'ChaosFormsData')
  local id = shownId
  local rankable = L.isOn(state) and L.isRankable(state, data, id)
  local aEntry = AL.entry(rawget(_G, 'ChaosAwakenedData'), id)
  local showAwake = rankable and view == 'awake' and aEntry ~= nil and AL.isOn(awake)
  for _, w in ipairs(COMMON_IDS) do p[w]:setVisible(rankable) end
  for _, w in ipairs(FORM_ONLY) do p[w]:setVisible(rankable and not showAwake) end
  for _, w in ipairs(AWAKE_ONLY) do p[w]:setVisible(showAwake) end
  p.awakeTab:setVisible(rankable and aEntry ~= nil and AL.isOn(awake))
  p.awakeTab:setText(showAwake and tr('Forms') or tr('Awakening'))
  p.awakeTab:setTooltip(showAwake and tr('Back to the Forms of this spell') or tr('Seals, slots and the awakened form of this spell'))
  p.emptyText:setVisible(not rankable)
  if not rankable then
    p.emptyText:setText(L.isOn(state) and tr('This spell has no upgrades.') or tr('Spell upgrades are not on yet.'))
    return
  end
  buildCells(p)

  local forms = L.formsFor(data, id)
  local e = L.rankEntry(state, id)
  local rank = e and e.rank or 0
  local isHeal = (forms and forms.heal) or (shownSpell and shownSpell.type == 'heal') or false
  local pk = picks[id] or { f1 = 0, f2 = 0 }
  local rl = rules()

  -- rank, SP, bar, strip
  local sp = tr('Spell Points (SP) come from the experience of the monsters this spell hurt or healed against. A new character of an account starts at half the best rank of the account on this spell, up to rank 10.')
  p.rankTitle:setText(tr('Rank %d of %d', rank, L.MAX_RANK))
  p.rankTitle:setTooltip(sp)
  p.spText:setTooltip(sp)
  if not e then
    p.spText:setText(tr('No SP yet'))
  elseif rank >= L.MAX_RANK then
    p.spText:setText(tr('Top rank'))
  else
    p.spText:setText(tr('%s / %s SP', decimal(e.into, '%.2f'), decimal(e.cost, '%.2f')))
  end
  p.rankBar:setPercent(e and (L.fraction(e) * 100) or 0)
  p.rankBar:setTooltip(e and rank < L.MAX_RANK and tr('%s SP to rank %d', decimal(L.spToGo(e), '%.2f'), rank + 1) or '')
  for i, c in ipairs(p.strip:getChildren()) do
    c:setBackgroundColor(i <= rank and CELL_ON or CELL_OFF)
    c:setBorderColor((i == rl.rank1 or i == rl.rank2) and '#e8b84a' or '#2a2226')
  end

  -- what the ranks give
  local nowText = effectParts(L.totals(rank, isHeal))
  local line1 = rank > 0 and tr('Now: %s', nowText) or tr('No bonus yet.')
  local line2 = rank < L.MAX_RANK and tr('Rank %d adds: %s', rank + 1, effectParts(L.gives(rank + 1, isHeal))) or tr('Top rank reached.')
  p.effects:setText(line1 .. '\n' .. line2)

  -- the Forms
  for tier = 1, 2 do
    local ids = FORM_IDS[tier]
    local a, b, ta, tb, title = p[ids[1]], p[ids[2]], p[ids[3]], p[ids[4]], p[ids[5]]
    local learn = shownSpell and tonumber(shownSpell.level) or nil
    local gate = learn and L.formGate(state.ms, tier, learn) or 0
    local st = L.tierState(rl, rank, pk.f1, pk.f2, tier, gate, playerLevel())
    local usable = not st.locked and not st.needForm1 and not st.levelLocked
    if tier == 1 then
      title:setText(st.locked and tr('Form I: opens at rank %d', st.rankNeeded)
        or (st.levelLocked and tr('Form I: opens at level %d', st.levelNeeded) or tr('Form I')))
    else
      title:setText(st.locked and tr('Form II: opens at rank %d', st.rankNeeded)
        or (st.needForm1 and tr('Form II: pick a Form I first')
        or (st.levelLocked and tr('Form II: opens at level %d', st.levelNeeded) or tr('Form II'))))
    end
    if st.levelNeeded > 0 then
      title:setTooltip(tr('This Form tier opens at rank %d and level %d.', st.rankNeeded, st.levelNeeded))
    end
    title:setColor(usable and GOLD or DIM)
    local row = forms and forms.tiers[tier]
    for pick, pair in ipairs({ { a, ta }, { b, tb } }) do
      local f = row and row[pick]
      local btn, label = pair[1], pair[2]
      if f then
        local name, text = tr(f.name), tr(f.text)
        setFormButton(btn, name, name .. '\n' .. text, st.picked == pick, usable)
        btn.onClick = function() onPickClick(tier, pick) end
        label:setText(text)
        label:setTooltip(text)
        label:setColor(usable and '#b8ac92' or '#6b6258')
      else
        btn:setText('-'); btn:setEnabled(false); label:setText(''); label:setTooltip('')
      end
    end
  end

  -- the price and the free window
  local lines = {}
  local anyPick = pk.f1 > 0 or pk.f2 > 0
  local left = L.windowLeft(rl, id, lastPick and lastPick.tier or 0, lastPick, now())
  if left then
    lines[#lines + 1] = tr('A change of the Form you just picked is free for %d more minutes.', math.ceil(left / 60))
  end
  if anyPick then
    lines[#lines + 1] = tr('Changing a Form costs %s gold, from the bank first. Right after a pick it is free for %d minutes.', gold(L.price(rl, playerLevel())), math.floor(rl.freeSeconds / 60))
  else
    lines[#lines + 1] = tr('The first pick of a Form is free. A later change costs gold.')
  end
  p.note:setText(table.concat(lines, ' '))

  if showAwake then renderAwake(p, id, rank, pk, aEntry) end

  if message and message.id == id then
    p.message:setText(message.text)
    p.message:setColor(message.good and GOOD or BAD)
  else
    p.message:setText('')
  end
end

-- the texts of every answer of a pick (the key words of the server's `why`, ranklogic.lua WHY_FAIL / WHY_OK)
local function whyText(code, res)
  local rl = rules()
  if code == 'off' then return tr('Spell upgrades are not on yet.') end
  if code == 'spell' then return tr('This spell has no Forms.') end
  if code == 'rank' then
    local tier = res and res.tier == 2 and rl.rank2 or rl.rank1
    return tr('The spell needs rank %d for this Form.', tier)
  end
  if code == 'form1' then return tr('Pick a Form I first.') end
  if code == 'level' then return tr('This Form opens at level %d.', res and res.need or 0) end
  if code == 'gold' then return tr('You need %s gold, in the bank and your backpack together.', gold(res and res.price or 0)) end
  if code == 'tier' or code == 'pick' then return tr('That Form does not exist.') end
  if code == 'first' then return tr('Form chosen.') end
  if code == 'same' then return tr('That Form is already chosen.') end
  if code == 'window' then return tr('Form changed. Free: you changed it right after a pick.') end
  if code == 'paid' then return tr('Form changed for %s gold.', gold(res and res.price or 0)) end
  return tr('The server did not accept that pick.')
end

local function say(id, text, good)
  message = { id = id, text = text, good = good }
end

local function sendPick(id, tier, pick)
  if not send('pick', { spell = id, tier = tier, pick = pick }) then
    say(id, tr('Not connected.'), false)
    render()
  end
end

-- a click on a Form button
onPickClick = function(tier, pick)
  local id = shownId
  if not id then return end
  local pk = picks[id] or { f1 = 0, f2 = 0 }
  local rank = L.rank(state, id)
  local rl = rules()
  local learn = shownSpell and tonumber(shownSpell.level) or nil
  local gate = learn and state and L.formGate(state.ms, tier, learn) or 0
  local q = L.quote(rl, id, tier, pick, rank, pk.f1, pk.f2, playerLevel(), lastPick, now(), gate)
  if q.kind == 'locked' then
    say(id, tr('The spell needs rank %d for this Form.', tier == 2 and rl.rank2 or rl.rank1), false)
    render()
  elseif q.kind == 'form1' then
    say(id, tr('Pick a Form I first.'), false)
    render()
  elseif q.kind == 'same' then
    say(id, tr('That Form is already chosen.'), false)
    render()
  elseif q.kind == 'level' then
    say(id, tr('This Form opens at level %d.', q.level or 0), false)
    render()
  elseif q.kind == 'paid' then
    local box
    local function close() if box then box:destroy() box = nil end end
    local function yes() close() sendPick(id, tier, pick) end
    if displayGeneralBox then
      box = displayGeneralBox(tr('Change Form'),
        tr('Change this Form for %s gold? The gold is taken from your bank first, then from the coins you carry.', gold(q.price)),
        { { text = tr('Change'), callback = yes }, { text = tr('Cancel'), callback = close }, anchor = AnchorHorizontalCenter }, yes, close)
    else
      yes()
    end
  else
    sendPick(id, tier, pick)
  end
end

-- a click on the Awaken button: the confirm box, then the request
onAwakenClick = function(chk)
  local id = shownId
  if not id or not chk or not chk.ok then return end
  local data = rawget(_G, 'ChaosAwakenedData')
  local name = AL.nameOf(data, id, isPt()) or '?'
  local spellName = shownSpell and shownSpell.name or name
  local function yes()
    if not send('awaken', { spell = id, slot = chk.slot }) then
      say(id, tr('Not connected.'), false)
      render()
    end
  end
  local box
  local function close() if box then box:destroy() box = nil end end
  local function go() close() yes() end
  if displayGeneralBox then
    box = displayGeneralBox(tr('Awaken spell'),
      tr('Awaken %s as %s? It costs %d Waystone, %d Rift and %d Pinnacle Seals and takes slot %d. The Seals are not returned if the spell goes dormant.',
        spellName, name, chk.cost[1], chk.cost[2], chk.cost[3], chk.slot),
      { { text = tr('Awaken'), callback = go }, { text = tr('Cancel'), callback = close }, anchor = AnchorHorizontalCenter }, go, close)
  else
    yes()
  end
end

-- the view button of the tab: the Forms or the Awakening of the spell
function toggleView()
  view = view == 'awake' and 'forms' or 'awake'
  render()
end

-- the Spellbook draws the tab for this spell
function fill(p, spell)
  panel, shownSpell = p, spell
  p.awakeTab.onClick = toggleView
  local id = spell and tonumber(spell.id)
  if id ~= shownId then message = nil end
  shownId = id
  render()
end

-- ---------------------------------------------------------------- protocol
function ask(force)
  if not g_game.isOnline() then return end
  local t = clock()
  if not force and t - askedAt < ASK_GAP then return end
  askedAt = t
  send('open', {})
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local msg = buffer
  if type(buffer) == 'string' then
    local ok, decoded = pcall(json.decode, buffer)
    if not ok then return end
    msg = decoded
  end
  if type(msg) ~= 'table' then return end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'state' then
    state = L.cleanState(data)
    if state and not state.on then state = nil end
    render()
    refreshBadge()
    local book = modules and modules.game_spellbook
    if book and book.onRanksChanged then pcall(book.onRanksChanged) end
  elseif msg.action == 'forms' then
    picks = L.cleanForms(data)
    render()
    refreshBadge()
  elseif msg.action == 'rank' then
    if state and L.applyRank(state.ranks, data) > 0 then
      render()
      refreshBadge()
      local book = modules and modules.game_spellbook
      if book and book.onRanksChanged then pcall(book.onRanksChanged) end
    end
  elseif msg.action == 'awakened' then
    awake = AL.cleanState(data)
    render()
    local book = modules and modules.game_spellbook
    if book and book.onRanksChanged then pcall(book.onRanksChanged) end
  elseif msg.action == 'awaken' then
    local res = AL.cleanAnswer(data)
    if not res then return end
    local code, good = AL.whyCode(res)
    if good then
      local name = AL.nameOf(rawget(_G, 'ChaosAwakenedData'), res.spell, isPt()) or (isPt() and res.namePt or res.name)
      say(res.spell, tr('Awakened: %s', name), true)
    else
      say(res.spell, awakeWhy(code, res), false)
    end
    render()
  elseif msg.action == 'combo' then
    showCombo(data)
  elseif msg.action == 'pick' then
    local res = L.cleanPick(data)
    if not res then return end
    local code, good = L.whyCode(res)
    if code == 'off' then
      state = nil
      refreshBadge()
    end
    if good then
      L.applyPick(picks, res)
      if code ~= 'same' and code ~= 'window' then
        lastPick = { spell = res.spell, tier = res.tier, at = now() }
      end
    end
    say(res.spell, whyText(code, res), good)
    render()
    refreshBadge()
  end
end

-- ---------------------------------------------------------------- start and end
local function poll()
  pollEvent = nil
  if g_game.isOnline() and L.isOn(state) then ask(false) end
  if g_game.isOnline() then pollEvent = scheduleEvent(poll, POLL_SECONDS * 1000) end
end

local function onGameStart()
  if startEvent then removeEvent(startEvent) end
  startEvent = scheduleEvent(function()
    startEvent = nil
    if g_game.isOnline() then ask(true) end
  end, START_DELAY)
  if pollEvent then removeEvent(pollEvent) end
  pollEvent = scheduleEvent(poll, POLL_SECONDS * 1000)
end

local function onGameEnd()
  state, picks, lastPick, message, panel, shownSpell, shownId = nil, {}, nil, nil, nil, nil, nil
  awake, view = nil, 'forms'
  askedAt, lastBadge = -100, -1
  comboGate = CL.newGate()
  if startEvent then removeEvent(startEvent); startEvent = nil end
  if pollEvent then removeEvent(pollEvent); pollEvent = nil end
end

function init()
  g_ui.importStyle('spellupgrades')
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  onGameEnd()
end
