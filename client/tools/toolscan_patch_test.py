#!/usr/bin/env python3
"""Guard for client base patch 0207: the known-tool scan of the bot detection (O722).

The patch adds src/client/chaostoolscan.h (pure parts tested by client/tools/chaostoolscan_test.cpp, a Windows part never built here) and
binds g_game.chaosScanTools in luafunctions_client.cpp. This test reads the patch text and checks that
  * it is the only patch numbered 0207, touches exactly luafunctions_client.cpp and adds chaostoolscan.h, and only adds lines,
  * the Lua function takes one string and returns the header's scan() result, and the header answers with codes only: no function returns a
    process name or a window title, nothing is logged, written to a file or sent, the Windows API calls are inside #ifdef _WIN32, and every
    other platform's scan() returns "",
  * the memory-handle check of the plan is not there (the patch says why),
  * each hunk has as many leading as trailing context lines (patch(1) takes an asymmetric hunk as anchored at an end of the file),
and applies the patch to a tree rebuilt from its own context with patch -p1 --fuzz=0. With BASE_TREE=<client source root with 0001-0206
applied> it also runs patch --dry-run on the real tree (client/BASE.md "0207").
Run: python3 -I client/tools/toolscan_patch_test.py (standard library only)."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'base-patches')
NAME = '0207-known-tool-scan.patch'
fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


files = sorted(f for f in os.listdir(PATCHES) if f.endswith('.patch'))
check([f for f in files if f.startswith('0207-')] == [NAME], 'one patch numbered 0207')
text = open(os.path.join(PATCHES, NAME), encoding='utf-8').read()
body = text[text.index('diff -ruN'):]
touched = re.findall(r'^diff -ruN a/(\S+) b/\S+', body, re.M)
check(touched == ['src/client/luafunctions_client.cpp', 'src/client/chaostoolscan.h'], 'the files the patch touches: %r' % touched)
added = [l[1:] for l in body.splitlines() if l.startswith('+') and not l.startswith('+++')]
removed = [l[1:] for l in body.splitlines() if l.startswith('-') and not l.startswith('---')]
check(removed == [], 'the patch removes no line of the client (it only adds)')
for f in files:
    if f > NAME:
        gone = [l for l in open(os.path.join(PATCHES, f), encoding='utf-8').read().splitlines() if l.startswith('-') and not l.startswith('---')]
        check(not any('toolscan' in l.lower() for l in gone), 'no later patch removes what 0207 adds: ' + f)

lua_part = body[:body.index('diff -ruN a/src/client/chaostoolscan.h')]
check('#include "chaostoolscan.h"' in lua_part, 'luafunctions_client.cpp includes the header')
check('g_lua.bindClassStaticFunction("g_game", "chaosScanTools", std::function<std::string(const std::string&)>'
      '([](const std::string& spec) { return chaos::toolscan::scan(spec); }));' in lua_part, 'g_game.chaosScanTools takes the list and returns scan(spec)')
check(lua_part.count('chaosScanTools') == 1, 'one Lua function')

header = '\n'.join(l for l in added if True)
hdr = body[body.index('diff -ruN a/src/client/chaostoolscan.h'):]
hlines = [l[1:] for l in hdr.splitlines() if l.startswith('+') and not l.startswith('+++')]
code = '\n'.join(l.split('//')[0] for l in hlines)
check(not re.search(r'\b(printf|fprintf|std::cout|std::cerr|g_logger|ofstream|fopen|send|socket|WriteFile|OutputDebugString)\b', code),
      'the header logs, writes and sends nothing')
check('#ifdef _WIN32' in code and '#else' in code, 'the Windows part is separate from the rest')
win = code[code.index('#ifdef _WIN32', code.index('inline std::string answerFor')):code.index('#else', code.index('inline std::string answerFor'))]
for api in ('CreateToolhelp32Snapshot', 'Process32FirstW', 'EnumWindows', 'GetWindowTextW'):
    check(api in win, api + ' is inside the Windows branch')
check('#include <windows.h>' in code and code.index('#include <windows.h>') < code.index('namespace chaos'), 'windows.h is included under #ifdef _WIN32 only')
pre_win = code[:code.index('#ifdef _WIN32', code.index('inline std::string answerFor'))]
for api in ('CreateToolhelp32Snapshot', 'EnumWindows', 'GetWindowText', 'OpenProcess', 'ReadProcessMemory', 'NtQuerySystemInformation'):
    check(api not in pre_win.replace('#include <tlhelp32.h>', ''), api + ' is not used outside the Windows branch')
check('OpenProcess' not in code and 'DuplicateHandle' not in code and 'NtQuery' not in code and 'ReadProcessMemory' not in code,
      'no process is opened and no handle table is read (the memory-handle check is not done)')
check(re.search(r'#else\s*inline std::string scan\(const std::string&\)\s*\{\s*return std::string\(\);\s*\}\s*#endif', code) is not None,
      'every other platform answers an empty string')
check('szExeFile' in win and 'th32ProcessID' not in code, 'only the image name of a process is read, never its id')
check('MAX_CODES = 8' in code and 'MAX_ENTRIES = 200' in code and 'MAX_NAMES = 8192' in code, 'the caps are there')
check('answerFor' in code and 'std::vector<std::string> codes' in code, 'the answer is built from codes')
check('not done on purpose' in text.lower() and 'memory handles' in text.lower(), 'the header comment says the memory-handle check was skipped')
check(re.search(r'^@@ -0,0 \+1,%d @@' % len(hlines), hdr, re.M) is not None, 'the new file hunk count is right')

for blk in re.split(r'(?m)^(?=diff -ruN )', body):
    if '--- /dev/null' in blk:
        continue
    for h in re.split(r'(?m)^(?=@@ )', blk)[1:]:
        kinds = [l[:1] for l in h.splitlines()[1:]]
        lead = 0
        while lead < len(kinds) and kinds[lead] == ' ':
            lead += 1
        trail = 0
        while trail < len(kinds) and kinds[len(kinds) - 1 - trail] == ' ':
            trail += 1
        check(lead == trail and lead >= 2, 'hunk %r has %d leading and %d trailing context lines' % (h.splitlines()[0][:30], lead, trail))

patch = shutil.which('patch')
if patch:
    tmp = tempfile.mkdtemp()
    try:
        for blk in re.split(r'(?m)^(?=diff -ruN )', body):
            m = re.match(r'diff -ruN a/(\S+) b/\S+', blk)
            if not m or '--- /dev/null' in blk:
                continue
            path = os.path.join(tmp, m.group(1))
            os.makedirs(os.path.dirname(path), exist_ok=True)
            out = []
            for n, h in enumerate(re.split(r'(?m)^(?=@@ )', blk)[1:], 1):
                out.append('// filler before hunk %d' % n)
                out += [l[1:] for l in h.splitlines()[1:] if l[:1] in (' ', '-')]
                out.append('// filler after hunk %d' % n)
            with open(path, 'w', encoding='utf-8') as fh:
                fh.write('\n'.join(out) + '\n')
        r = subprocess.run([patch, '-p1', '--fuzz=0', '-i', os.path.join(PATCHES, NAME)], cwd=tmp, capture_output=True, text=True)
        check(r.returncode == 0, 'patch -p1 --fuzz=0 applies to a tree of its own context: ' + r.stdout + r.stderr)
        check(os.path.exists(os.path.join(tmp, 'src', 'client', 'chaostoolscan.h')), 'the header file is created')
        if r.returncode == 0:
            check('chaosScanTools' in open(os.path.join(tmp, 'src', 'client', 'luafunctions_client.cpp'), encoding='utf-8').read(), 'applied: the binding')
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
base = os.environ.get('BASE_TREE')
if base:
    r = subprocess.run(['patch', '-p1', '--fuzz=0', '--dry-run', '-i', os.path.join(PATCHES, NAME)], cwd=base, capture_output=True, text=True)
    check(r.returncode == 0, 'patch --dry-run on BASE_TREE: ' + r.stdout + r.stderr)

if fails:
    print('%d failed' % fails)
    sys.exit(1)
print('known tool scan patch tests: ok')
