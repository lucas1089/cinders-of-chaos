-- Tests of charselect_core.lua (no client API): luajit / lua5.3 client/overlay/modules/client_chaos_charselect/charselect_core_test.lua
local dir = (arg and arg[0] or ''):match('^(.*)[/\\]') or '.'
local C = dofile(dir .. '/charselect_core.lua')

local fails = 0
local function check(cond, what)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. what)
  end
end

-- ---------------------------------------------------------------- classes
check(C.classText(4) == 'Warrior' and C.classText(8) == 'Juggernaut (Warrior)', 'base and ascended class text')
check(C.classText(19) == 'Iron Sage (Monk)' and C.classText(22) == 'Bone Lord (Necromancer)', 'locked lines too')
check(C.classText(2) == 'Mystic' and C.classText(6) == 'Illusionist (Mystic)' and C.classText(9) == 'Mystic', 'retired ids')
check(C.classInfo(0).name == 'No class' and C.classInfo(99).name == 'Unknown class', 'unknown ids')
check(C.iconPath(25) == '/images/chaos/charselect/class_templar' and C.iconPath(0) == '/images/chaos/charselect/class_none', 'icons')
check(C.classInfo(20).lock == 'necromancer' and C.classInfo(4).lock == '', 'lock keys')

-- every class id of the server (chaos_constants.lua) is known, with the same line (baseOf)
local f = io.open(dir .. '/../../../../server/data/scripts/chaos/chaos_constants.lua', 'r')
if f then
  local text = f:read('*a')
  f:close()
  local baseOf = text:match('baseOf = (%b{})')
  local n = 0
  for id, base in baseOf:gmatch('%[(%d+)%] = (%d+)') do
    n = n + 1
    check(C.classInfo(tonumber(id)).base == tonumber(base), 'line of class ' .. id)
  end
  check(n == 21, 'the 21 classes of Chaos.classes.baseOf')
  local ids = text:match('ids = (%b{})')
  for key, id in ids:gmatch('(%a+) = (%d+)') do
    local info = C.classInfo(tonumber(id))
    check(info.name:lower():gsub(' ', '') == key, 'class name of ' .. key)
  end
else
  print('note: server/data not found, the class table was not compared with chaos_constants.lua')
end

-- every class icon exists (client/tools/gen_charselect_art.py)
for _, line in ipairs(C.LINES) do
  local p = io.open(dir .. '/../../data/images/chaos/charselect/class_' .. line.icon .. '.png', 'rb')
  check(p ~= nil, 'icon of ' .. line.name)
  if p then p:close() end
end

-- ---------------------------------------------------------------- card text
local now = 1800000000
check(C.lastLoginText(0, now) == 'Never played', 'never played')
check(C.lastLoginText(now - 30, now) == 'Last played just now', 'just now')
check(C.lastLoginText(now - 600, now) == 'Last played 10 minutes ago', 'minutes')
check(C.lastLoginText(now - 5000, now) == 'Last played an hour ago', 'an hour')
check(C.lastLoginText(now - 5 * 3600, now) == 'Last played 5 hours ago', 'hours')
check(C.lastLoginText(now - 90000, now) == 'Last played yesterday', 'yesterday')
check(C.lastLoginText(now - 4 * 86400, now) == 'Last played 4 days ago', 'days')
check(C.lastLoginText(1700000000, now) == 'Last played on 2023-11-14', 'a date')
check(C.lastLoginText(now + 50, now) == 'Last played just now', 'a clock ahead')
check(C.lastLoginShort(now - 7300, now) == '2 hours ago' and C.lastLoginShort(0, now) == 'never played', 'short form')
check(C.lastLoginShort(1700000000, now) == '2023-11-14' and C.lastLoginShort(now - 90000, now) == 'yesterday', 'short form: date, yesterday')

-- the world name: ours from the config, never another one
local worlds = C.allowedWorlds({ LocalTestServ = { name = 'Cinders of Chaos', host = '127.0.0.1' }, Bad = 5 })
check(#worlds == 1 and worlds[1] == 'Cinders of Chaos', 'allowed worlds from Servers')
check(C.worldText('Cinders of Chaos', worlds, 'X') == 'Cinders of Chaos', 'our world name')
check(C.worldText('Some Base World', worlds, 'Cinders of Chaos') == 'Cinders of Chaos', 'a base data name is replaced')
check(C.worldText('Some Base World, Preview', worlds, 'Cinders of Chaos') == 'Cinders of Chaos, Preview', 'preview suffix kept')
check(C.worldText(nil, {}, nil) == 'Cinders of Chaos', 'nothing known')

-- ---------------------------------------------------------------- the outfit
local listOutfit = { type = 2161, head = 94, body = 77, legs = 79, feet = 114, addons = 3 }
local look = { type = 2161, head = 1, body = 2, legs = 3, feet = 4, addons = 0, wings = 937, aura = 932, shader = 'ember_glow' }
local o = C.mergeOutfit(listOutfit, look, function(s) return s == 'ember_glow' end)
check(o.type == 2161 and o.head == 94 and o.addons == 3, 'the list wins for look type, colours and addons')
check(o.wings == 937 and o.aura == 932 and o.shader == 'ember_glow', 'wings, aura and shader from the website')
o = C.mergeOutfit(listOutfit, look, function() return false end)
check(o.shader == nil, 'an unknown shader is not set')
o = C.mergeOutfit(listOutfit, nil)
check(o.type == 2161 and o.wings == nil and o.aura == nil, 'without the website: the list outfit alone')
o = C.mergeOutfit(nil, look)
check(o.type == 2161 and o.head == 1 and o.wings == 937, 'an item-shaped list outfit: the website look')
check(C.mergeOutfit(nil, nil) == nil and C.mergeOutfit({ type = 0 }, { type = 0 }) == nil, 'nothing to draw')

-- the cards
local chars = {
  { name = 'Old Guard', level = 312, vocationId = 8, worldName = 'Base World', outfit = listOutfit },
  { name = 'Ash Runner', level = 1, vocationId = 11, worldName = 'Cinders of Chaos', outfit = { type = 2175 } },
}
local cards = C.cards(chars, { ['Old Guard'] = look, ['Ash Runner'] = { lastLogin = 0, season = '[S1]' } }, now,
  { allowed = worlds, fallback = 'Cinders of Chaos' })
check(#cards == 2 and cards[1].classText == 'Juggernaut (Warrior)' and cards[1].levelText == 'Level 312', 'card 1')
check(cards[1].world == 'Cinders of Chaos' and cards[1].outfit.wings == 937, 'card 1 world and wings')
check(cards[1].lastShort == '' or cards[1].lastShort ~= nil, 'card 1 short last login')
check(cards[2].lastShort == 'never played' and cards[2].lastLogin == 'Never played' and cards[2].season == '[S1]' and cards[2].icon:find('class_thief'), 'card 2')
local bare = C.cards(chars, nil, now, {})
check(bare[1].lastLogin == '' and bare[1].outfit.type == 2161, 'cards without the website')

-- ---------------------------------------------------------------- navigation
check(C.move(1, 5, 'Up') == 1 and C.move(1, 5, 'Down') == 2 and C.move(5, 5, 'Down') == 5, 'up and down, clamped')
check(C.move(3, 5, 'Left') == 2 and C.move(3, 5, 'Right') == 4, 'left and right')
check(C.move(3, 9, 'Home') == 1 and C.move(3, 9, 'End') == 9, 'home and end')
check(C.move(2, 20, 'PageDown', 6) == 8 and C.move(2, 20, 'PageUp', 6) == 1, 'pages')
check(C.move(1, 0, 'Down') == 0, 'empty list')
check(C.initialIndex(chars, 'Ash Runner') == 2 and C.initialIndex(chars, 'Nobody') == 1 and C.initialIndex({}, 'x') == 0, 'first selection')

-- ---------------------------------------------------------------- the preview: feet on the pedestal
local A = dofile(dir .. '/outfit_anchors.lua')
check(type(A) == 'table' and type(A.dat) == 'string' and #A.dat == 32, 'anchor table with its pair md5')

-- the rect puts the feet exactly where asked, for every thing of the pair, at 3x and 4x, anywhere on screen
local n, worst = 0, 0
for id, e in pairs(A) do
  if type(id) == 'number' then
    n = n + 1
    local fig = C.figure(A, { type = id })
    for _, T in ipairs({ 96, 128 }) do
      for _, at in ipairs({ { 454, 418 }, { 90, 172 }, { 777, 641 } }) do
        local x, y, size = C.placeRect(fig, T, at[1], at[2])
        local fx, fy = C.feetOf(fig, x, y, size)
        worst = math.max(worst, math.abs(fx - at[1]), math.abs(fy - at[2]))
        check(size == 2 * T, 'rect size 2T')
      end
    end
    check(e[3] < e[2] and e[4] < e[5] and e[4] <= e[1] and e[1] <= e[5], 'anchor ' .. id .. ': feet inside its bounds')
  end
end
check(n > 1000, 'anchors for the pair\'s creature things: ' .. n)
check(worst <= 0.5, 'feet within half a pixel of the pedestal centre for every look (worst ' .. worst .. ')')

-- the maths by hand: a 1x1 look with its feet at (16, 24) on a 2x2 rect of 256 px (4x) at (500, 400)
local one = { fx = 16, fy = 24, top = -8, left = -8, right = 24 }
local x, y, size = C.placeRect(one, 128, 500, 400)
check(x == 500 - 48 * 4 and y == 400 - 56 * 4 and size == 256, '1x1: rect from the feet at 4x')
x, y, size = C.placeRect(one, 96, 500, 400)
check(x == 500 - 48 * 3 and y == 400 - 56 * 3 and size == 192, '1x1: rect from the feet at 3x')
-- a 2x2 class look drawn in the middle of its frame (feet left of its own tile) lands with its feet on the same spot
local wide = { fx = -8, fy = 17, top = -19, left = -23, right = 17 }
x, y = C.placeRect(wide, 128, 500, 400)
local fx, fy = C.feetOf(wide, x, y, 256)
check(fx == 500 and fy == 400 and x == 500 - 24 * 4, '2x2 look centred on the feet')

-- one stock 1x1-sized and the 2x2 class looks are in the table, and every class look of the server is
local function hasW(w)
  for id, e in pairs(A) do if type(id) == 'number' and e[6] == w and e[7] == w then return true end end
end
check(hasW(1) and hasW(2), '1x1 and 2x2 things in the table')
local cl = io.open(dir .. '/../../../../server/data/scripts/chaos/class_looks_core.lua', 'r')
if cl then
  local text = cl:read('*a')
  cl:close()
  local looks = 0
  for male, female in text:gmatch('male = (%d+), female = (%d+)') do
    looks = looks + 1
    check(A[tonumber(male)] ~= nil and A[tonumber(female)] ~= nil, 'class look ' .. male .. ' / ' .. female .. ' has its feet')
  end
  check(looks >= 21, 'every class look checked: ' .. looks)
end

-- wings and an aura make the picture taller and wider, never move the feet; a big aura is moved by (w - 1) * 16
local body = C.anchorOf(A, 2161)
local fig = C.figure(A, { type = 2161, wings = 1179, aura = 1512 })
local wingA, auraA = C.anchorOf(A, 1179), C.anchorOf(A, 1512)
check(fig.fx == body.fx and fig.fy == body.fy, 'wings and aura keep the feet')
check(fig.top == math.min(body.top, wingA.top, auraA.top + (auraA.h - 1) * 16), 'the top over body, wings and the moved aura')
check(fig.left <= body.left and fig.right >= body.right, 'wider with wings and aura')

-- a winged character flies 6 px up and left (GameWingOffset): its feet with it, its wings not
local lifted = C.figure(A, { type = 2161, wings = 1179 }, nil, 6)
local still = C.figure(A, { type = 2161, wings = 1179 })
check(lifted.fx == still.fx - 6 and lifted.fy == still.fy - 6, 'wings lift the feet by 6')
check(C.figure(A, { type = 2161 }, nil, 6).fy == C.anchorOf(A, 2161).fy, 'no wings, no lift')
x, y = C.placeRect(lifted, 128, 500, 400)
fx, fy = C.feetOf(lifted, x, y, 256)
check(fx == 500 and fy == 400 and y == 400 - (C.anchorOf(A, 2161).fy - 6 + 32) * 4, 'the lifted feet still on the platform')

-- the scale: 4x with room, 3x when the wings do not fit at 4x, the feet moved down when not even 3x fits
local plain = C.figure(A, { type = 2073 })
local T, sc, drop = C.fitPreview(plain, { above = 400, half = 300, below = 100 })
check(T == 128 and sc == 4 and drop == 0, 'a plain look: 4x')
local tall = (fig.fy - fig.top)
T, sc, drop = C.fitPreview(fig, { above = tall * 4 - 1, half = 1000, below = 100 })
check(T == 96 and sc == 3 and drop == 0, 'wings too tall for 4x: 3x')
T, sc, drop = C.fitPreview(fig, { above = tall * 3 - 30, half = 1000, below = 100 })
check(sc == 3 and drop == 30, 'too tall even at 3x: the feet move down by what is missing')
T, sc, drop = C.fitPreview(fig, { above = tall * 3 - 300, half = 1000, below = 100 })
check(drop == 100, 'never further down than allowed')
T, sc = C.fitPreview(plain, { above = 1000, half = (plain.right - plain.fx) * 4 - 1, below = 0 })
check(sc == 3, 'too wide for 4x: 3x')
T, sc = C.fitPreview(plain, { above = 1000, half = 10, below = 0 }, { 3, 2 })
check(sc == 2 and T == 64, 'other scales (the create window falls back to 2x)')

-- the platform: 2.2 tiles wide in the image's proportions, the feet on its top face's centre
for _, T in ipairs({ 64, 96, 128 }) do
  local px, py, pw, ph = C.platformRect(T, 500, 400)
  check(math.abs(pw - 2.2 * T) <= 0.5 and math.abs(ph - pw * 96 / 256) <= 0.5, 'platform size at ' .. T)
  check(math.abs(px + pw / 2 - 500) <= 0.5 and math.abs(py + ph * C.PLATFORM_FEET - 400) <= 0.5, 'platform under the feet at ' .. T)
end

-- auras: a small ring at the feet is drawn, a tall one (the "red crystal" behind the Juggernaut: 1512) is not;
-- wings always are
check(C.smallAura(A, 932) and not C.smallAura(A, 1512) and not C.smallAura(A, 1514) and not C.smallAura(A, 99999), 'which auras stay')
local po = C.previewOutfit(A, { type = 2161, head = 94, addons = 3, wings = 1179, aura = 1512 })
check(po.aura == 0 and po.wings == 1179 and po.type == 2161 and po.head == 94 and po.addons == 3, 'a tall aura left out, wings kept')
local orig = { type = 2164, aura = 932 }
po = C.previewOutfit(A, orig)
check(po.aura == 932 and po ~= orig, 'a small aura at the feet kept, on a copy')
check(C.previewOutfit(A, nil) == nil, 'no outfit')
local tallFig = C.figure(A, C.previewOutfit(A, { type = 2161, wings = 1179, aura = 1512 }))
check(tallFig.top == math.min(C.anchorOf(A, 2161).top, C.anchorOf(A, 1179).top), 'the bounds without the left-out aura')

-- the slots line never shows more used than the limit
check(C.slotsText(3, { used = 3, limit = 5 }) == '3 characters, 3 of 5 slots used', 'slots: some free')
check(C.slotsText(1, { used = 1, limit = 5 }) == '1 character, 1 of 5 slots used', 'slots: one character')
check(C.slotsText(5, { used = 5, limit = 5 }) == '5 characters, no free slot', 'slots: all used')
check(C.slotsText(10, { used = 10, limit = 5 }) == '10 characters, no free slot', 'slots: more characters than the limit')
check(C.slotsText(10, { used = 4, limit = 5 }) == '10 characters, no free slot', 'slots: the list counts more than the site')
check(C.slotsText(4, nil) == '4 characters', 'slots: no website')
local line, bad = C.slotsLine({ used = 2, limit = 5 })
check(line == 'Character slots: 2 of 5 used.' and bad == false, 'create window: slots free')
line, bad = C.slotsLine({ used = 10, limit = 5 })
check(line:find('No free character slot', 1, true) == 1 and bad == true and not line:find('10'), 'create window: no slot free, no "10 of 5"')
check(C.slotsLine(nil) == '', 'create window: no website')

-- a look of a newer pair (not in the table): its size and displacement
local fb = C.anchorOf(A, 99999, { w = 1, h = 1, dx = 8, dy = 8 })
check(fb.fx == 8 and fb.fy == 24 and fb.top == -8 and fb.left == -8 and fb.right == 24, 'fallback from displacement')
local fb2 = C.anchorOf(nil, 5, nil)
check(fb2.fy == 24 and fb2.w == 1, 'fallback without a table')
check(C.figure(A, nil) == nil, 'no outfit, no figure')

-- ---------------------------------------------------------------- the create window
local rules = { minL = 3, maxL = 20, maxW = 3 }
check(C.checkName('Ember Child', rules) == nil, 'a good name')
check(C.checkName('  Ember Child ', rules) == nil, 'spaces around are trimmed')
check(C.checkName('', rules) == 'Enter a name.', 'empty')
check(C.checkName('Ash3n', rules) == 'Use letters and spaces only.', 'digits')
check(C.checkName('Ash  Walker', rules) == 'Use one space between words.', 'double space')
check(C.checkName('A Walker', rules) == 'Every word needs at least two letters.', 'one-letter word')
check(C.checkName('One Two Three Four', rules) == 'Use at most 3 words.', 'too many words')
check(C.checkName('Ab', rules) == 'The name needs 3 to 20 letters.', 'too short')
check(C.checkName('Abcdefghijklmnopqrstu', rules) == 'The name needs 3 to 20 letters.', 'too long')

local state = { account = {
  classes = { { id = 4, name = 'Warrior', icon = 'warrior', locked = false }, { id = 20, name = 'Necromancer', icon = 'necromancer', locked = true } },
  season = { id = 1, name = 'Season of Ash', tag = '[S1]', modes = { { key = 'standard', name = 'Standard' }, { key = 'hc', name = 'Hardcore', hc = true, warning = 'One life.' } } },
} }
local cc = C.classChoices(state)
check(#cc == 2 and cc[2].locked and cc[2].icon == '/images/chaos/charselect/class_necromancer', 'classes from the website')
local offline = C.classChoices(nil)
check(#offline == 7 and not offline[1].locked and offline[5].locked and offline[6].locked and offline[7].locked, 'classes without the website: locks shown')
local sc = C.seasonChoices(state)
check(#sc == 3 and sc[1].season == 0 and sc[3].hc and sc[3].label == 'Season of Ash [S1]: Hardcore', 'season choices')
check(#C.seasonChoices({ account = { season = nil } }) == 1, 'no season running')

local n1, n2 = C.nonce(), C.nonce()
check(#n1 == 32 and n1:match('^[0-9a-f]+$') and n1 ~= n2, 'nonces')
local req = C.createRequest('tok', { name = ' Ash Runner ', vocation = '11', sex = 0, season = 1, mode = 'hc', hardcore = 1 }, 'abc')
check(req.action == 'create' and req.name == 'Ash Runner' and req.vocation == 11 and req.sex == 0 and req.hardcore == true
  and req.season == 1 and req.mode == 'hc' and req.nonce == 'abc' and req.token == 'tok', 'create request')
local lr = C.loginRequest('acc', 'pw', 'n')
check(lr.action == 'login' and lr.account == 'acc' and lr.password == 'pw' and lr.nonce == 'n', 'login request')

check(C.errorText({ ok = false, errors = { 'acc.name_taken', 'acc.name_taken', 'Too long.' } }) == 'acc.name_taken\nToo long.', 'errors listed once')
check(C.errorText({ ok = false, message = 'Your session ended.' }) == 'Your session ended.', 'message')
check(C.errorText(nil, 'HTTP error 503') == 'The website could not be reached (HTTP error 503).', 'transport error')
check(C.errorText(nil, nil) == 'The website gave no answer.', 'no answer')

check(C.apiUrl('https://www.example.org/chaos_client_api.php') ~= nil, 'https')
check(C.apiUrl('http://127.0.0.1:8095/chaos_client_api.php') ~= nil and C.apiUrl('http://localhost/chaos_client_api.php') ~= nil, 'local test http')
check(C.apiUrl('http://www.example.org/chaos_client_api.php') == nil, 'plain http to another host refused')
check(C.apiUrl('') == nil and C.apiUrl(nil) == nil and C.apiUrl('ftp://x/') == nil, 'unset or other schemes')

if fails > 0 then
  print('charselect_core_test: ' .. fails .. ' FAILED')
  os.exit(1)
end
print('charselect_core_test: OK')
