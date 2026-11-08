// Phase 17: the Unity client reads the sprite pair from the main client's encrypted container (Core/PackCipher.cs, PackReader.cs,
// SprShards.cs, ThingsPair.cs). Every key in this file is made up (the SHA-256 of a sentence below); the real client key is
// never needed, never in the repository and never in a message the reader raises.
//
// Two writers mirror the real tools. The fixtures FixturePack and FixtureBlob were made by the real Python tools
// (client/tools/pack_client.py encrypt_pack over build_zip of a tiny tree, client/tools/update_crypt.py encrypt) with FixtureKey, so the
// reader is checked against the other implementation. The C# writers below (TestWriter) mirror them for what a fixture cannot
// hold: a pack over one 4 MB chunk, tampered files, a version 1 header, a ZIP the engine would not mount, whole install folders.
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;

namespace Chaos.Core.Tests
{
    static class Phase17Tests
    {
        // SHA-256("made-up phase 17 test key, not a real key"); python3: hashlib.sha256(b"...").hexdigest()
        const string FixtureKeyHex = "a4983217cfce13c825013a74b48d2935d715cd391af8c6cb7bc1ed009425c9d1";

        // chaos.pack made by pack_client.py: init.lua, modules/game_x/x.lua and data/things/1098/ with Tibia.dat (bytes 1..8),
        // Tibia.sprshards, Tibia.000.spr (300 bytes: (i*7)&255) and Tibia.001.spr (500 bytes: (i*13+1)&255)
        const string FixturePack = "Q0hQSwIAAADlYcfwFfVeuKz1SPh4CAAAAAAAAMWDrqQUWr2JaqucEIQP0V1QZ7S28/gXioOwh5j36ujv8lrWJzPWtAC3ZIxQUM3qfY+zAIAt01LvS2XkRhW66R31epuAhTnTogblHudWJPYeL0Pm8oBii40tDKFFHMF6991Gngd1qc/TYPTCC8ffsvKGxkzapuBZQp4YC8DU6o/4Fdt7vBHLIeFd4XLpX/40dMbwUpnFFKVn8Ejj84lbDk8jW29JE1OurJXrCSMnw7o832D8z2r+Nz3CqRUK68lmLODgxjt725MaRqfh0oujxDrhr9NvtMVio3x9OfgwZxA8VlRUHTcEMDnch6JKABp2EFB1DpRmlEH+a4npj/336rtWqhg3Z6F8jUzSV/Lzcd1K7XEeCPPrwYkwljg9ZXwDtW9hU5C9k4TUY/VO5YOJ+rKB7YTq6oW4FHPi2zOt5X2w79tuaCSGmN5FoUTvlvEGCco9gX69Nh41byzpDt416Ed5hEB8lYXmDZ0dpau/0wv5KPECsRkOvIPo7vpMxesdQwnYKR7Rd+HAi2ZIwc+W//qZcM6yfXtZyVos+RszkPmWG1Ug5uoNeKtTzZe/aPCROtMr4MZ0nwS8FV9tVdrgDP+Dw2nSO/PkvvcVlltElTsjjSj2HA6CyWfGKjmG2JlHb1aEgTkOiPDWSzyKVFL5b8cuAfPPc3EMqp6DuPL4zhwsgCa8y8nXVIqod+V7uJ9FTxW3spKzOSpO5TOyy0jycQUpJPOiu3p9iw6wrBQmpPM6kJAHyPL/I/B7ZxLvm9XbqAr5srOOJxCfvqzk5IixXaIZAkqCk9DxIVACzZglkOB8/ljP/bRShzEWYwEHleq1DZpulLBnX7Pb+RF9XkpyTsc7p5lLYoRSr/J593HDBn0FVJpNj/wRXDwoE6h/6Vw5LmwsQ941x1Kl0StubNQnX5T58/WHj2cwh/rq6ws8ZJAVkoUrRuP0QuCeq0afOjBmiSfxI3pBazdFDjwYStGrU0VO8Z5/pwzggoaZDmSjsaBSukRHKZXYXv/tIVPnvpFxxDsZyjLsIVSiHIUG/vuImLqpnaPn0bPA120VpjPp5gDsMoZSIt+Y5plo57xldMeR61XMDzH/+4PoSdXEuX0GURz+4sIdZ3MiHRy2EDtwJFFqUBPXgm/W7fB8YfExHwF7pGAl/T9KuYd0yOkB72JYxQFLVsa/Zb7rKeO9ILIzlLjEinto7vPRfoG4Qdxop7GXcvgQc4n6L3B4t2E7/A35nPeSTheLADdfq+IlGr6Prxps";

        // an update blob made by update_crypt.py: 1000 bytes (i*31+5)&255
        const string FixtureBlob = "Q0hVQgEAAABPigAiD6Tc7RtG7rHoAwAAAAAAANA3YYzOi2VLFCNg7vUWUVdY2enyopG+3JSbjiAhj8ANOiWV9OfE8oURPVOXNFUHMe3z5lHOAWlxzxNEXk/ZKrfiQ8942Hrb1MjGoDKa9TtD7Vf2d8924HUgSHDHXKFMIbugg93N7MNx8R29O+mrEFHMfdU1z6qdJW/fx3HsuK6NndEoZ/0t0QhnC+HxnrJerBtEwDy9z2dcmbRp8VmJdHvEd6D1CWdPIaoxWUoQDzYTK1affTAWCbjGn0Y25FNcLzJmyLzgTR2YXDkZTFmLwTSae4jbGmmY0EGMeDK1YRqPQUIA9mcyhDLxH7fx0RsYcqqMVtcqmJecXCcpJBy+dk5s0FeHpPECcFehUhJecglOHT+oxCUnfBO9KjXVHd1Ob5w1+opU01UEt9xzulk0Z6W98TxNZD6KvB76P/LGc3Qn6Ef5FKpFYYPSxgfp9Hnqmr2Nvl2OhxozUmeP2xoJZapapdYYaDFd9COvR00gtNr9JxpNGRXEI4NtgUiVMHj17AmmJfV0i9FTy9ooOQe67C+hm1ttSVfh6ehQ+eZudM4XKcgruSO35l5TYYtoGITz38Ptk5moAIBoOgaDZQof7ZkdkMMgI6hGykyUt18pJVhTj/H7tzE5HPy4oAyGbgOa8gGdEQH1ebQWyshRkyPbRGV9lsGbvSWSNh5iIOLVHOiDZzUi88xB8WglL5xgGjUDtgi3OyBhEcEBrJzhVeVxlEqErhEPLyGpqrkxVjf2/LMzjPchThYRA4hzdxJeEJgqQaYklg8+uNFNSlTuRoLWE4qLNXJWAZrG4gRmXquznBjY9UvEA8loUWJ5IFOy1BKKc6hnRBqNZeE/ihjOSEqkA4r5ZEBrAZOqa3BNCv53YoYYZZe94K+1ujLHu2jQWAOMvj6PsMx0bZHePQE2/hNjim0QsYc/FTnvBXOAzF/dI1bYXeGqmzUw62SZxOzJix1x+rFZUkW+rShyCeRllXwlvUHYtm/oT3gCf53Mdxy7ioBbRlo62bV099g52YdYlFlLy2UtcUA+RYi1eTKJmVh1mtgPMP28NQqdZmwcharjqcoK2Zpl5zsizVB6gUoonuDr82thuZglnZQEus4d/K72vvos1tfOvbepQW1KmefUoUnmNiX+MrKGtg5N4w7nVGVLZZeAiHM/+bYI1Dl49BWlgPGsub1RI9EKq1O5VRh+DLzoWxqx8X8D8chiEfaLaNnR90Amn8JlqBJKt3tJiC0M7ublqdZIMS3ndHTOU+zxyfnVbJlaD104t47jdZBTq393EEFBHJIUHcdkzNeJWKTQGCxTQ7g7tLK3l4BZsIFkFm1fyGVES16vRXTJo1WAvsvokWzIEz1F8iAO";

        static byte[] Fx(string b64) => Convert.FromBase64String(b64);
        static byte[] Key(string hex) { var b = new byte[hex.Length / 2]; for (int i = 0; i < b.Length; i++) b[i] = Convert.ToByte(hex.Substring(2 * i, 2), 16); return b; }
        static byte[] FixtureKey => Key(FixtureKeyHex);
        static byte[] OtherKey { get { var k = FixtureKey; k[0] ^= 1; return k; } }
        static byte[] Pattern(int n, int mul, int add) { var b = new byte[n]; for (int i = 0; i < n; i++) b[i] = (byte)(i * mul + add); return b; }
        static bool Same(byte[] a, byte[] b) { if (a == null || b == null || a.Length != b.Length) return false; for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return false; return true; }

        // ------------------------------------------------------------------------------------------------ writers (mirror the real tools)

        static class TestWriter
        {
            public const string PackSalt = "CindersOfChaos/pack/v1", BlobSalt = "CindersOfChaos/update/v1";

            static byte[] Hkdf(byte[] key, string salt, string info) => PackFormat.Hkdf(key, Encoding.ASCII.GetBytes(salt), Encoding.ASCII.GetBytes(info), 32);

            public static byte[] Zlib(byte[] data)
            {
                var ms = new MemoryStream();
                using (var z = new ZLibStream(ms, CompressionLevel.SmallestSize, true)) z.Write(data, 0, data.Length);
                return ms.ToArray();
            }

            static uint Crc(byte[] d)
            {
                uint c = 0xFFFFFFFF;
                foreach (byte b in d) { c ^= b; for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? c >> 1 ^ 0xEDB88320 : c >> 1; }
                return ~c;
            }

            /// <summary>A store-only ZIP as pack_client.py build_zip writes it (stored, 1980 stamp, sizes in the local header, no data descriptor).
            /// method 8 and flag 8 are here only to build the files the reader must refuse.</summary>
            public static byte[] Zip(List<KeyValuePair<string, byte[]>> entries, int method = 0, int flags = 0)
            {
                var o = new MemoryStream();
                var w = new BinaryWriter(o);
                var central = new List<byte[]>();
                foreach (var e in entries)
                {
                    byte[] name = Encoding.UTF8.GetBytes(e.Key);
                    long at = o.Position;
                    uint crc = Crc(e.Value);
                    w.Write(0x04034b50u); w.Write((ushort)20); w.Write((ushort)flags); w.Write((ushort)method); w.Write((ushort)0); w.Write((ushort)0x21);
                    w.Write(crc); w.Write((uint)e.Value.Length); w.Write((uint)e.Value.Length); w.Write((ushort)name.Length); w.Write((ushort)0);
                    w.Write(name); w.Write(e.Value);
                    var c = new MemoryStream(); var cw = new BinaryWriter(c);
                    cw.Write(0x02014b50u); cw.Write((ushort)20); cw.Write((ushort)20); cw.Write((ushort)flags); cw.Write((ushort)method); cw.Write((ushort)0); cw.Write((ushort)0x21);
                    cw.Write(crc); cw.Write((uint)e.Value.Length); cw.Write((uint)e.Value.Length); cw.Write((ushort)name.Length);
                    cw.Write((ushort)0); cw.Write((ushort)0); cw.Write((ushort)0); cw.Write((ushort)0); cw.Write(0x81a40000u); cw.Write((uint)at); cw.Write(name);
                    central.Add(c.ToArray());
                }
                long start = o.Position, size = 0;
                foreach (var c in central) { w.Write(c); size += c.Length; }
                w.Write(0x06054b50u); w.Write((ushort)0); w.Write((ushort)0); w.Write((ushort)central.Count); w.Write((ushort)central.Count);
                w.Write((uint)size); w.Write((uint)start); w.Write((ushort)0);
                return o.ToArray();
            }

            static byte[] Seal(byte[] key, string salt, string info, byte[] header, byte[] nonceFrom, byte[] body)
            {
                byte[] enc = Hkdf(key, salt, info);
                var ct = new byte[body.Length];
                var tag = new byte[16];
                using (var g = new AesGcm(enc, 16)) g.Encrypt(header.AsSpan(8, 12), body, ct, tag, header);
                var o = new byte[header.Length + ct.Length + 16];
                Buffer.BlockCopy(header, 0, o, 0, header.Length);
                Buffer.BlockCopy(ct, 0, o, header.Length, ct.Length);
                Buffer.BlockCopy(tag, 0, o, header.Length + ct.Length, 16);
                return o;
            }

            static byte[] Header(string magic, int version, bool dev, byte[] nonce, long plainLen)
            {
                var h = new byte[28];
                for (int i = 0; i < 4; i++) h[i] = (byte)magic[i];
                h[4] = (byte)version; h[5] = (byte)(dev ? 1 : 0);
                Buffer.BlockCopy(nonce, 0, h, 8, 12);
                for (int i = 0; i < 8; i++) h[20 + i] = (byte)((ulong)plainLen >> 8 * i);
                return h;
            }

            /// <summary>chaos.pack as pack_client.py encrypt_pack: zlib of the ZIP, nonce = HMAC(nonce key, zlib stream)[:12], AES-256-GCM.</summary>
            public static byte[] Pack(byte[] zip, byte[] key, bool dev = false, int version = 2, long? declaredLen = null)
            {
                byte[] body = Zlib(zip);
                byte[] nonceKey = Hkdf(key, PackSalt, "chaos-pack-nonce");
                byte[] nonce;
                using (var h = new HMACSHA256(nonceKey)) { nonce = new byte[12]; Buffer.BlockCopy(h.ComputeHash(body), 0, nonce, 0, 12); }
                return Seal(key, PackSalt, "chaos-pack-aes-256-gcm", Header("CHPK", version, dev, nonce, declaredLen ?? zip.Length), nonce, body);
            }

            /// <summary>An update blob as update_crypt.py encrypt: nonce = HMAC(nonce key, plaintext)[:12], AES-256-GCM of the plaintext.</summary>
            public static byte[] Blob(byte[] plain, byte[] key, bool dev = false)
            {
                byte[] nonceKey = Hkdf(key, BlobSalt, "chaos-update-blob-nonce");
                byte[] nonce = new byte[12];
                using (var h = new HMACSHA256(nonceKey)) Buffer.BlockCopy(h.ComputeHash(plain), 0, nonce, 0, 12);
                return Seal(key, BlobSalt, "chaos-update-blob-aes-256-gcm", Header("CHUB", 1, dev, nonce, plain.Length), nonce, plain);
            }
        }

        /// <summary>A .spr as spr_shards.py reads it: u32 signature, u32 count, count x u32 address (0 = no sprite), then 3 colour key bytes, u16 size, runs.</summary>
        static byte[] SprFileBytes(uint sig, int count, Func<int, byte[]> record)
        {
            var recs = new List<byte[]>();
            for (int i = 0; i < count; i++) recs.Add(record(i));
            var o = new MemoryStream(); var w = new BinaryWriter(o);
            w.Write(sig); w.Write((uint)count);
            long at = 8 + 4L * count;
            foreach (var r in recs) { if (r == null) w.Write(0u); else { w.Write((uint)at); at += 5 + r.Length; } }
            foreach (var r in recs) if (r != null) { w.Write((byte)255); w.Write((byte)0); w.Write((byte)255); w.Write((ushort)r.Length); w.Write(r); }
            return o.ToArray();
        }

        // sprite n: skip n%20 pixels, two RGBA pixels; every fifth id has no sprite
        static byte[] Runs(int id)
        {
            if (id % 5 == 0) return null;
            return new byte[] { (byte)(id % 20), 0, 2, 0, (byte)id, (byte)(id >> 8), 7, 255, (byte)(id + 1), 9, (byte)id, 200 };
        }

        sealed class Shards
        {
            public byte[] Single;
            public string IndexText;
            public List<KeyValuePair<string, byte[]>> Files = new List<KeyValuePair<string, byte[]>>();   // Tibia.000.spr ...
            public uint Signature = 0x4a5b;
            public int Total;
        }

        static Shards MakeShards(int total, int perShard)
        {
            var s = new Shards { Total = total };
            s.Single = SprFileBytes(s.Signature, total, i => Runs(i + 1));
            var sb = new StringBuilder("chaos-spr-shards 1\nsignature " + s.Signature + "\nsprites " + total + "\nper-shard " + perShard + "\n");
            for (int first = 1, k = 0; first <= total; first += perShard, k++)
            {
                int n = Math.Min(perShard, total - first + 1);
                int f0 = first;
                byte[] b = SprFileBytes(s.Signature, n, i => Runs(f0 + i));
                string name = "Tibia." + k.ToString("000") + ".spr";
                s.Files.Add(new KeyValuePair<string, byte[]>(name, b));
                sb.Append("shard " + first + " " + n + " " + name + " " + b.Length + " " + new string('0', 64) + "\n");
            }
            s.IndexText = sb.ToString();
            return s;
        }

        sealed class MemFs : IPairFiles
        {
            public readonly Dictionary<string, byte[]> Files = new Dictionary<string, byte[]>(new SlashComparer());
            public int Opens;
            public bool Exists(string path) => Files.ContainsKey(path);
            public long Length(string path) => Files[path].Length;
            public Stream Open(string path) { Opens++; return new MemoryStream(Files[path], false); }
        }

        // the locator joins with Path.Combine, which uses '\' on Windows; the fixtures are written with '/'
        sealed class SlashComparer : IEqualityComparer<string>
        {
            public bool Equals(string a, string b) => N(a) == N(b);
            public int GetHashCode(string s) => N(s).GetHashCode();
        }

        static string N(string p) => p?.Replace('\\', '/');
        static string J(params string[] p) => N(Path.Combine(p));

        // ------------------------------------------------------------------------------------------------ the suite

        static bool Throws<T>(Action a, out string message) where T : Exception
        {
            message = null;
            try { a(); }
            catch (T e) { message = e.Message; return true; }
            return false;
        }

        public static void Run(Action<bool, string> check)
        {
            Gcm(check);
            Blobs(check);
            Packs(check);
            Index(check);
            ShardSets(check);
            Locator(check);
        }

        static string Hex(byte[] b) { var sb = new StringBuilder(); foreach (byte x in b) sb.Append(x.ToString("x2")); return sb.ToString(); }

        static void Gcm(Action<bool, string> check)
        {
            // RFC 5869 test case 1 (HKDF-SHA256)
            var ikm = new byte[22]; for (int i = 0; i < 22; i++) ikm[i] = 0x0b;
            var salt = new byte[13]; for (int i = 0; i < 13; i++) salt[i] = (byte)i;
            var info = new byte[10]; for (int i = 0; i < 10; i++) info[i] = (byte)(0xf0 + i);
            check(Hex(PackFormat.Hkdf(ikm, salt, info, 42)) == "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865", "pack: HKDF-SHA256 matches RFC 5869 test case 1");
            check(Hex(PackFormat.Hkdf(FixtureKey, Encoding.ASCII.GetBytes("CindersOfChaos/pack/v1"), Encoding.ASCII.GetBytes("chaos-pack-aes-256-gcm"), 32)).Length == 64, "pack: HKDF gives 32 bytes");

            // NIST GCM test case 16 (AES-256, 60 bytes of data, 20 bytes of additional data), the tag by python cryptography too
            byte[] k = Key("feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308"), iv = Key("cafebabefacedbaddecaf888");
            byte[] aad = Key("feedfacedeadbeeffeedfacedeadbeefabaddad2");
            byte[] pt = Key("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39");
            byte[] ct = Key("522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662");
            byte[] tag = Key("76fc6ece0f4e1768cddf8853bb2d551b");
            foreach (int step in new[] { 60, 1, 7, 16, 17, 33 })
            {
                var data = (byte[])ct.Clone();
                bool ok;
                using (var g = new GcmDecryptor(k, iv, aad))
                {
                    for (int at = 0; at < data.Length; at += step) g.Update(data, at, Math.Min(step, data.Length - at));
                    ok = g.Verify(tag);
                }
                check(ok && Same(data, pt), "gcm: NIST test case 16 decrypts and verifies in steps of " + step);
            }
            var bad = (byte[])ct.Clone(); bad[10] ^= 1;
            using (var g = new GcmDecryptor(k, iv, aad)) { g.Update(bad, 0, bad.Length); check(!g.Verify(tag), "gcm: a changed ciphertext fails the tag"); }
            using (var g = new GcmDecryptor(k, iv, new byte[] { 1 })) { var d = (byte[])ct.Clone(); g.Update(d, 0, d.Length); check(!g.Verify(tag), "gcm: other additional data fails the tag"); }
            var tag2 = (byte[])tag.Clone(); tag2[15] ^= 0x80;
            using (var g = new GcmDecryptor(k, iv, aad)) { var d = (byte[])ct.Clone(); g.Update(d, 0, d.Length); check(!g.Verify(tag2), "gcm: a changed tag fails"); }
            // against .NET's AesGcm over sizes around the block and counter-buffer edges
            bool all = true;
            foreach (int n in new[] { 0, 1, 15, 16, 17, 4095, 4096, 4097, 9000 })
            {
                var plain = Pattern(n, 29, 3); var c = new byte[n]; var t = new byte[16]; var nonce = Pattern(12, 5, 1);
                using (var g = new AesGcm(k, 16)) g.Encrypt(nonce, plain, c, t, aad);
                var d = (byte[])c.Clone();
                using (var g = new GcmDecryptor(k, nonce, aad)) { g.Update(d, 0, n); all &= g.Verify(t) && Same(d, plain); }
            }
            check(all, "gcm: sizes 0 to 9000 agree with System.Security.Cryptography.AesGcm");
        }

        static void Blobs(Action<bool, string> check)
        {
            byte[] plain = Pattern(1000, 31, 5), key = FixtureKey;
            byte[] blob = Fx(FixtureBlob);
            var head = BlobReader.Peek(new MemoryStream(blob));
            check(head.PlainLength == 1000 && !head.DevKey, "blob: the header of a blob made by update_crypt.py (length 1000, not a development key)");
            check(Same(BlobReader.Decrypt(blob, key), plain), "blob: a blob made by update_crypt.py decrypts to its plaintext");
            string m;
            check(Throws<PackException>(() => BlobReader.Decrypt(blob, OtherKey), out m) && m == "wrong key or changed file", "blob: a wrong key fails cleanly (" + m + ")");
            check(!m.Contains(FixtureKeyHex), "blob: the message does not hold the key");
            var flip = (byte[])blob.Clone(); flip[500] ^= 1;
            check(Throws<PackException>(() => BlobReader.Decrypt(flip, key), out m), "blob: a changed byte fails");
            var tagFlip = (byte[])blob.Clone(); tagFlip[tagFlip.Length - 1] ^= 1;
            check(Throws<PackException>(() => BlobReader.Decrypt(tagFlip, key), out m), "blob: a changed tag fails");
            var hdrFlip = (byte[])blob.Clone(); hdrFlip[9] ^= 1;
            check(Throws<PackException>(() => BlobReader.Decrypt(hdrFlip, key), out m), "blob: a changed header fails (it is the additional data)");
            check(Throws<PackException>(() => BlobReader.Decrypt(blob.AsSpan(0, blob.Length - 1).ToArray(), key), out m), "blob: a short file fails");
            var longer = new byte[blob.Length + 1]; Buffer.BlockCopy(blob, 0, longer, 0, blob.Length);
            check(Throws<PackException>(() => BlobReader.Decrypt(longer, key), out m) && m == "length mismatch", "blob: a file longer than its header says fails");
            var magic = (byte[])blob.Clone(); magic[0] = (byte)'X';
            check(Throws<PackException>(() => BlobReader.Decrypt(magic, key), out m), "blob: another magic is refused");
            var ver = (byte[])blob.Clone(); ver[4] = 2;
            check(Throws<PackException>(() => BlobReader.Decrypt(ver, key), out m), "blob: another version is refused");
            check(Throws<PackException>(() => BlobReader.Decrypt(blob, new byte[16]), out m), "blob: a key of the wrong size is refused");

            // the C# writer reads back, and a blob over one chunk of the reader (1 MB) crosses its boundary
            var big = Pattern((1 << 20) * 2 + 77, 17, 9);
            check(Same(BlobReader.Decrypt(TestWriter.Blob(big, key), key), big), "blob: the C# writer's 2 MB blob reads back across chunk edges");
            check(Same(BlobReader.Decrypt(TestWriter.Blob(new byte[0], key), key), new byte[0]), "blob: an empty file reads back");
            check(BlobReader.Peek(new MemoryStream(TestWriter.Blob(plain, key, dev: true))).DevKey, "blob: the development key flag is read");
            // the writer and update_crypt.py agree: the writer's blob of the fixture plaintext has the same size and header fields
            var mine = TestWriter.Blob(plain, key);
            check(mine.Length == blob.Length && Same(mine.AsSpan(0, 28).ToArray(), blob.AsSpan(0, 28).ToArray()) && Same(mine, blob), "blob: the C# writer builds the very bytes update_crypt.py built (nonce, header, ciphertext, tag)");
        }

        static void Packs(Action<bool, string> check)
        {
            byte[] key = FixtureKey;
            byte[] pack = Fx(FixturePack);
            // wanted entries of the python made pack: the pair only
            Func<string, bool> pair = n => { string v, f; return PairLocator.WantedEntry(n, out v, out f); };
            PackContents c;
            using (var ms = new MemoryStream(pack)) c = PackReader.Read(ms, pack.Length, key, pair);
            check(c.EntryCount == 6 && c.Entries.Count == 4 && !c.DevKey, "pack: the python made pack has 6 entries, 4 of them the pair (" + c.EntryCount + ", " + c.Entries.Count + ")");
            check(Same(c.Entries["data/things/1098/Tibia.dat"], new byte[] { 1, 2, 3, 4, 5, 6, 7, 8 }), "pack: Tibia.dat of the python made pack");
            check(Same(c.Entries["data/things/1098/Tibia.000.spr"], Pattern(300, 7, 0)) && Same(c.Entries["data/things/1098/Tibia.001.spr"], Pattern(500, 13, 1)), "pack: both shards of the python made pack, byte for byte");
            check(Encoding.ASCII.GetString(c.Entries["data/things/1098/Tibia.sprshards"]).StartsWith("chaos-spr-shards 1\n"), "pack: the shard index of the python made pack");
            check(!c.Entries.ContainsKey("init.lua") && !c.Entries.ContainsKey("modules/game_x/x.lua"), "pack: entries nobody asked for are not kept");
            using (var ms = new MemoryStream(pack)) c = PackReader.Read(ms, pack.Length, key, n => n == "init.lua");
            check(c.Entries.Count == 1 && Encoding.ASCII.GetString(c.Entries["init.lua"]).StartsWith("-- made up init"), "pack: any entry can be asked for (init.lua)");

            string m;
            check(Throws<PackException>(() => PackReader.Read(new MemoryStream(pack), pack.Length, OtherKey, pair), out m) && m == "wrong key or changed file", "pack: a wrong key fails cleanly (" + m + ")");
            check(!m.Contains(FixtureKeyHex), "pack: the message does not hold the key");
            var tag = (byte[])pack.Clone(); tag[tag.Length - 1] ^= 1;
            check(Throws<PackException>(() => PackReader.Read(new MemoryStream(tag), tag.Length, key, pair), out m) && m == "wrong key or changed file", "pack: a changed tag fails after a clean inflate");
            var body = (byte[])pack.Clone(); body[400] ^= 4;
            check(Throws<PackException>(() => PackReader.Read(new MemoryStream(body), body.Length, key, pair), out m), "pack: a changed byte of the body fails");
            var hdr = (byte[])pack.Clone(); hdr[6] ^= 1;
            check(Throws<PackException>(() => PackReader.Read(new MemoryStream(hdr), hdr.Length, key, pair), out m), "pack: a changed header fails (flags are additional data)");
            check(Throws<PackException>(() => PackReader.Read(new MemoryStream(pack, 0, pack.Length - 3), pack.Length - 3, key, pair), out m), "pack: a cut file fails");
            var v1 = (byte[])pack.Clone(); v1[4] = 1;
            check(Throws<PackException>(() => PackReader.Read(new MemoryStream(v1), v1.Length, key, pair), out m) && m.Contains("version 1"), "pack: version 1 (never released) is refused (" + m + ")");
            check(Throws<PackException>(() => PackReader.Read(new MemoryStream(Fx(FixtureBlob)), Fx(FixtureBlob).Length, key, pair), out m), "pack: a blob is not a pack");
            check(Throws<PackException>(() => PackReader.Read(new MemoryStream(new byte[10]), 10, key, pair), out m), "pack: ten bytes are not a pack");

            // the C# writer: the same tree reads back; flags
            var entries = new List<KeyValuePair<string, byte[]>>
            {
                new KeyValuePair<string, byte[]>("data/things/1098/Tibia.dat", Pattern(2000, 3, 1)),
                new KeyValuePair<string, byte[]>("modules/a/b.lua", Pattern(70000, 5, 2)),
                new KeyValuePair<string, byte[]>("empty.txt", new byte[0]),
            };
            byte[] zip = TestWriter.Zip(entries);
            { var p = TestWriter.Pack(zip, key, dev: true); c = PackReader.Read(new MemoryStream(p), p.Length, key, n => true); }
            check(c.DevKey && c.Entries.Count == 3 && Same(c.Entries["modules/a/b.lua"], Pattern(70000, 5, 2)) && c.Entries["empty.txt"].Length == 0, "pack: the C# writer's pack reads back with its development flag and an empty member");

            // a pack over one 4 MB chunk of the reader: ciphertext is read, decrypted and inflated in pieces
            var rnd = new Random(17); var noise = new byte[4_700_000]; rnd.NextBytes(noise);
            var bigEntries = new List<KeyValuePair<string, byte[]>>
            {
                new KeyValuePair<string, byte[]>("data/things/1098/Tibia.000.spr", noise),
                new KeyValuePair<string, byte[]>("other/skip.bin", Pattern(100000, 11, 4)),
                new KeyValuePair<string, byte[]>("data/things/1098/Tibia.dat", Pattern(50, 1, 1)),
            };
            byte[] bigPack = TestWriter.Pack(TestWriter.Zip(bigEntries), key);
            check(bigPack.Length > PackReader.Chunk, "pack: the test pack is over one 4 MB chunk (" + bigPack.Length + " bytes)");
            c = PackReader.Read(new MemoryStream(bigPack), bigPack.Length, key, pair);
            check(c.Entries.Count == 2 && Same(c.Entries["data/things/1098/Tibia.000.spr"], noise), "pack: a pack over one chunk reads back, member for member");
            var bigTag = (byte[])bigPack.Clone(); bigTag[bigTag.Length - 5] ^= 1;
            check(Throws<PackException>(() => PackReader.Read(new MemoryStream(bigTag), bigTag.Length, key, pair), out m), "pack: a changed tag of a big pack fails");
            var bigMid = (byte[])bigPack.Clone(); bigMid[PackReader.Chunk + 100] ^= 1;
            check(Throws<PackException>(() => PackReader.Read(new MemoryStream(bigMid), bigMid.Length, key, pair), out m), "pack: a changed byte after the first chunk fails");
            check(Throws<PackException>(() => PackReader.Read(new MemoryStream(bigPack), bigPack.Length, OtherKey, pair), out m), "pack: a wrong key fails on a big pack");

            // what the engine refuses
            check(Throws<PackException>(() => { var p = TestWriter.Pack(zip, key, declaredLen: zip.Length - 10); PackReader.Read(new MemoryStream(p), p.Length, key, n => true); }, out m), "pack: a ZIP longer than the header says is refused");
            check(Throws<PackException>(() => { var p = TestWriter.Pack(zip, key, declaredLen: zip.Length + 10); PackReader.Read(new MemoryStream(p), p.Length, key, n => true); }, out m), "pack: a ZIP shorter than the header says is refused");
            check(Throws<PackException>(() => { var p = TestWriter.Pack(zip, key, declaredLen: 1L << 40); PackReader.Read(new MemoryStream(p), p.Length, key, n => true); }, out m) && m == "length mismatch", "pack: a header that claims more than deflate can give is refused before inflating");
            check(Throws<PackException>(() => { var p = TestWriter.Pack(TestWriter.Zip(entries, method: 8), key); PackReader.Read(new MemoryStream(p), p.Length, key, n => true); }, out m) && m.Contains("not stored"), "pack: a member that is not stored is refused (" + m + ")");
            check(Throws<PackException>(() => { var p = TestWriter.Pack(TestWriter.Zip(entries, flags: 8), key); PackReader.Read(new MemoryStream(p), p.Length, key, n => true); }, out m), "pack: a member with a data descriptor is refused");
            foreach (string evil in new[] { "../x", "/abs", "a/../b", "a\\b", "c:x", "a//b" })
            {
                var e2 = new List<KeyValuePair<string, byte[]>> { new KeyValuePair<string, byte[]>(evil, new byte[3]) };
                check(Throws<PackException>(() => { var p = TestWriter.Pack(TestWriter.Zip(e2), key); PackReader.Read(new MemoryStream(p), p.Length, key, n => false); }, out m), "pack: the entry name '" + evil + "' is refused");
            }
            var twice = new List<KeyValuePair<string, byte[]>> { new KeyValuePair<string, byte[]>("a.txt", new byte[1]), new KeyValuePair<string, byte[]>("a.txt", new byte[2]) };
            check(Throws<PackException>(() => { var p = TestWriter.Pack(TestWriter.Zip(twice), key); PackReader.Read(new MemoryStream(p), p.Length, key, n => true); }, out m), "pack: one name twice is refused");
        }

        static void Index(Action<bool, string> check)
        {
            var s = MakeShards(7, 3);
            var idx = SprShardIndex.Parse(s.IndexText);
            check(idx.Signature == s.Signature && idx.Total == 7 && idx.Shards.Count == 3 && idx.Shards[2].First == 7 && idx.Shards[2].Count == 1, "index: signature, total and the three ranges (3, 3, 1)");
            check(idx.Find(1).Name == "Tibia.000.spr" && idx.Find(3).Name == "Tibia.000.spr" && idx.Find(4).Name == "Tibia.001.spr" && idx.Find(7).Name == "Tibia.002.spr" && idx.Find(8) == null && idx.Find(0) == null, "index: an id finds its shard, ids outside find none");
            string m;
            check(Throws<ProtocolException>(() => SprShardIndex.Parse("chaos-spr-shards 2\n"), out m), "index: another format line is refused");
            check(Throws<ProtocolException>(() => SprShardIndex.Parse(s.IndexText.Replace("shard 4 3", "shard 5 3")), out m) && m.Contains("expected 4"), "index: a gap between shards is refused (" + m + ")");
            check(Throws<ProtocolException>(() => SprShardIndex.Parse(s.IndexText.Replace("sprites 7", "sprites 9")), out m), "index: shards that do not hold exactly the sprites named are refused");
            check(Throws<ProtocolException>(() => SprShardIndex.Parse(s.IndexText.Replace("Tibia.001.spr", "../Tibia.001.spr")), out m), "index: a path in a shard name is refused");
            check(Throws<ProtocolException>(() => SprShardIndex.Parse(s.IndexText.Replace("Tibia.001.spr", ".hidden")), out m), "index: a hidden shard name is refused");
            check(Throws<ProtocolException>(() => SprShardIndex.Parse(s.IndexText + "mystery 1\n"), out m), "index: an unknown line is refused");
            check(Throws<ProtocolException>(() => SprShardIndex.Parse(s.IndexText.Replace("signature 19035\n", "")), out m), "index: a missing signature is refused");
            check(Throws<ProtocolException>(() => SprShardIndex.Parse("chaos-spr-shards 1\nsignature 1\nsprites 3\nshard 1 3 Tibia.000.spr 10 aa\n"), out m), "index: a shard too small for its address table is refused");
            check(SprShardIndex.Parse("# note\n\n" + s.IndexText.Replace("\n", "\r\n")).Shards.Count == 3, "index: comments, blank lines and CRLF are read");
        }

        static void ShardSets(Action<bool, string> check)
        {
            var s = MakeShards(23, 4);
            var idx = SprShardIndex.Parse(s.IndexText);
            var files = new Dictionary<string, byte[]>();
            foreach (var kv in s.Files) files[kv.Key] = kv.Value;
            using (var single = new SprFile(new MemoryStream(s.Single)))
            using (var sharded = new SprFile(new SprShardSet(idx, sh => new MemoryStream(files[sh.Name], false))))
            {
                check(sharded.Count == 23 && sharded.Signature == s.Signature, "shards: the sharded file has the index's count and signature");
                bool same = true;
                for (uint id = 0; id <= 25; id++)
                {
                    byte[] a = single.Rgba(id), b = sharded.Rgba(id);
                    same &= (a == null) == (b == null) && (a == null || Same(a, b));
                }
                check(same, "shards: every id (empty ids and ids out of range included) gives the pixels of the single file");
                check(sharded.Rgba(1) != null && sharded.Rgba(6) != null && sharded.Rgba(5) == null, "shards: ids on a shard edge and an empty id");
            }

            // only a few shards stay open: the least recently used closes first
            var set = new SprShardSet(idx, sh => new MemoryStream(files[sh.Name], false), 2);
            using (var f = new SprFile(set))
            {
                f.Rgba(1); f.Rgba(5); f.Rgba(9);
                check(set.ResidentCount == 2 && set.Opens == 3, "shards: three shards used, two kept (" + set.ResidentCount + " open, " + set.Opens + " opens)");
                f.Rgba(9); f.Rgba(5);
                check(set.Opens == 3, "shards: the two most recent shards are still there");
                f.Rgba(1);
                check(set.Opens == 4 && set.ResidentCount == 2, "shards: the first one had to be opened again");
            }

            // a shard that does not fit the index draws nothing and says why; the others are fine
            var broken = new Dictionary<string, byte[]>(files);
            broken["Tibia.001.spr"] = new byte[files["Tibia.001.spr"].Length];                      // right size, empty header
            broken["Tibia.002.spr"] = files["Tibia.002.spr"].AsSpan(0, files["Tibia.002.spr"].Length - 2).ToArray();   // short
            using (var f = new SprFile(new SprShardSet(idx, sh => new MemoryStream(broken[sh.Name], false))))
            {
                check(f.Rgba(1) != null && f.Rgba(6) == null && f.ShardError != null && f.ShardError.Contains("Tibia.001.spr"), "shards: a shard with a wrong header draws nothing (" + f.ShardError + ")");
                check(f.Rgba(10) == null && f.ShardError.Contains("Tibia.002.spr") && f.ShardError.Contains("bytes"), "shards: a short shard draws nothing (" + f.ShardError + ")");
                check(f.Rgba(2) != null, "shards: the shards before it still draw");
            }
        }

        // ------------------------------------------------------------------------------------------------ the locator

        static void Locator(Action<bool, string> check)
        {
            byte[] key = FixtureKey;
            var shards = MakeShards(23, 4);
            byte[] dat = Program.SyntheticDat();
            const string root = "/game", unity = "/game/unity", things = "/game/unity/things", enc = "/game/unity/things_enc";
            Func<SprFile, bool> drawsAll = spr =>
            {
                using (var single = new SprFile(new MemoryStream(shards.Single)))
                {
                    for (uint id = 0; id <= 24; id++) { var a = single.Rgba(id); var b = spr.Rgba(id); if ((a == null) != (b == null) || (a != null && !Same(a, b))) return false; }
                    return true;
                }
            };

            Func<bool, bool, bool, MemFs> make = (loose, blobs, pack) =>
            {
                var fs = new MemFs();
                if (loose)
                {
                    fs.Files[J(things, "Tibia.dat")] = dat;
                    fs.Files[J(things, "Tibia.sprshards")] = Encoding.UTF8.GetBytes(shards.IndexText);
                    foreach (var kv in shards.Files) fs.Files[J(things, kv.Key)] = kv.Value;
                }
                if (blobs)
                {
                    fs.Files[J(enc, "Tibia.dat.chub")] = TestWriter.Blob(dat, key);
                    fs.Files[J(enc, "Tibia.sprshards.chub")] = TestWriter.Blob(Encoding.UTF8.GetBytes(shards.IndexText), key);
                    foreach (var kv in shards.Files) fs.Files[J(enc, kv.Key + ".chub")] = TestWriter.Blob(kv.Value, key);
                }
                if (pack)
                {
                    var e = new List<KeyValuePair<string, byte[]>>
                    {
                        new KeyValuePair<string, byte[]>("init.lua", Encoding.ASCII.GetBytes("-- init\n")),
                        new KeyValuePair<string, byte[]>("data/things/1098/Tibia.dat", dat),
                        new KeyValuePair<string, byte[]>("data/things/1098/Tibia.sprshards", Encoding.UTF8.GetBytes(shards.IndexText)),
                    };
                    foreach (var kv in shards.Files) e.Add(new KeyValuePair<string, byte[]>("data/things/1098/" + kv.Key, kv.Value));
                    fs.Files[J(root, "chaos.pack")] = TestWriter.Pack(TestWriter.Zip(e), key);
                }
                return fs;
            };
            Func<PairRequest> req = () => new PairRequest { InstallDir = unity, LooseDir = things, Key = key };

            // order: flag, loose, blobs, main pack
            var fs1 = make(true, true, true);
            var r = PairLocator.Find(new PairRequest { InstallDir = unity, LooseDir = things, Key = key, FlagDir = things }, fs1);
            check(r.Ok && r.Origin == PairOrigin.Flag && N(r.Where) == things, "locator: -chaosThings first");
            fs1.Files[J("/elsewhere", "Tibia.dat")] = dat;
            r = PairLocator.Find(new PairRequest { InstallDir = unity, LooseDir = things, Key = key, FlagDir = "/elsewhere" }, fs1);
            check(!r.Ok && r.Origin == PairOrigin.None && r.Error.Contains("-chaosThings /elsewhere") && r.Error.Contains("Tibia.spr"), "locator: a wrong -chaosThings folder is an error, not a fall back (" + r.Error + ")");
            r = PairLocator.Find(req(), fs1);
            check(r.Ok && r.Origin == PairOrigin.Loose && drawsAll(r.Spr) && r.Dat.Item(100).Ground, "locator: loose files in things/ beat blobs and the pack, and draw the pair");
            var fs2 = make(false, true, true);
            r = PairLocator.Find(req(), fs2);
            check(r.Ok && r.Origin == PairOrigin.Blobs && N(r.Where) == enc && drawsAll(r.Spr) && r.Dat.Item(100).Ground, "locator: encrypted blobs of the install beat the main client's pack, and draw the pair");
            var fs3 = make(false, false, true);
            r = PairLocator.Find(req(), fs3);
            check(r.Ok && r.Origin == PairOrigin.MainPack && N(r.Where) == J(root, "chaos.pack") && drawsAll(r.Spr) && r.Dat.Item(100).Ground, "locator: the main client's chaos.pack above the player's folder, and draw the pair");
            var fs3b = new MemFs(); fs3b.Files[J(unity, "chaos.pack")] = fs3.Files[J(root, "chaos.pack")];
            r = PairLocator.Find(req(), fs3b);
            check(r.Ok && r.Origin == PairOrigin.MainPack && N(r.Where) == J(unity, "chaos.pack"), "locator: a chaos.pack beside the player is found too");
            var fs3c = new MemFs(); fs3c.Files["/anywhere/main.pack"] = fs3.Files[J(root, "chaos.pack")];
            r = PairLocator.Find(new PairRequest { InstallDir = unity, Key = key, PackFile = "/anywhere/main.pack" }, fs3c);
            check(r.Ok && r.Origin == PairOrigin.MainPack && N(r.Where) == "/anywhere/main.pack", "locator: -chaosPack FILE");
            var cands = PairLocator.PackCandidates(new PairRequest { InstallDir = unity + "/", PackFile = "/p.pack" });
            check(cands.Count == 3 && N(cands[0]) == "/p.pack" && N(cands[1]) == J(root, "chaos.pack") && N(cands[2]) == J(unity, "chaos.pack"), "locator: the pack is looked for in the flag, above the player, then beside it");

            // a missing things/ folder is normal; nothing at all is an error that says where it looked
            r = PairLocator.Find(req(), new MemFs());
            check(!r.Ok && r.Error.Contains("no loose pair") && r.Error.Contains("things_enc") && r.Error.Contains("chaos.pack"), "locator: nothing found says where it looked (" + r.Error + ")");

            // wrong key: both encrypted routes fail, cleanly, with no key in the text
            var fs4 = make(false, true, true);
            r = PairLocator.Find(new PairRequest { InstallDir = unity, LooseDir = things, Key = OtherKey }, fs4);
            check(!r.Ok && r.Error.Contains("things_enc") && r.Error.Contains("wrong key") && r.Error.Contains("chaos.pack") && !r.Error.Contains(FixtureKeyHex), "locator: a wrong key fails both routes cleanly (" + r.Error + ")");
            r = PairLocator.Find(new PairRequest { InstallDir = unity, LooseDir = things, Key = OtherKey, KeyIsDev = true }, fs4);
            check(!r.Ok && r.Error.Contains("development package") && r.Error.Contains("-chaosThings"), "locator: a development package is told why and what to do");
            r = PairLocator.Find(new PairRequest { InstallDir = unity, LooseDir = things }, fs4);
            check(!r.Ok && r.Error.Contains("no client key"), "locator: no key at all");
            r = PairLocator.Find(new PairRequest { InstallDir = unity, LooseDir = things, Key = OtherKey, KeyIsDev = false }, make(true, true, true));
            check(r.Ok && r.Origin == PairOrigin.Loose, "locator: loose files need no key");

            // the blob route
            var fs5 = make(false, true, false);
            fs5.Files.Remove(J(enc, "Tibia.002.spr.chub"));
            r = PairLocator.Find(req(), fs5);
            check(!r.Ok && r.Error.Contains("Tibia.002.spr.chub"), "locator: a missing shard blob fails at the start (" + r.Error + ")");
            var fs6 = make(false, true, false);
            var tampered = (byte[])fs6.Files[J(enc, "Tibia.001.spr.chub")].Clone(); tampered[60] ^= 1;
            fs6.Files[J(enc, "Tibia.001.spr.chub")] = tampered;
            r = PairLocator.Find(req(), fs6);
            check(r.Ok && r.Spr.Rgba(1) != null && r.Spr.Rgba(6) == null && r.Spr.ShardError.Contains("Tibia.001.spr") && !r.Spr.ShardError.Contains(FixtureKeyHex), "locator: a changed shard blob draws nothing and the rest does (" + r.Spr.ShardError + ")");
            var fs7 = make(false, true, false);
            var tdat = (byte[])fs7.Files[J(enc, "Tibia.dat.chub")].Clone(); tdat[40] ^= 1; fs7.Files[J(enc, "Tibia.dat.chub")] = tdat;
            r = PairLocator.Find(req(), fs7);
            check(!r.Ok && r.Error.Contains("wrong key"), "locator: a changed Tibia.dat blob fails (" + r.Error + ")");
            var fs8 = make(false, true, false);
            var rq = req(); rq.MaxResidentShards = 2;
            r = PairLocator.Find(rq, fs8);
            for (uint id = 1; id <= 23; id++) r.Spr.Rgba(id);
            r.Spr.Dispose();
            check(r.Ok, "locator: blob shards are opened one by one as ids ask for them");

            // loose files as the engine reads them: shards, a broken set falls back to the single file
            var fs9 = make(true, false, false);
            fs9.Files.Remove(J(things, "Tibia.003.spr"));
            fs9.Files[J(things, "Tibia.spr")] = shards.Single;
            r = PairLocator.Find(req(), fs9);
            check(r.Ok && r.Origin == PairOrigin.Loose && drawsAll(r.Spr), "locator: loose shards with one missing fall back to the single Tibia.spr, as the engine does");
            fs9.Files.Remove(J(things, "Tibia.spr"));
            r = PairLocator.Find(req(), fs9);
            check(!r.Ok && r.Error.Contains("missing shard"), "locator: loose shards with one missing and no single file fail (" + r.Error + ")");
            var fs10 = new MemFs(); fs10.Files[J(things, "Tibia.dat")] = dat; fs10.Files[J(things, "Tibia.spr")] = shards.Single;
            r = PairLocator.Find(req(), fs10);
            check(r.Ok && r.Origin == PairOrigin.Loose && drawsAll(r.Spr), "locator: the plain pair of things/ still works");

            // the pack names: the newest things folder wins; only the pair is kept
            string v, f;
            check(PairLocator.WantedEntry("data/things/1098/Tibia.dat", out v, out f) && v == "1098" && f == "Tibia.dat", "locator: Tibia.dat of a pack is wanted");
            check(PairLocator.WantedEntry("data/things/1098/Tibia.012.spr", out v, out f) && PairLocator.WantedEntry("data/things/1098/Tibia.sprshards", out v, out f), "locator: shards and their index are wanted");
            check(!PairLocator.WantedEntry("data/things/1098/Tibia.otfi", out v, out f) && !PairLocator.WantedEntry("data/images/Tibia.dat", out v, out f) && !PairLocator.WantedEntry("data/things/x/Tibia.dat", out v, out f) && !PairLocator.WantedEntry("modules/Tibia.dat", out v, out f), "locator: nothing else is wanted");
        }
    }
}
