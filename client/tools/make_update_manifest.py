#!/usr/bin/env python3
"""Cinders of Chaos signed updater: build, sign and check the update the client downloads (client/MANIFEST.md
"Signed updater", docs/LAUNCH.md "Publishing a client update").

  keygen  --private PATH [--public PATH]
          New Ed25519 key pair. The private key (32-byte seed, hex) is written with mode 600 and must stay OUTSIDE
          the repository (refused inside a git work tree). Prints the public key for init.lua (Services.update).
  build   CLIENT_DIR --out PUBLISH_DIR [--key PATH] [--version N] [--min-version N] [--min-package N]
          [--parallel N] [--channel NAME] [--roots modules,mods,data,layouts] [--dry-run] [--hardlink]
          [--with-single-spr]
          Hashes every file under the roots of an assembled client folder (client/tools/assemble_client.sh, with
          the Tibia.dat/.spr pair in data/things/1098/), copies each distinct file once to
          PUBLISH_DIR/files/<sha[:2]>/<sha> and writes PUBLISH_DIR/manifest.json, signed with the private key from
          --key or the environment variable CHAOS_UPDATE_KEY (a path, never the key itself). The manifest is
          written last, so a client never sees a manifest whose files are not there yet.
          --dry-run: no key needed, nothing written; checks the folder and prints what would be published (CI).
          Sprite shards (tools/sprites/spr_shards.py, base patch 0048): a <name>.sprshards index in data/things/
          is checked against its shard files (sizes, headers, SHA-256) and each shard is its own manifest file, so
          a sprite change downloads only the shards that hold it. Refused: a shard set next to its single .spr
          (both would be downloaded; --with-single-spr ships both on purpose) and a shard set without --min-package
          (a client built before patch 0048 ignores shards and would draw the new dat with its old .spr).
  verify  PUBLISH_DIR --public HEX
          Checks the signature, the payload and every blob's size and SHA-256.

The client refuses: a bad or missing signature, a manifest of another key, an older version than the one it applied,
paths outside modules/ mods/ data/ layouts/, "..", absolute paths, odd characters, and native code
(.exe .dll .so ...). The same rules are applied here, so a manifest the client would refuse is never published.
Uses the `cryptography` package when installed, else ed25519_ref.py (RFC 8032 reference code).
"""
import argparse, datetime, hashlib, json, os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
FORMAT = 'chaos-update-1'
PRODUCT = 'cinders-of-chaos'
DEFAULT_ROOTS = ('modules', 'mods', 'data', 'layouts')
ALLOWED_ROOTS = set(DEFAULT_ROOTS)
DENIED_EXT = {'exe', 'dll', 'so', 'dylib', 'bat', 'cmd', 'com', 'ps1', 'sh', 'msi', 'scr', 'vbs', 'jar', 'app', 'sys',
              'drv', 'cpl', 'lnk', 'reg', 'pif', 'hta', 'wsf', 'apk'}
# never published: editor and patch leftovers, archives and sources the client does not read
SKIP_EXT = {'orig', 'rej', 'bak', 'psd', 'rar', 'xcf', 'kra', 'tmp', 'swp', 'log'}
SKIP_NAMES = {'thumbs.db', '.ds_store', 'desktop.ini'}
WINDOWS_RESERVED = {'con', 'prn', 'aux', 'nul'} | {f'com{i}' for i in range(1, 10)} | {f'lpt{i}' for i in range(1, 10)}
SEGMENT = re.compile(r'^[A-Za-z0-9 ._()+,-]+$')
MAX_FILE_SIZE = 1024 ** 3
MAX_FILES = 50000


# ---------------------------------------------------------------- Ed25519

def _backend():
    try:
        from cryptography.hazmat.primitives.asymmetric import ed25519  # noqa: F401
        return 'cryptography'
    except Exception:
        return 'ref'


def public_from_seed(seed):
    if _backend() == 'cryptography':
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        from cryptography.hazmat.primitives import serialization
        k = Ed25519PrivateKey.from_private_bytes(seed)
        return k.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    sys.path.insert(0, HERE)
    import ed25519_ref
    return ed25519_ref.secret_to_public(seed)


def sign(seed, message):
    if _backend() == 'cryptography':
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        return Ed25519PrivateKey.from_private_bytes(seed).sign(message)
    sys.path.insert(0, HERE)
    import ed25519_ref
    return ed25519_ref.sign(seed, message)


def verify_sig(public, message, signature):
    if len(public) != 32 or len(signature) != 64:
        return False
    if _backend() == 'cryptography':
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
        from cryptography.exceptions import InvalidSignature
        try:
            Ed25519PublicKey.from_public_bytes(public).verify(signature, message)
            return True
        except (InvalidSignature, ValueError):
            return False
    sys.path.insert(0, HERE)
    import ed25519_ref
    return ed25519_ref.verify(public, message, signature)


# ---------------------------------------------------------------- paths

def check_path(path):
    """None when the client accepts the path, else the reason (same rules as updater_core.lua checkPath)."""
    if not path:
        return 'empty path'
    if len(path) > 200:
        return 'path too long'
    if '\\' in path:
        return 'backslash'
    if path.startswith('/'):
        return 'absolute path'
    if ':' in path:
        return 'drive or stream name'
    if path.endswith('/'):
        return 'trailing slash'
    parts = path.split('/')
    for part in parts:
        if part == '':
            return 'empty segment'
        if part in ('.', '..'):
            return 'dot segment'
        if not SEGMENT.match(part):
            return 'bad character'
        if part[0] == ' ' or part[-1] == ' ':
            return 'space at an end'
        if part.endswith('.'):
            return 'trailing dot'
        if part.lower().split('.')[0] in WINDOWS_RESERVED:
            return 'device name'
    if len(parts) < 2:
        return 'not in a folder'
    if parts[0] not in ALLOWED_ROOTS:
        return 'root not allowed'
    ext = parts[-1].lower().rsplit('.', 1)[1] if '.' in parts[-1] else ''
    if ext in DENIED_EXT:
        return 'native code is never updated'
    return None


def skipped(name):
    low = name.lower()
    if low in SKIP_NAMES or low.endswith('~'):
        return True
    return '.' in low and low.rsplit('.', 1)[1] in SKIP_EXT


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def collect(client_dir, roots):
    """[(relpath, abspath)] sorted, plus a list of problems."""
    files, problems, seen = [], [], {}
    for root in roots:
        if root not in ALLOWED_ROOTS:
            problems.append(f'{root}: not an allowed root ({", ".join(sorted(ALLOWED_ROOTS))})')
            continue
        top = os.path.join(client_dir, root)
        if not os.path.isdir(top):
            continue
        for dirpath, dirnames, filenames in os.walk(top):
            dirnames[:] = sorted(d for d in dirnames if not d.startswith('.'))
            for name in sorted(filenames):
                full = os.path.join(dirpath, name)
                rel = os.path.relpath(full, client_dir).replace(os.sep, '/')
                if name.startswith('.') or skipped(name):
                    continue
                if os.path.islink(full) and not os.path.isfile(full):
                    problems.append(f'{rel}: broken link')
                    continue
                why = check_path(rel)
                if why:
                    problems.append(f'{rel}: {why}')
                    continue
                if rel.lower() in seen:
                    problems.append(f'{rel}: same name as {seen[rel.lower()]} on Windows')
                    continue
                seen[rel.lower()] = rel
                files.append((rel, full))
    files.sort()
    if len(files) > MAX_FILES:
        problems.append(f'{len(files)} files (at most {MAX_FILES})')
    return files, problems


def inside_git(path):
    d = os.path.dirname(os.path.abspath(path)) or '.'
    while not os.path.isdir(d):
        d = os.path.dirname(d)
    try:
        r = subprocess.run(['git', '-C', d, 'rev-parse', '--is-inside-work-tree'], capture_output=True, text=True)
        return r.returncode == 0 and r.stdout.strip() == 'true'
    except FileNotFoundError:
        return False


def inside_this_repo(path):
    """True when path is inside the Cinders of Chaos repository (this file's checkout)."""
    repo = os.path.realpath(os.path.join(HERE, '..', '..'))
    target = os.path.realpath(path)
    return target == repo or target.startswith(repo + os.sep)


def read_seed(key_path):
    if inside_git(key_path) or inside_this_repo(key_path):
        sys.exit(f'refused: the private key {key_path} is inside a git work tree; keep it outside the repository')
    text = open(key_path, encoding='ascii').read().strip()
    if not re.fullmatch(r'[0-9a-f]{64}', text):
        sys.exit(f'{key_path}: not an Ed25519 private key (64 lowercase hex digits)')
    return bytes.fromhex(text)


# ---------------------------------------------------------------- manifest

def make_payload(entries, version, min_version, min_package, parallel, channel, created):
    payload = {
        'format': 1, 'product': PRODUCT, 'channel': channel, 'version': version, 'created': created,
        'min_version': min_version, 'min_package': min_package, 'parallel': parallel, 'files_url': 'files/',
        'files': [{'path': p, 'sha256': h, 'size': s} for p, h, s in entries],
    }
    return json.dumps(payload, sort_keys=True, separators=(',', ':'), ensure_ascii=True)


def make_envelope(payload_text, public_hex, signature_hex):
    return json.dumps({'format': FORMAT, 'key': public_hex, 'signature': signature_hex, 'payload': payload_text},
                      indent=1, ensure_ascii=True) + '\n'


def check_payload(m, last_version=None):
    """None when the client accepts the decoded payload (same checks as updater_core.lua validateManifest)."""
    if not isinstance(m, dict):
        return 'payload is not a JSON object'
    if m.get('format') != 1:
        return 'unknown payload format'
    if m.get('product') != PRODUCT:
        return 'manifest of another product'
    v = m.get('version')
    if not isinstance(v, int) or v < 1:
        return 'bad version'
    if last_version is not None and v < last_version:
        return 'older manifest'
    files = m.get('files')
    if not isinstance(files, list) or len(files) > MAX_FILES:
        return 'bad file list'
    seen = set()
    for f in files:
        why = check_path(f.get('path'))
        if why:
            return f'refused path {f.get("path")!r}: {why}'
        if f['path'].lower() in seen:
            return 'duplicate path ' + f['path']
        seen.add(f['path'].lower())
        if not re.fullmatch(r'[0-9a-f]{64}', str(f.get('sha256'))):
            return 'bad sha256 for ' + f['path']
        if not isinstance(f.get('size'), int) or not 0 <= f['size'] <= MAX_FILE_SIZE:
            return 'bad size for ' + f['path']
    return None


def check_sprite_shards(client_dir, entries, min_package, with_single_spr=False):
    """problems with sprite shard sets in data/things/ (texts; 'warning: ...' ones do not stop the build)"""
    sys.path.insert(0, os.path.join(HERE, 'sprites'))
    import spr_shards
    by_path = {p: h for p, h, _ in entries}
    out = []
    for path in sorted(by_path):
        if not (path.startswith('data/things/') and path.endswith('.sprshards')):
            continue
        folder, name = path.rsplit('/', 1)
        name = name[:-len('.sprshards')]
        try:
            idx = spr_shards.check(os.path.join(client_dir, folder), name, quiet=True, hashes=False)
        except spr_shards.ShardError as e:
            out.append(f'{path}: {e}')
            continue
        for _, _, fname, _, sha in idx['shards']:
            if by_path.get(f'{folder}/{fname}') != sha:
                out.append(f'{folder}/{fname}: SHA-256 differs from {path} (split again with spr_shards.py)')
        single = f'{folder}/{name}.spr'
        if single in by_path and not with_single_spr:
            out.append(f'{single} and the shard set {path} are both here: players would download the sprites twice. '
                       f'Remove {name}.spr, or pass --with-single-spr to ship both on purpose')
        if single not in by_path and not min_package:
            out.append(f'{path}: a shard set needs --min-package (the first package built with base patch 0048); '
                       f'an older client ignores the shards and would draw the new dat with its old {name}.spr')
    for path in sorted(by_path):
        if path.startswith('data/things/') and path.endswith('.spr') and not path[:-4].rsplit('.', 1)[-1].isdigit():
            if path[:-4] + '.sprshards' not in by_path:
                out.append(f'warning: {path} without a shard set: a client whose install has {path[:-4]}.sprshards '
                           f'keeps loading its shards (client/BASE.md 0048)')
    return out


def previous_version(out_dir):
    try:
        env = json.load(open(os.path.join(out_dir, 'manifest.json'), encoding='utf-8'))
        return json.loads(env['payload'])['version']
    except (OSError, ValueError, KeyError, TypeError):
        return 0


def build(args):
    client_dir = os.path.abspath(args.client_dir)
    if not os.path.isfile(os.path.join(client_dir, 'init.lua')):
        sys.exit(f'{client_dir}: not an assembled client folder (no init.lua)')
    roots = [r.strip() for r in args.roots.split(',') if r.strip()]
    files, problems = collect(client_dir, roots)
    if problems:
        for p in problems[:50]:
            print('refused:', p, file=sys.stderr)
        sys.exit(f'{len(problems)} file(s) the client would refuse; fix or remove them')
    if not files:
        sys.exit('no files under ' + ', '.join(roots))
    entries, blobs, total = [], {}, 0
    for rel, full in files:
        size = os.path.getsize(full)
        if size > MAX_FILE_SIZE:
            sys.exit(f'{rel}: larger than {MAX_FILE_SIZE} bytes')
        h = sha256_file(full)
        entries.append((rel, h, size))
        blobs.setdefault(h, (full, size))
        total += size
    things = [e for e in entries if e[0].startswith('data/things/') and e[0].lower().endswith(('.dat', '.spr'))]
    if not things:
        print('warning: no Tibia.dat/.spr under data/things/ (the pair is not part of this update)', file=sys.stderr)
    for problem in check_sprite_shards(client_dir, entries, args.min_package, args.with_single_spr):
        if problem.startswith('warning: '):
            print(problem, file=sys.stderr)
        else:
            sys.exit(problem)

    prev = previous_version(args.out) if args.out else 0
    version = args.version if args.version is not None else prev + 1
    if version < 1:
        sys.exit('--version must be 1 or more')
    if version <= prev and not args.dry_run:
        sys.exit(f'version {version} is not newer than the published {prev}; clients refuse older manifests')
    min_version = args.min_version if args.min_version is not None else 0
    if min_version > version:
        sys.exit('--min-version cannot be above --version')
    created = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    payload = make_payload(entries, version, min_version, args.min_package, args.parallel, args.channel, created)
    err = check_payload(json.loads(payload))
    if err:
        sys.exit('internal: ' + err)

    summary = (f'{len(entries)} files, {len(blobs)} distinct, {total / 1024 / 1024:.1f} MB, version {version}, '
               f'min_version {min_version}, min_package {args.min_package}, parallel {args.parallel}')
    if args.dry_run:
        print('dry run (unsigned, nothing written):', summary)
        return 0

    key_path = args.key or os.environ.get('CHAOS_UPDATE_KEY')
    if not key_path:
        sys.exit('no private key: give --key PATH or set CHAOS_UPDATE_KEY to its path (or use --dry-run)')
    seed = read_seed(key_path)
    public = public_from_seed(seed)
    signature = sign(seed, payload.encode('ascii'))
    if not verify_sig(public, payload.encode('ascii'), signature):
        sys.exit('internal: the new signature does not verify')

    out = os.path.abspath(args.out)
    if inside_this_repo(out):
        sys.exit(f'refused: {out} is inside the repository; publish to the website folder')
    os.makedirs(os.path.join(out, 'files'), exist_ok=True)
    new = 0
    for h, (src, size) in sorted(blobs.items()):
        dst = os.path.join(out, 'files', h[:2], h)
        if os.path.isfile(dst) and os.path.getsize(dst) == size:
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        tmp = dst + '.tmp'
        if os.path.exists(tmp):
            os.remove(tmp)
        if args.hardlink:
            os.link(src, tmp)
        else:
            shutil.copyfile(src, tmp)
        os.replace(tmp, dst)
        new += 1
    fd, tmp = tempfile.mkstemp(dir=out, prefix='.manifest.')
    with os.fdopen(fd, 'w', encoding='ascii') as f:
        f.write(make_envelope(payload, public.hex(), signature.hex()))
    os.chmod(tmp, 0o644)
    os.replace(tmp, os.path.join(out, 'manifest.json'))
    print(f'published {summary}; {new} new blob(s); public key {public.hex()}')
    return 0


def verify(args):
    out = os.path.abspath(args.publish_dir)
    try:
        env = json.load(open(os.path.join(out, 'manifest.json'), encoding='utf-8'))
    except (OSError, ValueError) as e:
        sys.exit(f'manifest.json: {e}')
    if env.get('format') != FORMAT or not isinstance(env.get('payload'), str):
        sys.exit('manifest.json: not a Cinders of Chaos update envelope')
    if not re.fullmatch(r'[0-9a-f]{64}', args.public or ''):
        sys.exit('--public: 64 lowercase hex digits')
    if not re.fullmatch(r'[0-9a-f]{128}', str(env.get('signature'))):
        sys.exit('refused: the manifest is not signed')
    if not verify_sig(bytes.fromhex(args.public), env['payload'].encode('utf-8'), bytes.fromhex(env['signature'])):
        sys.exit('refused: bad signature')
    m = json.loads(env['payload'])
    err = check_payload(m)
    if err:
        sys.exit('refused: ' + err)
    bad = 0
    for f in m['files']:
        blob = os.path.join(out, 'files', f['sha256'][:2], f['sha256'])
        if not os.path.isfile(blob) or os.path.getsize(blob) != f['size'] or sha256_file(blob) != f['sha256']:
            print('bad blob for', f['path'], file=sys.stderr)
            bad += 1
    if bad:
        sys.exit(f'{bad} blob(s) missing or changed')
    print(f'ok: version {m["version"]}, {len(m["files"])} files, signature good')
    return 0


def keygen(args):
    for path in filter(None, (args.private, args.public)):
        if inside_git(path) or inside_this_repo(path):
            sys.exit(f'refused: {path} is inside a git work tree; keep keys outside the repository')
    if os.path.exists(args.private):
        sys.exit(f'{args.private} exists; not overwritten')
    seed = os.urandom(32)
    public = public_from_seed(seed)
    fd = os.open(args.private, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w', encoding='ascii') as f:
        f.write(seed.hex() + '\n')
    if args.public:
        with open(args.public, 'w', encoding='ascii') as f:
            f.write(public.hex() + '\n')
    print('private key:', os.path.abspath(args.private), '(mode 600, back it up offline)')
    print('public key :', public.hex())
    print('put the public key in init.lua: Services.update.publicKey')
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    k = sub.add_parser('keygen')
    k.add_argument('--private', required=True)
    k.add_argument('--public')
    b = sub.add_parser('build')
    b.add_argument('client_dir')
    b.add_argument('--out')
    b.add_argument('--key')
    b.add_argument('--version', type=int)
    b.add_argument('--min-version', type=int)
    b.add_argument('--min-package', type=int, default=0)
    b.add_argument('--parallel', type=int, default=4, choices=range(1, 9), metavar='1..8')
    b.add_argument('--channel', default='live')
    b.add_argument('--roots', default=','.join(DEFAULT_ROOTS))
    b.add_argument('--dry-run', action='store_true')
    b.add_argument('--with-single-spr', action='store_true',
                   help='ship a single .spr next to its shard set (for clients built before base patch 0048)')
    b.add_argument('--hardlink', action='store_true',
                   help='hard-link blobs instead of copying (same disk; only if the client folder is never edited after)')
    v = sub.add_parser('verify')
    v.add_argument('publish_dir')
    v.add_argument('--public', required=True)
    args = ap.parse_args(argv)
    if args.cmd == 'build' and not args.dry_run and not args.out:
        ap.error('build needs --out (or --dry-run)')
    if args.cmd == 'build' and not re.fullmatch(r'[a-z0-9-]{1,32}', args.channel):
        ap.error('--channel: lowercase letters, digits and dashes')
    return {'keygen': keygen, 'build': build, 'verify': verify}[args.cmd](args)


if __name__ == '__main__':
    sys.exit(main())
