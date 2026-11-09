// Wire audit (phase 6, track T): byte vectors written by hand from what the patches write, not from what the parser reads.
//   server/src-patches: 0003 (markers, item attributes, features), 0013 (size caps), 0037 and 0052 (display scale, stats), 0051 (typed numbers),
//   0069 and 0073 (packet compression), 0072 (map description), 0077 (facing), 0079 (wide spell ids), 0081 (container pages), 0083 (creature refresh);
//   client/base-patches: 0012 (crafting skills), 0016 (class byte), 0028 (UTF-8 text), 0100 (typed numbers), 0131 and 0135 (inflate).
// The map is read with the negotiated aware range (0x42): the default 17 x 13 and the largest the main client asks for, 29 x 21.
using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;

namespace Chaos.Core.Tests
{
    static class WireAuditTests
    {
        static bool Throws<T>(Action a) where T : Exception
        {
            try { a(); } catch (T) { return true; }
            return false;
        }

        static string Hex(byte[] b) => string.Concat(b.Select(x => x.ToString("x2")));
        static byte[] FromHex(string h) { var b = new byte[h.Length / 2]; for (int i = 0; i < b.Length; i++) b[i] = Convert.ToByte(h.Substring(2 * i, 2), 16); return b; }
        static ByteWriter U64(ByteWriter w, ulong v) => w.U32((uint)v).U32((uint)(v >> 32));

        static DatFile Dat() => DatFile.Parse(Program.SyntheticDat());

        static GameParser Parser(bool chaos, out World world, params ushort[] features)
        {
            world = new World(Dat());
            var p = new GameParser(world) { Identity = chaos ? ClientIdentity.Chaos(30) : ClientIdentity.Extended };
            if (features.Length > 0)
            {
                var f = new ByteWriter().U8(0x43).U16((ushort)features.Length);
                foreach (ushort n in features) f.U8((byte)n).U8(1);
                p.Parse(f.ToArray());
            }
            return p;
        }

        public static void Run(Action<bool, string> check)
        {
            Markers(check);
            Features(check);
            Items(check);
            Creatures(check);
            Numbers(check);
            Stats(check);
            BasicData(check);
            TextChecks(check);
            AwareChecks(check);
            CompressionChecks(check);
        }

        // ------------------------------------------------------------------------------------------------ login markers (0003, 0051, 0079)
        /// <summary>What ProtocolGame::onRecvFirstMessage reads after the random byte, written out as the patches have it.</summary>
        static bool ServerReadsMarkers(byte[] b, out ushort v8, out bool chaosClient, out byte caps)
        {
            var r = new ByteReader(b);
            v8 = 0; chaosClient = false; caps = 0;
            int len = r.U16();
            if (len != 5 || Encoding.ASCII.GetString(r.Bytes(5)) != "OTCv8") return len == 0 && r.AtEnd;
            v8 = r.U16();
            string tier = r.Str();
            chaosClient = tier == "OTCv8TierByte" && r.Str() == "A";
            if (chaosClient)
            {
                r.U32();
                if (r.Str() == "C") caps = r.U8();
            }
            return r.AtEnd;
        }

        static void Markers(Action<bool, string> check)
        {
            var w = new ByteWriter();
            ClientIdentity.Chaos(30).WriteMarkers(w);
            string expect = "0500" + "4f544376" + "38" + "0501" + "0d00" + "4f54437638546965724279746" + "5" + "0100" + "41" + "1e000000" + "0100" + "43" + "c0";
            check(Hex(w.ToArray()) == expect, "markers: u16 5 OTCv8, u16 261, OTCv8TierByte, A, u32 build, C, capability byte 0xC0: " + Hex(w.ToArray()));
            check(ServerReadsMarkers(w.ToArray(), out ushort v8, out bool chaos, out byte caps) && v8 == 261 && chaos && (caps & 0x80) != 0 && (caps & 0x40) != 0,
                  "markers: the server's reads of 0003, 0051 and 0079 take them: version, chaosClient, bits 7 and 6");
            var plain = new ByteWriter();
            ClientIdentity.Extended.WriteMarkers(plain);
            check(Hex(plain.ToArray()) == "0000" && ServerReadsMarkers(plain.ToArray(), out _, out bool c2, out _) && !c2, "markers: Identity.Extended is u16 0, no chaosClient");
            // bit 6 asks for 16-bit spell ids, bit 7 for typed impact numbers; the other bits of the main client (store, marks) are not claimed
            check(ClientIdentity.CapWideSpellIds == 0x40 && ClientIdentity.CapImpactText == 0x80 && ClientIdentity.Chaos(1).Capabilities == 0xC0,
                  "markers: capabilities are bits 6 and 7 only (0079, 0051)");
        }

        // ------------------------------------------------------------------------------------------------ 0x43 feature list
        static void Features(Action<bool, string> check)
        {
            // sendFeatures: 0x43, u16 count, then u8 feature and u8 enabled each (feature 126 item attributes 0003, 152 wide spell ids 0079, 155 typed numbers 0051)
            // 0xF5, the engine's sendItems at login (the live server sends it, the fake server did not): u16 count, then u16 id, u8 0, u16 1 each
            var inv = Parser(false, out _);
            inv.Parse(FromHex("f5" + "0200" + "010000" + "0100" + "0b0000" + "0100" + "1d"));
            check(inv.Seen.ContainsKey(0xF5) && inv.Seen.ContainsKey(0x1D), "wire: 0xF5 inventory id list is read whole, the next message follows");

            var p = Parser(true, out _);
            p.Parse(FromHex("43" + "0500" + "7e01" + "9801" + "9b01" + "0600" + "6f00"));
            check(p.Features.Announced && p.Features.Has(126) && p.Features.Has(152) && p.Features.Has(155) && !p.Features.Has(6) && !p.Features.Has(111),
                  "0x43: the Chaos features 126, 152 and 155 on, a feature sent as 0 off");
            check(ClientFeatures.ItemCustomAttributes == 126 && ClientFeatures.ExtendedSpellIds == 152 && ClientFeatures.ImpactText == 155, "0x43: the feature numbers are those of const.h");
        }

        // ------------------------------------------------------------------------------------------------ items (0003, 0050, 0081)
        static ByteWriter ItemBytes(ByteWriter w, ushort id, int count, int phase, params (ushort key, ulong value)[] attrs)
        {
            w.U16(id).U8(0xFF);   // GameThingMarks byte
            if (id == 101) w.U8((byte)count);   // stackable: the count byte
            if (id == 101) w.U8((byte)phase);   // two phases: the phase byte (0 automatic)
            w.U16((ushort)attrs.Length);
            foreach (var a in attrs) { w.U16(a.key); U64(w, a.value); }
            return w;
        }

        static void Items(Action<bool, string> check)
        {
            var p = Parser(true, out var world, 126);
            // 0x78 inventory slot: slot, item, then u16 count and u16 key + u64 value per attribute (item lock key 3 carries 2 for a bound item, 0050)
            p.Parse(ItemBytes(new ByteWriter().U8(0x78).U8(4), 101, 7, 0, (1, 3), (3, 2), (6, 77)).ToArray());
            var it = p.Inventory[4];
            check(it != null && it.Id == 101 && it.Count == 7 && it.Attr(1) == 3 && it.Attr(3) == 2 && it.Attr(6) == 77 && it.Attrs.Count == 3,
                  "0x78: item with count, phase and three attributes (key 3 keeps its value 2)");
            p.Parse(ItemBytes(new ByteWriter().U8(0x78).U8(5), 100, 0, 0).ToArray());
            check(p.Inventory[5] != null && p.Inventory[5].Id == 100 && p.Inventory[5].Attrs == null, "0x78: a plain item has an attribute count of 0 and no dictionary");

            // 0x6E, a paged container (0081): capacity byte 250 for a 500 slot bag, has parent 0, unlocked 1, pages 1, size 500, first index 250
            var open = new ByteWriter().U8(0x6E).U8(3);
            ItemBytes(open, 100, 0, 0).Str("Loot Bag").U8(250).U8(0).U8(1).U8(1).U16(500).U16(250).U8(2);
            ItemBytes(open, 101, 3, 0, (4, 1)); ItemBytes(open, 100, 0, 0, (2, 40));
            p.Parse(open.ToArray());
            var bag = p.Containers.ContainsKey(3) ? p.Containers[3] : null;
            check(bag != null && bag.Capacity == 250 && bag.Size == 500 && bag.FirstIndex == 250 && bag.Items.Count == 2 && bag.Name == "Loot Bag" &&
                  bag.Items[0].Attr(4) == 1 && bag.Items[1].Attr(2) == 40, "0x6E: a 500 slot bag is sent in pages of 250 (size 500, first index 250)");
            // 0x70 add (slot u16), 0x71 update, 0x72 remove with the item that slides in from the next page, 0x72 with none (u16 0)
            p.Parse(ItemBytes(new ByteWriter().U8(0x70).U8(3).U16(250), 101, 9, 0, (6, 5)).ToArray());
            check(bag.Items.Count == 3 && bag.Items[0].Count == 9 && bag.Items[0].Attr(6) == 5 && bag.Size == 501, "0x70: an item is added at its slot with its attributes");
            p.Parse(ItemBytes(new ByteWriter().U8(0x71).U8(3).U16(250), 101, 4, 0, (6, 6)).ToArray());
            check(bag.Items[0].Count == 4 && bag.Items[0].Attr(6) == 6, "0x71: an item is replaced at its slot");
            p.Parse(ItemBytes(new ByteWriter().U8(0x72).U8(3).U16(250), 100, 0, 0, (1, 1)).ToArray());
            check(bag.Items.Count == 3 && bag.Items[2].Id == 100 && bag.Items[2].Attr(1) == 1 && bag.Size == 500, "0x72: remove with the next page's item (attributes after it)");
            p.Parse(new ByteWriter().U8(0x72).U8(3).U16(250).U16(0).ToArray());
            check(bag.Items.Count == 2 && bag.Size == 499, "0x72: remove with no item sliding in is u16 0 and no attribute count");
            // the browse-field container's own item is AddItem(id, count): count 0 as an attribute list
            var browse = new ByteWriter().U8(0x6E).U8(4);
            browse.U16(100).U8(0xFF).U16(0).Str("Browse Field").U8(8).U8(0).U8(1).U8(0).U16(0).U16(0).U8(0);
            p.Parse(browse.ToArray());
            check(p.Containers.ContainsKey(4) && p.Containers[4].Name == "Browse Field", "0x6E: browse field (the bag item written with an attribute count of 0)");

            // an item with no attribute feature (an Identity.Extended connection) carries none
            var plain = Parser(false, out _);
            plain.Parse(new ByteWriter().U8(0x78).U8(4).U16(101).U8(0xFF).U8(7).U8(0).ToArray());
            check(plain.Inventory[4] != null && plain.Inventory[4].Count == 7 && plain.Inventory[4].Attrs == null, "0x78: without feature 126 the item ends after its phase byte");
            check(Throws<ProtocolException>(() => p.Parse(new ByteWriter().U8(0x78).U8(4).U16(65000).U8(0xFF).ToArray())), "0x78: an item the dat does not have is refused (wrong pair)");

            // 0x6A add tile item with stack position (GameTileAddThingWithStackpos), after a map is held
            p.Parse(MapPacket(new Pos(100, 100, 7), Default, true, null));
            p.Parse(ItemBytes(new ByteWriter().U8(0x6A).U16(101).U16(100).U8(7).U8(1), 101, 5, 0, (1, 2)).ToArray());
            var t = world.Get(new Pos(101, 100, 7));
            check(t != null && t.Things.Count == 2 && t.Things[1].Item.Count == 5 && t.Things[1].Item.Attr(1) == 2, "0x6A: a thing added with its stack position and attributes");
        }

        // ------------------------------------------------------------------------------------------------ creatures and outfits (0077, 0083, base)
        static ByteWriter OutfitBytes(ByteWriter w, int look, int itemEx, int mount, int wings, int aura, string shader, bool markers)
        {
            w.U16((ushort)look);
            if (look != 0) w.U8(10).U8(20).U8(30).U8(40).U8(3); else w.U16((ushort)itemEx);
            w.U16((ushort)mount);
            if (markers) w.U16((ushort)wings).U16((ushort)aura).Str(shader);
            return w;
        }

        static ByteWriter CreatureBytes(ByteWriter w, bool full, uint remove, uint id, string name, byte dir, bool markers, byte type = 1)
        {
            if (full) w.U16(0x61).U32(remove).U32(id).U8(type).Str(name); else w.U16(0x62).U32(id);
            w.U8(80).U8(dir);
            OutfitBytes(w, 1, 0, 5, 7, 9, "fire", markers);
            w.U8(3).U8(215).U16(110).U8(2).U8(1);   // light, speed, skull, party shield
            if (full) w.U8(4);   // guild emblem, only in the full form
            w.U8(type).U8(0).U8(0xFF).U16(0).U8(1);   // creature type, speech bubble, mark, helpers, unpassable
            return w;
        }

        static void Creatures(Action<bool, string> check)
        {
            var p = Parser(true, out var world, 126);
            p.Parse(MapPacket(new Pos(100, 100, 7), Default, true, null));
            // 0x6A adds a creature at stack position 1: the full form (0x61), outfit with mount, wings, aura and shader (0003 / base), direction byte 5 = south-east (0077)
            p.Parse(CreatureBytes(new ByteWriter().U8(0x6A).U16(103).U16(100).U8(7).U8(1), true, 0, 0x40000010, "Wolf", 5, true).ToArray());
            var c = world.Creatures[0x40000010];
            check(c.Name == "Wolf" && c.Direction == Dir.SouthEast && c.Outfit.LookType == 1 && c.Outfit.Mount == 5 && c.Outfit.Wings == 7 && c.Outfit.Aura == 9 &&
                  c.Outfit.Shader == "fire" && c.Speed == 110 && c.Skull == 2 && c.Shield == 1 && c.Emblem == 4 && c.Type == 1 && c.Position.X == 103 && !c.Walkthrough,
                  "0x61: name, diagonal facing 5, outfit with mount, wings, aura and shader, speed, skull, shield, emblem, type, mark, helpers");
            // the turn packet (0x6B with the position or 0xFFFF + id, then 0x63): the facing 4 .. 7 are the diagonals in the client's order
            foreach (var (dir, want) in new[] { ((byte)4, Dir.NorthEast), ((byte)5, Dir.SouthEast), ((byte)6, Dir.SouthWest), ((byte)7, Dir.NorthWest), ((byte)0, Dir.North) })
            {
                p.Parse(new ByteWriter().U8(0x6B).U16(0xFFFF).U32(0x40000010).U16(0x63).U32(0x40000010).U8(dir).U8(1).ToArray());
                check(c.Direction == want, "0x63: facing byte " + dir + " is " + want);
            }
            check(c.Position.X == 103 && world.Get(new Pos(103, 100, 7)).Things.Any(x => x.Creature == c), "0x63: a turn leaves the creature where it is");
            // the refresh of 0083: 0x6B, 0xFFFF and the id, then the full form with remove = its own id and the new name
            var refresh = CreatureBytes(new ByteWriter().U8(0x6B).U16(0xFFFF).U32(0x40000010), true, 0x40000010, 0x40000010, "Wolf [20]", 2, true);
            p.Parse(refresh.ToArray());
            check(world.Creatures[0x40000010] == c && c.Name == "Wolf [20]" && c.Direction == Dir.South && world.Get(new Pos(103, 100, 7)).Things.Count(x => x.Creature == c) == 1,
                  "0x6B + 0xFFFF + id: the refresh of 0083 keeps the object and the tile, takes the new name");
            // 0x62: a creature the client knows, no name and no emblem
            p.Parse(CreatureBytes(new ByteWriter().U8(0x6A).U16(104).U16(100).U8(7).U8(1), false, 0, 0x40000010, "", 6, true).ToArray());
            check(c.Position.X == 104 && c.Direction == Dir.SouthWest, "0x62: a known creature on a new tile, no name, no emblem");
            // 0x8E: another outfit, with the extended fields; an item-shaped look (look type 0) is u16 item id then the same tail
            p.Parse(OutfitBytes(new ByteWriter().U8(0x8E).U32(0x40000010), 0, 101, 0, 11, 12, "blue", true).ToArray());
            check(c.Outfit.LookType == 0 && c.Outfit.LookTypeEx == 101 && c.Outfit.Wings == 11 && c.Outfit.Aura == 12 && c.Outfit.Shader == "blue", "0x8E: item look, wings, aura, shader");
            // the same creature on an Identity.Extended connection has no wings, aura or shader bytes
            var plain = Parser(false, out var pw);
            plain.Parse(MapPacket(new Pos(100, 100, 7), Default, false, null));
            plain.Parse(CreatureBytes(new ByteWriter().U8(0x6A).U16(103).U16(100).U8(7).U8(1), true, 0, 0x40000011, "Rat", 7, false).ToArray());
            check(pw.Creatures[0x40000011].Outfit.Mount == 5 && pw.Creatures[0x40000011].Outfit.Shader == "" && pw.Creatures[0x40000011].Direction == Dir.NorthWest, "0x61: plain wire, no extended outfit fields");
            // 0x93: the creature square of the 10.98 server is the id, a 1 and the colour
            world.Fx.Enabled = true;
            p.Parse(new ByteWriter().U8(0x93).U32(0x40000010).U8(1).U8(215).ToArray());
            check(world.Fx.TryDequeue(out var ev) && ev.Kind == FxKind.Square && ev.Creature == 0x40000010 && ev.Color == 215, "0x93: the creature square is read (id, 1, colour)");
            // the outfit window (0xC8): the current look carries the same extended fields, then the lists
            var win = OutfitBytes(new ByteWriter().U8(0xC8), 1, 0, 0, 7, 9, "fire", true);
            win.U8(1).U16(1).Str("Citizen").U8(3).U8(1).U16(5).Str("Wolf");
            win.U8(1).U16(7).Str("Wings").U8(1).U16(9).Str("Aura").U8(2).U8(19).Str("Fire").U8(20).Str("Ice");
            p.Parse(win.ToArray());
            var ow = p.Outfits;
            check(ow.Open && ow.Outfits.Count == 1 && ow.Outfits[0].Addons == 3 && ow.Mounts.Count == 1 && ow.Wings[0].Id == 7 && ow.Auras[0].Name == "Aura" && ow.Shaders.Count == 2 && ow.Shaders[1].Id == 20,
                  "0xC8: lists with u16 wing and aura ids and one-byte shader ids");
            var wideShader = OutfitBytes(new ByteWriter().U8(0xC8), 1, 0, 0, 0, 0, "", true);
            wideShader.U8(0).U8(0).U8(0).U8(0).U8(1).U16(19).Str("Fire");
            p.Parse(wideShader.ToArray());
            check(ow.Shaders.Count == 1 && ow.Shaders[0].Id == 19 && ow.Shaders[0].Name == "Fire", "0xC8: a shader list with u16 ids is read too (the width is the base server's, not in this repo)");
        }

        // ------------------------------------------------------------------------------------------------ numbers and spells (0051, 0037, 0052, 0079)
        static ByteWriter PutPos(ByteWriter w, int x, int y, int z) => w.U16((ushort)x).U16((ushort)y).U8((byte)z);

        static void Numbers(Action<bool, string> check)
        {
            // 0xB4: kind, position, value + colour (twice for damage 23, 24, 27), then u16 percent, u8 type, u32 creature id, then the text
            var typed = Parser(true, out var world, 126, 155);
            world.Fx.Enabled = true;
            foreach (int kind in new[] { 23, 24, 25, 26, 27, 28, 29 })
            {
                bool two = kind == 23 || kind == 24 || kind == 27;
                var m = PutPos(new ByteWriter().U8(0xB4).U8((byte)kind), 100, 100, 7).U32(1234).U8(180);
                if (two) m.U32(77).U8(30);
                m.U16(250).U8((byte)(kind - 22)).U32(0x40000010).Str("text " + kind);
                typed.Parse(m.ToArray());
                bool got = world.Fx.TryDequeue(out var e);
                check(got && e.Typed && e.Id == kind && e.Value == 1234 && e.Color == 180 && (!two || e.Value2 == 77 && e.Color2 == 30) && e.Percent == 250 && e.Impact == kind - 22 &&
                      e.Creature == 0x40000010 && e.Text == "text " + kind, "0xB4 typed: mode " + kind + " reads value, colour, percent, type, creature, text");
            }
            // mana drain and gain (types 3 and 4): the same layout (0052 only keeps their numbers out of the display scale)
            // without feature 155 the old layout: no extra fields
            var old = Parser(true, out var w2, 126);
            w2.Fx.Enabled = true;
            old.Parse(PutPos(new ByteWriter().U8(0xB4).U8(25), 100, 100, 7).U32(9).U8(180).Str("heal").ToArray());
            check(w2.Fx.TryDequeue(out var oe) && !oe.Typed && oe.Value == 9 && oe.Text == "heal", "0xB4: without feature 155 a heal is position, value, colour, text");
            // a plain status message (kind 20 and under 23): just the text
            var chat = new System.Collections.Generic.List<string>();
            typed.Chat = (who, text, type) => chat.Add(text);
            typed.Parse(new ByteWriter().U8(0xB4).U8(19).Str("You see a rat.").ToArray());
            check(chat.Count == 1 && chat[0] == "You see a rat.", "0xB4: a status text has no position and no numbers");
            // 0xA4: u8 spell id on a plain wire, u16 with feature 152 (0079), then u32 ms; 0xA5 group: u8 and u32
            int id = 0; uint ms = 0;
            var plain = Parser(true, out _, 126);
            plain.SpellCooldown = (i, m) => { id = i; ms = m; };
            plain.Parse(FromHex("a4" + "2a" + "e8030000"));
            check(id == 42 && ms == 1000, "0xA4: one byte spell id without feature 152");
            var wide = Parser(true, out _, 126, 152);
            wide.SpellCooldown = (i, m) => { id = i; ms = m; };
            wide.Parse(FromHex("a4" + "0201" + "e8030000"));
            check(id == 258 && ms == 1000, "0xA4: u16 spell id 258 with feature 152, spell ids above 255 are possible");
            int group = 0;
            wide.GroupCooldown = (g, m) => { group = g; ms = m; };
            wide.Parse(FromHex("a5" + "03" + "d0070000"));
            check(group == 3 && ms == 2000, "0xA5: group id stays one byte (0079 did not widen it)");
        }

        // ------------------------------------------------------------------------------------------------ stats (0037, 0052, 0012)
        static void Stats(Action<bool, string> check)
        {
            // 0xA0 as ProtocolGame::AddPlayerStats writes it: health, max health (display scale, u32), capacity, total capacity, u64 experience, level, percent,
            // 5 u16 (base rate, voucher, low level bonus, boost, stamina multiplier), mana and max mana (u32, not scaled), magic level x3, soul, stamina, speed,
            // regeneration, offline training, boost time, store flag
            var p = Parser(true, out _, 126);
            var s = new ByteWriter().U8(0xA0).U32(2000000000).U32(2100000000).U32(65000).U32(100000);
            U64(s, 5000000000UL).U16(512).U8(37).U16(100).U16(0).U16(0).U16(0).U16(100).U32(900000).U32(1000000).U8(120).U8(110).U8(55).U8(100).U16(2520).U16(310).U16(0).U16(1).U16(0).U8(0);
            // 0xA1: seven skills (u16 level, u16 base, u8 percent), seven crafting skills after fishing (base patch 0012), six special skills (u16, u16 each)
            var k = new ByteWriter().U8(0xA1);
            for (int i = 0; i < 14; i++) k.U16((ushort)(10 + i)).U16((ushort)(20 + i)).U8((byte)(30 + i));
            for (int i = 0; i < 6; i++) k.U16(5).U16(0);
            var m = new ByteWriter().Raw(s.ToArray()).Raw(k.ToArray()).U8(0x82).U8(77).U8(215);
            p.Parse(m.ToArray());
            check(p.Health == 2000000000 && p.MaxHealth == 2100000000 && p.FreeCap == 65000 && p.TotalCap == 100000 && p.Experience == 5000000000UL && p.Level == 512 && p.LevelPercent == 37 &&
                  p.Mana == 900000 && p.MaxMana == 1000000 && p.MagicLevel == 120 && p.BaseMagicLevel == 110 && p.MagicPercent == 55 && p.Soul == 100 && p.Stamina == 2520 && p.Speed == 310,
                  "0xA0: every field, with the 10 byte bonus block and the 7 byte tail skipped");
            check(p.Skills[6].Level == 16 && p.Skills[6].Base == 26 && p.Skills[6].Percent == 36 && p.CraftSkills[0].Level == 17 && p.CraftSkills[6].Percent == 43,
                  "0xA1: seven skills, then the seven crafting skills, then 24 bytes of special skills");
            // the display scale (0037) clamps to the u32 range: a value above 2^31 must not turn negative (the engine keeps health as a double)
            var big = new ByteWriter().U8(0xA0).U32(4000000000).U32(4294967295);
            var rest = s.ToArray().Skip(9).ToArray();
            p.Parse(big.Raw(rest).ToArray());
            check(p.Health > 0 && p.Health < p.MaxHealth && p.MaxHealth > 2000000000 && p.Mana == 900000, "0xA0: a scaled health above 2^31 is clamped to the int range, not negative");
        }

        // ------------------------------------------------------------------------------------------------ basic data (base patch 0016, ascension.lua)
        static void BasicData(Action<bool, string> check)
        {
            // ascension.lua sendBasicData: 0x9F, premium byte, u32 0, class byte, u16 0xFF, the 255 spell ids as bytes
            var p = Parser(true, out var world);
            world.PlayerVocation = 0;
            var m = new ByteWriter().U8(0x9F).U8(1).U32(0).U8(13).U16(0xFF);
            for (int i = 0; i < 255; i++) m.U8((byte)i);
            m.U8(0x82).U8(66).U8(215);
            p.Parse(m.ToArray());
            check(p.ClassByte == 13 && p.VocationId == 5 && world.PlayerVocation == 5 && world.WorldLight == 66, "0x9F: class byte 13 (the first ascended mystic) is vocation 5; the spell list is skipped");
            // the table of base patch 0016: tier = byte / 10, slot = byte % 10
            int[][] want =
            {
                new[] { 0, 4, 3, 1, 1, 1, 11, 20, 17, 23 },
                new[] { 0, 8, 7, 5, 10, 10, 12, 21, 18, 24 },
                new[] { 0, 14, 15, 10, 10, 10, 13, 22, 19, 25 },
            };
            bool all = true;
            for (int b = 0; b < 30; b++) all &= ChaosVocation.FromWire(b) == want[b / 10][b % 10];
            check(all && ChaosVocation.FromWire(31) == 31, "0x9F: the class byte table of 30 entries (3 tiers of 10), a byte past it stays as it is");
            p.Parse(new ByteWriter().U8(0x9F).U8(0).U32(0).U8(1).U16(0).ToArray());
            check(world.PlayerVocation == 4, "0x9F: again after an ascension, the vocation follows (a class byte 1 is vocation 4)");
        }

        // ------------------------------------------------------------------------------------------------ text (base patch 0028)
        static void TextChecks(Action<bool, string> check)
        {
            string R(params byte[] b) => new ByteReader(new ByteWriter().U16((ushort)b.Length).Raw(b).ToArray()).Str();
            check(R(0x41, 0xC3, 0xA7, 0xC3, 0xA3, 0x6F) == "Ação", "text: UTF-8 'ação' is read as UTF-8 (a script saved as UTF-8)");
            check(R(0x41, 0xE7, 0xE3, 0x6F) == "Ação", "text: Latin-1 'ação' stays Latin-1");
            check(R(0xC3, 0x28) == "Ã(", "text: an invalid UTF-8 sequence is Latin-1");
            check(R(0xC0, 0xAF) == "À¯", "text: an overlong sequence is Latin-1");
            check(R(0xED, 0xA0, 0x80) == "í \u0080", "text: a surrogate is Latin-1");
            check(R(0xEF, 0xBB, 0xBF, 0x68, 0x69) == "hi", "text: a byte order mark is dropped");
            check(R(0xE2, 0x82, 0xAC) == "€", "text: a character outside cp1252's Latin-1 half is kept as the character");
            var raw = new ByteReader(new ByteWriter().U16(2).U8(0xC3).U8(0xA7).ToArray());
            check(raw.StrRaw() == "Ã§", "text: StrRaw keeps one char per byte (extended opcodes decode their own UTF-8)");
            // an extended opcode keeps going through ExtOpcodes.FromWire: the UTF-8 of the JSON is still there as bytes
            string got = null;
            var p = Parser(true, out _);
            p.ExtendedOpcode = (op, s) => got = ExtOpcodes.FromWire(s);
            p.Parse(new ByteWriter().U8(0x32).U8(9).U16(4).U8(0x7B).U8(0xC3).U8(0xA7).U8(0x7D).ToArray());
            check(got == "{ç}", "text: the extended opcode string is decoded once, not twice");
            // a server text in the chat comes out as UTF-8 text
            var chat = new System.Collections.Generic.List<string>();
            p.Chat = (who, text, type) => chat.Add(text);
            p.Parse(new ByteWriter().U8(0xB4).U8(19).U16(5).U8(0x41).U8(0xC3).U8(0xA7).U8(0xC3).U8(0xA3).ToArray());
            check(chat.Count == 1 && chat[0] == "Açã", "text: a 0xB4 status line with UTF-8 bytes reads as text");
        }

        // ------------------------------------------------------------------------------------------------ aware range (0x42, 0x33), map reads
        static readonly AwareRange Default = AwareRange.Default;

        static Action<ByteWriter> Ground(Pos p, bool attrs, Func<Pos, bool> has)
        {
            if (!has(p)) return null;
            return w => { w.U16(100).U8(0xFF); if (attrs) w.U16(0); };
        }

        /// <summary>GetFloorDescription of the server with the skip chain it keeps across floors.</summary>
        static int FloorBytes(ByteWriter w, int x, int y, int z, int width, int height, int offset, int skip, Func<Pos, Action<ByteWriter>> tile)
        {
            for (int nx = 0; nx < width; nx++)
                for (int ny = 0; ny < height; ny++)
                {
                    var write = tile(new Pos(x + nx + offset, y + ny + offset, z));
                    if (write != null)
                    {
                        if (skip >= 0) w.U8((byte)skip).U8(0xFF);
                        skip = 0;
                        w.U16(0);
                        write(w);
                    }
                    else if (skip == 0xFE) { w.U8(0xFF).U8(0xFF); skip = -1; }
                    else skip++;
                }
            return skip;
        }

        static void Tail(ByteWriter w, int skip) { if (skip >= 0) w.U8((byte)skip).U8(0xFF); }

        /// <summary>GetMapDescription: the floors of z in the server's order, one skip chain, the tail.</summary>
        static void MapBytes(ByteWriter w, int x, int y, int z, int width, int height, Func<Pos, Action<ByteWriter>> tile)
        {
            int start = z > 7 ? z - 2 : 7, end = z > 7 ? Math.Min(z + 2, 15) : 0, step = z > 7 ? 1 : -1;
            int skip = -1;
            for (int nz = start; nz != end + step; nz += step) skip = FloorBytes(w, x, y, nz, width, height, z - nz, skip, tile);
            Tail(w, skip);
        }

        static Func<Pos, Action<ByteWriter>> Floor7(bool attrs) => p => Ground(p, attrs, q => q.Z == 7);

        /// <summary>0x64 and a map around `at` with ground on floor 7 (or on the floors `has` says).</summary>
        static byte[] MapPacket(Pos at, AwareRange r, bool attrs, Func<Pos, bool> has)
        {
            var w = new ByteWriter().U8(0x64).U16((ushort)at.X).U16((ushort)at.Y).U8((byte)at.Z);
            Func<Pos, Action<ByteWriter>> tile = has == null ? Floor7(attrs) : (Func<Pos, Action<ByteWriter>>)(p => Ground(p, attrs, has));
            MapBytes(w, at.X - r.Left, at.Y - r.Top, at.Z, r.Horizontal, r.Vertical, tile);
            return w.ToArray();
        }

        static int OnFloor(World w, int z) => w.Tiles.Keys.Count(p => p.Z == z);

        static void AwareChecks(Action<bool, string> check)
        {
            // the numbers of the engine's AwareRange: 17 x 13 is left 8, right 9, top 6, bottom 7, 18 x 14 tiles; 29 x 21 is 14, 15, 10, 11, 30 x 22
            var d = AwareRange.Default; var big = new AwareRange(29, 21);
            check(d.Left == 8 && d.Right == 9 && d.Top == 6 && d.Bottom == 7 && d.Horizontal == 18 && d.Vertical == 14 &&
                  d.Left == World.RangeLeft && d.Right == World.RangeRight && d.Top == World.RangeTop && d.Bottom == World.RangeBottom, "range: 17 x 13 is the 18 x 14 view of the constants");
            check(big.Left == 14 && big.Right == 15 && big.Top == 10 && big.Bottom == 11 && big.Horizontal == 30 && big.Vertical == 22, "range: 29 x 21 is 30 x 22 tiles from (x - 14, y - 10)");
            check(AwareRange.Valid(29, 21) && !AwareRange.Valid(18, 13) && !AwareRange.Valid(17, 0) && AwareRange.Clamp(40, 40).ToString() == "29x21" &&
                  AwareRange.Clamp(10, 4).ToString() == "9x3" && AwareRange.TryParse("29 x 21", out var tp) && tp.ToString() == "29x21" && !AwareRange.TryParse("big", out _),
                  "range: odd sizes only, a request is clamped to 3 .. 29 x 21 and made odd");
            check(Hex(WirePackets.ChangeAwareRange(29, 21)) == "331d15", "0x33: the request is opcode, u8 width, u8 height");

            // default range: a full map, then the same bytes as before
            var p = Parser(true, out var world);
            p.Parse(MapPacket(new Pos(100, 100, 7), d, false, null));
            check(OnFloor(world, 7) == 18 * 14 && world.Center == new Pos(100, 100, 7), "0x64: the default range reads 18 x 14 tiles");

            // a larger range: 0x42 first, then the map of 30 x 22 tiles
            var chaos = Parser(true, out var bw);
            AwareRange changed = default;
            chaos.AwareChanged = r => changed = r;
            chaos.Parse(new byte[] { 0x42, 29, 21 });
            check(chaos.AwareW == 29 && chaos.AwareH == 21 && bw.Range.Horizontal == 30 && changed.Width == 29, "0x42: 29 x 21 is taken and announced");
            chaos.Parse(MapPacket(new Pos(100, 100, 7), big, false, null).Concat(new byte[] { 0x82, 55, 215 }).ToArray());
            check(OnFloor(bw, 7) == 30 * 22 && bw.WorldLight == 55 && bw.Tiles.ContainsKey(new Pos(86, 90, 7)) && bw.Tiles.ContainsKey(new Pos(115, 111, 7)) && !bw.Tiles.ContainsKey(new Pos(116, 100, 7)),
                  "0x64: the full map of 29 x 21 is read to its last byte (x 86 .. 115, y 90 .. 111)");
            // steps: east reads the column at x + right, south the row at y + bottom, north the row at y - top, west the column at x - left
            var col = new ByteWriter().U8(0x66); MapBytes(col, 101 + 15, 100 - 10, 7, 1, 22, Floor7(false)); col.U8(0x82).U8(56).U8(215);
            chaos.Parse(col.ToArray());
            check(bw.Center == new Pos(101, 100, 7) && bw.Tiles.ContainsKey(new Pos(116, 100, 7)) && bw.Tiles.ContainsKey(new Pos(116, 111, 7)) && bw.WorldLight == 56, "0x66: east reads one column of 22 tiles at x + 15");
            var row = new ByteWriter().U8(0x67); MapBytes(row, 101 - 14, 101 + 11, 7, 30, 1, Floor7(false)); row.U8(0x82).U8(57).U8(215);
            chaos.Parse(row.ToArray());
            check(bw.Center == new Pos(101, 101, 7) && bw.Tiles.ContainsKey(new Pos(87, 112, 7)) && bw.WorldLight == 57, "0x67: south reads one row of 30 tiles at y + 11");
            var north = new ByteWriter().U8(0x65); MapBytes(north, 101 - 14, 100 - 10, 7, 30, 1, Floor7(false)); north.U8(0x82).U8(58).U8(215);
            chaos.Parse(north.ToArray());
            check(bw.Center == new Pos(101, 100, 7) && bw.Tiles.ContainsKey(new Pos(87, 90, 7)) && bw.WorldLight == 58, "0x65: north reads one row of 30 tiles at y - 10");
            var west = new ByteWriter().U8(0x68); MapBytes(west, 100 - 14, 100 - 10, 7, 1, 22, Floor7(false)); west.U8(0x82).U8(59).U8(215);
            chaos.Parse(west.ToArray());
            check(bw.Center == new Pos(100, 100, 7) && bw.Tiles.ContainsKey(new Pos(86, 95, 7)) && bw.WorldLight == 59, "0x68: west reads one column of 22 tiles at x - 14");
            // going back to the default range drops the tiles outside it
            chaos.Parse(new byte[] { 0x42, 17, 13 });
            check(bw.Range.Horizontal == 18 && bw.Tiles.Keys.All(t => t.X >= 100 - 9 && t.X <= 100 + 10 && t.Y >= 100 - 7 && t.Y <= 100 + 8), "0x42: back to 17 x 13 forgets the tiles outside the smaller window");
            check(Throws<ProtocolException>(() => chaos.Parse(new byte[] { 0x42, 18, 13 })) && bw.Range.Width == 17, "0x42: an even size is refused and the range stays");

            // 0x4B (the main client's floors of a change of level, before 0xBE and 0xBF): the floor message uses the range too
            foreach (var r in new[] { d, big })
            {
                var up = Parser(true, out var uw);
                up.Parse(new byte[] { 0x42, (byte)r.Width, (byte)r.Height });
                up.Parse(MapPacket(new Pos(100, 100, 8), r, false, q => q.Z == 8));
                var floors = new ByteWriter();
                for (int i = 5; i >= 0; i--)
                {
                    floors.U8(0x4B).U16(100).U16(100).U8(8).U8((byte)i);
                    int fl = i;
                    Tail(floors, FloorBytes(floors, 100 - r.Left, 100 - r.Top, fl, r.Horizontal, r.Vertical, 8 - fl, -1, q => fl == 5 || fl == 0 ? Ground(q, false, z => true) : null));
                }
                floors.U8(0xBE).U8(0x82).U8(44).U8(215);
                up.Parse(floors.ToArray());
                check(uw.Center == new Pos(101, 101, 7) && OnFloor(uw, 5) == r.Horizontal * r.Vertical && OnFloor(uw, 0) == r.Horizontal * r.Vertical && OnFloor(uw, 3) == 0 && uw.WorldLight == 44,
                      "0x4B + 0xBE at " + r + ": six floors of " + r.Horizontal + " x " + r.Vertical + " tiles and the floor change");
            }

            // 0xBE and 0xBF with the floors inside the message (a plain connection)
            foreach (var r in new[] { d, big })
            {
                var pw = new World(Dat());
                var plain = new GameParser(pw);
                plain.Parse(new byte[] { 0x42, (byte)r.Width, (byte)r.Height });   // a plain 10.98 server never sends it; the parser must not depend on who sent it
                plain.Parse(MapPacket(new Pos(100, 100, 8), r, false, q => q.Z == 8));
                var upMsg = new ByteWriter().U8(0xBE);
                int skip = -1;
                for (int i = 5; i >= 0; i--)
                {
                    int fl = i;
                    skip = FloorBytes(upMsg, 100 - r.Left, 100 - r.Top, fl, r.Horizontal, r.Vertical, 8 - fl, skip, q => fl == 5 || fl == 0 ? Ground(q, false, z => true) : null);
                }
                Tail(upMsg, skip);
                upMsg.U8(0x82).U8(45).U8(215);
                plain.Parse(upMsg.ToArray());
                check(pw.Center == new Pos(101, 101, 7) && OnFloor(pw, 5) == r.Horizontal * r.Vertical && OnFloor(pw, 0) == r.Horizontal * r.Vertical && pw.WorldLight == 45,
                      "0xBE at " + r + ": the six surface floors inside the message");
                // down again: floors 8, 9, 10 at offsets -1, -2, -3
                var downMsg = new ByteWriter().U8(0xBF);
                skip = -1;
                for (int i = 8, j = -1; i <= 10; i++, j--)
                {
                    int fl = i;
                    skip = FloorBytes(downMsg, 101 - r.Left, 101 - r.Top, fl, r.Horizontal, r.Vertical, j, skip, q => fl == 8 || fl == 10 ? Ground(q, false, z => true) : null);
                }
                Tail(downMsg, skip);
                downMsg.U8(0x82).U8(46).U8(215);
                plain.Parse(downMsg.ToArray());
                check(pw.Center == new Pos(100, 100, 8) && OnFloor(pw, 8) == r.Horizontal * r.Vertical && OnFloor(pw, 10) == r.Horizontal * r.Vertical && pw.WorldLight == 46,
                      "0xBF at " + r + ": the three underground floors inside the message");
                // one floor up underground (z 9 to 8 style: a single floor z - 2 at offset 3), and one down
                var up2 = new World(Dat());
                var g2 = new GameParser(up2);
                g2.Parse(new byte[] { 0x42, (byte)r.Width, (byte)r.Height });
                g2.Parse(MapPacket(new Pos(100, 100, 9), r, false, q => q.Z == 9));
                var m2 = new ByteWriter().U8(0xBE);
                Tail(m2, FloorBytes(m2, 100 - r.Left, 100 - r.Top, 6, r.Horizontal, r.Vertical, 3, -1, q => Ground(q, false, z => true)));
                m2.U8(0x82).U8(47).U8(215);
                g2.Parse(m2.ToArray());
                check(up2.Center == new Pos(101, 101, 8) && OnFloor(up2, 6) == r.Horizontal * r.Vertical && up2.WorldLight == 47, "0xBE at " + r + ": underground the one new floor z - 2 is read");
                // and one floor down underground: the floor z + 2 at offset -3
                var m3 = new ByteWriter().U8(0xBF);
                Tail(m3, FloorBytes(m3, 101 - r.Left, 101 - r.Top, 11, r.Horizontal, r.Vertical, -3, -1, q => Ground(q, false, z => true)));
                m3.U8(0x82).U8(48).U8(215);
                g2.Parse(m3.ToArray());
                check(up2.Center == new Pos(100, 100, 9) && OnFloor(up2, 11) == r.Horizontal * r.Vertical && up2.WorldLight == 48, "0xBF at " + r + ": underground the one new floor (new z) + 2 is read");
            }
        }

        // ------------------------------------------------------------------------------------------------ compression (0069, 0073, 0131, 0135)
        static byte[] Lcg(int n, int seed)
        {
            var o = new byte[n]; long x = seed;
            for (int i = 0; i < n; i++) { x = (x * 1103515245 + 12345) & 0x7fffffff; o[i] = (byte)((x >> 16) & 0xff); }
            return o;
        }

        /// <summary>A packet the way ProtocolGame sends it with compression on: deflated bytes, u16 length, XTEA, a zero for the checksum.</summary>
        static byte[] DeflatedPacket(byte[] deflated, uint[] key)
        {
            var inner = new ByteWriter().U16((ushort)deflated.Length).Raw(deflated);
            while (inner.Length % 8 != 0) inner.U8(0x33);
            byte[] enc = inner.ToArray();
            Xtea.Encrypt(enc, 0, enc.Length, key);
            return new ByteWriter().U32(0).Raw(enc).ToArray();
        }

        static byte[] PlainPacket(byte[] payload, uint[] key) => Protocol.Encrypt(payload, key).Skip(2).ToArray();

        static void CompressionChecks(Action<bool, string> check)
        {
            // four packets of one stream made by zlib (level 3, window 2^14, memLevel 7, Z_SYNC_FLUSH, the 00 00 FF FF tail cut), as the server's Deflater does
            byte[] p1 = Enumerable.Repeat(Encoding.ASCII.GetBytes("The Hero hits a Rat for 12 hitpoints. "), 6).SelectMany(x => x).Concat(Enumerable.Range(0x20, 0x40).Select(x => (byte)x)).ToArray();
            byte[] p2 = Enumerable.Repeat(Encoding.ASCII.GetBytes("The Hero hits a Rat for 12 hitpoints. "), 3).SelectMany(x => x).Concat(Encoding.ASCII.GetBytes("A rat dies. ")).Concat(p1.Take(40)).ToArray();
            byte[] p3 = Lcg(300, 7);
            byte[] p4 = new byte[150].Concat(Encoding.ASCII.GetBytes("end")).ToArray();
            string[] z =
            {
                "0ac94855f0482dca57c8c82c29564854084a2c5148cb2f523034028914e467e69514eb29840c69550a8a4aca2aaa6aea1a9a5ada3aba7afa068646c626a666e6169656d636b676f60e8e4ece2eae6eee1e9e5ede3ebe7efe018141c121a161e1119151d131b171f10000",
                "a2bfef1d158a80f19092994a42d80300",
                "002c01d3fe6c4e74921325222e31a1cd13be12ed426966ce24fc23d7da8d2097616a06956ec28ad403136828d4571e3c5dee6e5ec04a91115f5d3b513ec253a416ad6ee5389411d0289aa34cf5c0347c59caf08495f3611b0b5068d59804f92eb7299955577999be78c01066870299e57f6cd235bcfb8f449deee23be1eccc8cbff5bfbec20bdbf86b9ce54f85b607cf46e94a4b2afbd4e58f4fe15c11128218a32b18f772df8fd57a475bdee4743493265c919dd98be654598a9d0f1f0ed42adde0dcd85e906ead1cd9abea9ed3da8898dbe003c1427eeb72b84d2c03777b18e52f43397fb42ed9ca6a0b4dab6caf06137f6d55d9b9540152f12b8bb6e52d3c322e85f3cce488b0fb11b4df02d66c65105f716c198820ef724c6e042ff2a3ec3cf6d9dc3eb8348927e7de769babc9fd0600",
                "62189420352f0500",
            };
            byte[][] want = { p1, p2, p3, p4 };
            var inf = new RawInflater();
            bool all = true;
            for (int i = 0; i < 4; i++) { var d = FromHex(z[i]); var got = inf.Inflate(d, 0, d.Length); all &= got.SequenceEqual(want[i]); }
            check(all && inf.PacketsIn == 4, "inflate: four packets of one zlib stream (fixed codes, back references into the earlier packet, a stored block, zeros) come out as they went in");
            var again = new RawInflater();
            var first = FromHex(z[1]);
            check(Throws<CompressionException>(() => again.Inflate(first, 0, first.Length)), "inflate: the second packet alone refers to history that is not there");

            // a long stream made by DeflateStream with a sync flush after every packet: dynamic codes, more than 32 KB so the history wraps
            var ms = new MemoryStream();
            var ds = new DeflateStream(ms, CompressionLevel.Optimal, true);
            var words = new[] { "creature", "damage", "hitpoints", "experience", "Hero", "Rat", "Wolf", "the", "a", "of", "gold", "coins", "and", "loot", "bag" };
            var rnd = new Random(5);
            var inf2 = new RawInflater();
            int okPackets = 0, total = 0;
            long last = 0;
            for (int n = 0; n < 60; n++)
            {
                var sb = new StringBuilder();
                int size = 50 + rnd.Next(2400);
                while (sb.Length < size) sb.Append(words[rnd.Next(words.Length)]).Append(rnd.Next(4) == 0 ? "." : " ");
                byte[] payload = Encoding.ASCII.GetBytes(sb.ToString()).Concat(Lcg(rnd.Next(60), n)).ToArray();
                ds.Write(payload, 0, payload.Length);
                ds.Flush();
                byte[] all2 = ms.ToArray();
                byte[] chunk = all2.Skip((int)last).ToArray();
                last = all2.Length;
                if (chunk.Length < 5 || !chunk.Skip(chunk.Length - 4).SequenceEqual(new byte[] { 0, 0, 0xFF, 0xFF })) break;   // this runtime's flush is not a sync flush
                chunk = chunk.Take(chunk.Length - 4).ToArray();
                total += payload.Length;
                if (inf2.Inflate(chunk, 0, chunk.Length).SequenceEqual(payload)) okPackets++;
            }
            check(okPackets == 60 && total > 70000, "inflate: sixty packets of a DeflateStream (sync flush each) over 70 KB, history wrapping past 32 KB: " + okPackets + " of 60");

            // the limits of base patch 0131: 65536 bytes are the cap, a final block and a bad block are errors
            Func<byte[], byte[]> deflateOne = data =>
            {
                var m = new MemoryStream();
                byte[] snapshot;
                using (var d = new DeflateStream(m, CompressionLevel.Fastest, true)) { d.Write(data, 0, data.Length); d.Flush(); snapshot = m.ToArray(); }
                return snapshot.Take(snapshot.Length - 4).ToArray();
            };
            var cap = deflateOne(new byte[65536]);
            check(new RawInflater().Inflate(cap, 0, cap.Length).Length == 65536, "inflate: 65536 bytes in one packet are allowed");
            var over = deflateOne(new byte[65537]);
            check(Throws<CompressionException>(() => new RawInflater().Inflate(over, 0, over.Length)), "inflate: 65537 bytes in one packet are refused (the size cap of 0131)");
            check(Throws<CompressionException>(() => new RawInflater().Inflate(new byte[] { 0x06 }, 0, 1)), "inflate: block type 3 is an error");
            check(Throws<CompressionException>(() => new RawInflater().Inflate(new byte[] { 0x07 }, 0, 1)), "inflate: a final block ends the stream, which the client treats as an error");
            check(Throws<CompressionException>(() => new RawInflater().Inflate(new byte[0], 0, 0)), "inflate: nothing but the footer is an empty result, an error");
            var cut = FromHex(z[0]).Take(40).ToArray();
            check(Throws<CompressionException>(() => new RawInflater().Inflate(cut, 0, cut.Length)), "inflate: a packet cut short is an error");

            // the packet layer: checksum word 0, XTEA, inner length of the deflated bytes; small bodies stay plain with a real adler32 and do not touch the stream
            var key = Protocol.NewXteaKey();
            var stream = new RawInflater();
            byte[] q = Encoding.ASCII.GetBytes("plain small body");
            var a = Protocol.Decrypt(DeflatedPacket(FromHex(z[0]), key), key, stream);
            var b = Protocol.Decrypt(PlainPacket(q, key), key, stream);
            var c = Protocol.Decrypt(DeflatedPacket(FromHex(z[1]), key), key, stream);
            check(a.SequenceEqual(p1) && b.SequenceEqual(q) && c.SequenceEqual(p2), "Decrypt: deflated, plain and deflated packets of one connection, the plain one between does not disturb the stream");
            check(Throws<ProtocolException>(() => Protocol.Decrypt(DeflatedPacket(FromHex(z[0]), key), key)), "Decrypt: a deflated packet on a connection with no inflater (the login port) is refused");
            var bad = PlainPacket(q, key); bad[0] ^= 1;
            check(Throws<ProtocolException>(() => Protocol.Decrypt(bad, key, stream)), "Decrypt: a plain packet still needs its checksum");
            check(Protocol.Decrypt(PlainPacket(q, key), key).SequenceEqual(q), "Decrypt: the plain path is as before, no inflater needed");
        }
    }
}
