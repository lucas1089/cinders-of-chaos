// Checks of World3d (Core/Hd2dTerrain.cs, Core/Hd2dWorld3d.cs, Hd2dDemo.Outdoor): the pixel classification of ground on synthetic RGBA
// blocks, the roles of upright things, the plan (tiles, water, nature, scatter), the rebuild hash and the outdoor demo's id pick.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class World3dTests
    {
        static bool Near(float a, float b, float eps = 1e-3f) => Math.Abs(a - b) <= eps;

        static int H(int x, int y, int s) { unchecked { int h = x * 73856093 ^ y * 19349663 ^ s * 83492791; h ^= h >> 13; h *= 0x5bd1e995; return (h ^ (h >> 15)) & 0x7fffffff; } }

        /// <summary>A 32 x 32 RGBA block of one colour with +-noise on each channel; `shape` (x, y) -> opaque, null for all opaque.</summary>
        static byte[] Block(int r, int g, int b, int noise = 10, int seed = 1, Func<int, int, bool> shape = null, Func<int, int, int> row = null)
        {
            var o = new byte[32 * 32 * 4];
            for (int y = 0; y < 32; y++)
                for (int x = 0; x < 32; x++)
                {
                    int i = (y * 32 + x) * 4;
                    int n = noise == 0 ? 0 : H(x, y, seed) % (2 * noise + 1) - noise;
                    int k = row != null ? row(x, y) : 0;
                    o[i] = Cl(r + n + k); o[i + 1] = Cl(g + n + k); o[i + 2] = Cl(b + n + k);
                    o[i + 3] = (byte)(shape == null || shape(x, y) ? 255 : 0);
                }
            return o;
        }

        static byte Cl(int v) => (byte)(v < 0 ? 0 : v > 255 ? 255 : v);

        static bool Disc(int x, int y) => (x - 16) * (x - 16) + (y - 16) * (y - 16) <= 144;

        // ---- a small dat -------------------------------------------------------------------------------------------------

        sealed class Art
        {
            public DatFile Dat = new DatFile { Items = new ThingType[400], Outfits = new ThingType[200], Effects = new ThingType[2], Missiles = new ThingType[2] };
            public readonly Dictionary<int, Func<int, byte[]>> Paint = new Dictionary<int, Func<int, byte[]>>();   // item id -> (sprite index) -> block
            public int Reads;

            public byte[] Sprite(uint id)
            {
                Reads++;
                int item = (int)(id / 100), idx = (int)(id % 100);
                return Paint.TryGetValue(item, out var f) ? f(idx) : null;
            }

            public ThingType Item(int id, int w, int h, int phases, Action<ThingType> flags, Func<int, byte[]> paint)
            {
                var g = new FrameGroup { Width = w, Height = h, Layers = 1, PatternX = 1, PatternY = 1, PatternZ = 1, Phases = phases, Sprites = new uint[w * h * phases] };
                for (int i = 0; i < g.Sprites.Length; i++) g.Sprites[i] = (uint)(id * 100 + i);
                var t = new ThingType { Category = ThingCategory.Item, Id = id, Groups = new[] { g } };
                flags?.Invoke(t);
                Dat.Items[id] = t;
                Paint[id] = paint;
                return t;
            }

            public void Outfit(int id)
            {
                var g = new FrameGroup { Width = 1, Height = 1, Layers = 1, PatternX = 4, PatternY = 1, PatternZ = 1, Phases = 1, Sprites = new uint[4] };
                Dat.Outfits[id] = new ThingType { Category = ThingCategory.Outfit, Id = id, Groups = new[] { g } };
            }
        }

        const int Grass = 200, Water = 201, Dirt = 202, Lava = 203, Stone = 204, Snow = 205, Sand = 206, Wood = 207, Tree = 208, Rock = 209, Bush = 210, DeadTree = 211,
                  NoisyGrass = 212, Pond2 = 213, Pillar = 214, Wall = 215, Potion = 216, Hedge = 217;

        static Art MakeArt()
        {
            var a = new Art();
            Action<ThingType> ground = t => t.Ground = true;
            Action<ThingType> block = t => t.NotWalkable = true;
            a.Item(Grass, 1, 1, 1, ground, i => Block(62, 112, 44, 8, 1));
            a.Item(NoisyGrass, 1, 1, 1, ground, i => Block(62, 112, 44, 60, 2));
            a.Item(Water, 1, 1, 4, ground, i => Block(28, 62, 128, 6, 3 + i));
            a.Item(Pond2, 1, 1, 2, ground, i => Block(28, 62, 128, 6, 3 + i));
            a.Item(Dirt, 1, 1, 1, ground, i => Block(126, 92, 58, 10, 4));
            a.Item(Lava, 1, 1, 3, t => { t.Ground = true; t.LightLevel = 4; }, i => Block(225, 95, 14, 18, 5 + i));
            a.Item(Stone, 1, 1, 1, ground, i => Block(122, 122, 128, 12, 6));
            a.Item(Snow, 1, 1, 1, ground, i => Block(236, 240, 246, 5, 7));
            a.Item(Sand, 1, 1, 1, ground, i => Block(218, 198, 132, 8, 8));
            a.Item(Wood, 1, 1, 1, ground, i => Block(152, 102, 56, 4, 9, null, (x, y) => y % 8 == 0 ? -50 : 0));
            // a tree: 2 cells high, green crown in the upper cell, trunk and some grass in the lower one
            a.Item(Tree, 1, 2, 1, block, i => i == 0 ? Block(40, 100, 36, 12, 10, Disc) : Block(60, 40, 28, 8, 11, (x, y) => x > 12 && x < 20));
            a.Item(DeadTree, 2, 2, 1, block, i => Block(112, 82, 52, 10, 12, (x, y) => (x + y) % 5 != 0));
            a.Item(Rock, 1, 1, 1, block, i => Block(128, 128, 134, 14, 13, Disc));
            a.Item(Bush, 1, 1, 1, block, i => Block(58, 120, 42, 12, 14, Disc));
            a.Item(Pillar, 2, 2, 1, block, i => Block(130, 130, 136, 10, 15));
            a.Item(Wall, 2, 2, 1, t => { t.OnBottom = true; t.NotWalkable = true; }, i => Block(120, 118, 126, 10, 16));
            a.Item(Potion, 1, 1, 1, t => t.Pickupable = true, i => Block(50, 140, 50, 10, 17, Disc));
            a.Item(Hedge, 1, 1, 1, t => { t.OnBottom = true; t.NotWalkable = true; }, i => Block(48, 110, 40, 10, 18));
            a.Outfit(128); a.Outfit(129);
            return a;
        }

        static void AddItem(World w, int x, int y, int id) { w.AddThing(new Pos(x, y, 7), new Thing { Item = w.MakeItem(id, 0) }); }

        static Hd2dPiece PieceOf(Art a, int id, int w = 0, int h = 0)
        {
            var t = a.Dat.Items[id];
            return new Hd2dPiece { Type = t, Kind = Hd2d.Classify(t), Width = w > 0 ? w : t.Idle.Width, Height = h > 0 ? h : t.Idle.Height };
        }

        public static void Run(Action<bool, string> check)
        {
            // ---- ground classes on synthetic blocks ----
            Func<byte[], bool, bool, GroundClass> cls = (px, anim, lit) => Hd2dTerrain.Classify(Hd2dTerrain.Stats(px), anim, lit);
            check(cls(Block(62, 112, 44), false, false) == GroundClass.Grass, "world3d: green is Grass");
            check(cls(Block(28, 62, 128), true, false) == GroundClass.Water && cls(Block(28, 62, 128), false, false) == GroundClass.Water, "world3d: blue is Water, animated or not");
            check(cls(Block(80, 100, 150, 6), true, false) == GroundClass.Water && cls(Block(110, 124, 138, 6), true, false) != GroundClass.Water, "world3d: animated greyish blue is Water, a pale grey-blue is not");
            check(cls(Block(225, 95, 14, 18), false, false) == GroundClass.Lava, "world3d: bright orange-red is Lava");
            check(cls(Block(170, 65, 20, 10), true, false) == GroundClass.Lava && cls(Block(170, 65, 20, 10), false, false) != GroundClass.Lava, "world3d: a duller orange is Lava only when animated or lit");
            check(cls(Block(126, 92, 58), false, false) == GroundClass.Dirt && cls(Block(172, 112, 60), false, false) == GroundClass.Dirt, "world3d: brown, even a bright orange-brown, is Dirt, not Lava");
            check(cls(Block(218, 198, 132), false, false) == GroundClass.Sand, "world3d: pale yellow-brown is Sand");
            check(cls(Block(236, 240, 246, 5), false, false) == GroundClass.Snow, "world3d: bright grey-white is Snow");
            check(cls(Block(122, 122, 128, 12), false, false) == GroundClass.Stone && cls(Block(90, 95, 110, 6), false, false) == GroundClass.Stone, "world3d: grey and blue-grey are Stone");
            check(cls(Block(152, 102, 56, 4, 9, null, (x, y) => y % 8 == 0 ? -50 : 0), false, false) == GroundClass.Wood, "world3d: brown with lines is Wood");
            check(cls(Block(152, 102, 56, 30, 9), false, false) == GroundClass.Dirt, "world3d: the same brown as noise is Dirt (lines tell Wood)");
            check(cls(Block(4, 4, 8, 2), false, false) == GroundClass.Dark, "world3d: near black is Dark");
            check(cls(Block(100, 100, 100, 5, 1, (x, y) => x < 4), false, false) == GroundClass.Unknown, "world3d: a mostly clear sprite is Unknown");
            var st = Hd2dTerrain.Stats(Block(62, 112, 44, 8));
            check(st.Alpha > 0.99f && Near(st.R, 62 / 255f, 0.02f) && st.Hue > 90 && st.Hue < 130 && st.Spread < 0.08f && st.GreenShare > 0.95f, "world3d: stats of a grass block: mean, hue, spread, alpha, green share");
            check(Hd2dTerrain.Stats(Block(1, 1, 1, 0, 1, (x, y) => false)).Alpha == 0f, "world3d: a clear block has alpha 0");

            // ---- the cache by item id ----
            var art = MakeArt();
            var sc = new SpriteClassifier(art.Sprite);
            var gt = art.Dat.Items[Water];
            var i1 = sc.Info(gt); int reads = art.Reads;
            var i2 = sc.Info(gt);
            check(i1.Class == GroundClass.Water && i1.Animated && art.Reads == reads && sc.Count == 1 && i2.Class == i1.Class, "world3d: a type is measured once, by item id (all 4 water phases read)");
            check(reads == 4, "world3d: water reads its phases: " + reads);
            check(sc.Ground(art.Dat.Items[Lava]) == GroundClass.Lava && sc.Ground(art.Dat.Items[Stone]) == GroundClass.Stone && sc.Ground(art.Dat.Items[Wood]) == GroundClass.Wood
                  && sc.Ground(art.Dat.Items[Snow]) == GroundClass.Snow && sc.Ground(art.Dat.Items[Sand]) == GroundClass.Sand && sc.Ground(art.Dat.Items[Dirt]) == GroundClass.Dirt
                  && sc.Ground(art.Dat.Items[Grass]) == GroundClass.Grass, "world3d: every synthetic ground type gets its class through the dat");
            check(sc.Info(null).Class == GroundClass.Unknown, "world3d: no type, Unknown");

            // ---- roles of upright things ----
            var rules = new World3dRules(sc);
            Func<int, int, int, RuinsRole> role = (id, w, h) => rules.RoleOf(PieceOf(art, id, w, h));
            check(role(Grass, 1, 1) == RuinsRole.Terrain && role(Water, 1, 1) == RuinsRole.Water && role(Lava, 1, 1) == RuinsRole.Lava && role(Dirt, 1, 1) == RuinsRole.Terrain
                  && role(Sand, 1, 1) == RuinsRole.Terrain && role(Snow, 1, 1) == RuinsRole.Terrain, "world3d: ground roles: tile, water, lava");
            check(role(Stone, 1, 1) == RuinsRole.Floor && role(Wood, 1, 1) == RuinsRole.Floor, "world3d: stone and wood are the ruins floor");
            check(role(Tree, 1, 2) == RuinsRole.Tree, "world3d: a tall green blocking thing is a Tree");
            check(role(DeadTree, 2, 2) == RuinsRole.Tree && WorldIsDead(sc, art, DeadTree) && !WorldIsDead(sc, art, Tree), "world3d: a large brown blocking thing is a dead Tree");
            check(role(Rock, 1, 1) == RuinsRole.Rock, "world3d: a grey 1 x 1 blocking lump is a Rock");
            check(role(Bush, 1, 1) == RuinsRole.Bush, "world3d: a small green blocking thing is a Bush");
            check(role(Pillar, 2, 2) == RuinsRole.Pillar, "world3d: a large grey blocking thing stays a column");
            check(role(Wall, 2, 2) == RuinsRole.Wall && role(Hedge, 1, 1) == RuinsRole.None, "world3d: an on-bottom blocker is a wall, a green one (hedge) stays a sprite");
            check(role(Potion, 1, 1) == RuinsRole.None, "world3d: a carried green item stays a sprite");
            var loose = new Hd2dPiece { Type = art.Dat.Items[Bush], Kind = Hd2dKind.Object, Width = 1, Height = 1 };
            check(rules.RoleOf(loose) == RuinsRole.Bush, "world3d: a non-blocking small green thing is a Bush too");
            rules.Nature = false;
            check(role(Tree, 1, 2) == RuinsRole.None && role(Rock, 1, 1) == RuinsRole.None && role(Bush, 1, 1) == RuinsRole.None && !rules.ReplacesFn(PieceOf(art, Tree)) && role(Pillar, 2, 2) == RuinsRole.Pillar,
                  "world3d: without the nature models trees, rocks and bushes stay sprites (not columns)");
            rules.Nature = true;
            check(rules.RoleOf(null) == RuinsRole.None && rules.ReplacesFn(PieceOf(art, Grass)) && !rules.ReplacesFn(PieceOf(art, Potion)), "world3d: Replaces follows the role");

            // ---- the plan on a small map ----
            var world = new World(art.Dat) { Center = new Pos(100, 100, 7), WorldLight = 200 };
            var waterTiles = new HashSet<(int, int)>();
            var stoneTiles = new HashSet<(int, int)>();
            for (int x = 92; x <= 109; x++)
                for (int y = 94; y <= 107; y++)
                {
                    int id = Grass;
                    if (x >= 96 && x <= 98 && y >= 102 && y <= 103) { id = Water; waterTiles.Add((x, y)); }
                    else if (x >= 104 && x <= 106 && y >= 96 && y <= 98) { id = Stone; stoneTiles.Add((x, y)); }
                    else if (x == 101) id = Dirt;
                    AddItem(world, x, y, id);
                }
            AddItem(world, 95, 96, Tree); AddItem(world, 93, 99, DeadTree); AddItem(world, 99, 99, Rock); AddItem(world, 102, 103, Bush);
            var origin = world.Center;
            var layout = Hd2d.Layout(world, origin, 40f, null, false);
            var plan = Hd2dWorld3d.Plan(layout, origin, rules);
            var again = Hd2dWorld3d.Plan(layout, origin, rules);
            check(plan.Count == again.Count && plan.Zip(again, (p, q) => p.ToString() == q.ToString()).All(b => b), "world3d: the plan is deterministic");
            int dirtCount = 18 * 14 - waterTiles.Count - stoneTiles.Count;
            var tilesP = plan.Where(q => q.Piece == Hd2dWorld3d.TilePiece).ToList();
            var waterP = plan.Where(q => q.Piece == Hd2dWorld3d.WaterPiece).ToList();
            var floorP = plan.Where(q => q.Role == RuinsRole.Floor).ToList();
            check(tilesP.Count == dirtCount && waterP.Count == waterTiles.Count && floorP.Count == stoneTiles.Count, "world3d: a tile per grass and dirt tile, a plane per water tile, a ruins floor per stone tile: " + tilesP.Count + "/" + waterP.Count + "/" + floorP.Count);
            check(waterP.All(q => q.Ground == GroundClass.Water && Near(q.Y, Hd2dTerrain.WaterY)) && Hd2dTerrain.WaterY < Hd2dTerrain.TileTop - 0.05f && tilesP.All(q => Near(q.Y, Hd2dTerrain.TileTop)), "world3d: water lies below the tiles");
            var grassTile = tilesP.First(q => q.Ground == GroundClass.Grass);
            check(grassTile.TintG > grassTile.TintR && grassTile.TintG > grassTile.TintB && Near(grassTile.TintR, 62 / 255f, 0.03f), "world3d: a tile carries the sprite's mean colour: " + grassTile.TintR + "," + grassTile.TintG);
            var trees = plan.Where(q => q.Role == RuinsRole.Tree).ToList();
            check(trees.Count == 2 && trees.Count(q => Array.IndexOf(Hd2dWorld3d.LiveTrees, q.Piece) >= 0) == 1 && trees.Count(q => Array.IndexOf(Hd2dWorld3d.DeadTrees, q.Piece) >= 0) == 1, "world3d: a live and a dead tree model");
            var live = trees.First(q => Array.IndexOf(Hd2dWorld3d.LiveTrees, q.Piece) >= 0);
            check(Near(live.X, Hd2dRuins.TileX(origin, 95)) && Near(live.Z, Hd2dRuins.TileZ(origin, 96)) && Near(live.Y, 0f), "world3d: a one cell wide tree stands on its tile");
            check(Near(live.Scale * Hd2dWorld3d.ModelHeight(live.Piece), Hd2dWorld3d.TreeHeight(2), 0.3f), "world3d: tree height follows the sprite's height: " + live.Scale);
            var dead = trees.First(q => Array.IndexOf(Hd2dWorld3d.DeadTrees, q.Piece) >= 0);
            check(Near(dead.X, Hd2dRuins.TileX(origin, 93) - 0.5f), "world3d: a 2 cell wide tree is centred between its two columns");
            check(plan.Count(q => q.Role == RuinsRole.Rock && Array.IndexOf(Hd2dWorld3d.Rocks, q.Piece) >= 0 && Near(q.X, Hd2dRuins.TileX(origin, 99)) && Near(q.Z, Hd2dRuins.TileZ(origin, 99))) == 1, "world3d: the rock stands on its tile");
            check(plan.Count(q => q.Role == RuinsRole.Bush && Array.IndexOf(Hd2dWorld3d.Bushes, q.Piece) >= 0) == 1, "world3d: the bush");
            check(plan.All(q => q.Piece.StartsWith("@", StringComparison.Ordinal) || Array.IndexOf(Hd2dRuins.AllPieces, q.Piece) >= 0 || Hd2dWorld3d.IsNature(q.Piece)), "world3d: every placed piece is a known one");
            // scatter
            var scatter = plan.Where(q => q.Role == RuinsRole.Scatter || (q.Role == RuinsRole.Rock && !(Near(q.X, Hd2dRuins.TileX(origin, 99)) && Near(q.Z, Hd2dRuins.TileZ(origin, 99))))).ToList();
            Func<RuinsPlacement, (int, int)> tileOf = q => ((int)Math.Floor(q.X + origin.X), (int)Math.Floor(-q.Z + origin.Y));
            int free = 0, freeGrass = 0;
            foreach (var q in tilesP) { var tt = tileOf(q); if (!(tt.Item1 == 95 && tt.Item2 == 96) && !(tt.Item1 == 99 && tt.Item2 == 99) && !(tt.Item1 == 102 && tt.Item2 == 103) && !(tt.Item1 == 93 && tt.Item2 == 99)) { free++; if (q.Ground == GroundClass.Grass) freeGrass++; } }
            check(scatter.Count >= free * 0.07 && scatter.Count <= free * 0.25, "world3d: about 15% of the free grass and dirt tiles get a model: " + scatter.Count + " of " + free);
            check(scatter.All(q => { var tt = tileOf(q); return !waterTiles.Contains(tt) && !stoneTiles.Contains(tt) && tt != (95, 96) && tt != (99, 99) && tt != (102, 103) && tt != (93, 99); }), "world3d: no scatter on water, stone, trees, rocks or bushes");
            var dirtScatter = scatter.Where(q => tileOf(q).Item1 == 101).ToList();
            check(dirtScatter.All(q => q.Role == RuinsRole.Rock), "world3d: dirt gets rocks only");
            check(scatter.Any(q => q.Piece.StartsWith("Grass", StringComparison.Ordinal)) && scatter.Any(q => q.Piece.StartsWith("Plant", StringComparison.Ordinal)) && scatter.Any(q => q.Role == RuinsRole.Rock),
                  "world3d: the scatter mixes grass, plants and rocks: " + string.Join(",", scatter.Select(q => q.Piece).Distinct().OrderBy(s => s)));
            // creatures do not change the plan
            var hero = new Creature { Id = 1, Name = "Hero", Outfit = new Outfit(128, 0, 0, 0, 0) };
            world.Creatures[1] = hero; world.AddThing(new Pos(100, 101, 7), new Thing { Creature = hero }); world.PlayerId = 1;
            var withHero = Hd2dWorld3d.Plan(Hd2d.Layout(world, origin, 40f, null, false), origin, rules);
            check(withHero.Count == plan.Count && withHero.Zip(plan, (p, q) => p.ToString() == q.ToString()).All(b => b), "world3d: creatures are not part of the plan");
            var noNature = new World3dRules(sc) { Nature = false };
            var plain = Hd2dWorld3d.Plan(layout, origin, noNature);
            check(plain.All(q => !Hd2dWorld3d.IsNature(q.Piece)) && plain.Count(q => q.Piece == Hd2dWorld3d.TilePiece) == tilesP.Count, "world3d: no nature models without the pack, the tiles stay");

            // ---- tile look ----
            var ws = Hd2dTerrain.TileStyle(GroundClass.Water, 28 / 255f, 62 / 255f, 128 / 255f);
            check(ws.B > ws.R && ws.B > ws.G && ws.B < 0.35f && ws.Smoothness > 0.6f && !ws.Emissive, "world3d: water is dark blue and glossy");
            var ls = Hd2dTerrain.TileStyle(GroundClass.Lava, 225 / 255f, 95 / 255f, 14 / 255f);
            check(ls.Emissive && ls.EmitR > ls.EmitG && ls.EmitG > ls.EmitB && ls.EmitR >= 1.5f, "world3d: lava is emissive orange");
            var gs = Hd2dTerrain.TileStyle(GroundClass.Grass, 62 / 255f, 112 / 255f, 44 / 255f);
            check(gs.G > gs.R && gs.G > gs.B && gs.G < 112 / 255f && !gs.Emissive, "world3d: grass keeps its hue and is darker than the sprite");
            var ds1 = Hd2dTerrain.TileStyle(GroundClass.Dirt, 126 / 255f, 92 / 255f, 58 / 255f);
            check(ds1.R > ds1.G && ds1.G > ds1.B, "world3d: a map's palette survives: dirt stays brown");
            var rg = Hd2dRuins.Restyle("Green", 0.07f, 0.12f, 0.05f, RuinsRole.Tree);
            check(rg.G > rg.R && rg.G > rg.B && rg.G < 0.6f, "world3d: the leaves' green is restyled dark but green");

            // ---- the rebuild hash ----
            int h0 = Hd2dWorld3d.ViewHash(world);
            check(h0 == Hd2dWorld3d.ViewHash(world), "world3d: the hash of an unchanged view is stable");
            var hero2 = world.Tiles[new Pos(100, 101, 7)];
            hero2.Things.RemoveAll(t => t.IsCreature);
            world.AddThing(new Pos(101, 105, 7), new Thing { Creature = hero });
            check(Hd2dWorld3d.ViewHash(world) == h0, "world3d: a creature moving does not change the hash");
            AddItem(world, 97, 100, Bush);
            int h1 = Hd2dWorld3d.ViewHash(world);
            check(h1 != h0, "world3d: an item appearing changes the hash");
            world.Get(new Pos(97, 100, 7)).Things.RemoveAt(world.Get(new Pos(97, 100, 7)).Things.Count - 1);
            check(Hd2dWorld3d.ViewHash(world) == h0, "world3d: and removing it brings the hash back");
            AddItem(world, 60, 60, Tree);
            check(Hd2dWorld3d.ViewHash(world) == h0, "world3d: a tile outside the view window does not matter");
            world.Center = new Pos(101, 100, 7);
            check(Hd2dWorld3d.ViewHash(world) != h0, "world3d: walking a tile changes the hash (the window moves)");
            world.Center = origin;
            long before = GC.GetAllocatedBytesForCurrentThread();
            int acc = 0;
            for (int i = 0; i < 2000; i++) acc ^= Hd2dWorld3d.ViewHash(world);
            long alloc = GC.GetAllocatedBytesForCurrentThread() - before;
            check(alloc == 0 && acc == 0, "world3d: the hash allocates nothing: " + alloc + " bytes in 2000 calls");
            var sw = Stopwatch.StartNew();
            for (int i = 0; i < 2000; i++) acc ^= Hd2dWorld3d.ViewHash(world);
            double perHash = sw.Elapsed.TotalMilliseconds / 2000;
            check(perHash < 0.5, "world3d: a hash of the 18 x 14 view takes " + perHash.ToString("0.0000") + " ms");
            sw.Restart();
            int n = 0;
            for (int i = 0; i < 50; i++) n += Hd2dWorld3d.Plan(layout, origin, rules).Count;
            double perPlan = sw.Elapsed.TotalMilliseconds / 50;
            check(perPlan < 30, "world3d: planning an 18 x 14 view takes " + perPlan.ToString("0.00") + " ms (" + n / 50 + " pieces)");
            Console.WriteLine("world3d: hash " + perHash.ToString("0.0000") + " ms, plan " + perPlan.ToString("0.00") + " ms for " + n / 50 + " pieces");

            // ---- the outdoor demo ----
            var ids = Hd2dDemo.PickOutdoor(art.Dat, art.Sprite);
            check(ids != null && ids.Grass == Grass && ids.Water == Water && ids.Dirt == Dirt && ids.Tree == Tree && ids.Rock == Rock && ids.Bush == Bush, "world3d: the id pick from pixels: " + ids);
            var demo = Hd2dDemo.Outdoor(art.Dat, art.Sprite);
            check(demo != null && demo.World.Player != null && demo.World.Tiles.Count == 18 * 14, "world3d: the outdoor demo has the view's tiles and a hero");
            var dl = Hd2d.Layout(demo.World, demo.Center, 40f, null, false);
            var dplan = Hd2dWorld3d.Plan(dl, demo.Center, new World3dRules(new SpriteClassifier(art.Sprite)));
            check(dplan.Any(q => q.Piece == Hd2dWorld3d.WaterPiece) && dplan.Count(q => q.Role == RuinsRole.Tree) >= 3 && dplan.Any(q => q.Piece == Hd2dWorld3d.TilePiece && q.Ground == GroundClass.Dirt) && dplan.Any(q => q.Role == RuinsRole.Scatter),
                  "world3d: the outdoor plan has a pond, a path, trees and scatter: " + dplan.Count + " pieces");
            var bare = MakeArt();
            bare.Dat.Items[Tree] = null;
            check(Hd2dDemo.PickOutdoor(bare.Dat, bare.Sprite) == null && Hd2dDemo.Outdoor(bare.Dat, bare.Sprite) == null, "world3d: a pair without a tree gives no outdoor demo");
        }

        static bool WorldIsDead(SpriteClassifier sc, Art a, int id) => Hd2dWorld3d.IsDeadTree(sc.Info(a.Dat.Items[id]));
    }
}
