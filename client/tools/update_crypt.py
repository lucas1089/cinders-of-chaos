#!/usr/bin/env python3
"""Cinders of Chaos encrypted update blobs (client/MANIFEST.md "Signed updater", client/BASE.md "Encrypted updates").

Every file the signed updater serves is one encrypted blob: the per-file variant of the chaos.pack format (base patch
0102, tools/pack_client.py) with its own magic and its own HKDF labels, so the update key is not the pack key:

    header (28 bytes) = magic "CHUB" | version 1 | flags (bit 0: development key) | 2 reserved | 12-byte nonce |
                        plaintext length (u64 little endian)
    blob              = header | AES-256-GCM(plaintext, additional data = header) | 16-byte tag

    enc key   = HKDF-SHA256(client key, salt "CindersOfChaos/update/v1", info "chaos-update-blob-aes-256-gcm")
    nonce key = HKDF-SHA256(client key, salt "CindersOfChaos/update/v1", info "chaos-update-blob-nonce")
    nonce     = HMAC-SHA256(nonce key, plaintext)[:12]

The client key is the client guard build secret CHAOS_CLIENT_KEY (64 hex digits; base patch 0035). The nonce comes
from the content, so one file always gives the same blob (content addressing and resumable downloads keep working)
and two different files never share a nonce. The engine reads the same bytes (src/framework/util/chaosblob.h, base
patch 0103; vectors in tools/chaosblob_test.cpp). Large files are handled in 8 MB blocks, never read whole.

Also streams chaos.pack itself (decrypt_file with PACK), so the publisher can unpack a packed client package without
holding the ~900 MB pack in memory twice.
"""
import hashlib
import hmac
import os
import struct

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

HEADER_LEN = 28
TAG_LEN = 16
NONCE_LEN = 12
OVERHEAD = HEADER_LEN + TAG_LEN
FLAG_DEV = 0x01
VERSION = 1
BLOCK = 8 * 1024 * 1024

# The public development key (the bytes of "DEV-KEY-cinders-of-chaos-UNSAFE!"), the same as pack_client.py and the
# CMake default of base patch 0035. Used only with --dev (tests); a production publish refuses to run without the key.
DEV_KEY_HEX = "4445562d4b45592d63696e646572732d6f662d6368616f732d554e5341464521"


class Format:
    def __init__(self, magic, salt, info_enc, info_nonce):
        self.magic, self.salt, self.info_enc, self.info_nonce = magic, salt, info_enc, info_nonce


# update blobs (this file's own format)
BLOB = Format(b"CHUB", b"CindersOfChaos/update/v1", b"chaos-update-blob-aes-256-gcm", b"chaos-update-blob-nonce")
# chaos.pack (base patch 0102), byte-identical to pack_client.py
PACK = Format(b"CHPK", b"CindersOfChaos/pack/v1", b"chaos-pack-aes-256-gcm", b"chaos-pack-nonce")


class BlobError(ValueError):
    pass


def hkdf_sha256(ikm, salt, info, length):
    """RFC 5869 HKDF-SHA256 (extract + expand)."""
    prk = hmac.new(salt, ikm, hashlib.sha256).digest()
    okm, t, counter = b"", b"", 1
    while len(okm) < length:
        t = hmac.new(prk, t + info + bytes([counter]), hashlib.sha256).digest()
        okm += t
        counter += 1
    return okm[:length]


def derive_keys(client_key, fmt=BLOB):
    if len(client_key) != 32:
        raise BlobError("client key must be 32 bytes")
    return (hkdf_sha256(client_key, fmt.salt, fmt.info_enc, 32),
            hkdf_sha256(client_key, fmt.salt, fmt.info_nonce, 32))


def parse_client_keys(text):
    """CHAOS_CLIENT_KEY as the game server holds it: one key, or "old,new" during a rotation. Returns [32-byte keys].
    The error never quotes the value."""
    keys = []
    for part in (text or "").split(","):
        part = part.strip().lower()
        if not part:
            continue
        if len(part) != 64 or any(c not in "0123456789abcdef" for c in part):
            raise BlobError("CHAOS_CLIENT_KEY: each key must be 64 hex digits (openssl rand -hex 32)")
        keys.append(bytes.fromhex(part))
    return keys


def _header(fmt, nonce, length, dev):
    return fmt.magic + bytes([VERSION, FLAG_DEV if dev else 0]) + b"\x00\x00" + nonce + struct.pack("<Q", length)


def parse_header(header, fmt=BLOB):
    """(flags, nonce, plaintext length) of a blob header; BlobError when it is not one."""
    if len(header) < HEADER_LEN or header[:4] != fmt.magic:
        raise BlobError("not an encrypted %s file" % fmt.magic.decode())
    if header[4] != VERSION:
        raise BlobError("unsupported version %d" % header[4])
    return header[5], header[8:20], struct.unpack("<Q", header[20:28])[0]


def encrypt(plaintext, client_key, dev=False, fmt=BLOB):
    enc_key, nonce_key = derive_keys(client_key, fmt)
    nonce = hmac.new(nonce_key, plaintext, hashlib.sha256).digest()[:NONCE_LEN]
    header = _header(fmt, nonce, len(plaintext), dev)
    e = Cipher(algorithms.AES(enc_key), modes.GCM(nonce)).encryptor()
    e.authenticate_additional_data(header)
    body = e.update(plaintext) + e.finalize()
    return header + body + e.tag


def decrypt(blob, client_key, fmt=BLOB):
    _, nonce, length = parse_header(blob, fmt)
    if len(blob) != HEADER_LEN + length + TAG_LEN:
        raise BlobError("length mismatch")
    enc_key, _ = derive_keys(client_key, fmt)
    d = Cipher(algorithms.AES(enc_key), modes.GCM(nonce, blob[-TAG_LEN:])).decryptor()
    d.authenticate_additional_data(blob[:HEADER_LEN])
    try:
        return d.update(blob[HEADER_LEN:-TAG_LEN]) + d.finalize()
    except InvalidTag:
        raise BlobError("wrong key or changed file") from None


def _blocks(f, n):
    while n > 0:
        b = f.read(min(BLOCK, n))
        if not b:
            raise BlobError("file shorter than its header says")
        n -= len(b)
        yield b


def encrypt_file(src, out, client_key, dev=False, fmt=BLOB):
    """Encrypts the file at src into the open binary file out, in blocks (two passes: the nonce is an HMAC of the
    content). Returns (sha256 hex of the written blob, its size)."""
    enc_key, nonce_key = derive_keys(client_key, fmt)
    size = os.path.getsize(src)
    mac = hmac.new(nonce_key, digestmod=hashlib.sha256)
    with open(src, "rb") as f:
        for b in _blocks(f, size):
            mac.update(b)
    nonce = mac.digest()[:NONCE_LEN]
    header = _header(fmt, nonce, size, dev)
    e = Cipher(algorithms.AES(enc_key), modes.GCM(nonce)).encryptor()
    e.authenticate_additional_data(header)
    h = hashlib.sha256(header)
    out.write(header)
    with open(src, "rb") as f:
        if os.path.getsize(src) != size:
            raise BlobError("%s changed while it was read" % src)
        for b in _blocks(f, size):
            c = e.update(b)
            h.update(c)
            out.write(c)
    c = e.finalize()
    h.update(c + e.tag)
    out.write(c + e.tag)
    return h.hexdigest(), size + OVERHEAD


def decrypt_file(path, client_key, out=None, fmt=BLOB):
    """Decrypts the blob at path in blocks; writes the plaintext to the open binary file out (when given). Returns
    (flags, sha256 hex of the plaintext). BlobError on a wrong key, a changed file or a bad header; out then holds
    unauthenticated bytes and must be thrown away."""
    with open(path, "rb") as f:
        header = f.read(HEADER_LEN)
        flags, nonce, length = parse_header(header, fmt)
        if os.path.getsize(path) != HEADER_LEN + length + TAG_LEN:
            raise BlobError("length mismatch")
        f.seek(HEADER_LEN + length)
        tag = f.read(TAG_LEN)
        f.seek(HEADER_LEN)
        enc_key, _ = derive_keys(client_key, fmt)
        d = Cipher(algorithms.AES(enc_key), modes.GCM(nonce, tag)).decryptor()
        d.authenticate_additional_data(header)
        h = hashlib.sha256()
        for b in _blocks(f, length):
            p = d.update(b)
            h.update(p)
            if out is not None:
                out.write(p)
        try:
            p = d.finalize()
        except InvalidTag:
            raise BlobError("wrong key or changed file") from None
        h.update(p)
        if out is not None:
            out.write(p)
    return flags, h.hexdigest()


def header_flags(path, fmt=BLOB):
    with open(path, "rb") as f:
        return parse_header(f.read(HEADER_LEN), fmt)[0]
