#!/usr/bin/env python3
"""Guard for client base patch 0214: the default ambient light 60 % (owner 2026-11-26, "5 sobe 60%"; client/BASE.md "0214").

Checks on the patch text:
  * it is the only patch numbered 0214 and touches exactly dataset.lua and settings.lua of mods/client_settings,
  * dataset.lua: the `ambientLight` default goes from 40 to 60 and nothing else changes there,
  * settings.lua: migrateAmbientLightDefault is defined once and called once, right after the base migrateHdSpriteDefaultOff,
  * each hunk has as many leading as trailing context lines,
then runs the migration function cut from the patch in LuaJIT (or Lua 5.3) against a fake g_settings that behaves like the
engine's (setDefault writes only a missing key): a new install keeps 60, an old install's saved 40 becomes 60, a player's
own 25 or 80 stays, the migration runs once (a 40 chosen afterwards stays), and it marks itself done.
Run: python3 -I client/tools/ambient_light_patch_test.py (standard library; skips the Lua part when no Lua is found)."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'base-patches')
NAME = '0214-ambient-light-default-60.patch'
fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


files = sorted(f for f in os.listdir(PATCHES) if f.endswith('.patch'))
check([f for f in files if f.startswith('0214-')] == [NAME], 'one patch numbered 0214')
text = open(os.path.join(PATCHES, NAME), encoding='utf-8').read()
touched = re.findall(r'^\+\+\+ b/(\S+)', text, re.M)
check(touched == ['mods/client_settings/classes/dataset.lua', 'mods/client_settings/settings.lua'], 'files: %r' % touched)

parts = re.split(r'^--- a/', text, flags=re.M)[1:]
data_part = parts[0]
sett_part = parts[1]
removed = [l[1:] for l in data_part.splitlines() if l.startswith('-') and not l.startswith('---')]
added = [l[1:] for l in data_part.splitlines() if l.startswith('+') and not l.startswith('+++')]
check([l.strip() for l in removed] == ['value = 40,'], 'dataset.lua removes the old default only: %r' % removed)
check(len(added) == 1 and added[0].strip().startswith('value = 60,'), 'dataset.lua sets 60: %r' % added)
check('\tambientLight = {' in data_part, 'the change is in the ambientLight block')

check([l for l in sett_part.splitlines() if l.startswith('-') and not l.startswith('---')] == [], 'settings.lua only adds')
check(sett_part.count('local function migrateAmbientLightDefault()') == 1, 'one migration function')
check(re.search(r'^ +migrateHdSpriteDefaultOff\(\)\n\+ +migrateAmbientLightDefault\(\)$', sett_part, re.M) is not None,
      'called right after the base migrations')

for hunk in re.split(r'^@@ .*@@.*$', text, flags=re.M)[1:]:
    lines = [l for l in hunk.split('\n') if l != '' and not l.startswith('---') and not l.startswith('+++')]
    lines = [l for l in lines if l[:1] in (' ', '+', '-')]
    lead = 0
    while lead < len(lines) and lines[lead].startswith(' '):
        lead += 1
    trail = 0
    while trail < len(lines) and lines[-1 - trail].startswith(' '):
        trail += 1
    check(lead == trail, 'symmetric hunk context (%d / %d)' % (lead, trail))

# the migration, cut from the added lines of settings.lua
plus = [l[1:] for l in sett_part.splitlines() if l.startswith('+') and not l.startswith('+++')]
src = '\n'.join(plus)
start = src.index('local function migrateAmbientLightDefault()')
end = src.index('\nend', start) + 4
fn = src[start:end]

LUA = r'''
local store
g_settings = {
  setDefault = function(k, v) if store[k] == nil then store[k] = v end end,
  set = function(k, v) store[k] = v end,
  getBoolean = function(k) return store[k] == true end,
  getNumber = function(k) return tonumber(store[k]) or 0 end,
}
%s
local fails = 0
local function eq(a, b, what) if a ~= b then fails = fails + 1; print('FAIL ' .. what .. ': ' .. tostring(a)) end end
local function start(saved)
  store = saved
  g_settings.setDefault('ambientLight', 60) -- GameOptions:setupStart with the new dataset.lua
  migrateAmbientLightDefault()
end
start({}); eq(store.ambientLight, 60, 'a new install: 60'); eq(store.chaosAmbientLight60V1, true, 'marked done')
start({ambientLight = 40}); eq(store.ambientLight, 60, 'an old install at the old default: 60')
start({ambientLight = 25}); eq(store.ambientLight, 25, 'a player who chose 25 keeps it')
start({ambientLight = 80}); eq(store.ambientLight, 80, 'a player who chose 80 keeps it')
start({ambientLight = 40}); store.ambientLight = 40; migrateAmbientLightDefault()
eq(store.ambientLight, 40, 'once: a 40 chosen after the migration stays')
os.exit(fails == 0 and 0 or 1)
''' % fn

lua = shutil.which('luajit') or shutil.which('lua5.3')
if lua:
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, 'm.lua')
        with open(path, 'w') as fh:
            fh.write(LUA)
        r = subprocess.run([lua, path], capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout + r.stderr)
        check(r.returncode == 0, 'the migration in ' + os.path.basename(lua))
else:
    print('ambient_light_patch_test: no luajit or lua5.3, the Lua part skipped')

if fails:
    print('ambient_light_patch_test: %d failed' % fails)
    sys.exit(1)
print('ambient_light_patch_test: OK')
