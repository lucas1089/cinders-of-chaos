// Crafting Tables (opcode 91, Core/CollectCraftTable.cs): seven tabs of recipes (general crafting, woodcutting, mining, herbalist, armorsmith, weaponsmith, jewelsmith), search,
// "craftable" filter, materials with what you carry, gold, skill, rarity odds, quantity and the craft with its progress bar. Using a table opens its tab; you must stand next to it.
// The row tooltip of the main client (opcode 91 "tip") is shown as plain text. Top menu (Economy) opens the last tab.
using System.Collections.Generic;
using System.Linq;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class CraftTableWindow : ModelWindow
    {
        public override string Title => Loc.T("Crafting Tables");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 380, 40, 760, 600);

        Vector2 listScroll, matScroll;

        protected override bool ModelVisible(ChaosApp app) => app.Session.CraftTable.Visible;
        protected override void ModelShow(ChaosApp app) => app.Session.CraftTable.Show();
        protected override void ModelHide(ChaosApp app) => app.Session.CraftTable.Hide();

        protected override void Body(ChaosApp app, Rect inner)
        {
            var t = app.Session?.CraftTable;
            if (t == null) return;
            double now = app.Session.Now;
            string at = t.TableCategory(now);
            CU.Label(app, new Rect(inner.x + 6, inner.y, inner.width - 12, 36), t.HintText(now), "#c8b89a");
            // tabs
            var labels = CraftTableState.Categories.Select(c => Loc.T(c.Name) + (c.Key == at ? " *" : "")).ToArray();
            int cur = System.Array.FindIndex(CraftTableState.Categories, c => c.Key == t.Current);
            int tab = CU.Tabs(new Rect(inner.x + 4, inner.y + 38, inner.width - 8, 24), labels, Mathf.Max(0, cur), 60);
            if (tab != cur) { t.SelectTab(CraftTableState.Categories[tab].Key, now); listScroll = Vector2.zero; }
            var cat = CraftTableState.Category(t.Current);
            var ctx = t.Context(t.Current, now);
            float y = inner.y + 94;
            GUI.Label(new Rect(inner.x + 6, y, 260, 20), t.Money.HasValue ? Loc.T("Gold carried: {0}", CraftTableState.GoldText(t.Money.Value)) : "", app.SmallStyle);
            GUI.Label(new Rect(inner.x + 270, y, 200, 20), ctx.Skill.HasValue ? Loc.T("{0} skill: {1}", Loc.T(CraftTableState.SkillNames[cat.Skill - 7]), ctx.Skill.Value) : "", app.SmallStyle);
            y += 22;

            // the list
            float lw = 330;
            t.Search = CU.Field(app, new Rect(inner.x + 4, y, lw - 160, 22), "craftSearch", t.Search, 30);
            if (t.Search.Length == 0 && Event.current.type == EventType.Repaint && GUI.GetNameOfFocusedControl() != "craftSearch") GUI.Label(new Rect(inner.x + 6, y, 100, 22), Loc.T("Search"), app.SmallStyle);
            if (GUI.Toggle(new Rect(inner.x + lw - 152, y, 70, 22), t.Mode == "all", Loc.T("All"), GUI.skin.button)) t.Mode = "all";
            if (GUI.Toggle(new Rect(inner.x + lw - 78, y, 76, 22), t.Mode == "craftable", Loc.T("Craftable"), GUI.skin.button)) t.Mode = "craftable";
            var all = t.Recipes(t.Current);
            var shown = CraftTableState.Filter(all, t.Search, t.Mode, ctx);
            if (!t.Selected.ContainsKey(t.Current) && shown.Count > 0) t.Selected[t.Current] = shown[0].Index;
            var list = new Rect(inner.x + 4, y + 26, lw, inner.yMax - y - 30);
            if (shown.Count == 0) GUI.Label(new Rect(list.x + 4, list.y + 4, list.width, 22), all.Count == 0 ? Loc.T("Loading...") : t.Mode == "craftable" ? Loc.T("Nothing you can craft now.") : Loc.T("No recipe matches."), app.SmallStyle);
            listScroll = CU.Rows(list, listScroll, shown.Count, 44, (i, r) =>
            {
                var rec = shown[i];
                var check = CraftTableState.Check(rec, ctx);
                bool sel = t.Selected.TryGetValue(t.Current, out int si) && si == rec.Index;
                ChaosApp.Fill(r, sel ? new Color(0.23f, 0.16f, 0.13f, 1f) : new Color(0.1f, 0.08f, 0.1f, 1f));
                app.DrawItem(new Rect(r.x + 3, r.y + 5, 32, 32), (ushort)rec.ClientId, 1);
                CU.Label(app, new Rect(r.x + 40, r.y + 2, r.width - 110, 18), rec.Name, sel ? "#f6cf72" : "#e8b84a", false);
                CU.Label(app, new Rect(r.x + 40, r.y + 21, r.width - 110, 18), CraftTableState.RowSub(rec), "#8c8070", false);
                string st; string col;
                if (rec.Locked) { st = Loc.T("Locked"); col = CraftTableState.Bad; }
                else if (check.RecipeOk) { st = Loc.T("Ready"); col = CraftTableState.Good; }
                else if (ctx.Skill.HasValue && ctx.Skill.Value < rec.Level) { st = Loc.T("Skill {0}", rec.Level); col = "#6b6258"; }
                else { st = Loc.T("Missing"); col = CraftTableState.Warn; }
                CU.Label(app, new Rect(r.xMax - 66, r.y + 12, 62, 18), st, col, false, TextAnchor.UpperRight);
                if (Event.current.type == EventType.MouseDown && Event.current.button == 0 && r.Contains(Event.current.mousePosition)) { t.SelectRecipe(rec.Index); Event.current.Use(); }
            });

            Detail(app, t, ctx, new Rect(inner.x + lw + 12, y, inner.width - lw - 16, inner.yMax - y - 4), now);
            CU.Tooltip(app, new Rect(0, 0, Area.width, Area.height));
        }

        void Detail(ChaosApp app, CraftTableState t, CraftContext ctx, Rect d, double now)
        {
            var r = t.SelectedRecipe();
            if (r == null) { GUI.Label(new Rect(d.x, d.y, d.width, 22), Loc.T("Choose a recipe"), app.TitleStyle); return; }
            var check = CraftTableState.Check(r, ctx);
            var cat = CraftTableState.Category(r.Category);
            ChaosApp.Fill(new Rect(d.x, d.y, 44, 44), new Color(0.11f, 0.09f, 0.12f, 1f));
            app.DrawItem(new Rect(d.x + 6, d.y + 6, 32, 32), (ushort)r.ClientId, r.Count);
            GUI.Label(new Rect(d.x + 50, d.y, d.width - 50, 22), new GUIContent(r.Name, CraftTableState.PlainTip(r)), app.TitleStyle);
            GUI.Label(new Rect(d.x + 50, d.y + 24, d.width - 50, 20), Loc.T("{0}{1} recipe {2}", r.Count > 1 ? "x" + r.Count + "  -  " : "", cat.Name, r.Index), app.SmallStyle);
            float y = d.y + 52;
            string skillName = Loc.T(CraftTableState.SkillNames[cat.Skill - 7]);
            CU.Label(app, new Rect(d.x, y, d.width, 18), ctx.Skill.HasValue ? Loc.T("{0} skill: {1} needed, yours {2}", skillName, r.Level, ctx.Skill.Value) : Loc.T("{0} skill: {1} needed", skillName, r.Level), ctx.Skill.HasValue ? (ctx.Skill.Value >= r.Level ? CraftTableState.Good : CraftTableState.Bad) : null, false);
            y += 18;
            CU.Label(app, new Rect(d.x, y, d.width, 18), t.Money.HasValue ? Loc.T("Gold: {0} (you carry {1})", CraftTableState.GoldText(r.Cost), CraftTableState.GoldText(t.Money.Value)) : Loc.T("Gold: {0}", CraftTableState.GoldText(r.Cost)), t.Money.HasValue ? (t.Money.Value >= r.Cost ? CraftTableState.Good : CraftTableState.Bad) : null, false);
            y += 18;
            if (r.Locked) { CU.Label(app, new Rect(d.x, y, d.width, 36), CraftTableState.ReasonText("locked", r, ctx), CraftTableState.Bad); y += 36; }
            string bonus = CraftTableState.BonusText(r);
            if (bonus.Length > 0) { CU.Label(app, new Rect(d.x, y, d.width, 36), bonus, "#8c8070"); y += 36; }
            GUI.Label(new Rect(d.x, y + 2, d.width, 18), Loc.T("Materials"), app.TitleStyle);
            y += 22;
            float matH = d.yMax - y - 130;
            matScroll = CU.Rows(new Rect(d.x, y, d.width, matH), matScroll, r.Materials.Count, 38, (i, rr) =>
            {
                var m = r.Materials[i];
                ChaosApp.Fill(rr, new Color(1f, 1f, 1f, 0.04f));
                app.DrawItem(new Rect(rr.x + 3, rr.y + 3, 32, 32), (ushort)m.ClientId, 1);
                GUI.Label(new Rect(rr.x + 40, rr.y + 9, rr.width - 140, 20), CraftTableState.MaterialName(m), app.SmallStyle);
                CU.Label(app, new Rect(rr.xMax - 96, rr.y + 9, 92, 20), CraftTableState.HaveNeed(m), check.Mats[i] ? CraftTableState.Good : CraftTableState.Bad, false, TextAnchor.UpperRight);
            });
            float by = d.yMax - 122;
            bool busy = t.Craft != null;
            int max = CraftTableState.MaxCraftable(r, t.Money);
            t.Qty = CraftTableState.ClampQty(t.Qty, max);
            if (CU.Button(new Rect(d.x, by, 30, 26), "-", !busy && t.Qty > 1)) t.ChangeQty(-1, now);
            GUI.Label(new Rect(d.x + 34, by + 3, 60, 22), "x " + t.Qty, app.SmallStyle);
            if (CU.Button(new Rect(d.x + 92, by, 30, 26), "+", !busy && t.Qty < max)) t.ChangeQty(1, now);
            if (CU.Button(new Rect(d.x + 132, by, d.width - 132, 30), busy ? Loc.T("Crafting...") : t.Qty > 1 ? Loc.T("Craft x{0}", t.Qty) : Loc.T("Craft"), check.Ok && !busy)) t.DoCraft(now);
            if (t.ProgressPct >= 0) CU.Bar(app, new Rect(d.x, by + 36, d.width, 14), (int)t.ProgressPct, null, new Color(0.6f, 0.4f, 0.15f));
            string block = busy ? "" : CraftTableState.BlockText(check, r, ctx);
            CU.Label(app, new Rect(d.x, by + 54, d.width, 34), block.Length > 0 ? block : t.StatusText, block.Length > 0 ? CraftTableState.Warn : t.StatusColor);
            if (block.Length > 0 && t.StatusText.Length > 0) CU.Label(app, new Rect(d.x, by + 88, d.width, 30), t.StatusText, t.StatusColor);
        }
    }
}
