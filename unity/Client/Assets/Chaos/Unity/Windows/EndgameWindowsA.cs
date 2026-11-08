// Endgame windows, part A (track L): the Infinity Tower (window and run panel), Dungeons (finder and kill counter) and the Ashen Sepulchre raid
// (window, HUD and call-out). Models: Core/EndgamePve.cs. None has a Ctrl hotkey; they open from the Adventure menu or by the server.
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    // ================================================================================================ Infinity Tower
    public sealed class TowerWindow : GameWindow
    {
        bool lastVisible;
        Vector2 scroll;
        public override string Title => Loc.T("Infinity Tower");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 270, 60, 540, 520);
        public override void Reset() { lastVisible = false; Open = false; scroll = Vector2.zero; }

        public override void Tick(ChaosApp app)
        {
            var t = app.Session?.Endgame?.Tower;
            if (t == null) return;
            WindowSync.Run(ref lastVisible, this, t.Visible, t.ShowAndRequest, t.Hide);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var t = app.Session?.Endgame?.Tower;
            if (t == null) return;
            float x = inner.x + 6, w = inner.width - 12, y = inner.y + 2;
            Eu.Label(app, new Rect(x, y, w * 0.5f, 20), Loc.T("Current Season: {0}", t.HasData ? t.SeasonNum.ToString() : "--"), Eu.Bright, 14, true);
            Eu.Label(app, new Rect(x + w * 0.5f, y, w * 0.5f, 18), t.HasData ? t.SeasonEndText() : Loc.T("Season Ends In: --"), Eu.Text, 12, false, TextAnchor.UpperRight);
            y += 22;
            Eu.Label(app, new Rect(x, y, w * 0.5f, 18), Loc.T("Your Tower Points: {0}", Fmt.Short(t.PlayerPoints)), Eu.Gold, 12, true);
            Eu.Label(app, new Rect(x + w * 0.5f, y, w * 0.5f, 18), t.HasData ? t.NextTryText() : Loc.T("Next Try Available: --"), Eu.Text, 12, false, TextAnchor.UpperRight);
            y += 28;

            // the points bar with the milestones above and their Claim buttons below
            var ms = t.ShownMilestones();
            float barX = x + 30, barW = w - 60;
            var bar = new Rect(barX, y + 36, barW, 16);
            Eu.Bar(app, bar, t.PointsRatio() * 100, "#c9922a", Loc.T("{0} / {1} pts", Fmt.Short(t.PlayerPoints), Fmt.Short(t.MaxPoints())));
            for (int i = 0; i < ms.Count; i++)
            {
                float cx = barX + (float)ms[i].Points / t.MaxPoints() * barW;
                if (ms[i].Items.Count > 0) app.DrawItem(new Rect(cx - 15, y, 30, 30), (ushort)ms[i].Items[0].Id, ms[i].Items[0].Count);
                var b = new Rect(Mathf.Clamp(cx - 26, x, x + w - 52), y + 56, 52, 20);
                if (ms[i].Claimed) Eu.Button(b, Loc.T("Done"), false);
                else if (Eu.Button(b, Loc.T("Claim"), t.CanClaim(i + 1))) t.Claim(i + 1);
            }
            y += 86;

            Eu.Label(app, new Rect(x, y, w, 18), Loc.T("Top Rank Rewards"), Eu.Bright, 13, true);
            y += 20;
            string nextReward = t.NextRewardText();
            float nh = Eu.Height(app, nextReward, w * 0.55f, 11);
            Eu.Label(app, new Rect(x + w * 0.45f, y, w * 0.55f, nh), nextReward, Eu.Text, 11, false, TextAnchor.UpperLeft, true);
            for (int p = 1; p <= 3; p++)
            {
                object top = null;
                foreach (object o in t.TopRewards) if (Json.Int(o, "place") == p) top = o;
                var slot = new Rect(x + (p - 1) * 52, y, 46, 46);
                Eu.Panel(slot);
                if (top != null && Json.Int(top, "id") > 0) app.DrawItem(new Rect(slot.x + 7, slot.y + 7, 32, 32), (ushort)Json.Int(top, "id"), 1);
                Eu.Label(app, new Rect(slot.x, slot.y + 46, 46, 14), "#" + p, TowerState.Place(p), 11, true, TextAnchor.UpperCenter);
            }
            y += Mathf.Max(nh, 62) + 6;

            Eu.Label(app, new Rect(x, y, w, 18), Loc.T("Ranking"), Eu.Bright, 13, true);
            y += 20;
            float listH = inner.yMax - y - 40;
            var list = new Rect(x, y, w, Mathf.Max(60, listH));
            Eu.Panel(list, 0.04f);
            int rowH = 18;
            scroll = GUI.BeginScrollView(list, scroll, new Rect(0, 0, list.width - 18, Mathf.Max(list.height, t.Rankings.Count * rowH)));
            for (int i = 0; i < t.Rankings.Count; i++)
            {
                var rk = t.Rankings[i];
                string col = TowerState.Place(i + 1);
                float ry = i * rowH;
                Eu.Label(app, new Rect(4, ry, 26, rowH), (i + 1).ToString(), col, 12, true);
                Eu.Label(app, new Rect(34, ry, list.width * 0.5f, rowH), rk.Name, col, 12);
                Eu.Label(app, new Rect(list.width * 0.55f, ry, 60, rowH), Fmt.Short(rk.Floor), Eu.Text, 12, false, TextAnchor.UpperRight);
                Eu.Label(app, new Rect(list.width * 0.55f + 66, ry, 60, rowH), Eu.Two(rk.Time / 60) + ":" + Eu.Two(rk.Time % 60), Eu.Text, 12, false, TextAnchor.UpperRight);
            }
            if (t.Rankings.Count == 0) Eu.Label(app, new Rect(4, 2, list.width - 8, rowH), Loc.T("No ranking yet."), Eu.Dim, 12);
            GUI.EndScrollView();

            float bw = (w - 8) / 2;
            if (GUI.Button(new Rect(x, inner.yMax - 32, bw, 28), Loc.T("Enter"))) t.Enter();
            if (GUI.Button(new Rect(x + bw + 8, inner.yMax - 32, bw, 28), Loc.T("Leave"))) t.LeaveTower();
        }
    }

    /// <summary>The panel inside a run: the floor, monsters, the countdown, Next floor now (Ctrl+Shift+N), Auto and Leave.</summary>
    public sealed class TowerPanelWindow : EgHudWindow
    {
        public const string AutoKey = "chaos.towerAutoSkip";
        bool autoLoaded;
        public override string Title => Loc.T("Infinity Tower");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 130, 44, 260, 160);
        public override void Reset() { base.Reset(); autoLoaded = false; }
        protected override bool Wanted(ChaosApp app) => app.Session.Endgame.Tower.InRun;

        public override void Tick(ChaosApp app)
        {
            base.Tick(app);
            var t = app.Session?.Endgame?.Tower;
            if (t == null) return;
            if (!autoLoaded) { autoLoaded = true; try { t.AutoSkip = PlayerPrefs.GetInt(AutoKey, 0) == 1; } catch (Exception) { } }
            var e = Event.current;
            if (e != null && e.type == EventType.KeyDown && e.keyCode == KeyCode.N && e.control && e.shift && t.InRun) { t.Skip(); e.Use(); }
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var t = app.Session?.Endgame?.Tower;
            var p = t?.Panel(app.Session.Now);
            if (p == null) return;
            float x = inner.x + 6, w = inner.width - 12, y = inner.y + 2;
            Eu.Label(app, new Rect(x, y, w, 20), p.Floor, p.Boss ? Eu.Bad : Eu.Bright, 15, true);
            y += 22;
            Eu.Label(app, new Rect(x, y, w, 16), p.Cleared, Eu.Text, 12);
            y += 16;
            if (p.Monsters != null) { Eu.Label(app, new Rect(x, y, w, 16), p.Monsters, Eu.Text, 12); y += 16; }
            if (p.Timer != null) { Eu.Label(app, new Rect(x, y, w, 16), p.Timer, Eu.Gold, 12, true); y += 16; }
            y += 4;
            var v = t.View();
            if (Eu.Button(new Rect(x, y, w, 24), Loc.T("Next floor now") + " (" + TowerState.HotkeyText + ")", v.Enabled)) t.Skip();
            y += 28;
            bool auto = GUI.Toggle(new Rect(x, y, w * 0.5f, 20), t.AutoSkip, Loc.T("Auto"));
            if (auto != t.AutoSkip)
            {
                t.AutoSkip = auto;
                try { PlayerPrefs.SetInt(AutoKey, auto ? 1 : 0); } catch (Exception) { }
            }
            if (GUI.Button(new Rect(x + w * 0.5f, y, w * 0.5f, 22), Loc.T("Leave"))) t.LeaveRun();
        }
    }

    // ================================================================================================ Dungeons
    public sealed class DungeonsWindow : GameWindow
    {
        bool lastVisible;
        Vector2 listScroll;
        int board;   // 0 solo, 1 group
        public override string Title => Loc.T("Dungeons");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 340, 50, 680, 520);
        public override void Reset() { lastVisible = false; Open = false; }

        public override void Tick(ChaosApp app)
        {
            var d = app.Session?.Endgame?.Dungeons;
            if (d == null) return;
            WindowSync.Run(ref lastVisible, this, d.Visible, d.Show, d.Hide);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var d = app.Session?.Endgame?.Dungeons;
            if (d == null) return;
            double now = app.Session.Now;
            float x = inner.x + 4, y = inner.y + 2;
            float listW = 220;
            var list = new Rect(x, y, listW, inner.height - 4);
            Eu.Panel(list, 0.04f);
            int rowH = 46;
            listScroll = GUI.BeginScrollView(list, listScroll, new Rect(0, 0, list.width - 18, Mathf.Max(list.height, d.Rows.Count * rowH)));
            for (int i = 0; i < d.Rows.Count; i++)
            {
                var row = d.Rows[i];
                var r = new Rect(2, i * rowH, list.width - 22, rowH - 2);
                bool sel = row.Id == d.SelectedId;
                Eu.Panel(r, sel ? 0.16f : 0.05f);
                if (GUI.Button(r, GUIContent.none, GUIStyle.none) && !sel) d.Select(row.Id);
                // the boss of the dungeon (game_dungeons boss outfit)
                var boss = OutfitJson.Read(row.Boss);
                if (boss != null) app.DrawOutfit(new Rect(r.x + 2, r.y + 2, 40, 40), boss);
                float bx = boss != null ? 44 : 6;
                Eu.Label(app, new Rect(r.x + bx, r.y + 3, r.width - bx - 2, 18), row.Title, sel ? Eu.Bright : Eu.Text, 13, true);
                Eu.Label(app, new Rect(r.x + bx, r.y + 22, 70, 16), Loc.T("{0}+ Level", Fmt.Short(row.Level)), Eu.Dim, 11);
                var det = d.Details.TryGetValue(row.Id, out var dd) ? dd : null;
                int q = det != null ? det.QueuePlayers : row.Queue;
                Eu.Label(app, new Rect(r.x + 96, r.y + 22, r.width - 100, 16), DungeonsView.QueueText(q), Eg.QueueColor(q), 11, false, TextAnchor.UpperRight);
            }
            GUI.EndScrollView();

            var sel0 = d.Selected;
            float dx = x + listW + 8, dw = inner.width - listW - 16;
            var area = new Rect(dx, y, dw, inner.height - 4);
            if (sel0 == null) { Eu.Label(app, area, Loc.T("Pick a dungeon."), Eu.Dim, 12); return; }
            float cy = y;
            Eu.Label(app, new Rect(dx, cy, dw, 22), DungeonsView.BannerTitle(sel0), Eu.Bright, 16, true);
            cy += 24;
            string weeklyTitle = DungeonsView.WeeklyTitle(Json.Get(sel0.Data, "weekly"));
            // difficulties
            float bw = (dw - 5 * 4) / 6;
            bool weekly = Json.Get(sel0.Data, "weekly") is Dictionary<string, object>;
            for (int i = 1; i <= 6; i++)
            {
                var b = new Rect(dx + (i - 1) * (bw + 4), cy, bw, 26);
                bool locked = i > Mathf.Max(1, sel0.Difficulty) || (weekly && i > 1);
                bool on = d.SelectedDifficulty == i;
                string text = locked ? Loc.T("Locked") : Loc.T("Level {0}", i);
                if (on && !locked) ChaosApp.Fill(new Rect(b.x - 2, b.y - 2, b.width + 4, b.height + 4), Eu.Hex(Eu.Gold));
                if (Eu.Button(b, text, !locked)) d.SelectDifficulty(i);
            }
            cy += 32;
            cy += Eu.Wrap(app, dx, cy, dw, DungeonsView.PanelText(d.SelectedDifficulty, Json.Get(sel0.Data, "health")), Eu.Text, 12);

            // requirements
            var req = Json.Get(sel0.Data, "req");
            var parts = new List<string>();
            if (Json.Get(req, "level") is double lv) parts.Add(Loc.T("Level {0}", Fmt.Short(lv)));
            if (Json.Get(req, "party") != null) parts.Add(Loc.T("Party {0}", Json.Get(req, "party") is double pd ? Fmt.Short(pd) : Json.Text(req, "party")));
            if (Json.Get(req, "iLvl") is double il) parts.Add(Loc.T("Item level {0}", Fmt.Short(il)));
            if (Json.Get(req, "gold") is double g) parts.Add(Loc.T("{0} gold", Fmt.Short(g)));
            var quests = Eg.Strings(req, "quests");
            if (quests.Count > 0) parts.Add(Loc.T("Quests: {0}", string.Join(", ", quests)));
            if (parts.Count > 0) { Eu.Label(app, new Rect(dx, cy, dw, 16), Loc.T("Requirements"), Eu.Gold, 12, true); cy += 17; cy += Eu.Wrap(app, dx, cy, dw, string.Join("   ", parts), Eu.Text, 12); }
            var reqItems = Json.List(req, "items");
            if (reqItems.Count > 0)
            {
                for (int i = 0; i < reqItems.Count && i < 6; i++) app.DrawItem(new Rect(dx + i * 34, cy, 32, 32), (ushort)Json.Int(reqItems[i], "clientId"), Json.Int(reqItems[i], "count"));
                cy += 36;
            }

            // loot
            var loot = Json.List(sel0.Data, "loot");
            if (loot.Count > 0)
            {
                Eu.Label(app, new Rect(dx, cy, dw, 16), Loc.T("Boss loot"), Eu.Gold, 12, true);
                cy += 17;
                for (int i = 0; i < loot.Count && i < 28; i++)
                    app.DrawItem(new Rect(dx + (i % 14) * 34, cy + (i / 14) * 34, 32, 32), (ushort)Json.Int(loot[i], "clientId"), Json.Int(loot[i], "count"));
                cy += ((Mathf.Min(loot.Count, 28) + 13) / 14) * 34 + 4;
            }

            // challenges
            var chs = Json.List(sel0.Data, "challenges");
            if (weeklyTitle != null || chs.Count > 0)
            {
                Eu.Label(app, new Rect(dx, cy, dw, 16), Loc.T("Challenges"), Eu.Gold, 12, true);
                cy += 17;
                if (weeklyTitle != null) { cy += Eu.Wrap(app, dx, cy, dw, weeklyTitle, Eu.Bright, 12, true); cy += Eu.Wrap(app, dx + 8, cy, dw - 8, DungeonsView.WeeklyText(Json.Get(sel0.Data, "weekly")), Eu.Dim, 11); }
                foreach (object c in chs)
                {
                    bool done = Json.Truthy(c, "completed");
                    string head = (done ? "[x] " : "[ ] ") + Loc.T("{0} ({1} Points)", Json.Text(c, "title"), Fmt.Short(Json.Number(c, "points")));
                    cy += Eu.Wrap(app, dx, cy, dw, head, done ? Eu.Good : Eu.Text, 12, true);
                    cy += Eu.Wrap(app, dx + 8, cy, dw - 8, Json.Text(c, "desc"), Eu.Dim, 11);
                }
            }

            // leaderboards
            float bottom = y + inner.height - 4;
            float lbH = 92;
            if (cy < bottom - lbH - 78)
            {
                var tabs = new[] { Loc.T("Solo"), Loc.T("Group") };
                for (int i = 0; i < 2; i++)
                    if (GUI.Toggle(new Rect(dx + i * 80, bottom - lbH - 72, 76, 20), board == i, tabs[i], GUI.skin.button) && board != i) board = i;
                var tops = board == 0 ? sel0.Solo : sel0.Group;
                tops.TryGetValue(d.SelectedDifficulty, out var top);
                int shown = 0;
                if (top != null)
                    for (int i = 0; i < top.Count && shown < 4; i++, shown++)
                    {
                        object e = top[i];
                        string rank = Json.Get(e, "self") != null ? Json.Text(e, "self") : (i + 1).ToString();
                        string name = Json.Text(e, "name").Replace("\n", ", ");
                        Eu.Label(app, new Rect(dx, bottom - lbH - 50 + i * 16, dw, 16), rank + ".  " + name + "   " + DungeonsView.MsToShortTime(Json.Number(e, "time")), Json.Get(e, "self") != null ? "#2daadb" : Eu.Text, 11);
                    }
            }

            // queue
            float qy = bottom - 70;
            var det2 = sel0;
            Eu.Label(app, new Rect(dx, qy, dw * 0.6f, 16), Loc.T("Queue: {0}", DungeonsView.QueueStatus(det2.QueuePlayers)), Eg.QueueColor(det2.QueuePlayers), 12, true);
            Eu.Label(app, new Rect(dx, qy + 16, dw * 0.6f, 16), Loc.T("Estimated: {0}", DungeonsView.SecondsToShortTime(det2.QueueEstimatedMs / 1000)), Eu.Text, 11);
            bool queued = d.QueuedId != 0;
            string qd = queued ? (d.Details.TryGetValue(d.QueuedId, out var qdet) ? qdet.Title : "?") : "------";
            Eu.Label(app, new Rect(dx, qy + 32, dw * 0.6f, 16), qd + "  " + (queued ? DungeonsView.SecondsToShortTime(d.QueueWaitedSeconds(now)) : "00:00:00"), Eu.Dim, 11);
            if (GUI.Button(new Rect(dx + dw - 150, qy + 8, 150, 30), queued ? Loc.T("Leave") : Loc.T("Join"))) d.JoinQueue();
        }
    }

    /// <summary>The kill counter of a dungeon run: percent bar, the boss, the bonus objectives, monsters and the time, and the banner.</summary>
    public sealed class DungeonCounterWindow : EgHudWindow
    {
        public override string Title => Loc.T("Dungeon");
        protected override Rect Place(float w, float h) => new Rect(8, 150, 290, 220);
        protected override bool Wanted(ChaosApp app) => app.Session.Endgame.Dungeons.Counter;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var d = app.Session?.Endgame?.Dungeons;
            if (d == null) return;
            double now = app.Session.Now;
            float x = inner.x + 6, w = inner.width - 12, y = inner.y + 2;
            Eu.Bar(app, new Rect(x, y, w, 22), d.Percent, d.BossUnlocked ? "#2f7a2a" : "#8a1010", d.BossUnlocked ? Loc.T("Boss unlocked!") : d.Percent + "%", 12);
            y += 28;
            Eu.Label(app, new Rect(x, y, w, 16), (d.BossUnlocked ? "[x] " : "[ ] ") + Loc.T("Kill {0}% of the monsters to unlock {1}", d.Need, d.BossName), d.BossUnlocked ? Eu.Good : Eu.Text, 11);
            y += 17;
            Eu.Label(app, new Rect(x, y, w, 16), (d.BossKilled ? "[x] " : "[ ] ") + Loc.T("Kill {0}", d.BossName), d.BossKilled ? Eu.Good : (d.BossUnlocked ? Eu.Text : Eu.Dim), 11);
            y += 19;
            for (int i = 0; i < d.Objectives.Count; i++)
            {
                bool done = i < d.ObjectivesDone.Count && d.ObjectivesDone[i];
                Eu.Label(app, new Rect(x, y, w, 16), (done ? "[x] " : "[ ] ") + d.Objectives[i], done ? Eu.Good : Eu.Text, 11);
                y += 16;
            }
            y += 4;
            Eu.Label(app, new Rect(x, y, w, 16), Loc.T("Monsters Alive: {0}", d.MonstersLeft), Eu.Text, 12);
            Eu.Label(app, new Rect(x, y + 16, w, 16), Loc.T("Time left {0}", DungeonsView.MsToShortTime(d.CounterLeftMs(now))), Eu.Gold, 12, true);
            if (d.BannerActive(now)) Eu.Label(app, new Rect(x, y + 36, w, 20), d.Banner, Eu.Bright, 14, true, TextAnchor.UpperCenter);
        }
    }

    // ================================================================================================ Raid
    public sealed class RaidWindow : GameWindow
    {
        bool lastVisible;
        Vector2 scroll;
        public override string Title => Loc.T("Raid: Ashen Sepulchre");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 280, 50, 560, 520);
        public override void Reset() { lastVisible = false; Open = false; }

        public override void Tick(ChaosApp app)
        {
            var r = app.Session?.Endgame?.Raid;
            if (r == null) return;
            WindowSync.Run(ref lastVisible, this, r.Visible, r.Show, r.Hide);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var r = app.Session?.Endgame?.Raid;
            if (r == null) return;
            float x = inner.x + 4, w = inner.width - 8, y = inner.y + 2;
            string[] tabs = { "raids", "journal", "vendor" };
            string[] names = { Loc.T("Raids"), Loc.T("Journal"), Loc.T("Vendor") };
            for (int i = 0; i < 3; i++)
                if (GUI.Toggle(new Rect(x + i * 100, y, 96, 24), r.Tab == tabs[i], names[i], GUI.skin.button) && r.Tab != tabs[i]) r.ShowTab(tabs[i]);
            y += 30;
            var list = new Rect(x, y, w, inner.yMax - y - 60);
            Eu.Panel(list, 0.04f);
            // measure by drawing into a tall virtual area: rows are laid out top to bottom
            float contentH = DrawTab(app, r, new Rect(0, 0, list.width - 18, 3000), true);
            scroll = GUI.BeginScrollView(list, scroll, new Rect(0, 0, list.width - 18, Mathf.Max(list.height, contentH)));
            DrawTab(app, r, new Rect(0, 0, list.width - 18, contentH), false);
            GUI.EndScrollView();

            float by = inner.yMax - 52;
            Eu.Label(app, new Rect(x, by, w, 18), r.Message, r.MessageOk ? Eu.Good : Eu.Bright, 12);
            RaidView.StartState(r.Info, out string why);
            bool can = RaidView.StartState(r.Info, out _);
            if (Eu.Button(new Rect(x, by + 20, 180, 28), Json.Truthy(r.Info, "inRaid") ? Loc.T("In a raid") : Loc.T("Open New Raid"), can)) r.Start();
            if (why.Length > 0) Eu.Label(app, new Rect(x + 188, by + 20, w - 188, 30), why, Eu.Dim, 11, false, TextAnchor.UpperLeft, true);
        }

        float DrawTab(ChaosApp app, RaidState r, Rect area, bool measureOnly)
        {
            float y = 4, x = area.x + 4, w = area.width - 8;
            Func<float, Rect> row = h => { var rc = new Rect(x, y, w, h); y += h + 3; return rc; };
            Action<string, string, int, bool> text = (t, color, size, bold) =>
            {
                float h = Eu.Height(app, t, w, size);
                var rc = row(h);
                if (!measureOnly) Eu.Label(app, rc, t, color, size, bold, TextAnchor.UpperLeft, true);
            };
            if (r.Tab == "raids")
            {
                if (r.Info == null) { text(Loc.T("Asking the server..."), Eu.Dim, 12, false); return y; }
                text(RaidView.RecordLine(r.Info), Eu.Bright, 12, true);
                text(RaidView.LockSummary(r.Info), Eu.Text, 12, false);
                foreach (var l in RaidView.LockRows(r.Info))
                {
                    var rc = row(18);
                    if (measureOnly) continue;
                    Eu.Label(app, new Rect(rc.x, rc.y, rc.width * 0.6f, 18), l.Text, Eu.Text, 12);
                    Eu.Label(app, new Rect(rc.x + rc.width * 0.6f, rc.y, rc.width * 0.4f, 18), l.State, l.Color, 12, false, TextAnchor.UpperRight);
                }
                text(Loc.T("Saved raids"), Eu.Gold, 13, true);
                var saved = Eg.Objects(r.Info, "saved");
                if (saved.Count == 0) text(Loc.T("No saved raid this week."), Eu.Dim, 12, false);
                foreach (object s in saved)
                {
                    var sr = RaidView.SavedRow(s);
                    var rc = row(40);
                    if (measureOnly) continue;
                    Eu.Panel(rc, 0.05f);
                    Eu.Label(app, new Rect(rc.x + 6, rc.y + 2, rc.width - 130, 18), sr.Title, Eu.Text, 13, true);
                    Eu.Label(app, new Rect(rc.x + 6, rc.y + 21, rc.width - 130, 16), sr.Progress + "   " + sr.Next, sr.Color, 11);
                    if (sr.Action.Length > 0 && Eu.Button(new Rect(rc.xMax - 116, rc.y + 8, 110, 24), RaidView.ActionText(sr.Action), sr.Action != "inside"))
                    {
                        if (sr.Action == "continue") r.Continue(sr.Id); else if (sr.Action == "join") r.Join(sr.Id);
                    }
                }
            }
            else if (r.Tab == "journal")
            {
                if (r.JournalBosses.Count == 0) text(Loc.T("Asking the server..."), Eu.Dim, 12, false);
                for (int i = 0; i < r.JournalBosses.Count; i++)
                {
                    var j = RaidView.Journal(r.JournalBosses[i], i + 1);
                    text(j.Title, Eu.Bright, 14, true);
                    if (j.Intro.Length > 0) text(j.Intro, Eu.Text, 12, false);
                    text(j.Roles, Eu.Text, 12, false);
                    text(j.Phases, Eu.Text, 12, false);
                    foreach (var m in j.Mech) text(m, Eu.Text, 11, false);
                    text(Loc.T("Loot"), Eu.Gold, 12, true);
                    foreach (var l in j.Loot) text("- " + l, Eu.Dim, 11, false);
                    y += 6;
                }
            }
            else
            {
                if (r.Info == null) { text(Loc.T("Asking the server..."), Eu.Dim, 12, false); return y; }
                double marks = Json.Number(r.Info, "marks");
                text(Loc.T("Sepulchre Marks: {0}", Eg.Number(marks)), Eu.Bright, 13, true);
                foreach (object e in RaidView.VendorStock(r.Info))
                {
                    var v = RaidView.VendorRow(e, marks);
                    float sh = Eu.Height(app, v.Sub, w - 150, 11);
                    var rc = row(Mathf.Max(40, 22 + sh));
                    if (measureOnly) continue;
                    Eu.Panel(rc, 0.05f);
                    Eu.Label(app, new Rect(rc.x + 6, rc.y + 2, rc.width - 150, 18), v.Name, Eu.Text, 13, true);
                    Eu.Label(app, new Rect(rc.x + 6, rc.y + 20, rc.width - 150, sh), v.Sub, Eu.Dim, 11, false, TextAnchor.UpperLeft, true);
                    Eu.Label(app, new Rect(rc.xMax - 140, rc.y + 2, 134, 16), v.Limit, Eu.Dim, 11, false, TextAnchor.UpperRight);
                    if (Eu.Button(new Rect(rc.xMax - 116, rc.y + 18, 110, 22), v.Button, v.Can)) r.Buy(v.Key);
                }
            }
            return y + 4;
        }
    }

    /// <summary>The raid HUD: the boss and its health, phase, enrage clock, progress, raiders, stacks, and the call-out line.</summary>
    public sealed class RaidHudWindow : EgHudWindow
    {
        public override string Title => Loc.T("Raid");
        protected override Rect Place(float w, float h) => new Rect(8, 108, 280, 190);
        protected override bool Wanted(ChaosApp app) => app.Session.Endgame.Raid.Hud != null;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var r = app.Session?.Endgame?.Raid;
            if (r == null || r.Hud == null) return;
            double now = app.Session.Now;
            var d = r.Hud;
            float x = inner.x + 6, w = inner.width - 12, y = inner.y + 2;
            Eu.Label(app, new Rect(x, y, w, 18), RaidView.HudTitle(d), Eu.Bright, 14, true);
            y += 20;
            Eu.Label(app, new Rect(x, y, w, 16), RaidView.BossLine(d), Eu.Text, 12);
            y += 16;
            if (Json.Text(d, "state") == "fight")
            {
                double hp = Json.Get(d, "hp") is double h ? h : 100;
                Eu.Bar(app, new Rect(x, y, w, 14), hp, Json.Truthy(d, "enraged") ? "#c01010" : "#8a1010", (int)hp + "%");
                y += 18;
            }
            string phase = RaidView.PhaseLine(d);
            if (phase.Length > 0) { Eu.Label(app, new Rect(x, y, w, 16), phase, Eu.Text, 11); y += 16; }
            string clock = RaidView.EnrageText(d, r.EnrageLeft(now), out string cc);
            if (clock.Length > 0) { Eu.Label(app, new Rect(x, y, w, 18), clock, cc, 13, true); y += 18; }
            Eu.Bar(app, new Rect(x, y, w, 14), RaidView.Progress(d), "#8a3a10", Loc.T("{0} / {1} bosses slain", Json.Int(d, "done"), Json.Int(d, "total")));
            y += 18;
            Eu.Label(app, new Rect(x, y, w, 16), RaidView.CountsLine(d), Eu.Text, 11);
            y += 16;
            string st = RaidView.StacksLine(d);
            if (st.Length > 0) { Eu.Label(app, new Rect(x, y, w, 16), st, Eu.Bad, 11, true); y += 16; }
            foreach (string a in Eg.Strings(d, "alerts")) { Eu.Label(app, new Rect(x, y, w, 16), a, Eu.Bright, 11); y += 15; }
        }
    }

    /// <summary>The raid call-out: one coloured line near the top of the screen for a few seconds.</summary>
    public sealed class RaidCalloutWindow : GameWindow
    {
        public override string Title => Loc.T("Raid");
        public override bool InMenu => false;
        public override bool ClampToScreen => true;
        // the body is the window less 32 (title bar and frame): 40 left a 8 high body and a label 4 high, so only the title bar showed (phase 12, track H). 28 for the line, 32 for the bar and frame.
        public override bool Resizable => false;
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 260, 96, 520, 32 + 30);

        public override void Tick(ChaosApp app)
        {
            var r = app.Session?.Endgame?.Raid;
            Open = r != null && r.Callout.Active(app.Session.Now);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var r = app.Session?.Endgame?.Raid;
            if (r == null) return;
            Eu.Label(app, new Rect(inner.x + 4, inner.y + 2, inner.width - 8, inner.height - 4), r.Callout.Text, RaidView.AlertColor(r.Callout.Kind), 15, true, TextAnchor.MiddleCenter, true);
        }
    }
}
