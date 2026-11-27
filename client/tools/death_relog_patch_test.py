#!/usr/bin/env python3
"""Guard for client base patch 0217: Ok on the death window logs in again after the connection timed out
(client/BASE.md "0217"; seen in a client 2026-11-27, V38: a dead player's connection hit the client's 30 s read
timeout behind the death window, "Connection timed out (ERROR 110)", and Ok did nothing).

Checks on the patch text:
  * it is the only patch numbered 0217 and touches exactly game_playerdeath/playerdeath.lua and
    client_entergame/characterlist.lua,
  * the death module hunk spans the whole file (so the old and the new file are rebuilt from it), the line counts of
    every hunk match its header and the character list hunk has symmetric context,
  * onGameConnectionError asks game_playerdeath.holdsConnectionError() before it builds an error box,
then runs the old and the new death module in LuaJIT and Lua 5.3 on a fake engine, and the patched start of
onGameConnectionError:
  * Ok within a few seconds (still online): one CharacterList.doLogin(), as before,
  * the game ends while the window is open (the timeout): the new file keeps the window and gives it the input lock
    back, no error box; Ok then calls CharacterList.doLogin() while offline; the old file loses the window,
  * Cancel after the timeout: no login, the character list shows again,
  * a game start (auto reconnect) closes the window; a game end without a death opens nothing.
Run: python3 -I client/tools/death_relog_patch_test.py (standard library; skips the Lua part when no Lua is found)."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'base-patches')
NAME = '0217-death-window-relog-offline.patch'
DEATH = 'modules/game_playerdeath/playerdeath.lua'
CHARS = 'modules/client_entergame/characterlist.lua'
fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


files = sorted(f for f in os.listdir(PATCHES) if f.endswith('.patch'))
check([f for f in files if f.startswith('0217-')] == [NAME], 'one patch numbered 0217')
text = open(os.path.join(PATCHES, NAME), encoding='utf-8').read()
touched = re.findall(r'^\+\+\+ b/(\S+)', text, re.M)
check(touched == [DEATH, CHARS], 'files: %r' % touched)

# split per file, then per hunk
per_file = {}
for part in re.split(r'^--- a/', text, flags=re.M)[1:]:
    name = part.split('\n', 1)[0].strip()
    per_file[name] = part
heads = {}
hunks = {}
for name, part in per_file.items():
    heads[name] = re.findall(r'^@@ -(\d+),(\d+) \+(\d+),(\d+) @@', part, re.M)
    body = re.split(r'^@@ .*@@.*$', part, flags=re.M)[1:]
    hunks[name] = [[l for l in h.split('\n') if l[:1] in (' ', '+', '-') and not l.startswith(('---', '+++'))]
                   for h in body]
for name in (DEATH, CHARS):
    check(len(hunks.get(name, [])) == 1, 'one hunk in %s' % name)
    for head, lines in zip(heads.get(name, []), hunks.get(name, [])):
        old = sum(1 for l in lines if l[:1] in (' ', '-'))
        new = sum(1 for l in lines if l[:1] in (' ', '+'))
        check((old, new) == (int(head[1]), int(head[3])), 'hunk line counts of %s: %r against %r' % (name, (old, new), head))

death = hunks.get(DEATH, [[]])[0]
check(heads.get(DEATH, [('0',)])[0][0] == '1', 'the death module hunk starts at line 1')
old_file = '\n'.join(l[1:] for l in death if l[:1] in (' ', '-')) + '\n'
new_file = '\n'.join(l[1:] for l in death if l[:1] in (' ', '+')) + '\n'
check(old_file.rstrip().endswith('end') and 'okButton.onClick = okFunc' in old_file, 'the hunk holds the whole old file')
check('onGameEnd = reset' in old_file and 'onGameEnd = reset' not in new_file, 'game end no longer resets the window')
check('onGameStart = reset' in new_file, 'a game start closes the window')

chars = hunks.get(CHARS, [[]])[0]
lead = 0
while lead < len(chars) and chars[lead].startswith(' '):
    lead += 1
trail = 0
while trail < len(chars) and chars[-1 - trail].startswith(' '):
    trail += 1
check(lead == trail == 3, 'symmetric hunk context in characterlist.lua (%d / %d)' % (lead, trail))
check(not any(l.startswith('-') for l in chars), 'characterlist.lua: only additions')
chars_new = [l[1:] for l in chars if l[:1] in (' ', '+')]
check(any('handleCastLoginError(message, code) then' in l for l in chars_new), 'the hunk follows the cast check')
check(any('death.holdsConnectionError()' in l for l in chars_new), 'the error path asks the death module')

LUA = r'''
local SRC = ...
local fails = 0
local function eq(a, b, what) if a ~= b then fails = fails + 1; print('FAIL ' .. what .. ': ' .. tostring(a)) end end

local function engine()
  local E = { online = true, logging = false, lock = nil, handlers = {}, events = {}, logins = 0, logouts = 0,
              shows = 0, errorBoxes = 0, windows = 0 }
  local function widget(id)
    local w = { id = id, children = {}, destroyed = false, visible = true, baseWidth = 369, baseHeight = 217 }
    function w:getChildById(cid)
      if not self.children[cid] then
        local c = widget(cid); c.parent = self; self.children[cid] = c
      end
      return self.children[cid]
    end
    function w:getParent() return self.parent end
    function w:destroy() self.destroyed = true; if self.id == 'deathWindow' then E.windows = E.windows - 1 end end
    function w:focus() end
    function w:raise() end
    function w:show() self.visible = true end
    function w:setHeight() end
    function w:setWidth() end
    function w:setColoredText() end
    function w:isVisible() return false end
    function w:recursiveGetChildById(cid) return widget(cid) end
    return w
  end
  local env = setmetatable({}, { __index = _G })
  env.rootWidget = widget('root')
  env.DeathType = { Regular = 0 }
  env.tr = function(s) return s end
  env.setStringColor = function(t, s) t[#t + 1] = s end
  env.m_interface = { getRootPanel = function() return widget('rootPanel') end }
  env.modules = { game_textmessage = { displayGameMessage = function() end } }
  env.g_ui = { importStyle = function() end,
               createWidget = function(style, parent) E.windows = E.windows + 1; return widget('deathWindow') end }
  env.g_client = { setInputLockWidget = function(w) E.lock = w end }
  env.g_game = { isOnline = function() return E.online end, isLogging = function() return E.logging end,
                 safeLogout = function() E.logouts = E.logouts + 1 end }
  env.connect = function(_, t) for k, f in pairs(t) do E.handlers[k] = f end end
  env.disconnect = function(_, t) for k in pairs(t) do E.handlers[k] = nil end end
  env.addEvent = function(f) E.events[#E.events + 1] = f end
  env.CharacterList = {
    doLogin = function() E.logins = E.logins + 1 end,
    showAgain = function() E.shows = E.shows + 1; E.lock = 'characters' end,
    destroyLoadBox = function() end,
  }
  -- the patched start of client_entergame onGameConnectionError, then the error box the base builds
  env.removeAutoReconnectEvent = function() end
  local loadFn = loadstring or load
  local chunk
  if setfenv then
    chunk = assert(loadFn(SRC.death))
    setfenv(chunk, env)
  else
    chunk = assert(load(SRC.death, 'playerdeath', 't', env))
  end
  chunk()
  env.modules.game_playerdeath = env
  local errSrc = 'return function(message, code)\n' .. SRC.chars .. '\n  ERRORBOX = (ERRORBOX or 0) + 1\nend'
  local errChunk
  if setfenv then errChunk = assert(loadFn(errSrc)); setfenv(errChunk, env)
  else errChunk = assert(load(errSrc, 'chars', 't', env)) end
  E.connectionError = errChunk()
  function E.flush() local ev = E.events; E.events = {}; for _, f in ipairs(ev) do f() end end
  -- the engine order of a lost connection: onConnectionError while online, then the game end
  function E.timeout()
    E.connectionError('Connection timed out', 110)
    E.online = false
    if E.handlers.onGameEnd then E.handlers.onGameEnd() end
    E.lock = 'characters' -- CharacterList.showAgain in the character list's own onGameEnd
    E.flush()
  end
  E.env = env
  env.init()
  return E
end

local function window(E) return E.env.deathWindow end
local function ok(E) local w = window(E); w:getChildById('buttonOk').onClick() end
local function cancel(E) local w = window(E); w:getChildById('buttonCancel').onClick() end

-- Ok within a few seconds, still online
local E = engine()
E.handlers.onDeath(0, 100)
eq(E.windows, 1, 'death opens the window')
eq(E.lock, window(E), 'the window holds the input lock')
ok(E)
eq(E.logins, 1, 'Ok online logs in again')
eq(window(E), nil, 'Ok closes the window')

-- the connection times out behind the window, then Ok
E = engine()
E.handlers.onDeath(0, 100)
local w = window(E)
E.timeout()
if SRC.new then
  eq(E.env.ERRORBOX, nil, 'no error box for the expected timeout')
  eq(window(E), w, 'the window stays open after the game end')
  eq(w.destroyed, false, 'the window is not destroyed')
  eq(E.lock, w, 'the window takes the input lock back')
  ok(E)
  eq(E.logins, 1, 'Ok offline logs in again')
  eq(window(E), nil, 'Ok closes the window')
  eq(E.env.holdsConnectionError(), false, 'a later connection error shows its box again')
  E.connectionError('Connection refused', 16654)
  eq(E.env.ERRORBOX, 1, 'the error box after the window is gone')
else
  eq(E.env.ERRORBOX, 1, 'old file: the error box shows')
  eq(window(E), nil, 'old file: the window is gone, Ok cannot be pressed')
  eq(E.logins, 0, 'old file: no login')
end

if SRC.new then
  -- Cancel after the timeout
  E = engine()
  E.handlers.onDeath(0, 100)
  E.timeout()
  cancel(E)
  eq(E.logins, 0, 'Cancel offline: no login')
  eq(E.logouts, 0, 'Cancel offline: no logout')
  eq(E.shows, 1, 'Cancel offline: the character list shows again')
  eq(E.lock, 'characters', 'the list holds the input lock')

  -- Cancel online, as before
  E = engine()
  E.handlers.onDeath(0, 100)
  cancel(E)
  eq(E.logouts, 1, 'Cancel online logs out')
  eq(E.shows, 0, 'Cancel online leaves the list to the game end')

  -- a login already running when Ok is pressed
  E = engine()
  E.handlers.onDeath(0, 100)
  E.timeout()
  E.logging = true
  ok(E)
  eq(E.logins, 0, 'no second login while one runs')

  -- auto reconnect: the game starts again behind the window
  E = engine()
  E.handlers.onDeath(0, 100)
  E.timeout()
  E.online = true
  E.handlers.onGameStart()
  eq(window(E), nil, 'a game start closes the window')
  eq(E.lock, nil, 'and frees the input lock')

  -- a game end without a death
  E = engine()
  E.handlers.onGameEnd()
  E.flush()
  eq(window(E), nil, 'no window without a death')
  eq(E.windows, 0, 'nothing opened')
end
os.exit(fails == 0 and 0 or 1)
'''


def lua_quote(s):
    eq = '=' * 8
    return '[' + eq + '[\n' + s + ']' + eq + ']'


chars_start = '\n'.join(chars_new[:-3])  # up to (not with) the base's own error handling
chars_body = chars_start.split('\n')
# the hunk starts inside the function: the cast check's tail is dropped, only our lines are run
ours = []
take = False
for l in chars_body:
    if 'Chaos 0217' in l:
        take = True
    if take:
        ours.append(l)

luas = [x for x in ('luajit', 'lua5.3') if shutil.which(x)]
if not luas:
    print('SKIP Lua part: no luajit or lua5.3')
with tempfile.TemporaryDirectory() as tmp:
    for mode, src in (('new', new_file), ('old', old_file)):
        script = os.path.join(tmp, 'run_%s.lua' % mode)
        with open(script, 'w', encoding='utf-8') as f:
            f.write('local SRC = { death = %s, chars = %s, new = %s }\n' % (
                lua_quote(src), lua_quote('\n'.join(ours)), 'true' if mode == 'new' else 'false'))
            f.write('local run = assert((loadstring or load)(%s))\nrun(SRC)\n' % lua_quote(LUA))
        for lua in luas:
            r = subprocess.run([lua, script], capture_output=True, text=True)
            out = (r.stdout + r.stderr).strip()
            check(r.returncode == 0, '%s %s file: %s' % (lua, mode, out))

if fails:
    print('%d failure(s)' % fails)
    sys.exit(1)
print('death_relog_patch_test: ok')
