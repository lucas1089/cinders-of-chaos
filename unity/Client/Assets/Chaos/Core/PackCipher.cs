// The encrypted container of the main client, read by the Unity client (ROADMAP O433 phase 17, unity/README.md "Sprite pair").
//
// Ported from the main client's engine, not invented:
//   chaos.pack  client/base-patches/0102-client-encrypted-pack.patch, src/framework/util/chaospack.h (the new file in that patch):
//               header 28 bytes "CHPK" | version 2 | flags | 2 reserved | 12-byte nonce | u64 LE length of the UNCOMPRESSED ZIP;
//               body = AES-256-GCM(zlib stream of a store-only ZIP, additional data = header); then the 16-byte tag.
//   update blob client/base-patches/0103-encrypted-updates.patch, src/framework/util/chaosblob.h, and the writer client/tools/update_crypt.py:
//               header 28 bytes "CHUB" | version 1 | flags | 2 reserved | 12-byte nonce | u64 LE length;
//               body = AES-256-GCM(plaintext, additional data = header); then the tag.
//   keys        HKDF-SHA256 (RFC 5869) of the 32-byte client guard key, one salt and one info label per format (PackFormat below);
//               the nonce key only builds nonces when writing and is not needed to read.
// The client key is the guard key (ClientGuard, CHAOS_CLIENT_KEY): the same key the main client's exe carries.
// This deters copying and nothing more: the key sits in the build, as it does in the main client.
//
// AES-GCM is written out here (AES from System.Security.Cryptography in ECB mode builds the counter stream, GHASH is managed):
// AesGcm is not in the Mono of Unity 2022.3. Streaming, so a 30 MB shard or a 1 GB pack never needs a second copy.
// The tag is checked at the end and nothing is returned before it verified; every failure is a PackException that never
// quotes the key or a byte of the plaintext.
using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace Chaos.Core
{
    /// <summary>A pack or blob that cannot be read: wrong key, damaged or changed file, not a pack. The message names no secret.</summary>
    public sealed class PackException : Exception
    {
        public PackException(string message) : base(message) { }
    }

    /// <summary>One of the two container formats: magic, version and the HKDF labels (byte for byte as update_crypt.py).</summary>
    public sealed class PackFormat
    {
        public readonly string Magic;
        public readonly byte Version;
        public readonly string Salt, InfoEnc;
        public readonly bool Compressed;

        PackFormat(string magic, byte version, string salt, string infoEnc, bool compressed)
        {
            Magic = magic; Version = version; Salt = salt; InfoEnc = infoEnc; Compressed = compressed;
        }

        public const int HeaderLength = 28, NonceLength = 12, TagLength = 16;
        public const byte FlagDev = 0x01;
        /// <summary>chaospack.h MAX_PLAINTEXT and MAX_RATIO: a header that claims more is refused before anything is allocated.</summary>
        public const long MaxPlaintext = 16L * 1024 * 1024 * 1024;
        public const long MaxRatio = 1032;

        public static readonly PackFormat Pack = new PackFormat("CHPK", 2, "CindersOfChaos/pack/v1", "chaos-pack-aes-256-gcm", true);
        public static readonly PackFormat Blob = new PackFormat("CHUB", 1, "CindersOfChaos/update/v1", "chaos-update-blob-aes-256-gcm", false);

        /// <summary>The AES-256 key of the client key: HKDF-SHA256(key, salt, info, 32).</summary>
        public byte[] EncryptionKey(byte[] clientKey)
        {
            if (clientKey == null || clientKey.Length != 32) throw new PackException("the client key must be 32 bytes");
            return Hkdf(clientKey, Encoding.ASCII.GetBytes(Salt), Encoding.ASCII.GetBytes(InfoEnc), 32);
        }

        /// <summary>RFC 5869 HKDF-SHA256, extract and expand (the engine's manual version).</summary>
        public static byte[] Hkdf(byte[] ikm, byte[] salt, byte[] info, int length)
        {
            byte[] prk;
            using (var h = new HMACSHA256(salt)) prk = h.ComputeHash(ikm);
            var okm = new byte[length];
            byte[] t = new byte[0];
            int got = 0;
            byte counter = 1;
            using (var h = new HMACSHA256(prk))
            {
                while (got < length)
                {
                    var input = new byte[t.Length + info.Length + 1];
                    Buffer.BlockCopy(t, 0, input, 0, t.Length);
                    Buffer.BlockCopy(info, 0, input, t.Length, info.Length);
                    input[input.Length - 1] = counter++;
                    t = h.ComputeHash(input);
                    int n = Math.Min(t.Length, length - got);
                    Buffer.BlockCopy(t, 0, okm, got, n);
                    got += n;
                }
            }
            return okm;
        }

        /// <summary>The 28-byte header: flags, nonce, plaintext length. PackException when the bytes are not this format.</summary>
        public Header ParseHeader(byte[] h)
        {
            if (h == null || h.Length < HeaderLength) throw new PackException("not an encrypted " + Magic + " file");
            for (int i = 0; i < 4; i++) if (h[i] != Magic[i]) throw new PackException("not an encrypted " + Magic + " file");
            if (h[4] != Version) throw new PackException("unsupported " + Magic + " version " + h[4]);
            var nonce = new byte[NonceLength];
            Buffer.BlockCopy(h, 8, nonce, 0, NonceLength);
            ulong len = 0;
            for (int i = 7; i >= 0; i--) len = len << 8 | h[20 + i];
            if (len > (ulong)MaxPlaintext) throw new PackException("length mismatch");
            var raw = new byte[HeaderLength];
            Buffer.BlockCopy(h, 0, raw, 0, HeaderLength);
            return new Header { Flags = h[5], Nonce = nonce, PlainLength = (long)len, Raw = raw };
        }

        public sealed class Header
        {
            public byte Flags;
            public byte[] Nonce;
            public long PlainLength;
            public byte[] Raw;
            public bool DevKey => (Flags & FlagDev) != 0;
        }
    }

    /// <summary>AES-256-GCM decryption, 96-bit nonce, streamed in any chunk sizes: Update decrypts in place, Verify checks the tag.</summary>
    public sealed class GcmDecryptor : IDisposable
    {
        const int StreamBlocks = 256;
        readonly Aes aes;
        readonly ICryptoTransform ecb;
        readonly byte[] counter = new byte[16];
        readonly byte[] ek = new byte[16];          // AES_K(J0), masks the GHASH
        readonly ulong[] hh = new ulong[16], hl = new ulong[16];
        ulong yh, yl;                               // the GHASH state
        readonly byte[] pending = new byte[16];
        int pendingLen;
        readonly byte[] work = new byte[16];
        readonly byte[] stream = new byte[16 * StreamBlocks], ctrBlocks = new byte[16 * StreamBlocks];
        int streamPos = 16 * StreamBlocks;
        long aadLen, cipherLen;
        bool done;

        static readonly ulong[] Last4 = { 0x0000, 0x1c20, 0x3840, 0x2460, 0x7080, 0x6ca0, 0x48c0, 0x54e0, 0xe100, 0xfd20, 0xd940, 0xc560, 0x9180, 0x8da0, 0xa9c0, 0xb5e0 };

        public GcmDecryptor(byte[] key, byte[] nonce, byte[] aad)
        {
            if (key == null || key.Length != 32) throw new PackException("bad AES key size");
            if (nonce == null || nonce.Length != 12) throw new PackException("bad nonce size");
            aes = Aes.Create();
            aes.Mode = CipherMode.ECB;
            aes.Padding = PaddingMode.None;
            aes.Key = key;
            ecb = aes.CreateEncryptor();
            var h = new byte[16];
            ecb.TransformBlock(new byte[16], 0, 16, h, 0);
            Precompute(h);
            var j0 = new byte[16];
            Buffer.BlockCopy(nonce, 0, j0, 0, 12);
            j0[15] = 1;
            ecb.TransformBlock(j0, 0, 16, ek, 0);
            Buffer.BlockCopy(j0, 0, counter, 0, 16);
            Inc32();                                // the first data block uses counter 2
            if (aad != null && aad.Length > 0)
            {
                GhashAdd(aad, 0, aad.Length);
                FlushPending();
                aadLen = aad.Length;
            }
        }

        // the 4-bit table GHASH multiplier (the well-known Shoup layout); H is big endian
        void Precompute(byte[] h)
        {
            ulong vh = 0, vl = 0;
            for (int i = 0; i < 8; i++) { vh = vh << 8 | h[i]; vl = vl << 8 | h[8 + i]; }
            hl[8] = vl; hh[8] = vh;
            for (int i = 4; i > 0; i >>= 1)
            {
                ulong t = (vl & 1) * 0xe1000000UL;
                vl = vh << 63 | vl >> 1;
                vh = vh >> 1 ^ t << 32;
                hl[i] = vl; hh[i] = vh;
            }
            for (int i = 2; i <= 8; i *= 2)
            {
                ulong ch = hh[i], cl = hl[i];
                for (int j = 1; j < i; j++) { hh[i + j] = ch ^ hh[j]; hl[i + j] = cl ^ hl[j]; }
            }
        }

        // yh/yl = (Y xor block) * H, with the block in `work` (big endian)
        void Mult()
        {
            int lo = work[15] & 0xf, hi = work[15] >> 4;
            ulong zh = hh[lo], zl = hl[lo];
            for (int i = 15; i >= 0; i--)
            {
                lo = work[i] & 0xf; hi = work[i] >> 4;
                if (i != 15)
                {
                    int rem = (int)(zl & 0xf);
                    zl = zh << 60 | zl >> 4;
                    zh >>= 4;
                    zh ^= Last4[rem] << 48;
                    zh ^= hh[lo]; zl ^= hl[lo];
                }
                int rem2 = (int)(zl & 0xf);
                zl = zh << 60 | zl >> 4;
                zh >>= 4;
                zh ^= Last4[rem2] << 48;
                zh ^= hh[hi]; zl ^= hl[hi];
            }
            yh = zh; yl = zl;
        }

        void Block(byte[] data, int off)
        {
            ulong dh = 0, dl = 0;
            for (int i = 0; i < 8; i++) { dh = dh << 8 | data[off + i]; dl = dl << 8 | data[off + 8 + i]; }
            dh ^= yh; dl ^= yl;
            for (int i = 7; i >= 0; i--) { work[i] = (byte)dh; dh >>= 8; work[8 + i] = (byte)dl; dl >>= 8; }
            Mult();
        }

        void GhashAdd(byte[] data, int off, int n)
        {
            if (pendingLen > 0)
            {
                int take = Math.Min(16 - pendingLen, n);
                Buffer.BlockCopy(data, off, pending, pendingLen, take);
                pendingLen += take; off += take; n -= take;
                if (pendingLen < 16) return;
                Block(pending, 0);
                pendingLen = 0;
            }
            while (n >= 16) { Block(data, off); off += 16; n -= 16; }
            if (n > 0) { Buffer.BlockCopy(data, off, pending, 0, n); pendingLen = n; }
        }

        void FlushPending()
        {
            if (pendingLen == 0) return;
            for (int i = pendingLen; i < 16; i++) pending[i] = 0;
            Block(pending, 0);
            pendingLen = 0;
        }

        void Inc32()
        {
            for (int i = 15; i >= 12; i--) if (++counter[i] != 0) break;
        }

        void Refill()
        {
            for (int b = 0; b < StreamBlocks; b++)
            {
                Buffer.BlockCopy(counter, 0, ctrBlocks, b * 16, 16);
                Inc32();
            }
            ecb.TransformBlock(ctrBlocks, 0, ctrBlocks.Length, stream, 0);
            streamPos = 0;
        }

        /// <summary>Decrypts data[offset .. offset+count) in place. The bytes are unauthenticated until Verify returned true.</summary>
        public void Update(byte[] data, int offset, int count)
        {
            if (done) throw new InvalidOperationException("gcm: already finished");
            GhashAdd(data, offset, count);              // the GHASH runs over the ciphertext
            cipherLen += count;
            int i = offset, end = offset + count;
            while (i < end)
            {
                if (streamPos >= stream.Length) Refill();
                int n = Math.Min(stream.Length - streamPos, end - i);
                for (int k = 0; k < n; k++) data[i + k] ^= stream[streamPos + k];
                streamPos += n; i += n;
            }
        }

        /// <summary>True when the tag matches everything passed to Update (compared in constant time). Ends the decryptor.</summary>
        public bool Verify(byte[] tag)
        {
            if (done || tag == null || tag.Length != 16) return false;
            done = true;
            FlushPending();
            // the length block: bits of the additional data and of the ciphertext, big endian
            var lens = new byte[16];
            ulong a = (ulong)aadLen * 8, c = (ulong)cipherLen * 8;
            for (int i = 0; i < 8; i++) { lens[7 - i] = (byte)(a >> 8 * i); lens[15 - i] = (byte)(c >> 8 * i); }
            Block(lens, 0);
            var want = new byte[16];
            for (int i = 0; i < 8; i++) { want[i] = (byte)(yh >> 8 * (7 - i)); want[8 + i] = (byte)(yl >> 8 * (7 - i)); }
            int diff = 0;
            for (int i = 0; i < 16; i++) diff |= (want[i] ^ ek[i]) ^ tag[i];
            return diff == 0;
        }

        public void Dispose()
        {
            ecb.Dispose();
            aes.Dispose();
            Array.Clear(counter, 0, counter.Length);
            Array.Clear(stream, 0, stream.Length);
            Array.Clear(ek, 0, ek.Length);
        }
    }

    /// <summary>Update blobs (CHUB): one file, decrypted whole into memory after the tag verified.</summary>
    public static class BlobReader
    {
        public const int Chunk = 1 << 20;

        /// <summary>The header of a blob (flag bit 0: encrypted with the development key), without any key.</summary>
        public static PackFormat.Header Peek(Stream blob)
        {
            var h = new byte[PackFormat.HeaderLength];
            ReadExactly(blob, h, h.Length, "header");
            return PackFormat.Blob.ParseHeader(h);
        }

        /// <summary>Decrypts a whole blob. PackException for a wrong key, a changed file, a wrong size or a bad header; the
        /// bytes decrypted before a failed tag are wiped and never returned.</summary>
        public static byte[] Decrypt(Stream blob, long size, byte[] clientKey)
        {
            var fmt = PackFormat.Blob;
            if (blob == null || size < PackFormat.HeaderLength + PackFormat.TagLength) throw new PackException("not an encrypted CHUB file");
            var header = new byte[PackFormat.HeaderLength];
            ReadExactly(blob, header, header.Length, "header");
            var h = fmt.ParseHeader(header);
            if (size != PackFormat.HeaderLength + h.PlainLength + PackFormat.TagLength) throw new PackException("length mismatch");
            if (h.PlainLength > int.MaxValue - 64) throw new PackException("blob too large for memory");
            byte[] key = fmt.EncryptionKey(clientKey);
            var plain = new byte[h.PlainLength];
            bool ok = false;
            try
            {
                using (var gcm = new GcmDecryptor(key, h.Nonce, h.Raw))
                {
                    int at = 0;
                    var tmp = new byte[Math.Min(Chunk, Math.Max(16, plain.Length))];
                    while (at < plain.Length)
                    {
                        int n = Math.Min(tmp.Length, plain.Length - at);
                        ReadExactly(blob, tmp, n, "body");
                        gcm.Update(tmp, 0, n);
                        Buffer.BlockCopy(tmp, 0, plain, at, n);
                        at += n;
                    }
                    Array.Clear(tmp, 0, tmp.Length);
                    var tag = new byte[PackFormat.TagLength];
                    ReadExactly(blob, tag, tag.Length, "tag");
                    ok = gcm.Verify(tag);
                }
            }
            finally { Array.Clear(key, 0, key.Length); if (!ok) Array.Clear(plain, 0, plain.Length); }
            if (!ok) throw new PackException("wrong key or changed file");
            return plain;
        }

        public static byte[] Decrypt(byte[] blob, byte[] clientKey)
        {
            using (var ms = new MemoryStream(blob, false)) return Decrypt(ms, blob.Length, clientKey);
        }

        internal static void ReadExactly(Stream s, byte[] into, int n, string what)
        {
            int got = 0;
            while (got < n)
            {
                int k = s.Read(into, got, n - got);
                if (k <= 0) throw new PackException("file shorter than its header says (" + what + ")");
                got += k;
            }
        }
    }
}
