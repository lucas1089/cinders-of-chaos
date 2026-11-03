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

    # our build (O387): BUILD_INFO.txt listed in SHA256SUMS.txt, the patched variant
    o = os.path.join(tmp, 'ours')
    os.makedirs(o)
    up, ours_commit = 'a' * 40, 'b' * 40
    write(os.path.join(o, 'mapeditor-bbbbbbb-windows-x64.zip'), win)
    write(os.path.join(o, 'mapeditor-bbbbbbb-source.zip'), src)

    def info(variant='patched', patches='0001-profile-map-pan.patch, 0002-light.patch, 0003-overlays.patch',
             upstream=up):
        text = ('﻿upstream: %s\nupstream_repo: acme/ExampleMapEditor\nvariant: %s\npatches: %s\n'
                'cinders of chaos commit: %s\nbuilt: 2026-11-03T10:00Z by run 1\n'
                % (upstream, variant, patches, ours_commit))
        write(os.path.join(o, 'BUILD_INFO.txt'), text.encode('utf-8'))
        hi = er.sha256(os.path.join(o, 'BUILD_INFO.txt'))
        write(os.path.join(o, 'SHA256SUMS.txt'), ('%s  mapeditor-bbbbbbb-windows-x64.zip\n'
                                                  '%s  mapeditor-bbbbbbb-source.zip\n'
                                                  '%s  BUILD_INFO.txt\n' % (hw, hs, hi)).encode())
    info()
    out = er.verify(o, ours=True)
    check(out['upstream'] == up and out['commit'] == ours_commit, 'our build: upstream and commit')
    check(out['patches'] == '0001..0003', 'patch range: %s' % out['patches'])
    check(out['upstream_repo'] == 'acme/ExampleMapEditor', 'upstream repo from BUILD_INFO.txt')
    check(out['version'] == 'our build: upstream aaaaaaa + patches 0001..0003', 'version: %s' % out['version'])
    check(er.verify(o)['version'] == 'unknown', 'without --ours BUILD_INFO.txt is not read')
    check(er.main(['verify', o, '--ours']) == 0, 'exit 0 on our build')
    check(er.main(['verify', o, '--bogus']) == 2, 'unknown option: usage')
    for bad, what in ((dict(variant='baseline'), 'the baseline build is never shipped'),
                      (dict(patches=''), 'no patches'),
                      (dict(upstream='abc'), 'a short upstream sha')):
        info(**bad)
        try:
            er.verify(o, ours=True)
            check(False, what)
        except er.VerifyError:
            pass
    info()
    with open(os.path.join(o, 'BUILD_INFO.txt'), 'ab') as f:
        f.write(b'tampered\n')
    try:
        er.verify(o, ours=True)
        check(False, 'a changed BUILD_INFO.txt fails')
    except er.VerifyError as e:
        check('BUILD_INFO.txt' in str(e), 'the mismatch names BUILD_INFO.txt')
    # an upstream release (no BUILD_INFO.txt in its sums) is not taken for ours
    try:
        er.verify(d, ours=True)
        check(False, 'the upstream download is not our build')
    except er.VerifyError:
        pass

    # patch ranges
    check(er.patch_range(['0001-a.patch']) == '0001', 'one patch')
    check(er.patch_range(['0001-a.patch', '0003-c.patch']) == '0001, 0003', 'a gap lists the numbers')
    check(er.patch_range([]) == 'none', 'no patches')

    # latest tag of our builds: newest published mapeditor-<hex>, drafts and other tags left out
    rels = [{'tagName': 'winpkg-90', 'createdAt': '2026-11-05T00:00:00Z', 'isDraft': False},
            {'tagName': 'mapeditor-1111111', 'createdAt': '2026-11-01T00:00:00Z', 'isDraft': False},
            {'tagName': 'mapeditor-2222222', 'createdAt': '2026-11-03T00:00:00Z', 'isDraft': False},
            {'tagName': 'mapeditor-3333333', 'createdAt': '2026-11-04T00:00:00Z', 'isDraft': True},
            {'tagName': 'mapeditor-latest', 'createdAt': '2026-11-06T00:00:00Z', 'isDraft': False}]
    check(er.latest_tag(rels) == 'mapeditor-2222222', 'latest tag: %s' % er.latest_tag(rels))
    check(er.latest_tag(rels[:1]) is None, 'no build of ours yet')
    lst = os.path.join(tmp, 'releases.json')
    write(lst, json.dumps(rels).encode())
    check(er.main(['latest-tag', lst]) == 0, 'latest-tag exit 0')
    write(lst, b'[]')
    check(er.main(['latest-tag', lst]) == 1, 'latest-tag exit 1 when there is none')

    # settings key: both names stored as UTF-16 in the program
    exe = os.path.join(tmp, 'app.exe')
    write(exe, b'MZ..' + 'Acme'.encode('utf-16-le') + b'\0\0' + 'ExampleMapEditor'.encode('utf-16-le'))
    check(er.settings_key(exe, 'acme/ExampleMapEditor') == 'Software\\Acme\\ExampleMapEditor', 'settings key')
    write(exe, b'MZ.. Acme ExampleMapEditor')
    check(er.settings_key(exe, 'acme/ExampleMapEditor') is None, 'names not in UTF-16: no key')

print('editor_release: %s' % ('ok' if not failures else '%d failed' % failures))
sys.exit(1 if failures else 0)
