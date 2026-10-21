#!/usr/bin/env python3
"""Tests for the client pack (client/tools/pack_client.py): a synthetic tree pack/unpack round trip, determinism,
wrong-key failure and tamper detection, plus the fixed cross-language vector that client/tools/chaospack_test.cpp
(the engine's chaospack.h) checks against. Run with python3 -I; CI (.github/workflows/ci.yml)."""
import io
import os
import shutil
import sys
import tempfile
import zipfile

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


def test_tamper():
    data = b"hello cinders" * 50
    key = bytes(range(32))
    pack = bytearray(P.encrypt_pack(data, key))
    pack[P.HEADER_LEN + 5] ^= 0x01  # flip a ciphertext byte
    try:
        P.decrypt_pack(bytes(pack), key)
        check(False, "tampered ciphertext should fail")
    except Exception:
        check(True, "tampered ciphertext fails")
    pack2 = bytearray(P.encrypt_pack(data, key))
    pack2[5] ^= 0x01  # flip the flags byte (part of the AAD header)
    try:
        P.decrypt_pack(bytes(pack2), key)
        check(False, "tampered header should fail")
    except Exception:
        check(True, "tampered header fails")


def test_fixed_vector():
    # The cross-language vector: key = 00..1f, plaintext "cinders-of-chaos". chaospack_test.cpp asserts the same.
    key = bytes(range(32))
    plaintext = b"cinders-of-chaos"
    pack = P.encrypt_pack(plaintext, key)
    enc_key, nonce_key = P.derive_keys(key)
    # these hex strings are also hard-coded in chaospack_test.cpp
    print("VECTOR enc_key   =", enc_key.hex())
    print("VECTOR nonce     =", pack[8:20].hex())
    print("VECTOR pack      =", pack.hex())
    check(P.decrypt_pack(pack, key) == plaintext, "fixed vector round trip")


def main():
    test_roundtrip_and_exclusions()
    test_determinism()
    test_wrong_key()
    test_tamper()
    test_fixed_vector()
    if FAIL:
        print("%d check(s) failed" % FAIL)
        sys.exit(1)
    print("pack_client_test: all checks passed")


if __name__ == "__main__":
    main()
