#!/usr/bin/env python3
"""Cinders of Chaos Unity client channel (ROADMAP O433 phase 16, unity/README.md "Shipping the Unity client").

The Unity Windows player is a folder tree (ChaosUnity.exe, UnityPlayer.dll, ChaosUnity_Data/..., MonoBleedingEdge/...).
The game launcher (launcher/) installs it into a folder of its own next to the main client, through the same signed
manifest, the same verification and the same swap code. Only the file layout differs: the "native" section of this
channel lists relative paths with sub-folders ("layout": "tree"), the main client's lists plain file names.

  pack     BUILD_DIR --out ZIP --package N [--game ChaosUnity.exe]
           CI side (.github/workflows/unity-prototype.yml): hashes the player folder, checks every path against the rules
           below and writes ZIP with the files at its root plus unity_build.json: the file list (path, SHA-256, size) in
           the shape of the manifest's "native" section. Not signed: the key never leaves the VPS.
  build    DIR --out PUBLISH_DIR --key PATH [--version N]
           VPS side (server/deploy/publish_client_update.sh --unity): DIR is an extracted ZIP. Hashes the files again,
           refuses the build when they differ from unity_build.json (a damaged or changed download), copies them as PLAIN
           blobs to PUBLISH_DIR/native/<sha[:2]>/<sha> and writes PUBLISH_DIR/manifest.json signed with the update key,
           last. Same envelope and key as the main client's manifest, in its own folder (updates/unity). The Unity
           build is public client code (no secret in it), so its blobs are plain like the main client's native files.
  verify   PUBLISH_DIR --public HEX
           Signature, payload rules and the size and SHA-256 of every blob.

The sprite pair (ROADMAP O433 phase 17, unity/README.md "Sprite pair"): a Unity build that carries the client guard key
(pack --embed-client-key, the workflow input embed_client_key) can open the main client's encrypted update blobs, so build
--pair-from LIVE_DIR (the main client's published updates/live folder) adds the sprite pair to the channel as those same
blobs: data/things/<n>/Tibia.dat, Tibia.sprshards and the Tibia.NNN.spr shards, copied byte for byte (same encryption, same key,
nothing is decrypted or re-encrypted) to things_enc/<name>.chub. The live manifest's signature is checked first, then each blob's
size, SHA-256 and CHUB header (a development-key blob is refused); with CHAOS_CLIENT_KEY in the environment each blob is also
decrypted and compared with the signed plain hash and the shard index. A package built without the key is a DEV package: it is
published with "dev": true in its manifest (the launcher does not offer it to players) and gets no pair, since it could not open it.

Rules (the launcher refuses the same, launcher/src/manifest.rs `check_tree_path`): at most TREE_MAX_FILES files and
TREE_MAX_DEPTH folders deep; each name 1 to 96 characters of letters, digits and . _ - and space, starting with a
letter or digit, not ending in a dot or space, no Windows device name; no two paths that differ only in case; no path that
is also a folder; at most TREE_MAX_SIZE bytes a file; .exe only in the root folder; script and shortcut endings
(TREE_DENIED_EXT) never. Links and special files are refused. Folders Unity leaves beside a build for its own use
(*_BurstDebugInformation_DoNotShip, *_BackUpThisFolder_ButDontShipItWithYourGame) and .pdb files are left out.
"""
import argparse, datetime, json, os, re, shutil, sys, tempfile, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_update_manifest as mum  # noqa: E402

CHANNEL = 'unity'
BUILD_FILE = 'unity_build.json'
LAYOUT = 'tree'
DEFAULT_GAME = 'ChaosUnity.exe'
TREE_MAX_FILES = 4096
TREE_MAX_DEPTH = 12
TREE_MAX_SIZE = mum.NATIVE_MAX_FILE_SIZE
TREE_DENIED_EXT = {'bat', 'cmd', 'com', 'ps1', 'vbs', 'msi', 'scr', 'lnk', 'hta', 'wsf', 'reg', 'cpl', 'pif', 'jar'}
SEGMENT = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._ -]{0,95}$')
LEFT_OUT_DIR = re.compile(r'(_BurstDebugInformation_DoNotShip|_BackUpThisFolder_ButDontShipItWithYourGame)$')
LEFT_OUT_EXT = {'pdb'}
HEX64 = re.compile(r'^[0-9a-f]{64}$')
PAIR_DIR = 'things_enc'       # Core/ThingsPair.cs PairLocator.BlobDir
PAIR_EXT = '.chub'            # Core/ThingsPair.cs PairLocator.BlobExt
PAIR_FILE = re.compile(r'^data/things/(\d+)/(Tibia\.(?:dat|sprshards|\d{3}\.spr))$')
CHUB_MAGIC, CHUB_VERSION, CHUB_HEADER = b'CHUB', 1, 28


def check_tree_path(path):
    """None when the launcher accepts the relative path of a file of the Unity player, else the reason."""
    if not isinstance(path, str) or not path or len(path) > 240:
        return 'bad path'
    parts = path.split('/')
    if len(parts) > TREE_MAX_DEPTH:
        return 'too deep'
    for p in parts:
        if not SEGMENT.match(p) or p.endswith('.') or p.endswith(' '):
            return 'bad name ' + repr(p)
        if p.lower().split('.')[0].strip() in mum.WINDOWS_RESERVED:
            return 'device name'
    ext = parts[-1].lower().rsplit('.', 1)[1] if '.' in parts[-1] else ''
    if ext in TREE_DENIED_EXT:
        return 'ending .' + ext + ' is never shipped'
    if ext == 'exe' and len(parts) > 1:
        return '.exe only in the root folder'
    return None


def check_tree_native(n):
    """None when the launcher accepts the decoded "native" section of the unity channel."""
    if not isinstance(n, dict):
        return 'native is not an object'
    if not isinstance(n.get('package'), int) or n['package'] < 0:
        return 'native: bad package'
    if n.get('files_url') != mum.NATIVE_DIR + '/':
        return 'native: bad files_url'
    if n.get('layout') != LAYOUT:
        return 'native: layout is not tree'
    if 'launcher' in n:
        return 'native: the unity channel has no launcher entry'
    if 'dev' in n and not isinstance(n['dev'], bool):
        return 'native: dev is not a boolean'
    files = n.get('files')
    if not isinstance(files, list) or not files or len(files) > TREE_MAX_FILES:
        return 'native: bad file list'
    names = set()
    for f in files:
        if not isinstance(f, dict):
            return 'native: bad file entry'
        why = check_tree_path(f.get('path'))
        if why:
            return f'native: refused path {f.get("path")!r}: {why}'
        low = f['path'].lower()
        if low in names:
            return 'native: duplicate path ' + f['path']
        names.add(low)
        if not HEX64.match(str(f.get('sha256'))):
            return 'native: bad sha256 for ' + f['path']
        if not isinstance(f.get('size'), int) or not 0 <= f['size'] <= TREE_MAX_SIZE:
            return 'native: bad size for ' + f['path']
    for low in names:
        parts = low.split('/')
        for i in range(1, len(parts)):
            if '/'.join(parts[:i]) in names:
                return 'native: ' + low + ' is under a path that is also a file'
    game = n.get('game')
    if mum.check_native_name(game) or not game.lower().endswith('.exe') or game.lower() not in names:
        return 'native: game is not an .exe of the root folder'
    return None


def check_payload(m):
    if not isinstance(m, dict):
        return 'payload is not a JSON object'
    if m.get('format') != 1:
        return 'unknown payload format'
    if m.get('product') != mum.PRODUCT:
        return 'manifest of another product'
    if m.get('channel') != CHANNEL:
        return 'not a unity channel manifest'
    if not isinstance(m.get('version'), int) or m['version'] < 1:
        return 'bad version'
    if m.get('files') != []:
        return 'the unity channel has no in-game updater files'
    return check_tree_native(m.get('native'))


def make_native(entries, package, game, dev=None):
    """dev None leaves the flag out (the file list of unity_build.json); a published manifest says True or False: a DEV package
    (built without the client key) is not offered to players by the launcher."""
    n = {'package': package, 'game': game, 'files_url': mum.NATIVE_DIR + '/', 'layout': LAYOUT,
         'files': [{'path': p, 'sha256': h, 'size': s} for p, h, s in entries]}
    if dev is not None:
        n['dev'] = bool(dev)
    return n


def collect_tree(root, skip=()):
    """([(relative path, abspath)] sorted, [problems]) of a player folder."""
    files, problems = [], []
    root = os.path.abspath(root)
    for dirpath, dirnames, names in os.walk(root):
        keep = []
        for d in sorted(dirnames):
            full = os.path.join(dirpath, d)
            if LEFT_OUT_DIR.search(d):
                continue
            if os.path.islink(full):
                problems.append(os.path.relpath(full, root).replace(os.sep, '/') + ': a link')
                continue
            keep.append(d)
        dirnames[:] = keep
        for name in sorted(names):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, root).replace(os.sep, '/')
            if rel in skip or name.lower().rsplit('.', 1)[-1] in LEFT_OUT_EXT and '.' in name:
                continue
            if os.path.islink(full) or not os.path.isfile(full):
                problems.append(rel + ': not a plain file')
                continue
            why = check_tree_path(rel)
            if why:
                problems.append(f'{rel}: {why}')
                continue
            files.append((rel, full))
    files.sort()
    return files, problems


def hash_tree(root, skip=()):
    """([(path, sha256, size)], {sha256: abspath}) or exits with the problems."""
    files, problems = collect_tree(root, skip)
    if problems:
        for p in problems[:50]:
            print('refused:', p, file=sys.stderr)
        sys.exit(f'{len(problems)} file(s) the launcher would refuse')
    if not files:
        sys.exit(f'{root}: no files')
    entries, src = [], {}
    for rel, full in files:
        h = mum.sha256_file(full)
        entries.append((rel, h, os.path.getsize(full)))
        src.setdefault(h, full)
    return entries, src


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def pack(args):
    root = os.path.abspath(args.build_dir)
    if not os.path.isdir(root):
        sys.exit(f'{root}: not a folder')
    entries, _ = hash_tree(root, skip=(BUILD_FILE,))
    native = make_native(entries, args.package, args.game)
    err = check_tree_native(native)
    if err:
        sys.exit('refused: ' + err)
    # a boolean only, never the key: whether the build carries CHAOS_CLIENT_KEY (the workflow input embed_client_key)
    info = {'format': 1, 'kind': 'cinders-unity-build', 'created': now(), 'embed_client_key': bool(args.embed_client_key),
            'native': native}
    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
    tmp = out + '.tmp'
    with zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        z.writestr(BUILD_FILE, json.dumps(info, indent=1, sort_keys=True) + '\n')
        for p, _, _ in entries:
            z.write(os.path.join(root, *p.split('/')), p)
    os.replace(tmp, out)
    total = sum(s for _, _, s in entries)
    print(f'packed {len(entries)} files ({total} bytes) as {out}; package {args.package}, game {args.game}; '
          + ('KEYED: the client key is inside this build (embed_client_key), it can open the sprite pair blobs' if args.embed_client_key
             else 'DEV package: no client key inside, the launcher will not offer it to players'))
    return 0


def read_build_info(root):
    try:
        info = json.load(open(os.path.join(root, BUILD_FILE), encoding='utf-8'))
    except (OSError, ValueError) as e:
        sys.exit(f'{BUILD_FILE}: {e} (is this a Unity client zip made by the workflow?)')
    if not isinstance(info, dict) or info.get('format') != 1 or info.get('kind') != 'cinders-unity-build':
        sys.exit(f'{BUILD_FILE}: not a Unity build manifest')
    err = check_tree_native(info.get('native'))
    if err:
        sys.exit(f'{BUILD_FILE}: {err}')
    if 'embed_client_key' in info and not isinstance(info['embed_client_key'], bool):
        sys.exit(f'{BUILD_FILE}: embed_client_key is not a boolean')
    return info


def previous_version(out):
    try:
        env = json.load(open(os.path.join(out, 'manifest.json'), encoding='utf-8'))
        return json.loads(env['payload'])['version']
    except (OSError, ValueError, KeyError, TypeError):
        return 0


def read_live_pair(live_dir, public):
    """The sprite pair of the main client's published update (LIVE_DIR = updates/live) as Unity channel entries:
    ([(things_enc/<name>.chub, blob sha256, blob size)], {blob sha256: abspath of the blob}, text for the log).
    Exits with the reason when the live manifest is not signed by `public`, has no complete pair, or a blob is wrong. The blobs are
    NOT decrypted here unless CHAOS_CLIENT_KEY is set; then each one is checked against the signed plain hash and the shard index."""
    live = os.path.abspath(live_dir)
    try:
        env = json.load(open(os.path.join(live, 'manifest.json'), encoding='utf-8'))
    except (OSError, ValueError) as e:
        sys.exit(f'--pair-from {live}: manifest.json: {e}')
    if env.get('format') != mum.FORMAT or not isinstance(env.get('payload'), str):
        sys.exit(f'--pair-from {live}: not a Cinders of Chaos update envelope')
    if not re.fullmatch(r'[0-9a-f]{128}', str(env.get('signature'))) or \
            not mum.verify_sig(public, env['payload'].encode('utf-8'), bytes.fromhex(env['signature'])):
        sys.exit(f'--pair-from {live}: the live manifest is not signed by this update key')
    m = json.loads(env['payload'])
    err = mum.check_payload(m)
    if err:
        sys.exit(f'--pair-from {live}: refused: {err}')
    by_dir = {}
    for f in m['files']:
        hit = PAIR_FILE.match(f['path'])
        if hit:
            by_dir.setdefault(int(hit.group(1)), {})[hit.group(2)] = f
    complete = sorted(v for v, fs in by_dir.items() if 'Tibia.dat' in fs and 'Tibia.sprshards' in fs)
    if not complete:
        sys.exit(f'--pair-from {live}: the live manifest holds no data/things/<n>/Tibia.dat with Tibia.sprshards '
                 '(publish the main client first; the Unity pair is the main client\'s shard set)')
    ver = complete[-1]
    fs = by_dir[ver]
    shards = sorted(n for n in fs if re.fullmatch(r'Tibia\.\d{3}\.spr', n))
    if not shards or shards != ['Tibia.%03d.spr' % i for i in range(len(shards))]:
        sys.exit(f'--pair-from {live}: the shards of data/things/{ver}/ are missing or have a gap: {shards[:3]}...')
    names = ['Tibia.dat', 'Tibia.sprshards'] + shards
    entries, src = [], {}
    for n in names:
        f = fs[n]
        blob = os.path.join(live, 'files', f['blob'][:2], f['blob'])
        if not os.path.isfile(blob) or os.path.getsize(blob) != f['blob_size'] or mum.sha256_file(blob) != f['blob']:
            sys.exit(f'--pair-from {live}: the blob of {n} is missing or changed')
        with open(blob, 'rb') as bf:
            head = bf.read(CHUB_HEADER)
        if len(head) < CHUB_HEADER or head[:4] != CHUB_MAGIC or head[4] != CHUB_VERSION:
            sys.exit(f'--pair-from {live}: the blob of {n} is not an encrypted update blob')
        if head[5] & 1:
            sys.exit(f'--pair-from {live}: the blob of {n} is encrypted with the DEVELOPMENT key (a test publish); '
                     'a keyed Unity build cannot open it')
        entries.append((f'{PAIR_DIR}/{n}{PAIR_EXT}', f['blob'], f['blob_size']))
        src[f['blob']] = blob
    checked = check_pair_content(live, fs, names)
    return entries, src, (f'sprite pair: data/things/{ver}/ ({len(names)} blobs, {sum(e[2] for e in entries)} bytes, copied as they are; '
                          + ('decrypted and checked against the signed hashes and the shard index' if checked
                             else 'ciphertext checked only: no CHAOS_CLIENT_KEY here') + ')')


def check_pair_content(live, fs, names):
    """With CHAOS_CLIENT_KEY: every pair blob decrypts to the signed plain hash, and the shard index lists exactly the shards,
    with their sizes and hashes. Returns False when there is no key (nothing checked), exits on a mismatch."""
    if not os.environ.get(mum.KEY_ENV, '').strip():
        return False
    uc = mum.crypt()
    keys = [k for _, k in mum.client_keys(False)]
    plain = {}
    index_text = None
    for n in names:
        f = fs[n]
        blob = os.path.join(live, 'files', f['blob'][:2], f['blob'])
        got = None
        for k in keys:
            try:
                if n == 'Tibia.sprshards':
                    with open(blob, 'rb') as bf:
                        index_text = uc.decrypt(bf.read(), k).decode('utf-8')
                got = uc.decrypt_file(blob, k)[1]
                break
            except uc.BlobError:
                continue
        if got is None:
            sys.exit(f'--pair-from {live}: no key of {mum.KEY_ENV} opens the blob of {n} (another build key, or a damaged file)')
        if got != f['sha256']:
            sys.exit(f'--pair-from {live}: the blob of {n} does not decrypt to the signed content')
        plain[n] = (got, f['size'])
    listed = {}
    for line in (index_text or '').splitlines():
        w = line.split()
        if w and w[0] == 'shard' and len(w) >= 6:
            listed[w[3]] = (int(w[4]), w[5])
    want = {n: (plain[n][1], plain[n][0]) for n in names if n.endswith('.spr')}
    if listed != want:
        sys.exit(f'--pair-from {live}: Tibia.sprshards does not describe the shard blobs (names, sizes, SHA-256)')
    return True


def build(args):
    root = os.path.abspath(args.dir)
    info = read_build_info(root)
    entries, src = hash_tree(root, skip=(BUILD_FILE,))
    listed = {(f['path'], f['sha256'], f['size']) for f in info['native']['files']}
    if listed != set(entries):
        extra = sorted({p for p, _, _ in entries} - {p for p, _, _ in listed})
        gone = sorted({p for p, _, _ in listed} - {p for p, _, _ in entries})
        sys.exit(f'the files do not match {BUILD_FILE} (damaged or changed download): '
                 f'{len(extra)} extra {extra[:3]}, {len(gone)} missing {gone[:3]}, '
                 f'{len(listed ^ set(entries))} entries differ')
    out = os.path.abspath(args.out)
    if mum.inside_this_repo(out):
        sys.exit(f'refused: {out} is inside the repository; publish to the website folder')
    key_path = args.key or os.environ.get('CHAOS_UPDATE_KEY')
    if not key_path:
        sys.exit('no private key: give --key PATH or set CHAOS_UPDATE_KEY to its path')
    seed = mum.read_seed(key_path)
    public = mum.public_from_seed(seed)
    prev = previous_version(out)
    version = args.version if args.version is not None else prev + 1
    if version < 1:
        sys.exit('--version must be 1 or more')
    if version <= prev:
        sys.exit(f'version {version} is not newer than the published {prev}; the launcher refuses older manifests')
    keyed = info.get('embed_client_key') is True
    src_all = dict(src)
    all_entries = list(entries)
    if args.pair_from:
        if keyed:
            pair, psrc, note = read_live_pair(args.pair_from, public)
            have = {p.lower() for p, _, _ in entries}
            clash = [p for p, _, _ in pair if p.lower() in have]
            if clash:
                sys.exit(f'the player folder already has {clash[0]}: the sprite pair needs the {PAIR_DIR}/ folder')
            all_entries += pair
            src_all.update(psrc)
            print(note)
        else:
            print('DEV package (unity_build.json: embed_client_key is not true): no sprite pair is added, a build without the '
                  'client key could not open it; its manifest says "dev": true and the launcher does not offer it to players')
    elif not keyed:
        print('DEV package (unity_build.json: embed_client_key is not true): its manifest says "dev": true and the launcher does not '
              'offer it to players')
    native = make_native(all_entries, info['native']['package'], info['native']['game'], dev=not keyed)
    payload = json.dumps({'format': 1, 'product': mum.PRODUCT, 'channel': CHANNEL, 'version': version,
                          'created': now(), 'min_package': 0, 'files': [], 'native': native},
                         sort_keys=True, separators=(',', ':'), ensure_ascii=True)
    err = check_payload(json.loads(payload))
    if err:
        sys.exit('internal: ' + err)
    os.makedirs(out, exist_ok=True)
    mum.publish_native(out, all_entries, src_all)  # blobs first, the manifest last
    signature = mum.sign(seed, payload.encode('ascii'))
    if not mum.verify_sig(public, payload.encode('ascii'), signature):
        sys.exit('internal: the new signature does not verify')
    fd, tmp = tempfile.mkstemp(dir=out, prefix='.manifest.')
    with os.fdopen(fd, 'w', encoding='ascii') as f:
        f.write(mum.make_envelope(payload, public.hex(), signature.hex()))
    os.chmod(tmp, 0o644)
    os.replace(tmp, os.path.join(out, 'manifest.json'))
    removed = mum.prune_blobs(os.path.join(out, mum.NATIVE_DIR), {h for _, h, _ in all_entries})
    total = sum(s for _, _, s in all_entries)
    print(f'published unity version {version} (was {prev}): {len(all_entries)} files ({len(all_entries) - len(entries)} of the sprite pair), '
          f'{total} bytes, package {native["package"]}, game {native["game"]}, {"KEYED" if keyed else "DEV (not offered to players)"}; '
          f'{removed} old file(s) removed; public key {public.hex()}')
    return 0


def verify(args):
    out = os.path.abspath(args.publish_dir)
    try:
        env = json.load(open(os.path.join(out, 'manifest.json'), encoding='utf-8'))
    except (OSError, ValueError) as e:
        sys.exit(f'manifest.json: {e}')
    if env.get('format') != mum.FORMAT or not isinstance(env.get('payload'), str):
        sys.exit('manifest.json: not a Cinders of Chaos update envelope')
    if not HEX64.match(args.public or ''):
        sys.exit('--public: 64 lowercase hex digits')
    if not re.fullmatch(r'[0-9a-f]{128}', str(env.get('signature'))):
        sys.exit('refused: the manifest is not signed')
    if not mum.verify_sig(bytes.fromhex(args.public), env['payload'].encode('utf-8'), bytes.fromhex(env['signature'])):
        sys.exit('refused: bad signature')
    m = json.loads(env['payload'])
    err = check_payload(m)
    if err:
        sys.exit('refused: ' + err)
    bad = 0
    for f in m['native']['files']:
        blob = mum.native_blob_path(out, f['sha256'])
        if not os.path.isfile(blob) or os.path.getsize(blob) != f['size'] or mum.sha256_file(blob) != f['sha256']:
            print('bad native file', f['path'], file=sys.stderr)
            bad += 1
    if bad:
        sys.exit(f'{bad} blob(s) missing or changed')
    n = m['native']
    pair = sum(1 for f in n['files'] if f['path'].startswith(PAIR_DIR + '/'))
    print(f'ok: unity version {m["version"]}, {len(n["files"])} files (package {n["package"]}, game {n["game"]}, '
          f'{"DEV" if n.get("dev") else "keyed"}, {pair} sprite pair blobs), signature good, every blob checked')
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('pack')
    p.add_argument('build_dir')
    p.add_argument('--out', required=True)
    p.add_argument('--package', type=int, required=True, help='the client build the player was built for')
    p.add_argument('--game', default=DEFAULT_GAME)
    p.add_argument('--embed-client-key', action='store_true',
                   help='the build carries the client guard key (workflow input embed_client_key); only a boolean is written')
    b = sub.add_parser('build')
    b.add_argument('dir')
    b.add_argument('--out', required=True)
    b.add_argument('--key')
    b.add_argument('--version', type=int)
    b.add_argument('--pair-from', metavar='LIVE_DIR', help='the main client\'s published updates/live folder: its sprite pair '
                   'is added as encrypted blobs (keyed builds only)')
    v = sub.add_parser('verify')
    v.add_argument('publish_dir')
    v.add_argument('--public', required=True)
    args = ap.parse_args(argv)
    if args.cmd == 'pack' and (args.package < 0 or mum.check_native_name(args.game)):
        ap.error('--package N (0 or more) and --game a plain .exe name')
    return {'pack': pack, 'build': build, 'verify': verify}[args.cmd](args)


if __name__ == '__main__':
    sys.exit(main())
