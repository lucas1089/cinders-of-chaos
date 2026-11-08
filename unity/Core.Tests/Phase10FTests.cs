// Phase 10, track F (Core/Phase10F.cs): the window smoke run's pure parts: the step order, the log classification, the rect checks, the contact sheet maths and the json.
using System;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class Phase10FTests
    {
        public static void Run(Action<bool, string> check)
        {
            PlanChecks(check);
            LogChecks(check);
            RectChecks(check);
            SheetChecks(check);
            ReportChecks(check);
        }

        static void PlanChecks(Action<bool, string> check)
        {
            var login = WindowSmokePlan.LoginSteps(new[] { "General", "Sound", "Visuals", "Layout" });
            check(login.Count == 7 && login[0].Name == "screen:login" && login[1].Name == "login:bar" && login[2].Name == "login:options General" && login[5].Index == 3 && login[6].Name == "login:credits",
                "smoke plan: login screen, bar, four option pages, credits");
            var chars = WindowSmokePlan.CharacterSteps();
            check(chars.Count == 2 && chars[0].Name == "screen:characters", "smoke plan: the character list");

            var game = WindowSmokePlan.GameSteps(new[] { "Character", "Hunt", "Windows" }, new[] { 0, 1, 9, -1 }, new[] { "SkillsWindow", "BankWindow", "SkillsWindow", "" },
                new[] { "services", "character", "services" }, new[] { "General", "Sound" });
            var names = game.Select(s => s.Name).ToList();
            check(names.SequenceEqual(new[]
            {
                "menu:Character", "menu:Hunt", "menu:Windows", "more:Character", "more:Hunt",
                "win:SkillsWindow", "win:BankWindow", "info:character", "info:services", "options:General", "options:Sound",
            }), "smoke plan: menus, More menus (valid indexes only), windows in registry order without duplicates, sorted Info pages, options pages: " + string.Join(",", names));
            check(game.First(s => s.Name == "more:Hunt").Index == 1 && game.First(s => s.Name == "options:Sound").Index == 1, "smoke plan: menu and page indexes");
            check(game.Select(s => s.Name).Distinct().Count() == game.Count, "smoke plan: every name once");
            var empty = WindowSmokePlan.GameSteps(new string[0], new int[0], new string[0], new string[0], new string[0]);
            check(empty.Count == 0, "smoke plan: nothing in, nothing out");
        }

        static void LogChecks(Action<bool, string> check)
        {
            check(SmokeLog.Classify(true, false, "NullReferenceException: Object reference not set") == SmokeIssueKind.Exception, "smoke log: an exception");
            check(SmokeLog.Classify(true, false, "ArgumentException: Getting control 2's position in a group with only 2 controls when doing repaint") == SmokeIssueKind.Layout,
                "smoke log: Getting control is a layout error even as an exception");
            check(SmokeLog.Classify(false, true, "GUI Error: Invalid GUILayout state in ChaosApp view") == SmokeIssueKind.Layout, "smoke log: GUI Error is a layout error");
            check(SmokeLog.Classify(false, false, "GUI Error: warning text") == SmokeIssueKind.Layout, "smoke log: GUI Error counts at any log type");
            check(SmokeLog.Classify(false, true, "chaos: bad thing") == SmokeIssueKind.Error, "smoke log: a logged error");
            check(SmokeLog.Classify(false, false, "chaos window smoke: 3 windows") == SmokeIssueKind.None, "smoke log: a plain line is no issue");
            check(SmokeLog.Classify(false, false, null) == SmokeIssueKind.None, "smoke log: null message");
            check(SmokeLog.FirstLine("\r\n  at Chaos.Client.X.Body () [0x00001] in <abc>:0 \n at Y") == "at Chaos.Client.X.Body () [0x00001] in <abc>:0", "smoke log: first non-empty stack line, trimmed");
            check(SmokeLog.FirstLine("") == "" && SmokeLog.FirstLine(null) == "", "smoke log: no stack");
            check(SmokeLog.FirstLine(new string('x', 400)).Length == 300, "smoke log: long line capped");
        }

        static void RectChecks(Action<bool, string> check)
        {
            check(!SmokeRect.OffScreen(10, 10, 300, 200, 1280, 720) && !SmokeRect.Zero(300, 200), "smoke rect: a window inside the screen");
            check(!SmokeRect.OffScreen(0, 0, 1280, 720, 1280, 720), "smoke rect: exactly the screen is on screen");
            check(!SmokeRect.OffScreen(-0.5f, 0, 1280.5f, 720, 1280, 720), "smoke rect: half a pixel of slack");
            check(SmokeRect.OffScreen(1000, 10, 400, 200, 1280, 720), "smoke rect: past the right edge");
            check(SmokeRect.OffScreen(10, 600, 300, 200, 1280, 720), "smoke rect: past the bottom edge");
            check(SmokeRect.OffScreen(-30, 10, 300, 200, 1280, 720), "smoke rect: past the left edge");
            check(SmokeRect.OffScreen(float.NaN, 10, 300, 200, 1280, 720), "smoke rect: NaN is off screen");
            check(SmokeRect.Zero(0, 200) && SmokeRect.Zero(300, 1) && SmokeRect.Zero(float.NaN, 5), "smoke rect: no area");
        }

        static void SheetChecks(Action<bool, string> check)
        {
            check(SmokeSheet.PerSheet == 24, "smoke sheet: 24 tiles per sheet");
            check(SmokeSheet.SheetCount(0) == 0 && SmokeSheet.SheetCount(1) == 1 && SmokeSheet.SheetCount(24) == 1 && SmokeSheet.SheetCount(25) == 2 && SmokeSheet.SheetCount(250) == 11, "smoke sheet: sheet count");
            check(SmokeSheet.SheetOf(23) == 0 && SmokeSheet.SheetOf(24) == 1, "smoke sheet: tile 24 starts sheet 2");
            var a = SmokeSheet.Cell(0, 1280, 720);
            var b = SmokeSheet.Cell(5, 1280, 720);
            var c = SmokeSheet.Cell(6, 1280, 720);
            var d = SmokeSheet.Cell(24 + 23, 1280, 720);
            check(a.X == 0 && a.Y == 0 && Math.Abs(a.W - 1280f / 6) < 1e-3 && a.H == 180, "smoke sheet: first cell");
            check(Math.Abs(b.XMax - 1280) < 1e-3 && b.Y == 0, "smoke sheet: sixth cell ends at the right edge");
            check(c.X == 0 && c.Y == 180, "smoke sheet: seventh cell starts the second row");
            check(Math.Abs(d.XMax - 1280) < 1e-3 && Math.Abs(d.YMax - 720) < 1e-3, "smoke sheet: the last cell of a second sheet ends at the corner");
            var cells = Enumerable.Range(0, 24).Select(i => SmokeSheet.Cell(i, 1280, 720)).ToList();
            bool disjoint = true;
            for (int i = 0; i < cells.Count; i++)
                for (int j = i + 1; j < cells.Count; j++)
                    if (cells[i].X < cells[j].XMax - 1e-3 && cells[j].X < cells[i].XMax - 1e-3 && cells[i].Y < cells[j].YMax - 1e-3 && cells[j].Y < cells[i].YMax - 1e-3) disjoint = false;
            check(disjoint, "smoke sheet: cells never overlap");
            var img = SmokeSheet.Image(a);
            var lab = SmokeSheet.Label(a);
            check(img.Y >= lab.YMax && img.XMax <= a.XMax && img.YMax <= a.YMax && img.W > 100 && img.H > 100, "smoke sheet: image area under the label, inside the cell");

            var f = SmokeSheet.Fit(1280, 720, img);
            check(f.W <= img.W + 1e-3 && f.H <= img.H + 1e-3 && Math.Abs(f.W / f.H - 1280f / 720) < 1e-3, "smoke sheet: a full screenshot fits by aspect");
            check(Math.Abs((f.X + f.W / 2) - (img.X + img.W / 2)) < 1e-3, "smoke sheet: centred");
            var small = SmokeSheet.Fit(100, 50, img);
            check(small.W == 100 && small.H == 50, "smoke sheet: a small crop is not enlarged");
            var tall = SmokeSheet.Fit(300, 900, img);
            check(Math.Abs(tall.H - img.H) < 1e-3 && tall.W < img.W, "smoke sheet: a tall crop is limited by height");
            check(SmokeSheet.Fit(0, 10, img).W == 0, "smoke sheet: an empty source gives an empty fit");

            var crop = SmokeSheet.Crop(100, 50, 400, 300, 8, 1280, 720);
            check(crop.X == 92 && crop.Y == 42 && crop.W == 416 && crop.H == 316, "smoke sheet: crop grows by the margin");
            var edge = SmokeSheet.Crop(-20, 600, 300, 300, 8, 1280, 720);
            check(edge.X == 0 && edge.YMax == 720 && edge.W == 288 && edge.H == 128, "smoke sheet: crop is cut to the screen");
            var none = SmokeSheet.Crop(0, 0, 0, 0, 8, 1280, 720);
            check(none.W == 1280 && none.H == 720, "smoke sheet: a rect with no area keeps the whole screen");
            var gone = SmokeSheet.Crop(5000, 5000, 100, 100, 8, 1280, 720);
            check(gone.W == 1280 && gone.H == 720, "smoke sheet: a rect off the screen keeps the whole screen");
            string longName = "win:AVeryLongWindowNameThatDoesNotFit", cut = SmokeSheet.LabelText(longName, 20);
            check(SmokeSheet.LabelText("win:Short", 30) == "win:Short" && cut.Length == 20 && cut.StartsWith("...") && longName.EndsWith(cut.Substring(3)), "smoke sheet: a long label keeps its end");
            check(SmokeSheet.FileName(0) == "window_smoke_sheet_1.png" && SmokeSheet.FileName(10) == "window_smoke_sheet_11.png", "smoke sheet: file names count from 1");
        }

        static void ReportChecks(Action<bool, string> check)
        {
            var rep = new SmokeReport();
            rep.Log(true, false, "NullReferenceException: before any step", "at A.B () in <x>:0");
            var r1 = rep.Begin("win:SkillsWindow", "win");
            r1.Frames = 4; r1.HasRect = true; r1.Rect = new SmokeBox(10, 20, 300, 200);
            rep.Log(true, false, "NullReferenceException: Object reference not set\nmore", "at Chaos.Client.SkillsWindow.Body () [0x1] in <a>:0\nat X");
            rep.Log(true, false, "NullReferenceException: Object reference not set\nmore", "at Chaos.Client.SkillsWindow.Body () [0x1] in <a>:0\nat Y");
            rep.Log(false, false, "GUI Error: Invalid GUILayout state", "");
            rep.Log(false, false, "just a line", "");
            rep.End();
            var r2 = rep.Begin("win:BankWindow", "win");
            r2.Frames = 4; r2.HasRect = true; r2.Rect = new SmokeBox(900, 10, 600, 200); r2.OffScreen = SmokeRect.OffScreen(900, 10, 600, 200, 1280, 720);
            rep.End();
            var r3 = rep.Begin("win:ChannelsWindow", "win");
            r3.Frames = 4; r3.HasRect = true; r3.Rect = new SmokeBox(10, 10, 200, 100);
            rep.End();
            var r4 = rep.Begin("menu:Hunt", "menu");
            r4.Frames = 4; r4.OpenAtEnd = false;
            rep.End();
            check(rep.Records.Count == 4, "smoke report: one record per step");
            check(r1.Issues.Count == 2 && r1.Count(SmokeIssueKind.Exception) == 2 && r1.Count(SmokeIssueKind.Layout) == 1, "smoke report: the same exception twice is one issue with a count of 2");
            check(r1.Issues[0].Message == "NullReferenceException: Object reference not set" && r1.Issues[0].Stack.StartsWith("at Chaos.Client.SkillsWindow.Body"), "smoke report: message and first stack line");
            check(rep.BackgroundRecord.Issues.Count == 1, "smoke report: a line between steps goes to the background");
            check(r1.Problem && r2.Problem && !r3.Problem && !r4.Problem, "smoke report: problem flags");
            check(rep.WithProblems == 2 && rep.OffScreenCount == 1, "smoke report: counts");
            check(rep.SummaryLine() == "chaos window smoke: 4 windows, 2 with errors", "smoke report: summary line: " + rep.SummaryLine());
            check(rep.DetailLine() == "chaos window smoke: 2 exceptions, 1 layout errors, 0 logged errors, 1 off screen or empty, 1 in the background, 0 context only, 0 oversize, 0 thin or empty body", "smoke report: detail line: " + rep.DetailLine());

            string json = rep.ToJson(1280, 720);
            var root = Json.TryParse(json) as Dictionary<string, object>;
            check(root != null, "smoke json: parses");
            if (root == null) return;
            var wins = root["windows"] as List<object>;
            var sum = root["summary"] as Dictionary<string, object>;
            check(wins != null && wins.Count == 4 && (double)sum["windows"] == 4 && (double)sum["withErrors"] == 2 && (double)sum["exceptions"] == 2 && (double)sum["layoutErrors"] == 1 && (double)sum["offScreen"] == 1,
                "smoke json: summary numbers");
            var w0 = wins[0] as Dictionary<string, object>;
            var ex = w0["exceptions"] as List<object>;
            var e0 = ex[0] as Dictionary<string, object>;
            check((string)w0["name"] == "win:SkillsWindow" && (double)w0["frames"] == 4 && ex.Count == 2 && (string)e0["kind"] == "exception" && (double)e0["count"] == 2
                && ((string)e0["stack"]).StartsWith("at Chaos.Client.SkillsWindow.Body"), "smoke json: window, frames, exception with the first stack line");
            var rect = w0["rect"] as List<object>;
            check(rect != null && rect.Count == 4 && (double)rect[2] == 300, "smoke json: rect");
            var w1 = wins[1] as Dictionary<string, object>;
            check((bool)w1["offScreen"] && !(bool)w1["zeroSize"], "smoke json: off screen flag");
            var w3 = wins[3] as Dictionary<string, object>;
            check(!(bool)w3["openAtEnd"] && !w3.ContainsKey("rect") && (w3["exceptions"] as List<object>).Count == 0, "smoke json: a step without a rect, closed at the end, no exceptions");
            check((root["background"] as List<object>).Count == 1, "smoke json: background issues");

            var tricky = new SmokeReport();
            tricky.Begin("win:Q", "win");
            tricky.Log(true, false, "Boom \"quoted\" \\ back\ttab é中", "at \"a\"");
            tricky.End();
            var jt = Json.TryParse(tricky.ToJson(1280, 720)) as Dictionary<string, object>;
            string msg = jt == null ? null : (string)((((jt["windows"] as List<object>)[0] as Dictionary<string, object>)["exceptions"] as List<object>)[0] as Dictionary<string, object>)["message"];
            check(msg == "Boom \"quoted\" \\ back\ttab é中", "smoke json: quotes, backslash, tab and non-ASCII round trip");
            check(tricky.ToJson(1280, 720).All(ch => ch < 0x7f), "smoke json: ASCII only");
            check(new SmokeReport().ToJson(1280, 720).Contains("\"windows\":[\n ]") && Json.TryParse(new SmokeReport().ToJson(1280, 720)) != null, "smoke json: an empty report is valid json");

            string sample = Environment.GetEnvironmentVariable("CHAOS_SMOKE_SAMPLE");
            if (!string.IsNullOrEmpty(sample)) System.IO.File.WriteAllText(sample, json);
        }
    }
}
