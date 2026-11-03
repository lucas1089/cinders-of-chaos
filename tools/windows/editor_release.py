#!/usr/bin/env python3
"""The map editor the Windows package ships (O381; docs/CREDITS.md, the entry "Used for: editing the game map").

    python3 -I tools/windows/editor_release.py repo [CREDITS.md]
        prints the editor's GitHub owner/repo, read from its Source line in docs/CREDITS.md (the only file that may name
        it, tools/ci/check_names.py); exit 1 when there is no such entry
    python3 -I tools/windows/editor_release.py verify DIR
        DIR holds the release download: SHA256SUMS.txt, the Windows zip (*-windows-x64.zip), the source zip
        (*-source.zip) and maybe update-manifest.json. Checks both zips against SHA256SUMS.txt (exit 1 on a missing
        file or a mismatch) and prints key=value lines for the workflow: windows=, source=, windows_sha256=,
        source_sha256=, version= (from update-manifest.json when its sha256 is the Windows zip's, else "unknown")
    python3 -I tools/windows/editor_release.py settings-key EXE OWNER/REPO
        the editor keeps its settings in HKCU\\Software\\<organisation>\\<application>; the release names them after the
        repository (organisation = owner with a capital, application = repo). Prints the key when both names are in
        the program (UTF-16, as its strings are stored), else exit 3: open-map-editor.bat then presets nothing and
        README.txt has the clicks.
Used by .github/workflows/windows-package.yml; tests: tools/windows/editor_release_test.py.
"""
import hashlib, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
CREDITS = os.path.join(REPO, 'docs', 'CREDITS.md')


def source(credits=CREDITS):
    """owner/repo of the credits entry used for editing the game map"""
    with open(credits, encoding='utf-8') as f:
        text = f.read()
    for entry in re.split(r'\n(?=- \*\*)', text):
        if re.search(r'^\s+- Used for: editing the game map', entry, re.M):
            m = re.search(r'^\s+- Source: https://github\.com/([\w.-]+)/([\w.-]+?)(?:\.git)?/?\s*$', entry, re.M)
            if m:
                return m.group(1) + '/' + m.group(2)
    return None


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


class VerifyError(Exception):
    pass


def verify(d):
    sums = os.path.join(d, 'SHA256SUMS.txt')
    if not os.path.isfile(sums):
        raise VerifyError('no SHA256SUMS.txt')
    want = {}
    with open(sums, encoding='utf-8') as f:
        for line in f:
            m = re.match(r'^([0-9a-fA-F]{64})\s+\*?(\S+)\s*$', line)
            if m:
                want[m.group(2)] = m.group(1).lower()
    out = {}
    for kind, suffix in (('windows', '-windows-x64.zip'), ('source', '-source.zip')):
        names = [n for n in want if n.endswith(suffix)]
        if len(names) != 1:
            raise VerifyError('SHA256SUMS.txt names %d file(s) ending in %s' % (len(names), suffix))
        path = os.path.join(d, names[0])
        if not os.path.isfile(path):
            raise VerifyError('%s is not in the download' % names[0])
        got = sha256(path)
        if got != want[names[0]]:
            raise VerifyError('%s: sha256 %s, SHA256SUMS.txt says %s' % (names[0], got, want[names[0]]))
        out[kind] = names[0]
        out[kind + '_sha256'] = got
    out['version'] = 'unknown'
    man = os.path.join(d, 'update-manifest.json')
    if os.path.isfile(man):
        try:
            with open(man, encoding='utf-8') as f:
                m = json.load(f)
            v = str(m.get('version', ''))
            if str(m.get('sha256', '')).lower() == out['windows_sha256'] and re.match(r'^[0-9][0-9A-Za-z.+-]{0,40}$', v):
                out['version'] = v
        except (ValueError, OSError):
            pass
    return out


def settings_key(exe, slug):
    owner, repo = slug.split('/', 1)
    org = owner[:1].upper() + owner[1:]
    with open(exe, 'rb') as f:
        data = f.read()
    for name in (org, repo):
        if name.encode('utf-16-le') not in data:
            return None
    return 'Software\\%s\\%s' % (org, repo)


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    cmd, args = argv[0], argv[1:]
    if cmd == 'repo':
        s = source(args[0] if args else CREDITS)
        if not s:
            print('docs/CREDITS.md: no entry "Used for: editing the game map" with a GitHub Source line', file=sys.stderr)
            return 1
        print(s)
        return 0
    if cmd == 'verify' and len(args) == 1:
        try:
            out = verify(args[0])
        except VerifyError as e:
            print('map editor download: %s' % e, file=sys.stderr)
            return 1
        for k in ('windows', 'source', 'windows_sha256', 'source_sha256', 'version'):
            print('%s=%s' % (k, out[k]))
        return 0
    if cmd == 'settings-key' and len(args) == 2:
        key = settings_key(args[0], args[1])
        if not key:
            print('the program does not hold the names of %s: no settings preset' % args[1], file=sys.stderr)
            return 3
        print(key)
        return 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
