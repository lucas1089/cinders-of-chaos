// Phase 30 (2026-11-09): the rules of the tester bot system checks (server/tools/tester_checks.py), as pure Core functions so the Unity live check holds a Unity-driven account
// to the same facts (O433, unity/README.md "Tester checks on the Unity core (phase 30)"). The helper that answers (server/tools/tester_helper.lua, `!tester ...`) is TEST ONLY: it acts
// only for a character named "Tester Xxx" with the tester storage 7102900 = 1. Its answer is one server text line, "[tester-helper] <kind> <json>". Every function here reads such an
// answer (the JSON as plain C# objects, see Json) and returns the problems it finds; the numbers are the ones of tester_checks.py and of the configs it quotes.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;

namespace Chaos.Core
{
    public static class TesterChecks
    {
        public const string Mark = "[tester-helper]";
        public const long Storage = 7102900;
        /// <summary>Seconds a summon is watched for a wrong target (tester_checks.py WATCH) and between two looks (LOOK).</summary>
        public const double WatchSeconds = 20.0, LookSeconds = 2.0;
        public const int QuestLevel = 500;
        public static readonly int[] QuestLevels = { 500, 800, 1200 };
        public const long QuestGold = 2000;
        public const int LootTier = 8;
        public static readonly int[] WaystoneTiers = { 2, 8, 14 };
        public const double KillTolerance = 0.05, UniqueTolerance = 0.03;

        /// <summary>class name -> (summon spell words, check name, the cap of summons after one cast): tester_checks.py SUMMONERS.</summary>
        public static readonly Dictionary<string, (string Words, string Check, int Cap)> Summoners = new Dictionary<string, (string, string, int)>
        {
            { "Beastmaster", ("vael ferh", "beastmaster_wolf", 2) },
            { "Necromancer", ("vael oss", "necro_minions", 5) },
            { "Lich", ("vael oss", "necro_minions", 5) },
            { "Bone Lord", ("vael oss", "necro_minions", 5) },
        };

        public static readonly string[] MonkLine = { "Monk", "Shadowfist", "Iron Sage" };

        /// <summary>Every check of tester_checks.py (CHECKS) and the live scenario that drives it through the Unity core (phase 30). A test reads tester_checks.py and fails when a check is missing here.</summary>
        public static readonly (string Check, string Scenario)[] CheckScenarios =
        {
            ("beastmaster_wolf", "testsummons"), ("necro_minions", "testsummons"), ("pets", "testpets"), ("party", "testparty"), ("rift", "testrift"), ("rift_layout", "testrift"),
            ("waystone_run", "testwaystone"), ("content_rewards", "testloot"), ("party_xp", "testpartyxp"), ("unique_passive", "testunique"), ("dual_fists", "testdual"), ("dual_blades", "testdual"),
            ("waystone", "testwaystone"), ("reward_chest", "testchests"), ("cursed_chest", "testchests"), ("auto_setup", "testauto"), ("spell_quest", "testspellquest"),
        };

        // ------------------------------------------------------------------------------------ the line
        static readonly Regex TesterName = new Regex("^Tester [A-Z][a-z][a-z]$", RegexOptions.CultureInvariant);

        /// <summary>The helper's own guard (tester_helper_core.lua H.eligible): the name shape and the storage.</summary>
        public static bool Eligible(string name, long storage) => name != null && storage == 1 && TesterName.IsMatch(name);

        /// <summary>One answer line: "[tester-helper] kind {json}". False for any other text (and for a kind whose JSON does not parse).</summary>
        public static bool TryParseLine(string text, out string kind, out Dictionary<string, object> data)
        {
            kind = ""; data = null;
            if (text == null || !text.StartsWith(Mark + " ", StringComparison.Ordinal)) return false;
            string rest = text.Substring(Mark.Length + 1);
            int sp = rest.IndexOf(' ');
            if (sp <= 0) return false;
            kind = rest.Substring(0, sp);
            data = Json.TryParse(rest.Substring(sp + 1)) as Dictionary<string, object>;
            return data != null;
        }

        // ------------------------------------------------------------------------------------ reading the answer
        public static object Get(Dictionary<string, object> d, string key) => d != null && d.TryGetValue(key, out object v) ? v : null;
        public static bool Has(Dictionary<string, object> d, string key) => d != null && d.ContainsKey(key) && d[key] != null;
        public static long Int(Dictionary<string, object> d, string key, long def = 0)
        {
            object v = Get(d, key);
            if (v is double x) return (long)Math.Round(x);
            if (v is bool b) return b ? 1 : 0;
            return def;
        }
        public static double Num(Dictionary<string, object> d, string key, double def = 0) => Get(d, key) is double x ? x : def;
        public static string Str(Dictionary<string, object> d, string key, string def = "") => Get(d, key) is string s ? s : def;
        public static bool True(Dictionary<string, object> d, string key) => Get(d, key) is bool b && b;
        public static bool False(Dictionary<string, object> d, string key) => Get(d, key) is bool b && !b;
        public static Dictionary<string, object> Obj(Dictionary<string, object> d, string key) => Get(d, key) as Dictionary<string, object> ?? new Dictionary<string, object>();
        public static List<Dictionary<string, object>> Rows(Dictionary<string, object> d, string key)
        {
            var o = new List<Dictionary<string, object>>();
            if (Get(d, key) is List<object> l) foreach (var x in l) if (x is Dictionary<string, object> r) o.Add(r);
            return o;
        }
        public static List<string> Strings(Dictionary<string, object> d, string key)
        {
            var o = new List<string>();
            if (Get(d, key) is List<object> l) foreach (var x in l) if (x is string s) o.Add(s);
            return o;
        }
        public static string Err(Dictionary<string, object> d) => Get(d, "err") is string s ? s : (Get(d, "err") != null && !(Get(d, "err") is bool b && !b) ? Convert.ToString(Get(d, "err"), CultureInfo.InvariantCulture) : "");
        static string F(double v) => v.ToString("0.###", CultureInfo.InvariantCulture);
        static string N(object v) => v == null ? "None" : v is double x ? F(x) : v is bool b ? (b ? "True" : "False") : Convert.ToString(v, CultureInfo.InvariantCulture);
        static string Cut(string s, int n) => s != null && s.Length > n ? s.Substring(0, n) : s ?? "";

        // ------------------------------------------------------------------------------------ summons
        /// <summary>The wrong sides in one `!tester summons` answer: a summon that targets its owner or an ally or a summon, allies left in its engine target list, the owner holding a summon as target.</summary>
        public static List<string> SnapshotProblems(Dictionary<string, object> snap)
        {
            var o = new List<string>();
            if (snap == null) return o;
            foreach (var s in Rows(snap, "summons"))
            {
                string t = Str(s, "target");
                string name = Str(s, "name", "summon"), id = Has(s, "id") ? N(Get(s, "id")) : "?";
                if (t == "owner" || t == "ally" || t == "summon") o.Add(name + " #" + id + " targets " + (t == "owner" ? "its owner" : "an ally (" + t + ")"));
                if (Int(s, "listedAllies") > 0) o.Add(name + " #" + id + " has " + Int(s, "listedAllies") + " allies in its engine target list");
            }
            if (Str(snap, "ownerTarget") == "summon") o.Add("the owner holds its own or a party member's summon as target");
            return o;
        }

        /// <summary>Why the helper's `!tester pet` answer shows no live pet (tester_checks.py pet_rest_text).</summary>
        public static string PetRestText(Dictionary<string, object> live)
        {
            string rest = Str(live, "rest");
            if (rest.Length > 0)
            {
                string why = rest == "pz" ? "a protection zone" : rest == "zone" ? "a zone without pets" : rest == "summons" ? "the bot has other summons" : rest;
                return "rests: " + why;
            }
            if (Int(live, "deathLeft") > 0) return "death cooldown " + Int(live, "deathLeft") + " s";
            if (Int(live, "summonLeft") > 0 && !True(live, "live")) return "call cooldown " + Int(live, "summonLeft") + " s";
            if (live == null || live.Count == 0) return "no answer to !tester pet";
            return "no rule of the game says why";
        }

        // ------------------------------------------------------------------------------------ party and shared experience
        /// <summary>The party frames' bonus in percent for n class lines (party_xp_core.lua bonusPercent); the stock 20 for none.</summary>
        public static int BonusPercent(int lines)
        {
            if (lines <= 1) return 20;
            int n = Math.Min(lines, 5);
            return n * (5 * (n - 1) + 10);
        }

        /// <summary>What Party:onShareExperience pays one member for `exp`: ceil(exp x (100 + bonus) / 100 / members).</summary>
        public static long ShareExpected(int lines, int size, long exp = 1000)
        {
            long num = exp * (100 + BonusPercent(lines)), den = 100L * Math.Max(1, size);
            return (num + den - 1) / den;
        }

        /// <summary>The wrong facts of one `!tester party` answer of a party whose leader switched shared experience on.</summary>
        public static List<string> PartyShareProblems(Dictionary<string, object> p)
        {
            var o = new List<string>();
            if (!True(p, "shareActive")) o.Add("the leader switched shared experience on, the party says it is off");
            int lines = (int)Int(p, "lines"), size = (int)Int(p, "size");
            if (Has(p, "shareOf1000") && lines >= 1)
            {
                long want = ShareExpected(lines, size);
                if (Int(p, "shareOf1000") != want)
                    o.Add("1000 experience pays " + N(Get(p, "shareOf1000")) + " to a member, the rule (" + lines + " class line(s), " + size + " members, +" + BonusPercent(lines) + "%) gives " + want);
            }
            var hard = Rows(p, "problems").Where(x => Str(x, "kind") == "level" || Str(x, "kind") == "range").ToList();
            if (True(p, "shareEnabled") && hard.Count > 0)
                o.Add("shared experience works while " + Str(hard[0], "name", "?") + " " + (Str(hard[0], "kind") == "level" ? "is below two thirds of the highest level" : "is out of range"));
            return o;
        }

        /// <summary>The "kill" part of `!tester party kill`: a real kill with the share as the leader set it, then a solo kill. Returns the skip text (null when the kill ran); the problems go to `problems`.
        /// Working share: both gain, the leader's gain against the solo kill is what Party:onShareExperience pays (shareOf1000 / 1000, within KillTolerance). Share off: the partner gains nothing.
        /// A solo kill never pays the partner.</summary>
        public static string SharedKill(Dictionary<string, object> kill, long shareOf1000, List<string> problems)
        {
            if (kill == null) return "no answer to !tester party kill (an old helper file, or the bot died)";
            if (Err(kill).Length > 0) return "no shared kill: " + Err(kill);
            var sh = Obj(kill, "shared"); var so = Obj(kill, "solo");
            foreach (var k in new[] { sh, so })
            {
                if (Err(k).Length > 0) return "no shared kill: " + Err(k);
                if (!True(k, "dead"))
                    return "the " + Str(kill, "monster", "monster") + " did not die in the kill (health " + N(Get(k, "hp")) + " -> " + N(Get(k, "hpLeft")) + (True(k, "pz") ? ", leader in a protection zone" : "") + (Str(k, "hitErr").Length > 0 ? ", " + Str(k, "hitErr") : "") + ")";
            }
            if (Int(so, "leader") <= 0) return "the solo kill paid the leader nothing (no experience from this monster here)";
            if (Int(so, "partner") != 0 && !True(so, "partnerHit")) problems.Add("a solo kill of the leader paid the partner " + Int(so, "partner") + " experience");
            if (True(sh, "enabled"))
            {
                if (Int(sh, "partner") <= 0) problems.Add("a kill with the share working paid the partner nothing");
                if (shareOf1000 > 0)
                {
                    double got = Int(sh, "leader") / (double)Int(so, "leader"), want = shareOf1000 / 1000.0;
                    if (Math.Abs(got / want - 1) > KillTolerance)
                        problems.Add("the leader got " + F(Math.Round(got * 100)) + "% of a solo kill with the share working, Party:onShareExperience pays " + F(Math.Round(want * 100)) + "%");
                }
            }
            else if (Int(sh, "partner") > 0 && !True(sh, "partnerHit"))
                problems.Add("the partner got " + Int(sh, "partner") + " experience from a kill with the share not working");
            return null;
        }

        // ------------------------------------------------------------------------------------ waystones
        /// <summary>The level of a waystone run: 1100 at tier I, 100 more per tier up to 2500 (waystone_tiers_config.lua).</summary>
        public static long TierLevel(long tier) => 1000 + 100 * tier;

        /// <summary>The wrong facts of one `!tester waystone TIER` answer (a run of that tier, read back).</summary>
        public static List<string> WaystoneProblems(Dictionary<string, object> a)
        {
            var o = new List<string>();
            long t = Int(a, "tier");
            if (Int(a, "tierLevel") != TierLevel(t)) o.Add("tier " + t + " runs at level " + N(Get(a, "tierLevel")) + ", expected " + TierLevel(t));
            var held = Obj(a, "held"); var take = Obj(a, "take"); var run = Obj(a, "run");
            long n = Int(a, "nrolled");
            if (Int(held, "tier") != t || Int(held, "mods") != n) o.Add("the waystone written with " + n + " modifiers reads back as tier " + N(Get(held, "tier")) + " with " + N(Get(held, "mods")));
            if (Str(held, "rarity") != "Rare" || Str(held, "expectRarity") != "Rare") o.Add("a waystone with " + n + " modifiers is " + N(Get(held, "rarity")) + ", expected Rare");
            if (!True(take, "ok")) o.Add("the device could not take the waystone it was given");
            else
            {
                if (Int(take, "before") - Int(take, "after") != 1) o.Add("taking one waystone changed the count " + N(Get(take, "before")) + " -> " + N(Get(take, "after")));
                if (Int(take, "mods") != n) o.Add("the take returned " + N(Get(take, "mods")) + " modifiers, the waystone has " + n);
            }
            if (True(take, "ok"))
            {
                if (!True(run, "live")) o.Add("the run with " + n + " modifiers is not registered");
                else
                {
                    if (Int(run, "tier") != t || Int(run, "mods") != n) o.Add("the run is tier " + N(Get(run, "tier")) + " with " + N(Get(run, "mods")) + " modifiers, expected " + t + " with " + n);
                    long sec = Int(run, "seconds");
                    if (!(0 < sec && sec <= 3600)) o.Add("the run lasts " + N(Get(run, "seconds")) + " s");
                }
                if (Int(run, "active") != t) o.Add("the map counts at tier " + N(Get(run, "active")) + " during the run, expected " + t);
            }
            foreach (var m in Rows(a, "monsters"))
                if (Int(m, "level") != TierLevel(t) || Int(m, "expectLevel") != TierLevel(t))
                {
                    o.Add(Str(m, "name") + " is level " + N(Get(m, "level")) + " (rule " + N(Get(m, "expectLevel")) + ") in a tier " + t + " run, expected " + TierLevel(t));
                    break;
                }
            foreach (var m in Rows(a, "monsters"))
            {
                double r = Num(m, "ratio"), e = Num(m, "expectRatio");
                if (r != 0 && e != 0 && Math.Abs(r / e - 1) > 0.03)
                {
                    o.Add(Str(m, "name") + " health x" + r.ToString("0.000", CultureInfo.InvariantCulture) + " in the run, the level and modifiers give x" + e.ToString("0.000", CultureInfo.InvariantCulture));
                    break;
                }
            }
            return o;
        }

        /// <summary>The wrong facts of the "loot" part of `!tester waystone TIER loot`: what a boss kill of the run leaves.</summary>
        public static List<string> WaystoneLootProblems(Dictionary<string, object> loot)
        {
            var o = new List<string>();
            if (!True(loot, "paid")) { o.Add("the run's boss kill paid nothing through the content rewards"); return o; }
            if (Int(loot, "pieces") < Int(loot, "minPieces")) o.Add("boss table: " + N(Get(loot, "pieces")) + " gear piece(s) of Legendary or better, the config guarantees " + N(Get(loot, "minPieces")));
            if (Int(loot, "badRarity") > 0) o.Add("boss table: " + N(Get(loot, "badRarity")) + " piece(s) below Legendary");
            foreach (var orb in Rows(loot, "orbs"))
                if (Int(orb, "count") < Int(orb, "min")) o.Add("boss table: " + Str(orb, "name") + " x" + N(Get(orb, "count")) + ", the config guarantees at least " + N(Get(orb, "min")));
            if (Int(loot, "waystones") < Int(loot, "minWaystones")) o.Add("boss table: " + N(Get(loot, "waystones")) + " waystone(s) of the run's tier, the config guarantees " + N(Get(loot, "minWaystones")));
            return o;
        }

        // ------------------------------------------------------------------------------------ rifts
        /// <summary>The wrong facts of one `!tester riftrun layout` answer (a real rift run opened as a player does).</summary>
        public static List<string> RiftLayoutProblems(Dictionary<string, object> a)
        {
            var o = new List<string>();
            if (Err(a).Length > 0) o.Add(Cut(Err(a), 80));
            var kinds = Strings(a, "kinds");
            if (!kinds.Contains(Str(a, "kind"))) o.Add(Str(a, "theme") + " has the layout kind " + Str(a, "kind") + ", its config allows " + string.Join("/", kinds));
            var counts = Get(a, "floorCounts") as List<object> ?? new List<object>();
            if (!counts.Any(c => c is double x && Has(a, "floors") && Get(a, "floors") is double f && Math.Abs(x - f) < 0.5)) o.Add(Str(a, "theme") + " has " + N(Get(a, "floors")) + " floor(s), its config allows [" + string.Join(", ", counts.Select(N)) + "]");
            if (N(Get(a, "band")) != N(Get(a, "bandExpected")) && !(Get(a, "readyOfBand") is double rb && rb == 0)) o.Add("tier " + N(Get(a, "tier")) + " made a band " + N(Get(a, "band")) + " layout, the config says band " + N(Get(a, "bandExpected")));
            var lim = Obj(a, "limits");
            long w = Int(a, "walkable");
            if (lim.Count > 0 && !(Int(lim, "walkableMin") <= w && w <= (Has(lim, "walkableMax") ? Int(lim, "walkableMax") : long.MaxValue)))
                o.Add(w + " walkable tiles, the band holds " + N(Get(lim, "walkableMin")) + " to " + N(Get(lim, "walkableMax")));
            if (!(Int(a, "route") > 0)) o.Add("no walking route from the arrival to the guardian (" + N(Get(a, "route")) + ")");
            foreach (var (key, what) in new[] { ("startWalk", "the arrival"), ("bossWalk", "the guardian's spot"), ("mouthWalk", "the arena's mouth"), ("playerWalk", "the bot after entering") })
                if (!True(a, key)) o.Add(what + " is not a walkable cell of the layout");
            var s = Obj(a, "sample");
            if (Int(s, "bare") != 0 || Int(s, "blocked") != 0) o.Add("of " + N(Get(s, "n")) + " walkable cells sampled " + N(Get(s, "bare")) + " have no ground and " + N(Get(s, "blocked")) + " block");
            var after = Obj(a, "after");
            if (True(after, "inRun") || False(after, "slotFree")) o.Add("the run did not close (bot inside: " + N(Get(after, "inRun")) + ", slot free: " + N(Get(after, "slotFree")) + ")");
            return o;
        }

        // ------------------------------------------------------------------------------------ uniques and dual wield
        /// <summary>The wrong facts of one `!tester unique` answer: the worn unique's passive is active and the hit after it is worn lost `m` times the health of the hit before (within UniqueTolerance).</summary>
        public static List<string> UniqueProblems(Dictionary<string, object> u)
        {
            var o = new List<string>();
            string fam = Str(u, "family");
            var active = Strings(u, "active");
            if (!active.Contains(fam))
            {
                o.Add("a worn " + fam + " unique (item " + N(Get(u, "id")) + ") leaves its passive asleep (active: " + (active.Count > 0 ? string.Join(", ", active) : "none") + ")");
                return o;
            }
            if (!Has(u, "m")) { o.Add("a hit with the " + fam + " unique worn never reached the passive's damage rule"); return o; }
            long before = Int(u, "lostBefore"), after = Int(u, "lostAfter");
            double m = Num(u, "m");
            if (before > 0)
            {
                double got = after / (double)before;
                if (Math.Abs(got / m - 1) > UniqueTolerance) o.Add("with the " + fam + " unique worn a hit took x" + got.ToString("0.000", CultureInfo.InvariantCulture) + " of the health, its rule says x" + m.ToString("0.000", CultureInfo.InvariantCulture));
            }
            return o;
        }

        /// <summary>The wrong facts of one `!tester fists` / `!tester blades` answer. able: both worn (codes 0) and every melee hit of the main hand is followed by an off-hand strike.
        /// Not able: the fist weapon, or the dagger in the shield hand, is refused.</summary>
        public static List<string> DualProblems(Dictionary<string, object> f, string kind)
        {
            var o = new List<string>();
            string what = kind == "fists" ? "fist weapon" : "dagger";
            if (!True(f, "able"))
            {
                if (kind == "fists" && Has(f, "left") && Int(f, "left") == 0) o.Add("a class outside the Monk line could wear a fist weapon");
                if (kind == "blades" && Has(f, "right") && Int(f, "right") == 0) o.Add("a class that does not dual wield could hold a dagger in the shield hand");
                return o;
            }
            if (Int(f, "left", -1) != 0 || Int(f, "right", -1) != 0)
            {
                o.Add("could not wear a " + what + " in each hand (weapon hand code " + N(Get(f, "left")) + ", shield hand code " + N(Get(f, "right")) + ")");
                return o;
            }
            long melee = Int(f, "melee"), off = Int(f, "off");
            if (melee == 0) return o;
            if (off == 0) { o.Add(melee + " melee hits with a " + what + " in each hand and no off-hand strike"); return o; }
            if (off < melee - 1 || off > melee) o.Add(melee + " melee hits but " + off + " off-hand strikes (one each)");
            return o;
        }

        // ------------------------------------------------------------------------------------ cursed chest
        /// <summary>The wrong facts of the cursed chest legs: spawned idle, running after use with a horde that made monsters, gone after abort. `use` and `state` are the answers after the use and 3 s later, `abort` the one after the abort.</summary>
        public static List<string> ChestProblems(Dictionary<string, object> spawn, Dictionary<string, object> use, Dictionary<string, object> state, Dictionary<string, object> abort)
        {
            var o = new List<string>();
            if (Str(spawn, "state") != "idle") o.Add("spawned chest is '" + Str(spawn, "state") + "', expected idle");
            string us = Str(use, "state");
            if (use == null || (us != "running" && us != "idle")) o.Add("after use the chest is '" + us + "'");
            if (state != null && Str(state, "state") == "running" && Int(state, "monsters") < 1 && Int(state, "horde") > 0 && (Has(state, "made") ? Int(state, "made") : 0) < 1)
                o.Add("horde " + N(Get(state, "horde")) + " came with no monster");
            if (abort != null)
            {
                string zs = Str(abort, "state");
                if ((zs != "none" && zs != "gone") || Int(abort, "left") > 0) o.Add("after abort the chest is still '" + zs + "' (left " + N(Get(abort, "left")) + ")");
            }
            return o;
        }

        // ------------------------------------------------------------------------------------ spell quest
        /// <summary>The wrong facts of the quest spell a bot learned, held against what the Unity client knows: the spell list the server sent (by name: its level, whether the class may cast it) and the class's
        /// Auto setup data (a preset, the extras or the ultimate; a buff of the timers list, which Auto setup keeps up and never casts in a rotation). Null when the spell is not in the list at all.</summary>
        public static List<string> QuestSpellProblems(Spell spell, int level, bool openToClass, RotClass row, Func<int, bool> isTimerBuff)
        {
            if (spell == null) return null;
            var o = new List<string>();
            if (!openToClass) o.Add(spell.Name + " (" + spell.Id + ") is not open to the class");
            if (spell.Level > level) o.Add(spell.Name + " (" + spell.Id + ") needs level " + spell.Level);
            if (row != null)
            {
                var ids = new HashSet<int>(row.Presets.SelectMany(p => p.Spells));
                foreach (int e in row.Extras) ids.Add(e);
                if (row.Ultimate != 0) ids.Add(row.Ultimate);
                bool timer = isTimerBuff != null && isTimerBuff(spell.Id);
                if (!timer && !ids.Contains(spell.Id)) o.Add(spell.Name + " (" + spell.Id + ") is in no preset or extras of the Auto setup of " + row.Name + " and no timer buff of it");
            }
            return o;
        }

        /// <summary>Auto setup (O186): every spell of the class's preset at the level must be in the server's spell list and castable by the character (the list's own status Ready: class, level, learned).
        /// `statusOf` gives the spell for an id or null. Null when the class has no rotation row.</summary>
        public static List<string> AutoSetupProblems(RotClass row, int level, Func<int, Spell> spellOf, Func<Spell, SpellStatus> statusOf)
        {
            if (row == null) return null;
            var o = new List<string>();
            RotPreset best = null;
            foreach (var p in row.Presets) if (p.Level <= level) best = p;
            if (best == null) return o;
            foreach (int id in best.Spells)
            {
                var s = spellOf(id);
                if (s == null) { o.Add("spell " + id + " is not on the server"); continue; }
                var st = statusOf(s);
                if (st == SpellStatus.Vocation) o.Add(s.Name + " (" + id + ") is not open to " + row.Name);
                else if (st == SpellStatus.Level) o.Add(s.Name + " (" + id + ") needs level " + s.Level);
                else if (st == SpellStatus.Learn) o.Add(s.Name + " (" + id + ") is not learned");
                else if (st == SpellStatus.Quest) o.Add(s.Name + " (" + id + ") needs its quest");
            }
            return o;
        }
    }
}
