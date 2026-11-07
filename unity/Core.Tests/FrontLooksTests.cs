// Checks of the front-art creatures (Core/FrontLooks.cs, Core/FrontLiveAnim.cs): the name rules over every monster name of the server, the
// class mapping of the 21 vocations, which look any creature gets, the outfit composer, the name and health label, and the state machine
// (idle, walk progress, facing, attack timing, flinch on a health drop).
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class FrontLooksTests
    {
        static bool Near(float a, float b, float eps = 1e-3f) => Math.Abs(a - b) <= eps;

        static Creature Mk(uint id, byte type, string name, int x, int y, int hp = 100, int look = 100, Dir d = Dir.South) =>
            new Creature { Id = id, Type = type, Name = name, Position = new Pos(x, y, 7), HealthPercent = hp, Direction = d, Outfit = new Outfit(look, 1, 2, 3, 4) };

        static string FindRoot()
        {
            foreach (var start in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
                for (var d = new DirectoryInfo(start); d != null; d = d.Parent)
                    if (Directory.Exists(Path.Combine(d.FullName, "server", "data", "monster")) && File.Exists(Path.Combine(d.FullName, "ROADMAP.md"))) return d.FullName;
            return null;
        }

        static string PackOf(string name)
        {
            var l = FrontLooks.ForMonster(name);
            return l == null ? null : l.Folder;
        }

        public static void Run(Action<bool, string> check)
        {
            // ---- the pack and hero tables
            check(FrontLooks.PackFolders.Length == 14 && FrontLooks.PackFolders.Distinct().Count() == 14, "front looks: 14 pack folders");
            check(FrontLooks.HeroFolders.SequenceEqual(new[] { "knight", "mage", "skeleton", "ghoul" }), "front looks: the four committed picture sets");

            // ---- named monsters
            check(PackOf("Risen Skeleton") == "pk_armored_skeleton" && FrontLooks.ForMonster("Risen Skeleton").Alt == "skeleton", "front monster: a skeleton is the armoured skeleton, the skeleton pictures without the art");
            check(PackOf("Hollow Wraith") == "pk_ghost_knight" && PackOf("Phantom Shade") == "pk_ghost_knight", "front monster: ghosts are the ghost knight");
            check(PackOf("Malvorn the Hollow King") == "pk_ghost_king" && PackOf("Varkhul the Ashen Sovereign") == "pk_ghost_king" && PackOf("Nailcrown Regent") == "pk_ghost_king", "front monster: crowned undead are the ghost king");
            check(PackOf("Count Varethil") == "pk_vampire" && PackOf("Bloodmoon Thrall") == "pk_vampire", "front monster: counts and vampires are the vampire");
            check(PackOf("Forest Wolf") == "pk_werewolf" && PackOf("Blight Hound") == "pk_werewolf" && PackOf("Reapmoon Lycan") == "pk_werewolf" && PackOf("Dire Bear") == "pk_werewolf", "front monster: wolves, hounds, lycans and bears are the werewolf");
            check(PackOf("Hex Cultist") == "pk_cultist_dark" && PackOf("Cinder Acolyte") == "pk_cultist_red" && PackOf("Dark Sorcerer") == "pk_cultist_dark", "front monster: cultists, red for fire and blood, dark for the rest");
            check(PackOf("Ice Lich") == "pk_cultist_dark" && PackOf("Elite Ice Witch") == "pk_cultist_dark", "front monster: casters win over the ice family");
            check(PackOf("Goblin Archer") == "pk_goblin_shaman" && PackOf("Goblin Wolf Rider") == "pk_goblin_shaman" && PackOf("Hobgoblin Captain") == "pk_goblin_shaman", "front monster: every goblin is the goblin shaman");
            check(PackOf("Gnawbone Swarm") == "pk_goblin_shaman" || PackOf("Gnawbone Swarm") == "pk_rat_king" || PackOf("Gnawbone Swarm") == "pk_armored_skeleton", "front monster: a swarm of gnawing bone has a figure");
            check(PackOf("Hoarder Squirrel") == "pk_rat_king" && PackOf("Ashen Hare") == "pk_rat_king", "front monster: rats and small gnawers are the rat king");
            check(PackOf("Mirecoil Wyrm") == "pk_lizard_mystic" && PackOf("Elite Tidecrest Serpent") == "pk_lizard_mystic" && PackOf("Giant Thornback Toad") == "pk_lizard_mystic", "front monster: wyrms, serpents and toads are the lizard mystic");
            check(PackOf("Ice Dragon") == "pk_frost_demon" && PackOf("Frost Whelp") == "pk_frost_demon" && PackOf("Rime Penguin") == "pk_frost_demon" && PackOf("Elite Yeti") == "pk_frost_demon", "front monster: the ice family is the frost demon");
            check(PackOf("Ember Whelp") == "pk_fire_demon" && PackOf("Cinderhorn Juggernaut") == "pk_fire_demon" && PackOf("Ironbound Troll") == "pk_fire_demon", "front monster: fire and brutes are the fire demon");
            check(PackOf("Dusk Moth") == "pk_winged_demon" && PackOf("Gallows Raven") == "pk_winged_demon" && PackOf("Ember Parrot") == "pk_winged_demon", "front monster: flyers are the winged demon");
            check(PackOf("Hollow Rider") == "pk_headless", "front monster: riders are the headless");
            check(FrontLooks.ForMonster("Sepulchre Ghoul").Folder == "ghoul" && FrontLooks.ForMonster("Sepulchre Ghoul").Kind == FlKind.Hero, "front monster: ghouls are the ghoul pictures");
            check(FrontLooks.ForMonster("") == null && FrontLooks.ForMonster(null) == null && FrontLooks.ForMonster("Zxqv") == null, "front monster: no name or no rule is no pack figure (the outfit is drawn)");
            check(FrontLooks.ForMonster("Mercenary") == null && FrontLooks.ForMonster("Royal Man") == null, "front monster: humans are drawn as their outfit");
            check(FrontLooks.ForMonster("Risen Skeleton").Units == FrontLooks.SmallPackUnits && FrontLooks.ForMonster("Hex Cultist").Units == FrontLooks.PackUnits, "front monster: the 32-texel skeleton is small, the others 1.6 units");

            // ---- every monster name of the server
            string root = FindRoot();
            if (root != null)
            {
                var names = new List<string>();
                foreach (var f in Directory.GetFiles(Path.Combine(root, "server", "data", "monster", "monsters"), "*.xml", SearchOption.AllDirectories))
                {
                    var nm = Regex.Match(File.ReadAllText(f), "<monster\\s[^>]*name=\"([^\"]+)\"");
                    if (nm.Success) names.Add(nm.Groups[1].Value);
                }
                int xmlCount = names.Count;
                string csv = Path.Combine(root, "server", "data", "monster", "base_monster_names.csv");
                if (File.Exists(csv))
                    foreach (var line in File.ReadAllLines(csv).Skip(1))
                    {
                        var p = line.Split(',');
                        if (p.Length >= 3 && p[2] == "monster") names.Add(p[1]);
                    }
                check(xmlCount >= 250, "front monsters: the monster XML files were found (" + xmlCount + ")");
                var looks = names.Select(n => (n, l: FrontLooks.ForMonster(n))).ToList();
                bool valid = looks.All(x => x.l == null
                    || (x.l.Kind == FlKind.Pack && x.l.Folder.StartsWith("pk_", StringComparison.Ordinal) && FrontLooks.PackFolders.Contains(x.l.Folder.Substring(3)) && x.l.Units > 0f)
                    || (x.l.Kind == FlKind.Hero && FrontLooks.HeroFolders.Contains(x.l.Folder)));
                check(valid, "front monsters: every name gives nothing, a known pack folder or a committed set");
                check(looks.Select(x => x.l == null ? "-" : x.l.Folder).Distinct().Count(s => s != "-") >= 14, "front monsters: all 14 pack folders and the ghoul are used over the server's names");
                var mapped = looks.Count(x => x.l != null);
                Console.WriteLine("front looks (" + names.Count + " monster names: " + xmlCount + " custom, " + (names.Count - xmlCount) + " base): " + mapped + " get a figure, " + (names.Count - mapped) + " are drawn as their outfit");
                foreach (var g in looks.GroupBy(x => x.l == null ? "outfit" : x.l.Folder).OrderByDescending(g => g.Count()))
                    Console.WriteLine("  " + g.Key.PadRight(22) + g.Count().ToString().PadLeft(4) + "  " + (100.0 * g.Count() / names.Count).ToString("0.0").PadLeft(5) + " %");
                check(mapped * 100 >= names.Count * 50, "front monsters: at least 50% of the names have a figure (" + mapped + " of " + names.Count + ")");
                // the keywords the rules promise
                var promised = new (string word, string[] folders)[]
                {
                    ("skelet", new[] { "pk_armored_skeleton" }), ("wraith", new[] { "pk_ghost_knight", "pk_ghost_king", "pk_winged_demon", "pk_cultist_dark", "pk_cultist_red" }),
                    ("vampire", new[] { "pk_vampire" }), ("goblin", new[] { "pk_goblin_shaman" }), ("cultist", new[] { "pk_cultist_dark", "pk_cultist_red" }),
                    ("wolf", new[] { "pk_werewolf", "pk_goblin_shaman" }), ("demon", new[] { "pk_fire_demon", "pk_frost_demon", "pk_winged_demon" }),
                    ("lich", new[] { "pk_cultist_dark", "pk_cultist_red" }), ("ghoul", new[] { "ghoul" }),
                };
                foreach (var pr in promised)
                {
                    var hit = looks.Where(x => x.n.ToLowerInvariant().Contains(pr.word)).ToList();
                    check(hit.All(x => x.l != null && pr.folders.Contains(x.l.Folder)), "front monsters: the names with '" + pr.word + "' get " + string.Join(" or ", pr.folders) + (hit.Count > 0 ? " (" + hit.Count + ", e.g. " + hit[0].n + ")" : " (none in the list)"));
                }
                var stray = looks.Where(x => x.l == null).Select(x => x.n).Take(Environment.GetEnvironmentVariable("CHAOS_FL_ALL") != null ? 1000 : 40).ToList();
                Console.WriteLine("  drawn as their outfit, first 40: " + string.Join(", ", stray));
            }

            // ---- the 21 classes
            check(Hd2dChars.Classes.All(c => FrontLooks.ForClass(c.Id) != null), "front class: every one of the 21 vocations has a look");
            var cl = Hd2dChars.Classes.Select(c => FrontLooks.ForClass(c.Id)).ToList();
            check(cl.All(l => l.Kind == FlKind.Outfit ? l.Folder == "" : FrontLooks.HeroFolders.Contains(l.Folder) && l.Units == FrontLooks.HeroUnits), "front class: a class is a committed hero set or its outfit");
            foreach (int id in new[] { 4, 8, 14, 13, 17, 18, 23, 24, 25 }) check(FrontLooks.ForClass(id).Folder == "knight", "front class: the melee and holy classes are the knight (" + id + ")");
            foreach (int id in new[] { 1, 5, 10, 20, 19 }) check(FrontLooks.ForClass(id).Folder == "mage", "front class: the casters are the mage (" + id + ")");
            foreach (int id in new[] { 21, 22 }) check(FrontLooks.ForClass(id).Folder == "skeleton", "front class: the Lich and the Bone Lord are the skeleton (" + id + ")");
            foreach (int id in new[] { 3, 7, 15, 11, 12 }) check(FrontLooks.ForClass(id).Kind == FlKind.Outfit, "front class: the ranged and stealth classes have no picture yet and are their outfit (" + id + ")");
            check(cl.Count(l => l.Kind == FlKind.Hero) == 16, "front class: 16 of the 21 classes are a hero set");
            check(cl.All(l => l.R >= 0.75f && l.R <= 1.25f && l.G >= 0.75f && l.G <= 1.25f && l.B >= 0.75f && l.B <= 1.25f), "front class: tints stay within 0.75 to 1.25");
            check(FrontLooks.ForClass(14).R > FrontLooks.ForClass(14).B && FrontLooks.ForClass(18).B > FrontLooks.ForClass(18).R, "front class: a Berserker is red, a Shadowfist blue");
            check(FrontLooks.ForClass(99) == null && FrontLooks.ForClass(0) == null, "front class: an unknown vocation has no look");
            check(Hd2dChars.Classes.Select(c => FrontLooks.ForClass(c.Id).Label).Distinct().Count() == 21, "front class: every class has its own label");
            check(FrontLooks.HeroOfModel("Rogue") == "" && FrontLooks.HeroOfModel("RogueHooded") == "" && FrontLooks.HeroOfModel("Knight") == "knight" && FrontLooks.HeroOfModel(null) == "", "front class: the model to hero set table");

            // ---- which look any creature gets
            var local = Mk(1, 0, "Me", 10, 10);
            check(FrontLooks.For(local, true, 21).Folder == "skeleton" && FrontLooks.For(local, true, 1).Folder == "mage" && FrontLooks.For(local, true, 0).Label == "Warrior" && FrontLooks.For(local, true, 99).Label == "Warrior", "front look: the local player is its class, the Warrior when unknown");
            var other = Mk(2, 0, "Other", 11, 10, look: 130); other.Vocation = 12;
            check(FrontLooks.For(other, false, 4).Kind == FlKind.Outfit && FrontLooks.For(other, false, 4).Label == "Ninja", "front look: a player with a known vocation is that class");
            var picks = Enumerable.Range(1, 300).Select(l => FrontLooks.For(Mk(5, 0, "P", 1, 1, look: l), false, 0)).ToList();
            check(picks.All(l => l.Kind == FlKind.Hero && (l.Folder == "knight" || l.Folder == "mage")), "front look: another player of unknown class is the knight or the mage, never a skeleton or an outfit");
            check(picks.Select(l => l.Folder).Distinct().Count() == 2 && picks.Select(l => l.R + "," + l.G + "," + l.B).Distinct().Count() >= 5, "front look: both heroes and several tints appear among other players");
            check(FrontLooks.For(Mk(5, 0, "P", 1, 1, look: 130), false, 0).Folder == FrontLooks.For(Mk(77, 0, "Q", 1, 1, look: 130), false, 0).Folder, "front look: the same outfit look picks the same hero, whatever the id");
            check(FrontLooks.For(Mk(8, 2, "Guard Captain", 1, 1), false, 0).Kind == FlKind.Outfit && FrontLooks.For(Mk(8, 2, "Guard Captain", 1, 1), false, 0).Label == "npc", "front look: an NPC is its outfit");
            check(FrontLooks.For(Mk(9, 1, "Hex Cultist", 1, 1), false, 0).Folder == "pk_cultist_dark" && FrontLooks.For(Mk(9, 3, "Forest Wolf", 1, 1), false, 0).Folder == "pk_werewolf" && FrontLooks.For(Mk(9, 4, "Ice Dragon", 1, 1), false, 0).Folder == "pk_frost_demon", "front look: monsters and summons go by name");
            check(FrontLooks.For(Mk(9, 1, "Zxqv", 1, 1), false, 0).Kind == FlKind.Outfit && FrontLooks.For(Mk(9, 1, "Zxqv", 1, 1), false, 0).Monster, "front look: a monster with no rule is its outfit");
            check(FrontLooks.For(null, false, 0).Kind == FlKind.Outfit, "front look: null is safe");
            check(FrontLooks.KeyOf(Mk(1, 1, "A", 1, 1), false, 0) != FrontLooks.KeyOf(Mk(1, 1, "B", 1, 1), false, 0) && FrontLooks.KeyOf(Mk(1, 1, "A", 1, 1), false, 0) != FrontLooks.KeyOf(Mk(1, 1, "A", 1, 1, look: 5), false, 0), "front look: the look key changes with the name and the outfit");

            // ---- facing
            FrontLooks.Face(Dir.North, out float fx, out float fz); check(Near(fx, 0) && Near(fz, 1), "front facing: north is +z");
            FrontLooks.Face(Dir.East, out fx, out fz); check(Near(fx, 1) && Near(fz, 0), "front facing: east is +x");
            FrontLooks.Face(Dir.South, out fx, out fz); check(Near(fx, 0) && Near(fz, -1), "front facing: south is -z (looks at the camera)");
            FrontLooks.Face(Dir.NorthWest, out fx, out fz); check(Near(fx, -0.7071f) && Near(fz, 0.7071f), "front facing: north-west");
            check(FrontArtFacing.Index(0f, -1f, 0f) == 4 && FrontArtFacing.Index(1f, 0f, 0f) == 2, "front facing: a creature facing south shows the south picture, east the east one");
            foreach (Dir d in Enum.GetValues(typeof(Dir)))
            {
                FrontLooks.Face(d, out fx, out fz);
                check(FrontLooks.DirOf(fx, fz) == d, "front facing: heading round trip " + d);
            }
            check(FrontLooks.DirOf(0, 0) == Dir.South, "front facing: no heading is south");

            // ---- the state machine
            StateTests(check);
            OutfitTests(check);
            LabelTests(check);
        }

        // ---- state ------------------------------------------------------------------------------------------------------------

        static void StateTests(Action<bool, string> check)
        {
            // idle: stays on its tile
            var c = Mk(1, 1, "Rat", 10, 10);
            var st = new FrontCreatureState(1);
            st.Update(0.0, c, null);
            check(st.Clip == FcClip.Idle && !st.Walking && st.X == 10 && st.Y == 10 && Near(st.FaceX, 0) && Near(st.FaceZ, -1) && st.Flinch == 0, "front state: starts idle on its tile facing south");
            st.Update(5.0, c, null);
            check(st.Clip == FcClip.Idle && st.SwingU < 0, "front state: no foe, no swing, however long it stands");

            // a step: east, 300 ms
            c.WalkFrom = new Pos(10, 10, 7); c.Position = new Pos(11, 10, 7); c.Direction = Dir.East; c.WalkStart = 1000; c.WalkMs = 300;
            st.Update(6.0, c, null);
            check(st.Walking && st.Clip == FcClip.Walk && Near(st.X, 10f) && Near(st.WalkU, 0f) && Near(st.FaceX, 1) && Near(st.FaceZ, 0), "front state: a step starts at the tile it came from, facing the way it goes");
            st.Update(6.15, c, null);
            check(st.Walking && Near(st.WalkU, 0.5f) && Near(st.X, 10.5f) && Near(st.Y, 10f), "front state: half way through the step it is half a tile on");
            st.Update(6.29, c, null);
            check(st.Walking && st.X > 10.9f && st.X < 11f, "front state: nearly there");
            st.Update(6.31, c, null);
            check(!st.Walking && st.Clip == FcClip.Idle && st.X == 11 && st.WalkU == 0f, "front state: the step ends on the tile and goes idle");
            // chained steps run on: the next one starts where the picture is
            c.WalkFrom = new Pos(11, 10, 7); c.Position = new Pos(12, 10, 7); c.WalkStart = 1300; c.WalkMs = 300;
            st.Update(6.4, c, null);
            st.Update(6.69, c, null);   // nearly at the end of the east step
            c.WalkFrom = new Pos(12, 10, 7); c.Position = new Pos(12, 11, 7); c.Direction = Dir.South; c.WalkStart = 1600;
            st.Update(6.7, c, null);
            st.Update(6.85, c, null);   // half way through the south step
            check(st.Walking && Near(st.X, 12f, 0.05f) && Near(st.Y, 10.5f, 0.05f) && Near(st.FaceZ, -1), "front state: a south step follows an east one smoothly");
            // a diagonal step, speed from WalkMs
            c.WalkFrom = new Pos(12, 11, 7); c.Position = new Pos(13, 10, 7); c.Direction = Dir.NorthEast; c.WalkStart = 2000; c.WalkMs = 450;
            st.Update(6.7, c, null);
            check(st.Walking && Near(st.StepSeconds, 0.45f), "front state: the step takes the creature's step time");
            st.Update(7.2, c, null);
            // teleport (no step): snaps
            c.Position = new Pos(30, 30, 7); c.WalkStart = -1;
            st.Update(7.3, c, null);
            check(!st.Walking && st.X == 30 && st.Y == 30, "front state: a jump with no step snaps");
            // a step that begins far from the picture snaps to where the server says it began
            c.WalkFrom = new Pos(40, 40, 7); c.Position = new Pos(41, 40, 7); c.WalkStart = 5000; c.WalkMs = 200;
            st.Update(7.4, c, null);
            check(st.Walking && Near(st.X, 40f), "front state: a step from far away starts at its origin");

            // attack: a monster next to a player swings every 2 s, facing it
            var mon = Mk(10, 1, "Wolf", 20, 20); var hero = Mk(11, 0, "Hero", 21, 20);
            var all = new List<Creature> { mon, hero };
            var foe = FrontTargets.Foe(all, mon, 0);
            check(foe == hero && FrontTargets.Foe(all, hero, 0) == mon, "front targets: a monster and a player next to each other are foes");
            var far = Mk(12, 0, "Far", 25, 20);
            check(FrontTargets.Foe(new[] { mon, far }, mon, 0) == null, "front targets: a player far away is no foe");
            check(FrontTargets.Foe(new[] { mon, Mk(13, 2, "Npc", 21, 20) }, mon, 0) == null && FrontTargets.Foe(new[] { mon, Mk(14, 1, "Rat", 21, 21) }, mon, 0) == null, "front targets: an NPC or another monster is no foe");
            var wolf = Mk(15, 3, "Own wolf", 19, 19);
            check(FrontTargets.Foe(new[] { mon, wolf }, mon, 0) == wolf && FrontTargets.Foe(new[] { mon, wolf }, wolf, 0) == mon, "front targets: a monster and a summon next to each other are foes");
            var ps = Mk(16, 0, "P", 21, 21);
            check(FrontTargets.Foe(new[] { mon, hero, ps }, mon, 0) == hero && FrontTargets.Foe(new[] { mon, hero, ps }, mon, 16) == ps, "front targets: the straight neighbour before the diagonal one, the picked target first");
            check(FrontTargets.Foe(new[] { mon, Mk(17, 0, "Up", 21, 20) }, mon, 0) != null && !FrontCreatureState.Adjacent(new Pos(1, 1, 7), new Pos(1, 1, 7)) && !FrontCreatureState.Adjacent(new Pos(1, 1, 7), new Pos(1, 1, 8)) && FrontCreatureState.Adjacent(new Pos(1, 1, 7), new Pos(2, 2, 7)), "front targets: adjacent means one tile on the same floor");

            var ms = new FrontCreatureState(10);
            double t;
            var swings = new List<double>();
            bool prev = false;
            var lengths = new List<double>();
            double swingAt = 0; int blowFrames = 0, swingFrames = 0; bool facedFoe = true;
            for (int i = 0; i <= 1000; i++)
            {
                t = 100.0 + i * 0.01;
                ms.Update(t, mon, foe);
                bool sw = ms.Clip == FcClip.Attack;
                if (sw && !prev) { swings.Add(t); swingAt = t; }
                if (!sw && prev) lengths.Add(t - swingAt);
                if (sw) { swingFrames++; if (ms.Blow) blowFrames++; if (!(Near(ms.FaceX, 1f) && Near(ms.FaceZ, 0f))) facedFoe = false; }
                prev = sw;
            }
            check(swings.Count >= 4 && swings.Count <= 6, "front attack: about one swing every 2 s over 10 s (" + swings.Count + ")");
            check(swings.Zip(swings.Skip(1), (a, b) => b - a).All(d => Near((float)d, FrontCreatureState.AttackEvery, 0.03f)), "front attack: swings are 2 s apart");
            check(lengths.All(l => Near((float)l, FrontCreatureState.Swing, 0.03f)), "front attack: a swing lasts 0.75 s");
            check(facedFoe, "front attack: it faces its foe while swinging");
            check(blowFrames > 0 && blowFrames < swingFrames && Near(blowFrames / (float)swingFrames, 1f - 0.4f / 0.75f, 0.06f), "front attack: the blow lands 0.4 s into the swing");
            // out of reach or no foe: stops
            var ms2 = new FrontCreatureState(10);
            for (int i = 0; i < 500; i++) ms2.Update(200.0 + i * 0.01, mon, null);
            check(ms2.Clip == FcClip.Idle, "front attack: no foe, no swing");
            var m3 = Mk(30, 1, "Wolf", 19, 20);
            var ms3 = new FrontCreatureState(30);
            int walkSwing = 0;
            ms3.Update(299.0, m3, hero);
            m3.WalkFrom = new Pos(19, 20, 7); m3.Position = new Pos(20, 20, 7); m3.WalkStart = 1; m3.WalkMs = 10000;
            for (int i = 0; i < 400; i++) { ms3.Update(300.0 + i * 0.01, m3, hero); if (ms3.Clip == FcClip.Attack) walkSwing++; }
            check(walkSwing == 0, "front attack: a creature in the middle of a step does not swing");
            // Strike
            var ms4 = new FrontCreatureState(31); var m4 = Mk(31, 0, "P", 5, 5);
            ms4.Update(1.0, m4, null); ms4.Strike(1.1); ms4.Update(1.2, m4, null);
            check(ms4.Clip == FcClip.Attack && ms4.SwingU > 0f && ms4.SwingU < 0.3f, "front attack: Strike forces a swing");
            ms4.Update(2.0, m4, null);
            check(ms4.Clip == FcClip.Idle, "front attack: the forced swing ends");
            // swing offset leans toward the foe
            var ms5 = new FrontCreatureState(10);
            double leanMax = 0;
            for (int i = 0; i <= 400; i++) { ms5.Update(400.0 + i * 0.01, mon, foe); leanMax = Math.Max(leanMax, ms5.OffX); }
            check(leanMax > 0.05 && leanMax <= FrontCreatureState.Lean + 1e-3, "front attack: it leans into the swing toward the foe (" + leanMax.ToString("0.000") + ")");

            // flinch: health drops
            var v = Mk(40, 1, "Wolf", 50, 50, hp: 100); var f2 = Mk(41, 0, "Hero", 49, 50);
            var vs = new FrontCreatureState(40);
            vs.Update(10.0, v, f2);
            check(vs.Flinch == 0f && vs.OffX == 0f, "front flinch: none while health holds");
            v.HealthPercent = 80;
            vs.Update(10.01, v, f2);
            double peak = 0; float pushedX = 0;
            for (int i = 1; i <= 40; i++) { vs.Update(10.01 + i * 0.01, v, f2); if (vs.Flinch > peak) { peak = vs.Flinch; pushedX = vs.PushX; } }
            check(peak > 0.95 && peak <= 1.0 + 1e-4, "front flinch: a health drop flinches to the peak (" + peak.ToString("0.00") + ")");
            check(pushedX > 0.1f && pushedX <= FrontCreatureState.Knock + 1e-3f, "front flinch: pushed away from the foe (east, 0.16 tile at most)");
            vs.Update(10.5, v, f2);
            check(vs.Flinch == 0f && vs.PushX == 0f, "front flinch: over after 0.3 s");
            v.HealthPercent = 90;   // healing: no flinch
            vs.Update(11.0, v, f2);
            check(vs.Flinch == 0f, "front flinch: healing does not flinch");
            v.HealthPercent = 40;
            vs.Update(12.0, v, null);
            vs.Update(12.15, v, null);
            check(vs.Flinch > 0.9f && vs.PushZ > 0.1f, "front flinch: with no foe known the push is backwards (it faces south, so north)");
            check(Near(vs.OffZ, vs.PushZ), "front flinch: the push is the picture's offset");

            // a dead creature: health 0 does not swing
            var dead = Mk(50, 1, "Wolf", 20, 20, hp: 0); var ds = new FrontCreatureState(50);
            for (int i = 0; i < 300; i++) ds.Update(500.0 + i * 0.01, dead, hero);
            check(ds.Clip == FcClip.Idle, "front attack: a creature at 0 health does not swing");

            // frames
            check(FrontFrames.Index(FcClip.Idle, 1, 5.0, 0f, 0f, 0) == 0 && FrontFrames.Index(FcClip.Idle, 0, 5.0, 0f, 0f, 0) == 0, "front frames: one frame is frame 0");
            check(FrontFrames.Index(FcClip.Attack, 9, 5.0, 0f, 0f, 0) == 0 && FrontFrames.Index(FcClip.Attack, 9, 5.0, 0.5f, 0f, 0) == 4 && FrontFrames.Index(FcClip.Attack, 9, 5.0, 0.999f, 0f, 0) == 8 && FrontFrames.Index(FcClip.Attack, 9, 5.0, 1.5f, 0f, 0) == 8, "front frames: an attack plays through once");
            check(FrontFrames.Index(FcClip.Idle, 6, 0.0, 0f, 0f, 0) == 0 && FrontFrames.Index(FcClip.Idle, 6, 0.125, 0f, 0f, 0) == 1 && FrontFrames.Index(FcClip.Idle, 6, 1.0, 0f, 0f, 0) == 2 && FrontFrames.Index(FcClip.Idle, 6, 0.0, 0f, 0f, 3) == 3, "front frames: idle loops at 8 a second, shifted by the phase");
            check(FrontFrames.Index(FcClip.Walk, 8, 0.1, 0f, 0.5f, 0) == 1 && FrontFrames.Index(FcClip.Walk, 16, 0.5, 0f, 0.2f, 0) == 8, "front frames: walking is 10 a second, running 16");
            check(Enumerable.Range(0, 200).All(i => { int f = FrontFrames.Index(FcClip.Walk, 5, i * 0.07, 0f, 0.4f, -3); return f >= 0 && f < 5; }), "front frames: a negative phase stays in range");
        }

        // ---- outfit art -------------------------------------------------------------------------------------------------------

        static ThingType MakeOutfit(int w, int h, int patternX, int phases, bool mask, int addons, uint first = 1000)
        {
            var g = new FrameGroup { Type = 0, Width = w, Height = h, Layers = mask ? 2 : 1, PatternX = patternX, PatternY = addons, PatternZ = 1, Phases = phases };
            int n = w * h * g.Layers * patternX * addons * phases;
            g.Sprites = new uint[n];
            for (int i = 0; i < n; i++) g.Sprites[i] = first + (uint)i;
            return new ThingType { Category = ThingCategory.Outfit, Id = 7, Groups = new[] { g } };
        }

        static byte[] Solid(uint id, byte r, byte g, byte b, byte a = 255)
        {
            var px = new byte[32 * 32 * 4];
            for (int i = 0; i < px.Length; i += 4) { px[i] = r; px[i + 1] = g; px[i + 2] = b; px[i + 3] = a; }
            return px;
        }

        static void OutfitTests(Action<bool, string> check)
        {
            var t = MakeOutfit(2, 2, 4, 3, false, 1);
            var g = t.Idle;
            // each cell a flat colour by its id so the canvas layout shows
            Func<uint, byte[]> raw = id => Solid(id, (byte)(id % 251), (byte)(id / 7 % 251), 9);
            var px = FrontOutfit.Compose(t, new Outfit(1, 0, 0, 0, 0), Dir.South, false, 0f, raw, out int w, out int h);
            check(px != null && w == 2 && h == 2 && px.Length == 64 * 64 * 4, "front outfit: a 2 x 2 outfit composes a 64 x 64 picture");
            uint id00 = g.Sprite(0, 0, 0, FrontOutfit.PatternDir(Dir.South, 4), 0, 0, 0), id10 = g.Sprite(1, 0, 0, 2, 0, 0, 0), id01 = g.Sprite(0, 1, 0, 2, 0, 0, 0);
            // cell (0, 0) is the bottom right one, (1, 0) the bottom left one, (0, 1) the top right one
            Func<int, int, int> red = (x, y) => px[(y * 64 + x) * 4];
            check(red(48, 48) == (byte)(id00 % 251) && red(16, 48) == (byte)(id10 % 251) && red(48, 16) == (byte)(id01 % 251), "front outfit: cell (0, 0) is the bottom right, the art extends west and up");
            check(FrontOutfit.PatternDir(Dir.North, 4) == 0 && FrontOutfit.PatternDir(Dir.East, 4) == 1 && FrontOutfit.PatternDir(Dir.South, 4) == 2 && FrontOutfit.PatternDir(Dir.West, 4) == 3
                  && FrontOutfit.PatternDir(Dir.NorthEast, 4) == 1 && FrontOutfit.PatternDir(Dir.SouthEast, 4) == 1 && FrontOutfit.PatternDir(Dir.SouthWest, 4) == 3 && FrontOutfit.PatternDir(Dir.NorthWest, 4) == 3
                  && FrontOutfit.PatternDir(Dir.NorthWest, 8) == 7, "front outfit: four directions, the diagonals take east or west, eight when the dat has eight");
            var east = FrontOutfit.Compose(t, new Outfit(1, 0, 0, 0, 0), Dir.East, false, 0f, raw, out w, out h);
            check(!east.SequenceEqual(px), "front outfit: another direction is another picture");
            // walking: phases from 1
            var tw = MakeOutfit(1, 1, 4, 4, false, 1);
            int phase;
            FrontOutfit.Group(tw, false, 0.5f, out phase); check(phase == 0, "front outfit: idle is phase 0");
            FrontOutfit.Group(tw, true, 0f, out phase); check(phase == 1, "front outfit: a walk starts at phase 1");
            FrontOutfit.Group(tw, true, 0.5f, out phase); check(phase == 2, "front outfit: half way through the step is phase 2 of 3");
            FrontOutfit.Group(tw, true, 1f, out phase); check(phase == 3, "front outfit: the end of the step is the last phase");
            FrontOutfit.Group(MakeOutfit(1, 1, 4, 1, false, 1), true, 0.5f, out phase); check(phase == 0, "front outfit: one phase only is phase 0");
            // colour mask
            var tm = MakeOutfit(1, 1, 4, 1, true, 1);
            var tg = tm.Idle;
            uint baseId = tg.Sprite(0, 0, 0, 2, 0, 0, 0), maskId = tg.Sprite(0, 0, 1, 2, 0, 0, 0);
            Func<uint, byte[]> rawm = id => id == baseId ? Solid(id, 200, 200, 200) : id == maskId ? Solid(id, 255, 0, 0) : Solid(id, 1, 1, 1);
            var o1 = new Outfit(1, 0, 94, 0, 0); var o2 = new Outfit(1, 0, 78, 0, 0);
            var c1 = FrontOutfit.Compose(tm, o1, Dir.South, false, 0f, rawm, out w, out h); var c2 = FrontOutfit.Compose(tm, o2, Dir.South, false, 0f, rawm, out w, out h);
            check(c1 != null && !c1.SequenceEqual(c2) && c1[3] == 255, "front outfit: the body colour of the outfit tints the red mask area");
            check(FrontOutfit.Key(tm, o1, 2, 0) != FrontOutfit.Key(tm, o2, 2, 0) && FrontOutfit.Key(tm, o1, 2, 0) == FrontOutfit.Key(tm, new Outfit(1, 0, 94, 0, 0), 2, 0) && FrontOutfit.Key(tm, o1, 2, 0) != FrontOutfit.Key(tm, o1, 1, 0) && FrontOutfit.Key(tm, o1, 2, 0) != FrontOutfit.Key(tm, o1, 2, 1), "front outfit: the key follows colours, direction and phase");
            // addons
            var ta = MakeOutfit(1, 1, 4, 1, false, 3, 2000);
            Func<uint, byte[]> rawa = id => Solid(id, 10, 20, 30, id == ta.Idle.Sprite(0, 0, 0, 2, 1, 0, 0) ? (byte)255 : (byte)0);
            check(FrontOutfit.Compose(ta, new Outfit(1, 0, 0, 0, 0, 0), Dir.South, false, 0f, rawa, out w, out h) == null, "front outfit: addon art is left out when the outfit has no addon");
            check(FrontOutfit.Compose(ta, new Outfit(1, 0, 0, 0, 0, 1), Dir.South, false, 0f, rawa, out w, out h) != null, "front outfit: the first addon is drawn when the outfit has it");
            check(FrontOutfit.Compose(null, new Outfit(), Dir.South, false, 0f, raw, out w, out h) == null && FrontOutfit.Compose(t, new Outfit(), Dir.South, false, 0f, id => null, out w, out h) == null, "front outfit: no type or no sprites is no picture");
            // alpha over: a half clear top layer over a base
            var tl = MakeOutfit(1, 1, 4, 1, false, 2, 3000);
            var topId = tl.Idle.Sprite(0, 0, 0, 2, 1, 0, 0);
            var l2 = FrontOutfit.Compose(tl, new Outfit(1, 0, 0, 0, 0, 1), Dir.South, false, 0f, id => id == topId ? Solid(id, 255, 255, 255, 128) : Solid(id, 0, 0, 0), out w, out h);
            check(l2 != null && l2[0] > 100 && l2[0] < 160 && l2[3] == 255, "front outfit: a half clear layer blends over the one below");
            // item look
            var item = new ThingType { Category = ThingCategory.Item, Id = 1500, Groups = new[] { new FrameGroup { Width = 1, Height = 2, Layers = 1, PatternX = 1, PatternY = 1, PatternZ = 1, Phases = 1, Sprites = new uint[] { 5000, 5001 } } } };
            var ip = FrontOutfit.Compose(item, new Outfit { LookTypeEx = 1500 }, Dir.North, true, 0.5f, id => Solid(id, 80, 90, 100), out w, out h);
            check(ip != null && w == 1 && h == 2, "front outfit: an item shown as a creature is composed too");
            // type lookup
            var dat = new DatFile { Outfits = new ThingType[8], Items = new ThingType[1600] };
            dat.Outfits[7] = t; dat.Items[1500] = item;
            check(FrontOutfit.TypeOf(dat, new Outfit(7, 0, 0, 0, 0)) == t && FrontOutfit.TypeOf(dat, new Outfit { LookTypeEx = 1500 }) == item && FrontOutfit.TypeOf(dat, new Outfit(3, 0, 0, 0, 0)) == null && FrontOutfit.TypeOf(null, new Outfit()) == null, "front outfit: the type of an outfit or an item look");
        }

        // ---- label ------------------------------------------------------------------------------------------------------------

        static void LabelTests(Action<bool, string> check)
        {
            var px = FrontLabel.Pixels("Risen Mage", 100, true, out int w, out int h);
            FrontLabel.Size("Risen Mage", true, out int w2, out int h2);
            check(px.Length == w * h * 4 && w == w2 && h == h2 && h == 15 && w >= 28, "front label: name and bar fill a " + w + " x " + h + " picture");
            int opaque = 0, green = 0;
            for (int i = 0; i < px.Length; i += 4) { if (px[i + 3] > 0) opaque++; if (px[i + 3] == 255 && px[i + 1] > px[i] + 60 && px[i + 1] > px[i + 2] + 60) green++; }
            check(opaque > 100 && green >= 26 * 3 - 10, "front label: full health is a full green bar (" + green + " green texels)");
            // rows are bottom first: the bar is at the bottom, the name at the top
            int bottomOpaque = 0, topOpaque = 0;
            for (int x = 0; x < w; x++) { if (px[(0 * w + x) * 4 + 3] > 0) bottomOpaque++; if (px[((h - 1) * w + x) * 4 + 3] > 0) topOpaque++; }
            check(bottomOpaque >= 26 && topOpaque > 0 && topOpaque < w, "front label: the bar is under the name (rows bottom first)");
            var low = FrontLabel.Pixels("Risen Mage", 20, true, out int lw, out int lh);
            int fillLow = 0, fillFull = 0;
            Func<byte[], int, int, int> redTexels = (a, ww, hh) => { int n = 0; for (int i = 0; i < a.Length; i += 4) if (a[i + 3] == 255 && a[i] > 180 && a[i + 1] < 160 && a[i + 2] < 90) n++; return n; };
            fillLow = redTexels(low, lw, lh); fillFull = redTexels(px, w, h);
            check(fillLow >= 8 && fillFull == 0, "front label: 20% health is a short orange or red bar (" + fillLow + " texels)");
            byte r, g, b;
            FrontLabel.HealthColor(100, out r, out g, out b); check(g > r && g > b, "front label: full is green");
            FrontLabel.HealthColor(50, out r, out g, out b); check(r > 200 && g > 200 && b < 100, "front label: half is yellow");
            FrontLabel.HealthColor(20, out r, out g, out b); check(r > 200 && g > 100 && g < 160, "front label: low is orange");
            FrontLabel.HealthColor(3, out r, out g, out b); check(r > 200 && g < 80, "front label: nearly dead is red");
            var nb = FrontLabel.Pixels("Guard", 100, false, out int nw, out int nh);
            check(nh == 9 && nb.Length == nw * nh * 4, "front label: a name alone is 9 texels high");
            var bo = FrontLabel.Pixels("", 100, true, out int bw, out int bh);
            check(bh == 5 && bo.Length == bw * bh * 4, "front label: a bar alone is 5 texels high");
            var no = FrontLabel.Pixels("", 100, false, out int ow, out int oh);
            check(ow == 1 && oh == 1 && no.Length == 4 && no[3] == 0, "front label: nothing to draw is one clear texel");
            check(FrontLabel.Shorten("A very very long creature name indeed").Length == FrontLabel.MaxChars && FrontLabel.Shorten("  Rat ") == "Rat" && FrontLabel.Shorten(null) == "", "front label: names are trimmed and cut at 20");
            var zero = FrontLabel.Pixels("X", 0, true, out int zw, out int zh);
            var one = FrontLabel.Pixels("X", 1, true, out zw, out zh);
            Func<byte[], int> darkFill = a => { int n = 0; for (int i = 0; i < a.Length; i += 4) if (a[i + 3] == 255 && a[i] > 150) n++; return n; };
            check(darkFill(one) > darkFill(zero), "front label: 1% still shows a texel of bar, 0% none");
        }
    }
}
