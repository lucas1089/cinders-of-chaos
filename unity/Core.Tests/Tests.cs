// Unit tests of the engine-free core. Vectors for XTEA, Adler-32, RSA and the client guard MAC come from
// server/tools/loadtest.py, the protocol client the load tests use against the real server.
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace Chaos.Core.Tests
{
    static class Program
    {
        static int failures;
        static int checks;

        static void Check(bool ok, string what)
        {
            checks++;
            if (!ok)
            {
                failures++;
                Console.WriteLine("FAIL: " + what);
            }
        }

        static string Hex(byte[] b, int off = 0, int n = -1)
        {
            if (n < 0) n = b.Length - off;
            var sb = new StringBuilder();
            for (int i = off; i < off + n; i++) sb.Append(b[i].ToString("x2"));
            return sb.ToString();
        }

        static int Main(string[] args)
        {
            if (args.Length > 0 && args[0] == "probe") return Probe.Run(args);
            if (args.Length > 0 && args[0] == "live") return LiveProbe.Run(args);
            CryptoChecks();
            ByteChecks();
            DatChecks();
            SprChecks();
            foreach (var t in Suites) t(Check);
            Console.WriteLine(failures == 0 ? "core tests: ok (" + checks + " checks)" : "core tests: " + failures + " of " + checks + " failed");
            return failures == 0 ? 0 : 1;
        }

        /// <summary>Further suites (protocol, map) register here.</summary>
        public static readonly List<Action<Action<bool, string>>> Suites = new List<Action<Action<bool, string>>>
        {
            ProtocolTests.Run,
            ExtTests.Run,
            WindowTests.Run,
            Hd2dTests.Run,
            RuinsTests.Run,
            CharsTests.Run,
            World3dTests.Run,
            FrontArtTests.Run,
            FrontLiveTests.Run,
            FrontLooksTests.Run,
            FrontFxTests.Run,
            NpcTests.Run,
            ProgressionTests.Run,
            PartyTests.Run,
            ChatTests.Run,
            HudTests.Run,
            ItemTests.Run,
            HelperTests.Run,
            SocialTests.Run,
            EndgameTests.Run,
            CollectTests.Run,
            WorldTests.Run,
            InfoTests.Run,
        };

        static void CryptoChecks()
        {
            uint[] key = { 0x01234567, 0x89abcdef, 0xfedcba98, 0x76543210 };
            var data = new byte[24];
            for (int i = 0; i < 24; i++) data[i] = (byte)i;
            Xtea.Encrypt(data, 0, 24, key);
            Check(Hex(data) == "e490d158660e3f4f65cdd38e97a90d15fa7433f92a81faf2", "xtea encrypt matches loadtest.py: " + Hex(data));
            Xtea.Decrypt(data, 0, 24, key);
            bool same = true;
            for (int i = 0; i < 24; i++) same &= data[i] == i;
            Check(same, "xtea decrypt round trip");

            var text = Encoding.ASCII.GetBytes(string.Concat(System.Linq.Enumerable.Repeat("Cinders of Chaos", 100)));
            Check(Adler32.Of(text, 0, text.Length) == 0xcf4d436b, "adler32 matches zlib");

            var rsa = new Rsa(Protocol.OpenRsaModulus);
            Check(rsa.Size == 128, "rsa size 128");
            var block = new byte[128];
            Encoding.ASCII.GetBytes("hello").CopyTo(block, 1);
            byte[] enc = rsa.Encrypt(block);
            Check(Hex(enc, 0, 16) == "99573cec773b72c909f8a09fbf310e9e" && Hex(enc, 120, 8) == "22c151841593a528",
                  "rsa block matches loadtest.py: " + Hex(enc, 0, 16));

            byte[] mac = ClientGuard.Mac(Encoding.ASCII.GetBytes(new string('k', 32)), new byte[16], "acc", "Char", 7);
            Check(Hex(mac) == "8415a93882d40df2246b361759457ed0fe19e82948015a3a35045e7576a8b89f", "guard mac matches loadtest.py");
        }

        static void ByteChecks()
        {
            var w = new ByteWriter().U8(1).U16(0x1234).U32(0xdeadbeef).Str("Ação");
            var r = new ByteReader(w.ToArray());
            Check(r.U8() == 1 && r.U16() == 0x1234 && r.U32() == 0xdeadbeef && r.Str() == "Ação" && r.AtEnd, "byte writer and reader agree (latin-1 text)");
            bool threw = false;
            try { r.U8(); } catch (ProtocolException) { threw = true; }
            Check(threw, "reading past the end throws");
        }

        internal static byte[] SyntheticDat()
        {
            var w = new ByteWriter().U32(0x42a3).U16(101).U16(1).U16(1).U16(1);
            // item 100: ground speed 150, 1x1, one sprite (id 7)
            w.U8(0).U16(150).U8(0xFF).U8(1).U8(1).U8(1).U8(1).U8(1).U8(1).U8(1).U32(7);
            // item 101: stackable, custom flag 39 (16 bytes), market, 2x1 exact 64, 2 phases with durations
            w.U8(5).U8(39).Zeros(16).U8(34).U16(1).U16(101).U16(101).Str("coin").U16(0).U16(0).U8(0xFF);
            w.U8(2).U8(1).U8(64).U8(1).U8(1).U8(1).U8(1).U8(2);
            w.U8(1).U32(0xFFFFFFFF).U8(0).U32(100).U32(200).U32(150).U32(150);
            for (uint i = 1; i <= 4; i++) w.U32(i);
            // outfit 1: two frame groups, 1x1, 4 directions (pattern x 4), idle 1 phase / moving 2 phases
            w.U8(0xFF).U8(2);
            w.U8(0).U8(1).U8(1).U8(1).U8(4).U8(1).U8(1).U8(1);
            for (uint i = 0; i < 4; i++) w.U32(10 + i);
            w.U8(1).U8(1).U8(1).U8(1).U8(4).U8(1).U8(1).U8(2).U8(1).U32(0).U8(0).U32(50).U32(50).U32(50).U32(50);
            for (uint i = 0; i < 8; i++) w.U32(20 + i);
            // effect 1, missile 1: 1x1, one sprite
            w.U8(0xFF).U8(1).U8(1).U8(1).U8(1).U8(1).U8(1).U8(1).U32(30);
            w.U8(0xFF).U8(1).U8(1).U8(1).U8(1).U8(1).U8(1).U8(1).U32(31);
            return w.ToArray();
        }

        static void DatChecks()
        {
            var dat = DatFile.Parse(SyntheticDat());
            Check(dat.Signature == 0x42a3, "dat signature");
            var ground = dat.Item(100);
            Check(ground.Ground && ground.GroundSpeed == 150 && ground.Idle.Sprites[0] == 7, "dat ground item");
            var coin = dat.Item(101);
            Check(coin.Stackable && coin.HasSubType && coin.Idle.Width == 2 && coin.Idle.ExactSize == 64 && coin.Idle.Phases == 2, "dat stackable 2x1 item");
            Check(coin.Idle.MinDuration[1] == 150 && coin.Idle.LoopCount == -1 && !coin.Idle.Async, "dat frame durations");
            Check(coin.Idle.Sprite(1, 0, 0, 0, 0, 0, 1) == 4, "dat sprite index (w 1, phase 1)");
            var o = dat.Outfit(1);
            Check(o.Groups.Length == 2 && o.Idle.Phases == 1 && o.Moving.Phases == 2, "dat outfit frame groups");
            Check(o.Moving.Sprite(0, 0, 0, 3, 0, 0, 1) == 27, "dat outfit sprite (west, phase 1)");
            Check(dat.Effect(1).Idle.Sprites[0] == 30 && dat.Missile(1).Idle.Sprites[0] == 31, "dat effects and missiles");

            byte[] bad = SyntheticDat();
            Array.Resize(ref bad, bad.Length + 1);
            bool threw = false;
            try { DatFile.Parse(bad); } catch (ProtocolException) { threw = true; }
            Check(threw, "dat with trailing bytes is refused");
        }

        static void SprChecks()
        {
            // one sprite: 2 transparent pixels, then 2 coloured (RGBA), rest transparent
            var rec = new ByteWriter().U16(2).U16(2).U8(255).U8(0).U8(0).U8(255).U8(0).U8(255).U8(0).U8(128).ToArray();
            var file = new ByteWriter().U32(0x1234).U32(2).U32(16).U32(0).Raw(new byte[] { 255, 0, 255 }).U16((ushort)rec.Length).Raw(rec).ToArray();
            using var spr = new SprFile(new MemoryStream(file));
            Check(spr.Count == 2 && spr.Signature == 0x1234, "spr header");
            byte[] px = spr.Rgba(1);
            Check(px != null && px[3] == 0 && px[8] == 255 && px[11] == 255 && px[13] == 255 && px[15] == 128 && px[19] == 0, "spr pixels decoded");
            Check(spr.Rgba(2) == null && spr.Rgba(3) == null && spr.Rgba(0) == null, "spr empty and out of range ids");
        }
    }
}
