-- The forge window (O481), its view logic without client API (tested by forgeview_test.lua with LuaJIT and Lua 5.3).
-- Owner request 2026-11-11: "place the item, pick an action, check the change, forge", with the materials of the
-- backpack and the stash. Server: extended opcode 232 (server/data/scripts/chaos/crafting.lua), the additive fields:
--   open {forge = 1}            the window asks for them; an old client never does
--   forgeinfo {orbs = {key -> {kind, safety}}}   kind: mod | add | whole | sockets, safety: safe | random | risky
--   state.bag / state.stash = {orb key -> count}  (state.counts is their sum); state.item.free = {prefix, suffix},
--                                                 state.item.veil = 1 (veiled) | 2 (revealed)
--   explain {orb, path, id, sig, mod} -> explain {orb, mod, sig, ok, kind, tag, reason, reasonText, text, lead, warn,
--                                                 cost = {orb, n, bag, stash, from}}
--   result {ok, orb, text, from = "bag" | "stash"}
-- Every text of what happens comes from the server (explain); nothing is computed here but counts and layout. The window
-- never sends "apply" for an action the server has not explained for this very item (V.request).
-- The view does not assume tabs or one screen: groups of modifiers, the actions with their kind, enabled state and
-- reason, the safety tag, the cost with both counts, the current step.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

CraftingForgeView = CraftingForgeView or {}
local V = CraftingForgeView

-- ---------------------------------------------------------------- fixed tables
V.KINDS = { 'mod', 'add', 'whole', 'sockets' } -- the tabs of the actions, in order
V.SETTINGS = 'chaosForge'

-- the tier colours of the item tooltip (game_itemtooltip/tooltiplogic.lua L.TIER_COLORS; forgeview_test.lua keeps them equal)
V.TIER_COLORS = { '#8c8070', '#a89c88', '#c8c8c8', '#5ccf5c', '#4a90ff', '#a35cf0', '#ffd040', '#ff8a40' }
-- rarity colours (crafting.lua RARITY_COLOR; an old id 6 .. 9 became Legendary, 11 .. 15 Divine)
V.RARITY_COLORS = { '#c4cebc', '#5fd35f', '#4a8cff', '#b070ff', '#f6cf72', '#f6cf72', '#f6cf72', '#f6cf72', '#f6cf72',
  '#7fe6ff', '#7fe6ff', '#7fe6ff', '#7fe6ff', '#7fe6ff', '#7fe6ff' }
V.KEY_COLOR = '#c0a0ff'
V.TAG_COLORS = { safe = '#7fe0a0', random = '#e8b84a', risky = '#e05a40' }
V.DIM = '#6b6258'

local function num(v) return tonumber(v) or 0 end
local function tbl(v) return type(v) == 'table' and v or {} end
local function str(v) return type(v) == 'string' and v or '' end

function V.tierColor(t)
  local tip = rawget(_G, 'ItemTooltipLogic')
  local colors = tip and tip.TIER_COLORS or V.TIER_COLORS
  return colors[num(t)] or '#8c8070'
end

function V.rarityColor(r) return V.RARITY_COLORS[num(r)] or '#d6c9ae' end

function V.tagColor(tag) return V.TAG_COLORS[tag] or V.DIM end

-- ---------------------------------------------------------------- the words
-- the short action of each orb: what pressing it does (the name of the orb is next to it)
function V.verb(key, name)
  if key == 'ember' then return tr('Raise tier')
  elseif key == 'reforging' then return tr('Roll again')
  elseif key == 'excision' then return tr('Remove')
  elseif key == 'binding' then return tr('Bind')
  elseif key == 'exalted' then return tr('Add a modifier')
  elseif key == 'unveiling' then return tr('Reveal the veil')
  elseif key == 'transmutation' then return tr('Awaken')
  elseif key == 'alchemy' then return tr('Gild')
  elseif key == 'annulment' then return tr('Take one away')
  elseif key == 'scouring' then return tr('Erase all')
  elseif key == 'chaos' then return tr('Redo all')
  elseif key == 'divine' then return tr('Raise by fate')
  elseif key == 'tempering' then return tr('Roll the values')
  elseif key == 'ruin' then return tr('Gamble')
  elseif key == 'whetstone' then return tr('Quality +1%')
  elseif key == 'crown' then return tr('Raise rarity')
  elseif key == 'void' then return tr('Corrupt')
  elseif key == 'sockets' then return tr('Roll the sockets')
  end
  return name or key
end

function V.tabLabel(id)
  if id == 'mod' then return tr('SHAPE A MODIFIER')
  elseif id == 'add' then return tr('ADD A MODIFIER')
  elseif id == 'whole' then return tr('WHOLE ITEM')
  elseif id == 'sockets' then return tr('SOCKETS AND GEMS')
  elseif id == 'salvage' then return tr('SALVAGE')
  elseif id == 'guide' then return tr('GUIDE')
  end
  return id
end

function V.stepLabel(i)
  if i == 1 then return tr('Place the item')
  elseif i == 2 then return tr('Pick an action')
  elseif i == 3 then return tr('Check the change')
  elseif i == 4 then return tr('Forge')
  end
  return ''
end

function V.tagLabel(tag)
  if tag == 'safe' then return tr('SAFE')
  elseif tag == 'random' then return tr('RANDOM')
  elseif tag == 'risky' then return tr('RISKY')
  end
  return ''
end

function V.groupLabel(side)
  if side == 'prefix' then return tr('PREFIXES')
  elseif side == 'suffix' then return tr('SUFFIXES')
  elseif side == 'implicit' then return tr('CORRUPTED IMPLICIT')
  end
  return tr('KEY MODIFIERS')
end

-- ---------------------------------------------------------------- the actions
local function contains(list, value)
  for _, v in ipairs(tbl(list)) do
    if v == value then return true end
  end
  return false
end
V.contains = contains

local function reasonText(info, code)
  local reasons = info and type(info.reasons) == 'table' and info.reasons or {}
  return reasons[code] or code
end

-- the orbs of the server's list as actions: {key, name, verb, clientId, kind, tag, bag, stash, total, can, why, text}
-- ctx = {info, forge (forgeinfo), state, mod (the chosen modifier key or nil)}. `can` = the server allows it on this item
-- (and, for an action aimed at a modifier, the chosen one is one it may act on) and the player has the orb; `why` is the
-- server's own reason when not.
function V.actions(ctx)
  local state, info = ctx.state or {}, ctx.info or {}
  local item = type(state.item) == 'table' and state.item or nil
  local counts = tbl(state.counts)
  local out = {}
  for _, o in ipairs(tbl(info.orbs)) do
    if type(o) == 'table' and type(o.key) == 'string' then
      local f = tbl(tbl(ctx.forge and ctx.forge.orbs)[o.key])
      local bag = state.bag and num(tbl(state.bag)[o.key]) or num(counts[o.key])
      local stash = state.stash and num(tbl(state.stash)[o.key]) or 0
      local total = num(counts[o.key])
      if total < bag + stash then total = bag + stash end
      local kind = f.kind
      if not contains(V.KINDS, kind) then kind = 'whole' end
      local a = { key = o.key, name = str(o.name) ~= '' and o.name or o.key, clientId = num(o.clientId), kind = kind,
        tag = V.TAG_COLORS[f.safety] and f.safety or 'random', bag = bag, stash = stash, total = total, text = str(o.text),
        keyText = str(o.keyText), itemOk = false }
      a.verb = V.verb(a.key, a.name)
      local why = ''
      if not item then
        why = tr('Put an item on the bench first.')
      else
        local code = tbl(item.orbs)[a.key]
        if code ~= nil and code ~= '' then
          why = reasonText(info, code)
        else
          a.itemOk = true
          if kind == 'mod' then
            local picks = tbl(tbl(item.pick)[a.key])
            if #picks == 0 then
              why = tr('No modifier of this item can take this action.')
              a.itemOk = false
            elseif not ctx.mod then
              why = reasonText(info, 'needMod')
            elseif not contains(picks, ctx.mod) then
              why = reasonText(info, 'badMod')
            end
          end
        end
        if why == '' and total <= 0 then why = tr('You have no %s.', a.name) end
      end
      a.why, a.can = why, why == ''
      out[#out + 1] = a
    end
  end
  return out
end

function V.find(actions, key)
  for _, a in ipairs(actions) do
    if a.key == key then return a end
  end
  return nil
end

-- the actions of one kind
function V.ofKind(actions, kind)
  local out = {}
  for _, a in ipairs(actions) do
    if a.kind == kind then out[#out + 1] = a end
  end
  return out
end

-- ---------------------------------------------------------------- the tabs
-- the tabs to draw: {id, label, can, exist, counted}; "can / exist" is the actions of the kind the server lets you do now
-- against all that exist. A Rift Key and a waystone have no sockets: that tab is left out. Salvage and Guide carry no count.
function V.tabs(actions, item)
  local out = {}
  local isKey = type(item) == 'table' and item.kind == 'riftkey'
  for _, kind in ipairs(V.KINDS) do
    local list = V.ofKind(actions, kind)
    if #list > 0 and not (kind == 'sockets' and isKey) then
      local can = 0
      for _, a in ipairs(list) do
        if a.itemOk and a.total > 0 then can = can + 1 end
      end
      out[#out + 1] = { id = kind, label = V.tabLabel(kind), can = can, exist = #list, counted = true }
    end
  end
  out[#out + 1] = { id = 'salvage', label = V.tabLabel('salvage'), counted = false }
  out[#out + 1] = { id = 'guide', label = V.tabLabel('guide'), counted = false }
  return out
end

function V.tabText(t)
  if t.counted then return string.format('%s  %d/%d', t.label, t.can or 0, t.exist or 0) end
  return t.label
end

-- ---------------------------------------------------------------- the item
-- the modifiers in groups: {implicit = rows, prefix = rows, suffix = rows, key = rows (a Rift Key or a waystone)}
-- row = {key, tier, tierText, color, text, range, bound, power, implicit, group, mark}
function V.modGroups(item)
  local groups = { implicit = {}, prefix = {}, suffix = {}, key = {} }
  if type(item) ~= 'table' then return groups end
  for _, m in ipairs(tbl(item.mods)) do
    if type(m) == 'table' then
      local side = m.implicit and 'implicit' or m.side
      if side ~= 'implicit' and side ~= 'prefix' and side ~= 'suffix' then side = 'key' end
      local tier = tonumber(m.tier)
      local row = { key = m.key, tier = tier, tierText = tier and ('T' .. tier) or '', color = tier and V.tierColor(tier) or V.KEY_COLOR,
        text = str(m.short) ~= '' and m.short or str(m.text), bound = m.bound == true, power = m.power == true,
        implicit = m.implicit == true, group = m.group, side = side }
      if tier and m.lo and m.hi then
        row.range = m.lo == m.hi and string.format('[%d]', num(m.lo)) or string.format('[%d-%d]', num(m.lo), num(m.hi))
      end
      row.mark = row.bound and tr('BOUND') or ''
      local g = groups[side]
      g[#g + 1] = row
    end
  end
  return groups
end

-- the groups to draw in order, each {side, label, rows}; empty groups left out (a header without a row says nothing)
function V.groupList(item)
  local groups, out = V.modGroups(item), {}
  for _, side in ipairs({ 'implicit', 'prefix', 'suffix', 'key' }) do
    if #groups[side] > 0 then out[#out + 1] = { side = side, label = V.groupLabel(side), rows = groups[side] } end
  end
  return out
end

-- the modifier chosen before stays chosen while the item still has it
function V.keepSelection(item, mod)
  if not mod or type(item) ~= 'table' then return nil end
  for _, m in ipairs(tbl(item.mods)) do
    if type(m) == 'table' and m.key == mod and not m.implicit then return mod end
  end
  return nil
end

function V.modByKey(item, key)
  for _, m in ipairs(tbl(type(item) == 'table' and item.mods or nil)) do
    if type(m) == 'table' and m.key == key then return m end
  end
  return nil
end

-- "Free slots: 1 prefix, 0 suffix": the server's numbers (item.free; before them: the limits less the used)
function V.freeSlots(item)
  if type(item) ~= 'table' then return nil end
  local free = item.free
  if type(free) == 'table' then return num(free.prefix), num(free.suffix) end
  local p, s = tbl(item.prefixes), tbl(item.suffixes)
  if p[2] and s[2] then return math.max(0, num(p[2]) - num(p[1])), math.max(0, num(s[2]) - num(s[1])) end
  return nil
end

function V.freeText(item)
  local p, s = V.freeSlots(item)
  if not p then return '' end
  return tr('Free slots: %d prefix, %d suffix', p, s)
end

-- the header of the item on the bench: {name, color, line, free, lock}
function V.header(item)
  if type(item) ~= 'table' then
    return { name = tr('Empty bench'), color = '#8c8070', line = tr('Put an item from your backpack on the bench.'), free = '', lock = '' }
  end
  local h = { name = str(item.name) ~= '' and item.name or '?', free = V.freeText(item), lock = item.locked and tr('Locked') or '' }
  if item.kind == 'riftkey' then
    h.color = V.KEY_COLOR
    h.line = item.waystone and tr('%s, tier %d (monster level %d)', tr(str(item.rarityName)), num(item.tier), num(item.level))
      or tr('Rift Key, tier %d (level %d+)', num(item.tier), num(item.level))
    h.free = tr('Modifiers %d/%d', #tbl(item.mods), num(item.maxMods))
    return h
  end
  if item.unique then
    h.color = '#e07b24'
    h.line = tr('Unique item: orbs cannot change it')
    h.free = ''
    return h
  end
  h.color = V.rarityColor(item.rarity)
  local parts = { tr(str(item.rarityName) ~= '' and item.rarityName or 'Normal') }
  if num(item.level) > 0 then parts[#parts + 1] = tr('item level %d', num(item.level)) end
  if num(item.rarity) > 0 then parts[#parts + 1] = tr('quality %d%%', num(item.quality)) end
  local sk = tbl(item.sockets)
  if num(sk.max) > 0 then parts[#parts + 1] = tr('sockets %d/%d', num(sk.count), num(sk.max)) end
  if item.ruined then parts[#parts + 1] = tr('RUINED') end
  if item.corrupted then parts[#parts + 1] = tr('CORRUPTED') end
  h.line = table.concat(parts, ' · ')
  return h
end

-- ---------------------------------------------------------------- the materials strip
local function shortName(name) return (str(name):gsub('^Orb of ', '')) end

-- every material the bench can spend: {key, name, clientId, count, bag, stash, dim, tip}
function V.materials(ctx)
  local state, out = ctx.state or {}, {}
  for _, a in ipairs(V.actions({ info = ctx.info, forge = ctx.forge, state = { counts = state.counts, bag = state.bag, stash = state.stash } })) do
    local tip = a.name .. '\n' .. a.text .. '\n' .. tr('%d in backpack, %d in stash', a.bag, a.stash)
    out[#out + 1] = { key = a.key, name = shortName(a.name), clientId = a.clientId, count = a.total, bag = a.bag, stash = a.stash,
      dim = a.total <= 0, tip = tip }
  end
  return out
end

-- ---------------------------------------------------------------- the chosen change
function V.costLine(a)
  if not a then return '' end
  return tr('Cost: 1 %s. You have %d (%d in backpack, %d in stash).', a.name, a.total, a.bag, a.stash)
end

function V.costShort(a)
  if not a then return '' end
  return tr('Costs 1 %s (backpack first, then stash)', a.name)
end

-- the server's answer in one text: "Guaranteed: tier 3 to tier 4. ..." / "Random: ..." (+ the warning of a risky one)
function V.explainText(ex)
  if type(ex) ~= 'table' then return '' end
  if ex.ok == false then return str(ex.reasonText) ~= '' and ex.reasonText or str(ex.reason) end
  local text = str(ex.text)
  if ex.lead == 'fixed' then text = tr('Guaranteed:') .. ' ' .. text
  elseif ex.lead == 'random' then text = tr('Random:') .. ' ' .. text end
  if ex.warn then text = text .. ' ' .. tr('This can cost you modifiers.') end
  return text
end

-- does the answer belong to the chosen action on the item as it is now?
function V.answered(ctx)
  local item, sel, ex = ctx.state and ctx.state.item, ctx.sel or {}, ctx.explain
  if type(item) ~= 'table' or type(ex) ~= 'table' or not sel.orb then return false end
  return ex.orb == sel.orb and (ex.mod or false) == (sel.mod or false) and ex.sig == item.sig
end

-- the current step 1 .. 4 and the lit (done) ones: 1 no item; 2 an item, no action chosen; 3 an action chosen, the
-- server has not (or not yet well) explained it; 4 explained: forge
function V.step(ctx)
  local item, sel = ctx.state and ctx.state.item, ctx.sel or {}
  local cur
  if type(item) ~= 'table' then cur = 1
  elseif not sel.orb then cur = 2
  elseif V.answered(ctx) and ctx.explain.ok == true then cur = 4
  else cur = 3 end
  local done = {}
  for i = 1, 4 do done[i] = i < cur end
  return cur, done
end

-- the data of "apply", or nil and why: only for an action the server explained for this item, with the orb in hand
function V.request(ctx)
  local item, sel = ctx.state and ctx.state.item, ctx.sel or {}
  if type(item) ~= 'table' then return nil, tr('Put an item on the bench first.') end
  if not sel.orb then return nil, tr('Pick an action first.') end
  if not V.answered(ctx) then return nil, tr('Wait for the server to explain the change.') end
  if ctx.explain.ok ~= true then return nil, V.explainText(ctx.explain) end
  local a = V.find(V.actions({ info = ctx.info, forge = ctx.forge, state = ctx.state, mod = sel.mod }), sel.orb)
  if not a then return nil, tr('Pick an action first.') end
  if not a.can then return nil, a.why end
  return { orb = sel.orb, path = item.path, id = item.id, sig = item.sig, mod = sel.mod }
end

-- the bottom bar: {summary, detail, cost, can, why, confirm (a text to ask once, a risky action), tag}
function V.bar(ctx)
  local sel = ctx.sel or {}
  local bar = { summary = tr('Choose an action'), detail = '', cost = '', can = false, why = '', tag = nil }
  local a = sel.orb and V.find(V.actions({ info = ctx.info, forge = ctx.forge, state = ctx.state, mod = sel.mod }), sel.orb)
  if not a then
    bar.why = (ctx.state and ctx.state.item) and tr('Pick an action first.') or tr('Put an item on the bench first.')
    return bar
  end
  bar.tag = a.tag
  local m = sel.mod and V.modByKey(ctx.state and ctx.state.item, sel.mod)
  bar.summary = m and tr('%s: %s', a.verb, str(m.short) ~= '' and m.short or str(m.text)) or a.verb
  bar.cost = V.costShort(a)
  if V.answered(ctx) then bar.detail = V.explainText(ctx.explain) end
  local req, why = V.request(ctx)
  bar.can, bar.why = req ~= nil, why or ''
  if req and a.tag == 'risky' then bar.confirm = tr('%s can cost you modifiers. Forge anyway?', a.name) end
  return bar
end

-- the line under the window after a craft: the server's text and where the orb came from
function V.resultLine(res)
  if type(res) ~= 'table' then return '' end
  local text = str(res.text)
  if res.ok and res.from == 'stash' then text = text .. ' ' .. tr('(the orb came from the stash)') end
  return text
end

-- ---------------------------------------------------------------- the classic choice, per character (g_settings node)
function V.savedMode(node, name)
  local chars = type(node) == 'table' and type(node.chars) == 'table' and node.chars or {}
  return chars[tostring(name or '')] == 'classic' and 'classic' or 'forge'
end

function V.rememberMode(node, name, mode)
  local out = { chars = {} }
  if type(node) == 'table' and type(node.chars) == 'table' then
    for k, v in pairs(node.chars) do out.chars[k] = v end
  end
  if name and name ~= '' then out.chars[tostring(name)] = mode == 'classic' and 'classic' or 'forge' end
  return out
end

-- ---------------------------------------------------------------- a text dump of what the window shows (states.txt)
function V.lines(ctx)
  local state = ctx.state or {}
  local item = type(state.item) == 'table' and state.item or nil
  local out = {}
  local function put(s) out[#out + 1] = s end
  local cur, done = V.step(ctx)
  local steps = {}
  for i = 1, 4 do
    steps[#steps + 1] = string.format('%d %s%s', i, V.stepLabel(i), i == cur and ' [now]' or (done[i] and ' [done]' or ''))
  end
  put('steps: ' .. table.concat(steps, '  >  '))
  local mats = {}
  for _, m in ipairs(V.materials(ctx)) do
    if not m.dim then mats[#mats + 1] = string.format('%s %d', m.name, m.count) end
  end
  put('materials: ' .. (#mats > 0 and table.concat(mats, ', ') or '-'))
  local h = V.header(item)
  put('item: ' .. h.name .. ' | ' .. h.line .. (h.free ~= '' and (' | ' .. h.free) or '') .. (h.lock ~= '' and (' | ' .. h.lock) or ''))
  local actions = V.actions({ info = ctx.info, forge = ctx.forge, state = state, mod = ctx.sel and ctx.sel.mod })
  local tabs = {}
  for _, t in ipairs(V.tabs(actions, item)) do tabs[#tabs + 1] = V.tabText(t) end
  put('tabs: ' .. table.concat(tabs, ' | '))
  local groups = V.groupList(item)
  if #groups == 0 then put('modifiers: none') end
  for _, g in ipairs(groups) do
    put(g.label .. ':')
    for _, r in ipairs(g.rows) do
      local sel = ctx.sel and ctx.sel.mod == r.key and '>' or ' '
      put(string.format(' %s %s %s %s%s', sel, r.tierText ~= '' and r.tierText or '--', r.text, r.range or '', r.bound and ' [' .. r.mark .. ']' or ''))
    end
  end
  if item and item.veil == 1 then put(' (veiled modifier, not revealed)') end
  for _, kind in ipairs(V.KINDS) do
    for _, a in ipairs(V.ofKind(actions, kind)) do
      put(string.format('action [%s] %s (%s) x%d (%d backpack, %d stash) tag %s: %s', kind, a.verb, a.name, a.total, a.bag, a.stash, -- i18n-ok: a text dump for the review, not UI
        V.tagLabel(a.tag), a.can and 'ready' or a.why))
    end
  end
  local bar = V.bar(ctx)
  put('bar: ' .. bar.summary .. (bar.detail ~= '' and (' | ' .. bar.detail) or '') .. (bar.cost ~= '' and (' | ' .. bar.cost) or '')
    .. ' | forge ' .. (bar.can and 'on' or ('off: ' .. bar.why)))
  return out
end

return V
