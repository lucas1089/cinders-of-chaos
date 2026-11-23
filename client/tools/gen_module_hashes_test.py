#!/usr/bin/env python3
"""Tests of gen_module_hashes.py (O722): the digest rule, the list file the server reads, --check, and the one fixture shared with the
client's integrity.lua (the Lua side is run with lua5.3 or luajit when one is installed: the same folders must give the same digests).
Run: python3 -I client/tools/gen_module_hashes_test.py"""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_module_hashes as G  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


def put(root, rel, data):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'wb') as f:
        f.write(data)


tmp = tempfile.mkdtemp()
try:
    put(tmp, 'modules/game_b/b2.lua', b'two\n')
    put(tmp, 'modules/game_b/b1.lua', b'one\n')
    put(tmp, 'modules/game_b/ui/main.otui', b'MainWindow\n')
    put(tmp, 'modules/game_b/icon.png', b'\x89PNG')
    put(tmp, 'modules/game_a/a.LUA', b'upper\n')
    put(tmp, 'modules/game_a/a.lua2', b'not code\n')
    put(tmp, 'modules/game_a/a.lua', b'plain\n')
    put(tmp, 'mods/game_helper/helper.json', b'{}\n')
    put(tmp, 'modules/loose.lua', b'no folder\n')
    put(tmp, 'modules/empty_pictures/x.png', b'png')
    put(tmp, 'data/things/x.lua', b'not a module\n')
    d = G.digests(tmp)
    check(sorted(d) == ['game_a', 'game_b', 'mods/game_helper'], 'keys: %r' % sorted(d))

    def line(rel, data):
        return '%s:%s\n' % (rel, hashlib.sha256(data).hexdigest())

    want_b = ''.join(sorted([line('b1.lua', b'one\n'), line('b2.lua', b'two\n'), line('ui/main.otui', b'MainWindow\n')],
                            key=lambda s: s.encode()))
    check(d['game_b'] == hashlib.sha256(want_b.encode()).hexdigest(), 'game_b digest is the sha256 of the sorted lines')
    # lines sort as text: "a.LUA:" < "a.lua:" (upper case first), and a.lua2 is not counted at all
    want_a = ''.join(sorted([line('a.LUA', b'upper\n'), line('a.lua', b'plain\n')], key=lambda s: s.encode()))
    check(d['game_a'] == hashlib.sha256(want_a.encode()).hexdigest(), 'game_a digest: any case of the extension, a.lua2 is no code file')
    check(d['mods/game_helper'] == hashlib.sha256(line('helper.json', b'{}\n').encode()).hexdigest(), 'a mods module has mods/ in its key')
    # one byte changes the digest, a picture does not
    put(tmp, 'modules/game_b/icon.png', b'other picture')
    check(G.digests(tmp)['game_b'] == d['game_b'], 'a picture does not change the digest')
    put(tmp, 'modules/game_b/b1.lua', b'one!\n')
    check(G.digests(tmp)['game_b'] != d['game_b'], 'a changed file changes the digest')
    put(tmp, 'modules/game_b/b1.lua', b'one\n')
    put(tmp, 'modules/game_extra/bot.lua', b'-- a bot\n')
    check('game_extra' in G.digests(tmp), 'an extra module shows')
    shutil.rmtree(os.path.join(tmp, 'modules', 'game_extra'))

    # the list file
    out = os.path.join(tmp, 'list.lua')
    put(tmp, 'chaos_build.txt', b'build 77\n')
    check(G.main([tmp, '--out', out]) == 0, 'the list is written')
    text = open(out, encoding='utf-8').read()
    check('build = 77,' in text and '["game_a"] = "' in text and '["mods/game_helper"] = "' in text, 'the list has the build and the keys')
    check(G.main([tmp, '--out', out, '--check']) == 0, '--check passes on a fresh list')
    put(tmp, 'modules/game_b/b2.lua', b'two changed\n')
    check(G.main([tmp, '--out', out, '--check']) == 1, '--check fails on an old list')
    put(tmp, 'modules/game_b/b2.lua', b'two\n')
    check(G.main([tmp, '--out', out, '--build', '9']) == 0 and 'build = 9,' in open(out).read(), '--build overrides chaos_build.txt')
    check(G.main([os.path.join(tmp, 'nothere')]) == 2, 'a missing folder is refused')
    empty = tempfile.mkdtemp()
    try:
        check(G.main([empty, '--out', os.path.join(empty, 'x.lua')]) == 1, 'a tree without modules writes nothing')
    finally:
        shutil.rmtree(empty)
    # the server reads it with dofile: it is valid Lua with the two fields
    for interp in ('luajit', 'lua5.3', 'lua'):
        exe = shutil.which(interp)
        if exe:
            chk = os.path.join(tmp, 'chk.lua')
            with open(chk, 'w') as f:
                f.write('local t = dofile(arg[1])\nassert(type(t.build) == "number" and type(t.modules) == "table" and t.modules.game_a)\nio.write("ok")\n')
            r = subprocess.run([exe, chk, out], capture_output=True, text=True)
            check(r.stdout == 'ok', interp + ' reads the list: ' + r.stderr)

    # one fixture for both sides: integrity.lua with a stand-in hash (the hex of the text) over the same folders
    lua = shutil.which('lua5.3') or shutil.which('luajit') or shutil.which('lua')
    if lua:
        paths = []
        hashes = {}
        for root in ('modules', 'mods'):
            for d_, dirs, files in os.walk(os.path.join(tmp, root)):
                for n in files:
                    full = os.path.join(d_, n)
                    v = '/' + os.path.relpath(full, tmp).replace(os.sep, '/')
                    paths.append(v)
                    hashes[v] = G.file_sha256(full)
        script = ['dofile(arg[1])', 'local files, hashes = {}, {}']
        for v in sorted(paths):
            script.append('files[#files + 1] = %r' % v)
            script.append('hashes[%r] = %r' % (v, hashes[v]))
        script += ['local function hex(t) return (t:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end',
                   'local d = Integrity.digests(files, function(p) return hashes[p] end, hex)',
                   'local keys = {}', 'for k in pairs(d) do keys[#keys + 1] = k end', 'table.sort(keys)',
                   'for _, k in ipairs(keys) do io.write(k, " ", d[k], "\\n") end']
        sf = os.path.join(tmp, 'fixture.lua')
        with open(sf, 'w') as f:
            f.write('\n'.join(s.replace("'", '"') if s.startswith(('files[', 'hashes[')) else s for s in script) + '\n')
        r = subprocess.run([lua, sf, os.path.join(HERE, '..', 'overlay', 'modules', 'game_chaosguard', 'integrity.lua')], capture_output=True, text=True)
        py = G.digests(tmp, sha=lambda t: t.encode('utf-8').hex())
        got = dict(l.split(' ', 1) for l in r.stdout.splitlines() if ' ' in l)
        check(r.returncode == 0 and got == py, 'Lua and Python agree on the digests: %r vs %r %s' % (got, py, r.stderr))
finally:
    shutil.rmtree(tmp, ignore_errors=True)

if fails:
    print('%d failed' % fails)
    sys.exit(1)
print('gen_module_hashes tests: ok')
