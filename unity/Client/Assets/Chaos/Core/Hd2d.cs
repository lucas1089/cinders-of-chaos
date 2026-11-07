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
// The classic sprites draw height going up and to the left (one tile west per tile up): an upright quad of a thing at
// least two cells wide and high (walls, pillars, tall objects; not creatures, whose art stands straight) is sheared one tile east per
// cell of height, so its vertical edges come out vertical in 3D and its top sits over its base (Hd2dPiece.Shear).
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
            float y0 = Y + h * Stretch, y1 = y0 + Stretch;
            float s0 = h * Shear, s1 = s0 + Shear;   // the quad leans east as it rises: the sprite's slant comes out upright
            return new[] { new Vec3(west + s0, y0, Z), new Vec3(east + s0, y0, Z), new Vec3(east + s1, y1, Z), new Vec3(west + s1, y1, Z) };
        }

        /// <summary>The middle of the thing's footprint and body: the point a light or a name label hangs on.</summary>
        public Vec3 Center => Flat
            ? new Vec3(Right - Width / 2f, Y, Z - Height / 2f)
            : new Vec3(Right - Width / 2f + Height * Shear / 2f, Y + Height * Stretch / 2f, Z);
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

        /// <summary>The shear of an upright piece: 1 for a wall, pillar or object at least two cells wide and high (the
        /// sprites whose art climbs up-left across cells), else 0: a one-cell-wide sprite stands straight in its column.</summary>
        public static float ShearFor(Hd2dKind kind, int width, int height) =>
            width > 1 && height > 1 && (kind == Hd2dKind.Billboard || kind == Hd2dKind.OnTop || kind == Hd2dKind.Object) ? 1f : 0f;

        /// <summary>1 / cos(pitch): the height factor of an upright sprite under a camera looking down by `pitchDeg`.</summary>
        public static float StretchFor(float pitchDeg) => 1f / (float)Math.Cos(pitchDeg * Math.PI / 180.0);

        public static float WorldX(Pos origin, float tileX) => tileX - origin.X;
        public static float WorldZ(Pos origin, float tileY) => -(tileY - origin.Y);

        /// <summary>The pieces of one tile in stack order. `drawn` gives a creature's drawn tile position (walking); null: its tile.</summary>
        public static void LayoutTile(DatFile dat, Tile tile, Pos origin, float stretch, List<Hd2dPiece> into, Func<Creature, float[]> drawn = null, bool slantedArt = true)
        {
            float elevation = 0f;
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
                    into.Add(cp);
                    continue;
                }
                var type = th.Item.Type;
                var kind = Classify(type);
                if (kind == Hd2dKind.None) continue;
                float depth = kind == Hd2dKind.Billboard ? BackEdge : TileMiddle;
                var p = Make(kind, type, tile.Pos, i, tx, ty, elevation, origin, stretch, depth, slantedArt);
                p.Item = th.Item;
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
        public static List<Hd2dPiece> Layout(World w, Pos origin, float pitchDeg, Func<Creature, float[]> drawn = null, bool slantedArt = true)
        {
            var list = new List<Hd2dPiece>();
            float stretch = StretchFor(pitchDeg);
            foreach (var tile in w.Tiles.Values)
            {
                if (tile.Pos.Z != origin.Z) continue;
                LayoutTile(w.Dat, tile, origin, stretch, list, drawn, slantedArt);
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

        static float Dist2(Vec3 a, Vec3 b) { var d = a - b; return Vec3.Dot(d, d); }
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
