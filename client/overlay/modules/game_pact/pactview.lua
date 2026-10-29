-- Chaos Pact window: the texts and rows, without client API (tested by pactview_test.lua).
-- The server (data/scripts/chaos/pact.lua) decides everything; this only formats its `status`:
--   {active, ends, daysLeft, dailyMarks, canClaim, claimedTotal, premiumDays, coins, title, titleText,
--    marks, marksEarned, shelf = [{key, name, marks, owned}], monthExp, monthExpAccount, month,
--    limits = [{key, label, free, pact, extra, maxExtra, total, pactActive}], tabSize, special = [{name, owned, source}],
--    buildLimit, builds = [{slot, name, nodes, cls, editable, updated}]}
-- Pact Marks (O317): 5 a day while the Pact runs; they buy the cosmetics of the shelf and nothing else.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

PactView = {}
local V = PactView

local function n(v)
  return math.floor(tonumber(v) or 0)
end

local function plural(count, word)
  return count .. ' ' .. word .. (count == 1 and '' or 's')
end

-- the headline and the line under it
function V.status(s)
  if type(s) ~= 'table' then return 'Loading...', '' end
  if s.active then
    return tr('Chaos Pact active'), tr('Until %s (%s left). Title: %s.', s.ends or '?', plural(n(s.daysLeft), 'day'),
      s.title ~= '' and s.title or (s.titleText or ''))
  end
  if n(s.endsAt) > 0 then
    return tr('Chaos Pact ended'), tr('Ended %s. Nothing is lost: extra tabs are withdraw-only, extra builds read-only.', (s.ends or ''))
  end
  return tr('No Chaos Pact'), tr('Perks for 30 days: +10%% XP, stamina x1.5, remote stash deposit, room, slots, %s Pact Marks a day and a title.', n(s.dailyMarks))
end

-- the claim button: text and whether it is enabled
function V.claim(s)
  if type(s) ~= 'table' or not s.active then
    return tr('Daily Pact Marks'), false
  end
  if s.canClaim then
    return tr('Claim %d Pact Marks', n(s.dailyMarks)), true
  end
  return tr('Claimed today'), false
end

-- 12345678 -> "12,345,678"
function V.thousands(v)
  local str = tostring(n(v))
  local out = str:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  return (out:gsub('^,', ''))
end

-- the Pact Marks section: the balance line and the month's experience line
function V.marksLine(s)
  if type(s) ~= 'table' then return '' end
  return tr('Pact Marks: %s (earned so far: %s). They buy only the cosmetics below.', V.thousands(s.marks), V.thousands(s.marksEarned))
end

function V.monthLine(s)
  if type(s) ~= 'table' then return '' end
  if n(s.monthExp) <= 0 and n(s.monthExpAccount) <= 0 then
    return tr('This month the Pact has given you no extra experience yet.')
  end
  if n(s.monthExpAccount) > n(s.monthExp) then
    return tr('This month the Pact gave you %s extra experience (%s on all your characters).', V.thousands(s.monthExp), V.thousands(s.monthExpAccount))
  end
  return tr('This month the Pact gave you %s extra experience.', V.thousands(s.monthExp))
end

-- the shelf rows: {key, name, marks, owned, canBuy, button, price}; the button text says why a row cannot be bought
function V.shelfRows(s)
  local rows = {}
  local have = n(type(s) == 'table' and s.marks)
  for _, it in ipairs(type(s) == 'table' and s.shelf or {}) do
    local price = n(it.marks)
    local button, canBuy
    if it.owned then
      button, canBuy = tr('Owned'), false
    elseif have < price then
      button, canBuy = tr('Buy'), false
    else
      button, canBuy = tr('Buy'), true
    end
    rows[#rows + 1] = { key = it.key, name = it.name or it.key, marks = price, owned = it.owned == true, canBuy = canBuy, button = button,
      price = tr('%d Marks', price) }
  end
  return rows
end

-- one row of the limits table: {label, free, pact, bought, total} as texts
function V.limitRow(r)
  local pact = n(r.pact) > 0 and ('+' .. n(r.pact)) or '-'
  if n(r.pact) > 0 and not r.pactActive then
    pact = pact .. ' (off)'
  end
  local bought = '-'
  if n(r.maxExtra) > 0 or n(r.extra) > 0 then
    bought = n(r.extra) .. ' / ' .. n(r.maxExtra)
  end
  return { r.label or r.key or '?', tostring(n(r.free)), pact, bought, tostring(n(r.total)) }
end

function V.limitRows(s)
  local out = {}
  for _, r in ipairs(type(s) == 'table' and s.limits or {}) do
    local row = V.limitRow(r)
    if r.pactActive and not s.active and n(r.pact) > 0 then
      row[3] = row[3] .. ' (premium)' -- the loot rules: premium alone gives that bonus
    end
    out[#out + 1] = row
  end
  return out
end

-- the affinity stash tabs line (server stash_config.lua affinities: each takes one class of item)
function V.specialText(s)
  local parts = {}
  for _, t in ipairs(type(s) == 'table' and s.special or {}) do
    parts[#parts + 1] = tr(t.name) .. (t.owned and tr(' (owned)') or tr(' (store)'))
  end
  if #parts == 0 then return '' end
  return tr('Affinity stash tabs: %s. The free stash tab holds %s entries; Slot Expansions make it bigger.', table.concat(parts, ', '), n(s.tabSize))
end

-- saved builds: one row per slot from 1 to max(limit, highest saved slot); empty editable slots included
function V.buildRows(s)
  local bySlot, highest = {}, n(type(s) == 'table' and s.buildLimit)
  for _, b in ipairs(type(s) == 'table' and s.builds or {}) do
    bySlot[n(b.slot)] = b
    highest = math.max(highest, n(b.slot))
  end
  local rows = {}
  for slot = 1, highest do
    local b = bySlot[slot]
    local editable = slot <= n(s.buildLimit)
    if b then
      local sub = string.format('%s, %s', (b.cls and b.cls ~= '') and (b.cls:sub(1, 1):upper() .. b.cls:sub(2) .. ' line') or 'no class',
        plural(n(b.nodes), 'node'))
      if not editable then sub = sub .. ' - read-only' end
      rows[#rows + 1] = { slot = slot, name = b.name or ('Build ' .. slot), sub = sub, saved = true, editable = editable }
    else
      rows[#rows + 1] = { slot = slot, name = tr('Empty slot'), sub = editable and tr('Save your current tree here') or '', saved = false,
        editable = editable }
    end
  end
  return rows
end

function V.buildHeader(s)
  if type(s) ~= 'table' then return '' end
  local used = #(s.builds or {})
  return tr('Saved builds: %d of %d slots (account-wide)', used, n(s.buildLimit))
end
