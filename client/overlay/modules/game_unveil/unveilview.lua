-- The Unveil window's logic without client API (tested by unveilview_test.lua): the three cards of a veiled item, the
-- selection, the request sent back and the texts. The data comes from the server (server/data/scripts/chaos/veiled.lua,
-- extended opcode 196):
--   open {path, id, clientId, name, rarity, rarityName, level, sig, orbs, offers = [{i, key, name, text, tier, tn, lo,
--        hi, value, hook}]}
--   result {ok, text, veil = {s, n, t, tr, tn, lo, hi, h}}

UnveilView = {}
local V = UnveilView

V.WRAP = 26 -- characters per line of a card's text
V.COLORS = { title = '#d9c8ff', text = '#d6c9ae', dim = '#8c8070', veiled = '#b48cff', hook = '#ff9a3c', ok = '#7fe0a0',
  bad = '#e03a1e' }
-- veiled tiers V1 .. V4 (the same as the tooltip, game_itemtooltip tooltiplogic.lua)
V.TIER_COLORS = { '#9a8cc0', '#a98cff', '#c070ff', '#ff70e0' }

function V.title(name)
  name = tostring(name or '')
  return (name:gsub('^%l', string.upper))
end

function V.wrap(text, n)
  n = n or V.WRAP
  local lines, line = {}, ''
  for word in tostring(text or ''):gmatch('%S+') do
    if line == '' then
      line = word
    elseif #line + 1 + #word <= n then
      line = line .. ' ' .. word
    else
      lines[#lines + 1] = line
      line = word
    end
  end
  if line ~= '' then lines[#lines + 1] = line end
  return lines
end

function V.tierColor(t)
  return V.TIER_COLORS[tonumber(t) or 0] or V.COLORS.veiled
end

-- the line over the cards: the item, its rarity and item level
function V.headerText(data)
  if type(data) ~= 'table' then return '' end
  local parts = { V.title(data.name or '?') }
  if data.rarityName then parts[#parts + 1] = tostring(data.rarityName) end
  if (tonumber(data.level) or 0) > 0 then parts[#parts + 1] = 'Item Level ' .. data.level end
  return table.concat(parts, '  -  ')
end

function V.orbsText(n)
  n = tonumber(n) or 0
  return string.format('Orbs of Unveiling: %d', n)
end

-- the cards: [{i, name, lines, tierText, tierColor, rangeText, hookText}] (at most three; malformed offers are skipped)
function V.cards(data)
  local out = {}
  if type(data) ~= 'table' or type(data.offers) ~= 'table' then return out end
  for _, o in ipairs(data.offers) do
    if type(o) == 'table' and tonumber(o.i) and o.name and o.text and #out < 3 then
      local tn = o.tn or ('V' .. tostring(o.tier or 1))
      out[#out + 1] = {
        i = tonumber(o.i), key = o.key, name = tostring(o.name), text = tostring(o.text), lines = V.wrap(o.text, V.WRAP),
        tierText = 'Veiled tier ' .. tn, tierColor = V.tierColor(o.tier),
        rangeText = (o.lo and o.hi) and (o.lo == o.hi and string.format('Range %d', o.lo) or string.format('Range %d-%d', o.lo, o.hi)) or '',
        hookText = o.hook and 'Effect of its own' or ''
      }
    end
  end
  return out
end

-- the card's text as the label shows it (the label wraps it to the card's width)
function V.cardText(card)
  return card.text or table.concat(card.lines or {}, ' ')
end

-- can choice i be confirmed? (an offer of the window and at least one orb)
function V.canConfirm(data, i)
  if type(data) ~= 'table' or not tonumber(i) then return false end
  if (tonumber(data.orbs) or 0) < 1 then return false end
  for _, c in ipairs(V.cards(data)) do
    if c.i == tonumber(i) then return true end
  end
  return false
end

-- the request for choice i, or nil
function V.request(data, i)
  if not V.canConfirm(data, i) then return nil end
  return { path = data.path, id = data.id, sig = data.sig, choice = tonumber(i) }
end

-- the line under the cards
function V.statusText(data, selected)
  if type(data) ~= 'table' then return '' end
  if (tonumber(data.orbs) or 0) < 1 then return 'You have no Orb of Unveiling.' end
  for _, c in ipairs(V.cards(data)) do
    if c.i == selected then
      return string.format('Reveal %s? The choice is final and takes one orb.', c.name)
    end
  end
  return 'Choose one of the three modifiers. The choice is final.'
end

-- the result line: text and colour
function V.resultText(res)
  if type(res) ~= 'table' then return '', V.COLORS.dim end
  if res.ok then
    local v = type(res.veil) == 'table' and res.veil or nil
    if v and v.n then
      return string.format('The veil lifts: %s (%s) is yours.', tostring(v.n), tostring(v.tn or ('V' .. tostring(v.tr or 1)))),
        V.COLORS.ok
    end
    return tostring(res.text or 'The veil lifts.'), V.COLORS.ok
  end
  return tostring(res.text or 'That did not work.'), V.COLORS.bad
end

return V
