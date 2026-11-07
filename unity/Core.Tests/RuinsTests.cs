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

            // walls: 16 tiles (8 pieces of 2 cells), 3 courses each (a long run is one taller than its sprite), facing south, the face on the back side of the tile row cy - 5.
            // The middle two tiles hold an arch (2 tiles wide, 2 courses, a plain course above) instead of 4 plain pieces; a gothic arch holds a door.
            var wall = plan.Where(q => q.Role == RuinsRole.Wall).ToList();
            float backZ = Hd2dRuins.TileZ(origin, origin.Y - 5) + Hd2dRuins.WallFace;
            var arch = wall.Where(q => q.Piece.StartsWith("Wall_Arch", StringComparison.Ordinal)).ToList();
            var door = wall.Where(q => q.Piece == "Doors_GothicArch").ToList();
            check(arch.Count == 1 && door.Count == (arch[0].Piece == "Wall_ArchGothic" ? 1 : 0), "ruins: one arch in the back wall, a door only in the gothic one");
            float x0 = Hd2dRuins.TileX(origin, origin.X - 7), x1 = Hd2dRuins.TileX(origin, origin.X + 8);
            check(Near(arch[0].X, (x0 + x1) / 2f) && Near(arch[0].Y, 0f) && Near(arch[0].Yaw, 180f), "ruins: the arch is the middle piece of the back wall, on the floor, facing south");
            check(door.All(q => Near(q.X, arch[0].X, 0.01f) && q.Z > arch[0].Z && q.Z < arch[0].Z + 0.1f), "ruins: the door stands in the arch");
            var plain = wall.Where(q => !q.Piece.StartsWith("Wall_Arch", StringComparison.Ordinal) && q.Piece != "Doors_GothicArch").ToList();
            check(plain.Count == 16 * 3 - 4, "ruins: 16 tiles of 3 courses (a long run is one course taller) minus the 4 the arch fills: " + plain.Count);
            check(wall.All(q => Near(q.Yaw, 180f) || q.Piece == "Wall_Half"), "ruins: the back wall faces south, into the room (a half wall is turned round)");
            check(plain.Where(q => q.Piece != "Wall_Half").All(q => Near(q.Z, backZ)), "ruins: the wall face stands on the back side of its tile");
            check(plain.Select(q => q.Y).Distinct().OrderBy(y => y).SequenceEqual(new[] { 0f, 1f, 2f }), "ruins: courses stack one tile high");
            check(plain.Where(q => q.Y < 1.5f).All(q => q.Piece == "Wall"), "ruins: the lower courses are plain wall");
            var top = plain.Where(q => Near(q.Y, 2f)).Select(q => q.Piece).Distinct().ToList();
            check(top.Count >= 3 && top.All(n => n == "Wall" || n == "Wall_Broken" || n == "Wall_Hole" || n == "Wall_Half" || n == "Window_Bars"), "ruins: the top course has variety: " + string.Join(",", top));
            var flags = plan.Where(q => q.Piece == "Flag_Wall").ToList();
            check(flags.Count >= 1 && flags.All(q => Near(q.Yaw, 180f) && q.Z < backZ && q.Z > backZ - 0.25f), "ruins: banners hang on the wall faces: " + flags.Count);
            check(Hd2dRuins.ArchIndex(5, i => true) == -1 && Hd2dRuins.ArchIndex(16, i => true) == 7 && Hd2dRuins.ArchIndex(6, i => true) == 2, "ruins: the arch goes in the middle of a long run, none in a short one");
            int aside = Hd2dRuins.ArchIndex(16, i => i != 7 && i != 8);
            check(aside == 8 || aside == 9 || aside == 5, "ruins: the arch steps aside from a torch: " + aside);

            // lights: torches hang in front of the wall face, the loose one is candles on a short column
            var torch = plan.Where(q => q.Piece == "Torch").ToList();
            check(torch.Count == 2 && torch.All(q => Near(q.Yaw, 180f) && Near(q.Y, Hd2dRuins.TorchY) && q.Z < backZ && q.Z > backZ - 0.25f), "ruins: two torches hang on the back wall, just in front of its face");
            check(plan.Count(q => q.Role == RuinsRole.Light && q.Piece.StartsWith("Candles", StringComparison.Ordinal)) == 1 && plan.Count(q => q.Role == RuinsRole.Light && q.Piece == "Column_Round_Short") == 1, "ruins: the loose torch becomes candles on a short column");
            var pillars = plan.Where(q => q.Role == RuinsRole.Pillar).ToList();
            check(pillars.Count == 4 && pillars.All(q => q.Piece.StartsWith("Column_", StringComparison.Ordinal) && Near(q.Y, 0f)), "ruins: four pillars become columns on the floor");
            check(!wall.Any(q => (q.Piece == "Window_Bars" || q.Piece == "Wall_Hole" || q.Piece == "Wall_Half" || q.Piece == "Wall_Broken") && torch.Any(t => Math.Abs(t.X - q.X) < 0.3f)), "ruins: no window, hole or broken piece behind a torch");
            var beams = plan.Where(q => q.Piece == "Support_Tall").ToList();
            check(beams.All(q => q.Role == RuinsRole.Trim && Near(q.Y, 0f) && q.Z < backZ + 0.01f), "ruins: beams stand against the wall: " + beams.Count);

            // corners: a statue on a plinth at each end of the back wall, a dead tree and a broken column at the far end
            var statues = plan.Where(q => q.Piece.StartsWith("Statue_", StringComparison.Ordinal)).ToList();
            float frontZ = Hd2dRuins.TileZ(origin, origin.Y - 4);
            check(statues.Count == 2 && statues.Any(q => q.Piece == "Statue_Stag") && statues.Any(q => q.Piece == "Statue_Fox"), "ruins: a stag and a fox statue");
            check(statues.All(q => Math.Abs(q.Z - frontZ) < 0.2f && Near(q.Y, 0.4f)) && statues.Min(q => q.X) < x0 + 0.3f && statues.Max(q => q.X) > x1 - 0.3f, "ruins: the statues stand on plinths at the two ends of the back wall");
            var plinths = plan.Where(q => q.Piece == "Column_Square" && q.ScaleY > 0f).ToList();
            check(plinths.Count == 2 && plinths.All(q => statues.Any(s2 => Math.Abs(s2.X - q.X) < 0.2f && Math.Abs(s2.Z - q.Z) < 0.2f)), "ruins: each statue has a squat plinth");
            float farZ = Hd2dRuins.TileZ(origin, origin.Y + 7);
            var trees = plan.Where(q => q.Piece.StartsWith("DeadTree_", StringComparison.Ordinal)).ToList();
            check(trees.Count == 1 && Math.Abs(trees[0].Z - farZ) < 0.6f, "ruins: one dead tree in a far corner");

            // props: many, never on a tile that holds anything, never on or beside the carpet or a creature
            var wallMounted = new HashSet<string> { "Bookcase_Full", "Flag_Wall" };
            var floorProps = plan.Where(q => q.Role == RuinsRole.None && !wallMounted.Contains(q.Piece)).ToList();
            int propCount = plan.Count(q => q.Role == RuinsRole.None && Array.IndexOf(new[] { "Barrel", "Crate", "Chest", "Pot1", "Pot2", "Pot3", "Pot1_Broken", "Pot2_Broken", "Pot3_Broken", "Skull", "Candles_1", "Candles_2", "Bookcase_Full" }, q.Piece) >= 0
                                                       || q.Role == RuinsRole.None && (q.Piece == "Bricks" || q.Piece == "Column_Round_Short"));
            check(propCount >= 15 && propCount <= Hd2dRuins.MaxProps + 2, "ruins: 15 or more props, at most the limit " + Hd2dRuins.MaxProps + " (+2 for the corner column and rubble): " + propCount);
            var busy = new HashSet<string>();
            foreach (var p in dl)
            {
                if (p.Kind == Hd2dKind.Floor || p.Kind == Hd2dKind.Border) continue;
                int m = p.Creature != null || p.Flat || p.Kind == Hd2dKind.Decal ? 1 : 0;
                for (int x = p.Tile.X - Math.Max(1, p.Width) + 1 - m; x <= p.Tile.X + m; x++)
                    for (int y = p.Tile.Y - Math.Max(1, p.Height) + 1 - m; y <= p.Tile.Y + m; y++) busy.Add(x + "," + y);
            }
            bool free = true;
            var onTile = new List<string>();
            foreach (var q in floorProps)
            {
                int tx = (int)Math.Floor(q.X) + origin.X, ty = (int)Math.Round(-(q.Z + 0.5f)) + origin.Y;
                if (busy.Contains(tx + "," + ty)) free = false;
                onTile.Add(tx + "," + ty);
            }
            check(free, "ruins: nothing stands on a tile that holds an item, a creature or the carpet, or beside the carpet or a creature");
            var carpet = dl.First(p => p.Width == 2 && p.Height == 3);
            bool clear = true;
            foreach (var t in onTile)
            {
                var xy = t.Split(',');
                int px = int.Parse(xy[0]), py = int.Parse(xy[1]);
                if (px >= carpet.Tile.X - carpet.Width && px <= carpet.Tile.X + 1 && py >= carpet.Tile.Y - carpet.Height && py <= carpet.Tile.Y + 1) clear = false;
                foreach (var c in dl.Where(p => p.Creature != null)) if (Math.Abs(px - c.Tile.X) <= 1 && Math.Abs(py - c.Tile.Y) <= 1) clear = false;
            }
            check(clear, "ruins: the carpet stays a sprite with nothing on or beside it, creatures have room: " + string.Join(" ", onTile) + " carpet " + carpet.Tile.X + "," + carpet.Tile.Y + " w" + carpet.Width + " h" + carpet.Height + " c " + origin.X + "," + origin.Y);
            check(onTile.Distinct().Count() >= onTile.Count - 3, "ruins: props do not pile on one tile");
            var books = plan.Where(q => q.Piece == "Bookcase_Full").ToList();
            check(books.All(q => q.Z < backZ + 0.01f && Near(q.Yaw, 180f)), "ruins: bookcases stand against the wall");
            check(new[] { "Barrel", "Crate", "Chest", "Skull", "Candles_1", "Pot1_Broken", "Statue_Stag", "DeadTree_3", "Support_Tall" }.All(n => Array.IndexOf(Hd2dRuins.AllPieces, n) >= 0), "ruins: the new pieces are listed");

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

            // a run of one-cell walls at the west edge of a floor faces east, its face on the west side of the tile
            var fl = new ThingType { Category = ThingCategory.Item, Id = 1, Ground = true, Groups = new[] { One() } };
            var wl = new ThingType { Category = ThingCategory.Item, Id = 2, OnBottom = true, NotWalkable = true, Groups = new[] { One() } };
            var side = new List<Hd2dPiece>
            {
                new Hd2dPiece { Kind = Hd2dKind.Floor, Type = fl, Tile = new Pos(99, 100, 7) },
                new Hd2dPiece { Kind = Hd2dKind.Floor, Type = fl, Tile = new Pos(100, 100, 7) },
                new Hd2dPiece { Kind = Hd2dKind.Billboard, Type = wl, Tile = new Pos(99, 100, 7), Width = 1, Height = 1 },
                new Hd2dPiece { Kind = Hd2dKind.Floor, Type = fl, Tile = new Pos(99, 101, 7) },
                new Hd2dPiece { Kind = Hd2dKind.Floor, Type = fl, Tile = new Pos(100, 101, 7) },
                new Hd2dPiece { Kind = Hd2dKind.Billboard, Type = wl, Tile = new Pos(99, 101, 7), Width = 1, Height = 1 },
            };
            var sp = Hd2dRuins.Plan(side, origin);
            var sw = sp.Where(q => q.Role == RuinsRole.Wall).ToList();
            check(sw.Count == 2 && sw.All(q => Near(q.Yaw, 90f)) && Near(sw[1].X, sw[0].X) && Near(sw[0].X, Hd2dRuins.TileX(origin, 99) - Hd2dRuins.WallFace) && Near(sw[0].Y, 0f), "ruins: a west edge wall faces east and is one course");
            // a lone blocking on-bottom piece (the temple pillar) is a column, not a wall
            var lone = new List<Hd2dPiece> { side[0], side[1], side[2] };
            var lp = Hd2dRuins.Plan(lone, origin);
            check(lp.Count(q => q.Role == RuinsRole.Wall) == 0 && lp.Count(q => q.Role == RuinsRole.Pillar) == 1, "ruins: a lone on-bottom blocker becomes a column");
            check(Hd2dRuins.Plan(new List<Hd2dPiece>(), origin).Count == 0, "ruins: an empty layout plans nothing");

            // the restyle: walls and columns the gloomiest, floor darker than before and warm, flames lit
            Func<RuinsStyle, float> lum = t => 0.299f * t.R + 0.587f * t.G + 0.114f * t.B;
            var stone = Hd2dRuins.Restyle("Main", 0.127169f, 0.129624f, 0.099817f, RuinsRole.Wall);
            var floor = Hd2dRuins.Restyle("Main", 0.127169f, 0.129624f, 0.099817f, RuinsRole.Floor);
            check(lum(stone) < 0.2f && lum(stone) > 0.06f && stone.B > stone.R && !stone.Emissive, "ruins: wall stone is dark and blue-grey: " + stone.R + "," + stone.G + "," + stone.B);
            check(lum(floor) < 0.3f && floor.R > floor.B && lum(floor) > lum(stone), "ruins: the floor is dark with a warm brown tint, brighter than the wall: " + floor.R + "," + floor.G + "," + floor.B);
            check(lum(stone) / lum(floor) < 0.85f && lum(stone) / lum(floor) > 0.5f, "ruins: the wall is about 0.42 / 0.55 of the floor: " + (lum(stone) / lum(floor)));
            var hi = Hd2dRuins.Restyle("Highlights", 0.231946f, 0.23655f, 0.180764f, RuinsRole.Pillar);
            check(lum(hi) > lum(stone) && lum(hi) < 0.3f, "ruins: the lighter wall trim keeps its contrast");
            check(Math.Abs(lum(Hd2dRuins.Restyle("Main", 0.127169f, 0.129624f, 0.099817f, RuinsRole.Trim)) - lum(stone)) < 1e-5f, "ruins: a beam is dark like a wall");
            var statue = Hd2dRuins.Restyle("Stone", 0.119897f, 0.119897f, 0.119897f, RuinsRole.None);
            check(lum(statue) > lum(Hd2dRuins.Restyle("Stone", 0.119897f, 0.119897f, 0.119897f, RuinsRole.Wall)), "ruins: a statue reads against the wall behind it");
            var fire = Hd2dRuins.Restyle("Fire", 0.4569f, 0.136222f, 0.019765f, RuinsRole.Light);
            check(fire.Emissive && fire.R > fire.G && fire.G > fire.B && fire.EmitR >= 1f, "ruins: a flame stays warm and emissive");
            check(Hd2dRuins.Restyle("Light", 0.55f, 0.08f, 0.05f, RuinsRole.Light).Emissive, "ruins: a candle flame is emissive");
            var wood = Hd2dRuins.Restyle("Wood", 0.12234f, 0.083516f, 0.041304f, RuinsRole.None);
            check(wood.R > wood.B && lum(wood) < 0.2f && !wood.Emissive && (wood.R - wood.B) < 0.1f, "ruins: wood stays brown but dark and dull: " + wood.R + "," + wood.G + "," + wood.B);
            var flag = Hd2dRuins.Restyle("Flag", 0.210681f, 0.067752f, 0.018038f, RuinsRole.None);
            check(flag.R > flag.G && flag.R < 0.4f && !flag.Emissive, "ruins: a banner is a dull dark red: " + flag.R + "," + flag.G + "," + flag.B);
            var bark = Hd2dRuins.Restyle("Bark", 0.64f, 0.64f, 0.64f, RuinsRole.None);
            check(bark.R > bark.B && bark.R < 0.35f, "ruins: a dead tree is dark brown, not the pack's pale grey: " + bark.R);
            check(Hd2dRuins.Restyle("DarkMetal", 0.033179f, 0.029635f, 0.048573f, RuinsRole.Wall).R < 0.3f, "ruins: metal is dark");
            var wild = Hd2dRuins.Restyle(null, 5f, -2f, 1f, RuinsRole.Wall);
            check(wild.R <= 1f && wild.G >= 0f, "ruins: the restyle clamps");
            check(Hd2dRuins.Restyle("Main", 0.127169f, 0.129624f, 0.099817f).R == Hd2dRuins.Restyle("Main", 0.127169f, 0.129624f, 0.099817f, RuinsRole.None).R, "ruins: no role means a stone prop");

            // the back wall is inside the frame of the demo camera at its normal fit: base and top of a 2 tile wall project onto the screen
            var pose = Hd2dCamera.ForTile(origin.X, origin.Y, origin, 1200f / 880f, 40f, 25f);
            float wz = Hd2dRuins.TileZ(origin, origin.Y - 5) + Hd2dRuins.WallFace;
            bool baseIn = pose.Project(new Vec3(0.5f, 0f, wz), out float bnx, out float bny), topIn = pose.Project(new Vec3(0.5f, 3f, wz), out float tnx, out float tny);
            check(baseIn && topIn && Math.Abs(bny) < 1f && Math.Abs(tny) < 1f && tny > bny + 0.1f, "ruins: the 3 tile back wall is in frame, " + (tny - bny).ToString("0.00") + " of the half height tall");

            // the shipped files
            string found = Find();
            if (found == null) { check(true, "ruins: Resources/Ruins3d not found from here, file checks skipped"); return; }
            check(Hd2dRuins.AllPieces.All(n => File.Exists(Path.Combine(found, n + ".obj")) && File.Exists(Path.Combine(found, n + ".mtl"))), "ruins: every piece of the plan has its .obj and .mtl");
            check(File.Exists(Path.Combine(found, "License.txt")) && File.ReadAllText(Path.Combine(found, "License.txt")).Contains("CC0"), "ruins: the pack's CC0 licence text ships with the models");
        }
    }
}
