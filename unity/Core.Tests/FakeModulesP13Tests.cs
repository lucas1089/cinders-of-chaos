// Phase 13, track G (Core/FakeModulesP13.cs, Core/Phase13G.cs): the answers for the windows the phase 12 smoke run found empty. Per module: the opcode is the server's
// (chaos_constants.lua, admin/core.lua), every sample message is fed to a real GameSession (the Unity parsers) and the window's own rows or lines come out non-empty. The keys of
// every sample against the cited server file are checked by FakeModulesTests (the catalog now holds these modules). Also: the trade packets (0x7D, 0x7E), the covered-window share.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class FakeModulesP13Tests
    {
        public static void Run(Action<bool, string> check)
        {
            OpcodeChecks(check);
            Social(check);
            Community(check);
            Endgame(check);
            Items(check);
            World(check);
            OpenNumber(check);
            TradeChecks(check);
            CoverChecks(check);
        }

        static GameSession NewSession() => new GameSession(new World(DatFile.Parse(Program.SyntheticDat())), new GameSession.Options());

        static object Request(string action, string data = null)
        {
            var root = new Dictionary<string, object> { { "action", action } };
            root["data"] = data == null ? new Dictionary<string, object>() : Json.Parse(data.Replace('\'', '"'));
            return root;
        }

        /// <summary>The answers of a request fed to the session the way the wire does it; returns them.</summary>
        static List<FakeMsg> Ask(GameSession s, byte op, string action, string data = null)
        {
            var answers = FakeModules.Answer(op, Request(action, data));
            foreach (var m in answers)
                foreach (var part in ExtChunks.Split(ExtOpcodes.ToWire(Json.Serialize(m.Root)))) s.Ext.Receive(m.Op, part);
            return answers;
        }

        static string RepoRoot()
        {
            for (var d = new DirectoryInfo(Directory.GetCurrentDirectory()); d != null; d = d.Parent)
                if (File.Exists(Path.Combine(d.FullName, "server/data/scripts/chaos/chaos_constants.lua"))) return d.FullName;
            return null;
        }

        static int Rows(SocialPanel p) => p.BuildRows().Count;
        static bool HasText(SocialPanel p, string part) => p.BuildRows().Any(r => (r.Text ?? "").Contains(part) || (r.Right ?? "").Contains(part) || (r.Sub ?? "").Contains(part));

        // ------------------------------------------------------------------------------------ the opcodes are the server's
        static void OpcodeChecks(Action<bool, string> check)
        {
            var mine = FakeModules.Catalog.Where(m => m.Source.Length > 0).ToList();
            string[] names = { "factions", "conquest", "admin", "bossspawns", "referral", "nemesis", "community", "patchnotes", "chronicle", "inspect", "descent", "invasion", "siege", "arena", "battleground",
                "orbexchange", "gamble", "embercache", "loadouts", "supports", "pact", "candlemarks", "lootfilter", "hideout", "riftatlas", "waystoneatlas" };
            check(names.All(n => FakeModules.Catalog.Any(m => m.Name == n)), "fake modules p13: all " + names.Length + " modules are in the catalog");
            string root = RepoRoot();
            if (root == null) { check(true, "fake modules p13: server folder not found, opcode check skipped"); return; }
            string consts = File.ReadAllText(Path.Combine(root, "server/data/scripts/chaos/chaos_constants.lua"));
            string admin = File.ReadAllText(Path.Combine(root, "server/data/scripts/chaos/admin/core.lua"));
            var keys = new Dictionary<string, string>
            {
                { "factions", "factions" }, { "conquest", "conquest" }, { "bossspawns", "bossSpawns" }, { "referral", "referral" }, { "nemesis", "nemesis" }, { "community", "community" },
                { "patchnotes", "patchnotes" }, { "chronicle", "chronicle" }, { "inspect", "inspect" }, { "descent", "descent" }, { "invasion", "invasion" }, { "siege", "siege" }, { "arena", "arena" },
                { "battleground", "battleground" }, { "orbexchange", "orbExchange" }, { "gamble", "gamble" }, { "embercache", "emberCache" }, { "loadouts", "loadouts" }, { "supports", "supports" },
                { "pact", "pact" }, { "candlemarks", "candlemarks" }, { "lootfilter", "lootfilter" }, { "hideout", "hideout" }, { "riftatlas", "riftAtlas" }, { "waystoneatlas", "waystoneAtlas" },
            };
            foreach (var kv in keys)
            {
                var m = Regex.Match(consts, @"(?:\b" + kv.Value + @"\s*=\s*|ChaosOpcodes\." + kv.Value + @"\s*=\s*)(\d+)");
                var mod = FakeModules.Catalog.First(x => x.Name == kv.Key);
                check(m.Success && byte.Parse(m.Groups[1].Value) == mod.Op, "fake modules p13: opcode of " + kv.Key + " is the server's " + (m.Success ? m.Groups[1].Value : "?") + ", the sample has " + mod.Op);
            }
            var am = Regex.Match(admin, @"CHAOS_ADMIN_OPCODE\s*=\s*(\d+)");
            check(am.Success && byte.Parse(am.Groups[1].Value) == AdminPanel.Opcode, "fake modules p13: opcode of admin is the server's " + (am.Success ? am.Groups[1].Value : "?"));
            // every message of every sample names the module's opcode
            var s = NewSession();
            bool allOp = true;
            foreach (var name in names)
            {
                var mod = FakeModules.Catalog.First(x => x.Name == name);
                foreach (string action in mod.Requests)
                    foreach (var msg in FakeModules.Answer(mod.Op, Request(action, FakeModules.SampleData(mod.Op, action)))) allOp &= msg.Op == mod.Op && msg.Source.Length > 0;
            }
            check(allOp, "fake modules p13: every answer carries its module's opcode and a server source");
            check(mine.Count >= 46, "fake modules p13: the catalog holds " + mine.Count + " modules");
        }

        // ------------------------------------------------------------------------------------ social windows
        static void Social(Action<bool, string> check)
        {
            var s = NewSession();
            Ask(s, FactionsPanel.Opcode, "open");
            var f = s.Social.Factions;
            check(f.Data != null && f.Tabs.Count == 2 && f.Selected == "ash" && Rows(f) >= 12 && HasText(f, "Slay 20 ghouls") && f.Header2.Length > 0, "fake p13: Factions: state, two tabs, contracts, reset line: " + Rows(f) + " rows");
            f.OffersTab = true;
            check(HasText(f, "Warden Helm") && FactionsMath.OffersFor(f.Data, "ash").Count == 3, "fake p13: Factions: the offers tab lists 3 offers");

            Ask(s, ConquestPanel.Opcode, "open");
            var c = s.Social.Conquest;
            check(c.State != null && ConquestMath.Rows(c.State, "uniques").Count == 2 && ConquestMath.Rows(c.State, "sets").Count == 1 && ConquestMath.Rows(c.State, "chase").Count == 1
                && ConquestMath.Rows(c.State, "cinder").Count > 4 && ConquestMath.Rows(c.State, "refine").Count == 1 && ConquestMath.ProgressLines(c.State).Count > 5, "fake p13: Conquest: every tab has rows");
            c.Tab = "uniques";
            check(Rows(c) >= 4 && c.Header1.Contains("180") && c.Header2.Length > 0, "fake p13: Conquest: vendor rows and the token header: " + c.Header1);

            Ask(s, InspectPanel.Opcode, "privacy");
            check(s.Social.Inspect.PrivacyKnown && s.Social.Inspect.AllowMe, "fake p13: Inspect: the privacy answer");
            var ans = Ask(s, InspectPanel.Opcode, "inspect", "{'name':'" + FakeModules.InspectName + "'}");
            var ins = s.Social.Inspect;
            check(ans.Count == 3 && ins.Data != null && ins.Complete && ins.Tips.Count == 3 && ins.Records != null && ins.Records.Count == 3 && InspectMath.Header(ins.Data).Count >= 4
                && InspectMath.CombatStats(ins.Data).Count == 3 && Json.Text(ins.Data, "name") == FakeModules.InspectName, "fake p13: Inspect: result, equipment, records and the combat sheet of " + FakeModules.InspectName + " (" + ans.Count + " answers, data " + (ins.Data != null) + ", complete " + ins.Complete + ", tips " + ins.Tips.Count + ", records " + (ins.Records == null ? -1 : ins.Records.Count) + ", header " + (ins.Data == null ? -1 : InspectMath.Header(ins.Data).Count) + ", combat " + (ins.Data == null ? -1 : InspectMath.CombatStats(ins.Data).Count) + ")");
            ins.Tab = "gear";
            check(Rows(ins) > 8, "fake p13: Inspect: the equipment tab draws rows: " + Rows(ins));
        }

        // ------------------------------------------------------------------------------------ community windows
        static void Community(Action<bool, string> check)
        {
            var s = NewSession();
            var cm = s.Community;
            Ask(s, AdminPanel.Opcode, "catalog");
            check(cm.Admin.HasCatalog && cm.Admin.Categories.Count == 2 && cm.Admin.Find("kick") != null && cm.Admin.Find("kick").Dangerous && cm.Admin.Find("kick").Params.Count == 2 && cm.Admin.Find("status").Params.Count == 0,
                "fake p13: Admin: the catalog gives 2 categories, a dangerous action with 2 parameters and one with none");
            cm.Admin.Show();
            check(cm.Admin.Visible && Rows(cm.Admin) > 3, "fake p13: Admin: the window draws its action list: " + Rows(cm.Admin) + " rows");

            Ask(s, BossSpawnsPanel.Opcode, "open");
            var bs = cm.BossSpawns;
            var groups = BossSpawnsPanel.GroupRows(bs.Data, "");
            check(bs.Data != null && bs.Pocket != null && groups.Count == 2 && groups[0].Rows.Count == 3 && Rows(bs) >= 7 && HasText(bs, "Vorn the Hollow"), "fake p13: Boss Spawns: 2 categories, 4 bosses and the pocket data (" + (bs.Data != null) + " " + (bs.Pocket != null) + " groups " + groups.Count + " rows " + (groups.Count > 0 ? groups[0].Rows.Count : -1) + " built " + Rows(bs) + ")");
            string pt, tip; bool pe;
            check(BossSpawnsPanel.PocketOf(groups[0].Rows[0], bs.Pocket, 0, out pt, out pe, out tip) && pe && pt.Contains("2/3") && BossSpawnsPanel.StatusOf(groups[0].Rows[1], 0, out _).Contains("Respawns in"), "fake p13: Boss Spawns: a pocket button and a respawn countdown");

            Ask(s, ReferralPanel.Opcode, "open");
            var rf = cm.Referral;
            check(rf.StatusData != null && rf.Visible && HasText(rf, "EMBER7K2Q") && HasText(rf, "Vex") && Rows(rf) >= 9, "fake p13: Referral: code, rewards and the referred friends: " + Rows(rf) + " rows (" + (rf.StatusData != null) + " " + rf.Visible + " code " + HasText(rf, "EMBER7K2Q") + " vex " + HasText(rf, "Vex") + ")");

            Ask(s, NemesisPanel.Opcode, "get");
            check(cm.Nemesis.State != null && HasText(cm.Nemesis, "Ghoul") && cm.Nemesis.Header1.Contains("Varkh") && Rows(cm.Nemesis) >= 8, "fake p13: Nemesis: the monster, kills and traits");

            Ask(s, CommunityGoalPanel.Opcode, "open");
            var g = cm.Goal;
            check(g.Data != null && CommunityGoalPanel.BarPercent(g.Data) == 42 && Rows(g) >= 14 && HasText(g, "Roaring Fire") && HasText(g, "Vex") && g.Header1.Contains("Ember Harvest"), "fake p13: Community goal: bar, stages, your part and the top list: " + Rows(g) + " rows");

            var pa = Ask(s, PatchNotesPanel.Opcode, "open");
            var pn = cm.PatchNotes;
            check(pa.Count == 2 && pn.Weeks.Count == 2 && pn.SelectedId == "2026-w45" && pn.Notes.ContainsKey("2026-w45") && pn.Visible && Rows(pn) >= 6, "fake p13: Patch notes: 2 weeks, the selected note and the window open: " + Rows(pn) + " rows");
            Ask(s, PatchNotesPanel.Opcode, "changelog");
            int shown;
            check(pn.Changelog != null && PatchNotesPanel.ChangelogRows(pn.Changelog, "all", 0, out shown).Count >= 4 && shown == 2, "fake p13: Patch notes: the changelog has 2 entries under 2 dates");

            Ask(s, ChroniclePanel.Opcode, "open");
            Ask(s, ChroniclePanel.Opcode, "mem");
            var ch = cm.Chronicle;
            check(ch.State != null && ChroniclePanel.Chapters(ch.State).Count == 3 && ChroniclePanel.DefaultChapter(ch.State) == 2 && ch.Mem != null && Rows(ch) >= 8, "fake p13: Chronicle: 3 chapters, chapter 2 open, the memorial data: " + Rows(ch) + " rows");
            ch.Tab = "memorial";
            check(Rows(ch) >= 3, "fake p13: Chronicle: the memorial tab draws rows");
        }

        // ------------------------------------------------------------------------------------ endgame windows
        static void Endgame(Action<bool, string> check)
        {
            var s = NewSession();
            var eg = s.Endgame;
            Ask(s, DescentState.Opcode, "open");
            var lines = DescentView.InfoLines(eg.Descent.Info);
            DescentView.EntryButtons(eg.Descent.Info, out var normal, out var weekly);
            check(eg.Descent.Info != null && eg.Descent.InfoVisible && lines.Count >= 6 && DescentView.Craft(eg.Descent.Info, out string craft) && craft.Length > 0 && normal.Can && normal.Text.Contains("free") && weekly.Can && weekly.Text.Contains("sigil"),
                "fake p13: Descent: " + lines.Count + " info lines, the forge and the entry buttons (" + (eg.Descent.Info != null) + " " + eg.Descent.InfoVisible + " " + normal.Can + " " + normal.Text + " " + weekly.Can + ")");

            Ask(s, InvasionState.Opcode, "calendar", "{'open':true}");
            check(eg.Invasion.CalendarVisible && eg.Invasion.Calendar.Count == 3 && Json.Text(eg.Invasion.Calendar[0], "name").Contains("invades"), "fake p13: Invasion: the calendar lists 3 events");

            Ask(s, SiegeState.Opcode, "open");
            check(eg.Siege.Info != null && eg.Siege.Visible && eg.Siege.CountdownText(eg.Siege.InfoAt).StartsWith("Starts in") && Eg.Objects(eg.Siege.Info, "signups").Count == 2 && Eg.Strings(eg.Siege.Info, "rules").Count == 2,
                "fake p13: Siege: info, countdown, 2 signed up guilds, 2 rules");

            Ask(s, ArenaState.Opcode, "open");
            var a = eg.Arena;
            check(a.State != null && a.Visible && !a.InQueue && !a.InMatch && Eg.Objects(a.State, "recent").Count == 2 && a.RulesLine().Contains("260") && a.StatusText(0).Length > 0
                && ArenaText.SeasonLine(Json.Get(Json.Get(Json.Get(a.State, "season"), "brackets"), "1v1"), 3, out _, out _).Contains("Gold") && ArenaText.SeasonLine(Json.Get(Json.Get(Json.Get(a.State, "season"), "brackets"), "2v2"), 3, out _, out _).Contains("placement"),
                "fake p13: Arena: ratings, season cards (placed and placing), 2 recent matches, the rules line");

            Ask(s, BattlegroundState.Opcode, "open");
            var b = eg.Battleground;
            var season = Json.Get(b.State, "season");
            var card = BgView.Card(Json.Get(Json.Get(season, "brackets"), "bg"), Json.Get(season, "tiers"), 5);
            check(b.State != null && b.Visible && !b.InQueue && b.CanQueue && BgView.RoleOptions(b.State).Count == 3 && BgView.RoleOptions(b.State).Any(r => r.Chosen && r.Key == "dps") && card.Tier == "Platinum" && Eg.Objects(b.State, "vendor").Count == 3
                && BgView.VendorRow(Eg.Objects(b.State, "vendor")[0], Json.Number(b.State, "honor")).Can && BgView.HonorLine(b.State).Contains("640"), "fake p13: Battleground: queue page, roles, season card, vendor rows");

            // the atlases: tree first, then the state
            Ask(s, AtlasState.RiftOpcode, "open", "{'tree':true}");
            var ra = eg.RiftAtlas;
            check(ra.Tree != null && ra.Tree.Nodes.Count == 7 && ra.Tree.Branches.Count == 2 && ra.Ix.Adj[1].Count == 3 && ra.Alloc.Count == 2 && ra.Done.Contains("c1.1") && ra.Points == 3, "fake p13: Rift atlas: 7 nodes, 2 branches, 2 allocated, 3 points");
            var rows = ra.Grid();
            check(rows.Count == 5 && rows[0].Cells.Count == 3 && rows[0].Cells[0].Done && rows[4].Cells.Count == 1 && AtlasView.PointsLine(ra.State) == "3" && ra.StatusOf(5) == "avail" && ra.StatusOf(2) == "alloc",
                "fake p13: Rift atlas: the grid has 2 theme rows, Flawless, Swift and Omens; node 5 is open to the points (rows " + rows.Count + " " + (rows.Count > 0 ? rows[0].Cells.Count + "" : "") + " " + AtlasView.PointsLine(ra.State) + " " + ra.StatusOf(5) + " " + ra.StatusOf(2) + ")");
            Ask(s, AtlasState.WaystoneOpcode, "open", "{'tree':true}");
            var wa = eg.WaystoneAtlas;
            var wrows = wa.Grid();
            check(wa.IsWaystone && wa.Tree != null && wa.Tree.Nodes.Count == 7 && wa.Alloc.Count == 2 && wrows.Count == 2 && wrows[0].Cells.Count == 2 && wrows[0].Cells[0].Done && wrows[1].Cells[0].Done, "fake p13: Waystone atlas: tree, state and the server's own grid rows");
            // a client that has the tree asks without it
            var plain = FakeModules.Answer(AtlasState.RiftOpcode, Request("open", "{'tree':false}"));
            check(plain.Count == 1 && plain[0].Action == "state", "fake p13: Rift atlas: no tree when the client asks without one");
        }

        // ------------------------------------------------------------------------------------ item and world windows
        static void Items(Action<bool, string> check)
        {
            var s = NewSession();
            var u = s.Utils;
            Ask(s, OrbExchangeState.Opcode, "open");
            check(u.Orbs.Meta != null && u.Orbs.Base == "fate" && u.Orbs.OrbKeys().Count == 2 && u.Orbs.Have("fate") == 20 && u.Orbs.GoldHeld() == 1200000, "fake p13: Orb Exchange: meta, the first orb is the base");
            Ask(s, OrbExchangeState.Opcode, "book", "{'base':'fate','quote':'gold','seq':1}");
            Ask(s, OrbExchangeState.Opcode, "mine");
            var book = OrbExchangeState.BookRows(u.Orbs.Book);
            check(u.Orbs.Book != null && book.Count == 5 && book.Count(r => r.Kind == "ask") == 2 && book.Count(r => r.Kind == "bid") == 2 && Json.List(u.Orbs.Mine, "open").Count == 1 && Json.List(u.Orbs.Mine, "fills").Count == 1
                && PriceChartPoints(u.Orbs.Book) == 3, "fake p13: Orb Exchange: the book has 2 asks, a spread and 2 bids, the chart 3 points, one open order and one fill");
            // a book for another pair than the open one is ignored (the Unity rule), the sample answers the pair it is asked for
            var other = FakeModules.Answer(OrbExchangeState.Opcode, Request("book", "{'base':'upheaval','quote':'fate','seq':2}"));
            check(other.Count == 1 && Json.Text(other[0].Root, "action") == "book" && Json.Text(Json.Get(other[0].Root, "data"), "base") == "upheaval", "fake p13: Orb Exchange: the book answers the pair that is asked");

            Ask(s, GambleState.Opcode, "open");
            check(u.Gamble.State != null && u.Gamble.Cells().Count == 4 && u.Gamble.SoldCount() == 1 && u.Gamble.Near && u.Gamble.Cells().Count(c => c.CanBuy) == 3 && u.Gamble.OddsText().Contains("Rare") && u.Gamble.Header().Length > 0,
                "fake p13: Gamble: 4 crates, 1 sold, 3 can be bought, the odds");

            Ask(s, EmberCacheState.Opcode, "open");
            var em = u.Ember;
            check(em.State != null && em.Visible && em.Tiers().Count == 3 && em.Tiers()[0].Reached && !em.Tiers()[1].Reached && EmberCacheState.SourceRows(Json.Get(em.State, "src")).Count == 3 && em.BookRows().Count == 9 && em.TodayLine().Contains("55"),
                "fake p13: Ember Cache: 3 tiers, 3 sources, the day book (" + (em.State != null) + " " + em.Visible + " " + em.Tiers().Count + " " + EmberCacheState.SourceRows(Json.Get(em.State, "src")).Count + " " + em.BookRows().Count + " " + em.TodayLine() + ")");

            Ask(s, LoadoutsState.Opcode, "open");
            var lo = u.Loadouts;
            check(lo.State != null && lo.Selected == 1 && lo.SlotRow(lo.SlotOf(1)).Tag == "ACTIVE" && lo.SlotRow(lo.SlotOf(2)).Tag == "CHECK" && lo.SlotRow(lo.SlotOf(3)).Title == "Empty slot" && lo.SlotRow(lo.SlotOf(4)).Title == "Locked slot"
                && lo.Summary(lo.SlotOf(2), "").Count >= 6 && lo.Icons().Count == 3, "fake p13: Loadouts: an active, a build to check, an empty and a locked slot");

            Ask(s, SpellSupportsState.Opcode, "open");
            var su = u.Supports;
            check(su.State != null && su.Visible && su.Spells().Count == 2 && su.Runes().Count == 2 && su.Bar.Count == 1 && su.BarWords.Count == 2 && su.Socket(su.SpellById(1), 1, 0).HasRune && su.Socket(su.SpellById(1), 3, 0).Button1On
                && su.CanCombine(su.RuneById(6)) && su.BarRunes(1).Count == 1, "fake p13: Spell supports: 2 spells, 2 runes, a socketed rune, a socket that can be opened, the bar data");

            Ask(s, PactState.Opcode, "open");
            var pa = u.Pact;
            string line;
            check(pa.Status != null && pa.Visible && pa.StatusTitle(out line) == "Chaos Pact active" && line.Contains("24 days") && pa.ShelfRows().Count == 3 && pa.LimitRows().Count == 2 && pa.BuildRows().Count == 6 && pa.BuildRows()[0].Saved
                && pa.ClaimText(out bool canClaim).Contains("5") && canClaim && pa.SpecialText().Length > 0, "fake p13: Pact: active, 3 shelf rows, 2 limits, 6 build slots, a claim");

            Ask(s, CandlemarksState.Opcode, "open");
            var ca = u.Candles;
            var offers = ca.Offers();
            check(ca.State != null && offers.Count == 3 && offers[2].Owned && offers[0].CanBuy && offers[1].CanBuy && ca.HeaderBalance().Contains("14") && CandlemarksState.OfferTitle(offers[1]).Contains("Vorn"), "fake p13: Candlemarks: 3 offers (one owned), the balance");

            // the loot filter model lives in the Loot window: a model of its own on the session's extended opcodes
            var model = new LootFilterModel(s.Ext) { Clock = () => 1000 };
            Ask(s, LootFilterModel.Opcode, "sync");
            check(model.Loaded && model.Unlocked && model.Presets.Count == 2 && model.Kills.Count == 1 && model.Kills[0].Items.Count == 3 && model.Kills[0].Monster == "Ghoul" && model.CountTotal.Values.Sum() > 100 && model.Settings.Highlight == 3,
                "fake p13: Loot filter: settings, 2 presets, the rule counters and a kill with 3 items");
            Ask(s, LootFilterModel.Opcode, "open");
            check(model.Loaded && model.Kills.Count == 1, "fake p13: Loot filter: open answers the settings alone");
        }

        static int PriceChartPoints(object book) => PriceChart.Points(Json.Get(book, "points")).Count;

        static void World(Action<bool, string> check)
        {
            var s = NewSession();
            var h = s.Utils.Hideout;
            Ask(s, HideoutState.Opcode, "open");
            Ask(s, HideoutState.Opcode, "visits");
            check(h.Loaded && h.Visible && h.HasInside && h.Inside.IsOwner && h.Layout.W == 9 && h.Layout.Reserved.Count == 3 && h.Catalogue.Count == 3 && h.Placed.Count == 2 && h.Themes.Count == 2 && h.Permissions.Count == 2
                && h.Categories.Count == 3 && h.CountText().Contains("2 / 30") && h.Friends.Count == 1 && h.Recent.Count == 1 && h.ShowLikes.Count == 1 && h.RowOf("banner").WallW != null && !h.RowOf("banner").Owned,
                "fake p13: Hideout: layout, 3 decorations, 2 placed, themes, permissions and the visits lists");
            check(HideoutState.Filter(h.Catalogue, "all", "all", false, "").Count == 3 && HideoutState.Filter(h.Catalogue, "floor", "all", false, "").Count == 1 && HideoutState.Filter(h.Catalogue, "all", "all", true, "").Count == 2, "fake p13: Hideout: the filters find the decorations");
        }

        /// <summary>The server sends open = 1 (a number, not true) in the hunt tracker state and the Ember Cache state (hunt.lua, embercache.lua): the Unity parsers read it as "show the window".</summary>
        static void OpenNumber(Action<bool, string> check)
        {
            var s = NewSession();
            string wire = ExtOpcodes.ToWire("{\"action\":\"state\",\"data\":{\"open\":1,\"t\":60,\"p\":0,\"xp\":100,\"xph\":6000,\"lvl\":2,\"left\":0,\"ttl\":0}}");
            foreach (var part in ExtChunks.Split(wire)) s.Ext.Receive(HuntTracker.Opcode, part);
            check(s.Progress.Hunt.HasState && s.Progress.Hunt.OpenRequested, "fake p13: hunt tracker: a state with open = 1 asks for the window");
            var s2 = NewSession();
            foreach (var part in ExtChunks.Split(ExtOpcodes.ToWire("{\"action\":\"state\",\"data\":{\"open\":1,\"week\":{\"pts\":1,\"got\":0,\"sparks\":0,\"ends\":10,\"tiers\":[]},\"day\":{\"pts\":0,\"goal\":10},\"src\":[],\"book\":{}}}"))) s2.Ext.Receive(EmberCacheState.Opcode, part);
            check(s2.Utils.Ember.Visible, "fake p13: Ember Cache: a state with open = 1 shows the window");
            var s3 = NewSession();
            foreach (var part in ExtChunks.Split(ExtOpcodes.ToWire("{\"action\":\"state\",\"data\":{\"week\":{\"pts\":1,\"got\":0,\"sparks\":0,\"ends\":10,\"tiers\":[]},\"day\":{\"pts\":0,\"goal\":10},\"src\":[],\"book\":{}}}"))) s3.Ext.Receive(EmberCacheState.Opcode, part);
            check(!s3.Utils.Ember.Visible, "fake p13: Ember Cache: a state without open does not show the window");
        }

        // ------------------------------------------------------------------------------------ the trade window (base protocol)
        static void TradeChecks(Action<bool, string> check)
        {
            var p = new GameParser(new World(DatFile.Parse(Program.SyntheticDat())));
            check(FakeModules.TradePartner.Length > 0 && FakeModules.TradeOwn.Length == 2 && FakeModules.TradeTheirs.Length == 1, "fake p13: the trade sample has a partner and two offers");
            // ids 101 (a counted coin of the synthetic dat) and 100 (a plain item), like PlayTests
            var own = new[] { new[] { 101, 5 }, new[] { 100, 1 } };
            var theirs = new[] { new[] { 100, 1 } };
            Func<int, bool> counted = id => id == 101, phased = id => id == 101;   // 101 has a count and a phase byte in the synthetic dat (PlayTests: 101, 0xFF, 5, 0)
            p.Parse(FakeModules.TradePacket(0x7D, "Vex", own, counted, phased));
            p.Parse(FakeModules.TradePacket(0x7E, "Vex", theirs, counted, phased));
            var t = p.PlayerTrade;
            check(t.Open && t.Own.Name == "Vex" && t.Own.Items.Count == 2 && t.Own.Items[0].Id == 101 && t.Own.Items[0].Count == 5 && t.Counter.Name == "Vex" && t.Counter.Items.Count == 1 && t.Counter.Items[0].Id == 100,
                "fake p13: trade: 0x7D and 0x7E from the sample open the window with both offers");
            var sent = new List<byte[]>();
            t.Send = sent.Add;
            check(t.Accept() && sent.Count == 1, "fake p13: trade: both sides filled, so Accept works");
            // an animated item carries its phase byte
            var pk = FakeModules.TradePacket(0x7D, "A", new[] { new[] { 100, 1 } }, null, id => id == 100);
            check(pk.Length == 9 && pk[pk.Length - 1] == 0xFE && pk[pk.Length - 2] == 0xFF, "fake p13: trade: an animated item gets its phase byte after the mark");
        }

        // ------------------------------------------------------------------------------------ covered windows
        static void CoverChecks(Action<bool, string> check)
        {
            var a = new SmokeBox(100, 100, 200, 100);
            check(SmokeCover.Share(a, null) == 0f && SmokeCover.Share(a, new List<SmokeBox>()) == 0f, "cover: nothing above, nothing hidden");
            check(Math.Abs(SmokeCover.Share(a, new List<SmokeBox> { new SmokeBox(0, 0, 80, 80) }) - 0f) < 1e-6f, "cover: a window beside it hides nothing");
            check(Math.Abs(SmokeCover.Share(a, new List<SmokeBox> { new SmokeBox(0, 0, 1000, 1000) }) - 1f) < 1e-6f && SmokeCover.Covered(1f), "cover: a window over it hides all of it");
            check(Math.Abs(SmokeCover.Share(a, new List<SmokeBox> { new SmokeBox(100, 100, 100, 100) }) - 0.5f) < 1e-6f && SmokeCover.Covered(0.5f) && !SmokeCover.Covered(0.49f), "cover: the left half hidden is covered at the limit");
            // two covering windows that overlap each other count once: the left 150 of 200 (0.75) with an overlap of 50
            check(Math.Abs(SmokeCover.Share(a, new List<SmokeBox> { new SmokeBox(100, 100, 100, 100), new SmokeBox(150, 100, 100, 100) }) - 0.75f) < 1e-6f, "cover: overlapping windows above count once");
            // a window poking out of the rect is cut to it
            check(Math.Abs(SmokeCover.Share(a, new List<SmokeBox> { new SmokeBox(250, 50, 500, 100) }) - 0.125f) < 1e-6f, "cover: only the part inside the rect counts: " + SmokeCover.Share(a, new List<SmokeBox> { new SmokeBox(250, 50, 500, 100) }));
            check(SmokeCover.Share(a, new List<SmokeBox> { new SmokeBox(float.NaN, 0, 10, 10) }) == 0f && SmokeCover.Share(new SmokeBox(0, 0, 0, 0), new List<SmokeBox> { new SmokeBox(0, 0, 10, 10) }) == 0f && SmokeCover.Share(new SmokeBox(float.NaN, 0, 1, 1), new List<SmokeBox> { new SmokeBox(0, 0, 10, 10) }) == 0f,
                "cover: NaN and empty rects give 0");
            // two small windows in a corner each hide less than half, together more
            var big = new SmokeBox(0, 0, 400, 300);
            var parts = new List<SmokeBox> { new SmokeBox(0, 0, 400, 100), new SmokeBox(0, 100, 400, 100) };
            check(Math.Abs(SmokeCover.Share(big, parts) - 2f / 3f) < 1e-5f && SmokeCover.Covered(SmokeCover.Share(big, parts)), "cover: two strips together hide two thirds");

            // the record and the json carry it, and it is not a problem
            var rep = new SmokeReport();
            var r = rep.Begin("win:ParentWindow", "window");
            r.HasRect = true; r.Rect = new SmokeBox(10, 10, 300, 200); r.CoverShare = 0.8f; r.Covered = true;
            rep.End();
            var r2 = rep.Begin("win:Other", "window");
            r2.CoverShare = 0f;
            rep.End();
            string json = rep.ToJson(1280, 720);
            check(!r.Problem && rep.CoveredCount == 1 && rep.WithProblems == 0, "cover: a covered window is reported but not a problem");
            check(json.Contains("\"covered\":1") && json.Contains("\"covered\":true,\"coverShare\":0.8") && json.Contains("\"covered\":false,\"coverShare\":0"), "cover: window_smoke.json has covered and coverShare per window and the count in the summary");
            var plain = new SmokeReport();
            plain.Begin("win:X", "window"); plain.End();
            check(plain.ToJson(1280, 720).Contains("\"covered\":false") && !plain.ToJson(1280, 720).Contains("coverShare"), "cover: a window that was not measured has no coverShare");
        }
    }
}
