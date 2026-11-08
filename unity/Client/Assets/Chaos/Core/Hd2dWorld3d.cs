// World3d (Unity only): the real game maps drawn with 3D models instead of sprites. Pure C#, no Unity types, so it builds in
// Core.Tests. The Unity side (Unity/Hd2dRuins3d.cs, WorldMode) loads the models and keeps them in a pool; this file decides what
// stands where and when the 3D layer has to be rebuilt.
//
// It is the Ruins3d plan (Core/Hd2dRuins.cs: walls, pillars, torches, stone floors, props) with one more role set that works
// from the pixels of the sprites (Core/Hd2dTerrain.cs), because a real map has no demo tileset to know by id.
// Role of a sprite piece (RoleOf), the first rule that fits:
//   ground, class Stone or Wood           -> Floor    the ruins floor piece
//   ground, Grass Dirt Sand Snow Dark     -> Terrain  a flat tile, tinted from the sprite's mean colour, darkened
//   ground, Water                         -> Water    a dark glossy plane a little below the floor
//   ground, Lava                          -> Lava     an emissive orange plane
//   ground, Unknown                       -> None     the sprite stays
//   ground border                         -> Border   dropped (the tile is enough)
//   decal, creature, flat                 -> None     sprites
//   light source standing upright         -> Light    as the ruins
//   on-bottom blocking                    -> Wall     as the ruins (a green one, a hedge, stays a sprite)
//   upright and not carried (no pickupable, container or stackable item), blocking, not on-bottom, no light:
//       green (share of green pixels >= 0.3) and 2 cells high or more    -> Tree (live: CommonTree, PineTree)
//       2 x 2 or larger, brown, not green                                -> Tree (dead: CommonTree_Dead)
//       green, one cell high                                             -> Bush (Bush, BushBerries)
//       grey (share of grey pixels >= 0.6), 1 x 1                        -> Rock (Rock, Rock_Moss)
//       else                                                             -> Pillar (a column, as the ruins)
//   not blocking, green, one cell high    -> Bush
//   everything else (items, doors, stairs, signs, on-top things) -> None: a sprite billboard as before.
// A big grey 2 x 2 thing stays a column (the real pair draws its pillars 2 x 2); a large thing that is neither green nor brown stays
// a column too. Nature roles need the nature models (rules.Nature); without them the pieces stay sprites.
//
// On top: Grass tiles get a sparse scatter (ScatterPercent of the tiles, by a hash of the tile: Grass, Grass_Short, Plant, Rock),
// Dirt tiles Rock only; never on a tile that holds anything. Creatures are not part of the plan (so a walking monster does not
// rebuild the scene); the ruins props therefore ignore them.
//
// Units, tiles and yaw as Hd2dRuins: tile (tx, ty) is x = tx - origin.X + 0.5, z = -(ty - origin.Y) - 0.5; one tile is one unit.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    /// <summary>The rules of one World3d: which classifier reads the sprites and whether the nature models exist.</summary>
    public sealed class World3dRules
    {
        public readonly SpriteClassifier Classifier;
        public bool Nature = true;
        /// <summary>The Hd2dView.Skip hook: one delegate for the life of the rules (no allocation per frame).</summary>
        public readonly Func<Hd2dPiece, bool> ReplacesFn;
        public readonly Func<Hd2dPiece, RuinsRole> RoleFn;

        public World3dRules(SpriteClassifier classifier)
        {
            Classifier = classifier;
            RoleFn = p => Hd2dWorld3d.RoleOf(p, Classifier, Nature);
            ReplacesFn = p => RoleFn(p) != RuinsRole.None;
        }

        public RuinsRole RoleOf(Hd2dPiece p) => RoleFn(p);
    }

    public static class Hd2dWorld3d
    {
        /// <summary>Share of the tiles of a grass or dirt field that get a model (one tile in about seven).</summary>
        public const int ScatterPercent = 15;
        public const float GreenShare = 0.3f, GreyShare = 0.6f, BrownShare = 0.35f;

        public static readonly string[] LiveTrees = { "CommonTree_1", "CommonTree_2", "CommonTree_3", "PineTree_1", "PineTree_2", "PineTree_3" };
        public static readonly string[] DeadTrees = { "CommonTree_Dead_3", "CommonTree_Dead_4", "CommonTree_Dead_5" };
        public static readonly string[] Bushes = { "Bush_1", "Bush_2", "BushBerries_1", "BushBerries_2" };
        public static readonly string[] Rocks = { "Rock_1", "Rock_2", "Rock_3", "Rock_4", "Rock_5", "Rock_6", "Rock_7", "Rock_Moss_1", "Rock_Moss_2", "Rock_Moss_3" };
        public static readonly string[] Grasses = { "Grass", "Grass_Short" };
        public static readonly string[] Plants = { "Plant_1", "Plant_2", "Plant_3" };

        /// <summary>The generated pieces: a terrain tile (a box), a water plane, a lava plane.</summary>
        public const string TilePiece = "@Tile", WaterPiece = "@Water", LavaPiece = "@Lava";

        /// <summary>The pieces the nature part needs: if one is missing the nature roles stay sprites.</summary>
        public static readonly string[] NatureRequired = { "CommonTree_1", "Bush_1", "Rock_1", "Grass" };

        static readonly HashSet<string> natureNames = BuildNatureNames();

        static HashSet<string> BuildNatureNames()
        {
            var h = new HashSet<string>();
            foreach (var l in new[] { LiveTrees, DeadTrees, Bushes, Rocks, Grasses, Plants }) foreach (var n in l) h.Add(n);
            return h;
        }

        /// <summary>Every nature model name (the files of Resources/Nature3d).</summary>
        public static IEnumerable<string> NaturePieces => natureNames;

        public static bool IsNature(string piece) => natureNames.Contains(piece);

        /// <summary>Height of each nature model in its own units (measured on the OBJ files), to scale it to a size in tiles.</summary>
        static readonly Dictionary<string, float> heights = new Dictionary<string, float>
        {
            { "CommonTree_1", 2.48f }, { "CommonTree_2", 3.12f }, { "CommonTree_3", 3.45f },
            { "PineTree_1", 2.7f }, { "PineTree_2", 3.57f }, { "PineTree_3", 3.31f },
            { "CommonTree_Dead_3", 3.0f }, { "CommonTree_Dead_4", 2.37f }, { "CommonTree_Dead_5", 2.3f },
            { "Bush_1", 1.25f }, { "Bush_2", 1.11f }, { "BushBerries_1", 1.27f }, { "BushBerries_2", 1.13f },
            { "Grass", 1.02f }, { "Grass_Short", 0.41f }, { "Plant_1", 0.51f }, { "Plant_2", 1.77f }, { "Plant_3", 0.94f },
        };

        public static float ModelHeight(string piece) => heights.TryGetValue(piece, out var h) ? h : 1f;

        /// <summary>Height in tiles of a tree standing for a sprite `cells` cells high.</summary>
        public static float TreeHeight(int cells) => Math.Min(4.6f, 0.9f + 0.85f * Math.Max(1, cells));

        public static RuinsRole RoleOf(Hd2dPiece p, SpriteClassifier cls, bool nature)
        {
            if (p == null || p.Creature != null || p.Type == null) return RuinsRole.None;
            var t = p.Type;
            if (p.Kind == Hd2dKind.Floor)
            {
                switch (cls.Ground(t))
                {
                    case GroundClass.Stone: case GroundClass.Wood: return RuinsRole.Floor;
                    case GroundClass.Grass: case GroundClass.Dirt: case GroundClass.Sand: case GroundClass.Snow: case GroundClass.Dark: return RuinsRole.Terrain;
                    case GroundClass.Water: return RuinsRole.Water;
                    case GroundClass.Lava: return RuinsRole.Lava;
                    default: return RuinsRole.None;
                }
            }
            if (p.Kind == Hd2dKind.Border) return RuinsRole.Border;
            if (p.Flat) return RuinsRole.None;
            bool blocking = p.Kind == Hd2dKind.Billboard;
            if (!blocking && p.Kind != Hd2dKind.Object) return RuinsRole.None;
            if (t.LightLevel > 0) return RuinsRole.Light;
            var s = cls.Info(t).Stats;
            bool green = s.GreenShare >= GreenShare;
            if (t.OnBottom) return green && s.GreenShare >= 0.4f ? RuinsRole.None : RuinsRole.Wall;
            bool loose = !t.Pickupable && !t.Container && !t.Stackable;
            int w = Math.Max(1, p.Width), h = Math.Max(1, p.Height);
            RuinsRole nat = RuinsRole.None;
            if (loose)
            {
                if (blocking)
                {
                    if (green && h >= 2) nat = RuinsRole.Tree;
                    else if (!green && w >= 2 && h >= 2 && s.BrownShare >= BrownShare) nat = RuinsRole.Tree;
                    else if (green) nat = RuinsRole.Bush;
                    else if (w * h == 1 && s.GreyShare >= GreyShare) nat = RuinsRole.Rock;
                }
                else if (green && h == 1 && w <= 2) nat = RuinsRole.Bush;
            }
            if (nat != RuinsRole.None) return nature ? nat : RuinsRole.None;
            if (blocking && green && !nature) return RuinsRole.None;   // a tree without its model stays a sprite, not a column
            return blocking ? RuinsRole.Pillar : RuinsRole.None;
        }

        /// <summary>True for a tree sprite that is not green (the dead models).</summary>
        public static bool IsDeadTree(SpriteInfo i) => i.Stats.GreenShare < GreenShare;

        static void Sort(List<Hd2dPiece> l)
        {
            l.Sort((a, b) => a.Tile.X != b.Tile.X ? a.Tile.X.CompareTo(b.Tile.X) : a.Tile.Y.CompareTo(b.Tile.Y));
        }

        static string Pick(string[] list, int h) => list[h % list.Length];

        static float Jitter(int h, float lo, float hi) => lo + (hi - lo) * ((h % 1000) / 1000f);

        /// <summary>The 3D pieces of a layout. Deterministic: the same layout gives the same list. Creature pieces are ignored.</summary>
        public static List<RuinsPlacement> Plan(IEnumerable<Hd2dPiece> pieces, Pos origin, World3dRules rules)
        {
            var all = new List<Hd2dPiece>();
            foreach (var p in pieces) if (p.Creature == null) all.Add(p);
            var list = Hd2dRuins.Plan(all, origin, rules.RoleFn);

            var terrain = new Dictionary<long, Hd2dPiece>();
            var nature = new List<Hd2dPiece>();
            var busy = new HashSet<long>();
            foreach (var p in all)
            {
                var role = rules.RoleFn(p);
                switch (role)
                {
                    case RuinsRole.Terrain: case RuinsRole.Water: case RuinsRole.Lava: terrain[Hd2dRuins.Key(p.Tile.X, p.Tile.Y)] = p; break;
                    case RuinsRole.Floor: case RuinsRole.Border: break;
                    case RuinsRole.Tree: case RuinsRole.Bush: case RuinsRole.Rock: nature.Add(p); Hd2dRuins.Block(busy, p, 0); break;
                    default: Hd2dRuins.Block(busy, p, 0); break;
                }
            }
            var tiles = new List<Hd2dPiece>(terrain.Values);
            Sort(tiles);
            foreach (var p in tiles)
            {
                var role = rules.RoleFn(p);
                var info = rules.Classifier.Info(p.Type);
                int tx = p.Tile.X, ty = p.Tile.Y;
                list.Add(new RuinsPlacement
                {
                    Piece = role == RuinsRole.Water ? WaterPiece : role == RuinsRole.Lava ? LavaPiece : TilePiece,
                    Role = role, Ground = info.Class,
                    X = Hd2dRuins.TileX(origin, tx), Z = Hd2dRuins.TileZ(origin, ty), Scale = 1f,
                    Y = role == RuinsRole.Water ? Hd2dTerrain.WaterY : role == RuinsRole.Lava ? Hd2dTerrain.LavaY : Hd2dTerrain.TileTop,
                    TintR = info.Stats.R, TintG = info.Stats.G, TintB = info.Stats.B,
                });
            }
            if (rules.Nature)
            {
                foreach (var p in nature) AddNature(list, origin, p, rules);
                foreach (var p in tiles) AddScatter(list, origin, p, rules, busy);
            }
            return list;
        }

        static void AddNature(List<RuinsPlacement> list, Pos origin, Hd2dPiece p, World3dRules rules)
        {
            int tx = p.Tile.X, ty = p.Tile.Y;
            int h = Hd2dRuins.Hash(tx, ty, 31);
            var role = rules.RoleFn(p);
            string name; float scale;
            // the footprint of a W cells wide sprite is centred on its middle (the anchor cell is the east one)
            float x = p.Right - Math.Max(1, p.Width) / 2f, z = Hd2dRuins.TileZ(origin, ty);
            switch (role)
            {
                case RuinsRole.Tree:
                    name = IsDeadTree(rules.Classifier.Info(p.Type)) ? Pick(DeadTrees, h) : Pick(LiveTrees, h);
                    scale = TreeHeight(p.Height) / ModelHeight(name) * Jitter(h / 7, 0.92f, 1.08f);
                    break;
                case RuinsRole.Bush:
                    name = Pick(Bushes, h);
                    scale = 0.85f / ModelHeight(name) * Jitter(h / 7, 0.9f, 1.15f);
                    break;
                default:
                    name = Pick(Rocks, h);
                    scale = Jitter(h / 7, 0.85f, 1.2f);
                    break;
            }
            list.Add(new RuinsPlacement { Piece = name, Role = role, X = x, Y = 0f, Z = z, Yaw = h / 11 % 360, Scale = scale });
        }

        static void AddScatter(List<RuinsPlacement> list, Pos origin, Hd2dPiece p, World3dRules rules, HashSet<long> busy)
        {
            if (rules.RoleFn(p) != RuinsRole.Terrain) return;
            var cls = rules.Classifier.Info(p.Type).Class;
            if (cls != GroundClass.Grass && cls != GroundClass.Dirt) return;
            int tx = p.Tile.X, ty = p.Tile.Y;
            if (busy.Contains(Hd2dRuins.Key(tx, ty))) return;
            if (Hd2dRuins.Hash(tx, ty, 21) % 100 >= ScatterPercent) return;
            int h = Hd2dRuins.Hash(tx, ty, 22);
            int r = h % 100, v = h / 100;
            string name; RuinsRole role = RuinsRole.Scatter; float scale;
            if (cls == GroundClass.Grass && r < 28) { name = "Grass"; scale = 0.6f; }
            else if (cls == GroundClass.Grass && r < 56) { name = "Grass_Short"; scale = 0.8f; }
            else if (cls == GroundClass.Grass && r < 82) { name = Pick(Plants, v); scale = 0.7f; }
            else { name = Pick(Rocks, v); role = RuinsRole.Rock; scale = 0.9f; }
            scale *= Jitter(h / 13, 0.85f, 1.15f);
            float ox = (Jitter(h / 17, 0f, 1f) - 0.5f) * 0.5f, oz = (Jitter(h / 19, 0f, 1f) - 0.5f) * 0.5f;
            list.Add(new RuinsPlacement { Piece = name, Role = role, X = Hd2dRuins.TileX(origin, tx) + ox, Y = Hd2dTerrain.TileTop, Z = Hd2dRuins.TileZ(origin, ty) + oz, Yaw = h / 23 % 360, Scale = scale });
        }

        // ---- when to rebuild ---------------------------------------------------------------------------------------------

        /// <summary>A cheap hash of what the plan reads: the view window around the centre, and per tile its position and the ids of
        /// its items (creatures are not read). No allocation. The 3D layer rebuilds only when it changes; walking one tile changes it
        /// (the window moves), standing still with a monster passing by does not.</summary>
        public static int ViewHash(World w)
        {
            var c = w.Center;
            unchecked
            {
                int h = (int)2166136261u;
                h = (h ^ c.X) * 16777619; h = (h ^ c.Y) * 16777619; h = (h ^ c.Z) * 16777619;
                for (int y = c.Y - w.Range.Top; y <= c.Y + w.Range.Bottom; y++)
                    for (int x = c.X - w.Range.Left; x <= c.X + w.Range.Right; x++)
                    {
                        if (!w.Tiles.TryGetValue(new Pos(x, y, c.Z), out var tile)) continue;
                        h = (h ^ (x * 73856093 ^ y * 19349663)) * 16777619;
                        var things = tile.Things;
                        for (int i = 0; i < things.Count; i++)
                            if (!things[i].IsCreature && things[i].Item != null) h = (h ^ things[i].Item.Id) * 16777619;
                    }
                return h;
            }
        }
    }
}
