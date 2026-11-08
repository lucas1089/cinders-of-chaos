// Daily reward (client game_daily, extended opcode 207) and the Weekly Chest (client game_weeklychest, extended opcode 117, server weeklychest.lua).
//
// Daily: client -> server {open} | {closed} | {calim, data = server day number (a bare number, the main client's spelling)}.
//   server -> client OpenDailyWindow {DAILY_REWARDS [{ClientID, Count}], Day, TakenReward, NextIn, Login, Streak?, Broken, Best, Grace, GraceMax, GraceUse,
//                    Next {Days, In, Reward}, Title, Cosmetics [{Name, Days, Owned}]}
//   The client day is the server day + 2, wrapped to 1 above 7 (the main client's rule); a claim maps it back with {6, 7, 1, 2, 3, 4, 5}.
// Weekly Chest: client -> server open | close. server -> client state {acts [{k, done, open, lv}], got, need, bonusNeed, open, chest {given, gold, it [{n, name}]},
//   bonus {given, lo, hi}, endsIn, chests}.
using System;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core
{
    public sealed class DailyState : CollectModel
    {
        public const byte OpcodeId = 207;
        static readonly int[] ServerDay = { 6, 7, 1, 2, 3, 4, 5 };

        public object Data;
        public int Day;          // client day 1..7
        public double ResetAt;   // session ms when the next reward opens
        public bool Visible, LoginOpen;
        public double Clock0;

        public DailyState(ExtOpcodes e) : base(e, OpcodeId) { }

        public void Show() { Visible = true; Send("open"); }
        public void Toggle() { if (Visible) Hide(); else Show(); }
        public void Hide() { if (Visible) { Visible = false; Send("closed"); } }

        public override void Handle(string action, object data)
        {
            if (action != "OpenDailyWindow" || !(data is Dictionary<string, object>)) return;
            Data = data;
            Day = ClientDay(CF.I(data, "Day"));
            ResetAt = Clock() + CF.N(data, "NextIn") * 1000;
            LoginOpen = CF.I(data, "Login") == 1;
            Visible = true;
        }

        /// <summary>server Day + 2, and 1 when that is above 7.</summary>
        public static int ClientDay(int serverDay) { int d = serverDay + 2; return d > 7 ? 1 : d; }

        public bool Claim()
        {
            if (Data == null || CF.I(Data, "TakenReward") == 1) return false;
            return Send("calim", null, (double)ServerDay[Math.Max(1, Math.Min(7, Day)) - 1]);
        }

        bool Send(string action, Dictionary<string, object> unused, object data) => Ext.Send(Opcode, action, data);

        public void Clear() { Data = null; Visible = false; }

        /// <summary>The state of a reward cell: claimed, claimable, next (with a timer), later.</summary>
        public string CellState(int i)
        {
            if (i < Day) return "claimed";
            if (i == Day) return CF.I(Data, "TakenReward") == 1 ? "claimed" : "claimable";
            if (i == Day + 1 && Day < 7) return "next";
            return "later";
        }

        public double RemainingSeconds(double nowMs) => Math.Max(0, (ResetAt - nowMs) / 1000.0);

        /// <summary>The timer of the next cell: "hh:mm" and the percent of the 24 hours gone.</summary>
        public string NextTimer(double nowMs, out int percent)
        {
            double r = RemainingSeconds(nowMs);
            percent = (int)Math.Max(0, Math.Min(100, (86400 - r) / 86400 * 100));
            return string.Format("{0:00}:{1:00}", (long)(r / 3600), (long)(r % 3600 / 60));
        }

        public List<Dictionary<string, object>> Rewards => CF.Rows(CF.G(Data, "DAILY_REWARDS"));

        public bool HasStreak => Data != null && CF.G(Data, "Streak") != null;

        public string StreakLine()
        {
            int streak = CF.I(Data, "Streak");
            string text = Loc.T("Streak: {0} {1}", streak, streak == 1 ? Loc.T("day") : Loc.T("days"));
            if (CF.I(Data, "Broken") == 1 && CF.I(Data, "TakenReward") != 1) text += "  " + Loc.T("(your streak was broken: it starts again today)");
            return text;
        }

        public string BestLine() => Loc.T("Best: {0} days", CF.I(Data, "Best"));
        public string GraceLine() => Loc.T("Grace charges: {0} / {1}", CF.I(Data, "Grace"), CF.G(Data, "GraceMax") != null ? CF.I(Data, "GraceMax") : 2);

        public string GraceTip()
        {
            string tip = Loc.T("A grace charge keeps your streak alive when you miss a single day. You earn one every 7 days in a row.");
            if (CF.I(Data, "GraceUse") > 0) tip += "\n" + Loc.T("You missed a day: today's claim uses a grace charge.");
            return tip;
        }

        public string MilestoneLine()
        {
            var n = CF.G(Data, "Next") as Dictionary<string, object>;
            if (n == null) return Loc.T("Every milestone reached. Keep the streak going!");
            int inDays = CF.I(n, "In");
            return Loc.T("Next milestone: {0} days ({1}): {2}", CF.I(n, "Days"), inDays <= 1 ? Loc.T("next claim") : Loc.T("in {0} days", inDays), CF.T(n, "Reward"));
        }

        public string TitleLine() => CF.T(Data, "Title").Length > 0 ? Loc.T("Your title: {0}", CF.T(Data, "Title")) : "";

        public string CosmeticsLine()
        {
            var parts = new List<string>();
            foreach (var c in CF.Rows(CF.G(Data, "Cosmetics")))
            {
                if (!(CF.G(c, "Name") is string name)) continue;
                parts.Add(CF.I(c, "Owned") == 1 ? Loc.T("{0} ({1} days, owned)", name, CF.I(c, "Days")) : Loc.T("{0} ({1} days)", name, CF.I(c, "Days")));
            }
            return parts.Count > 0 ? Loc.T("Streak cosmetics: {0}", string.Join(", ", parts)) : "";
        }
    }

    /// <summary>One line of the weekly chest window.</summary>
    public sealed class WeeklyRow { public string Key = "", Name = "", What = "", Status = "", Color = ""; }

    public sealed class WeeklyState : CollectModel
    {
        public const byte OpcodeId = 117;
        public const string Done = "#7ccf5c", OpenColor = "#c8b89a", Locked = "#6e655c";
        static readonly Dictionary<string, string[]> Acts = new Dictionary<string, string[]>
        {
            { "dungeon", new[] { "Dungeon", "Clear a dungeon." } }, { "rift", new[] { "Rift", "Seal a rift." } },
            { "waystone", new[] { "Waystone run", "Open a waystone map." } }, { "tower", new[] { "Infinity Tower", "Clear a floor of the Infinity Tower." } },
            { "boss", new[] { "World boss or invasion", "Fight a world boss or an invasion." } }, { "bounty", new[] { "Bounty contract", "Finish a bounty contract." } },
        };

        public object State;
        public bool Visible;

        public WeeklyState(ExtOpcodes e) : base(e, OpcodeId) { }

        public void Show() { Visible = true; Send("open"); }
        public void Hide() { if (Visible) { Visible = false; Send("close"); } }
        public void Toggle() { if (Visible) Hide(); else Show(); }

        public override void Handle(string action, object data) { if (action == "state" && data is Dictionary<string, object>) State = data; }
        public void Clear() { State = null; Visible = false; }

        static int I(object v) { double d = CF.Num(v); return double.IsInfinity(d) || d < 0 ? 0 : (int)Math.Floor(d); }

        public static string Short(object n)
        {
            double v = I(n);
            double[] lim = { 1e12, 1e9, 1e6, 1e3 }; string[] unit = { "T", "B", "M", "k" };
            for (int i = 0; i < lim.Length; i++)
                if (v >= lim[i])
                {
                    double x = v / lim[i];
                    string s = x >= 100 ? ((long)Math.Floor(x)).ToString() : (Math.Floor(x * 10) / 10).ToString("0.0", System.Globalization.CultureInfo.InvariantCulture);
                    if (s.EndsWith(".0")) s = s.Substring(0, s.Length - 2);
                    return s + unit[i];
                }
            return ((long)v).ToString();
        }

        public static string Left(object seconds)
        {
            long s = I(seconds); long d = s / 86400, h = s % 86400 / 3600;
            if (d >= 2) return Loc.T("{0} days", d);
            if (d == 1) return Loc.T("{0} day", 1);
            if (h >= 1) return Loc.T("{0} h", h);
            return Loc.T("under an hour");
        }

        public static string Reward(object gold, object items)
        {
            var parts = new List<string>();
            foreach (var it in CF.Rows(items))
            {
                int n = I(CF.G(it, "n")); string name = CF.T(it, "name");
                if (name.Length > 48) name = name.Substring(0, 48);
                if (name.Length > 0) parts.Add((n > 1 ? n + "x " : "") + name);
            }
            if (parts.Count == 0) return Loc.T("{0} gold", Short(gold));
            return Loc.T("{0} gold, {1}", Short(gold), string.Join(", ", parts));
        }

        public List<WeeklyRow> Rows()
        {
            var o = new List<WeeklyRow>();
            foreach (var a in CF.Rows(CF.G(State, "acts")))
            {
                string k = CF.G(a, "k") as string;
                if (k == null) continue;
                var info = Acts.TryGetValue(k, out var x) ? x : new[] { k, "" };
                var row = new WeeklyRow { Key = k, Name = Loc.T(info[0]), What = info[1].Length > 0 ? Loc.T(info[1]) : "" };
                if (I(CF.G(a, "done")) == 1) { row.Status = Loc.T("Done"); row.Color = Done; }
                else if (I(CF.G(a, "open")) == 1) { row.Status = Loc.T("Not yet"); row.Color = OpenColor; }
                else { row.Status = Loc.T("Unlocks at level {0}", I(CF.G(a, "lv"))); row.Color = Locked; }
                o.Add(row);
            }
            return o;
        }

        public string Head()
        {
            int got = I(CF.G(State, "got")), need = I(CF.G(State, "need")), bonusNeed = I(CF.G(State, "bonusNeed"));
            int goal = got >= need && bonusNeed > 0 ? bonusNeed : need;
            return Loc.T("{0} of {1} activities done this week", got, Math.Max(goal, 1));
        }

        public string Ends() => Loc.T("The week ends in {0}", Left(CF.G(State, "endsIn")));
        public string ChestsLine() => Loc.T("Chests opened so far: {0}", I(CF.G(State, "chests")));

        public string ChestLine(out string color)
        {
            var chest = CF.M(State, "chest");
            if (I(CF.G(chest, "given")) == 1) { color = Done; return Loc.T("The chest is open: this week's reward is yours."); }
            color = OpenColor;
            return Loc.T("The chest opens at {0} of {1} activities.", I(CF.G(State, "need")), I(CF.G(State, "open")));
        }

        public string RewardLine() { var c = CF.M(State, "chest"); return Reward(CF.G(c, "gold"), CF.G(c, "it")); }

        public string BonusLine(out string color)
        {
            int bonusNeed = I(CF.G(State, "bonusNeed"));
            var b = CF.M(State, "bonus");
            if (bonusNeed <= 0) { color = Locked; return Loc.T("No bonus roll at your level: more systems unlock as you level."); }
            if (I(CF.G(b, "given")) == 1) { color = Done; return Loc.T("Bonus roll taken this week."); }
            color = OpenColor;
            return Loc.T("All {0} activities add a bonus roll: {1} to {2} gold or orbs.", bonusNeed, Short(CF.G(b, "lo")), Short(CF.G(b, "hi")));
        }
    }
}
