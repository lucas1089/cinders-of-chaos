// Phase 30 (2026-11-09): the tester bot checks on the Unity core (O433, unity/README.md "Tester checks on the Unity core (phase 30)"). The rules of server/tools/tester_checks.py as Core
// functions (Core/TesterChecks.cs) on synthetic helper answers, the coverage table against the real tester_checks.py, and the scenario list of the live check.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class Phase30Tests
    {
        static Dictionary<string, object> J(string json) => (Dictionary<string, object>)Json.Parse(json);

        public static void Run(Action<bool, string> check)
        {
            Lines(check);
            Summons(check);
            PartyRules(check);
            WaystoneRules(check);
            RiftRules(check);
            ProbeRules(check);
            ChestRules(check);
            SpellRules(check);
            Coverage(check);
        }

        static void Lines(Action<bool, string> check)
        {
            check(TesterChecks.TryParseLine("[tester-helper] summons {\"count\":2,\"summons\":[]}", out string k, out var d) && k == "summons" && TesterChecks.Int(d, "count") == 2, "tester line: kind and json are read");
            check(!TesterChecks.TryParseLine("[tester-helper] town not json", out _, out _) && !TesterChecks.TryParseLine("You see a rat.", out _, out _) && !TesterChecks.TryParseLine("[tester-helper]", out _, out _) && !TesterChecks.TryParseLine(null, out _, out _), "tester line: other text and broken json are no answer");
            check(TesterChecks.TryParseLine("[tester-helper] error {\"err\":\"unknown command\",\"param\":\"x\"}", out k, out d) && k == "error" && TesterChecks.Err(d) == "unknown command", "tester line: the helper's error line carries err");
            check(TesterChecks.Eligible("Tester Abc", 1) && !TesterChecks.Eligible("Tester Abc", 0) && !TesterChecks.Eligible("Tester ABc", 1) && !TesterChecks.Eligible("Tester Abcd", 1) && !TesterChecks.Eligible("Player Abc", 1) && !TesterChecks.Eligible(null, 1), "tester name: the helper's rule (Tester + 3 letters, storage 1)");
            check(TesterChecks.Err(J("{\"err\":false}")).Length == 0 && TesterChecks.Err(J("{\"x\":1}")).Length == 0 && TesterChecks.Err(J("{\"err\":\"no waystone system\"}")) == "no waystone system", "tester answer: err false or missing is no error");
        }

        static void Summons(Action<bool, string> check)
        {
            check(TesterChecks.SnapshotProblems(J("{\"summons\":[{\"target\":\"monster\"},{\"target\":\"none\"}]}")).Count == 0 && TesterChecks.SnapshotProblems(null).Count == 0, "summons: monsters and nothing as target are fine");
            check(TesterChecks.SnapshotProblems(J("{\"summons\":[{\"name\":\"Wolf\",\"id\":7,\"target\":\"owner\"}]}"))[0].Contains("targets its owner"), "summons: a wolf at its owner is a problem");
            check(TesterChecks.SnapshotProblems(J("{\"summons\":[{\"target\":\"ally\"}]}"))[0].Contains("an ally (ally)") && TesterChecks.SnapshotProblems(J("{\"summons\":[{\"target\":\"summon\"}]}"))[0].Contains("an ally (summon)"), "summons: an ally or another summon as target");
            check(TesterChecks.SnapshotProblems(J("{\"summons\":[{\"listedAllies\":2}]}"))[0].Contains("engine target list") && TesterChecks.SnapshotProblems(J("{\"summons\":[],\"ownerTarget\":\"summon\"}"))[0].Contains("holds"), "summons: allies in the engine list, the owner holding a summon");
            check(TesterChecks.Summoners["Beastmaster"].Words == "vael ferh" && TesterChecks.Summoners["Necromancer"].Cap == 5 && TesterChecks.Summoners.Count == 4 && TesterChecks.Summoners["Lich"].Check == "necro_minions", "summons: the four summoner classes as in tester_checks.py");
            check(TesterChecks.PetRestText(J("{\"rest\":\"pz\"}")) == "rests: a protection zone" && TesterChecks.PetRestText(J("{\"deathLeft\":12}")) == "death cooldown 12 s" && TesterChecks.PetRestText(J("{\"summonLeft\":3,\"live\":false}")) == "call cooldown 3 s" && TesterChecks.PetRestText(new Dictionary<string, object>()) == "no answer to !tester pet" && TesterChecks.PetRestText(J("{\"x\":1}")) == "no rule of the game says why", "pets: the text of a pet that is not out");
        }

        static void PartyRules(Action<bool, string> check)
        {
            check(TesterChecks.BonusPercent(0) == 20 && TesterChecks.BonusPercent(1) == 20 && TesterChecks.BonusPercent(2) == 30 && TesterChecks.BonusPercent(3) == 60 && TesterChecks.BonusPercent(4) == 100 && TesterChecks.BonusPercent(5) == 150 && TesterChecks.BonusPercent(9) == 150, "party xp: the class line bonus (party_xp_core.lua bonusPercent)");
            check(TesterChecks.ShareExpected(2, 2) == 650 && TesterChecks.ShareExpected(1, 1) == 1200 && TesterChecks.ShareExpected(3, 2) == 800 && TesterChecks.ShareExpected(2, 3) == 434, "party xp: ceil(1000 x (100 + bonus) / 100 / members); the live run read 650 for 2 lines and 2 members");
            check(TesterChecks.PartyShareProblems(J("{\"shareActive\":true,\"lines\":2,\"size\":2,\"shareOf1000\":650,\"shareEnabled\":false}")).Count == 0, "party xp: the share the rule gives is fine");
            check(TesterChecks.PartyShareProblems(J("{\"shareActive\":false,\"lines\":2,\"size\":2}"))[0].Contains("says it is off"), "party xp: a switch that did not take");
            check(TesterChecks.PartyShareProblems(J("{\"shareActive\":true,\"lines\":2,\"size\":2,\"shareOf1000\":900}"))[0].Contains("pays 900") && TesterChecks.PartyShareProblems(J("{\"shareActive\":true,\"lines\":2,\"size\":2,\"shareOf1000\":900}"))[0].Contains("gives 650"), "party xp: a wrong share is named with the rule's number");
            check(TesterChecks.PartyShareProblems(J("{\"shareActive\":true,\"shareEnabled\":true,\"problems\":[{\"kind\":\"level\",\"name\":\"B\"}]}"))[0].Contains("two thirds") && TesterChecks.PartyShareProblems(J("{\"shareActive\":true,\"shareEnabled\":true,\"problems\":[{\"kind\":\"range\",\"name\":\"B\"}]}"))[0].Contains("out of range") && TesterChecks.PartyShareProblems(J("{\"shareActive\":true,\"shareEnabled\":false,\"problems\":[{\"kind\":\"level\",\"name\":\"B\"}]}")).Count == 0, "party xp: working while a member fails level or range is a problem, off for that reason is fine");
            var bad = new List<string>();
            check(TesterChecks.SharedKill(J("{\"shared\":{\"dead\":true,\"enabled\":true,\"leader\":650,\"partner\":650},\"solo\":{\"dead\":true,\"leader\":1000,\"partner\":0}}"), 650, bad) == null && bad.Count == 0, "shared kill: a leader share of 65 % of the solo kill passes");
            bad = new List<string>();
            check(TesterChecks.SharedKill(J("{\"shared\":{\"dead\":true,\"enabled\":true,\"leader\":1000,\"partner\":1000},\"solo\":{\"dead\":true,\"leader\":1000,\"partner\":0}}"), 650, bad) == null && bad.Count == 1 && bad[0].Contains("100% of a solo kill") && bad[0].Contains("pays 65%"), "shared kill: a leader that got the whole kill with the share working is a problem");
            bad = new List<string>();
            check(TesterChecks.SharedKill(J("{\"shared\":{\"dead\":true,\"enabled\":true,\"leader\":650,\"partner\":0},\"solo\":{\"dead\":true,\"leader\":1000,\"partner\":40}}"), 650, bad) == null && bad.Count == 2 && bad.Any(x => x.Contains("paid the partner nothing")) && bad.Any(x => x.Contains("solo kill of the leader paid the partner 40")), "shared kill: a working share that pays the partner nothing, a solo kill that pays the partner");
            bad = new List<string>();
            check(TesterChecks.SharedKill(J("{\"shared\":{\"dead\":true,\"enabled\":false,\"leader\":1000,\"partner\":50,\"partnerHit\":true},\"solo\":{\"dead\":true,\"leader\":1000,\"partner\":0}}"), 0, bad) == null && bad.Count == 0, "shared kill: a partner that hit the monster earns its own share (no failure)");
            bad = new List<string>();
            check(TesterChecks.SharedKill(null, 650, bad).Contains("old helper file") && TesterChecks.SharedKill(J("{\"err\":\"x\"}"), 650, bad) == "no shared kill: x" && TesterChecks.SharedKill(J("{\"monster\":\"Demon\",\"shared\":{\"dead\":false,\"hp\":10,\"hpLeft\":5,\"pz\":true},\"solo\":{}}"), 650, bad).Contains("did not die") && TesterChecks.SharedKill(J("{\"shared\":{\"dead\":true},\"solo\":{\"dead\":true,\"leader\":0}}"), 650, bad).Contains("paid the leader nothing") && bad.Count == 0, "shared kill: a kill that did not run is a skip text, not a problem");
        }

        static string Waystone(int tier, string patch = "")
        {
            long lv = TesterChecks.TierLevel(tier);
            return "{\"tier\":" + tier + ",\"tierLevel\":" + lv + ",\"nrolled\":3,\"held\":{\"tier\":" + tier + ",\"mods\":3,\"rarity\":\"Rare\",\"expectRarity\":\"Rare\"},\"take\":{\"ok\":true,\"before\":2,\"after\":1,\"mods\":3},\"run\":{\"live\":true,\"tier\":" + tier + ",\"mods\":3,\"seconds\":900,\"active\":" + tier + "},\"monsters\":[{\"name\":\"Ghoul\",\"level\":" + lv + ",\"expectLevel\":" + lv + ",\"ratio\":2.0,\"expectRatio\":2.0}]" + patch + "}";
        }

        static void WaystoneRules(Action<bool, string> check)
        {
            check(TesterChecks.TierLevel(1) == 1100 && TesterChecks.TierLevel(15) == 2500, "waystone: 1100 at tier I, 2500 at tier XV");
            foreach (int t in TesterChecks.WaystoneTiers) check(TesterChecks.WaystoneProblems(J(Waystone(t))).Count == 0, "waystone: a correct run of tier " + t + " passes");
            check(TesterChecks.WaystoneProblems(J(Waystone(8).Replace("\"tierLevel\":1800", "\"tierLevel\":1700")))[0].Contains("runs at level 1700, expected 1800"), "waystone: a wrong tier level");
            check(TesterChecks.WaystoneProblems(J(Waystone(8).Replace("\"rarity\":\"Rare\",\"expectRarity\"", "\"rarity\":\"Magic\",\"expectRarity\"")))[0].Contains("is Magic, expected Rare"), "waystone: a waystone that is not Rare");
            check(TesterChecks.WaystoneProblems(J(Waystone(8).Replace("\"before\":2,\"after\":1", "\"before\":2,\"after\":2")))[0].Contains("changed the count 2 -> 2"), "waystone: the device must take exactly one");
            check(TesterChecks.WaystoneProblems(J(Waystone(8).Replace("\"live\":true", "\"live\":false")))[0].Contains("not registered"), "waystone: a run that is not registered");
            check(TesterChecks.WaystoneProblems(J(Waystone(8).Replace("\"seconds\":900", "\"seconds\":7200")))[0].Contains("lasts 7200 s") && TesterChecks.WaystoneProblems(J(Waystone(8).Replace("\"active\":8", "\"active\":2")))[0].Contains("counts at tier 2"), "waystone: the run time and the map's tier");
            check(TesterChecks.WaystoneProblems(J(Waystone(8).Replace("\"level\":1800,\"expectLevel\":1800", "\"level\":1100,\"expectLevel\":1800")))[0].Contains("is level 1100 (rule 1800)"), "waystone: a monster at the wrong level");
            check(TesterChecks.WaystoneProblems(J(Waystone(8).Replace("\"ratio\":2.0", "\"ratio\":1.5")))[0].Contains("health x1.500") && TesterChecks.WaystoneProblems(J(Waystone(8).Replace("\"ratio\":2.0", "\"ratio\":2.05"))).Count == 0, "waystone: monster health within 3 %");
            check(TesterChecks.WaystoneProblems(J(Waystone(8).Replace(",\"monsters\":[{\"name\":\"Ghoul\",\"level\":1800,\"expectLevel\":1800,\"ratio\":2.0,\"expectRatio\":2.0}]", ""))).Count == 0, "waystone: no monster in range still checks the rest");
            var loot = J("{\"paid\":true,\"pieces\":8,\"minPieces\":6,\"badRarity\":0,\"orbs\":[{\"name\":\"Orb\",\"count\":3,\"min\":2}],\"waystones\":1,\"minWaystones\":1}");
            check(TesterChecks.WaystoneLootProblems(loot).Count == 0, "waystone loot: what the config guarantees passes");
            check(TesterChecks.WaystoneLootProblems(J("{\"paid\":false}"))[0].Contains("paid nothing") && TesterChecks.WaystoneLootProblems(J("{\"paid\":true,\"pieces\":3,\"minPieces\":6}"))[0].Contains("guarantees 6"), "waystone loot: nothing paid, too few pieces");
            check(TesterChecks.WaystoneLootProblems(J("{\"paid\":true,\"badRarity\":2,\"orbs\":[{\"name\":\"Orb\",\"count\":1,\"min\":2}],\"waystones\":0,\"minWaystones\":1}")).Count == 3, "waystone loot: pieces below Legendary, a short orb stack and no waystone are three problems");
        }

        static string Layout(string patch = "")
        {
            return "{\"theme\":\"Ashen Crypt\",\"kind\":\"dungeon\",\"kinds\":[\"dungeon\",\"cave\"],\"floors\":1,\"floorCounts\":[1,2],\"band\":3,\"bandExpected\":3,\"readyOfBand\":2,\"tier\":15,\"limits\":{\"walkableMin\":5000,\"walkableMax\":20000},\"walkable\":13429,\"route\":203,"
                 + "\"startWalk\":true,\"bossWalk\":true,\"mouthWalk\":true,\"playerWalk\":true,\"sample\":{\"n\":40,\"bare\":0,\"blocked\":0},\"after\":{\"inRun\":false,\"slotFree\":true}" + patch + "}";
        }

        static void RiftRules(Action<bool, string> check)
        {
            check(TesterChecks.RiftLayoutProblems(J(Layout())).Count == 0, "rift layout: a valid layout passes (the band is a number, as the live answer has it)");
            check(TesterChecks.RiftLayoutProblems(J(Layout().Replace("\"band\":3", "\"band\":2")))[0].Contains("made a band 2 layout, the config says band 3"), "rift layout: another band fails when one of the tier was ready");
            check(TesterChecks.RiftLayoutProblems(J(Layout().Replace("\"band\":3", "\"band\":2").Replace("\"readyOfBand\":2", "\"readyOfBand\":0"))).Count == 0, "rift layout: another band is fine when none of the tier was ready");
            check(TesterChecks.RiftLayoutProblems(J(Layout().Replace("\"kind\":\"dungeon\"", "\"kind\":\"maze\"")))[0].Contains("layout kind maze") && TesterChecks.RiftLayoutProblems(J(Layout().Replace("\"floors\":1", "\"floors\":5")))[0].Contains("5 floor(s)"), "rift layout: kind and floors from the theme's config");
            check(TesterChecks.RiftLayoutProblems(J(Layout().Replace("13429", "100")))[0].Contains("100 walkable tiles, the band holds 5000 to 20000") && TesterChecks.RiftLayoutProblems(J(Layout().Replace("\"route\":203", "\"route\":0")))[0].Contains("no walking route"), "rift layout: the walkable count and the route");
            check(TesterChecks.RiftLayoutProblems(J(Layout().Replace("\"bossWalk\":true", "\"bossWalk\":false")))[0].Contains("guardian's spot") && TesterChecks.RiftLayoutProblems(J(Layout().Replace("\"bare\":0,\"blocked\":0", "\"bare\":2,\"blocked\":1")))[0].Contains("2 have no ground and 1 block"), "rift layout: a spot that is not a cell, bare or blocking cells");
            check(TesterChecks.RiftLayoutProblems(J(Layout().Replace("\"slotFree\":true", "\"slotFree\":false")))[0].Contains("did not close") && TesterChecks.RiftLayoutProblems(J(Layout(",\"err\":\"boom\"")))[0].Contains("boom"), "rift layout: a run that did not close, an error in the answer");
        }

        static void ProbeRules(Action<bool, string> check)
        {
            check(TesterChecks.UniqueProblems(J("{\"family\":\"critrule\",\"active\":[\"critrule\"],\"m\":0.9,\"lostBefore\":331,\"lostAfter\":298}")).Count == 0, "unique: a hit that follows the rule (331 to 298 is x0.900)");
            check(TesterChecks.UniqueProblems(J("{\"family\":\"critrule\",\"active\":[\"critrule\"],\"m\":0.9,\"lostBefore\":159,\"lostAfter\":78}"))[0].Contains("x0.491") && TesterChecks.UniqueProblems(J("{\"family\":\"critrule\",\"active\":[\"critrule\"],\"m\":0.9,\"lostBefore\":159,\"lostAfter\":78}"))[0].Contains("rule says x0.900"), "unique: a hit off the rule is named with both numbers (the Beastmaster of the live run)");
            check(TesterChecks.UniqueProblems(J("{\"family\":\"opener\",\"active\":[],\"id\":5}"))[0].Contains("passive asleep") && TesterChecks.UniqueProblems(J("{\"family\":\"opener\",\"active\":[\"opener\"]}"))[0].Contains("never reached"), "unique: a sleeping passive, a hit that never reached the rule");
            check(TesterChecks.DualProblems(J("{\"able\":true,\"left\":0,\"right\":0,\"melee\":8,\"off\":8}"), "fists").Count == 0 && TesterChecks.DualProblems(J("{\"able\":true,\"left\":0,\"right\":0,\"melee\":8,\"off\":7}"), "fists").Count == 0, "dual: an off-hand strike for each melee hit (one fewer is the last hit cut by the watch)");
            check(TesterChecks.DualProblems(J("{\"able\":true,\"left\":0,\"right\":0,\"melee\":8,\"off\":0}"), "blades")[0].Contains("no off-hand strike") && TesterChecks.DualProblems(J("{\"able\":true,\"left\":0,\"right\":0,\"melee\":8,\"off\":3}"), "blades")[0].Contains("3 off-hand strikes") && TesterChecks.DualProblems(J("{\"able\":true,\"left\":0,\"right\":14}"), "blades")[0].Contains("shield hand code 14"), "dual: no strike, too few strikes, an item that could not be worn");
            check(TesterChecks.DualProblems(J("{\"able\":false,\"left\":71}"), "fists").Count == 0 && TesterChecks.DualProblems(J("{\"able\":false,\"left\":0}"), "fists")[0].Contains("outside the Monk line could wear") && TesterChecks.DualProblems(J("{\"able\":false,\"left\":0,\"right\":14}"), "blades").Count == 0 && TesterChecks.DualProblems(J("{\"able\":false,\"left\":0,\"right\":0}"), "blades")[0].Contains("could hold a dagger"), "dual: another class must be refused");
            check(TesterChecks.MonkLine.Length == 3, "dual: the Monk line");
        }

        static void ChestRules(Action<bool, string> check)
        {
            var spawn = J("{\"state\":\"idle\",\"left\":1}");
            check(TesterChecks.ChestProblems(spawn, J("{\"state\":\"running\"}"), J("{\"state\":\"running\",\"monsters\":3,\"horde\":3,\"made\":3}"), J("{\"state\":\"none\",\"left\":0}")).Count == 0, "cursed chest: spawn, use, abort leaves nothing");
            check(TesterChecks.ChestProblems(J("{\"state\":\"running\"}"), J("{\"state\":\"running\"}"), null, null)[0].Contains("expected idle"), "cursed chest: a chest that is not idle at the spawn");
            check(TesterChecks.ChestProblems(spawn, J("{\"state\":\"gone\"}"), null, null)[0].Contains("after use the chest is 'gone'"), "cursed chest: a chest that is gone after the use");
            check(TesterChecks.ChestProblems(spawn, J("{\"state\":\"running\"}"), J("{\"state\":\"running\",\"monsters\":0,\"horde\":4,\"made\":0}"), null)[0].Contains("horde 4 came with no monster") && TesterChecks.ChestProblems(spawn, J("{\"state\":\"running\"}"), J("{\"state\":\"running\",\"monsters\":0,\"horde\":4,\"made\":4}"), null).Count == 0, "cursed chest: a horde that made no monster, one the bots killed at once is fine");
            check(TesterChecks.ChestProblems(spawn, J("{\"state\":\"running\"}"), null, J("{\"state\":\"running\",\"left\":1}"))[0].Contains("still 'running' (left 1)") && TesterChecks.ChestProblems(spawn, J("{\"state\":\"idle\"}"), null, J("{\"state\":\"gone\",\"left\":0}")).Count == 0, "cursed chest: a chest that survives the abort");
        }

        static void SpellRules(Action<bool, string> check)
        {
            var row = new RotClass { Id = 15, Name = "Beastmaster", Ultimate = 9 };
            row.Presets.Add(new RotPreset(100, 2.0, new[] { 1, 2 }, new[] { 1, 1 }));
            row.Presets.Add(new RotPreset(400, 2.0, new[] { 3, 4 }, new[] { 1, 1 }));
            row.Extras.Add(7);
            var spells = new Dictionary<int, Spell>
            {
                { 1, new Spell { Id = 1, Name = "One", Level = 10 } }, { 2, new Spell { Id = 2, Name = "Two", Level = 20 } },
                { 3, new Spell { Id = 3, Name = "Three", Level = 400 } }, { 4, new Spell { Id = 4, Name = "Four", Level = 500 } },
            };
            Func<int, Spell> spellOf = id => spells.TryGetValue(id, out var s) ? s : null;
            Func<Spell, SpellStatus> allReady = s => SpellStatus.Ready;
            check(TesterChecks.AutoSetupProblems(row, 150, spellOf, allReady).Count == 0 && TesterChecks.AutoSetupProblems(row, 5, spellOf, allReady).Count == 0, "auto setup: the preset of the level is castable; below the first preset there is nothing to check");
            check(TesterChecks.AutoSetupProblems(null, 50, spellOf, allReady) == null, "auto setup: a class with no row is a skip");
            var bad = TesterChecks.AutoSetupProblems(row, 450, spellOf, s => s.Id == 3 ? SpellStatus.Ready : s.Id == 4 ? SpellStatus.Level : SpellStatus.Ready);
            check(bad.Count == 1 && bad[0].Contains("Four (4) needs level 500"), "auto setup: a spell above the level is named");
            bad = TesterChecks.AutoSetupProblems(row, 150, id => id == 1 ? null : spellOf(id), s => s.Id == 2 ? SpellStatus.Vocation : SpellStatus.Ready);
            check(bad.Count == 2 && bad.Any(x => x.Contains("spell 1 is not on the server")) && bad.Any(x => x.Contains("Two (2) is not open to Beastmaster")), "auto setup: a spell the server does not list, one the class may not cast");
            bad = TesterChecks.AutoSetupProblems(row, 150, spellOf, s => s.Id == 1 ? SpellStatus.Learn : SpellStatus.Quest);
            check(bad.Count == 2 && bad[0].Contains("not learned") && bad[1].Contains("needs its quest"), "auto setup: a spell that is not learned or needs its quest");
            var quest = new Spell { Id = 9, Name = "Quest Spell", Level = 500 };
            check(TesterChecks.QuestSpellProblems(quest, 500, true, row, null).Count == 0, "quest spell: the class's ultimate is in the Auto setup data");
            var extra = new Spell { Id = 7, Name = "Extra", Level = 100 };
            check(TesterChecks.QuestSpellProblems(extra, 500, true, row, null).Count == 0, "quest spell: an extra is in the Auto setup data");
            var buff = new Spell { Id = 50, Name = "Buff", Level = 800 };
            check(TesterChecks.QuestSpellProblems(buff, 800, true, row, null)[0].Contains("in no preset or extras"), "quest spell: a spell in no preset fails");
            check(TesterChecks.QuestSpellProblems(buff, 800, true, row, id => id == 50).Count == 0, "quest spell: a level 800 buff that Auto setup keeps up as a timer passes");
            check(TesterChecks.QuestSpellProblems(buff, 700, false, row, id => id == 50).Count == 2, "quest spell: not open to the class and gated above the level");
            check(TesterChecks.QuestSpellProblems(null, 500, true, row, null) == null, "quest spell: a spell the server does not list is null");
            // the real rotation data: every class has a preset at level 1500 and its ultimate / extras are ids of the spell data
            int classes = 0;
            foreach (var kv in HelperRotation.Classes)
            {
                classes++;
                check(kv.Value.Presets.Count > 0 && kv.Value.Presets.All(p => p.Spells.Length > 0), "auto setup data: " + kv.Value.Name + " has presets with spells");
            }
            check(classes >= 21, "auto setup data: all 21 classes are in the rotation data (" + classes + ")");
        }

        static string Repo(string rel)
        {
            string f = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", rel));
            return File.Exists(f) ? File.ReadAllText(f) : null;
        }

        static void Coverage(Action<bool, string> check)
        {
            string py = Repo("server/tools/tester_checks.py");
            check(py != null, "coverage: server/tools/tester_checks.py is there");
            if (py != null)
            {
                var keys = new List<string>();
                int at = py.IndexOf("CHECKS = [", StringComparison.Ordinal);
                int end = py.IndexOf("\n]", at, StringComparison.Ordinal);
                foreach (Match m in Regex.Matches(py.Substring(at, end - at), @"\('(\w+)', check_")) keys.Add(m.Groups[1].Value);
                var table = TesterChecks.CheckScenarios.Select(x => x.Check).ToList();
                check(keys.Count >= 17 && keys.OrderBy(x => x).SequenceEqual(table.OrderBy(x => x)), "coverage: every check of tester_checks.py has its scenario, and no other (" + string.Join(",", keys.Except(table)) + " missing, " + string.Join(",", table.Except(keys)) + " extra)");
            }
            var scenarios = TesterChecks.CheckScenarios.Select(x => x.Scenario).Distinct().ToList();
            check(scenarios.All(s => Core.LiveCheck.LiveRun.OptInScenarios.Contains(s) && !Core.LiveCheck.LiveRun.AllScenarios.Contains(s)), "coverage: every tester scenario is opt-in by name, none in `all` (the helper is TEST ONLY)");
            check(Core.LiveCheck.LiveRun.TesterScenarios.OrderBy(x => x).SequenceEqual(scenarios.OrderBy(x => x)), "coverage: the scenario list of LiveRun.TesterScenarios is the one of the table");
            check(Core.LiveCheck.LiveRun.OptInScenarios.Distinct().Count() == Core.LiveCheck.LiveRun.OptInScenarios.Length, "coverage: no scenario name twice");
            {
                // The run order is the list order. A partner scenario logs the second character in and leaves it online,
                // and the server refuses a trial or dungeon entry while a second character of the same address is online.
                var partner = Core.LiveCheck.LiveRun.TesterPartnerScenarios;
                var tester = Core.LiveCheck.LiveRun.TesterScenarios;
                var optIn = Core.LiveCheck.LiveRun.OptInScenarios.ToList();
                string src = Repo("unity/Core.LiveCheck/LiveScenarios11.cs");
                var uses = new List<string>();
                if (src != null)
                    foreach (Match m in Regex.Matches(src, @"void (ScT\w+)\(ScenarioResult r\)\s*\{(.*?)\n        \}", RegexOptions.Singleline))
                        if (m.Groups[2].Value.Contains("PartnerTester(")) uses.Add(m.Groups[1].Value);
                check(partner.Length == 2 && uses.Count == partner.Length, "order: the partner scenario list names every scenario that calls PartnerTester (" + uses.Count + " in the source)");
                check(tester.Skip(tester.Length - partner.Length).SequenceEqual(partner), "order: the partner scenarios end LiveRun.TesterScenarios");
                check(optIn.Skip(optIn.Count - partner.Length).SequenceEqual(partner), "order: the partner scenarios end LiveRun.OptInScenarios, the order a run follows");
                int firstPartner = partner.Min(x => optIn.IndexOf(x));
                check(tester.Where(x => !partner.Contains(x)).All(x => optIn.IndexOf(x) >= 0 && optIn.IndexOf(x) < firstPartner), "order: every other tester scenario runs before the partner logs in");
            }
            string run = Repo("unity/Core.LiveCheck/LiveScenarios.cs");
            check(run != null && scenarios.All(s => run.Contains("case \"" + s + "\":")), "coverage: every tester scenario has its case in the dispatcher");
        }
    }
}
