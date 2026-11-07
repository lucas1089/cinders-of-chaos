// Checks of the 3D architecture test (Core/Hd2dRuins.cs): which sprite pieces a 3D piece replaces, which piece stands on which
// tile and how it is turned, the props, and the dark fantasy restyle.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class RuinsTests
    {
        static bool Near(float a, float b, float eps = 1e-3f) => Math.Abs(a - b) <= eps;

        static FrameGroup One() => new FrameGroup { Width = 1, Height = 1, Layers = 1, PatternX = 1, PatternY = 1, PatternZ = 1, Phases = 1, Sprites = new uint[1] };

        static string Find()
        {
            string dir = AppContext.BaseDirectory;
            for (int i = 0; i < 10 && dir != null; i++, dir = Path.GetDirectoryName(dir))
            {
                foreach (var rel in new[] { "Client", "unity/Client" })
                {
                    string c = Path.Combine(dir, rel, "Assets", "Chaos", "Resources", "Ruins3d");
                    if (Directory.Exists(c)) return c;
                }
            }
            return null;
        }

        public static void Run(Action<bool, string> check)
        {
            var demo = Hd2dDemo.Synthetic();
            var origin = demo.Center;
            var dl = Hd2d.Layout(demo.World, origin, 40f, null, false);

            // roles
            var roles = dl.GroupBy(p => Hd2dRuins.RoleOf(p)).ToDictionary(g => g.Key, g => g.Count());
            check(roles[RuinsRole.Floor] == 18 * 14 && roles[RuinsRole.Border] == 15 && roles[RuinsRole.Wall] == 8 && roles[RuinsRole.Pillar] == 4 && roles[RuinsRole.Light] == 3,
                  "ruins: roles of the demo room: floor, border, 8 wall pieces, 4 pillars, 3 lights");
            check(dl.Where(p => p.Creature != null || p.Kind == Hd2dKind.Decal).All(p => !Hd2dRuins.Replaces(p)), "ruins: creatures and decals (the carpet) stay sprites");
            check(Hd2dRuins.RoleOf(null) == RuinsRole.None, "ruins: no piece, no role");

            // the plan
            var plan = Hd2dRuins.Plan(dl, origin);
            var again = Hd2dRuins.Plan(dl, origin);
            check(plan.Count == again.Count && plan.Zip(again, (a, b) => a.ToString() == b.ToString()).All(x => x), "ruins: the plan is deterministic");
            check(plan.All(q => Array.IndexOf(Hd2dRuins.AllPieces, q.Piece) >= 0) && Hd2dRuins.Required.All(n => Array.IndexOf(Hd2dRuins.AllPieces, n) >= 0), "ruins: every placed and required piece is a pack file we ship");
            var floors = plan.Where(q => q.Role == RuinsRole.Floor).ToList();
            check(floors.Count == 18 * 14 && floors.All(q => Near(q.Y, Hd2dRuins.FloorY) && Near(q.Scale, 0.5f)), "ruins: one floor piece per ground tile, under the flat sprites, at pack scale 0.5");
            check(floors.Select(q => q.X.ToString("0.##") + "," + q.Z.ToString("0.##")).Distinct().Count() == floors.Count, "ruins: floors sit on different tiles");
            check(floors.Any(q => q.Piece == "Floor_Standard") && floors.Any(q => q.Piece == "Floor_Squares"), "ruins: the checker pattern uses both floor pieces");

            // walls: 16 tiles (8 pieces of 2 cells), 2 courses each, facing south, the face on the back side of the tile row cy - 5
            var wall = plan.Where(q => q.Role == RuinsRole.Wall).ToList();
            float backZ = Hd2dRuins.TileZ(origin, origin.Y - 5) + Hd2dRuins.WallFace;
            check(wall.Count == 16 * 2, "ruins: a 2 x 2 wall piece gives 2 tiles of 2 courses: " + wall.Count);
            check(wall.All(q => Near(q.Yaw, 180f)), "ruins: the back wall faces south, into the room");
            check(wall.All(q => Near(q.Z, backZ)), "ruins: the wall face stands on the back side of its tile");
            check(wall.Select(q => q.Y).Distinct().OrderBy(y => y).SequenceEqual(new[] { 0f, 1f }), "ruins: courses stack one tile high");
            check(wall.Where(q => Near(q.Y, 0f)).All(q => q.Piece == "Wall") && wall.Select(q => q.X).Distinct().Count() == 16, "ruins: the bottom course is plain wall, 16 columns, none doubled");

            // lights: torches hang in front of the wall face, the loose one is candles on a short column
            var torch = plan.Where(q => q.Piece == "Torch").ToList();
            check(torch.Count == 2 && torch.All(q => Near(q.Yaw, 180f) && Near(q.Y, Hd2dRuins.TorchY) && q.Z < backZ && q.Z > backZ - 0.25f), "ruins: two torches hang on the back wall, just in front of its face");
            check(plan.Count(q => q.Piece.StartsWith("Candles", StringComparison.Ordinal)) == 1 && plan.Count(q => q.Piece == "Column_Round_Short") == 1, "ruins: the loose torch becomes candles on a short column");
            var pillars = plan.Where(q => q.Role == RuinsRole.Pillar).ToList();
            check(pillars.Count == 4 && pillars.All(q => q.Piece.StartsWith("Column_", StringComparison.Ordinal) && Near(q.Y, 0f)), "ruins: four pillars become columns on the floor");
            check(!wall.Any(q => q.Piece == "Window_Bars" && torch.Any(t => Near(t.X, q.X))), "ruins: no window behind a torch");

            // props: few, in front of the wall, never on a tile that holds another thing
            var props = plan.Where(q => q.Role == RuinsRole.None).ToList();
            check(props.Count <= Hd2dRuins.MaxProps, "ruins: at most " + Hd2dRuins.MaxProps + " props: " + props.Count);
            var busy = new HashSet<string>(dl.Where(p => p.Kind != Hd2dKind.Floor && p.Kind != Hd2dKind.Border).Select(p => p.Tile.X + "," + p.Tile.Y));
            bool free = true, front = true;
            foreach (var q in props.Where(q => q.Piece != "Bookcase_Full"))
            {
                int tx = (int)Math.Floor(q.X) + origin.X, ty = (int)Math.Round(-(q.Z + 0.5f)) + origin.Y;
                if (busy.Contains(tx + "," + ty)) free = false;
                if (ty != origin.Y - 4) front = false;
            }
            check(free && front, "ruins: props stand on the free row in front of the wall");

            // facing: south first, then east, west, north
            Hd2dRuins.Facing((x, y) => y == 6, 5, 5, out int dx, out int dz, out float yaw);
            check(dx == 0 && dz == -1 && Near(yaw, 180f), "ruins: open to the south faces south");
            Hd2dRuins.Facing((x, y) => x == 6, 5, 5, out dx, out dz, out yaw);
            check(dx == 1 && dz == 0 && Near(yaw, 90f), "ruins: open to the east faces east (yaw 90)");
            Hd2dRuins.Facing((x, y) => x == 4, 5, 5, out dx, out dz, out yaw);
            check(dx == -1 && dz == 0 && Near(yaw, 270f), "ruins: open to the west faces west (yaw 270)");
            Hd2dRuins.Facing((x, y) => y == 4, 5, 5, out dx, out dz, out yaw);
            check(dx == 0 && dz == 1 && Near(yaw, 0f), "ruins: open to the north faces north (yaw 0)");
            Hd2dRuins.Facing((x, y) => false, 5, 5, out dx, out dz, out yaw);
            check(dz == -1 && Near(yaw, 180f), "ruins: a closed wall faces south");

            // a one-cell wall at the west edge of a floor faces east, its face on the west side of the tile
            var fl = new ThingType { Category = ThingCategory.Item, Id = 1, Ground = true, Groups = new[] { One() } };
            var wl = new ThingType { Category = ThingCategory.Item, Id = 2, OnBottom = true, NotWalkable = true, Groups = new[] { One() } };
            var side = new List<Hd2dPiece>
            {
                new Hd2dPiece { Kind = Hd2dKind.Floor, Type = fl, Tile = new Pos(99, 100, 7) },
                new Hd2dPiece { Kind = Hd2dKind.Floor, Type = fl, Tile = new Pos(100, 100, 7) },
                new Hd2dPiece { Kind = Hd2dKind.Billboard, Type = wl, Tile = new Pos(99, 100, 7), Width = 1, Height = 1 },
            };
            var sp = Hd2dRuins.Plan(side, origin);
            var sw = sp.Where(q => q.Role == RuinsRole.Wall).ToList();
            check(sw.Count == 1 && Near(sw[0].Yaw, 90f) && Near(sw[0].X, Hd2dRuins.TileX(origin, 99) - Hd2dRuins.WallFace) && Near(sw[0].Y, 0f), "ruins: a west edge wall faces east and is one course");
            check(Hd2dRuins.Plan(new List<Hd2dPiece>(), origin).Count == 0, "ruins: an empty layout plans nothing");

            // the restyle
            var stone = Hd2dRuins.Restyle("Main", 0.127169f, 0.129624f, 0.099817f);
            check(stone.R < 0.45f && stone.R > 0.1f && Math.Abs(stone.R - stone.G) < 0.06f && stone.B >= stone.R && !stone.Emissive, "ruins: stone goes cold grey and dark: " + stone.R + "," + stone.G + "," + stone.B);
            var fire = Hd2dRuins.Restyle("Fire", 0.4569f, 0.136222f, 0.019765f);
            check(fire.Emissive && fire.R > fire.G && fire.G > fire.B && fire.EmitR >= 1f, "ruins: a flame stays warm and emissive");
            check(Hd2dRuins.Restyle("Light", 0.55f, 0.08f, 0.05f).Emissive, "ruins: a candle flame is emissive");
            var wood = Hd2dRuins.Restyle("Wood", 0.12234f, 0.083516f, 0.041304f);
            check(wood.R > wood.B && wood.R < 0.45f && !wood.Emissive, "ruins: wood stays brown but dark");
            check(Hd2dRuins.Restyle("DarkMetal", 0.033179f, 0.029635f, 0.048573f).R < 0.3f, "ruins: metal is dark");
            var wild = Hd2dRuins.Restyle(null, 5f, -2f, 1f);
            check(wild.R <= 1f && wild.G >= 0f, "ruins: the restyle clamps");

            // the shipped files
            string found = Find();
            if (found == null) { check(true, "ruins: Resources/Ruins3d not found from here, file checks skipped"); return; }
            check(Hd2dRuins.AllPieces.All(n => File.Exists(Path.Combine(found, n + ".obj")) && File.Exists(Path.Combine(found, n + ".mtl"))), "ruins: every piece of the plan has its .obj and .mtl");
            check(File.Exists(Path.Combine(found, "License.txt")) && File.ReadAllText(Path.Combine(found, "License.txt")).Contains("CC0"), "ruins: the pack's CC0 licence text ships with the models");
        }
    }
}
