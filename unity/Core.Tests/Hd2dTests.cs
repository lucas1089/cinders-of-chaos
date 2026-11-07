// Checks of the HD-2D scene layout (O432): classification of dat things, footprints and offsets, light colours and the light
// list, the camera keeping the 15 x 11 view, and the synthetic demo room (its dat and spr bytes).
using System;
using System.IO;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class Hd2dTests
    {
        static ThingType T(Action<ThingType> set, int w = 1, int h = 1)
        {
            var t = new ThingType { Category = ThingCategory.Item, Id = 100, Groups = new[] { new FrameGroup { Width = w, Height = h, ExactSize = 32 * Math.Max(w, h), Layers = 1, PatternX = 1, PatternY = 1, PatternZ = 1, Phases = 1, Sprites = new uint[w * h] } } };
            set(t);
            return t;
        }

        static bool Near(float a, float b, float eps = 1e-3f) => Math.Abs(a - b) <= eps;

        public static void Run(Action<bool, string> check)
        {
            // ---- classification
            check(Hd2d.Classify(null) == Hd2dKind.None, "hd2d: no type, no piece");
            check(Hd2d.Classify(T(t => t.Ground = true)) == Hd2dKind.Floor, "hd2d: ground is a floor quad");
            check(Hd2d.Classify(T(t => t.GroundBorder = true)) == Hd2dKind.Border, "hd2d: ground border is flat");
            check(Hd2d.Classify(T(t => t.Splash = true)) == Hd2dKind.Decal, "hd2d: a splash lies on the floor");
            check(Hd2d.Classify(T(t => t.Lying = true, 1, 1)) == Hd2dKind.Decal, "hd2d: a lying item lies on the floor");
            check(Hd2d.Classify(T(t => { t.OnBottom = true; t.NotWalkable = true; }, 2, 2)) == Hd2dKind.Billboard, "hd2d: a blocking on-bottom item (wall) stands");
            check(Hd2d.Classify(T(t => t.OnBottom = true)) == Hd2dKind.Decal, "hd2d: a walkable on-bottom item is flat");
            check(Hd2d.Classify(T(t => t.OnTop = true)) == Hd2dKind.OnTop, "hd2d: an on-top item stands in front");
            check(Hd2d.Classify(T(t => t.NotWalkable = true, 2, 2)) == Hd2dKind.Billboard, "hd2d: a blocking common item (pillar) stands at the back edge");
            check(Hd2d.Classify(T(t => t.Pickupable = true)) == Hd2dKind.Object, "hd2d: a pickupable item is an object");
            check(Hd2d.Classify(T(t => t.NotMoveable = true, 3, 4)) == Hd2dKind.Decal, "hd2d: a large walkable decoration (carpet) lies flat");
            check(Hd2d.Classify(T(t => { t.NotMoveable = true; t.LightLevel = 5; }, 2, 2)) == Hd2dKind.Object, "hd2d: a large item with a light stands");
            check(Hd2d.Classify(T(t => t.Container = true, 2, 2)) == Hd2dKind.Object, "hd2d: a large container stands");

            // ---- footprint, offsets, stretch
            var origin = new Pos(100, 100, 7);
            var wallType = T(t => { t.OnBottom = true; t.NotWalkable = true; }, 2, 2);
            var tile = new Tile(new Pos(103, 98, 7));
            tile.Things.Add(new Thing { Item = new Item { Id = 1, Type = T(t => { t.Ground = true; }) } });
            tile.Things.Add(new Thing { Item = new Item { Id = 2, Type = wallType } });
            var dat = DatFile.Parse(Program.SyntheticDat());
            var pieces = new System.Collections.Generic.List<Hd2dPiece>();
            float stretch = Hd2d.StretchFor(40f);
            check(Near(stretch, 1f / (float)Math.Cos(40 * Math.PI / 180)) && stretch > 1.3f, "hd2d: stretch is 1 / cos(pitch)");
            Hd2d.LayoutTile(dat, tile, origin, stretch, pieces);
            check(pieces.Count == 2 && pieces[0].Kind == Hd2dKind.Floor && pieces[1].Kind == Hd2dKind.Billboard, "hd2d: a tile stack gives a floor and a wall");
            var floor = pieces[0].Cell(0, 0);
            check(Near(floor[0].X, 3f) && Near(floor[1].X, 4f) && Near(floor[0].Z, 1f) && Near(floor[3].Z, 2f) && Near(floor[0].Y, 0f), "hd2d: the floor quad covers its own tile (x 3..4, z 1..2 north of the origin)");
            var wall = pieces[1];
            check(Near(wall.Z, 2f - 0.0015f), "hd2d: a wall stands at the tile's back (north) edge, a hair towards the camera per stack index: " + wall.Z);
            var c00 = wall.Cell(0, 0);
            var c10 = wall.Cell(1, 0);
            var c01 = wall.Cell(0, 1);
            check(Near(c00[1].X, 4f) && Near(c00[0].X, 3f) && Near(c10[0].X, 2f) && Near(c10[1].X, 3f), "hd2d: a 64 px item extends west of its east-edge anchor, footprint x 2..4");
            check(Near(c00[2].Y - c00[1].Y, stretch) && Near(c01[0].Y, c00[3].Y), "hd2d: cells stack upwards, each one stretch high");
            var c11 = wall.Cell(1, 1);
            check(Near(wall.Shear, 1f) && Near(c00[2].X, 5f) && Near(c11[0].X, 3f) && Near(c11[1].X, 4f),
                "hd2d: a 2 x 2 wall leans one tile east per cell: its top-left cell sits over its base (x 3..4)");
            check(Near(Hd2d.ShearFor(Hd2dKind.Creature, 2, 2), 0f) && Near(Hd2d.ShearFor(Hd2dKind.Object, 1, 2), 0f) && Near(Hd2d.ShearFor(Hd2dKind.Object, 2, 1), 0f) && Near(Hd2d.ShearFor(Hd2dKind.Object, 2, 2), 0f)
                && Near(Hd2d.ShearFor(Hd2dKind.OnTop, 2, 2), 1f) && Near(Hd2d.ShearFor(Hd2dKind.Decal, 2, 2), 0f),
                "hd2d: no shear for creatures, loose objects, one-cell-wide or one-cell-high things, or flat things");
            var shifted = T(t => { t.Ground = true; t.DisplacementX = 8; t.DisplacementY = 16; });
            var t2 = new Tile(new Pos(100, 100, 7));
            t2.Things.Add(new Thing { Item = new Item { Id = 3, Type = shifted } });
            pieces.Clear();
            Hd2d.LayoutTile(dat, t2, origin, stretch, pieces);
            var sc = pieces[0].Cell(0, 0);
            check(Near(sc[1].X, 1f - 0.25f) && Near(sc[2].Z, 0.5f), "hd2d: displacement moves a flat quad west and north");

            // elevation lifts what is above it in the stack
            var t3 = new Tile(new Pos(100, 100, 7));
            t3.Things.Add(new Thing { Item = new Item { Id = 4, Type = T(t => { t.NotWalkable = true; t.Elevation = 16; }) } });
            t3.Things.Add(new Thing { Item = new Item { Id = 5, Type = T(t => t.Pickupable = true) } });
            pieces.Clear();
            Hd2d.LayoutTile(dat, t3, origin, 1f, pieces);
            check(pieces.Count == 2 && Near(pieces[0].Y, 0f) && Near(pieces[1].Y, 0.5f), "hd2d: elevation 16 lifts the next item by half a tile");

            // ---- light colours
            Hd2d.ColorFromIndex(0, out int r, out int g, out int b);
            check(r == 0 && g == 0 && b == 0, "hd2d: colour 0 is black");
            Hd2d.ColorFromIndex(215, out r, out g, out b);
            check(r == 255 && g == 255 && b == 255, "hd2d: colour 215 is white");
            Hd2d.ColorFromIndex(206, out r, out g, out b);
            check(r == 255 && g == 204 && b == 102, "hd2d: colour 206 is the torch orange (255, 204, 102)");
            Hd2d.ColorFromIndex(36, out r, out g, out b);
            check(r == 51 && g == 0 && b == 0, "hd2d: colour 36 is dark red");
            Hd2d.ColorFromIndex(6 + 1, out r, out g, out b);
            check(r == 0 && g == 51 && b == 51, "hd2d: colour 7 is dark cyan");
            Hd2d.ColorFromIndex(216, out r, out g, out b);
            check(r == 0 && g == 0 && b == 0, "hd2d: colours from 216 are black");

            // ---- lights from a synthetic map
            var world = new World(dat) { Center = origin };
            var torch = new ThingType { Category = ThingCategory.Item, Id = 150, OnBottom = true, NotWalkable = true, LightLevel = 6, LightColor = 206, Groups = wallType.Groups };
            var plain = T(t => t.Ground = true);
            foreach (var (x, y) in new[] { (96, 98), (104, 98), (100, 104) })
            {
                world.AddThing(new Pos(x, y, 7), new Thing { Item = new Item { Id = 1, Type = plain } });
                world.AddThing(new Pos(x, y, 7), new Thing { Item = new Item { Id = 150, Type = torch } });
            }
            var lamp = new Creature { Id = 9, LightLevel = 3, LightColor = 0, Outfit = new Outfit(1, 0, 0, 0, 0) };
            world.Creatures[9] = lamp;
            world.AddThing(new Pos(100, 100, 7), new Thing { Creature = lamp });
            world.AddThing(new Pos(100, 100, 6), new Thing { Item = new Item { Id = 150, Type = torch } });   // another floor: not laid out
            var lay = Hd2d.Layout(world, origin, 40f);
            var lights = Hd2d.Lights(lay, new Vec3(0.5f, 0f, -0.5f), 10);
            check(lights.Count == 4, "hd2d: three torches and a lantern are four lights: " + lights.Count);
            check(lights[0].R == 1f && lights[0].G == 1f && lights[0].B == 1f && lights[0].Range == 3f, "hd2d: nearest light first, colour 0 means white");
            var warm = lights.First(l => l.Range == 6f);
            check(Near(warm.R, 1f) && Near(warm.G, 0.8f) && Near(warm.B, 0.4f), "hd2d: the torch light is warm orange");
            var back = lights.First(l => l.Range == 6f && l.Position.Z > 0f);
            check(Near(back.Position.Z, 2f - 0.4f - 0.0015f * 1, 0.005f), "hd2d: a wall light hangs in front of its wall: " + back.Position.Z);
            check(Hd2d.Lights(lay, new Vec3(0.5f, 0f, -0.5f), 2).Count == 2, "hd2d: the light count is capped");
            var far = Hd2d.Lights(lay, new Vec3(100f, 0f, 100f), 1)[0];
            check(far.Range == 6f, "hd2d: nearest to the focus, not to the origin");

            // ---- camera
            foreach (float aspect in new[] { 15f / 11f, 16f / 9f, 4f / 3f, 1f })
            {
                var pose = Hd2dCamera.ForTile(100, 100, origin, aspect);
                bool inside = true;
                foreach (var (dx, dz) in new[] { (-7.5f, -5.5f), (7.5f, -5.5f), (7.5f, 5.5f), (-7.5f, 5.5f), (0f, 0f) })
                {
                    bool ok = pose.Project(pose.Target + new Vec3(dx, 0, dz), out float nx, out float ny);
                    inside &= ok && Math.Abs(nx) <= 1.0005f && Math.Abs(ny) <= 1.0005f;
                }
                check(inside, "hd2d: the 15 x 11 rectangle is in view at aspect " + aspect.ToString("0.00"));
                var tighter = Hd2dCamera.ForTile(100, 100, origin, aspect);
                tighter.Position = pose.Target - pose.Forward * (pose.Distance * 0.97f);
                bool someOut = false;
                foreach (var (dx, dz) in new[] { (-7.5f, -5.5f), (7.5f, -5.5f), (7.5f, 5.5f), (-7.5f, 5.5f) })
                {
                    tighter.Project(tighter.Target + new Vec3(dx, 0, dz), out float nx, out float ny);
                    someOut |= Math.Abs(nx) > 1f || Math.Abs(ny) > 1f;
                }
                check(someOut, "hd2d: the camera is as close as it can be at aspect " + aspect.ToString("0.00"));
            }
            var cam = Hd2dCamera.ForTile(100.5f, 97, origin, 15f / 11f, 40f, 25f);
            check(Near(cam.Target.X, 1f) && Near(cam.Target.Z, 2.5f), "hd2d: the camera looks at the middle of the player's tile, also while walking");
            check(cam.Position.Z < cam.Target.Z && cam.Position.Y > 0, "hd2d: the camera is south of the target and above it");
            float pitch = (float)(Math.Atan2(cam.Position.Y, cam.Target.Z - cam.Position.Z) * 180 / Math.PI);
            check(Near(pitch, 40f, 0.01f), "hd2d: the camera pitch is the asked 40 degrees: " + pitch);
            var steep = Hd2dCamera.ForTile(100, 100, origin, 15f / 11f, 45f, 20f);
            var flat = Hd2dCamera.ForTile(100, 100, origin, 15f / 11f, 35f, 20f);
            check(steep.Distance > 0 && flat.Distance > 0 && Near(steep.Distance, flat.Distance, steep.Distance * 0.05f), "hd2d: pitch 35 to 45 needs about the same distance (width bound)");
            var wide = Hd2dCamera.ForTile(100, 100, origin, 15f / 11f, 40f, 25f, margin: 1f);
            check(wide.Distance > cam.Distance, "hd2d: a margin backs the camera off");

            // ---- the synthetic demo room: real dat and spr bytes
            var demo = Hd2dDemo.Synthetic();
            check(demo.Dat.Item(105).LightLevel == 6 && demo.Dat.Item(105).LightColor == 206 && demo.Dat.Item(103).Idle.Width == 2, "hd2d demo: dat holds the torch light and 2 x 2 walls");
            check(Hd2d.Classify(demo.Dat.Item(100)) == Hd2dKind.Floor && Hd2d.Classify(demo.Dat.Item(102)) == Hd2dKind.Border &&
                  Hd2d.Classify(demo.Dat.Item(103)) == Hd2dKind.Billboard && Hd2d.Classify(demo.Dat.Item(104)) == Hd2dKind.Billboard &&
                  Hd2d.Classify(demo.Dat.Item(105)) == Hd2dKind.Billboard && Hd2d.Classify(demo.Dat.Item(106)) == Hd2dKind.Decal, "hd2d demo: floor, border, wall, pillar, torch, carpet classify as built");
            using (var spr = new SprFile(new MemoryStream(demo.SprBytes)))
            {
                var fl = demo.Dat.Item(100).Idle.Sprites[0];
                var px = spr.Rgba(fl);
                check(px != null && px[3] == 255, "hd2d demo: the floor sprite decodes opaque");
                uint torchTop = demo.Dat.Item(105).Idle.Sprite(0, 1, 0, 0, 0, 0, 0);
                check(spr.Rgba(torchTop) != null, "hd2d demo: the torch flame cell is drawn");
                var hero = demo.Dat.Outfit(1);
                check(hero.Idle.PatternX == 4 && spr.Rgba(hero.Idle.Sprite(0, 0, 0, 2, 0, 0, 0)) != null, "hd2d demo: the outfit has 4 facings");
            }
            var dl = Hd2d.Layout(demo.World, demo.Center, 40f, null, false);   // the synthetic art stands straight
            check(dl.All(p => p.Shear == 0f) && Hd2d.Layout(demo.World, demo.Center, 40f).Any(p => p.Shear == 1f), "hd2d demo: straight art is not sheared, the same room as game art is");
            int ground = dl.Count(p => p.Kind == Hd2dKind.Floor), walls = dl.Count(p => p.Kind == Hd2dKind.Billboard), mobs = dl.Count(p => p.Kind == Hd2dKind.Creature);
            check(ground == 18 * 14 && mobs == 2 && walls >= 12 && dl.Any(p => p.Kind == Hd2dKind.Decal && p.Width == 2 && p.Height == 3), "hd2d demo: floor, walls, creatures and the carpet decal are laid out");
            var dlights = Hd2d.Lights(dl, new Vec3(0.5f, 0f, -0.5f), 8);
            check(dlights.Count == 4 && dlights[0].Range == 3f, "hd2d demo: two wall torches, a standing torch and the hero's lantern light the room: " + dlights.Count);
            var real = Hd2dDemo.FromPair(dat);
            check(real == null, "hd2d demo: a dat without the temple tileset gives no temple room");
        }
    }
}
