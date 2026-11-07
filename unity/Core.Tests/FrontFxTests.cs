// Checks of the front-art live effects (Core/FrontFx.cs, FrontFxIds.cs, FrontFxArt.cs, FrontFxDirector.cs and the parser's 0x83 / 0x84 /
// 0x85 / 0x86 / 0xB4 events): byte-level packets, the id to element table against the server's Lua files, the look of each element, number
// text, the melee rule, the timing and the director's rules.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class FrontFxTests
    {
        static readonly Pos P0 = new Pos(1000, 1000, 7);

        static World NewWorld()
        {
            var w = new World(DatFile.Parse(Program.SyntheticDat()));
            w.Center = P0;
            return w;
        }

        static Creature Put(World w, uint id, string name, byte type, Pos p, Dir d = Dir.South)
        {
            var c = new Creature { Id = id, Name = name, Type = type, Direction = d };
            w.Creatures[id] = c;
            w.AddThing(p, new Thing { Creature = c });
            return c;
        }

        static ByteWriter Pos3(ByteWriter b, Pos p) { return b.U16((ushort)p.X).U16((ushort)p.Y).U8((byte)p.Z); }

        static string FindServerLib()
        {
            string dir = AppContext.BaseDirectory;
            for (int i = 0; i < 10 && dir != null; i++, dir = Path.GetDirectoryName(dir))
            {
                string c = Path.Combine(dir, "server", "data", "lib");
                if (Directory.Exists(c) && File.Exists(Path.Combine(c, "chaos_fx.lua"))) return c;
                c = Path.Combine(dir, "..", "server", "data", "lib");
                if (Directory.Exists(c) && File.Exists(Path.Combine(c, "chaos_fx.lua"))) return c;
            }
            return null;
        }

        /// <summary>The ids the server names in its Lua files (read here by its own small reader, not the generator's).</summary>
        static void ServerIds(string lib, HashSet<int> effects, HashSet<int> missiles)
        {
            var open = new Regex(@"^(ChaosFx|ChaosFxMissile|ChaosVfx|ChaosVfxMissile|ChaosVfxAura)\s*=\s*\{");
            var dotted = new Regex(@"^(ChaosVfxMissile|ChaosVfx|ChaosPair51Missile)\.\w+\s*=\s*(?:\{\s*id\s*=\s*)?(\d+)\b");
            var inTable = new Regex(@"^\s*\w+\s*=\s*(?:\{\s*id\s*=\s*)?(\d+)\b");
            foreach (var file in Directory.GetFiles(lib, "*.lua"))
            {
                string table = null;
                foreach (var line in File.ReadLines(file))
                {
                    var m = open.Match(line);
                    if (m.Success) { table = m.Groups[1].Value; continue; }
                    if (table != null && line.StartsWith("}")) { table = null; continue; }
                    m = dotted.Match(line);
                    if (m.Success)
                    {
                        (m.Groups[1].Value.EndsWith("Missile") || m.Groups[1].Value.StartsWith("ChaosPair51") ? missiles : effects).Add(int.Parse(m.Groups[2].Value));
                        continue;
                    }
                    if (table != null && !line.TrimStart().StartsWith("--"))
                    {
                        m = inTable.Match(line);
                        if (m.Success) (table.EndsWith("Missile") ? missiles : effects).Add(int.Parse(m.Groups[1].Value));
                    }
                }
            }
            string cat = Path.Combine(lib, "..", "spells", "effects_catalog.csv");
            if (File.Exists(cat))
                foreach (var line in File.ReadLines(cat).Skip(1))
                {
                    var f = line.Split(',');
                    if (f.Length < 4) continue;
                    (f[2] == "missile" ? missiles : effects).Add(int.Parse(f[3]));
                }
        }

        public static void Run(Action<bool, string> check)
        {
            Parser(check);
            Ids(check);
            Look(check);
            Text(check);
            Melee(check);
            Timing(check);
            Director(check);
            Art(check);
        }

        // ---- the parser ----

        static void Parser(Action<bool, string> check)
        {
            var w = NewWorld();
            var parser = new GameParser(w);
            var pk = Pos3(new ByteWriter().U8(0x83), P0.Offset(2, 1)).U16(372);
            pk.U8(0x1D);
            bool pinged = false;
            parser.Pinged = () => pinged = true;
            parser.Parse(pk.ToArray());
            check(w.Fx.Count == 0 && pinged, "fx: nothing is queued until a consumer enables the feed, and the packet still reads through");

            w.Fx.Enabled = true;
            pinged = false;
            // magic effect with a 16 bit id, missile with an 8 bit id, animated text, creature square, then a ping: one packet
            var b = Pos3(new ByteWriter().U8(0x83), P0.Offset(2, 1)).U16(372);
            Pos3(Pos3(b.U8(0x85), P0), P0.Offset(4, -1)).U8(118);
            Pos3(b.U8(0x84), P0.Offset(1, 0)).U8(180).Str("12");
            b.U8(0x86).U32(0x40000007).U8(215);
            b.U8(0x1D);
            parser.Parse(b.ToArray());
            check(pinged && w.Fx.Count == 4, "fx: effect, missile, text and square are queued and the packet reads to its end");
            FxEvent e;
            w.Fx.TryDequeue(out e);
            check(e.Kind == FxKind.Effect && e.Pos == P0.Offset(2, 1) && e.Id == 372, "fx: 0x83 reads position and a 16 bit effect id");
            w.Fx.TryDequeue(out e);
            check(e.Kind == FxKind.Missile && e.Pos == P0 && e.To == P0.Offset(4, -1) && e.Id == 118, "fx: 0x85 reads from, to and an 8 bit missile id");
            w.Fx.TryDequeue(out e);
            check(e.Kind == FxKind.AnimText && e.Pos == P0.Offset(1, 0) && e.Color == 180 && e.Text == "12", "fx: 0x84 reads position, colour and text");
            w.Fx.TryDequeue(out e);
            check(e.Kind == FxKind.Square && e.Creature == 0x40000007 && e.Color == 215, "fx: 0x86 reads the creature and its square colour");
            check(!w.Fx.TryDequeue(out e), "fx: the queue is empty after the four");

            // damage dealt (two pairs), damage received, heal (one pair), experience, damage of others, then an ordinary server line
            b = Pos3(new ByteWriter().U8(0xB4).U8(23), P0.Offset(1, 0)).U32(50).U8(180).U32(7).U8(198).Str("A rat loses 57 hitpoints due to your attack.");
            Pos3(b.U8(0xB4).U8(24), P0).U32(12).U8(180).U32(0).U8(0).Str("You lose 12 hitpoints due to an attack by a rat.");
            Pos3(b.U8(0xB4).U8(25), P0).U32(300).U8(30).Str("You healed yourself for 300 hitpoints.");
            Pos3(b.U8(0xB4).U8(26), P0.Offset(1, 0)).U32(120).U8(215).Str("A rat dies. 120 exp");
            Pos3(b.U8(0xB4).U8(27), P0.Offset(3, 3)).U32(9).U8(154).U32(0).U8(0).Str("A bat loses 9 hitpoints due to an attack by a cultist.");
            Pos3(b.U8(0xB4).U8(28), P0.Offset(3, 3)).U32(4).U8(30).Str("A bat heals itself for 4 hitpoints.");
            b.U8(0xB4).U8(20).Str("You see a rat.");
            var said = new List<string>();
            parser.Chat = (who, text, type) => said.Add(text);
            parser.Parse(b.ToArray());
            var got = new List<FxEvent>();
            while (w.Fx.TryDequeue(out e)) got.Add(e);
            check(got.Count == 6 && got.All(x => x.Kind == FxKind.Number), "fx: six damage, heal and experience messages become numbers");
            check(got[0].Id == 23 && got[0].Pos == P0.Offset(1, 0) && got[0].Value == 50 && got[0].Color == 180 && got[0].Value2 == 7 && got[0].Color2 == 198 &&
                  got[0].Text.Contains("your attack"), "fx: damage dealt carries both values and colours and the sentence");
            check(got[1].Id == 24 && got[1].Value == 12 && got[1].Value2 == 0, "fx: damage received");
            check(got[2].Id == 25 && got[2].Value == 300 && got[2].Color == 30, "fx: a heal has one pair");
            check(got[3].Id == 26 && got[3].Value == 120 && got[4].Id == 27 && got[4].Color == 154 && got[5].Id == 28, "fx: experience, damage of others, heal of others");
            check(said.Count == 1 && said[0] == "You see a rat.", "fx: an ordinary server line is still chat and not a number");

            // a Chaos-extended layout is not read here (the client does not ask for it): the old layout ends the message at the text
            var a = new ByteWriter();
            Pos3(a.U8(0xB4).U8(23), P0).U32(5).U8(180).U32(0).U8(0).Str("x");
            w.Fx.Clear();
            parser.Parse(a.ToArray());
            check(w.Fx.Count == 1, "fx: one message, one number event");
            w.Fx.Enabled = false;
            for (int i = 0; i < 3; i++) w.Fx.Push(FxEvent.Effect(P0, 1));
            check(w.Fx.Count == 1, "fx: a disabled feed drops pushes");
            w.Fx.Enabled = true;
            for (int i = 0; i < FxFeed.Max + 50; i++) w.Fx.Push(FxEvent.Effect(P0, i));
            w.Fx.TryDequeue(out e);
            check(w.Fx.Count == FxFeed.Max - 1 && e.Id == 50, "fx: the feed keeps the newest " + FxFeed.Max + " events");
        }

        // ---- ids ----

        static void Ids(Action<bool, string> check)
        {
            check(FrontFx.ElementOfEffect(372) == FxElement.Fire && FrontFx.ElementOfEffect(379) == FxElement.Ice && FrontFx.ElementOfEffect(384) == FxElement.Energy &&
                  FrontFx.ElementOfEffect(390) == FxElement.Blood && FrontFx.ElementOfEffect(397) == FxElement.Death && FrontFx.ElementOfEffect(403) == FxElement.Holy &&
                  FrontFx.ElementOfEffect(406) == FxElement.Arcane && FrontFx.ElementOfEffect(402) == FxElement.Poison && FrontFx.ElementOfEffect(393) == FxElement.Shadow &&
                  FrontFx.ElementOfEffect(411) == FxElement.Heal, "fx ids: our effects 372..411 by element");
            check(FrontFx.ElementOfEffect(424) == FxElement.None && FrontFx.ElementOfEffect(11) == FxElement.None && FrontFx.ElementOfEffect(3) == FxElement.None,
                  "fx ids: loot rays, teleports and puffs draw nothing");
            check(FrontFx.ElementOfEffect(7) == FxElement.Fire && FrontFx.ElementOfEffect(12) == FxElement.Energy && FrontFx.ElementOfEffect(40) == FxElement.Holy && FrontFx.ElementOfEffect(44) == FxElement.Ice,
                  "fx ids: stock effects (fire area, energy hit, holy damage, ice attack)");
            check(FrontFx.ElementOfEffect(99999) == FxElement.Neutral && FrontFx.ElementOfMissile(250) != FxElement.None && FrontFx.ElementOfMissile(0) == FxElement.Neutral,
                  "fx ids: an unknown id is neutral, a missile is never 'nothing'");
            check(FrontFx.ElementOfMissile(116) == FxElement.Fire && FrontFx.ElementOfMissile(118) == FxElement.Ice && FrontFx.ElementOfMissile(119) == FxElement.Arcane &&
                  FrontFx.ElementOfMissile(120) == FxElement.Shadow && FrontFx.ElementOfMissile(121) == FxElement.Holy && FrontFx.ElementOfMissile(122) == FxElement.Blood &&
                  FrontFx.ElementOfMissile(123) == FxElement.Energy && FrontFx.ElementOfMissile(124) == FxElement.Poison && FrontFx.ElementOfMissile(125) == FxElement.Death,
                  "fx ids: our ten missiles 116..125 by element");
            check(FrontFx.ElementOfMissile(4) == FxElement.Fire && FrontFx.ElementOfMissile(29) == FxElement.Ice && FrontFx.ElementOfMissile(31) == FxElement.Holy &&
                  FrontFx.ElementOfMissile(3) == FxElement.Physical, "fx ids: stock missiles (fire, ice, holy, arrow)");
            check(FrontFx.EffectTable.Count > 4000 && FrontFx.MissileTable.Count > 150, "fx ids: the table holds " + FrontFx.EffectTable.Count + " effects and " + FrontFx.MissileTable.Count + " missiles");

            string lib = FindServerLib();
            if (lib == null) { check(true, "fx ids: server/data/lib not found, the coverage check is skipped"); }
            else
            {
                var ef = new HashSet<int>(); var mi = new HashSet<int>();
                ServerIds(lib, ef, mi);
                check(ef.Count > 4000 && mi.Count > 150, "fx ids: the Lua files name " + ef.Count + " effects and " + mi.Count + " missiles");
                var noEf = ef.Where(i => !FrontFx.EffectTable.ContainsKey(i)).Take(8).ToList();
                var noMi = mi.Where(i => !FrontFx.MissileTable.ContainsKey(i)).Take(8).ToList();
                check(noEf.Count == 0, "fx ids: every effect id the server names maps to an element (run unity/tools/gen_front_fx_ids.py): " + string.Join(",", noEf));
                check(noMi.Count == 0, "fx ids: every missile id the server names maps to an element: " + string.Join(",", noMi));
                check(mi.All(i => i <= 255), "fx ids: missile ids fit the 8 bits of 0x85");
                check(mi.All(i => FrontFx.MissileKinds.Contains(FrontFx.MissileLook(FrontFx.ElementOfMissile(i)).Kind)), "fx ids: every missile gets one of the 8 missile arts");
                var el = ef.Select(FrontFx.ElementOfEffect).Distinct().ToList();
                check(new[] { FxElement.Fire, FxElement.Ice, FxElement.Energy, FxElement.Arcane, FxElement.Death, FxElement.Holy, FxElement.Physical, FxElement.Blood, FxElement.Shadow, FxElement.Poison }
                      .All(x => el.Contains(x)), "fx ids: the server's effects use every element");
            }

            // runs decode
            var d = FrontFx.Decode("1-3F,4I,6-7X");
            check(d.Count == 6 && d[2] == FxElement.Fire && d[4] == FxElement.Ice && d[7] == FxElement.None && !d.ContainsKey(5), "fx ids: runs decode");
        }

        // ---- the look of an element ----

        static void Look(Action<bool, string> check)
        {
            var all = Enum.GetValues(typeof(FxElement)).Cast<FxElement>().ToList();
            check(all.All(e =>
            {
                var p = FrontFx.Palette(e);
                float core = p.CR + p.CG + p.CB, body = p.BR + p.BG + p.BB, rim = p.RR + p.RG + p.RB;
                return core >= body && body >= rim && rim > 0.2f;
            }), "fx look: every element's palette goes core, body, rim from light to dark");
            var fire = FrontFx.Palette(FxElement.Fire); var ice = FrontFx.Palette(FxElement.Ice); var blood = FrontFx.Palette(FxElement.Blood);
            check(fire.BR > fire.BB && ice.BB > ice.BR && blood.BR > blood.BG * 3f, "fx look: fire is warm, ice cold, blood red");
            check(all.All(e => FrontFx.MissileKinds.Contains(FrontFx.MissileLook(e).Kind)), "fx look: every element has one of the 8 missile arts");
            check(FrontFx.MissileLook(FxElement.Fire).Kind == "fireball" && FrontFx.MissileLook(FxElement.Ice).Kind == "frost" && FrontFx.MissileLook(FxElement.Arcane).Kind == "arcane" &&
                  FrontFx.MissileLook(FxElement.Death).Kind == "skull_necrotic" && FrontFx.MissileLook(FxElement.Holy).Kind == "holy" && FrontFx.MissileLook(FxElement.Physical).Kind == "blood" &&
                  FrontFx.MissileLook(FxElement.Blood).Kind == "blood" && FrontFx.MissileLook(FxElement.Shadow).Kind == "shadow", "fx look: missile kinds by element");
            var pz = FrontFx.MissileLook(FxElement.Poison);
            check(pz.G > pz.R && pz.G > pz.B && FrontFx.MissileLook(FxElement.Fire).R == 1f, "fx look: poison is a tinted missile (green), fire is untinted");
            check(FrontFx.ElementOfTextColor(180) == FxElement.Physical && FrontFx.ElementOfTextColor(198) == FxElement.Fire && FrontFx.ElementOfTextColor(154) == FxElement.Energy &&
                  FrontFx.ElementOfTextColor(30) == FxElement.Earth && FrontFx.ElementOfTextColor(143) == FxElement.Ice && FrontFx.ElementOfTextColor(210) == FxElement.Holy &&
                  FrontFx.ElementOfTextColor(108) == FxElement.Death && FrontFx.ElementOfTextColor(7) == FxElement.Neutral, "fx look: damage colours to elements");
        }

        // ---- text ----

        static void Text(Action<bool, string> check)
        {
            check(FrontFx.Format(0) == "0" && FrontFx.Format(57) == "57" && FrontFx.Format(9999) == "9999" && FrontFx.Format(10000) == "10K" && FrontFx.Format(12345) == "12.3K" &&
                  FrontFx.Format(123456) == "123K" && FrontFx.Format(1234567) == "1.2M" && FrontFx.Format(25000000) == "25M" && FrontFx.Format(2500000000L) == "2.5B", "fx text: numbers shorten above 9999");
            var samples = new[] { "0", "9999", "12.3K", "123K", "1.2M", "99B", "+120", "CHAOS!".Replace("!", "") };
            check(samples.All(s => s.All(c => PixelText.Has(c))), "fx text: the pixel font has every character a number needs");
            check(FrontFx.AttackerName("You lose 12 hitpoints due to an attack by a rat.") == "rat" && FrontFx.AttackerName("A bat loses 9 hitpoints due to an attack by Mira.") == "mira" &&
                  FrontFx.AttackerName("A rat loses 5 hitpoints due to your attack.") == null && FrontFx.AttackerName("") == null, "fx text: the attacker named by a damage sentence");
        }

        // ---- melee ----

        static void Melee(Action<bool, string> check)
        {
            var w = NewWorld();
            var me = Put(w, 1, "Hero", 0, P0, Dir.East); w.PlayerId = 1;
            var rat = Put(w, 2, "Rat", 1, P0.Offset(1, 0), Dir.West);
            var bat = Put(w, 3, "Bat", 1, P0.Offset(2, 1), Dir.South);
            var far = Put(w, 4, "Troll", 1, P0.Offset(4, 0), Dir.West);
            check(FrontFx.MeleeAttacker(w, rat.Position, 23, "A rat loses 5 hitpoints due to your attack.") == me, "melee: our own hit is ours when we stand next to the target");
            check(FrontFx.MeleeAttacker(w, P0, 24, "You lose 5 hitpoints due to an attack by a rat.") == rat, "melee: the sentence names the rat next to us");
            check(FrontFx.MeleeAttacker(w, P0, 24, "You lose 5 hitpoints.") == rat, "melee: without a name the hostile neighbour that faces the target");
            check(FrontFx.MeleeAttacker(w, P0, 24, "You lose 5 hitpoints due to an attack by a troll.") == rat, "melee: a named attacker that is not next to the target is ignored");
            check(FrontFx.MeleeAttacker(w, rat.Position, 27, "A rat loses 3 hitpoints due to an attack by a bat.") == bat, "melee: damage of others, the named bat next to the rat");
            check(FrontFx.MeleeAttacker(w, P0.Offset(5, 5), 24, "") == null, "melee: nobody next to the tile, nobody swings");
            check(FrontFx.MeleeAttacker(w, far.Position, 23, "") == null, "melee: our hit on a far target is a ranged hit");
            check(FrontFx.MeleeAttacker(w, P0, 27, "") == rat, "melee: a monster next to a player swings at it");
            var guard = Put(w, 5, "Guard", 2, P0.Offset(0, 1), Dir.North);
            check(FrontFx.MeleeAttacker(w, P0, 24, "") == rat && FrontFx.MeleeAttacker(w, rat.Position, 27, "") != guard, "melee: an npc neither swings nor is hit");
            check(FrontFx.Faces(rat, P0) && !FrontFx.Faces(bat, P0.Offset(2, 0)) && FrontFx.Faces(me, rat.Position), "melee: facing follows the direction to the tile");
            check(FrontFx.IsPhysical(FxElement.Physical) && FrontFx.IsPhysical(FxElement.Blood) && !FrontFx.IsPhysical(FxElement.Fire), "melee: only physical hits slash");
        }

        // ---- timing ----

        static void Timing(Action<bool, string> check)
        {
            check(Math.Abs(FrontFxTiming.Flight(0f) - FrontFxTiming.MissileMin) < 1e-6f && Math.Abs(FrontFxTiming.Flight(100f) - FrontFxTiming.MissileMax) < 1e-6f &&
                  Math.Abs(FrontFxTiming.Flight(8f) - 0.5f) < 1e-6f && FrontFxTiming.Flight(3f) < FrontFxTiming.Flight(6f), "fx timing: flight time follows the distance, clamped");
            check(FrontFxTiming.Arc(5f, 0f) == 0f && FrontFxTiming.Arc(5f, 1f) == 0f && FrontFxTiming.Arc(5f, 0.5f) > 0f && FrontFxTiming.Arc(50f, 0.5f) <= FrontFxTiming.ArcMax + 1e-6f, "fx timing: the arc is 0 at both ends and capped");
            check(FrontFxTiming.BurstFrame(0f) == 0 && FrontFxTiming.BurstFrame(1f) == FrontFxTiming.BurstFrames - 1 && FrontFxTiming.BurstFrame(2f) == FrontFxTiming.BurstFrames - 1 &&
                  FrontFxTiming.BurstFrame(-1f) == 0 && FrontFxTiming.BurstFrame(0.5f) == FrontFxTiming.BurstFrames / 2, "fx timing: burst frames");
            check(FrontFxTiming.SlashFrame(0f) == 0 && FrontFxTiming.SlashFrame(1f) == FrontArtSlash.Frames - 1, "fx timing: slash frames match the slash strip");
            float prev = -1f; bool rising = true;
            for (int i = 0; i <= 20; i++) { float r = FrontFxTiming.NumberRiseAt(i / 20f); rising &= r >= prev; prev = r; }
            check(rising && FrontFxTiming.NumberRiseAt(0f) == 0f && Math.Abs(FrontFxTiming.NumberRiseAt(1f) - FrontFxTiming.NumberRise) < 1e-6f &&
                  FrontFxTiming.NumberRiseAt(0.5f) > FrontFxTiming.NumberRise * 0.5f, "fx timing: a number rises fast and then slows, ending at its full rise");
            check(FrontFxTiming.NumberAlpha(0f) == 1f && FrontFxTiming.NumberAlpha(0.6f) == 1f && FrontFxTiming.NumberAlpha(1f) < 1e-5f && FrontFxTiming.NumberAlpha(0.8f) > 0.45f && FrontFxTiming.NumberAlpha(0.8f) < 0.55f,
                  "fx timing: a number is opaque for 60 percent of its life, then fades out");
            check(FrontFxTiming.NumberScale(0f) == 1.5f && FrontFxTiming.NumberScale(0.5f) == 1f && FrontFxTiming.NumberScale(0.06f) > 1f && FrontFxTiming.NumberScale(0.06f) < 1.5f, "fx timing: a number pops from 1.5 to 1");
            check(FrontFxTiming.Flash(0f) == 1f && FrontFxTiming.Flash(1f) == 0f && FrontFxTiming.Flash(0.5f) == 0.25f, "fx timing: a flash falls off with the square");
        }

        // ---- the director ----

        static void Director(Action<bool, string> check)
        {
            var w = NewWorld();
            var me = Put(w, 1, "Hero", 0, P0, Dir.East); w.PlayerId = 1;
            var rat = Put(w, 2, "Rat", 1, P0.Offset(1, 0), Dir.West);
            var dir = new FrontFxDirector();
            dir.Update(10f);

            // an effect with no missile starts now; a loot ray draws nothing
            dir.Feed(w, FxEvent.Effect(P0.Offset(3, 0), 372));
            dir.Feed(w, FxEvent.Effect(P0.Offset(3, 0), 424));
            check(dir.Bursts.Count == 1 && dir.Bursts[0].T0 == 10f && dir.Bursts[0].El == FxElement.Fire && dir.Bursts[0].Light, "director: a fire effect is a burst now, a loot ray nothing");
            dir.Feed(w, FxEvent.Effect(P0, 411));
            check(dir.Bursts.Count == 2 && dir.Bursts[1].Heal, "director: a heal effect is a heal burst");

            // a missile, then the effect and the damage at its end wait for the landing
            dir.Clear();
            var end = P0.Offset(6, 0);
            dir.Feed(w, FxEvent.Missile(P0, end, 118));
            var m = dir.Missiles[0];
            check(m.El == FxElement.Ice && Math.Abs(m.Dur - FrontFxTiming.Flight(6f)) < 1e-6f && m.T0 == 10f, "director: a missile flies the time its distance needs");
            dir.Update(10.1f);
            dir.Feed(w, FxEvent.Effect(end, 379));
            dir.Feed(w, FxEvent.Number(23, end, 40, 143, 0, 0, "x"));
            float land = 10f + m.Dur;
            check(Math.Abs(dir.Bursts[0].T0 - land) < 1e-5f && Math.Abs(dir.Numbers[0].T0 - land) < 1e-5f, "director: the effect and the number at the missile's end wait for it to land");
            dir.Feed(w, FxEvent.Effect(P0.Offset(2, 2), 379));
            check(Math.Abs(dir.Bursts[1].T0 - 10.1f) < 1e-5f, "director: an effect elsewhere does not wait");
            dir.Update(10.3f);
            dir.Feed(w, FxEvent.Effect(end, 379));
            check(Math.Abs(dir.Bursts[dir.Bursts.Count - 1].T0 - 10.3f) < 1e-5f || dir.LandingDelay(end) > 0f, "director: the landing delay never goes negative: " + dir.LandingDelay(end));
            dir.Update(12f);
            check(dir.Missiles.Count == 0 && dir.Bursts.Count == 0 && dir.Numbers.Count == 0, "director: Update drops what is over");
            dir.Clear();
            dir.Update(20f);

            // numbers: two values are two numbers, same tile stacks, element colours, sizes
            dir.Feed(w, FxEvent.Number(23, rat.Position, 50, 180, 7, 198, "A rat loses 57 hitpoints due to your attack."));
            check(dir.Numbers.Count == 2 && dir.Numbers[0].Text == "50" && dir.Numbers[0].El == FxElement.Physical && dir.Numbers[1].Text == "7" && dir.Numbers[1].El == FxElement.Fire &&
                  dir.Numbers[0].Stack == 0 && dir.Numbers[1].Stack == 1, "director: the two values of a hit are two numbers, the second stacks");
            dir.Feed(w, FxEvent.Number(24, P0, 12345, 180, 0, 0, ""));
            dir.Feed(w, FxEvent.Number(25, P0, 300, 30, 0, 0, ""));
            dir.Feed(w, FxEvent.Number(27, P0.Offset(5, 5), 9, 154, 0, 0, ""));
            dir.Feed(w, FxEvent.Number(26, P0, 120, 215, 0, 0, ""));
            var rec = dir.Numbers.First(n => n.Text == "12.3K");
            check(rec.Size > 1f && dir.Numbers.First(n => n.Text == "300").El == FxElement.Heal && dir.Numbers.First(n => n.Text == "9").Size < 1f && dir.Numbers.Any(n => n.Text == "+120"),
                  "director: received numbers are big, heals green, numbers of others small, experience gets a plus");
            check(dir.Numbers.Count == 6, "director: nothing is added for a value of 0");
            dir.Feed(w, FxEvent.AnimText(P0, 198, "Critical hit now and forever"));
            check(dir.Numbers.Last().Text.Length == 12 && dir.Numbers.Last().El == FxElement.Fire, "director: animated text is a number, cut to 12 letters");

            // the slash rule
            dir.Clear(); dir.Update(30f);
            dir.Feed(w, FxEvent.Number(23, rat.Position, 5, 180, 0, 0, "A rat loses 5 hitpoints due to your attack."));
            check(dir.Slashes.Count == 1 && dir.Slashes[0].From == P0 && dir.Slashes[0].To == rat.Position, "director: a physical hit next to its attacker draws a slash from the attacker to the target");
            dir.Update(30.1f);
            dir.Feed(w, FxEvent.Number(23, rat.Position, 5, 180, 0, 0, ""));
            check(dir.Slashes.Count == 1, "director: the same attacker does not slash twice within a quarter second");
            dir.Update(30.4f);
            dir.Feed(w, FxEvent.Number(23, rat.Position, 5, 180, 0, 0, ""));
            check(dir.Slashes.Count == 1 && Math.Abs(dir.Slashes[0].T0 - 30.4f) < 1e-5f, "director: it slashes again later (the first slash is over)");
            dir.Clear(); dir.Update(40f);
            dir.Feed(w, FxEvent.Number(23, rat.Position, 5, 198, 0, 0, ""));
            check(dir.Slashes.Count == 0, "director: a fire hit is no slash");
            dir.Feed(w, FxEvent.Missile(P0, rat.Position, 3));
            dir.Feed(w, FxEvent.Number(23, rat.Position, 5, 180, 0, 0, ""));
            check(dir.Slashes.Count == 0, "director: a physical hit that comes with a missile (an arrow) is no slash");
            dir.Clear(); dir.Update(50f);
            dir.Feed(w, FxEvent.Number(24, P0, 5, 180, 0, 0, "You lose 5 hitpoints due to an attack by a rat."));
            check(dir.Slashes.Count == 1 && dir.Slashes[0].From == rat.Position && dir.Slashes[0].To == P0, "director: the rat's blow on us slashes from the rat to us");
            dir.Feed(w, FxEvent.Number(23, P0.Offset(9, 9), 5, 180, 0, 0, ""));
            check(dir.Slashes.Count == 1, "director: a hit with no attacker next to it draws no slash");

            // crowds: an area spell starts many bursts at once, the later ones are small and unlit
            dir.Clear(); dir.Update(60f);
            for (int i = 0; i < 30; i++) dir.Feed(w, FxEvent.Effect(P0.Offset(i % 7, i / 7), 372));
            check(dir.Bursts.Count == 30 && dir.Bursts.Count(b => b.Light) == FrontFxDirector.CrowdBursts && dir.Bursts.Last().Scale < 1f, "director: the first " + FrontFxDirector.CrowdBursts + " bursts of a crowd have light, the rest are small");
            var lights = new List<FxLight>();
            dir.Lights(lights, 6);
            check(lights.Count == 6 && lights.Zip(lights.Skip(1), (a, b) => a.Intensity >= b.Intensity).All(x => x), "director: at most 6 lights, the brightest first");
            dir.Update(60.9f);
            dir.Lights(lights, 6);
            check(lights.Count == 0, "director: the flashes are over after the flash time");

            // light along a missile
            dir.Clear(); dir.Update(70f);
            dir.Feed(w, FxEvent.Missile(P0, P0.Offset(8, 0), 116));
            dir.Update(70f + dir.Missiles[0].Dur / 2f);
            dir.Lights(lights, 6);
            check(lights.Count == 1 && Math.Abs(lights[0].U - 0.5f) < 1e-3f && lights[0].R > lights[0].B, "director: a warm light travels with a fire missile");

            // caps
            dir.Clear(); dir.Update(80f);
            for (int i = 0; i < 100; i++) { dir.Feed(w, FxEvent.Effect(P0.Offset(i, 0), 372)); dir.Feed(w, FxEvent.Missile(P0, P0.Offset(i + 1, 0), 116)); dir.Feed(w, FxEvent.Number(25, P0.Offset(i, 1), 5, 30, 0, 0, "")); }
            check(dir.Bursts.Count <= FrontFxDirector.MaxBursts && dir.Missiles.Count <= FrontFxDirector.MaxMissiles && dir.Numbers.Count <= FrontFxDirector.MaxNumbers, "director: the pools are capped");
            check(dir.Bursts.Select(b => b.Id).Concat(dir.Missiles.Select(x => x.Id)).Concat(dir.Numbers.Select(n => n.Id)).Distinct().Count() == dir.Bursts.Count + dir.Missiles.Count + dir.Numbers.Count, "director: every item has its own id");
        }

        // ---- the pictures ----

        static int Opaque(byte[] px) { int n = 0; for (int i = 3; i < px.Length; i += 4) if (px[i] > 0) n++; return n; }

        static void Art(Action<bool, string> check)
        {
            var fire = FrontFx.Palette(FxElement.Fire); var ice = FrontFx.Palette(FxElement.Ice);
            var a = FrontFxArt.ImpactStrip(fire, false);
            int frame = FrontFxArt.ImpactSize * FrontFxArt.ImpactSize * 4;
            check(a.Length == frame * FrontFxTiming.BurstFrames && Opaque(a) > 2000, "fx art: the impact strip is 12 frames of 64 with ink");
            check(a.SequenceEqual(FrontFxArt.ImpactStrip(fire, false)) && !a.SequenceEqual(FrontFxArt.ImpactStrip(ice, false)) && !a.SequenceEqual(FrontFxArt.ImpactStrip(fire, true)), "fx art: deterministic, one per element, heal differs");
            // the flash shrinks, the ring grows: the first frame's ink is in the middle, the last frame's outside it
            int Ink(byte[] px, int f, bool inner)
            {
                int s = FrontFxArt.ImpactSize, n = 0;
                for (int y = 0; y < s; y++)
                    for (int x = 0; x < s; x++)
                    {
                        float d = (float)Math.Sqrt((x - 31.5) * (x - 31.5) + (y - 31.5) * (y - 31.5));
                        if (px[((y * s * FrontFxTiming.BurstFrames) + f * s + x) * 4 + 3] > 0 && (d < 12) == inner) n++;
                    }
                return n;
            }
            check(Ink(a, 0, true) > Ink(a, 0, false) && Ink(a, 9, false) > Ink(a, 9, true) && Ink(a, 11, true) == 0, "fx art: the burst starts as a flash in the middle, grows into a ring and sparks and is empty in the middle at the end");
            var core = a[(32 * FrontFxArt.ImpactSize * FrontFxTiming.BurstFrames + 32) * 4];
            check(core > 200, "fx art: the flash's core is the hot colour of the element");
            var heal = FrontFxArt.ImpactStrip(FrontFx.Palette(FxElement.Heal), true);
            int up = 0, down = 0;
            for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++) if (heal[((y * 64 * 12) + 8 * 64 + x) * 4 + 3] > 0) { if (y > 32) up++; else down++; }
            check(up > down, "fx art: heal sparks rise (rows go up)");

            var c = FrontFxArt.CometStrip(fire);
            check(c.Length == FrontFxArt.CometSize * FrontFxArt.CometSize * FrontFxArt.CometFrames * 4 && Opaque(c) > 400, "fx art: the comet strip");
            int left = 0, right = 0;
            for (int y = 0; y < 32; y++) for (int x = 0; x < 32; x++) if (c[(y * 128 + x) * 4 + 3] > 0) { if (x < 16) left++; else right++; }
            check(left > 0 && right > 0, "fx art: the comet has a head and a tail");

            int w, h;
            var n = FrontFxArt.NumberPixels("123", 1f, 0.9f, 0.2f, 0.1f, 0f, 0f, out w, out h);
            check(w == PixelText.Width("123", 1) + 4 && h == PixelText.Height(1) + 4 && n.Length == w * h * 4, "fx art: number picture size is the text plus a margin");
            int fill = 0, edge = 0;
            for (int i = 0; i < n.Length; i += 4) if (n[i + 3] > 0) { if (n[i] > 200) fill++; else edge++; }
            check(fill > 20 && edge > fill / 2, "fx art: number picture has a fill and an outline: " + fill + " / " + edge);
            check(Opaque(FrontFxArt.NumberPixels("", 1, 1, 1, 0, 0, 0, out w, out h)) == 0, "fx art: empty text is empty");
        }
    }
}
