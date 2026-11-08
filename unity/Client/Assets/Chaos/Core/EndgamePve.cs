// Endgame activities, the PvE half: Infinity Tower (opcode 214, client game_infinitytower), Dungeons (109, game_dungeons), the Ashen Sepulchre raid
// (213, game_raid), the Ember Descent (205, game_descent) and invasions (251, game_invasion). Each module has a state class (messages in, requests
// out) and a static view class that holds the main client's text and rules (towerskip.lua, dungeonsview.lua, raidview.lua, descentmath.lua,
// invasionmath.lua). The server's payload is read as the main client reads it: missing fields give the same defaults.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    // ================================================================================================ Infinity Tower
    public sealed class TowerMilestone { public int Points; public bool Claimed; public List<EgItem> Items = new List<EgItem>(); }
    public sealed class TowerRank { public string Name = ""; public int Floor; public double Time; }
    public sealed class TowerPanel { public string Floor = "", Cleared = "", Monsters, Timer; public bool Boss; }
    public sealed class TowerButton { public bool Visible, Enabled; public string Tip = ""; }

    /// <summary>The tower is flat JSON ({action, fields...}), not {action, data}: the requests go out flat as well.</summary>
    public sealed class TowerState : EgModule
    {
        public const byte Opcode = 214;
        public const double MinPressMs = 1000, AutoGapMs = 2000;
        public const string HotkeyText = "Ctrl+Shift+N";
        protected override byte Op => Opcode;
        public Func<double> UnixNow = () => (DateTime.UtcNow - new DateTime(1970, 1, 1)).TotalSeconds;

        // the run panel (action "state")
        public bool InRun, CanSkip, NextBoss, Waiting, Boss, IsLeader = true, HasRunState;
        public int Floor, Cleared, Remaining, Total;
        public double NextIn, FloorLeft = -1, StateAt;
        public double LastSkipAt = double.NaN, LastLeaveAt = double.NaN;
        /// <summary>The "Auto" box of the panel: skip each floor as soon as the run waits (the app keeps it in PlayerPrefs).</summary>
        public bool AutoSkip;

        // the window ("open" / "update")
        public bool Visible, HasData;
        public int SeasonNum = 1, PlayerPoints;
        public double SeasonEnd, NextTry, DataAt;
        public List<TowerMilestone> Milestones = new List<TowerMilestone>();
        public List<TowerRank> Rankings = new List<TowerRank>();
        public List<object> TopRewards = new List<object>();
        public object FloorRewards;

        public static readonly int[][] DefaultMilestones = { new[] { 60000, 3043, 30 }, new[] { 120000, 51964, 1 }, new[] { 180000, 63185, 1 }, new[] { 240000, 51956, 10 }, new[] { 300000, 43895, 1 } };

        public TowerState(ExtOpcodes e) : base(e) { ext.On(Opcode, m => Handle(m.Root)); }

        bool SendFlat(string action, Dictionary<string, object> extra = null)
        {
            var d = new Dictionary<string, object> { { "action", action } };
            if (extra != null) foreach (var kv in extra) d[kv.Key] = kv.Value;
            return ext.SendText(Opcode, Json.Serialize(d));
        }

        public void QueryState() { SendFlat("state"); }
        public void Request() { SendFlat("request"); }

        public void Handle(object root)
        {
            string action = Json.Text(root, "action");
            if (action == "state")
            {
                InRun = Json.Truthy(root, "inRun"); CanSkip = Json.Truthy(root, "canSkip"); NextBoss = Json.Truthy(root, "nextBoss");
                IsLeader = Json.Truthy(root, "isLeader", true);
                Waiting = Json.Truthy(root, "waiting"); Boss = Json.Truthy(root, "boss");
                Floor = Json.Int(root, "floor"); Cleared = Json.Int(root, "cleared"); Remaining = Json.Int(root, "remaining"); Total = Json.Int(root, "total");
                NextIn = Json.Number(root, "nextIn"); FloorLeft = Json.Get(root, "floorLeft") is double fl ? fl : -1;
                HasRunState = true;
                StateAt = Now;
                AutoSkipCheck();
                Changed();
            }
            else if (action == "open" || action == "update")
            {
                Apply(root);
                if (action == "open") Visible = true;
                Changed();
            }
        }

        void Apply(object d)
        {
            HasData = true;
            DataAt = Now;
            SeasonNum = Json.Get(d, "seasonNum") is double sn ? (int)sn : 1;
            SeasonEnd = Json.Number(d, "seasonEnd"); NextTry = Json.Number(d, "nextTry"); PlayerPoints = Json.Int(d, "playerPoints");
            if (Json.Get(d, "milestones") is List<object> ms)
            {
                Milestones = new List<TowerMilestone>();
                foreach (object o in ms)
                    if (o is Dictionary<string, object>) Milestones.Add(new TowerMilestone { Points = Json.Int(o, "points"), Claimed = Json.Truthy(o, "claimed"), Items = EgItem.ListOf(o, "items") });
            }
            if (Json.Get(d, "rankings") is List<object> rk)
            {
                Rankings = new List<TowerRank>();
                foreach (object o in rk)
                    if (o is Dictionary<string, object>) Rankings.Add(new TowerRank { Name = Json.Text(o, "name"), Floor = Json.Int(o, "floor"), Time = Json.Number(o, "time") });
            }
            if (Json.Get(d, "topRewards") is List<object> tr) TopRewards = Eg.Objects(d, "topRewards");
            FloorRewards = Json.Get(d, "floorRewards");
        }

        // ---- the milestones (defaults while no data came, as showLoadingState does)
        public List<TowerMilestone> ShownMilestones()
        {
            if (Milestones.Count > 0) return Milestones;
            var list = new List<TowerMilestone>();
            foreach (var m in DefaultMilestones)
                list.Add(new TowerMilestone { Points = m[0], Items = new List<EgItem> { new EgItem { Id = m[1], Count = m[2], Name = m[1] == 3043 ? "Gold Coin" : "Prize" } } });
            return list;
        }

        public int MaxPoints() { var l = ShownMilestones(); return l.Count > 0 ? Math.Max(1, l[l.Count - 1].Points) : 1; }
        /// <summary>The fill of the points bar, 0..1.</summary>
        public double PointsRatio() => Math.Min(1.0, (double)PlayerPoints / MaxPoints());
        public bool CanClaim(int index) => index >= 1 && index <= Milestones.Count && !Milestones[index - 1].Claimed && PlayerPoints >= Milestones[index - 1].Points;
        public static string Place(int i) => i == 1 ? "#FFD700" : i == 2 ? "#C0C0C0" : i == 3 ? "#CD7F32" : "#FFFFFF";

        public string NextRewardText()
        {
            if (!(FloorRewards is Dictionary<string, object>) || !(Json.Get(FloorRewards, "nextFloor") is double nf)) return Loc.T("Next reward: --");
            var lines = new List<string> { Loc.T("Next reward: floor {0}", (long)nf) };
            string first = EgItem.Text(EgItem.ListOf(FloorRewards, "first"));
            if (first.Length > 0) lines.Add(Loc.T("First clear this season: {0}", first));
            string again = EgItem.Text(EgItem.ListOf(FloorRewards, "repeatable"));
            if (again.Length > 0) lines.Add(Loc.T("Every clear: {0}", again));
            return string.Join("\n", lines);
        }

        public string SeasonEndText() => SeasonEnd - UnixNow() > 0 ? Loc.T("Season Ends In: {0}", Eg.TimeRemaining(SeasonEnd - UnixNow())) : Loc.T("Season Ends In: Finished");
        public string NextTryText() => NextTry - UnixNow() > 0 ? Loc.T("Next Try Available: {0}", Eg.TimeRemaining(NextTry - UnixNow())) : Loc.T("Next Try Available: Ready Now!");

        // ---- the run panel
        /// <summary>The Next floor button (towerskip.lua view): visible inside a run, enabled when the server says canSkip.</summary>
        public TowerButton View()
        {
            if (!InRun) return new TowerButton { Tip = "Start the next floor at once instead of waiting." };
            if (CanSkip) return new TowerButton { Visible = true, Enabled = true, Tip = "Start the next floor at once instead of waiting." };
            string tip = "Available when the floor is cleared.";
            if (!IsLeader) tip = "Only the run leader can call the next floor.";
            else if (NextBoss) tip = "A boss floor is next: it starts by itself.";
            return new TowerButton { Visible = true, Tip = tip };
        }

        public bool CanPress(double nowMs) => View().Enabled && (double.IsNaN(LastSkipAt) || nowMs - LastSkipAt >= MinPressMs);
        public bool CanLeave(double nowMs) => InRun && (double.IsNaN(LastLeaveAt) || nowMs - LastLeaveAt >= MinPressMs);
        public bool ShouldAutoSkip(double nowMs) => AutoSkip && InRun && CanSkip && (double.IsNaN(LastSkipAt) || nowMs - LastSkipAt >= AutoGapMs);

        public bool Skip()
        {
            if (!CanPress(Now)) return false;
            LastSkipAt = Now;
            return SendFlat("skip");
        }

        void AutoSkipCheck()
        {
            if (!ShouldAutoSkip(Now)) return;
            LastSkipAt = Now;
            SendFlat("skip");
        }

        /// <summary>The panel's Leave button.</summary>
        public bool LeaveRun()
        {
            if (!CanLeave(Now)) return false;
            LastLeaveAt = Now;
            return SendFlat("leave");
        }

        /// <summary>The window's Enter button: the window closes.</summary>
        public void Enter() { SendFlat("enter"); Visible = false; Changed(); }
        /// <summary>The window's Leave button: the window closes.</summary>
        public void LeaveTower() { SendFlat("leave"); Visible = false; Changed(); }
        public bool Claim(int milestoneIndex) { if (!CanClaim(milestoneIndex)) return false; return SendFlat("claim", D("milestoneIndex", milestoneIndex)); }

        public void Show() { Visible = true; Changed(); }
        public void Hide() { Visible = false; }
        /// <summary>Opens with what it has and asks for a fresh state (toggle of the main client).</summary>
        public void Toggle() { if (Visible) Hide(); else ShowAndRequest(); }
        /// <summary>Opens with what it has (or the defaults) and asks for a fresh state.</summary>
        public void ShowAndRequest() { Visible = true; Request(); Changed(); }

        /// <summary>The panel text (towerskip.lua panel); null outside a run.</summary>
        public TowerPanel Panel(double nowMs)
        {
            if (!InRun) return null;
            var p = new TowerPanel { Boss = Boss };
            p.Floor = Floor <= 0 ? Loc.T("Get ready") : Loc.T(Boss ? "Floor {0} (boss)" : "Floor {0}", Floor);
            p.Cleared = Loc.T("Floors cleared: {0}", Cleared);
            double el = Math.Max(0, (nowMs - StateAt) / 1000.0);
            if (Waiting) p.Timer = Loc.T("Next floor in {0}s", (long)Math.Max(0, Math.Ceiling(NextIn - el)));
            else
            {
                p.Monsters = Loc.T("Monsters left: {0} of {1}", Remaining, Total);
                if (FloorLeft >= 0) p.Timer = Loc.T("Floor time left: {0}", Eg.Clock(Math.Max(0, Math.Ceiling(FloorLeft - el))));
            }
            return p;
        }

        public void Clear()
        {
            InRun = CanSkip = NextBoss = Waiting = Boss = HasRunState = false; IsLeader = true;
            Floor = Cleared = Remaining = Total = 0; NextIn = 0; FloorLeft = -1;
            Visible = HasData = false; Milestones = new List<TowerMilestone>(); Rankings = new List<TowerRank>(); TopRewards = new List<object>(); FloorRewards = null;
            LastSkipAt = LastLeaveAt = double.NaN;
        }
    }

    // ================================================================================================ Dungeons
    public sealed class DungeonRow
    {
        public int Id, Level, Queue;
        public string Title = "";
        public object Boss;
    }

    public sealed class DungeonDetail
    {
        public int Id, Difficulty = 1, QueuePlayers;
        public double QueueEstimatedMs;
        public string Title = "";
        public object Data;
        public Dictionary<int, List<object>> Solo = new Dictionary<int, List<object>>(), Group = new Dictionary<int, List<object>>();
    }

    public static class DungeonsView
    {
        public sealed class Level { public int Health, Damage, Experience, Gold, Loot; public Level(int h, int d, int x, int g, int l) { Health = h; Damage = d; Experience = x; Gold = g; Loot = l; } }
        public static readonly Level[] Levels =
        {
            new Level(100, 100, 0, 0, 0), new Level(200, 130, 75, 75, 0), new Level(320, 190, 100, 100, 15),
            new Level(500, 280, 200, 200, 30), new Level(800, 400, 300, 300, 45), new Level(1300, 600, 400, 400, 60),
        };

        public static int Clamp(double d) => double.IsNaN(d) || d < 1 ? 1 : (int)Math.Min(Levels.Length, Math.Floor(d));

        static bool Percent(object v, out int p)
        {
            p = 0;
            if (!(v is double d) || double.IsNaN(d) || d < 1 || d > 100000) return false;
            p = (int)Math.Floor(d);
            return true;
        }

        /// <summary>The monster and boss health of a dungeon with its own curves, else false.</summary>
        public static bool HealthOf(object health, int diff, out int monsters, out int boss)
        {
            monsters = boss = 0;
            if (!(Json.Get(health, "monsters") is List<object> m) || !(Json.Get(health, "boss") is List<object> b)) return false;
            diff = Clamp(diff);
            return diff <= m.Count && diff <= b.Count && Percent(m[diff - 1], out monsters) && Percent(b[diff - 1], out boss);
        }

        /// <summary>The panel text of a difficulty (dungeonsview.lua panelText): the table's numbers, health from the server when it sends curves.</summary>
        public static string PanelText(int diff, object health)
        {
            diff = Clamp(diff);
            var l = Levels[diff - 1];
            if (!HealthOf(health, diff, out int m, out int b))
            {
                var d = new List<string> { Loc.T("Monster Health {0}%", l.Health), Loc.T("Monster Damage {0}%", l.Damage) };
                if (l.Experience > 0) d.Add(Loc.T("Bonus XP +{0}%", l.Experience));
                if (l.Gold > 0) d.Add(Loc.T("Gold Drop +{0}%", l.Gold));
                if (l.Loot > 0) d.Add(Loc.T("Loot Chance +{0}%", l.Loot));
                return string.Join("\n", d);
            }
            var lines = new List<string> { Loc.T("Monster Health {0}%", m), Loc.T("Boss Health {0}%", b), Loc.T("Monster Damage {0}%", l.Damage) };
            if (l.Experience > 0) lines.Add(Loc.T("Bonus XP +{0}%", l.Experience));
            if (l.Gold > 0) lines.Add(Loc.T("Gold Drop +{0}%", l.Gold));
            if (l.Loot > 0) lines.Add(Loc.T("Loot Chance +{0}%", l.Loot));
            return string.Join("\n", lines);
        }

        public static string WeeklyTitle(object w)
        {
            if (!(w is Dictionary<string, object>) || !(Json.Get(w, "label") is string label)) return null;
            return Loc.T("Weekly Challenge {0}: {1}", label, Json.Get(w, "theme") is string th ? th : "?");
        }

        public static string WeeklyText(object w)
        {
            if (!(w is Dictionary<string, object>) || !(Json.Get(w, "label") is string)) return null;
            var lines = new List<string>
            {
                Loc.T("The same layout for everyone this week, always at difficulty 1. Solo or a party of up to 4."),
                Loc.T("Fastest clear per class: Leaderboards, Weekly Challenge Solo and Party. The top 3 of each class get Conquest Tokens."),
            };
            if (Json.Get(w, "current") != null && !Json.Truthy(w, "current", true)) lines.Add(Loc.T("This layout is last week's: the new one opens at the next server save."));
            else if (Json.Get(w, "resetIn") is double r) lines.Add(Loc.T("New layout in {0}.", Eg.Span(r)));
            return string.Join("\n", lines);
        }

        public static string BannerTitle(DungeonDetail d)
        {
            if (d == null) return null;
            if (Json.Get(d.Data, "weekly") is Dictionary<string, object> && Json.Get(Json.Get(d.Data, "weekly"), "theme") is string th) return "The " + th;
            return d.Title;
        }

        public static string QueueText(int players) => players == 0 ? Loc.T("Queue: {0}", Loc.T("Open")) : Loc.T("Queue: {0}", Loc.T("{0} Players", players));
        public static string QueueStatus(int players) => players == 0 ? Loc.T("Open") : Loc.T("{0} Players", players);

        public static string MsToShortTime(double ms)
        {
            if (ms <= 0) return "00:00.000";
            long mins = (long)Math.Floor(ms / 1000 / 60), secs = (long)Math.Floor(ms / 1000 % 60);
            long tenth = (long)((ms % 1000) / 100);
            return mins.ToString("00", CultureInfo.InvariantCulture) + ":" + secs.ToString("00", CultureInfo.InvariantCulture) + "." + tenth.ToString(CultureInfo.InvariantCulture);
        }

        public static string SecondsToShortTime(double seconds)
        {
            if (seconds <= 0) return "00:00:00";
            long h = (long)Math.Floor(seconds / 3600), m = (long)Math.Floor(seconds / 60 - h * 60), s = (long)Math.Floor(seconds - h * 3600 - m * 60);
            return h.ToString("00", CultureInfo.InvariantCulture) + ":" + m.ToString("00", CultureInfo.InvariantCulture) + ":" + s.ToString("00", CultureInfo.InvariantCulture);
        }
    }

    public sealed class DungeonsState : EgModule
    {
        public const byte Opcode = 109;
        protected override byte Op => Opcode;

        public bool Visible;
        public readonly List<DungeonRow> Rows = new List<DungeonRow>();
        public readonly Dictionary<int, DungeonDetail> Details = new Dictionary<int, DungeonDetail>();
        public int SelectedId, SelectedDifficulty = 1;
        /// <summary>The dungeon the player waits in the queue of (0: none) and when the wait began (ms).</summary>
        public int QueuedId;
        public double QueueStartedAt;

        // the kill counter (action "start" .. "finish")
        public bool Counter, BossUnlocked, BossKilled;
        public string BossName = "";
        public int Need = 85, Percent, MonstersLeft;
        public List<string> Objectives = new List<string>();
        public List<bool> ObjectivesDone = new List<bool>();
        public double DurationMs, StartedAt;
        public string Banner = "";
        public double BannerUntil;
        public const double BannerSeconds = 3.25;

        public DungeonsState(ExtOpcodes e) : base(e) { ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        public void Fetch() { Send("fetch"); Changed(); }

        public void Handle(string action, object data)
        {
            switch (action)
            {
                case "list": OnList(data); break;
                case "dungeon": OnDungeon(data); break;
                case "solo": OnRunners(data, true); break;
                case "group": OnRunners(data, false); break;
                case "queue": OnQueue(data); break;
                case "prepare": StopQueue(); Visible = false; break;
                case "start": OnStart(data); break;
                case "finish": Counter = false; break;
                case "objective": OnObjective(data); break;
                case "killed": OnKilled(data); break;
                case "queueUpdate": OnQueueUpdate(data); break;
                case "difficulty": OnDifficulty(data); break;
                case "challenge": ShowBanner(Loc.T("{0} challenge completed!", data is string t ? t : "")); break;
                case "stopQueue": StopQueue(); break;
                case "open": Visible = true; break;
            }
            Changed();
        }

        void OnList(object data)
        {
            Rows.Clear();
            if (!(data is List<object> list)) return;
            foreach (object o in list)
                if (o is Dictionary<string, object>)
                    Rows.Add(new DungeonRow { Id = Json.Int(o, "id"), Title = Json.Text(o, "title"), Level = Json.Int(o, "level"), Boss = Json.Get(o, "boss"), Queue = Json.Int(o, "queue") });
            Rows.Sort((a, b) => a.Level.CompareTo(b.Level));
            if (Rows.Count > 0 && !Rows.Exists(r => r.Id == SelectedId)) SelectedId = Rows[0].Id;
        }

        void OnDungeon(object data)
        {
            if (!(data is Dictionary<string, object>) || !(Json.Get(data, "id") is double)) return;
            int id = Json.Int(data, "id");
            var d = new DungeonDetail { Id = id, Title = Json.Text(data, "title"), Difficulty = Json.Get(data, "difficulty") is double df ? (int)df : 1, Data = data };
            var q = Json.Get(data, "queue");
            d.QueuePlayers = q is Dictionary<string, object> ? Json.Int(q, "players") : Json.Int(data, "queue");
            d.QueueEstimatedMs = q is Dictionary<string, object> ? Json.Number(q, "estimated") : 0;
            if (Details.TryGetValue(id, out var old)) { d.Solo = old.Solo; d.Group = old.Group; }
            Details[id] = d;
        }

        void OnRunners(object data, bool solo)
        {
            if (!Details.TryGetValue(Json.Int(data, "id"), out var d)) return;
            var top = Json.Get(data, "top") as List<object> ?? new List<object>();
            (solo ? d.Solo : d.Group)[Json.Int(data, "diff")] = top;
        }

        void OnQueue(object data)
        {
            if (Json.Truthy(data, "joined")) { QueuedId = Json.Int(data, "id"); QueueStartedAt = Now; }
            else StopQueue();
        }

        void StopQueue() { QueuedId = 0; }

        void OnStart(object data)
        {
            StopQueue();
            Counter = true; BossUnlocked = false; BossKilled = false; Percent = 0;
            Objectives = Eg.Strings(data, "objectives");
            ObjectivesDone = new List<bool>(new bool[Objectives.Count]);
            Need = Json.Get(data, "need") is double n ? (int)n : 85;
            BossName = Json.Text(data, "boss");
            MonstersLeft = Json.Int(data, "left");
            DurationMs = Json.Number(data, "duration"); StartedAt = Now;
        }

        void OnObjective(object data)
        {
            int id = Json.Int(data, "id");
            while (ObjectivesDone.Count <= id) ObjectivesDone.Add(false);
            ObjectivesDone[id] = Json.Truthy(data, "finished");
        }

        void OnKilled(object data)
        {
            if (Json.Get(data, "percent") is double p)
            {
                Percent = (int)Math.Min(100, p);
                if (Json.Truthy(data, "unlocked") && !BossUnlocked) { BossUnlocked = true; ShowBanner(Loc.T("Boss unlocked!")); }
            }
            else if (Json.Truthy(data, "boss")) { BossKilled = true; ShowBanner(Loc.T("You completed the dungeon!")); }
            if (Json.Get(data, "left") is double l) MonstersLeft = (int)l;
        }

        void OnQueueUpdate(object data)
        {
            if (!Details.TryGetValue(Json.Int(data, "id"), out var d)) return;
            d.QueuePlayers = Json.Int(data, "queue"); d.QueueEstimatedMs = Json.Number(data, "estimated");
            foreach (var r in Rows) if (r.Id == d.Id) r.Queue = d.QueuePlayers;
        }

        void OnDifficulty(object data)
        {
            if (Details.TryGetValue(Json.Int(data, "id"), out var d)) d.Difficulty = Json.Int(data, "difficulty");
        }

        void ShowBanner(string text) { Banner = text; BannerUntil = Now + BannerSeconds * 1000; }

        // ---- what the window asks
        public DungeonDetail Selected => Details.TryGetValue(SelectedId, out var d) ? d : null;
        public void Select(int id) { SelectedId = id; SelectedDifficulty = 1; Changed(); }
        public bool Unlocked(int difficulty)
        {
            var d = Selected;
            return d != null && difficulty <= Math.Max(1, d.Difficulty) && !(Json.Get(d.Data, "weekly") is Dictionary<string, object>) || difficulty == 1;
        }

        public void SelectDifficulty(int diff) { if (Unlocked(diff)) { SelectedDifficulty = diff; Changed(); } }

        /// <summary>Join (or leave, when queued) the selected dungeon at the selected difficulty.</summary>
        public bool JoinQueue()
        {
            if (SelectedId == 0) return false;
            return ext.Send(Opcode, "queue", D("id", SelectedId, "difficulty", SelectedDifficulty));
        }

        public double QueueWaitedSeconds(double nowMs) => QueuedId == 0 ? 0 : Math.Floor((nowMs - QueueStartedAt) / 1000);
        public double CounterLeftMs(double nowMs) => Math.Max(0, DurationMs - (nowMs - StartedAt));
        public bool BannerActive(double nowMs) => Banner.Length > 0 && nowMs < BannerUntil;
        public void Show() { Visible = true; Changed(); }
        public void Hide() { Visible = false; }

        public void Clear()
        {
            Visible = false; Rows.Clear(); Details.Clear(); SelectedId = 0; SelectedDifficulty = 1; QueuedId = 0; Counter = false; Banner = "";
        }
    }

    // ================================================================================================ Ashen Sepulchre raid
    public sealed class RaidRow { public string Title = "", Progress = "", Next = "", Color = "", Action = ""; public int Id; }
    public sealed class RaidLockRow { public string Text = "", State = "", Color = ""; public bool Looted; }
    public sealed class RaidVendorRow { public string Key = "", Name = "", Sub = "", Limit = "", Button = ""; public bool Can; }

    public static class RaidView
    {
        public static string LockSummary(object info)
        {
            var lockd = Json.Get(info, "lock");
            return Loc.T("{0} of {1} bosses looted this week. Lockouts reset in {2}.", Json.Int(lockd, "looted"), Json.Int(lockd, "total"), Eg.ResetText(Json.Number(lockd, "reset")));
        }

        public static List<RaidLockRow> LockRows(object info)
        {
            var rows = new List<RaidLockRow>();
            var bosses = Json.List(Json.Get(info, "lock"), "bosses");
            for (int i = 0; i < bosses.Count; i++)
            {
                object b = bosses[i];
                bool looted = Json.Truthy(b, "l");
                rows.Add(new RaidLockRow { Text = (i + 1) + ". " + Json.Text(b, "n", "?"), Looted = looted, State = looted ? Loc.T("Looted this week") : Loc.T("Loot available"), Color = looted ? "#8c8070" : "#9fd89f" });
            }
            return rows;
        }

        public static RaidRow SavedRow(object s)
        {
            int done = Json.Int(s, "done");
            var killed = Json.List(s, "killed");
            var marks = new StringBuilder();
            foreach (object k in killed) marks.Append(Json.Truthy(k) ? 'X' : '-');
            bool cleared = Json.Truthy(s, "cleared");
            var row = new RaidRow
            {
                Id = Json.Int(s, "id"),
                Title = Loc.T("Raid #{0} ({1})", Json.Int(s, "id"), Json.Text(s, "leader", "?")),
                Progress = Loc.T("{0} / {1} slain  [{2}]", done, killed.Count, marks.ToString()),
                Next = cleared ? Loc.T("Cleared") : Loc.T("Next: {0}", Json.Text(s, "next", "?")),
                Color = cleared ? "#8c8070" : "#e8b84a",
            };
            if (Json.Truthy(s, "inside")) row.Action = "inside";
            else if (Json.Truthy(s, "open")) row.Action = "join";
            else if (!cleared) row.Action = "continue";
            return row;
        }

        public static string ActionText(string action) => action == "continue" ? Loc.T("Continue") : action == "join" ? Loc.T("Join") : action == "inside" ? Loc.T("Inside") : "";

        /// <summary>The Open New Raid button: can start, the label and the reason.</summary>
        public static bool StartState(object info, out string why)
        {
            why = "";
            if (!(info is Dictionary<string, object>)) return false;
            if (Json.Truthy(info, "inRaid")) { why = Loc.T("You are inside a raid."); return false; }
            if (Json.Int(info, "level") < Json.Int(info, "minLevel")) { why = Loc.T("Level {0} needed.", Json.Int(info, "minLevel")); return false; }
            why = Loc.T("Alone, or your party of up to {0} within range comes along (protection zone, out of combat).", Json.Get(info, "maxPlayers") is double mp ? (int)mp : 15);
            return true;
        }

        public static string RecordLine(object info)
        {
            if (!(info is Dictionary<string, object>)) return "";
            double best = Json.Number(info, "best");
            return Loc.T("Sepulchre Marks: {0}   Bosses looted: {1}   Full clears: {2}{3}", Eg.Number(Json.Number(info, "marks")), Json.Int(info, "kills"), Json.Int(info, "clears"),
                best > 0 ? Loc.T("   Best clear: {0}", Eg.Clock(best)) : "");
        }

        public sealed class JournalBoss { public string Title = "", Intro = "", Roles = "", Phases = ""; public List<string> Mech = new List<string>(), Loot = new List<string>(); }

        public static JournalBoss Journal(object b, int index)
        {
            var phases = new List<string>();
            foreach (object p in Json.List(b, "phases")) phases.Add(Json.Text(p, "n") + " (" + Json.Int(p, "at") + "%)");
            var j = new JournalBoss();
            foreach (object m in Json.List(b, "mech")) j.Mech.Add("- " + (m is string s ? s : ""));
            var l = Json.Get(b, "loot");
            j.Loot.Add(Loc.T("{0} gold to the bank, {1} Sepulchre Marks", Eg.Number(Json.Number(l, "gold")), Json.Int(l, "marks")));
            foreach (object it in Json.List(l, "items"))
                j.Loot.Add(Json.Get(it, "n") is string n ? Json.Int(it, "count") + " " + n : LootText(Json.Int(it, "count") + " item " + Json.Int(it, "id")));
            var lv = Json.List(l, "gearLevel");
            j.Loot.Add(Loc.T("{0} gear rolls, item level {1}-{2} ({3} base items)", Json.Int(l, "gearRolls"),
                lv.Count > 0 && lv[0] is double a ? (int)a : 0, lv.Count > 1 && lv[1] is double c ? (int)c : 0, Json.List(l, "gear").Count));
            var uniques = Eg.Strings(l, "uniques");
            if (uniques.Count > 0) j.Loot.Add(Loc.T("{0}% chance of a raid unique: {1}", (Json.Number(l, "unique") / 100).ToString("0.0", CultureInfo.InvariantCulture), string.Join(", ", uniques)));
            j.Title = index + ". " + Json.Text(b, "n", "?") + (Json.Truthy(b, "final") ? " " + Loc.T("(final)") : "");
            j.Intro = Json.Text(b, "intro");
            j.Roles = Loc.T("Roles: {0}", Json.Text(b, "roles"));
            j.Phases = Loc.T("Phases: {0}{1}", string.Join(", ", phases), Loc.T(". Enrage at {0}.", Eg.Clock(Json.Number(b, "enrage"))));
            return j;
        }

        static readonly Dictionary<int, string> Items = new Dictionary<int, string> { { 29856, "Orbs of Upheaval" }, { 29857, "Orbs of Fate" }, { 29855, "Exalted Orb" } };

        public static string LootText(string line)
        {
            return System.Text.RegularExpressions.Regex.Replace(line ?? "", @"item (\d+)", m =>
            {
                int id = int.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture);
                return Items.TryGetValue(id, out var n) ? n : Loc.T("item {0}", id);
            });
        }

        static readonly string[] Rarity = { "", "Common", "Uncommon", "Magic", "Rare", "Legendary" };

        /// <summary>The vendor's stock rows of an info message. The server sends vendor = {marks, stock = [rows]} (raid.lua vendorView); the window read vendor as the list itself and
        /// so showed an empty Vendor tab (phase 12, track H). A plain list is still accepted.</summary>
        public static List<object> VendorStock(object info)
        {
            object v = Json.Get(info, "vendor");
            return v is List<object> ? Eg.Objects(info, "vendor") : Eg.Objects(v, "stock");
        }

        public static RaidVendorRow VendorRow(object e, double marks)
        {
            string sub;
            if (Json.Text(e, "kind") == "gear")
            {
                int r = Json.Int(e, "rarity");
                sub = Loc.T("{0}, item level {1}: {2}", Loc.T(r >= 1 && r < Rarity.Length ? Rarity[r] : "Rare"), Json.Int(e, "level"), string.Join(", ", Eg.Strings(e, "mods")));
            }
            else
            {
                var parts = new List<string>();
                foreach (object it in Json.List(e, "items")) parts.Add(Json.Int(it, "c") + " " + Json.Text(it, "n"));
                sub = string.Join(", ", parts);
            }
            int bought = Json.Int(e, "bought"), weekly = Json.Get(e, "weekly") is double w ? (int)w : 1, price = Json.Int(e, "price");
            return new RaidVendorRow
            {
                Key = Json.Text(e, "key"), Name = Json.Text(e, "n", "?"), Sub = sub, Limit = Loc.T("{0} / {1} this week", bought, weekly),
                Button = bought >= weekly ? Loc.T("Sold out") : Loc.T("{0} marks", price), Can = bought < weekly && marks >= price,
            };
        }

        public static string HudTitle(object d) => Json.Text(d, "raid", "Raid") + " #" + Json.Int(d, "id");

        public static int Progress(object d)
        {
            int total = Json.Int(d, "total");
            return total <= 0 ? 0 : (int)Math.Floor(Json.Number(d, "done") * 100 / total);
        }

        public static string BossLine(object d)
        {
            string state = Json.Text(d, "state");
            if (state == "clear") return Loc.T("Every boss is slain.");
            string who = Json.Int(d, "idx") + ". " + Json.Text(d, "boss", "?");
            if (state == "fight") return who + " - " + (Json.Get(d, "hp") is double hp ? (int)hp : 100) + "%";
            if (Json.Get(d, "trash") is double t) return Loc.T("{0} - clear the corridor ({1} left)", who, (int)t);
            return Loc.T("{0} awaits", who);
        }

        public static string PhaseLine(object d)
        {
            if (Json.Text(d, "state") != "fight" || !(Json.Get(d, "phase") is double ph)) return "";
            return Loc.T("Phase {0} of {1}: {2}", (int)ph, Json.Get(d, "phases") is double ps ? (int)ps : 1, Json.Text(d, "phaseName"));
        }

        public static string EnrageText(object d, double left, out string color)
        {
            color = "#f4d27a";
            if (Json.Text(d, "state") != "fight") return "";
            if (Json.Truthy(d, "enraged")) { color = "#ff4030"; return "ENRAGED"; }
            color = left <= 60 ? "#ff9a30" : "#f4d27a";
            return "Enrage " + Eg.Clock(left);
        }

        public static string CountsLine(object d)
        {
            var parts = new List<string> { Loc.T("Raiders {0}", Json.Int(d, "players")) };
            if (Json.Get(d, "fallen") is double f) parts.Add(Loc.T("fallen {0}", (int)f));
            if (Json.Get(d, "adds") is double a) parts.Add(Loc.T("adds {0}", (int)a));
            if (Json.Get(d, "totems") is double t) parts.Add(Loc.T("effigies {0}", (int)t));
            return string.Join(", ", parts);
        }

        public static string StacksLine(object d)
        {
            var s = Json.Get(d, "stacks");
            var parts = new List<string>();
            if (Json.Number(s, "sunder") > 0) parts.Add(Loc.T("Sundered x{0}", Json.Int(s, "sunder")));
            if (Json.Number(s, "hexed") > 0) parts.Add(Loc.T("Hexed x{0}", Json.Int(s, "hexed")));
            if (Json.Get(d, "hexed") is double h) parts.Add(Loc.T("WITHERING HEX {0}s: cleanse!", (int)h));
            return string.Join("   ", parts);
        }

        static readonly Dictionary<string, string> AlertColors = new Dictionary<string, string>
        {
            { "mech", "#f6cf72" }, { "tank", "#ff9a30" }, { "swap", "#9fd8ff" }, { "fail", "#ff4030" }, { "phase", "#e8b84a" }, { "pull", "#ff7a2a" },
            { "kill", "#7fd07f" }, { "wipe", "#ff4030" }, { "fall", "#c8a0a0" }, { "door", "#9fd89f" },
        };

        public static string AlertColor(string kind) => kind != null && AlertColors.TryGetValue(kind, out var c) ? c : "#f6cf72";
        public static double AlertSeconds(string kind) => kind == "kill" || kind == "wipe" || kind == "pull" ? 6 : 4;

        public static string LootSummary(object d)
        {
            if (!Json.Truthy(d, "eligible")) return Loc.T("{0} slain. You looted it already this week: no spoils until the reset.", Json.Text(d, "boss", "?"));
            return Loc.T("Spoils of {0}: {1}", Json.Text(d, "boss", "?"), string.Join(", ", Eg.Strings(d, "lines")));
        }
    }

    public sealed class RaidState : EgModule
    {
        public const byte Opcode = 213;
        protected override byte Op => Opcode;

        public bool Visible;
        public object Info;
        public List<object> JournalBosses = new List<object>();
        public string Tab = "raids";
        public string Message = "";
        public bool MessageOk;
        public object Hud;
        public double HudAt;
        public readonly EgCallout Callout = new EgCallout();

        public RaidState(ExtOpcodes e) : base(e) { ext.On(Opcode, m => Handle(m.Action, Eg.DataOf(m))); }

        public void Query() { Send("query"); }
        public void Toggle() { if (Visible) Hide(); else Show(); }
        /// <summary>Shows the window at once and asks for the info.</summary>
        public void Show() { Visible = true; Message = ""; Send("open"); Changed(); }
        public void Start() { Send("start"); }
        public void Continue(int id) { Send("continue", D("id", id)); }
        public void Join(int id) { Send("join", D("id", id)); }
        public void Leave() { Send("leave"); }
        public void Buy(string key) { Send("buy", D("key", key)); }
        public void ShowTab(string tab) { Tab = tab; if (tab == "journal") Send("journal"); Changed(); }
        public void Hide() { Visible = false; }

        public void Handle(string action, object d)
        {
            switch (action)
            {
                case "info":
                    Info = d;
                    if (!Visible) Message = "";
                    Visible = true;
                    break;
                case "journal": JournalBosses = Json.Get(d, "bosses") as List<object> ?? new List<object>(); break;
                case "hud": Hud = d; HudAt = Now; break;
                case "alert": Callout.Show(Json.Text(d, "text"), Json.Text(d, "kind"), Now, RaidView.AlertSeconds(Json.Text(d, "kind"))); break;
                case "loot": { string k = Json.Truthy(d, "eligible") ? "kill" : "fall"; Callout.Show(RaidView.LootSummary(d), k, Now, RaidView.AlertSeconds(k)); break; }
                case "end": Callout.Show(Json.Text(d, "text"), "door", Now, RaidView.AlertSeconds("door")); Hud = null; break;
                case "msg":
                    if (Visible) { Message = Json.Text(d, "text"); MessageOk = Json.Truthy(d, "ok"); }
                    else if (Json.Text(d, "text").Length > 0) Notice(Json.Text(d, "text"));
                    break;
                case "closeInfo": Visible = false; break;
            }
            Changed();
        }

        /// <summary>Seconds of enrage left of the last hud message.</summary>
        public double EnrageLeft(double nowMs) => Hud == null ? 0 : Eg.Left(Json.Number(Hud, "enrage"), HudAt, nowMs);

        public void Clear() { Visible = false; Info = null; JournalBosses = new List<object>(); Hud = null; Message = ""; Callout.Clear(); Tab = "raids"; }
    }

    // ================================================================================================ Ember Descent
    public sealed class DescentRoom { public string Name, Color; }

    public static class DescentView
    {
        public static readonly Dictionary<string, string[]> Rooms = new Dictionary<string, string[]>
        {
            { "combat", new[] { "Combat", "#d6c9ae" } }, { "elite", new[] { "Elite", "#c79bff" } }, { "treasure", new[] { "Treasure", "#f6cf72" } },
            { "shrine", new[] { "Shrine", "#7fd0c0" } }, { "merchant", new[] { "Merchant", "#9fd89f" } }, { "boss", new[] { "Boss", "#ff6040" } },
        };

        static readonly string[] Roman = { "I", "II", "III", "IV", "V" };

        public static string RoomName(string kind) => kind != null && Rooms.TryGetValue(kind, out var r) ? r[0] : (kind ?? "");
        public static string RoomColor(string kind) => kind != null && Rooms.TryGetValue(kind, out var r) ? r[1] : "#d6c9ae";
        public static string RoomLine(object d) => d == null ? "" : Loc.T("Room {0} / {1} - {2}", Json.Int(d, "room"), Json.Int(d, "rooms"), Loc.T(RoomName(Json.Text(d, "type"))));

        public static int Progress(object d)
        {
            int rooms = Json.Int(d, "rooms");
            return rooms <= 0 ? 0 : (int)Math.Min(100, Math.Floor(Json.Number(d, "depth") * 100 / rooms));
        }

        public static string StateLine(object d)
        {
            if (d == null) return "";
            string s = Json.Text(d, "state"), type = Json.Text(d, "type");
            if (s == "choose") return Loc.T("Room cleared: choose a boon.");
            if (s == "travel") return Loc.T("The next door opens...");
            if (s == "done") return Loc.T("The descent is over.");
            if (s == "rest")
            {
                if (Json.Truthy(d, "ready")) return Loc.T("Waiting for the party...");
                if (type == "shrine") return Loc.T("Use the altar (health for a boon), then Continue.");
                if (type == "merchant") return Loc.T("Spend your embers at the stand, then Continue.");
                return Loc.T("Continue when you are ready.");
            }
            if (type == "boss") return Json.Get(d, "bossName") is string bn ? bn + " awaits." : Loc.T("The last hall.");
            int left = Json.Int(d, "monsters"), waves = Json.Int(d, "waves");
            if (waves > 0) return Loc.T(left == 1 ? "Wave {0} / {1} - {2} monster left" : "Wave {0} / {1} - {2} monsters left", Math.Max(1, Json.Int(d, "wave")), waves, left);
            return Loc.T(left == 1 ? "{0} monster left" : "{0} monsters left", left);
        }

        public static string EmbersLine(object d)
        {
            if (d == null) return "";
            string text = "Embers " + Eg.Number(Json.Number(d, "embers"));
            if (Json.Number(d, "reward") > 0) text += Loc.T("   Rewards +{0}%", Json.Int(d, "reward"));
            if (Json.Number(d, "ward") > 0) text += "   Ward " + Eg.Number(Json.Number(d, "ward"));
            return text;
        }

        public static string StacksText(double stacks, double max) => max <= 1 ? "" : Loc.T("Stack {0} of {1}", (long)stacks, (long)max);

        public static string Tooltip(object b, bool curse)
        {
            if (!(b is Dictionary<string, object>)) return "";
            string head = Json.Text(b, "n");
            if (curse) return head + " (curse)\n" + Json.Text(b, "d") + (Json.Number(b, "r") > 0 ? Loc.T("\nRewards +{0}%", Json.Int(b, "r")) : "");
            int m = Json.Get(b, "m") is double mm ? (int)mm : 1, s = Json.Get(b, "s") is double ss ? (int)ss : 1;
            string roman = m > 1 && s >= 1 && s <= Roman.Length ? Roman[s - 1] : null;
            return head + (roman != null ? " " + roman : "") + "\n" + Json.Text(b, "d");
        }

        public static string CardTitle(object c)
        {
            if (!(c is Dictionary<string, object>)) return "";
            int next = Json.Int(c, "s") + 1, max = Json.Get(c, "m") is double m ? (int)m : 1;
            if (max > 1 && next > 1) return Json.Text(c, "n") + " " + (next <= Roman.Length ? Roman[next - 1] : next.ToString(CultureInfo.InvariantCulture));
            return Json.Text(c, "n");
        }

        public static string CardNote(object c)
        {
            if (!(c is Dictionary<string, object>)) return "";
            int have = Json.Int(c, "s"), max = Json.Get(c, "m") is double m ? (int)m : 1;
            if (max <= 1) return Loc.T("Unique boon");
            if (have == 0) return Loc.T("New (stacks to {0})", max);
            return Loc.T("Held {0} of {1}", have, max);
        }

        public static string CurseLine(object c)
        {
            if (!(c is Dictionary<string, object>)) return "";
            var extra = new List<string>();
            if (Json.Number(c, "r") > 0) extra.Add(Loc.T("+{0}% rewards", Json.Int(c, "r")));
            if (Json.Number(c, "e") > 0) extra.Add(Loc.T("+{0} embers", Json.Int(c, "e")));
            return Json.Text(c, "n") + " - " + Json.Text(c, "d") + (extra.Count > 0 ? " (" + string.Join(", ", extra) + ")" : "");
        }

        public static bool Ware(object w, double embers, out string text)
        {
            text = "";
            if (!(w is Dictionary<string, object>)) return false;
            double price = Json.Number(w, "p");
            if (Json.Truthy(w, "off")) { text = Loc.T("Not needed"); return false; }
            text = Loc.T("{0} embers", (long)price);
            return embers >= price;
        }

        public sealed class Line { public string Text, Color; public Line(string t, string c) { Text = t; Color = c; } }

        public static List<Line> InfoLines(object info)
        {
            var lines = new List<Line>();
            if (!(info is Dictionary<string, object>)) return lines;
            var rooms = Json.List(info, "rooms");
            int lo = rooms.Count > 0 && rooms[0] is double a ? (int)a : 8, hi = rooms.Count > 1 && rooms[1] is double b ? (int)b : 12;
            lines.Add(new Line(Loc.T("{0}-{1} rooms, {2} minutes, up to {3} players. Level {4}+.", lo, hi, (int)Math.Floor(Json.Number(info, "timeLimit") / 60),
                Json.Get(info, "maxPlayers") is double mp ? (int)mp : 4, Json.Int(info, "minLevel")), "#8c8070"));
            int banked = (int)Math.Floor(Json.Number(info, "freeDailyCount"));
            if (Json.Truthy(info, "freeDaily") && banked > 1) lines.Add(new Line(Loc.T("Free descents: {0} ready (unused days bank up to 3)", banked), "#7fd07f"));
            else if (Json.Truthy(info, "freeDaily")) lines.Add(new Line(Loc.T("Free descent today: ready"), "#7fd07f"));
            else lines.Add(new Line(Loc.T("Free descent today: used (next in {0})", Eg.HoursMinutes(Json.Number(info, "nextDaily"))), "#8c8070"));
            lines.Add(new Line(Json.Truthy(info, "freeWeekly") ? Loc.T("Free weekly descent: ready") : Loc.T("Free weekly descent: used this week"), Json.Truthy(info, "freeWeekly") ? "#7fd07f" : "#8c8070"));
            var craft = Json.Get(info, "craft");
            int sigils = Json.Int(info, "sigils");
            lines.Add(new Line(Loc.T("{0}: {1} carried", Json.Get(craft, "name") is string cn ? cn : Loc.T("Ember Sigils"), sigils), sigils > 0 ? "#f6cf72" : "#8c8070"));
            lines.Add(new Line(Loc.T("Best depth: {0}{1}   Runs: {2}   Clears: {3}", Json.Int(info, "best"), Json.Truthy(info, "bestClear") ? " (conquered)" : "", Json.Int(info, "runs"), Json.Int(info, "clears")), "#e8b84a"));
            lines.Add(new Line(Loc.T("This week (seed {0}): best depth {1}", Json.Get(info, "weekSeed") is string ws ? ws : (Json.Get(info, "weekSeed") is double wd ? ((long)wd).ToString(CultureInfo.InvariantCulture) : "?"), Json.Int(info, "weekBest")), "#e8b84a"));
            return lines;
        }

        public static bool Craft(object info, out string text)
        {
            text = "";
            var c = Json.Get(info, "craft");
            if (!(c is Dictionary<string, object>)) return false;
            double shards = Json.Number(c, "shards"), gold = Json.Number(c, "gold"), hs = Json.Number(c, "haveShards"), hg = Json.Number(c, "haveGold");
            text = Loc.T("Forge: {0} rune shards ({1}) and {2} gold ({3})", (long)shards, (long)hs, Eg.Number(gold), Eg.Number(hg));
            return hs >= shards && hg >= gold;
        }

        public sealed class EntryButton { public bool Can; public string Text = ""; }

        /// <summary>The Descend and Weekly Descent buttons (free run first, then a sigil).</summary>
        public static void EntryButtons(object info, out EntryButton normal, out EntryButton weekly)
        {
            normal = new EntryButton { Text = Loc.T("Descend") }; weekly = new EntryButton { Text = Loc.T("Weekly Descent") };
            if (!(info is Dictionary<string, object>)) return;
            int sig = Json.Int(info, "sigils");
            bool lvl = Json.Int(info, "level") >= Json.Int(info, "minLevel"), inRun = Json.Truthy(info, "inRun");
            EntryButton One(bool free, string label)
            {
                var b = new EntryButton { Text = label };
                if (inRun || !lvl) return b;
                if (free) { b.Can = true; b.Text = label + Loc.T(" (free)"); }
                else if (sig > 0) { b.Can = true; b.Text = label + Loc.T(" (1 sigil)"); }
                return b;
            }
            normal = One(Json.Truthy(info, "freeDaily"), Loc.T("Descend"));
            weekly = One(Json.Truthy(info, "freeWeekly"), Loc.T("Weekly Descent"));
        }

        public sealed class EndView { public string Title = "", Color = "#d6c9ae"; public List<string> Lines = new List<string>(); }

        public static EndView EndLines(object d)
        {
            var e = new EndView();
            if (!(d is Dictionary<string, object>)) return e;
            string result = Json.Text(d, "result");
            switch (result)
            {
                case "cleared": e.Title = Loc.T("The Descent is conquered!"); e.Color = "#7fd07f"; break;
                case "fallen": e.Title = Loc.T("You fell in the Descent."); e.Color = "#ff6040"; break;
                case "time": e.Title = Loc.T("The embers burned out."); e.Color = "#ff9a30"; break;
                case "left": case "logout": e.Title = Loc.T("You left the Descent."); e.Color = "#8c8070"; break;
                case "shutdown": e.Title = Loc.T("The Descent closed for a restart."); e.Color = "#8c8070"; break;
                default: e.Title = Json.Text(d, "text"); break;
            }
            e.Lines.Add(Loc.T("Depth {0} of {1}", Json.Int(d, "depth"), Json.Int(d, "rooms")) + (Json.Truthy(d, "weekly") ? " " + Loc.T("(weekly)") : ""));
            if (Json.Number(d, "gold") > 0) e.Lines.Add(Loc.T("{0} gold to your bank", Eg.Number(Json.Number(d, "gold"))));
            foreach (object it in Json.List(d, "items"))
            {
                int count = Json.Get(it, "count") is double c ? (int)c : 1;
                e.Lines.Add((Json.Truthy(it, "unique") ? Loc.T("Unique: ") : "") + (count > 1 ? count + " " : "") + Json.Text(it, "name"));
            }
            if (Json.Get(d, "title") is string t) e.Lines.Add(Loc.T("New title: {0}", t));
            return e;
        }

        public static string PartyLine(object p)
        {
            if (!(p is Dictionary<string, object>)) return "";
            if (!Json.Truthy(p, "alive")) return Json.Text(p, "name", "?") + " (out)";
            return Json.Text(p, "name", "?") + " " + Json.Int(p, "hp") + "%";
        }
    }

    public sealed class DescentState : EgModule
    {
        public const byte Opcode = 205;
        public const double HideEndMs = 20000;
        protected override byte Op => Opcode;

        public bool InfoVisible, ShopVisible;
        public object Info, Hud, Offer, Shop;
        public double HudAt, OfferAt, EndShownAt = -1;
        public DescentView.EndView End;
        public string Message = "";

        public DescentState(ExtOpcodes e) : base(e) { ext.On(Opcode, m => Handle(m.Action, Eg.DataOf(m))); }

        public void Query() { Send("query"); }
        public void Toggle() { if (InfoVisible) InfoVisible = false; else ShowInfo(); }
        public void ShowInfo() { InfoVisible = true; Message = ""; Send("open"); Changed(); }
        public void HideInfo() { InfoVisible = false; }
        public void Start(bool weekly) { Send("start", D("weekly", weekly)); }
        public void Craft() { Send("craft"); }
        public void Ready() { Send("ready"); }
        public void Leave() { Send("leave"); }
        public void Buy(string key) { Send("buy", D("key", key)); }

        /// <summary>Pick the card (1-based), with the curse when the offer has one and the box is checked.</summary>
        public bool Pick(int index, bool takeCurse)
        {
            if (!(Offer is Dictionary<string, object>)) return false;
            bool ok = Send("pick", D("offer", Json.Get(Offer, "id"), "card", index, "curse", Json.Get(Offer, "curse") is Dictionary<string, object> && takeCurse));
            Offer = null;
            Changed();
            return ok;
        }

        public void Handle(string action, object d)
        {
            switch (action)
            {
                case "hud":
                    Hud = d; HudAt = Now; EndShownAt = -1; End = null;
                    break;
                case "offer": Offer = d; OfferAt = Now; break;
                case "closeOffer": if (!(Json.Get(d, "id") != null) || (Offer != null && Equals(Json.Get(Offer, "id"), Json.Get(d, "id")))) Offer = null; break;
                case "shop": Shop = d; ShopVisible = true; break;
                case "closeShop": ShopVisible = false; break;
                case "info": Info = d; if (!InfoVisible) Message = ""; InfoVisible = true; break;
                case "closeInfo": InfoVisible = false; break;
                case "msg":
                    if (InfoVisible) Message = Json.Text(d, "text"); else if (Json.Text(d, "text").Length > 0) Notice(Json.Text(d, "text"));
                    break;
                case "end": OnEnd(d); break;
            }
            Changed();
        }

        void OnEnd(object d)
        {
            Offer = null; ShopVisible = false;
            End = DescentView.EndLines(d);
            if (Hud == null) Hud = new Dictionary<string, object> { { "state", "done" }, { "room", Json.Number(d, "depth") }, { "rooms", Json.Number(d, "rooms") }, { "depth", Json.Number(d, "depth") }, { "type", "boss" }, { "left", 0.0 } };
            var h = (Dictionary<string, object>)Hud;
            h["state"] = "done"; h["depth"] = Json.Number(d, "depth");
            HudAt = Now;
            EndShownAt = Now;
        }

        public bool HudShown(double nowMs)
        {
            if (Hud == null) return false;
            if (EndShownAt >= 0 && nowMs - EndShownAt > HideEndMs) { Hud = null; End = null; EndShownAt = -1; return false; }
            return true;
        }

        /// <summary>Seconds of the run left, counted down from the last hud message.</summary>
        public double TimeLeft(double nowMs) => Hud == null ? 0 : Math.Max(0, Json.Number(Hud, "left") - Math.Max(0, (nowMs - HudAt) / 1000.0));
        public double OfferLeft(double nowMs) => Offer == null ? 0 : Math.Max(0, Json.Number(Offer, "timeout") - Math.Max(0, (nowMs - OfferAt) / 1000.0));

        public void Clear() { InfoVisible = ShopVisible = false; Info = Hud = Offer = Shop = null; End = null; EndShownAt = -1; Message = ""; }
    }

    // ================================================================================================ Invasions
    public static class InvasionView
    {
        public static string Countdown(double seconds)
        {
            long s = (long)Math.Max(0, Math.Floor(seconds));
            if (s <= 0) return "now";
            long d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60;
            if (d > 0) return "in " + d + "d " + h + "h";
            if (h > 0) return "in " + h + "h " + m.ToString("00", CultureInfo.InvariantCulture) + "m";
            return "in " + Math.Max(1, m) + "m";
        }

        public static string Title(object d) => Json.Text(d, "phase") == "occupied" ? Loc.T("{0} is occupied", Json.Text(d, "area", "?")) : "Invasion: " + Json.Text(d, "area", "?");

        public static List<object> Sides(object d) => Eg.Objects(d, "sides");

        public static string Subtitle(object d)
        {
            if (Json.Text(d, "phase") == "occupied") return Loc.T("Slay the occupiers to free it");
            var s = Sides(d);
            if (s.Count > 1) return Loc.T("{0} and {1} - defend {2}", Json.Text(s[0], "name", "?"), Json.Text(s[1], "name", "?"), Json.Text(d, "target", "the target"));
            return Loc.T("{0} - defend {1}", Json.Text(d, "faction", "A horde"), Json.Text(d, "target", "the target"));
        }

        public static List<KeyValuePair<string, string>> SideLines(object d)
        {
            var list = new List<KeyValuePair<string, string>>();
            foreach (object s in Sides(d))
            {
                int left = Json.Int(s, "left");
                string text = Json.Get(s, "boss") is string boss
                    ? Loc.T("{0}: {1} left, {2} {3}%", Json.Text(s, "name", "?"), left, boss, Json.Get(s, "bossHp") is double hp ? (int)hp : 100)
                    : Loc.T("{0}: {1} left", Json.Text(s, "name", "?"), left);
                list.Add(new KeyValuePair<string, string>(text, Eg.Hex(Json.Text(s, "color"), "#d6c9ae")));
            }
            return list;
        }

        public static string WaveLine(object d, double nextLeft)
        {
            int left = Json.Int(d, "left");
            if (Json.Text(d, "phase") == "occupied") return Loc.T(left == 1 ? "{0} occupier left" : "{0} occupiers left", left);
            if (Json.Int(d, "wave") == 0) return Loc.T("Wave 1 of {0} in {1}", Json.Int(d, "waves"), Eg.Clock(nextLeft));
            return Loc.T(left == 1 ? "Wave {0} of {1} - {2} invader left" : "Wave {0} of {1} - {2} invaders left", Json.Int(d, "wave"), Json.Int(d, "waves"), left);
        }

        public static string BreachColor(double b) => b >= 80 ? "#d01818" : b >= 50 ? "#d86a10" : "#b08a20";

        public static List<string> TopLines(object d)
        {
            var list = new List<string>();
            int i = 0;
            foreach (object o in Json.List(d, "top"))
            {
                i++;
                list.Add(i + ". " + (Json.Get(o, "name") is string n ? n : "nil") + "  " + Json.Int(o, "share") + "%");
            }
            return list;
        }

        public static string YouLine(object you)
        {
            if (!(you is Dictionary<string, object>)) return Loc.T("You: not in the defence yet");
            int kills = Json.Int(you, "kills");
            return Loc.T("You: #{0}, {1}% of the defence, {2} kill{3}", Json.Int(you, "rank"), Json.Int(you, "share"), kills, kills == 1 ? "" : "s");
        }

        public static string ResultColor(string result) => result == "win" || result == "liberated" ? "#7fd07f" : result == "withdrawn" ? "#d6c9ae" : "#ff5030";

        public static string KindColor(string kind)
        {
            switch (kind)
            {
                case "invasion": return "#e0603a"; case "storm": return "#b07aff"; case "merchant": return "#e8b84a"; case "golden": return "#f6cf72";
                case "buff": return "#7fd07f"; case "world": return "#a89c86"; default: return "#d6c9ae";
            }
        }
    }

    public sealed class InvasionState : EgModule
    {
        public const byte Opcode = 251;
        protected override byte Op => Opcode;

        public object Hud;
        public double HudAt;
        public bool Ended, Folded, CalendarVisible;
        public string ResultText = "", ResultColor = "#d6c9ae";
        public List<object> Calendar = new List<object>();

        public InvasionState(ExtOpcodes e) : base(e) { ext.On(Opcode, m => Handle(m.Action, Eg.DataOf(m))); }

        public void Query() { Send("query"); }
        public void Toggle() { if (CalendarVisible) HideCalendar(); else ShowCalendar(); }
        public void ShowCalendar() { CalendarVisible = true; Send("calendar", D("open", true)); Changed(); }
        public void HideCalendar() { CalendarVisible = false; }

        public void Handle(string action, object d)
        {
            switch (action)
            {
                case "hud":
                    Hud = d; HudAt = Now; Ended = false;
                    if (Json.Text(d, "phase") != "occupied") ResultText = "";
                    break;
                case "end":
                    if (Hud == null) Hud = new Dictionary<string, object> { { "phase", "running" }, { "wave", 0.0 }, { "waves", 0.0 } };
                    ((Dictionary<string, object>)Hud)["time"] = 0.0;
                    Ended = true;
                    ResultText = Json.Text(d, "text"); ResultColor = InvasionView.ResultColor(Json.Text(d, "result"));
                    break;
                case "hide": Hud = null; ResultText = ""; Ended = false; break;
                case "calendar":
                    Calendar = Eg.Objects(d, "list");
                    if (Json.Truthy(d, "open")) CalendarVisible = true;
                    break;
            }
            Changed();
        }

        public double TimeLeft(double nowMs) => Hud == null || Ended ? 0 : Eg.Left(Json.Number(Hud, "time"), HudAt, nowMs);
        public double NextLeft(double nowMs) => Hud == null ? 0 : Eg.Left(Json.Number(Hud, "next"), HudAt, nowMs);
        public bool HudShown => Hud != null;

        public void Clear() { Hud = null; Ended = false; CalendarVisible = false; ResultText = ""; Calendar = new List<object>(); }
    }
}
