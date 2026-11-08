// Collections, seasons and crafting (O433 phase 4, track N): achievements 250, bestiary 253, charms 198, season pass 227, seasons 246, daily 207,
// weekly chest 117, cosmetics and unlocks 225, transmog 212, pets 254, professions 195, crafting bench 232, crafting tables 91, craft skills (0xA1).
// The messages are the ones the main client's *_test.lua files and the server scripts show.
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Chaos.Core.Tests
{
    static class CollectTests
    {
        static string Text(byte[] sent) => Encoding.UTF8.GetString(sent, 4, sent.Length - 4);

        sealed class Rig
        {
            public readonly ExtOpcodes Ext = new ExtOpcodes();
            public readonly List<string> Sent = new List<string>();
            public double Now;
            public Rig() { Ext.Transmit = p => Sent.Add(Text(p)); }
            public void Recv(byte op, string json) => Ext.Receive(op, ExtOpcodes.ToWire(json));
            public string Last => Sent.Count > 0 ? Sent[Sent.Count - 1] : "";
        }

        public static void Run(Action<bool, string> check)
        {
            Achievements(check);
            Bestiary(check);
            Charms(check);
            Pass(check);
            Season(check);
            Daily(check);
            Weekly(check);
            Cosmetics(check);
            Transmog(check);
            Pets(check);
            Professions(check);
            Crafting(check);
            CraftTable(check);
            Helpers(check);
        }

        static void Achievements(Action<bool, string> check)
        {
            var rig = new Rig();
            var a = new AchievementsState(rig.Ext);
            a.Toggle();
            check(rig.Last == "{\"action\":\"open\",\"data\":{}}", "achievements: the toggle asks the server: " + rig.Last);
            rig.Recv(250, "{\"action\":\"state\",\"data\":{\"points\":30,\"accountPoints\":55,\"unlocked\":2,\"total\":3,\"maxPoints\":900,\"open\":true," +
                "\"categories\":[{\"key\":\"hunt\",\"name\":\"Hunting\",\"done\":1,\"total\":2,\"points\":10,\"max\":40}],\"recent\":[{\"name\":\"First Blood\",\"points\":5}],\"titlesOn\":true," +
                "\"titles\":[{\"text\":\"Slayer\"}],\"activeTitle\":\"Slayer\"}}");
            check(a.WantOpen && !a.Visible, "achievements: the window waits for the list");
            rig.Recv(250, "{\"action\":\"list\",\"data\":{\"first\":true,\"last\":false,\"rows\":[{\"n\":\"First Blood\",\"p\":5,\"d\":\"Kill one.\",\"c\":\"hunt\",\"t\":1,\"v\":1,\"u\":1700000000,\"ti\":\"Slayer\"}]}}");
            check(a.Rows.Count == 0, "achievements: rows are held until the last part");
            rig.Recv(250, "{\"action\":\"list\",\"data\":{\"first\":false,\"last\":true,\"rows\":[{\"n\":\"Secret\",\"p\":50,\"d\":\"???\",\"c\":\"hunt\",\"t\":10,\"v\":3,\"u\":0,\"h\":1},{\"n\":\"Walker\",\"p\":10,\"d\":\"Walk.\",\"c\":\"misc\",\"t\":2000,\"v\":500,\"u\":0,\"r\":\"A boots\"}]}}");
            check(a.Rows.Count == 3 && a.Visible && !a.WantOpen, "achievements: three rows, the window shows");
            var all = AchievementsState.Filter(a.Rows, AchievementsState.All, true);
            check(all[0].Name == "First Blood" && all[1].Name == "Secret", "achievements: unlocked first, the rest in server order");
            var recent = AchievementsState.Filter(a.Rows, AchievementsState.Recent, false);
            check(recent.Count == 1 && recent[0].Name == "First Blood", "achievements: recent keeps the unlocked");
            check(AchievementsState.Filter(a.Rows, "misc", true).Count == 1, "achievements: filter by category");
            check(AchievementsState.PercentOf(a.Rows[2]) == 25 && AchievementsState.PercentOf(a.Rows[0]) == 100, "achievements: percent");
            check(AchievementsState.ProgressText(a.Rows[1]) == "???" && AchievementsState.ProgressText(a.Rows[2]) == "500 / 2,000", "achievements: hidden and plain progress text");
            check(AchievementsState.ExtraText(a.Rows[2]) == "Reward: A boots" && AchievementsState.ExtraText(a.Rows[0]) == "Title: Slayer", "achievements: extra line");
            check(CF.Date(1700000000) == "2023-11-14", "achievements: date");
            check(a.SummaryText() == "Points: 30   -   Account: 55   -   Unlocked: 2 / 3", "achievements: summary: " + a.SummaryText());
            check(a.RecentText() == "Recent: First Blood (+5)" && AchievementsState.CategoryLabel(CF.Rows(CF.G(a.State, "categories"))[0]) == "Hunting  1/2", "achievements: recent line and category label");
            check(a.TitlesOn && a.TitleOptions().Count == 1 && a.ActiveTitle == "Slayer", "achievements: titles");
            a.SetTitle("none");
            check(rig.Last == "{\"action\":\"title\",\"data\":{\"title\":\"none\"}}", "achievements: title packet");
            rig.Recv(250, "{\"action\":\"track\",\"data\":{\"ap\":120,\"steps\":[{\"n\":\"Ember\",\"k\":\"killfx\",\"p\":100,\"d\":\"Burns. Reward track: 100 points.\"},{\"n\":\"Azure\",\"k\":\"chatcolor\",\"p\":500,\"c\":\"#4a8cff\"}]," +
                "\"cats\":[{\"key\":\"hunt\",\"cn\":\"Hunting\",\"n\":\"Hunter\",\"k\":\"lootbeam\",\"t\":2,\"dn\":1,\"x\":0,\"ti\":\"Hunter\"}]}}");
            check(AchievementsState.TrackReached(a.Track) == 1 && AchievementsState.TrackPercent(a.Track) == 5, "achievements: track reached and percent: " + AchievementsState.TrackPercent(a.Track));
            check(AchievementsState.TrackText(a.Track) == "120 / 500 account points  -  next: Azure (Chat name colour)", "achievements: track text: " + AchievementsState.TrackText(a.Track));
            var rows = AchievementsState.TrackRows(a.Track);
            check(rows.Count == 3 && rows[0].Done && rows[0].Desc == "Burns." && rows[1].Color == "#4a8cff" && rows[2].Progress == "1 / 2 achievements" && rows[2].Right == "Category", "achievements: track rows");
            check(AchievementsState.CategoryReward(a.Track, "hunt").StartsWith("Complete all 2: title Hunter + Hunter (Loot label accent)"), "achievements: category reward line");
            rig.Sent.Clear();
            a.Visible = true;
            rig.Recv(250, "{\"action\":\"unlock\",\"data\":{}}");
            check(rig.Last == "{\"action\":\"get\",\"data\":{}}", "achievements: an unlock while open asks again");
        }

        static void Bestiary(Action<bool, string> check)
        {
            var rig = new Rig();
            var b = new BestiaryState(rig.Ext);
            b.Query();
            check(rig.Last == "{\"action\":\"query\",\"data\":{}}", "bestiary: the tracker query");
            rig.Recv(253, "{\"action\":\"summary\",\"data\":{\"known\":2,\"total\":3,\"completed\":1,\"percent\":33.3,\"points\":12,\"stagePoints\":9,\"taskPoints\":3,\"count\":3,\"open\":true," +
                "\"rank\":{\"name\":\"Scout\",\"exp\":1,\"next\":50,\"nextName\":\"Hunter\"},\"cats\":[{\"key\":\"beast\",\"name\":\"Beasts\",\"known\":1,\"completed\":0,\"total\":2},{\"key\":\"undead\",\"name\":\"Undead\",\"known\":1,\"completed\":1,\"total\":1}]," +
                "\"diffs\":[{\"key\":\"easy\",\"name\":\"Easy\"}],\"stages\":[\"Seen\",\"Studied\",\"Known\",\"Mastered\"]}}");
            check(b.Visible && rig.Last == "{\"action\":\"list\",\"data\":{}}" && b.ListAsked, "bestiary: the summary opens the window and asks the list once");
            check(b.HeaderText() == "Known 2 / 3   Completed 1 (33.3%)   Points 12   Rank: Scout", "bestiary: header: " + b.HeaderText());
            check(b.HeaderTip().Contains("Next rank: Hunter at 50 points."), "bestiary: header tip");
            rig.Recv(253, "{\"action\":\"list\",\"data\":{\"first\":true,\"last\":false,\"rows\":[[1,\"Rat\",\"beast\",\"easy\",1,12,2,100],[2,\"Wolf\",\"beast\",\"easy\",5,0,0,101]]}}");
            check(!b.ListComplete, "bestiary: list part");
            rig.Recv(253, "{\"action\":\"list\",\"data\":{\"first\":false,\"last\":true,\"rows\":[[3,\"Ghoul\",\"undead\",\"easy\",20,300,4,102]]}}");
            check(b.ListComplete && b.Rows.Count == 3 && !b.ListAsked, "bestiary: list complete");
            check(rig.Last == "{\"action\":\"entry\",\"data\":{\"id\":1}}" && b.SelectedId == 1, "bestiary: the first known monster is selected: " + rig.Last);
            check(b.Filtered().Count == 3, "bestiary: all");
            b.SelectedCat = "beast";
            check(b.Filtered().Count == 2, "bestiary: category");
            b.KnownOnly = true; b.Search = " RA ";
            check(b.Filtered().Count == 1 && b.Filtered()[0].Name == "Rat", "bestiary: known only and search");
            var page = BestiaryState.Paged(Enumerable.Range(0, 130).ToList(), 9, 60, out int shown, out int pages);
            check(shown == 3 && pages == 3 && page.Count == 10, "bestiary: paging clamps");
            check(b.StageName(0) == "Undiscovered" && b.StageName(3) == "Known" && BestiaryState.StageName(9, new List<object>()) == "Stage 9", "bestiary: stage names");
            check(BestiaryState.KillText(12, 50.0) == "Kills 12 / 50" && BestiaryState.KillText(300, null) == "Kills 300", "bestiary: kill text");
            check(BestiaryState.StagePercent(30, new List<string> { "10", "50", "100" }) == 50 && BestiaryState.StagePercent(500, new List<string> { "10" }) == 100, "bestiary: stage percent");
            check(BestiaryState.ChanceText(0.5) == "0.50%" && BestiaryState.ChanceText(2.5) == "2.5%" && BestiaryState.ChanceText(40) == "40%", "bestiary: chance text: " + BestiaryState.ChanceText(2.5));
            check(BestiaryState.Plural("Wolf", 2) == "Wolfs" && BestiaryState.Plural("Spy", 3) == "Spies" && BestiaryState.Plural("Fox", 2) == "Foxes" && BestiaryState.Plural("Orc", 1) == "Orc", "bestiary: plural");
            var el = CF.Raw(Json.Parse("[{\"name\":\"Fire\",\"pct\":-25},{\"name\":\"Ice\",\"pct\":50}]"));
            check(BestiaryState.ElementsText(el) == "Fire +25%, Ice -50%", "bestiary: elements: " + BestiaryState.ElementsText(el));
            var reward = Json.Parse("{\"gold\":1500,\"chaos\":2,\"exp\":2000000,\"points\":3}");
            check(BestiaryState.RewardText(reward) == "1.5k gold, 2 Orbs of Upheaval, 2M exp, 3 points" && BestiaryState.RewardShort(reward) == "1.5k gold, 2 Upheaval, 2M exp, 3 points", "bestiary: reward text: " + BestiaryState.RewardText(reward));
            rig.Sent.Clear();
            rig.Recv(253, "{\"action\":\"kill\",\"data\":{\"id\":1,\"kills\":13,\"stage\":2,\"next\":50}}");
            check(b.ById[1].Kills == 13 && rig.Sent.Count == 0, "bestiary: a kill within the stage updates the row only");
            rig.Recv(253, "{\"action\":\"entry\",\"data\":{\"id\":1,\"kills\":13,\"stage\":2,\"next\":50,\"th\":[10,50,100]}}");
            rig.Recv(253, "{\"action\":\"kill\",\"data\":{\"id\":1,\"kills\":50,\"stage\":3,\"next\":100}}");
            check(rig.Sent.Contains("{\"action\":\"entry\",\"data\":{\"id\":1}}") && rig.Sent.Contains("{\"action\":\"summary\",\"data\":{}}"), "bestiary: a stage change asks the entry and the summary");
            b.Visible = false;
            b.TakeTask(1); b.Accept("hunt:rat"); b.Abandon("hunt:rat"); b.Reroll();
            check(rig.Sent.Skip(rig.Sent.Count - 4).SequenceEqual(new[]
            {
                "{\"action\":\"take\",\"data\":{\"id\":1}}", "{\"action\":\"accept\",\"data\":{\"key\":\"hunt:rat\"}}", "{\"action\":\"abandon\",\"data\":{\"key\":\"hunt:rat\"}}", "{\"action\":\"reroll\",\"data\":{}}",
            }), "bestiary: task packets");
            rig.Now = 10000;
            rig.Recv(253, "{\"action\":\"board\",\"data\":{\"active\":1,\"maxActive\":3,\"doneDay\":2,\"dailyLimit\":3,\"doneWeek\":5,\"weeklyLimit\":10,\"rerolls\":1,\"nextIn\":7200,\"offers\":[],\"tasks\":[]}}");
            check(BestiaryState.LimitsText(b.Board) == "Active 1 / 3   Today 2 / 3   This week 5 / 10", "bestiary: limits text");
            check(BestiaryState.AcceptBlock(b.Board) == "At most 3 kill tasks a day (completed and held).", "bestiary: accept block: " + BestiaryState.AcceptBlock(b.Board));
            check(BestiaryState.AcceptBlock(Json.Parse("{\"active\":0,\"maxActive\":3,\"doneDay\":0,\"dailyLimit\":3,\"doneWeek\":0,\"weeklyLimit\":10}")) == null, "bestiary: accept allowed");
            check(b.NextIn(0) == 7200, "bestiary: board timer");
            var task = Json.Parse("{\"kind\":\"hunt\",\"label\":\"Wolf\",\"required\":10}");
            check(BestiaryState.TaskText(task) == "Kill 10 Wolfs." && BestiaryState.TaskText(Json.Parse("{\"kind\":\"family\",\"label\":\"Undead\",\"required\":5,\"lo\":10,\"hi\":20}")) == "Kill 5 Undead of level 10-20.", "bestiary: task text");
            rig.Recv(253, "{\"action\":\"tracker\",\"data\":{\"rows\":[{\"k\":\"task\",\"label\":\"Rat\",\"p\":4,\"r\":10}]}}");
            check(b.TrackerRows.Count == 1 && BestiaryState.TrackerLine(b.TrackerRows[0], out int pct, out bool done) == "Rat 4/10" && pct == 40 && !done, "bestiary: tracker line");
            rig.Recv(253, "{\"action\":\"show\",\"data\":{\"tab\":\"tasks\"}}");
            check(b.Visible && b.Tab == "tasks", "bestiary: show tasks");
        }

        static void Charms(Action<bool, string> check)
        {
            var rig = new Rig();
            var c = new CharmsState(rig.Ext);
            rig.Recv(198, "{\"action\":\"state\",\"data\":{\"cols\":4,\"rows\":3,\"max\":2,\"shards\":7,\"cells\":[" +
                string.Join(",", Enumerable.Range(1, 3).SelectMany(y => Enumerable.Range(1, 4).Select(x => "{\"x\":" + x + ",\"y\":" + y + ",\"open\":" + (x <= 3 ? "true" : "false") + ",\"why\":\"level 100\"}"))) + "]," +
                "\"placed\":[{\"id\":9,\"ref\":\"p1\",\"x\":1,\"y\":1,\"w\":2,\"h\":1,\"name\":\"Ash\",\"rarity\":\"Glowing\",\"ilvl\":30}]," +
                "\"bag\":[{\"ref\":\"b1\",\"sid\":\"5\",\"iid\":\"77\",\"w\":1,\"h\":2,\"name\":\"Cinder\",\"rarity\":\"Rare\",\"ilvl\":20,\"salvage\":3,\"reforge\":4,\"mods\":[{\"t\":\"+5% fire\"}]}]," +
                "\"totals\":[{\"t\":\"+9% fire\",\"v\":9,\"cap\":9}],\"groups\":[{\"open\":true,\"text\":\"Level 100\",\"cells\":9}]}}");
            check(c.Cols == 4 && c.Placed.Count == 1 && c.Bag.Count == 1, "charms: state");
            check(c.Header() == "9 of 12 cells open  -  1 charms placed  -  7 charm shards", "charms: header: " + c.Header());
            check(c.CellAt(0, 0, out int x, out int y) && x == 1 && y == 1 && c.CellAt(46, 47, out x, out y) && x == 2 && y == 2 && !c.CellAt(500, 0, out _, out _) && !c.CellAt(-1, 0, out _, out _), "charms: cell under a point");
            check(c.Anchor(46 * 1 + 10, 10, 2, 1, out x, out y) && x == 1 && y == 1, "charms: a 2 wide charm anchors by its middle");
            var r = CharmsState.Rect(2, 2, 2, 1);
            check(r[0] == 46 && r[1] == 46 && r[2] == 90 && r[3] == 44, "charms: rect");
            var drag = CharmsState.DragOf(c.Bag[0], "bag");
            var drop = c.DropAction(drag, "grid", 46 * 2 + 5, 46 + 5, out string why);
            check(drop != null && drop.Action == "place" && CF.Int(drop.Data["x"]) == 3 && CF.Int(drop.Data["y"]) == 1 && drop.Data["ref"] as string == "b1" && drop.Data["iid"] as string == "77", "charms: place packet");
            var p = c.Preview(drag, 5, 46 + 5);
            check(p != null && !p.Ok && p.Why == "Another charm is in the way.", "charms: preview over a placed charm: " + p?.Why);
            var blocked = c.Preview(drag, 46 * 3 + 5, 46 + 5);
            check(!blocked.Ok && blocked.Why == "That cell is locked: level 100", "charms: a locked cell refuses: " + blocked.Why);
            var tooBig = c.Preview(new CharmDrag { W = 2, H = 2 }, 46 * 3 + 20, 46 * 2 + 20);
            check(!tooBig.Ok, "charms: outside the grid refuses");
            var movePlaced = c.DropAction(CharmsState.DragOf(c.Placed[0], "placed"), "grid", 46 * 2 + 5, 46 * 2 + 5, out why);
            check(movePlaced != null && movePlaced.Action == "move" && CF.Int(movePlaced.Data["id"]) == 9, "charms: move packet");
            check(c.DropAction(CharmsState.DragOf(c.Placed[0], "placed"), "grid", 46, 10, out why) == null && why == null, "charms: a drop on the same cell does nothing");
            var take = c.DropAction(CharmsState.DragOf(c.Placed[0], "placed"), "bag", 0, 0, out why);
            check(take != null && take.Action == "take" && c.DropAction(drag, "bag", 0, 0, out why) == null, "charms: a placed charm dropped on the list is taken out");
            check(c.DropAction(drag, "outside", 0, 0, out why) == null, "charms: a drop outside does nothing");
            rig.Sent.Clear();
            check(!c.CanSalvage, "charms: nothing selected");
            c.SelectedRef = "b1";
            check(c.CanSalvage && c.CanReforge, "charms: salvage and reforge enable");
            c.SalvageSelected(); c.ReforgeSelected();
            check(rig.Sent[0] == "{\"action\":\"salvage\",\"data\":{\"ref\":\"b1\",\"sid\":\"5\",\"iid\":\"77\"}}" && rig.Sent[1].StartsWith("{\"action\":\"reforge\""), "charms: salvage and reforge packets: " + rig.Sent[0]);
            check(CharmsState.Tooltip(c.Bag[0], false).Contains("Rare, item level 20, 1x2") && CharmsState.Tooltip(c.Bag[0], false).Contains("salvage: 3 shards, reforge: 4 shards") && CharmsState.Tooltip(c.Placed[0], true).Contains("Drag it to move it"), "charms: tooltips");
            check(CharmsState.Glows(c.Placed[0]) && !CharmsState.Glows(c.Bag[0]), "charms: glow by rarity");
            var totals = c.TotalsLines();
            check(totals[0].Key == "+9% fire  (cap)" && c.UnlockLines()[0].Key == "[open] Level 100: 9 cells", "charms: totals and unlocks");
            rig.Recv(198, "{\"action\":\"result\",\"data\":{\"ok\":false,\"text\":\"No room.\"}}");
            check(c.StatusText == "No room." && c.StatusColor == CharmsState.ColorBad, "charms: result");
            rig.Recv(198, "{\"action\":\"state\",\"data\":{\"cols\":4,\"rows\":3,\"cells\":[],\"bag\":[]}}");
            check(c.SelectedRef == null, "charms: the selection goes when the charm leaves the list");
        }

        static void Pass(Action<bool, string> check)
        {
            var rig = new Rig();
            var s = new PassState(rig.Ext);
            rig.Now = 0;
            rig.Recv(227, "{\"action\":\"state\",\"data\":{\"open\":true,\"season\":{\"id\":3,\"pass\":\"Ash Pass\",\"name\":\"Season 3\",\"tag\":\"[S3]\",\"status\":\"active\",\"endsIn\":90000}," +
                "\"tier\":2,\"maxTier\":3,\"into\":40,\"need\":100,\"premium\":false,\"claimed\":[\"10\",\"00\"],\"coins\":50," +
                "\"daily\":{\"resetIn\":3600,\"list\":[{\"text\":\"Kill 10\",\"target\":10,\"progress\":4,\"xp\":20}]},\"weekly\":7,\"sources\":[{\"name\":\"Hunt\",\"today\":3,\"cap\":10}]," +
                "\"offers\":[{\"what\":\"premium\",\"name\":\"Premium\",\"price\":300,\"full\":300},{\"what\":\"up\",\"name\":\"Upgrade\",\"price\":100,\"full\":300},{\"what\":\"x\",\"name\":\"X\",\"owned\":true}]}}");
            check(s.Visible && rig.Last == "{\"action\":\"tiers\",\"data\":{\"season\":3}}", "pass: state opens the window and asks the tiers: " + rig.Last);
            check(CF.G(s.State, "weekly") == null, "pass: a weekly that is no table is dropped");
            check(s.Title() == "Ash Pass - Season 3 [S3]" && s.TimerText(5000) == "Season ends in 1d 00h 59m", "pass: title and timer: " + s.TimerText(5000));
            int pct = PassState.Progress(s.State, out string ptext);
            check(pct == 40 && ptext == "40 / 100 XP to tier 3", "pass: progress");
            check(PassState.CellState(s.State, 1, 0) == "claimed" && PassState.CellState(s.State, 2, 0) == "claimable" && PassState.CellState(s.State, 2, 1) == "premium" && PassState.CellState(s.State, 3, 0) == "locked", "pass: cell states");
            check(PassState.ClaimableCount(s.State) == 1, "pass: claimable count");
            rig.Recv(227, "{\"action\":\"tiers\",\"data\":{\"season\":3,\"total\":3,\"rows\":[{\"tier\":1,\"free\":{\"text\":\"Gold\"}},{\"tier\":2,\"free\":{\"text\":\"Orb\"}}]}}");
            check(!s.Tiers.Complete, "pass: tiers incomplete");
            rig.Recv(227, "{\"action\":\"tiers\",\"data\":{\"season\":3,\"total\":3,\"rows\":[{\"tier\":3,\"free\":{\"text\":\"Key\"}}]}}");
            check(s.Tiers.Complete, "pass: tiers complete after the third");
            s.Claim(2, 0); s.ClaimAll();
            check(rig.Sent[rig.Sent.Count - 2] == "{\"action\":\"claim\",\"data\":{\"tier\":2,\"track\":0}}" && rig.Last == "{\"action\":\"claimAll\",\"data\":{}}", "pass: claim packets");
            bool en; string bt = PassState.OfferButton(CF.Rows(CF.G(s.State, "offers"))[1], out en);
            check(bt == "Upgrade 100" && en, "pass: upgrade button");
            check(PassState.OfferButton(CF.Rows(CF.G(s.State, "offers"))[2], out en) == "Owned" && !en && PassState.OfferButton(null, out en) == "" && PassState.OfferButton(Json.Parse("{}"), out en) == "Unavailable", "pass: owned button");
            var offer = CF.Rows(CF.G(s.State, "offers"))[0];
            s.AskBuy(offer, 300, null);
            check(s.ConfirmText == "Buy Premium for 300 Chaos Coins?", "pass: buy text");
            s.AskBuy(CF.Rows(CF.G(s.State, "offers"))[1], 100, null);
            check(s.ConfirmText.StartsWith("Upgrade to Upgrade for 100"), "pass: upgrade text");
            s.AskBuy(offer, 300, null);
            check(s.Confirm() && rig.Last == "{\"action\":\"buy\",\"data\":{\"what\":\"premium\",\"price\":300}}" && s.ConfirmBuyData == null, "pass: confirm sends the buy");
            s.AskGift(offer, " Kai ");
            check(rig.Last == "{\"action\":\"giftPrice\",\"data\":{\"what\":\"premium\",\"gift\":\"Kai\"}}", "pass: gift price asked");
            rig.Recv(227, "{\"action\":\"giftPrice\",\"data\":{\"what\":\"premium\",\"price\":280,\"name\":\"Kai\"}}");
            check(s.ConfirmText == "Give Premium to Kai for 280 Chaos Coins?" && s.Confirm() && rig.Last.Contains("\"gift\":\"Kai\""), "pass: the gift price answer asks for confirmation: " + rig.Last);
            string prog; int cp; bool done;
            check(PassState.Challenge(CF.Rows(CF.G(CF.G(s.State, "daily"), "list"))[0], out prog, out cp, out done) == "Kill 10" && prog == "4 / 10" && cp == 40 && !done, "pass: challenge row");
            check(s.DailyTitle(0) == "Daily challenges (new in 1h 00m 00s)", "pass: daily title");
            check(PassState.SourceLine(CF.Rows(CF.G(s.State, "sources"))[0]) == "Hunt 3 / 10", "pass: source line");
            rig.Recv(227, "{\"action\":\"notice\",\"data\":{\"text\":\"No coins.\"}}");
            check(s.Notice == "No coins.", "pass: notice");
            s.SetFrame(true);
            check(rig.Last == "{\"action\":\"frame\",\"data\":{\"on\":true}}", "pass: frame packet");
        }

        static void Season(Action<bool, string> check)
        {
            var rig = new Rig();
            var s = new SeasonState(rig.Ext);
            s.Sync();
            check(rig.Last == "{\"action\":\"sync\",\"data\":{}}", "season: sync");
            rig.Recv(246, "{\"action\":\"state\",\"data\":{\"open\":true,\"season\":{\"name\":\"Ember\",\"tag\":\"[E]\",\"status\":\"active\",\"endsIn\":7200,\"modifier\":{\"name\":\"Fury\",\"description\":\"More damage\"}}," +
                "\"mine\":{\"eligible\":true},\"track\":[{\"name\":\"Level 50\",\"reward\":\"A title\",\"value\":50,\"progress\":20},{\"name\":\"Level 10\",\"value\":10,\"progress\":10,\"unlocked\":true}],\"titles\":[\"Emberborn\"]}}");
            check(s.Visible && s.NameLine() == "Ember [E]" && s.ModifierLine() == "Season modifier Fury: More damage" && s.CanJoin, "season: overview");
            check(s.TimerText(1000) == "Ends in 1h 59m 59s" && s.TitlesLine() == "Season titles of your account: Emberborn", "season: timer and titles: " + s.TimerText(1000));
            check(s.MineText().StartsWith("This character can join Ember"), "season: mine text");
            string tp = SeasonState.TrackProgress(s.Track[0], out int pct, out bool un);
            check(tp == "20 / 50" && pct == 40 && !un && SeasonState.TrackProgress(s.Track[1], out pct, out un) == "Unlocked" && un && pct == 100, "season: track progress");
            s.AskJoin();
            check(rig.Last == "{\"action\":\"join\",\"data\":{\"confirm\":false}}", "season: join question");
            rig.Recv(246, "{\"action\":\"confirm\",\"data\":{\"text\":\"Terms.\",\"modes\":[{\"key\":\"hc\",\"name\":\"Hardcore\",\"short\":\"HC\",\"warning\":\"One life.\",\"hc\":true},{\"key\":\"ssf\",\"name\":\"Self-Found\",\"short\":\"SSF\",\"ssf\":true}]}}");
            check(s.JoinOpen && s.JoinChoices.Count == 3 && s.JoinChoices[0].Key == "standard" && s.JoinChoice.Key == "standard", "season: standard is added and chosen");
            check(SeasonJoin.CanJoin(s.JoinChoice, false), "season: standard needs no acknowledgement");
            s.SelectMode("hc");
            check(SeasonJoin.NeedsAck(s.JoinChoice) && !SeasonJoin.CanJoin(s.JoinChoice, false) && SeasonJoin.JoinLabel(s.JoinChoice) == "Join (one life)" && SeasonJoin.WarningText(s.JoinChoice) == "One life.", "season: hardcore needs the box");
            check(!s.ConfirmJoin(), "season: no join without the box");
            s.JoinAcked = true;
            check(s.ConfirmJoin() && rig.Last == "{\"action\":\"join\",\"data\":{\"confirm\":true,\"mode\":\"hc\"}}" && !s.JoinOpen, "season: join packet: " + rig.Last);
            check(SeasonJoin.WarningText(SeasonJoin.Find(s.JoinChoices, "ssf")) == "Self-Found", "season: the warning falls back to the name");
            rig.Recv(246, "{\"action\":\"state\",\"data\":{\"season\":{\"name\":\"Ember\",\"tag\":\"\",\"status\":\"active\",\"endsIn\":10},\"mine\":{\"seasonal\":true,\"hc\":true,\"heartbeat\":30,\"mode\":\"hc\",\"modeName\":\"Hardcore\"}}}");
            check(s.BeatSeconds == 30, "season: a Hardcore character starts the heartbeat");
            rig.Sent.Clear(); rig.Now = 0;
            s.Tick(0); s.Tick(10000); s.Tick(31000);
            check(rig.Sent.Count == 2 && rig.Sent[0] == "{\"action\":\"beat\",\"data\":{}}", "season: beats every 30 s: " + rig.Sent.Count);
            check(SeasonJoin.ModeLine(CF.G(s.State, "mine")) == "Mode: Hardcore." && SeasonJoin.ModeLine(Json.Parse("{\"fallen\":{\"level\":40,\"cause\":\"a troll\"}}")) == "Fallen in Hardcore at level 40. (a troll)", "season: mode line");
            s.ShowTab("journey");
            check(rig.Last == "{\"action\":\"journey\",\"data\":{}}" && s.Tab == "journey", "season: the journey tab asks");
            rig.Recv(246, "{\"action\":\"journey\",\"data\":{\"name\":\"Ash Road\",\"mode\":\"Hardcore\",\"current\":2,\"finished\":1,\"set\":\"Ash\",\"pieces\":1,\"piecesTotal\":4," +
                "\"chapters\":[{\"key\":\"a\",\"name\":\"Wake\",\"state\":\"done\",\"done\":3,\"total\":3},{\"key\":\"b\",\"name\":\"Walk\",\"state\":\"open\",\"done\":1,\"total\":4},{\"key\":\"c\",\"name\":\"Climb\",\"state\":\"locked\",\"level\":200,\"lockedWhy\":\"Level 200\"}]}}");
            check(s.Chapters.Count == 3 && s.Selected == 2 && s.JourneyTitle() == "Ash Road  -  Hardcore" && s.JourneySummary() == "Chapters 1 / 3   Ash set 1 / 4", "season: journey header: " + s.JourneySummary());
            check(SeasonState.ChapterLabel(s.Chapters[1], 2) == "II. Walk" && SeasonState.ChapterStatus(s.Chapters[0]) == "Complete" && SeasonState.ChapterStatus(s.Chapters[1]) == "1 / 4" && SeasonState.ChapterStatus(s.Chapters[2]) == "Lv 200" && SeasonState.ChapterNote(s.Chapters[2]) == "Locked: Level 200", "season: chapter rows");
            rig.Recv(246, "{\"action\":\"journeyChapter\",\"data\":{\"index\":2,\"objectives\":[{\"text\":\"Kill 10\",\"target\":10,\"progress\":4,\"only\":\"hc\"},{\"text\":\"Hardcore: Reach 20\",\"target\":1,\"done\":true,\"only\":\"hc\"}],\"rewards\":[{\"text\":\"Boots\",\"piece\":true}]}}");
            check(s.Details.ContainsKey(2), "season: chapter detail");
            var o1 = SeasonState.ObjectiveRow(Json.Parse("{\"text\":\"Kill 10\",\"target\":10,\"progress\":4,\"only\":\"hc\"}"), false);
            check(o1.Percent == 40 && o1.Label == "4 / 10" && o1.Tag == "Hardcore", "season: objective row");
            check(SeasonState.ObjectiveRow(Json.Parse("{\"text\":\"Hardcore: Reach 20\",\"only\":\"hc\",\"done\":true}"), false).Tag == null, "season: the tag is dropped when the text starts with it");
            check(SeasonState.ObjectiveRow(Json.Parse("{\"text\":\"Kill\",\"target\":5}"), true).Label == "Goal: 5", "season: preview objective");
            check(SeasonState.RewardLine(CF.Rows(CF.G(s.Details[2], "rewards"))[0]) == "Boots (set)", "season: reward line");
            rig.Recv(246, "{\"action\":\"journeyDone\",\"data\":{\"chapter\":true,\"text\":\"Wake\"}}");
            check(s.Banner == "Chapter complete: Wake!", "season: done banner");
            s.ShowTab("season");
            check(rig.Last == "{\"action\":\"journeyClose\",\"data\":{}}", "season: leaving the journey tab closes it");
            check(SeasonState.LastOpen(s.Chapters) == 2 && SeasonState.RomanOf(13) == "13", "season: last open chapter and roman numbers");
            rig.Recv(246, "{\"action\":\"journey\",\"data\":{\"none\":true}}");
            check(s.JourneyTitle() == "No journey this season" && s.Chapters.Count == 0, "season: no journey");
        }

        static void Daily(Action<bool, string> check)
        {
            var rig = new Rig();
            var d = new DailyState(rig.Ext);
            d.Toggle();
            check(rig.Last == "{\"action\":\"open\",\"data\":{}}", "daily: open");
            rig.Recv(207, "{\"action\":\"OpenDailyWindow\",\"data\":{\"Day\":2,\"TakenReward\":0,\"NextIn\":7200,\"Login\":1,\"DAILY_REWARDS\":[{\"ClientID\":3031,\"Count\":10},{\"ClientID\":3031,\"Count\":20},{\"ClientID\":3031,\"Count\":30},{\"ClientID\":3031,\"Count\":40},{\"ClientID\":3031,\"Count\":50},{\"ClientID\":3031,\"Count\":60},{\"ClientID\":3031,\"Count\":70}]," +
                "\"Streak\":6,\"Broken\":0,\"Best\":9,\"Grace\":1,\"GraceMax\":2,\"GraceUse\":0,\"Next\":{\"Days\":7,\"In\":1,\"Reward\":\"A frame\"},\"Title\":\"Loyal\",\"Cosmetics\":[{\"Name\":\"Ash\",\"Days\":14,\"Owned\":0},{\"Name\":\"Fire\",\"Days\":7,\"Owned\":1}]}}");
            check(d.Visible && d.Day == 4 && d.LoginOpen && d.Rewards.Count == 7, "daily: the client day is the server day + 2");
            check(d.CellState(3) == "claimed" && d.CellState(4) == "claimable" && d.CellState(5) == "next" && d.CellState(6) == "later", "daily: cell states");
            check(DailyState.ClientDay(5) == 7 && DailyState.ClientDay(6) == 1 && DailyState.ClientDay(7) == 1, "daily: the day wraps to 1");
            check(d.NextTimer(0, out int pct) == "02:00" && pct == 91, "daily: next timer: " + d.NextTimer(0, out pct) + " " + pct);
            check(d.Claim() && rig.Last == "{\"action\":\"calim\",\"data\":2}", "daily: claim sends the mapped server day as a bare number: " + rig.Last);
            check(d.StreakLine() == "Streak: 6 days" && d.BestLine() == "Best: 9 days" && d.GraceLine() == "Grace charges: 1 / 2" && d.MilestoneLine() == "Next milestone: 7 days (next claim): A frame" && d.TitleLine() == "Your title: Loyal", "daily: streak lines");
            check(d.CosmeticsLine() == "Streak cosmetics: Ash (14 days), Fire (7 days, owned)", "daily: cosmetics line: " + d.CosmeticsLine());
            rig.Recv(207, "{\"action\":\"OpenDailyWindow\",\"data\":{\"Day\":2,\"TakenReward\":1,\"NextIn\":60,\"DAILY_REWARDS\":[]}}");
            check(!d.HasStreak && !d.Claim() && d.CellState(4) == "claimed", "daily: no streak, nothing to claim after the claim");
            d.Hide();
            check(rig.Last == "{\"action\":\"closed\",\"data\":{}}" && !d.Visible, "daily: closing tells the server");
        }

        static void Weekly(Action<bool, string> check)
        {
            var rig = new Rig();
            var w = new WeeklyState(rig.Ext);
            w.Show();
            check(rig.Last == "{\"action\":\"open\",\"data\":{}}" && w.Visible, "weekly: open");
            rig.Recv(117, "{\"action\":\"state\",\"data\":{\"acts\":[{\"k\":\"dungeon\",\"done\":1,\"open\":1,\"lv\":50},{\"k\":\"rift\",\"done\":0,\"open\":1,\"lv\":80},{\"k\":\"tower\",\"done\":0,\"open\":0,\"lv\":300}],\"got\":1,\"need\":3,\"bonusNeed\":6,\"open\":3," +
                "\"chest\":{\"given\":0,\"gold\":2500000,\"it\":[{\"n\":3,\"name\":\"Orb\"}]},\"bonus\":{\"given\":0,\"lo\":1000,\"hi\":50000},\"endsIn\":200000,\"chests\":4}}");
            var rows = w.Rows();
            check(rows.Count == 3 && rows[0].Status == "Done" && rows[0].Color == WeeklyState.Done && rows[1].Status == "Not yet" && rows[2].Status == "Unlocks at level 300" && rows[2].Color == WeeklyState.Locked && rows[0].Name == "Dungeon", "weekly: rows");
            check(w.Head() == "1 of 3 activities done this week" && w.Ends() == "The week ends in 2 days" && w.ChestsLine() == "Chests opened so far: 4", "weekly: head: " + w.Head());
            check(w.RewardLine() == "2.5M gold, 3x Orb", "weekly: reward line: " + w.RewardLine());
            check(w.ChestLine(out string color) == "The chest opens at 3 of 3 activities." && color == WeeklyState.OpenColor, "weekly: chest line: " + w.ChestLine(out color));
            check(w.BonusLine(out color) == "All 6 activities add a bonus roll: 1k to 50k gold or orbs.", "weekly: bonus line: " + w.BonusLine(out color));
            check(WeeklyState.Left(3000.0) == "under an hour" && WeeklyState.Left(7300.0) == "2 h" && WeeklyState.Left(90000.0) == "1 day", "weekly: time left");
            w.Hide();
            check(rig.Last == "{\"action\":\"close\",\"data\":{}}" && !w.Visible, "weekly: close");
        }

        static void Cosmetics(Action<bool, string> check)
        {
            var rig = new Rig();
            var c = new CosmeticsState(rig.Ext);
            c.Hello(); c.AskWardrobe();
            check(rig.Sent[0] == "{\"action\":\"hello\",\"data\":{}}" && rig.Sent[1] == "{\"action\":\"wardrobe\",\"data\":{}}", "cosmetics: hello and wardrobe");
            rig.Recv(225, "{\"action\":\"state\",\"data\":{\"line\":\"mage\",\"lineName\":\"Mages\",\"rows\":[" +
                "{\"id\":11,\"kind\":\"spellskin\",\"line\":\"mage\",\"name\":\"Cinder\",\"owned\":true,\"selected\":true}," +
                "{\"id\":12,\"kind\":\"spellskin\",\"line\":\"mage\",\"name\":\"Frost\",\"owned\":false,\"how\":\"Reach level 100\"}," +
                "{\"id\":13,\"kind\":\"spellskin\",\"line\":\"knight\",\"lineName\":\"Knights\",\"name\":\"Iron\",\"owned\":true}," +
                "{\"id\":21,\"kind\":\"chatcolor\",\"name\":\"Azure\",\"owned\":true,\"color\":\"#4a8cff\"}]," +
                "\"collection\":[{\"key\":\"c1\",\"name\":\"Ember\",\"kind\":\"killfx\",\"kindName\":\"Kill effect\",\"owned\":true},{\"key\":\"c2\",\"name\":\"Ash\",\"kind\":\"footprint\",\"kindName\":\"Footprints\",\"owned\":false,\"how\":\"Win a duel\"}]," +
                "\"score\":{\"score\":42,\"next\":{\"points\":100,\"left\":58},\"milestones\":[{\"points\":25,\"done\":true,\"rewards\":[{\"k\":\"title\",\"n\":\"Collector\",\"f\":true}]}],\"groups\":[{\"g\":\"outfit\",\"n\":3,\"p\":9}]},\"open\":true}}");
            check(c.Visible, "cosmetics: state opens the window");
            var rows = c.TabRows();
            check(rows.Count == 4 && rows[0].Id == "0" && !rows[0].Selected && rows[1].Id == "11" && rows[1].Selected && rows[2].Id == "13" && rows[2].OtherLine && rows[3].Id == "12", "cosmetics: spell skin rows: default, mine, then the other line (owned), the locked one last");
            check(rows[0].How == "Every spell of your Mages" && CosmeticsLogic.SubText(rows[1]) == "In use" && CosmeticsLogic.SubText(rows[3]) == "Reach level 100" && CosmeticsLogic.SubText(rows[2]) == "Knights - not your class", "cosmetics: sub texts");
            check(CosmeticsLogic.CanUse(rows[2]) == false && CosmeticsLogic.CanUse(rows[3]) == false && !UnlocksCore.CanUse(rows[3]) && UnlocksCore.IsLocked(rows[3]) && !UnlocksCore.IsLocked(rows[0]), "cosmetics: locked and unusable rows");
            check(UnlocksCore.Tooltip(rows[3]) == "Not unlocked yet.\nHow to get it: Reach level 100", "cosmetics: locked tooltip: " + UnlocksCore.Tooltip(rows[3]));
            c.SetOnlyMine("spellskin", true);
            check(c.TabRows().Count == 3 && c.TabRows().All(r => r.Id != "12"), "cosmetics: only mine hides the locked rows");
            c.SetOnlyMine("spellskin", false);
            c.SelectTab("chatcolor");
            check(c.TabRows().Count == 2 && c.TabRows()[0].Selected, "cosmetics: chat colour tab, Default in use");
            var azure = c.RowOf("21");
            c.Select(azure);
            check(rig.Last == "{\"action\":\"select\",\"data\":{\"kind\":\"chatcolor\",\"id\":21,\"line\":\"mage\"}}", "cosmetics: select packet: " + rig.Last);
            c.SelectTab("collection");
            var col = c.TabRows();
            check(col[0].Id == CosmeticsLogic.ScoreRow && col[1].Id == "x:c1" && col[2].Id == "x:c2" && CosmeticsLogic.SubText(col[2]) == "Footprints - Win a duel", "cosmetics: collection rows, score first");
            check(c.StatusLine() == "Earned 1 / 2 (never sold)" && c.DefaultSelection() == CosmeticsLogic.ScoreRow, "cosmetics: collection status and selection: " + c.StatusLine());
            check(c.ScoreLine() == "Collection score: 42 - next reward at 100 (58 to go)" && col[0].Desc == "[x] 25 points: Title Collector and a plate frame" && col[0].How == "Outfits 3 (9)", "cosmetics: score row: " + col[0].Desc);
            rig.Recv(225, "{\"action\":\"colors\",\"data\":{\"full\":true,\"names\":{\"Kai\":\"#ff0000\",\"Bad\":\"red\"}}}");
            rig.Recv(225, "{\"action\":\"colors\",\"data\":{\"names\":{\"Mia\":\"#00ff00\",\"Kai\":0}}}");
            check(c.NameColors.Count == 1 && c.NameColors["Mia"] == "#00ff00", "cosmetics: name colours merge and drop");
            rig.Recv(225, "{\"action\":\"style\",\"data\":{\"accent\":\"#100c0ef0\"}}");
            check(c.Accent == "#100c0ef0", "cosmetics: accent");
            check(CosmeticsLogic.NameRange("12:00 Kai [20]: hi", "Kai", out int f, out int l) && f == 7 && l == 9 && !CosmeticsLogic.NameRange("12:00 Kaito [20]: hi", "Kai", out f, out l) && !CosmeticsLogic.NameRange("12:00 Bob: Kai", "Kai", out f, out l), "cosmetics: the name range stops at the colon and whole names");
            rig.Recv(225, "{\"action\":\"wardrobe\",\"data\":{\"hash\":\"h1\",\"outfit\":[{\"l\":128,\"n\":\"Citizen\",\"o\":1},{\"l\":129,\"n\":\"Hunter\",\"o\":0,\"s\":\"Win a duel\"}],\"shader\":[{\"l\":0,\"n\":\"Ember\",\"o\":true}],\"mount\":[{\"l\":0,\"n\":\"Bad\"}]}}");
            check(c.Wardrobe["outfit"].Count == 2 && c.Wardrobe["outfit"][1].Source == "Win a duel" && !c.Wardrobe["outfit"][1].Owned && c.Wardrobe["shader"].Count == 1 && c.Wardrobe["mount"].Count == 0 && c.WardrobeHash == "h1", "cosmetics: wardrobe read");
            rig.Recv(225, "{\"action\":\"result\",\"data\":{\"ok\":true,\"text\":\"Done.\"}}");
            check(c.StatusText == "Done." && c.StatusOk, "cosmetics: result");
        }

        static void Transmog(Action<bool, string> check)
        {
            var rig = new Rig();
            var t = new TransmogState(rig.Ext);
            t.Show();
            rig.Recv(212, "{\"action\":\"state\",\"data\":{\"open\":true,\"money\":5000,\"total\":{\"unlocked\":4,\"total\":10},\"kinds\":[{\"key\":\"helmet\",\"name\":\"Helmets\",\"unlocked\":2,\"total\":5}]," +
                "\"slots\":[{\"slot\":1,\"name\":\"Head\",\"item\":{\"id\":100,\"cid\":2457,\"name\":\"Steel Helmet\",\"kind\":\"helmet\",\"kindName\":\"Helmet\",\"applyFee\":1000,\"removeFee\":0}}," +
                "{\"slot\":4,\"name\":\"Body\",\"item\":{\"id\":300,\"name\":\"Cloak\",\"look\":{\"id\":301,\"name\":\"Rags\"},\"kind\":\"armor\",\"applyFee\":9000,\"removeFee\":500}},{\"slot\":5,\"name\":\"Shield\"},{\"slot\":6,\"name\":\"Ring\",\"item\":{\"id\":1,\"name\":\"Ring\"}}]," +
                "\"sets\":[{\"name\":\"Zed\",\"owned\":false,\"how\":\"Season 2\",\"source\":\"season\"},{\"name\":\"Ash\",\"owned\":true},{\"name\":\"Abe\",\"owned\":false,\"how\":\"Store\"}]}}");
            check(t.Visible && t.HasSlot && t.SelectedSlot == 1, "transmog: the first changeable slot is selected");
            check(TransmogState.SlotSub(t.Slots[0]) == "Helmet, own look" && TransmogState.SlotSub(t.Slots[1]) == "Look: Rags" && TransmogState.SlotSub(t.Slots[2]) == "Empty" && TransmogState.SlotSub(t.Slots[3]) == "Cannot change its look", "transmog: slot sub texts");
            check(TransmogState.ProgressText(4.0, 10.0) == "4 / 10 (40%)" && TransmogState.Percent(5.0, 0.0) == 0 && TransmogState.Gold(1234567.0) == "1,234,567", "transmog: progress and gold");
            check(t.Looks() == null && rig.Last == "{\"action\":\"looks\",\"data\":{\"kind\":\"helmet\"}}", "transmog: the looks of the kind are asked once");
            int n = rig.Sent.Count; t.Looks();
            check(rig.Sent.Count == n, "transmog: not asked twice");
            rig.Recv(212, "{\"action\":\"looks\",\"data\":{\"kind\":\"helmet\",\"rows\":[{\"id\":100,\"cid\":2457,\"name\":\"Steel Helmet\"},{\"id\":101,\"cid\":2458,\"name\":\"Crown\",\"set\":\"King\"},{\"id\":102,\"cid\":2459,\"name\":\"Iron Cap\"}]}}");
            check(t.Looks().Count == 3, "transmog: looks listed");
            t.Search = " cro ";
            check(t.Looks().Count == 1, "transmog: search");
            t.Select(t.Looks()[0]);
            var d = t.Detail();
            check(d.Apply && !d.Remove && d.Fee == "Fee: 1,000 gold" && d.Hint == "Appearance only: stats and tooltip stay the item's own.", "transmog: detail for a new look: " + d.Hint);
            check(t.ApplySelected() && rig.Last == "{\"action\":\"apply\",\"data\":{\"slot\":1,\"look\":101}}", "transmog: apply packet: " + rig.Last);
            t.Select(t.LooksByKind["helmet"][0]);
            check(t.Detail().Hint == "That is the item's own look." && !t.Detail().Apply, "transmog: its own look");
            t.SelectSlot(4);
            var d2 = TransmogState.DetailOf(t.SelectedRow(), t.LooksByKind["helmet"][1], 5000);
            check(d2.Remove && d2.Fee == "Fee: 9,000 gold  -  remove: 500 gold" && d2.Hint == "Not enough gold (backpack and bank).", "transmog: not enough gold and a remove fee: " + d2.Fee);
            check(TransmogState.DetailOf(t.SelectedRow(), Json.Parse("{\"id\":301}") as Dictionary<string, object>, 99999).Hint == "The item already has this look.", "transmog: the item already has it");
            check(t.RemoveSelected() && rig.Last == "{\"action\":\"remove\",\"data\":{\"slot\":4}}", "transmog: remove packet");
            check(TransmogState.DetailOf(null, null, 0).Hint == "Equip an item in this slot to change its look.", "transmog: empty slot hint");
            check(t.SortedSets().Select(s => CF.T(s, "name")).SequenceEqual(new[] { "Ash", "Abe", "Zed" }), "transmog: sets, owned first then by name");
            rig.Recv(212, "{\"action\":\"result\",\"data\":{\"ok\":true,\"text\":\"Applied.\"}}");
            check(t.StatusOk && t.SelectedLook == null, "transmog: a good result clears the chosen look");
        }

        static void Pets(Action<bool, string> check)
        {
            var rig = new Rig();
            var p = new PetsState(rig.Ext);
            p.Toggle();
            check(rig.Last == "{\"action\":\"open\",\"data\":{}}", "pets: open");
            rig.Recv(254, "{\"action\":\"state\",\"data\":{\"open\":true,\"active\":\"wolf\",\"out\":true,\"secondAt\":10,\"cooldowns\":{\"death\":0,\"summon\":5},\"zone\":\"utility only\"," +
                "\"pets\":[{\"species\":\"wolf\",\"speciesName\":\"Wolf\",\"name\":\"Fang\",\"look\":27,\"level\":4,\"xp\":50,\"into\":10,\"need\":40,\"pct\":25,\"element\":\"Ice\",\"abilities\":[{\"name\":\"Bite\",\"kind\":\"combat\",\"desc\":\"Bites.\",\"cooldown\":8,\"unlocked\":true},{\"name\":\"Howl\",\"kind\":\"utility\",\"desc\":\"Buffs.\",\"unlocked\":false,\"unlockAt\":10}]}]," +
                "\"catalog\":[{\"key\":\"wolf\",\"name\":\"Wolf\",\"look\":27,\"how\":\"A gift\"},{\"key\":\"owl\",\"name\":\"Owl\",\"look\":28,\"how\":\"Find an egg\",\"abilities\":[\"Scout\",\"Dive\"]}]}}");
            var e = p.Entries();
            check(p.Visible && e.Count == 2 && e[0].Owned && !e[1].Owned && p.Selected == "wolf", "pets: owned first, the active one selected");
            check(p.TitleText(e[0]) == "Fang (Wolf)" && p.RowSub(e[0]) == "Level 4, out" && p.RowSub(e[1]) == "Not owned", "pets: titles and row sub: " + p.RowSub(e[0]));
            check(PetsState.XpText(e[0].Pet) == "Level 4  -  10 / 40 XP (25%)", "pets: xp text");
            var lines = p.AbilityLines(e[0]);
            check(lines.Count == 2 && lines[0].Title == "Bite  [combat]" && lines[0].Text == "Bites. (every 8 s at most)" && lines[1].Locked && lines[1].LockText == "Unlocks at pet level 10.", "pets: ability lines");
            var unowned = p.AbilityLines(e[1]);
            check(unowned[0].Text == "From level 1." && unowned[1].Text == "From level 10.", "pets: unowned ability lines");
            check(p.StatusText() == "Your pet is with you.  Here: utility abilities only only  Call again in 5 s." || p.StatusText().StartsWith("Your pet is with you."), "pets: status: " + p.StatusText());
            var bw = p.Buttons(e[0]); var bo = p.Buttons(e[1]);
            check(!bw.Summon && bw.Dismiss && bw.Rename && !bo.Summon && !bo.Dismiss && !bo.Rename, "pets: buttons");
            rig.Recv(254, "{\"action\":\"xp\",\"data\":{\"species\":\"wolf\",\"level\":5,\"xp\":90,\"into\":0,\"need\":60,\"pct\":0}}");
            check(CF.I(p.Entries()[0].Pet, "level") == 5 && CF.I(p.Entries()[0].Pet, "into") == 0, "pets: the xp message updates the pet");
            check(PetsState.CleanName("  ") == null && PetsState.CleanName(" Rex ") == "Rex", "pets: clean name");
            check(p.Rename("wolf", " Rex ") && rig.Last == "{\"action\":\"rename\",\"data\":{\"species\":\"wolf\",\"name\":\"Rex\"}}" && !p.Rename("wolf", ""), "pets: rename packet");
            p.Summon("owl"); p.Dismiss();
            check(rig.Sent[rig.Sent.Count - 2] == "{\"action\":\"summon\",\"data\":{\"species\":\"owl\"}}" && rig.Last == "{\"action\":\"dismiss\",\"data\":{}}", "pets: summon and dismiss");
            rig.Sent.Clear();
            p.Tick(1000); p.Tick(2000); p.Tick(4100); p.Tick(5000); p.Tick(7200);
            check(rig.Sent.Count == 2 && rig.Sent[0] == "{\"action\":\"get\",\"data\":{}}", "pets: refresh every 3 s while open: " + rig.Sent.Count);
            p.Hide();
            check(rig.Last == "{\"action\":\"close\",\"data\":{}}" && !p.Visible, "pets: close");
        }

        static void Professions(Action<bool, string> check)
        {
            var rig = new Rig();
            var p = new ProfessionsState(rig.Ext);
            p.Show();
            rig.Recv(195, "{\"action\":\"state\",\"data\":{\"bonus\":4.5,\"per\":0.5,\"cap\":20,\"broker\":true,\"full\":20,\"late\":0.5,\"capDay\":40,\"nextDay\":3700,\"nextWeek\":100000," +
                "\"tiers\":{\"1\":{\"n\":\"Common\",\"col\":\"#c4cebc\"},\"2\":{\"n\":\"Fine\",\"col\":\"#5fd35f\"}}," +
                "\"profs\":[{\"k\":\"delving\",\"n\":\"Delving\",\"lv\":9,\"xp\":50,\"need\":200,\"pct\":25,\"tier\":2,\"d\":\"Dig.\",\"tool\":\"Pick\",\"g\":1234,\"bp\":2.5,\"book\":\"mining\",\"perks\":[{\"k\":\"channel\",\"v\":0.9,\"lv\":5,\"n\":\"Swift\",\"on\":true},{\"k\":\"lucky\",\"v\":0.05,\"lv\":20,\"n\":\"Lucky\",\"on\":false}]}," +
                "{\"k\":\"flaying\",\"n\":\"Flaying\",\"lv\":40,\"xp\":1,\"need\":0,\"pct\":0,\"tier\":1}]," +
                "\"demand\":[{\"id\":1,\"c\":5880,\"n\":\"iron ore\",\"p\":\"delving\",\"t\":2,\"g\":100,\"l\":50,\"m\":1.5,\"h\":30,\"s\":10},{\"id\":2,\"n\":\"hide\",\"p\":\"flaying\",\"t\":1,\"g\":10,\"l\":5,\"m\":0.8,\"h\":0,\"s\":0}]," +
                "\"areas\":[{\"n\":\"Old Mine\",\"t\":2,\"h\":true,\"m\":\"Trolls\",\"near\":\"Cinderhold\",\"x\":100,\"y\":200,\"z\":7,\"nodes\":[{\"k\":\"delving\",\"r\":3,\"t\":5},{\"k\":\"angling\"}]}]}}");
            var rows = p.ProfRows();
            check(rows.Count == 2 && rows[0].XpText == "50 / 200" && rows[0].TierText == "Gathers fine materials" && rows[0].TierColor == "#5fd35f" && rows[1].XpText == "Mastered" && rows[1].Pct == 100, "professions: rows");
            check(p.BonusText() == "Experience bonus: +4.5% from monsters (every profession level above 1 adds 0.5%, at most +20%)", "professions: bonus text: " + p.BonusText());
            check(ProfessionsState.FmtPct(0.05) == "0.05" && ProfessionsState.FmtPct(20) == "20" && ProfessionsState.FmtPct(0.0125) == "0.0125" && ProfessionsState.FmtPct(2.5) == "2.5", "professions: percent format");
            check(ProfessionsState.TimeText(3700) == "1h 1m" && ProfessionsState.TimeText(100000) == "1d 3h" && ProfessionsState.TimeText(5) == "1m", "professions: time text");
            var perks = p.PerkLines(CF.Rows(CF.G(p.State, "profs"))[0]);
            check(perks.Count == 2 && perks[0].Key == "Level 5, Swift: gathering takes 10% less time" && perks[0].Value && perks[1].Key == "Level 20, Lucky: +5% chance of one more unit" && !perks[1].Value, "professions: perks: " + perks[0].Key);
            check(ProfessionsState.CraftText(CF.Rows(CF.G(p.State, "profs"))[0]) == "Crafting: 2.5% chance of a base crafting material per gather; refine at the Mining crafting table", "professions: craft text");
            var demand = p.DemandRows();
            check(demand.Count == 2 && demand[0].Name == "iron ore" && demand[0].MultText == "x1.5" && demand[0].MultColor == ProfessionsState.Up && demand[1].MultColor == ProfessionsState.Down && demand[0].CanSell && !demand[1].CanSell, "professions: demand rows");
            check(demand[0].Units == 30 && demand[0].Worth == 10 * 100 + 20 * 50 && demand[0].SoldText == "10 / 40 today" && demand[0].PriceText == "100 gold", "professions: quote: " + demand[0].Worth);
            p.SellAllEstimate(out int units, out double gold);
            check(units == 30 && gold == 2000, "professions: sell all estimate");
            p.Sell(1); p.SellAll();
            check(rig.Sent[rig.Sent.Count - 2] == "{\"action\":\"sell\",\"data\":{\"id\":1}}" && rig.Last == "{\"action\":\"sellAll\",\"data\":{}}", "professions: sell packets");
            var area = p.AreaLines();
            check(area[0].Title == "Old Mine (Fine, hunt)" && area[0].Text == "Delving 3/5 ready, fishing; near Cinderhold" && area[0].Tip.Contains("hunting ground of Trolls"), "professions: area lines: " + area[0].Text);
            check(p.Footer() == "Full price for 20 a day per material, then 50% up to 40. New day in 1h 1m, new demand in 1d 3h.", "professions: footer: " + p.Footer());
            rig.Recv(195, "{\"action\":\"levelup\",\"data\":{\"k\":\"delving\",\"lv\":10}}");
            check(p.StatusText == "Delving level 10!" && p.StatusColor == ProfessionsState.Gold, "professions: level up");
            rig.Recv(195, "{\"action\":\"result\",\"data\":{\"ok\":false,\"text\":\"No.\"}}");
            check(p.StatusColor == ProfessionsState.Bad, "professions: result");
            p.Hide();
            rig.Recv(195, "{\"action\":\"npc\",\"data\":{}}");
            check(p.Visible && rig.Last == "{\"action\":\"open\",\"data\":{}}", "professions: the broker NPC opens the window");
        }

        static void Crafting(Action<bool, string> check)
        {
            var rig = new Rig();
            var c = new CraftingState(rig.Ext);
            rig.Recv(232, "{\"action\":\"info\",\"data\":{\"orbs\":[{\"key\":\"transmutation\",\"name\":\"Orb of Awakening\",\"clientId\":3001,\"text\":\"Gives a rarity.\"},{\"key\":\"binding\",\"name\":\"Orb of Binding\",\"clientId\":3002,\"text\":\"Binds a bonus.\"}],\"reasons\":{\"noslots\":\"No free slot.\"}}}");
            rig.Recv(232, "{\"action\":\"state\",\"data\":{\"open\":true,\"counts\":{\"transmutation\":3,\"binding\":1},\"item\":{\"path\":\"p1\",\"id\":9,\"sig\":\"s\",\"clientId\":2400,\"name\":\"Ash Blade\",\"rarity\":3,\"rarityName\":\"Magic\",\"level\":40,\"maxTier\":4,\"maxMods\":4," +
                "\"mods\":[{\"key\":\"fire\",\"text\":\"+9 fire\",\"short\":\"+9 fire\",\"tier\":2,\"lo\":5,\"hi\":9,\"side\":\"prefix\",\"group\":\"element\"},{\"key\":\"hp\",\"text\":\"+5 hp\",\"side\":\"suffix\",\"bound\":true}],\"prefixes\":[1,2],\"suffixes\":[1,2],\"quality\":4,\"qualityCap\":20," +
                "\"orbs\":{\"transmutation\":\"noslots\"},\"pick\":{\"binding\":[\"fire\",\"hp\"]},\"preview\":{},\"sockets\":{\"count\":2,\"max\":3,\"list\":[{\"index\":1,\"id\":5,\"name\":\"Ruby\",\"text\":\"+1\",\"cost\":2500},{\"index\":2,\"id\":0}]}," +
                "\"salvage\":{\"ok\":true,\"shards\":4,\"orbChance\":12}},\"items\":[{\"path\":\"p1\",\"id\":9,\"name\":\"Ash Blade\",\"rarity\":3}],\"history\":[{\"time\":1700000000,\"orb\":\"Orb of Awakening\",\"item\":\"x\",\"text\":\"ok\"}]," +
                "\"salvage\":{\"mode\":\"salvage\",\"installed\":true,\"shards\":120,\"shardName\":\"Rune shards\",\"shardSingular\":\"Rune shard\",\"bags\":[{\"name\":\"Backpack\",\"path\":\"b\"}],\"rarityNames\":[\"Common\",\"Uncommon\"],\"rarityIds\":[1,2]," +
                "\"batch\":{\"bag\":\"b\",\"maxRarity\":2,\"count\":3,\"shards\":9,\"orbs\":6,\"skipped\":{\"locked\":2,\"cap\":1},\"cap\":50,\"sig\":\"bs\"},\"recipes\":[{\"key\":\"transmutation\",\"name\":\"Orb of Awakening\",\"cost\":30,\"count\":2,\"back\":10},{\"key\":\"x\",\"name\":\"Rift Key\",\"cost\":500,\"input\":1,\"inputName\":\"Rift dust\",\"have\":700}],\"maxCombine\":20}}}");
            check(c.Visible && c.Mode == "salvage" && c.Orbs.Count == 2 && CF.I(c.Orbs[0], "count") == 3, "crafting: state and counts");
            var rows = c.OrbRows();
            check(!rows[0].CanUse && rows[0].Why == "No free slot." && rows[0].Name == "Orb of Awakening", "crafting: a reason code becomes its text");
            check(!rows[1].CanUse && rows[1].Why == "Click a modifier of the item first.", "crafting: an aimed orb needs a modifier");
            c.SelectMod("fire");
            rows = c.OrbRows();
            check(rows[1].CanUse && rows[1].IsText && rows[1].Line == "Binds a bonus.", "crafting: with a modifier the orb is ready");
            rig.Sent.Clear();
            check(c.ApplyOrb("binding") && rig.Last == "{\"action\":\"apply\",\"data\":{\"orb\":\"binding\",\"path\":\"p1\",\"id\":9,\"sig\":\"s\",\"mod\":\"fire\"}}", "crafting: apply packet with the modifier: " + rig.Last);
            check(c.ApplyOrb("transmutation") && !rig.Last.Contains("\"mod\""), "crafting: no modifier for an orb that does not aim");
            check(CraftingState.ModText(c.Mods[0]) == "T2  +9 fire  [5-9]" && CraftingState.ModText(c.Mods[1]) == "+5 hp" && CraftingState.ModColor(c.Mods[0]) == "#ff8a5a", "crafting: mod text and colour");
            string col;
            check(CraftingState.RarityLine(c.Item, out col) == "Magic, item level 40 (up to T4)" && col == "#4a8cff", "crafting: rarity line: " + CraftingState.RarityLine(c.Item, out col));
            check(CraftingState.ModCountLine(c.Item) == "Modifiers 2/4 (prefixes 1/2, suffixes 1/2)", "crafting: mod count line: " + CraftingState.ModCountLine(c.Item));
            check(CraftingState.QualityText(c.Item, out int qp) == "Quality +4% / 20%" && qp == 20, "crafting: quality");
            check(CraftingState.SocketHeader(c.Item) == "Sockets: 1 / 2" && c.GemOp("shatter", 1) && rig.Last == "{\"action\":\"gem\",\"data\":{\"op\":\"shatter\",\"socket\":1,\"path\":\"p1\",\"id\":9,\"sig\":\"s\"}}", "crafting: sockets and the gem packet");
            check(c.SalvageItemText(out bool ok) == "Ash Blade: 4 Rune shards, 12% chance of an orb." && ok, "crafting: salvage item text: " + c.SalvageItemText(out ok));
            check(c.BatchText() == "3 items -> 9 Rune shards, 6% orb chance in total.\nSkipped: 1 over the limit of 50, 2 locked." && c.BatchButtonText() == "Salvage 3 items", "crafting: batch text: " + c.BatchText());
            check(c.SalvageAllText().StartsWith("Salvage 3 item(s) (rarity up to Uncommon) into 9 Rune shards?"), "crafting: salvage all text");
            check(c.SalvageAll() && rig.Last == "{\"action\":\"salvageBatch\",\"data\":{\"bag\":\"b\",\"maxRarity\":2,\"sig\":\"bs\"}}", "crafting: batch packet: " + rig.Last);
            c.SalvageItem(); c.ToggleLock(); c.SetMode("orbs"); c.SetScope("b", 2); c.Combine("transmutation", 4); c.Recycle("transmutation", 2);
            var tail = rig.Sent.Skip(rig.Sent.Count - 6).ToList();
            check(tail[0].StartsWith("{\"action\":\"salvage\"") && tail[1] == "{\"action\":\"lock\",\"data\":{\"path\":\"p1\",\"id\":9,\"on\":true}}" && tail[2] == "{\"action\":\"salvageScope\",\"data\":{\"mode\":\"orbs\"}}" &&
                tail[3] == "{\"action\":\"salvageScope\",\"data\":{\"bag\":\"b\",\"maxRarity\":2}}" && tail[4] == "{\"action\":\"combine\",\"data\":{\"key\":\"transmutation\",\"count\":4}}" && tail[5].StartsWith("{\"action\":\"recycle\""), "crafting: salvage, lock, scope, combine and recycle packets");
            var recipes = c.Recipes; var sv = c.Salvage;
            check(CraftingState.CostText(recipes[0], sv) == "30 shards" && CraftingState.CostText(recipes[1], sv) == "500 Rift dust" && CraftingState.Have(recipes[0], sv) == 120 && CraftingState.Have(recipes[1], sv) == 700, "crafting: recipe costs");
            check(CraftingState.CombineCount(120, 30, 20, false) == 1 && CraftingState.CombineCount(120, 30, 20, true) == 4 && CraftingState.CombineCount(10, 30, 20, true) == 0 && CraftingState.CombineCount(9000, 30, 20, true) == 20, "crafting: combine count");
            check(CraftingState.RecycleBack(recipes[0]) == 10 && CraftingState.RecycleBack(recipes[1]) == 0 && CraftingState.RecipeEnabled(recipes[0], sv) && CraftingState.RecipeEnabled(recipes[1], sv), "crafting: recipe enable");
            check(CraftingState.RecipeTip(recipes[0], sv).Contains("Shift+click: recycle your Orb of Awakening into 10 Rune shards each."), "crafting: recipe tip");
            check(c.SelectAt(new Pos(0xFFFF, 0x41, 2), 2400) && rig.Last == "{\"action\":\"select\",\"data\":{\"pos\":{\"x\":65535,\"y\":65,\"z\":2},\"clientId\":2400}}", "crafting: a backpack item dropped on the bench");
            check(!c.SelectAt(new Pos(100, 100, 7), 2400) && c.ResultText == "Only items from your backpack can go on the bench." && !c.ResultOk, "crafting: a map item is refused");
            rig.Recv(232, "{\"action\":\"state\",\"data\":{\"counts\":{},\"item\":null}}");
            check(c.Item == null && c.SelectedMod == null, "crafting: an empty bench clears the picked modifier");
            check(CraftGuide.RiskOf("void") == "final" && CraftGuide.RiskText("gamble") == "Gamble: the result is random." && CraftGuide.AdviceOf("binding").StartsWith("Protects one bonus") && CraftGuide.Plan.Length == 8, "crafting: guide texts");
            check(CraftGuide.EffectText(Json.Parse("{\"label\":\"Damage\",\"fmt\":\"pair\",\"label2\":\"Crit\"}"), CF.Raw(Json.Parse("[1,2]")), CF.Raw(Json.Parse("[3]"))) == "Damage +1 / 2%, Crit +3%", "crafting: gem effect text");
            // the lock menu
            check(CraftingLockMenu.Applies(new Pos(0xFFFF, 5, 0), false, false, false, 2, false, "Blade") && !CraftingLockMenu.Applies(new Pos(100, 100, 7), false, false, true, 2, false, "Blade") &&
                !CraftingLockMenu.Applies(new Pos(0xFFFF, 5, 0), true, false, true, 2, false, "Arrow") && CraftingLockMenu.Applies(new Pos(0xFFFF, 0x41, 3), false, false, false, 0, false, "Waystone Rift Key") && !CraftingLockMenu.Applies(new Pos(0xFFFF, 5, 0), false, false, false, 0, false, "Stick"), "crafting: lock menu applies");
            check(CraftingLockMenu.Show(new Pos(0xFFFF, 5, 0), false, false, true, 1, false, "x", true) && !CraftingLockMenu.Show(new Pos(0xFFFF, 5, 0), false, false, true, 1, false, "x", false), "crafting: lock or unlock entry");
            var req = CraftingLockMenu.Request(new Pos(0xFFFF, 5, 9), 2400, true);
            check(Json.Serialize(req) == "{\"pos\":{\"x\":65535,\"y\":5,\"z\":0},\"cid\":2400,\"on\":true}" && CraftingLockMenu.Request(new Pos(1, 1, 1), 5, true) == null, "crafting: lock request: " + Json.Serialize(req));
        }

        static void CraftTable(Action<bool, string> check)
        {
            var rig = new Rig();
            var t = new CraftTableState(rig.Ext);
            t.Clock = () => rig.Now;
            Pos? player = new Pos(31650, 32233, 4);
            t.PlayerPos = () => player;
            int? skill = 20;
            t.SkillLevel = i => skill;
            rig.Recv(91, "{\"action\":\"show\",\"data\":{\"category\":\"mining\"}}");
            check(t.Visible && t.Current == "mining" && t.AtTable == "mining" && rig.Last == "{\"action\":\"fetch\",\"data\":{\"category\":\"mining\",\"page\":1}}", "craft table: a table opens its tab and asks page 1: " + rig.Last);
            string page = "{\"action\":\"fetch\",\"data\":{\"category\":\"mining\",\"totalPages\":2,\"page\":1,\"crafts\":[" +
                "{\"index\":1,\"name\":\"Iron Bar\",\"id\":5,\"clientId\":3000,\"level\":10,\"cost\":100,\"count\":2,\"materials\":[{\"id\":7,\"clientId\":3001,\"count\":2,\"player\":5,\"name\":\"Iron Ore\"}]}," +
                "{\"index\":2,\"name\":\"Gem Ring\",\"id\":6,\"clientId\":3002,\"level\":50,\"cost\":900,\"storage\":100,\"playerStorage\":0,\"storageText\":\"Do the quest.\",\"materials\":[{\"id\":8,\"clientId\":3003,\"count\":1,\"player\":0}],\"bonus\":{\"kind\":\"gear\",\"level\":30,\"odds\":[{\"rarity\":2,\"name\":\"Uncommon\",\"pct\":20},{\"rarity\":1,\"name\":\"Common\",\"pct\":80}]}}]}}";
            rig.Recv(91, page);
            check(rig.Last == "{\"action\":\"fetch\",\"data\":{\"category\":\"mining\",\"page\":2}}" && !t.Loaded("mining") && t.Recipes("mining").Count == 2, "craft table: the second page is asked");
            rig.Recv(91, "{\"action\":\"money\",\"data\":1000}");
            check(t.Money == 1000, "craft table: money");
            t.SelectRecipe(1);
            var r = t.SelectedRecipe();
            var ctx = t.Context("mining", 0);
            var ch = CraftTableState.Check(r, ctx);
            check(ch.Ok && ch.RecipeOk && ch.Mats[0], "craft table: a craftable recipe at its table");
            var gem = t.Recipes("mining")[1];
            var gc = CraftTableState.Check(gem, ctx);
            check(!gc.Ok && gc.Reasons.SequenceEqual(new[] { "locked", "skill", "materials" }) && CraftTableState.BlockText(gc, gem, ctx) == "Recipe not unlocked yet. Do the quest.", "craft table: reasons in order: " + string.Join(",", gc.Reasons));
            check(CraftTableState.BonusText(gem) == "Rarity at item level 30: Common 80% / Uncommon 20%" && CraftTableState.RowSub(r) == "x2  -  Lv 10  -  100 gp" && CraftTableState.HaveNeed(r.Materials[0]) == "5/2", "craft table: bonus, row, materials text");
            check(CraftTableState.MaxCraftable(r, 1000) == 2 && CraftTableState.MaxCraftable(r, 150) == 1 && CraftTableState.MaxCraftable(new CraftRecipe(), null) == 50, "craft table: max craftable");
            check(CraftTableState.Filter(t.Recipes("mining"), "iron", "all", ctx).Count == 1 && CraftTableState.Filter(t.Recipes("mining"), "ore", "all", ctx).Count == 1 && CraftTableState.Filter(t.Recipes("mining"), "", "craftable", ctx).Count == 1, "craft table: search and the craftable filter");
            t.ChangeQty(5, 0);
            check(t.Qty == 2, "craft table: quantity is clamped");
            player = new Pos(31650, 32236, 4);
            check(CraftTableState.Check(r, t.Context("mining", 0)).Reasons.SequenceEqual(new[] { "away" }) && !t.DoCraft(0) && t.StatusText == "Go back to the crafting table.", "craft table: away from the table");
            player = new Pos(31651, 32233, 4);
            check(t.DoCraft(100) && rig.Last == "{\"action\":\"craft\",\"data\":{\"category\":\"mining\",\"craftId\":1}}" && t.Craft != null && t.ProgressPct == 0, "craft table: craft packet: " + rig.Last);
            rig.Now = 200;
            rig.Recv(91, "{\"action\":\"craft\",\"data\":{\"success\":true}}");
            t.Tick(630);
            check(t.ProgressPct == (int)((630 - 200) * 100 / 860), "craft table: progress after the accepted request: " + t.ProgressPct);
            rig.Now = 1100;
            rig.Recv(91, "{\"action\":\"message\",\"data\":{\"kind\":\"ok\",\"text\":\"You made an Iron Bar.\"}}");
            check(t.Craft != null && t.Craft.Left == 1 && t.StatusText == "You made an Iron Bar. (1 crafted, 1 to go)" && t.NextSendAt >= 1100, "craft table: the second one is queued: " + t.StatusText);
            int before = rig.Sent.Count;
            t.Tick(1100);
            check(rig.Sent.Count == before, "craft table: the repeat waits for the cooldown");
            t.Tick(t.NextSendAt);
            check(rig.Sent.Count == before + 1 && rig.Last.Contains("\"craft\""), "craft table: the repeat goes out");
            rig.Now = t.NextSendAt + 100;
            rig.Recv(91, "{\"action\":\"craft\",\"data\":{\"success\":true}}");
            rig.Recv(91, "{\"action\":\"message\",\"data\":{\"kind\":\"ok\",\"text\":\"You made an Iron Bar.\"}}");
            check(t.Craft == null && t.StatusText == "You made an Iron Bar. (2 crafted)" && t.ProgressPct < 0, "craft table: the run ends: " + t.StatusText);
            t.Qty = 1;
            t.DoCraft(rig.Now + 5000);
            t.Tick(rig.Now + 5000 + 6000);
            check(t.Craft == null && t.StatusText == "No answer from the server.", "craft table: five seconds without an answer stops it");
            t.DoCraft(rig.Now + 20000);
            rig.Recv(91, "{\"action\":\"message\",\"data\":{\"kind\":\"error\",\"text\":\"Failed.\"}}");
            check(t.Craft == null && t.StatusText == "Failed." && rig.Last == "{\"action\":\"fetch\",\"data\":{\"category\":\"mining\",\"page\":1}}", "craft table: a refusal stops it and refreshes the page");
            // a chunked fetch
            string whole = "{\"action\":\"fetch\",\"data\":{\"category\":\"herbalist\",\"totalPages\":1,\"page\":1,\"crafts\":[{\"index\":1,\"name\":\"Potion\",\"id\":9,\"clientId\":3100,\"level\":1,\"cost\":10,\"materials\":[]}]}}";
            int cut = whole.Length / 2;
            rig.Recv(91, "{\"action\":\"chunkedFetch\",\"chunkData\":{\"msgID\":\"m1\",\"index\":2,\"count\":2,\"payload\":" + Json.Serialize(ExtOpcodes.ToWire(whole.Substring(cut))) + "}}");
            check(t.Recipes("herbalist").Count == 0, "craft table: half a chunked fetch shows nothing");
            rig.Recv(91, "{\"action\":\"chunkedFetch\",\"chunkData\":{\"msgID\":\"m1\",\"index\":1,\"count\":2,\"payload\":" + Json.Serialize(ExtOpcodes.ToWire(whole.Substring(0, cut))) + "}}");
            check(t.Recipes("herbalist").Count == 1 && t.Recipes("herbalist")[0].Name == "Potion", "craft table: the joined chunks are a fetch");
            check(CraftTableState.Progress(100, 530) == 50 && CraftTableState.RepeatDelay(1000, 1500) == 650 && CraftTableState.ClampQty(99, 7) == 7 && CraftTableState.PageOf(11) == 2, "craft table: timing helpers");
            check(t.NeedsTip("mining", 1), "craft table: no tip yet");
            t.AskTip("mining", 1);
            check(rig.Last == "{\"action\":\"tip\",\"data\":{\"category\":\"mining\",\"craftId\":1}}" && !t.NeedsTip("mining", 1), "craft table: tip asked once");
            check(CraftTableState.PlainTip(gem) == "Gem Ring\nCrafting level 50, 900 gp\nRarity at item level 30: Common 80% / Uncommon 20%".Replace("Crafting level", "Mining level"), "craft table: plain tip: " + CraftTableState.PlainTip(gem));
            check(CraftTableState.SkillIndex("jewelsmith") == 6 && CraftTableState.SkillIndex("nothing") == null, "craft table: skill index");
        }

        static void Helpers(Action<bool, string> check)
        {
            // craft skills of the 0xA1 packet (Chaos wire: seven skills after fishing, then the special skills)
            var dat = DatFile.Parse(Program.SyntheticDat());
            var w = new ByteWriter().U8(0xA1);
            for (int i = 0; i < 14; i++) w.U16((ushort)(10 + i)).U16((ushort)(5 + i)).U8((byte)i);
            for (int i = 0; i < 6; i++) w.U32(0);
            var p = new GameParser(new World(dat));
            p.Parse(w.ToArray());
            check(p.Skills[6].Level == 16 && p.CraftSkills[0].Level == 17 && p.CraftSkills[6].Level == 23 && p.CraftSkills[6].Base == 18 && p.CraftSkills[6].Percent == 13, "craft skills: the packet gives seven crafting skills after fishing");
            check(CraftSkills.Tooltip(2, new SkillValue { Level = 30, Base = 20, Percent = 40 }) == "Mining: 30 (base 20)\n40% to the next level" && CraftSkills.Tooltip(0, new SkillValue { Level = 5, Base = 5, Percent = 1 }) == "Crafting: 5\n1% to the next level" && CraftSkills.ShortLevel(15300) == "15.3k", "craft skills: tooltip and short level");
            check(CF.Group(1234567) == "1,234,567" && CF.Short(1500) == "1.5k" && CF.Pct(12.5) == "12.5%" && CF.HoursMinutes(7260) == "2h 01m", "collect helpers: number formats");
            check(CF.Rows(Json.Parse("[1,{\"a\":1},\"x\"]")).Count == 1 && CF.Values(Json.Parse("[1,\"a\",{},true]")).SequenceEqual(new[] { "1", "a" }), "collect helpers: rows and values drop what is no table or string");
        }
    }
}
