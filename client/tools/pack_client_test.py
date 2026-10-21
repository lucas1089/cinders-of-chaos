#!/usr/bin/env python3
"""Tests for the client pack (client/tools/pack_client.py, format version 2: zlib then AES-256-GCM): a synthetic tree
pack/unpack round trip, compression, determinism, wrong-key failure, tamper and truncation detection, the zlib length
checks, plus the fixed cross-language vector that client/tools/chaospack_test.cpp (the engine's chaospack.h) checks
byte for byte. Run with python3 -I; CI (.github/workflows/ci.yml)."""
import hashlib
import hmac
import io
import os
import shutil
import struct
import sys
import tempfile
import zipfile
import zlib

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pack_client as P  # noqa: E402

FAIL = 0


def check(cond, msg):
    global FAIL
    if not cond:
        print("FAIL:", msg)
        FAIL += 1


def make_tree(root):
    os.makedirs(os.path.join(root, "modules", "game_x"))
    os.makedirs(os.path.join(root, "data", "images"))
    os.makedirs(os.path.join(root, "chaos_update", "files"))  # must be excluded
    with open(os.path.join(root, "init.lua"), "w") as f:
        f.write("APP_NAME = 'CindersOfChaos'\n")
    with open(os.path.join(root, "modules", "game_x", "x.lua"), "w") as f:
        f.write("return 1\n")
    with open(os.path.join(root, "data", "images", "a.png"), "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + b"pixels" * 100)
    with open(os.path.join(root, "config.otml"), "w") as f:  # must be excluded
        f.write("secret\n")
    with open(os.path.join(root, "modules", "game_x", "x.log"), "w") as f:  # excluded
        f.write("log\n")


def test_roundtrip_and_exclusions():
    root = tempfile.mkdtemp()
    try:
        make_tree(root)
        key = bytes(range(32))
        zip_bytes = P.build_zip(root)
        names = set(zipfile.ZipFile(io.BytesIO(zip_bytes)).namelist())
        check("init.lua" in names, "init.lua packed")
        check("modules/game_x/x.lua" in names, "module packed")
        check("data/images/a.png" in names, "data packed")
        check("config.otml" not in names, "config.otml excluded")
        check(not any(n.startswith("chaos_update") for n in names), "chaos_update excluded")
        check(not any(n.endswith(".log") for n in names), ".log excluded")

        pack = P.encrypt_pack(zip_bytes, key)
        check(pack[4] == 2, "format version 2")
        check(struct.unpack("<Q", pack[20:28])[0] == len(zip_bytes), "header length is the uncompressed ZIP length")
        check(len(pack) < len(zip_bytes), "compressed: the pack is smaller than the store-only ZIP")
        back = P.decrypt_pack(pack, key)
        check(back == zip_bytes, "decrypt round trip")

        dest = tempfile.mkdtemp()
        try:
            with zipfile.ZipFile(io.BytesIO(back)) as zf:
                zf.extractall(dest)
            with open(os.path.join(dest, "modules", "game_x", "x.lua")) as f:
                check(f.read() == "return 1\n", "unpacked file content")
        finally:
            shutil.rmtree(dest)
    finally:
        shutil.rmtree(root)


def test_determinism():
    root = tempfile.mkdtemp()
    try:
        make_tree(root)
        key = bytes(range(32))
        a = P.encrypt_pack(P.build_zip(root), key)
        b = P.encrypt_pack(P.build_zip(root), key)
        check(a == b, "same tree + key -> same bytes")
    finally:
        shutil.rmtree(root)


def test_wrong_key():
    data = b"hello cinders" * 50
    pack = P.encrypt_pack(data, bytes(range(32)))
    other = bytes(range(1, 33))
    try:
        P.decrypt_pack(pack, other)
        check(False, "wrong key should fail")
    except Exception:
        check(True, "wrong key fails")


def fails(pack, key, msg):
    try:
        P.decrypt_pack(bytes(pack), key)
        check(False, msg + " should fail")
    except Exception:
        pass


def test_tamper():
    data = b"hello cinders" * 50 + os.urandom(300)
    key = bytes(range(32))
    pack = P.encrypt_pack(data, key)
    # every header field (magic, version, flags, reserved, nonce, length), the body and the tag
    for at in (0, 4, 5, 6, 9, 20, 21, 27, P.HEADER_LEN, P.HEADER_LEN + 5, len(pack) - P.TAG_LEN - 1, len(pack) - 1):
        bad = bytearray(pack)
        bad[at] ^= 0x01
        fails(bad, key, "flipped byte %d" % at)
    for cut in (1, P.TAG_LEN, P.TAG_LEN + 1, len(pack) - P.HEADER_LEN):
        fails(pack[:-cut], key, "truncated by %d" % cut)
    fails(pack + b"\0", key, "a trailing byte")


def seal(header_len_value, body, key, version=P.VERSION):
    """an authentic pack around any body (so only the zlib / length checks can refuse it)"""
    enc_key, nonce_key = P.derive_keys(key)
    nonce = hmac.new(nonce_key, body, hashlib.sha256).digest()[:P.NONCE_LEN]
    header = P.MAGIC + bytes([version, 0]) + b"\x00\x00" + nonce + struct.pack("<Q", header_len_value)
    return header + AESGCM(enc_key).encrypt(nonce, body, header)


def test_length_checks():
    key = bytes(range(32))
    data = b"cinders " * 1000
    z = zlib.compress(data, 9)
    check(P.decrypt_pack(seal(len(data), z, key), key) == data, "sealed helper round trip")
    fails(seal(len(data) - 1, z, key), key, "longer than the header says")
    fails(seal(len(data) + 1, z, key), key, "shorter than the header says")
    fails(seal(len(data), z + b"x", key), key, "bytes after the zlib stream")
    fails(seal(len(data), z[:-1], key), key, "zlib stream cut short")
    fails(seal(len(data), data, key), key, "not a zlib stream")
    fails(seal(len(data), z, key, version=1), key, "version 1 (store-only) is refused")
    fails(seal(1 << 40, z, key), key, "a length beyond the deflate ratio")


# The cross-language vector: key = 00..1f, plaintext "cinders-of-chaos " * 8 (136 bytes, 56 compressed).
# chaospack_test.cpp asserts the same hex strings and builds the same pack with zlib's compress2 at level 9.
VECTOR_ENC_KEY = "8664f864be53d89bd9681ba75531422d12fb7458f0e1daca98980079154470ab"
VECTOR_NONCE = "a4f05f4f646c80674642f216"
VECTOR_PACK = ("4348504b02000000a4f05f4f646c80674642f2168800000000000000"
               "2adfd565c2ccbec47d45ae8bed629eb494db35d0f392e139d1ea224a73a1abe379728e73d0750f8aa8a6c21e")


def test_fixed_vector():
    key = bytes(range(32))
    plaintext = b"cinders-of-chaos " * 8
    pack = P.encrypt_pack(plaintext, key)
    enc_key, nonce_key = P.derive_keys(key)
    check(enc_key.hex() == VECTOR_ENC_KEY, "fixed vector: enc key")
    check(pack[8:20].hex() == VECTOR_NONCE, "fixed vector: nonce (HMAC of the zlib stream)")
    check(pack.hex() == VECTOR_PACK, "fixed vector: pack bytes (zlib %s)" % zlib.ZLIB_RUNTIME_VERSION)
    check(P.decrypt_pack(bytes.fromhex(VECTOR_PACK), key) == plaintext, "fixed vector decrypts")


def main():
    test_roundtrip_and_exclusions()
    test_determinism()
    test_wrong_key()
    test_tamper()
    test_length_checks()
    test_fixed_vector()
    if FAIL:
        print("%d check(s) failed" % FAIL)
        sys.exit(1)
    print("pack_client_test: all checks passed")


if __name__ == "__main__":
    main()
