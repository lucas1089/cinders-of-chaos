#!/usr/bin/env python3
"""Cinders of Chaos signed updater: build, sign and check the update the client downloads (client/MANIFEST.md
"Signed updater", docs/LAUNCH.md "Publishing a client update").

  keygen  --private PATH [--public PATH]
          New Ed25519 key pair. The private key (32-byte seed, hex) is written with mode 600 and must stay OUTSIDE
          the repository (refused inside a git work tree). Prints the public key for init.lua (Services.update).
  pubkey  --private PATH
          Prints only the public key (64 hex digits) of a private key file (server/deploy/publish_client_update.sh).
  build   CLIENT_DIR --out PUBLISH_DIR [--key PATH] [--version N] [--min-version N] [--min-package N]
          [--parallel N] [--channel NAME] [--roots modules,mods,data,layouts] [--dry-run] [--dev] [--key-index N]
          [--with-single-spr] [--native-dir DIR --native-package N [--native-game NAME] [--native-launcher NAME]]
          [--no-android] [--android-exclude PREFIX ...]
          Hashes every file under the roots of an assembled client folder (client/tools/assemble_client.sh, with
          the Tibia.dat/.spr pair in data/things/1098/; or a packed package unpacked with `unpack`), ENCRYPTS each
          distinct file once (update_crypt.py: AES-256-GCM, key = HKDF of the client guard secret CHAOS_CLIENT_KEY,
          deterministic nonce) to PUBLISH_DIR/files/<c[:2]>/<c> where c is the SHA-256 of the encrypted blob, and
          writes PUBLISH_DIR/manifest.json, signed with the private key from --key or the environment variable
          CHAOS_UPDATE_KEY (a path, never the key itself). The manifest is written last, so a client never sees a
          manifest whose files are not there yet; then every other file of PUBLISH_DIR/files/ (older blobs, the
          plain blobs of a publish before build 13) is removed, so the web folder holds only ciphertext.
          The blob key: CHAOS_CLIENT_KEY in the environment (64 hex digits; "old,new" during a rotation, then
          --key-index picks one, 1-based; `unpack` prints the index that opens the package). It is never printed.
          No key: refused (no plain fallback). --dev: the public development key instead (tests and allow_dev_key
          packages only; a production client cannot open such blobs). Without --dev, --min-package must be 13 or
          more (the first client build that can decrypt updates, base patch 0103).
          --dry-run: no key needed, nothing written; checks the folder and prints what would be published (CI).
          Version: a package with Services.update.baseline = B in its init.lua (base patch 0101, the release number
          winpkg-B written by set_update_config.py --baseline) is published as version B, and --version must be B:
          clients never apply a manifest below their own baseline. Without a baseline: --version, else the
          published version + 1.
          Sprite shards (tools/sprites/spr_shards.py, base patch 0048): a <name>.sprshards index in data/things/
          is checked against its shard files (sizes, headers, SHA-256) and each shard is its own manifest file, so
          a sprite change downloads only the shards that hold it. Refused: a shard set next to its single .spr
          (both would be downloaded; --with-single-spr ships both on purpose) and a shard set without --min-package
          (a client built before patch 0048 ignores shards and would draw the new dat with its old .spr).
          Size limits: every file at most 1 GiB (MAX_FILE_SIZE, the same in updater_core.lua; the updater of the
          builds already out refuses a whole manifest that lists a bigger file, so the limit cannot grow): a bigger
          .spr is refused with a hint to ship it as shards. All files together must fit the engine's update overlay,
          a ZIP without ZIP64 (base patch 0103: below 4 GiB).
          Phone data (O313, client/MANIFEST.md "Phone data"): the payload also gets an "android" section, the list of
          the files an Android phone downloads on first start: {"version": 1, "files": [paths of "files"], "count",
          "bytes"}. It lists every file of the update except layouts/mobile/ (the APK leaves that folder out on
          purpose) and the prefixes given with --android-exclude (desktop-only art); "bytes" is the size of the
          distinct encrypted blobs (the download). The paths refer to the "files" entries, so the sizes and hashes
          stay under the same signature. Clients built before the key existed ignore it. --no-android leaves it out.
          Native files for the game launcher (O314, client/MANIFEST.md "Game launcher"): --native-dir is a folder with
          the program files of the package (Chaos.exe, its DLLs, chaos.pack, the launcher exe; only .exe .dll .pack, no
          sub-folders). They go into the signed payload as a separate "native" section and are published as PLAIN
          blobs under PUBLISH_DIR/native/<sha[:2]>/<sha> (the package ships them plain anyway; chaos.pack is already
          ciphertext). The client's Lua updater never reads that section and its "files" list is unchanged, so every
          client already out keeps working. --native-package N is the package number (Services.update.package) of
          these files and must be at least --min-package. --native-game is the exe the launcher starts (default
          Chaos.exe), --native-launcher the launcher's own file in the folder (it updates itself at its next start).
  verify  PUBLISH_DIR --public HEX [--dev] [--key-index N]
          Checks the signature, the payload and every blob's size and SHA-256; with the blob key (CHAOS_CLIENT_KEY or
          --dev) also decrypts every blob and checks the plaintext SHA-256 the manifest signs.
  unpack  PACK DEST [--dev]
          Decrypts a packed client (chaos.pack, base patch 0102) with the key of CHAOS_CLIENT_KEY that opens it and
          extracts it into the new folder DEST (safe names only). Prints "key-index=N" for build --key-index.
          A development pack is refused unless --dev.

Signing: the payload lists, for each file, the plaintext SHA-256 and size and the encrypted blob's SHA-256 ("blob")
and size ("blob_size"), plus "encryption": "chaos-blob-1"; the Ed25519 signature covers all of them. The client checks
the downloaded bytes against "blob" (transit), decrypts them (the GCM tag) and checks the plaintext against "sha256"
(content), so a blob is accepted only when both hashes the operator signed match.
The client refuses: a bad or missing signature, a manifest of another key, an older version than the one it applied,
paths outside modules/ mods/ data/ layouts/, "..", absolute paths, odd characters, and native code
(.exe .dll .so ...). The same rules are applied here, so a manifest the client would refuse is never published.
It also skips (never applies) a manifest whose version is below its package's baseline.
The launcher refuses the same things and, for the native section: a path that is not one plain file name of
.exe .dll .pack, a hash or size that does not match, more than NATIVE_MAX_FILES files or a file over NATIVE_MAX_FILE_SIZE.
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
# Never raise it: the updater of every client build already out (updater_core.lua M.MAX_FILE_SIZE) refuses the whole
# manifest when one file is bigger. A sprite file past it ships as shards (tools/sprites/spr_shards.py, base patch 0048).
MAX_FILE_SIZE = 1024 ** 3
# the engine mounts the update files as one in-memory ZIP without ZIP64 (base patch 0103, chaosblob::StoreZip::fits)
MAX_OVERLAY_SIZE = 0xFFFFFFF0
MAX_FILES = 50000
# encrypted update blobs (update_crypt.py, base patch 0103): the client refuses a manifest without them
ENCRYPTION = 'chaos-blob-1'
BLOB_OVERHEAD = 44  # header 28 + GCM tag 16
ENCRYPTED_MIN_PACKAGE = 13  # the first client build that decrypts updates
KEY_ENV = 'CHAOS_CLIENT_KEY'
# native files of the game launcher (O314): one section of the signed payload, plain blobs, never read by the Lua updater
NATIVE_EXT = {'exe', 'dll', 'pack'}
NATIVE_DIR = 'native'
NATIVE_MAX_FILES = 64
NATIVE_MAX_FILE_SIZE = 2 * 1024 ** 3  # chaos.pack is about 0.9 GB
NATIVE_NAME = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')
# phone data (O313): the "android" section of the signed payload lists the "files" an Android phone downloads on first start
ANDROID_SECTION_VERSION = 1
# never on a phone: the APK leaves layouts/mobile out on purpose (client/android/tools/make_assets.sh; its console style
# has no readOnly widget and stopped game_console at start), so the phone keeps the default layout
ANDROID_EXCLUDE = ('layouts/mobile/',)


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


def crypt():
    """update_crypt.py (needs the `cryptography` package; only publishing, verifying with a key and unpacking do)"""
    sys.path.insert(0, HERE)
    try:
        import update_crypt
    except ImportError as e:
        sys.exit(f'the blob encryption needs the python3 `cryptography` package (apt install python3-cryptography): {e}')
    return update_crypt


def client_keys(dev):
    """[(index, 32-byte key)] from CHAOS_CLIENT_KEY, or the development key with --dev. [] when none is set."""
    uc = crypt()
    if dev:
        return [(0, bytes.fromhex(uc.DEV_KEY_HEX))]
    try:
        keys = uc.parse_client_keys(os.environ.get(KEY_ENV, ''))
    except uc.BlobError as e:
        sys.exit(str(e))
    return list(enumerate(keys, 1))


def blob_key(args, need):
    """The one key the blobs are encrypted with: (key, dev), or None when there is none and need is False."""
    if not args.dev and not need and not os.environ.get(KEY_ENV, '').strip():
        return None
    keys = client_keys(args.dev)
    if args.dev:
        return keys[0][1], True
    if not keys:
        if need:
            sys.exit(f'no blob key: set {KEY_ENV} (64 hex digits, the client guard secret the package was built with; '
                     f'on the VPS it is in /etc/chaos/chaos.env). Updates are never published unencrypted; '
                     f'--dev uses the public development key (tests only)')
        return None
    if args.key_index is not None:
        if not 1 <= args.key_index <= len(keys):
            sys.exit(f'--key-index {args.key_index}: {KEY_ENV} holds {len(keys)} key(s)')
        return keys[args.key_index - 1][1], False
    if len(keys) > 1:
        sys.exit(f'{KEY_ENV} holds {len(keys)} keys (a rotation): give --key-index (unpack prints the one that opens '
                 f'the package)')
    return keys[0][1], False


# ---------------------------------------------------------------- native files (game launcher, O314)

def check_native_name(name):
    """None when the launcher accepts the file name (one plain name in the install folder), else the reason."""
    if not isinstance(name, str) or not NATIVE_NAME.match(name):
        return 'bad file name'
    if name.endswith('.'):
        return 'trailing dot'
    if name.lower().split('.')[0] in WINDOWS_RESERVED:
        return 'device name'
    ext = name.lower().rsplit('.', 1)[1] if '.' in name else ''
    if ext not in NATIVE_EXT:
        return 'only .exe .dll .pack'
    return None


def collect_native(native_dir):
    """[(name, abspath)] of the program files in the folder (no sub-folders), plus a list of problems."""
    files, problems, seen = [], [], {}
    for name in sorted(os.listdir(native_dir)):
        full = os.path.join(native_dir, name)
        if name.startswith('.') or skipped(name):
            continue
        if not os.path.isfile(full):
            problems.append(f'{name}: not a plain file')
            continue
        why = check_native_name(name)
        if why:
            problems.append(f'{name}: {why}')
            continue
        if name.lower() in seen:
            problems.append(f'{name}: same name as {seen[name.lower()]} on Windows')
            continue
        seen[name.lower()] = name
        if os.path.getsize(full) > NATIVE_MAX_FILE_SIZE:
            problems.append(f'{name}: larger than {NATIVE_MAX_FILE_SIZE} bytes')
            continue
        files.append((name, full))
    if len(files) > NATIVE_MAX_FILES:
        problems.append(f'{len(files)} native files (at most {NATIVE_MAX_FILES})')
    return files, problems


def make_native(entries, package, game, launcher):
    """entries: (name, sha256, size). The "native" payload section."""
    n = {'package': package, 'game': game, 'files_url': NATIVE_DIR + '/',
         'files': [{'path': p, 'sha256': h, 'size': s} for p, h, s in entries]}
    if launcher:
        n['launcher'] = launcher
    return n


def check_native(n):
    """None when the launcher accepts the decoded "native" section (same rules as launcher/src/manifest.rs)."""
    if not isinstance(n, dict):
        return 'native is not an object'
    if not isinstance(n.get('package'), int) or n['package'] < 0:
        return 'native: bad package'
    if n.get('files_url') != NATIVE_DIR + '/':
        return 'native: bad files_url'
    files = n.get('files')
    if not isinstance(files, list) or not files or len(files) > NATIVE_MAX_FILES:
        return 'native: bad file list'
    names = set()
    for f in files:
        why = check_native_name(f.get('path'))
        if why:
            return f'native: refused path {f.get("path")!r}: {why}'
        if f['path'].lower() in names:
            return 'native: duplicate path ' + f['path']
        names.add(f['path'].lower())
        if not re.fullmatch(r'[0-9a-f]{64}', str(f.get('sha256'))):
            return 'native: bad sha256 for ' + f['path']
        if not isinstance(f.get('size'), int) or not 0 <= f['size'] <= NATIVE_MAX_FILE_SIZE:
            return 'native: bad size for ' + f['path']
    game = n.get('game')
    if check_native_name(game) or not game.lower().endswith('.exe') or game.lower() not in names:
        return 'native: game is not an .exe of the file list'
    launcher = n.get('launcher')
    if launcher is not None and (check_native_name(launcher) or not launcher.lower().endswith('.exe')
                                 or launcher.lower() not in names or launcher.lower() == game.lower()):
        return 'native: launcher is not another .exe of the file list'
    return None


def android_excluded(path, extra=()):
    """True when the phone does not download this path (ANDROID_EXCLUDE plus the extra prefixes)."""
    return any(path.startswith(x) for x in ANDROID_EXCLUDE + tuple(extra))


def make_android(entries, extra_exclude=()):
    """entries: (path, plaintext sha256, plaintext size, blob sha256, blob size). The "android" payload section."""
    chosen = sorted((e for e in entries if not android_excluded(e[0], extra_exclude)), key=lambda e: e[0])
    blobs = {}
    for _, _, _, b, bs in chosen:
        blobs[b] = bs
    return {'version': ANDROID_SECTION_VERSION, 'files': [e[0] for e in chosen], 'count': len(chosen),
            'bytes': sum(blobs.values())}


def check_android(a, files):
    """None when the phone client accepts the decoded "android" section (same rules as firststart_core.lua
    androidEntries); files: the decoded "files" list of the same payload."""
    if not isinstance(a, dict):
        return 'android is not an object'
    if a.get('version') != ANDROID_SECTION_VERSION:
        return 'android: bad version'
    listed = a.get('files')
    if not isinstance(listed, list) or not listed:
        return 'android: bad file list'
    by_path = {f['path']: f for f in files}
    seen, blobs = set(), {}
    for p in listed:
        if not isinstance(p, str) or p not in by_path:
            return f'android: {p!r} is not a file of the update'
        if p in seen:
            return 'android: duplicate path ' + p
        seen.add(p)
        if android_excluded(p):
            return 'android: ' + p + ' is never on a phone'
        blobs[by_path[p]['blob']] = by_path[p]['blob_size']
    if a.get('count') != len(listed):
        return 'android: bad count'
    if a.get('bytes') != sum(blobs.values()):
        return 'android: bad bytes'
    return None


def native_blob_path(out_dir, sha):
    return os.path.join(out_dir, NATIVE_DIR, sha[:2], sha)


# ---------------------------------------------------------------- manifest

def make_payload(entries, version, min_version, min_package, parallel, channel, created, native=None, android=None):
    """entries: (path, plaintext sha256, plaintext size, blob sha256, blob size). android: None leaves the phone
    section out, a tuple of extra path prefixes (maybe empty) writes it."""
    payload = {
        'format': 1, 'product': PRODUCT, 'channel': channel, 'version': version, 'created': created,
        'min_version': min_version, 'min_package': min_package, 'parallel': parallel, 'files_url': 'files/',
        'encryption': ENCRYPTION,
        'files': [{'path': p, 'sha256': h, 'size': s, 'blob': b, 'blob_size': bs} for p, h, s, b, bs in entries],
    }
    if native is not None:
        payload['native'] = native
    if android is not None:
        payload['android'] = make_android(entries, android)
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
    if m.get('encryption') != ENCRYPTION:
        return 'manifest is not encrypted'
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
        if not re.fullmatch(r'[0-9a-f]{64}', str(f.get('blob'))):
            return 'bad blob for ' + f['path']
        if f.get('blob_size') != f['size'] + BLOB_OVERHEAD:
            return 'bad blob_size for ' + f['path']
    if 'android' in m:
        err = check_android(m['android'], files)
        if err:
            return err
    if 'native' in m:
        return check_native(m['native'])
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


def overlay_size(entries):
    """bytes of the in-memory ZIP the client builds when every file is in its update tree (base patch 0103,
    chaosblob::StoreZip::sizeFor: 22 + per file 30 + 46 + 2 x name + data)"""
    return 22 + sum(76 + 2 * len(path.encode('utf-8')) + size for path, _, size in entries)


def package_baseline(client_dir):
    """Services.update.baseline of the client's init.lua (base patch 0101): the update version the package's own files
    are (its release number). 0 when the field is missing (a package built before 0101) or not a number."""
    try:
        text = open(os.path.join(client_dir, 'init.lua'), encoding='utf-8', errors='replace').read()
    except OSError:
        return 0
    block = re.search(r'\n  update = \{\n(.*?)\n  \}', text, re.S)
    m = re.search(r'(?m)^\s*baseline = (\d{1,9})\s*,?\s*$', block.group(1)) if block else None
    return int(m.group(1)) if m else 0


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
            hint = ''
            if rel.startswith('data/things/') and rel.lower().endswith('.spr'):
                hint = (f'; ship it as sprite shards: python3 -I client/tools/sprites/spr_shards.py split '
                        f'{rel.rsplit("/", 1)[-1]} <folder>, then leave the single file out '
                        f'(client/MANIFEST.md "Sharded sprites")')
            sys.exit(f'{rel}: larger than {MAX_FILE_SIZE} bytes (the client updater refuses it){hint}')
        h = sha256_file(full)
        entries.append((rel, h, size))
        blobs.setdefault(h, (full, size))
        total += size
    overlay = overlay_size(entries)
    if overlay >= MAX_OVERLAY_SIZE:
        sys.exit(f'{len(entries)} files make an update overlay of {overlay} bytes; the client mounts at most '
                 f'{MAX_OVERLAY_SIZE} (a ZIP without ZIP64, base patch 0103)')
    things = [e for e in entries if e[0].startswith('data/things/') and e[0].lower().endswith(('.dat', '.spr'))]
    if not things:
        print('warning: no Tibia.dat/.spr under data/things/ (the pair is not part of this update)', file=sys.stderr)
    for problem in check_sprite_shards(client_dir, entries, args.min_package, args.with_single_spr):
        if problem.startswith('warning: '):
            print(problem, file=sys.stderr)
        else:
            sys.exit(problem)

    native_entries, native_src = None, {}
    if args.native_dir:
        native_entries, native_src = read_native(args)
    prev = previous_version(args.out) if args.out else 0
    # the package's baseline (its release number, Services.update.baseline) IS the version of its files: clients never
    # apply a manifest below their own baseline, so a manifest of these files under another number would either be
    # skipped by this package's own players (lower) or put these older files over a newer package's (higher)
    baseline = package_baseline(client_dir)
    if baseline and args.version is not None and args.version != baseline:
        sys.exit(f'--version {args.version} is not this package\'s baseline {baseline} (Services.update.baseline, its release '
                 f'number); the manifest of these files must be version {baseline}')
    version = args.version if args.version is not None else (baseline or prev + 1)
    if version < 1:
        sys.exit('--version must be 1 or more')
    if version <= prev and not args.dry_run:
        sys.exit(f'version {version} is not newer than the published {prev}; clients refuse older manifests'
                 + (' (this package is older than the published one: publish a newer package)' if baseline else ''))
    min_version = args.min_version if args.min_version is not None else 0
    if min_version > version:
        sys.exit('--min-version cannot be above --version')
    created = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    native = (make_native(native_entries, args.native_package, args.native_game, args.native_launcher)
              if native_entries is not None else None)
    android = None if args.no_android else tuple(args.android_exclude or ())
    for x in android or ():
        if not re.fullmatch(r'(modules|mods|data|layouts)/[A-Za-z0-9 ._()+,/-]*/', x) or '..' in x:
            sys.exit(f'--android-exclude {x!r}: a folder prefix like data/images/streamer/ (with the final slash)')
    if android is not None and not any(e[0].startswith('data/things/') and e[0].lower().endswith('.dat')
                                       and not android_excluded(e[0], android) for e in entries):
        print('warning: no data/things/*.dat in the phone data list (a phone could not start from this update)',
              file=sys.stderr)
    summary = (f'{len(entries)} files, {len(blobs)} distinct, {total / 1024 / 1024:.1f} MB, version {version}'
               + (f', native package {args.native_package} ({len(native_entries)} files)' if native else '')
               + (f' (package baseline {baseline})' if baseline else '') + ', '
               f'min_version {min_version}, min_package {args.min_package}, parallel {args.parallel}'
               + (f', phone data {sum(1 for e in entries if not android_excluded(e[0], android))} files'
                  if android is not None else ''))
    if args.dry_run:
        # the blob hashes need the key: the payload rules are checked with stand-ins
        stand_in = [(p, h, s, h, s + BLOB_OVERHEAD) for p, h, s in entries]
        err = check_payload(json.loads(make_payload(stand_in, version, min_version, args.min_package, args.parallel,
                                                    args.channel, created, native, android)))
        if err:
            sys.exit('internal: ' + err)
        print('dry run (unsigned, unencrypted, nothing written):', summary)
        return 0

    if not args.dev and args.min_package < ENCRYPTED_MIN_PACKAGE:
        sys.exit(f'--min-package {args.min_package}: encrypted updates need --min-package {ENCRYPTED_MIN_PACKAGE} or '
                 f'more (older clients cannot decrypt them and must download the new client)')
    key_path = args.key or os.environ.get('CHAOS_UPDATE_KEY')
    if not key_path:
        sys.exit('no private key: give --key PATH or set CHAOS_UPDATE_KEY to its path (or use --dry-run)')
    seed = read_seed(key_path)
    public = public_from_seed(seed)
    ckey, dev = blob_key(args, need=True)
    uc = crypt()

    out = os.path.abspath(args.out)
    if inside_this_repo(out):
        sys.exit(f'refused: {out} is inside the repository; publish to the website folder')
    files_dir = os.path.join(out, 'files')
    os.makedirs(files_dir, exist_ok=True)
    # encrypt each distinct file once; the blob is addressed by its own SHA-256 (the bytes the web server holds)
    enc, new = {}, 0
    for h, (src, size) in sorted(blobs.items()):
        fd, tmp = tempfile.mkstemp(dir=files_dir, prefix='.blob.')
        try:
            with os.fdopen(fd, 'wb') as f:
                c, csize = uc.encrypt_file(src, f, ckey, dev=dev)
            dst = os.path.join(files_dir, c[:2], c)
            if os.path.isfile(dst) and os.path.getsize(dst) == csize:
                os.remove(tmp)
            else:
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                os.chmod(tmp, 0o644)
                os.replace(tmp, dst)
                new += 1
        except BaseException:
            if os.path.exists(tmp):
                os.remove(tmp)
            raise
        enc[h] = (c, csize)
    full = [(p, h, s) + enc[h] for p, h, s in entries]
    payload = make_payload(full, version, min_version, args.min_package, args.parallel, args.channel, created, native,
                           android)
    err = check_payload(json.loads(payload))
    if err:
        sys.exit('internal: ' + err)
    # plain native blobs first, like the encrypted ones: the manifest is written last
    publish_native(out, native_entries or [], native_src)
    signature = sign(seed, payload.encode('ascii'))
    if not verify_sig(public, payload.encode('ascii'), signature):
        sys.exit('internal: the new signature does not verify')
    fd, tmp = tempfile.mkstemp(dir=out, prefix='.manifest.')
    with os.fdopen(fd, 'w', encoding='ascii') as f:
        f.write(make_envelope(payload, public.hex(), signature.hex()))
    os.chmod(tmp, 0o644)
    os.replace(tmp, os.path.join(out, 'manifest.json'))
    removed = prune_blobs(files_dir, {c for c, _ in enc.values()})
    removed += prune_blobs(os.path.join(out, NATIVE_DIR), {h for _, h, _ in native_entries or []})
    print(f'published {summary}; encrypted ({"DEVELOPMENT key" if dev else KEY_ENV}); {new} new blob(s), '
          f'{removed} old file(s) removed; public key {public.hex()}')
    return 0


def read_native(args):
    """([(name, sha256, size)], {sha256: abspath}) of --native-dir, or exits with the reason."""
    if args.native_package is None:
        sys.exit('--native-dir needs --native-package (the package number of these files, Services.update.package)')
    if args.native_package < args.min_package:
        sys.exit(f'--native-package {args.native_package} is below --min-package {args.min_package}: the launcher '
                 f'would leave the player on a package the manifest calls too old')
    nd = os.path.abspath(args.native_dir)
    if not os.path.isdir(nd):
        sys.exit(f'{nd}: not a folder')
    files, problems = collect_native(nd)
    if problems:
        for p in problems:
            print('refused:', p, file=sys.stderr)
        sys.exit(f'{len(problems)} native file(s) the launcher would refuse')
    if not files:
        sys.exit(f'{nd}: no .exe .dll .pack files')
    entries, src = [], {}
    for name, full in files:
        h = sha256_file(full)
        entries.append((name, h, os.path.getsize(full)))
        src.setdefault(h, full)
    names = {n.lower() for n, _, _ in entries}
    if args.native_game.lower() not in names:
        sys.exit(f'--native-game {args.native_game}: not in {nd}')
    if args.native_launcher and args.native_launcher.lower() not in names:
        sys.exit(f'--native-launcher {args.native_launcher}: not in {nd}')
    err = check_native(make_native(entries, args.native_package, args.native_game, args.native_launcher))
    if err:
        sys.exit('refused: ' + err)
    return entries, src


def publish_native(out, entries, src):
    """copies the plain native blobs to OUT/native/<sha[:2]>/<sha> (atomic per file; a present blob is kept)"""
    for _, h, size in entries:
        dst = native_blob_path(out, h)
        if os.path.isfile(dst) and os.path.getsize(dst) == size:
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(dst), prefix='.native.')
        try:
            with os.fdopen(fd, 'wb') as f, open(src[h], 'rb') as s:
                shutil.copyfileobj(s, f, 1 << 20)
            os.chmod(tmp, 0o644)
            os.replace(tmp, dst)
        except BaseException:
            if os.path.exists(tmp):
                os.remove(tmp)
            raise


def prune_blobs(files_dir, keep):
    """removes every file of PUBLISH_DIR/files/ the new manifest does not name (older blobs, the plain blobs of a
    publish before build 13, leftovers) and the folders left empty. Returns how many files went."""
    removed = 0
    if not os.path.isdir(files_dir):
        return 0
    for dirpath, dirnames, filenames in os.walk(files_dir, topdown=False):
        for name in filenames:
            if name not in keep or os.path.basename(dirpath) != name[:2]:
                os.remove(os.path.join(dirpath, name))
                removed += 1
        if dirpath != files_dir and not os.listdir(dirpath):
            os.rmdir(dirpath)
    return removed


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
    found = blob_key(args, need=False)
    uc = crypt() if found else None
    bad, plain = 0, {}
    for f in m['files']:
        blob = os.path.join(out, 'files', f['blob'][:2], f['blob'])
        if not os.path.isfile(blob) or os.path.getsize(blob) != f['blob_size'] or sha256_file(blob) != f['blob']:
            print('bad blob for', f['path'], file=sys.stderr)
            bad += 1
            continue
        if found:
            if f['blob'] not in plain:
                try:
                    plain[f['blob']] = uc.decrypt_file(blob, found[0])[1]
                except uc.BlobError as e:
                    plain[f['blob']] = 'error: ' + str(e)
            if plain[f['blob']] != f['sha256']:
                why = plain[f['blob']] if plain[f['blob']].startswith('error') else 'another SHA-256'
                print('bad blob for', f['path'], f'(does not decrypt to the signed content: {why})', file=sys.stderr)
                bad += 1
    nat = m.get('native')
    for f in (nat or {}).get('files', []):
        blob = native_blob_path(out, f['sha256'])
        if not os.path.isfile(blob) or os.path.getsize(blob) != f['size'] or sha256_file(blob) != f['sha256']:
            print('bad native file', f['path'], file=sys.stderr)
            bad += 1
    if bad:
        sys.exit(f'{bad} blob(s) missing or changed')
    print(f'ok: version {m["version"]}, {len(m["files"])} files, '
          + (f'{len(nat["files"])} native files (package {nat["package"]}), ' if nat else '')
          + (f'{m["android"]["count"]} phone files, ' if m.get('android') else '') + 'signature good, '
          + ('every blob decrypts to its signed content' if found else
             f'blobs checked as ciphertext only (no {KEY_ENV}: plaintext not checked)'))
    return 0


def check_pack_name(n):
    """None for a safe relative file name inside a pack, else the reason"""
    if not n or n.startswith('/') or '\\' in n or ':' in n or '\0' in n:
        return 'unsafe path'
    if any(p in ('', '.', '..') for p in n.split('/')):
        return 'unsafe path'
    return None


def unpack(args):
    """chaos.pack -> DEST with the key of CHAOS_CLIENT_KEY that opens it (streamed: the ZIP goes through a temporary
    file beside DEST, the ~900 MB pack is never held in memory)"""
    uc = crypt()
    import zipfile
    dest = os.path.abspath(args.dest)
    if os.path.exists(dest) and os.listdir(dest):
        sys.exit(f'{dest}: not empty')
    try:
        flags = uc.header_flags(args.pack, uc.PACK)
    except (OSError, uc.BlobError) as e:
        sys.exit(f'{args.pack}: {e}')
    if flags & uc.FLAG_DEV and not args.dev:
        sys.exit(f'{args.pack} is a DEVELOPMENT pack (public key, an allow_dev_key build): refused without --dev')
    keys = client_keys(args.dev)
    if not keys:
        sys.exit(f'no {KEY_ENV}: a packed client (chaos.pack) opens only with the client guard secret it was built '
                 f'with (on the VPS: /etc/chaos/chaos.env)')
    os.makedirs(dest, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(dest), prefix='.pack-')
    os.close(fd)
    index = None
    try:
        for i, key in keys:
            try:
                with open(tmp, 'wb') as f:
                    uc.decrypt_file(args.pack, key, f, uc.PACK)
                index = i
                break
            except uc.BlobError:
                continue
        if index is None:
            sys.exit(f'{args.pack}: no key of {KEY_ENV} opens it (another build key, or a damaged file)')
        with zipfile.ZipFile(tmp) as z:
            for info in z.infolist():
                n = info.filename
                if n.endswith('/'):
                    continue
                if check_pack_name(n):
                    sys.exit(f'{args.pack}: refused entry {n!r}')
                target = os.path.join(dest, *n.split('/'))
                os.makedirs(os.path.dirname(target), exist_ok=True)
                with z.open(info) as src, open(target, 'xb') as dst:
                    shutil.copyfileobj(src, dst, 1 << 20)
    finally:
        os.remove(tmp)
    print(f'unpacked {args.pack} -> {dest}' + (' (development key)' if args.dev else ''))
    print(f'key-index={index}')
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


def pubkey(args):
    print(public_from_seed(read_seed(args.private)).hex())
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    k = sub.add_parser('keygen')
    k.add_argument('--private', required=True)
    k.add_argument('--public')
    pk = sub.add_parser('pubkey')
    pk.add_argument('--private', required=True)
    b = sub.add_parser('build')
    b.add_argument('client_dir')
    b.add_argument('--out')
    b.add_argument('--key')
    b.add_argument('--version', type=int)
    b.add_argument('--min-version', type=int)
    b.add_argument('--min-package', type=int, default=0)
    b.add_argument('--parallel', type=int, default=8, choices=range(1, 9), metavar='1..8')
    b.add_argument('--channel', default='live')
    b.add_argument('--roots', default=','.join(DEFAULT_ROOTS))
    b.add_argument('--dry-run', action='store_true')
    b.add_argument('--with-single-spr', action='store_true',
                   help='ship a single .spr next to its shard set (for clients built before base patch 0048)')
    b.add_argument('--native-dir', help='folder with the package program files for the game launcher (O314)')
    b.add_argument('--native-package', type=int, help='package number of the native files')
    b.add_argument('--native-game', default='Chaos.exe')
    b.add_argument('--native-launcher', help='file name of the launcher itself in --native-dir')
    b.add_argument('--no-android', action='store_true', help='leave the "android" (phone data) section out')
    b.add_argument('--android-exclude', action='append', metavar='PREFIX',
                   help='a folder the phone does not download, e.g. data/images/streamer/ (repeatable; desktop-only art)')
    b.add_argument('--dev', action='store_true',
                   help='encrypt with the public development key (tests, allow_dev_key packages; never for players)')
    b.add_argument('--key-index', type=int, help=f'which key of {KEY_ENV} ("old,new"), 1-based')
    v = sub.add_parser('verify')
    v.add_argument('publish_dir')
    v.add_argument('--public', required=True)
    v.add_argument('--dev', action='store_true')
    v.add_argument('--key-index', type=int)
    u = sub.add_parser('unpack')
    u.add_argument('pack')
    u.add_argument('dest')
    u.add_argument('--dev', action='store_true')
    args = ap.parse_args(argv)
    if args.cmd == 'build' and not args.dry_run and not args.out:
        ap.error('build needs --out (or --dry-run)')
    if args.cmd == 'build' and (args.native_package is not None or args.native_launcher) and not args.native_dir:
        ap.error('--native-package and --native-launcher need --native-dir')
    if args.cmd == 'build' and not re.fullmatch(r'[a-z0-9-]{1,32}', args.channel):
        ap.error('--channel: lowercase letters, digits and dashes')
    return {'keygen': keygen, 'pubkey': pubkey, 'build': build, 'verify': verify, 'unpack': unpack}[args.cmd](args)


if __name__ == '__main__':
    sys.exit(main())
