// Tests of the endgame models (track L): Infinity Tower, Dungeons, raid, Ember Descent, the atlases, invasions, siege, arena, battleground, the
// Scorched Marches and the bounty board. Payloads follow the servers' contracts (server/data/scripts/chaos/*.lua headers) and the main client's
// view / math modules (client/overlay/modules/game_*/*view.lua, *math.lua, *text.lua, towerskip.lua).
using System;
using System.Collections.Generic;
using System.Text;

namespace Chaos.Core.Tests
{
    static class EndgameTests
    {
        sealed class Rig
        {
            public readonly ExtOpcodes Ext = new ExtOpcodes();
            public readonly List<byte[]> Sent = new List<byte[]>();
            public double Now;
            public readonly Endgame E;
            public double Unix = 1000000;
            public Rig()
            {
                Ext.Transmit = p => Sent.Add(p);
                E = new Endgame(Ext, () => Now, () => Unix);
            }
            public void In(byte op, string json) => Ext.Receive(op, ExtOpcodes.ToWire(json));
            public string Last() { var p = Sent[Sent.Count - 1]; return p[1] + " " + Encoding.UTF8.GetString(p, 4, p.Length - 4); }
        }

        public static void Run(Action<bool, string> check)
        {
            Loc.Set("en");
            Tower(check);
            Dungeons(check);
            Raid(check);
            Descent(check);
            Atlas(check);
            Invasion(check);
            Siege(check);
            Arena(check);
            Battleground(check);
            PvpZone(check);
            Bounty(check);
            Menu(check);
            Strings(check);
            Loc.Set("en");
        }

        // ------------------------------------------------------------------------------------ Infinity Tower
        static void Tower(Action<bool, string> check)
        {
            var r = new Rig();
            var t = r.E.Tower;
            r.E.Start();
            check(r.Sent.Count >= 1 && r.Sent[0][1] == 214 && Encoding.UTF8.GetString(r.Sent[0], 4, r.Sent[0].Length - 4) == "{\"action\":\"state\"}", "tower: the state is asked flat on start");
            check(!t.View().Visible && t.Panel(0) == null, "tower: no panel outside a run");
            r.Now = 10000;
            r.In(214, "{\"action\":\"state\",\"inRun\":true,\"canSkip\":false,\"floor\":4,\"nextBoss\":true,\"isLeader\":true,\"cleared\":3,\"waiting\":false,\"remaining\":5,\"total\":12,\"boss\":false,\"floorLeft\":90}");
            var v = t.View();
            check(v.Visible && !v.Enabled && v.Tip == "A boss floor is next: it starts by itself.", "tower: a boss floor next gives the boss tip");
            var p = t.Panel(10000);
            check(p.Floor == "Floor 4" && p.Cleared == "Floors cleared: 3" && p.Monsters == "Monsters left: 5 of 12" && p.Timer == "Floor time left: 1:30", "tower: panel floor, cleared, monsters, timer");
            check(t.Panel(40000).Timer == "Floor time left: 1:00", "tower: the floor timer counts on from the state");
            r.In(214, "{\"action\":\"state\",\"inRun\":true,\"canSkip\":false,\"floor\":5,\"isLeader\":false,\"waiting\":true,\"nextIn\":20,\"cleared\":4,\"boss\":true}");
            check(t.View().Tip == "Only the run leader can call the next floor." && t.Panel(10000).Floor == "Floor 5 (boss)" && t.Panel(10000).Timer == "Next floor in 20s" && t.Panel(15000).Timer == "Next floor in 15s", "tower: leader tip, boss floor title and the wait timer");
            r.In(214, "{\"action\":\"state\",\"inRun\":true,\"canSkip\":true,\"floor\":0,\"waiting\":true,\"nextIn\":3,\"isLeader\":true}");
            check(t.View().Enabled && t.Panel(10000).Floor == "Get ready", "tower: floor 0 reads Get ready and canSkip enables the button");
            r.Sent.Clear();
            r.Now = 20000;
            bool first = t.Skip();
            r.Now = 20500;
            bool tooSoon = t.Skip();
            check(first && !tooSoon && r.Last() == "50 {\"action\":\"skip\"}".Replace("50", "214"), "tower: skip goes out flat and not twice within a second");
            r.Now = 21500;
            check(t.CanPress(r.Now), "tower: skip allowed again after a second");
            // auto skip: not closer than 2 s
            t.AutoSkip = true;
            r.Sent.Clear();
            r.Now = 30000;
            t.LastSkipAt = double.NaN;
            r.In(214, "{\"action\":\"state\",\"inRun\":true,\"canSkip\":true,\"floor\":2,\"isLeader\":true}");
            check(r.Sent.Count == 1 && r.Last().EndsWith("{\"action\":\"skip\"}"), "tower: auto skip presses when the run waits");
            r.Now = 31000;
            r.In(214, "{\"action\":\"state\",\"inRun\":true,\"canSkip\":true,\"floor\":3,\"isLeader\":true}");
            check(r.Sent.Count == 1, "tower: auto skip keeps 2 s between presses");
            r.Now = 32500;
            r.In(214, "{\"action\":\"state\",\"inRun\":true,\"canSkip\":true,\"floor\":3,\"isLeader\":true}");
            check(r.Sent.Count == 2, "tower: auto skip again after the gap");
            t.AutoSkip = false;
            r.Sent.Clear();
            t.LastLeaveAt = double.NaN;
            check(t.LeaveRun() && r.Last().EndsWith("{\"action\":\"leave\"}") && !t.LeaveRun(), "tower: leave goes out once a second");
            r.In(214, "{\"action\":\"state\",\"inRun\":false}");
            check(!t.View().Visible && t.Panel(0) == null && !t.CanLeave(99999), "tower: leaving a run hides the panel");

            // the window
            t.Toggle();
            check(t.Visible && r.Last().EndsWith("{\"action\":\"request\"}"), "tower: toggle shows the window and asks");
            check(t.ShownMilestones().Count == 5 && t.ShownMilestones()[0].Points == 60000 && t.MaxPoints() == 300000, "tower: default milestones while loading");
            r.In(214, "{\"action\":\"update\",\"seasonNum\":3,\"seasonEnd\":1090000,\"nextTry\":1000030,\"playerPoints\":130000,\"milestones\":[{\"points\":60000,\"claimed\":true,\"items\":[{\"id\":3043,\"count\":30,\"name\":\"Gold Coin\"}]},{\"points\":120000,\"claimed\":false,\"items\":[{\"id\":51964,\"count\":1,\"name\":\"Prize\"}]},{\"points\":240000,\"claimed\":false,\"items\":[]}],\"rankings\":[{\"name\":\"Ana\",\"floor\":42,\"time\":605},{\"name\":\"Bo\",\"floor\":40,\"time\":590}],\"topRewards\":[{\"place\":1,\"name\":\"Gold Tower Chest\",\"id\":2478}],\"floorRewards\":{\"every\":5,\"paid\":10,\"nextFloor\":15,\"first\":[{\"id\":1,\"count\":2,\"name\":\"Orb\"}],\"repeatable\":[{\"id\":3043,\"count\":9,\"name\":\"Gold Coin\"}]}}");
            check(t.SeasonNum == 3 && t.PlayerPoints == 130000 && t.Milestones.Count == 3 && t.Rankings.Count == 2 && t.Rankings[0].Floor == 42, "tower: update fills season, points, milestones, rankings");
            check(!t.CanClaim(1) && t.CanClaim(2) && !t.CanClaim(3) && !t.CanClaim(4), "tower: claim needs enough points and an open milestone");
            check(Math.Abs(t.PointsRatio() - 130000.0 / 240000.0) < 1e-9, "tower: the bar fills against the last milestone");
            r.Sent.Clear();
            t.Claim(2);
            check(r.Last() == "214 {\"action\":\"claim\",\"milestoneIndex\":2}", "tower: claim sends the 1-based index flat");
            check(t.NextRewardText() == "Next reward: floor 15\nFirst clear this season: 2 Orb\nEvery clear: 9 Gold Coin", "tower: next reward text");
            check(t.SeasonEndText() == "Season Ends In: 1 days, 01:00:00" || t.SeasonEndText().StartsWith("Season Ends In: 1 days"), "tower: the season end counts down with days");
            check(t.NextTryText() == "Next Try Available: 00:00:30", "tower: next try countdown");
            r.Unix = 1000100;
            check(t.NextTryText() == "Next Try Available: Ready Now!", "tower: next try ready");
            check(TowerState.Place(1) == "#FFD700" && TowerState.Place(4) == "#FFFFFF", "tower: podium colours");
            r.Sent.Clear();
            t.Enter();
            check(r.Last().EndsWith("{\"action\":\"enter\"}") && !t.Visible, "tower: Enter sends and closes");
        }

        // ------------------------------------------------------------------------------------ Dungeons
        static void Dungeons(Action<bool, string> check)
        {
            var r = new Rig();
            var d = r.E.Dungeons;
            d.Fetch();
            check(r.Last() == "109 {\"action\":\"fetch\",\"data\":{}}", "dungeons: fetch on start");
            r.In(109, "{\"action\":\"list\",\"data\":[{\"id\":2,\"title\":\"The Marrow Crypts\",\"level\":300,\"boss\":{\"type\":12},\"queue\":4},{\"id\":1,\"title\":\"Bones Dungeon\",\"level\":150,\"boss\":{\"type\":10},\"queue\":0}]}");
            check(d.Rows.Count == 2 && d.Rows[0].Id == 1 && d.Rows[1].Level == 300 && d.SelectedId == 1, "dungeons: the list is sorted by level and the first is selected");
            check(Eg.QueueColor(0) == "#7fd07f" && Eg.QueueColor(3) == "#f6a030" && Eg.QueueColor(6) == "#e03a1e", "dungeons: queue colours at 3 and 6");
            check(DungeonsView.QueueText(0) == "Queue: Open" && DungeonsView.QueueText(4) == "Queue: 4 Players", "dungeons: queue text");
            r.In(109, "{\"action\":\"dungeon\",\"data\":{\"id\":1,\"title\":\"Bones Dungeon\",\"difficulty\":3,\"req\":{\"level\":150},\"loot\":[],\"queue\":{\"players\":2,\"estimated\":65000},\"challenges\":[{\"title\":\"Speed\",\"points\":50,\"completed\":false,\"desc\":\"Be fast\"}]}}");
            var det = d.Selected;
            check(det != null && det.Difficulty == 3 && det.QueuePlayers == 2 && det.QueueEstimatedMs == 65000, "dungeons: the detail keeps difficulty and queue");
            check(d.Unlocked(1) && d.Unlocked(3) && !d.Unlocked(4), "dungeons: difficulties above the unlocked one are locked");
            r.In(109, "{\"action\":\"solo\",\"data\":{\"id\":1,\"diff\":1,\"top\":[{\"name\":\"Ana\",\"time\":61234}]}}");
            check(det.Solo[1].Count == 1, "dungeons: solo runners by difficulty");
            r.In(109, "{\"action\":\"difficulty\",\"data\":{\"id\":1,\"difficulty\":5}}");
            check(det.Difficulty == 5 && d.Unlocked(5), "dungeons: a difficulty message unlocks a level");
            d.SelectDifficulty(5);
            r.Sent.Clear();
            d.JoinQueue();
            check(r.Last() == "109 {\"action\":\"queue\",\"data\":{\"id\":1,\"difficulty\":5}}", "dungeons: queue sends id and difficulty");
            r.Now = 5000;
            r.In(109, "{\"action\":\"queue\",\"data\":{\"id\":1,\"joined\":true}}");
            r.Now = 12000;
            check(d.QueuedId == 1 && d.QueueWaitedSeconds(r.Now) == 7, "dungeons: the queue wait counts seconds");
            r.In(109, "{\"action\":\"queueUpdate\",\"data\":{\"id\":1,\"queue\":7,\"estimated\":120000}}");
            check(det.QueuePlayers == 7 && d.Rows.Find(x => x.Id == 1).Queue == 7, "dungeons: queue updates reach the list and the detail");
            d.Show();
            r.In(109, "{\"action\":\"prepare\"}");
            check(d.QueuedId == 0 && !d.Visible, "dungeons: prepare stops the queue and closes the window");
            r.Now = 20000;
            r.In(109, "{\"action\":\"start\",\"data\":{\"boss\":\"Bonelord\",\"left\":40,\"duration\":600000,\"objectives\":[\"No deaths\",\"Fast\"],\"need\":80}}");
            check(d.Counter && d.BossName == "Bonelord" && d.Need == 80 && d.Objectives.Count == 2 && d.MonstersLeft == 40, "dungeons: start opens the kill counter");
            check(d.CounterLeftMs(30000) == 590000, "dungeons: the time left counts down");
            r.In(109, "{\"action\":\"killed\",\"data\":{\"percent\":50,\"left\":20}}");
            check(d.Percent == 50 && !d.BossUnlocked && d.MonstersLeft == 20, "dungeons: kills move the percent");
            r.In(109, "{\"action\":\"killed\",\"data\":{\"unlocked\":true,\"percent\":120,\"left\":5}}");
            check(d.Percent == 100 && d.BossUnlocked && d.Banner == "Boss unlocked!" && d.BannerActive(r.Now), "dungeons: the boss unlocks with a banner and the percent is capped");
            r.In(109, "{\"action\":\"objective\",\"data\":{\"id\":1,\"finished\":true}}");
            check(!d.ObjectivesDone[0] && d.ObjectivesDone[1], "dungeons: a bonus objective is ticked");
            r.In(109, "{\"action\":\"killed\",\"data\":{\"boss\":true}}");
            check(d.BossKilled && d.Banner == "You completed the dungeon!", "dungeons: the boss kill completes the dungeon");
            r.In(109, "{\"action\":\"challenge\",\"data\":\"Speed\"}");
            check(d.Banner == "Speed challenge completed!", "dungeons: a challenge banner");
            r.In(109, "{\"action\":\"finish\"}");
            check(!d.Counter, "dungeons: finish hides the counter");
            r.In(109, "{\"action\":\"open\"}");
            check(d.Visible, "dungeons: open shows the window");
            // view text
            check(DungeonsView.PanelText(2, null) == "Monster Health 200%\nMonster Damage 130%\nBonus XP +75%\nGold Drop +75%", "dungeons: the default panel text");
            var health = Json.Parse("{\"monsters\":[100,150,250,400,700,1000],\"boss\":[100,120,300,500,900,1500]}");
            check(DungeonsView.PanelText(3, health) == "Monster Health 250%\nBoss Health 300%\nMonster Damage 190%\nBonus XP +100%\nGold Drop +100%\nLoot Chance +15%", "dungeons: the panel text with the server's health curves");
            check(DungeonsView.PanelText(9, null).StartsWith("Monster Health 1300%") && DungeonsView.Clamp(0) == 1, "dungeons: the difficulty is clamped");
            check(DungeonsView.MsToShortTime(61234) == "01:01.2" && DungeonsView.MsToShortTime(0) == "00:00.000" && DungeonsView.SecondsToShortTime(3725) == "01:02:05", "dungeons: time formats");
            check(DungeonsView.WeeklyTitle(Json.Parse("{\"label\":\"W12\",\"theme\":\"Crucible\"}")) == "Weekly Challenge W12: Crucible", "dungeons: the weekly title");
            check(DungeonsView.WeeklyText(Json.Parse("{\"label\":\"W12\",\"current\":false}")).Contains("last week's"), "dungeons: the weekly text for an old layout");
            check(Eg.Span(90061) == "1d 1h" && Eg.Span(3700) == "1h 01m" && Eg.Span(300) == "5m", "dungeons: span formats");
        }

        // ------------------------------------------------------------------------------------ Raid
        static void Raid(Action<bool, string> check)
        {
            var r = new Rig();
            var s = r.E.Raid;
            s.Query();
            check(r.Last() == "213 {\"action\":\"query\",\"data\":{}}", "raid: query on start");
            r.In(213, "{\"action\":\"info\",\"data\":{\"level\":900,\"minLevel\":800,\"maxPlayers\":15,\"marks\":1234,\"kills\":7,\"clears\":2,\"best\":845,\"lock\":{\"looted\":1,\"total\":3,\"reset\":93700,\"bosses\":[{\"n\":\"Ash\",\"l\":true},{\"n\":\"Cinder\",\"l\":false}]},\"saved\":[{\"id\":5,\"leader\":\"Ana\",\"done\":1,\"killed\":[true,false,false],\"next\":\"Cinder\",\"open\":true},{\"id\":6,\"leader\":\"Bo\",\"done\":3,\"killed\":[true,true,true],\"cleared\":true}],\"vendor\":[{\"key\":\"k1\",\"n\":\"Helm\",\"kind\":\"gear\",\"rarity\":4,\"level\":125,\"mods\":[\"+1\",\"+2\"],\"price\":100,\"bought\":0,\"weekly\":1}]}}");
            check(s.Visible, "raid: info opens the window");
            check(RaidView.LockSummary(s.Info) == "1 of 3 bosses looted this week. Lockouts reset in 1d 2h." && Eg.ResetText(3700) == "1h 1m", "raid: lock summary and reset text");
            var rows = RaidView.LockRows(s.Info);
            check(rows.Count == 2 && rows[0].Looted && rows[0].Text == "1. Ash" && rows[1].State == "Loot available", "raid: lock rows");
            var saved = Eg.Objects(s.Info, "saved");
            var a = RaidView.SavedRow(saved[0]);
            check(a.Action == "join" && a.Progress == "1 / 3 slain  [X--]" && a.Next == "Next: Cinder" && a.Title == "Raid #5 (Ana)", "raid: a saved raid that is open offers Join");
            var b = RaidView.SavedRow(saved[1]);
            check(b.Action == "" && b.Next == "Cleared", "raid: a cleared saved raid has no button");
            check(RaidView.StartState(s.Info, out string why) && why.Contains("15"), "raid: can start at the level");
            check(!RaidView.StartState(Json.Parse("{\"level\":700,\"minLevel\":800}"), out why) && why == "Level 800 needed.", "raid: the level gate text");
            check(!RaidView.StartState(Json.Parse("{\"inRaid\":true}"), out why) && why == "You are inside a raid.", "raid: in a raid cannot start");
            check(RaidView.RecordLine(s.Info) == "Sepulchre Marks: 1,234   Bosses looted: 7   Full clears: 2   Best clear: 14:05", "raid: record line");
            var vr = RaidView.VendorRow(Eg.Objects(s.Info, "vendor")[0], 1234);
            check(vr.Can && vr.Button == "100 marks" && vr.Sub == "Rare, item level 125: +1, +2" && vr.Limit == "0 / 1 this week", "raid: a vendor row");
            check(!RaidView.VendorRow(Eg.Objects(s.Info, "vendor")[0], 50).Can, "raid: not enough marks");
            r.Sent.Clear();
            s.Continue(5); s.Join(5); s.Start(); s.Buy("k1"); s.Leave(); s.ShowTab("journal");
            check(r.Sent.Count == 6 && r.Last() == "213 {\"action\":\"journal\",\"data\":{}}", "raid: requests go out");
            check(Encoding.UTF8.GetString(r.Sent[0], 4, r.Sent[0].Length - 4) == "{\"action\":\"continue\",\"data\":{\"id\":5}}" && Encoding.UTF8.GetString(r.Sent[3], 4, r.Sent[3].Length - 4) == "{\"action\":\"buy\",\"data\":{\"key\":\"k1\"}}", "raid: continue and buy payloads");
            r.In(213, "{\"action\":\"journal\",\"data\":{\"bosses\":[{\"n\":\"Ash\",\"final\":true,\"intro\":\"Hi\",\"roles\":\"tank\",\"enrage\":300,\"phases\":[{\"n\":\"One\",\"at\":100}],\"mech\":[\"Cleave\"],\"loot\":{\"gold\":5000,\"marks\":3,\"items\":[{\"id\":29856,\"count\":2}],\"gearRolls\":2,\"gearLevel\":[120,130],\"gear\":[1,2],\"unique\":150,\"uniques\":[\"Blade\"]}}]}}");
            var jb = RaidView.Journal(s.JournalBosses[0], 1);
            check(jb.Title == "1. Ash (final)" && jb.Phases == "Phases: One (100%). Enrage at 5:00." && jb.Mech[0] == "- Cleave", "raid: journal title and phases");
            check(jb.Loot[0] == "5,000 gold to the bank, 3 Sepulchre Marks" && jb.Loot[1].StartsWith("2 Orbs of Upheaval") && jb.Loot[2] == "2 gear rolls, item level 120-130 (2 base items)" && jb.Loot[3] == "1.5% chance of a raid unique: Blade", "raid: journal loot lines");
            r.Now = 100000;
            r.In(213, "{\"action\":\"hud\",\"data\":{\"raid\":\"Ashen Sepulchre\",\"id\":5,\"state\":\"fight\",\"idx\":2,\"boss\":\"Cinder\",\"hp\":64,\"phase\":2,\"phases\":3,\"phaseName\":\"Embers\",\"enrage\":120,\"done\":1,\"total\":3,\"players\":4,\"fallen\":1,\"adds\":3,\"stacks\":{\"sunder\":2,\"hexed\":0},\"hexed\":7}}");
            var h = s.Hud;
            check(RaidView.HudTitle(h) == "Ashen Sepulchre #5" && RaidView.BossLine(h) == "2. Cinder - 64%" && RaidView.PhaseLine(h) == "Phase 2 of 3: Embers" && RaidView.Progress(h) == 33, "raid: hud title, boss, phase, progress");
            check(RaidView.CountsLine(h) == "Raiders 4, fallen 1, adds 3" && RaidView.StacksLine(h) == "Sundered x2   WITHERING HEX 7s: cleanse!", "raid: counts and stacks");
            check(s.EnrageLeft(130000) == 90, "raid: the enrage counts down from the message");
            check(RaidView.EnrageText(h, 50, out string col) == "Enrage 0:50" && col == "#ff9a30" && RaidView.EnrageText(h, 90, out col) == "Enrage 1:30" && col == "#f4d27a", "raid: enrage colours at 60 s");
            check(RaidView.BossLine(Json.Parse("{\"state\":\"corridor\",\"idx\":1,\"boss\":\"Ash\",\"trash\":4}")) == "1. Ash - clear the corridor (4 left)" && RaidView.BossLine(Json.Parse("{\"state\":\"clear\"}")) == "Every boss is slain.", "raid: boss line states");
            r.In(213, "{\"action\":\"alert\",\"data\":{\"text\":\"Spread out\",\"kind\":\"mech\"}}");
            check(s.Callout.Active(r.Now) && s.Callout.Text == "Spread out" && RaidView.AlertColor("mech") == "#f6cf72" && !s.Callout.Active(r.Now + 4001), "raid: an alert shows for 4 s");
            r.In(213, "{\"action\":\"loot\",\"data\":{\"boss\":\"Ash\",\"eligible\":true,\"lines\":[\"500 gold\",\"1 orb\"]}}");
            check(s.Callout.Text == "Spoils of Ash: 500 gold, 1 orb" && s.Callout.Kind == "kill" && s.Callout.Active(r.Now + 5999), "raid: loot call-out lasts 6 s");
            r.In(213, "{\"action\":\"loot\",\"data\":{\"boss\":\"Ash\",\"eligible\":false}}");
            check(s.Callout.Text.Contains("looted it already") && s.Callout.Kind == "fall", "raid: an ineligible loot call-out");
            r.In(213, "{\"action\":\"end\",\"data\":{\"text\":\"The raid ends.\"}}");
            check(s.Hud == null && s.Callout.Text == "The raid ends.", "raid: end hides the hud");
            r.In(213, "{\"action\":\"msg\",\"data\":{\"text\":\"Not now\",\"ok\":false}}");
            check(s.Message == "Not now" && !s.MessageOk, "raid: a message shows in the open window");
            r.In(213, "{\"action\":\"closeInfo\"}");
            string noticed = null;
            s.Notice = t => noticed = t;
            r.In(213, "{\"action\":\"msg\",\"data\":{\"text\":\"Refused\"}}");
            check(!s.Visible && noticed == "Refused", "raid: closeInfo hides it and a message with the window closed goes to the log");
        }

        // ------------------------------------------------------------------------------------ Descent
        static void Descent(Action<bool, string> check)
        {
            var r = new Rig();
            var s = r.E.Descent;
            r.In(205, "{\"action\":\"info\",\"data\":{\"rooms\":[8,12],\"timeLimit\":900,\"maxPlayers\":4,\"minLevel\":100,\"level\":150,\"freeDaily\":true,\"freeDailyCount\":2,\"freeWeekly\":false,\"sigils\":1,\"craft\":{\"name\":\"Ember Sigils\",\"shards\":10,\"gold\":5000,\"haveShards\":12,\"haveGold\":4000},\"best\":7,\"bestClear\":false,\"runs\":12,\"clears\":1,\"weekSeed\":\"W9\",\"weekBest\":5}}");
            check(s.InfoVisible, "descent: info opens the window");
            var lines = DescentView.InfoLines(s.Info);
            check(lines[0].Text == "8-12 rooms, 15 minutes, up to 4 players. Level 100+." && lines[1].Text == "Free descents: 2 ready (unused days bank up to 3)" && lines[2].Text == "Free weekly descent: used this week", "descent: info lines");
            check(lines[3].Text == "Ember Sigils: 1 carried" && lines[4].Text == "Best depth: 7   Runs: 12   Clears: 1" && lines[5].Text == "This week (seed W9): best depth 5", "descent: sigils, best, week");
            check(!DescentView.Craft(s.Info, out string craft) && craft == "Forge: 10 rune shards (12) and 5,000 gold (4,000)", "descent: the forge needs the gold");
            DescentView.EntryButtons(s.Info, out var normal, out var weekly);
            check(normal.Can && normal.Text == "Descend (free)" && weekly.Can && weekly.Text == "Weekly Descent (1 sigil)", "descent: entry buttons use the free run, then a sigil");
            DescentView.EntryButtons(Json.Parse("{\"level\":50,\"minLevel\":100,\"freeDaily\":true}"), out normal, out weekly);
            check(!normal.Can && !weekly.Can, "descent: below the level nothing enters");
            r.Sent.Clear();
            s.Start(true);
            check(r.Last() == "205 {\"action\":\"start\",\"data\":{\"weekly\":true}}", "descent: start sends weekly");
            r.Now = 1000;
            r.In(205, "{\"action\":\"hud\",\"data\":{\"weekly\":false,\"room\":3,\"rooms\":10,\"type\":\"elite\",\"state\":\"fight\",\"depth\":2,\"monsters\":1,\"waves\":2,\"wave\":2,\"embers\":1200,\"reward\":15,\"ward\":300,\"left\":125,\"boons\":[{\"k\":\"fury\",\"n\":\"Fury\",\"d\":\"+dmg\",\"s\":2,\"m\":3}],\"curses\":[{\"k\":\"frail\",\"n\":\"Frail\",\"d\":\"-hp\",\"r\":10}],\"party\":[{\"name\":\"Ana\",\"alive\":true,\"hp\":80},{\"name\":\"Bo\",\"alive\":false}]}}");
            var h = s.Hud;
            check(DescentView.RoomLine(h) == "Room 3 / 10 - Elite" && DescentView.RoomColor("elite") == "#c79bff" && DescentView.Progress(h) == 20, "descent: room line, colour, progress");
            check(DescentView.StateLine(h) == "Wave 2 / 2 - 1 monster left" && DescentView.EmbersLine(h) == "Embers 1,200   Rewards +15%   Ward 300", "descent: state and embers lines");
            check(DescentView.PartyLine(Json.List(h, "party")[0]) == "Ana 80%" && DescentView.PartyLine(Json.List(h, "party")[1]) == "Bo (out)", "descent: party lines");
            check(DescentView.Tooltip(Json.List(h, "boons")[0], false) == "Fury II\n+dmg" && DescentView.Tooltip(Json.List(h, "curses")[0], true) == "Frail (curse)\n-hp\nRewards +10%", "descent: boon and curse tooltips");
            check(s.TimeLeft(11000) == 115 && s.HudShown(11000), "descent: the run clock counts down");
            check(DescentView.StateLine(Json.Parse("{\"state\":\"rest\",\"type\":\"shrine\"}")) == "Use the altar (health for a boon), then Continue." && DescentView.StateLine(Json.Parse("{\"state\":\"rest\",\"ready\":true}")) == "Waiting for the party...", "descent: rest lines");
            r.In(205, "{\"action\":\"offer\",\"data\":{\"id\":77,\"room\":3,\"rooms\":10,\"source\":\"shrine\",\"timeout\":30,\"cards\":[{\"k\":\"fury\",\"n\":\"Fury\",\"d\":\"+dmg\",\"s\":1,\"m\":3},{\"k\":\"ward\",\"n\":\"Ward\",\"d\":\"+ward\",\"s\":0,\"m\":1}],\"curse\":{\"k\":\"frail\",\"n\":\"Frail\",\"d\":\"-hp\",\"r\":10,\"e\":50}}}");
            var cards = Json.List(s.Offer, "cards");
            check(DescentView.CardTitle(cards[0]) == "Fury II" && DescentView.CardNote(cards[0]) == "Held 1 of 3" && DescentView.CardNote(cards[1]) == "Unique boon" && DescentView.CurseLine(Json.Get(s.Offer, "curse")) == "Frail - -hp (+10% rewards, +50 embers)", "descent: card titles, notes and the curse line");
            check(s.OfferLeft(11000) == 20, "descent: the offer timer");
            r.Sent.Clear();
            s.Pick(2, true);
            check(r.Last() == "205 {\"action\":\"pick\",\"data\":{\"offer\":77,\"card\":2,\"curse\":true}}" && s.Offer == null, "descent: pick sends the offer, the card and the curse flag");
            r.In(205, "{\"action\":\"offer\",\"data\":{\"id\":78,\"cards\":[{\"k\":\"a\",\"n\":\"A\",\"d\":\"\"}]}}");
            r.In(205, "{\"action\":\"closeOffer\",\"data\":{\"id\":78}}");
            check(s.Offer == null, "descent: closeOffer with the id closes it");
            r.In(205, "{\"action\":\"shop\",\"data\":{\"embers\":500,\"wares\":[{\"k\":\"heal\",\"n\":\"Heal\",\"d\":\"+hp\",\"p\":300},{\"k\":\"x\",\"n\":\"X\",\"p\":900},{\"k\":\"y\",\"n\":\"Y\",\"p\":10,\"off\":true}]}}");
            var wares = Json.List(s.Shop, "wares");
            check(s.ShopVisible && DescentView.Ware(wares[0], 500, out string t0) && t0 == "300 embers" && !DescentView.Ware(wares[1], 500, out _) && !DescentView.Ware(wares[2], 500, out string t2) && t2 == "Not needed", "descent: ware prices and the not-needed ware");
            r.In(205, "{\"action\":\"end\",\"data\":{\"result\":\"cleared\",\"depth\":10,\"rooms\":10,\"weekly\":true,\"gold\":50000,\"items\":[{\"name\":\"Ember Blade\",\"unique\":true},{\"name\":\"Orb\",\"count\":3}],\"title\":\"Ember Walker\"}}");
            check(s.End.Title == "The Descent is conquered!" && s.End.Color == "#7fd07f" && s.End.Lines[0] == "Depth 10 of 10 (weekly)" && s.End.Lines[1] == "50,000 gold to your bank" && s.End.Lines[2] == "Unique: Ember Blade" && s.End.Lines[3] == "3 Orb" && s.End.Lines[4] == "New title: Ember Walker", "descent: the end result text");
            check(s.HudShown(r.Now + 19000) && !s.HudShown(r.Now + 21000) && s.Hud == null, "descent: the result hud hides after 20 s");
            r.In(205, "{\"action\":\"hud\",\"data\":{\"room\":1,\"rooms\":8,\"type\":\"combat\",\"state\":\"rest\",\"left\":900}}");
            r.In(205, "{\"action\":\"msg\",\"data\":{\"text\":\"Full\"}}");
            check(s.Message == "Full", "descent: a message in the open info window");
        }

        // ------------------------------------------------------------------------------------ Atlas
        const string TreeJson = "{\"action\":\"tree\",\"data\":{\"start\":1,\"keystoneMax\":1,\"branches\":[{\"k\":\"abyss\",\"th\":\"Abyssal Rift\",\"c\":\"#6a4aa0\"}],"
            + "\"nodes\":[{\"i\":1,\"k\":\"start\",\"c\":0,\"n\":\"Core\",\"x\":0,\"y\":0,\"l\":[2,3]},{\"i\":2,\"k\":\"small\",\"c\":1,\"n\":\"Density\",\"g\":\"density\",\"x\":100,\"y\":0,\"l\":[1,4],\"t\":[\"+5% monsters\"]},"
            + "{\"i\":3,\"k\":\"notable\",\"c\":2,\"n\":\"Elite\",\"g\":\"theme\",\"b\":\"Abyssal Rift\",\"x\":-100,\"y\":50,\"l\":[1]},{\"i\":4,\"k\":\"keystone\",\"c\":3,\"n\":\"Crown\",\"x\":200,\"y\":100,\"l\":[2]},{\"i\":5,\"k\":\"keystone\",\"c\":1,\"n\":\"Far\",\"x\":300,\"y\":100,\"l\":[4]}],"
            + "\"grid\":{\"tiers\":2,\"themes\":[\"Abyssal Rift\"],\"points\":{\"cell\":2,\"flawless\":3,\"swift\":4,\"omen\":5},\"swift\":600,\"swiftTiers\":[300,400],\"omens\":[{\"k\":\"ash\",\"n\":\"Ash\",\"b\":\"Ash Lord\"}]}}}";

        static void Atlas(Action<bool, string> check)
        {
            var r = new Rig();
            var a = r.E.RiftAtlas;
            a.Open();
            check(a.Visible && r.Last() == "210 {\"action\":\"open\",\"data\":{\"tree\":true}}", "atlas: open asks for the tree when it has none");
            r.In(210, TreeJson);
            check(a.Tree != null && a.Ix.List.Count == 5 && a.Ix.Pairs.Count == 4 && a.Ix.Start == 1, "atlas: the tree is indexed and links are unique pairs");
            r.In(210, "{\"action\":\"state\",\"data\":{\"earned\":4,\"spent\":1,\"points\":2,\"max\":40,\"alloc\":[2],\"done\":[\"c1.1\",\"f1\"],\"refund\":{\"gold\":50000,\"orbs\":1},\"orb\":\"Orb\",\"totals\":[\"+5% monsters\"],\"msg\":\"Allocated.\"}}");
            check(a.Alloc.Contains(2) && a.Done.Contains("c1.1") && a.StatusText == "Allocated." && AtlasView.PointsLine(a.State) == "2" && AtlasView.EarnedLine(a.State) == "Earned 4 / 40, spent 1", "atlas: the state fills allocation, done cells and the lines");
            check(a.StatusOf(1) == "start" && a.StatusOf(2) == "alloc" && a.StatusOf(3) == "avail" && a.StatusOf(4) == "reach" && a.StatusOf(5) == "locked", "atlas: node status (start, alloc, avail, reach, locked)");
            check(!a.CanAllocate(4, out string why) && why == "points" && !a.CanAllocate(5, out why) && why == "path" && !a.CanAllocate(2, out why) && why == "held" && !a.CanAllocate(1, out why) && why == "unknown" && a.CanAllocate(3, out why), "atlas: allocation rules");
            check(AtlasView.ReasonText("points") == "Not enough points: seal new rifts to earn more." && AtlasView.ReasonText("path") == "Not connected to your atlas yet.", "atlas: reason texts");
            a.Alloc.Add(4);
            a.State = Json.Parse("{\"points\":10}");
            check(!a.CanAllocate(5, out why) && why == "keystone", "atlas: only one keystone at a time");
            a.Alloc.Remove(4);
            check(a.CanRefund(2, out why) && !a.CanRefund(3, out why) && why == "not held", "atlas: refund needs a held node");
            a.Alloc.Add(4);
            check(!a.CanRefund(2, out why) && why == "path", "atlas: a node others depend on cannot be refunded");
            a.Alloc.Remove(4);
            check(AtlasView.LinkState(a.Ix, a.Alloc, 1, 2) == "Active" && AtlasView.LinkState(a.Ix, a.Alloc, 2, 4) == "Intermediate" && AtlasView.LinkState(a.Ix, a.Alloc, 4, 5) == "Normal", "atlas: link states");
            check(AtlasView.Glyph(a.Ix, a.Ix.ById[3]) == "theme_abyss" && AtlasView.Glyph(a.Ix, a.Ix.ById[2]) == "density", "atlas: the theme glyph uses the branch set");
            check(AtlasView.NodeSize("small", 1.0) == 27 && AtlasView.NodeSize("keystone", 0.3) == (int)Math.Floor(60 * (0.45 + 0.55 * 0.3) + 0.5), "atlas: node size follows the zoom");
            var w = a.World;
            check(w.W == 400 + 2 * 140 && w.Cx == 100 && w.Cy == 50, "atlas: the world box has the margin");
            AtlasView.ClampPan(9999, -9999, 0.5, w, 100, 100, out double px, out double py);
            check(px == w.W * 0.5 / 2 - 50 && py == -(w.H * 0.5 / 2 - 50), "atlas: the pan is clamped to the map");
            AtlasView.Place(w, a.Ix.ById[2], 1.0, out int x, out int y);
            check(x == 0 && y == -50, "atlas: node place from the world centre");
            check(a.ZoomIndex == 2 && a.Zoom == 0.4 && AtlasView.ZoomStep(1, -1) == 1 && AtlasView.ZoomStep(6, 1) == 6, "atlas: zoom steps stay in range");
            a.Center();
            check(a.PanX == 100 * a.Zoom && a.PanY == 50 * a.Zoom, "atlas: Center pans to the start node");
            check(AtlasView.KindLine(a.Ix.ById[3]) == "Notable, 2 points" && AtlasView.KindLine(a.Ix.ById[2]) == "Node, 1 point" && AtlasView.Tooltip(a.Ix.ById[2], "alloc") == "Density\nNode, 1 point\n+5% monsters\nAllocated.", "atlas: kind line and tooltip");
            check(AtlasView.Short(1500) == "1.5k" && AtlasView.Short(2000000) == "2M" && AtlasView.Short(12) == "12", "atlas: short numbers");
            AtlasView.RefundLabels(a.State, out string g, out string o);
            check(g == "Refund " + AtlasView.Short(Json.Number(Json.Get(a.State, "refund"), "gold")), "atlas: refund labels handle a state without a refund");
            a.State = Json.Parse("{\"points\":3,\"refund\":{\"gold\":50000,\"orbs\":1}}");
            AtlasView.RefundLabels(a.State, out g, out o);
            check(g == "Refund 50k" && o == "Refund 1 orb", "atlas: refund labels");
            r.Sent.Clear();
            a.Alloc = new HashSet<int> { 2 };
            a.Pick(3);
            check(a.AllocateSelected() && r.Last() == "210 {\"action\":\"alloc\",\"data\":{\"id\":3}}", "atlas: allocate the selected node");
            a.Pick(2);
            check(a.RefundSelected("orb") && r.Last() == "210 {\"action\":\"refund\",\"data\":{\"id\":2,\"pay\":\"orb\"}}", "atlas: refund with orbs");
            check(a.Reset("gold") && r.Last() == "210 {\"action\":\"reset\",\"data\":{\"pay\":\"gold\"}}", "atlas: reset");
            a.Pick(5);
            check(!a.AllocateSelected(), "atlas: a node out of reach is not sent");
            // the grid
            a.Done = new HashSet<string> { "c1.1", "f1", "oash" };
            var rows = a.Grid();
            AtlasView.GridCount(rows, out int done, out int total);
            check(rows.Count == 4 && rows[0].Label == "Abyss" && rows[0].Color == "#6a4aa0" && rows[0].Cells.Count == 2 && rows[0].Cells[0].Done && !rows[0].Cells[1].Done && total == 2 + 2 + 2 + 1 && done == 3, "atlas: the grid rows and the count");
            check(rows[2].Cells[1].Tip == "Swift tier 2 (sealed within 6:40): not yet (+4)" && rows[1].Cells[0].Tip == "Flawless tier 1 (no death): done (+3)" && rows[3].Cells[0].Name == "Ash", "atlas: grid tips use the swift times and the omen name");
            // chunked tree
            var r2 = new Rig();
            var w2 = r2.E.WaystoneAtlas;
            var parts = ExtChunks.Split(ExtOpcodes.ToWire(TreeJson), 200, 150);
            foreach (var part in parts) r2.Ext.Receive(159, part);
            check(parts.Count > 2 && w2.Tree != null && w2.Tree.Nodes.Count == 5 && r2.E.RiftAtlas.Tree == null, "atlas: a chunked tree reaches the right opcode only");
            r2.In(159, "{\"action\":\"state\",\"data\":{\"points\":1,\"done\":[\"w1\"],\"alloc\":[]}}");
            r2.In(159, "{\"action\":\"credit\",\"data\":{\"cells\":[\"A\",\"B\"],\"points\":4}}");
            check(w2.IsWaystone && w2.StatusText == "Completed: A, B (+4)" && w2.StatusColor == "#7fd07f", "atlas: a credit message");
            var lr = AtlasView.ListRows(new List<object> { Json.Parse("{\"label\":\"T1\",\"color\":\"#ffffff\",\"cells\":[{\"k\":\"w1\",\"n\":\"Wave\",\"p\":2,\"c\":1},{\"k\":\"w2\",\"n\":\"Wave 2\",\"p\":3}]}") }, w2.Done);
            check(lr[0].Cells[0].Done && lr[0].Cells[0].Tip == "Wave: done (+2)" && lr[0].Cells[1].Tip == "Wave 2: not yet (+3)", "atlas: waystone list rows");
            r2.Sent.Clear();
            w2.Open();
            check(r2.Last() == "159 {\"action\":\"open\",\"data\":{\"tree\":false}}", "atlas: a second open does not ask for the tree again");
        }

        // ------------------------------------------------------------------------------------ Invasion
        static void Invasion(Action<bool, string> check)
        {
            var r = new Rig();
            var s = r.E.Invasion;
            r.Now = 1000;
            r.In(251, "{\"action\":\"hud\",\"data\":{\"area\":\"Ash Town\",\"faction\":\"Ember Horde\",\"target\":\"the gate\",\"phase\":\"running\",\"wave\":0,\"waves\":5,\"next\":90,\"time\":600,\"left\":0,\"progress\":0,\"breach\":55,\"top\":[{\"name\":\"Ana\",\"share\":40}],\"you\":{\"rank\":2,\"share\":25,\"kills\":1}}}");
            var h = s.Hud;
            check(InvasionView.Title(h) == "Invasion: Ash Town" && InvasionView.Subtitle(h) == "Ember Horde - defend the gate", "invasion: title and subtitle");
            check(InvasionView.WaveLine(h, s.NextLeft(31000)) == "Wave 1 of 5 in 1:00" && s.TimeLeft(31000) == 570, "invasion: the first wave counts down");
            check(InvasionView.BreachColor(55) == "#d86a10" && InvasionView.BreachColor(80) == "#d01818" && InvasionView.BreachColor(10) == "#b08a20", "invasion: breach colours");
            check(InvasionView.TopLines(h)[0] == "1. Ana  40%" && InvasionView.YouLine(Json.Get(h, "you")) == "You: #2, 25% of the defence, 1 kill" && InvasionView.YouLine(null) == "You: not in the defence yet", "invasion: top and you lines");
            r.In(251, "{\"action\":\"hud\",\"data\":{\"area\":\"Ash Town\",\"target\":\"the gate\",\"phase\":\"running\",\"wave\":2,\"waves\":5,\"left\":3,\"time\":500,\"sides\":[{\"name\":\"Ember\",\"left\":2,\"color\":\"#ff0000\",\"boss\":\"Kral\",\"bossHp\":80},{\"name\":\"Frost\",\"left\":1,\"color\":\"bad\"}]}}");
            h = s.Hud;
            check(InvasionView.Subtitle(h) == "Ember and Frost - defend the gate" && InvasionView.WaveLine(h, 0) == "Wave 2 of 5 - 3 invaders left", "invasion: a clash of two hordes");
            var sl = InvasionView.SideLines(h);
            check(sl[0].Key == "Ember: 2 left, Kral 80%" && sl[0].Value == "#ff0000" && sl[1].Key == "Frost: 1 left" && sl[1].Value == "#d6c9ae", "invasion: side lines and a bad colour falls back");
            r.In(251, "{\"action\":\"hud\",\"data\":{\"area\":\"Ash Town\",\"phase\":\"occupied\",\"left\":1}}");
            check(InvasionView.Title(s.Hud) == "Ash Town is occupied" && InvasionView.Subtitle(s.Hud) == "Slay the occupiers to free it" && InvasionView.WaveLine(s.Hud, 0) == "1 occupier left", "invasion: an occupied area");
            r.In(251, "{\"action\":\"end\",\"data\":{\"result\":\"win\",\"text\":\"Victory!\"}}");
            check(s.Ended && s.ResultText == "Victory!" && s.ResultColor == "#7fd07f" && s.TimeLeft(5000) == 0, "invasion: the end result");
            check(InvasionView.ResultColor("withdrawn") == "#d6c9ae" && InvasionView.ResultColor("lost") == "#ff5030", "invasion: result colours");
            r.In(251, "{\"action\":\"hide\"}");
            check(!s.HudShown, "invasion: hide");
            r.Sent.Clear();
            s.Toggle();
            check(r.Last() == "251 {\"action\":\"calendar\",\"data\":{\"open\":true}}", "invasion: the calendar is asked with open");
            r.In(251, "{\"action\":\"calendar\",\"data\":{\"open\":true,\"list\":[{\"when\":\"Fri 20:00\",\"name\":\"Ash Town\",\"kind\":\"invasion\",\"inSeconds\":4000},\"bad\",{\"when\":\"Sat\",\"name\":\"Storm\",\"kind\":\"storm\"}]}}");
            check(s.CalendarVisible && s.Calendar.Count == 2 && InvasionView.KindColor("storm") == "#b07aff" && InvasionView.KindColor("zzz") == "#d6c9ae", "invasion: the calendar rows");
            check(InvasionView.Countdown(0) == "now" && InvasionView.Countdown(30) == "in 1m" && InvasionView.Countdown(4000) == "in 1h 06m" && InvasionView.Countdown(100000) == "in 1d 3h", "invasion: countdown texts");
            s.Toggle();
            check(!s.CalendarVisible, "invasion: toggle closes the calendar");
        }

        // ------------------------------------------------------------------------------------ Siege
        static void Siege(Action<bool, string> check)
        {
            var r = new Rig();
            var s = r.E.Siege;
            r.Now = 1000;
            r.In(233, "{\"action\":\"info\",\"data\":{\"open\":true,\"phase\":\"idle\",\"inSeconds\":7300,\"whenText\":\"Sat 20:00\",\"guild\":\"Ash\",\"members\":5,\"signed\":true,\"canJoin\":false,\"canLeave\":true,\"capacity\":8,\"signups\":[{\"name\":\"Ash\",\"own\":true}],\"champions\":[{\"name\":\"Old\",\"untilText\":\"Sun\"}],\"rules\":[\"No pets\"]}}");
            check(s.Visible && s.CountdownText(1000 + 100000) == "Starts in 2h 00m" && SiegeView.Countdown(61) == "1m 01s" && SiegeView.Countdown(100000) == "1d 3h", "siege: the window and its countdown");
            r.In(233, "{\"action\":\"info\",\"data\":{\"phase\":\"running\"}}");
            check(s.CountdownText(5000) == "Running", "siege: a running siege");
            r.In(233, "{\"action\":\"hud\",\"data\":{\"phase\":\"gather\",\"left\":75,\"brackets\":2,\"bracket\":\"B\",\"teams\":[{\"name\":\"Ash\",\"score\":10,\"kills\":1,\"own\":true},{\"name\":\"Zed\",\"score\":10,\"kills\":3},\"bad\",{\"name\":\"Cin\",\"score\":30,\"kills\":0}],\"you\":{\"kills\":1,\"deaths\":2,\"points\":10}}}");
            var h = s.Hud;
            var sorted = SiegeView.Sorted(Json.Get(h, "teams"));
            check(sorted.Count == 3 && Json.Text(sorted[0], "name") == "Cin" && Json.Text(sorted[1], "name") == "Zed" && Json.Text(sorted[2], "name") == "Ash", "siege: teams by score, then kills, bad rows left out");
            check(SiegeView.Title(h) == "Guild Siege - gathering" && SiegeView.Holder(h, out string c) == "Gates open in 1:15" && c == "#d6c9ae" && SiegeView.YouText(Json.Get(h, "you")) == "You: 1 kills, 2 downed, 10 points", "siege: gather title, holder, you");
            check(SiegeView.Holder(Json.Parse("{\"phase\":\"fight\",\"holder\":\"Ash\",\"holderColor\":\"#112233\"}"), out c) == "Obelisk: Ash" && c == "#112233" && SiegeView.Holder(Json.Parse("{\"phase\":\"fight\",\"contested\":true}"), out c) == "Obelisk: contested" && SiegeView.Holder(Json.Parse("{\"phase\":\"fight\"}"), out c) == "Obelisk: neutral", "siege: holder lines");
            check(SiegeView.Title(Json.Parse("{\"phase\":\"fight\",\"brackets\":2,\"bracket\":2}")) == "Guild Siege - arena 2" && SiegeView.Title(Json.Parse("{\"phase\":\"ending\",\"result\":{\"winner\":\"Ash\"}}")) == "Ash wins!" && SiegeView.Title(Json.Parse("{\"phase\":\"ending\"}")) == "Siege over", "siege: titles");
            r.In(233, "{\"action\":\"hide\"}");
            check(s.Hud == null, "siege: hide");
            r.Sent.Clear();
            s.Join(); s.Leave();
            check(r.Sent.Count == 2 && r.Last() == "233 {\"action\":\"leave\",\"data\":{}}", "siege: join and leave");
        }

        // ------------------------------------------------------------------------------------ Arena
        static void Arena(Action<bool, string> check)
        {
            var r = new Rig();
            var s = r.E.Arena;
            int started = 0, ended = 0;
            s.Started = () => started++; s.Ended = () => ended++;
            s.Toggle();
            check(r.Last() == "236 {\"action\":\"open\",\"data\":{}}" && s.Visible, "arena: toggle shows the window at once and asks");
            r.Now = 1000;
            r.In(236, "{\"action\":\"state\",\"data\":{\"open\":true,\"now\":2000000,\"ratings\":{\"1v1\":{\"rating\":1210,\"wins\":3,\"losses\":2,\"draws\":1,\"best\":1300}},\"queueCount\":{\"1v1\":2},\"season\":{\"id\":2,\"brackets\":{\"1v1\":{\"rating\":1650,\"matches\":9,\"placed\":true,\"tierName\":\"Gold\",\"color\":\"#f6cf72\"},\"2v2\":{\"matches\":2,\"placementLeft\":3}}},\"rules\":{\"levelLow\":40,\"levelHigh\":70,\"minLevel\":50,\"countdown\":10,\"fight\":300},\"firstWinDone\":false,\"queue\":{\"mode\":\"1v1\",\"waited\":30,\"rating\":1210,\"window\":150},\"recent\":[{\"mode\":\"1v1\",\"result\":\"win\",\"before\":1190,\"after\":1210,\"opponents\":\"Bo\",\"at\":1999000,\"reason\":\"defeat\"}]}}");
            check(s.Visible && s.InQueue && !s.InMatch, "arena: the state opens the window and shows the queue");
            check(s.StatusText(1000 + 5000) == "In the 1v1 queue: 0:35 (rating 1210, window +/-150)", "arena: the wait counts on");
            var sea = Json.Get(s.State, "season");
            check(ArenaText.SeasonLine(Json.Get(Json.Get(sea, "brackets"), "1v1"), 2, out string col, out string tip) == "Season: Gold 1650" && col == "#f6cf72" && tip == "PvP Season 2 rating 1650 (9 matches).", "arena: a placed season line");
            check(ArenaText.SeasonLine(Json.Get(Json.Get(sea, "brackets"), "2v2"), 2, out col, out tip) == "Season: placement 2/5" && col == "#8c8070", "arena: a placement season line");
            check(ArenaText.SeasonLine(null, 2, out col, out tip) == "", "arena: no bracket, no line");
            check(s.RulesLine() == "Opponent levels 40 - 70.  First-win bonus: ready" && s.RulesTip().Contains("5:00"), "arena: rules line and tip");
            check(ArenaText.Record(Json.Get(Json.Get(s.State, "ratings"), "1v1")) == "3-2-1" && ArenaText.Ago(7200) == "2h ago" && ArenaText.Ago(10) == "just now" && ArenaText.Reason("timeout") == "time ran out", "arena: record, ago and reasons");
            check(ArenaText.ModeTitle("3v3") == "Warband 3v3" && ArenaText.Result("win", out col) == "VICTORY" && col == "#f6cf72" && ArenaText.Result("x", out col) == "X", "arena: titles and results");
            r.Sent.Clear();
            s.Queue("2v2"); s.LeaveQueue();
            check(r.Sent[0][1] == 236 && Encoding.UTF8.GetString(r.Sent[0], 4, r.Sent[0].Length - 4) == "{\"action\":\"queue\",\"data\":{\"mode\":\"2v2\"}}" && r.Last() == "236 {\"action\":\"leave\",\"data\":{}}", "arena: queue and leave");
            r.In(236, "{\"action\":\"start\",\"data\":{\"team\":2,\"mode\":\"1v1\"}}");
            check(started == 1 && !s.Visible && s.MyTeam == 2, "arena: start hides the window and raises Started");
            r.In(236, "{\"action\":\"hud\",\"data\":{\"mode\":\"1v1\",\"phase\":\"countdown\",\"left\":7,\"team\":2,\"sides\":[[{\"name\":\"Ana\",\"hp\":100}],[{\"name\":\"Bo\",\"hp\":40},{\"name\":\"Cy\",\"defeated\":true}]]}}");
            var mine = s.Side(true); var theirs = s.Side(false);
            check(mine.Count == 2 && Json.Text(mine[0], "name") == "Bo" && theirs.Count == 1 && Json.Text(theirs[0], "name") == "Ana", "arena: own side is sides[team]");
            check(ArenaText.HudCenter("countdown", 7, out string small) == "7" && small == "starts in" && ArenaText.HudCenter("fight", 125, out small) == "2:05" && small == "fight", "arena: hud centre");
            check(ArenaText.HpColor(80) == "#2f7a2a" && ArenaText.HpColor(40) == "#b07a10" && ArenaText.HpColor(10) == "#8a1010", "arena: health colours");
            r.In(236, "{\"action\":\"end\",\"data\":{\"result\":\"win\",\"before\":1210,\"after\":1230,\"delta\":20,\"reward\":\"2 orbs\",\"firstWin\":true,\"season\":{\"before\":1650,\"after\":1670,\"delta\":20,\"placed\":true,\"tierName\":\"Gold\"}}}");
            check(ended == 1 && s.ResultShown(r.Now + 7000) && !s.ResultShown(r.Now + 9000) && s.Hud == null, "arena: the result shows 8 s and raises Ended");
            check(ArenaText.RatingLine(1210, 1230, 20) == "Rating 1210 -> 1230 (+20)" && ArenaText.SeasonDelta(Json.Get(s.Result, "season")) == "Season 1650 -> 1670 (+20) Gold", "arena: rating and season delta lines");
            r.In(236, "{\"action\":\"hud\",\"data\":{\"phase\":\"fight\",\"team\":1,\"sides\":[[],[]]}}");
            check(s.Hud == null, "arena: a hud message while the result is on screen is ignored");
        }

        // ------------------------------------------------------------------------------------ Battleground
        static void Battleground(Action<bool, string> check)
        {
            var r = new Rig();
            var s = r.E.Battleground;
            int started = 0, ended = 0;
            s.Started = () => started++; s.Ended = () => ended++;
            string alert = null;
            s.Alert = t => alert = t;
            r.Now = 1000;
            r.In(200, "{\"action\":\"state\",\"data\":{\"open\":true,\"minLevel\":100,\"bracket\":{\"name\":\"Mid\",\"ref\":300},\"waiting\":4,\"est\":90,\"role\":\"dps\",\"roles\":[\"tank\",\"healer\",\"dps\"],\"honor\":1200,\"weekHonor\":300,\"weekCap\":2000,\"firstWinDone\":true,\"record\":{\"matches\":10,\"wins\":6,\"losses\":3,\"draws\":1,\"kills\":40,\"captures\":12},\"season\":{\"id\":1,\"placement\":5,\"brackets\":{\"bg\":{\"name\":\"Wells\",\"rating\":1800,\"wins\":6,\"losses\":3,\"draws\":1,\"placed\":true,\"tier\":2,\"tierName\":\"Ember\",\"color\":\"#ff9a3c\",\"rd\":80,\"peak\":1850,\"matches\":10,\"decayIn\":86400}}},\"vendor\":[{\"key\":\"cape\",\"name\":\"Cape\",\"cost\":900,\"kind\":\"cosmetic\"},{\"key\":\"x\",\"name\":\"X\",\"cost\":5000,\"kind\":\"item\"},{\"key\":\"y\",\"name\":\"Y\",\"cost\":10,\"owned\":true}]}}");
            check(s.Visible && s.CanQueue && !s.InMatch && !s.InQueue, "bg: the state opens the window and allows the queue");
            string color;
            check(BgView.QueueStatus(s.State, 0, out color) == "4 waiting in your bracket. Estimated wait: ~1m" && color == "#d6c9ae", "bg: waiting text");
            check(BgView.QueueStatus(Json.Parse("{\"minLevel\":100}"), 0, out color) == "You need level 100 for the battleground." && color == "#e03a1e", "bg: below the level");
            check(BgView.QueueStatus(Json.Parse("{\"bracket\":{},\"deserter\":120}"), 20, out color) == "Deserter: no queue for 1m." && color == "#e03a1e", "bg: deserter text");
            check(BgView.QueueStatus(Json.Parse("{\"bracket\":{},\"queue\":{\"waited\":30,\"players\":6,\"est\":50}}"), 10, out color) == "In the queue 0:40 (6 players waiting). Estimated: ~40s" && color == "#f6cf72", "bg: in the queue");
            var roles = BgView.RoleOptions(s.State);
            check(roles.Count == 3 && roles[2].Chosen && roles[0].Text == "Tank" && roles[1].Color == "#6fd8a8", "bg: roles");
            check(BgView.HonorLine(s.State) == "Honor 1,200   (this week 300 / 2,000)   Weekly first win: taken" && BgView.RecordLine(s.State) == "Battlegrounds 10   W-L-D 6-3-1   Downs dealt 40   Wells taken 12", "bg: honor and record lines");
            var sea = Json.Get(s.State, "season");
            var card = BgView.Card(Json.Get(Json.Get(sea, "brackets"), "bg"), Json.Parse("[{\"key\":\"ashen\"},{\"key\":\"ember\"}]"), 5);
            check(card.Rating == "1800" && card.Tier == "Ember" && card.TierKey == "ember" && card.Record == "6-3-1" && card.Decay == "Decay in 1d 0h without a rated match" && card.Tooltip == "Season rating 1800 (deviation 80), peak 1850, 10 matches.", "bg: a placed card");
            var card2 = BgView.Card(Json.Parse("{\"name\":\"1v1\",\"placementLeft\":3}"), null, 5);
            check(card2.Unplaced && card2.Rating == "?" && card2.Tier == "Placement 2/5" && card2.TierKey == "ashen", "bg: a card still in placement");
            var v = Eg.Objects(s.State, "vendor");
            var v0 = BgView.VendorRow(v[0], 1200); var v1 = BgView.VendorRow(v[1], 1200); var v2 = BgView.VendorRow(v[2], 1200);
            check(v0.Can && v0.Sub == "Cosmetic, account-wide." && !v1.Can && v1.Sub == "You need 3,800 more honor." && !v2.Can && v2.Button == "Owned", "bg: vendor rows");
            r.Sent.Clear();
            s.SetRole("tank"); s.QueueOrLeave();
            check(r.Sent.Count == 2 && Encoding.UTF8.GetString(r.Sent[0], 4, r.Sent[0].Length - 4) == "{\"action\":\"role\",\"data\":{\"role\":\"tank\"}}" && r.Last() == "200 {\"action\":\"queue\",\"data\":{\"role\":\"dps\"}}", "bg: role and queue as the chosen role");
            s.Buy("cape");
            check(r.Last() == "200 {\"action\":\"buy\",\"data\":{\"key\":\"cape\"}}", "bg: buy");
            r.In(200, "{\"action\":\"start\",\"data\":{\"team\":2}}");
            check(started == 1 && !s.Visible && s.MyTeam == 2, "bg: start");
            r.In(200, "{\"action\":\"hud\",\"data\":{\"team\":2,\"phase\":\"prep\",\"left\":12,\"win\":1000,\"score\":[300,120],\"teams\":[\"Ash\",\"Wave\"],\"colors\":[\"#ff9a3c\",\"#8fb8ff\"],\"players\":[5,5],\"respawn\":9,\"braziers\":[{\"name\":\"North\",\"owner\":1,\"progress\":100},{\"name\":\"Mid\",\"owner\":0,\"progress\":-40},{\"name\":\"South\",\"owner\":2,\"progress\":-60},{\"name\":\"Hot\",\"contested\":true}]}}");
            var d = s.Hud;
            check(BgView.ScorePercent(300, 1000) == 30 && BgView.ScorePercent(5000, 1000) == 100 && BgView.ScorePercent(5, 0) == 0, "bg: score percent");
            check(BgView.HudCenter(d, 12, out string small) == "12" && small == "the wells open in" && BgView.HudCenter(Json.Parse("{\"phase\":\"fight\"}"), 125, out small) == "2:05" && small == "left", "bg: hud centre");
            var teams = Json.Get(d, "teams"); var colors = Json.Get(d, "colors"); var bz = Json.List(d, "braziers");
            var w0 = BgView.Brazier(bz[0], teams, colors); var w1 = BgView.Brazier(bz[1], teams, colors); var w2 = BgView.Brazier(bz[2], teams, colors); var w3 = BgView.Brazier(bz[3], teams, colors);
            check(w0.Text == "Ash" && w0.Color == "#ff9a3c" && w1.Text == "40% Wave" && w1.Color == "#8fb8ff" && w2.Text == "Wave 60%" && w3.Text == "contested" && w3.Color == "#ff5050", "bg: brazier states");
            check(BgView.Brazier(Json.Parse("{\"name\":\"N\"}"), null, null).Text == "neutral", "bg: a neutral brazier");
            check(BgView.HudNotice(d, 9 - 4, 0, out color) == "Downed: back with the next wave in 5s" && color == "#e03a1e" && BgView.HudNotice(Json.Parse("{\"afk\":20}"), 0, 20, out color) == "Inactive: move or fight within 20s" && BgView.HudNotice(Json.Parse("{}"), 0, 0, out color) == "", "bg: notices");
            check(s.HudElapsed(r.Now + 4000) == 4, "bg: hud elapsed seconds");
            r.In(200, "{\"action\":\"alert\",\"data\":{\"text\":\"Wells open\"}}");
            check(alert == "Wells open", "bg: an alert line");
            r.In(200, "{\"action\":\"board\",\"data\":{\"team\":2,\"teams\":[\"Ash\",\"Wave\"],\"score\":[1,2],\"rows\":[{\"name\":\"Ana\",\"team\":1,\"role\":\"tank\",\"kills\":3,\"assists\":1,\"downs\":2,\"captures\":1,\"damage\":12345,\"healing\":0},{\"name\":\"Bo\",\"team\":2,\"role\":\"dps\",\"left\":true,\"honor\":50}]}}");
            var sides = BgView.BoardSides(Json.Get(s.Board, "rows"), 2);
            check(sides[0].Count == 1 && sides[0][0].Name == "Bo (left)" && sides[0][0].Left && sides[0][0].Honor == "50" && sides[1][0].Damage == "12,345" && sides[1][0].Role == "Tank", "bg: the board splits own team first");
            r.In(200, "{\"action\":\"end\",\"data\":{\"result\":\"loss\",\"team\":2,\"reason\":\"time\",\"score\":[500,400],\"teams\":[\"Ash\",\"Wave\"],\"honor\":120,\"items\":\"1 Orb\",\"firstWin\":false,\"season\":{\"before\":1800,\"after\":1790,\"delta\":-10,\"placed\":true,\"tierName\":\"Ember\"}}}");
            var sm = BgView.Summary(s.Summary, 2);
            check(ended == 1 && s.BoardVisible && s.Hud == null && sm.Title == "DEFEAT" && sm.Score == "Wave 400  -  500 Ash" && sm.Reason == "time ran out" && sm.Rating == "Season rating 1800 -> 1790 (-10)  Ember" && sm.Honor == "Honor +120  1 Orb", "bg: the summary");
            check(BgView.Summary(Json.Parse("{\"result\":\"win\",\"rated\":false,\"score\":[1,0]}"), 1).Rating == "Not rated", "bg: an unrated match");
            check(Eg.SpanLong(45) == "45s" && Eg.SpanLong(7300) == "2h 1m" && Eg.SpanLong(200000) == "2d 7h" && Eg.SpanLong(800000) == "1w 2d", "bg: span texts");
            r.Sent.Clear();
            s.ToggleBoard();
            check(!s.BoardVisible && r.Sent.Count == 0, "bg: the board toggles off");
            s.ToggleBoard();
            check(s.BoardVisible && r.Last() == "200 {\"action\":\"board\",\"data\":{}}" && s.Summary == null, "bg: the board toggles on and asks for the rows");
            string noticed = null;
            s.Notice = t => noticed = t;
            r.In(200, "{\"action\":\"msg\",\"data\":{\"text\":\"Cooldown\",\"ok\":false}}");
            check(s.Message == "" && noticed == "Cooldown", "bg: a message with the window closed goes to the log");
        }

        // ------------------------------------------------------------------------------------ Scorched Marches
        static void PvpZone(Action<bool, string> check)
        {
            var r = new Rig();
            var s = r.E.PvpZone;
            int started = 0, ended = 0;
            s.Started = () => started++; s.Ended = () => ended++;
            r.Now = 1000;
            r.In(193, "{\"action\":\"state\",\"data\":{\"open\":true,\"confirm\":true,\"minLevel\":150,\"canEnter\":true,\"carried\":300,\"carryMax\":2500,\"pickup\":{\"perKill\":800},\"rules\":[\"No loss of gear\"],\"exitSeconds\":5,\"banked\":4000,\"weekBanked\":900,\"total\":12000,\"kills\":8,\"defeats\":2,\"captures\":1,\"pledgeChangeIn\":7300,\"factions\":[{\"key\":\"ash\",\"name\":\"Ash\",\"pledged\":true,\"rival\":\"Frost\"},{\"key\":\"frost\",\"name\":\"Frost\",\"can\":true},{\"key\":\"x\",\"name\":\"X\",\"why\":\"Level\"}],\"vendor\":[{\"key\":\"orb\",\"name\":\"Orb\",\"kind\":\"item\",\"cost\":500,\"can\":true,\"weekly\":3,\"bought\":1},{\"key\":\"c\",\"name\":\"Cape\",\"kind\":\"cosmetic\",\"cost\":9999,\"can\":true},{\"key\":\"o\",\"name\":\"Own\",\"kind\":\"cosmetic\",\"owned\":true}],\"hc\":{\"isHc\":true,\"allow\":true}}}");
            check(s.Visible && s.ConfirmAsked, "marches: open and confirm ask for the rules box");
            check(PvpZoneView.EnterButton(s.State, out bool en, out string tip) == "Enter the Marches" && en, "marches: the Enter button");
            check(PvpZoneView.EnterButton(Json.Parse("{\"inside\":true}"), out en, out tip) == "Inside" && !en && PvpZoneView.EnterButton(Json.Parse("{\"canEnter\":false,\"why\":\"Level 150 needed\"}"), out en, out tip) == "Enter" && !en && tip == "Level 150 needed", "marches: inside and blocked buttons");
            check(!PvpZoneView.CanConfirm(s.State, false, true) && !PvpZoneView.CanConfirm(s.State, true, false) && PvpZoneView.CanConfirm(s.State, true, true), "marches: a hardcore character must tick both boxes");
            check(PvpZoneView.RiskText(s.State) == "- No loss of gear\nYou carry 300 embers now. A defeat drops them all; your killer may take up to 800 of them.\nHARDCORE: a defeat here may end your Hardcore run.", "marches: the risk text");
            r.Sent.Clear();
            check(!s.Enter(true, false) && r.Sent.Count == 0 && s.Enter(true, true) && r.Last() == "193 {\"action\":\"enter\",\"data\":{\"accept\":true,\"hcAccept\":true}}" && !s.ConfirmAsked, "marches: enter sends accept and hcAccept");
            string btn; bool can;
            check(PvpZoneView.FactionRow(Eg.Objects(s.State, "factions")[0], s.State, out btn, out can, out tip) == "Ash" && btn == "Pledged" && !can && tip == "You can change in 2h 1m", "marches: a pledged faction with a wait");
            check(PvpZoneView.FactionRow(Eg.Objects(s.State, "factions")[1], s.State, out btn, out can, out tip) == "Frost" && btn == "Pledge" && can, "marches: a faction to pledge to");
            check(PvpZoneView.FactionRow(Eg.Objects(s.State, "factions")[2], s.State, out btn, out can, out tip) == "X" && !can && tip == "Level", "marches: a faction that cannot be pledged shows why");
            var vend = Eg.Objects(s.State, "vendor");
            check(PvpZoneView.VendorRow(vend[0], 4000, out btn, out can) == "1 of 3 this week" && btn == "500 embers" && can && PvpZoneView.VendorRow(vend[1], 4000, out btn, out can) == "Cosmetic, account-wide" && !can && PvpZoneView.VendorRow(vend[2], 4000, out btn, out can) == "Cosmetic, account-wide" && btn == "Owned", "marches: vendor rows");
            check(PvpZoneView.RecordLine(s.State) == "Banked 4,000 (this week 900, all time 12,000)   Defeats dealt 8, taken 2   Shrines 1", "marches: the record line");
            check(PvpZoneView.Steps(s.State)[1].StartsWith("2. Enter from a protection zone.") && PvpZoneView.Steps(s.State)[1].Contains("2,500") && PvpZoneView.Steps(s.State)[3].Contains("5s"), "marches: the steps");
            r.In(193, "{\"action\":\"enter\",\"data\":{\"marks\":[{\"kind\":\"exit\",\"x\":100,\"y\":100,\"z\":7,\"name\":\"North exit\"},{\"kind\":\"exit\",\"x\":130,\"y\":96,\"z\":7},{\"kind\":\"shrine\",\"x\":110,\"y\":150,\"z\":7},{\"kind\":\"bad\",\"x\":1,\"y\":1,\"z\":1},{\"kind\":\"exit\",\"x\":\"a\",\"y\":1,\"z\":1}]}}");
            check(started == 1 && !s.Visible && s.Marks.Count == 3, "marches: enter hides the window, keeps clean marks and raises Started");
            var ex = PvpZoneView.Nearest(s.Marks, "exit", 101, 100, 7, out string where);
            check(ex != null && ex.Name == "North exit" && where == "1 tiles west", "marches: the nearest exit and its direction");
            check(PvpZoneView.Compass(100, 100, 100, 90, out string dir) == 10 && dir == "n" && PvpZoneView.Compass(100, 100, 108, 108, out dir) == 8 && dir == "se" && PvpZoneView.Compass(5, 5, 5, 5, out dir) == 0 && dir == null, "marches: compass words");
            check(PvpZoneView.WhereText(0, null) == "you are here" && PvpZoneView.WhereText(4, "nw") == "4 tiles north-west", "marches: where text");
            check(PvpZoneView.Nearest(s.Marks, "shrine", 100, 100, 6, out where) == null && where == null, "marches: no mark on another floor");
            r.In(193, "{\"action\":\"hud\",\"data\":{\"embers\":2300,\"cap\":2500,\"protect\":5,\"piles\":2,\"pledge\":{\"key\":\"ash\",\"name\":\"Ash\",\"color\":\"#ff0000\"},\"contest\":{\"phase\":\"capture\",\"left\":125,\"progress\":[{\"name\":\"Ash\",\"short\":\"AS\",\"pct\":60,\"color\":\"#ff0000\"}],\"holder\":{\"name\":\"Frost\",\"left\":5400}}}}");
            var h = s.Hud;
            double pct = PvpZoneView.CarryPercent(h, out string pc);
            check(pct == 92 && pc == "#ff5a2a" && PvpZoneView.EmbersLine(h) == "Embers 2,300 / 2,500", "marches: embers bar");
            check(PvpZoneView.ContestLine(Json.Get(h, "contest"), 125, out string cc) == "Shrine: AS 60% - 2:05 left" && cc == "#ff0000", "marches: the contest line");
            check(PvpZoneView.ContestLine(Json.Parse("{\"phase\":\"warden\",\"warden\":70}"), 30, out cc) == "Shrine Warden 70% - 0:30 left" && PvpZoneView.ContestLine(Json.Parse("{\"phase\":\"capture\",\"contested\":true}"), 5, out cc) == "Shrine: CONTESTED - 0:05 left" && PvpZoneView.ContestLine(Json.Parse("{\"phase\":\"wait\"}"), 90, out cc) == "Shrine contest in 1:30", "marches: warden, contested and waiting lines");
            check(PvpZoneView.HolderLine(Json.Get(h, "contest"), out cc) == "Frost hold the shrine (1h 30m)" && PvpZoneView.HolderLine(null, out cc) == "Nobody holds the Cinder Shrine", "marches: the holder line");
            check(PvpZoneView.PledgeLine(Json.Get(h, "pledge"), out cc) == "Fighting for Ash" && cc == "#ff0000" && PvpZoneView.PledgeLine(null, out cc) == "Not pledged: no reputation, no shrine", "marches: the pledge line");
            check(PvpZoneView.StatusLine(h, 5 - s.HudElapsed(r.Now + 2000), out cc) == "Protected for 3s" && PvpZoneView.StatusLine(Json.Parse("{\"exit\":40}"), 0, out cc) == "Leaving... 40% (do not fight)" && PvpZoneView.StatusLine(Json.Parse("{\"piles\":3}"), 0, out cc) == "3 embers lie on the ground" && PvpZoneView.StatusLine(Json.Parse("{}"), 0, out cc) == "Bank your embers at a safe exit", "marches: status lines");
            var goals = PvpZoneView.GoalLines(h, "1 tiles east", "7 tiles south");
            check(goals.Count == 2 && goals[0].Key == "Embers carried: 2,300. Bank them at the nearest safe exit (1 tiles east, marked on your map) before you are defeated." && goals[1].Key == "Shrine event: stand in the shrine circle with your faction to take it (7 tiles south, marked on your map).", "marches: goal lines");
            check(PvpZoneView.GoalLines(Json.Parse("{\"exit\":10,\"embers\":50}"), null, null).Count == 1 && PvpZoneView.GoalLines(Json.Parse("{}"), null, null)[0].Key.StartsWith("Goal: kill monsters"), "marches: leaving and empty goals");
            r.In(193, "{\"action\":\"hide\"}");
            check(ended == 1 && s.Hud == null && s.Marks.Count == 0, "marches: hide ends the zone");
            r.Sent.Clear();
            s.Pledge("frost"); s.Buy("orb");
            check(Encoding.UTF8.GetString(r.Sent[0], 4, r.Sent[0].Length - 4) == "{\"action\":\"pledge\",\"data\":{\"faction\":\"frost\"}}" && r.Last() == "193 {\"action\":\"buy\",\"data\":{\"key\":\"orb\"}}", "marches: pledge and buy");
        }

        // ------------------------------------------------------------------------------------ Bounty
        static void Bounty(Action<bool, string> check)
        {
            var r = new Rig();
            var s = r.E.Bounty;
            r.Now = 1000;
            s.Toggle();
            check(r.Last() == "223 {\"action\":\"open\",\"data\":{}}", "bounty: toggle asks for the board");
            r.In(223, "{\"action\":\"board\",\"data\":{\"day\":5,\"nextIn\":3700,\"open\":true,\"band\":2,\"active\":1,\"maxActive\":3,\"rerolls\":1,\"week\":{\"done\":4,\"need\":7,\"claimed\":false},\"bands\":[{\"index\":1,\"label\":\"8-49\",\"contracts\":[]},{\"index\":2,\"label\":\"50-99\",\"own\":true,\"contracts\":[{\"key\":\"a\",\"type\":\"hunt\",\"name\":\"Rat\",\"count\":30,\"state\":\"open\",\"progress\":0,\"reward\":{\"gold\":12000,\"chaos\":1,\"exp\":50000}},{\"key\":\"b\",\"type\":\"elite\",\"name\":\"Bandit\",\"tier\":\"rare\",\"count\":5,\"state\":\"active\",\"progress\":2,\"level\":80,\"reward\":{\"divine\":2}},{\"key\":\"c\",\"type\":\"boss\",\"name\":\"Ogre\",\"count\":1,\"state\":\"done\",\"progress\":1,\"reward\":{}}]}]}}");
            check(s.Visible && s.Bands.Count == 2 && s.Current.Label == "50-99" && s.Current.Contracts.Count == 3 && s.SelectedBand == 2, "bounty: the board opens on the band of the character");
            check(s.ActiveText() == "Active contracts: 1 / 3" && s.WeekText() == "Weekly chest: 4 / 7" && !s.Full, "bounty: header texts");
            var cs = s.Current.Contracts;
            check(BountyView.TaskText(cs[0]) == "Kill 30 Rats." && BountyView.TaskText(cs[1]) == "Kill 5 rare or stronger Bandits." && BountyView.TaskText(cs[2]) == "Slay the boss once.", "bounty: task texts with plurals");
            check(BountyView.Plural("Fox", 2) == "Foxes" && BountyView.Plural("Baby", 2) == "Babies" && BountyView.Plural("Ogreman", 3) == "Ogremen" && BountyView.Plural("Dragon", 1) == "Dragon" && BountyView.Plural("Bats", 3) == "Bats", "bounty: plural rules");
            string exact;
            check(BountyView.RewardText(cs[0].Reward, out exact) == "12k gold, 1 Orb of Upheaval, 50k exp" && exact == "Reward:\n12,000 gold to your bank\n1 Orb of Upheaval\n50,000 experience", "bounty: reward text and tooltip");
            check(BountyView.RewardText(cs[1].Reward, out exact) == "2 Orbs of Fate", "bounty: divine orbs");
            check(BountyView.KindText("hunt") == "HUNT" && BountyView.KindColor("boss") == "#e03a1e" && BountyView.TierColor("legendary") == "#e8582a" && BountyView.TierColor("zzz") == null, "bounty: kind and tier colours");
            check(BountyView.FormatTime(3725) == "1h 02m 05s" && s.NextLeft(1000 + 100000) == 3600, "bounty: time text and the countdown");
            r.Sent.Clear();
            s.Accept("a"); s.Abandon("b"); s.Reroll("b");
            check(r.Sent.Count == 3 && Encoding.UTF8.GetString(r.Sent[0], 4, r.Sent[0].Length - 4) == "{\"action\":\"accept\",\"data\":{\"key\":\"a\"}}" && r.Last() == "223 {\"action\":\"reroll\",\"data\":{\"key\":\"b\"}}", "bounty: accept, abandon and reroll");
            r.In(223, "{\"action\":\"progress\",\"data\":{\"key\":\"b\",\"progress\":5,\"count\":5,\"state\":\"done\"}}");
            check(cs[1].Progress == 5 && cs[1].State == "done", "bounty: progress updates a contract");
            s.SelectBand(s.Bands[0]);
            check(s.SelectedBand == 1 && s.Current.Contracts.Count == 0, "bounty: another tab");
            r.In(223, "{\"action\":\"board\",\"data\":{\"nextIn\":100,\"band\":2,\"active\":3,\"maxActive\":3,\"bands\":[{\"index\":1,\"label\":\"8-49\",\"contracts\":[]},{\"index\":2,\"label\":\"50-99\",\"contracts\":[]}],\"week\":{\"claimed\":true}}}");
            check(s.SelectedBand == 1 && s.Full && s.WeekText() == "Weekly chest: collected", "bounty: a new board keeps the tab and a full list blocks Accept");
            r.Now = 1000 + 102000;
            check(!s.WantsRefresh(r.Now) && s.WantsRefresh(r.Now + 2000) && !s.WantsRefresh(r.Now + 5000), "bounty: the board asks again once, 3 s after the timer ends");
        }

        // ------------------------------------------------------------------------------------ top menu
        static void Menu(Action<bool, string> check)
        {
            var adv = Array.Find(TopMenu.Categories, c => c.Id == "adventure");
            var targets = new Dictionary<string, string>();
            foreach (var e in adv.Entries) targets[e.Text] = e.Target;
            string[][] want =
            {
                new[] { "Dungeons", "win:DungeonsWindow" }, new[] { "Infinity Tower", "win:TowerWindow" }, new[] { "Bounty Board", "win:BountyWindow" },
                new[] { "Arena", "win:ArenaWindow" }, new[] { "Guild Siege", "win:SiegeWindow" }, new[] { "Ember Descent", "win:DescentWindow" },
                new[] { "Rift Atlas", "win:RiftAtlasWindow" }, new[] { "Waystone Atlas", "win:WaystoneAtlasWindow" }, new[] { "Raid: Ashen Sepulchre", "win:RaidWindow" },
                new[] { "Scorched Marches", "win:PvpZoneWindow" }, new[] { "Battleground", "win:BattlegroundWindow" }, new[] { "Invasions", "win:InvasionWindow" },
            };
            bool all = true;
            foreach (var w in want) all &= targets.TryGetValue(w[0], out var t) && t == w[1];
            check(all, "menu: the Adventure menu has an entry for every endgame activity");
            // the unlock gates: the server's menu texts (unlocks_config.lua) name these entries
            var u = new MenuUnlocks(new ExtOpcodes());
            u.Apply(Json.Parse("{\"entries\":[{\"key\":\"raid\",\"level\":800,\"menu\":\"Raid: Ashen Sepulchre\"},{\"key\":\"arena\",\"level\":50,\"menu\":\"Arena\"}],\"unlocked\":[\"arena\"],\"next\":{\"key\":\"raid\",\"level\":800}}"));
            check(u.Status("Arena", out _) == MenuStatus.Open && u.Status("Raid: Ashen Sepulchre", out int lv) == MenuStatus.Locked && lv == 800 && u.Status("Invasions", out _) == MenuStatus.Open, "menu: a locked activity shows grey with its level, an unlisted one is open");
        }

        // ------------------------------------------------------------------------------------ strings
        static void Strings(Action<bool, string> check)
        {
            Loc.Set("pt-BR");
            check(Loc.T("Infinity Tower") != "Infinity Tower" || LocEndgame.PtBr.ContainsKey("Infinity Tower"), "endgame: the tower title has a pt-BR text");
            var missing = new List<string>();
            foreach (var kv in LocEndgame.PtBr)
            {
                if (kv.Value.Length == 0) missing.Add(kv.Key);
                int a = 0, b = 0;
                while (kv.Key.Contains("{" + a + "}")) a++;
                while (kv.Value.Contains("{" + b + "}")) b++;
                if (a != b) missing.Add("placeholders: " + kv.Key);
            }
            check(missing.Count == 0, "endgame: every pt-BR text has its placeholders: " + string.Join(" | ", missing));
            check(LocStrings.PtBr.ContainsKey("Next reward: --"), "endgame: the texts are merged into the main table");
            check(Loc.T("Floor {0}", 3) == "Andar 3", "endgame: a formatted pt-BR text");
            Loc.Set("en");
        }
    }
}
