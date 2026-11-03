#!/usr/bin/env python3
"""The map editor the Windows package ships (O381, O387; docs/CREDITS.md, the entry "Used for: editing the game map").
Our build (mapeditor-build.yml, releases mapeditor-<short sha> of this repository) or the upstream release.

    python3 -I tools/windows/editor_release.py repo [CREDITS.md]
        prints the editor's GitHub owner/repo, read from its Source line in docs/CREDITS.md (the only file that may name
        it, tools/ci/check_names.py); exit 1 when there is no such entry
    python3 -I tools/windows/editor_release.py verify DIR [--ours]
        DIR holds the release download: SHA256SUMS.txt, the Windows zip (*-windows-x64.zip), the source zip
        (*-source.zip) and maybe update-manifest.json. Checks both zips against SHA256SUMS.txt (exit 1 on a missing
        file or a mismatch) and prints key=value lines for the workflow: windows=, source=, windows_sha256=,
        source_sha256=, version= (from update-manifest.json when its sha256 is the Windows zip's, else "unknown").
        --ours (O387): DIR is a release of our build (mapeditor-build.yml, tag mapeditor-<short sha>): BUILD_INFO.txt
        must be in SHA256SUMS.txt and match too, name the patched variant, a full upstream sha and our patches. Adds
        upstream=, upstream_repo= (may be empty), patches= (0001..0006 or a list), commit=; version= says
        "our build: upstream <sha7> + patches <patches>", with the program version first when BUILD_INFO.txt has one
        ("our build 1.1.43.57: ...", O388)
    python3 -I tools/windows/editor_release.py latest-tag [FILE]
        FILE (default stdin) is the JSON of `gh release list --json tagName,createdAt,isDraft`. Prints the newest
        published mapeditor-<hex> tag; exit 1 when there is none (no build of ours yet)
    python3 -I tools/windows/editor_release.py settings-key EXE [OWNER/REPO]
        the editor keeps its settings in HKCU\\Software\\<organisation>\\<application>. Our build (Cinders Map Editor,
        mapeditor/patches/0008, O388) uses Cinders\\CindersMapEditor; the upstream release names them after its
        repository (organisation = owner with a capital, application = repo). Prints the first key whose two names are
        both in the program (UTF-16, as its strings are stored): ours, then the upstream one; else exit 3:
        open-map-editor.bat then presets nothing and README.txt has the clicks.
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


OUR_TAG = re.compile(r'^mapeditor-[0-9a-f]{7,40}$')


def latest_tag(releases):
    """newest published tag of our editor builds in a gh release list, or None"""
    ours = [r for r in releases if isinstance(r, dict) and OUR_TAG.match(str(r.get('tagName', '')))
            and not r.get('isDraft')]
    if not ours:
        return None
    return max(ours, key=lambda r: (str(r.get('createdAt', '')), str(r['tagName'])))['tagName']


def patch_range(names):
    """'0001..0006' for consecutive numbered patches, else their numbers (or names) joined by commas"""
    nums = []
    for n in names:
        m = re.match(r'^(\d{4})-', n)
        nums.append(m.group(1) if m else n)
    if not nums:
        return 'none'
    if all(re.match(r'^\d{4}$', x) for x in nums) and len(nums) > 1 and \
            [int(x) for x in nums] == list(range(int(nums[0]), int(nums[0]) + len(nums))):
        return '%s..%s' % (nums[0], nums[-1])
    return ', '.join(nums)


def build_info(path):
    """the key: value lines of BUILD_INFO.txt"""
    info = {}
    with open(path, encoding='utf-8-sig') as f:
        for line in f:
            if ':' in line:
                k, v = line.split(':', 1)
                info[k.strip().lower()] = v.strip()
    return info


def verify_ours(d, want):
    """BUILD_INFO.txt of our build: listed in SHA256SUMS.txt, matching, the patched variant"""
    if 'BUILD_INFO.txt' not in want:
        raise VerifyError('SHA256SUMS.txt does not name BUILD_INFO.txt (not a release of our build)')
    path = os.path.join(d, 'BUILD_INFO.txt')
    if not os.path.isfile(path):
        raise VerifyError('BUILD_INFO.txt is not in the download')
    got = sha256(path)
    if got != want['BUILD_INFO.txt']:
        raise VerifyError('BUILD_INFO.txt: sha256 %s, SHA256SUMS.txt says %s' % (got, want['BUILD_INFO.txt']))
    info = build_info(path)
    if info.get('variant') != 'patched':
        raise VerifyError('BUILD_INFO.txt: variant %r, not patched' % info.get('variant'))
    upstream = info.get('upstream', '')
    if not re.match(r'^[0-9a-f]{40}$', upstream):
        raise VerifyError('BUILD_INFO.txt: upstream %r is not a full sha' % upstream)
    patches = [p.strip() for p in info.get('patches', '').split(',') if p.strip()]
    if not patches or not all(re.match(r'^\d{4}-[\w.-]+\.patch$', p) for p in patches):
        raise VerifyError('BUILD_INFO.txt: no list of our patches')
    commit = info.get('cinders of chaos commit', '')
    if not re.match(r'^[0-9a-f]{40}$', commit):
        raise VerifyError('BUILD_INFO.txt: commit %r is not a full sha' % commit)
    repo = info.get('upstream_repo', '')
    if repo and not re.match(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$', repo):
        repo = ''
    rng = patch_range(patches)
    version = info.get('version', '')
    label = 'our build %s' % version if re.match(r'^[0-9]+(\.[0-9]+){1,3}$', version) else 'our build'
    return {'upstream': upstream, 'upstream_repo': repo, 'patches': rng, 'commit': commit,
            'version': '%s: upstream %s + patches %s' % (label, upstream[:7], rng)}


def verify(d, ours=False):
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
    if ours:
        out.update(verify_ours(d, want))
    return out


# QSettings organisation and application of our build (mapeditor/patches/0008-cinders-map-editor-name.patch)
OUR_SETTINGS = ('Cinders', 'CindersMapEditor')


def settings_key(exe, slug=None):
    """HKCU subkey of the editor's settings: ours when the program holds our names, else the upstream names"""
    with open(exe, 'rb') as f:
        data = f.read()
    candidates = [OUR_SETTINGS]
    if slug and '/' in slug:
        owner, repo = slug.split('/', 1)
        candidates.append((owner[:1].upper() + owner[1:], repo))
    for org, app in candidates:
        # the organisation as a whole string (UTF-16 NUL after it): ours is the start of the application name
        if (org + '\0').encode('utf-16-le') in data and app.encode('utf-16-le') in data:
            return 'Software\\%s\\%s' % (org, app)
    return None


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
    if cmd == 'verify' and len(args) in (1, 2) and (len(args) == 1 or args[1] == '--ours'):
        ours = len(args) == 2
        try:
            out = verify(args[0], ours)
        except VerifyError as e:
            print('map editor download: %s' % e, file=sys.stderr)
            return 1
        keys = ['windows', 'source', 'windows_sha256', 'source_sha256', 'version']
        if ours:
            keys += ['upstream', 'upstream_repo', 'patches', 'commit']
        for k in keys:
            print('%s=%s' % (k, out[k]))
        return 0
    if cmd == 'latest-tag' and len(args) <= 1:
        try:
            if args:
                with open(args[0], encoding='utf-8') as f:
                    releases = json.load(f)
            else:
                releases = json.load(sys.stdin)
        except (ValueError, OSError) as e:
            print('release list: %s' % e, file=sys.stderr)
            return 1
        tag = latest_tag(releases if isinstance(releases, list) else [])
        if not tag:
            print('no mapeditor-<sha> release of our build yet', file=sys.stderr)
            return 1
        print(tag)
        return 0
    if cmd == 'settings-key' and len(args) in (1, 2):
        key = settings_key(args[0], args[1] if len(args) == 2 else None)
        if not key:
            print('the program holds neither our settings names nor those of %s: no settings preset'
                  % (args[1] if len(args) == 2 else 'the upstream release'), file=sys.stderr)
            return 3
        print(key)
        return 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
