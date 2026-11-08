// The game connection: the parser of the server's messages (into a World), the client guard handshake, pings and
// walking. The parser runs on the caller's thread (GameSession.Poll from Unity's Update), so World is single-threaded.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Chaos.Core
{
    /// <summary>Reads server messages into a World. Stateless apart from the World and a few counters, so tests can feed
    /// it payloads directly.</summary>
    public sealed partial class GameParser
    {
        public readonly World W;
        public Func<double> Clock = () => 0;
        public Action<byte, string> ExtendedOpcode = delegate { };
        public Action<string> Text = delegate { };
        /// <summary>A chat line: speaker (empty for a server message), text, talk type (0 for a server message).</summary>
        public Action<string, string, byte> Chat = delegate { };
        public Action<string> Disconnected = delegate { };
        public Action Pinged = delegate { };
        public Action<Dir> WalkCancelled = delegate { };
        public Action<Creature> PlayerMoved = delegate { };
        public bool LoggedIn;
        /// <summary>The NPC shop of 0x7A, 0x7B and 0x7C, and the NPC conversation (Core/NpcTrade.cs).</summary>
        public readonly NpcTradeState Trade = new NpcTradeState();
        public readonly NpcTalkState NpcTalk = new NpcTalkState();
        /// <summary>What we told the server at the game login: Markers decides whether outfits carry wings, aura and shader.</summary>
        public ClientIdentity Identity = ClientIdentity.Extended;
        /// <summary>The 0x43 feature list (only on an Identity.Chaos connection). Item attributes (126) and the width of the
        /// spell id of 0xA4 (152) depend on it; the effect and text parsers read the rest from it.</summary>
        public readonly ClientFeatures Features = new ClientFeatures();
        /// <summary>The aware range of the last 0x42: the view is 18 x 14 tiles (17 x 13 plus one), the only size read.</summary>
        public int AwareW = 17, AwareH = 13;
        /// <summary>0xA4: spell id (u8, or u16 with feature 152) and the cooldown in ms. 0xA5: group id and ms.</summary>
        public Action<int, uint> SpellCooldown = delegate { };
        public Action<int, uint> GroupCooldown = delegate { };
        /// <summary>The creature we attack (0 none). Set by GameSession.Attack, cleared by the server's 0xA3.</summary>
        public uint AttackTarget;
        public int Health, MaxHealth, Mana, MaxMana, Level;
        /// <summary>0xA2: the status icon bits (1 poison, 2 burning, 4 energy, 8 drunk, 16 mana shield, 32 paralyzed, 64 haste, 16384 protection zone ...). The helper reads haste and the zone.</summary>
        public int PlayerStates;
        // more of 0xA0 (player stats)
        public uint FreeCap, TotalCap;
        public ulong Experience;
        public int LevelPercent, MagicLevel, BaseMagicLevel, MagicPercent, Soul, Stamina, Speed;
        /// <summary>0xA1: fist, club, sword, axe, distance, shielding, fishing.</summary>
        public readonly SkillValue[] Skills = new SkillValue[7];
        /// <summary>0xA1, the seven skills after fishing: crafting, woodcutting, mining, herbalist, armorsmith, weaponsmith, jewelsmith (Chaos wire).</summary>
        public readonly SkillValue[] CraftSkills = new SkillValue[7];
        /// <summary>Equipment slots 1..10 (0 unused). Null when empty.</summary>
        public readonly Item[] Inventory = new Item[11];
        /// <summary>Open containers by server container id.</summary>
        public readonly Dictionary<byte, Container> Containers = new Dictionary<byte, Container>();
        /// <summary>A container was opened (by id) or closed.</summary>
        public Action<byte> ContainerOpened = delegate { };
        public Action<byte> ContainerClosed = delegate { };
        public readonly Dictionary<byte, int> Seen = new Dictionary<byte, int>();

        public GameParser(World w) { W = w; }

        Pos ReadPos(ByteReader r) => new Pos(r.U16(), r.U16(), r.U8());

        /// <summary>All messages of one payload. Throws ProtocolException on an opcode it cannot read.</summary>
        public void Parse(byte[] payload)
        {
            var r = new ByteReader(payload);
            while (!r.AtEnd)
            {
                byte op = r.U8();
                Seen.TryGetValue(op, out int n);
                Seen[op] = n + 1;
                Message(op, r);
            }
        }

        void Message(byte op, ByteReader r)
        {
            switch (op)
            {
                case 0x0A: case 0x0F: break;                      // pending state, enter world
                case 0x14: Disconnected(r.Str()); break;
                case 0x15: Text(r.Str()); break;
                case 0x16: Disconnected(r.Str() + " (waiting list)"); r.U8(); break;
                case 0x17:
                    W.PlayerId = r.U32();
                    r.U16(); r.Double(); r.Double(); r.Double();
                    r.U8(); r.U8(); r.U8(); r.Str(); r.U16();
                    LoggedIn = true;
                    break;
                case 0x1D: Pinged(); break;
                case 0x1E: break;
                case 0x1F: r.U32(); r.U8(); break;
                case 0x28: Death(r); break;
                case 0x32: ExtendedOpcode(r.U8(), r.Str()); break;
                case 0x42:
                {
                    AwareW = r.U8(); AwareH = r.U8();
                    if (AwareW + 1 != World.ViewW || AwareH + 1 != World.ViewH)
                        throw new ProtocolException("aware range " + AwareW + "x" + AwareH + ": only " + (World.ViewW - 1) + "x" + (World.ViewH - 1) + " is read");
                    break;
                }
                case 0x43: Features.Read(r); break;
                case 0x4B:
                {
                    // a floor of the view on its own (OTCv8 clients get the floors of a change of level this way, before 0xBE / 0xBF)
                    var p = ReadPos(r);
                    int floor = r.U8();
                    if (floor > 15) throw new ProtocolException("floor " + floor);
                    if (p.Z == floor) SetCenter(p);
                    FloorDescription(r, p.X - World.RangeLeft, p.Y - World.RangeTop, floor, World.ViewW, World.ViewH, p.Z - floor, 0);
                    break;
                }
                case 0x64:
                {
                    var p = ReadPos(r);
                    SetCenter(p);
                    W.Tiles.Clear();
                    MapDescription(r, p.X - World.RangeLeft, p.Y - World.RangeTop, p.Z, World.ViewW, World.ViewH);
                    break;
                }
                case 0x65: { var c = W.Center; c.Y--; MapDescription(r, c.X - World.RangeLeft, c.Y - World.RangeTop, c.Z, World.ViewW, 1); SetCenter(c); break; }
                case 0x66: { var c = W.Center; c.X++; MapDescription(r, c.X + World.RangeRight, c.Y - World.RangeTop, c.Z, 1, World.ViewH); SetCenter(c); break; }
                case 0x67: { var c = W.Center; c.Y++; MapDescription(r, c.X - World.RangeLeft, c.Y + World.RangeBottom, c.Z, World.ViewW, 1); SetCenter(c); break; }
                case 0x68: { var c = W.Center; c.X--; MapDescription(r, c.X - World.RangeLeft, c.Y - World.RangeTop, c.Z, 1, World.ViewH); SetCenter(c); break; }
                case 0x69: { var p = ReadPos(r); TileDescription(r, p); break; }
                case 0x6A:
                {
                    var p = ReadPos(r);
                    int sp = r.U8();
                    W.AddThing(p, ReadThing(r), sp);
                    break;
                }
                case 0x6B:
                {
                    var (p, sp, cr) = Mapped(r);
                    var pos = cr != null ? cr.Position : p;
                    var th = ReadThing(r);
                    if (cr == null && sp >= 0) W.RemoveAt(p, sp);
                    else if (cr != null && !th.IsCreature) W.RemoveCreature(cr);
                    if (th.IsCreature && (th.Creature.Id == 0 || OnTile(pos, th.Creature))) break;   // a turn: updated in place
                    W.AddThing(pos, th, sp);
                    break;
                }
                case 0x6C:
                {
                    var (p, sp, cr) = Mapped(r);
                    if (cr != null) W.RemoveCreature(cr);
                    else if (sp >= 0) W.RemoveAt(p, sp);
                    break;
                }
                case 0x6D: MoveCreature(r); break;
                case 0x6E:
                {
                    var c = new Container { Id = r.U8() };
                    c.ItemId = r.U16(); ReadItem(r, c.ItemId);
                    c.Name = r.Str(); c.Capacity = r.U8(); c.HasParent = r.U8() != 0;
                    r.U8(); r.U8();   // isUnlocked, hasPages
                    c.Size = r.U16(); c.FirstIndex = r.U16();
                    for (int n = r.U8(), i = 0; i < n; i++) c.Items.Add(ReadItem(r, r.U16()));
                    Containers[c.Id] = c;
                    ContainerOpened(c.Id);
                    break;
                }
                case 0x6F: { byte cid = r.U8(); Containers.Remove(cid); ContainerClosed(cid); break; }
                case 0x70:
                {
                    byte cid = r.U8(); int slot = r.U16(); var it = ReadItem(r, r.U16());
                    if (Containers.TryGetValue(cid, out var c))
                    {
                        int at = slot - c.FirstIndex;
                        c.Items.Insert(Math.Max(0, Math.Min(at, c.Items.Count)), it);
                        c.Size++;
                    }
                    break;
                }
                case 0x71:
                {
                    byte cid = r.U8(); int slot = r.U16(); var it = ReadItem(r, r.U16());
                    if (Containers.TryGetValue(cid, out var c))
                    {
                        int at = slot - c.FirstIndex;
                        if (at >= 0 && at < c.Items.Count) c.Items[at] = it;
                    }
                    break;
                }
                case 0x72:
                {
                    byte cid = r.U8(); int slot = r.U16(); ushort id = r.U16();
                    var last = id != 0 ? ReadItem(r, id) : null;
                    if (Containers.TryGetValue(cid, out var c))
                    {
                        int at = slot - c.FirstIndex;
                        if (at >= 0 && at < c.Items.Count) c.Items.RemoveAt(at);
                        if (c.Size > 0) c.Size--;
                        if (last != null) c.Items.Add(last);   // the item that slid in from the next page
                    }
                    break;
                }
                case 0x78: { int slot = r.U8(); var it = ReadItem(r, r.U16()); if (slot >= 1 && slot < Inventory.Length) Inventory[slot] = it; InventoryChanged(); break; }
                case 0x79: { int slot = r.U8(); if (slot >= 1 && slot < Inventory.Length) Inventory[slot] = null; InventoryChanged(); break; }
                case 0x96: case 0x97: case 0xC8: case 0xFA: ItemsMessage(op, r); break;   // text windows, outfit window, modal windows (GameItems.cs)
                case 0x7A: Trade.ReadShop(r, Clock()); break;
                case 0x7B: Trade.ReadGoods(r); break;
                case 0x7C: Trade.Close(); break;
                case 0x82: W.WorldLight = r.U8(); W.WorldLightColor = r.U8(); break;
                case 0x83: { var p = ReadPos(r); int id = r.U16(); if (W.Fx.Enabled) W.Fx.Push(FxEvent.Effect(p, id)); break; }
                case 0x84: { var p = ReadPos(r); byte col = r.U8(); string t = r.Str(); if (W.Fx.Enabled) W.Fx.Push(FxEvent.AnimText(p, col, t)); break; }
                case 0x85: { var a = ReadPos(r); var b = ReadPos(r); int id = r.U8(); if (W.Fx.Enabled) W.Fx.Push(FxEvent.Missile(a, b, id)); break; }
                case 0x86: { uint cid = r.U32(); byte col = r.U8(); if (W.Fx.Enabled) W.Fx.Push(FxEvent.Square(cid, col)); break; }
                case 0x8C: { var c = Find(r.U32()); byte hp = r.U8(); if (c != null) c.HealthPercent = Math.Min(100, (int)hp); break; }
                case 0x8D: { var c = Find(r.U32()); byte l = r.U8(), col = r.U8(); if (c != null) { c.LightLevel = l; c.LightColor = col; } break; }
                case 0x8E: { var c = Find(r.U32()); var o = ReadOutfit(r); if (c != null) c.Outfit = o; break; }
                case 0x8F: { var c = Find(r.U32()); r.U16(); int s = r.U16(); if (c != null) c.Speed = s; break; }
                case 0x90: { var c = Find(r.U32()); byte v = r.U8(); if (c != null) c.Skull = v; break; }
                case 0x91: { var c = Find(r.U32()); byte v = r.U8(); if (c != null) c.Shield = v; break; }
                case 0x92: { var c = Find(r.U32()); byte v = r.U8(); if (c != null) c.Walkthrough = v == 0; break; }
                case 0x93: r.U32(); r.U8(); r.U8(); break;
                case 0x94: r.U32(); r.U16(); break;
                case 0x95: { var c = Find(r.U32()); byte v = r.U8(); if (c != null) c.Type = v; break; }
                case 0x9F: r.U8(); r.U32(); r.U8(); r.Skip(r.U16()); break;
                case 0xA0:
                    Health = (int)r.U32(); MaxHealth = (int)r.U32();
                    FreeCap = r.U32(); TotalCap = r.U32(); Experience = r.U64();
                    Level = r.U16(); LevelPercent = r.U8();
                    r.Skip(10);   // xp display, bonuses (5 x u16)
                    Mana = (int)r.U32(); MaxMana = (int)r.U32();
                    MagicLevel = r.U8(); BaseMagicLevel = r.U8(); MagicPercent = r.U8();
                    Soul = r.U8(); Stamina = r.U16(); Speed = r.U16();
                    r.Skip(2 + 2 + 2 + 1);   // regen, offline training, store xp boost, flag
                    break;
                case 0xA1:
                    for (int i = 0; i < Skills.Length; i++) Skills[i] = new SkillValue { Level = r.U16(), Base = r.U16(), Percent = r.U8() };
                    for (int i = 0; i < CraftSkills.Length; i++) CraftSkills[i] = new SkillValue { Level = r.U16(), Base = r.U16(), Percent = r.U8() };
                    r.Skip(6 * 4);   // the special skills
                    break;
                case 0xA2: PlayerStates = r.U16(); break;
                case 0xA3: r.U32(); AttackTarget = 0; break;   // cancel target
                case 0xA4: { int id = Features.Has(ClientFeatures.ExtendedSpellIds) ? r.U16() : r.U8(); SpellCooldown(id, r.U32()); break; }
                case 0xA5: { int g = r.U8(); GroupCooldown(g, r.U32()); break; }
                case 0xA7: r.U8(); r.U8(); r.U8(); r.U8(); break;
                case 0xAA: Talk(r); break;
                case 0xAB: ChannelList(r); break;
                case 0xAC: ChannelOpened(r, true); break;
                case 0xAD: PrivateOpened(r); break;
                case 0xB2: ChannelOpened(r, true); break;
                case 0xB3: ChannelClosed(r); break;
                case 0xB4: TextMessage(r); break;
                case 0xB5:
                {
                    var d = (Dir)r.U8();
                    var me = W.Player;
                    if (me != null) { me.Direction = d; me.WalkStart = -1; }
                    WalkCancelled(d);
                    break;
                }
                case 0xBE: FloorUp(r); break;
                case 0xBF: FloorDown(r); break;
                case 0xD2: r.U32(); r.Str(); r.Str(); r.U32(); r.U8(); r.U8(); break;
                case 0xD3: r.U32(); r.U8(); break;
                case 0xDC: r.U8(); break;
                case 0xDD: ReadPos(r); r.U8(); r.Str(); break;
                case 0xF3: r.U16(); r.Str(); r.U8(); break;
                default:
                    throw new ProtocolException("unknown opcode 0x" + op.ToString("X2") + " at " + (r.Pos - 1));
            }
        }

        void SetCenter(Pos p)
        {
            W.Center = p;
            W.ForgetOutside(p);
        }

        Creature Find(uint id) { W.Creatures.TryGetValue(id, out var c); return c; }

        /// <summary>A position + stack position, or 0xFFFF + creature id.</summary>
        (Pos p, int sp, Creature c) Mapped(ByteReader r)
        {
            ushort x = r.U16();
            if (x != 0xFFFF)
            {
                var p = new Pos(x, r.U16(), r.U8());
                int sp = r.U8();
                var th = W.ThingAt(p, sp);
                return (p, sp, th.HasValue && th.Value.IsCreature ? th.Value.Creature : null);
            }
            var cr = Find(r.U32());
            return (cr != null ? cr.Position : default, -1, cr);
        }

        void MoveCreature(ByteReader r)
        {
            var (from, sp, c) = Mapped(r);
            var to = ReadPos(r);
            if (c == null) return;
            W.RemoveCreature(c);
            from = c.Position;
            W.AddThing(to, new Thing { Creature = c });
            int dx = to.X - from.X, dy = to.Y - from.Y;
            if (from.Z == to.Z && Math.Max(Math.Abs(dx), Math.Abs(dy)) == 1)
            {
                c.Direction = DirOf(dx, dy, c.Direction);
                c.WalkFrom = from;
                c.WalkStart = Clock();
                c.WalkMs = StepMs(c, to, dx != 0 && dy != 0);
            }
            else c.WalkStart = -1;
            if (c.Id == W.PlayerId) PlayerMoved(c);
        }

        static Dir DirOf(int dx, int dy, Dir old)
        {
            if (dx > 0 && dy < 0) return Dir.NorthEast;
            if (dx > 0 && dy > 0) return Dir.SouthEast;
            if (dx < 0 && dy > 0) return Dir.SouthWest;
            if (dx < 0 && dy < 0) return Dir.NorthWest;
            if (dy < 0) return Dir.North;
            if (dy > 0) return Dir.South;
            if (dx > 0) return Dir.East;
            if (dx < 0) return Dir.West;
            return old;
        }

        /// <summary>The server's step duration (src-patch 0018), as server/tools/cast_relay.py step_ms computes it.</summary>
        public double StepMs(Creature c, Pos to, bool diagonal)
        {
            int ground = 150;
            var t = W.Get(to);
            if (t != null && t.Things.Count > 0 && !t.Things[0].IsCreature && t.Things[0].Item.Type != null && t.Things[0].Item.Type.Ground)
                ground = Math.Max(1, t.Things[0].Item.Type.GroundSpeed);
            bool player = c.Id == W.PlayerId;
            double calc = Math.Floor(857.36 * Math.Log(Math.Max(0, c.Speed) + 261.29) - 4795.01 + 0.5);
            calc = Math.Max(1, calc);
            long ms = (long)(1000 * ground / calc);
            if (diagonal) ms = player ? ms * 7 / 5 : ms * 3 / 2;
            int step = player ? 10 : 50;
            ms = (ms + step - 1) / step * step;
            return Math.Max(step, Math.Min(5000, ms));
        }

        void MapDescription(ByteReader r, int x, int y, int z, int w, int h)
        {
            int start, end, step;
            if (z > 7) { start = z - 2; end = Math.Min(z + 2, 15); step = 1; }
            else { start = 7; end = 0; step = -1; }
            int skip = 0;
            for (int nz = start; nz != end + step; nz += step)
                skip = FloorDescription(r, x, y, nz, w, h, z - nz, skip);
        }

        int FloorDescription(ByteReader r, int x, int y, int z, int w, int h, int offset, int skip)
        {
            for (int nx = 0; nx < w; nx++)
                for (int ny = 0; ny < h; ny++)
                {
                    var p = new Pos(x + nx + offset, y + ny + offset, z);
                    if (skip == 0) skip = TileDescription(r, p);
                    else { CleanTile(p); skip--; }
                }
            return skip;
        }

        void CleanTile(Pos p) { W.Clean(p); }

        bool OnTile(Pos p, Creature c)
        {
            var t = W.Get(p);
            if (t == null) return false;
            foreach (var th in t.Things) if (th.Creature == c) return true;
            return false;
        }

        /// <summary>One tile: an optional environment u16, things, then the end marker whose low byte is the new skip.</summary>
        int TileDescription(ByteReader r, Pos p)
        {
            CleanTile(p);
            if (r.PeekU16() >= 0xFF00) return r.U16() & 0xFF;
            r.U16();   // environment effect
            for (int sp = 0; ; sp++)
            {
                if (r.PeekU16() >= 0xFF00) return r.U16() & 0xFF;
                if (sp > 255) throw new ProtocolException("too many things on " + p);
                W.AddThing(p, ReadThing(r), sp);
            }
        }

        Thing ReadThing(ByteReader r)
        {
            ushort id = r.U16();
            if (id == 0x61 || id == 0x62 || id == 0x63) return new Thing { Creature = ReadCreature(r, id) };
            return new Thing { Item = ReadItem(r, id) };
        }

        Item ReadItem(ByteReader r, ushort id)
        {
            var it = W.MakeItem(id, 0);
            if (it.Type == null) throw new ProtocolException("item " + id + " is not in the dat (wrong pair?)");
            r.U8();   // mark
            if (it.Type.HasSubType) it.Count = r.U8();
            if (it.Type.HasPhaseByte) r.U8();
            if (Features.Has(ClientFeatures.ItemCustomAttributes))
            {
                // src-patch 0003: u16 count, then u16 key and u64 value each
                int n = r.U16();
                if (n > 64) throw new ProtocolException("too many item attributes (" + n + ")");
                if (n > 0) it.Attrs = new Dictionary<ushort, ulong>();
                for (int i = 0; i < n; i++) { ushort k = r.U16(); it.Attrs[k] = r.U64(); }
            }
            return it;
        }

        Outfit ReadOutfit(ByteReader r)
        {
            var o = new Outfit { LookType = r.U16() };
            if (o.LookType != 0)
            {
                o.Head = r.U8(); o.Body = r.U8(); o.Legs = r.U8(); o.Feet = r.U8(); o.Addons = r.U8();
            }
            else o.LookTypeEx = r.U16();
            o.Mount = r.U16();
            if (Identity.Markers)
            {
                o.Wings = r.U16();
                o.Aura = r.U16();
                o.Shader = r.Str();
            }
            return o;
        }

        Creature ReadCreature(ByteReader r, ushort kind)
        {
            Creature c;
            if (kind == 0x63)
            {
                c = Find(r.U32());
                byte d = r.U8();
                r.U8();
                if (c != null) c.Direction = (Dir)Math.Min(7, (int)d);
                return c ?? new Creature();
            }
            if (kind == 0x61)
            {
                uint remove = r.U32();
                uint id = r.U32();
                if (remove != 0 && remove != id && W.Creatures.TryGetValue(remove, out var gone))
                {
                    W.RemoveCreature(gone);
                    W.Creatures.Remove(remove);
                }
                if (!W.Creatures.TryGetValue(id, out c))
                {
                    c = new Creature { Id = id };
                    W.Creatures[id] = c;
                }
                else W.RemoveCreature(c);   // a refresh (src-patch 0083) puts it back where the message says
                c.Type = r.U8();
                c.Name = r.Str();
            }
            else
            {
                uint id = r.U32();
                if (!W.Creatures.TryGetValue(id, out c))
                {
                    c = new Creature { Id = id };   // known to the server, unknown here: keep going
                    W.Creatures[id] = c;
                }
                else W.RemoveCreature(c);
            }
            c.HealthPercent = Math.Min(100, (int)r.U8());
            c.Direction = (Dir)Math.Min(7, (int)r.U8());
            c.Outfit = ReadOutfit(r);
            c.LightLevel = r.U8(); c.LightColor = r.U8();
            c.Speed = r.U16();
            c.Skull = r.U8();
            c.Shield = r.U8();
            if (kind == 0x61) c.Emblem = r.U8();
            c.Type = r.U8();
            c.Icon = r.U8();
            r.U8();    // mark
            r.U16();   // helpers
            c.Walkthrough = r.U8() == 0;
            c.WalkStart = -1;
            return c;
        }

        void FloorUp(ByteReader r)
        {
            var c = W.Center;
            int z = c.Z - 1;
            var nc = new Pos(c.X + 1, c.Y + 1, z);
            if (z == 7)
            {
                int skip = 0;
                if (!Identity.Markers)   // an OTCv8 client got these floors as 0x4B messages just before
                    for (int i = 5; i >= 0; i--)
                        skip = FloorDescription(r, c.X - World.RangeLeft, c.Y - World.RangeTop, i, World.ViewW, World.ViewH, 8 - i, skip);
            }
            else if (z > 7)
                FloorDescription(r, c.X - World.RangeLeft, c.Y - World.RangeTop, z - 2, World.ViewW, World.ViewH, 3, 0);
            SetCenter(nc);
        }

        void FloorDown(ByteReader r)
        {
            var c = W.Center;
            int z = c.Z + 1;
            var nc = new Pos(c.X - 1, c.Y - 1, z);
            if (z == 8)
            {
                int skip = 0, j = -1;
                if (!Identity.Markers)
                    for (int i = z; i <= z + 2; i++, j--)
                        skip = FloorDescription(r, c.X - World.RangeLeft, c.Y - World.RangeTop, i, World.ViewW, World.ViewH, j, skip);
            }
            else if (z > 8 && z < 14)
                FloorDescription(r, c.X - World.RangeLeft, c.Y - World.RangeTop, z + 2, World.ViewW, World.ViewH, -3, 0);
            SetCenter(nc);
        }
    }

    public struct SkillValue { public int Level, Base, Percent; }

    /// <summary>An open container (0x6E). Items is the visible page, FirstIndex its first slot.</summary>
    public sealed class Container
    {
        public byte Id;
        public ushort ItemId;
        public string Name = "";
        public int Capacity, Size, FirstIndex;
        public bool HasParent;
        public readonly List<Item> Items = new List<Item>();
    }

    /// <summary>A logged-in game connection: login handshake, client guard, pings, walking. Poll() from one thread.</summary>
    public sealed partial class GameSession : IDisposable
    {
        public sealed class Options
        {
            public string Host, Account, Password, SessionKey, Character;
            public int Port = 7172;
            public string RsaModulus = Protocol.OpenRsaModulus;
            public byte[] GuardKey = ClientGuard.DevKey;
            public ushort Build = 30;
            /// <summary>Extended (default): OS 21, markers u16 0, plain 10.98 wire, extended opcodes on. Chaos: the markers of the
            /// main client too (feature list, wings / aura / shader, 0x4B floors, item attributes). See ClientIdentity.</summary>
            public ClientIdentity Identity = ClientIdentity.Extended;
        }

        readonly World world;
        readonly Options opt;
        readonly GameParser parser;
        readonly Stopwatch clock = Stopwatch.StartNew();
        Connection conn;
        uint[] key;
        bool started;
        public bool GuardAnswered { get; private set; }
        double stepSent = -1;
        public string Closed;
        public event Action<string> Log = delegate { };
        public event Action<string, string, byte> Chat = delegate { };
        public int Packets, Bytes;
        /// <summary>Extended opcodes: modules register with Ext.On(opcode, handler) and send with Ext.Send(opcode, action, data).</summary>
        public readonly ExtOpcodes Ext = new ExtOpcodes();
        /// <summary>The spell list (opcode 219) and the spell cooldowns.</summary>
        public readonly SpellBook Spells;
        /// <summary>The party frames (opcode 235) and the party packets.</summary>
        public readonly PartyFrames Party;
        /// <summary>The HUD models (toasts, buff bar, cast bar, shield, chi, monster bar, anti-bot, options): Core/Hud.cs.</summary>
        public readonly HudState Hud;
        int hudAskedLevel;
        bool featuresLogged, spellsAsked, partyOpened, progressStarted;
        /// <summary>The progression windows' state: passive tree, skill stats, goals, hunt tracker, rift HUD, info pages, menu unlocks.</summary>
        public readonly Progression Progress;
        double enteredAt = -1;

        public GameSession(World w, Options o)
        {
            world = w;
            opt = o;
            parser = new GameParser(w) { Clock = () => Now, Identity = o.Identity ?? ClientIdentity.Extended };
            Ext.Transmit = payload => conn?.Send(payload);
            Ext.Log = m => Log(m);
            Spells = new SpellBook(Ext) { Clock = () => Now, Say = Say, LevelNow = () => parser.Level, MagicLevelNow = () => parser.MagicLevel };
            Party = new PartyFrames(Ext) { Clock = () => Now, Packet = payload => conn?.Send(payload) };
            Hud = new HudState(Ext, () => Now, () => world.PlayerVocation);
            Progress = new Progression(Ext, () => Now);
            parser.SpellCooldown = (id, ms) => Spells.OnSpellCooldown(id, ms);
            parser.GroupCooldown = (g, ms) => Spells.OnGroupCooldown(g, ms);
            parser.ExtendedOpcode = OnExtended;
            parser.Text = t => Log(t);
            parser.Chat = (who, text, type) => { Chat(who, text, type); if (who.Length == 0) Party.OnServerText(text); };
            parser.Disconnected = reason => Closed = reason;
            Ext.On(NpcTradeState.OpcodeCurrency, m => parser.Trade.ReceiveCurrency(NpcTradeState.ParseCurrency(m), Now));
            parser.Pinged = () => conn?.Send(new byte[] { 0x1E });
            InitItems();
            InitCollect();
            parser.WalkCancelled = _ => stepSent = -1;
            parser.PlayerMoved = _ => stepSent = -1;
        }

        public double Now => clock.Elapsed.TotalMilliseconds;
        public GameParser Parser => parser;
        public string Stats => "hp " + parser.Health + "/" + parser.MaxHealth + "  mana " + parser.Mana + "/" + parser.MaxMana +
                               "  level " + parser.Level + "  " + Packets + " packets";

        public async void Start()
        {
            try
            {
                conn = await Connection.Open(opt.Host, opt.Port);
                await Task.Run(() =>
                {
                    byte[] first = conn.ReadBody();
                    if (first == null) throw new ProtocolException("the game server closed the connection");
                    var r = new ByteReader(first);
                    r.U32();   // adler32
                    r.U16();   // inner length
                    if (r.U8() != 0x1F) throw new ProtocolException("no login challenge from the game server");
                    uint ts = r.U32();
                    byte rnd = r.U8();
                    key = Protocol.NewXteaKey();
                    conn.Key = key;
                    conn.SendRaw(Protocol.GameLoginPacket(new Rsa(opt.RsaModulus), key, opt.SessionKey, opt.Character,
                                                          ClientGuard.Identifier(opt.Build), ts, rnd, opt.Identity));
                });
                conn.StartReading();
                started = true;
                Log("Entering the game as " + opt.Character + "...");
            }
            catch (Exception e)
            {
                Closed = "Could not enter the game: " + e.Message;
            }
        }

        void OnExtended(byte op, string data)
        {
            if (op == ClientGuard.ChallengeOpcode)
            {
                byte[] nonce = ClientGuard.ParseChallenge(data);
                if (nonce == null) return;
                GuardAnswered = true;
                string account = (opt.SessionKey ?? opt.Account ?? "").Split('\n')[0];
                SendExtended(ClientGuard.ChallengeOpcode, ClientGuard.Answer(opt.GuardKey, nonce, account, opt.Character, opt.Build));
                SendExtended(ClientGuard.HelloOpcode, ClientGuard.Hello(opt.Build));
                Log(opt.GuardKey == ClientGuard.DevKey ? "Client guard answered with the development key." : "Client guard answered.");
                return;
            }
            Ext.Receive(op, data);
        }

        public void SendExtended(byte op, string data)
        {
            conn?.Send(new ByteWriter().U8(0x32).U8(op).Str(data).ToArray());
        }

        /// <summary>Reads what arrived and applies it to the World. Call once per frame.</summary>
        public void Poll()
        {
            if (!started || conn == null) return;
            while (conn.Received.TryDequeue(out var body))
            {
                Packets++;
                Bytes += body.Length + 2;
                try
                {
                    parser.Parse(Protocol.Decrypt(body, key));
                }
                catch (ProtocolException e)
                {
                    // one message the prototype cannot read: the rest of that packet is lost, the next ones go on
                    Log("parse: " + e.Message);
                }
                if (Closed != null) return;
            }
            if (parser.Features.Announced && !featuresLogged)
            {
                featuresLogged = true;
                Log("Server features: " + string.Join(",", parser.Features.All.OrderBy(f => f)));
            }
            if (parser.LoggedIn && enteredAt < 0) enteredAt = Now;
            ChatPoll();
            ItemsPoll();
            CollectPoll();
            // the spell list is fetched a few seconds after the login (the main client's prefetch), so the first window is instant
            if (!spellsAsked && enteredAt >= 0 && Now - enteredAt > 3000) { spellsAsked = true; Spells.Open(true); }
            // the party frames: watch a moment after the login (the main client waits 400 ms)
            if (!partyOpened && enteredAt >= 0 && Now - enteredAt > 600) { partyOpened = true; Party.Open(); }
            // the HUD: the options and the language go out a moment after the login; the timers run every frame
            if (enteredAt >= 0 && Now - enteredAt > 800) Hud.Hello(Loc.Language);
            if (Hud.Options.LevelChanged(parser.Level) && parser.Level != hudAskedLevel) { hudAskedLevel = parser.Level; Hud.Options.SendHello(Loc.Language); }
            Hud.Tick(Now);
            // the progression requests (menu unlocks hello, combat stats, rift query, goal tracker): the main client waits 1.8 s
            if (!progressStarted && enteredAt >= 0 && Now - enteredAt > 1800) { progressStarted = true; Progress.Start(); }
            if (conn.Closed && Closed == null) Closed = conn.Error ?? "The server closed the connection.";
            if (stepSent >= 0 && Now - stepSent > 1500) stepSent = -1;   // no answer to a step: let the next one go
        }

        /// <summary>A step can go when the last one was answered and the walk animation is nearly over.</summary>
        public bool CanWalk
        {
            get
            {
                if (!parser.LoggedIn || stepSent >= 0) return false;
                var me = world.Player;
                if (me == null) return false;
                return me.WalkStart < 0 || Now - me.WalkStart >= me.WalkMs - 30;
            }
        }

        static readonly byte[] WalkOps = { 0x65, 0x66, 0x67, 0x68, 0x6A, 0x6B, 0x6C, 0x6D };

        public void Walk(Dir d)
        {
            if (!CanWalk) return;
            stepSent = Now;
            conn.Send(new[] { WalkOps[(int)d] });
        }

        public void Turn(Dir d)
        {
            if ((int)d < 4) conn?.Send(new[] { (byte)(0x6F + (int)d) });
        }

        /// <summary>Says a line on the default channel (0x96, talk type 1).</summary>
        public void Say(string text)
        {
            if (string.IsNullOrWhiteSpace(text) || conn == null) return;
            if (text.Length > 255) text = text.Substring(0, 255);
            conn.Send(Protocol.SayPacket(text));
        }

        /// <summary>Words to an NPC: the default channel to greet it or when no conversation runs, else the NPC channel (talk type 12).
        /// The line also goes into the NPC log (the server does not echo it).</summary>
        public void SayToNpc(string text)
        {
            if (string.IsNullOrWhiteSpace(text) || conn == null) return;
            text = text.Trim();
            if (text.Length > 255) text = text.Substring(0, 255);
            var talk = parser.NpcTalk;
            bool channel = talk.ToNpcChannel(text, Now);
            talk.FromPlayer(world.Player?.Name ?? opt.Character ?? "", text, Now);
            conn.Send(channel ? NpcPackets.SayToNpc(text) : Protocol.SayPacket(text));
        }

        /// <summary>Buys from the open shop (0x7A). False when the rules forbid it (money, capacity, amount).</summary>
        public bool NpcBuy(ShopItem it, int amount, bool ignoreCap, bool inBackpacks = false)
        {
            byte[] p = parser.Trade.BuyRequest(it, amount, parser.FreeCap, ignoreCap, inBackpacks);
            if (p == null || conn == null) return false;
            conn.Send(p);
            return true;
        }

        /// <summary>Sells to the open shop (0x7B).</summary>
        public bool NpcSell(ShopItem it, int amount, bool ignoreEquipped = true)
        {
            byte[] p = parser.Trade.SellRequest(it, amount, ignoreEquipped);
            if (p == null || conn == null) return false;
            conn.Send(p);
            return true;
        }

        /// <summary>Looks at a shop row (0x79).</summary>
        public void NpcLook(ShopItem it) { if (it != null) conn?.Send(NpcPackets.Look(it.Id, it.SubType)); }

        /// <summary>Closes the shop (0x7C).</summary>
        public void NpcClose()
        {
            if (parser.Trade.Open) conn?.Send(NpcPackets.Close());
            parser.Trade.Close();
        }

        /// <summary>Inventory slot position (0xFFFF, slot, 0).</summary>
        public static Pos InventoryPos(int slot) => new Pos(0xFFFF, slot, 0);
        /// <summary>Container slot position (0xFFFF, 0x40 | cid, slot).</summary>
        public static Pos ContainerPos(int cid, int slot) => new Pos(0xFFFF, 0x40 | cid, slot);

        public void UseItem(Pos p, ushort id, byte stackPos, byte index = 0) => conn?.Send(Protocol.UseItemPacket(p, id, stackPos, index));
        public void CloseContainer(byte cid) => conn?.Send(Protocol.CloseContainerPacket(cid));
        public void UpContainer(byte cid) => conn?.Send(Protocol.UpContainerPacket(cid));
        public void MoveItem(Pos from, ushort id, byte stackPos, Pos to, byte count) => conn?.Send(Protocol.MoveItemPacket(from, id, stackPos, to, count));
        uint attackSeq;
        /// <summary>The creature we attack, 0 when none or when it left the view.</summary>
        public uint AttackTarget => parser.AttackTarget != 0 && world.Creatures.ContainsKey(parser.AttackTarget) ? parser.AttackTarget : 0;

        /// <summary>Attacks a creature (0xA1).</summary>
        public void Attack(uint id)
        {
            if (id == 0) { CancelAttack(); return; }
            parser.AttackTarget = id;
            conn?.Send(Protocol.AttackPacket(0xA1, id, ++attackSeq));
        }

        /// <summary>Follows a creature (0xA2). The attack, if any, ends.</summary>
        public void Follow(uint id)
        {
            if (id == 0) { CancelAttack(); return; }
            parser.AttackTarget = 0;
            conn?.Send(Protocol.AttackPacket(0xA2, id, ++attackSeq));
        }

        /// <summary>Stops attacking and following (0xA1 with id 0).</summary>
        public void CancelAttack()
        {
            parser.AttackTarget = 0;
            conn?.Send(Protocol.AttackPacket(0xA1, 0, ++attackSeq));
        }

        public void Logout()
        {
            try { conn?.Send(new byte[] { 0x14 }); } catch (Exception) { }
        }

        public void Dispose() { conn?.Dispose(); }
    }
}
