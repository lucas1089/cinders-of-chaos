// Bestiary and Kill Tasks (opcode 253, Core/CollectBestiary.cs): monster list by category with search and pages, the entry of a monster (stage, elements, loot, bonus,
// task) and the kill task board with the tracker lines. Reached from the top menu (Hunt).
using System.Collections.Generic;
using System.Linq;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class BestiaryWindow : ModelWindow
    {
        public override string Title => Loc.T("Bestiary");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 360, 40, 720, 600);

        Vector2 catScroll, listScroll, infoScroll, boardScroll, activeScroll;

        protected override bool ModelVisible(ChaosApp app) => app.Session.Bestiary.Visible;
        protected override void ModelShow(ChaosApp app) => app.Session.Bestiary.Show();
        protected override void ModelHide(ChaosApp app) => app.Session.Bestiary.Hide();

        protected override void Body(ChaosApp app, Rect inner)
        {
            var b = app.Session?.Bestiary;
            if (b == null) return;
            int tab = CU.Tabs(new Rect(inner.x + 4, inner.y, 300, 24), new[] { Loc.T("Bestiary"), Loc.T("Kill Tasks") }, b.Tab == "tasks" ? 1 : 0);
            if ((tab == 1 ? "tasks" : "bestiary") != b.Tab) b.SetTab(tab == 1 ? "tasks" : "bestiary");
            if (b.Summary == null) { GUI.Label(new Rect(inner.x + 8, inner.y + 34, 300, 22), Loc.T("Loading the bestiary..."), app.SmallStyle); return; }
            GUI.Label(new Rect(inner.x + 310, inner.y + 2, inner.width - 314, 20), new GUIContent(b.HeaderText(), b.HeaderTip()), app.SmallStyle);
            var body = new Rect(inner.x, inner.y + 30, inner.width, inner.height - 30);
            if (b.Tab == "tasks") Tasks(app, b, body); else Entries(app, b, body);
            CU.Tooltip(app, new Rect(0, 0, Area.width, Area.height));
        }

        void Entries(ChaosApp app, BestiaryState b, Rect body)
        {
            // categories
            var cats = new List<KeyValuePair<string, string>> { new KeyValuePair<string, string>(BestiaryState.All, Loc.T("All ({0} / {1})", CF.I(b.Summary, "known"), CF.I(b.Summary, "total"))) };
            foreach (var c in CF.Rows(CF.G(b.Summary, "cats")))
                cats.Add(new KeyValuePair<string, string>(CF.Str(CF.G(c, "key")), string.Format("{0} ({1} / {2})", CF.T(c, "name"), CF.I(c, "known"), CF.I(c, "total"))));
            var catRect = new Rect(body.x + 4, body.y, 150, body.height - 4);
            catScroll = CU.Rows(catRect, catScroll, cats.Count, 26, (i, r) =>
            {
                bool on = cats[i].Key == b.SelectedCat;
                if (GUI.Toggle(new Rect(r.x, r.y, r.width, 24), on, cats[i].Value, GUI.skin.button) && !on) { b.SelectedCat = cats[i].Key; b.Page = 1; listScroll = Vector2.zero; }
            });

            // the list
            float x = body.x + 160, w = 260;
            b.Search = CU.Field(app, new Rect(x, body.y, w - 100, 22), "bestiarySearch", b.Search, 30);
            if (b.Search.Length == 0 && Event.current.type == EventType.Repaint && GUI.GetNameOfFocusedControl() != "bestiarySearch") GUI.Label(new Rect(x + 2, body.y, w - 100, 22), "  " + Loc.T("Search"), app.SmallStyle);
            b.KnownOnly = GUI.Toggle(new Rect(x + w - 94, body.y, 94, 22), b.KnownOnly, Loc.T("Known only"), GUI.skin.toggle);
            if (!b.ListComplete) { GUI.Label(new Rect(x + 4, body.y + 30, w, 22), Loc.T("Loading the bestiary..."), app.SmallStyle); }
            else
            {
                var filtered = b.Filtered();
                var part = BestiaryState.Paged(filtered, b.Page, BestiaryState.PageSize, out int page, out int pages);
                b.Page = page;
                var list = new Rect(x, body.y + 26, w, body.height - 56);
                if (part.Count == 0) GUI.Label(new Rect(list.x + 4, list.y + 4, list.width, 22), Loc.T("No monster matches."), app.SmallStyle);
                listScroll = CU.Rows(list, listScroll, part.Count, 22, (i, r) =>
                {
                    var m = part[i];
                    bool sel = m.Id == b.SelectedId;
                    ChaosApp.Fill(r, sel ? new Color(0.35f, 0.25f, 0.1f, 1f) : new Color(1f, 1f, 1f, 0.04f));
                    ChaosApp.Fill(new Rect(r.x + 3, r.y + 6, 8, 8), CU.Hex(BestiaryState.StageColors[Mathf.Clamp(m.Stage, 0, 4)], Color.gray));
                    var st = new GUIStyle(app.SmallStyle);
                    st.normal.textColor = m.Stage >= 1 ? new Color(0.84f, 0.79f, 0.68f) : new Color(0.42f, 0.38f, 0.34f);
                    GUI.Label(new Rect(r.x + 16, r.y, r.width - 110, 20), m.Name, st);
                    GUI.Label(new Rect(r.xMax - 94, r.y, 40, 20), Loc.T("lv {0}", m.Level), app.SmallStyle);
                    GUI.Label(new Rect(r.xMax - 54, r.y, 52, 20), m.Kills > 0 ? CF.Group(m.Kills) : "-", app.SmallStyle);
                    if (Event.current.type == EventType.MouseDown && Event.current.button == 0 && r.Contains(Event.current.mousePosition)) { b.SelectEntry(m.Id); Event.current.Use(); }
                });
                float py = list.yMax + 4;
                if (CU.Button(new Rect(x, py, 40, 22), "<", page > 1)) b.Page = page - 1;
                GUI.Label(new Rect(x + 46, py, w - 92, 22), Loc.T("Page {0} / {1}  ({2})", page, pages, filtered.Count), app.SmallStyle);
                if (CU.Button(new Rect(x + w - 40, py, 40, 22), ">", page < pages)) b.Page = page + 1;
            }

            // the entry
            var d = new Rect(x + w + 6, body.y, body.xMax - x - w - 10, body.height - 4);
            Detail(app, b, d);
        }

        void Detail(ChaosApp app, BestiaryState b, Rect d)
        {
            if (b.Detail == null) { GUI.Label(new Rect(d.x + 4, d.y + 4, d.width, 22), Loc.T("Select a monster"), app.SmallStyle); return; }
            var e = b.Detail as Dictionary<string, object>;
            int stage = CF.I(e, "stage");
            var th = CF.Values(CF.G(e, "th"));
            float y = d.y;
            if (stage >= 1 && CF.G(e, "outfit") is Dictionary<string, object> of && CF.I(of, "type") > 0)
                app.DrawOutfit(new Rect(d.x, y, 64, 64), new Outfit { LookType = CF.I(of, "type"), Head = CF.I(of, "head"), Body = CF.I(of, "body"), Legs = CF.I(of, "legs"), Feet = CF.I(of, "feet"), Addons = CF.I(of, "addons") });
            var nameStyle = new GUIStyle(app.TitleStyle);
            GUI.Label(new Rect(d.x + 70, y, d.width - 70, 22), CF.T(e, "name"), nameStyle);
            CU.Label(app, new Rect(d.x + 70, y + 22, d.width - 70, 18), string.Format("{0} - {1}", b.StageName(stage), BestiaryState.KillText(CF.N(e, "kills"), CF.G(e, "next"))), BestiaryState.StageColors[Mathf.Clamp(stage, 0, 4)], false);
            CU.Bar(app, new Rect(d.x + 70, y + 42, d.width - 70, 14), BestiaryState.StagePercent(CF.N(e, "kills"), th),
                CF.G(e, "next") != null ? Loc.T("Next: {0} at {1}", b.StageName(stage + 1), CF.I(e, "next")) : Loc.T("Completed"), stage >= 4 ? new Color(0.18f, 0.48f, 0.16f) : new Color(0.54f, 0.06f, 0.06f));
            y += 70;
            // task line and button
            var task = CF.M(e, "task");
            float footer = 56f;
            var info = new Rect(d.x, y, d.width, d.yMax - y - footer);
            var lines = DetailLines(b, e, stage);
            float h = 0;
            foreach (var l in lines) h += l.Height(app, info.width - 20);
            infoScroll = GUI.BeginScrollView(info, infoScroll, new Rect(0, 0, info.width - 18, Mathf.Max(info.height, h)));
            float ly = 0;
            foreach (var l in lines) { float lh = l.Height(app, info.width - 20); l.Draw(app, new Rect(0, ly, info.width - 20, lh)); ly += lh; }
            GUI.EndScrollView();
            float fy = d.yMax - footer + 4;
            string tl = CF.B(task, "active") ? Loc.T("You hold a kill task for it.") : CF.B(task, "can") ? Loc.T("Task: {0} kills. {1}", CF.I(task, "required"), BestiaryState.RewardText(CF.G(task, "reward"))) : CF.T(task, "text");
            GUI.Label(new Rect(d.x, fy, d.width - 100, 40), tl, CU.Wrap(app));
            if (CU.Button(new Rect(d.xMax - 96, fy, 94, 26), Loc.T("Take task"), CF.B(task, "can") && !CF.B(task, "active"))) b.TakeTask(CF.I(e, "id"));
        }

        sealed class Line
        {
            public string Text = "", Color; public bool Header; public List<Dictionary<string, object>> Items; public bool Chance;
            public float Height(ChaosApp app, float w) => Items != null ? Mathf.Ceil(Items.Count / Mathf.Max(1f, Mathf.Floor(w / 36f))) * 36f + 4 : Header ? 22 : CU.Wrap(app).CalcHeight(new GUIContent(Text), w) + 2;
            public void Draw(ChaosApp app, Rect r)
            {
                if (Items != null)
                {
                    int per = Mathf.Max(1, (int)(r.width / 36f));
                    for (int i = 0; i < Items.Count; i++)
                    {
                        var it = Items[i];
                        var cell = new Rect(r.x + (i % per) * 36, r.y + (i / per) * 36, 34, 34);
                        ChaosApp.Fill(cell, new Color(0.11f, 0.09f, 0.12f, 1f));
                        app.DrawItem(new Rect(cell.x + 1, cell.y + 1, 32, 32), (ushort)CF.I(it, "cid"), 1);
                        string tip = CF.T(it, "name");
                        if (Chance) { tip += " - " + BestiaryState.ChanceText(CF.N(it, "chance")); if (CF.I(it, "max") > 1) tip += Loc.T(", up to {0}", CF.I(it, "max")); }
                        if (CF.B(it, "bossOnly")) tip += Loc.T(" (boss kills only)");
                        GUI.Label(cell, new GUIContent("", tip));
                    }
                    return;
                }
                var st = new GUIStyle(Header ? app.TitleStyle : CU.Wrap(app));
                if (Color != null) st.normal.textColor = CU.Hex(Color, st.normal.textColor);
                GUI.Label(r, Text, st);
            }
        }

        List<Line> DetailLines(BestiaryState b, Dictionary<string, object> e, int stage)
        {
            var o = new List<Line>();
            Line H(string t) { var l = new Line { Text = t, Header = true }; o.Add(l); return l; }
            Line T(string t, string c = null) { var l = new Line { Text = t, Color = c }; o.Add(l); return l; }
            H(string.Format("{0} - {1}", b.CatName(CF.Str(CF.G(e, "cat"))), CF.G(e, "diffName") as string ?? b.DiffName(CF.Str(CF.G(e, "diff")))));
            if (stage < 1)
            {
                T(Loc.T("Not discovered yet: kill one to discover it."), "#8c8070");
                T(Loc.T("Hunting level about {0}.", CF.I(e, "level")));
                if (CF.G(e, "spawns") == null) T(Loc.T("It does not live anywhere on the map."), "#8c8070");
            }
            else
            {
                if (CF.I(e, "minLevel") > 0) T(Loc.T("Level {0}-{1} (scales with the area)", CF.I(e, "minLevel"), CF.I(e, "maxLevel")));
                else T(Loc.T("Hunting level about {0}", CF.I(e, "level")));
                T(Loc.T("Health {0}   Experience {1}", CF.Group(CF.N(e, "health")), CF.Group(CF.N(e, "exp"))));
            }
            var pts = CF.Values(CF.G(e, "points"));
            if (pts.Count > 0) T(Loc.T("Bestiary points per stage: {0}", string.Join(" / ", pts)), "#8c8070");
            if (stage >= 2)
            {
                H(Loc.T("Damage taken"));
                string els = BestiaryState.ElementsText(CF.G(e, "elements"));
                T(els.Length > 0 ? els : Loc.T("No strength or weakness."));
                var imm = CF.Values(CF.G(e, "immunities"));
                if (imm.Count > 0) T(Loc.T("Immune to {0}", string.Join(", ", imm)));
                H(Loc.T("Where it lives"));
                var areas = CF.Rows(CF.G(e, "areas"));
                if (areas.Count == 0) T(Loc.T("Nowhere on the map."), "#8c8070");
                foreach (var a in areas) T("- " + CF.T(a, "text"));
            }
            var loot = CF.Rows(CF.G(e, "loot"));
            if (stage >= 2 && loot.Count > 0) { H(stage >= 3 ? Loc.T("Loot") : Loc.T("Loot highlights (rarest)")); o.Add(new Line { Items = loot, Chance = true }); }
            else if (stage < 2) { H(Loc.T("More at stage 2")); T(Loc.T("Elements, where it lives and the rarest loot unlock at {0}.", b.StageName(2)), "#8c8070"); }
            var uniques = CF.Rows(CF.G(e, "uniques"));
            if (uniques.Count > 0) { H(Loc.T("Chaos uniques it can drop")); o.Add(new Line { Items = uniques }); }
            var bonus = CF.M(e, "bonus");
            H(Loc.T("Completion bonus"));
            T(Loc.T("+{0}% damage and +{1}% experience against it", CF.I(bonus, "damage"), CF.I(bonus, "exp")), stage >= 4 ? "#7fd07f" : "#8c8070");
            if (stage < 4) T(Loc.T("(active once the entry is completed)"), "#8c8070");
            return o;
        }

        void Tasks(ChaosApp app, BestiaryState b, Rect body)
        {
            if (b.Board == null) { GUI.Label(new Rect(body.x + 8, body.y + 4, 300, 22), Loc.T("Loading..."), app.SmallStyle); return; }
            var bd = b.Board;
            GUI.Label(new Rect(body.x + 6, body.y, body.width - 220, 20), new GUIContent(BestiaryState.LimitsText(bd), Loc.T("Tasks you hold, tasks completed today and this week (a task day starts at 06:00).")), app.SmallStyle);
            GUI.Label(new Rect(body.xMax - 200, body.y, 196, 20), Loc.T("New board in {0}", CF.HoursMinutes(b.NextIn(app.Session.Now))), app.SmallStyle);
            int rerolls = CF.I(bd, "rerolls");
            float y = body.y + 22;
            if (rerolls > 0 && GUI.Button(new Rect(body.xMax - 170, y, 166, 22), Loc.T("Reroll board ({0})", rerolls))) b.Reroll();
            string why = BestiaryState.AcceptBlock(bd);
            var offers = CF.Rows(CF.G(bd, "offers"));
            var tasks = CF.Rows(CF.G(bd, "tasks"));
            float half = (body.yMax - y - 30) / 2;
            GUI.Label(new Rect(body.x + 6, y, 200, 20), Loc.T("Today's board"), app.TitleStyle);
            var offerRect = new Rect(body.x + 4, y + 22, body.width - 8, half - 22);
            boardScroll = CU.Rows(offerRect, boardScroll, offers.Count, 40, (i, r) => TaskRow(app, b, offers[i], CF.T(offers[i], "state"), r, why));
            if (offers.Count == 0) GUI.Label(new Rect(offerRect.x + 6, offerRect.y + 4, 300, 20), Loc.T("No offers right now."), app.SmallStyle);
            float y2 = y + half + 4;
            GUI.Label(new Rect(body.x + 6, y2, 200, 20), Loc.T("Your tasks"), app.TitleStyle);
            var activeRect = new Rect(body.x + 4, y2 + 22, body.width - 8, body.yMax - y2 - 26);
            activeScroll = CU.Rows(activeRect, activeScroll, tasks.Count, 40, (i, r) => TaskRow(app, b, tasks[i], "active", r, why));
            if (tasks.Count == 0) GUI.Label(new Rect(activeRect.x + 6, activeRect.y + 4, 400, 20), Loc.T("No task yet: take one from the board."), app.SmallStyle);
        }

        void TaskRow(ChaosApp app, BestiaryState b, Dictionary<string, object> t, string state, Rect r, string block)
        {
            ChaosApp.Fill(r, new Color(1f, 1f, 1f, 0.04f));
            bool family = CF.T(t, "kind") == "family";
            if (CF.G(t, "outfit") is Dictionary<string, object> of && CF.I(of, "type") > 0)
                app.DrawOutfit(new Rect(r.x + 2, r.y + 2, 34, 34), new Outfit { LookType = CF.I(of, "type"), Head = CF.I(of, "head"), Body = CF.I(of, "body"), Legs = CF.I(of, "legs"), Feet = CF.I(of, "feet") });
            CU.Label(app, new Rect(r.x + 40, r.y, 60, 18), family ? Loc.T("FAMILY") : Loc.T("HUNT"), family ? "#b070ff" : "#8c8070", false);
            GUI.Label(new Rect(r.x + 100, r.y, r.width - 330, 18), family ? Loc.T("{0} family", CF.T(t, "label")) : CF.T(t, "label"), app.SmallStyle);
            CU.Label(app, new Rect(r.x + 40, r.y + 18, r.width - 260, 18), BestiaryState.TaskText(t), "#c8b89a", false);
            GUI.Label(new Rect(r.xMax - 280, r.y, 170, 18), new GUIContent(BestiaryState.RewardShort(CF.G(t, "reward")), Loc.T("Reward: {0} (gold to your bank)", BestiaryState.RewardText(CF.G(t, "reward")))), app.SmallStyle);
            if (state == "active")
            {
                CU.Bar(app, new Rect(r.xMax - 280, r.y + 20, 170, 14), CF.Percent(CF.N(t, "progress"), Mathf.Max(1, CF.I(t, "required"))), (long)CF.N(t, "progress") + " / " + CF.I(t, "required"), new Color(0.64f, 0.52f, 0.29f));
                if (GUI.Button(new Rect(r.xMax - 100, r.y + 6, 96, 26), new GUIContent(Loc.T("Abandon"), Loc.T("Drop this task (its progress is lost).")))) b.Abandon(CF.T(t, "key"));
            }
            else if (state == "open") { if (CU.Button(new Rect(r.xMax - 100, r.y + 6, 96, 26), Loc.T("Accept"), block == null, block)) b.Accept(CF.T(t, "key")); }
            else CU.Button(new Rect(r.xMax - 100, r.y + 6, 96, 26), state == "done" ? Loc.T("Done today") : Loc.T("Taken"), false);
        }
    }
}
