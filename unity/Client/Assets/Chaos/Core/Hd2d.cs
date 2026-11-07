// HD-2D scene layout (O432): the same pixel-art sprites placed in a 3D scene. Pure C#, no Unity types, so it builds in
// Core.Tests. The Unity side (Unity/Hd2dView.cs) turns the pieces into quads; unity/tools/hd2d_preview.py ports the
// classification and light rules for the offline preview: keep the two in sync.
//
// World space: x east, y up, z north, one unit = one tile, the origin is the tile `origin` (its west edge at x 0, its
// north edge at z 0). Tile (tx, ty) spans x in [tx - ox, tx - ox + 1] and z in [-(ty - oy) - 1, -(ty - oy)].
//
// Classification of a stack entry (Hd2d.Classify), from the dat flags the Things reader exposes:
//   ground                           -> Floor      flat quad on the floor
//   ground border                    -> Border     flat quad, a hair above the ground
//   fluid, splash, lying             -> Decal      flat quad (blood, puddles, corpses)
//   on-bottom and walkable           -> Decal      flat (paths, carpets that are on-bottom items)
//   on-bottom and not walkable /
//     block-path                     -> Billboard  wall-like: upright, at the tile's back (north) edge
//   on-top                           -> OnTop      upright, tile middle, drawn over creatures
//   common item, large (more than one cell), not pickupable, not blocking, no light, not stackable, no elevation
//                                    -> Decal      carpets, mosaics, big stains: they lie on the floor
//   other common item: blocking      -> Billboard  at the back edge (pillars, statues, trees)
//                      not blocking  -> Object     upright, tile middle (barrels, bags, torches on a stand)
//   creature                         -> Creature   upright, tile middle
// Upright things are billboards: a vertical quad facing the camera. Their footprint is their own tile: a sprite of W x H
// cells is drawn as in the classic view, anchored on the tile's east edge and extending west (x) and up (height), the
// way a 64 px item is drawn up and to the left. The height is stretched by 1 / cos(pitch) so that the sprite keeps its
// height on screen under the tilted camera (the floor is foreshortened on purpose, that is the look).
// The classic sprites draw height going up and to the left (about one tile west per tile up). Every upright quad is cut
// into strips (Hd2d.Strips per cell) moved east as they rise by the lean profile of its own art (Hd2dPiece.Lean, measured
// by Hd2d.Lean: the middle of each height over the base), creatures included, so walls, pillars, torches and figures stand
// straight in 3D with their top over their base. Without a measurement (the tests,
// the synthetic demo) the fixed rule ShearFor applies: one tile per cell for 2 x 2 walls and pillars.
// Displacement (dat) moves a thing west by dx / 32 and up by dy / 32; elevation lifts the things above it in the stack.
// Only the player's floor is laid out (no floors above or below).
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public struct Vec3
    {
        public float X, Y, Z;
        public Vec3(float x, float y, float z) { X = x; Y = y; Z = z; }
        public static Vec3 operator +(Vec3 a, Vec3 b) => new Vec3(a.X + b.X, a.Y + b.Y, a.Z + b.Z);
        public static Vec3 operator -(Vec3 a, Vec3 b) => new Vec3(a.X - b.X, a.Y - b.Y, a.Z - b.Z);
        public static Vec3 operator *(Vec3 a, float k) => new Vec3(a.X * k, a.Y * k, a.Z * k);
        public static float Dot(Vec3 a, Vec3 b) => a.X * b.X + a.Y * b.Y + a.Z * b.Z;
        public float Length => (float)Math.Sqrt(Dot(this, this));
        public override string ToString() => "(" + X.ToString("0.###") + ", " + Y.ToString("0.###") + ", " + Z.ToString("0.###") + ")";
    }

    public enum Hd2dKind { None, Floor, Border, Decal, Billboard, Object, OnTop, Creature }

    /// <summary>One thing of a tile stack, placed in world space. A W x H thing has W x H cells (see Cell).</summary>
    public sealed class Hd2dPiece
    {
        public Hd2dKind Kind;
        public Item Item;           // set for items
        public Creature Creature;   // set for creatures
        public ThingType Type;      // the item's or the outfit's type
        public Pos Tile;
        public int StackIndex;
        public float Right;         // x of the east edge of the anchor cell
        public float Z;             // flat: the north edge of the anchor cell; upright: the plane the quad stands in
        public float Y;             // height of the base
        public int Width = 1, Height = 1;
        public float Stretch = 1f;  // upright: world height of one cell
        public float Shear;         // upright: tiles east per cell of height (undoes the classic up-left slant), 0 or 1
        public float[] Lean;        // upright: measured offsets east per strip boundary (Hd2d.Lean); overrides Shear

        /// <summary>How far east the art at `cells` cells up is moved (Lean, else Shear).</summary>
        public float OffsetAt(float cells)
        {
            if (Lean == null) return cells * Shear;
            float f = cells * Hd2d.Strips;
            if (f <= 0) return 0f;
            int last = Lean.Length - 1;
            if (f >= last) return Lean[last];
            int i = (int)f;
            return Lean[i] + (Lean[i + 1] - Lean[i]) * (f - i);
        }

        public bool Flat => Kind == Hd2dKind.Floor || Kind == Hd2dKind.Border || Kind == Hd2dKind.Decal;
        public bool CastsShadow => !Flat;

        /// <summary>The four corners of cell (w, h) of the thing: bottom-left, bottom-right, top-right, top-left, seen from
        /// the camera (south of the scene). Cell (0, 0) is the anchor cell; w grows west, h grows up (north when flat).</summary>
        public Vec3[] Cell(int w, int h)
        {
            float east = Right - w, west = east - 1f;
            if (Flat)
            {
                float north = Z + h, south = north - 1f;
                return new[] { new Vec3(west, Y, south), new Vec3(east, Y, south), new Vec3(east, Y, north), new Vec3(west, Y, north) };
            }
            return Strip(w, h, 0, 1);
        }

        /// <summary>Strip k of n (from the bottom) of upright cell (w, h): the quad moves east as it rises (OffsetAt), so the
        /// sprite's slant comes out upright.</summary>
        public Vec3[] Strip(int w, int h, int k, int n)
        {
            float east = Right - w, west = east - 1f;
            float c0 = h + k / (float)n, c1 = h + (k + 1) / (float)n;
            float y0 = Y + c0 * Stretch, y1 = Y + c1 * Stretch;
            float s0 = OffsetAt(c0), s1 = OffsetAt(c1);
            return new[] { new Vec3(west + s0, y0, Z), new Vec3(east + s0, y0, Z), new Vec3(east + s1, y1, Z), new Vec3(west + s1, y1, Z) };
        }

        /// <summary>The middle of the thing's footprint and body: the point a light or a name label hangs on.</summary>
        public Vec3 Center => Flat
            ? new Vec3(Right - Width / 2f, Y, Z - Height / 2f)
            : new Vec3(Right - Width / 2f + OffsetAt(Height / 2f), Y + Height * Stretch / 2f, Z);
    }

    public struct Hd2dLight
    {
        public Vec3 Position;
        public float R, G, B;       // 0..1
        public float Range;         // tiles
        public float Intensity;
        public override string ToString() => "light " + Position + " rgb " + R.ToString("0.##") + "," + G.ToString("0.##") + "," + B.ToString("0.##") + " range " + Range;
    }

    public static class Hd2d
    {
        /// <summary>Depth of a blocking upright thing inside its tile: 0 is the back (north) edge, 1 the front edge.</summary>
        public const float BackEdge = 0f, TileMiddle = 0.5f;
        /// <summary>A light sits this far in front of the wall it hangs on, or the wall would only be lit edge on.</summary>
        public const float LightForward = 0.4f;
        public const float StackBias = 0.0015f;

        public static bool Blocking(ThingType t) => t.NotWalkable || t.BlockPath;

        /// <summary>The kind of an item type (see the file comment). None for a null type.</summary>
        public static Hd2dKind Classify(ThingType t)
        {
            if (t == null) return Hd2dKind.None;
            if (t.Ground) return Hd2dKind.Floor;
            if (t.GroundBorder) return Hd2dKind.Border;
            if (t.Fluid || t.Splash || t.Lying) return Hd2dKind.Decal;
            if (t.OnBottom) return Blocking(t) ? Hd2dKind.Billboard : Hd2dKind.Decal;
            if (t.OnTop) return Hd2dKind.OnTop;
            var g = t.Idle;
            bool large = g.Width * g.Height > 1;
            if (large && !t.Pickupable && !Blocking(t) && !t.BlockMissile && !t.Container && !t.Stackable && t.Elevation == 0 && t.LightLevel == 0)
                return Hd2dKind.Decal;
            return Blocking(t) ? Hd2dKind.Billboard : Hd2dKind.Object;
        }

        /// <summary>The shear of an upright piece: 1 for architecture (a blocking or on-top thing: walls, pillars, arches) at
        /// least two cells wide and high, whose art climbs up-left across cells; else 0. LayoutTile also leaves a light source unsheared
        /// unless it hangs on a sheared wall of its tile. A one-cell-wide sprite stands straight
        /// in its column; loose objects (a standing torch) keep their art, which often leans on purpose.</summary>
        public static float ShearFor(Hd2dKind kind, int width, int height) =>
            width > 1 && height > 1 && (kind == Hd2dKind.Billboard || kind == Hd2dKind.OnTop) ? 1f : 0f;

        public const float MaxSlant = 1.25f;
        /// <summary>Strips per cell of an upright quad: the lean is straightened in steps of 32 / Strips pixels.</summary>
        public const int Strips = 4;

        /// <summary>The lean profile of a thing's art, measured on its first idle frame (layer 0; an outfit facing south): for
        /// each strip boundary (Strips per cell, from the bottom) how far east, in tiles, that height is moved so the middle of
        /// the art sits over its base. The classic art draws height up and to the left; straightened row by row, a pillar,
        /// a torch on its pole and a figure all stand up. Never leans back, at most MaxSlant tiles per tile up; null when the
        /// art is too small to tell. `sprite` gives a sprite's 32 x 32 RGBA, or null.</summary>
        public static float[] Lean(ThingType t, bool outfit, Func<uint, byte[]> sprite)
        {
            if (t == null || t.Idle == null || t.Idle.Sprites == null) return null;
            var g = t.Idle;
            int W = g.Width, H = g.Height, ih = H * 32;
            int px = outfit ? Math.Min(2, g.PatternX - 1) : 0;
            var rowSum = new double[ih];
            var rowCount = new int[ih];
            for (int hh = 0; hh < H; hh++)
                for (int ww = 0; ww < W; ww++)
                {
                    var rgba = sprite(g.Sprite(ww, hh, 0, px, 0, 0, 0));
                    if (rgba == null) continue;
                    int ox = (W - 1 - ww) * 32, oy = (H - 1 - hh) * 32;
                    for (int y = 0; y < 32; y++)
                        for (int x = 0; x < 32; x++)
                            if (rgba[(y * 32 + x) * 4 + 3] >= 128) { rowSum[oy + y] += ox + x; rowCount[oy + y]++; }
                }
            return LeanOfRows(rowSum, rowCount);
        }

        /// <summary>The profile behind Lean: per image row (top first, 32 rows per cell) the sum of the x of its opaque pixels
        /// and their count. Returns cells * Strips + 1 offsets, the first 0.</summary>
        public static float[] LeanOfRows(double[] rowSum, int[] rowCount)
        {
            int ih = rowCount.Length, cells = Math.Max(1, ih / 32), n = cells * Strips;
            int bottom = -1, rows = 0;
            for (int y = 0; y < ih; y++) if (rowCount[y] > 0) { bottom = y; rows++; }
            if (rows < 12) return null;
            // the base: the middle of the lowest 6 opaque rows
            double bs = 0, bc = 0;
            for (int y = Math.Max(0, bottom - 5); y <= bottom; y++) { bs += rowSum[y]; bc += rowCount[y]; }
            double baseX = bs / bc;
            const int window = 4, step = 32 / Strips;
            var off = new float[n + 1];
            float prev = 0f;
            for (int j = 1; j <= n; j++)
            {
                int yc = ih - 1 - j * step;   // the image row at this boundary
                double s = 0, c = 0;
                for (int y = Math.Max(0, yc - window); y <= Math.Min(ih - 1, yc + window); y++) { s += rowSum[y]; c += rowCount[y]; }
                float want = c > 0 && yc < bottom ? (float)((baseX - s / c) / 32.0) : prev;
                float d = Math.Max(0f, Math.Min(MaxSlant / Strips, want - prev));
                prev += d;
                off[j] = prev;
            }
            return off;
        }

        /// <summary>1 / cos(pitch): the height factor of an upright sprite under a camera looking down by `pitchDeg`.</summary>
        public static float StretchFor(float pitchDeg) => 1f / (float)Math.Cos(pitchDeg * Math.PI / 180.0);

        public static float WorldX(Pos origin, float tileX) => tileX - origin.X;
        public static float WorldZ(Pos origin, float tileY) => -(tileY - origin.Y);

        /// <summary>The pieces of one tile in stack order. `drawn` gives a creature's drawn tile position (walking); null: its tile.</summary>
        /// `lean` (type, is an outfit) gives the measured lean profile of a thing's art (Lean); with it every upright piece,
        /// creatures included, is straightened by its own profile. Without it the fixed rules apply (ShearFor, the torch rule).
        public static void LayoutTile(DatFile dat, Tile tile, Pos origin, float stretch, List<Hd2dPiece> into, Func<Creature, float[]> drawn = null, bool slantedArt = true,
                                      Func<ThingType, bool, float[]> lean = null)
        {
            float elevation = 0f;
            bool shearedBelow = false;   // a wall on this tile was sheared: a torch hung on it follows
            for (int i = 0; i < tile.Things.Count; i++)
            {
                var th = tile.Things[i];
                float tx = tile.Pos.X, ty = tile.Pos.Y;
                if (th.IsCreature)
                {
                    var c = th.Creature;
                    if (drawn != null) { var at = drawn(c); tx = at[0]; ty = at[1]; }
                    // an outfit look, or an item look (a chest, a statue)
                    var ct = c.Outfit.LookType != 0 ? dat.Outfit(c.Outfit.LookType) : dat.Item(c.Outfit.LookTypeEx);
                    if (ct == null) continue;
                    var cp = Make(Hd2dKind.Creature, ct, tile.Pos, i, tx, ty, elevation, origin, stretch, TileMiddle, slantedArt);
                    cp.Creature = c;
                    // characters stand upright already: a measured lean bends their pose and weapons, so only item looks lean
                    if (lean != null && slantedArt) { cp.Lean = c.Outfit.LookType != 0 ? null : lean(ct, false); cp.Shear = 0f; }
                    into.Add(cp);
                    continue;
                }
                var type = th.Item.Type;
                var kind = Classify(type);
                if (kind == Hd2dKind.None) continue;
                float depth = kind == Hd2dKind.Billboard ? BackEdge : TileMiddle;
                var p = Make(kind, type, tile.Pos, i, tx, ty, elevation, origin, stretch, depth, slantedArt);
                p.Item = th.Item;
                // a light source (a standing torch) leans on purpose in its art: sheared only when it hangs on a sheared wall
                if (lean != null) { p.Lean = slantedArt && !p.Flat ? lean(type, false) : null; p.Shear = 0f; }
                else
                {
                    if (type.LightLevel > 0 && !shearedBelow) p.Shear = 0f;
                    if (p.Shear > 0f && type.LightLevel == 0) shearedBelow = true;
                }
                into.Add(p);
                if (type.Elevation > 0) elevation = Math.Min(24f, elevation + type.Elevation);
            }
        }

        static Hd2dPiece Make(Hd2dKind kind, ThingType t, Pos tile, int index, float tx, float ty, float elevation, Pos origin, float stretch, float depth, bool slantedArt)
        {
            var g = t.Idle;
            var p = new Hd2dPiece
            {
                Kind = kind, Type = t, Tile = tile, StackIndex = index, Width = g.Width, Height = g.Height, Stretch = stretch,
                Right = WorldX(origin, tx) + 1f - t.DisplacementX / 32f,
                Shear = slantedArt ? ShearFor(kind, g.Width, g.Height) : 0f,
            };
            float lift = elevation / 32f;
            if (p.Flat)
            {
                p.Z = WorldZ(origin, ty) + t.DisplacementY / 32f;
                p.Y = lift + StackBias * index;
            }
            else
            {
                p.Z = WorldZ(origin, ty) - depth - StackBias * index;
                p.Y = (lift + t.DisplacementY / 32f) * stretch;
            }
            return p;
        }

        /// <summary>All pieces of the tiles near `origin` (the player's floor), ready to draw.</summary>
        /// `slantedArt`: the sprites are the game's, drawn in the classic slant (sheared upright); false for art drawn straight
        /// up (the synthetic demo art).
        public static List<Hd2dPiece> Layout(World w, Pos origin, float pitchDeg, Func<Creature, float[]> drawn = null, bool slantedArt = true,
                                             Func<ThingType, bool, float[]> lean = null)
        {
            var list = new List<Hd2dPiece>();
            float stretch = StretchFor(pitchDeg);
            foreach (var tile in w.Tiles.Values)
            {
                if (tile.Pos.Z != origin.Z) continue;
                LayoutTile(w.Dat, tile, origin, stretch, list, drawn, slantedArt, lean);
            }
            return list;
        }

        // ---- lights -------------------------------------------------------------------------------------------------

        /// <summary>The client's 8-bit light colour: 6 x 6 x 6 levels of 51 (index = 36 r + 6 g + b). 0 and 216+ are black.</summary>
        public static void ColorFromIndex(int index, out int r, out int g, out int b)
        {
            if (index <= 0 || index >= 216) { r = g = b = 0; return; }
            r = index / 36 % 6 * 51;
            g = index / 6 % 6 * 51;
            b = index % 6 * 51;
        }

        /// <summary>Smooth torch flicker (O432): a factor around 1 (0.88..1.12) from layered sines, different per `seed`. Pure, so a
        /// light and its glow halo can share it.</summary>
        public const float FlickerAmount = 0.12f;
        public static float Flicker(float t, int seed)
        {
            float a = (seed * 1.618f) % 6.2832f, b = (seed * 2.399f) % 6.2832f, c = (seed * 0.731f) % 6.2832f;
            float n = 0.5f * (float)Math.Sin(t * 7.3f + a) + 0.3f * (float)Math.Sin(t * 13.1f + b) + 0.2f * (float)Math.Sin(t * 23.7f + c);
            return 1f + FlickerAmount * n;
        }

        /// <summary>Warm (flame) light: red clearly above blue. Only these flicker and throw embers.</summary>
        public static bool IsFlame(Hd2dLight l) { return l.R >= 0.6f && l.R > l.B + 0.15f; }

        /// <summary>The point lights of a layout: things with the dat light attribute and creatures with a light, nearest to
        /// `focus` first, at most `max`. A light colour of 0 (or 216+) means white. Range is the light level in tiles.</summary>
        public static List<Hd2dLight> Lights(IEnumerable<Hd2dPiece> pieces, Vec3 focus, int max)
        {
            var all = new List<Hd2dLight>();
            foreach (var p in pieces)
            {
                int level, color;
                if (p.Creature != null) { level = p.Creature.LightLevel; color = p.Creature.LightColor; }
                else { level = p.Type.LightLevel; color = p.Type.LightColor; }
                if (level <= 0) continue;
                ColorFromIndex(color, out int r, out int g, out int b);
                if (r + g + b == 0) { r = g = b = 255; }
                var at = p.Center;
                if (!p.Flat) at.Z -= LightForward;
                all.Add(new Hd2dLight
                {
                    Position = at, R = r / 255f, G = g / 255f, B = b / 255f,
                    Range = Math.Max(2f, level), Intensity = Math.Max(0.5f, Math.Min(2f, level / 5f)),
                });
            }
            all.Sort((a, b) =>
            {
                float da = Dist2(a.Position, focus), db = Dist2(b.Position, focus);
                return da.CompareTo(db);
            });
            if (all.Count > max) all.RemoveRange(max, all.Count - max);
            return all;
        }

        public static List<Hd2dBlob> ContactShadows(IEnumerable<Hd2dPiece> pieces) => Hd2dGroundMath.ContactShadows(pieces);
        public static List<Hd2dAoStrip> WallAo(IEnumerable<Hd2dPiece> pieces) => Hd2dGroundMath.WallAo(pieces);

        static float Dist2(Vec3 a, Vec3 b) { var d = a - b; return Vec3.Dot(d, d); }
    }

    /// <summary>A soft dark ellipse on the floor (world units: x east, z north). Strength 0..1 is the alpha at its middle.</summary>
    public struct Hd2dBlob
    {
        public float X, Y, Z, RadiusX, RadiusZ, Strength;
        public override string ToString() => "blob (" + X.ToString("0.###") + ", " + Z.ToString("0.###") + ") r " + RadiusX.ToString("0.###") + " x " + RadiusZ.ToString("0.###") + " s " + Strength.ToString("0.##");
    }

    /// <summary>A gradient strip on the floor along the base of a wall: darkest at the wall (z = ZWall), fading `Depth` tiles south.</summary>
    public struct Hd2dAoStrip
    {
        public float X0, X1, Y, ZWall, Depth, Strength;
    }

    public static class Hd2dGroundMath
    {
        public const float CreatureStrength = 0.55f, ObjectStrength = 0.38f, WallBlobStrength = 0.28f, AoStrength = 0.5f, AoDepth = 0.45f;
        /// <summary>A blob sits this far above the floor of its piece (clears borders and decals, whose stack bias is 0.0015 per entry).</summary>
        public const float Lift = 0.03f;
        /// <summary>The blob of a creature or object is this fraction of its width, and RadiusZ is this fraction of RadiusX (a flattened ellipse).</summary>
        public const float WidthShare = 0.46f, Flatten = 0.6f;

        static float FloorY(Hd2dPiece p) => p.Stretch > 0f ? p.Y / p.Stretch : p.Y;

        /// <summary>One blob under every upright piece (creatures darker, then objects, billboards softest), scaled to the footprint width.
        /// Flat pieces and empty ones give none. The blob is centred a little south of the plane the sprite stands in, under its feet.</summary>
        public static List<Hd2dBlob> ContactShadows(IEnumerable<Hd2dPiece> pieces)
        {
            var list = new List<Hd2dBlob>();
            foreach (var p in pieces)
            {
                if (p.Flat || p.Width <= 0 || p.Kind == Hd2dKind.None) continue;
                float strength = p.Kind == Hd2dKind.Creature ? CreatureStrength
                    : p.Kind == Hd2dKind.Billboard ? WallBlobStrength : ObjectStrength;
                float rx = Math.Max(0.2f, p.Width * WidthShare);
                float rz = rx * Flatten;
                // a billboard stands on the back edge of its tile: its blob reaches out in front of it; others stand mid tile
                float z = p.Z - (p.Kind == Hd2dKind.Billboard ? rz * 0.5f : 0.04f);
                list.Add(new Hd2dBlob { X = p.Right - p.Width / 2f, Y = FloorY(p) + Lift, Z = z, RadiusX = rx, RadiusZ = rz, Strength = strength });
            }
            return list;
        }

        /// <summary>A strip along the foot of every Billboard piece (walls, pillars, trees): the floor in front of its footprint is darkened.</summary>
        public static List<Hd2dAoStrip> WallAo(IEnumerable<Hd2dPiece> pieces)
        {
            var list = new List<Hd2dAoStrip>();
            foreach (var p in pieces)
            {
                if (p.Kind != Hd2dKind.Billboard || p.Width <= 0) continue;
                list.Add(new Hd2dAoStrip { X0 = p.Right - p.Width, X1 = p.Right, Y = FloorY(p) + Lift * 0.5f, ZWall = p.Z, Depth = AoDepth, Strength = AoStrength });
            }
            return list;
        }
    }

    public struct Hd2dCameraPose
    {
        public Vec3 Position, Target;
        public float PitchDeg, FovDeg, Aspect;
        public Vec3 Forward, Right, Up;
        public float Distance;

        /// <summary>Normalised device coordinates (-1..1) of a world point; false when behind the camera.</summary>
        public bool Project(Vec3 p, out float nx, out float ny)
        {
            var v = p - Position;
            float zc = Vec3.Dot(v, Forward);
            nx = ny = 0;
            if (zc <= 1e-4f) return false;
            float th = (float)Math.Tan(FovDeg * Math.PI / 360.0);
            nx = Vec3.Dot(v, Right) / (zc * th * Aspect);
            ny = Vec3.Dot(v, Up) / (zc * th);
            return true;
        }
    }

    public static class Hd2dCamera
    {
        public const float DefaultPitch = 40f, DefaultFov = 25f;

        static Hd2dCameraPose Make(Vec3 target, float dist, float pitchDeg, float fovDeg, float aspect)
        {
            double p = pitchDeg * Math.PI / 180.0;
            float s = (float)Math.Sin(p), c = (float)Math.Cos(p);
            var fwd = new Vec3(0, -s, c);   // looks north and down
            return new Hd2dCameraPose
            {
                Target = target, PitchDeg = pitchDeg, FovDeg = fovDeg, Aspect = aspect, Distance = dist,
                Position = target - fwd * dist, Forward = fwd, Right = new Vec3(1, 0, 0), Up = new Vec3(0, c, s),
            };
        }

        /// <summary>The camera for the player at tile (tileX, tileY) (fractions while walking): looks at the tile's middle from the
        /// south and above, at the smallest distance that keeps the whole viewW x viewH tile rectangle (15 x 11, the classic
        /// view) inside the frame at the given aspect, plus `margin` tiles of floor on every side.</summary>
        public static Hd2dCameraPose ForTile(float tileX, float tileY, Pos origin, float aspect, float pitchDeg = DefaultPitch,
                                             float fovDeg = DefaultFov, float viewW = 15f, float viewH = 11f, float margin = 0f)
        {
            var target = new Vec3(Hd2d.WorldX(origin, tileX) + 0.5f, 0f, Hd2d.WorldZ(origin, tileY) - 0.5f);
            float hw = viewW / 2f + margin, hh = viewH / 2f + margin;
            var corners = new[] { new Vec3(-hw, 0, -hh), new Vec3(hw, 0, -hh), new Vec3(hw, 0, hh), new Vec3(-hw, 0, hh) };
            float lo = 1f, hi = 400f;
            for (int i = 0; i < 60; i++)
            {
                float mid = (lo + hi) / 2f;
                if (Fits(Make(target, mid, pitchDeg, fovDeg, aspect), target, corners)) hi = mid; else lo = mid;
            }
            return Make(target, hi, pitchDeg, fovDeg, aspect);
        }

        static bool Fits(Hd2dCameraPose pose, Vec3 target, Vec3[] corners)
        {
            foreach (var c in corners)
            {
                if (!pose.Project(target + c, out float nx, out float ny)) return false;
                if (Math.Abs(nx) > 1f || Math.Abs(ny) > 1f) return false;
            }
            return true;
        }
    }
}
