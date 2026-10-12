-- Loadouts window texts and rules (pure, no UI calls): shared by loadouts.lua and loadoutsview_test.lua.
-- `s` is the server's state (server data/scripts/chaos/loadouts.lua L.state), `slot` one of s.slots.

LoadoutsView = LoadoutsView or {}
local V = LoadoutsView

V.COLORS = { gold = '#e8b84a', text = '#d8ccb4', dim = '#8c8070', good = '#8fd16a', warn = '#e0a050', bad = '#e07060',
  active = '#7fc4ff' }
V.ICON_DIR = '/images/chaos/small/topbutton_'

local function num(v) return tonumber(v) or 0 end

local function cap(s)
  s = tostring(s or '')
  return (s:gsub('^%l', string.upper))
end

function V.iconPath(icon)
  if not icon or icon == '' then icon = 'skills' end
  return V.ICON_DIR .. icon
end

-- the level a locked slot opens at (nil: never / not locked)
function V.unlockLevel(s, index)
  if not s then return nil end
  local k = index - num(s.baseSlots)
  local levels = s.unlockLevels or {}
  return levels[k]
end

-- one row of the slot list: title, sub line, tag (and its colour), dim
function V.slotRow(s, slot)
  local row = { icon = V.iconPath(slot and slot.icon), tag = '', tagColor = V.COLORS.dim, dim = false }
  if not slot then
    row.title, row.sub = '?', ''
    return row
  end
  if slot.locked and slot.empty then
    local lvl = V.unlockLevel(s, slot.slot)
    row.title = 'Locked slot'
    row.sub = lvl and string.format('Opens at level %d', lvl) or 'Locked'
    row.dim = true
    row.icon = V.iconPath('options')
    return row
  end
  if slot.empty then
    row.title, row.sub = 'Empty slot', 'Save your current build here'
    row.dim = true
    row.icon = V.iconPath('inventory')
    return row
  end
  row.title = slot.name or ('Loadout ' .. num(slot.slot))
  local parts = {}
  parts[#parts + 1] = string.format('%d pts', num(slot.points))
  if num(slot.supports and slot.supports.count) > 0 then
    parts[#parts + 1] = string.format('%d runes', num(slot.supports.count))
  end
  local g = slot.gear or {}
  if num(g.total) > 0 then
    parts[#parts + 1] = string.format('gear %d/%d', num(g.ready), num(g.total))
  end
  row.sub = table.concat(parts, ' | ')
  if slot.active then
    row.tag, row.tagColor = 'ACTIVE', V.COLORS.active
  elseif slot.locked then
    row.tag, row.tagColor = 'LOCKED', V.COLORS.dim
  elseif #(slot.warnings or {}) > 0 or #(g.missing or {}) > 0 then
    row.tag, row.tagColor = 'CHECK', V.COLORS.warn
  end
  return row
end

function V.gearLine(g)
  g = g or {}
  local total, ready = num(g.total), num(g.ready)
  if total == 0 then return 'Gear set: none (save while wearing it)', V.COLORS.dim end
  if ready >= total then return string.format('Gear set: complete (%d/%d)', ready, total), V.COLORS.good end
  return string.format('Gear set: %d/%d ready', ready, total), V.COLORS.warn
end

-- the summary of a slot: {{text, color}, ...}; profile = the action bar profile remembered for it (client-side)
function V.summary(s, slot, profile)
  local out = {}
  local function add(text, color) out[#out + 1] = { text = text, color = color or V.COLORS.text } end
  if not slot then return out end
  if slot.empty then
    if slot.locked then
      local lvl = V.unlockLevel(s, slot.slot)
      add(lvl and string.format('This slot opens at level %d. Extra slots are earned by levelling, never sold.', lvl)
        or 'This slot is locked.', V.COLORS.dim)
    else
      add('Empty. Save copies your current build here: passive tree, Paragon points, the equipped gear set.', V.COLORS.dim)
      add('Support runes stay with the loadout they are socketed in.', V.COLORS.dim)
    end
    return out
  end
  local cls = cap(slot.cls)
  if (slot.voc or '') ~= '' and cap(slot.voc) ~= cls and cls ~= '' then
    add(string.format('Class: %s (%s)', cls, slot.voc))
  else
    add('Class: ' .. (slot.voc ~= '' and slot.voc or cls))
  end
  add(string.format('Passive points: %d / %d', num(slot.points), num(slot.pointsTotal)))
  if #(slot.keystones or {}) > 0 then
    add('Keystones: ' .. table.concat(slot.keystones, ', '), V.COLORS.gold)
  else
    add('Keystones: none', V.COLORS.dim)
  end
  if num(slot.paragon) > 0 then add(string.format('Paragon points: %d', num(slot.paragon))) end
  local sup = slot.supports or {}
  if num(sup.count) > 0 then
    add(string.format('Supports: %d rune%s', num(sup.count), num(sup.count) == 1 and '' or 's'))
    for _, sp in ipairs(sup.spells or {}) do
      add('  ' .. tostring(sp.name) .. ': ' .. table.concat(sp.runes or {}, ', '), V.COLORS.dim)
    end
  else
    add('Supports: none', V.COLORS.dim)
  end
  local gtext, gcolor = V.gearLine(slot.gear)
  add(gtext, gcolor)
  for _, m in ipairs((slot.gear or {}).missing or {}) do
    local where = m.where == 'missing' and 'not found' or tostring(m.where or 'not found')
    add('  Missing: ' .. tostring(m.name) .. ' (' .. where .. ')', V.COLORS.bad)
  end
  if profile and profile ~= '' then add('Action bar: ' .. profile, V.COLORS.dim) end
  for _, w in ipairs(slot.warnings or {}) do add(w, V.COLORS.warn) end
  if slot.active then add('Active: this is your current build. Edit it in the passive tree window.', V.COLORS.active) end
  return out
end

-- seconds of cooldown left, counted down from the state's time
function V.cooldownLeft(s, elapsed)
  if not s then return 0 end
  return math.max(0, num(s.cooldown) - math.floor(num(elapsed)))
end

-- the status line under the buttons: how a switch would go now
function V.switchHint(s, elapsed)
  if not s then return '', V.COLORS.dim end
  if num(s.level) < num(s.minLevel) then return string.format('Loadouts open at level %d.', num(s.minLevel)), V.COLORS.dim end
  if s.casting then return 'Switching... stand still.', V.COLORS.active end
  if s.busy then return 'No switching inside ' .. s.busy .. '.', V.COLORS.bad end
  local left = V.cooldownLeft(s, elapsed)
  if left > 0 then return string.format('Next switch in %d s.', left), V.COLORS.warn end
  if s.inPz then return 'Protection zone: switching is instant and free.', V.COLORS.good end
  return string.format('Switching takes %.1f s here (stand still). Free.', num(s.castMs) / 1000), V.COLORS.text
end

-- which buttons work for the selected slot
function V.buttons(s, slot, elapsed)
  local b = { save = false, load = false, rename = false, delete = false }
  if not s or not slot then return b end
  local usable = not slot.locked and num(s.level) >= num(s.minLevel)
  b.save = usable
  b.rename = not slot.empty
  b.delete = not slot.empty
  b.load = usable and not slot.empty and not slot.active and not s.casting and not s.busy and V.cooldownLeft(s, elapsed) == 0
  b.saveText = slot.empty and 'Save here' or (slot.active and 'Save' or 'Overwrite')
  return b
end

function V.nextIcon(icons, current)
  icons = icons or {}
  if #icons == 0 then return current end
  for i, icon in ipairs(icons) do
    if icon == current then return icons[i % #icons + 1] end
  end
  return icons[1]
end

-- the client-side action bar profile per character and slot
function V.profileKey(charName, slot)
  return tostring(charName or '?'):lower() .. ':' .. tostring(num(slot))
end

-- the result box text: the main line and the extra lines
function V.resultText(res)
  if type(res) ~= 'table' then return '' end
  local lines = { tostring(res.text or '') }
  for _, l in ipairs(res.lines or {}) do lines[#lines + 1] = tostring(l) end
  return table.concat(lines, '\n')
end

-- the slot to select after a new state: keep the selection, else the active one, else the first
function V.pickSelection(s, current)
  if not s or not s.slots or #s.slots == 0 then return nil end
  for _, slot in ipairs(s.slots) do
    if slot.slot == current then return current end
  end
  for _, slot in ipairs(s.slots) do
    if slot.active then return slot.slot end
  end
  return s.slots[1].slot
end
