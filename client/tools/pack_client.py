#!/usr/bin/env python3
"""Build the single encrypted client pack (chaos.pack) that the Cinders of Chaos client ships beside the exe.

  python3 -I client/tools/pack_client.py build  GAME_DIR  OUT.pack  [--key-env CHAOS_CLIENT_KEY | --key HEX]
  python3 -I client/tools/pack_client.py unpack OUT.pack  DEST_DIR [--key-env ... | --key ...]
  python3 -I client/tools/pack_client.py verify OUT.pack  GAME_DIR [--key-env ... | --key ...]

The pack is a deterministic store-only ZIP of the assembled client tree (init.lua, data/, modules/, mods/, layouts/),
compressed as one zlib stream (level 9) and encrypted as one blob with AES-256-GCM (format version 2; compressing first
keeps the download near the size of a plain zip, encrypted bytes do not compress). The key is derived with HKDF-SHA256
from the client guard build secret CHAOS_CLIENT_KEY (client/BASE.md "Client guard"); without the secret the public
DEVELOPMENT key is used and the pack is marked dev. The engine streams it through AES-256-GCM and inflate with the same
key into one buffer of the ZIP's size (src/framework/util/chaospack.h, base patch 0102) and mounts it from memory, so
modules keep reading files through g_resources unchanged. This deters copying; it does not stop a determined reverse
engineer (the key is in the binary, obfuscated the way chaosguard_key.h is).

Format: header (28 bytes: magic "CHPK", version 2, flags with the development-key bit, 2 reserved, 12-byte nonce, the
UNCOMPRESSED ZIP length as u64 little endian; it is the GCM additional data) | AES-256-GCM(zlib stream) | 16-byte tag.

Determinism: the ZIP entries are sorted, stored (not deflated) with a fixed timestamp, the zlib level is fixed and the
GCM nonce is HMAC-SHA256 of the zlib stream (the bytes GCM encrypts, so two different ciphertexts never share a nonce
even if another zlib build compresses differently), so the same tree and key always give the same bytes with one zlib
build. The members stay stored so PhysFS reads them straight from the mounted buffer. Writable per-user files
(config.otml, the updater tree, logs, screenshots) are never packed; they live in the user write directory.
"""
import argparse
import hashlib
import hmac
import io
import os
import struct
import sys
import zipfile
import zlib

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

MAGIC = b"CHPK"
VERSION = 2  # 2: zlib stream of the ZIP, then AES-256-GCM. Version 1 (store-only, never released) is refused.
HEADER_LEN = 28  # magic(4) ver(1) flags(1) reserved(2) nonce(12) plaintext_len(8) (the uncompressed ZIP length)
TAG_LEN = 16
NONCE_LEN = 12
FLAG_DEV = 0x01
ZLIB_LEVEL = 9
MAX_RATIO = 1032  # deflate never expands more than this; the engine refuses a header that claims more

# The public development key, byte-for-byte the CMake default (src/client/CMakeLists.txt, base patch 0035): the bytes
# of "DEV-KEY-cinders-of-chaos-UNSAFE!". A build with no CHAOS_CLIENT_KEY uses it, and so does the pack; a production
# server refuses such a client, so a dev pack is clearly a test artefact.
DEV_KEY_HEX = "4445562d4b45592d63696e646572732d6f662d6368616f732d554e5341464521"

# HKDF context, byte-identical in the engine (src/framework/util/chaospack.h).
HKDF_SALT = b"CindersOfChaos/pack/v1"
INFO_ENC = b"chaos-pack-aes-256-gcm"
INFO_NONCE = b"chaos-pack-nonce"

# The logical top-level names packed, in the order init.lua loads them. Anything else in the tree is left out on
# purpose; pass --extra to add a name.
PACK_ROOTS = ("init.lua", "data", "layouts", "modules", "mods")

# Never packed: per-user writable state belongs in the write directory, not in the read-only pack.
EXCLUDE_NAMES = {"config.otml", "chaos_update"}
EXCLUDE_SUFFIX = (".log", ".dmp", ".part", ".rollback", ".tmp", ".bak")


def _hkdf_sha256(ikm, salt, info, length):
    """RFC 5869 HKDF-SHA256 (extract + expand); matches the engine's manual HKDF in chaospack.h."""
    prk = hmac.new(salt, ikm, hashlib.sha256).digest()
    okm = b""
    t = b""
    counter = 1
    while len(okm) < length:
        t = hmac.new(prk, t + info + bytes([counter]), hashlib.sha256).digest()
        okm += t
        counter += 1
    return okm[:length]


def derive_keys(client_key):
    """client_key: 32 raw bytes. Returns (enc_key 32 bytes, nonce_key 32 bytes)."""
    if len(client_key) != 32:
        raise ValueError("client key must be 32 bytes")
    enc_key = _hkdf_sha256(client_key, HKDF_SALT, INFO_ENC, 32)
    nonce_key = _hkdf_sha256(client_key, HKDF_SALT, INFO_NONCE, 32)
    return enc_key, nonce_key


def _resolve_key(args):
    hexkey = None
    if args.key:
        hexkey = args.key.strip().lower()
    elif args.key_env:
        hexkey = (os.environ.get(args.key_env) or "").strip().lower()
    is_dev = False
    if not hexkey:
        hexkey = DEV_KEY_HEX
        is_dev = True
    if len(hexkey) != 64 or any(c not in "0123456789abcdef" for c in hexkey):
        sys.exit("client key must be 64 hex digits (openssl rand -hex 32)")
    return bytes.fromhex(hexkey), is_dev


def build_zip(game_dir, extra=()):
    """Deterministic store-only ZIP of the packed roots. Returns the ZIP bytes."""
    entries = []
    roots = list(PACK_ROOTS) + list(extra)
    for root in roots:
        path = os.path.join(game_dir, root)
        if os.path.isfile(path):
            entries.append((root, path))
        elif os.path.isdir(path):
            for dirpath, dirnames, filenames in os.walk(path):
                dirnames.sort()
                # prune excluded subtrees (the updater's chaos_update/ never gets packed)
                dirnames[:] = [d for d in dirnames if d not in EXCLUDE_NAMES]
                for name in sorted(filenames):
                    if name in EXCLUDE_NAMES or name.endswith(EXCLUDE_SUFFIX):
                        continue
                    full = os.path.join(dirpath, name)
                    arc = os.path.relpath(full, game_dir).replace(os.sep, "/")
                    entries.append((arc, full))
    entries.sort(key=lambda e: e[0])

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_STORED) as zf:
        for arc, full in entries:
            with open(full, "rb") as fh:
                data = fh.read()
            info = zipfile.ZipInfo(arc, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_STORED
            info.external_attr = 0o644 << 16
            zf.writestr(info, data)
    return buf.getvalue()


def encrypt_pack(plaintext, client_key, is_dev=False):
    """plaintext (the ZIP) -> pack: zlib level 9, nonce = HMAC(nonce key, the zlib stream), AES-256-GCM."""
    enc_key, nonce_key = derive_keys(client_key)
    body = zlib.compress(plaintext, ZLIB_LEVEL)
    nonce = hmac.new(nonce_key, body, hashlib.sha256).digest()[:NONCE_LEN]
    flags = FLAG_DEV if is_dev else 0
    header = (MAGIC + bytes([VERSION, flags]) + b"\x00\x00" + nonce +
              struct.pack("<Q", len(plaintext)))
    assert len(header) == HEADER_LEN
    ct_and_tag = AESGCM(enc_key).encrypt(nonce, body, header)
    return header + ct_and_tag


def inflate_exact(body, length):
    """The zlib stream body -> exactly `length` bytes; ValueError when it is longer, shorter, has trailing bytes or is
    not one complete zlib stream (the engine's checks)."""
    d = zlib.decompressobj()
    try:
        out = d.decompress(body, length + 1)
    except zlib.error as e:
        raise ValueError("bad zlib stream: %s" % e) from None
    if not d.eof or d.unconsumed_tail or d.unused_data or len(out) != length:
        raise ValueError("zlib stream does not end at the declared length")
    return out


def decrypt_pack(pack, client_key):
    if len(pack) < HEADER_LEN + TAG_LEN:
        raise ValueError("pack too small")
    if pack[0:4] != MAGIC:
        raise ValueError("bad magic")
    if pack[4] != VERSION:
        raise ValueError("unsupported pack version %d" % pack[4])
    nonce = pack[8:20]
    plaintext_len = struct.unpack("<Q", pack[20:28])[0]
    header = pack[0:HEADER_LEN]
    ct_and_tag = pack[HEADER_LEN:]
    enc_key, _ = derive_keys(client_key)
    if plaintext_len > (len(ct_and_tag) - TAG_LEN) * MAX_RATIO + 1024:
        raise ValueError("length mismatch")
    body = AESGCM(enc_key).decrypt(nonce, ct_and_tag, header)  # authenticated before it is inflated
    return inflate_exact(body, plaintext_len)


def _cmd_build(args):
    key, is_dev = _resolve_key(args)
    zip_bytes = build_zip(args.game_dir, extra=args.extra or ())
    pack = encrypt_pack(zip_bytes, key, is_dev=is_dev)
    tmp = args.out + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(pack)
    os.replace(tmp, args.out)
    digest = hashlib.sha256(pack).hexdigest()
    print("%s: %d bytes (ZIP %d bytes), %s key, sha256 %s" %
          (args.out, len(pack), len(zip_bytes), "DEVELOPMENT" if is_dev else "build", digest))


def _cmd_unpack(args):
    key, _ = _resolve_key(args)
    with open(args.pack, "rb") as fh:
        plaintext = decrypt_pack(fh.read(), key)
    with zipfile.ZipFile(io.BytesIO(plaintext)) as zf:
        zf.extractall(args.dest)
    print("unpacked to %s" % args.dest)


def _cmd_verify(args):
    key, _ = _resolve_key(args)
    with open(args.pack, "rb") as fh:
        plaintext = decrypt_pack(fh.read(), key)
    want = build_zip(args.game_dir, extra=args.extra or ())
    if plaintext != want:
        sys.exit("pack does not match the tree (not deterministic, or tree changed)")
    print("ok: pack decrypts and matches %s" % args.game_dir)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    def add_key(p):
        p.add_argument("--key", help="client key, 64 hex digits (avoid on a shared machine)")
        p.add_argument("--key-env", default="CHAOS_CLIENT_KEY", help="env var holding the key (default CHAOS_CLIENT_KEY)")
        p.add_argument("--extra", action="append", help="extra top-level name to include")

    b = sub.add_parser("build", help="pack GAME_DIR into OUT.pack")
    b.add_argument("game_dir")
    b.add_argument("out")
    add_key(b)
    b.set_defaults(func=_cmd_build)

    u = sub.add_parser("unpack", help="decrypt OUT.pack into DEST_DIR")
    u.add_argument("pack")
    u.add_argument("dest")
    add_key(u)
    u.set_defaults(func=_cmd_unpack)

    v = sub.add_parser("verify", help="check OUT.pack decrypts and equals GAME_DIR")
    v.add_argument("pack")
    v.add_argument("game_dir")
    add_key(v)
    v.set_defaults(func=_cmd_verify)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
