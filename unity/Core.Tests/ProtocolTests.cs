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

        static void Creature(ByteWriter w, uint id, string name, byte type, ushort speed)
        {
            w.U16(0x61).U32(0).U32(id).U8(type).Str(name);
            w.U8(100).U8(2).U16(1).U8(1).U8(2).U8(3).U8(4).U8(0).U16(0);   // hp, dir south, outfit 1, colours, no mount
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

        static byte[] EnterPayload()
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

            var k = ClientGuard.ParseKey("\"" + new string('a', 64) + "," + new string('0', 62) + "ff\"");
            check(k != null && k[31] == 0xff && k[0] == 0 && ClientGuard.ParseKey("xyz") == null, "guard key from hex, last of a list");

            FakeServer(check, dat);
        }

        /// <summary>A whole game login against a server on localhost with its own RSA key.</summary>
        static void FakeServer(Action<bool, string> check, DatFile dat)
        {
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
                        if (ts != 0x11223344 || rnd != 0x55 || cid != 0x43430007) throw new Exception("challenge or client id");
                        var nonce = new byte[16];
                        for (int i = 0; i < 16; i++) nonce[i] = (byte)(i * 17);
                        string challenge = "cg1:" + string.Concat(nonce.Select(b => b.ToString("x2")));
                        var payload = new ByteWriter().U8(0x32).U8(0).U16(0).U8(0x32).U8(189).Str(challenge).Raw(EnterPayload()).ToArray();
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
                        // the pong and the step, in either order
                        var two = new[] { Protocol.Decrypt(ReadBody(s), k), Protocol.Decrypt(ReadBody(s), k) };
                        if (!two.Any(x => x.Length == 1 && x[0] == 0x1E)) got = "no pong";
                        if (!two.Any(x => x.Length == 1 && x[0] == 0x66)) got = "no walk east";
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
            });
            session.Start();
            var until = DateTime.UtcNow.AddSeconds(10);
            bool walked = false;
            while (DateTime.UtcNow < until && server.IsAlive && session.Closed == null)
            {
                session.Poll();
                if (!walked && session.CanWalk) { session.Walk(Dir.East); walked = true; }
                Thread.Sleep(5);
            }
            server.Join(2000);
            check(problem == null, "fake server: " + (problem ?? "no error"));
            check(got == "ok", "fake server: guard answer, hello, pong and a step: " + got);
            check(session.GuardAnswered && world.Player != null && world.Tiles.Count == World.ViewW * World.ViewH,
                  "fake server: the session entered the world");
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
