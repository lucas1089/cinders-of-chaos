// Front-art live view (F8): the real map around the player in the front-art look. Pure C#, no Unity types, so it builds in Core.Tests.
// Unity/FrontLiveView.cs turns the result into meshes; this file decides what stands where and when to rebuild.
//
// The same recipe as Core/FrontArt.cs: a blocky diorama (a grid of tile blocks with heights of 0.5 units, hidden faces dropped, vertex
// ambient occlusion, procedural pixel textures) with upright front-facing sprites of the real art, warm point lights. What changes is
// where the picture comes from: the World the server fills, not a hand-made layout.
//
// Coordinates. World units, +x east, +z north, +y up, one tile is one unit. Tile (tx, ty) of the player's floor spans
// x in [tx - Anchor.X, +1] and z in [Anchor.Y - ty - 1, Anchor.Y - ty] (the same mapping as Hd2dCamera with origin = anchor). The anchor is
// fixed by the view for a long walk so the numbers stay small and the textures (mapped by world position) do not swim; the grid is a
// window of FrontArtLayout cells inside that space (OriginX, OriginZ). Grid cell (gx, gz) is tile (X0 + gx, Y1 - gz).
//
// The window is the area the client keeps (World.ForgetOutside): 8 left, 9 right, 6 up, 7 down of the player and one more tile round
// it, 20 x 16 tiles. A tile the server did not send is a void: no top, the neighbours' sides fall away into the dark (the slab's cut edge).
//
// Ground (class by pixels, Hd2dTerrain.Classify; the class picks the texture, the sprite's mean colour leans through as a tint):
//   Stone Flagstone (one in six Cobble)   Wood Wood   Grass Grass   Dirt Dirt (one in eight MossDirt)   Sand Sand   Snow Snow
//   Water Water, one level (0.5 units) lower   Lava Lava, one level lower, lit   Unknown Dirt   Dark a hole: the floor below, else a void
//   a ground item the dat marks not walkable and that reads Stone, Dirt or Unknown: a cliff, CliffLevels high
// Walls: an on-bottom blocking item raises its tile to a block. Height by how much of the cell the sprite fills (Alpha): 0.7 and up a full
//   wall (WallLevels), 0.45 and up a low wall, less a fence (2 levels); a green one (green share 0.4 and up) is a hedge (HedgeLevels, Grass).
//   The side texture comes from the colour: grey Flagstone, red-brown Brick, brown with lines Wood, pale yellow-brown Cobble.
// Items (Hd2d.Classify, then the role):
//   decal, or a loose one-cell thing that fills the tile (stairs, a hatch, a rug)          flat sprite on the block top
//   grey blocking loose: 1 x 1 rock (boxes), tall or wide pillar (boxes: base, shaft, capital, band)
//   brown blocking loose, two cells or more: big furniture (a wooden box and its lid)
//   everything else, light sources included                                                upright sprite of the real art
//   ground borders                                                                          dropped (hard tile edges)
// An upright sprite is front-facing in the plane through the middle of its tile, W cells wide going west from the east edge of its tile
//   and H cells high, straightened row by row when a lean profile is given (Hd2d.Lean, as the HD-2D view does).
// Lights: every item with a dat light attribute (level, colour index) becomes a FaLight at its tile: range and intensity from the level,
//   Flame for warm colours (flicker and embers in the view). The view lights the nearest few.
// Floors below: a tile without ground on the player's floor shows the tile of the floor below at the cell shifted by one tile south-east
//   (what the stock client draws), FloorLevels (3 units) lower, darker for each floor, ground and walls only; two floors at most.
// Not done: stairs and ramps (the dat does not tell which item changes the floor: they stay sprites), doors as doors (a closed door is a wall
//   block, an open one a flat sprite), animated water (the view scrolls the water texture), roofs and floors above.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    /// <summary>The numbers of the live view in one place.</summary>
    public sealed class FrontLiveOptions
    {
        /// <summary>Block heights in levels of 0.5 units.</summary>
        public int WallLevels = 5, LowWallLevels = 3, FenceLevels = 2, HedgeLevels = 2, CliffLevels = 4, WaterLevels = -1, FloorLevels = 6;
        /// <summary>Floors below shown through holes.</summary>
        public int Below = 2;
        /// <summary>Tiles of window beyond the 20 x 16 the client keeps (tests).</summary>
        public int Extra = 0;
        /// <summary>World height of one cell of an upright sprite (1: as drawn, 32 texels a unit).</summary>
        public float Stretch = 1f;
    }

    /// <summary>What an item of a tile becomes (FrontLive.RoleOf).</summary>
    public enum LiveRole { Skip, Flat, Upright, Rock, Pillar, Furniture }

    /// <summary>The result of one build: the grid, the sprites, the lights.</summary>
    public sealed class FrontLiveLayout
    {
        public FrontArtLayout Grid;                 // terrain (heights, textures, tints, voids) and the boxes of props
        public readonly List<Hd2dPiece> Upright = new List<Hd2dPiece>();   // front-facing sprites (item pieces: Item, Type, Right, Z, Y, Width, Height)
        public readonly List<Hd2dPiece> Flat = new List<Hd2dPiece>();      // sprites lying on a block top
        public readonly List<FaLight> Lights = new List<FaLight>();
        public Pos Anchor;
        public int X0, Y0, X1, Y1, Floor;           // the window in tiles, the player's floor
        public int Hash;                            // FrontLive.ViewHash when it was built
        public int WallTiles, HedgeTiles, CliffTiles, WaterTiles, LavaTiles, LowerTiles, VoidTiles, GroundTiles;
        public bool Animated;                       // some sprite has phases: the view refreshes the sprite mesh now and then

        public float FloorLevelUnits = 6 * FrontArtLayout.Level;

        public bool InWindow(int tx, int ty) { return tx >= X0 && tx <= X1 && ty >= Y0 && ty <= Y1; }

        /// <summary>Top of the block of tile (tx, ty) on the player's floor, in units; 0 outside the window.</summary>
        public float GroundY(int tx, int ty)
        {
            if (!InWindow(tx, ty)) return 0f;
            int gx = tx - X0, gz = Y1 - ty;
            return Grid.IsVoid(gx, gz) ? FrontArtLayout.OuterLevels * FrontArtLayout.Level : Grid.H[gx, gz] * FrontArtLayout.Level;
        }

        /// <summary>Centre of a tile at its ground height. A tile on another floor is drawn shifted one tile north-west per floor
        /// it lies below, `FloorLevelUnits` lower.</summary>
        public Vec3 TileToWorld(int tx, int ty, int z)
        {
            int k = z - Floor;
            int cx = tx - k, cy = ty - k;
            float y = k == 0 ? GroundY(tx, ty) : (InWindow(cx, cy) ? GroundY(cx, cy) : -k * FloorLevelUnits);
            return new Vec3(cx - Anchor.X + 0.5f, y, Anchor.Y - cy - 0.5f);
        }
    }

    public static class FrontLive
    {
        public const float Level = FrontArtLayout.Level;
        /// <summary>A flat sprite lies this far above its block's top; a light hangs this far above the floor.</summary>
        public const float FlatLift = 0.012f, LightHeight = 1.15f;
        public const float WallAlpha = 0.7f, LowWallAlpha = 0.45f, HedgeGreen = 0.4f, FillAlpha = 0.85f;
        /// <summary>The most lights a layout keeps (the view picks the nearest few each frame).</summary>
        public const int MaxLights = 96;

        // ---- the window -------------------------------------------------------------------------------------------------

        /// <summary>The tiles of the window round the player: what the client keeps, plus Extra.</summary>
        public static void Window(World w, FrontLiveOptions o, out int x0, out int y0, out int x1, out int y1)
        {
            var c = w.Center;
            int e = o == null ? 0 : o.Extra;
            x0 = c.X - World.RangeLeft - 1 - e; x1 = c.X + World.RangeRight + 1 + e;
            y0 = c.Y - World.RangeTop - 1 - e; y1 = c.Y + World.RangeBottom + 1 + e;
        }

        /// <summary>The world position of a (fractional) tile position: its middle, x east, z north.</summary>
        public static Vec3 ToWorld(Pos anchor, float tileX, float tileY, float y)
        {
            return new Vec3(tileX - anchor.X + 0.5f, y, anchor.Y - tileY - 0.5f);
        }

        // ---- when to rebuild ---------------------------------------------------------------------------------------------

        /// <summary>A cheap hash of what the layout reads: the centre, and per tile of the window (and of the floors below, where they show
        /// through) its position and the ids of its items. Creatures are not read. No allocation.</summary>
        public static int ViewHash(World w, FrontLiveOptions o = null)
        {
            Window(w, o, out int x0, out int y0, out int x1, out int y1);
            var c = w.Center;
            int below = o == null ? 2 : o.Below;
            unchecked
            {
                int h = (int)2166136261u;
                h = (h ^ c.X) * 16777619; h = (h ^ c.Y) * 16777619; h = (h ^ c.Z) * 16777619;
                for (int k = 0; k <= below; k++)
                    for (int y = y0; y <= y1; y++)
                        for (int x = x0; x <= x1; x++)
                        {
                            if (!w.Tiles.TryGetValue(new Pos(x + k, y + k, c.Z + k), out var tile)) continue;
                            h = (h ^ (x * 73856093 ^ y * 19349663 ^ k * 83492791)) * 16777619;
                            var things = tile.Things;
                            for (int i = 0; i < things.Count; i++)
                                if (!things[i].IsCreature && things[i].Item != null) h = (h ^ things[i].Item.Id) * 16777619;
                        }
                return h;
            }
        }

        // ---- the colours of sprites --------------------------------------------------------------------------------------

        /// <summary>The wall side texture a sprite's colours say.</summary>
        public static FaTex WallTex(SpriteStats s)
        {
            if (s.Sat < 0.2f) return FaTex.Flagstone;
            if ((s.Hue <= 22f || s.Hue >= 340f) && s.Sat >= 0.3f) return FaTex.Brick;
            if (s.Hue < 65f)
            {
                if (s.Value >= 0.62f && s.Sat < 0.65f) return FaTex.Cobble;
                return s.Grain >= 0.3f ? FaTex.Wood : FaTex.Brick;
            }
            return FaTex.Flagstone;
        }

        /// <summary>The block's tint: the sprite's colour as a lean away from grey, a third of the way.</summary>
        public static void Tint(SpriteStats s, float shade, out float r, out float g, out float b)
        {
            float l = Math.Max(0.05f, StatsBuilder.Luma(s.R, s.G, s.B));
            r = Lean(s.R / l); g = Lean(s.G / l); b = Lean(s.B / l);
            r *= shade; g *= shade; b *= shade;
        }

        static float Lean(float ratio) { float v = 1f + (ratio - 1f) * 0.3f; return v < 0.7f ? 0.7f : v > 1.3f ? 1.3f : v; }

        public static int Hash(int x, int y, int salt)
        {
            unchecked
            {
                uint h = (uint)x * 374761393u + (uint)y * 668265263u + (uint)salt * 2246822519u + 0x9E3779B9u;
                h = (h ^ (h >> 13)) * 1274126177u;
                return (int)((h ^ (h >> 16)) & 0x7fffffff);
            }
        }

        // ---- one tile column ---------------------------------------------------------------------------------------------

        struct Col
        {
            public bool Has, Hole;
            public GroundClass Class;
            public SpriteStats Ground;      // the ground sprite's stats
            public int Wall;                // levels of a wall, hedge or fence on the tile; 0 none
            public bool Hedge;
            public SpriteStats WallStats;
            public bool Cliff;
            public int LightLevel, LightColor;   // of the ground (lava)
        }

        static Col Column(World w, SpriteClassifier cls, int tx, int ty, int z, FrontLiveOptions o)
        {
            var col = new Col();
            var tile = w.Get(new Pos(tx, ty, z));
            if (tile == null) return col;
            ThingType ground = null;
            for (int i = 0; i < tile.Things.Count; i++)
            {
                var th = tile.Things[i];
                if (th.IsCreature || th.Item == null || th.Item.Type == null) continue;
                var t = th.Item.Type;
                if (t.Ground && ground == null) ground = t;
                else if (!t.Ground && t.OnBottom && Hd2d.Blocking(t))
                {
                    var info = cls.Info(t);
                    var s = info.Stats;
                    int lv;
                    bool hedge = s.GreenShare >= HedgeGreen;
                    if (hedge) lv = o.HedgeLevels;
                    else if (s.Alpha >= WallAlpha) lv = o.WallLevels;
                    else if (s.Alpha >= LowWallAlpha) lv = o.LowWallLevels;
                    else lv = o.FenceLevels;
                    if (lv > col.Wall) { col.Wall = lv; col.Hedge = hedge; col.WallStats = s; }
                }
            }
            if (ground == null) return col;
            col.Has = true;
            var gi = cls.Info(ground);
            col.Ground = gi.Stats;
            col.Class = gi.Class;
            col.Hole = gi.Class == GroundClass.Dark;
            col.Cliff = ground.NotWalkable && (gi.Class == GroundClass.Stone || gi.Class == GroundClass.Dirt || gi.Class == GroundClass.Unknown);
            col.LightLevel = ground.LightLevel; col.LightColor = ground.LightColor;
            return col;
        }

        static void TopOf(Col c, int tx, int ty, out FaTex top, out FaTex side)
        {
            int h = Hash(tx, ty, 5);
            switch (c.Class)
            {
                case GroundClass.Stone: top = h % 6 == 0 ? FaTex.Cobble : FaTex.Flagstone; side = FaTex.Brick; break;
                case GroundClass.Wood: top = FaTex.Wood; side = FaTex.Wood; break;
                case GroundClass.Grass: top = FaTex.Grass; side = FaTex.MossDirt; break;
                case GroundClass.Sand: top = FaTex.Sand; side = FaTex.Sand; break;
                case GroundClass.Snow: top = FaTex.Snow; side = FaTex.Snow; break;
                case GroundClass.Water: top = FaTex.Water; side = FaTex.MossDirt; break;
                case GroundClass.Lava: top = FaTex.Lava; side = FaTex.Cobble; break;
                case GroundClass.Dark: top = FaTex.Flagstone; side = FaTex.Brick; break;
                default: top = h % 8 == 0 ? FaTex.MossDirt : FaTex.Dirt; side = FaTex.MossDirt; break;
            }
        }

        // ---- the build ---------------------------------------------------------------------------------------------------

        /// <summary>Lays out the window around the player. `lean` (type, outfit) gives a thing's measured lean profile (Hd2d.Lean), or null.</summary>
        public static FrontLiveLayout Build(World w, Pos anchor, SpriteClassifier cls, FrontLiveOptions o = null, Func<ThingType, bool, float[]> lean = null)
        {
            o = o ?? new FrontLiveOptions();
            Window(w, o, out int x0, out int y0, out int x1, out int y1);
            int W = x1 - x0 + 1, D = y1 - y0 + 1, z = w.Center.Z;
            var L = new FrontArtLayout(W, D)
            {
                OriginX = x0 - anchor.X, OriginZ = anchor.Y - y1 - 1, OuterTex = FaTex.Dirt,
                Void = new bool[W, D], TintR = new float[W, D], TintG = new float[W, D], TintB = new float[W, D],
            };
            var res = new FrontLiveLayout { Grid = L, Anchor = anchor, X0 = x0, Y0 = y0, X1 = x1, Y1 = y1, Floor = z, Hash = ViewHash(w, o), FloorLevelUnits = o.FloorLevels * Level };
            var cols = new bool[W, D];   // the tile has ground on the player's floor (items stand on it)
            for (int ty = y0; ty <= y1; ty++)
                for (int tx = x0; tx <= x1; tx++)
                {
                    int gx = tx - x0, gz = y1 - ty;
                    var c = Column(w, cls, tx, ty, z, o);
                    int below = 0;
                    if (!c.Has || c.Hole)
                    {
                        // a hole or no tile: the floor below shows, a tile south-east of the cell, a floor lower
                        bool found = false;
                        for (int k = 1; k <= o.Below && !found; k++)
                        {
                            var cb = Column(w, cls, tx + k, ty + k, z + k, o);
                            if (cb.Has && !cb.Hole) { c = cb; below = k; found = true; }
                        }
                        if (!found)
                        {
                            if (c.Has) { /* a dark hole with nothing below: a dark floor tile */ }
                            else { L.Void[gx, gz] = true; L.TintR[gx, gz] = L.TintG[gx, gz] = L.TintB[gx, gz] = 1f; res.VoidTiles++; continue; }
                        }
                    }
                    PlaceColumn(L, res, c, tx, ty, gx, gz, below, o);
                    cols[gx, gz] = below == 0;
                }
            // the things standing on the tiles of the player's floor
            var tmp = new List<Hd2dPiece>();
            for (int ty = y0; ty <= y1; ty++)
                for (int tx = x0; tx <= x1; tx++)
                {
                    int gx = tx - x0, gz = y1 - ty;
                    if (!cols[gx, gz]) continue;
                    var tile = w.Get(new Pos(tx, ty, z));
                    if (tile == null) continue;
                    float top = L.H[gx, gz] * Level;
                    tmp.Clear();
                    Hd2d.LayoutTile(w.Dat, tile, anchor, o.Stretch, tmp, null, true, lean);
                    foreach (var p in tmp)
                    {
                        if (p.Creature != null || p.Item == null || p.Type == null) continue;
                        var t = p.Type;
                        if (t.LightLevel > 0 && res.Lights.Count < MaxLights) AddLight(res, p, top, tx, ty);
                        switch (RoleOf(p, cls))
                        {
                            case LiveRole.Skip: break;
                            case LiveRole.Flat:
                                if (!p.Flat)
                                {
                                    // a loose thing that fills its tile (stairs, a hatch) lies on the floor like a decal
                                    p.Kind = Hd2dKind.Decal;
                                    p.Z = Hd2d.WorldZ(anchor, ty) + t.DisplacementY / 32f;
                                    p.Y = Hd2d.StackBias * p.StackIndex;
                                }
                                p.Y += top + FlatLift;
                                res.Flat.Add(p);
                                break;
                            case LiveRole.Upright:
                                p.Y += top;
                                p.Z = Hd2d.WorldZ(anchor, ty) - 0.5f - Hd2d.StackBias * p.StackIndex;
                                res.Upright.Add(p);
                                if (t.Idle.Phases > 1) res.Animated = true;
                                break;
                            case LiveRole.Rock: AddRock(L, anchor, top, tx, ty); break;
                            case LiveRole.Pillar: AddPillar(L, anchor, p, top, tx, ty); break;
                            case LiveRole.Furniture: AddFurniture(L, anchor, p, top, tx, ty); break;
                        }
                    }
                }
            return res;
        }

        static void PlaceColumn(FrontArtLayout L, FrontLiveLayout res, Col c, int tx, int ty, int gx, int gz, int below, FrontLiveOptions o)
        {
            FaTex top, side;
            TopOf(c, tx, ty, out top, out side);
            int level = 0;
            float shade = below == 0 ? 1f : (float)Math.Pow(0.55, below);
            var stats = c.Ground;
            if (c.Class == GroundClass.Water) { level = o.WaterLevels; res.WaterTiles++; }
            else if (c.Class == GroundClass.Lava) { level = o.WaterLevels; res.LavaTiles++; }
            else if (c.Cliff) { level = o.CliffLevels; res.CliffTiles++; side = top == FaTex.Dirt || top == FaTex.MossDirt ? FaTex.MossDirt : FaTex.Flagstone; }
            if (c.Class == GroundClass.Dark) shade *= 0.4f;
            if (c.Wall > 0)
            {
                level = Math.Max(level, c.Wall);
                if (c.Hedge) { top = FaTex.Grass; side = FaTex.Grass; stats = c.WallStats; res.HedgeTiles++; }
                else
                {
                    side = WallTex(c.WallStats);
                    top = side == FaTex.Wood ? FaTex.Wood : FaTex.Flagstone;
                    stats = c.WallStats;
                    res.WallTiles++;
                }
                L.Masonry[gx, gz] = !c.Hedge;
            }
            if (below > 0) { level -= below * o.FloorLevels; res.LowerTiles++; }
            else res.GroundTiles++;
            L.H[gx, gz] = level;
            L.Top[gx, gz] = top; L.Side[gx, gz] = side;
            if (c.Class == GroundClass.Water || c.Class == GroundClass.Lava) { L.TintR[gx, gz] = L.TintG[gx, gz] = L.TintB[gx, gz] = shade; }
            else { Tint(stats, shade, out float r, out float g, out float b); L.TintR[gx, gz] = r; L.TintG[gx, gz] = g; L.TintB[gx, gz] = b; }
        }

        // ---- roles of items ----------------------------------------------------------------------------------------------

        /// <summary>What an item piece becomes (see the file comment).</summary>
        public static LiveRole RoleOf(Hd2dPiece p, SpriteClassifier cls)
        {
            var t = p.Type;
            if (t == null || p.Creature != null) return LiveRole.Skip;
            if (t.Ground || p.Kind == Hd2dKind.Floor || p.Kind == Hd2dKind.Border || p.Kind == Hd2dKind.None) return LiveRole.Skip;
            if (p.Kind == Hd2dKind.Decal) return LiveRole.Flat;
            bool blocking = Hd2d.Blocking(t);
            if (t.OnBottom && blocking) return LiveRole.Skip;   // a wall: its tile became a block
            var s = cls.Info(t).Stats;
            bool loose = !t.Pickupable && !t.Container && !t.Stackable;
            int w = Math.Max(1, p.Width), h = Math.Max(1, p.Height);
            if (t.LightLevel > 0) return LiveRole.Upright;
            bool green = s.GreenShare >= 0.3f;
            if (loose && !blocking && t.Elevation == 0 && w * h == 1 && s.Alpha >= FillAlpha && !green && !t.OnTop) return LiveRole.Flat;
            if (loose && blocking && !green)
            {
                if (s.GreyShare >= 0.5f)
                {
                    if (w * h == 1) return LiveRole.Rock;
                    return w <= 2 && h >= 2 ? LiveRole.Pillar : LiveRole.Furniture;
                }
                if (w * h >= 2 && (s.BrownShare >= 0.3f || (s.Hue >= 8f && s.Hue <= 50f && s.Sat >= 0.25f))) return LiveRole.Furniture;
            }
            return LiveRole.Upright;
        }

        // ---- boxes -------------------------------------------------------------------------------------------------------

        static FaBox Box(FaTex tex, float cx, float y0, float cz, float sx, float sy, float sz, float yaw, float tint, int seed, string tag)
        {
            return new FaBox { X0 = cx - sx / 2, X1 = cx + sx / 2, Z0 = cz - sz / 2, Z1 = cz + sz / 2, Y0 = y0, Y1 = y0 + sy, Yaw = yaw, Tex = tex, R = tint, G = tint, B = tint, Seed = seed, Tag = tag };
        }

        static float Rnd(int h, int k) { return ((h >> k) % 1000) / 1000f; }

        static void Centre(Hd2dPiece p, Pos anchor, int tx, int ty, out float cx, out float cz)
        {
            cx = p.Right - Math.Max(1, p.Width) / 2f;
            cz = Hd2d.WorldZ(anchor, ty) - 0.5f;
        }

        static void AddRock(FrontArtLayout L, Pos anchor, float top, int tx, int ty)
        {
            int h = Hash(tx, ty, 41);
            float cx = tx - anchor.X + 0.5f, cz = anchor.Y - ty - 0.5f;
            var tex = h % 3 == 0 ? FaTex.Cobble : FaTex.Flagstone;
            float s = 0.55f + 0.2f * Rnd(h, 3);
            L.Boxes.Add(Box(tex, cx - 0.06f, top, cz, s * 1.15f, s * 0.75f, s, Rnd(h, 5) * 90f, 0.8f, h, "rock"));
            L.Boxes.Add(Box(tex, cx + 0.22f, top, cz - 0.16f, s * 0.6f, s * 0.5f, s * 0.55f, Rnd(h, 7) * 90f, 0.7f, h + 1, "rock"));
            L.Boxes.Add(Box(FaTex.Flagstone, cx - 0.04f, top + s * 0.75f, cz, s * 0.55f, s * 0.28f, s * 0.5f, Rnd(h, 9) * 90f, 0.85f, h + 2, "rock"));
        }

        static void AddPillar(FrontArtLayout L, Pos anchor, Hd2dPiece p, float top, int tx, int ty)
        {
            int h = Hash(tx, ty, 43);
            float cx = tx - anchor.X + 0.5f, cz = anchor.Y - ty - 0.5f;
            float height = Math.Min(3.4f, Math.Max(1.6f, 0.8f * Math.Max(1, p.Height) + 0.4f));
            float shaft = height - 0.30f - 0.28f;
            L.Boxes.Add(Box(FaTex.Brick, cx, top, cz, 1.05f, 0.30f, 1.05f, 0f, 0.9f, h, "pillar"));
            L.Boxes.Add(Box(FaTex.Brick, cx, top + 0.30f, cz, 0.78f, shaft, 0.78f, 0f, 1f, h + 1, "pillar"));
            L.Boxes.Add(Box(FaTex.Flagstone, cx, top + 0.30f + shaft, cz, 1.0f, 0.28f, 1.0f, 0f, 0.95f, h + 2, "pillar"));
            L.Boxes.Add(Box(FaTex.Brick, cx, top + 0.30f + shaft * 0.45f, cz, 0.9f, 0.14f, 0.9f, 0f, 0.8f, h + 3, "pillar"));
        }

        static void AddFurniture(FrontArtLayout L, Pos anchor, Hd2dPiece p, float top, int tx, int ty)
        {
            int h = Hash(tx, ty, 47);
            Centre(p, anchor, tx, ty, out float cx, out float cz);
            int w = Math.Max(1, p.Width), hh = Math.Max(1, p.Height);
            float sx = Math.Min(2.6f, 0.9f * w), sz = w >= 2 ? 0.95f : 0.75f;
            float sy = Math.Max(0.5f, Math.Min(1.9f, 0.55f * hh + 0.25f));
            var tex = FaTex.Wood;
            L.Boxes.Add(Box(tex, cx, top, cz, sx, sy, sz, 0f, 0.85f, h, "furniture"));
            L.Boxes.Add(Box(tex, cx, top + sy, cz, sx + 0.1f, 0.08f, sz + 0.1f, 0f, 1.0f, h + 1, "furniture"));
        }

        // ---- lights ------------------------------------------------------------------------------------------------------

        static FaLight MakeLight(Pos anchor, int tx, int ty, float y, int r, int g, int b, int level, int seed)
        {
            float range = Math.Max(3f, Math.Min(8f, level * 0.85f + 2f));
            float intensity = Math.Max(0.6f, Math.Min(1.6f, 0.55f + level * 0.12f));
            var c = ToWorld(anchor, tx, ty, y);
            bool flame = r >= 153 && r > b + 38;   // Hd2d.IsFlame: red at 0.6 or more and clearly above blue
            return new FaLight { X = c.X, Y = c.Y, Z = c.Z, R = r / 255f, G = g / 255f, B = b / 255f, Range = range, Intensity = intensity, Flame = flame, Seed = seed };
        }

        static void AddLight(FrontLiveLayout res, Hd2dPiece p, float top, int tx, int ty)
        {
            var t = p.Type;
            Hd2d.ColorFromIndex(t.LightColor, out int r, out int g, out int b);
            if (r + g + b == 0) { r = g = b = 255; }
            float y = top + LightHeight + t.Elevation / 32f;
            res.Lights.Add(MakeLight(res.Anchor, tx, ty, y, r, g, b, t.LightLevel, Hash(tx, ty, 61)));
        }
    }
}
