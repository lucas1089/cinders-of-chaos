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

local L = ChaosRankLogic
local OPCODE = L.OPCODE

local ASK_GAP = 5          -- seconds between two asks from the client (the server allows one per 2 s)
local POLL_SECONDS = 60    -- while the switch is on: ranks move with every kill, the server sends no push yet
local START_DELAY = 6000   -- ms after login before the first ask

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

function getPickableCount()
  return L.pickableCount(state, picks, rawget(_G, 'ChaosFormsData'))
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

local function refreshBadge()
  local n = getPickableCount()
  if n == lastBadge then return end
  lastBadge = n
  local top = modules and modules.client_chaos_topbar
  if top and top.ChaosTopBar and top.ChaosTopBar.refresh then pcall(top.ChaosTopBar.refresh) end
end

-- ---------------------------------------------------------------- the Upgrades tab
local FORM_IDS = {
  { 'form1a', 'form1b', 'form1aText', 'form1bText', 'form1Title' },
  { 'form2a', 'form2b', 'form2aText', 'form2bText', 'form2Title' },
}
local ALL_IDS = { 'rankTitle', 'spText', 'rankBar', 'strip', 'effects', 'sep1', 'form1Title', 'form1a', 'form1b', 'form1aText',
  'form1bText', 'form2Title', 'form2a', 'form2b', 'form2aText', 'form2bText', 'note', 'message' }

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

local function render()
  local p = panel
  if not p or not shownId then return end
  local data = rawget(_G, 'ChaosFormsData')
  local id = shownId
  local rankable = L.isOn(state) and L.isRankable(state, data, id)
  for _, w in ipairs(ALL_IDS) do p[w]:setVisible(rankable) end
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
    local st = L.tierState(rl, rank, pk.f1, pk.f2, tier)
    local usable = not st.locked and not st.needForm1
    if tier == 1 then
      title:setText(st.locked and tr('Form I: opens at rank %d', st.rankNeeded) or tr('Form I'))
    else
      title:setText(st.locked and tr('Form II: opens at rank %d', st.rankNeeded)
        or (st.needForm1 and tr('Form II: pick a Form I first') or tr('Form II')))
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
  local q = L.quote(rl, id, tier, pick, rank, pk.f1, pk.f2, playerLevel(), lastPick, now())
  if q.kind == 'locked' then
    say(id, tr('The spell needs rank %d for this Form.', tier == 2 and rl.rank2 or rl.rank1), false)
    render()
  elseif q.kind == 'form1' then
    say(id, tr('Pick a Form I first.'), false)
    render()
  elseif q.kind == 'same' then
    say(id, tr('That Form is already chosen.'), false)
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

-- the Spellbook draws the tab for this spell
function fill(p, spell)
  panel, shownSpell = p, spell
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
  askedAt, lastBadge = -100, -1
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
