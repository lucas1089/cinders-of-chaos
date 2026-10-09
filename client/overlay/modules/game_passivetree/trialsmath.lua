-- Vocation Trials panel maths (no client API, tested by trialsmath_test.lua). `state` is the server's trialState
-- (server/data/scripts/chaos/trials_core.lua clientState): {supported, trial, story, level, tier (cleared), tokens, maxTokens,
-- switchGold, running, tiers = [{name, minLevel, cleared, problem, time, lives, bossHealth}],
-- pairs = [{pair, tier (difficulty name), locked, held (0/1/2), nodes = [{id, name, lore, lines = [{text, good}], can, why,
-- switch, needsSpellEvents}]}]}.
TrialsMath = {}

local GOOD, BAD, DIM, HELD = '#7fd06a', '#e0654a', '#8c8070', '#f6cf72'
TrialsMath.GOOD, TrialsMath.BAD, TrialsMath.DIM, TrialsMath.HELD = GOOD, BAD, DIM, HELD
TrialsMath.MAX_LINES = 5

function TrialsMath.gold(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  return (out:gsub('^,', ''))
end

-- shorten a text to `max` characters (the cards have fixed boxes)
function TrialsMath.fit(text, max)
  text = tostring(text or '')
  if #text <= max then
    return text
  end
  return text:sub(1, math.max(1, max - 3)) .. '...'
end

function TrialsMath.tokensLine(state)
  return string.format('Trial Tokens: %d / %d     Changing a held node costs 1 token and %s gold',
    state.tokens or 0, state.maxTokens or 10, TrialsMath.gold(state.switchGold))
end

function TrialsMath.lockText(tierName)
  return 'Locked: clear on ' .. tostring(tierName)
end

function TrialsMath.lockTooltip(state, entry)
  return string.format('Clear %s on %s to open this pair of nodes.', tostring(state.trial), tostring(entry.tier))
end

-- what a node card shows for `side` (1 or 2) of `entry`: {action, enabled, status, statusColor, tooltip}
function TrialsMath.card(state, entry, side)
  local node = entry.nodes[side]
  if state.running then
    return {action = entry.held == side and 'Held' or 'In a trial', enabled = false,
      status = entry.locked and TrialsMath.lockText(entry.tier) or 'Not during a trial', statusColor = DIM,
      tooltip = 'Nodes cannot be changed while a trial runs.'}
  end
  if entry.locked then
    return {action = 'Locked', enabled = false, status = TrialsMath.lockText(entry.tier), statusColor = DIM,
      tooltip = TrialsMath.lockTooltip(state, entry)}
  end
  if entry.held == side then
    return {action = 'Held', enabled = false, status = 'Held', statusColor = HELD,
      tooltip = 'You hold this node. Pick the other one to change (1 Trial Token and gold).'}
  end
  if (entry.held or 0) == 0 then
    return {action = 'Choose', enabled = node.can == true, status = node.can and 'Free to choose' or tostring(node.why or ''),
      statusColor = node.can and GOOD or BAD, tooltip = 'The first choice of a pair is free. Choosing one locks the other.'}
  end
  local can = node.can == true
  return {action = 'Switch', enabled = can, status = can and '1 token + gold' or 'Needs a Trial Token',
    statusColor = can and HELD or BAD,
    tooltip = string.format('Replaces %s. Costs 1 Trial Token and %s gold.', tostring(entry.nodes[entry.held] and entry.nodes[entry.held].name or '?'),
      TrialsMath.gold(state.switchGold))}
end

-- the Enter button of tier i
function TrialsMath.tierButton(state, i)
  local t = state.tiers[i]
  local text = 'Enter ' .. t.name
  if t.cleared then
    text = text .. ' (cleared)'
  end
  local tip = string.format('%s: level %d, %d minutes, %d lives, guardian about %s health.', t.name, t.minLevel,
    math.floor((t.time or 0) / 60), t.lives or 0, TrialsMath.gold(t.bossHealth))
  if state.running then
    return {text = text, enabled = false, tooltip = 'A trial is running.'}
  end
  if t.problem then
    tip = tip .. '\n' .. t.problem
  elseif t.cleared then
    tip = tip .. '\nCleared: another clear gives a Trial Token.'
  else
    tip = tip .. '\nThe first clear opens a pair of nodes.'
  end
  return {text = text, enabled = t.problem == nil, tooltip = tip}
end

-- confirmation text before choosing / switching
function TrialsMath.confirmText(state, entry, side)
  local node = entry.nodes[side]
  local lines = {}
  for _, l in ipairs(node.lines or {}) do
    lines[#lines + 1] = (l.good and '+ ' or '- ') .. l.text
  end
  local head
  if (entry.held or 0) == 0 then
    head = string.format('Choose %s? The other node of the pair is locked while you hold it.', node.name)
  else
    head = string.format('Switch to %s? It costs 1 Trial Token and %s gold coins.', node.name, TrialsMath.gold(state.switchGold))
  end
  return head .. '\n\n' .. table.concat(lines, '\n')
end
