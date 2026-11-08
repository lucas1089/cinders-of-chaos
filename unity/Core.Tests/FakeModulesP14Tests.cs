// Phase 14, track H (Core/FakeModulesP14.cs): the replies for the windows the smoke run still found empty: Mentor (194), Survey (122, a server push), the Drop feed (a text line)
// and the Battleground scoreboard of a running match. Every sample message is fed to a real GameSession (the Unity parsers) and the window's own rows come out. The keys of every
// sample against the cited server file are checked by FakeModulesTests (the catalog and the contexts hold these messages).
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class FakeModulesP14Tests
    {
        public static void Run(Action<bool, string> check)
        {
            Mentor(check);
            Survey(check);
            DropFeed(check);
            Board(check);
        }

        static GameSession NewSession() => new GameSession(new World(DatFile.Parse(Program.SyntheticDat())), new GameSession.Options());

        static object Request(string action, string data = null)
        {
            var root = new Dictionary<string, object> { { "action", action } };
            root["data"] = data == null ? new Dictionary<string, object>() : Json.Parse(data.Replace('\'', '"'));
            return root;
        }

        static List<FakeMsg> Ask(GameSession s, byte op, string action, string data = null)
        {
            var answers = FakeModules.Answer(op, Request(action, data));
            foreach (var m in answers) Feed(s, m);
            return answers;
        }

        static void Feed(GameSession s, FakeMsg m)
        {
            foreach (var part in ExtChunks.Split(ExtOpcodes.ToWire(Json.Serialize(m.Root)))) s.Ext.Receive(m.Op, part);
        }

        static string RepoRoot()
        {
            for (var d = new DirectoryInfo(Directory.GetCurrentDirectory()); d != null; d = d.Parent)
                if (File.Exists(Path.Combine(d.FullName, "server/data/scripts/chaos/chaos_constants.lua"))) return d.FullName;
            return null;
        }

        static bool HasText(SocialPanel p, string part) => p.BuildRows().Any(r => (r.Text ?? "").Contains(part) || (r.Right ?? "").Contains(part) || (r.Sub ?? "").Contains(part));

        // ------------------------------------------------------------------------------------ 194 mentor
        static void Mentor(Action<bool, string> check)
        {
            var mod = FakeModules.Catalog.FirstOrDefault(m => m.Name == "mentor");
            check(mod != null && mod.Op == MentorPanel.Opcode && mod.Op == 194 && mod.Windows[0] == "MentorWindow" && mod.Requests.Length == 3, "fake p14: Mentor is in the catalog with opcode 194");
            string root = RepoRoot();
            if (root != null)
            {
                string consts = File.ReadAllText(Path.Combine(root, "server/data/scripts/chaos/chaos_constants.lua"));
                var m = Regex.Match(consts, @"(?:\bmentor\s*=\s*|ChaosOpcodes\.mentor\s*=\s*)(\d+)");
                check(m.Success && byte.Parse(m.Groups[1].Value) == MentorPanel.Opcode, "fake p14: opcode of mentor is the server's " + (m.Success ? m.Groups[1].Value : "?"));
            }
            var s = NewSession();
            var a = Ask(s, MentorPanel.Opcode, "open");
            var mp = s.Community.Mentor;
            check(a.Count == 1 && a[0].Action == "status" && mp.StatusData != null && mp.Visible && mp.Tab == "mentoring", "fake p14: Mentor: open gives the status, opens the window on the Mentoring tab (a registered mentor)");
            var rows = mp.BuildRows();
            check(rows.Count >= 12 && HasText(mp, "Kit") && HasText(mp, "Lyra") && HasText(mp, "Marks 35") && MentorPanel.MentorStats(mp.StatusData).Contains("Graduates 4"), "fake p14: Mentor: apprentices, stats and the card form draw " + rows.Count + " rows");
            check(MentorPanel.ShopRows(mp.StatusData).Count == 3 && MentorPanel.ShopRows(mp.StatusData)[0].Buyable && !MentorPanel.ShopRows(mp.StatusData)[2].Buyable && MentorPanel.ShopRows(mp.StatusData)[2].Button == "Owned",
                "fake p14: Mentor: 3 shop rows, the title buyable with 35 marks, the owned frame not");
            mp.SelectTab("shop");
            check(mp.BuildRows().Count >= 4 && HasText(mp, "Mentor Supplies"), "fake p14: Mentor: the shop tab lists the offers");
            mp.SelectTab("top");
            check(mp.BuildRows().Count >= 2 && HasText(mp, "Mira"), "fake p14: Mentor: the top tab lists the graduates");
            mp.SelectTab("find");
            var l = Ask(s, MentorPanel.Opcode, "list");
            check(l.Count == 1 && mp.MentorRows != null && mp.MentorRows.Count == 2 && HasText(mp, "Mira") && HasText(mp, "Vex"), "fake p14: Mentor: the list answer fills the find tab");
            check(MentorPanel.InviteRows(mp.StatusData).Count == 1 && MentorPanel.LineOptions(mp.StatusData).Count == 5, "fake p14: Mentor: 1 invite and the class lines");
            var sync = Ask(NewSession(), MentorPanel.Opcode, "sync");
            check(sync.Count == 1 && !Json.Truthy(Json.Get(sync[0].Root, "data"), "open"), "fake p14: Mentor: sync sends the status with open false (the window stays shut)");
            var s2 = NewSession();
            Ask(s2, MentorPanel.Opcode, "sync");
            check(s2.Community.Mentor.StatusData != null && !s2.Community.Mentor.Visible, "fake p14: Mentor: a sync status fills the state without opening the window");
        }

        // ------------------------------------------------------------------------------------ 122 survey
        static void Survey(Action<bool, string> check)
        {
            var ctx = FakeModules.Context("SurveyWindow");
            check(ctx != null && ctx.Drivable && ctx.Pushes.Count == 1 && ctx.Close.Count == 1 && ctx.Pushes[0].Op == SurveyPanel.Opcode && ctx.Pushes[0].Action == "open" && ctx.Close[0].Action == "done", "fake p14: Survey: a context with the open push and the done message");
            var s = NewSession();
            var sv = s.Community.Survey;
            check(!sv.Visible && sv.Stage == 0, "fake p14: Survey: shut before the server opens it");
            Feed(s, ctx.Pushes[0]);
            var rows = sv.BuildRows();
            check(sv.Visible && sv.Stage == 20 && sv.Max == 200 && rows.Count >= 6 && HasText(sv, "Where did you hear") && HasText(sv, "What confused you"), "fake p14: Survey: the push opens stage 20 with the source question, the text, fun, recommend and the buttons: " + rows.Count + " rows");
            Feed(s, FakeModules.SurveyOpen(50));
            check(sv.Stage == 50 && !HasText(sv, "Where did you hear"), "fake p14: Survey: stage 50 has no source question");
            Feed(s, ctx.Close[0]);
            check(!sv.Visible && sv.Stage == 0, "fake p14: Survey: done closes it");
            // the server only opens a stage the client knows: s = 35 is ignored
            Feed(s, FakeModules.SurveyOpen(35));
            check(!sv.Visible, "fake p14: Survey: an unknown stage is ignored");
            // survey.lua sends max as a number and s as a number; as text they read too
            var s2 = NewSession();
            foreach (var part in ExtChunks.Split(ExtOpcodes.ToWire("{\"action\":\"open\",\"data\":{\"s\":\"20\",\"max\":\"120\"}}"))) s2.Ext.Receive(SurveyPanel.Opcode, part);
            check(s2.Community.Survey.Visible && s2.Community.Survey.Stage == 20 && s2.Community.Survey.Max == 120, "fake p14: Survey: s and max as text read as numbers");
        }

        // ------------------------------------------------------------------------------------ the drop feed
        static void DropFeed(Action<bool, string> check)
        {
            string line = FakeModules.DropFeedLine();
            string root = RepoRoot();
            if (root != null)
            {
                string cfg = File.ReadAllText(Path.Combine(root, "server/data/scripts/chaos/retention_loot_config.lua"));
                var m = Regex.Match(cfg, "text\\s*=\\s*\"([^\"]*\\%s[^\"]*)\"");
                check(m.Success && m.Groups[1].Value == "%s (Lv %d) found %s!", "fake p14: Drop feed: the server's line pattern is " + (m.Success ? m.Groups[1].Value : "?"));
                var t = Regex.Match(cfg, @"fallbackType\s*=\s*(\d+)");
                check(t.Success && byte.Parse(t.Groups[1].Value) == FakeModules.DropFeedTextType, "fake p14: Drop feed: the message type is the server's fallbackType");
                var ch = Regex.Match(cfg, @"channelId\s*=\s*(\d+)");
                check(ch.Success, "fake p14: Drop feed: the server's channel id is " + (ch.Success ? ch.Groups[1].Value : "?"));
            }
            var links = ChatLinksMath.Parse(line);
            check(links.Count == 1 && links[0].Name == "Emberfang" && links[0].Unique && ChatLinksMath.ValidId(links[0].Id) && ChatLinksMath.Plain(line) == "Vex (Lv 310) found [Emberfang]!", "fake p14: Drop feed: the link parses and reads as [Emberfang] in the chat: " + ChatLinksMath.Plain(line));
            check(FakeModules.DropFeedLine("Mira", 12, false).StartsWith("Mira (Lv 12) found [Emberfang]{5") && ChatLinksMath.Parse(FakeModules.DropFeedLine("Mira", 12, false))[0].Rarity == 5, "fake p14: Drop feed: a legendary link has the rarity digit 5");
            // the client gets it as a text message of the server's type: it lands in the Server Log tab with the link kept
            var p = new GameParser(new World(DatFile.Parse(Program.SyntheticDat())));
            p.Parse(new ByteWriter().U8(0xB4).U8(FakeModules.DropFeedTextType).Str(line).ToArray());
            var log = p.Talks.LogTab.Lines;
            check(log.Count == 1 && log[0].Text == line && ChatLinksMath.Parse(log[0].Text).Count == 1, "fake p14: Drop feed: the line reaches the Server Log tab with its link");
            // the option the window sends (feedopt on opcode 229) has no reply: the server only filters
            check(FakeModules.Answer(DropFeedPanel.Opcode, Request("feedopt", "{'mode':'unique'}")).Count == 0, "fake p14: Drop feed: feedopt gets no module message (the server sets the option and posts text lines)");
            var s = NewSession();
            var df = s.Community.DropFeed;
            check(df.BuildRows().Count == 1 && DropFeedPanel.Packet("unique").ContainsKey("mode"), "fake p14: Drop feed: the window is one choice of three modes");
        }

        // ------------------------------------------------------------------------------------ the Battleground scoreboard of a running match
        static void Board(Action<bool, string> check)
        {
            var ctx = FakeModules.Context("BattlegroundBoardWindow");
            check(ctx != null && ctx.Drivable && ctx.Pushes.Count == 3 && ctx.Pushes[0].Action == "state" && ctx.Pushes[1].Action == "hud" && ctx.Pushes[2].Action == "board", "fake p14: Battleground board: a match context of state, hud and board");
            var s = NewSession();
            var b = s.Endgame.Battleground;
            check(!b.InMatch && b.BoardData == null, "fake p14: Battleground board: no match before the push");
            foreach (var m in ctx.Pushes) Feed(s, m);
            check(b.InMatch && b.MyTeam == 1 && b.Hud != null && b.Board != null && b.Summary == null && !b.Visible, "fake p14: Battleground board: in a match, hud and board known, no summary, the queue window shut");
            var sides = BgView.BoardSides(Json.Get(b.BoardData, "rows"), 1);
            check(sides[0].Count == 2 && sides[1].Count == 2 && sides[0][0].Name == "Ember" && sides[0][0].Kills == 12 && sides[1].Any(r => r.Left), "fake p14: Battleground board: two rows per team, the player who left is marked");
            // the window asks `board` when it opens, and the responder answers it
            var asked = Ask(NewSession(), BattlegroundState.Opcode, "board");
            check(asked.Count == 1 && asked[0].Action == "board" && Json.List(asked[0].Root is Dictionary<string, object> r ? r["data"] : null, "rows").Count == 4, "fake p14: Battleground board: the board request is answered with 4 rows");
            b.ToggleBoard();
            check(b.BoardVisible, "fake p14: Battleground board: ToggleBoard opens the scoreboard on the live data");
            // the end summary is the other view of the window
            Feed(s, FakeModules.BgEnd());
            var sm = BgView.Summary(b.Summary, b.MyTeam);
            check(b.Summary != null && b.BoardVisible && b.BoardData == b.Summary && sm.Title.Length > 0 && sm.Score.Length > 0, "fake p14: Battleground board: the end message gives the summary view: " + sm.Title + " " + sm.Score);
            s.Endgame.Clear();
            check(!b.InMatch && b.BoardData == null && !b.BoardVisible, "fake p14: Battleground board: the clear after the step leaves no match");
        }
    }
}
