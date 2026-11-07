// 3D architecture test (Ruins3d): which 3D piece stands on which tile, and how it is turned. Pure C#, no Unity types, so it
// builds in Core.Tests. The Unity side (Unity/Hd2dRuins3d.cs) loads the models of Resources/Ruins3d and places them.
//
// The input is the HD-2D layout (Core/Hd2d.cs). Every sprite piece gets a role (RoleOf):
//   ground                                  -> Floor    one floor piece on the tile
//   ground border                           -> Border   no piece: the floor is enough, the sprite is hidden
//   light source standing upright           -> Light    a torch on the wall of its tile, else candles on a short column
//   upright, blocking, on-bottom (a wall)   -> Wall     one wall segment per cell of width, one course per cell of height (1..3)
//   upright, blocking, not on-bottom        -> Pillar   a column in the middle of the tile
//   anything else (decals, objects, creatures, on-top things) -> None: stays a sprite.
// The pieces of a role other than None are hidden in the sprite meshes (Hd2dView.Skip = Replaces).
//
// Units: the pack is built on a 2 x 2 unit cell, so PackScale 0.5 makes one cell one tile (one Unity unit, as Hd2dView).
// A wall course is then one tile high. Models stand on y = 0 (floors have their top at 0) and the pack's front side is +z:
// Yaw turns +z to the way the piece faces. Walls face the open side: south first (the camera side), then east, west, north.
// Tile (tx, ty): world x = tx - origin.X + 0.5, world z = -(ty - origin.Y) - 0.5 (the tile's middle); y grows south.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public enum RuinsRole { None, Floor, Border, Wall, Pillar, Light }

    /// <summary>One model to place: the pack file name (Resources/Ruins3d/NAME), where, turned by Yaw degrees round y, scaled.</summary>
    public sealed class RuinsPlacement
    {
        public string Piece;
        public float X, Y, Z, Yaw, Scale = Hd2dRuins.PackScale;
        public RuinsRole Role;
        public override string ToString() => Piece + " at (" + X.ToString("0.##") + ", " + Y.ToString("0.##") + ", " + Z.ToString("0.##") + ") yaw " + Yaw.ToString("0");
    }

    /// <summary>How a material of the pack is drawn after the dark fantasy restyle (Restyle).</summary>
    public struct RuinsStyle
    {
        public float R, G, B;
        public float EmitR, EmitG, EmitB;   // emission, 0 for none (flames)
        public float Smoothness;
        public bool Emissive => EmitR + EmitG + EmitB > 0f;
    }

    public static class Hd2dRuins
    {
        /// <summary>The pack's cell is 2 units wide: half of that is one tile.</summary>
        public const float PackScale = 0.5f;
        public const int MaxProps = 5;
        /// <summary>The face of a wall sits this far from the tile's middle towards its back; the wall is 0.125 thick behind it.</summary>
        public const float WallFace = 0.35f;
        /// <summary>The floor top sits a little under the flat sprites (decals, carpets) so they do not sink into the 3D floor.</summary>
        public const float FloorY = -0.035f;
        public const float TorchY = 1.0f;

        /// <summary>The pieces the experiment needs: if one is missing the view keeps its sprites.</summary>
        public static readonly string[] Required = { "Floor_Standard", "Floor_Squares", "Wall", "Column_Round" };

        /// <summary>Every model name the plan can use (the files of Resources/Ruins3d).</summary>
        public static readonly string[] AllPieces =
        {
            "Floor_Standard", "Floor_Squares", "Floor_Diamond", "Wall", "Wall_Broken", "Window_Bars", "Column_Round", "Column_Square",
            "Column_Round_Short", "Torch", "Candles_1", "Candles_2", "Barrel", "Crate", "Pot1", "Pot2", "Skull", "Chest", "Bookcase_Full",
        };

        public static RuinsRole RoleOf(Hd2dPiece p)
        {
            if (p == null || p.Creature != null || p.Type == null) return RuinsRole.None;
            if (p.Kind == Hd2dKind.Floor) return RuinsRole.Floor;
            if (p.Kind == Hd2dKind.Border) return RuinsRole.Border;
            if (p.Flat) return RuinsRole.None;
            if (p.Type.LightLevel > 0 && (p.Kind == Hd2dKind.Billboard || p.Kind == Hd2dKind.Object)) return RuinsRole.Light;
            if (p.Kind == Hd2dKind.Billboard) return p.Type.OnBottom ? RuinsRole.Wall : RuinsRole.Pillar;
            return RuinsRole.None;
        }

        /// <summary>True when a 3D piece takes the place of this sprite piece (the Hd2dView.Skip rule).</summary>
        public static bool Replaces(Hd2dPiece p) => RoleOf(p) != RuinsRole.None;

        // ---- the plan -----------------------------------------------------------------------------------------------

        static long Key(int x, int y) => ((long)x << 32) ^ (uint)y;

        static int Hash(int x, int y, int salt)
        {
            unchecked
            {
                int h = x * 73856093 ^ y * 19349663 ^ salt * 83492791;
                h ^= h >> 13; h *= 0x5bd1e995;
                return (h ^ (h >> 15)) & 0x7fffffff;
            }
        }

        public static float TileX(Pos origin, int tx) => tx - origin.X + 0.5f;
        public static float TileZ(Pos origin, int ty) => -(ty - origin.Y) - 0.5f;

        /// <summary>The direction (x east, z north) and yaw of a wall facing the open side of tile (tx, ty).</summary>
        public static void Facing(Func<int, int, bool> open, int tx, int ty, out int dx, out int dz, out float yaw)
        {
            dx = 0; dz = -1;   // south by default
            if (open(tx, ty + 1)) { dx = 0; dz = -1; }
            else if (open(tx + 1, ty)) { dx = 1; dz = 0; }
            else if (open(tx - 1, ty)) { dx = -1; dz = 0; }
            else if (open(tx, ty - 1)) { dx = 0; dz = 1; }
            yaw = (float)(Math.Atan2(dx, dz) * 180.0 / Math.PI);
            if (yaw < 0) yaw += 360f;
        }

        sealed class WallTile { public int Courses = 1; public bool Mounted; public int Dx, Dz; public float Yaw; }

        /// <summary>The 3D pieces of a layout. Deterministic: the same layout gives the same list (variants come from a hash of the tile).</summary>
        public static List<RuinsPlacement> Plan(IEnumerable<Hd2dPiece> pieces, Pos origin)
        {
            var floors = new Dictionary<long, int[]>();    // tile -> {x, y}
            var walls = new Dictionary<long, WallTile>();
            var wallXY = new Dictionary<long, int[]>();
            var pillars = new Dictionary<long, int[]>();
            var lights = new Dictionary<long, int[]>();
            var busy = new HashSet<long>();                // tiles that hold anything that is not plain floor
            foreach (var p in pieces)
            {
                int tx = p.Tile.X, ty = p.Tile.Y;
                switch (RoleOf(p))
                {
                    case RuinsRole.Floor: floors[Key(tx, ty)] = new[] { tx, ty }; break;
                    case RuinsRole.Border: break;
                    case RuinsRole.Wall:
                        for (int w = 0; w < Math.Max(1, p.Width); w++)
                        {
                            long k = Key(tx - w, ty);
                            if (!walls.TryGetValue(k, out var wt)) { wt = new WallTile(); walls[k] = wt; wallXY[k] = new[] { tx - w, ty }; }
                            wt.Courses = Math.Max(wt.Courses, Math.Min(3, Math.Max(1, p.Height)));
                        }
                        break;
                    case RuinsRole.Pillar: pillars[Key(tx, ty)] = new[] { tx, ty }; busy.Add(Key(tx, ty)); break;
                    case RuinsRole.Light: lights[Key(tx, ty)] = new[] { tx, ty }; busy.Add(Key(tx, ty)); break;
                    default: busy.Add(Key(tx, ty)); break;
                }
            }
            foreach (var k in walls.Keys) busy.Add(k);

            Func<int, int, bool> open = (x, y) => floors.ContainsKey(Key(x, y)) && !walls.ContainsKey(Key(x, y)) && !pillars.ContainsKey(Key(x, y));
            foreach (var kv in walls)
            {
                var xy = wallXY[kv.Key];
                Facing(open, xy[0], xy[1], out kv.Value.Dx, out kv.Value.Dz, out kv.Value.Yaw);
            }
            foreach (var k in lights.Keys) if (walls.TryGetValue(k, out var wt)) wt.Mounted = true;

            var list = new List<RuinsPlacement>();
            foreach (var xy in Sorted(floors.Values))
            {
                int tx = xy[0], ty = xy[1];
                int h = Hash(tx, ty, 1);
                string name = h % 10 == 0 ? "Floor_Diamond" : (tx + ty) % 2 == 0 ? "Floor_Standard" : "Floor_Squares";
                list.Add(new RuinsPlacement { Piece = name, Role = RuinsRole.Floor, X = TileX(origin, tx), Y = FloorY, Z = TileZ(origin, ty), Yaw = name == "Floor_Standard" ? h / 7 % 4 * 90f : 0f });
            }
            foreach (var xy in Sorted(wallXY.Values))
            {
                int tx = xy[0], ty = xy[1];
                var wt = walls[Key(tx, ty)];
                float cx = TileX(origin, tx) - wt.Dx * WallFace, cz = TileZ(origin, ty) - wt.Dz * WallFace;
                for (int c = 0; c < wt.Courses; c++)
                {
                    string name = "Wall";
                    int h = Hash(tx, ty, 2 + c);
                    if (c > 0 && c == wt.Courses - 1 && !wt.Mounted) name = h % 8 == 0 ? "Wall_Broken" : h % 8 == 1 ? "Window_Bars" : "Wall";
                    list.Add(new RuinsPlacement { Piece = name, Role = RuinsRole.Wall, X = cx, Y = c * 2f * PackScale, Z = cz, Yaw = wt.Yaw });
                }
            }
            foreach (var xy in Sorted(pillars.Values))
            {
                int tx = xy[0], ty = xy[1];
                int h = Hash(tx, ty, 3);
                list.Add(new RuinsPlacement { Piece = h % 3 == 0 ? "Column_Square" : "Column_Round", Role = RuinsRole.Pillar, X = TileX(origin, tx), Y = 0f, Z = TileZ(origin, ty), Yaw = h / 3 % 4 * 90f });
            }
            foreach (var xy in Sorted(lights.Values))
            {
                int tx = xy[0], ty = xy[1];
                long k = Key(tx, ty);
                if (walls.TryGetValue(k, out var wt))
                {
                    // a torch hangs on the face of its wall: the pack's torch has its back at -z and leans out at +z
                    list.Add(new RuinsPlacement
                    {
                        Piece = "Torch", Role = RuinsRole.Light, Y = TorchY, Yaw = wt.Yaw,
                        X = TileX(origin, tx) - wt.Dx * (WallFace - 0.15f), Z = TileZ(origin, ty) - wt.Dz * (WallFace - 0.15f),
                    });
                }
                else
                {
                    // a loose light: candles on a short column
                    float x = TileX(origin, tx), z = TileZ(origin, ty);
                    const float colScale = 0.45f;
                    list.Add(new RuinsPlacement { Piece = "Column_Round_Short", Role = RuinsRole.Light, X = x, Y = 0f, Z = z, Scale = colScale });
                    list.Add(new RuinsPlacement { Piece = Hash(tx, ty, 4) % 2 == 0 ? "Candles_1" : "Candles_2", Role = RuinsRole.Light, X = x, Y = 1.83f * colScale, Z = z, Yaw = 180f });
                }
            }
            AddProps(list, origin, walls, wallXY, floors, busy);
            return list;
        }

        sealed class Prop { public string Piece; public bool AtWall; public float Depth; }
        static readonly Prop[] PropTable =
        {
            new Prop { Piece = "Barrel" }, new Prop { Piece = "Crate" }, new Prop { Piece = "Pot1" }, new Prop { Piece = "Pot2" },
            new Prop { Piece = "Chest" }, new Prop { Piece = "Skull" }, new Prop { Piece = "Bookcase_Full", AtWall = true, Depth = 0.19f },
        };

        /// <summary>A few props on the floor tile in front of a wall (not on a tile that holds any other thing, not on the way
        /// along the wall): a hash of the wall tile picks the place and the prop, at most MaxProps.</summary>
        static void AddProps(List<RuinsPlacement> list, Pos origin, Dictionary<long, WallTile> walls, Dictionary<long, int[]> wallXY,
                             Dictionary<long, int[]> floors, HashSet<long> busy)
        {
            int count = 0;
            var taken = new HashSet<long>();
            foreach (var xy in Sorted(wallXY.Values))
            {
                if (count >= MaxProps) break;
                int tx = xy[0], ty = xy[1];
                var wt = walls[Key(tx, ty)];
                if (wt.Mounted) continue;
                int fx = tx + wt.Dx, fy = ty - wt.Dz;   // the tile in front: south is ty + 1
                long fk = Key(fx, fy);
                if (!floors.ContainsKey(fk) || busy.Contains(fk) || taken.Contains(fk)) continue;
                int h = Hash(tx, ty, 9);
                if (h % 3 != 0) continue;
                var prop = PropTable[h / 3 % PropTable.Length];
                taken.Add(fk);
                count++;
                float x, z;
                if (prop.AtWall)
                {
                    x = TileX(origin, tx) - wt.Dx * (WallFace - prop.Depth); z = TileZ(origin, ty) - wt.Dz * (WallFace - prop.Depth);
                    list.Add(new RuinsPlacement { Piece = prop.Piece, Role = RuinsRole.None, X = x, Y = 0f, Z = z, Yaw = wt.Yaw });
                }
                else
                {
                    x = TileX(origin, fx) + (h / 7 % 5 - 2) * 0.05f; z = TileZ(origin, fy) + (h / 11 % 5 - 2) * 0.05f;
                    list.Add(new RuinsPlacement { Piece = prop.Piece, Role = RuinsRole.None, X = x, Y = 0f, Z = z, Yaw = h / 13 % 8 * 45f });
                }
            }
        }

        static List<int[]> Sorted(IEnumerable<int[]> xy)
        {
            var l = new List<int[]>(xy);
            l.Sort((a, b) => a[0] != b[0] ? a[0].CompareTo(b[0]) : a[1].CompareTo(b[1]));
            return l;
        }

        // ---- the dark fantasy restyle -------------------------------------------------------------------------------

        static float Gamma(float v) => (float)Math.Pow(Math.Max(0f, Math.Min(1f, v)), 1.0 / 2.2);
        static float Clamp01(float v) => v < 0f ? 0f : v > 1f ? 1f : v;

        /// <summary>The colour of a pack material after the restyle. The pack's colours are bright cartoon values written for a
        /// linear workflow, and Unity reads them as sRGB, so they are first lifted (gamma), then pulled toward their luminance and
        /// darkened: stone goes cold grey (x 0.7), wood and metal dark, flames ("Fire", "Light") stay warm and emissive.
        /// `name` is the material name of the mtl file; r, g, b the mtl's Kd.</summary>
        public static RuinsStyle Restyle(string name, float r, float g, float b)
        {
            string n = (name ?? "").ToLowerInvariant();
            if (n.StartsWith("fire", StringComparison.Ordinal) || n.StartsWith("light", StringComparison.Ordinal))
                return new RuinsStyle { R = 1f, G = 0.55f, B = 0.14f, EmitR = 2.2f, EmitG = 1.0f, EmitB = 0.25f, Smoothness = 0f };
            r = Gamma(r); g = Gamma(g); b = Gamma(b);
            float lum = 0.299f * r + 0.587f * g + 0.114f * b;
            float keep, dark; float tr = 1f, tg = 1f, tb = 1f, smooth = 0.08f;
            if (n.Contains("wood")) { keep = 0.7f; dark = 0.6f; }
            else if (n.Contains("metal") || n.Contains("black")) { keep = 0.3f; dark = 0.6f; smooth = 0.3f; }
            else if (n.StartsWith("candle", StringComparison.Ordinal) || n.Contains("bone") || n.Contains("pages")) { keep = 0.5f; dark = 0.75f; }
            else if (n.StartsWith("book", StringComparison.Ordinal) || n.StartsWith("pot", StringComparison.Ordinal)) { keep = 0.55f; dark = 0.6f; }
            else { keep = 0.35f; dark = 0.7f; tr = 0.93f; tg = 0.98f; tb = 1.08f; }   // stone: cold grey
            float mr = lum + (r - lum) * keep, mg = lum + (g - lum) * keep, mb = lum + (b - lum) * keep;
            return new RuinsStyle { R = Clamp01(mr * dark * tr), G = Clamp01(mg * dark * tg), B = Clamp01(mb * dark * tb), Smoothness = smooth };
        }
    }
}
