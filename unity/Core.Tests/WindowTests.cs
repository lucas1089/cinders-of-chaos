// Checks for the attack packets and the remembered minimap (battle list and minimap windows).
using System;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class WindowTests
    {
        static Thing ItemThing(int color, bool ground = false) =>
            new Thing { Item = new Item { Id = 1, Type = new ThingType { MinimapColor = color, Ground = ground } } };

        public static void Run(Action<bool, string> check)
        {
            // attack, follow, cancel
            check(Protocol.AttackPacket(0xA1, 0x40000002, 5).SequenceEqual(new byte[] { 0xA1, 2, 0, 0, 0x40, 5, 0, 0, 0 }), "attack packet bytes");
            check(Protocol.AttackPacket(0xA2, 0x10000001, 6).SequenceEqual(new byte[] { 0xA2, 1, 0, 0, 0x10, 6, 0, 0, 0 }), "follow packet bytes");
            check(Protocol.AttackPacket(0xA1, 0, 7).SequenceEqual(new byte[] { 0xA1, 0, 0, 0, 0, 7, 0, 0, 0 }), "cancel packet bytes");

            // the server's 0xA3 clears the target
            var dat = DatFile.Parse(Program.SyntheticDat());
            var world = new World(dat);
            var parser = new GameParser(world);
            parser.AttackTarget = 0x40000002;
            parser.Parse(new ByteWriter().U8(0xA3).U32(9).ToArray());
            check(parser.AttackTarget == 0, "0xA3 clears the attack target");

            // minimap colours: 6x6x6 cube
            MinimapMemory.Rgb(0, out var r, out var g, out var b);
            check(r == 0 && g == 0 && b == 0, "minimap colour 0");
            MinimapMemory.Rgb(215, out r, out g, out b);
            check(r == 255 && g == 255 && b == 255, "minimap colour 215 is white");
            MinimapMemory.Rgb((byte)(1 * 36 + 2 * 6 + 3), out r, out g, out b);
            check(r == 51 && g == 102 && b == 153, "minimap colour cube decode");

            // top-most thing with a colour; creatures and colourless items are skipped
            var tile = new Tile(new Pos(10, 20, 7));
            tile.Things.Add(ItemThing(30, true));
            tile.Things.Add(ItemThing(0));
            tile.Things.Add(new Thing { Creature = new Creature { Id = 1 } });
            check(MinimapMemory.Pick(tile) == 30, "minimap pick: the ground when nothing above has a colour");
            tile.Things.Insert(1, ItemThing(100));
            check(MinimapMemory.Pick(tile) == 100, "minimap pick: top-most coloured item");
            check(MinimapMemory.Pick(null) == 0, "minimap pick: no tile");

            // memory: kept after the tile leaves the world, per floor
            var mem = new MinimapMemory();
            var p = new Pos(10, 20, 7);
            world.GetOrMake(p).Things.AddRange(tile.Things);
            mem.Update(world);
            int v = mem.Version;
            check(mem.Get(10, 20, 7) == 100 && mem.Get(10, 20, 6) == 0 && mem.Count(7) == 1, "minimap memory: colour stored on its floor");
            mem.Update(world);
            check(mem.Version == v, "minimap memory: no change, same version");
            world.Clean(p);
            mem.Update(world);
            check(mem.Get(10, 20, 7) == 100, "minimap memory: explored area stays");
            world.GetOrMake(p).Things.Add(ItemThing(42, true));
            mem.Update(world);
            check(mem.Get(10, 20, 7) == 42 && mem.Version > v, "minimap memory: a new colour replaces the old");
            mem.Clear();
            check(mem.Get(10, 20, 7) == 0, "minimap memory: clear");
        }
    }
}
