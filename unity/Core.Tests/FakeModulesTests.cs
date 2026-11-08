// Phase 11, track G (Core/FakeModules.cs): the module answers and the context pushes of the window smoke run. Every sample message is fed to a real GameSession (the Unity
// parsers of the modules) and must leave a non-empty state; every key of a sample must appear in the server file the entry cites (when the repo's server folder is found).
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class FakeModulesTests
    {
        public static void Run(Action<bool, string> check)
        {
            CatalogChecks(check);
            AnswerChecks(check);
            ContextChecks(check);
            ServerKeyChecks(check);
            ResponderChecks(check);
        }

        static GameSession NewSession() => new GameSession(new World(DatFile.Parse(Program.SyntheticDat())), new GameSession.Options());

        static object Request(string action, string data = null)
        {
            var root = new Dictionary<string, object> { { "action", action } };
            root["data"] = data == null ? new Dictionary<string, object>() : Json.Parse(data.Replace('\'', '"'));
            return root;
        }

        /// <summary>One message into the session's Ext the way the wire does it: the server's parts (ExtChunks.Split) in order.</summary>
        static void Feed(GameSession s, FakeMsg m)
        {
            foreach (var part in ExtChunks.Split(ExtOpcodes.ToWire(Json.Serialize(m.Root)))) s.Ext.Receive(m.Op, part);
        }

        static void CatalogChecks(Action<bool, string> check)
        {
            var ops = FakeModules.Catalog.Select(m => m.Op).ToList();
            check(ops.Distinct().Count() == ops.Count && ops.Count >= 20, "fake modules: " + ops.Count + " modules, every opcode once");
            check(FakeModules.Catalog.All(m => m.Source.StartsWith("server/") && m.Windows.Length > 0 && m.Requests.Length > 0), "fake modules: every module names its server file, window and requests");
            // the opcodes are the server's (chaos_constants.lua) for the modules that list one there
            string root = RepoRoot();
            if (root != null)
            {
                string consts = File.ReadAllText(Path.Combine(root, "server/data/scripts/chaos/chaos_constants.lua"));
                var pairs = new Dictionary<string, byte>
                {
                    { "achievements", AchievementsState.OpcodeId }, { "bestiary", BestiaryState.OpcodeId }, { "seasonPass", PassState.OpcodeId }, { "season", SeasonState.OpcodeId },
                    { "daily", DailyState.OpcodeId }, { "cosmetics", CosmeticsState.OpcodeId }, { "transmog", TransmogState.OpcodeId }, { "pets", PetsState.OpcodeId },
                    { "crafting", CraftingState.OpcodeId }, { "hunt", HuntTracker.Opcode }, { "guild", GuildPanel.Opcode }, { "infinitytower", TowerState.Opcode },
                    { "dungeons", DungeonsState.Opcode }, { "invasion", InvasionState.Opcode }, { "siege", SiegeState.Opcode }, { "arena", ArenaState.Opcode },
                    { "rift", RiftHud.Opcode }, { "groupQueue", GroupQueuePanel.Opcode }, { "partyFinder", PartyFinderPanel.Opcode },
                    { "bank", BankState.Opcode }, { "stash", StashState.Opcode }, { "shop", StoreState.Opcode }, { "market", MarketPanel.Opcode }, { "bounty", BountyState.Opcode },
                    { "leaderboard", LeaderboardPanel.Opcode }, { "raid", RaidState.Opcode },
                };
                foreach (var kv in pairs)
                {
                    var m = Regex.Match(consts, @"(?:\b" + kv.Key + @"\s*=\s*|ChaosOpcodes\." + kv.Key + @"\s*=\s*)(\d+)");
                    check(m.Success && byte.Parse(m.Groups[1].Value) == kv.Value, "fake modules: opcode of " + kv.Key + " is the server's " + (m.Success ? m.Groups[1].Value : "?"));
                }
            }
        }

        static void AnswerChecks(Action<bool, string> check)
        {
            var s = NewSession();
            int fed = 0;
            foreach (var mod in FakeModules.Catalog)
                foreach (string action in mod.Requests)
                {
                    var answers = FakeModules.Answer(mod.Op, Request(action, FakeModules.SampleData(mod.Op, action)));
                    check(answers.Count > 0, "fake modules: " + mod.Name + " answers '" + action + "'");
                    foreach (var m in answers)
                    {
                        check(m.Op == mod.Op && m.Source.Length > 0, "fake modules: " + mod.Name + " " + m.Action + " names its server source");
                        Feed(s, m); fed++;
                    }
                }
            check(fed > 40 && s.Ext.Invalid == 0, "fake modules: " + fed + " messages parse as JSON, " + s.Ext.Invalid + " invalid");
            check(FakeModules.Answer(77, Request("open")).Count == 0 && FakeModules.Answer(AchievementsState.OpcodeId, Request("nope")).Count == 0, "fake modules: an opcode or action not covered gets no answer");

            check(s.Achievements.State != null && s.Achievements.Rows.Count == 5 && s.Achievements.Visible, "fake modules: achievements state and 5 rows, window open");
            check(s.Achievements.Track != null && s.Achievements.SummaryText().Contains("Points: 30"), "fake modules: achievements summary: " + s.Achievements.SummaryText());
            check(s.Bestiary.Summary != null && s.Bestiary.ListComplete && s.Bestiary.Rows.Count == 4 && s.Bestiary.Detail != null && s.Bestiary.Board != null, "fake modules: bestiary summary, list, entry, board");
            check(s.Charms.State != null && s.Charms.Cells.Count == 12 && s.Charms.Placed.Count == 1 && s.Charms.Bag.Count == 1, "fake modules: charms grid, placed and bag");
            check(s.Pass.State != null && s.Pass.Tiers != null && s.Pass.Tiers.Complete && s.Pass.Visible, "fake modules: season pass state and all three tiers");
            check(s.Seasons.State != null && s.Seasons.Header != null && s.Seasons.Chapters.Count == 3, "fake modules: season overview, journey header and chapters");
            check(s.Daily.Data != null && s.Daily.Rewards.Count == 7, "fake modules: daily reward calendar");
            check(s.Weekly.State != null && s.Weekly.Rows().Count == 3, "fake modules: weekly chest activities");
            check(s.Cosmetics.State != null && s.Cosmetics.Wardrobe != null && s.Cosmetics.Wardrobe.Count > 0, "fake modules: cosmetics state and wardrobe");
            check(s.Transmog.State != null && s.Transmog.Slots.Count == 4, "fake modules: transmog slots");
            check(s.Pets.State != null && s.Pets.Entries().Count == 2, "fake modules: pets owned and catalog");
            check(s.Professions.State != null && s.Professions.ProfRows().Count == 2, "fake modules: professions rows");
            check(s.Crafting.State != null && s.Crafting.Orbs.Count == 2, "fake modules: crafting bench orbs");
            check(s.CraftTable.Recipes("mining").Count == 2 && s.CraftTable.Money == 12500, "fake modules: craft table recipes and money");
            check(s.Progress.Hunt.HasState && s.Progress.Hunt.Loot.Count == 3, "fake modules: hunt tracker state");
            check(s.Progress.Goals.HasHeader && s.Progress.Goals.GoalList.Count == 3 && s.Progress.Goals.TrackerHasRows, "fake modules: goals header, list and tracker");
            check(s.Social.Guild.State != null && s.Social.GuildWar.State != null, "fake modules: guild and guild war state");
            check(s.Social.PartyFinder.Init != null && s.Social.PartyFinder.Data != null, "fake modules: party finder init and list");
            check(s.Social.GroupQueue.State != null, "fake modules: group queue state");
            check(s.Endgame.Tower.HasData && s.Endgame.Tower.Milestones.Count == 2 && s.Endgame.Tower.Rankings.Count == 2, "fake modules: tower window data");
            Phase12Checks(check, s);
        }

        // phase 12, track H: the answers of Core/FakeModulesP12.cs leave the state the windows draw
        static void Phase12Checks(Action<bool, string> check, GameSession s)
        {
            check(s.Bank.HasState && s.Bank.GoldCarried == 350000 && s.Bank.GoldBank == 1200000, "fake modules: bank gold carried and banked");
            check(s.Stash.HasTabs && s.Stash.Tabs.Count == 2 && s.Stash.ItemsLoaded && s.Stash.Items.Count == 3 && s.Stash.CanWithdraw && s.Stash.Blocks.Count == 0, "fake modules: stash tabs and items");
            check(s.Store.Loaded && s.Store.Categories.Count == 3 && s.Store.Tree.Count == 2 && s.Store.Coins == 250, "fake modules: store tree and coins");
            check(s.Social.Market.Meta != null && s.Social.Market.PageData != null && s.Social.Market.Total == 3 && s.Social.Market.SellData != null && s.Social.Market.MineData != null
                && s.Social.Market.HistoryData != null && s.Social.Market.OrdersData != null, "fake modules: market meta and every tab's data");
            check(s.Endgame.Dungeons.Rows.Count == 2 && s.Endgame.Dungeons.Details.Count == 2 && s.Endgame.Dungeons.Selected != null && s.Endgame.Dungeons.Selected.Solo.Count == 1, "fake modules: dungeons list, details and the solo board");
            check(s.Endgame.Raid.Info != null && s.Endgame.Raid.JournalBosses.Count == 1 && RaidView.VendorStock(s.Endgame.Raid.Info).Count == 2 && RaidView.SavedRow(Json.List(s.Endgame.Raid.Info, "saved")[0]).Id == 7,
                "fake modules: raid info, the vendor stock and the journal");
            check(s.Endgame.Bounty.HasBoard && s.Endgame.Bounty.Bands.Count == 2 && s.Endgame.Bounty.Current != null && s.Endgame.Bounty.Current.Contracts.Count == 3, "fake modules: bounty bands and contracts");
            check(s.Utils.AutoLoot.Rows.Count == 3 && s.Utils.AutoLoot.MaxSlot == 40, "fake modules: auto loot list");
            check(s.Utils.Pouches.Owned.Count == 3 && s.Utils.Pouches.Rules.Gold && s.Utils.Pouches.SellerKnown && s.Utils.Pouches.Seller.Unlocked && s.Utils.Pouches.Seller.List.Count == 1, "fake modules: pouch rules and the auto seller");
            check(s.Utils.Portal.Loaded && s.Utils.Portal.Styles.Count == 2 && s.Utils.Portal.SelectedId == "ember", "fake modules: town portal styles");
            check(s.Endgame.PvpZone.State != null && Json.List(s.Endgame.PvpZone.State, "factions").Count == 2 && Json.List(s.Endgame.PvpZone.State, "vendor").Count == 2 && s.Endgame.PvpZone.Visible && !s.Endgame.PvpZone.ConfirmAsked, "fake modules: Marches window state, no confirm");
            check(s.Social.Leaderboard.Meta != null && s.Social.Leaderboard.Current != null && SFmt.Rows(s.Social.Leaderboard.Current, "rows").Count == 3, "fake modules: leaderboard meta and the board");
        }

        static void ContextChecks(Action<bool, string> check)
        {
            string[] expected =
            {
                "TowerPanelWindow", "DungeonCounterWindow", "RaidHudWindow", "RaidCalloutWindow", "DescentHudWindow", "DescentOfferWindow", "DescentShopWindow", "InvasionHudWindow",
                "SiegeHudWindow", "ArenaHudWindow", "BattlegroundHudWindow", "BattlegroundBoardWindow", "PvpZoneConfirmWindow", "PvpZoneHudWindow", "RiftWindow", "ReadyCheckWindow",
                "TaskTrackerWindow", "HelperHudWindow", "WaystoneWindow", "SurveyWindow",
            };
            check(expected.All(w => FakeModules.Context(w) != null) && FakeModules.ContextWindows.Count() == expected.Length, "fake contexts: the " + expected.Length + " context HUDs");
            check(FakeModules.Context("HelperHudWindow") != null && !FakeModules.Context("HelperHudWindow").Drivable && FakeModules.Context("HelperHudWindow").Reason.Length > 10, "fake contexts: the Bot HUD says why no push opens it");
            check(expected.Where(w => w != "HelperHudWindow").All(w => FakeModules.Context(w).Drivable && FakeModules.Context(w).Pushes.Count > 0), "fake contexts: every other HUD has a push");

            var s = NewSession();
            double now = s.Now;
            var wanted = new Dictionary<string, Func<bool>>
            {
                { "TowerPanelWindow", () => s.Endgame.Tower.InRun && s.Endgame.Tower.Panel(now) != null },
                { "DungeonCounterWindow", () => s.Endgame.Dungeons.Counter && s.Endgame.Dungeons.Objectives.Count == 2 },
                { "RaidHudWindow", () => s.Endgame.Raid.Hud != null },
                { "RaidCalloutWindow", () => s.Endgame.Raid.Callout.Active(now) },
                { "DescentHudWindow", () => s.Endgame.Descent.HudShown(now) },
                { "DescentOfferWindow", () => s.Endgame.Descent.Offer != null },
                { "DescentShopWindow", () => s.Endgame.Descent.ShopVisible },
                { "InvasionHudWindow", () => s.Endgame.Invasion.HudShown },
                { "SiegeHudWindow", () => s.Endgame.Siege.Hud != null },
                { "ArenaHudWindow", () => s.Endgame.Arena.HudShown(now) && s.Endgame.Arena.Side(true).Count == 2 },
                { "BattlegroundHudWindow", () => s.Endgame.Battleground.Hud != null },
                { "BattlegroundBoardWindow", () => s.Endgame.Battleground.InMatch && s.Endgame.Battleground.BoardData != null },   // phase 14: the live board of a running match
                { "PvpZoneConfirmWindow", () => s.Endgame.PvpZone.ConfirmAsked },
                { "PvpZoneHudWindow", () => s.Endgame.PvpZone.Inside },
                { "RiftWindow", () => s.Progress.Rift.Active },
                { "ReadyCheckWindow", () => s.Social.GroupQueue.CheckOpen },
                { "TaskTrackerWindow", () => TaskTrackerState.Rows(s.Bestiary.TrackerRows).Count == 2 },
                { "SurveyWindow", () => s.Community.Survey.Visible && s.Community.Survey.Stage == SurveyPanel.SourceStage },
                { "WaystoneWindow", () => s.Utils.Waystone.Visible && s.Utils.Waystone.Rows.Count >= 6 && s.Utils.Waystone.Rows[0].Count == 5 },
            };
            foreach (var kv in wanted)
            {
                var ctx = FakeModules.Context(kv.Key);
                check(!kv.Value(), "fake contexts: " + kv.Key + " is not wanted before its push");
                foreach (var m in ctx.Pushes) Feed(s, m);
                check(kv.Value(), "fake contexts: " + kv.Key + " is wanted after its push");
                foreach (var m in ctx.Close) Feed(s, m);
                s.Endgame.Clear(); s.Progress.Rift.Hide(); s.Utils.Waystone.Clear();
                check(!kv.Value(), "fake contexts: " + kv.Key + " is gone after the end messages and the clear");
            }
        }

        // ------------------------------------------------------------------------------------ the keys against the server files
        static string RepoRoot()
        {
            for (var d = new DirectoryInfo(Directory.GetCurrentDirectory()); d != null; d = d.Parent)
                if (File.Exists(Path.Combine(d.FullName, "server/data/scripts/chaos/chaos_constants.lua"))) return d.FullName;
            return null;
        }

        // keys under these are dynamic names (player names, counts per orb, tier numbers), not field names of the server
        static readonly HashSet<string> Dynamic = new HashSet<string> { "names", "counts", "reasons", "orbs", "pick", "tiers", "skipped", "cooldowns", "bosses", "shards", "relics", "have", "words" };

        static void Keys(object o, string parent, HashSet<string> into)
        {
            if (o is Dictionary<string, object> d)
            {
                foreach (var kv in d)
                {
                    if (!Dynamic.Contains(parent) && kv.Key != "action" && kv.Key != "data") into.Add(kv.Key);
                    Keys(kv.Value, kv.Key, into);
                }
            }
            else if (o is List<object> l) foreach (var x in l) Keys(x, parent, into);
        }

        static IEnumerable<string> SourceFiles(string root, string source)
        {
            // "server/data/scripts/chaos/raid.lua, raid_core.lua" or "server/.../x.lua (what)": the files named, and the module's _core, _config and run files next to it
            string dir = Path.Combine(root, "server/data/scripts/chaos");
            var names = new HashSet<string>();
            foreach (var part in source.Split(','))
            {
                string p = Regex.Replace(part, @"\s*\(.*\)\s*$", "").Trim();
                if (p.Length == 0) continue;
                if (p.StartsWith("server/", StringComparison.Ordinal)) { names.Add(Path.Combine(root, p)); p = Path.GetFileName(p); }
                else names.Add(Path.Combine(dir, p));
                string stem = Path.GetFileNameWithoutExtension(p);
                foreach (var suffix in new[] { "_core", "_config", "_run", "_data" })
                {
                    string f = Path.Combine(dir, (stem.EndsWith(suffix, StringComparison.Ordinal) ? stem.Substring(0, stem.Length - suffix.Length) : stem) + suffix + ".lua");
                    if (File.Exists(f)) names.Add(f);
                }
            }
            return names.Where(File.Exists);
        }

        static void ServerKeyChecks(Action<bool, string> check)
        {
            string root = RepoRoot();
            if (root == null) { check(true, "fake modules: server folder not found, key check skipped"); return; }
            var msgs = new List<FakeMsg>();
            var s = NewSession();
            foreach (var mod in FakeModules.Catalog)
                foreach (string action in mod.Requests)
                    msgs.AddRange(FakeModules.Answer(mod.Op, Request(action, FakeModules.SampleData(mod.Op, action))));
            foreach (var w in FakeModules.ContextWindows) { var c = FakeModules.Context(w); msgs.AddRange(c.Pushes); msgs.AddRange(c.Close); }
            var missing = new List<string>();
            var textCache = new Dictionary<string, string>();
            foreach (var m in msgs)
            {
                var keys = new HashSet<string>();
                Keys(m.Root, "", keys);
                string text = "";
                foreach (var f in SourceFiles(root, m.Source)) { if (!textCache.TryGetValue(f, out var t)) textCache[f] = t = File.ReadAllText(f); text += t + "\n"; }
                if (text.Length == 0) { missing.Add(m.Op + " " + m.Action + ": no server file found for '" + m.Source + "'"); continue; }
                foreach (string k in keys)
                    if (!Regex.IsMatch(text, @"(?<![A-Za-z0-9_])" + Regex.Escape(k) + @"(?![A-Za-z0-9_])")) missing.Add(m.Op + " " + m.Action + ": '" + k + "' is not in " + m.Source);
            }
            foreach (var x in missing.Distinct()) Console.WriteLine("  fake modules: " + x);
            check(missing.Count == 0, "fake modules: every key of every sample is in its server file (" + msgs.Count + " messages, " + missing.Distinct().Count() + " keys missing)");
        }

        // ------------------------------------------------------------------------------------ the server side of the responder
        static void ResponderChecks(Action<bool, string> check)
        {
            // a payload over 8192 bytes leaves the fake server in parts and the client joins them (the same split as Chaos.send): a long craft table page
            var big = FakeModules.Answer(CraftTableState.OpcodeId, Request("fetch", "{'category':'mining','page':1}"))[0];
            string wire = ExtOpcodes.ToWire(Json.Serialize(big.Root));
            check(ExtChunks.Split(wire).Count == 1, "fake modules: a small sample goes out whole");
            var s = NewSession();
            var padded = new Dictionary<string, object> { { "action", "fetch" }, { "data", Json.Parse("{\"category\":\"mining\",\"totalPages\":1,\"page\":1,\"crafts\":[]}") }, { "pad", new string('x', 20000) } };
            var parts = ExtChunks.Split(ExtOpcodes.ToWire(Json.Serialize(padded)));
            foreach (var p in parts) s.Ext.Receive(CraftTableState.OpcodeId, p);
            check(parts.Count > 1 && s.Ext.Invalid == 0 && s.CraftTable.Loaded("mining"), "fake modules: an oversize message is sent in parts and joined: " + parts.Count + " parts");
        }
    }
}
