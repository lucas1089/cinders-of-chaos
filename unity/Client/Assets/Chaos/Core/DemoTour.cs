// The demo tour (unity/README.md "Demo tour video"): a small fake game server the player starts in its own process on localhost,
// and the scripted timeline it plays. The player logs in to it through the normal ChaosApp flow (login port, character list,
// game port with the guard challenge), so a recording shows the client running the game, not a test scene.
//   TourArt   the item and outfit ids the map uses (the synthetic art, the temple tileset or the outdoor ids of the real pair)
//   TourMap   a synthetic meadow (grass, a winding path, a pond, trees, rocks, a ruin wall), the same tile every time
//   TourPlan  the times (ms from the start of the recording) both sides keep: the server script and the player's director
//   FakeGameServer  RSA, XTEA, framing, the guard handshake, steps, and the script. Nothing here is real server data.
// Deterministic: the script runs on the clock the caller feeds to Advance (the player feeds its fixed 60 fps frame clock), never
// on the wall clock. Plain 10.98 wire (ClientIdentity.Extended): no feature list, no wings or item attributes.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Numerics;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

namespace Chaos.Core
{
    /// <summary>The ids the tour map and creatures use.</summary>
    public sealed class TourArt
    {
        public int Grass, Path, Water, Tree, Rock, Wall, Torch, OutfitHero, OutfitMonster, OutfitNpc;
        public ushort[] ShopIds = { 100, 101, 102, 103, 104 };
        public string Source = "";
        /// <summary>Ids whose item carries a phase byte (animated) or a count byte on the wire; filled by Probe from the dat.</summary>
        public readonly HashSet<int> Phased = new HashSet<int>(), Counted = new HashSet<int>();

        /// <summary>The synthetic art (Hd2dDemo.Synthetic) or the temple tileset of the real pair: floors, pillars for trees, a wall, torches.</summary>
        public static TourArt FromDemo(DemoIds d)
        {
            return new TourArt
            {
                Grass = d.Floor, Path = d.Checker, Water = 0, Tree = d.Pillar, Rock = d.Pillar, Wall = d.Wall, Torch = d.Torch,
                OutfitHero = d.OutfitA, OutfitMonster = d.OutfitB, OutfitNpc = d.OutfitB, Source = "temple floors",
                ShopIds = new ushort[] { (ushort)d.Floor, (ushort)d.Checker, (ushort)d.Border, (ushort)d.Wall, (ushort)d.Pillar },
            };
        }

        /// <summary>The outdoor ids picked from the real pair (Hd2dDemo.PickOutdoor): grass, path, pond, trees, rocks.</summary>
        public static TourArt FromOutdoor(OutdoorIds o)
        {
            return new TourArt
            {
                Grass = o.Grass, Path = o.Dirt, Water = o.Water, Tree = o.Tree, Rock = o.Rock != 0 ? o.Rock : o.Tree, Wall = 0, Torch = 0,
                OutfitHero = o.OutfitA, OutfitMonster = o.OutfitB, OutfitNpc = o.OutfitB, Source = "outdoor ids of the real pair",
                ShopIds = new ushort[] { 2666, 2674, 7618, 7620, 2148 },
            };
        }

        /// <summary>Reads which of the ids need the extra bytes on the wire (the client reads them by its dat).</summary>
        public TourArt Probe(DatFile dat)
        {
            foreach (int id in new[] { Grass, Path, Water, Tree, Rock, Wall, Torch })
            {
                var t = id > 0 ? dat.Item(id) : null;
                if (t == null) continue;
                if (t.HasPhaseByte) Phased.Add(id);
                if (t.HasSubType) Counted.Add(id);
            }
            return this;
        }
    }

    /// <summary>The meadow: a function of the tile, so the strips of a walk are always the same as the first view.</summary>
    public sealed class TourMap
    {
        public readonly TourArt Art;
        public readonly Pos Center;
        static readonly int[][] Trees = { new[] { -7, -3 }, new[] { -4, -5 }, new[] { 2, -5 }, new[] { 6, -4 }, new[] { 8, 0 }, new[] { 6, 5 }, new[] { 8, 6 },
                                          new[] { -7, 6 }, new[] { -7, 1 }, new[] { 3, 6 }, new[] { -10, -2 }, new[] { 10, 2 }, new[] { 11, -3 } };
        static readonly int[][] Rocks = { new[] { 3, 4 }, new[] { -2, -2 }, new[] { 4, 1 }, new[] { -1, 6 } };

        public TourMap(TourArt art, Pos center) { Art = art; Center = center; }

        static int Hash(int x, int y) { unchecked { int h = x * 73856093 ^ y * 19349663; h ^= h >> 13; h *= 0x5bd1e995; return (h ^ (h >> 15)) & 0x7fffffff; } }

        public int Ground(int x, int y)
        {
            int dx = x - Center.X, dy = y - Center.Y;
            if (Art.Water != 0)
            {
                double ex = (dx + 4) / 3.4, ey = (dy - 3) / 2.4;
                if (ex * ex + ey * ey <= 1.0) return Art.Water;
            }
            int px = Center.X - 1 + (int)Math.Round(1.5 * Math.Sin(0.7 * dy));
            return x == px || x == px + 1 ? Art.Path : Art.Grass;
        }

        /// <summary>A blocking thing standing on the tile (a tree, a rock, a wall piece, a torch), 0 when the tile is bare.</summary>
        public int Item(int x, int y)
        {
            int dx = x - Center.X, dy = y - Center.Y;
            int ground = Ground(x, y);
            if (ground == Art.Water && Art.Water != 0) return 0;
            foreach (var t in Trees) if (t[0] == dx && t[1] == dy && ground == Art.Grass) return Art.Tree;
            foreach (var r in Rocks) if (r[0] == dx && r[1] == dy && ground == Art.Grass) return Art.Rock;
            // the ruin wall behind the archer: wall pieces (two tiles wide) or a row of rocks
            if (dy == -5 && dx >= 3 && dx <= 9) return Art.Wall != 0 ? (dx % 2 == 1 ? Art.Wall : 0) : Art.Rock;
            if (Art.Torch != 0 && dx == 5 && dy == 3) return Art.Torch;
            if ((Math.Abs(dx) > 10 || dy < -7 || dy > 8) && ground == Art.Grass && Hash(x, y) % 8 == 0) return Art.Tree;
            return 0;
        }

        public bool Walkable(int x, int y) => Item(x, y) == 0 && !(Art.Water != 0 && Ground(x, y) == Art.Water);
    }

    /// <summary>The times (ms from the first recorded frame) the server script and the player's director agree on.</summary>
    public static class TourPlan
    {
        public const double Total = 23000;
        public const double WalkFrom = 800;
        public static readonly Dir[] Walk = { Dir.North, Dir.North, Dir.North, Dir.East, Dir.East };
        public const double AttackSkeleton = 4300, AttackGhoul = 7500, CastFury = 6600, CastHeal = 8700;
        public const double SayHi = 10800, ShopOpens = 12300, ShopCloses = 14000;
        public const double SpellbookOpens = 14200, SpellbookCloses = 16000, PartyInvite = 16000, PartyJoins = 17000, PartyCloses = 19000;
        public const double TreeOpens = 19000, TreeCloses = 20300, SkillsOpens = 20300, SkillsCloses = 21300, MenuFirst = 21300, MenuSecond = 22100;
    }

    /// <summary>A fake game server on localhost: the login port and the game port are one socket (a connection that talks first is a login).</summary>
    public sealed class FakeGameServer : IDisposable
    {
        public const uint HeroId = 0x10000001, SkeletonId = 0x40000001, GhoulId = 0x40000002, ArcherId = 0x40000003, NpcId = 0x80000001;
        public const string HeroName = "Ember", NpcName = "Mira";
        public const int HeroLevel = 150, HeroVocation = 8, MaxHealth = 1500, MaxMana = 600;

        public readonly byte[] GuardKey;
        public readonly string RsaModulus;
        public readonly TourMap Map;
        public readonly Pos Start;
        /// <summary>The login port (what the client dials first).</summary>
        public int Port { get; private set; }
        /// <summary>The game port the character list names. Its own listener, so the server never has to guess a connection's kind from timing.</summary>
        public int GamePort { get; private set; }

        readonly TourArt art;
        readonly Rsa rsa;
        readonly BigInteger d;
        TcpListener listener, gameListener;
        volatile bool stop;
        readonly object gate = new object();
        Conn cur;
        Pos hero;
        int health = MaxHealth, mana = MaxMana;
        readonly Dictionary<uint, Mob> mobs = new Dictionary<uint, Mob>();
        readonly List<KeyValuePair<double, Action<Out>>> script = new List<KeyValuePair<double, Action<Out>>>();
        int next;
        public int Steps, Blocked, Attacks, Says, Logins, Pings;
        public uint AttackTarget;
        public string LastSay = "", Problem;
        public readonly Dictionary<byte, int> ExtRequests = new Dictionary<byte, int>();
        /// <summary>The window smoke run switches this on: the server then also answers what the Chaos windows ask on opening (Core/FakeModules.cs) and the channel list. Off for the demo tour.</summary>
        public bool ModuleResponder;
        /// <summary>Messages the responder sent for requests, and requests it had no answer for (a window then keeps its empty state).</summary>
        public int Answered, Unanswered;
        public readonly List<string> UnansweredList = new List<string>();

        sealed class Mob
        {
            public uint Id; public string Name; public byte Type; public Pos At; public int Look, Hp = 100, Light;
        }

        sealed class Conn
        {
            public Stream S; public uint[] Key; public bool Entered;
            readonly object sendGate = new object();
            public void Send(byte[] payload)
            {
                var p = Protocol.Encrypt(payload, Key);
                lock (sendGate) S.Write(p, 0, p.Length);
            }
        }

        public FakeGameServer(TourArt a)
        {
            art = a;
            Start = new Pos(100, 102, 7);
            Map = new TourMap(a, new Pos(100, 100, 7));
            RSAParameters pk;
            using (var r = RSA.Create(1024)) pk = r.ExportParameters(true);
            RsaModulus = Rsa.FromBigEndian(pk.Modulus).ToString();
            d = Rsa.FromBigEndian(pk.D);
            rsa = new Rsa(RsaModulus);
            GuardKey = Encoding.ASCII.GetBytes("demo-tour-key-0123456789abcdef-1");
            Reset();
            BuildScript();
        }

        void Reset()
        {
            hero = Start;
            health = MaxHealth; mana = MaxMana;
            mobs.Clear();
            int cx = Map.Center.X, cy = Map.Center.Y;
            AddMob(SkeletonId, "Skeleton", 1, new Pos(cx + 8, cy - 1, 7), art.OutfitMonster);
            AddMob(GhoulId, "Ghoul", 1, new Pos(cx - 5, cy - 1, 7), art.OutfitMonster);
            AddMob(ArcherId, "Skeleton Archer", 1, new Pos(cx + 7, cy - 3, 7), art.OutfitMonster);
            AddMob(NpcId, NpcName, 2, new Pos(cx + 3, cy + 3, 7), art.OutfitNpc);
            next = 0;
        }

        void AddMob(uint id, string name, byte type, Pos at, int look) { mobs[id] = new Mob { Id = id, Name = name, Type = type, At = at, Look = look, Light = type == 2 ? 4 : 0 }; }

        public IEnumerable<Pos> MobPositions { get { lock (gate) { var l = new List<Pos>(); foreach (var m in mobs.Values) l.Add(m.At); return l; } } }
        public bool InGame { get { lock (gate) return cur != null && cur.Entered; } }
        public Pos HeroPos { get { lock (gate) return hero; } }
        public bool HasMob(uint id) { lock (gate) return mobs.ContainsKey(id); }
        public int Health { get { lock (gate) return health; } }
        public int ScriptEvents => script.Count;

        // ------------------------------------------------------------------------------------ sockets
        /// <summary>Starts listening on two free localhost ports: login (Port) and game (GamePort).</summary>
        public void Begin()
        {
            listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            Port = ((IPEndPoint)listener.LocalEndpoint).Port;
            gameListener = new TcpListener(IPAddress.Loopback, 0);
            gameListener.Start();
            GamePort = ((IPEndPoint)gameListener.LocalEndpoint).Port;
            new Thread(() => AcceptLoop(listener, false)) { IsBackground = true, Name = "demo-server-login" }.Start();
            new Thread(() => AcceptLoop(gameListener, true)) { IsBackground = true, Name = "demo-server-game" }.Start();
        }

        void AcceptLoop(TcpListener l, bool game)
        {
            while (!stop)
            {
                TcpClient c;
                try { c = l.AcceptTcpClient(); }
                catch (Exception) { return; }
                new Thread(() => Serve(c, game)) { IsBackground = true, Name = "demo-server-conn" }.Start();
            }
        }

        public void Dispose()
        {
            stop = true;
            try { listener?.Stop(); } catch (Exception) { }
            try { gameListener?.Stop(); } catch (Exception) { }
            lock (gate) { try { cur?.S.Close(); } catch (Exception) { } cur = null; }
        }

        void Serve(TcpClient cl, bool game)
        {
            try
            {
                cl.NoDelay = true;
                var s = cl.GetStream();
                // one port per kind: a slow client (a player under software GL takes more than a second to send its login) is never taken for a game client
                if (game) ServeGame(s); else ServeLogin(s);
            }
            catch (Exception e)
            {
                if (!stop && !(e is IOException)) Problem = e.Message;   // a closed connection is the normal end
            }
            finally { try { cl.Close(); } catch (Exception) { } }
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

        void ServeLogin(Stream s)
        {
            var r = new ByteReader(ReadBody(s));
            r.U32();
            if (r.U8() != 0x01) throw new Exception("not a login packet");
            r.U16(); r.U16(); r.U32(); r.U32(); r.U32(); r.U32(); r.U8();
            var plain = new ByteReader(rsa.DecryptWith(d, r.Bytes(rsa.Size)));
            if (plain.U8() != 0) throw new Exception("rsa block does not start with 0");
            var key = new uint[4];
            for (int i = 0; i < 4; i++) key[i] = plain.U32();
            string account = plain.Str(), password = plain.Str();
            var w = new ByteWriter();
            w.U8(0x14).Str("1\nDemo tour: a fake server on this computer.");
            w.U8(0x28).Str(account + "\n" + password + "\n\n0");
            w.U8(0x64).U8(1).U8(0).Str("Demo").Str("127.0.0.1").U16((ushort)GamePort).U8(0);
            w.U8(1).U8(0).Str(HeroName).U32(HeroLevel).U16(HeroVocation).U16((ushort)art.OutfitHero).U8(78).U8(69).U8(58).U8(76).U8(0).U16(0);
            w.U8(0).U8(1).U32(0);
            var p = Protocol.Encrypt(w.ToArray(), key);
            s.Write(p, 0, p.Length);
            Thread.Sleep(200);
            lock (gate) Logins++;
        }

        void ServeGame(Stream s)
        {
            var hello = new ByteWriter().U16(6).U8(0x1F).U32(0x11223344).U8(0x55).ToArray();
            var first = new ByteWriter().U16((ushort)(hello.Length + 4)).U32(Adler32.Of(hello, 0, hello.Length)).Raw(hello).ToArray();
            s.Write(first, 0, first.Length);
            var r = new ByteReader(ReadBody(s));
            r.U32();
            if (r.U8() != 0x0A) throw new Exception("not a game login");
            r.U16(); r.U16(); r.U32(); r.U16(); r.U8();
            var plain = new ByteReader(rsa.DecryptWith(d, r.Bytes(rsa.Size)));
            if (plain.U8() != 0) throw new Exception("rsa block does not start with 0");
            var key = new uint[4];
            for (int i = 0; i < 4; i++) key[i] = plain.U32();
            plain.U8(); plain.Str(); plain.Str(); plain.U32(); plain.U8();
            if (plain.U16() != 0) throw new Exception("the demo server speaks the plain wire only (identity Extended)");
            var conn = new Conn { S = s, Key = key };
            var nonce = new byte[16];
            for (int i = 0; i < 16; i++) nonce[i] = (byte)(i * 17 + 3);
            var sb = new StringBuilder("cg1:");
            foreach (byte b in nonce) sb.Append(b.ToString("x2"));
            lock (gate)
            {
                Reset();
                var w = new ByteWriter().U8(0x32).U8(0).U16(0);
                w.U8(0x32).U8(ClientGuard.ChallengeOpcode).Str(sb.ToString());
                w.U8(0x17).U32(HeroId).U16(0x32);
                for (int i = 0; i < 3; i++) w.U8(3).U32(int.MaxValue);
                w.U8(0).U8(0).U8(1).Str("").U16(25);
                w.U8(0x0A).U8(0x0F);
                w.U8(0x64).U16((ushort)Start.X).U16((ushort)Start.Y).U8((byte)Start.Z);
                Floors(w, Start.X - World.RangeLeft, Start.Y - World.RangeTop, Start.Z, World.ViewW, World.ViewH);
                w.U8(0x82).U8(220).U8(215);
                conn.Send(w.ToArray());
                var o = new Out(this);
                o.Stats();
                o.Skills();
                o.Spellbook();
                o.Buffs();
                o.Ext(65, Msg("sendPoints", 3.0));
                o.Flush(conn);
                cur = conn;
                conn.Entered = true;
            }
            while (!stop)
            {
                var body = ReadBody(s);
                Incoming(conn, Protocol.Decrypt(body, key));
            }
        }

        void Incoming(Conn c, byte[] payload)
        {
            if (payload.Length == 0) return;
            var r = new ByteReader(payload);
            byte op = r.U8();
            lock (gate)
            {
                switch (op)
                {
                    case 0x1D: Pings++; c.Send(new byte[] { 0x1E }); break;
                    case 0x65: Step(c, Dir.North); break;
                    case 0x66: Step(c, Dir.East); break;
                    case 0x67: Step(c, Dir.South); break;
                    case 0x68: Step(c, Dir.West); break;
                    case 0xA1: Attacks++; AttackTarget = r.U32(); break;
                    case 0x96: Says++; r.U8(); LastSay = r.Str(); break;
                    case 0x32:
                    {
                        byte eo = r.U8();
                        ExtRequests.TryGetValue(eo, out int n);
                        ExtRequests[eo] = n + 1;
                        if (ModuleResponder) Respond(c, eo, r);
                        break;
                    }
                    case 0x97:
                        if (ModuleResponder)
                        {
                            // the channel list (engine protocolgame.cpp sendChannelsDialog: 0xAB, u8 count, u16 id + string name per channel)
                            var w = new ByteWriter().U8(0xAB).U8(3);
                            w.U16(0x0003).Str("Party").U16(0x0004).Str("Guild").U16(0x0009).Str("Trade");
                            c.Send(w.ToArray());
                            Answered++;
                        }
                        break;
                }
            }
        }

        /// <summary>Answers one extended request with the sample messages of Core/FakeModules.cs. Called with the gate held.</summary>
        void Respond(Conn c, byte op, ByteReader r)
        {
            object request = null;
            try { request = Json.TryParse(ExtOpcodes.FromWire(r.Str())); } catch (Exception) { }
            var answers = request == null ? new List<FakeMsg>() : FakeModules.Answer(op, request);
            if (answers.Count == 0)
            {
                Unanswered++;
                string key = op + ":" + Json.Text(request, "action");
                if (!UnansweredList.Contains(key)) UnansweredList.Add(key);
                return;
            }
            var o = new Out(this);
            foreach (var m in answers) o.Ext(m.Op, m.Root);
            o.Flush(c);
            Answered += answers.Count;
        }

        /// <summary>Sends server messages the player did not ask for (the smoke run's context pushes). Thread safe; false when nobody is in the game.</summary>
        public bool Push(IEnumerable<FakeMsg> messages)
        {
            lock (gate)
            {
                if (cur == null || !cur.Entered) return false;
                var o = new Out(this);
                foreach (var m in messages) o.Ext(m.Op, m.Root);
                o.Flush(cur);
                return true;
            }
        }

        /// <summary>Phase 13, track G (the smoke run): a player trade with a partner, as the server opens one: 0x7D your offer, 0x7E theirs (FakeModules.TradePacket). The items are ids the client knows
        /// (the tour's ground and tree ids), since the wire form of an item depends on the client's dat. Thread safe; false when nobody is in the game.</summary>
        public bool PushTrade(string partner)
        {
            lock (gate)
            {
                if (cur == null || !cur.Entered) return false;
                var ids = new List<int>();
                foreach (int id in new[] { art.Grass, art.Path, art.Tree, art.Rock, art.Wall, art.Torch }) if (id > 0 && !ids.Contains(id)) ids.Add(id);
                if (ids.Count == 0) return false;
                int At(int i) => ids[i % ids.Count];
                var own = new[] { new[] { At(0), 1 }, new[] { At(1), 3 } };
                var theirs = new[] { new[] { At(2), 1 } };
                Func<int, bool> counted = id => art.Counted.Contains(id), phased = id => art.Phased.Contains(id);
                var w = new ByteWriter();
                foreach (byte b in FakeModules.TradePacket(0x7D, partner, own, counted, phased)) w.U8(b);
                foreach (byte b in FakeModules.TradePacket(0x7E, partner, theirs, counted, phased)) w.U8(b);
                cur.Send(w.ToArray());
                return true;
            }
        }

        // ------------------------------------------------------------------------------------ the map on the wire
        /// <summary>The server's floor encoding (protocolgame.cpp GetFloorDescription): skip counters across floors; only floor 7 has tiles.</summary>
        void Floors(ByteWriter w, int x, int y, int z, int width, int height)
        {
            int skip = -1;
            for (int nz = 7; nz >= 0; nz--)
            {
                int offset = z - nz;
                for (int nx = 0; nx < width; nx++)
                    for (int ny = 0; ny < height; ny++)
                    {
                        bool has = nz == 7;
                        if (has)
                        {
                            if (skip >= 0) w.U8((byte)skip).U8(0xFF);
                            skip = 0;
                            Tile(w, x + nx + offset, y + ny + offset);
                        }
                        else if (skip == 0xFE) { w.U8(0xFF).U8(0xFF); skip = -1; }
                        else skip++;
                    }
            }
            if (skip >= 0) w.U8((byte)skip).U8(0xFF);
        }

        void Tile(ByteWriter w, int x, int y)
        {
            w.U16(0);   // no environment effect
            Item(w, Map.Ground(x, y));
            int item = Map.Item(x, y);
            if (item != 0) Item(w, item);
            if (hero.X == x && hero.Y == y) Creature(w, HeroId, HeroName, 0, art.OutfitHero, 100, 220, 3, 215, HeroVocation);
            foreach (var m in mobs.Values)
                if (m.At.X == x && m.At.Y == y) Creature(w, m.Id, m.Name, m.Type, m.Look, m.Hp, m.Type == 2 ? 100 : 150, m.Light, 0, 0);
        }

        void Item(ByteWriter w, int id)
        {
            w.U16((ushort)id).U8(0xFF);
            if (art.Counted.Contains(id)) w.U8(1);
            if (art.Phased.Contains(id)) w.U8(0xFE);
        }

        static void Creature(ByteWriter w, uint id, string name, byte type, int look, int hp, int speed, int light, int lightColor, int vocation)
        {
            w.U16(0x61).U32(0).U32(id).U8(type).Str(name);
            w.U8((byte)hp).U8(2).U16((ushort)look).U8(78).U8(69).U8(58).U8(76).U8(0).U16(0);   // health %, south, outfit and colours, no mount
            w.U8((byte)light).U8((byte)lightColor).U16((ushort)speed).U8(0).U8(0).U8(0).U8(type).U8(0).U8(0xFF).U16(0).U8(1);
        }

        void Step(Conn c, Dir dir)
        {
            int dx = dir == Dir.East ? 1 : dir == Dir.West ? -1 : 0, dy = dir == Dir.South ? 1 : dir == Dir.North ? -1 : 0;
            var to = hero.Offset(dx, dy);
            bool taken = false;
            foreach (var m in mobs.Values) if (m.At == to) taken = true;
            if (!Map.Walkable(to.X, to.Y) || taken)
            {
                Blocked++;
                c.Send(new byte[] { 0xB5, (byte)dir });
                return;
            }
            Steps++;
            var from = hero;
            hero = to;
            var w = new ByteWriter().U8(0x6D).U16((ushort)from.X).U16((ushort)from.Y).U8(7).U8(1).U16((ushort)to.X).U16((ushort)to.Y).U8(7);
            switch (dir)
            {
                case Dir.North: w.U8(0x65); Floors(w, to.X - World.RangeLeft, to.Y - World.RangeTop, 7, World.ViewW, 1); break;
                case Dir.East: w.U8(0x66); Floors(w, to.X + World.RangeRight, to.Y - World.RangeTop, 7, 1, World.ViewH); break;
                case Dir.South: w.U8(0x67); Floors(w, to.X - World.RangeLeft, to.Y + World.RangeBottom, 7, World.ViewW, 1); break;
                default: w.U8(0x68); Floors(w, to.X - World.RangeLeft, to.Y - World.RangeTop, 7, 1, World.ViewH); break;
            }
            c.Send(w.ToArray());
        }

        // ------------------------------------------------------------------------------------ the script
        /// <summary>Plays every event due at `ms` (from the first recorded frame). Call once per frame from one thread.</summary>
        public void Advance(double ms)
        {
            lock (gate)
            {
                if (cur == null || !cur.Entered) return;
                var o = new Out(this);
                while (next < script.Count && script[next].Key <= ms) script[next++].Value(o);
                o.Flush(cur);
            }
        }

        public bool Finished { get { lock (gate) return next >= script.Count; } }

        void At(double ms, Action<Out> run) { script.Add(new KeyValuePair<double, Action<Out>>(ms, run)); }

        static Dictionary<string, object> Msg(string action, object data) => new Dictionary<string, object> { { "action", action }, { "data", data } };
        static Dictionary<string, object> Flat(string action, params object[] kv)
        {
            var m = new Dictionary<string, object> { { "action", action } };
            for (int i = 0; i + 1 < kv.Length; i += 2) m[(string)kv[i]] = kv[i + 1];
            return m;
        }

        void BuildScript()
        {
            int cx = Map.Center.X, cy = Map.Center.Y;
            // the pack walks in: the skeleton along the row north of the path, the ghoul from the west
            for (int i = 1; i <= 5; i++) { int x = cx + 8 - i; At(1300 + (i - 1) * 750, o => o.Move(SkeletonId, new Pos(x, cy - 1, 7))); }
            for (int i = 1; i <= 6; i++) { int x = cx - 5 + i; At(1500 + (i - 1) * 750, o => o.Move(GhoulId, new Pos(x, cy - 1, 7))); }
            At(600, o => o.Ext(79, Flat("journey", "message", "Ashen Fields: the dead walk at dusk.")));
            // the skeleton fight: four hits, the archer shoots, a fire spell, the skeleton falls
            var hits = new[] { 5000.0, 5900.0, 6900.0, 7300.0 };
            var left = new[] { 78, 56, 8, 0 };
            var dmg = new uint[] { 120, 95, 140, 110 };
            for (int i = 0; i < hits.Length; i++)
            {
                int k = i;
                At(hits[k], o => o.Hit(SkeletonId, dmg[k], 180, 1, left[k]));
            }
            foreach (double t in new[] { 5400.0, 6300.0 }) At(t, o => o.Struck(SkeletonId, 38));
            foreach (double t in new[] { 5200.0, 6100.0, 7000.0, 7900.0 }) At(t, o => o.Shoot(ArcherId, 3, 26));
            At(TourPlan.CastFury, o =>
            {
                o.Say(9, HeroName, hero, "exori gran");
                o.Mana(60);
                o.Effect(hero, 7);
                o.Effect(hero.Offset(1, 0), 7);
                o.Effect(hero.Offset(-1, 0), 7);
                o.Number(23, Pos_(SkeletonId), 210, 192);
                o.Number(23, Pos_(GhoulId), 210, 192);
                o.SetHp(SkeletonId, 28);
                o.SetHp(GhoulId, 70);
                o.Cooldown(1, 4000);
                o.GroupCooldown(1, 2000);
                o.Ext(234, Msg("diff", new Dictionary<string, object> { { "add", new List<object> { Buff("fury", "Fury", "Your strikes hit harder for a short while.", "fury", false, 8000) } } }));
            });
            At(7400, o => { o.Remove(SkeletonId); o.Text(22, "Loot of a skeleton: 14 gold coins, a bone."); o.Number(26, hero.Offset(2, 0), 340, 215); });
            // the ghoul fight
            var ghoulHits = new[] { 8000.0, 8800.0, 9600.0, 10300.0 };
            var ghoulLeft = new[] { 50, 32, 12, 0 };
            for (int i = 0; i < ghoulHits.Length; i++)
            {
                int k = i;
                At(ghoulHits[k], o => o.Hit(GhoulId, 105 + 12u * (uint)k, 180, 1, ghoulLeft[k]));
            }
            foreach (double t in new[] { 8300.0, 9200.0 }) At(t, o => o.Struck(GhoulId, 44));
            At(TourPlan.CastHeal, o =>
            {
                o.Say(9, HeroName, hero, "exura gran ico");
                o.Mana(80);
                o.Effect(hero, 36);
                o.Heal(hero, 320, 30);
                o.Cooldown(2, 6000);
            });
            At(10400, o => { o.Remove(GhoulId); o.Text(22, "Loot of a ghoul: 9 gold coins, a rotten heart."); o.Number(26, hero.Offset(-1, 0), 520, 215); });
            At(9000, o => o.Ext(79, Flat("achievement", "message", "Achievement unlocked: First Blood")));
            // the NPC
            At(TourPlan.SayHi + 300, o => o.Say(10, NpcName, Pos_(NpcId), "Greetings, wanderer. I sell potions and bandages. Would you like to trade?"));
            At(TourPlan.ShopOpens, o => o.Shop());
            // the party
            At(TourPlan.PartyInvite, o =>
            {
                o.Text(4, "Mira has invited you to join her party.");
                o.Ext(79, Flat("partyInvite", "inviterName", "Mira", "inviterResets", 3, "element", "fire", "level", 12));
            });
            At(TourPlan.PartyJoins, o => o.Ext(235, Msg("state", PartyState())));
            At(TourPlan.Total - 500, o => o.Ext(79, Flat("seasonpass", "message", "Season pass: 120 experience toward the next reward.")));
            script.Sort((a, b) => a.Key.CompareTo(b.Key));
        }

        Pos Pos_(uint id) { Mob m; return mobs.TryGetValue(id, out m) ? m.At : hero; }

        static Dictionary<string, object> Buff(string key, string name, string desc, string icon, bool debuff, int ms)
        {
            return new Dictionary<string, object> { { "k", key }, { "n", name }, { "d", desc }, { "i", icon }, { "t", debuff ? 1 : 0 }, { "l", ms } };
        }

        Dictionary<string, object> PartyState()
        {
            Func<uint, string, int, int, int, int, int, int, bool, Dictionary<string, object>> member = (id, name, lv, vc, hp, hpMax, mp, mpMax, leader) =>
                new Dictionary<string, object>
                {
                    { "i", id }, { "n", name }, { "lv", lv }, { "vc", vc }, { "p", 40 }, { "dz", 0 }, { "f", (leader ? 1 : 0) | (id == HeroId ? 16 : 0) }, { "far", 0 },
                    { "h", hp }, { "H", hpMax }, { "m", mp }, { "M", mpMax }, { "d", id == HeroId ? 0 : 4 },
                    { "o", new Dictionary<string, object> { { "t", art.OutfitHero }, { "h", 78 }, { "b", 69 }, { "l", 58 }, { "f", 76 }, { "a", 0 } } },
                    { "b", new List<object> { new Dictionary<string, object> { { "i", "haste" }, { "n", "Haste" }, { "t", 0 }, { "l", 12000 } } } },
                };
            return new Dictionary<string, object>
            {
                { "leader", 0x10000010u },
                { "members", new List<object>
                    {
                        member(0x10000010u, "Mira", 162, 12, 880, 1100, 310, 400, true),
                        member(HeroId, HeroName, HeroLevel, HeroVocation, Math.Max(1, health), MaxHealth, mana, MaxMana, false),
                        member(0x10000011u, "Dorn", 148, 5, 640, 900, 520, 700, false),
                    } },
                { "xp", new Dictionary<string, object> { { "p", 15 }, { "on", 1 } } },
            };
        }

        /// <summary>The packets of one moment, written under the gate and sent as one payload.</summary>
        sealed class Out
        {
            readonly FakeGameServer s;
            readonly ByteWriter w = new ByteWriter();
            public Out(FakeGameServer server) { s = server; }

            public void Flush(Conn c)
            {
                if (w.Length == 0) return;
                c.Send(w.ToArray());
            }

            static ByteWriter PosW(ByteWriter b, Pos p) => b.U16((ushort)p.X).U16((ushort)p.Y).U8((byte)p.Z);

            public void Move(uint id, Pos to)
            {
                if (!s.mobs.TryGetValue(id, out var m)) return;
                m.At = to;
                w.U8(0x6D).U16(0xFFFF).U32(id);
                PosW(w, to);
            }

            public void Remove(uint id)
            {
                if (!s.mobs.ContainsKey(id)) return;
                s.mobs.Remove(id);
                w.U8(0x6C).U16(0xFFFF).U32(id);
                // the server drops a dead target as the base does (cancel target), so the client's dead guard never has to
                if (s.AttackTarget == id) w.U8(0xA3).U32(0);
            }

            public void SetHp(uint id, int percent)
            {
                if (s.mobs.TryGetValue(id, out var m)) m.Hp = percent;
                w.U8(0x8C).U32(id).U8((byte)percent);
            }

            public void Effect(Pos p, int id) { PosW(w.U8(0x83), p).U16((ushort)id); }

            public void Missile(Pos a, Pos b, int id) { PosW(PosW(w.U8(0x85), a), b).U8((byte)id); }

            /// <summary>0xB4 with a position: damage dealt (23), taken (24), healing (25), experience (26).</summary>
            public void Number(byte kind, Pos at, uint value, byte color, string text = "")
            {
                PosW(w.U8(0xB4).U8(kind), at).U32(value).U8(color);
                if (kind == 23 || kind == 24 || kind == 27) w.U32(0).U8(0);
                w.Str(text);
            }

            public void Text(byte kind, string text) { w.U8(0xB4).U8(kind).Str(text); }

            public void Say(byte type, string name, Pos at, string text)
            {
                w.U8(0xAA).U32(0).Str(name).U16(type == 10 ? (ushort)0 : (ushort)HeroLevel).U8(type);
                PosW(w, at).Str(text);
            }

            public void Cooldown(int spell, uint ms) { w.U8(0xA4).U8((byte)spell).U32(ms); }
            public void GroupCooldown(int group, uint ms) { w.U8(0xA5).U8((byte)group).U32(ms); }

            /// <summary>The hero hits a creature: the effect on it, the damage number, its health bar; at 0 it stays until Remove.</summary>
            public void Hit(uint id, uint damage, byte color, int effect, int percent)
            {
                var at = s.Pos_(id);
                Effect(at, effect);
                Number(23, at, damage, color);
                SetHp(id, percent);
            }

            /// <summary>A creature hits the hero.</summary>
            public void Struck(uint id, uint damage)
            {
                s.health = Math.Max(1, s.health - (int)damage);
                Effect(s.hero, 1);
                Number(24, s.hero, damage, 180);
                Stats();
            }

            /// <summary>A ranged creature shoots the hero: the missile, the hit, the number.</summary>
            public void Shoot(uint id, int missile, uint damage)
            {
                Missile(s.Pos_(id), s.hero, missile);
                Struck(id, damage);
            }

            public void Heal(Pos at, uint value, byte color)
            {
                s.health = Math.Min(MaxHealth, s.health + (int)value);
                Number(25, at, value, color);
                Stats();
            }

            public void Mana(int cost) { s.mana = Math.Max(0, s.mana - cost); Stats(); }

            public void Stats()
            {
                w.U8(0xA0).U32((uint)s.health).U32(MaxHealth).U32(30000).U32(40000).U32(1500000).U32(0).U16(HeroLevel).U8(35);
                w.Zeros(10);
                w.U32((uint)s.mana).U32(MaxMana).U8(40).U8(40).U8(20).U8(100).U16(2520).U16(220).Zeros(7);
            }

            public void Skills()
            {
                w.U8(0xA1);
                int[] levels = { 110, 118, 126, 96, 140, 20, 12 };
                for (int i = 0; i < 7; i++) w.U16((ushort)levels[i]).U16((ushort)levels[i]).U8((byte)(20 + 9 * i));
                for (int i = 0; i < 7; i++) w.U16(10).U16(10).U8(0);
                w.Zeros(24);
            }

            public void Shop()
            {
                string[] names = { "Health Potion", "Mana Potion", "Bandage", "Apple", "Torch" };
                uint[] buy = { 50, 45, 20, 3, 8 }, sell = { 0, 0, 5, 1, 2 };
                int n = Math.Min(names.Length, s.art.ShopIds.Length);
                w.U8(0x7A).Str(NpcName).U16((ushort)n);
                for (int i = 0; i < n; i++) w.U16(s.art.ShopIds[i]).U8(0).Str(names[i]).U32(180).U32(buy[i]).U32(sell[i]);
                w.U8(0x7B).U32(12500).U32(0).U8((byte)Math.Min(3, n));
                for (int i = 0; i < Math.Min(3, n); i++) w.U16(s.art.ShopIds[i]).U8((byte)(2 + i));
            }

            public void Ext(byte op, object json)
            {
                foreach (var part in ExtChunks.Split(ExtOpcodes.ToWire(Json.Serialize(json)))) w.U8(0x32).U8(op).Str(part);
            }

            public void Buffs()
            {
                Ext(234, Msg("full", new Dictionary<string, object>
                {
                    { "list", new List<object>
                        {
                            Buff("haste", "Haste", "Faster steps.", "haste", false, 45000),
                            Buff("blessing", "Ember Blessing", "Less damage from the dead.", "blessing", false, 600000),
                            Buff("weak", "Frayed", "A little less armour.", "weak", true, 30000),
                        } },
                }));
            }

            public void Spellbook()
            {
                var spells = new List<object>();
                Action<string, string, string, int, int, int, int, string, string> add = (name, words, element, level, ml, mana, cd, kind, text) =>
                    spells.Add(new Dictionary<string, object>
                    {
                        { "name", name }, { "words", words }, { "type", "instant" }, { "element", element }, { "target", "area" }, { "id", spells.Count + 1 },
                        { "level", level }, { "maglevel", ml }, { "mana", mana }, { "cooldown", cd }, { "groupCooldown", 2000 }, { "range", 1 },
                        { "group", kind }, { "description", text }, { "vocations", new List<object> { HeroVocation } },
                        { "area", new List<object> { new List<object> { 0, 1, 0 }, new List<object> { 1, 2, 1 }, new List<object> { 0, 1, 0 } } },
                    });
                add("Fury Strike", "exori gran", "fire", 90, 0, 60, 4000, "attack", "A fiery blow that hits every enemy next to you.");
                add("Ember Slam", "exori", "fire", 20, 0, 30, 2000, "attack", "A heavy strike on one target.");
                add("Whirlwind", "exori mas", "physical", 60, 0, 50, 5000, "attack", "Spin and hit everything around you.");
                add("Groundshaker", "exori mas pug", "earth", 110, 0, 90, 8000, "attack", "Shake the ground under the pack.");
                add("Challenge", "exeta res", "physical", 30, 0, 40, 10000, "support", "Make nearby monsters turn on you.");
                add("Battle Cry", "utito tempo", "physical", 55, 0, 70, 12000, "support", "More damage for a short while.");
                add("Intense Healing", "exura gran ico", "heal", 80, 0, 80, 6000, "support", "Heals a large part of your health.");
                add("Haste", "utani hur", "neutral", 14, 0, 40, 22000, "support", "Move faster for a while.");
                add("Iron Skin", "utamo tempo", "physical", 70, 0, 100, 15000, "support", "Take less damage for a short while.");
                add("Cinder Wave", "exevo flam hur", "fire", 150, 0, 120, 8000, "attack", "A wave of embers in front of you.");
                var open = new Dictionary<string, object>
                {
                    { "vocation", HeroVocation }, { "level", HeroLevel }, { "magicLevel", 40 }, { "total", spells.Count },
                    { "learned", new List<object>() },
                    { "vocationNames", new List<object> { new Dictionary<string, object> { { "id", HeroVocation }, { "name", "Juggernaut" } } } },
                };
                Ext(219, Msg("open", open));
                Ext(219, Msg("spells", new Dictionary<string, object> { { "spells", spells } }));
                Ext(219, Msg("done", new Dictionary<string, object> { { "sig", "demo-1" } }));
            }
        }
    }
}
