// Phase 7, track Z: gaps of the gameplay system rows (Core/Phase7Z*.cs): Auto Target reach, profession rows of the Skills window, Go to NPC tips, locked rows of the outfit window,
// Codex links and texts in pt-BR, the gem guide, the task tracker, the daily login order, DPS meter icons, spell support pips and drops, loadout action bar profiles,
// price charts and price history, bounty and dungeon outfits, safe exit flags, the read-only inspect tree, charm item drops.
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Chaos.Core.Tests
{
    static class Phase7ZTests
    {
        static object J(string json) => Json.TryParse(json);

        public static void Run(Action<bool, string> check)
        {
            Loc.Set("en");
            AutoTargetChecks(check);
            CraftSkillChecks(check);
            TravelChecks(check);
            WardrobeChecks(check);
            CodexLinkChecks(check);
            CodexTextChecks(check);
            GemGuideChecks(check);
            TrackerChecks(check);
            DailyChecks(check);
            DpsChecks(check);
            SupportChecks(check);
            LoadoutChecks(check);
            ChartChecks(check);
            MarketPriceChecks(check);
            OutfitChecks(check);
            PvpFlagChecks(check);
            InspectTreeChecks(check);
            CharmDropChecks(check);
            Loc.Set("en");
        }

        // ------------------------------------------------------------------------------------ game_autotarget
        sealed class Host : IHelperHost, IHelperHostExt
        {
            public double Now { get; set; }
            public int Health { get; set; } = 100;
            public int MaxHealth { get; set; } = 100;
            public int Mana { get; set; } = 500;
            public int MaxMana { get; set; } = 500;
            public int Level { get; set; } = 100;
            public Pos Position { get; set; } = new Pos(100, 100, 7);
            public Dir Facing { get; set; } = Dir.North;
            public bool InProtectionZone { get; set; }
            public bool Hasted { get; set; }
            public uint AttackTarget { get; set; }
            public bool Following { get; set; }
            public double MsSinceLastRead { get; set; }
            public List<HelperCreature> Mon = new List<HelperCreature>();
            public List<string> Log = new List<string>();
            public int Vocation { get; set; } = 4;
            public bool Hungry => false;
            public IList<HelperPlayer> Players() { return new List<HelperPlayer>(); }
            public bool UseOnCreature(int clientId, uint creature) { return false; }
            public bool UseItem(int clientId) { return false; }
            public IList<string> OwnSummons() { return new List<string>(); }
            public IList<HelperCreature> Monsters() { return Mon; }
            public void Say(string words) { }
            public void Attack(uint id) { AttackTarget = id; Log.Add("attack " + id); }
            public void CancelAttack() { AttackTarget = 0; }
            public void Turn(Dir d) { Facing = d; }
            public int ItemCount(int id) { return 0; }
            public void UseOnSelf(int id) { }
        }

        static void AutoTargetChecks(Action<bool, string> check)
        {
            var from = new Pos(100, 100, 7);
            // ReachCache: a path answer is kept, the budget of a tick is shared
            int searches = 0;
            var rc = new ReachCache { PathBudget = 2, Steps = (a, b) => { searches++; return b.X == 103 ? -1 : 4; }, Sight = (a, b) => true };
            rc.NewTick(0);
            var near = rc.Query(1, from, new Pos(102, 100, 7), false, 0, out double d1);
            var wall = rc.Query(2, from, new Pos(103, 100, 7), false, 0, out _);
            var third = rc.Query(3, from, new Pos(101, 100, 7), false, 0, out _);
            check(near == true && d1 == 4 && wall == false && third == null && searches == 2, "reach: two searches a tick, the third monster is not known yet");
            check(rc.Query(1, from, new Pos(102, 100, 7), false, 300, out _) == true && searches == 2, "reach: a fresh answer is reused");
            rc.NewTick(100);
            check(rc.Query(3, from, new Pos(101, 100, 7), false, 100, out _) == true && searches == 3, "reach: the next tick answers the third");
            check(rc.Query(1, from, new Pos(102, 100, 7), false, 5000, out _) == true && searches == 4, "reach: an old answer is searched again");
            check(rc.Query(9, from, new Pos(102, 100, 8), false, 5000, out _) == false, "reach: another floor is not reachable");
            var shoot = new ReachCache { Steps = (a, b) => -1, Sight = (a, b) => true };
            shoot.NewTick(0);
            check(shoot.Query(1, from, new Pos(105, 100, 7), true, 0, out double sd) == true && sd == 5, "reach: a ranged class shoots over a gap (the straight distance)");
            check(shoot.Query(2, from, new Pos(105, 100, 7), false, 0, out _) == false, "reach: a melee class does not");
            check(SightLine.Clear(from, new Pos(105, 100, 7), p => false) && !SightLine.Clear(from, new Pos(105, 100, 7), p => p.X == 103) && SightLine.Clear(from, new Pos(101, 100, 7), p => true) && !SightLine.Clear(from, new Pos(105, 100, 8), p => false), "sight: a blocking tile between stops a shot, the end tiles do not count");

            // the engine: only reachable, priority classes
            var host = new Host();
            host.Mon.Add(new HelperCreature(1, new Pos(101, 100, 7), 100));   // the nearest, behind a wall
            host.Mon.Add(new HelperCreature(2, new Pos(104, 100, 7), 100));
            var book = new SpellBook(new ExtOpcodes());
            var e = new HelperEngine(book, host);
            e.Config.Enabled = true; e.Config.AutoTarget = true; e.Config.AutoTargetMode = 6;
            e.Reach = new ReachCache { Steps = (a, b) => b.X == 101 ? -1 : 4, Sight = (a, b) => false };
            for (double t = 1000; t < 1600; t += 50) { host.Now = t; e.Tick(); }
            check(host.Log.Count > 0 && host.Log[0] == "attack 2", "auto target: the nearest monster behind a wall is skipped: " + string.Join(",", host.Log));
            e.Config.AutoTargetReachable = false;
            e.LockedTarget = 0; host.AttackTarget = 0; host.Log.Clear();
            for (double t = 2000; t < 2600; t += 50) { host.Now = t; e.Tick(); }
            check(host.Log.Count > 0 && host.Log[0] == "attack 1", "auto target: with Only reachable off the nearest is attacked: " + string.Join(",", host.Log));

            host.Log.Clear(); host.AttackTarget = 0; e.LockedTarget = 0;
            e.Config.AutoTargetReachable = true;
            host.Mon.Clear();
            host.Mon.Add(new HelperCreature(5, new Pos(101, 101, 7), 100));
            host.Mon.Add(new HelperCreature(6, new Pos(104, 101, 7), 100));   // a boss, farther
            e.Reach = new ReachCache { Steps = (a, b) => 3, Sight = (a, b) => false };
            e.RankOf = id => id == 6 ? AutoTargetCore.RankBoss : AutoTargetCore.RankNormal;
            for (double t = 3000; t < 3600; t += 50) { host.Now = t; e.Tick(); }
            check(host.Log.Count > 0 && host.Log[0] == "attack 6", "auto target: Priority targets sends the character after the boss");
            e.Config.AutoTargetPriority = false;
            host.Log.Clear(); host.AttackTarget = 0; e.LockedTarget = 0;
            for (double t = 4000; t < 4600; t += 50) { host.Now = t; e.Tick(); }
            check(host.Log.Count > 0 && host.Log[0] == "attack 5", "auto target: with Priority targets off the nearest comes first");
            var cfg = HelperConfig.FromJson(new HelperConfig { AutoTargetPriority = false, AutoTargetReachable = false }.ToJson());
            check(!cfg.AutoTargetPriority && !cfg.AutoTargetReachable && HelperConfig.FromJson("{}").AutoTargetPriority && HelperConfig.FromJson("{}").AutoTargetReachable, "auto target: both options are saved and default to on");
        }

        // ------------------------------------------------------------------------------------ game_craftskills
        static void CraftSkillChecks(Action<bool, string> check)
        {
            var v = new SkillValue[7];
            check(!CraftSkillRows.Any(v), "craft skills: nothing is shown before the packet");
            v[2] = new SkillValue { Level = 15300, Base = 15000, Percent = 40 };
            v[0] = new SkillValue { Level = 20, Base = 20, Percent = 5 };
            check(CraftSkillRows.Any(v), "craft skills: shown once a skill has a value");
            var rows = CraftSkillRows.Build(v);
            check(rows.Count == 7 && rows[2].Name == "Mining" && rows[2].Value == "15.3k" && rows[2].Boosted && rows[2].Percent == 40, "craft skills: short level, boosted, percent");
            check(rows[2].Tip == "Mining: 15300 (base 15000)\n40% to the next level" && rows[0].Tip == "Crafting: 20\n5% to the next level" && !rows[0].Boosted, "craft skills: tooltips");
        }

        // ------------------------------------------------------------------------------------ game_npctravel
        static void TravelChecks(Action<bool, string> check)
        {
            foreach (string k in new[] { "stash", "pocketboss", "candlemarks", "gambler", "materials" }) check(NpcTravel.Valid(k) && NpcTravel.PanelNpc.ContainsKey(k), "go to npc: the panel key " + k + " is a travel key with an NPC");
            check(NpcTravel.PanelTip("stash") == "Takes you in front of Tavish Coldhand, the stash keeper, in the market of the teleport room. Not in combat; a short wait between two trips.", "go to npc: the tooltip of the stash panel");
            check(NpcTravel.PanelTip("materials").Contains("the Material Broker"), "go to npc: the broker");
            Loc.Set("pt-BR");
            check(NpcTravel.PanelTip("gambler").StartsWith("Leva você até a frente de Mordecai Ashwager"), "go to npc: pt-BR: " + NpcTravel.PanelTip("gambler"));
            Loc.Set("en");
        }

        // ------------------------------------------------------------------------------------ game_unlocks
        static void WardrobeChecks(Action<bool, string> check)
        {
            var cat = new List<WardrobeEntry>
            {
                new WardrobeEntry { Look = 128, Name = "Citizen", Source = "Starter" },
                new WardrobeEntry { Look = 300, Name = "Ember Knight", Source = "Reach level 100" },
                new WardrobeEntry { Look = 301, Name = "Ash Mage" },
            };
            var stock = new List<KeyValuePair<int, string>> { new KeyValuePair<int, string>(128, "Citizen") };
            var rows = WardrobeView.Display("outfit", stock, cat, false);
            check(rows.Count == 3 && !rows[0].Locked && rows[1].Locked && rows[1].Name == "Ember Knight" && rows[2].Locked, "wardrobe: owned rows first, then the catalogue's locked ones");
            check(rows[0].How == "Starter" && rows[0].Tip == "Unlocked.\nStarter", "wardrobe: an owned row names its source");
            check(rows[1].Tip == "Not unlocked yet.\nHow to get it: Reach level 100" && rows[2].Tip == "Not unlocked yet.", "wardrobe: a locked row says how to get it");
            check(WardrobeView.Display("outfit", stock, cat, true).Count == 1, "wardrobe: Only what I own drops the locked rows");
            WardrobeView.Count(rows, out int have, out int all);
            check(have == 1 && all == 3, "wardrobe: the have / all count");
            var shaders = WardrobeView.Display("shader", new List<KeyValuePair<int, string>> { new KeyValuePair<int, string>(0, "Cinder") },
                new List<WardrobeEntry> { new WardrobeEntry { Name = "Cinder" }, new WardrobeEntry { Name = "Frost", Source = "Season pass" } }, false);
            check(shaders.Count == 2 && shaders[1].Locked && shaders[1].Name == "Frost", "wardrobe: shaders are keyed by name");
            check(WardrobeView.Display("mount", null, null, false).Count == 0, "wardrobe: no lists, no rows");
        }

        // ------------------------------------------------------------------------------------ game_itemfinder, game_crafting
        static CodexData SmallCodex()
        {
            return CodexData.Load("{\"rarities\":[],\"tiers\":{\"levels\":[1],\"weights\":[1],\"window\":5},\"shared\":{},\"tabs\":[{\"id\":\"items\",\"name\":\"Items\",\"filters\":[],\"entries\":["
                + "{\"id\":\"item:a\",\"name\":\"A\",\"items\":[100,101]},{\"id\":\"item:b\",\"name\":\"B\",\"items\":[101,102]},{\"id\":\"mod:fire\",\"name\":\"Fire\"},{\"id\":\"power:rage\",\"name\":\"Rage\"}]}]}");
        }

        static void CodexLinkChecks(Action<bool, string> check)
        {
            var d = SmallCodex();
            check(d.Ready && d.Tabs[0].Entries.Count == 4, "codex links: the small data loads");
            var idx = CodexLinks.ItemIndex(d);
            check(idx[100] == "item:a" && idx[101] == "item:a" && idx[102] == "item:b", "codex links: a server id maps to the first entry that lists it");
            check(CodexLinks.ForItem(d, 102) == "item:b" && CodexLinks.ForItem(d, 5) == null && CodexLinks.ForItem(d, 0) == null && CodexLinks.ForItem(null, 100) == null, "codex links: unknown ids and no data give no link");
            check(CodexLinks.ModTip(d, "fire", "prefix") == "Right-click: its page in the Codex." && CodexLinks.ModTip(d, "chaos_mod_rage", "") == "Right-click: its page in the Codex." && CodexLinks.ModTip(d, "ice", "") == null, "codex links: a modifier row with a page gets the tip");
        }

        // ------------------------------------------------------------------------------------ game_codex
        static void CodexTextChecks(Action<bool, string> check)
        {
            var k1 = CodexText.Key("Cap: at most 15% from all equipped items together.", out var n1);
            check(k1 == "Cap: at most %s%% from all equipped items together." && string.Join("|", n1) == "15", "codex text: key with a number and a percent");
            var k2 = CodexText.Key("Salvage gives 4 rune shards and 78 Conquest Tokens. Level 40.", out var n2);
            check(k2 == "Salvage gives %s rune shards and %s Conquest Tokens. Level %s." && string.Join("|", n2) == "4|78|40", "codex text: the dot of a sentence stays");
            var k3 = CodexText.Key("x0.75, +10-14% (T8)", out var n3);
            check(k3 == "x%s, +%s-%s%% (T%s)" && string.Join("|", n3) == "0.75|10|14|8", "codex text: decimals, ranges and tiers");
            check(CodexText.Fill("a %s b %s 100%%", new[] { "1", "2" }) == "a 1 b 2 100%", "codex text: fill");
            foreach (string s in new[] { "Cap: at most 15% from all equipped items together.", "Orb of Awakening", "100% sure", "" })
                check(CodexText.T(s) == s && CodexText.Sub(s) == s, "codex text: English unchanged: " + s);
            check(CodexText.T(null) == null, "codex text: null");
            Loc.Set("pt-BR");
            check(CodexText.T("Cap: at most 15% from all equipped items together.") == "Limite: no máximo 15% de todos os itens equipados juntos.", "codex text: pt cap: " + CodexText.T("Cap: at most 15% from all equipped items together."));
            check(CodexText.T("Armor 16") == "Armadura 16", "codex text: stat with a number");
            check(CodexText.T("A unique keeps its stats: no orb changes it. Salvage gives 4 rune shards and 78 Conquest Tokens.") == "Um unique mantém seus atributos: nenhum orbe o muda. O salvage dá 4 rune shards e 78 Conquest Tokens.", "codex text: two numbers");
            check(CodexText.T("Orb of Awakening") == "Orb of Awakening" && CodexText.T("Some paragraph nobody translated, 5 times.") == "Some paragraph nobody translated, 5 times.", "codex text: a name and an untranslated text stay English");
            check(CodexText.Sub("Suffix, any gear. +2% (T1) to +10-14% (T8)") == "Sufixo, qualquer equipamento. +2% (T1) a +10-14% (T8)", "codex text: list line of a modifier: " + CodexText.Sub("Suffix, any gear. +2% (T1) to +10-14% (T8)"));
            check(CodexText.Sub("Shield, level 40. Defense 36, Health on Hit +6, Physical Penetration +18%") == "Escudo, nível 40. Defesa 36, Vida por golpe +6, Penetração física +18%", "codex text: list line of a unique");
            check(CodexText.Sub("Ring, level 120. Armor 6, Life Leech: chance +10%, amount +8%") == "Anel, nível 120. Armadura 6, Roubo de vida: chance +10%, quantidade +8%", "codex text: a stat with its own comma stays one part");
            check(CodexText.Sub("Legendary power. Prefix, Weapon, Jewel. 3-5% (T1) to 30-45% (T8)") == "Poder lendário. Prefixo, Arma, joia. 3-5% (T1) a 30-45% (T8)", "codex text: three sentences");
            check(CodexTextData.Table.Count > 600, "codex text: the table has its entries: " + CodexTextData.Table.Count);
            Loc.Set("en");
            // the real data: every tab, filter option and heading of the Codex has an entry, nearly every paragraph too
            string json = LoadCodexJson();
            if (json != null)
            {
                Loc.Set("pt-BR");
                var data = CodexData.Load(json);
                var missing = new List<string>();
                int prose = 0, proseOk = 0;
                Action<string, string> need = (what, text) => { if (!string.IsNullOrEmpty(text) && CodexText.T(text) == text && Loc.T(text) == text && !CodexTextData.Table.ContainsKey(CodexText.Key(text, out _)) && text != "The Ashen Chronicle" && text != "Item" && text != "Item level") missing.Add(what + ": " + text); };
                foreach (var tab in data.Tabs)
                {
                    need("tab", tab.Name);
                    foreach (var f in tab.Filters) { need("filter", f.Label); foreach (var o in f.Options) need("option", o.Text); }
                    foreach (var e in tab.Entries)
                        foreach (var s in e.Sections)
                        {
                            if (!string.IsNullOrEmpty(s.Ref)) continue;
                            need("heading", s.H);
                            if (tab.Name != "Lore") foreach (var p in s.Paragraphs) { prose++; if (CodexTextData.Table.ContainsKey(CodexText.Key(p, out _))) proseOk++; }
                        }
                }
                // a short label the main client's table keeps as it is (Rift, Keys, Quality ...) has no entry here: those are English in both clients
                var distinct = new HashSet<string>(missing.Select(m => m.Substring(m.IndexOf(": ", StringComparison.Ordinal) + 2)));
                check(distinct.Count <= 12 && distinct.All(t => t.Split(' ').Length <= 4), "codex text: every tab, filter, option and heading has a pt-BR entry except short names (left: " + string.Join(" / ", distinct) + ")");
                check(prose > 500 && proseOk >= prose * 0.85, "codex text: paragraphs translated " + proseOk + " of " + prose);
                Loc.Set("en");
            }
        }

        static string LoadCodexJson()
        {
            string dir = AppContext.BaseDirectory;
            for (int i = 0; i < 10 && dir != null; i++, dir = System.IO.Path.GetDirectoryName(dir))
            {
                string p = System.IO.Path.Combine(dir, "unity", "Client", "Assets", "Chaos", "Resources", "Codex.json");
                if (System.IO.File.Exists(p)) return System.IO.File.ReadAllText(p);
            }
            return null;
        }

        // ------------------------------------------------------------------------------------ game_crafting
        static void GemGuideChecks(Action<bool, string> check)
        {
            var guide = J("{\"tiers\":[\"Chipped\",\"Flawed\",\"Perfect\"],\"removeCost\":[1000,5000,25000],\"socketOrb\":\"Orb of Sockets\",\"combine\":3,"
                + "\"effects\":{\"fire\":{\"label\":\"Fire damage\",\"fmt\":\"pct\",\"cap\":30},\"hp\":{\"label\":\"Health\",\"fmt\":\"flat\"},\"leech\":{\"label\":\"Life leech\",\"label2\":\"Mana leech\",\"fmt\":\"pair\",\"cap\":12}},"
                + "\"types\":[{\"name\":\"Ruby\",\"color\":\"#e03a1e\",\"look\":[1,2,3],\"weapon\":{\"effect\":\"fire\",\"values\":[2,4,6]},\"armour\":{\"effect\":\"hp\",\"values\":[20,45,80]},\"jewel\":{\"effect\":\"leech\",\"values\":[1,2,3.5],\"values2\":[1,1,2]}}]}");
            var rows = GemGuide.Rows(guide);
            check(rows.Count == 1 && rows[0].Name == "Ruby" && rows[0].Look == 3 && rows[0].Color == "#e03a1e" && rows[0].Groups.Count == 3, "gem guide: one row per gem with its three groups");
            check(GemGuide.GroupLine(rows[0].Groups[0]) == "Weapon: Fire damage +2 / 4 / 6%  (limit 30%)", "gem guide: percent bonus with its limit: " + GemGuide.GroupLine(rows[0].Groups[0]));
            check(GemGuide.GroupLine(rows[0].Groups[1]) == "Armour: Health +20 / 45 / 80", "gem guide: flat bonus, no limit: " + GemGuide.GroupLine(rows[0].Groups[1]));
            check(GemGuide.GroupLine(rows[0].Groups[2]) == "Jewellery: Life leech +1 / 2 / 3.5%, Mana leech +1 / 1 / 2%  (limit 12%)", "gem guide: a pair of bonuses: " + GemGuide.GroupLine(rows[0].Groups[2]));
            var basics = GemGuide.Basics(guide);
            check(basics.Count == 6 && basics[0].Key == "What a gem does" && basics[3].Value == "Three gems of the same kind and quality become one of the next quality: use the stack, then click the same stack. Qualities: Chipped, Flawed, Perfect.", "gem guide: six paragraphs: " + basics[3].Value);
            check(basics[4].Value.Contains("(1,000 / 5,000 / 25,000 by quality)") && basics[2].Value.Contains("An Orb of Sockets rolls"), "gem guide: costs and the socket orb");
            check(GemGuide.Rows(null).Count == 0 && GemGuide.Number(12345.9) == "12,345", "gem guide: no message, no rows");
        }

        // ------------------------------------------------------------------------------------ game_bestiary
        static void TrackerChecks(Action<bool, string> check)
        {
            var t = new TaskTrackerState();
            check(!t.Visible(0) && t.Visible(2), "tracker: an empty tracker stays out of the way");
            check(t.Title(3) == "Tasks" && ((Func<string>)(() => { t.Fold(); return t.Title(3); }))() == "Tasks (3) +", "tracker: the title folds to a count");
            t.Fold();
            check(!t.Toggle(2) == false && !t.Enabled, "tracker: the menu entry hides a shown tracker");
            check(t.Toggle(0) == false && t.Enabled && t.Opened && t.Visible(0), "tracker: the menu entry shows an empty one with its hint");
            var rows = TaskTrackerState.Rows(new object[] { J("{\"k\":\"bounty\",\"label\":\"Wolf\",\"p\":2,\"r\":5}"), "junk", J("{\"k\":\"task\",\"label\":\"Rat\",\"p\":1,\"r\":4}") });
            check(rows.Count == 2 && TaskTrackerState.Kind(rows[0]) == "B" && TaskTrackerState.Kind(rows[1]) == "T" && TaskTrackerState.KindColor(rows[0]) == "#e03a1e" && TaskTrackerState.BarColor(rows[1]) == "#a3844b", "tracker: kind letters and colours");
            check(TopMenu.Categories.Any(c => c.Entries.Any(e => e.Target == "act:killtasks")) && TopMenu.Categories.Any(c => c.Entries.Any(e => e.Target == "act:tracker")), "tracker: the Hunt menu has Kill Tasks and Task Tracker");
        }

        // ------------------------------------------------------------------------------------ game_daily
        static void DailyChecks(Action<bool, string> check)
        {
            check(DailyGate.ShouldWait(1, true, false) && DailyGate.ShouldWait(1, false, true) && !DailyGate.ShouldWait(1, false, false), "daily: a login window waits for a modal and the patch notes");
            check(!DailyGate.ShouldWait(0, true, true), "daily: opened by the player it shows at once");
            var a = new DailyAnchor();
            check(!a.Moved(new Pos(100, 100, 7), new Pos(101, 100, 7), true), "daily: no anchor, no close");
            a.Set(new Pos(100, 100, 7));
            check(!a.Moved(new Pos(100, 100, 7), new Pos(101, 100, 7), true) && !a.Moved(new Pos(101, 100, 7), new Pos(102, 100, 7), true) && !a.Moved(new Pos(102, 100, 7), new Pos(103, 100, 7), true), "daily: three tiles away is still near");
            check(a.Moved(new Pos(103, 100, 7), new Pos(104, 100, 7), true) && !a.Has, "daily: more than three tiles away closes it");
            a.Set(new Pos(100, 100, 7));
            check(!a.Moved(new Pos(100, 100, 7), new Pos(110, 100, 7), true) && a.Moved(new Pos(110, 100, 7), new Pos(111, 100, 7), false) == false, "daily: a jump moves the anchor, a closed window needs no close");
            check(!a.Moved(new Pos(111, 100, 7), new Pos(110, 100, 7), true), "daily: back at the new anchor");
            a.Set(new Pos(100, 100, 7));
            check(!a.Moved(new Pos(100, 100, 7), new Pos(100, 100, 6), true), "daily: a floor change is a jump");
        }

        // ------------------------------------------------------------------------------------ game_dpsmeter
        static void DpsChecks(Action<bool, string> check)
        {
            var spell = DpsIcons.Spec("s", "exori flam");
            check(spell.Kind == "spell" && spell.Words == "exori flam", "dps icons: a spell by its words");
            var rune = DpsIcons.Spec("r", 3155.0);
            check(rune.Kind == "item" && rune.ItemId == 3155, "dps icons: a rune by its item");
            check(DpsIcons.Spec("d", "burning").Kind == "buff" && DpsIcons.Spec("w", "sword").Kind == "own" && DpsIcons.Spec("w", "sword").Glyph == "S", "dps icons: a buff and one of our own");
            check(DpsIcons.Spec("c", null).Key == "monster" && DpsIcons.Spec("u", null).Key == "player" && DpsIcons.Spec("m", null).Key == "summon" && DpsIcons.Spec("d", null).Key == "dot" && DpsIcons.Spec("z", null).Key == "other", "dps icons: by the kind letter");
            DpsPanel.Resize(236, 200, 50, -300, out int w, out int h);
            check(w == 286 && h == DpsMath.MinH, "dps panel: the corner drag is kept inside the limits");
            DpsPanel.Resize(236, 200, 9999, 9999, out w, out h);
            check(w == DpsMath.MaxW && h == DpsMath.MaxH, "dps panel: and at the top");
            float x = -500, y = 900;
            DpsPanel.ClampPosition(ref x, ref y, 236, 200, 1280, 720);
            check(x == 24 - 236 && y == 720 - 24, "dps panel: a position keeps 24 px on the screen");
            var s = new DpsSettings { W = 300, H = 250, X = 12, Y = 40 };
            var back = DpsMath.Sanitize(Json.TryParse(s.ToJson()));
            check(back.W == 300 && back.H == 250 && back.X == 12 && back.Y == 40, "dps panel: position and size survive the settings");
        }

        // ------------------------------------------------------------------------------------ game_spellsupports
        static void SupportChecks(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var s = new SpellSupportsState(ext);
            s.Bar["7"] = J("[{\"name\":\"Rune of Force\",\"text\":\"+10% damage\",\"color\":\"#e03a1e\"},{\"name\":\"Rune of Calm\",\"text\":\"-5% mana\"}]");
            var colors = SupportPips.Colors(s, 7);
            check(colors.Count == 2 && colors[0] == "#e03a1e" && colors[1] == SupportPips.DefaultColor && SupportPips.Colors(s, 8).Count == 0 && SupportPips.Colors(null, 7).Count == 0, "pips: one colour per rune");
            check(SupportPips.Width(0) == 0 && SupportPips.Width(3) == 17, "pips: strip width");
            check(SupportPips.Tip(s, 7, "Exori") == "Exori\n\nSupports:\n  Rune of Force: +10% damage\n  Rune of Calm: -5% mana" && SupportPips.Tip(s, 8, "Exori") == "Exori", "pips: the tooltip lists the runes");
            var targets = new List<SocketTarget>
            {
                new SocketTarget { X = 100, Y = 100, W = 200, H = 66, Spell = 7, Slot = 1, Free = false },
                new SocketTarget { X = 100, Y = 170, W = 200, H = 66, Spell = 7, Slot = 2, Free = true },
                new SocketTarget { X = 100, Y = 240, W = 200, H = 66, Spell = 7, Slot = 3, Free = true },
            };
            check(SupportDrop.Hit(targets, 150, 120, 90, 300) == -1, "drop: a taken socket takes nothing");
            check(SupportDrop.Hit(targets, 150, 200, 90, 300) == 1 && SupportDrop.Hit(targets, 150, 260, 90, 300) == 2, "drop: a free socket under the pointer");
            check(SupportDrop.Hit(targets, 150, 260, 90, 250) == -1 && SupportDrop.Hit(targets, 50, 200, 90, 300) == -1, "drop: outside the view or beside the sockets");
        }

        // ------------------------------------------------------------------------------------ game_loadouts
        static void LoadoutChecks(Action<bool, string> check)
        {
            var store = new Dictionary<string, string>();
            var p = new HotbarProfiles(k => store.TryGetValue(k, out var v) ? v : "", (k, v) => store[k] = v);
            var bar = new string[12];
            for (int i = 0; i < 12; i++) bar[i] = i == 0 ? "exura" : i == 1 ? "item:3160:2" : "";
            check(p.ProfileOf("Ash", 2) == "" && p.Recall("Ash", 2, 12) == null, "loadout profile: none before a save");
            p.Remember("Ash", 2, bar);
            check(p.ProfileOf("Ash", 2) == "Loadout 2" && p.ProfileOf("ash", 2) == "Loadout 2" && p.ProfileOf("Ash", 3) == "" && p.ProfileOf("Bob", 2) == "", "loadout profile: per character and slot");
            var back = p.Recall("Ash", 2, 12);
            check(back != null && back.Length == 12 && back[0] == "exura" && back[1] == "item:3160:2" && back[5] == "", "loadout profile: the bar comes back as it was");
            bar[0] = "exori";
            p.Remember("Ash", 2, bar);
            check(p.Recall("Ash", 2, 12)[0] == "exori", "loadout profile: a later save replaces it");
            p.Forget("Ash", 2);
            check(p.ProfileOf("Ash", 2) == "" && p.Recall("Ash", 2, 12) == null, "loadout profile: a deleted slot loses it");
            p.Remember("Ash", 0, bar);
            check(p.ProfileOf("Ash", 0) == "", "loadout profile: slot 0 is not a slot");
            check(HotbarProfiles.Unpack("a" + HotbarProfiles.Sep + "b", 4).SequenceEqual(new[] { "a", "b", "", "" }), "loadout profile: unpack pads to the bar size");
        }

        // ------------------------------------------------------------------------------------ game_orbexchange, game_market
        static void ChartChecks(Action<bool, string> check)
        {
            var pts = PriceChart.Points(J("[{\"h\":5,\"p\":4500,\"v\":2},{\"h\":1,\"p\":5000,\"v\":3},{\"h\":0,\"p\":5500,\"v\":1}]"));
            check(pts.Count == 3 && pts[0].Ago == 5 && pts[2].Price == 5500, "chart: points");
            var rects = PriceChart.Rects(pts, 24, 240, 80);
            check(rects.Count(r => r.Line) == 5 && rects.Count(r => !r.Line) == 3, "chart: a step line (a bar and a riser) and the volume bars");
            check(rects.Where(r => !r.Line).All(r => r.Y + r.H == 80 && r.H <= 20), "chart: volume bars sit at the bottom, at most a quarter of the height");
            check(rects[0].X == (int)Math.Floor((24 - 1 - 5) * 10.0), "chart: x by hours ago");
            check(PriceChart.Rects(new List<ChartPoint>(), 24, 240, 80).Count == 0 && PriceChart.Rects(pts, 24, 0, 80).Count == 0, "chart: no points, no box, no chart");
            check(PriceChart.Rects(new List<ChartPoint> { new ChartPoint(0, 100, 1) }, 24, 240, 80).Count == 2, "chart: one flat point is a line and a bar");
            check(PriceChart.Scale(pts, out string hi, out string lo) && hi == "5.5k" && lo == "4.5k" && !PriceChart.Scale(null, out _, out _), "chart: scale texts");
            var row = new SocialRow { Kind = RowKind.Chart };
            check(row.Units == 30 && new RowList().Chart("x", pts, 30).Kind == RowKind.Chart, "chart: the social row kind");
        }

        static void MarketPriceChecks(Action<bool, string> check)
        {
            var stats = J("{\"typical\":1500,\"basis\":\"30d\",\"n30\":12,\"n7\":4,\"days\":30,\"last\":1400,\"lastAgo\":7200,\"median7\":1450,\"units7\":6,\"min7\":1000,\"max7\":2000,\"lo\":1200,\"hi\":1800}");
            var lines = MarketPrices.Stats(stats, "gold");
            check(lines.Count == 4 && lines[0].Text == "Typical price: 1,500 gold each (daily medians of 12 sales, 30 days)" && lines[0].Tone == "gold", "prices: typical line: " + lines[0].Text);
            check(lines[1].Text == "Last sale: 1,400 gold, 2h ago" && lines[2].Text == "7 days: median 1,450, 4 sales (6 units)" && lines[3].Text == "Usual range: 1,200 - 1,800 (lowest 1,000, highest 2,000)", "prices: last sale, 7 days and range");
            check(MarketPrices.Stats(null, "gold")[0].Text == "No sales of this item yet.", "prices: no sales");
            check(MarketPrices.Typical(J("{\"n7\":3,\"n30\":3,\"need\":5}"), "gold").Text == "Typical price: not enough sales yet (3 of 5).", "prices: not enough sales");
            check(MarketPrices.Currency(J("{\"gold\":{\"n30\":0},\"coins\":{\"n30\":2}}"), "gold") == "coins" && MarketPrices.Currency(J("{\"gold\":{\"n30\":2},\"coins\":{\"n30\":2}}"), "coins") == "coins" && MarketPrices.Currency(J("{}"), "coins") == "gold", "prices: the currency that has sales comes first");
            check(MarketPrices.Suggest(1234567, 1, 100) == 1230000 && MarketPrices.Suggest(1500, 3, 0) == 4500 && MarketPrices.Suggest(5, 1, 100) == 100 && MarketPrices.Suggest(0, 1, 0) == -1, "prices: the suggested price: 3 digits, times the count, never under the minimum");
            check(MarketPrices.SellWarning(100, 1, 1500, 0.5, 2.0, "gold").Text == "Far below the typical price: 7% of 1,500 gold each. Is that what you want?", "prices: far below warns");
            check(MarketPrices.SellWarning(4000, 1, 1500, 0.5, 2.0, "gold").Text == "Far above the typical price: 267% of 1,500 gold each; it may not sell." && MarketPrices.SellWarning(1400, 1, 1500, 0.5, 2.0, "gold") == null && MarketPrices.SellWarning(0, 1, 1500, 0.5, 2.0, "gold") == null && MarketPrices.SellWarning(100, 1, 0, 0.5, 2.0, "gold") == null, "prices: far above warns, near or unknown does not");
            var low = MarketPrices.RowMark(J("{\"pm\":\"low\",\"typ\":1000,\"tcur\":\"gold\",\"gold\":2400,\"count\":3}"));
            check(low != null && low.Text == "20% under typical" && low.Tone == "good", "prices: a row under the typical price: " + low?.Text);
            check(MarketPrices.RowMark(J("{\"pm\":\"high\",\"typ\":1000,\"tcur\":\"coins\",\"coins\":1500}")).Text == "50% over typical" && MarketPrices.RowMark(J("{\"typ\":1000}")) == null, "prices: over the typical price, no mark");
            check(MarketPrices.RowTypical(J("{\"typ\":1000,\"tcur\":\"coins\"}")) == "Typical price: 1,000 Chaos Coins each" && MarketPrices.RowTypical(J("{}")) == null, "prices: the typical price in a tooltip");
            check(MarketPrices.KeyText(3, "iLvl 60-69").EndsWith(" - iLvl 60-69") && MarketPrices.KeyText(0, "") == "", "prices: the key text");
            // the panel: a Prices click, the answer, and the sell hint
            var ext = new ExtOpcodes();
            var sent = new List<string>();
            ext.Transmit = pk => sent.Add(Encoding.UTF8.GetString(pk, 4, pk.Length - 4));
            var m = new MarketPanel(ext);
            m.ShowPrices(J("{\"id\":55,\"name\":\"Cinder Blade\"}"));
            check(sent.Count > 0 && sent[sent.Count - 1].Contains("\"action\":\"prices\"") && sent[sent.Count - 1].Contains("\"id\":55"), "market panel: a click asks for the prices of the offer");
            ext.Receive(221, ExtOpcodes.ToWire("{\"action\":\"prices\",\"data\":{\"seq\":1,\"gold\":{\"n30\":5,\"n7\":5,\"typical\":1500,\"days\":30,\"points\":[{\"h\":1,\"p\":1400,\"v\":2},{\"h\":0,\"p\":1500,\"v\":3}]},\"coins\":{\"n30\":0}}}"));
            check(m.PriceData != null && m.PriceCur == "gold", "market panel: the answer is kept");
            m.SelectTab("browse");
            var rowsList = m.BuildRows();
            check(rowsList.Any(r => r.Kind == RowKind.Chart && r.Points.Count == 2 && r.Units == 30) && rowsList.Any(r => r.Kind == RowKind.Section && r.Text == "Price history: Cinder Blade"), "market panel: the price block has its chart");
            m.ClosePrices();
            check(m.PriceOffer == null && !m.BuildRows().Any(r => r.Kind == RowKind.Chart), "market panel: Close removes it");
            // the sell form
            ext.Receive(221, ExtOpcodes.ToWire("{\"action\":\"meta\",\"data\":{\"price\":{\"gold\":{\"min\":10},\"coins\":{\"min\":1}},\"durations\":[1,3,7]}}"));
            var item = J("{\"ref\":\"s1.0\",\"sid\":4000,\"item\":3100,\"count\":3,\"name\":\"Cinder Blade\",\"rarity\":3,\"ilvl\":60,\"stack\":true}");
            m.ChooseSell(item);
            check(sent[sent.Count - 1].Contains("\"action\":\"prices\"") && sent[sent.Count - 1].Contains("\"sid\":4000"), "market panel: choosing an item asks for its prices");
            ext.Receive(221, ExtOpcodes.ToWire("{\"action\":\"prices\",\"data\":{\"seq\":2,\"rarity\":3,\"bandText\":\"iLvl 60-69\",\"gold\":{\"typical\":1500,\"n30\":6,\"n7\":6,\"days\":30},\"warn\":{\"low\":0.5,\"high\":2}}}"));
            m.Form["count"] = "3";
            string hint = m.SellHint(out long suggest);
            check(suggest == 4500 && hint.EndsWith(". Suggested: 4,500 gold for 3.") && hint.Contains("Typical price: 1,500 gold each"), "market panel: the sell hint suggests the price for the count: " + hint);
            m.Form["gold"] = "300";
            check(m.SellWarnings().Count == 1 && m.SellWarnings()[0].Text.StartsWith("Far below the typical price: 7% of"), "market panel: a far price warns: " + string.Join("|", m.SellWarnings().Select(w => w.Text)));
            // the drop on the Sell tab
            m.SelectTab("sell");
            ext.Receive(221, ExtOpcodes.ToWire("{\"action\":\"sellable\",\"data\":{\"items\":[{\"ref\":\"s1.0\",\"sid\":4000,\"item\":3100,\"count\":3,\"iid\":\"77\",\"name\":\"Cinder Blade\"},{\"ref\":\"s1.1\",\"sid\":4001,\"item\":3101,\"count\":1,\"iid\":\"78\",\"name\":\"Ash Shield\"}]}}"));
            check(m.DropItem(3101, 1, 0) && m.Selected != null && Json.Text(m.Selected, "name") == "Ash Shield", "market drop: an item without an id matches by look and count");
            check(m.DropItem(1, 1, 77) && Json.Text(m.Selected, "name") == "Cinder Blade", "market drop: an item with an id matches by it");
            check(m.DropItem(9999, 1, 0) && m.StatusTone == "bad", "market drop: an item that is not in the list says so");
            m.SelectTab("browse");
            check(!m.DropItem(1, 1, 77), "market drop: only on the Sell tab");
            var containers = new Dictionary<byte, Container>();
            var bag = new Container { Id = 0, FirstIndex = 0 };
            var it = new Item { Id = 3100, Count = 1 };
            bag.Items.Add(it);
            containers[0] = bag;
            check(MarketDrop.BagItem(containers, new Pos(0xFFFF, 0x40, 0)) == it && MarketDrop.BagItem(containers, new Pos(0xFFFF, 0x40, 4)) == null && MarketDrop.BagItem(containers, new Pos(0xFFFF, 3, 0)) == null && MarketDrop.BagItem(containers, new Pos(100, 100, 7)) == null, "market drop: the bag item at a position");
        }

        // ------------------------------------------------------------------------------------ game_bounty, game_dungeons
        static void OutfitChecks(Action<bool, string> check)
        {
            var o = OutfitJson.Read(J("{\"type\":131,\"head\":10,\"body\":20,\"legs\":30,\"feet\":40,\"addons\":2}"));
            check(o != null && o.LookType == 131 && o.Head == 10 && o.Body == 20 && o.Legs == 30 && o.Feet == 40 && o.Addons == 2, "outfit json: the bounty spelling");
            var b = OutfitJson.Read(J("{\"lookType\":250,\"lookHead\":1,\"lookBody\":2,\"lookLegs\":3,\"lookFeet\":4,\"lookAddons\":1}"));
            check(b != null && b.LookType == 250 && b.Head == 1 && b.Feet == 4 && b.Addons == 1, "outfit json: the dungeon spelling");
            var fb = OutfitJson.Read(J("{\"head\":5,\"body\":6}"), 77);
            check(fb != null && fb.LookType == 77 && fb.Head == 5, "outfit json: the contract's look fills a missing type");
            var ex = OutfitJson.Read(J("{\"lookType\":0,\"lookTypeEx\":2160}"));
            check(ex != null && ex.LookType == 0 && ex.LookTypeEx == 2160, "outfit json: an item look");
            check(OutfitJson.Read(null) == null && OutfitJson.Read(J("{\"lookType\":0}")) == null && OutfitJson.Read(J("{\"type\":0}"), 0) == null, "outfit json: nothing to draw");
        }

        // ------------------------------------------------------------------------------------ game_pvpzone
        static void PvpFlagChecks(Action<bool, string> check)
        {
            var marks = PvpZoneView.CleanMarks(J("[{\"kind\":\"exit\",\"x\":100,\"y\":100,\"z\":7,\"name\":\"North exit\"},{\"kind\":\"shrine\",\"x\":120,\"y\":90,\"z\":7},{\"kind\":\"exit\",\"x\":100,\"y\":100,\"z\":6}]"));
            check(marks.Count == 3, "pvp flags: marks");
            check(PvpZoneFlags.Visible(marks, 7, 90, 80, 110, 110).Count == 1 && PvpZoneFlags.Visible(marks, 7, 90, 80, 130, 110).Count == 2 && PvpZoneFlags.Visible(marks, 6, 0, 0, 200, 200).Count == 1 && PvpZoneFlags.Visible(null, 7, 0, 0, 1, 1).Count == 0, "pvp flags: on this floor, in the box");
            check(PvpZoneFlags.Color("shrine") == "#ff8a3c" && PvpZoneFlags.Color("exit") == "#f2f2f2", "pvp flags: colours");
            check(PvpZoneFlags.Tip(marks[0]) == "North exit" && PvpZoneFlags.Tip(marks[1]) == "Cinder Shrine" && PvpZoneFlags.Tip(marks[2]) == "Safe exit", "pvp flags: tips");
            var ext = new ExtOpcodes();
            var z = new PvpZoneState(ext);
            ext.Receive(193, ExtOpcodes.ToWire("{\"action\":\"enter\",\"data\":{\"marks\":[{\"kind\":\"exit\",\"x\":5,\"y\":6,\"z\":7}]}}"));
            check(z.Marks.Count == 1, "pvp flags: the zone keeps its marks while entered");
            ext.Receive(193, ExtOpcodes.ToWire("{\"action\":\"hide\",\"data\":{}}"));
            check(z.Marks.Count == 0, "pvp flags: gone when the zone is left");
        }

        // ------------------------------------------------------------------------------------ game_playerinspect
        static void InspectTreeChecks(Action<bool, string> check)
        {
            var d = J("{\"name\":\"Ash\",\"nodes\":[1,2,5],\"masteries\":[{\"id\":5,\"choice\":\"Ember Heart\"}],\"line\":\"fire\",\"vocation\":\"Pyromancer\",\"spent\":3,\"total\":40}");
            var v = InspectTreeView.From(d);
            check(v != null && v.Owned.Count == 3 && v.Owned.Contains(5) && v.Choices[5] == "Ember Heart" && v.Spent == 3 && v.Total == 40, "inspect tree: the packet");
            check(v.Summary() == "Ash: 3 / 40 points" && InspectTreeView.From(J("{\"name\":\"x\"}")) == null, "inspect tree: the title, and a packet without nodes");
            var plain = new TreeNode { Id = 1, Name = "Vigor", Stats = new[] { "+5 health" } };
            var mastery = new TreeNode { Id = 5, Type = 'M', Name = "Mastery" };
            var other = new TreeNode { Id = 9, Name = "Frost Touch", Line = "frost" };
            var mine = new TreeNode { Id = 10, Name = "Fire Touch", Line = "fire" };
            check(v.Shown(plain) && v.Shown(mine) && !v.Shown(other) && !v.Shown(new TreeNode { Id = 11, Hidden = true }), "inspect tree: nodes of other lines and hidden ones are not drawn");
            check(v.Tip(plain) == "Vigor\n+5 health\nTaken" && v.Tip(mastery) == "Mastery\nChoice: Ember Heart\nTaken" && v.Tip(other).EndsWith("Not taken"), "inspect tree: node tips: " + v.Tip(mastery));
            var td = new TreeData { MinX = -1000, MaxX = 1000, MinY = -500, MaxY = 500 };
            InspectTreeView.Fit(td, 800, 400, out float zoom, out float cx, out float cy);
            check(Math.Abs(zoom - 400f / 1200f) < 0.001f && cx == 0 && cy == 0, "inspect tree: fit");
            var ext = new ExtOpcodes();
            var panel = new InspectPanel(ext);
            panel.Data = J("{\"name\":\"Ash\"}");
            ext.Receive(240, ExtOpcodes.ToWire("{\"action\":\"tree\",\"data\":{\"name\":\"Ash\",\"nodes\":[1,2],\"spent\":2,\"total\":10}}"));
            var rows = panel.BuildRows();
            panel.Tab = "profile";
            rows = panel.BuildRows();
            var tree = rows.FirstOrDefault(r => r.Text != null && r.Text.StartsWith("Passive Tree (2)"));
            check(tree != null && tree.Buttons.Count == 1 && tree.Buttons[0].Text == "View tree", "inspect tree: the profile tab has a View tree button");
            tree.Buttons[0].Click();
            check(panel.TreeViewRequested, "inspect tree: the button asks the window to open");
        }

        // ------------------------------------------------------------------------------------ game_charms
        static void CharmDropChecks(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var c = new CharmsState(ext);
            ext.Receive(198, ExtOpcodes.ToWire("{\"action\":\"state\",\"data\":{\"cols\":4,\"rows\":3,\"max\":2,\"shards\":7,\"cells\":[" +
                string.Join(",", Enumerable.Range(1, 3).SelectMany(y => Enumerable.Range(1, 4).Select(x => "{\"x\":" + x + ",\"y\":" + y + ",\"open\":" + (x <= 3 ? "true" : "false") + ",\"why\":\"level 100\"}"))) + "]," +
                "\"placed\":[{\"id\":9,\"ref\":\"p1\",\"x\":1,\"y\":1,\"w\":2,\"h\":1,\"name\":\"Ash\"}]," +
                "\"bag\":[{\"ref\":\"b1\",\"sid\":\"5\",\"iid\":\"77\",\"w\":1,\"h\":2,\"name\":\"Cinder\"}]}}"));
            var pos = new Pos(0xFFFF, 0x40, 3);
            var act = c.ItemDropAction(pos, 77, 46 * 2 + 5, 46 + 5, out string why);
            check(act != null && act.Action == "place" && CF.Int(act.Data["x"]) == 3 && CF.Int(act.Data["y"]) == 1 && act.Data["iid"] as string == "77", "charm item drop: the place packet at the cell under the pointer");
            var p = act.Data["pos"] as Dictionary<string, object>;
            check(p != null && CF.Int(p["x"]) == 0xFFFF && CF.Int(p["y"]) == 0x40 && CF.Int(p["z"]) == 3, "charm item drop: the item's position goes along");
            check(c.ItemDropAction(pos, 77, 46 * 3 + 5, 46 + 5, out why) == null && why == "That cell is locked: level 100", "charm item drop: a locked cell refuses: " + why);
            check(c.ItemDropAction(pos, 77, 5, 46 + 5, out why) == null && why == "Another charm is in the way.", "charm item drop: another charm in the way refuses");
            check(c.ItemDropAction(pos, 0, 46 * 2 + 5, 46 * 2 + 5, out why) != null, "charm item drop: an item without an id counts as 1 x 1");
            check(c.ItemDropAction(pos, 77, 9999, 9999, out why) == null && why == "Drop it on the grid.", "charm item drop: outside the grid");
        }
    }
}
