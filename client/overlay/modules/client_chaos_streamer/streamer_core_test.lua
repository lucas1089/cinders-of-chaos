-- Run from the repo root: luajit client/overlay/modules/client_chaos_streamer/streamer_core_test.lua (also lua5.3)
-- Streamer and cinema mode rules (streamer_core.lua): options, private message masking, window title, list names, IP
-- masking, the Creature.setInfoHide mask and the cinema widget pick.
local here = (arg and arg[0] or ''):match('^(.*)/[^/]*$') or '.'
dofile(here .. '/streamer_core.lua')
local C = StreamerCore
local fails, n = 0, 0
local function eq(a, b, name)
  n = n + 1
  if a ~= b then fails = fails + 1; print('FAIL ' .. name .. ': got ' .. tostring(a) .. ', want ' .. tostring(b)) end
end
local function upper(s) return '<' .. s .. '>' end

-- ------------------------------------------------------------------ options
local o = C.normalize(nil)
eq(o.streamerMode, false, 'default off')
eq(o.cinemaHideOthers, false, 'cinema sub-option off')
o = C.normalize({ streamerMode = true, streamerHideSender = 'yes', cinemaHideOthers = true })
eq(o.streamerMode, true, 'saved on')
eq(o.streamerHideSender, false, 'not a boolean: default')
eq(o.cinemaHideOthers, true, 'sub-option saved')
eq(C.toggled({ streamerMode = true }, 'streamerMode'), false, 'toggle off')
eq(C.toggled({}, 'streamerMode'), true, 'toggle on')
eq(C.HOTKEY_STREAMER, 'Ctrl+Shift+S', 'streamer hotkey')
eq(C.HOTKEY_CINEMA, 'Ctrl+Shift+H', 'cinema hotkey')

-- ------------------------------------------------------------------ private messages
local modes = { Say = 1, PrivateFrom = 4, PrivateTo = 5, GamemasterPrivateFrom = 14 }
local on = { streamerMode = true }
local onHide = { streamerMode = true, streamerHideSender = true }
local name, text, masked = C.maskTalk(on, 'Ashkar', 4, 'my address is 12 Elm St', modes, upper)
eq(name, 'Ashkar', 'sender kept')
eq(text, '<(private message hidden: streamer mode)>', 'text hidden, translated')
eq(masked, true, 'masked flag')
name, text = C.maskTalk(onHide, 'Ashkar', 4, 'secret', modes, upper)
eq(name, '<[hidden]>', 'sender hidden with the sub-option')
eq(text, '<(private message hidden: streamer mode)>', 'text hidden with the sub-option')
name, text, masked = C.maskTalk(on, 'Ashkar', 1, 'hello all', modes, upper)
eq(text, 'hello all', 'local say stays')
eq(masked, false, 'say not masked')
name, text = C.maskTalk(on, 'Ashkar', 5, 'my own line', modes, upper)
eq(text, 'my own line', 'own sent private message stays')
name, text = C.maskTalk(on, 'GM Rook', 14, 'staff warning', modes, upper)
eq(text, 'staff warning', 'a gamemaster private message stays readable')
name, text = C.maskTalk({ streamerMode = false, streamerHideSender = true }, 'Ashkar', 4, 'secret', modes, upper)
eq(name .. '|' .. text, 'Ashkar|secret', 'mode off: nothing hidden')
eq(C.HIDDEN_SENDER:find('[%[%]]') ~= nil, true, 'hidden sender cannot be a character name')

-- ------------------------------------------------------------------ title, list
eq(C.title('Cinders of Chaos - Ashkar', 'Cinders of Chaos', on), 'Cinders of Chaos', 'title without the name')
eq(C.title('Cinders of Chaos - Ashkar', 'Cinders of Chaos', {}), 'Cinders of Chaos - Ashkar', 'title as asked when off')
eq(C.listName('Ashkar', true, on, upper), 'Ashkar', 'chosen character shown')
eq(C.listName('Velka', false, on, upper), '<Hidden character>', 'other characters masked')
eq(C.listName('Velka', false, {}, upper), 'Velka', 'list as is when off')

-- ------------------------------------------------------------------ IPs
eq(C.maskIps('Connecting to 192.168.0.12:7172 now', on), 'Connecting to ***.***.***.*** now', 'ip and port masked')
eq(C.maskIps('host 10.0.0.1 and 8.8.8.8', on), 'host ***.***.***.*** and ***.***.***.***', 'two ips')
eq(C.maskIps('version 1.2.3.400 build', on), 'version 1.2.3.400 build', 'not an address (part above 255)')
eq(C.maskIps('You see 3 gold coins.', on), 'You see 3 gold coins.', 'plain text untouched')
eq(C.maskIps('192.168.0.12', {}), '192.168.0.12', 'off: ip shown')
eq(C.maskIps(nil, on), nil, 'nil passes')

-- ------------------------------------------------------------------ info hide mask
eq(C.infoHideMask({ streamerMode = true, streamerHideOwnName = true }, false), 1, 'own name')
eq(C.infoHideMask({ streamerMode = false, streamerHideOwnName = true }, false), 0, 'own name only in streamer mode')
eq(C.infoHideMask({ cinemaHideOthers = true }, true), 2, 'others in cinema mode')
eq(C.infoHideMask({ cinemaHideOthers = true }, false), 0, 'others only in cinema mode')
eq(C.infoHideMask({ streamerMode = true, streamerHideOwnName = true, cinemaHideOthers = true }, true), 3, 'both')
eq(C.infoHideMask({ cinemaHideOthers = false }, true), 0, 'cinema without the sub-option')

-- ------------------------------------------------------------------ cinema pick
local map, root, chat, side, topbar, toast, hud, closed = {}, {}, {}, {}, {}, {}, {}, {}
local chain = {
  { widget = map, siblings = { { widget = map, visible = true }, { widget = chat, visible = true },
    { widget = side, visible = true }, { widget = closed, visible = false }, { widget = topbar, visible = true } } },
  { widget = root, siblings = { { widget = root, visible = true }, { widget = toast, visible = true } } },
}
local picked = C.cinemaPick(chain, { { widget = hud, visible = true } })
eq(#picked, 5, 'chat, side, top bar, toast, map hud')
local set = {}
for _, w in ipairs(picked) do set[w] = true end
eq(set[map], nil, 'map stays')
eq(set[root], nil, 'game root stays')
eq(set[closed], nil, 'a hidden window is not touched (stays hidden after)')
eq(set[hud], true, 'hud on the map hidden')
local hidden = { chat, side }
local added = C.addNew(hidden, { side, toast })
eq(#added, 1, 'one new widget')
eq(added[1], toast, 'the new one')
eq(#hidden, 3, 'recorded for the restore')

print(string.format('%d checks, %d failures', n, fails))
if fails > 0 then os.exit(1) end
