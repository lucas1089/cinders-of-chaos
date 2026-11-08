// Checks of the front-art live view (Core/FrontLive.cs, the new textures of Core/FrontArtTex.cs, the origin / void / tint of the mesher):
// ground and wall classes to blocks and textures, heights, items as sprites or boxes, lights, the floors below, the rebuild hash and
// the size and time bounds of one rebuild. The art is synthetic blocks of colour, like World3dTests.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class FrontLiveTests
    {
        static int H(int x, int y, int s) { unchecked { int h = x * 73856093 ^ y * 19349663 ^ s * 83492791; h ^= h >> 13; h *= 0x5bd1e995; return (h ^ (h >> 15)) & 0x7fffffff; } }

        static byte Cl(int v) { return (byte)(v < 0 ? 0 : v > 255 ? 255 : v); }

        static byte[] Block(int r, int g, int b, int noise = 8, int seed = 1, Func<int, int, bool> shape = null, Func<int, int, int> row = null)
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

        static bool Disc(int x, int y) { return (x - 16) * (x - 16) + (y - 16) * (y - 16) <= 144; }

        sealed class Art
        {
            public DatFile Dat = new DatFile { Items = new ThingType[400], Outfits = new ThingType[200], Effects = new ThingType[2], Missiles = new ThingType[2] };
            readonly Dictionary<int, Func<int, byte[]>> paint = new Dictionary<int, Func<int, byte[]>>();

            public byte[] Sprite(uint id)
            {
                int item = (int)(id / 100), idx = (int)(id % 100);
                return paint.TryGetValue(item, out var f) ? f(idx) : null;
            }

            public void Item(int id, int w, int h, int phases, Action<ThingType> flags, Func<int, byte[]> p)
            {
                var g = new FrameGroup { Width = w, Height = h, Layers = 1, PatternX = 1, PatternY = 1, PatternZ = 1, Phases = phases, Sprites = new uint[w * h * phases] };
                for (int i = 0; i < g.Sprites.Length; i++) g.Sprites[i] = (uint)(id * 100 + i);
                var t = new ThingType { Category = ThingCategory.Item, Id = id, Groups = new[] { g } };
                flags?.Invoke(t);
                Dat.Items[id] = t;
                paint[id] = p;
            }

            public void Outfit(int id)
            {
                var g = new FrameGroup { Width = 1, Height = 1, Layers = 1, PatternX = 4, PatternY = 1, PatternZ = 1, Phases = 1, Sprites = new uint[4] };
                Dat.Outfits[id] = new ThingType { Category = ThingCategory.Outfit, Id = id, Groups = new[] { g } };
            }
        }

        const int Grass = 200, Water = 201, Dirt = 202, Lava = 203, Stone = 204, Snow = 205, Sand = 206, Wood = 207, Tree = 208, Rock = 209, Pillar = 210,
                  WallGrey = 211, WallRed = 212, Hedge = 213, Fence = 214, Potion = 215, Rug = 216, Torch = 217, Table = 218, Hole = 219, Cliff = 220, Blood = 221, Stairs = 222, WallPlank = 223;

        static Art MakeArt()
        {
            var a = new Art();
            Action<ThingType> ground = t => t.Ground = true;
            Action<ThingType> block = t => t.NotWalkable = true;
            Action<ThingType> wall = t => { t.OnBottom = true; t.NotWalkable = true; };
            a.Item(Grass, 1, 1, 1, ground, i => Block(62, 112, 44, 8, 1));
            a.Item(Water, 1, 1, 4, ground, i => Block(28, 62, 128, 6, 3 + i));
            a.Item(Dirt, 1, 1, 1, ground, i => Block(126, 92, 58, 10, 4));
            a.Item(Lava, 1, 1, 3, t => { t.Ground = true; t.LightLevel = 5; t.LightColor = 198; }, i => Block(225, 95, 14, 18, 5 + i));
            a.Item(Stone, 1, 1, 1, ground, i => Block(122, 122, 128, 12, 6));
            a.Item(Snow, 1, 1, 1, ground, i => Block(236, 240, 246, 5, 7));
            a.Item(Sand, 1, 1, 1, ground, i => Block(218, 198, 132, 8, 8));
            a.Item(Wood, 1, 1, 1, ground, i => Block(152, 102, 56, 4, 9, null, (x, y) => y % 8 == 0 ? -50 : 0));
            a.Item(Hole, 1, 1, 1, ground, i => Block(4, 4, 8, 2));
            a.Item(Cliff, 1, 1, 1, t => { t.Ground = true; t.NotWalkable = true; }, i => Block(122, 122, 128, 12, 6));
            a.Item(Tree, 1, 2, 1, block, i => i == 0 ? Block(40, 100, 36, 12, 10, Disc) : Block(60, 40, 28, 8, 11, (x, y) => x > 12 && x < 20));
            a.Item(Rock, 1, 1, 1, block, i => Block(128, 128, 134, 14, 13, Disc));
            a.Item(Pillar, 1, 2, 1, block, i => Block(130, 130, 136, 10, 15));
            a.Item(WallGrey, 1, 1, 1, wall, i => Block(120, 118, 126, 10, 16));
            a.Item(WallRed, 1, 1, 1, wall, i => Block(150, 60, 44, 10, 17));
            a.Item(WallPlank, 1, 1, 1, wall, i => Block(152, 102, 56, 4, 19, null, (x, y) => y % 8 == 0 ? -50 : 0));
            a.Item(Hedge, 1, 1, 1, wall, i => Block(48, 110, 40, 10, 18));
            a.Item(Fence, 1, 1, 1, wall, i => Block(150, 110, 70, 6, 20, (x, y) => x % 6 < 2));
            a.Item(Potion, 1, 1, 1, t => t.Pickupable = true, i => Block(50, 140, 50, 10, 21, Disc));
            a.Item(Rug, 1, 1, 1, t => { t.OnBottom = true; }, i => Block(160, 40, 50, 6, 22));
            a.Item(Stairs, 1, 1, 1, t => { }, i => Block(130, 110, 90, 8, 23));
            a.Item(Blood, 1, 1, 1, t => t.Splash = true, i => Block(150, 20, 20, 6, 24, Disc));
            a.Item(Torch, 1, 1, 2, t => { t.LightLevel = 7; t.LightColor = 208; t.NotWalkable = false; }, i => Block(200, 140, 60, 10, 25 + i, Disc));
            a.Item(Table, 2, 1, 1, block, i => Block(152, 102, 56, 14, 26));
            a.Outfit(128);
            return a;
        }

        static World Field(Art a, int id, int cx = 100, int cy = 100, int z = 7)
        {
            var w = new World(a.Dat) { Center = new Pos(cx, cy, z) };
            for (int y = cy - 8; y <= cy + 9; y++) for (int x = cx - 10; x <= cx + 11; x++) w.AddThing(new Pos(x, y, z), new Thing { Item = w.MakeItem(id, 0) });
            return w;
        }

        static void Put(World w, int x, int y, int id, int z = 7) { w.AddThing(new Pos(x, y, z), new Thing { Item = w.MakeItem(id, 0) }); }

        static FrontLiveLayout Build(World w, Art a, Pos? anchor = null, FrontLiveOptions o = null)
        {
            return FrontLive.Build(w, anchor ?? w.Center, new SpriteClassifier(a.Sprite), o);
        }

        static bool At(FrontLiveLayout l, int tx, int ty, FaTex top, int level)
        {
            int gx = tx - l.X0, gz = l.Y1 - ty;
            return l.Grid.Top[gx, gz] == top && l.Grid.H[gx, gz] == level && !l.Grid.IsVoid(gx, gz);
        }

        static bool Near(float a, float b, float e = 1e-3f) { return Math.Abs(a - b) <= e; }

        public static void Run(Action<bool, string> check)
        {
            // ---- the new block textures ----
            var kinds = new[] { FaTex.Grass, FaTex.Sand, FaTex.Snow, FaTex.Water, FaTex.Lava };
            var texs = kinds.ToDictionary(k => k, k => FrontArtTex.Make(k, 1098));
            Func<PixelTex, int> distinct = t => { var set = new HashSet<uint>(); for (int y = 0; y < t.H; y++) for (int x = 0; x < t.W; x++) set.Add(t.Get(x, y)); return set.Count; };
            check(kinds.All(k => texs[k].W == 64 && texs[k].H == 64 && texs[k].Rgba.Length == 64 * 64 * 4), "front live: the live ground textures are 64 x 64 RGBA");
            check(kinds.All(k => { var t = texs[k]; for (int i = 3; i < t.Rgba.Length; i += 4) if (t.Rgba[i] != 255) return false; return true; }), "front live: they are opaque");
            check(kinds.All(k => FrontArtTex.Make(k, 1098).Rgba.SequenceEqual(texs[k].Rgba) && !FrontArtTex.Make(k, 7).Rgba.SequenceEqual(texs[k].Rgba)), "front live: same seed same bytes, another seed another texture");
            check(kinds.All(k => { int n = distinct(texs[k]); return n >= 6 && n <= 120; }), "front live: a small palette each: " + string.Join(",", kinds.Select(k => distinct(texs[k]))));
            check((int)FaTex.Count == 13 && FrontArtTex.Emit(FaTex.Lava) > 1f && FrontArtTex.Emit(FaTex.Coal) > 1f && FrontArtTex.Emit(FaTex.Grass) == 0f, "front live: 13 kinds, lava and coal glow, grass does not");
            foreach (var k in new[] { FaTex.Grass, FaTex.Sand, FaTex.Snow, FaTex.Water })
            {
                var ramp = FrontArtTex.Ramp(k);
                bool rising = true;
                for (int i = 1; i < ramp.Length; i++) rising &= (((ramp[i] >> 16) & 255) + (ramp[i] & 255)) > (((ramp[i - 1] >> 16) & 255) + (ramp[i - 1] & 255));
                check(rising && ((ramp[0] & 255) >= ((ramp[0] >> 16) & 255)), "front live: " + k + " ramp gets lighter, cool in the shadow");
            }
            foreach (var k in kinds)
            {
                var t = texs[k];
                double seam = 0, inner = 0, seamV = 0, innerV = 0;
                for (int y = 0; y < 64; y++) seam += Math.Abs(((int)(t.Get(63, y) >> 16) & 255) - ((int)(t.Get(0, y) >> 16) & 255));
                for (int x = 0; x < 63; x++) for (int y = 0; y < 64; y++) inner += Math.Abs(((int)(t.Get(x, y) >> 16) & 255) - ((int)(t.Get(x + 1, y) >> 16) & 255));
                for (int x = 0; x < 64; x++) seamV += Math.Abs(((int)(t.Get(x, 63) >> 16) & 255) - ((int)(t.Get(x, 0) >> 16) & 255));
                for (int y = 0; y < 63; y++) for (int x = 0; x < 64; x++) innerV += Math.Abs(((int)(t.Get(x, y) >> 16) & 255) - ((int)(t.Get(x, y + 1) >> 16) & 255));
                inner /= 63; innerV /= 63;
                check(seam <= inner * 1.5 + 40 && seamV <= innerV * 1.5 + 40, "front live: " + k + " tiles without a seam");
            }
            int bright = 0;
            for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++) if (((int)(texs[FaTex.Lava].Get(x, y) >> 16) & 255) > 200) bright++;
            check(bright > 100 && bright < 1500, "front live: lava has glowing veins in a dark crust (" + bright + " bright texels)");
            int waterBlue = 0;
            for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++) { var c = texs[FaTex.Water].Get(x, y); if ((c & 255) > ((c >> 16) & 255)) waterBlue++; }
            check(waterBlue > 64 * 64 * 0.95, "front live: water is blue");

            var art = MakeArt();

            // ---- ground classes to blocks and textures ----
            var map = new Dictionary<int, FaTex> { { Grass, FaTex.Grass }, { Water, FaTex.Water }, { Dirt, FaTex.Dirt }, { Lava, FaTex.Lava }, { Snow, FaTex.Snow }, { Sand, FaTex.Sand }, { Wood, FaTex.Wood } };
            // one tile of each kind on its own: build a field per kind and read the middle tile
            foreach (var kv in map)
            {
                var wk = Field(art, kv.Key);
                var lk = Build(wk, art);
                int expect = kv.Key == Water || kv.Key == Lava ? -1 : 0;
                bool ok = At(lk, 100, 100, kv.Value, expect) || (kv.Key == Dirt && (lk.Grid.Top[100 - lk.X0, lk.Y1 - 100] == FaTex.MossDirt));
                check(ok, "front live: ground " + kv.Key + " becomes " + kv.Value + " at level " + expect);
            }
            var wStone = Field(art, Stone);
            var lStone = Build(wStone, art);
            int stoneTiles = 0, cobble = 0;
            for (int ty = lStone.Y0; ty <= lStone.Y1; ty++) for (int tx = lStone.X0; tx <= lStone.X1; tx++)
            {
                var tp = lStone.Grid.Top[tx - lStone.X0, lStone.Y1 - ty];
                if (tp == FaTex.Flagstone) stoneTiles++; else if (tp == FaTex.Cobble) cobble++;
            }
            check(stoneTiles + cobble == 20 * 16 && cobble > 10 && cobble < stoneTiles / 2, "front live: stone is flagstone with some cobble: " + stoneTiles + " / " + cobble);
            check(lStone.Grid.W == 20 && lStone.Grid.D == 16 && lStone.X1 - lStone.X0 == 19 && lStone.Y1 - lStone.Y0 == 15, "front live: the window is the client's 18 x 14 and a tile round it: 20 x 16");
            check(lStone.GroundTiles == 320 && lStone.VoidTiles == 0 && lStone.WallTiles == 0, "front live: a stone field is 320 ground tiles");

            // ---- water and lava lie lower, the shore has a side ----
            var wPond = new World(art.Dat) { Center = new Pos(100, 100, 7) };
            for (int y = 92; y <= 109; y++) for (int x = 90; x <= 111; x++) Put(wPond, x, y, Math.Abs(x - 100) <= 2 && Math.Abs(y - 100) <= 2 ? Water : Grass);
            var lPond = Build(wPond, art);
            var pondMesh = FrontArtMesher.Terrain(lPond.Grid);
            check(lPond.WaterTiles == 25 && At(lPond, 100, 100, FaTex.Water, -1) && At(lPond, 95, 100, FaTex.Grass, 0), "front live: a pond is 25 water tiles one level lower than the grass");
            check(pondMesh[(int)FaTex.MossDirt].Quads >= 20, "front live: the shore has sides of earth (" + pondMesh[(int)FaTex.MossDirt].Quads + " quads)");
            check(Near(lPond.GroundY(100, 100), -0.5f) && Near(lPond.GroundY(95, 100), 0f), "front live: ground height -0.5 on the water, 0 on the grass");

            // ---- walls are tall blocks ----
            var wW = Field(art, Stone);
            Put(wW, 100, 100, WallGrey); Put(wW, 101, 100, WallRed); Put(wW, 102, 100, WallPlank); Put(wW, 103, 100, Hedge); Put(wW, 104, 100, Fence);
            var lW = Build(wW, art);
            var o = new FrontLiveOptions();
            check(At(lW, 100, 100, FaTex.Flagstone, o.WallLevels) && lW.Grid.Side[100 - lW.X0, lW.Y1 - 100] == FaTex.Flagstone, "front live: a grey wall is a 5 level block of flagstone (" + o.WallLevels * 0.5f + " units)");
            check(lW.Grid.H[100 - lW.X0, lW.Y1 - 100] * 0.5f >= 2.5f && lW.Grid.Masonry[100 - lW.X0, lW.Y1 - 100], "front live: walls are at least 2.5 units, masonry");
            check(lW.Grid.Side[101 - lW.X0, lW.Y1 - 100] == FaTex.Brick, "front live: a red-brown wall has brick sides");
            check(lW.Grid.Side[102 - lW.X0, lW.Y1 - 100] == FaTex.Wood && lW.Grid.Top[102 - lW.X0, lW.Y1 - 100] == FaTex.Wood, "front live: a plank wall is wood");
            check(At(lW, 103, 100, FaTex.Grass, o.HedgeLevels) && !lW.Grid.Masonry[103 - lW.X0, lW.Y1 - 100], "front live: a green wall is a low hedge of grass");
            check(lW.Grid.H[104 - lW.X0, lW.Y1 - 100] == o.FenceLevels, "front live: a mostly clear wall is a fence, 2 levels");
            check(lW.WallTiles == 4 && lW.HedgeTiles == 1, "front live: wall counts " + lW.WallTiles + " / " + lW.HedgeTiles);
            check(lW.Grid.H[100 - lW.X0, lW.Y1 - 100] > lW.Grid.H[104 - lW.X0, lW.Y1 - 100] && lW.Grid.H[104 - lW.X0, lW.Y1 - 100] > lW.Grid.H[99 - lW.X0, lW.Y1 - 100], "front live: wall taller than fence taller than floor");
            var wallMesh = FrontArtMesher.Terrain(lW.Grid);
            check(wallMesh[(int)FaTex.Brick].Quads >= 2, "front live: the wall's sides are meshed");
            // a cliff: ground the dat marks not walkable
            var wC2 = new World(art.Dat) { Center = new Pos(100, 100, 7) };
            for (int y = 92; y <= 109; y++) for (int x = 90; x <= 111; x++) Put(wC2, x, y, x == 100 && y == 100 ? Cliff : Dirt);
            var lC = Build(wC2, art);
            check(lC.Grid.H[100 - lC.X0, lC.Y1 - 100] == o.CliffLevels && lC.CliffTiles == 1, "front live: a not walkable stone ground is a cliff block of 4 levels");

            // ---- items: sprites, boxes, flats ----
            var wI = Field(art, Grass);
            Put(wI, 98, 100, Potion);
            Put(wI, 99, 102, Tree);
            Put(wI, 101, 98, Blood);
            Put(wI, 102, 98, Rug);
            Put(wI, 103, 98, Stairs);
            Put(wI, 104, 100, Rock);
            Put(wI, 105, 100, Pillar);
            Put(wI, 106, 100, Table);
            var lI = Build(wI, art);
            Func<int, int, List<Hd2dPiece>> upAt = (tx, ty) => lI.Upright.Where(p => p.Tile.X == tx && p.Tile.Y == ty).ToList();
            check(upAt(98, 100).Count == 1 && upAt(98, 100)[0].Item.Id == Potion, "front live: a potion is an upright sprite");
            check(upAt(99, 102).Count == 1 && upAt(99, 102)[0].Height == 2, "front live: a tree is an upright sprite, two cells high");
            check(lI.Flat.Any(p => p.Tile.X == 101 && p.Tile.Y == 98) && lI.Flat.Any(p => p.Tile.X == 102 && p.Tile.Y == 98), "front live: blood and a rug lie flat");
            check(lI.Flat.Any(p => p.Tile.X == 103 && p.Tile.Y == 98) && upAt(103, 98).Count == 0, "front live: a loose item that fills its tile (stairs, a hatch) lies flat");
            check(lI.Grid.Boxes.Count(b => b.Tag == "rock") == 3 && upAt(104, 100).Count == 0, "front live: a grey 1 x 1 blocker is three rock boxes, no sprite");
            check(lI.Grid.Boxes.Count(b => b.Tag == "pillar") == 4 && upAt(105, 100).Count == 0, "front live: a tall grey blocker is a pillar of four boxes");
            check(lI.Grid.Boxes.Count(b => b.Tag == "furniture") == 2 && lI.Grid.Boxes.Where(b => b.Tag == "furniture").All(b => b.Tex == FaTex.Wood) && upAt(106, 100).Count == 0, "front live: a wide brown blocker is a wooden box and its lid");
            var fb = lI.Grid.Boxes.First(b => b.Tag == "furniture");
            check(fb.X1 - fb.X0 > 1.5f && fb.Y1 - fb.Y0 >= 0.5f, "front live: the table box is two tiles wide");
            var pot = upAt(98, 100)[0];
            check(Near(pot.Y, 0f) && Near(pot.Right, 98 - 100 + 1f) && Near(pot.Z, 100 - 100 - 0.5f, 0.01f), "front live: the sprite stands on the block top in the middle of its tile (x " + pot.Right + ", z " + pot.Z + ")");
            check(lI.Flat.All(p => p.Y > 0f && p.Y < 0.1f) && lI.Upright.All(p => p.Y >= 0f), "front live: flat sprites lie a hair above the top");
            check(lI.Flat.All(p => p.Flat) && lI.Upright.All(p => !p.Flat), "front live: flat and upright lists hold the right kind");

            // items stand at the height of their block
            var wH = new World(art.Dat) { Center = new Pos(100, 100, 7) };
            for (int y = 92; y <= 109; y++) for (int x = 90; x <= 111; x++) Put(wH, x, y, Math.Abs(x - 100) <= 2 && Math.Abs(y - 100) <= 2 ? Water : Grass);
            Put(wH, 100, 100, Potion); Put(wH, 95, 100, Potion);
            var lH = Build(wH, art);
            check(Near(lH.Upright.First(p => p.Tile.X == 100).Y, -0.5f) && Near(lH.Upright.First(p => p.Tile.X == 95).Y, 0f), "front live: an item on the water stands at -0.5, on the grass at 0");

            // ---- lights ----
            var wL = Field(art, Stone);
            Put(wL, 99, 99, Torch);
            Put(wL, 104, 100, Lava);   // a second ground under the first: ignored by the column but the piece still lights
            var lL = Build(wL, art);
            var tl = lL.Lights.Where(l => l.Flame).ToList();
            check(tl.Count >= 1, "front live: a torch is a warm Flame light");
            var torchLight = lL.Lights.OrderBy(l => Math.Abs(l.X - (99 - 100 + 0.5f)) + Math.Abs(l.Z - (100 - 99 - 0.5f))).First();
            check(Near(torchLight.X, -0.5f, 0.01f) && Near(torchLight.Z, 0.5f, 0.01f) && torchLight.Y > 1f && torchLight.Range >= 5f && torchLight.Range <= 8f && torchLight.Intensity >= 0.6f && torchLight.Intensity <= 1.6f,
                  "front live: the light hangs at its tile (" + torchLight.X + ", " + torchLight.Y + ", " + torchLight.Z + ") range " + torchLight.Range);
            check(torchLight.R > torchLight.B + 0.15f && torchLight.R >= 0.6f, "front live: the colour index 208 is a warm orange");
            check(lL.Upright.Any(p => p.Item.Id == Torch) && lL.Animated, "front live: the torch is also a sprite, and its two phases make the layout animated");
            check(lL.Lights.Count >= 2, "front live: a lit ground adds its light (" + lL.Lights.Count + " lights)");
            var wLava = Field(art, Lava);
            var lLava = Build(wLava, art);
            check(lLava.Lights.Count == FrontLive.MaxLights && lLava.LavaTiles == 320, "front live: a field of lava keeps at most " + FrontLive.MaxLights + " lights");

            // ---- the floors below, voids ----
            var wB = new World(art.Dat) { Center = new Pos(100, 100, 8) };
            for (int y = 92; y <= 109; y++) for (int x = 90; x <= 111; x++)
                    if (!(x >= 98 && x <= 101 && y >= 98 && y <= 101)) Put(wB, x, y, Stone, 8);   // a hole of 4 x 4 tiles in the floor
            // the floor below, shown shifted one tile south-east
            for (int y = 92; y <= 110; y++) for (int x = 90; x <= 112; x++) Put(wB, x, y, Grass, 9);
            var lB = Build(wB, art);
            check(lB.LowerTiles >= 16 && lB.Grid.H[99 - lB.X0, lB.Y1 - 99] == -6 && lB.Grid.Top[99 - lB.X0, lB.Y1 - 99] == FaTex.Grass, "front live: a hole shows the floor below, 6 levels (3 units) lower: " + lB.LowerTiles + " tiles");
            var cellTint = lB.Grid.TintG[99 - lB.X0, lB.Y1 - 99];
            check(cellTint < lB.Grid.TintG[95 - lB.X0, lB.Y1 - 95] * 0.7f, "front live: the floor below is darker");
            check(lB.VoidTiles == 0 && !lB.Grid.IsVoid(99 - lB.X0, lB.Y1 - 99), "front live: no void where a floor below shows");
            var wBv = new World(art.Dat) { Center = new Pos(100, 100, 7) };
            for (int y = 92; y <= 109; y++) for (int x = 90; x <= 111; x++) if (!(x >= 98 && x <= 101 && y >= 98 && y <= 101)) Put(wBv, x, y, Stone);
            var lBv = Build(wBv, art);
            check(lBv.VoidTiles == 16 && lBv.Grid.IsVoid(99 - lBv.X0, lBv.Y1 - 99) && lBv.LowerTiles == 0, "front live: a hole with nothing below is a void of 16 tiles");
            var voidMesh = FrontArtMesher.Terrain(lBv.Grid);
            int topsNoVoid = FrontArtMesher.TotalQuads(FrontArtMesher.Terrain(Build(Field(art, Stone), art).Grid));
            check(FrontArtMesher.TotalQuads(voidMesh) > topsNoVoid - 16, "front live: the void has no top, its rim has sides (" + FrontArtMesher.TotalQuads(voidMesh) + " quads against " + topsNoVoid + ")");
            check(Near(lBv.GroundY(99, 99), -1.5f), "front live: the ground of a void is the far ground's depth");
            var wDark = Field(art, Hole);
            var lDark = Build(wDark, art);
            check(lDark.VoidTiles == 0 && lDark.Grid.TintR[5, 5] < 0.6f, "front live: a dark ground with nothing below is a dark floor");
            // an empty world: everything is a void
            var wEmpty = new World(art.Dat) { Center = new Pos(100, 100, 7) };
            var lEmpty = Build(wEmpty, art);
            check(lEmpty.VoidTiles == 320 && lEmpty.Upright.Count == 0, "front live: no tiles, all void");

            // ---- the world mapping ----
            var wM = Field(art, Grass);
            var lM = Build(wM, art, new Pos(90, 80, 7));
            var c0 = lM.TileToWorld(100, 100, 7);
            check(Near(c0.X, 100 - 90 + 0.5f) && Near(c0.Z, 80 - 100 - 0.5f) && Near(c0.Y, 0f), "front live: tile (100,100) is at x 10.5, z -20.5 with the anchor (90,80)");
            check(lM.TileToWorld(101, 100, 7).X - c0.X == 1f && lM.TileToWorld(100, 101, 7).Z - c0.Z == -1f, "front live: east is +x, south is -z, one unit a tile");
            var cb = lB.TileToWorld(100, 100, 10);
            check(Near(cb.X, 100 - 2 - 100 + 0.5f) && Near(cb.Z, 100 - (100 - 2) - 0.5f), "front live: a tile two floors below is drawn two tiles north-west");
            var la = Build(wM, art, new Pos(90, 80, 7));
            var lb = Build(wM, art, new Pos(95, 83, 7));
            var ta = FrontArtMesher.Terrain(la.Grid)[(int)FaTex.Grass];
            var tb = FrontArtMesher.Terrain(lb.Grid)[(int)FaTex.Grass];
            bool same = ta.Quads == tb.Quads && la.Grid.Top[7, 7] == lb.Grid.Top[7, 7];
            for (int i = 0; same && i < ta.V.Count; i += 3) same &= Near(ta.V[i] - tb.V[i], 5f) && Near(ta.V[i + 2] - tb.V[i + 2], -3f) && Near(ta.V[i + 1], tb.V[i + 1]);
            check(same, "front live: another anchor moves the whole mesh by the anchor's change and keeps the textures");
            bool texSame = true;
            for (int ty = la.Y0; ty <= la.Y1; ty++) for (int tx = la.X0; tx <= la.X1; tx++) texSame &= la.Grid.Top[tx - la.X0, la.Y1 - ty] == lb.Grid.Top[tx - lb.X0, lb.Y1 - ty];
            check(texSame, "front live: the texture of a tile does not depend on the anchor");
            // the window moves with the player: the same tile keeps its texture and variety
            var wS = Field(art, Stone, 100, 100);
            for (int y = 90; y <= 112; y++) for (int x = 90; x <= 115; x++) if (wS.Get(new Pos(x, y, 7)) == null) Put(wS, x, y, Stone);
            var l1 = Build(wS, art, new Pos(100, 100, 7));
            wS.Center = new Pos(103, 101, 7);
            var l2 = Build(wS, art, new Pos(100, 100, 7));
            bool keep = true;
            for (int ty = Math.Max(l1.Y0, l2.Y0); ty <= Math.Min(l1.Y1, l2.Y1); ty++) for (int tx = Math.Max(l1.X0, l2.X0); tx <= Math.Min(l1.X1, l2.X1); tx++) keep &= l1.Grid.Top[tx - l1.X0, l1.Y1 - ty] == l2.Grid.Top[tx - l2.X0, l2.Y1 - ty];
            check(keep, "front live: walking keeps the texture of each tile");

            // ---- tint ----
            var wT = Field(art, Grass);
            var lT = Build(wT, art);
            float tr = lT.Grid.TintR[5, 5], tg = lT.Grid.TintG[5, 5], tbl = lT.Grid.TintB[5, 5];
            check(tg > tr && tg > tbl && tr > 0.6f && tg < 1.31f, "front live: a green ground leans the block green (" + tr.ToString("0.00") + ", " + tg.ToString("0.00") + ", " + tbl.ToString("0.00") + ")");
            var tm = FrontArtMesher.Terrain(lT.Grid)[(int)FaTex.Grass];
            bool colours = false;
            for (int i = 0; i < tm.C.Count; i += 4) if (tm.C[i + 1] > tm.C[i] * 1.05f && tm.C[i + 1] > tm.C[i + 2] * 1.05f) colours = true;
            check(colours, "front live: the tint reaches the vertex colours");

            // ---- the rebuild hash ----
            var wR = Field(art, Grass);
            Put(wR, 100, 100, Potion);
            int h0 = FrontLive.ViewHash(wR);
            check(h0 == FrontLive.ViewHash(wR) && h0 == Build(wR, art).Hash, "front live: the hash of an unchanged view is stable and is kept in the layout");
            var hero = new Creature { Id = 1, Name = "Hero" };
            wR.AddThing(new Pos(101, 100, 7), new Thing { Creature = hero });
            wR.PlayerId = 1;
            check(FrontLive.ViewHash(wR) == h0, "front live: a creature does not change the hash");
            wR.RemoveCreature(hero);
            wR.AddThing(new Pos(104, 103, 7), new Thing { Creature = hero });
            check(FrontLive.ViewHash(wR) == h0, "front live: nor does it moving");
            Put(wR, 97, 97, Tree);
            int h1 = FrontLive.ViewHash(wR);
            check(h1 != h0, "front live: an item appearing changes the hash");
            wR.Get(new Pos(97, 97, 7)).Things.RemoveAt(wR.Get(new Pos(97, 97, 7)).Things.Count - 1);
            check(FrontLive.ViewHash(wR) == h0, "front live: and removing it brings the hash back");
            Put(wR, 40, 40, Tree);
            check(FrontLive.ViewHash(wR) == h0, "front live: a tile outside the window does not matter");
            wR.Center = new Pos(101, 100, 7);
            check(FrontLive.ViewHash(wR) != h0, "front live: walking a tile changes the hash");
            wR.Center = new Pos(100, 100, 7);
            Put(wR, 100, 100, Stone, 9);
            check(FrontLive.ViewHash(wR) != h0, "front live: a floor below the player's changes it where it shows through");
            wR.Get(new Pos(100, 100, 9)).Things.Clear();
            wR.Center = new Pos(100, 100, 7);
            long before = GC.GetAllocatedBytesForCurrentThread();
            int acc = 0;
            for (int i = 0; i < 2000; i++) acc ^= FrontLive.ViewHash(wR);
            long alloc = GC.GetAllocatedBytesForCurrentThread() - before;
            check(alloc == 0 && acc == 0, "front live: the hash allocates nothing: " + alloc + " bytes in 2000 calls");
            var sw = Stopwatch.StartNew();
            for (int i = 0; i < 2000; i++) acc ^= FrontLive.ViewHash(wR);
            double perHash = sw.Elapsed.TotalMilliseconds / 2000;
            check(perHash < 0.5, "front live: a hash of the window and two floors below takes " + perHash.ToString("0.0000") + " ms");

            // ---- the whole thing on a mixed map: size and time bounds ----
            var wX = new World(art.Dat) { Center = new Pos(100, 100, 7) };
            int[] grounds = { Grass, Grass, Grass, Dirt, Stone, Sand, Water, Wood, Snow };
            for (int y = 92; y <= 109; y++)
                for (int x = 90; x <= 111; x++)
                {
                    int g = grounds[H(x / 3, y / 3, 3) % grounds.Length];
                    Put(wX, x, y, g);
                    int r = H(x, y, 9) % 40;
                    if (g == Water) continue;
                    if (r == 0) Put(wX, x, y, Tree); else if (r == 1) Put(wX, x, y, Rock); else if (r == 2) Put(wX, x, y, WallGrey); else if (r == 3) Put(wX, x, y, Potion);
                    else if (r == 4) Put(wX, x, y, Torch); else if (r == 5) Put(wX, x, y, Table); else if (r == 6) Put(wX, x, y, Pillar); else if (r == 7) Put(wX, x, y, Blood);
                }
            var cx = new SpriteClassifier(art.Sprite);
            FrontLive.Build(wX, wX.Center, cx);   // measure every type once
            sw.Restart();
            FrontLiveLayout lX = null;
            for (int i = 0; i < 20; i++) lX = FrontLive.Build(wX, wX.Center, cx);
            double perBuild = sw.Elapsed.TotalMilliseconds / 20;
            sw.Restart();
            FaBucket[] terr = null, props = null;
            for (int i = 0; i < 20; i++) { terr = FrontArtMesher.Terrain(lX.Grid); props = FrontArtMesher.Boxes(lX.Grid.Boxes); }
            double perMesh = sw.Elapsed.TotalMilliseconds / 20;
            int quads = FrontArtMesher.TotalQuads(terr) + FrontArtMesher.TotalQuads(props);
            int spriteQuads = lX.Upright.Sum(p => p.Width * p.Height) + lX.Flat.Sum(p => p.Width * p.Height);
            check(perBuild < 25, "front live: laying out a mixed 20 x 16 window takes " + perBuild.ToString("0.00") + " ms (limit 25)");
            check(perMesh < 25, "front live: meshing it takes " + perMesh.ToString("0.00") + " ms (limit 25)");
            check(FrontArtMesher.TotalQuads(terr) <= 20 * 16 * 5 + 1, "front live: terrain quads stay under a top and four sides per tile: " + FrontArtMesher.TotalQuads(terr));
            check(quads < 6000 && spriteQuads < 1200, "front live: block quads " + quads + " (limit 6000), sprite quads " + spriteQuads + " (limit 1200)");
            check(lX.WallTiles > 0 && lX.WaterTiles > 0 && lX.Upright.Count > 0 && lX.Flat.Count > 0 && lX.Grid.Boxes.Count > 0 && lX.Lights.Count > 0, "front live: the mixed map has walls, water, sprites, decals, boxes and lights");
            Console.WriteLine("front live: build " + perBuild.ToString("0.00") + " ms, mesh " + perMesh.ToString("0.00") + " ms, " + quads + " block quads, " + spriteQuads + " sprite quads, " + lX.Lights.Count + " lights, hash " + perHash.ToString("0.0000") + " ms");

            // ---- the temple room of the demo (synthetic art): floors, walls, a pillar, torches, a carpet, two creatures ----
            var demo = Hd2dDemo.Synthetic();
            var dsc = new SpriteClassifier(id => new SprFile(new System.IO.MemoryStream(demo.SprBytes)).Rgba(id));
            var dl = FrontLive.Build(demo.World, demo.World.Center, dsc);
            check(dl.GroundTiles > 100 && dl.Lights.Count >= 1 && dl.Upright.Count + dl.Flat.Count + dl.Grid.Boxes.Count > 5, "front live: the demo room builds: " + dl.GroundTiles + " ground tiles, " + dl.Lights.Count + " lights, " + dl.Upright.Count + " upright, " + dl.Flat.Count + " flat, " + dl.Grid.Boxes.Count + " boxes");
            check(dl.Upright.All(p => p.Creature == null) && dl.Flat.All(p => p.Creature == null), "front live: creatures are never part of the layout");
            // the front-art layout still builds the way it did
            var fa = FrontArtLayout.Build();
            check(fa.OriginX == 0 && fa.OriginZ == 0 && fa.Void == null && FrontArtMesher.TotalQuads(FrontArtMesher.Terrain(fa)) > 340, "front live: the hand-made scene is unchanged by the origin, void and tint fields");
        }
    }
}
