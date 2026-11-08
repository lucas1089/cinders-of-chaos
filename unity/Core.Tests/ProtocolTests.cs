// Protocol checks on synthetic packets: login answer, map description, moves, the game session against a fake server
// on localhost (own RSA key, real framing, XTEA and the client guard), and `live`, a console login to a real server.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Numerics;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

namespace Chaos.Core.Tests
{
    static class ProtocolTests
    {
        const uint Hero = 0x10000001, Rat = 0x40000002;

        /// <summary>True while the synthetic server speaks to an Identity.Chaos client: outfits carry wings, aura and shader, items their
        /// custom attributes (the ground under the hero has rarity 3).</summary>
        internal static bool ChaosWire;
        internal static readonly Pos StartPos = new Pos(100, 100, 7);

        internal static void Creature(ByteWriter w, uint id, string name, byte type, ushort speed)
        {
            w.U16(0x61).U32(0).U32(id).U8(type).Str(name);
            w.U8(100).U8(2).U16(1).U8(1).U8(2).U8(3).U8(4).U8(0).U16(0);   // hp, dir south, outfit 1, colours, no mount
            if (ChaosWire) { if (id == Hero) w.U16(7).U16(9).Str("fire"); else w.U16(0).U16(0).Str(""); }
            w.U8(0).U8(0).U16(speed).U8(0).U8(0).U8(0).U8(type).U8(0).U8(0xFF).U16(0).U8(1);
        }

        /// <summary>The server's floor encoding (protocolgame.cpp GetFloorDescription): skip counters across floors.</summary>
        static void Floors(ByteWriter w, int x, int y, int z, int width, int height, Func<Pos, Action<ByteWriter>> tile)
        {
            int start = z > 7 ? z - 2 : 7, end = z > 7 ? Math.Min(z + 2, 15) : 0, step = z > 7 ? 1 : -1;
            int skip = -1;
            for (int nz = start; nz != end + step; nz += step)
            {
                int offset = z - nz;
                for (int nx = 0; nx < width; nx++)
                    for (int ny = 0; ny < height; ny++)
                    {
                        var write = tile(new Pos(x + nx + offset, y + ny + offset, nz));
                        if (write != null)
                        {
                            if (skip >= 0) w.U8((byte)skip).U8(0xFF);
                            skip = 0;
                            w.U16(0);
                            write(w);
                        }
                        else if (skip == 0xFE) { w.U8(0xFF).U8(0xFF); skip = -1; }
                        else skip++;
                    }
            }
            if (skip >= 0) w.U8((byte)skip).U8(0xFF);
        }

        static readonly Pos Start = new Pos(100, 100, 7);

        /// <summary>Ground on every tile of floor 7 around Start, the hero on Start, a rat next to it.</summary>
        static Action<ByteWriter> MapTile(Pos p)
        {
            if (p.Z != 7) return null;
            return w =>
            {
                w.U16(100).U8(0xFF);
                if (ChaosWire) { if (p == Start) w.U16(1).U16(1).U32(3).U32(0); else w.U16(0); }   // item attributes: rarity 3 under the hero
                if (p == Start) Creature(w, Hero, "Hero", 0, 220);
                if (p == Start.Offset(2, 0)) Creature(w, Rat, "Rat", 1, 100);
            };
        }

        static byte[] LoginPayload()
        {
            var w = new ByteWriter();
            w.U8(0x14).Str("1\nWelcome");
            w.U8(0x28).Str("acc\npwd\n\n0");
            w.U8(0x64).U8(1).U8(0).Str("Chaos").Str("127.0.0.1").U16(7172).U8(0);
            w.U8(1).U8(0).Str("Hero").U32(42).U16(3).U16(1).U8(1).U8(2).U8(3).U8(4).U8(0).U16(0);
            w.U8(0).U8(1).U32(0);
            return w.ToArray();
        }

        internal static byte[] EnterPayload()
        {
            var w = new ByteWriter();
            w.U8(0x17).U32(Hero).U16(0x32);
            for (int i = 0; i < 3; i++) w.U8(3).U32(int.MaxValue);
            w.U8(0).U8(0).U8(1).Str("").U16(25);
            w.U8(0x0A).U8(0x0F);
            w.U8(0x64).U16((ushort)Start.X).U16((ushort)Start.Y).U8((byte)Start.Z);
            Floors(w, Start.X - World.RangeLeft, Start.Y - World.RangeTop, Start.Z, World.ViewW, World.ViewH, MapTile);
            w.U8(0x82).U8(200).U8(215);
            return w.ToArray();
        }

        public static void Run(Action<bool, string> check)
        {
            var dat = DatFile.Parse(Program.SyntheticDat());

            // login answer
            var res = new LoginResult();
            LoginClient.ParseLogin(LoginPayload(), res);
            var ch = res.Characters.FirstOrDefault();
            check(res.Motd == "1\nWelcome" && res.SessionKey == "acc\npwd\n\n0" && ch != null && ch.Name == "Hero" && ch.Level == 42 &&
                  ch.Vocation == 3 && ch.World == "Chaos" && ch.Host == "127.0.0.1" && ch.Port == 7172 && ch.Outfit.LookType == 1 &&
                  ch.Outfit.Feet == 4, "login answer: motd, session key, character list");
            var err = new LoginResult();
            LoginClient.ParseLogin(new ByteWriter().U8(0x0B).Str("Account name or password is not correct.").ToArray(), err);
            check(err.Error == "Account name or password is not correct.", "login error text");

            // packet sizes and encryption
            var key = Protocol.NewXteaKey();
            var rsa = new Rsa(Protocol.OpenRsaModulus);
            byte[] login = Protocol.LoginPacket(rsa, key, "acc", "pwd", ClientGuard.Identifier(30));
            check(login.Length == 2 + 4 + 1 + 2 + 2 + 4 + 12 + 1 + 256 && (login[0] | login[1] << 8) == login.Length - 2,
                  "login packet: size, two RSA blocks");
            check(login[6] == 0x01 && BitConverter.ToUInt32(login, 11) == 0x4343001E, "login packet: opcode and guard client id (build 30)");
            byte[] payload = { 1, 2, 3, 4, 5 };
            byte[] enc = Protocol.Encrypt(payload, key);
            byte[] body = enc.Skip(2).ToArray();
            check(enc.Length == 2 + 4 + 8 && Protocol.Decrypt(body, key).SequenceEqual(payload), "game packet round trip");
            body[7] ^= 1;
            bool threw = false;
            try { Protocol.Decrypt(body, key); } catch (ProtocolException) { threw = true; }
            check(threw, "game packet with a bad checksum is refused");

            // enter the world: player, map, creatures
            var world = new World(dat);
            double now = 1000;
            var parser = new GameParser(world) { Clock = () => now };
            parser.Parse(EnterPayload());
            var hero = world.Player;
            check(parser.LoggedIn && hero != null && hero.Name == "Hero" && hero.Position == Start && hero.Speed == 220,
                  "enter: the player and its position");
            int floor7 = world.Tiles.Keys.Count(p => p.Z == 7);
            check(floor7 == World.ViewW * World.ViewH && world.Tiles.Count == floor7, "enter: 18x14 tiles on floor 7, none above");
            var t = world.Get(Start);
            check(t.Things.Count == 2 && t.Things[0].Item.Id == 100 && t.Things[1].Creature == hero, "enter: ground then the player");
            check(world.Creatures.TryGetValue(Rat, out var rat) && rat.Position == Start.Offset(2, 0) && rat.Type == 1, "enter: the rat");
            check(world.Center == Start && world.WorldLight == 200, "enter: center and world light");

            // the player steps east: move, then the new east column
            now = 2000;
            var w = new ByteWriter().U8(0x6D).U16((ushort)Start.X).U16((ushort)Start.Y).U8(7).U8(1);
            w.U16((ushort)(Start.X + 1)).U16((ushort)Start.Y).U8(7);
            var c = Start.Offset(1, 0);
            w.U8(0x66);
            Floors(w, c.X + World.RangeRight, c.Y - World.RangeTop, c.Z, 1, World.ViewH, p => p.Z == 7 ? (Action<ByteWriter>)(x => x.U16(100).U8(0xFF)) : null);
            bool moved = false;
            parser.PlayerMoved = _ => moved = true;
            parser.Parse(w.ToArray());
            check(moved && hero.Position == c && hero.Direction == Dir.East && hero.WalkFrom == Start && hero.WalkStart == 2000,
                  "move: the player walks east");
            check(hero.WalkMs >= 290 && hero.WalkMs <= 310, "move: step time from speed 220 on ground speed 150: " + hero.WalkMs);
            check(world.Center == c && world.Get(new Pos(c.X + World.RangeRight, c.Y, 7)) != null &&
                  world.Tiles.Count == (World.ViewW + 1) * World.ViewH, "move: the east column comes in (one column kept behind)");
            check(world.Get(Start).Things.Count == 1, "move: the old tile keeps only its ground");

            // a creature moves by id, turns, takes damage, leaves
            now = 3000;
            w = new ByteWriter().U8(0x6D).U16(0xFFFF).U32(Rat).U16((ushort)(Start.X + 3)).U16((ushort)(Start.Y + 1)).U8(7);
            w.U8(0x6B).U16((ushort)(Start.X + 3)).U16((ushort)(Start.Y + 1)).U8(7).U8(1).U16(0x63).U32(Rat).U8(3).U8(1);
            w.U8(0x8C).U32(Rat).U8(40);
            parser.Parse(w.ToArray());
            check(rat.Position == Start.Offset(3, 1) && rat.Direction == Dir.West && rat.HealthPercent == 40 &&
                  world.Get(rat.Position).Things.Count == 2, "creature: diagonal move, turn in place, health");
            check(rat.WalkMs % 50 == 0 && rat.WalkMs > 0, "creature: step time rounded to 50 ms: " + rat.WalkMs);
            parser.Parse(new ByteWriter().U8(0x6C).U16(0xFFFF).U32(Rat).ToArray());
            check(world.Get(Start.Offset(3, 1)).Things.Count == 1, "creature: removed from its tile");

            // items, pings, extended opcodes, texts, unknown opcodes
            bool pinged = false;
            string ext = null;
            parser.Pinged = () => pinged = true;
            parser.ExtendedOpcode = (op, data) => ext = op + ":" + data;
            w = new ByteWriter().U8(0x6A).U16((ushort)Start.X).U16((ushort)Start.Y).U8(7).U8(1).U16(101).U8(0xFF).U8(7).U8(0);
            w.U8(0x1D).U8(0x32).U8(189).Str("cg1:00112233445566778899aabbccddeeff");
            parser.Parse(w.ToArray());
            var coin = world.Get(Start).Things[1].Item;
            check(coin.Id == 101 && coin.Count == 7, "item added with count (stackable) and phase byte");
            check(pinged && ext == "189:cg1:00112233445566778899aabbccddeeff", "ping and extended opcode");
            threw = false;
            try { parser.Parse(new byte[] { 0x0A, 0x01 }); } catch (ProtocolException) { threw = true; }
            check(threw, "an unknown opcode stops the packet");

            // chat: a say in, a server message in, a say out
            var said = new System.Collections.Generic.List<string>();
            parser.Chat = (who, text, type) => said.Add(type + "|" + who + "|" + text);
            w = new ByteWriter().U8(0xAA).U32(1).Str("Rat").U16(1).U8(1).U16((ushort)Start.X).U16((ushort)Start.Y).U8(7).Str("squeak");
            w.U8(0xAA).U32(2).Str("Mira").U16(9).U8(7).U16(5).Str("hello world");
            w.U8(0xB4).U8(20).Str("You see a rat.");
            parser.Parse(w.ToArray());
            check(said.Count == 3 && said[0] == "1|Rat|squeak" && said[1] == "7|Mira|hello world" && said[2] == "0||You see a rat.",
                  "chat: say, channel and server lines: " + string.Join(" / ", said));
            byte[] say = Protocol.SayPacket("hi");
            check(say.SequenceEqual(new byte[] { 0x96, 1, 2, 0, (byte)'h', (byte)'i' }), "chat: say packet");

            // inventory and containers (item 100 plain, item 101 stackable with a phase byte)
            w = new ByteWriter().U8(0x78).U8(6).U16(101).U8(0xFF).U8(25).U8(0);
            w.U8(0x78).U8(3).U16(100).U8(0xFF);
            parser.Parse(w.ToArray());
            check(parser.Inventory[6].Id == 101 && parser.Inventory[6].Count == 25 && parser.Inventory[3].Id == 100 &&
                  parser.Inventory[1] == null, "inventory: slots set");
            parser.Parse(new ByteWriter().U8(0x79).U8(6).ToArray());
            check(parser.Inventory[6] == null && parser.Inventory[3] != null, "inventory: slot cleared");
            byte opened = 255, closed = 255;
            parser.ContainerOpened = id => opened = id;
            parser.ContainerClosed = id => closed = id;
            w = new ByteWriter().U8(0x6E).U8(2).U16(100).U8(0xFF).Str("Backpack").U8(20).U8(1).U8(1).U8(0).U16(2).U16(0).U8(2);
            w.U16(101).U8(0xFF).U8(5).U8(0).U16(100).U8(0xFF);
            parser.Parse(w.ToArray());
            var cont = parser.Containers[2];
            check(opened == 2 && cont.Name == "Backpack" && cont.Capacity == 20 && cont.HasParent && cont.ItemId == 100 &&
                  cont.Items.Count == 2 && cont.Items[0].Count == 5 && cont.Items[1].Id == 100, "container: open");
            parser.Parse(new ByteWriter().U8(0x70).U8(2).U16(0).U16(101).U8(0xFF).U8(9).U8(0).ToArray());
            check(cont.Items.Count == 3 && cont.Items[0].Count == 9 && cont.Items[1].Count == 5, "container: add at the front");
            parser.Parse(new ByteWriter().U8(0x71).U8(2).U16(1).U16(100).U8(0xFF).ToArray());
            check(cont.Items.Count == 3 && cont.Items[1].Id == 100, "container: update");
            parser.Parse(new ByteWriter().U8(0x72).U8(2).U16(0).U16(0).ToArray());
            check(cont.Items.Count == 2 && cont.Items[0].Id == 100, "container: remove");
            parser.Parse(new ByteWriter().U8(0x72).U8(2).U16(0).U16(101).U8(0xFF).U8(3).U8(0).ToArray());
            check(cont.Items.Count == 2 && cont.Items[1].Id == 101 && cont.Items[1].Count == 3, "container: remove with a last item");
            parser.Parse(new ByteWriter().U8(0x6F).U8(2).ToArray());
            check(closed == 2 && !parser.Containers.ContainsKey(2), "container: close");

            // stats (0xA0) and skills (0xA1), with the trailing messages still read in line
            w = new ByteWriter().U8(0xA0).U32(150).U32(200).U32(4000).U32(5000).U32((uint)(123456789012UL & 0xFFFFFFFF)).U32((uint)(123456789012UL >> 32)).U16(80).U8(42);
            w.U16(100).U16(0).U16(0).U16(0).U16(0);
            w.U32(60).U32(90).U8(25).U8(20).U8(17).U8(5).U16(2520).U16(310).U16(0).U16(0).U16(0).U8(0);
            w.U8(0xA2).U16(7);
            parser.Parse(w.ToArray());
            check(parser.Health == 150 && parser.MaxHealth == 200 && parser.FreeCap == 4000 && parser.TotalCap == 5000 &&
                  parser.Experience == 123456789012UL && parser.Level == 80 && parser.LevelPercent == 42 && parser.Mana == 60 &&
                  parser.MaxMana == 90 && parser.MagicLevel == 25 && parser.BaseMagicLevel == 20 && parser.MagicPercent == 17 &&
                  parser.Soul == 5 && parser.Stamina == 2520 && parser.Speed == 310, "stats: all fields");
            w = new ByteWriter().U8(0xA1);
            for (int i = 0; i < 14; i++) w.U16((ushort)(10 + i)).U16((ushort)(9 + i)).U8((byte)(i * 5));
            for (int i = 0; i < 6; i++) w.U32(0);
            w.U8(0xA2).U16(7);
            parser.Parse(w.ToArray());
            check(parser.Skills[0].Level == 10 && parser.Skills[0].Base == 9 && parser.Skills[6].Level == 16 &&
                  parser.Skills[6].Percent == 30, "skills: seven named");

            // outgoing item packets
            var invPos = GameSession.InventoryPos(6);
            var bagPos = GameSession.ContainerPos(2, 3);
            check(Protocol.UseItemPacket(bagPos, 101, 3, 2).SequenceEqual(new byte[] { 0x82, 0xFF, 0xFF, 0x42, 0, 3, 101, 0, 3, 2 }), "out: use item");
            check(Protocol.CloseContainerPacket(2).SequenceEqual(new byte[] { 0x87, 2 }) &&
                  Protocol.UpContainerPacket(2).SequenceEqual(new byte[] { 0x88, 2 }), "out: close and up container");
            check(Protocol.MoveItemPacket(bagPos, 101, 3, invPos, 5).SequenceEqual(
                      new byte[] { 0x78, 0xFF, 0xFF, 0x42, 0, 3, 101, 0, 3, 0xFF, 0xFF, 6, 0, 0, 5 }), "out: move item");

            var k = ClientGuard.ParseKey("\"" + new string('a', 64) + "," + new string('0', 62) + "ff\"");
            check(k != null && k[31] == 0xff && k[0] == 0 && ClientGuard.ParseKey("xyz") == null, "guard key from hex, last of a list");

            FakeServer(check, dat, false);
            FakeServer(check, dat, true);
        }

        /// <summary>A whole game login against a server on localhost with its own RSA key.</summary>
        static void FakeServer(Action<bool, string> check, DatFile dat, bool chaos)
        {
            string what = chaos ? "fake server (Chaos identity)" : "fake server";
            ChaosWire = false;
            RSAParameters pk;
            using (var r = RSA.Create(1024)) pk = r.ExportParameters(true);
            string modulus = Rsa.FromBigEndian(pk.Modulus).ToString();
            BigInteger d = Rsa.FromBigEndian(pk.D);
            var rsa = new Rsa(modulus);
            byte[] guardKey = Encoding.ASCII.GetBytes("test-key-0123456789abcdef0123456");
            var listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            int port = ((IPEndPoint)listener.LocalEndpoint).Port;
            string got = null, problem = null;
            var server = new Thread(() =>
            {
                try
                {
                    using (var cl = listener.AcceptTcpClient())
                    {
                        cl.ReceiveTimeout = 5000;
                        var s = cl.GetStream();
                        var hello = new ByteWriter().U16(6).U8(0x1F).U32(0x11223344).U8(0x55).ToArray();
                        var first = new ByteWriter().U16((ushort)(hello.Length + 4)).U32(Adler32.Of(hello, 0, hello.Length)).Raw(hello).ToArray();
                        s.Write(first, 0, first.Length);
                        byte[] body = ReadBody(s);
                        var r = new ByteReader(body);
                        r.U32();
                        if (r.U8() != 0x0A || r.U16() != Protocol.Os || r.U16() != Protocol.Version) throw new Exception("bad header");
                        uint cid = r.U32();
                        r.U16(); r.U8();
                        var plain = new ByteReader(rsa.DecryptWith(d, r.Bytes(128)));
                        if (plain.U8() != 0) throw new Exception("rsa block does not start with 0");
                        var k = new uint[4];
                        for (int i = 0; i < 4; i++) k[i] = plain.U32();
                        plain.U8();
                        string sessionKey = plain.Str(), character = plain.Str();
                        uint ts = plain.U32();
                        byte rnd = plain.U8();
                        if (chaos)
                        {
                            // the markers of the main client: "OTCv8", version, "OTCv8TierByte", "A", u32, "C", capabilities (bit 6 wide spell ids)
                            if (plain.U16() != 5 || plain.Bytes(5).Length != 5) throw new Exception("no OTCv8 marker");
                            if (plain.U16() != 261 || plain.Str() != "OTCv8TierByte" || plain.Str() != "A") throw new Exception("tier marker");
                            if (plain.U32() != 7 || plain.Str() != "C" || plain.U8() != 0x40) throw new Exception("capabilities");
                        }
                        else if (plain.U16() != 0) throw new Exception("markers are not u16 0");
                        if (ts != 0x11223344 || rnd != 0x55 || cid != 0x43430007) throw new Exception("challenge or client id");
                        var nonce = new byte[16];
                        for (int i = 0; i < 16; i++) nonce[i] = (byte)(i * 17);
                        string challenge = "cg1:" + string.Concat(nonce.Select(b => b.ToString("x2")));
                        ChaosWire = chaos;
                        var pw = new ByteWriter().U8(0x32).U8(0).U16(0);
                        if (chaos) pw.U8(0x43).U16(2).U8(126).U8(1).U8(152).U8(1);   // the feature list: item attributes, 16-bit spell ids
                        var payload = pw.U8(0x32).U8(189).Str(challenge).Raw(EnterPayload()).ToArray();
                        var p = Protocol.Encrypt(payload, k);
                        s.Write(p, 0, p.Length);
                        var answers = new List<string>();
                        while (answers.Count < 2)
                        {
                            var m = new ByteReader(Protocol.Decrypt(ReadBody(s), k));
                            if (m.U8() != 0x32) continue;
                            m.U8();
                            answers.Add(m.Str());
                        }
                        string expect = ClientGuard.Answer(guardKey, nonce, sessionKey.Split('\n')[0], character, 7);
                        got = answers[0] == expect && answers[1] == ClientGuard.Hello(7) ? "ok" : "answers " + string.Join(" | ", answers);
                        var ping = Protocol.Encrypt(new byte[] { 0x1D }, k);
                        s.Write(ping, 0, ping.Length);
                        // the pong, the step and (Chaos) the extended opcode request, in any order
                        bool pongSeen = false, stepSeen = false, askSeen = !chaos;
                        string asked = null;
                        while (!(pongSeen && stepSeen && askSeen))
                        {
                            var x = Protocol.Decrypt(ReadBody(s), k);
                            if (x.Length == 1 && x[0] == 0x1E) pongSeen = true;
                            else if (x.Length == 1 && x[0] == 0x66) stepSeen = true;
                            else if (x.Length > 2 && x[0] == 0x32 && x[1] == 99)
                            {
                                var ask = new ByteReader(x);
                                ask.U8(); ask.U8();
                                asked = ExtOpcodes.FromWire(ask.Str());
                                askSeen = true;
                            }
                        }
                        if (chaos)
                        {
                            // an extended opcode round trip: the client asks (UTF-8 text), the server answers in parts
                            var root = Json.Parse(asked);
                            if (Json.Text(root, "action") != "echo") throw new Exception("request " + asked);
                            string word = Json.Text(Json.Get(root, "data"), "text");
                            string big = Json.Serialize(new Dictionary<string, object> { { "action", "pong" },
                                { "data", new Dictionary<string, object> { { "text", string.Concat(Enumerable.Repeat(word, 6000)) }, { "n", Json.Int(Json.Get(root, "data"), "n") } } } });
                            var reply = new ByteWriter();
                            foreach (var part in ExtChunks.Split(ExtOpcodes.ToWire(big))) reply.U8(0x32).U8(99).Str(part);
                            var rp = Protocol.Encrypt(reply.ToArray(), k);
                            s.Write(rp, 0, rp.Length);
                            Thread.Sleep(300);   // keep the connection open while the client reads
                        }
                    }
                }
                catch (Exception e) { problem = e.Message; }
                finally { listener.Stop(); }
            }) { IsBackground = true };
            server.Start();

            var world = new World(dat);
            var session = new GameSession(world, new GameSession.Options
            {
                Host = "127.0.0.1", Port = port, Account = "acc", Password = "pwd", SessionKey = "acc\npwd\n\n0", Character = "Hero",
                GuardKey = guardKey, Build = 7, RsaModulus = modulus,
                Identity = chaos ? ClientIdentity.Chaos(7) : ClientIdentity.Extended,
            });
            ExtMessage pong = null;
            string bigText = null;
            session.Ext.On(99, m => { pong = m; bigText = Json.Text(m.Data, "text"); });
            session.Start();
            var until = DateTime.UtcNow.AddSeconds(10);
            bool walked = false, asked = false;
            while (DateTime.UtcNow < until && server.IsAlive && session.Closed == null)
            {
                session.Poll();
                if (!walked && session.CanWalk) { session.Walk(Dir.East); walked = true; }
                if (chaos && walked && !asked && session.Parser.LoggedIn && session.Now > 0)
                {
                    // after the step was sent (the server reads the pong and the step first)
                    asked = true;
                    session.Ext.Send(99, "echo", new Dictionary<string, object> { { "text", "ação " }, { "n", 5 } });
                }
                Thread.Sleep(5);
            }
            server.Join(2000);
            ChaosWire = false;
            check(problem == null, what + ": " + (problem ?? "no error"));
            check(got == "ok", what + ": guard answer, hello, pong and a step: " + got);
            check(session.GuardAnswered && world.Player != null && world.Tiles.Count == World.ViewW * World.ViewH,
                  what + ": the session entered the world");
            if (chaos)
            {
                var hero = world.Player;
                var ground = world.Get(StartPos)?.Things[0].Item;
                check(session.Parser.Features.Announced && session.Parser.Features.Has(126) && session.Parser.Features.Has(152) &&
                      !session.Parser.Features.Has(155), what + ": the feature list");
                check(hero != null && hero.Outfit.Wings == 7 && hero.Outfit.Aura == 9 && hero.Outfit.Shader == "fire" &&
                      world.Creatures[Rat].Outfit.Wings == 0 && world.Creatures[Rat].Outfit.Shader == "", what + ": extended outfits");
                check(ground != null && ground.Attr(1) == 3 && ground.Attr(2) == 0, what + ": item attributes");
                check(pong != null && pong.Action == "pong" && Json.Int(pong.Data, "n") == 5 && bigText != null &&
                      bigText.Length == 30000 && bigText.StartsWith("ação ação "),
                      what + ": extended opcode round trip, answer in parts (" + (bigText == null ? -1 : bigText.Length) + " chars)");
            }
            session.Dispose();
        }

        static byte[] ReadBody(Stream s)
        {
            var head = new byte[2];
            ReadFull(s, head);
            var b = new byte[head[0] | head[1] << 8];
            ReadFull(s, b);
            return b;
        }

        static void ReadFull(Stream s, byte[] b)
        {
            int got = 0;
            while (got < b.Length)
            {
                int n = s.Read(b, got, b.Length - got);
                if (n <= 0) throw new EndOfStreamException("connection closed");
                got += n;
            }
        }
    }

    /// <summary>`dotnet run -c Release -- live PAIR_DIR HOST ACCOUNT PASSWORD [CHARACTER] [RSA_MODULUS_FILE]`: logs in,
    /// enters the game, takes four steps, prints what it read. The guard key comes from CHAOS_CLIENT_KEY (else the dev key).</summary>
    static class LiveProbe
    {
        public static int Run(string[] a)
        {
            if (a.Length < 5)
            {
                Console.Error.WriteLine("usage: live PAIR_DIR HOST ACCOUNT PASSWORD [CHARACTER] [RSA_MODULUS_FILE]");
                return 2;
            }
            var dat = DatFile.Load(Path.Combine(a[1], "Tibia.dat"));
            string host = a[2], modulus = a.Length > 6 ? File.ReadAllText(a[6]).Trim() : Protocol.OpenRsaModulus;
            var env = Environment.GetEnvironmentVariable("CHAOS_CLIENT_KEY");
            byte[] guard = ClientGuard.ParseKey(env) ?? ClientGuard.DevKey;
            if (!string.IsNullOrEmpty(env) && guard == ClientGuard.DevKey) { Console.Error.WriteLine("CHAOS_CLIENT_KEY must be 64 hex digits"); return 2; }
            var res = LoginClient.Login(host, 7171, a[3], a[4], modulus).GetAwaiter().GetResult();
            if (res.Error != null) { Console.Error.WriteLine("login: " + res.Error); return 1; }
            Console.WriteLine("login ok: " + string.Join(", ", res.Characters.Select(x => x.Name + " (" + x.Level + ")")));
            var ch = a.Length > 5 ? res.Characters.FirstOrDefault(x => x.Name == a[5]) : res.Characters.FirstOrDefault();
            if (ch == null) { Console.Error.WriteLine("no such character"); return 1; }
            var world = new World(dat);
            var s = new GameSession(world, new GameSession.Options
            {
                Host = ch.Host, Port = ch.Port, Account = a[3], Password = a[4], SessionKey = res.SessionKey, Character = ch.Name,
                GuardKey = guard, RsaModulus = modulus,
            });
            s.Log += m => Console.WriteLine("  " + m);
            s.Start();
            var steps = new[] { Dir.North, Dir.East, Dir.South, Dir.West };
            int step = 0;
            var until = DateTime.UtcNow.AddSeconds(15);
            while (DateTime.UtcNow < until && s.Closed == null)
            {
                s.Poll();
                if (s.Parser.LoggedIn && step < steps.Length && s.CanWalk && s.Now > 3000) s.Walk(steps[step++]);
                Thread.Sleep(10);
            }
            Console.WriteLine("closed: " + (s.Closed ?? "no"));
            Console.WriteLine("player: " + (world.Player != null ? world.Player.Name + " at " + world.Player.Position : "none"));
            Console.WriteLine("tiles " + world.Tiles.Count + ", creatures " + world.Creatures.Count + ", " + s.Stats);
            Console.WriteLine("opcodes: " + string.Join(" ", s.Parser.Seen.OrderBy(x => x.Key).Select(x => x.Key.ToString("X2") + "x" + x.Value)));
            s.Logout();
            s.Dispose();
            return s.Closed == null && world.Player != null ? 0 : 1;
        }
    }
}
