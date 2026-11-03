#!/usr/bin/env python3
"""Tests of editor_release.py on synthetic files: python3 -I tools/windows/editor_release_test.py"""
import hashlib
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import editor_release as er  # noqa: E402

failures = 0


def check(cond, what):
    global failures
    if not cond:
        failures += 1
        print('FAIL', what)


def write(path, data):
    with open(path, 'wb') as f:
        f.write(data)


with tempfile.TemporaryDirectory() as tmp:
    # source: the entry used for editing the game map, not another one with a GitHub link
    credits = os.path.join(tmp, 'CREDITS.md')
    write(credits, b'# Credits\n\n## Tools\n\n- **Some Tool**\n  - Source: https://github.com/other/tool\n'
          b'  - Used for: drawing\n- **Example Map Editor**\n  - Author: someone\n'
          b'  - Source: https://github.com/acme/ExampleMapEditor\n'
          b'  - Used for: editing the game map (shipped in the Windows package)\n\n<!-- credits:end -->\n')
    check(er.source(credits) == 'acme/ExampleMapEditor', 'source: %s' % er.source(credits))
    write(credits, b'- **Some Tool**\n  - Source: https://github.com/other/tool\n  - Used for: drawing\n')
    check(er.source(credits) is None, 'no map editor entry')
    # the real file names one
    check(er.source() is not None and '/' in er.source(), 'docs/CREDITS.md names the map editor\'s source')

    # verify
    d = os.path.join(tmp, 'dl')
    os.makedirs(d)
    win, src = b'windows zip bytes', b'source zip bytes'
    write(os.path.join(d, 'Ed-windows-x64.zip'), win)
    write(os.path.join(d, 'Ed-source.zip'), src)
    hw, hs = hashlib.sha256(win).hexdigest(), hashlib.sha256(src).hexdigest()
    write(os.path.join(d, 'SHA256SUMS.txt'), ('%s  Ed-windows-x64.zip\n%s  Ed-source.zip\n' % (hw, hs)).encode())
    out = er.verify(d)
    check(out['windows'] == 'Ed-windows-x64.zip' and out['source'] == 'Ed-source.zip', 'the two zips')
    check(out['windows_sha256'] == hw and out['version'] == 'unknown', 'no manifest: version unknown')
    write(os.path.join(d, 'update-manifest.json'), json.dumps({'version': '1.4.2', 'sha256': hw.upper()}).encode())
    check(er.verify(d)['version'] == '1.4.2', 'the manifest of this zip gives the version')
    write(os.path.join(d, 'update-manifest.json'), json.dumps({'version': '1.4.3', 'sha256': hs}).encode())
    check(er.verify(d)['version'] == 'unknown', 'a manifest of another zip (rolling release) is not trusted')
    write(os.path.join(d, 'update-manifest.json'), b'{broken')
    check(er.verify(d)['version'] == 'unknown', 'a broken manifest')
    write(os.path.join(d, 'Ed-source.zip'), b'changed while uploading')
    try:
        er.verify(d)
        check(False, 'a mismatch fails')
    except er.VerifyError as e:
        check('Ed-source.zip' in str(e), 'the mismatch names the file: %s' % e)
    write(os.path.join(d, 'Ed-source.zip'), src)
    os.remove(os.path.join(d, 'Ed-windows-x64.zip'))
    try:
        er.verify(d)
        check(False, 'a missing zip fails')
    except er.VerifyError:
        pass
    check(er.main(['verify', d]) == 1, 'exit 1 on a missing zip')

    # settings key: both names stored as UTF-16 in the program
    exe = os.path.join(tmp, 'app.exe')
    write(exe, b'MZ..' + 'Acme'.encode('utf-16-le') + b'\0\0' + 'ExampleMapEditor'.encode('utf-16-le'))
    check(er.settings_key(exe, 'acme/ExampleMapEditor') == 'Software\\Acme\\ExampleMapEditor', 'settings key')
    write(exe, b'MZ.. Acme ExampleMapEditor')
    check(er.settings_key(exe, 'acme/ExampleMapEditor') is None, 'names not in UTF-16: no key')

print('editor_release: %s' % ('ok' if not failures else '%d failed' % failures))
sys.exit(1 if failures else 0)
