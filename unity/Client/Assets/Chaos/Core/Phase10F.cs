// Phase 10, track F: the window smoke run (unity/README.md "Window smoke run"). Pure C#, no Unity types. The player (Unity/ChaosApp.Smoke.cs) opens every window one at
// a time and asks this file: in what order (WindowSmokePlan), what a log line means (SmokeLog), whether a rect is on the screen (SmokeRect), where a screenshot goes on
// the contact sheet (SmokeSheet) and how the report reads as json (SmokeReport.ToJson).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    /// <summary>One thing the smoke run opens: a screen, a login bar page, a menu drop-down, a window class, an Info page, an options page.</summary>
    public sealed class SmokeStep
    {
        public string Kind = "", Id = "";
        /// <summary>The menu button index (menu and more steps), the page number (options steps).</summary>
        public int Index;
        public string Name => Kind + ":" + Id;
    }

    /// <summary>The order of the run. Login screen first (no session), then the character list, then the game: menus, windows in the registry's order, Info pages, options pages.</summary>
    public static class WindowSmokePlan
    {
        public const string Screen = "screen", Login = "login", Menu = "menu", More = "more", Window = "win", Info = "info", Options = "options";

        static SmokeStep S(string kind, string id, int index = 0) => new SmokeStep { Kind = kind, Id = id, Index = index };

        /// <summary>The login screen, its System drop-down, the pages of its options window and the credits.</summary>
        public static List<SmokeStep> LoginSteps(IList<string> optionPages)
        {
            var o = new List<SmokeStep> { S(Screen, "login"), S(Login, "bar") };
            for (int i = 0; i < optionPages.Count; i++) o.Add(S(Login, "options " + optionPages[i], i));
            o.Add(S(Login, "credits"));
            return o;
        }

        /// <summary>The character list and its bar.</summary>
        public static List<SmokeStep> CharacterSteps() => new List<SmokeStep> { S(Screen, "characters"), S(Login, "characters bar") };

        /// <summary>The game steps. menus: the button texts in button order; moreMenus: the button indexes that have a More sub-menu; windows: the class names in registry order;
        /// infoPages: the Info page ids (sorted here, duplicates dropped); optionPages: the options window's pages. A name seen twice is kept once.</summary>
        public static List<SmokeStep> GameSteps(IList<string> menus, IList<int> moreMenus, IList<string> windows, IEnumerable<string> infoPages, IList<string> optionPages)
        {
            var o = new List<SmokeStep>();
            var seen = new HashSet<string>(StringComparer.Ordinal);
            void Add(SmokeStep s) { if (seen.Add(s.Name)) o.Add(s); }
            for (int i = 0; i < menus.Count; i++) Add(S(Menu, menus[i], i));
            foreach (int i in moreMenus) if (i >= 0 && i < menus.Count) Add(S(More, menus[i], i));
            foreach (var w in windows) if (!string.IsNullOrEmpty(w)) Add(S(Window, w));
            var pages = new List<string>();
            foreach (var p in infoPages) if (!string.IsNullOrEmpty(p) && !pages.Contains(p)) pages.Add(p);
            pages.Sort(StringComparer.Ordinal);
            foreach (var p in pages) Add(S(Info, p));
            for (int i = 0; i < optionPages.Count; i++) Add(S(Options, optionPages[i], i));
            return o;
        }
    }

    public enum SmokeIssueKind { None, Exception, Layout, Error }

    /// <summary>What a Unity log line means for the run.</summary>
    public static class SmokeLog
    {
        static readonly string[] LayoutMarks = { "GUI Error", "Getting control", "GUILayout: Mismatched", "pushing more GUIClips", "EndLayoutGroup", "Unbalanced" };

        /// <summary>isException: the line is an exception (LogType.Exception); isError: LogType.Error or Assert. Warnings and plain logs are not issues unless they are an IMGUI layout error.</summary>
        public static SmokeIssueKind Classify(bool isException, bool isError, string message)
        {
            message = message ?? "";
            foreach (var m in LayoutMarks) if (message.IndexOf(m, StringComparison.Ordinal) >= 0) return SmokeIssueKind.Layout;
            if (isException) return SmokeIssueKind.Exception;
            if (isError) return SmokeIssueKind.Error;
            return SmokeIssueKind.None;
        }

        /// <summary>The first non-empty line of a stack trace, trimmed; "" when there is none.</summary>
        public static string FirstLine(string text)
        {
            if (string.IsNullOrEmpty(text)) return "";
            foreach (var line in text.Replace("\r", "").Split('\n'))
            {
                string t = line.Trim();
                if (t.Length > 0) return Cap(t, 300);
            }
            return "";
        }

        public static string Cap(string s, int max) => s == null ? "" : s.Length <= max ? s : s.Substring(0, max - 3) + "...";
    }

    /// <summary>Whether a window's rect (UI units) sits on the screen (UI units).</summary>
    public static class SmokeRect
    {
        public const float Slack = 1f, MinSide = 2f;

        public static bool Zero(float w, float h) => float.IsNaN(w) || float.IsNaN(h) || w < MinSide || h < MinSide;

        /// <summary>Phase 12, track H: a side larger than the screen (after the window's first frames). Such a window cannot show its frame whole, however it is moved.</summary>
        public static bool Oversize(float w, float h, float screenW, float screenH)
        {
            if (float.IsNaN(w) || float.IsNaN(h)) return false;
            return w > screenW + Slack || h > screenH + Slack;
        }

        /// <summary>True when any edge is outside the screen by more than the slack, or the rect has NaN in it.</summary>
        public static bool OffScreen(float x, float y, float w, float h, float screenW, float screenH)
        {
            if (float.IsNaN(x) || float.IsNaN(y) || float.IsNaN(w) || float.IsNaN(h)) return true;
            return x < -Slack || y < -Slack || x + w > screenW + Slack || y + h > screenH + Slack;
        }
    }

    public struct SmokeBox
    {
        public float X, Y, W, H;
        public SmokeBox(float x, float y, float w, float h) { X = x; Y = y; W = w; H = h; }
        public float XMax => X + W;
        public float YMax => Y + H;
    }

    /// <summary>The contact sheets: a grid of cells, each a screenshot crop under a label strip.</summary>
    public static class SmokeSheet
    {
        public const int Cols = 6, Rows = 4, PerSheet = Cols * Rows, LabelH = 16, Pad = 4;

        public static int SheetCount(int tiles) => tiles <= 0 ? 0 : (tiles + PerSheet - 1) / PerSheet;
        public static int SheetOf(int tile) => tile / PerSheet;

        /// <summary>The cell of a tile on its sheet (the border box, label strip inside it).</summary>
        public static SmokeBox Cell(int tile, float sheetW, float sheetH)
        {
            int k = tile % PerSheet;
            float cw = sheetW / Cols, ch = sheetH / Rows;
            return new SmokeBox((k % Cols) * cw, (k / Cols) * ch, cw, ch);
        }

        /// <summary>The label strip at the top of a cell.</summary>
        public static SmokeBox Label(SmokeBox cell) => new SmokeBox(cell.X + Pad, cell.Y + 1, cell.W - 2 * Pad, LabelH);

        /// <summary>The area under the label where the screenshot goes.</summary>
        public static SmokeBox Image(SmokeBox cell) => new SmokeBox(cell.X + Pad, cell.Y + LabelH + 2, cell.W - 2 * Pad, cell.H - LabelH - 2 - Pad);

        /// <summary>The largest rect of the source's aspect that fits in the area, centred. Never grows a picture past its own size.</summary>
        public static SmokeBox Fit(float srcW, float srcH, SmokeBox area)
        {
            if (srcW <= 0 || srcH <= 0 || area.W <= 0 || area.H <= 0) return new SmokeBox(area.X, area.Y, 0, 0);
            float s = Math.Min(Math.Min(area.W / srcW, area.H / srcH), 1f);
            float w = srcW * s, h = srcH * s;
            return new SmokeBox(area.X + (area.W - w) / 2f, area.Y + (area.H - h) / 2f, w, h);
        }

        /// <summary>The part of the screenshot to keep for a window: its rect grown by the margin and cut to the screen (all in pixels). A rect with no area gives the whole screen.</summary>
        public static SmokeBox Crop(float x, float y, float w, float h, float margin, float screenW, float screenH)
        {
            if (float.IsNaN(x + y + w + h) || w < 1 || h < 1) return new SmokeBox(0, 0, screenW, screenH);
            float x0 = Math.Max(0, x - margin), y0 = Math.Max(0, y - margin), x1 = Math.Min(screenW, x + w + margin), y1 = Math.Min(screenH, y + h + margin);
            if (x1 - x0 < 1 || y1 - y0 < 1) return new SmokeBox(0, 0, screenW, screenH);
            return new SmokeBox(x0, y0, x1 - x0, y1 - y0);
        }

        /// <summary>The label text cut to fit about maxChars characters: a long name keeps its end ("...Window").</summary>
        public static string LabelText(string name, int maxChars)
        {
            name = name ?? "";
            if (maxChars < 4 || name.Length <= maxChars) return name;
            return "..." + name.Substring(name.Length - (maxChars - 3));
        }

        public static string FileName(int sheet) => "window_smoke_sheet_" + (sheet + 1).ToString(CultureInfo.InvariantCulture) + ".png";
    }

    public sealed class SmokeIssue
    {
        public SmokeIssueKind Kind;
        public string Message = "", Stack = "";
        public int Count = 1;
    }

    public sealed class SmokeRecord
    {
        public string Name = "", Kind = "";
        public int Frames;
        public bool OffScreen, ZeroSize, HasRect, OpenAtEnd = true;
        /// <summary>Phase 12, track H: a side larger than the screen; a body too thin for a line (Thin); a body with no ink under the title bar (EmptyBody; Ink is the share measured, -1 when not measured).</summary>
        public bool Oversize, Thin, EmptyBody;
        public float Ink = -1f;
        /// <summary>Phase 13, track G: other open windows drawn after this one hide at least SmokeCover.Limit of its rect (CoverShare is the part hidden, -1 when not measured). A report only: it is not a Problem.</summary>
        public bool Covered;
        public float CoverShare = -1f;
        public SmokeBox Rect;
        /// <summary>Phase 11, track G: why a context HUD could not be shown (no server push drives it). Not an error: the step is classified "context".</summary>
        public string Context = "";
        public readonly List<SmokeIssue> Issues = new List<SmokeIssue>();

        public int Count(SmokeIssueKind k) { int n = 0; foreach (var i in Issues) if (i.Kind == k) n += i.Count; return n; }
        /// <summary>Any exception, layout error, logged error, zero size or off-screen rect.</summary>
        public bool Problem => Issues.Count > 0 || OffScreen || ZeroSize || Oversize || Thin || EmptyBody;
    }

    /// <summary>The run's record: one SmokeRecord per step in order, log lines go to the open step (or the background record between steps).</summary>
    public sealed class SmokeReport
    {
        public const string BackgroundName = "(background)";
        readonly List<SmokeRecord> records = new List<SmokeRecord>();
        readonly SmokeRecord background = new SmokeRecord { Name = BackgroundName, Kind = "background" };
        readonly object gate = new object();
        SmokeRecord open;

        public IList<SmokeRecord> Records => records;
        public SmokeRecord BackgroundRecord => background;

        public SmokeRecord Begin(string name, string kind)
        {
            lock (gate) { open = new SmokeRecord { Name = name, Kind = kind }; records.Add(open); return open; }
        }

        public void End() { lock (gate) open = null; }

        /// <summary>A log line of Unity. The same message and first stack line twice in one step are one issue with a count.</summary>
        public void Log(bool isException, bool isError, string message, string stack)
        {
            var kind = SmokeLog.Classify(isException, isError, message);
            if (kind == SmokeIssueKind.None) return;
            lock (gate) AddIssue(open ?? background, kind, message, stack);
        }

        public static void AddIssue(SmokeRecord r, SmokeIssueKind kind, string message, string stack)
        {
            string first = SmokeLog.FirstLine(message), top = SmokeLog.FirstLine(stack);
            foreach (var i in r.Issues)
                if (i.Kind == kind && i.Message == first && i.Stack == top) { i.Count++; return; }
            r.Issues.Add(new SmokeIssue { Kind = kind, Message = first, Stack = top });
        }

        public int WithProblems { get { int n = 0; foreach (var r in records) if (r.Problem) n++; return n; } }
        public int Total(SmokeIssueKind k) { int n = 0; foreach (var r in records) n += r.Count(k); return n; }
        /// <summary>Steps classified "context" (a HUD that no server push opens), not counted as problems.</summary>
        public int ContextCount { get { int n = 0; foreach (var r in records) if (r.Context.Length > 0) n++; return n; } }
        public int OffScreenCount { get { int n = 0; foreach (var r in records) if (r.OffScreen || r.ZeroSize) n++; return n; } }
        public int OversizeCount { get { int n = 0; foreach (var r in records) if (r.Oversize) n++; return n; } }
        /// <summary>Windows whose body is too thin or has no ink.</summary>
        public int EmptyCount { get { int n = 0; foreach (var r in records) if (r.Thin || r.EmptyBody) n++; return n; } }
        /// <summary>Phase 13, track G: windows mostly hidden by a window drawn after them (reported, not counted as problems).</summary>
        public int CoveredCount { get { int n = 0; foreach (var r in records) if (r.Covered) n++; return n; } }

        /// <summary>The line the CI step greps for.</summary>
        public string SummaryLine() => "chaos window smoke: " + records.Count + " windows, " + WithProblems + " with errors";

        /// <summary>The detail line under it.</summary>
        public string DetailLine() => "chaos window smoke: " + Total(SmokeIssueKind.Exception) + " exceptions, " + Total(SmokeIssueKind.Layout) + " layout errors, "
            + Total(SmokeIssueKind.Error) + " logged errors, " + OffScreenCount + " off screen or empty, " + background.Issues.Count + " in the background, " + ContextCount + " context only, " + OversizeCount + " oversize, " + EmptyCount + " thin or empty body";

        // ------------------------------------------------------------------------------------ json
        static string Q(string s)
        {
            var b = new StringBuilder("\"");
            foreach (char c in s ?? "")
            {
                switch (c)
                {
                    case '"': b.Append("\\\""); break;
                    case '\\': b.Append("\\\\"); break;
                    case '\n': b.Append("\\n"); break;
                    case '\r': b.Append("\\r"); break;
                    case '\t': b.Append("\\t"); break;
                    default:
                        if (c < 0x20 || c > 0x7e) b.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture)); else b.Append(c);
                        break;
                }
            }
            return b.Append('"').ToString();
        }

        static string N(float f) => float.IsNaN(f) || float.IsInfinity(f) ? "null" : Math.Round(f, 1).ToString("0.#", CultureInfo.InvariantCulture);

        static string KindName(SmokeIssueKind k) => k == SmokeIssueKind.Exception ? "exception" : k == SmokeIssueKind.Layout ? "layout" : "error";

        static void WriteIssues(StringBuilder b, SmokeRecord r, string indent)
        {
            b.Append('[');
            for (int i = 0; i < r.Issues.Count; i++)
            {
                var x = r.Issues[i];
                b.Append(i == 0 ? "" : ",").Append('\n').Append(indent).Append("  {\"kind\":").Append(Q(KindName(x.Kind))).Append(",\"message\":").Append(Q(x.Message))
                 .Append(",\"stack\":").Append(Q(x.Stack)).Append(",\"count\":").Append(x.Count).Append('}');
            }
            if (r.Issues.Count > 0) b.Append('\n').Append(indent);
            b.Append(']');
        }

        /// <summary>window_smoke.json. ASCII only, stable order, the screen size in UI units for the rect numbers.</summary>
        public string ToJson(float screenW, float screenH)
        {
            var b = new StringBuilder();
            b.Append("{\n \"screen\":[").Append(N(screenW)).Append(',').Append(N(screenH)).Append("],\n \"summary\":{\"windows\":").Append(records.Count)
             .Append(",\"withErrors\":").Append(WithProblems)
             .Append(",\"exceptions\":").Append(Total(SmokeIssueKind.Exception))
             .Append(",\"layoutErrors\":").Append(Total(SmokeIssueKind.Layout))
             .Append(",\"loggedErrors\":").Append(Total(SmokeIssueKind.Error))
             .Append(",\"offScreen\":").Append(OffScreenCount).Append(",\"oversize\":").Append(OversizeCount).Append(",\"emptyBody\":").Append(EmptyCount)
             .Append(",\"context\":").Append(ContextCount).Append(",\"covered\":").Append(CoveredCount).Append("},\n \"windows\":[");
            for (int i = 0; i < records.Count; i++)
            {
                var r = records[i];
                b.Append(i == 0 ? "" : ",").Append("\n  {\"name\":").Append(Q(r.Name)).Append(",\"kind\":").Append(Q(r.Kind)).Append(",\"frames\":").Append(r.Frames)
                 .Append(",\"offScreen\":").Append(r.OffScreen ? "true" : "false").Append(",\"zeroSize\":").Append(r.ZeroSize ? "true" : "false")
                 .Append(",\"openAtEnd\":").Append(r.OpenAtEnd ? "true" : "false")
                 .Append(",\"oversize\":").Append(r.Oversize ? "true" : "false").Append(",\"thin\":").Append(r.Thin ? "true" : "false").Append(",\"emptyBody\":").Append(r.EmptyBody ? "true" : "false").Append(",\"covered\":").Append(r.Covered ? "true" : "false");
                if (r.CoverShare >= 0f) b.Append(",\"coverShare\":").Append(Math.Round(r.CoverShare, 2).ToString("0.##", CultureInfo.InvariantCulture));
                if (r.Ink >= 0f) b.Append(",\"ink\":").Append(Math.Round(r.Ink, 3).ToString("0.###", CultureInfo.InvariantCulture));
                if (r.Context.Length > 0) b.Append(",\"context\":").Append(Q(r.Context));
                if (r.HasRect) b.Append(",\"rect\":[").Append(N(r.Rect.X)).Append(',').Append(N(r.Rect.Y)).Append(',').Append(N(r.Rect.W)).Append(',').Append(N(r.Rect.H)).Append(']');
                b.Append(",\"exceptions\":");
                WriteIssues(b, r, "  ");
                b.Append('}');
            }
            b.Append("\n ],\n \"background\":");
            WriteIssues(b, background, " ");
            b.Append("\n}\n");
            return b.ToString();
        }
    }
}
