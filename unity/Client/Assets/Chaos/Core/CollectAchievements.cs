// Achievements (client game_achievements, extended opcode 250, server achievements.lua). Both ways {"action":..., "data":...}.
//   client -> server  open | get | title {title: "auto" | "none" | text}
//   server -> client  state {points, accountPoints, unlocked, total, maxPoints, categories [{key, name, done, total, points, max}], recent [{name, points}],
//                     titlesOn, titles | heldTitles [{text}], activeTitle, open}
//                     list {first, last, rows [{n, p, d, c, t, v, u, h, ti, r}]}   (rows come in parts, shown when the last arrived)
//                     track {ap, steps [{n, d, k, p, c?, a?, o?, ti?}], cats [{key, cn, n, d, k, t, dn, x, ti, c?, a?, o?}]}
//                     unlock {...}  (the window asks for the state again while it is open)
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace Chaos.Core
{
    public sealed class AchRow
    {
        public string Name = "", Desc = "", Cat = "", Title = "", Reward = "";
        public int Points, Pos;
        public double Total, Value, Unlocked;
        public bool Hidden;
        public bool IsUnlocked => Unlocked > 0;
        public bool HiddenLocked => Hidden && !IsUnlocked;
    }

    /// <summary>A line of the reward track (a step or a category reward), as trackRows builds it.</summary>
    public sealed class AchTrackRow
    {
        public string Name = "", Right = "", Desc = "", Extra = "", Progress = "", Tip = "", Color, Accent;
        public int Percent;
        public bool Done;
    }

    public sealed class AchievementsState : CollectModel
    {
        public const byte OpcodeId = 250;
        public const string All = "all", Recent = "recent", TrackKey = "track";
        public object State;
        public List<AchRow> Rows = new List<AchRow>();
        List<AchRow> pending = new List<AchRow>();
        public object Track;
        public string Selected = All;
        public bool WantOpen, Visible;

        public AchievementsState(ExtOpcodes e) : base(e, OpcodeId) { }

        /// <summary>The window asks the server, which answers with state and list; the window shows when the list is whole.</summary>
        public void Toggle() { if (Visible) Visible = false; else Send("open"); }
        public void Get() { Send("get"); }
        public void SetTitle(string choice) { Send("title", D("title", choice ?? "")); }

        public override void Handle(string action, object data)
        {
            switch (action)
            {
                case "state":
                    State = data;
                    if (CF.B(data, "open")) WantOpen = true;
                    break;
                case "list":
                    if (CF.B(data, "first")) pending = new List<AchRow>();
                    foreach (var r in CF.Rows(CF.G(data, "rows"))) pending.Add(ToRow(r, pending.Count + 1));
                    if (CF.B(data, "last"))
                    {
                        Rows = pending;
                        pending = new List<AchRow>();
                        if (WantOpen) { WantOpen = false; Visible = true; }
                    }
                    break;
                case "track": Track = data; break;
                case "unlock": if (Visible) Get(); break;
            }
        }

        static AchRow ToRow(Dictionary<string, object> r, int pos) => new AchRow
        {
            Name = CF.T(r, "n", "?"), Desc = CF.T(r, "d"), Cat = CF.Str(CF.G(r, "c")), Title = CF.T(r, "ti"), Reward = CF.T(r, "r"),
            Points = CF.I(r, "p"), Total = CF.N(r, "t"), Value = CF.N(r, "v"), Unlocked = CF.N(r, "u"), Hidden = CF.I(r, "h") == 1, Pos = pos,
        };

        public void Clear() { State = null; Rows = new List<AchRow>(); pending = new List<AchRow>(); Track = null; Selected = All; Visible = false; WantOpen = false; }

        // ---------------------------------------------------------------------------------------------- the view rules
        /// <summary>Rows of a category: All, Recent (unlocked, newest first), or one key; unlocked first except in Recent.</summary>
        public static List<AchRow> Filter(IList<AchRow> rows, string cat, bool unlockedFirst)
        {
            var q = rows.Where(r => cat == All || cat == null || r.Cat == cat || (cat == Recent && r.IsUnlocked));
            return StableSort(q, (a, b) =>
            {
                if (cat == Recent) { if (a.Unlocked != b.Unlocked) return b.Unlocked.CompareTo(a.Unlocked); }
                else if (unlockedFirst && a.IsUnlocked != b.IsUnlocked) return a.IsUnlocked ? -1 : 1;
                return a.Pos.CompareTo(b.Pos);
            });
        }

        public static int PercentOf(AchRow r) => r.IsUnlocked ? 100 : CF.Percent(r.Value, r.Total);

        public static string ProgressText(AchRow r)
        {
            if (r.HiddenLocked) return "???";
            if (r.IsUnlocked) return Loc.T("Unlocked");
            return CF.Group(r.Value) + " / " + CF.Group(r.Total);
        }

        public static string ExtraText(AchRow r)
        {
            var p = new List<string>();
            if (r.Title.Length > 0) p.Add(Loc.T("Title: {0}", r.Title));
            if (r.Reward.Length > 0) p.Add(Loc.T("Reward: {0}", r.Reward));
            return string.Join("   -   ", p);
        }

        public static string CategoryLabel(object c) => string.Format("{0}  {1}/{2}", CF.T(c, "name", CF.T(c, "key", "?")), CF.I(c, "done"), CF.I(c, "total"));

        public string SummaryText() => Loc.T("Points: {0}   -   Account: {1}   -   Unlocked: {2} / {3}", CF.I(State, "points"), CF.I(State, "accountPoints"), CF.I(State, "unlocked"), CF.I(State, "total"));

        /// <summary>The titles the combo lists (heldTitles when present, else titles).</summary>
        public List<string> TitleOptions()
        {
            var held = CF.Rows(CF.G(State, "heldTitles"));
            var list = held.Count > 0 ? held : CF.Rows(CF.G(State, "titles"));
            return list.Select(t => CF.T(t, "text")).Where(t => t.Length > 0).ToList();
        }

        public bool TitlesOn => CF.B(State, "titlesOn");
        public string ActiveTitle => CF.T(State, "activeTitle");

        public string RecentText()
        {
            var parts = CF.Rows(CF.G(State, "recent")).Select(r => string.Format("{0} (+{1})", CF.T(r, "name", "?"), CF.I(r, "points"))).ToList();
            return parts.Count > 0 ? Loc.T("Recent:") + " " + string.Join(",  ", parts) : Loc.T("Recent: nothing yet. Level up, hunt tiered monsters, seal rifts...");
        }

        // ---------------------------------------------------------------------------------------------- reward track
        public static string KindName(string k)
        {
            switch (k) { case "killfx": return Loc.T("Kill effect"); case "lootbeam": return Loc.T("Loot label accent"); case "chatcolor": return Loc.T("Chat name colour"); case "spellskin": return Loc.T("Spell effect skin"); }
            return Loc.T("Cosmetic");
        }

        public static List<Dictionary<string, object>> Steps(object track) => CF.Rows(CF.G(track, "steps"));
        public static int TrackReached(object track) { double ap = CF.N(track, "ap"); return Steps(track).Count(s => ap >= CF.N(s, "p")); }

        public static Dictionary<string, object> TrackNext(object track, out double prev)
        {
            double ap = CF.N(track, "ap"); prev = 0;
            foreach (var s in Steps(track)) { if (ap < CF.N(s, "p")) return s; prev = CF.N(s, "p"); }
            return null;
        }

        public static int TrackPercent(object track)
        {
            var next = TrackNext(track, out double prev);
            if (next == null) return 100;
            double span = CF.N(next, "p") - prev;
            return span <= 0 ? 0 : (int)Math.Max(0, Math.Min(100, Math.Floor((CF.N(track, "ap") - prev) * 100 / span)));
        }

        public static string TrackText(object track)
        {
            var next = TrackNext(track, out _);
            double ap = CF.N(track, "ap");
            if (next == null) return Loc.T("{0} account points  -  every reward unlocked ({1})", CF.Group(ap), Steps(track).Count);
            return Loc.T("{0} / {1} account points  -  next: {2} ({3})", CF.Group(ap), CF.Group(CF.N(next, "p")), CF.T(next, "n", "?"), KindName(CF.T(next, "k")));
        }

        public static string RewardTooltip(object r, double ap)
        {
            var lines = new List<string> { string.Format("{0}  -  {1}", CF.T(r, "n", "?"), KindName(CF.T(r, "k"))) };
            if (CF.T(r, "d").Length > 0) lines.Add(CF.T(r, "d"));
            if (CF.G(r, "c") != null) lines.Add(Loc.T("Colour: {0}", CF.Str(CF.G(r, "c"))));
            if (CF.G(r, "a") is string a) lines.Add(Loc.T("Label background: {0}", a.Length > 7 ? a.Substring(0, 7) : a));
            if (CF.G(r, "p") != null)
            {
                double p = CF.N(r, "p");
                lines.Add(ap >= p ? Loc.T("Reached at {0} account points.", CF.Group(p)) : Loc.T("Unlocks at {0} account points ({1} to go).", CF.Group(p), CF.Group(p - ap)));
            }
            if (CF.G(r, "ti") != null) lines.Add(Loc.T("Title: {0}", CF.T(r, "ti")));
            lines.Add(CF.G(r, "o") != null && CF.B(r, "o") ? Loc.T("Owned: choose it in Character > Cosmetics.") : Loc.T("Earned by playing, never sold."));
            return string.Join("\n", lines);
        }

        public static string CategoryReward(object track, string key)
        {
            foreach (var c in CF.Rows(CF.G(track, "cats")))
                if (CF.Str(CF.G(c, "key")) == key)
                    return Loc.T("Complete all {0}: title {1} + {2} ({3}){4}", CF.I(c, "t"), CF.T(c, "ti", "?"), CF.T(c, "n", "?"), KindName(CF.T(c, "k")), CF.I(c, "x") == 1 ? "  -  done" : "");
            return null;
        }

        static string ShortDesc(string d)
        {
            d = Regex.Replace(d ?? "", @"\s+Reward track: [\d,]+ points\.$", "");
            return Regex.Replace(d, @"\s+Complete [^.]+\.$", "");
        }

        public static List<AchTrackRow> TrackRows(object track)
        {
            var o = new List<AchTrackRow>();
            double ap = CF.N(track, "ap");
            foreach (var s in Steps(track))
            {
                double p = CF.N(s, "p");
                bool done = ap >= p;
                o.Add(new AchTrackRow
                {
                    Name = CF.T(s, "n", "?"), Right = CF.Group(p) + " pts", Desc = ShortDesc(CF.T(s, "d")),
                    Extra = KindName(CF.T(s, "k")) + (CF.B(s, "o") ? "  -  owned" : ""), Done = done, Color = CF.Hex(CF.G(s, "c")), Accent = CF.Hex(CF.G(s, "a")),
                    Percent = done ? 100 : (int)Math.Floor(Math.Min(ap, p) * 100 / Math.Max(1, p)),
                    Progress = done ? Loc.T("Unlocked") : Loc.T("{0} / {1} account points", CF.Group(ap), CF.Group(p)), Tip = RewardTooltip(s, ap),
                });
            }
            foreach (var c in CF.Rows(CF.G(track, "cats")))
            {
                bool done = CF.I(c, "x") == 1;
                double t = CF.N(c, "t"), dn = CF.N(c, "dn");
                o.Add(new AchTrackRow
                {
                    Name = string.Format("{0}: {1}", CF.T(c, "cn", CF.T(c, "key", "?")), CF.T(c, "n", "?")), Right = Loc.T("Category"), Desc = ShortDesc(CF.T(c, "d")),
                    Extra = Loc.T("Title: {0}", CF.T(c, "ti", "?")) + "   -   " + KindName(CF.T(c, "k")) + (CF.B(c, "o") ? "  -  owned" : ""),
                    Done = done, Color = CF.Hex(CF.G(c, "c")), Accent = CF.Hex(CF.G(c, "a")),
                    Percent = t > 0 ? (int)Math.Floor(Math.Min(dn, t) * 100 / t) : 0,
                    Progress = done ? Loc.T("Complete") : CF.Group(dn) + " / " + CF.Group(t) + " " + Loc.T("achievements"), Tip = RewardTooltip(c, ap),
                });
            }
            return o;
        }
    }
}
