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
// On top of that the plan dresses the room (all by a hash of the tile, so the same layout gives the same room):
//   wall variety   a long run (6+ tiles) is one course taller (3); the top course of a tall wall is sometimes broken, a hole, half a wall or a barred window; a long run (6+ tiles)
//                  has an arch (round or gothic) as its middle piece, and a gothic one holds a door; banners hang on some faces
//                  and a few tall walls have a beam standing against them
//   corners        the two ends of the longest wall run hold a statue (stag, fox) on a plinth; its two far corners a dead tree and
//                  a broken column
//   props          barrels, crates, a chest, pots, broken pots, skulls, candles, rubble, bookcases on the wall: in front of the
//                  wall, along the room edge and a few in the open, at most MaxProps. Never on a tile that holds anything (items,
//                  creatures, the 3D pieces), and never on or within one tile of a flat decal (the carpet) or a creature.
//
// Units: the pack is built on a 2 x 2 unit cell, so PackScale 0.5 makes one cell one tile (one Unity unit, as Hd2dView).
// A wall course is then one tile high. Models stand on y = 0 (floors have their top at 0) and the pack's front side is +z:
// Yaw turns +z to the way the piece faces. Walls face the open side: south first (the camera side), then east, west, north.
// Tile (tx, ty): world x = tx - origin.X + 0.5, world z = -(ty - origin.Y) - 0.5 (the tile's middle); y grows south.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    /// <summary>Trim: a wooden or stone beam against a wall (dark like the wall). Props and statues are None.</summary>
    /// <summary>The roles from Terrain on belong to World3d (Core/Hd2dWorld3d.cs): terrain tile, water, lava, tree, bush, rock, a
    /// scattered grass tuft, plant or rock.</summary>
    public enum RuinsRole { None, Floor, Border, Wall, Pillar, Light, Trim, Terrain, Water, Lava, Tree, Bush, Rock, Scatter }

    /// <summary>One model to place: the pack file name (Resources/Ruins3d/NAME), where, turned by Yaw degrees round y, scaled.</summary>
    public sealed class RuinsPlacement
    {
        public string Piece;
        public float X, Y, Z, Yaw, Scale = Hd2dRuins.PackScale;
        /// <summary>Height scale when it differs from Scale (a squat plinth from a tall column); 0 means the same as Scale.</summary>
        public float ScaleY;
        public RuinsRole Role;
        /// <summary>World3d terrain tiles: the ground class and the mean colour of the sprite the tile is tinted from.</summary>
        public GroundClass Ground;
        public float TintR, TintG, TintB;
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
        /// <summary>Most props (and wall bookcases) in one plan; corners, beams and banners do not count.</summary>
        public const int MaxProps = 22;
        /// <summary>A wall run of at least this many tiles gets an arch in its middle.</summary>
        public const int LongRun = 6;
        /// <summary>The face of a wall sits this far from the tile's middle towards its back; the wall is 0.125 thick behind it.</summary>
        public const float WallFace = 0.35f;
        /// <summary>The floor top sits a little under the flat sprites (decals, carpets) so they do not sink into the 3D floor.</summary>
        public const float FloorY = -0.035f;
        public const float TorchY = 1.0f;

        // Restyle numbers: brightness after the gamma lift (the floor is the reference the torch pools are read against).
        public const float WallBrightness = 0.42f, FloorBrightness = 0.55f, StoneBrightness = 0.5f, WallContrast = 1.18f;

        /// <summary>The pieces the experiment needs: if one is missing the view keeps its sprites.</summary>
        public static readonly string[] Required = { "Floor_Standard", "Floor_Squares", "Wall", "Column_Round" };

        /// <summary>Every model name the plan can use (the files of Resources/Ruins3d).</summary>
        public static readonly string[] AllPieces =
        {
            "Floor_Standard", "Floor_Squares", "Floor_Diamond", "Wall", "Wall_Broken", "Wall_Hole", "Wall_Half", "Window_Bars",
            "Wall_ArchRound", "Wall_ArchGothic", "Doors_GothicArch", "Flag_Wall", "Support_Tall",
            "Column_Round", "Column_Square", "Column_Round_Short", "Torch", "Candles_1", "Candles_2",
            "Statue_Stag", "Statue_Fox", "DeadTree_1", "DeadTree_2", "DeadTree_3",
            "Barrel", "Crate", "Pot1", "Pot2", "Pot3", "Pot1_Broken", "Pot2_Broken", "Pot3_Broken", "Skull", "Chest", "Bricks", "Bookcase_Full",
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

        public static long Key(int x, int y) => ((long)x << 32) ^ (uint)y;

        internal static int Hash(int x, int y, int salt)
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

        /// <summary>True when no other wall piece starts within one piece width of it along its row or its column.</summary>
        public static bool Isolated(HashSet<long> wallAt, int tx, int ty, int width)
        {
            for (int d = 1; d <= width; d++)
                if (wallAt.Contains(Key(tx - d, ty)) || wallAt.Contains(Key(tx + d, ty)) || wallAt.Contains(Key(tx, ty - d)) || wallAt.Contains(Key(tx, ty + d))) return false;
            return true;
        }

        sealed class WallTile
        {
            public int Courses = 1; public bool Mounted; public int Dx, Dz; public float Yaw;
            public bool Arch, Flag, Beam;
            public string Top = "Wall";   // the piece of the top course
        }

        /// <summary>Marks the tiles a piece covers (its anchor is the south-east cell) plus `margin` tiles all round.</summary>
        internal static void Block(HashSet<long> busy, Hd2dPiece p, int margin)
        {
            int w = Math.Max(1, p.Width), h = Math.Max(1, p.Height);
            for (int x = p.Tile.X - w + 1 - margin; x <= p.Tile.X + margin; x++)
                for (int y = p.Tile.Y - h + 1 - margin; y <= p.Tile.Y + margin; y++)
                    busy.Add(Key(x, y));
        }

        /// <summary>The 3D pieces of a layout. Deterministic: the same layout gives the same list (variants come from a hash of the tile).</summary>
        public static List<RuinsPlacement> Plan(IEnumerable<Hd2dPiece> pieces, Pos origin, Func<Hd2dPiece, RuinsRole> roleOf = null)
        {
            roleOf = roleOf ?? RoleOf;
            var floors = new Dictionary<long, int[]>();    // tile -> {x, y}
            var walls = new Dictionary<long, WallTile>();
            var wallXY = new Dictionary<long, int[]>();
            var pillars = new Dictionary<long, int[]>();
            var lights = new Dictionary<long, int[]>();
            var busy = new HashSet<long>();                // tiles that hold anything that is not plain floor, and the tiles beside a decal or a creature
            // a blocking upright piece with no other one beside it on its row is a pillar, not a wall run
            var all = new List<Hd2dPiece>(pieces);
            var wallAt = new HashSet<long>();
            foreach (var p in all) if (roleOf(p) == RuinsRole.Wall) wallAt.Add(Key(p.Tile.X, p.Tile.Y));
            foreach (var p in all)
            {
                int tx = p.Tile.X, ty = p.Tile.Y;
                var role = roleOf(p);
                if (role == RuinsRole.Wall && Isolated(wallAt, tx, ty, Math.Max(1, p.Width))) role = RuinsRole.Pillar;
                switch (role)
                {
                    case RuinsRole.Floor: floors[Key(tx, ty)] = new[] { tx, ty }; break;
                    case RuinsRole.Border: break;
                    case RuinsRole.Terrain: case RuinsRole.Water: case RuinsRole.Lava: break;   // World3d tiles: no halo for props
                    case RuinsRole.Wall:
                        for (int w = 0; w < Math.Max(1, p.Width); w++)
                        {
                            long k = Key(tx - w, ty);
                            if (!walls.TryGetValue(k, out var wt)) { wt = new WallTile(); walls[k] = wt; wallXY[k] = new[] { tx - w, ty }; }
                            wt.Courses = Math.Max(wt.Courses, Math.Min(3, Math.Max(1, p.Height)));
                        }
                        break;
                    case RuinsRole.Pillar: pillars[Key(tx, ty)] = new[] { tx, ty }; Block(busy, p, 0); break;
                    case RuinsRole.Light: lights[Key(tx, ty)] = new[] { tx, ty }; Block(busy, p, 0); break;
                    default: Block(busy, p, p.Creature != null || p.Flat || p.Kind == Hd2dKind.Decal ? 1 : 0); break;
                }
            }
            foreach (var k in walls.Keys) busy.Add(k);

            Func<int, int, bool> open = (x, y) => floors.ContainsKey(Key(x, y)) && !walls.ContainsKey(Key(x, y)) && !pillars.ContainsKey(Key(x, y));
            var behind = new HashSet<long>();              // the tiles on the far side of a wall: not part of the room
            foreach (var kv in walls)
            {
                var xy = wallXY[kv.Key];
                Facing(open, xy[0], xy[1], out kv.Value.Dx, out kv.Value.Dz, out kv.Value.Yaw);
                behind.Add(Key(xy[0] - kv.Value.Dx, xy[1] + kv.Value.Dz));
            }
            foreach (var k in lights.Keys) if (walls.TryGetValue(k, out var wt)) wt.Mounted = true;
            var interior = new HashSet<long>();
            foreach (var k in floors.Keys) if (open(floors[k][0], floors[k][1]) && !behind.Contains(k)) interior.Add(k);

            var runs = Runs(walls, wallXY);
            foreach (var run in runs)
            {
                // a long wall is a hall wall: one course taller than its sprite (the camera looks down, a 2 tile wall is a low band)
                if (run.Count >= LongRun) foreach (var xy in run) { var w = walls[Key(xy[0], xy[1])]; if (w.Courses >= 2) w.Courses = 3; }
                PickArch(run, walls);
            }

            var list = new List<RuinsPlacement>();
            foreach (var xy in Sorted(floors.Values))
            {
                int tx = xy[0], ty = xy[1];
                int h = Hash(tx, ty, 1);
                string name = h % 10 == 0 ? "Floor_Diamond" : (tx + ty) % 2 == 0 ? "Floor_Standard" : "Floor_Squares";
                list.Add(new RuinsPlacement { Piece = name, Role = RuinsRole.Floor, X = TileX(origin, tx), Y = FloorY, Z = TileZ(origin, ty), Yaw = name == "Floor_Standard" ? h / 7 % 4 * 90f : 0f });
            }
            foreach (var xy in Sorted(wallXY.Values)) AddWallTile(list, origin, walls[Key(xy[0], xy[1])], xy[0], xy[1]);
            foreach (var run in runs) AddArch(list, origin, run, walls);
            AddDressing(list, origin, walls, wallXY);
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
            var taken = new HashSet<long>();
            AddCorners(list, origin, runs, walls, interior, busy, taken);
            AddProps(list, origin, walls, wallXY, floors, interior, busy, taken);
            return list;
        }

        // ---- wall runs, arches and dressing -------------------------------------------------------------------------

        /// <summary>The wall tiles grouped in runs: same facing, same line, next to each other along it (sorted along the run).</summary>
        static List<List<int[]>> Runs(Dictionary<long, WallTile> walls, Dictionary<long, int[]> wallXY)
        {
            var groups = new Dictionary<string, List<int[]>>();
            var order = new List<string>();
            foreach (var xy in Sorted(wallXY.Values))
            {
                var wt = walls[Key(xy[0], xy[1])];
                string g = wt.Dx + "," + wt.Dz + "," + (wt.Dz != 0 ? xy[1] : xy[0]);
                if (!groups.TryGetValue(g, out var l)) { l = new List<int[]>(); groups[g] = l; order.Add(g); }
                l.Add(xy);
            }
            var runs = new List<List<int[]>>();
            foreach (var g in order)
            {
                var l = groups[g];
                int axis = walls[Key(l[0][0], l[0][1])].Dz != 0 ? 0 : 1;   // the tiles along the wall: x for a wall facing north or south
                var cur = new List<int[]> { l[0] };
                for (int i = 1; i < l.Count; i++)
                {
                    if (l[i][axis] != l[i - 1][axis] + 1) { runs.Add(cur); cur = new List<int[]>(); }
                    cur.Add(l[i]);
                }
                runs.Add(cur);
            }
            return runs;
        }

        /// <summary>The index of the first of the two tiles an arch takes in this run (null: none). The middle of the run, a step
        /// aside if a torch hangs there or the wall is only one course high.</summary>
        public static int ArchIndex(int count, Func<int, bool> fits)
        {
            if (count < LongRun) return -1;
            int mid = count / 2 - 1;
            foreach (int d in new[] { 0, 1, -1, 2, -2 })
            {
                int i = mid + d;
                if (i >= 0 && i + 1 < count && fits(i) && fits(i + 1)) return i;
            }
            return -1;
        }

        static void PickArch(List<int[]> run, Dictionary<long, WallTile> walls)
        {
            int i = ArchIndex(run.Count, j => { var w = walls[Key(run[j][0], run[j][1])]; return w.Courses >= 2 && !w.Mounted; });
            if (i < 0) return;
            walls[Key(run[i][0], run[i][1])].Arch = true;
            walls[Key(run[i + 1][0], run[i + 1][1])].Arch = true;
        }

        /// <summary>Where a wall piece sits: the tile's middle moved to the wall face, `along` tiles along the wall.</summary>
        static void WallPos(Pos origin, WallTile wt, int tx, int ty, float depth, float along, out float x, out float z)
        {
            x = TileX(origin, tx) - wt.Dx * depth + along * wt.Dz;
            z = TileZ(origin, ty) - wt.Dz * depth - along * wt.Dx;
        }

        static void AddWallTile(List<RuinsPlacement> list, Pos origin, WallTile wt, int tx, int ty)
        {
            for (int c = 0; c < wt.Courses; c++)
            {
                if (wt.Arch && c < 2) continue;   // the arch piece fills these
                string name = "Wall";
                float along = 0f, yaw = wt.Yaw;
                int h = Hash(tx, ty, 2 + c);
                if (!wt.Mounted && !wt.Arch)
                {
                    if (wt.Courses == 1) name = h % 10 == 0 ? "Wall_Broken" : h % 10 == 1 ? "Wall_Hole" : "Wall";
                    else if (c > 0 && c == wt.Courses - 1)
                    {
                        switch (h % 7)
                        {
                            case 0: name = "Wall_Broken"; break;
                            case 1: name = "Window_Bars"; break;
                            case 2: name = "Wall_Hole"; break;
                            case 3: name = "Wall_Half"; along = h / 7 % 2 == 0 ? 0.25f : -0.25f; yaw = (yaw + 180f) % 360f; break;   // its thick side is on +z
                        }
                    }
                }
                if (c == wt.Courses - 1) wt.Top = name;
                WallPos(origin, wt, tx, ty, WallFace, along, out float x, out float z);
                list.Add(new RuinsPlacement { Piece = name, Role = RuinsRole.Wall, X = x, Y = c * 2f * PackScale, Z = z, Yaw = yaw });
            }
        }

        static void AddArch(List<RuinsPlacement> list, Pos origin, List<int[]> run, Dictionary<long, WallTile> walls)
        {
            for (int i = 0; i + 1 < run.Count; i++)
            {
                var a = walls[Key(run[i][0], run[i][1])];
                var b = walls[Key(run[i + 1][0], run[i + 1][1])];
                if (!a.Arch || !b.Arch) continue;
                // the arch is 4 units (2 tiles) wide and 2 tiles high: it takes the two tiles and their two lower courses
                WallPos(origin, a, run[i][0], run[i][1], WallFace, 0f, out float x, out float z);
                WallPos(origin, b, run[i + 1][0], run[i + 1][1], WallFace, 0f, out float x2, out float z2);
                bool gothic = Hash(run[0][0], run[0][1], 20) % 2 == 0;
                float mx = (x + x2) / 2f, mz = (z + z2) / 2f;
                list.Add(new RuinsPlacement { Piece = gothic ? "Wall_ArchGothic" : "Wall_ArchRound", Role = RuinsRole.Wall, X = mx, Y = 0f, Z = mz, Yaw = a.Yaw });
                if (gothic)   // the door fills the opening, set at the middle of the arch's thickness
                    list.Add(new RuinsPlacement { Piece = "Doors_GothicArch", Role = RuinsRole.Wall, X = mx - a.Dx * 0.05f, Y = 0f, Z = mz - a.Dz * 0.05f, Yaw = a.Yaw });
                a.Top = b.Top = "Wall";
                i++;
            }
        }

        /// <summary>Banners and beams on the tall walls: not on a torch tile, not on the arch, never two side by side.</summary>
        static void AddDressing(List<RuinsPlacement> list, Pos origin, Dictionary<long, WallTile> walls, Dictionary<long, int[]> wallXY)
        {
            var dressed = new HashSet<long>();
            foreach (var xy in Sorted(wallXY.Values))
            {
                int tx = xy[0], ty = xy[1];
                var wt = walls[Key(tx, ty)];
                if (wt.Mounted || wt.Arch || wt.Courses < 2) continue;
                if (dressed.Contains(Key(tx - 1, ty)) || dressed.Contains(Key(tx, ty - 1)) || dressed.Contains(Key(tx + 1, ty)) || dressed.Contains(Key(tx, ty + 1))) continue;
                if (Hash(tx, ty, 30) % 5 == 0)
                {
                    wt.Flag = true; dressed.Add(Key(tx, ty));
                    WallPos(origin, wt, tx, ty, WallFace - 0.04f, 0f, out float x, out float z);
                    list.Add(new RuinsPlacement { Piece = "Flag_Wall", Role = RuinsRole.None, X = x, Y = 0.04f, Z = z, Yaw = wt.Yaw });
                }
                else if (wt.Top == "Wall" && Hash(tx, ty, 31) % 7 == 0)
                {
                    wt.Beam = true; dressed.Add(Key(tx, ty));
                    WallPos(origin, wt, tx, ty, WallFace - 0.17f, 0f, out float x, out float z);
                    list.Add(new RuinsPlacement { Piece = "Support_Tall", Role = RuinsRole.Trim, X = x, Y = 0f, Z = z, Yaw = wt.Yaw });
                }
            }
        }

        // ---- corners ------------------------------------------------------------------------------------------------

        static void Rot(float yaw, float lx, float lz, out float wx, out float wz)
        {
            double a = yaw * Math.PI / 180.0, c = Math.Cos(a), s = Math.Sin(a);
            wx = (float)(lx * c + lz * s);      // local +x turns to (cos, -sin), local +z to (sin, cos)
            wz = (float)(-lx * s + lz * c);
        }

        /// <summary>The model's middle in its own frame (x, z), so a statue or a tree stands with its middle on the tile's middle.</summary>
        static void Pivot(string piece, out float px, out float pz)
        {
            switch (piece)
            {
                case "Statue_Stag": px = -0.555f; pz = 0.035f; break;
                case "Statue_Fox": px = 0.075f; pz = -0.06f; break;
                case "DeadTree_1": px = -0.34f; pz = 0.16f; break;
                default: px = 0f; pz = 0f; break;
            }
        }

        static void AddCentered(List<RuinsPlacement> list, string piece, float cx, float y, float cz, float yaw, float scale)
        {
            Pivot(piece, out float px, out float pz);
            Rot(yaw, px * scale, pz * scale, out float ox, out float oz);
            list.Add(new RuinsPlacement { Piece = piece, Role = RuinsRole.None, X = cx - ox, Y = y, Z = cz - oz, Yaw = yaw, Scale = scale });
        }

        /// <summary>A statue on a squat plinth (the pack's square column, 0.4 tall).</summary>
        static void AddStatue(List<RuinsPlacement> list, string piece, float x, float z, float yaw)
        {
            list.Add(new RuinsPlacement { Piece = "Column_Square", Role = RuinsRole.None, X = x, Y = 0f, Z = z, Yaw = yaw, Scale = 0.8f, ScaleY = 0.1f });
            AddCentered(list, piece, x, 0.4f, z, yaw, 0.2f);
        }

        static int[] Walk(HashSet<long> interior, int x, int y, int sx, int sy)
        {
            while (interior.Contains(Key(x + sx, y + sy))) { x += sx; y += sy; }
            return new[] { x, y };
        }

        /// <summary>The longest wall run (4+ tiles) has a statue at each end, in front of the wall; the far end of each side of the
        /// room holds a dead tree and a broken column. A corner that is busy stays empty.</summary>
        static void AddCorners(List<RuinsPlacement> list, Pos origin, List<List<int[]>> runs, Dictionary<long, WallTile> walls,
                               HashSet<long> interior, HashSet<long> busy, HashSet<long> taken)
        {
            List<int[]> best = null;
            foreach (var r in runs) if (r.Count >= 4 && (best == null || r.Count > best.Count)) best = r;
            if (best == null) return;
            var a = best[0]; var b = best[best.Count - 1];
            var wt = walls[Key(a[0], a[1])];
            int sx = wt.Dx, sy = -wt.Dz;   // the step from the wall into the room
            int[] fa = { a[0] + sx, a[1] + sy }, fb = { b[0] + sx, b[1] + sy };
            int[] ca = Walk(interior, fa[0], fa[1], sx, sy), cb = Walk(interior, fb[0], fb[1], sx, sy);
            Func<int[], bool> free = t => interior.Contains(Key(t[0], t[1])) && !busy.Contains(Key(t[0], t[1])) && !taken.Contains(Key(t[0], t[1]));
            int h = Hash(a[0], a[1], 40);
            if (free(fa)) { taken.Add(Key(fa[0], fa[1])); AddStatue(list, "Statue_Stag", TileX(origin, fa[0]), TileZ(origin, fa[1]), wt.Yaw + 20f); }
            if (free(fb)) { taken.Add(Key(fb[0], fb[1])); AddStatue(list, "Statue_Fox", TileX(origin, fb[0]), TileZ(origin, fb[1]), wt.Yaw - 20f); }
            bool treeA = h % 2 == 0;
            foreach (var c in new[] { ca, cb })
            {
                bool tree = (c == ca) == treeA;
                if (!free(c) || (c[0] == fa[0] && c[1] == fa[1]) || (c[0] == fb[0] && c[1] == fb[1])) continue;
                taken.Add(Key(c[0], c[1]));
                float x = TileX(origin, c[0]), z = TileZ(origin, c[1]);
                if (tree) AddCentered(list, "DeadTree_" + (1 + h / 2 % 3), x, 0f, z, h / 6 % 4 * 90f, 0.4f);
                else
                {
                    list.Add(new RuinsPlacement { Piece = "Column_Round_Short", Role = RuinsRole.None, X = x, Y = 0f, Z = z, Scale = 0.36f });
                    list.Add(new RuinsPlacement { Piece = "Bricks", Role = RuinsRole.None, X = x + 0.2f, Y = 0f, Z = z - 0.18f, Yaw = h / 5 % 8 * 45f, Scale = 0.3f });
                }
            }
        }

        // ---- props --------------------------------------------------------------------------------------------------

        sealed class Prop { public string Piece; public float Scale = PackScale; }
        static Prop P(string piece, float scale = PackScale) => new Prop { Piece = piece, Scale = scale };
        static readonly Prop[] EdgeProps =
        {
            P("Barrel"), P("Crate"), P("Chest"), P("Pot1"), P("Pot2"), P("Pot3"), P("Pot1_Broken"), P("Pot2_Broken"), P("Skull"),
            P("Candles_1"), P("Candles_2"), P("Column_Round_Short", 0f), P("Bricks", 0.4f), P("Barrel"), P("Crate"), P("Pot3_Broken"),
        };
        static readonly Prop[] OpenProps =
        {
            P("Skull"), P("Pot1_Broken"), P("Pot2_Broken"), P("Pot3_Broken"), P("Candles_1"), P("Candles_2"), P("Bricks", 0.3f), P("Skull"),
        };

        sealed class Cand { public int Score, Kind, X, Y; public WallTile Wall; }

        /// <summary>Props on free floor tiles, picked by a hash of the tile: in front of the walls (a torch tile keeps its pool clear),
        /// along the other edges of the room, a few in the open, and bookcases standing on the wall. The highest-ranked MaxProps stay.</summary>
        static void AddProps(List<RuinsPlacement> list, Pos origin, Dictionary<long, WallTile> walls, Dictionary<long, int[]> wallXY,
                             Dictionary<long, int[]> floors, HashSet<long> interior, HashSet<long> busy, HashSet<long> taken)
        {
            var frontOf = new Dictionary<long, WallTile>();
            foreach (var xy in Sorted(wallXY.Values))
            {
                var wt = walls[Key(xy[0], xy[1])];
                long fk = Key(xy[0] + wt.Dx, xy[1] - wt.Dz);
                if (!frontOf.ContainsKey(fk)) frontOf[fk] = wt;
            }
            var cands = new List<Cand>();
            foreach (var xy in Sorted(floors.Values))
            {
                int tx = xy[0], ty = xy[1];
                long k = Key(tx, ty);
                if (!interior.Contains(k) || busy.Contains(k) || taken.Contains(k)) continue;
                if (frontOf.TryGetValue(k, out var fw))
                {
                    if (!fw.Mounted && Hash(tx, ty, 9) % 5 < 3) cands.Add(new Cand { Score = Hash(tx, ty, 10), Kind = 0, X = tx, Y = ty });
                    continue;
                }
                bool edge = !floors.ContainsKey(Key(tx - 1, ty)) || !floors.ContainsKey(Key(tx + 1, ty)) || !floors.ContainsKey(Key(tx, ty - 1)) || !floors.ContainsKey(Key(tx, ty + 1));
                if (edge ? Hash(tx, ty, 9) % 5 == 0 : Hash(tx, ty, 9) % 25 == 0) cands.Add(new Cand { Score = Hash(tx, ty, 10), Kind = edge ? 1 : 2, X = tx, Y = ty });
            }
            foreach (var xy in Sorted(wallXY.Values))
            {
                var wt = walls[Key(xy[0], xy[1])];
                if (wt.Mounted || wt.Arch || wt.Flag || wt.Beam) continue;
                long fk = Key(xy[0] + wt.Dx, xy[1] - wt.Dz);
                if (!interior.Contains(fk) || busy.Contains(fk) || taken.Contains(fk)) continue;
                if (Hash(xy[0], xy[1], 12) % 6 == 0) cands.Add(new Cand { Score = Hash(xy[0], xy[1], 13), Kind = 3, X = xy[0], Y = xy[1], Wall = wt });
            }
            cands.Sort((p, q) => p.Score != q.Score ? p.Score.CompareTo(q.Score) : p.X != q.X ? p.X.CompareTo(q.X) : p.Y.CompareTo(q.Y));
            var chosen = new List<Cand>();
            foreach (var c in cands)
            {
                if (chosen.Count >= MaxProps) break;
                long k = c.Kind == 3 ? Key(c.X + c.Wall.Dx, c.Y - c.Wall.Dz) : Key(c.X, c.Y);
                if (taken.Contains(k)) continue;
                taken.Add(k);
                chosen.Add(c);
            }
            chosen.Sort((p, q) => p.X != q.X ? p.X.CompareTo(q.X) : p.Y.CompareTo(q.Y));
            foreach (var c in chosen)
            {
                int h = Hash(c.X, c.Y, 11);
                if (c.Kind == 3)
                {
                    WallPos(origin, c.Wall, c.X, c.Y, WallFace - 0.19f, 0f, out float bx, out float bz);
                    list.Add(new RuinsPlacement { Piece = "Bookcase_Full", Role = RuinsRole.None, X = bx, Y = 0f, Z = bz, Yaw = c.Wall.Yaw });
                    continue;
                }
                var table = c.Kind == 2 ? OpenProps : EdgeProps;
                var prop = table[h % table.Length];
                float scale = prop.Scale > 0f ? prop.Scale : 0.3f + h / 3 % 4 * 0.05f;   // a broken column is a stump of any height
                float x = TileX(origin, c.X) + (h / 7 % 5 - 2) * 0.05f, z = TileZ(origin, c.Y) + (h / 11 % 5 - 2) * 0.05f;
                list.Add(new RuinsPlacement { Piece = prop.Piece, Role = RuinsRole.None, X = x, Y = 0f, Z = z, Yaw = h / 13 % 8 * 45f, Scale = scale });
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

        /// <summary>The colour of a pack material after the restyle, by the role of the piece that wears it. The pack's colours are
        /// bright cartoon values written for a linear workflow, and Unity reads them as sRGB, so they are first lifted (gamma),
        /// then pulled toward their luminance and darkened:
        ///   walls, columns, beams  x WallBrightness (0.42), blue-grey, contrast x 1.18: the gloomiest thing in the room
        ///   floor                  x FloorBrightness (0.55), warm brown dirt, so the torch pools read against it
        ///   stone props, statues   x StoneBrightness (0.5), cool grey
        ///   wood and metal         dark and desaturated, flags a dull dried red, bark dark brown
        ///   flames ("Fire", "Light") stay warm and emissive.
        /// `name` is the material name of the mtl file; r, g, b the mtl's Kd.</summary>
        public static RuinsStyle Restyle(string name, float r, float g, float b, RuinsRole role)
        {
            string n = (name ?? "").ToLowerInvariant();
            if (n.StartsWith("fire", StringComparison.Ordinal) || n.StartsWith("light", StringComparison.Ordinal))
                return new RuinsStyle { R = 1f, G = 0.55f, B = 0.14f, EmitR = 2.2f, EmitG = 1.0f, EmitB = 0.25f, Smoothness = 0f };
            r = Gamma(r); g = Gamma(g); b = Gamma(b);
            float lum = 0.299f * r + 0.587f * g + 0.114f * b;
            float keep, dark, contrast = 1f; float tr = 1f, tg = 1f, tb = 1f, smooth = 0.08f;
            if (n.Contains("wood")) { keep = 0.45f; dark = 0.5f; tr = 1.05f; tb = 0.92f; }
            else if (n.Contains("metal") || n.Contains("black")) { keep = 0.3f; dark = 0.5f; smooth = 0.3f; }
            else if (n.StartsWith("flag", StringComparison.Ordinal)) { keep = 0.7f; dark = 0.55f; }
            else if (n.StartsWith("green", StringComparison.Ordinal)) { keep = 0.8f; dark = 0.85f; tr = 0.95f; tg = 1.02f; tb = 0.9f; }   // leaves, grass, moss (World3d)
            else if (n.StartsWith("berry", StringComparison.Ordinal)) { keep = 0.8f; dark = 0.8f; }
            else if (n.StartsWith("bark", StringComparison.Ordinal)) { keep = 0f; dark = 0.32f; tr = 1.1f; tg = 0.95f; tb = 0.78f; }
            else if (n.StartsWith("candle", StringComparison.Ordinal) || n.Contains("pages")) { keep = 0.5f; dark = 0.75f; }
            else if (n.Contains("bone")) { keep = 0.5f; dark = 0.65f; }
            else if (n.StartsWith("book", StringComparison.Ordinal) || n.StartsWith("pot", StringComparison.Ordinal)) { keep = 0.5f; dark = 0.55f; }
            else if (role == RuinsRole.Wall || role == RuinsRole.Pillar || role == RuinsRole.Trim)
            { keep = 0.3f; dark = WallBrightness; contrast = WallContrast; tr = 0.88f; tg = 0.97f; tb = 1.14f; }
            else if (role == RuinsRole.Floor)
            { keep = 0.3f; dark = FloorBrightness; tr = 1.12f; tg = 1.0f; tb = 0.82f; }
            else { keep = 0.3f; dark = StoneBrightness; tr = 0.93f; tg = 0.98f; tb = 1.06f; }
            float mr = lum + (r - lum) * keep, mg = lum + (g - lum) * keep, mb = lum + (b - lum) * keep;
            if (contrast != 1f) { mr = 0.5f + (mr - 0.5f) * contrast; mg = 0.5f + (mg - 0.5f) * contrast; mb = 0.5f + (mb - 0.5f) * contrast; }
            return new RuinsStyle { R = Clamp01(mr * dark * tr), G = Clamp01(mg * dark * tg), B = Clamp01(mb * dark * tb), Smoothness = smooth };
        }

        /// <summary>The restyle of a piece with no role at hand (a prop).</summary>
        public static RuinsStyle Restyle(string name, float r, float g, float b) => Restyle(name, r, g, b, RuinsRole.None);
    }
}
