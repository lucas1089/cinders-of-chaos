-- luajit trialsmath_test.lua && lua5.3 trialsmath_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'trialsmath.lua')
local M = TrialsMath
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(M.gold(1234567), '1,234,567', 'gold format')
eq(M.gold(999), '999', 'small gold')
eq(M.fit('short', 10), 'short', 'fit keeps short text')
eq(M.fit('a very long node description', 10), 'a very ...', 'fit shortens')
eq(#M.fit('x', 1), 1, 'fit tiny')

local function node(name, can, why)
  return {name = name, can = can, why = why, lines = {{text = '+15% melee damage', good = true}, {text = '+6% damage taken', good = false}}}
end
local state = {trial = 'The Iron Gauntlet', tokens = 2, maxTokens = 10, switchGold = 30000, tier = 1,
  tiers = {{name = 'Normal', minLevel = 100, cleared = true, time = 480, lives = 3, bossHealth = 9000},
    {name = 'Cruel', minLevel = 250, cleared = false, problem = 'Cruel needs level 250.', time = 540, lives = 3, bossHealth = 40000},
    {name = 'Merciless', minLevel = 400, cleared = false, problem = 'Clear the trial on Cruel first.', time = 600, lives = 2, bossHealth = 130000}},
  pairs = {{pair = 1, tier = 'Normal', locked = false, held = 1, nodes = {node('A', true), node('B', true)}},
    {pair = 2, tier = 'Cruel', locked = true, held = 0, nodes = {node('C', false, 'Locked'), node('D', false, 'Locked')}},
    {pair = 3, tier = 'Merciless', locked = false, held = 0, nodes = {node('E', true), node('F', false, 'No')}}}}

eq(M.tokensLine(state), 'Trial Tokens: 2 / 10     Changing a held node costs 1 token and 30,000 gold', 'tokens line')
local held = M.card(state, state.pairs[1], 1)
eq(held.action, 'Held', 'held card'); eq(held.enabled, false, 'held is not clickable')
local other = M.card(state, state.pairs[1], 2)
eq(other.action, 'Switch', 'the other node switches'); eq(other.enabled, true, 'switch enabled with a token')
state.pairs[1].nodes[2].can = false
eq(M.card(state, state.pairs[1], 2).enabled, false, 'no token, no switch')
eq(M.card(state, state.pairs[1], 2).status, 'Needs a Trial Token', 'says why')
local locked = M.card(state, state.pairs[2], 1)
eq(locked.action, 'Locked', 'locked card'); eq(locked.status, 'Locked: clear on Cruel', 'lock text')
eq(locked.tooltip, 'Clear The Iron Gauntlet on Cruel to open this pair of nodes.', 'lock tooltip')
eq(#locked.status <= 30, true, 'lock text fits the status box')
local first = M.card(state, state.pairs[3], 1)
eq(first.action, 'Choose', 'first pick'); eq(first.enabled, true, 'free first pick')
state.running = true
eq(M.card(state, state.pairs[3], 1).enabled, false, 'nothing changes during a run')
eq(M.tierButton(state, 1).enabled, false, 'no entering during a run')
state.running = nil
eq(M.tierButton(state, 1).text, 'Enter Normal (cleared)', 'cleared tier text')
eq(M.tierButton(state, 1).enabled, true, 'cleared tier can be repeated')
eq(M.tierButton(state, 2).enabled, false, 'Cruel blocked'); eq(M.tierButton(state, 2).tooltip:find('Cruel needs level 250.') ~= nil, true, 'reason in the tooltip')
eq(M.confirmText(state, state.pairs[3], 1):find('Choose E') ~= nil, true, 'confirm text: choose')
eq(M.confirmText(state, state.pairs[1], 2):find('30,000 gold coins') ~= nil, true, 'confirm text: switch price')
eq(M.confirmText(state, state.pairs[3], 1):find('%- %+6%% damage taken') ~= nil, true, 'confirm text lists the price')

-- Clear: give a pair up (side 0), the price of a switch
state.pairs[1].clear = {can = true}
local cl = M.clearCard(state, state.pairs[1])
eq(cl.enabled, true, 'a held node can be cleared with a token')
eq(cl.tooltip:find('Gives up A') ~= nil and cl.tooltip:find('30,000 gold') ~= nil, true, 'clear tooltip names the node and the price')
state.pairs[1].clear = {can = false, why = 'You need a Trial Token.'}
eq(M.clearCard(state, state.pairs[1]).enabled, false, 'no token, no clear')
eq(M.clearCard(state, state.pairs[3]).enabled, false, 'nothing held, nothing to clear')
eq(M.clearCard(state, state.pairs[2]).enabled, false, 'a locked pair has nothing to clear')
eq(M.clearConfirmText(state, state.pairs[1]):find('Give up A') ~= nil, true, 'clear confirm text')
state.running = true
state.pairs[1].clear = {can = true}
eq(M.clearCard(state, state.pairs[1]).enabled, false, 'no clear during a run')
state.running = nil

-- O559: a trial is open to you
local function st(level, tier, extra)
  local s = {supported = true, voc = 4, trial = 'The Iron Gauntlet', level = level, tier = tier,
    tiers = {{name = 'Normal', minLevel = 100, cleared = tier >= 1}, {name = 'Cruel', minLevel = 250, cleared = tier >= 2},
      {name = 'Merciless', minLevel = 400, cleared = tier >= 3}},
    pairs = {{locked = tier < 1, held = 0, nodes = {{can = true}, {can = true}}}, {locked = tier < 2, held = 0, nodes = {{can = false}, {can = false}}},
      {locked = tier < 3, held = 0, nodes = {{can = true}, {can = true}}}}}
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end
eq(M.openTier(st(99, 0)), nil, 'below level 100: nothing open')
eq(M.openTier(st(100, 0)), 1, 'level 100, nothing cleared: Normal is open')
eq(M.availableCount(st(100, 0)), 1, 'count 1')
eq(M.openTier(st(600, 0)), 1, 'a high level still opens Normal first')
eq(M.openTier(st(249, 1)), nil, 'Normal cleared, Cruel needs 250')
eq(M.openTier(st(250, 1)), 2, 'Cruel open at 250')
eq(M.openTier(st(400, 3)), nil, 'all three cleared: nothing open')
eq(M.availableCount(st(400, 3)), 0, 'count 0 when all cleared')
eq(M.openTier(st(100, 0, {running = true})), nil, 'not while a trial runs')
eq(M.openTier(st(100, 0, {supported = false})), nil, 'not for a vocation without a trial')
eq(M.openTier(nil), nil, 'no state, nothing open')
local cool = st(100, 0)
cool.tiers[1].problem = 'The trial is still closed to you for 40 seconds.'
eq(M.openTier(cool), 1, 'the cooldown after a failed run keeps it open')
eq(M.badgeText(st(100, 0)), '!', 'badge while open'); eq(M.badgeText(st(99, 0)), '', 'no badge when not')
eq(M.availableText(st(250, 1)), 'Trial open: The Iron Gauntlet on Cruel. Your level (250) reaches it. The first clear opens a pair of special nodes.', 'which trial and why')
eq(M.availableText(st(99, 0)), '', 'no text when none')
eq(M.pendingPicks(st(100, 1)), 1, 'pair 1 unlocked, nothing held: one choice waits')
eq(M.pendingPicks(st(400, 3)), 2, 'a pair with no choosable node does not count')
eq(M.pendingPicks(st(100, 0)), 0, 'locked pairs do not count')
local tip = M.buttonTooltip(st(100, 0), 'BASE')
eq(tip:find('Trial open: The Iron Gauntlet on Normal', 1, true) == 1 and tip:sub(-4) == 'BASE', true, 'tooltip: the trial first, the plain text last')
eq(M.buttonTooltip(st(99, 0), 'BASE'), 'BASE', 'tooltip: the plain text alone when nothing is open')
eq(M.buttonTooltip(st(250, 2, {tiers = st(250, 2).tiers}), 'BASE'):find('open pairs', 1, true) ~= nil, true, 'tooltip: pairs waiting for a choice')
eq(M.needsRefresh(nil, 1), true, 'no state: ask')
eq(M.needsRefresh(st(99, 0), 99), false, 'level 99: nothing new')
eq(M.needsRefresh(st(99, 0), 100), true, 'the level reached Normal: ask again')
eq(M.needsRefresh(st(100, 0), 101), false, 'already open: no need')
eq(M.needsRefresh(st(400, 3), 500), false, 'all cleared: never')
eq(M.needsRefresh(st(100, 0, {supported = false}), 500), false, 'no trial for the vocation: never')
eq(M.pulseColor(0), '#ffffff', 'pulse starts white')
eq(M.pulseColor(M.PULSE_MS / 2), '#ffa850', 'pulse peaks at ember')
eq(M.pulseColor(M.PULSE_MS), '#ffffff', 'pulse repeats')
for ms = 0, M.PULSE_MS, 50 do eq(M.pulseColor(ms):match('^#%x%x%x%x%x%x$') ~= nil, true, 'pulse colour is a hex colour') end
eq(M.toastKey('Ana', st(100, 0)), 'Ana:4:1', 'toast key: character, vocation, tier')
eq(M.toastKey('Ana', st(99, 0)), nil, 'no key when nothing is open')
eq(M.shouldToast(nil, 'Ana:4:1'), true, 'a new availability toasts')
eq(M.shouldToast('Ana:4:1', 'Ana:4:1'), false, 'the same one does not toast again')
eq(M.shouldToast('Ana:4:1', 'Ana:4:2'), true, 'the next difficulty is new')
eq(M.shouldToast('Ana:4:1', nil), false, 'nothing open, no toast')
eq(M.toastText(st(100, 0)), 'The Iron Gauntlet on Normal is open to you. Open the Trials button of the passive tree.', 'toast text')

if fails > 0 then os.exit(1) end
print('trialsmath_test: OK')
