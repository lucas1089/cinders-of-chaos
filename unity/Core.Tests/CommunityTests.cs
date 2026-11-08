// Community modules (O433 phase 5, track S): admin panel, boss spawns, survey, nemesis, referral, community goal, chronicle, mentors, patch notes, card borders, drop feed, credits,
// streamer and cinema mode, performance record, automatic screenshots, Customise Character extras. Each panel is driven with the server's messages (as the main client's *_test.lua
// files and the server's senders build them) and the requests it sends are read back from the extended opcode packets.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class CommunityTests
    {
        sealed class Rig
        {
            public readonly ExtOpcodes Ext = new ExtOpcodes();
            public readonly List<string> Sent = new List<string>();
            public double Now;
            public Rig() { Ext.Transmit = p => Sent.Add(p[1] + ":" + Encoding.UTF8.GetString(p, 4, p.Length - 4)); }
            public string Last => Sent.Count > 0 ? Sent[Sent.Count - 1] : "";
            public bool Has(string text) => Sent.Any(s => s.Contains(text));
            public void Feed(byte op, string action, string data)
            {
                string json = "{\"action\":\"" + action + "\",\"data\":" + data.Replace('\'', '"') + "}";
                Ext.Receive(op, ExtOpcodes.ToWire(json));
            }
            public Func<double> Clock => () => Now;
        }

        static SocialRow Find(List<SocialRow> rows, Func<SocialRow, bool> f) => rows.FirstOrDefault(f);
        static bool Click(List<SocialRow> rows, string text)
        {
            foreach (var r in rows) foreach (var b in r.Buttons) if (b.Text == text && b.Enabled) { b.Click(); return true; }
            return false;
        }
        static bool Texts(List<SocialRow> rows, string part) => rows.Any(r => r.Text.Contains(part) || r.Right.Contains(part) || r.Sub.Contains(part));

        public static void Run(Action<bool, string> check)
        {
            Loc.Set("en");
            AdminChecks(check);
            BossChecks(check);
            SurveyChecks(check);
            NemesisChecks(check);
            ReferralChecks(check);
            GoalChecks(check);
            ChronicleChecks(check);
            MentorChecks(check);
            PatchNotesChecks(check);
            SmallChecks(check);
            StreamerChecks(check);
            PerfChecks(check);
            ShotsChecks(check);
            ExtrasChecks(check);
            SessionChecks(check);
            LocChecks(check);
        }

        // ------------------------------------------------------------------------------------ game_admin
        static void AdminChecks(Action<bool, string> check)
        {
            var rig = new Rig();
            var p = new AdminPanel(rig.Ext) { Clock = rig.Clock };
            // a player never gets a catalog: nothing opens
            p.Poll(100, true, 0);
            check(!p.Asked, "admin: it waits 600 ms after the login before it asks");
            p.Poll(700, true, 0);
            check(p.Asked && rig.Last == "120:{\"action\":\"catalog\",\"data\":{}}", "admin: the catalog is asked once after the login: " + rig.Last);
            p.Show();
            check(!p.Visible, "admin: no catalog, no window (GM tools only for GM accounts)");
            string cat = "{'categories':[{'id':'players','label':'Players','actions':[" +
                "{'id':'kick','name':'Kick','description':'Throw a player out','dangerous':true,'confirm':true,'params':[{'name':'name','label':'Name','type':'text','required':true},{'name':'why','label':'Reason','type':'select','options':[{'label':'Bug','value':'bug'},{'label':'Abuse','value':'abuse'}],'default':'abuse'},{'name':'ban','label':'Ban','type':'bool','default':false},{'name':'days','label':'Days','type':'int'}]}," +
                "{'id':'broadcast','name':'Broadcast','params':[]},{'bad':1}]},{'noid':true}]}";
            rig.Feed(120, "catalog", cat);
            check(p.HasCatalog && p.Categories.Count == 1 && p.Categories[0].Actions.Count == 2, "admin: a catalog is cleaned (entries without an id are left out)");
            p.Show();
            check(p.Visible, "admin: with a catalog the window opens");
            var rows = p.BuildRows();
            check(Texts(rows, "Kick") && Texts(rows, "Broadcast"), "admin: the action list shows the actions");
            Click(rows, "Open");
            check(p.Selected != null, "admin: Open selects the first action");
            // required field first
            p.Select(p.Find("kick"));
            rows = p.BuildRows();
            Click(rows, "Run");
            check(p.Results.Count > 0 && p.Results[0].Text.Contains("missing required field: Name") && !rig.Has("\"action\":\"run\""), "admin: a missing required field is refused on the client");
            p.Form["p_name"] = "Bob"; p.Form["p_days"] = "3";
            rows = p.BuildRows();
            Click(rows, "Run");
            check(p.Armed && !rig.Has("\"action\":\"run\""), "admin: a confirm action arms on the first press");
            rows = p.BuildRows();
            Click(rows, "Click again to confirm");
            check(rig.Has("\"action\":\"run\"") && rig.Has("\"id\":\"kick\"") && rig.Has("\"name\":\"Bob\"") && rig.Has("\"why\":\"abuse\"") && rig.Has("\"ban\":false") && rig.Has("\"days\":3"), "admin: the second press sends run with the typed params: " + rig.Last);
            check(p.Busy, "admin: the Run button waits for the answer");
            rig.Feed(120, "result", "{'rid':1,'id':'kick','ok':true,'message':'Bob is gone','lines':['one','two']}");
            check(!p.Busy && p.Results.Any(r => r.Text == "[Kick] Bob is gone" && r.Tone == "good") && p.Results.Any(r => r.Text == "  two"), "admin: the result and its lines are listed");
            // the confirm arming lapses
            p.Select(p.Find("kick")); p.Form["p_name"] = "Al";
            p.BuildRows(); Click(p.BuildRows(), "Run");
            p.Poll(700 + 5000, true, 0);
            check(!p.Armed, "admin: the confirm lapses after 4 s");
            for (int i = 0; i < 350; i++) p.Results.Add(new AdminPanel.Line { Text = "x" });
            rig.Feed(120, "result", "{'rid':99,'id':'x','ok':false,'message':'no'}");
            check(p.Results.Count == AdminPanel.MaxResultLines, "admin: the result list keeps 300 lines");
        }

        // ------------------------------------------------------------------------------------ game_bossspawns
        const string BossList = "{'now':1,'refresh':30,'cats':[{'k':'world','n':'World Bosses','c':'#ff0000','t':'Weekly'},{'k':'raid','n':'Raids'},{'k':'empty','n':'Nothing'}]," +
            "'rows':[{'k':'a','c':'world','n':'Rootkraken','loc':'Greenmarsh','p':{'x':100,'y':200,'z':7},'lv':100,'st':'respawn','in':125,'ago':600,'by':'Vexa','kills':4}," +
            "{'k':'b','c':'world','n':'Ember Titan','loc':'Cinder Pass','st':'alive','alive':2}," +
            "{'k':'c','c':'raid','n':'Sepulchre','loc':'Crypts','st':'scheduled','in':30,'at':'Wed 19:30','pl':200,'party':3}]}";

        static void BossChecks(Action<bool, string> check)
        {
            var rig = new Rig();
            var p = new BossSpawnsPanel(rig.Ext) { Clock = rig.Clock };
            p.Show();
            check(rig.Last == "217:{\"action\":\"open\",\"data\":{}}" && p.Visible, "bosses: open asks the list");
            rig.Now = 1000;
            rig.Feed(217, "list", BossList);
            string tone;
            var rows = p.BuildRows();
            check(rows.Count(r => r.Text.StartsWith("- ")) == 2, "bosses: a category without rows is left out (2 of 3)");
            check(Texts(rows, "- Raids (1)") && Texts(rows, "- World Bosses (2) - 1 alive"), "bosses: the header counts rows and the ones alive");
            var kraken = Find(rows, r => r.Text == "Rootkraken");
            check(kraken != null && kraken.Right == "Respawns in 2m 05s", "bosses: respawn countdown: " + kraken?.Right);
            rig.Now = 1000 + 65000;
            rows = p.BuildRows();
            check(Find(rows, r => r.Text == "Rootkraken").Right == "Respawns in 1m 00s", "bosses: the countdown runs between two lists");
            rig.Now = 1000 + 200000;
            check(Find(p.BuildRows(), r => r.Text == "Rootkraken").Right == "Respawn due", "bosses: at zero the boss is due");
            check(Find(rows, r => r.Text == "Ember Titan").Right == "Alive (2)", "bosses: several alive");
            check(BossSpawnsPanel.StatusOf(Json.Parse("{\"st\":\"cooldown\",\"in\":0}"), 0, out tone) == "Ready" && tone == "#6fd86f", "bosses: an ended cooldown is ready");
            check(BossSpawnsPanel.StatusOf(Json.Parse("{}"), 0, out tone) == "Not seen yet", "bosses: no state is not seen yet");
            check(BossSpawnsPanel.LevelText(Json.Parse("{\"lv\":100}")) == "Level 100+" && BossSpawnsPanel.LevelText(Json.Parse("{\"pl\":200,\"party\":3}")) == "Pocket: level 200+, party of 3", "bosses: level and party text");
            check(BossSpawnsPanel.Coords(Json.Parse("{\"x\":1,\"y\":2}")) == "1, 2, 7" && BossSpawnsPanel.Where(Json.Parse("{\"ln\":\"a portal\"}")) == "a portal", "bosses: coordinates, else the place note");
            check(BossSpawnsPanel.Tooltip(Json.Parse("{\"n\":\"X\",\"ago\":120,\"by\":\"Y\",\"kills\":3}"), 0).Contains("Last kill: 2m ago by Y (3 kills)"), "bosses: tooltip");
            // collapse and filter
            Click(rows, "Hide");
            check(p.Collapsed.Contains("world") && !Texts(p.BuildRows(), "Rootkraken"), "bosses: a category folds");
            p.Form["search"] = "ember";
            rows = p.BuildRows();
            check(Texts(rows, "Ember Titan") && !Texts(rows, "Sepulchre") && Texts(rows, "- World Bosses (1 of 2)"), "bosses: the filter keeps matching rows and shows 1 of 2 (and unfolds)");
            p.Form["search"] = "zzz";
            check(Texts(p.BuildRows(), "No boss matches."), "bosses: no match text");
            p.Form["search"] = "";
            // the pocket button
            p.Collapsed.Clear();
            rig.Feed(217, "pocket", "{'bosses':{'a':{'l':2,'m':3,'b':1,'lv':100,'ok':1}},'reset':3600}");
            rows = p.BuildRows();
            var pb = rows.SelectMany(r => r.Buttons).FirstOrDefault(b => b.Text == "Pocket 2/3");
            check(pb != null && pb.Enabled && pb.Tip.Contains("Charges left: 2 (daily 3, bonus 1). New daily charges in 1h 00m."), "bosses: the pocket button shows the charges");
            pb.Click();
            check(rig.Last == "217:{\"action\":\"pocketEnter\",\"data\":{\"k\":\"a\"}}", "bosses: the pocket button sends pocketEnter: " + rig.Last);
            rig.Feed(217, "pocket", "{'bosses':{'a':{'l':0,'m':3,'b':0,'lv':100,'ok':1}},'reset':60}");
            check(!p.BuildRows().SelectMany(r => r.Buttons).First(b => b.Text == "Pocket 0/3").Enabled, "bosses: no charge, no pocket");
            rig.Feed(217, "pocket", "{'bosses':{'a':{'l':2,'m':3,'b':0,'lv':100,'ok':1}},'reset':60,'inside':'a'}");
            check(!p.BuildRows().SelectMany(r => r.Buttons).First(b => b.Text == "Pocket 2/3").Enabled, "bosses: inside a pocket the buttons are off");
            rig.Feed(217, "pocketError", "{'text':'Not now.'}");
            p.BuildRows();
            check(p.Header2 == "Not now.", "bosses: a refusal shows in the header line");
            // refresh by itself after the period
            rig.Feed(217, "list", BossList);
            int before = rig.Sent.Count;
            p.Poll(rig.Now + 10);
            check(rig.Sent.Count == before, "bosses: no refresh before the period");
            p.Poll(rig.Now + 40000);
            check(rig.Last == "217:{\"action\":\"refresh\",\"data\":{}}", "bosses: refresh after the period");
            rig.Feed(217, "npc", "{}");
            check(p.Visible, "bosses: the pocket NPC leaves the window open");
        }

        // ------------------------------------------------------------------------------------ game_chaossurvey
        static void SurveyChecks(Action<bool, string> check)
        {
            var rig = new Rig();
            var p = new SurveyPanel(rig.Ext) { Clock = rig.Clock };
            rig.Feed(122, "open", "{'s':7}");
            check(!p.Visible, "survey: an unknown stage is ignored");
            rig.Feed(122, "open", "{'s':20,'max':120}");
            check(p.Visible && p.Stage == 20 && p.Max == 120, "survey: open at level 20");
            var rows = p.BuildRows();
            check(rows.Any(r => r.Kind == RowKind.Combo && r.Key == "src") && rows.Any(r => r.Kind == RowKind.Input && r.Key == "text"), "survey: the source question is asked at 20");
            check(!Find(rows, r => r.Buttons.Any(b => b.Text == "Send")).Buttons.First(b => b.Text == "Send").Enabled, "survey: Send needs an answer");
            p.Form["fun"] = "4"; p.Form["rec"] = "1"; p.Form["src"] = "7"; p.Form["text"] = "  too   many\tspaces  ";
            Click(p.BuildRows(), "Send");
            check(rig.Last.Contains("\"action\":\"answer\"") && rig.Last.Contains("\"s\":20") && rig.Last.Contains("\"fun\":4") && rig.Last.Contains("\"rec\":true") && rig.Last.Contains("\"src\":\"friend\"") && rig.Last.Contains("\"text\":\"too many spaces\""), "survey: the answer: " + rig.Last);
            check(!p.Visible, "survey: Send closes the window");
            rig.Feed(122, "open", "{'s':50}");
            check(p.Stage == 50 && !p.BuildRows().Any(r => r.Key == "src"), "survey: no source question at 50");
            p.Form["src"] = "3";
            var d = SurveyPanel.Answer(50, 0, 2, "", 200, 3);
            check(!d.ContainsKey("src") && !d.ContainsKey("fun") && (bool)d["rec"] == false && !d.ContainsKey("text"), "survey: stage 50 sends no source, rec 2 is false");
            check(SurveyPanel.Answer(20, 9, 0, new string('x', 300), 50, 0)["text"].ToString().Length == 50 && !SurveyPanel.Answer(20, 9, 0, "", 50, 0).ContainsKey("fun"), "survey: text cut to max, fun out of range dropped");
            Click(p.BuildRows(), "Skip");
            check(rig.Last == "122:{\"action\":\"skip\",\"data\":{\"s\":50}}" && !p.Visible, "survey: Skip: " + rig.Last);
            rig.Feed(122, "open", "{'s':20}");
            rig.Feed(122, "done", "{'s':20}");
            check(!p.Visible, "survey: done closes the window");
        }

        // ------------------------------------------------------------------------------------ game_nemesis
        static void NemesisChecks(Action<bool, string> check)
        {
            var rig = new Rig();
            var p = new NemesisPanel(rig.Ext) { Clock = rig.Clock, Epoch = () => 10000 };
            p.Show();
            check(rig.Last == "163:{\"action\":\"get\",\"data\":{}}", "nemesis: Show asks the state");
            var rows = p.BuildRows();
            check(p.Header1 == "No Nemesis hunts you" && Texts(rows, "Avenger of Self") && Texts(rows, "Nemeses avenged: 0"), "nemesis: nobody hunts you");
            rig.Feed(163, "state", "{'has':true,'name':'Grim','shown':'Grim the Hungry','monster':'Wolf','level':120,'kills':2,'traits':[{'key':'swift','name':'Swift','desc':'Fast.'},{'name':''},{'key':'x','name':'Odd','desc':'?'}],'lastSeen':9000,'expiresIn':90000,'avenged':3,'hunted':5}");
            rows = p.BuildRows();
            check(p.Header1 == "Grim the Hungry" && p.Header2 == "A Wolf that killed you twice", "nemesis: title and sub line");
            check(Find(rows, r => r.Text == "Last seen").Right == "16 min ago" && Find(rows, r => r.Text == "Fades in").Right == "1 day" && Find(rows, r => r.Text == "Level").Right == "120", "nemesis: rows: " + Find(rows, r => r.Text == "Last seen").Right);
            check(rows.Count(r => r.Kind == RowKind.Row && (r.Text == "Swift" || r.Text == "Odd")) == 2 && Find(rows, r => r.Text == "Swift").Tone == "#70c8f0", "nemesis: traits with their colour, a nameless one left out");
            check(Texts(rows, "Nemeses avenged: 3   |   Nemeses of others slain: 5"), "nemesis: footer");
            check(NemesisPanel.SubText("Rat", 1) == "A Rat that killed you once" && NemesisPanel.SubText("Rat", 7) == "A Rat that killed you 7 times" && NemesisPanel.Left(7200) == "2 h" && NemesisPanel.Left(10) == "under an hour", "nemesis: sub text, time left");
        }

        // ------------------------------------------------------------------------------------ game_referral
        static void ReferralChecks(Action<bool, string> check)
        {
            var rig = new Rig();
            var p = new ReferralPanel(rig.Ext) { Clock = rig.Clock };
            string copied = null;
            p.Copy = t => copied = t;
            p.Show();
            check(rig.Last == "220:{\"action\":\"open\",\"data\":{}}", "referral: open");
            rig.Feed(220, "status", "{'open':true,'enabled':true,'code':'ABC123','shareUrl':'https://x.test/r/ABC123','gift':'a pet','giftTitle':'Friend','milestones':[{'level':50,'reward':'100 coins'}],'tiers':[{'count':3,'reward':'a cape','reached':true}],'qualifyLevel':50,'qualified':2,'canEnter':true,'enterLeft':260000,'linksThisMonth':1,'monthlyLinks':5,'paidThisMonth':1,'monthlyRewards':3,'coinsEarned':100," +
                "'friends':[{'name':'Zed','level':60,'linkedAt':1700000000,'steps':[{'level':50,'state':'paid'},{'level':100,'state':'open'}]}]}");
            var rows = p.BuildRows();
            check(p.Visible && Find(rows, r => r.Text == "ABC123") != null && Texts(rows, "Share it, or the link https://x.test/r/ABC123"), "referral: the code and its link");
            Click(rows, "Copy code");
            check(copied == "ABC123" && p.Status == "Code copied.", "referral: Copy code puts the code on the clipboard");
            check(Texts(rows, "Your friend gets: a pet and the title Friend.") && Texts(rows, "level 50: 100 coins") && Texts(rows, "3 friends: a cape (yours)"), "referral: rewards text");
            check(Texts(rows, "Got a code from a friend? Enter it here (3 days left).") && rows.Any(r => r.Kind == RowKind.Input && r.Key == "code"), "referral: the code box while the account is new");
            var fr = Find(rows, r => r.Text == "Zed");
            check(fr != null && fr.Sub == "Lv 50: rewarded   Lv 100: -" && fr.Right == "Level 60, joined 2023-11-14", "referral: friend row: " + fr?.Sub + " / " + fr?.Right);
            check(Texts(rows, "This month: 1 / 5 new friends, 1 / 3 rewards.   Chaos Coins earned: 100"), "referral: month line");
            p.Form["code"] = "  ";
            Click(p.BuildRows(), "Use code");
            check(p.Status == "Type the code first.", "referral: an empty code is refused");
            p.Form["code"] = "XYZ";
            Click(p.BuildRows(), "Use code");
            check(rig.Last == "220:{\"action\":\"enter\",\"data\":{\"code\":\"XYZ\"}}", "referral: enter: " + rig.Last);
            rig.Feed(220, "message", "{'text':'Not valid.','error':true}");
            check(p.Status == "Not valid." && p.StatusTone == "bad", "referral: the answer shows");
            rig.Feed(220, "status", "{'enabled':true,'code':'ABC123','referrer':'Mia','linkStatus':'active','giftGiven':false,'friends':[]}");
            rows = p.BuildRows();
            check(Texts(rows, "You were referred by Mia. Your welcome gift comes at your next login.") && !rows.Any(r => r.Key == "code") && Texts(rows, "Nobody has joined with your code yet."), "referral: referred, no box");
            rig.Feed(220, "status", "{'enabled':false}");
            check(Texts(p.BuildRows(), "The referral program is off."), "referral: program off");
        }

        // ------------------------------------------------------------------------------------ game_community
        const string GoalState = "{'now':1,'goal':{'n':'Ashen Hearth','d':'Light the hearth.','left':93784,'target':10000,'p':2500,'pct':25,'rn':'Greenmarsh'},'stages':[{'i':1,'pct':25,'key':'a','n':'Warmth','d':'+10% exp','h':3,'done':true,'left':7200},{'i':2,'pct':50,'key':'b','n':'Light','d':'+5% loot','h':3},{'i':3,'pct':100,'key':'c','n':'Dawn','d':'x'}]," +
            "'sources':[{'k':'kills','n':'Kills','cap':4000,'mine':120}],'mine':{'p':1018,'today':300,'cap':2000,'rank':2,'token':2000,'tokenText':'a token','title':'Hearthkeeper','top':3},'top':[{'n':'Vexa','p':4000},{'n':'Bob','p':1018}]," +
            "'week':{'mods':[{'k':'double','n':'Double loot','d':'Twice the loot.'}],'left':3600,'staff':true},'brazier':{'near':true,'min':10000,'max':1000000,'gold':250000,'per':1000,'room':50000}}";

        static void GoalChecks(Action<bool, string> check)
        {
            var rig = new Rig();
            var p = new CommunityGoalPanel(rig.Ext) { Clock = rig.Clock };
            p.Show();
            check(rig.Last == "203:{\"action\":\"open\",\"data\":{}}", "community: open");
            rig.Feed(203, "state", GoalState);
            var rows = p.BuildRows();
            check(p.Header1 == "Ashen Hearth - Greenmarsh" && p.Header2 == "Light the hearth.", "community: header");
            var bar = rows.First(r => r.Kind == RowKind.Bar);
            check(bar.Text == "2,500 / 10,000  (25%)" && bar.Percent == 25, "community: goal bar: " + bar.Text);
            check(Texts(rows, "Ends in 1d 2h"), "community: goal time");
            var warm = Find(rows, r => r.Text == "Warmth");
            check(warm.Right == "Active: 2h 00m left" && Find(rows, r => r.Text == "Light").Right == "At 50%", "community: stage lines: " + warm.Right);
            rig.Now = 3600 * 1000;
            check(Find(p.BuildRows(), r => r.Text == "Warmth").Right == "Active: 1h 00m left", "community: the stage countdown runs by itself");
            rig.Now = 8000 * 1000;
            check(Find(p.BuildRows(), r => r.Text == "Warmth").Right == "Reached at 25%", "community: a done stage whose window is over");
            rows = p.BuildRows();
            check(Find(rows, r => r.Text == "1,018 points (rank 2)").Right == "Today: 300 / 2,000", "community: your part");
            check(Texts(rows, "Top 3: the title Hearthkeeper.") && Texts(rows, "2,000 points: a token") && !Texts(rows, "(earned)"), "community: rewards text");
            check(Texts(rows, "1.  Vexa") && Texts(rows, "2.  Bob") && Texts(rows, "This week (1m left), set by the staff"), "community: top rows and the week");
            check(rows.Any(r => r.Kind == RowKind.Bar && r.Text.StartsWith("Kills   120 / 4,000") && r.Percent == 3), "community: source bar");
            check(Texts(rows, "Double loot"), "community: week modifiers");
            // the Brazier
            check(CommunityGoalPanel.ParseGold("150k") == 150000 && CommunityGoalPanel.ParseGold("1.5m") == 1500000 && CommunityGoalPanel.ParseGold("25,000") == 25000 && CommunityGoalPanel.ParseGold("2kk") == 2000000 && CommunityGoalPanel.ParseGold("abc") == -1 && CommunityGoalPanel.ParseGold("5x") == -1, "community: gold amounts");
            var data = Json.Parse(GoalState.Replace('\'', '"'));
            long take, pts;
            check(CommunityGoalPanel.Donation(data, 5000, out take, out pts) == "At least 10,000 gold.", "community: under the minimum");
            check(CommunityGoalPanel.Donation(data, 300000, out take, out pts) == null && take == 50000 && pts == 50, "community: the room of the day caps the donation");
            check(CommunityGoalPanel.Donation(data, 10500, out take, out pts) == null && take == 10000 && pts == 10, "community: whole units only");
            check(CommunityGoalPanel.Donation(Json.Parse("{\"brazier\":{\"min\":1,\"max\":0,\"gold\":5,\"per\":1,\"room\":100}}"), 50, out take, out pts) == "You do not have that much gold.", "community: not enough gold");
            check(CommunityGoalPanel.QuickAmounts(data).SequenceEqual(new long[] { 10000, 100000, 1000000 }) && CommunityGoalPanel.Short(1000000) == "1m" && CommunityGoalPanel.Short(10000) == "10k", "community: quick amounts");
            rig.Feed(203, "brazier", "{}");
            check(p.Tab == "brazier" && p.Visible, "community: the Brazier message opens its tab");
            rows = p.BuildRows();
            check(Texts(rows, "You carry 250,000 gold") && Texts(rows, "Enter an amount of gold."), "community: the Brazier tab");
            Click(rows, "+10k");
            check(p.Text("gold") == "10000", "community: a quick button adds");
            rows = p.BuildRows();
            check(Texts(rows, "Give 10,000 gold for 10 points."), "community: preview line");
            Click(rows, "Give");
            check(rig.Last == "203:{\"action\":\"donate\",\"data\":{\"gold\":10000}}" && p.Text("gold") == "", "community: donate: " + rig.Last);
            rig.Feed(203, "msg", "{'text':'Thank you.','ok':true}");
            check(p.Status == "Thank you." && p.StatusTone == "good", "community: a message");
            p.Poll(rig.Now + 7000);
            check(p.Status == "", "community: the message goes away");
            p.Hide();
            check(rig.Last == "203:{\"action\":\"close\",\"data\":{}}", "community: close");
        }

        // ------------------------------------------------------------------------------------ game_chronicle
        const string ChronState = "{'season':'3','active':true,'title':{'en':'The Long Fire','pt':'O Fogo Longo'},'intro':{'en':['It began.'],'pt':['Começou.']},'chapters':[" +
            "{'i':1,'key':'one','state':'done','pct':100,'doneAt':1700000000,'title':{'en':'Embers','pt':'Brasas'},'text':{'en':['The embers woke.'],'pt':['As brasas acordaram.']},'world':{'en':'A gate opened.','pt':'Um portão abriu.'},'goals':[{'l':'Kills','lp':'Abates','p':500,'t':1000}],'mine':42,'top':[{'n':'Vexa','p':300}]}," +
            "{'i':2,'key':'two','state':'open','pct':12.5,'title':{'en':'Flames','pt':'Chamas'},'text':{'en':['It spread.']},'pending':['x']},{'i':3,'key':'three','state':'locked','title':{'en':'Ash'}}]," +
            "'record':[{'season':2,'name':'Winter','title':{'en':'Frost'},'chapters':[{'i':1,'title':{'en':'Ice'},'top':[{'n':'Al','p':10},{'n':'Bo','p':9}]}]}]}";

        static void ChronicleChecks(Action<bool, string> check)
        {
            var rig = new Rig();
            var p = new ChroniclePanel(rig.Ext) { Clock = rig.Clock };
            p.Show();
            check(rig.Sent.Contains("171:{\"action\":\"open\",\"data\":{}}") && rig.Last == "171:{\"action\":\"mem\",\"data\":{}}", "chronicle: open asks the chronicle and the memorial");
            rig.Feed(171, "state", ChronState);
            check(p.SelectedChapter == 2, "chronicle: the open chapter is selected first");
            var rows = p.BuildRows();
            check(p.Header1 == "The Long Fire" && p.Header2 == "Season 3", "chronicle: header in English");
            check(Find(rows, r => r.Text == "1. Embers").Right == "Written on 14 Nov 2023" && Find(rows, r => r.Text == "2. Flames").Right == "Open: 12.5% written" && Find(rows, r => r.Text == "3. Ash").Right == "Not yet told", "chronicle: chapter lines");
            check(Texts(rows, "It spread.") && Texts(rows, "The way is not on the map yet"), "chronicle: the selected chapter text and the pending note");
            Click(rows, "Read");
            rows = p.BuildRows();
            Loc.Set("pt-BR");
            check(ChroniclePanel.Lang() == "pt", "chronicle: the language follows the client");
            p.SelectedChapter = 1;
            rows = p.BuildRows();
            check(p.Header1 == "O Fogo Longo" && Texts(rows, "As brasas acordaram.") && Texts(rows, "Um portão abriu.") && rows.Any(r => r.Kind == RowKind.Bar && r.Text.StartsWith("Abates") && r.Percent == 50), "chronicle: Portuguese story, world text and goal label");
            Loc.Set("en");
            rows = p.BuildRows();
            check(Texts(rows, "The embers woke.") && rows.Any(r => r.Kind == RowKind.Bar && r.Text.StartsWith("Kills   500 / 1,000")) && Texts(rows, "1.  Vexa"), "chronicle: English story and the top");
            p.SelectTab("record");
            rows = p.BuildRows();
            check(Texts(rows, "Winter: Frost") && Find(rows, r => r.Text == "1. Ice").Sub == "1. Al 10   2. Bo 9", "chronicle: the record of past seasons");
            p.SelectTab("memorial");
            check(rig.Last == "171:{\"action\":\"mem\",\"data\":{}}", "chronicle: the memorial tab asks the memorial");
            rig.Feed(171, "mem", "{'season':'3','records':true,'fallen':false,'ask':true,'firsts':[{'t':'First kill','n':'Vexa','at':1700000000}],'recs':[{'t':'Fastest','v':'12:00','n':'','c':'','at':0}],'falls':[{'n':'Grim','l':80,'c':'Warrior','k':'a wolf','at':1700000000}]}");
            rows = p.BuildRows();
            check(p.Header2 == "Your fall waits for an answer" && p.Text("m_records") == "1" && p.Text("m_fallen") == "0", "chronicle: the choice page asks and shows the saved choice");
            p.Form["m_fallen"] = "1";
            Click(rows, "Save");
            check(rig.Last == "171:{\"action\":\"memset\",\"data\":{\"records\":true,\"fallen\":true}}", "chronicle: memset sends booleans: " + rig.Last);
            p.MemSection = "firsts"; rows = p.BuildRows();
            check(Find(rows, r => r.Text == "First kill").Sub == "Vexa" && Find(rows, r => r.Text == "First kill").Right == "14 Nov 2023", "chronicle: realm firsts");
            p.MemSection = "records"; rows = p.BuildRows();
            check(Find(rows, r => r.Text == "Fastest").Sub == "12:00, a hero who keeps their name", "chronicle: a hidden record keeps no name");
            p.MemSection = "falls"; rows = p.BuildRows();
            check(Find(rows, r => r.Text == "Grim").Sub == "level 80 Warrior, a wolf", "chronicle: the fallen");
            p.Hide();
            check(rig.Last == "171:{\"action\":\"close\",\"data\":{}}", "chronicle: close");
        }

        // ------------------------------------------------------------------------------------ game_mentor
        const string MentorStatus = "{'open':true,'enabled':true,'canPick':true,'seeking':false,'lines':[{'key':'knight','name':'Knights'}],'rules':{'maxLevel':50,'accountDays':14,'exp':20,'dmg':15,'gradLevel':50,'gradReward':'a title','gradMarks':30,'gradShared':60," +
            "'mentorLevel':100,'mentorHours':20,'mentorDays':30,'maxApprentices':3,'minShared':20,'huntMinutes':10,'dailyHuntMarks':6,'monthlyCap':60},'referrer':{'guid':9,'name':'Mia'},'invites':[{'guid':5,'name':'Old','level':200,'voc':'Knight','left':125}],'shop':[{'key':'t1','kind':'title','name':'Guide','cost':20,'desc':'A title.'},{'key':'s1','kind':'item','name':'Potions','cost':5,'weeklyLeft':0}],'top':[{'rank':1,'name':'Ace','level':300,'voc':'Mage','graduates':4}]}";

        static void MentorChecks(Action<bool, string> check)
        {
            var rig = new Rig();
            var p = new MentorPanel(rig.Ext) { Clock = rig.Clock };
            p.Show();
            check(rig.Last == "194:{\"action\":\"open\",\"data\":{}}", "mentor: open");
            rig.Feed(194, "status", MentorStatus);
            check(p.Visible && p.Tab == "find" && rig.Last.Contains("\"action\":\"list\"") && rig.Last.Contains("\"online\":\"any\""), "mentor: open status shows Find and searches: " + rig.Last);
            rig.Feed(194, "mentors", "{'rows':[{'guid':1,'name':'Sage','level':350,'voc':'Druid','lang':'English','hours':'evenings','graduates':1,'max':3,'active':2,'online':true,'note':'Be kind.'},{'guid':2,'name':'Full','level':300,'voc':'Mage','max':1,'active':1,'online':false}]}");
            var rows = p.BuildRows();
            check(Texts(rows, "New characters (up to level 50, account up to 14 days old)") && Texts(rows, "Your referrer mentors as Mia."), "mentor: pick text and the referrer");
            var sage = Find(rows, r => r.Text == "Sage  -  Lv 350 Druid");
            check(sage != null && sage.Right == "online" && sage.Sub == "English  -  evenings  -  1 graduate  -  1 place free", "mentor: row: " + sage?.Sub);
            check(sage.Buttons[0].Enabled && !Find(rows, r => r.Text.StartsWith("Full")).Buttons[0].Enabled, "mentor: a full mentor cannot be chosen");
            sage.Buttons[0].Click();
            check(rig.Last == "194:{\"action\":\"choose\",\"data\":{\"guid\":1}}", "mentor: choose: " + rig.Last);
            Click(rows, "Accept");
            check(rig.Last == "194:{\"action\":\"accept\",\"data\":{\"guid\":5}}" && Texts(rows, "Old (Lv 200 Knight) invites you - 3 min left"), "mentor: accept an invitation");
            p.Form["f_online"] = "2"; p.Form["f_lang"] = "Portuguese"; p.Form["f_line"] = "1";
            Click(p.BuildRows(), "Search");
            check(rig.Last == "194:{\"action\":\"list\",\"data\":{\"line\":\"knight\",\"lang\":\"Portuguese\",\"online\":\"now\"}}", "mentor: the filter: " + rig.Last);
            p.Form["seek"] = "1"; p.OnForm("seek");
            check(rig.Last == "194:{\"action\":\"seek\",\"data\":{\"on\":true}}", "mentor: seek");
            p.SelectTab("shop");
            rows = p.BuildRows();
            check(Texts(rows, "Mentor Marks are earned by mentoring."), "mentor: the shop needs a mentor");
            var buy = Find(rows, r => r.Text == "Title: Guide").Buttons[0];
            check(!buy.Enabled && buy.Text == "Mentors only", "mentor: shop button for a non-mentor");
            // as a mentor
            rig.Feed(194, "status", MentorStatus.Replace("'open':true", "'open':false").Replace("'top':[", "'mentor':{'marks':25,'earned':80,'graduates':2,'dayMarks':3,'dayMinutes':45,'monthMarks':10,'linksThisMonth':1,'monthlyLinks':3,'lang':'English','hours':'nights','note':'hi','accepting':true,'public':true,'apprentices':[{'guid':7,'name':'Kid','level':20,'voc':'Knight','online':true,'linkedAt':1700000000,'shared':95,'milestones':[{'key':'l25','state':'paid'},{'key':'rift','state':'open'}]}]},'top':["));
            rows = p.BuildRows();
            check(Find(rows, r => r.Text == "Title: Guide").Buttons[0].Enabled && Texts(rows, "Your Mentor Marks: 25") && Find(rows, r => r.Text == "Title: Guide").Right == "20 marks", "mentor: shop as a mentor");
            check(!Find(rows, r => r.Text == "Supplies: Potions").Buttons[0].Enabled && Find(rows, r => r.Text == "Supplies: Potions").Buttons[0].Text == "Next week", "mentor: weekly limit");
            Find(rows, r => r.Text == "Title: Guide").Buttons[0].Click();
            check(rig.Last == "194:{\"action\":\"buy\",\"data\":{\"key\":\"t1\"}}", "mentor: buy");
            p.SelectTab("mentoring");
            rows = p.BuildRows();
            check(Texts(rows, "Marks 25 (earned 80)   Graduates 2   Today 3/6 marks, 45 min   Month 10/60 marks, 1/3 new") && Texts(rows, "Apprentices (1 / 3)"), "mentor: stats and apprentices");
            var kid = Find(rows, r => r.Text.StartsWith("Kid  -  Lv 20 Knight"));
            check(kid.Sub == "25 marks paid   Rift -" && kid.Right == "Since 2023-11-14, together 1h 35m", "mentor: apprentice row: " + kid.Sub + " / " + kid.Right);
            kid.Buttons[0].Click();
            check(rig.Last == "194:{\"action\":\"release\",\"data\":{\"guid\":7}}", "mentor: release");
            p.Form["inv"] = "Newbie";
            Click(p.BuildRows(), "Invite");
            check(rig.Last == "194:{\"action\":\"invite\",\"data\":{\"name\":\"Newbie\"}}", "mentor: invite");
            Click(p.BuildRows(), "Save card");
            check(rig.Last.Contains("\"action\":\"register\"") && rig.Last.Contains("\"lang\":\"English\"") && rig.Last.Contains("\"accepting\":true"), "mentor: the card is saved with its flags: " + rig.Last);
            Click(p.BuildRows(), "Retire");
            check(rig.Last == "194:{\"action\":\"retire\",\"data\":{}}", "mentor: retire");
            p.SelectTab("top");
            check(Texts(p.BuildRows(), "#1  Ace  -  Lv 300 Mage"), "mentor: top mentors");
            // apprentice view
            rig.Feed(194, "status", "{'open':true,'enabled':true,'apprentice':{'name':'Sage','level':350,'voc':'Druid','online':true,'linkedAt':1700000000,'shared':30,'source':'invite','bonus':true,'bonusText':'Bonus on.','milestones':[{'key':'l25','name':'Level 25','state':'paid','got':5}]},'rules':{'gradLevel':50,'gradReward':'x','gradMarks':1,'gradShared':1}}");
            check(p.Tab == "top", "mentor: a status that does not open the window keeps the tab");
            p.SelectTab("mine");
            rows = p.BuildRows();
            check(Texts(rows, "Sage  -  Lv 350 Druid  (online)") && Texts(rows, "Mentor since 2023-11-14 (by invitation). Hunted together: 30 min.") && Texts(rows, "Bonus on.") && Find(rows, r => r.Text == "Level 25").Right == "marks paid  +5", "mentor: My mentor page");
            Click(rows, "Dismiss");
            check(rig.Last == "194:{\"action\":\"dismiss\",\"data\":{}}", "mentor: dismiss");
            // the offer
            rig.Feed(194, "offer", "{'online':2,'any':5,'exp':20,'dmg':15}");
            rows = p.BuildRows();
            check(Texts(rows, "2 mentors who speak your language are online now.") && Texts(rows, "+20% experience and take 15% less damage"), "mentor: the offer texts");
            Click(rows, "No thanks");
            check(rig.Last == "194:{\"action\":\"offer\",\"data\":{\"answer\":\"no\"}}" && p.Offer == null, "mentor: no thanks ends the offer");
            rig.Feed(194, "offer", "{'online':0,'any':0,'exp':20,'dmg':15}");
            check(Texts(p.BuildRows(), "No mentor is online right now"), "mentor: nobody online text");
            Click(p.BuildRows(), "Find a mentor");
            check(rig.Last == "194:{\"action\":\"offer\",\"data\":{\"answer\":\"find\"}}" && p.Tab == "find", "mentor: the offer's Find a mentor");
            rig.Feed(194, "message", "{'text':'Done.'}");
            check(p.Status == "Done." && p.StatusTone == "good", "mentor: a message");
        }

        // ------------------------------------------------------------------------------------ game_patchnotes
        static void PatchNotesChecks(Action<bool, string> check)
        {
            var rig = new Rig();
            var p = new PatchNotesPanel(rig.Ext) { Clock = rig.Clock };
            bool daily = false;
            p.DailyVisible = () => daily;
            double saved = 0;
            p.LoadSeen = () => saved; p.SaveSeen = v => saved = v;
            // the login auto-open waits for the Daily Reward window
            rig.Feed(244, "list", "{'weeks':[{'id':'2026-w45','title':'Autumn','date':'2026-11-02','new':true},{'id':'2026-w44','title':'Earlier','date':'2026-10-26'}],'selected':'2026-w45','auto':true,'autoEnabled':true,'dailyFirst':true}");
            check(!p.Visible && p.Pending != null && p.SelectedId == "2026-w45", "patchnotes: a login auto message does not open the window by itself");
            rig.Now = 1000; p.Poll(1000, true);
            check(!p.Visible, "patchnotes: it waits for a Daily Reward window the server expects (6 s)");
            daily = true; p.Poll(2000, true); p.Poll(3000, true);
            check(!p.Visible, "patchnotes: it waits while the daily window is on screen");
            daily = false; p.Poll(4000, true);
            check(!p.Visible, "patchnotes: a short pause after the daily window closed");
            p.Poll(5000, true);
            check(p.Visible && rig.Last == "244:{\"action\":\"open\",\"data\":{\"id\":\"2026-w45\"}}", "patchnotes: then it opens: " + rig.Last);
            p.Hide();
            check(rig.Last == "244:{\"action\":\"closed\",\"data\":{}}", "patchnotes: closed is reported");
            var st = new PatchNotesPanel.Auto { DailyFirst = false, Since = 0 };
            check(PatchNotesPanel.AutoStep(st, false, 1) == "show", "patchnotes: no daily expected, show");
            st = new PatchNotesPanel.Auto { DailyFirst = true, Since = 0 };
            check(PatchNotesPanel.AutoStep(st, false, 5) == "wait" && PatchNotesPanel.AutoStep(st, false, 6.5) == "show", "patchnotes: waits at most 6 s for a daily window that never comes");
            // a note in parts is joined
            rig.Feed(244, "note", "{'id':'2026-w45','title':'Autumn','date':'2026-11-02','part':2,'parts':2,'sections':[{'name':'Fixes','kind':'fixes','cont':true,'items':[{'text':'Two','level':1}]},{'name':'Balance','kind':'balance','items':[{'text':'Nerf','level':2,'lead':'Mage:'}]}]}");
            check(!p.Notes.ContainsKey("2026-w45"), "patchnotes: a note waits for its missing part");
            rig.Feed(244, "note", "{'id':'2026-w45','title':'Autumn','date':'2026-11-02','part':1,'parts':2,'intro':['Hello.'],'sections':[{'name':'Fixes','kind':'fixes','items':[{'text':'One','level':1},{'text':'Plain','level':0}]}]}");
            check(p.Notes.ContainsKey("2026-w45"), "patchnotes: both parts make the note");
            p.Show();
            var rows = p.BuildRows();
            check(p.Header1 == "Autumn" && p.Header2 == "2 November 2026", "patchnotes: title and date");
            check(Texts(rows, "Hello.") && rows.Count(r => r.Kind == RowKind.Section && r.Text == "Fixes") == 1 && Texts(rows, "  - One") && Texts(rows, "  - Two") && Texts(rows, "Plain") && Texts(rows, "      - Mage: Nerf"), "patchnotes: a continued section is one section, bullets by level");
            check(rig.Sent.Any(s => s.Contains("\"action\":\"seen\"") && s.Contains("2026-w45")), "patchnotes: a shown note is reported seen");
            check(rig.Sent.Count(s => s.Contains("\"action\":\"seen\"")) == 1, "patchnotes: once");
            // the week list: another week is asked for
            p.Form["week"] = "1";
            p.BuildRows();
            check(rig.Last == "244:{\"action\":\"get\",\"data\":{\"id\":\"2026-w44\"}}" && p.SelectedId == "2026-w44", "patchnotes: picking another week asks its note: " + rig.Last);
            p.Form["auto"] = "1"; p.OnForm("auto");
            check(rig.Last == "244:{\"action\":\"auto\",\"data\":{\"enabled\":false}}", "patchnotes: the login auto-open can be switched off");
            // changelog
            p.SelectTab("changelog");
            check(rig.Last == "244:{\"action\":\"changelog\",\"data\":{}}", "patchnotes: the Changelog tab asks the changelog");
            rig.Feed(244, "changelog", "{'available':true,'server':{'date':'2026-11-05'},'entries':[{'id':'a','date':'2026-11-05','ts':200,'text':'Boss fix','tags':['server','client'],'client':31},{'id':'b','date':'2026-11-05','ts':100,'text':'New icon','tags':['content'],'pending':false}]}");
            saved = 150;
            rows = p.BuildRows();
            check(Texts(rows, "NEW [Server] [Client 31] Boss fix") && Texts(rows, "[Content] New icon") && !Texts(rows, "NEW [Content]"), "patchnotes: changelog rows with tags and NEW against the last look");
            check(p.Header2.Contains("Server updated: 5 November 2026"), "patchnotes: the info line");
            check(saved == 200, "patchnotes: the last look is saved");
            p.Form["cl_filter"] = "3";
            rows = p.BuildRows();
            check(Texts(rows, "New icon") && !Texts(rows, "Boss fix"), "patchnotes: the filter by tag");
            check(PatchNotesPanel.FormatDate("2026-10-08") == "8 October 2026" && PatchNotesPanel.FormatDate("junk") == "junk" && PatchNotesPanel.FormatDate("2026-10-08", true) == "8 Oct 2026", "patchnotes: dates");
            check(PatchNotesPanel.NewCount(Json.Parse("{\"entries\":[{\"ts\":5},{\"ts\":50}]}"), 10) == 1 && PatchNotesPanel.NewCount(Json.Parse("{\"entries\":[{\"ts\":5}]}"), 0) == 0, "patchnotes: new count is 0 before the first look");
        }

        // ------------------------------------------------------------------------------------ card borders, drop feed, credits
        static void SmallChecks(Action<bool, string> check)
        {
            var rig = new Rig();
            var cb = new CardBorderState(rig.Ext);
            check(cb.Kind(1, 2) == null, "cardborder: before the first message nothing is drawn");
            cb.Sync();
            check(rig.Last == "172:{\"action\":\"sync\",\"data\":{}}", "cardborder: sync");
            rig.Feed(172, "state", "{'on':[10],'cards':[10,11],'decks':[500]}");
            check(cb.Kind(500, 10) == "on" && cb.Kind(500, 11) == "off" && cb.Kind(501, 10) == null && cb.Kind(500, 12) == null, "cardborder: lit, dim, not a deck, not a card");
            check(CardBorderState.ColorOf("on") == "#7fe05a" && CardBorderState.ColorOf("off") == "#6a3a3a" && CardBorderState.ColorOf(null) == null, "cardborder: colours");

            var df = new DropFeedPanel(rig.Ext) { Load = () => "unique" };
            df.Poll(false);
            int before = rig.Sent.Count;
            check(rig.Sent.Count == before, "dropfeed: nothing before the login");
            df.Poll(true);
            check(rig.Last == "229:{\"action\":\"feedopt\",\"data\":{\"mode\":\"unique\"}}", "dropfeed: the saved mode is sent at the login: " + rig.Last);
            df.Poll(true);
            check(rig.Sent.Count == before + 1, "dropfeed: once");
            string saved = null;
            df.Save = m => saved = m;
            df.BuildRows();
            df.Form["mode"] = "0"; df.OnForm("mode");
            check(rig.Last == "229:{\"action\":\"feedopt\",\"data\":{\"mode\":\"off\"}}" && saved == "off", "dropfeed: a change is saved and sent");
            check(DropFeedPanel.Normalize("x") == "legendary" && DropFeedPanel.IndexOf("x") == 2 && DropFeedPanel.NameOf("unique") == "Unique and Divine only", "dropfeed: modes");

            var cr = new CreditsPanel();
            var rows = cr.BuildRows();
            check(CreditsData.All.Length >= 3 && rows.Count(r => r.Kind == RowKind.Section) == CreditsData.All.Length, "credits: one section per section of docs/CREDITS.md");
            check(CreditsPanel.RequiredCredits().Count > 0 && CreditsPanel.RequiredCredits().All(c => rows.Any(r => r.Sub == c || r.Text == "    " + c || r.Text.Contains(c))), "credits: every required credit line is shown word for word");
            Loc.Set("pt-BR");
            check(cr.BuildRows().Any(r => r.Kind == RowKind.Section && r.Text == CreditsData.All[1].Pt), "credits: headings in Portuguese");
            Loc.Set("en");
        }

        // ------------------------------------------------------------------------------------ streamer and cinema mode
        static void StreamerChecks(Action<bool, string> check)
        {
            var st = new StreamerState();
            var store = new Dictionary<string, bool>();
            st.Load = k => store.TryGetValue(k, out bool v) && v;
            st.Save = (k, v) => store[k] = v;
            string who = "Mia", text = "hello";
            check(!st.MaskTalk(TalkType.PrivateFrom, ref who, ref text) && text == "hello", "streamer: off, nothing is hidden");
            st.Set("streamerMode", true);
            check(store["streamerMode"], "streamer: the option is saved");
            check(st.MaskTalk(TalkType.PrivateFrom, ref who, ref text) && text == "(private message hidden: streamer mode)" && who == "Mia", "streamer: private text hidden, the sender stays");
            st.Set("streamerHideSender", true); text = "hi";
            st.MaskTalk(TalkType.PrivateFrom, ref who, ref text);
            check(who == "[hidden]", "streamer: the sender too with the sub-option");
            who = "Mia"; text = "say";
            check(!st.MaskTalk(TalkType.Say, ref who, ref text) && text == "say" && who == "Mia", "streamer: public speech is left alone");
            check(st.MaskIps("connect to 192.168.1.20:7172 now, or 10.0.0.1.") == "connect to ***.***.***.*** now, or ***.***.***.***.", "streamer: IP addresses masked (port dropped): " + st.MaskIps("connect to 192.168.1.20:7172 now, or 10.0.0.1."));
            check(st.MaskIps("version 1.2.3 and 999.1.1.1 and 5.6") == "version 1.2.3 and 999.1.1.1 and 5.6", "streamer: what is not an address stays");
            check(st.ListName("Zed", false) == "Hidden character" && st.ListName("Zed", true) == "Zed", "streamer: the other characters of the list are masked");
            check(!st.HideOwnNameNow, "streamer: the own name shows until its sub-option is on");
            st.Set("streamerHideOwnName", true);
            check(st.HideOwnNameNow, "streamer: the own name sub-option");
            check(!st.HideOthersNow, "streamer: cinema off hides no names");
            st.Set("cinemaHideOthers", true); st.ToggleCinema();
            check(st.Cinema && st.HideOthersNow, "cinema: on, other players' names hidden with the sub-option");
            st.ToggleCinema();
            check(!st.Cinema && !st.HideOthersNow, "cinema: off");
            var st2 = new StreamerState { Load = st.Load };
            st2.LoadAll();
            check(st2.Streamer && st2.HideSender && st2.HideOwnName && st2.CinemaHideOthers, "streamer: the options load back");
            st.Set("streamerMode", false);
            who = "Mia"; text = "x";
            check(st.ListName("Zed", false) == "Zed" && st.MaskIps("1.2.3.4") == "1.2.3.4", "streamer: off again, nothing masked");
            // the chat model uses it
            var chat = new ChatModel();
            var s3 = new StreamerState { Streamer = true };
            chat.Streamer = s3;
            var line = chat.OnTalk("Mia", 10, TalkType.PrivateFrom, 0, "secret plan");
            check(line != null && line.Text == "(private message hidden: streamer mode)" && !line.Display.Contains("secret"), "streamer: a private message is hidden before the chat stores it");
            var l2 = chat.OnText(4, -1, "server is 10.1.2.3:7171");
            check(l2.Text == "server is ***.***.***.***", "streamer: the chat masks addresses in server texts: " + l2.Text);
            string got = null;
            chat.ServerText = t => got = t;
            chat.OnText(4, -1, "New record: Fastest: 9");
            check(got == "New record: Fastest: 9", "streamer: server texts reach the screenshot hook");
        }

        // ------------------------------------------------------------------------------------ performance
        static void PerfChecks(Action<bool, string> check)
        {
            var s = PerfCore.Stats(new double[] { 60, 50, 40, 30, 20, 10, 5, 100, 90, 80 });
            check(s.N == 10 && s.Min == 5 && s.Max == 100 && s.Median == 40 && s.P5 == 5 && s.P95 == 100 && Math.Abs(s.Avg - 48.5) < 1e-9, "perf: stats (nearest rank)");
            check(PerfCore.Stats(new double[0]).N == 0 && PerfCore.Percentile(new List<double>(), 50) == 0, "perf: empty stats");
            check(PerfCore.Verdict(60, 40) == "good" && PerfCore.Verdict(45, 20) == "ok" && PerfCore.Verdict(20, 10) == "low" && PerfCore.Verdict(60, 20) == "ok", "perf: verdicts");
            var perf = new PerfState { Os = "Test", Screen = "1280x720", Version = "t" };
            string stampSeen = null, csv = null, report = null;
            perf.WriteFiles = (st, c, r) => { stampSeen = st; csv = c; report = r; };
            perf.UtcNow = () => new DateTime(2026, 11, 8, 14, 25, 1, DateTimeKind.Utc);
            double t = 0;
            // 30 fps for 12 seconds: 10 samples kept for the overlay
            for (int i = 0; i < 12 * 30; i++) { t += 1000.0 / 30; perf.Frame(t, 1000.0 / 30, 50000, 7, new[] { "SkillsWindow" }); }
            check(perf.Recent.Count == PerfCore.WindowS && Math.Abs(perf.Recent[perf.Recent.Count - 1].Fps - 30) < 1.5, "perf: the overlay keeps the last 10 samples, about 30 fps");
            perf.Record();
            for (int i = 0; i < 61 * 30 && perf.Recording != null; i++) { t += 1000.0 / 30; perf.Frame(t, i % 30 == 0 ? 80 : 33, 50000 + i, 7, new[] { "SkillsWindow", "MapWindow", "SkillsWindow" }); }
            check(perf.Recording == null && csv != null, "perf: a record ends after 60 samples and writes its files");
            check(stampSeen == "20261108-142501" && PerfCore.CsvName(stampSeen) == "chaos-perf-20261108-142501.csv", "perf: file names use the time");
            check(csv.Split('\n').Length == 62 && csv.StartsWith("second,fps,frame_ms,worst_frame_ms,managed_kb,creatures,windows\n") && csv.Contains("MapWindow SkillsWindow"), "perf: CSV has a header and 60 rows, windows once each, sorted");
            check(report.Contains("verdict: ok") || report.Contains("verdict: low") || report.Contains("verdict: good"), "perf: report has a verdict");
            check(report.Contains("open windows (seconds visible of 60):") && report.Contains("  MapWindow 60") && report.Contains("creatures on screen: avg 7.0") && report.Contains("Unity client performance record"), "perf: report lists windows and creatures");
            check(perf.LastFiles.Contains("chaos-perf-20261108-142501.txt"), "perf: the panel names the last files");
            var panel = new PerfPanel(perf);
            string copied = null;
            panel.Copy = c => copied = c;
            var rows = panel.BuildRows();
            Click(rows, "Copy summary");
            check(copied == report && Texts(rows, "FPS") && Texts(rows, "Managed memory"), "perf: the overlay rows and Copy summary");
            Click(rows, "Record 60 s");
            check(perf.Recording != null && Texts(panel.BuildRows(), "Recording: 0 of 60 s"), "perf: Record 60 s starts a record");
        }

        // ------------------------------------------------------------------------------------ automatic screenshots
        static void ShotsChecks(Action<bool, string> check)
        {
            var rig = new Rig();
            var s = new ShotsState(rig.Ext);
            var taken = new List<string>();
            s.Shoot = (ev, name) => taken.Add(ev + "=" + name);
            s.CharName = () => "Mia Vex";
            int level = 10;
            s.LevelNow = () => level;
            s.UtcNow = () => new DateTime(2026, 11, 8, 14, 25, 1, DateTimeKind.Utc);
            s.Poll(0, false);
            s.Poll(1000, true);
            check(taken.Count == 0 && s.LastLevel == 10, "shots: the level at the login is not a level up");
            level = 11;
            s.Poll(2000, true);
            check(s.Pending == "level" && taken.Count == 0, "shots: a level up waits 300 ms");
            s.Poll(2400, true);
            check(taken.Count == 1 && taken[0] == "level=screenshots/Mia_Vex_11_levelup_20261108-142501.png", "shots: the picture is named: " + (taken.Count > 0 ? taken[0] : ""));
            level = 12;
            s.Poll(3000, true);
            check(s.Pending == null, "shots: the same event again within 3 s is one picture");
            s.Poll(6000, true); level = 13; s.Poll(6100, true); s.Poll(6500, true);
            check(taken.Count == 2, "shots: after 3 s a new level up is a new picture");
            check(s.Request("loot", 10000) == "off" && !s.Wants("loot"), "shots: valuable loot is off by default");
            s.SetOption("shots_loot", true);
            // loot message through opcode 238
            s.Poll(10000, true);
            rig.Feed(238, "kill", "{'k':1,'m':'Wolf','items':[{'r':2,'n':1},{'r':5,'n':2}]}");
            check(s.Pending == "loot", "shots: a legendary drop asks for a picture");
            s.Poll(10400, true);
            check(taken.Count == 3 && taken[2].Contains("_loot_"), "shots: loot picture");
            // two events at once: the higher rank names the picture
            s.Poll(20000, true);
            s.SetOption("shots_record", true);
            s.OnServerText("New record: Fastest: 9 (was 10)");
            s.Request("achievement", 20000);
            check(s.Pending == "record", "shots: a new record outranks an achievement in the same picture");
            s.Poll(20400, true);
            check(taken.Count == 4 && taken[3].Contains("_record_"), "shots: one picture for both");
            rig.Feed(250, "unlock", "{}");
            s.Poll(30000, true);
            rig.Feed(250, "unlock", "{}");
            s.Poll(30000, true); s.Poll(30500, true);
            check(taken.Count == 5 && taken[4].Contains("_achievement_"), "shots: achievement unlock");
            s.SetOption(ShotsState.MasterKey, false);
            check(!s.Wants("level") && s.Request("level", 50000) == "off", "shots: the master switch");
            check(ShotsState.FileName("boss", "Zed", 5, "d", true, null) == "screenshots/5_boss_d.png", "shots: streamer mode leaves the name out");
            check(ShotsState.FileName("level", "Zed", 5, "d", false, p => p == "screenshots/Zed_5_levelup_d.png" || p == "screenshots/Zed_5_levelup_d_1.png") == "screenshots/Zed_5_levelup_d_2.png", "shots: a free file name");
            check(ShotsState.FileName("level", "A/B:c", 1, "x y", false, null) == "screenshots/A_B_c_1_levelup_x_y.png", "shots: file name characters");
            check(ShotsState.ValuableLoot(5, false) && ShotsState.ValuableLoot(1, true) && !ShotsState.ValuableLoot(4, false) && ShotsState.IsRecordMessage("Novo recorde: x") && !ShotsState.IsRecordMessage("Record"), "shots: loot ranks and record lines");
            check(ShotsState.ToastText("C:\\Users\\Name\\x", true) == "Screenshot saved in screenshots" && ShotsState.ToastText("/data/x", false) == "Screenshot saved in /data/x", "shots: the toast hides the path in streamer mode");
            var panel = new ShotsPanel(s);
            panel.BuildRows();
            panel.Form["s_master"] = "1"; panel.OnForm("s_master");
            check(s.Master, "shots: the options window changes the master switch");
        }

        // ------------------------------------------------------------------------------------ Customise Character extras
        static void ExtrasChecks(Action<bool, string> check)
        {
            var rig = new Rig();
            var cos = new CosmeticsState(rig.Ext) { Clock = rig.Clock };
            var pets = new PetsState(rig.Ext) { Clock = rig.Clock };
            var info = new ChaosInfo(rig.Ext);
            var panel = new OutfitExtrasPanel(() => cos, () => pets, () => info);
            check(panel.Rows().Count == 0 && Texts(panel.BuildRows(), "Loading..."), "extras: no source, no rows");
            rig.Feed(225, "state", "{'line':'ember','rows':[{'id':1,'kind':'outline','name':'Gold outline','owned':true,'selected':true},{'id':2,'kind':'outline','name':'Red outline','owned':true},{'id':3,'kind':'outline','name':'Blue outline','owned':false}," +
                "{'id':5,'kind':'spellskin','name':'Ember skin','owned':true,'line':'ember'},{'id':6,'kind':'spellskin','name':'Frost skin','owned':true,'line':'frost'}]}");
            rig.Feed(254, "state", "{'pets':[{'species':'wolf','name':'Rex','speciesName':'Wolf','level':7}],'active':'','catalog':[{'key':'wolf','owned':true},{'key':'bat','owned':false}]}");
            rig.Feed(237, "services", "{'frames':['gold','iron'],'activeFrame':'iron'}");
            info.Services = (Dictionary<string, object>)Json.Parse("{\"frames\":[\"gold\",\"iron\"],\"activeFrame\":\"iron\"}");
            var rows = panel.Rows();
            var outline = rows.First(r => r.Key == "outline");
            check(outline.Options.Count == 3 && outline.Current == "1" && outline.Locked == 1 && outline.Options[0].Text == "Default", "extras: outline row: owned first, one locked, current selected");
            var skin = rows.First(r => r.Key == "spellskin");
            check(skin.Options.Count == 2 && skin.Options[1].Text == "Ember skin" && skin.Line == "ember", "extras: a spell skin of the character's line only");
            check(rows.First(r => r.Key == "frame").Current == "iron" && rows.First(r => r.Key == "frame").Options.Count == 3, "extras: plate frame");
            check(rows.First(r => r.Key == "pet").Options.Count == 2 && rows.First(r => r.Key == "pet").Locked == 1 && rows.First(r => r.Key == "pet").Options[1].Text == "Rex (level 7)", "extras: pet row and what is locked");
            check(OutfitExtrasPanel.Plan(rows, k => -1).Count == 0, "extras: nothing chosen, nothing to do");
            var plan = OutfitExtrasPanel.Plan(rows, k => k == "outline" ? 1 : k == "frame" ? 0 : k == "pet" ? 1 : k == "spellskin" ? 1 : -1);
            check(plan.Count == 3 && plan[0].Act == "cosmetic" && plan[0].Kind == "spellskin" && plan[1].Act == "frame" && plan[1].Value == "" && plan[2].Act == "pet" && plan[2].Value == "wolf", "extras: plan lists only the rows that changed, in order");
            panel.BuildRows();
            panel.Form["x_outline"] = "1"; panel.Form["x_pet"] = "1"; panel.Form["x_frame"] = "0"; panel.Form["x_spellskin"] = "1";
            rig.Sent.Clear();
            Click(panel.BuildRows(), "Apply");
            check(rig.Has("225:{\"action\":\"select\"") && rig.Has("\"kind\":\"spellskin\"") && rig.Has("254:{\"action\":\"summon\",\"data\":{\"species\":\"wolf\"}}") && rig.Has("237:") && rig.Has("plateframe"), "extras: Apply uses the cosmetics, pets and info calls: " + string.Join(" | ", rig.Sent));
            check(panel.Status == "Applied 3 change(s).", "extras: status");
            Click(panel.BuildRows(), "Apply");
            check(panel.Status == "Nothing to change.", "extras: nothing changed");
        }

        // ------------------------------------------------------------------------------------ the session
        static void SessionChecks(Action<bool, string> check)
        {
            var w = new World(DatFile.Parse(Program.SyntheticDat()));
            var st = new StreamerState();
            var s = new GameSession(w, new GameSession.Options { Streamer = st });
            var c = s.Community;
            check(c != null && c.Admin != null && c.BossSpawns != null && c.Survey != null && c.Nemesis != null && c.Referral != null && c.Goal != null && c.Chronicle != null && c.Mentor != null && c.PatchNotes != null &&
                  c.CardBorder != null && c.DropFeed != null && c.Credits != null && c.Streamer == st && c.Perf != null && c.Shots != null && c.OutfitExtras != null, "community: a session holds every panel and shares the app's streamer state");
            check(s.Parser.Talks.Streamer == st, "community: the chat model uses the streamer state");
            foreach (byte op in new byte[] { 120, 217, 122, 163, 220, 203, 171, 194, 244, 172 }) check(s.Ext.Handles(op), "community: opcode " + op + " has a handler");
            string[] sent = { "" };
            s.Ext.Transmit = p => sent[0] = Encoding.UTF8.GetString(p, 4, p.Length - 4);
            s.Ext.Receive(122, ExtOpcodes.ToWire("{\"action\":\"open\",\"data\":{\"s\":20}}"));
            check(c.Survey.Visible, "community: a survey message opens the survey");
            // every top menu entry of this track names a window that exists
            var entries = TopMenu.Categories.SelectMany(cat => cat.Entries).Where(e => e.Target.StartsWith("win:")).Select(e => e.Target.Substring(4)).ToList();
            foreach (var win in new[] { "ReferralWindow", "OutfitExtrasWindow", "NemesisWindow", "BossSpawnsWindow", "CommunityGoalWindow", "ChronicleWindow", "MentorWindow", "PatchNotesWindow", "DropFeedWindow", "CreditsWindow", "StreamerWindow", "PerfWindow", "ShotsWindow" })
                check(entries.Contains(win), "community: the top menu has " + win);
            string src = ReadSrc("Unity/Windows/CommunityWindows.cs");
            if (src != null)
                foreach (var win in entries.Where(e => new[] { "ReferralWindow", "NemesisWindow", "MentorWindow" }.Contains(e)))
                    check(src.Contains("class " + win), "community: " + win + " is a class in CommunityWindows.cs");
        }

        static string ReadSrc(string rel)
        {
            string dir = Path.GetFullPath(Path.Combine("..", "Client", "Assets", "Chaos"));
            if (!Directory.Exists(dir)) dir = Path.GetFullPath(Path.Combine("unity", "Client", "Assets", "Chaos"));
            string path = Path.Combine(dir, rel);
            return File.Exists(path) ? File.ReadAllText(path) : null;
        }

        // ------------------------------------------------------------------------------------ texts
        static void LocChecks(Action<bool, string> check)
        {
            var missing = new List<string>();
            int count = 0;
            foreach (var f in new[] { "Core/Community.cs", "Core/CommunityGoal.cs", "Core/CommunityExtras.cs" })
            {
                string src = ReadSrc(f);
                if (src == null) { check(true, "community loc: sources not found (skipped)"); return; }
                foreach (Match m in Regex.Matches(src, "Loc\\.T\\((?:[^\"\\n)]*\\?\\s*)?\"((?:[^\"\\\\]|\\\\.)*)\"(?:\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\")?"))
                    foreach (int gi in new[] { 1, 2 })
                        if (m.Groups[gi].Success)
                        {
                            count++;
                            string key = m.Groups[gi].Value.Replace("\\\"", "\"").Replace("\\n", "\n").Replace("\\\\", "\\");
                            if (!LocStrings.PtBr.ContainsKey(key)) missing.Add(key);
                        }
            }
            check(missing.Count == 0, "community loc: every Loc.T key of the community Core files has a pt-BR text (" + count + " keys)" + (missing.Count > 0 ? ": " + string.Join(" | ", missing) : ""));
            // texts the windows translate at run time: tabs, event labels, source names, options
            var rig = new Rig();
            var run = new List<string>();
            foreach (var panel in new SocialPanel[] { new CommunityGoalPanel(rig.Ext), new ChroniclePanel(rig.Ext), new MentorPanel(rig.Ext), new PatchNotesPanel(rig.Ext) })
                foreach (var t in panel.Tabs) run.Add(t.Value);
            foreach (var e in ShotsState.Events) run.Add(e.Label);
            foreach (var sc in SurveyPanel.Sources) run.Add(sc.Value);
            foreach (var o in MentorPanel.OnlineOptions) run.Add(o[1]);
            foreach (var sec in ChroniclePanel.MemSections) run.Add(sec[1]);
            run.Add("Any class");
            var lack = run.Where(t => !LocStrings.PtBr.ContainsKey(t)).Distinct().ToList();
            check(lack.Count == 0, "community loc: tab, event, source and option names have a pt-BR text" + (lack.Count > 0 ? ": " + string.Join(" | ", lack) : ""));
            var mine = new[] { "Referral", "Customise Character", "Nemesis", "Boss Spawns", "Community", "Chronicle", "Mentors", "Patch Notes", "Drop Feed", "Credits", "Streamer and cinema mode", "Performance", "Screenshots" };
            var menu = TopMenu.Categories.SelectMany(cat => cat.Entries).Select(e => e.Text).Where(t => mine.Contains(t) && !LocStrings.PtBr.ContainsKey(t)).ToList();
            check(menu.Count == 0, "community loc: every top menu text has a pt-BR text" + (menu.Count > 0 ? ": " + string.Join(" | ", menu) : ""));
            Loc.Set("pt-BR");
            check(Loc.T("Referral") == "Indicação" && Loc.T("Pocket {0}/{1}", 2, 3) == "Bolso 2/3" && Loc.T("Boss Spawns") == "Chefes", "community loc: pt-BR with arguments");
            var p = new NemesisPanel(rig.Ext) { Epoch = () => 100 };
            p.BuildRows();
            check(p.Header1 == "Nenhum Nêmesis caça você", "community loc: a panel in Portuguese");
            Loc.Set("en");
        }
    }
}
