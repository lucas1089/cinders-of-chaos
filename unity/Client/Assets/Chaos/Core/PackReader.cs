// Reads chaos.pack, the main client's encrypted container (format: PackCipher.cs header, base patch 0102): decrypts the body
// chunk by chunk, inflates the zlib stream, walks the store-only ZIP inside and keeps the entries a caller asks for.
// The engine mounts the whole ZIP from memory (one buffer of the ZIP's size). The Unity client keeps only what it needs
// (the sprite pair), so the rest of a pack of about a gigabyte never sits in memory.
//
// Nothing is returned before the GCM tag verified: the entries are collected while the stream is read, the tag is checked at
// the end, and on any failure the collected bytes are wiped. As the engine does, inflate runs on bytes the tag has not
// authenticated yet (the output size is fixed by the header, so it cannot grow past it) and the result is refused when the
// stream does not end at exactly the declared length. Not checked, unlike the engine: bytes after the end of the zlib
// stream (the tag still covers them) and the Adler-32 trailer (the tag covers the content).
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;

namespace Chaos.Core
{
    /// <summary>The entries of a pack that a caller asked for, after the tag verified.</summary>
    public sealed class PackContents
    {
        public readonly Dictionary<string, byte[]> Entries = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        public bool DevKey;
        public long PlainLength;
        public int EntryCount;
    }

    public static class PackReader
    {
        public const int Chunk = 4 * 1024 * 1024;     // chaospack.h READ_CHUNK

        public static PackContents ReadFile(string path, byte[] clientKey, Func<string, bool> want)
        {
            using (var f = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16, FileOptions.SequentialScan))
                return Read(f, f.Length, clientKey, want);
        }

        /// <summary>Opens the pack and returns the entries `want(name)` accepts. PackException for a wrong key, a damaged or changed
        /// pack, a version that is not 2 or a ZIP the engine would not mount.</summary>
        public static PackContents Read(Stream pack, long size, byte[] clientKey, Func<string, bool> want)
        {
            var fmt = PackFormat.Pack;
            if (pack == null || size < PackFormat.HeaderLength + PackFormat.TagLength) throw new PackException("not an encrypted CHPK file");
            var raw = new byte[PackFormat.HeaderLength];
            BlobReader.ReadExactly(pack, raw, raw.Length, "header");
            var h = fmt.ParseHeader(raw);
            long bodyLen = size - PackFormat.HeaderLength - PackFormat.TagLength;
            // chaospack.h: refused before anything is allocated (the tag is only checked at the end)
            if (bodyLen <= 0 || bodyLen > PackFormat.MaxPlaintext || h.PlainLength > bodyLen * PackFormat.MaxRatio + 1024)
                throw new PackException("length mismatch");
            byte[] key = fmt.EncryptionKey(clientKey);
            var result = new PackContents { DevKey = h.DevKey, PlainLength = h.PlainLength };
            bool ok = false;
            try
            {
                using (var gcm = new GcmDecryptor(key, h.Nonce, h.Raw))
                {
                    var body = new BodyStream(pack, gcm, bodyLen);
                    try
                    {
                        Scan(body, h.PlainLength, want, result);
                    }
                    catch (InvalidDataException) { throw new PackException("wrong key or changed file"); }
                    body.Drain();                         // every byte of the body has to pass the GCM before the tag is read
                    var tag = new byte[PackFormat.TagLength];
                    BlobReader.ReadExactly(pack, tag, tag.Length, "tag");
                    ok = gcm.Verify(tag);
                }
            }
            finally
            {
                Array.Clear(key, 0, key.Length);
                if (!ok)
                {
                    foreach (var kv in result.Entries) Array.Clear(kv.Value, 0, kv.Value.Length);
                    result.Entries.Clear();
                }
            }
            if (!ok) throw new PackException("wrong key or changed file");
            return result;
        }

        /// <summary>The ciphertext of the body as a stream of decrypted bytes, 4 MB at a time.</summary>
        sealed class BodyStream : Stream
        {
            readonly Stream src;
            readonly GcmDecryptor gcm;
            long left;
            readonly byte[] buf;
            int pos, len;

            public BodyStream(Stream src, GcmDecryptor gcm, long bodyLen)
            {
                this.src = src; this.gcm = gcm; left = bodyLen;
                buf = new byte[(int)Math.Min(Chunk, bodyLen)];
            }

            bool Fill()
            {
                if (left == 0) return false;
                int n = (int)Math.Min(buf.Length, left);
                BlobReader.ReadExactly(src, buf, n, "body");
                gcm.Update(buf, 0, n);
                left -= n; pos = 0; len = n;
                return true;
            }

            public override int Read(byte[] b, int off, int count)
            {
                if (pos >= len && !Fill()) return 0;
                int k = Math.Min(count, len - pos);
                Buffer.BlockCopy(buf, pos, b, off, k);
                pos += k;
                return k;
            }

            public void Drain() { pos = len; while (Fill()) { } Array.Clear(buf, 0, buf.Length); }

            public override bool CanRead => true;
            public override bool CanSeek => false;
            public override bool CanWrite => false;
            public override long Length => throw new NotSupportedException();
            public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
            public override void Flush() { }
            public override long Seek(long o, SeekOrigin so) => throw new NotSupportedException();
            public override void SetLength(long v) => throw new NotSupportedException();
            public override void Write(byte[] b, int o, int c) => throw new NotSupportedException();
        }

        /// <summary>Counts what comes out of inflate and refuses more than the header declared.</summary>
        sealed class Counted
        {
            readonly Stream s;
            readonly long limit;
            public long Produced;

            public Counted(Stream s, long limit) { this.s = s; this.limit = limit; }

            public int Read(byte[] b, int off, int count)
            {
                int k = s.Read(b, off, count);
                Produced += k;
                if (Produced > limit) throw new PackException("length mismatch");
                return k;
            }

            public void ReadExactly(byte[] b, int n)
            {
                int got = 0;
                while (got < n)
                {
                    int k = Read(b, got, n - got);
                    if (k <= 0) throw new PackException("wrong key or changed file");
                    got += k;
                }
            }

            public void Skip(long n)
            {
                var tmp = new byte[(int)Math.Min(n, 1 << 16)];
                while (n > 0)
                {
                    int k = Read(tmp, 0, (int)Math.Min(n, tmp.Length));
                    if (k <= 0) throw new PackException("wrong key or changed file");
                    n -= k;
                }
            }
        }

        static void Scan(BodyStream body, long plainLen, Func<string, bool> want, PackContents result)
        {
            // zlib header: deflate with a window up to 32 KB, no preset dictionary, and the check bits of RFC 1950
            var zh = new byte[2];
            if (body.Read(zh, 0, 1) != 1 || body.Read(zh, 1, 1) != 1) throw new PackException("wrong key or changed file");
            if ((zh[0] & 0x0f) != 8 || zh[0] >> 4 > 7 || (zh[0] * 256 + zh[1]) % 31 != 0 || (zh[1] & 0x20) != 0)
                throw new PackException("wrong key or changed file");
            using (var inflate = new DeflateStream(body, CompressionMode.Decompress, true))
            {
                var z = new Counted(inflate, plainLen);
                var head = new byte[30];
                while (true)
                {
                    z.ReadExactly(head, 4);
                    uint sig = Le32(head, 0);
                    if (sig == 0x02014b50 || sig == 0x06054b50) break;     // the central directory: no more entries
                    if (sig != 0x04034b50) throw new PackException("wrong key or changed file");
                    var rest = new byte[26];
                    z.ReadExactly(rest, 26);
                    int flags = rest[2] | rest[3] << 8, method = rest[4] | rest[5] << 8;
                    uint csize = Le32(rest, 14), usize = Le32(rest, 18);
                    int nlen = rest[22] | rest[23] << 8, elen = rest[24] | rest[25] << 8;
                    if ((flags & 8) != 0 || method != 0 || csize != usize || csize == 0xFFFFFFFFu)
                        throw new PackException("the pack holds a ZIP entry that is not stored (the engine's packer stores every member)");
                    var nameBytes = new byte[nlen];
                    z.ReadExactly(nameBytes, nlen);
                    string name = Encoding.UTF8.GetString(nameBytes);
                    if (!SafeName(name)) throw new PackException("the pack holds an unsafe entry name");
                    if (elen > 0) z.Skip(elen);
                    result.EntryCount++;
                    if (usize > plainLen - z.Produced) throw new PackException("length mismatch");
                    bool keep = !name.EndsWith("/") && usize <= int.MaxValue - 64 && want != null && want(name);
                    if (keep)
                    {
                        var data = new byte[usize];
                        if (usize > 0) z.ReadExactly(data, (int)usize);
                        if (result.Entries.ContainsKey(name)) throw new PackException("the pack holds one entry twice");
                        result.Entries[name] = data;
                    }
                    else z.Skip(usize);
                }
                // the rest of the ZIP (central directory) to the declared end, then the stream has to end there
                var drain = new byte[1 << 16];
                while (z.Read(drain, 0, drain.Length) > 0) { }
                if (z.Produced != plainLen) throw new PackException("wrong key or changed file");
            }
        }

        static uint Le32(byte[] b, int i) => (uint)(b[i] | b[i + 1] << 8 | b[i + 2] << 16 | b[i + 3] << 24);

        /// <summary>make_update_manifest.py check_pack_name: a relative path with no empty, dot or dot-dot part, no backslash, colon or NUL.</summary>
        public static bool SafeName(string n)
        {
            if (string.IsNullOrEmpty(n) || n[0] == '/' || n.IndexOf('\\') >= 0 || n.IndexOf(':') >= 0 || n.IndexOf('\0') >= 0) return false;
            foreach (var p in n.TrimEnd('/').Split('/')) if (p.Length == 0 || p == "." || p == "..") return false;
            return true;
        }
    }
}
