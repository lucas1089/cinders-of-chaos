// The client's picture of the world: tiles with their stacks, the creatures, the player's position.
// Filled by GameSession from the server's packets; drawn by the Unity side.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public struct Pos : System.IEquatable<Pos>
    {
        public int X, Y, Z;
        public Pos(int x, int y, int z) { X = x; Y = y; Z = z; }
        public override string ToString() => X + "," + Y + "," + Z;
        public override int GetHashCode() => (X * 73856093) ^ (Y * 19349663) ^ (Z * 83492791);
        public override bool Equals(object o) => o is Pos p && p.X == X && p.Y == Y && p.Z == Z;
        public bool Equals(Pos p) => p.X == X && p.Y == Y && p.Z == Z;   // no boxing in a Dictionary<Pos, T> lookup
        public static bool operator ==(Pos a, Pos b) => a.X == b.X && a.Y == b.Y && a.Z == b.Z;
        public static bool operator !=(Pos a, Pos b) => !(a == b);
        public Pos Offset(int dx, int dy, int dz = 0) => new Pos(X + dx, Y + dy, Z + dz);
    }

    public enum Dir { North = 0, East = 1, South = 2, West = 3, NorthEast = 4, SouthEast = 5, SouthWest = 6, NorthWest = 7 }

    public sealed class Item
    {
        public int Id;          // client id
        public int Count;       // count or fluid subtype; 0 when the type has none
        public ThingType Type;  // null when the dat has no such item
        /// <summary>The custom attributes of an Identity.Chaos connection (ChaosItemAttr keys: 1 rarity, 2 item level, 3 locked,
        /// 4 unique, 5 sockets, 6 per-item id, 7 version); null when the item carries none.</summary>
        public Dictionary<ushort, ulong> Attrs;
        public ulong Attr(ushort key) => Attrs != null && Attrs.TryGetValue(key, out var v) ? v : 0;
    }

    public sealed class Creature
    {
        public uint Id;
        public string Name = "";
        public byte Type;       // 0 player, 1 monster, 2 npc, 3 own summon, 4 other summon
        public int Vocation;    // the class (vocation id) when known: the local player from the login, the offline demo's cast; 0 = unknown (the protocol does not send it)
        public int HealthPercent = 100;
        public Dir Direction = Dir.South;
        public Outfit Outfit = new Outfit();
        public int Speed;
        public byte Skull, Shield, Emblem, Icon;
        public int LightLevel, LightColor;
        public bool Walkthrough;
        public Pos Position;
        // walking (the Unity side animates from WalkFrom to Position over WalkMs)
        public Pos WalkFrom;
        public double WalkStart = -1, WalkMs;
        /// <summary>The local player's steps sent and not yet confirmed (Core/SmoothWalk.cs), drawn ahead of the server's answer; null when none.</summary>
        public System.Collections.Generic.List<PredStep> Pred;
        /// <summary>The glide before the one in WalkFrom / WalkStart, kept while the next one waits for it to end (it ends on WalkFrom); PrevStart -1 when none.</summary>
        public Pos PrevFrom;
        public double PrevStart = -1, PrevMs;
    }

    /// <summary>One stack entry of a tile: an item or a creature.</summary>
    public struct Thing
    {
        public Item Item;
        public Creature Creature;
        public bool IsCreature => Creature != null;
    }

    public sealed class Tile
    {
        public readonly Pos Pos;
        public readonly List<Thing> Things = new List<Thing>();
        public Tile(Pos p) { Pos = p; }
    }

    /// <summary>The aware range as the server's 0x42 gives it (width and height, 17 x 13 by default) and the tile counts the map messages use
    /// (the engine's AwareRange of protocolgame.h, as server/tools/cast_relay.py reads it): a full map is Horizontal x Vertical tiles from
    /// (x - Left, y - Top); a step reads a row or column at Bottom or Right. Only odd sizes make a consistent window (left + right + 1 =
    /// horizontal); the main client asks for 29 x 21 (game_chaosview).</summary>
    public struct AwareRange
    {
        public readonly int Width, Height;
        public AwareRange(int width, int height) { Width = width; Height = height; }

        public static readonly AwareRange Default = new AwareRange(17, 13);
        /// <summary>The server's limits (Map::maxClientViewportX * 2 + 1, Y: game_chaosview AWARE_WIDTH and AWARE_HEIGHT).</summary>
        public const int MaxWidth = 29, MaxHeight = 21;

        public int Left => Width / 2;
        public int Right => 1 + Width / 2;
        public int Top => Height / 2;
        public int Bottom => 1 + Height / 2;
        public int Horizontal => Width + 1;
        public int Vertical => Height + 1;

        /// <summary>True for sizes the map messages can be read with: odd and at least 1.</summary>
        public static bool Valid(int width, int height) => width >= 1 && height >= 1 && width % 2 == 1 && height % 2 == 1;

        /// <summary>A request the server accepts: odd, 3 up to the limits.</summary>
        public static AwareRange Clamp(int width, int height)
        {
            width = Math.Max(3, Math.Min(MaxWidth, width));
            height = Math.Max(3, Math.Min(MaxHeight, height));
            if (width % 2 == 0) width--;
            if (height % 2 == 0) height--;
            return new AwareRange(width, height);
        }

        /// <summary>"29x21" (or "29 x 21") to a request; false for anything else. Used for the setting that asks the server for a larger area.</summary>
        public static bool TryParse(string text, out AwareRange range)
        {
            range = Default;
            if (string.IsNullOrWhiteSpace(text)) return false;
            var parts = text.ToLowerInvariant().Replace(" ", "").Split('x');
            if (parts.Length != 2 || !int.TryParse(parts[0], out int w) || !int.TryParse(parts[1], out int h) || w < 1 || h < 1) return false;
            range = Clamp(w, h);
            return true;
        }

        public override string ToString() => Width + "x" + Height;
    }

    public sealed class World
    {
        // the 10.98 view: 18 x 14 tiles around the player (8 left, 9 right, 6 up, 7 down). These are the DEFAULT range and the area the views draw
        // (15 x 11 of it); what the parser reads is `Range`, which the server's 0x42 changes (AwareRange).
        public const int RangeLeft = 8, RangeRight = 9, RangeTop = 6, RangeBottom = 7;
        public const int ViewW = RangeLeft + RangeRight + 1, ViewH = RangeTop + RangeBottom + 1;

        /// <summary>The area of tiles the server describes round the player: the default 17 x 13 (18 x 14 tiles), or what the last 0x42 said.</summary>
        public AwareRange Range = AwareRange.Default;

        public readonly DatFile Dat;
        public readonly Dictionary<Pos, Tile> Tiles = new Dictionary<Pos, Tile>();
        public readonly Dictionary<uint, Creature> Creatures = new Dictionary<uint, Creature>();
        public uint PlayerId;
        public int PlayerVocation;   // the local character's vocation id from the character list (0 = unknown)
        public Pos Center;
        public int WorldLight = 255, WorldLightColor = 215;
        /// <summary>Combat effects the parser read (magic effects, missiles, damage numbers): drained by the front-art live view (Core/FrontFx.cs). Off until a consumer sets Enabled.</summary>
        public readonly FxFeed Fx = new FxFeed();

        public World(DatFile dat) { Dat = dat; }

        public Creature Player { get { Creatures.TryGetValue(PlayerId, out var c); return c; } }

        public Tile Get(Pos p) { Tiles.TryGetValue(p, out var t); return t; }

        public Tile GetOrMake(Pos p)
        {
            if (!Tiles.TryGetValue(p, out var t)) { t = new Tile(p); Tiles[p] = t; }
            return t;
        }

        public void Clean(Pos p)
        {
            Tiles.Remove(p);
        }

        public Item MakeItem(int id, int count)
        {
            return new Item { Id = id, Count = count, Type = Dat.Item(id) };
        }

        /// <summary>The order the stock client keeps a stack in: ground, bottom (borders, on-bottom), on-top, creatures, other items.</summary>
        public static int StackPriority(Thing th)
        {
            if (th.IsCreature) return 4;
            var t = th.Item.Type;
            if (t == null) return 5;
            if (t.Ground) return 0;
            if (t.GroundBorder) return 1;
            if (t.OnBottom) return 2;
            if (t.OnTop) return 3;
            return 5;
        }

        /// <summary>Adds a thing at `stackPos` (map description order), or with -1 where the stock client puts it:
        /// ground, borders, on-bottom and on-top items and creatures after their own kind, other items before theirs.</summary>
        public void AddThing(Pos p, Thing th, int stackPos = -1)
        {
            var t = GetOrMake(p);
            if (stackPos < 0 || stackPos > t.Things.Count)
            {
                int prio = StackPriority(th);
                bool append = prio <= 4;
                for (stackPos = 0; stackPos < t.Things.Count; stackPos++)
                {
                    int other = StackPriority(t.Things[stackPos]);
                    if (append ? other > prio : other >= prio) break;
                }
            }
            t.Things.Insert(stackPos, th);
            if (th.IsCreature) th.Creature.Position = p;
        }

        public Thing? ThingAt(Pos p, int stackPos)
        {
            var t = Get(p);
            if (t == null || stackPos < 0 || stackPos >= t.Things.Count) return null;
            return t.Things[stackPos];
        }

        public bool RemoveAt(Pos p, int stackPos)
        {
            var t = Get(p);
            if (t == null || stackPos < 0 || stackPos >= t.Things.Count) return false;
            t.Things.RemoveAt(stackPos);
            return true;
        }

        public void RemoveCreature(Creature c)
        {
            var t = Get(c.Position);
            if (t == null) return;
            for (int i = 0; i < t.Things.Count; i++)
                if (t.Things[i].Creature == c) { t.Things.RemoveAt(i); return; }
        }

        /// <summary>Drops the tiles outside the view of `center` (all floors), as the client forgets them.</summary>
        public void ForgetOutside(Pos center)
        {
            var gone = new List<Pos>();
            foreach (var p in Tiles.Keys)
            {
                int off = center.Z - p.Z;
                int dx = p.X - off - center.X, dy = p.Y - off - center.Y;
                if (dx < -Range.Left - 1 || dx > Range.Right + 1 || dy < -Range.Top - 1 || dy > Range.Bottom + 1) gone.Add(p);
            }
            foreach (var p in gone)
            {
                var tile = Tiles[p];
                foreach (var th in tile.Things) if (th.IsCreature && th.Creature.Id != PlayerId) th.Creature.Position = default;   // a creature left behind is off the map, not a ghost at its last tile
                Tiles.Remove(p);
            }
        }
    }
}
