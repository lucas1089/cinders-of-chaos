// Extended opcodes (JSON, chunks, dispatcher), the client identity and the Chaos parts of the parser (feature list,
// extended outfits, item attributes, 0x4B floors, spell cooldowns), the spell model and the UI texts.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class ExtTests
    {
        static bool Throws<T>(Action a) where T : Exception
        {
            try { a(); } catch (T) { return true; }
            return false;
        }

        public static void Run(Action<bool, string> check)
        {
            JsonChecks(check);
            WireChecks(check);
            ChunkChecks(check);
            IdentityChecks(check);
            ParserChecks(check);
            SpellChecks(check);
            LocChecks(check);
        }

        // ------------------------------------------------------------------------------------ JSON
        static void JsonChecks(Action<bool, string> check)
        {
            var v = Json.Parse(" {\"action\":\"open\",\"data\":{\"level\":42,\"xp\":1.5e2,\"neg\":-3,\"ok\":true,\"no\":false,\"nil\":null," +
                               "\"list\":[1,[2,3],{\"a\":\"b\"}],\"empty\":{},\"none\":[]}} ");
            var data = Json.Get(v, "data");
            check(Json.Text(v, "action") == "open" && Json.Int(data, "level") == 42 && Json.Number(data, "xp") == 150 &&
                  Json.Int(data, "neg") == -3 && Json.Bool(data, "ok") && !Json.Bool(data, "no") && Json.Get(data, "nil") == null,
                  "json: object, numbers, booleans, null");
            var list = Json.List(data, "list");
            check(list.Count == 3 && ((List<object>)list[1]).Count == 2 && Json.Text(list[2], "a") == "b" &&
                  Json.List(data, "none").Count == 0 && ((Dictionary<string, object>)Json.Get(data, "empty")).Count == 0 &&
                  Json.List(data, "missing").Count == 0, "json: arrays, empty values, a missing key");

            check(Json.Text(Json.Parse("{\"t\":\"a\\\"b\\\\c\\/d\\n\\t\\u00e7\\u0041\"}"), "t") == "a\"b\\c/d\n\tçA", "json: escapes");
            check(Json.Text(Json.Parse("{\"t\":\"\\ud83d\\ude00 ação\"}"), "t") == "\U0001F600 ação", "json: a surrogate pair and raw non-ASCII");

            string text = Json.Serialize(new Dictionary<string, object>
            {
                { "n", 7 }, { "f", 0.25 }, { "d", 3.0 }, { "big", 4294967295u }, { "s", "line\n\"q\" \u0001 ç" }, { "b", true }, { "z", null },
                { "l", new List<object> { 1, "x", new Dictionary<string, object>() } },
            });
            check(text == "{\"n\":7,\"f\":0.25,\"d\":3,\"big\":4294967295,\"s\":\"line\\n\\\"q\\\" \\u0001 ç\",\"b\":true,\"z\":null,\"l\":[1,\"x\",{}]}",
                  "json: serialize: " + text);
            var back = Json.Parse(text);
            check(Json.Serialize(back) == text, "json: parse then serialize gives the same text");

            string[] bad = { "", "{", "{\"a\"}", "{\"a\":}", "[1,]", "[1 2]", "{\"a\":1,}", "tru", "nul", "01x", "-", "1.", "1e", "\"abc", "\"\\x\"",
                             "\"\\u12\"", "\"a\nb\"", "{} x", "{1:2}", "[1]]", "NaN", "'a'" };
            int refused = bad.Count(b => Throws<Json.JsonException>(() => Json.Parse(b)));
            check(refused == bad.Length, "json: " + bad.Length + " broken texts are refused (" + refused + ")");
            check(Throws<Json.JsonException>(() => Json.Parse(new string('[', 70) + new string(']', 70))), "json: nesting over 64 is refused");
            check(Json.Parse(new string('[', 60) + new string(']', 60)) != null, "json: nesting of 60 is fine");
            check(Json.TryParse("{oops") == null && Json.TryParse(null) == null, "json: TryParse answers null");
            check(Throws<Json.JsonException>(() => Json.Serialize(double.NaN)) && Throws<Json.JsonException>(() => Json.Serialize(new object())),
                  "json: NaN and unknown types are not written");
        }

        // ------------------------------------------------------------------------------------ the wire
        static void WireChecks(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var sent = new List<byte[]>();
            ext.Transmit = p => sent.Add(p);
            ext.Send(219, "open", new Dictionary<string, object> { { "have", "abc" } });
            string json = "{\"action\":\"open\",\"data\":{\"have\":\"abc\"}}";
            var expect = new byte[] { 0x32, 219, (byte)json.Length, 0 }.Concat(Encoding.ASCII.GetBytes(json)).ToArray();
            check(sent.Count == 1 && sent[0].SequenceEqual(expect), "ext: Send is 0x32, opcode, u16 length, the JSON bytes");
            ext.Send(10, "hello");
            check(Encoding.UTF8.GetString(sent[1], 4, sent[1].Length - 4) == "{\"action\":\"hello\"}", "ext: no data member when there is none");
            ext.SendText(224, "ação");
            check(sent[2].Skip(2).Take(2).SequenceEqual(new byte[] { 6, 0 }) && sent[2].Length == 4 + 6 && sent[2][5] == 0xC3, "ext: text goes out as UTF-8 (ação = 6 bytes)");
            var logs = new List<string>();
            ext.Log = logs.Add;
            check(!ext.SendText(5, new string('x', ExtOpcodes.MaxRequestBytes + 1)) && sent.Count == 3 && logs.Count == 1, "ext: a request over 16384 bytes is not sent");
            check(ext.SendText(5, new string('x', ExtOpcodes.MaxRequestBytes)) && sent.Count == 4, "ext: 16384 bytes go");

            // through the packet layer: a payload with two messages, encrypted and read back by the parser
            var key = new uint[] { 1, 2, 3, 4 };
            var wire = new ByteWriter().U8(0x32).U8(7).Str(ExtOpcodes.ToWire("{\"action\":\"hi\",\"data\":{\"t\":\"ação\"}}")).U8(0x32).U8(8).Str("es:30:120").ToArray();
            var enc = Protocol.Encrypt(wire, key);
            var parser = new GameParser(new World(DatFile.Parse(Program.SyntheticDat())));
            var inbox = new ExtOpcodes();
            ExtMessage got = null;
            string plainText = null;
            inbox.On(7, m => got = m);
            inbox.OnText(8, t => plainText = t);
            parser.ExtendedOpcode = inbox.Receive;
            parser.Parse(Protocol.Decrypt(enc.Skip(2).ToArray(), key));
            check(got != null && got.Action == "hi" && Json.Text(got.Data, "t") == "ação" && plainText == "es:30:120" && inbox.Received == 2,
                  "ext: two messages of one encrypted packet reach their handlers (UTF-8 and plain text)");

            // errors: invalid JSON is counted and logged, a throwing handler does not stop the next one
            var d = new ExtOpcodes();
            var dl = new List<string>();
            d.Log = dl.Add;
            int calls = 0;
            d.On(3, m => throw new InvalidOperationException("boom"));
            d.On(3, m => calls++);
            d.Receive(3, "{\"action\":\"a\"}");
            check(calls == 1 && dl.Count == 1 && dl[0].Contains("boom"), "ext: a handler that throws is logged, the next one runs");
            d.Receive(3, "not json");
            d.Receive(3, "[1,2]");
            d.Receive(4, "{\"action\":\"nobody listens\"}");
            check(d.Invalid == 2 && calls == 1 && d.Handles(3) && !d.Handles(4), "ext: invalid JSON (and a non-object) is dropped, an opcode with no handler is ignored");
            check(ExtOpcodes.FromWire(ExtOpcodes.ToWire("ação \U0001F600")) == "ação \U0001F600", "ext: wire string round trip");
        }

        // ------------------------------------------------------------------------------------ chunks
        static void ChunkChecks(Action<bool, string> check)
        {
            // the server's Chaos.splitExtended: a text that fits stays whole, else parts of 8000 bytes: S, P..., E
            string small = new string('a', 8192);
            check(ExtChunks.Split(small).Count == 1 && ExtChunks.Split(small)[0] == small, "chunks: 8192 bytes are not split");
            string big = "{\"action\":\"state\",\"data\":{\"t\":\"" + string.Concat(Enumerable.Repeat("0123456789", 2500)) + "\"}}";
            var parts = ExtChunks.Split(big);
            check(parts.Count == 4 && parts[0][0] == 'S' && parts[1][0] == 'P' && parts[2][0] == 'P' && parts[3][0] == 'E' &&
                  parts.All(p => p.Length <= 8192) && parts[0].Length == 8001, "chunks: " + big.Length + " bytes make S, P, P, E of at most 8001 each (" + parts.Count + ")");

            var c = new ExtChunks();
            string whole = null;
            int done = 0;
            foreach (var p in parts) { var r = c.Feed(50, p); if (r != null) { whole = r; done++; } }
            check(done == 1 && whole == big, "chunks: the parts join to the text, delivered once at E");
            check(c.Feed(50, "{\"x\":1}") == "{\"x\":1}", "chunks: a whole message passes as it is");

            // two opcodes interleave without mixing
            var a = ExtChunks.Split(ExtOpcodes.ToWire(big));
            var b = ExtChunks.Split(ExtOpcodes.ToWire(big.Replace("0123", "ç123")));
            string ra = null, rb = null;
            for (int i = 0; i < Math.Max(a.Count, b.Count); i++)
            {
                if (i < a.Count) ra = c.Feed(1, a[i]) ?? ra;
                if (i < b.Count) rb = c.Feed(2, b[i]) ?? rb;
            }
            check(ra == ExtOpcodes.ToWire(big) && rb == ExtOpcodes.ToWire(big.Replace("0123", "ç123")), "chunks: opcodes keep their own chains");

            // as the main client: a part with no start is dropped; a start again restarts; a whole message ends a chain
            var d = new ExtChunks();
            check(d.Feed(9, "Pabc") == null && d.Feed(9, "Eabc") == null && d.Dropped == 2, "chunks: P and E without S are dropped and counted");
            d.Feed(9, "Sone");
            check(d.Feed(9, "Stwo") == null && d.Feed(9, "Ethree") == "twothree", "chunks: a second S starts the text again");
            d.Feed(9, "Sjunk");
            check(d.Feed(9, "{\"whole\":1}") == "{\"whole\":1}" && d.Feed(9, "Eend") == null, "chunks: a whole message forgets an open chain");
            check(d.Feed(9, "") == "", "chunks: an empty string is a whole message");
            var small2 = new ExtChunks { MaxChars = 10 };
            small2.Feed(1, "Sabcdef");
            check(small2.Feed(1, "Pghijkl") == null && small2.Feed(1, "Eend") == null && small2.Dropped >= 2, "chunks: a chain over the limit is dropped");

            // a multi-byte character cut by a part boundary is whole again after the join
            string prefix = "{\"action\":\"t\",\"data\":{\"v\":\"";
            int n = 7999 - prefix.Length;   // the first byte of the two-byte ç is the last byte of the first part
            string text = prefix + new string('x', n) + "ç and more" + new string('y', 400) + "\"}}";
            string wire = ExtOpcodes.ToWire(text);
            var cut = ExtChunks.Split(wire);
            var ext = new ExtOpcodes();
            ExtMessage m = null;
            ext.On(77, x => m = x);
            foreach (var p in cut) ext.Receive(77, p);
            check(cut.Count == 2 && cut[0][cut[0].Length - 1] == '\u00C3' && m != null && Json.Text(m.Data, "v").EndsWith("ç and more" + new string('y', 400)) && Json.Text(m.Data, "v").Length == n + 410,
                  "chunks: a UTF-8 character across the cut is whole after the join");

            // the whole thing through three encrypted packets
            var key = new uint[] { 9, 8, 7, 6 };
            var ext2 = new ExtOpcodes();
            ExtMessage got = null;
            ext2.On(120, x => got = x);
            var parser = new GameParser(new World(DatFile.Parse(Program.SyntheticDat()))) { ExtendedOpcode = ext2.Receive };
            var bigWire = ExtOpcodes.ToWire("{\"action\":\"catalog\",\"data\":{\"rows\":[" + string.Join(",", Enumerable.Range(0, 3000).Select(i => "{\"i\":" + i + ",\"n\":\"item ç" + i + "\"}")) + "]}}");
            var pieces = ExtChunks.Split(bigWire);
            foreach (var piece in pieces)
            {
                var pk = Protocol.Encrypt(new ByteWriter().U8(0x32).U8(120).Str(piece).ToArray(), key);
                parser.Parse(Protocol.Decrypt(pk.Skip(2).ToArray(), key));
            }
            var rows = got == null ? null : Json.List(got.Data, "rows");
            check(pieces.Count > 2 && rows != null && rows.Count == 3000 && Json.Text(rows[2999], "n") == "item ç2999",
                  "chunks: a " + bigWire.Length + " byte message in " + pieces.Count + " packets round trips");
        }

        // ------------------------------------------------------------------------------------ identity
        static void IdentityChecks(Action<bool, string> check)
        {
            var w = new ByteWriter();
            ClientIdentity.Extended.WriteMarkers(w);
            check(w.ToArray().SequenceEqual(new byte[] { 0, 0 }), "identity: Extended sends u16 0 as markers");
            w = new ByteWriter();
            ClientIdentity.Chaos(0x1234).WriteMarkers(w);
            var expect = new List<byte> { 5, 0 };
            expect.AddRange(Encoding.ASCII.GetBytes("OTCv8"));
            expect.AddRange(new byte[] { 0x05, 0x01, 13, 0 });
            expect.AddRange(Encoding.ASCII.GetBytes("OTCv8TierByte"));
            expect.AddRange(new byte[] { 1, 0, (byte)'A', 0x34, 0x12, 0, 0, 1, 0, (byte)'C', 0x40 });
            check(w.ToArray().SequenceEqual(expect), "identity: Chaos sends OTCv8 261, OTCv8TierByte, A, signature, C, capabilities 0x40");
            check(ClientIdentity.Extended.Os == 21 && ClientIdentity.Extended.Os >= 10 && !ClientIdentity.Extended.Markers, "identity: OS 21 is an extended opcode client (the engine's limit is 10)");
            check(ClientIdentity.Parse("chaos", 5).Markers && !ClientIdentity.Parse("", 5).Markers && !ClientIdentity.Parse("nonsense", 5).Markers, "identity: named by text");

            // the game login packet carries the OS word and the markers inside the RSA block
            var key = Protocol.NewXteaKey();
            var rsa = new Rsa(Protocol.OpenRsaModulus);
            var plainLogin = Protocol.GameLoginPacket(rsa, key, "acc\npwd\n\n0", "Hero", ClientGuard.Identifier(30), 1, 2);
            var chaosLogin = Protocol.GameLoginPacket(rsa, key, "acc\npwd\n\n0", "Hero", ClientGuard.Identifier(30), 1, 2, ClientIdentity.Chaos(30));
            check(plainLogin.Length == chaosLogin.Length && plainLogin[7] == 21 && chaosLogin[7] == 21 && plainLogin.Length == 2 + 4 + 1 + 2 + 2 + 4 + 2 + 1 + 128,
                  "identity: the game login packet is one RSA block either way");
            var tooLong = new string('k', 90);
            check(Throws<ProtocolException>(() => Protocol.GameLoginPacket(rsa, key, tooLong, "Hero", 1, 1, 1, ClientIdentity.Chaos(1))),
                  "identity: a session key too long for the markers is refused, not cut");

            // features
            var f = new ClientFeatures();
            f.Read(new ByteReader(new ByteWriter().U16(3).U8(126).U8(1).U8(152).U8(1).U8(20).U8(0).ToArray()));
            check(f.Announced && f.Has(126) && f.Has(152) && !f.Has(20) && f.All.Count() == 2, "identity: the feature list packet");
            f.Read(new ByteReader(new ByteWriter().U16(1).U8(126).U8(0).ToArray()));
            check(!f.Has(126) && f.Has(152), "identity: a later packet turns a feature off");
        }

        // ------------------------------------------------------------------------------------ the parser, Chaos parts
        static GameParser Entered(bool chaos, DatFile dat, byte[] features = null)
        {
            ProtocolTests.ChaosWire = chaos;
            var w = new World(dat);
            var p = new GameParser(w) { Identity = chaos ? ClientIdentity.Chaos(1) : ClientIdentity.Extended };
            if (features != null) p.Parse(features);
            p.Parse(ProtocolTests.EnterPayload());
            ProtocolTests.ChaosWire = false;
            return p;
        }

        static void ParserChecks(Action<bool, string> check)
        {
            var dat = DatFile.Parse(Program.SyntheticDat());
            var feat = new ByteWriter().U8(0x43).U16(2).U8(126).U8(1).U8(152).U8(1).ToArray();

            var plain = Entered(false, dat);
            check(plain.W.Player.Outfit.Wings == 0 && plain.W.Player.Outfit.Shader == "" && !plain.Features.Announced, "parser: a plain connection reads plain outfits");
            var chaos = Entered(true, dat, feat);
            var hero = chaos.W.Player;
            var ground = chaos.W.Get(ProtocolTests.StartPos).Things[0].Item;
            check(chaos.Features.Announced && hero.Outfit.Wings == 7 && hero.Outfit.Aura == 9 && hero.Outfit.Shader == "fire" &&
                  hero.Outfit.Mount == 0 && ground.Attr(1) == 3 && chaos.W.Tiles.Count == World.ViewW * World.ViewH,
                  "parser: a Chaos connection reads wings, aura, shader and item attributes");

            // 0x8E outfit change and 0x43 mid-session
            var outfit = new ByteWriter().U8(0x8E).U32(hero.Id).U16(1).U8(9).U8(8).U8(7).U8(6).U8(3).U16(0).U16(11).U16(12).Str("blue").ToArray();
            chaos.Parse(outfit);
            check(hero.Outfit.Head == 9 && hero.Outfit.Wings == 11 && hero.Outfit.Aura == 12 && hero.Outfit.Shader == "blue", "parser: 0x8E carries the extended fields");

            // an item with attributes in a container (0x6E): item 101 is stackable, 2 phases
            var cont = new ByteWriter().U8(0x6E).U8(1).U16(101).U8(0xFF).U8(5).U8(0).U16(0).Str("bag").U8(8).U8(0).U8(1).U8(0).U16(1).U16(0).U8(1);
            cont.U16(101).U8(0xFF).U8(9).U8(0).U16(2).U16(1).U32(4).U32(0).U16(6).U32(77).U32(0);
            chaos.Parse(cont.ToArray());
            var coin = chaos.Containers[1].Items[0];
            check(coin.Id == 101 && coin.Count == 9 && coin.Attr(1) == 4 && coin.Attr(6) == 77 && coin.Attrs.Count == 2, "parser: container items carry their attributes (stackable, phase byte, then the list)");
            check(Throws<ProtocolException>(() => chaos.Parse(new ByteWriter().U8(0x6E).U8(2).U16(101).U8(0xFF).U8(5).U8(0).U16(65535).ToArray())),
                  "parser: more than 64 item attributes are refused");

            // aware range: the view of the 10.98 map is the only one read
            var aware = Entered(true, dat, feat);
            aware.Parse(new byte[] { 0x42, 17, 13 });
            check(aware.AwareW == 17 && aware.AwareH == 13 && Throws<ProtocolException>(() => aware.Parse(new byte[] { 0x42, 21, 15 })), "parser: aware range 17 x 13 is read, another is refused");

            // 0x4B: a floor on its own. Going up out of a cave: the surface floors come first, then 0xBE has none
            var cave = new World(dat);
            var up = new GameParser(cave) { Identity = ClientIdentity.Chaos(1) };
            ProtocolTests.ChaosWire = false;
            // the underground view (z 8): floors 6..10, every tile skipped
            up.Parse(new ByteWriter().U8(0x64).U16(100).U16(100).U8(8).Raw(EmptyFloors(5)).ToArray());
            var floorMsgs = new ByteWriter();
            for (int i = 5; i >= 0; i--)
                floorMsgs.U8(0x4B).U16(100).U16(100).U8(8).U8((byte)i).Raw(OneFloorOfGround(8 - i));
            floorMsgs.U8(0xBE);
            up.Parse(floorMsgs.ToArray());
            check(cave.Center == new Pos(101, 101, 7) && cave.Tiles.Keys.Any(p => p.Z == 5) && cave.Tiles.Keys.Any(p => p.Z == 0) && up.Seen[0x4B] == 6,
                  "parser: six 0x4B floors and an empty 0xBE move the view up to the surface");
            // the plain parser would read those floors out of 0xBE itself
            var plainUp = new World(dat);
            var pu = new GameParser(plainUp);
            pu.Parse(new ByteWriter().U8(0x64).U16(100).U16(100).U8(8).Raw(EmptyFloors(5)).ToArray());
            pu.Parse(new ByteWriter().U8(0xBE).Raw(FloorsForUp(8)).ToArray());
            check(plainUp.Center == new Pos(101, 101, 7) && plainUp.Tiles.Keys.Any(p => p.Z == 0), "parser: a plain connection reads the same floors inside 0xBE");

            // spell cooldowns: a u8 id, or a u16 with feature 152; group cooldowns
            var cds = new List<string>();
            var cd = Entered(false, dat);
            cd.SpellCooldown = (id, ms) => cds.Add("s" + id + ":" + ms);
            cd.GroupCooldown = (g, ms) => cds.Add("g" + g + ":" + ms);
            cd.Parse(new ByteWriter().U8(0xA4).U8(12).U32(2000).U8(0xA5).U8(1).U32(1000).ToArray());
            var cw = Entered(true, dat, feat);
            cw.SpellCooldown = (id, ms) => cds.Add("s" + id + ":" + ms);
            cw.Parse(new ByteWriter().U8(0xA4).U16(300).U32(5000).ToArray());
            check(string.Join(" ", cds) == "s12:2000 g1:1000 s300:5000", "parser: 0xA4 reads one byte, or two with feature 152, and 0xA5 the group");
        }

        // an empty floor encoding for `n` floors of 18 x 14 tiles: every tile skipped (skip counters of 0xFE at most)
        static byte[] EmptyFloors(int n)
        {
            var w = new ByteWriter();
            int tiles = n * World.ViewW * World.ViewH;
            while (tiles > 0)
            {
                int run = Math.Min(tiles, 0xFF);
                // a run of `run` empty tiles: skip counter run-1 with the end marker FF
                w.U8((byte)(run - 1)).U8(0xFF);
                tiles -= run;
            }
            return w.ToArray();
        }

        // one floor of ground tiles (every tile one ground item), `offset` unused: the tile positions come from the reader
        static byte[] OneFloorOfGround(int offset)
        {
            var w = new ByteWriter();
            for (int i = 0; i < World.ViewW * World.ViewH; i++) w.U16(0).U16(100).U8(0xFF).U8(0).U8(0xFF);
            return w.ToArray();
        }

        // what the stock 0xBE carries from z 8 to 7: floors 5..0, each one ground tile per position (no skips across floors)
        static byte[] FloorsForUp(int z)
        {
            var w = new ByteWriter();
            for (int i = 5; i >= 0; i--) w.Raw(OneFloorOfGround(8 - i));
            return w.ToArray();
        }

        // ------------------------------------------------------------------------------------ spells
        static string SpellJson(string name, string words, int level, int id, string type, string extra = "")
        {
            return "{\"name\":\"" + name + "\",\"words\":\"" + words + "\",\"level\":" + level + ",\"maglevel\":0,\"mana\":20,\"cooldown\":2000,\"groupCooldown\":1000," +
                   "\"group\":\"attack\",\"type\":\"" + type + "\",\"element\":\"fire\",\"target\":\"single\",\"vocations\":[3,4],\"id\":" + id + extra + "}";
        }

        static void SpellChecks(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var sent = new List<byte[]>();
            ext.Transmit = p => sent.Add(p);
            double now = 1000;
            var said = new List<string>();
            var book = new SpellBook(ext) { Clock = () => now, Say = said.Add };
            book.LevelNow = () => 100;
            book.MagicLevelNow = () => 30;
            book.Open();
            check(Encoding.UTF8.GetString(sent[0], 4, sent[0].Length - 4) == "{\"action\":\"open\"}", "spells: the first open has no signature");

            string list1 = "[" + SpellJson("Flame Strike", "exori flam", 14, 150, "damage") + "," + SpellJson("Ice Wave", "exevo frigo hur", 18, 118, "damage", ",\"quest\":0") + "," +
                           SpellJson("Light Healing", "exura", 8, 84, "heal").Replace("\"group\":\"attack\"", "\"group\":2") + "," +
                           SpellJson("Great Fireball", "exevo gran mas pox", 300, 1200, "damage") + "," +
                           SpellJson("Hidden Spell", "exura gran hid", 20, 7, "utility", ",\"needLearn\":true") + "," +
                           SpellJson("Other Class", "exori oth", 10, 8, "damage").Replace("[3,4]", "[1]") + "," +
                           "{\"name\":\"Fire Rune\",\"words\":\"adori flam\",\"level\":27,\"rune\":2268,\"runeClientId\":3190,\"vocations\":[3],\"id\":9,\"type\":\"damage\"}]";
            string open = "{\"action\":\"open\",\"data\":{\"vocation\":3,\"level\":100,\"magicLevel\":30,\"total\":7,\"chunks\":1,\"sig\":\"s1\",\"learned\":[\"Other Learned\"],\"vocationNames\":[{\"id\":3,\"name\":\"Sorcerer\"}]}}";
            ext.Receive(219, open);
            ext.Receive(219, "{\"action\":\"spells\",\"data\":{\"index\":1,\"spells\":" + list1 + "}}");
            check(!book.Loaded, "spells: not loaded before done");
            int changes = 0;
            book.Changed += () => changes++;
            ext.Receive(219, "{\"action\":\"done\",\"data\":{\"total\":7,\"sig\":\"s1\"}}");
            check(book.Loaded && book.Spells.Count == 7 && book.Sig == "s1" && changes == 1 && book.Vocation == 3 && book.VocationNames[3] == "Sorcerer",
                  "spells: open, spells and done fill the book");
            check(book.Spells.Select(s => s.Name).SequenceEqual(new[] { "Light Healing", "Other Class", "Flame Strike", "Ice Wave", "Hidden Spell", "Fire Rune", "Great Fireball" }),
                  "spells: sorted by level, then name: " + string.Join(", ", book.Spells.Select(s => s.Name)));
            var flame = book.ByWords("EXORI FLAM");
            check(flame != null && flame.Id == 150 && flame.Mana == 20 && flame.Cooldown == 2000 && flame.Group == 1 && flame.Vocations.SequenceEqual(new[] { 3, 4 }) &&
                  book.ById(84).Group == 2 && book.ByWords("adori flam") == null, "spells: fields, the group by name or number, runes are not found by words");

            check(book.Status(flame) == SpellStatus.Ready && book.Status(book.ByWords("exori oth")) == SpellStatus.Vocation &&
                  book.Status(book.ByWords("exura gran hid")) == SpellStatus.Learn && book.Status(book.ByWords("exevo gran mas pox")) == SpellStatus.Level,
                  "spells: status ready, vocation, learn, level");
            string Names(IEnumerable<Spell> l) => string.Join(",", l.Select(s => s.Name));
            check(Names(book.Visible("learned", "all", "")) == "Light Healing,Flame Strike,Ice Wave", "spells: filter learned: " + Names(book.Visible("learned", "all", "")));
            check(Names(book.Visible("vocation", "all", "")) == "Light Healing,Flame Strike,Ice Wave,Hidden Spell,Great Fireball", "spells: filter my vocation");
            check(Names(book.Visible("all", "all", "")).Split(',').Length == 6 && Names(book.Visible("runes", "all", "")) == "Fire Rune", "spells: filter all (no runes) and runes only");
            check(Names(book.Visible("learned", "support", "")) == "Light Healing" && Names(book.Visible("learned", "attack", "")) == "Flame Strike,Ice Wave" &&
                  Names(book.Visible("learned", "all", "FRIGO")) == "Ice Wave" && Names(book.Visible("learned", "all", "flame")) == "Flame Strike", "spells: kind and search text");
            book.LevelNow = () => 295;
            check(Names(book.Visible("soon", "all", "")) == "Hidden Spell,Great Fireball", "spells: filter soon (the next 10 levels and spells to learn): " + Names(book.Visible("soon", "all", "")));
            book.LevelNow = () => 100;

            // a second open sends the signature; the server says unchanged
            sent.Clear();
            book.Open();
            check(Encoding.UTF8.GetString(sent[0], 4, sent[0].Length - 4) == "{\"action\":\"open\",\"data\":{\"have\":\"s1\"}}", "spells: the next open carries the signature");
            ext.Receive(219, "{\"action\":\"open\",\"data\":{\"vocation\":3,\"level\":101,\"magicLevel\":31,\"unchanged\":true,\"sig\":\"s1\",\"learned\":[\"Hidden Spell\"]}}");
            check(book.Spells.Count == 7 && book.Status(book.ByWords("exura gran hid")) == SpellStatus.Ready && book.Level == 101, "spells: unchanged keeps the list and takes the new learned names");

            // cooldowns: own, and the group's
            sent.Clear();
            book.OnSpellCooldown(150, 2000);
            check(book.CooldownLeft(flame) == 2000 && book.CooldownSeconds(flame) == 2, "spells: a cooldown of 2000 ms");
            now = 2500;
            check(book.CooldownLeft(flame) == 500 && book.CooldownSeconds(flame) == 1, "spells: 500 ms left, shown as 1 s");
            book.OnGroupCooldown(1, 4000);
            check(book.CooldownLeft(flame) == 4000 && book.CooldownLeft(book.ByWords("exura")) == 0 && book.CooldownLeft(book.ByWords("exevo frigo hur")) == 4000,
                  "spells: a group cooldown holds every spell of the group, not another group's");
            now = 7000;
            check(book.CooldownLeft(flame) == 0 && book.CooldownSeconds(flame) == 0, "spells: cooldowns end");

            // casting says the words; not a rune, not an unknown or too-high spell
            check(book.Cast(flame) && said.SequenceEqual(new[] { "exori flam" }), "spells: cast says the words");
            check(!book.Cast(book.ByWords("exevo gran mas pox")) && !book.Cast(book.Spells.First(s => s.IsRune)) && !book.Cast(null) && said.Count == 1, "spells: no cast above the level, of a rune, of nothing");
            book.CastOrSay("utani hur");
            check(said.Last() == "utani hur", "spells: a hotkey line is said as it is");

            // a list over 8192 bytes comes in parts through the same layer
            var many = new List<string>();
            for (int i = 0; i < 160; i++) many.Add(SpellJson("Spell " + i.ToString("000"), "words " + i, 1 + i % 50, 1000 + i, "damage", ",\"description\":\"" + new string('d', 60) + "\""));
            string bigSpells = "{\"action\":\"spells\",\"data\":{\"index\":1,\"spells\":[" + string.Join(",", many) + "]}}";
            var other = new ExtOpcodes();
            var book2 = new SpellBook(other);
            other.Receive(219, open);
            var pieces = ExtChunks.Split(ExtOpcodes.ToWire(bigSpells));
            foreach (var piece in pieces) other.Receive(219, piece);
            other.Receive(219, "{\"action\":\"done\",\"data\":{\"sig\":\"big\"}}");
            check(pieces.Count >= 2 && book2.Spells.Count == 160 && book2.Spells[0].Level == 1 && book2.Spells[159].Level == 50, "spells: a spell list in " + pieces.Count + " parts");
            bool shown = false;
            book.ShowRequested += () => shown = true;
            ext.Receive(219, "{\"action\":\"show\"}");
            check(shown, "spells: show asks the window to open");
            book.Reset();
            check(book.Spells.Count == 0 && !book.Loaded && book.Sig == null, "spells: reset forgets the last character");
        }

        // ------------------------------------------------------------------------------------ UI texts
        static void LocChecks(Action<bool, string> check)
        {
            check(Loc.Normalize("pt_BR") == "pt-BR" && Loc.Normalize("pt") == "pt-BR" && Loc.Normalize("Portuguese") == "pt-BR" && Loc.Normalize("en-US") == "en" &&
                  Loc.Normalize("de") == null && Loc.Normalize("") == null, "loc: language names");
            check(Loc.Choose("en", "pt-BR") == "en" && Loc.Choose(null, "pt_BR") == "pt-BR" && Loc.Choose(null, "de") == "en" && Loc.Choose("zz", "pt") == "pt-BR", "loc: the saved choice, else the system, else English");
            Loc.Set("en");
            check(Loc.T("Learned") == "Learned" && Loc.T("Level {0}", 5) == "Level 5", "loc: English is the key");
            Loc.Set("pt-BR");
            check(Loc.T("Learned") == "Aprendidas" && Loc.T("Level {0}", 5) == "Nível 5" && Loc.T("Unknown text {0}", 1) == "Unknown text 1", "loc: pt-BR, with arguments and a missing entry");
            Loc.Set("en");

            // every Loc.T("...") of the Unity sources has a pt-BR entry
            string dir = Path.GetFullPath(Path.Combine("..", "Client", "Assets", "Chaos", "Unity"));
            if (!Directory.Exists(dir)) dir = Path.GetFullPath(Path.Combine("unity", "Client", "Assets", "Chaos", "Unity"));
            if (!Directory.Exists(dir)) { check(true, "loc: sources not found (skipped)"); return; }
            var used = new HashSet<string>();
            foreach (string file in Directory.GetFiles(dir, "*.cs", SearchOption.AllDirectories))
                foreach (Match m in Regex.Matches(File.ReadAllText(file), "\\bLoc\\.T\\(\"((?:[^\"\\\\]|\\\\.)*)\""))
                    used.Add(m.Groups[1].Value.Replace("\\\"", "\"").Replace("\\\\", "\\"));
            var missing = used.Where(k => !LocStrings.PtBr.ContainsKey(k)).ToList();
            check(missing.Count == 0, "loc: every Loc.T key of the Unity sources has a pt-BR text" + (missing.Count > 0 ? ": " + string.Join(" | ", missing) : " (" + used.Count + " keys)"));
        }
    }
}
