// Crafting bench (opcode 232, Core/CollectCrafting.cs): put a gear item on the bench (pick it from the grid or drop a backpack item on the slot), see its modifiers, use orbs
// (click a modifier first for the orbs that aim), sockets and gems, quality, history; the Salvage tab (item, whole bag, shards into orbs) and a short guide.
// Lock and unlock an item from the bench. The right-click Lock entries of the main client's item menu are not in Unity. Top menu (Economy).
using System.Collections.Generic;
using System.Linq;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class CraftingWindow : ModelWindow
    {
        public override string Title => Loc.T("Crafting Bench");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 400, 30, 800, 640);

        Vector2 modScroll, orbScroll, gearScroll, histScroll, recipeScroll, guideScroll;
        bool guide, confirmAll;
        int guidePage;

        protected override bool ModelVisible(ChaosApp app) => app.Session.Crafting.Visible;
        protected override void ModelShow(ChaosApp app) => app.Session.Crafting.Show();
        protected override void ModelHide(ChaosApp app) { app.Session.Crafting.Hide(); confirmAll = false; }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var c = app.Session?.Crafting;
            if (c == null) return;
            if (c.State == null) { GUI.Label(new Rect(inner.x + 8, inner.y + 8, 300, 22), Loc.T("Loading..."), app.SmallStyle); return; }
            int tab = CU.Tabs(new Rect(inner.x + 4, inner.y, 300, 24), new[] { Loc.T("Orbs"), Loc.T("Salvage") }, c.Mode == "salvage" ? 1 : 0);
            if ((tab == 1 ? "salvage" : "orbs") != c.Mode) c.SetMode(tab == 1 ? "salvage" : "orbs");
            if (GUI.Button(new Rect(inner.xMax - 90, inner.y, 86, 24), guide ? Loc.T("Bench") : Loc.T("Guide"))) guide = !guide;
            var body = new Rect(inner.x, inner.y + 28, inner.width, inner.height - 28);
            if (guide) Guide(app, c, body);
            else
            {
                float left = 300;
                Bench(app, c, new Rect(body.x, body.y, left, body.height));
                var right = new Rect(body.x + left + 4, body.y, body.width - left - 4, body.height);
                if (c.Mode == "salvage") Salvage(app, c, right); else Orbs(app, c, right);
            }
            CU.Tooltip(app, new Rect(0, 0, Area.width, Area.height));
            if (confirmAll)
            {
                bool yes = CU.Ask(app, inner, c.SalvageAllText(), Loc.T("Salvage"), Loc.T("Cancel"), out bool answered);
                if (answered) { confirmAll = false; if (yes) c.SalvageAll(); }
            }
        }

        // ---------------------------------------------------------------------------------------------- the bench (left)
        void Bench(ChaosApp app, CraftingState c, Rect r)
        {
            var item = c.Item;
            var slot = new Rect(r.x + 4, r.y + 2, 44, 44);
            ChaosApp.Fill(slot, new Color(0.11f, 0.09f, 0.12f, 1f));
            if (item != null) app.DrawItem(new Rect(slot.x + 6, slot.y + 6, 32, 32), (ushort)CF.I(item, "clientId"), 1);
            ItemSlots.Drop(slot, (pos, id, stack, count) => c.SelectAt(pos, id));
            if (item != null && Event.current.type == EventType.MouseDown && Event.current.button == 1 && slot.Contains(Event.current.mousePosition)) { c.Clear(); Event.current.Use(); }
            string rc = null;
            if (item == null)
            {
                GUI.Label(new Rect(r.x + 54, r.y + 2, r.width - 58, 20), Loc.T("Empty bench"), app.TitleStyle);
                GUI.Label(new Rect(r.x + 54, r.y + 24, r.width - 58, 36), Loc.T("Pick an item below, or drag one from your backpack onto the slot."), CU.Wrap(app));
            }
            else
            {
                var ns = new GUIStyle(app.TitleStyle);
                ns.normal.textColor = CF.N(item, "rarity") > 0 ? CU.Hex(CraftingState.RarityColorOf(CF.N(item, "rarity")), Color.white) : new Color(0.84f, 0.79f, 0.68f);
                GUI.Label(new Rect(r.x + 54, r.y + 2, r.width - 110, 20), CF.T(item, "name", "?"), ns);
                CU.Label(app, new Rect(r.x + 54, r.y + 22, r.width - 58, 20), CraftingState.RarityLine(item, out rc), rc, false);
                if (GUI.Button(new Rect(r.xMax - 54, r.y + 2, 52, 20), new GUIContent(CF.B(item, "locked") ? Loc.T("Unlock") : Loc.T("Lock"), CF.B(item, "locked") ? Loc.T("Locked: it cannot be sold, salvaged or thrown away. Click to unlock.") : Loc.T("Lock the item: it cannot be sold, salvaged or thrown away.")))) c.ToggleLock();
                GUI.Label(new Rect(r.x + 4, r.y + 48, r.width - 8, 20), CraftingState.ModCountLine(item), app.SmallStyle);
                string qt = CraftingState.QualityText(item, out int qp);
                if (qt.Length > 0) CU.Bar(app, new Rect(r.x + 4, r.y + 68, r.width - 8, 14), qp, qt, new Color(0.45f, 0.4f, 0.15f));
            }
            // the modifiers
            var mods = item != null ? c.Mods : new List<Dictionary<string, object>>();
            var lines = new List<System.Func<Rect, float>>();
            var mv = new Rect(r.x + 4, r.y + 88, r.width - 8, r.height * 0.42f);
            float y = 0, total = 0;
            var entries = new List<KeyValuePair<string, Dictionary<string, object>>>();
            string side = null;
            foreach (var m in mods)
            {
                string s = CF.T(m, "side");
                if (s.Length > 0 && s != side) { side = s; entries.Add(new KeyValuePair<string, Dictionary<string, object>>(CraftingState.SideHeader(s), null)); }
                entries.Add(new KeyValuePair<string, Dictionary<string, object>>(null, m));
            }
            string sh = item != null ? CraftingState.SocketHeader(item) : null;
            modScroll = CU.Rows(mv, modScroll, entries.Count + (sh != null ? 1 + CraftingState.SocketList(item).Count : 0), 22, (i, rr) =>
            {
                if (i < entries.Count)
                {
                    var e = entries[i];
                    if (e.Value == null) { CU.Label(app, rr, e.Key, "#8c8070", false); return; }
                    var m = e.Value;
                    string key = CF.T(m, "key");
                    bool on = key.Length > 0 && key == c.SelectedMod;
                    ChaosApp.Fill(rr, on ? new Color(0.96f, 0.81f, 0.45f, 0.21f) : new Color(1f, 1f, 1f, 0.03f));
                    string codexId = CodexView.IdForMod(key, CF.T(m, "group"), InfoStore.Codex);
                    string codexTip = codexId != null ? Loc.T("Right-click: its page in the Codex.") : null;
                    string baseTip = CF.B(m, "power") ? CF.T(m, "text") + "\n" + Loc.T("Legendary power: it changes what your character does.") : CF.B(m, "bound") ? Loc.T("Bound: the orbs that change modifiers leave it alone. Only an Orb of Erasure frees it.") : "";
                    GUI.Label(new Rect(rr.x + 4, rr.y, rr.width - 50, 20), new GUIContent(CraftingState.ModText(m), baseTip.Length > 0 ? (codexTip != null ? baseTip + "\n" + codexTip : baseTip) : (codexTip ?? "")), ColoredSmall(app, CraftingState.ModColor(m)));
                    if (codexId != null && Event.current.type == EventType.MouseDown && Event.current.button == 1 && rr.Contains(Event.current.mousePosition)) { app.OpenCodex(codexId); Event.current.Use(); }
                    if (CF.B(m, "bound")) GUI.Label(new Rect(rr.xMax - 46, rr.y, 44, 20), Loc.T("bound"), app.SmallStyle);
                    if (key.Length > 0 && Event.current.type == EventType.MouseDown && Event.current.button == 0 && rr.Contains(Event.current.mousePosition)) { c.SelectMod(key); Event.current.Use(); }
                    return;
                }
                int k = i - entries.Count;
                if (k == 0) { CU.Label(app, rr, sh, "#e8b84a", false); return; }
                var so = CraftingState.SocketList(item)[k - 1];
                if (CF.I(so, "id") > 0)
                {
                    GUI.Label(new Rect(rr.x + 4, rr.y, rr.width - 130, 20), new GUIContent(CF.T(so, "name"), CF.T(so, "name") + "\n" + CF.T(so, "text")), ColoredSmall(app, CF.T(so, "color", "#d6c9ae")));
                    if (GUI.Button(new Rect(rr.xMax - 124, rr.y, 62, 20), new GUIContent(CF.Short(CF.N(so, "cost")), Loc.T("Take the gem out for {0} gold (bank first, then the backpack). It comes back to you.", CF.I(so, "cost"))))) c.GemOp("remove", CF.I(so, "index"));
                    if (GUI.Button(new Rect(rr.xMax - 60, rr.y, 58, 20), new GUIContent(Loc.T("Shatter"), Loc.T("Take the gem out for free: it is destroyed.")))) c.GemOp("shatter", CF.I(so, "index"));
                }
                else CU.Label(app, rr, Loc.T("Empty socket"), "#8c8070", false);
            });

            // the picker
            float gy = mv.yMax + 6;
            GUI.Label(new Rect(r.x + 4, gy, 200, 18), Loc.T("Your gear"), app.SmallStyle);
            var gv = new Rect(r.x + 4, gy + 18, r.width - 8, r.yMax - gy - 18 - 80);
            var items = c.Items;
            var batch = c.Mode == "salvage" && c.Batch != null ? new HashSet<string>(CF.Raw(CF.G(c.Batch, "paths")).Select(x => CF.Str(x))) : null;
            int per = Mathf.Max(1, (int)((gv.width - 18) / 38));
            int rows = (items.Count + per - 1) / per;
            gearScroll = GUI.BeginScrollView(gv, gearScroll, new Rect(0, 0, gv.width - 18, Mathf.Max(gv.height, rows * 38)));
            for (int i = 0; i < items.Count; i++)
            {
                var it = items[i];
                var cell = new Rect((i % per) * 38, (i / per) * 38, 36, 36);
                ChaosApp.Fill(cell, new Color(0.11f, 0.09f, 0.12f, 1f));
                app.DrawItem(new Rect(cell.x + 2, cell.y + 2, 32, 32), (ushort)CF.I(it, "clientId"), 1);
                double rar = CF.N(it, "rarity");
                if (rar > 0 || CF.B(it, "unique") || CF.B(it, "key")) ItemSlots.Frame(cell, CF.B(it, "unique") ? "#e8582a" : CF.B(it, "key") ? CraftingState.KeyColor : CraftingState.RarityColorOf(rar));
                if (CF.B(it, "locked")) ChaosApp.Fill(cell, new Color(0, 0, 0, 0.4f));
                if (batch != null && batch.Contains(CF.T(it, "path"))) ItemSlots.Frame(cell, "#e03a1e");
                if (item != null && CF.T(item, "path") == CF.T(it, "path")) ItemSlots.Frame(cell, "#ffffff");
                string tip = CF.T(it, "name") + (CF.B(it, "unique") ? "\n" + Loc.T("Unique") : CF.B(it, "key") ? "\n" + Loc.T("Rift Key") : rar > 0 ? "\n" + CF.T(it, "rarityName") : "") + (CF.B(it, "locked") ? "\n" + Loc.T("Locked") : "");
                GUI.Label(cell, new GUIContent("", tip));
                if (Event.current.type == EventType.MouseDown && Event.current.button == 0 && cell.Contains(Event.current.mousePosition)) { c.SelectItem(it); Event.current.Use(); }
            }
            GUI.EndScrollView();
            if (items.Count == 0) GUI.Label(new Rect(gv.x + 4, gv.y + 4, gv.width, 20), Loc.T("No gear in your backpack."), app.SmallStyle);
            // result
            CU.Label(app, new Rect(r.x + 4, r.yMax - 78, r.width - 8, 76), c.ResultText, c.ResultOk ? "#9fdc7f" : "#e03a1e");
        }

        static GUIStyle ColoredSmall(ChaosApp app, string hex) { var s = new GUIStyle(app.SmallStyle); s.normal.textColor = CU.Hex(hex, s.normal.textColor); return s; }

        // ---------------------------------------------------------------------------------------------- orbs (right)
        void Orbs(ChaosApp app, CraftingState c, Rect r)
        {
            var rows = c.OrbRows();
            orbScroll = CU.Rows(new Rect(r.x, r.y, r.width, r.height * 0.62f), orbScroll, rows.Count, 58, (i, rr) =>
            {
                var o = rows[i];
                ChaosApp.Fill(rr, new Color(1f, 1f, 1f, 0.04f));
                bool open = c.Expanded.Contains(o.Key);
                app.DrawItem(new Rect(rr.x + 4, rr.y + 10, 36, 36), (ushort)o.ClientId, Mathf.Max(1, Mathf.Min(o.Count, 100)));
                GUI.Label(new Rect(rr.x + 46, rr.y + 2, rr.width - 130, 18), new GUIContent(o.Name + "  x" + CF.Short(o.Count), o.Name + "\n" + o.Text + (o.Preview.Length > 0 ? "\n" + Loc.T("Preview: {0}", o.Preview) : "") + (o.Why.Length > 0 ? "\n" + o.Why : "")), ColoredSmall(app, "#e8b84a"));
                string desc = open && !o.IsText && o.Text.Length > 0 ? o.Line + "\n" + o.Text : o.Line;
                CU.Label(app, new Rect(rr.x + 46, rr.y + 20, rr.width - 130, 38), desc, o.Color);
                if (CU.Button(new Rect(rr.xMax - 78, rr.y + 14, 72, 28), Loc.T("Use"), o.CanUse, o.Why)) c.ApplyOrb(o.Key);
                if (Event.current.type == EventType.MouseDown && Event.current.button == 0 && new Rect(rr.x, rr.y, rr.width - 82, rr.height).Contains(Event.current.mousePosition)) { if (open) c.Expanded.Remove(o.Key); else c.Expanded.Add(o.Key); Event.current.Use(); }
            });
            float hy = r.y + r.height * 0.62f + 6;
            GUI.Label(new Rect(r.x + 4, hy, 200, 18), Loc.T("History"), app.TitleStyle);
            var hist = c.History;
            histScroll = CU.Rows(new Rect(r.x, hy + 20, r.width, r.yMax - hy - 20), histScroll, Mathf.Max(1, hist.Count), 20, (i, rr) =>
            {
                if (hist.Count == 0) { CU.Label(app, rr, Loc.T("Nothing crafted yet."), "#8c8070", false); return; }
                var h = hist[i];
                GUI.Label(rr, new GUIContent(string.Format("{0}  {1}: {2}", CF.Date(CF.N(h, "time")), CF.T(h, "orb", "?"), CF.T(h, "text")), CF.T(h, "item") + "\n" + CF.T(h, "orb", "?") + ": " + CF.T(h, "text")), app.SmallStyle);
            });
        }

        // ---------------------------------------------------------------------------------------------- salvage (right)
        void Salvage(ChaosApp app, CraftingState c, Rect r)
        {
            var sv = c.Salvage;
            if (sv == null) { GUI.Label(new Rect(r.x + 4, r.y + 4, 300, 20), Loc.T("Loading..."), app.SmallStyle); return; }
            app.DrawItem(new Rect(r.x + 4, r.y, 32, 32), (ushort)CF.I(sv, "shardClientId"), 1);
            GUI.Label(new Rect(r.x + 42, r.y, r.width - 46, 18), Loc.T("Rune shards: {0}", CF.Short(CF.N(sv, "shards"))), app.TitleStyle);
            GUI.Label(new Rect(r.x + 42, r.y + 18, r.width - 46, 18), c.Installed ? Loc.T("Salvage gear into shards, shards into orbs.") : Loc.T("Salvage is not installed on this server."), app.SmallStyle);
            float y = r.y + 44;
            string t = c.SalvageItemText(out bool ok);
            CU.Label(app, new Rect(r.x + 4, y, r.width - 150, 40), t, c.Item == null ? "#8c8070" : ok ? "#9fdc7f" : "#e8582a");
            if (CU.Button(new Rect(r.xMax - 140, y + 4, 134, 28), Loc.T("Salvage"), ok)) c.SalvageItem();
            y += 46;
            // the batch
            GUI.Label(new Rect(r.x + 4, y, 200, 18), Loc.T("Salvage a whole bag"), app.TitleStyle);
            y += 22;
            var batch = c.Batch;
            var bags = CF.Rows(CF.G(sv, "bags"));
            string curBag = batch != null ? CF.T(batch, "bag") : "";
            int maxR = batch != null ? CF.I(batch, "maxRarity") : 1;
            float x = r.x + 4;
            foreach (var b in bags)
            {
                bool on = CF.T(b, "path") == curBag;
                if (GUI.Toggle(new Rect(x, y, 100, 22), on, CF.T(b, "name", "?"), GUI.skin.button) && !on) c.SetScope(CF.T(b, "path"), maxR);
                x += 104;
            }
            y += 26;
            var names = CF.Values(CF.G(sv, "rarityNames")); var ids = CraftingState.RarityIds(sv);
            x = r.x + 4;
            GUI.Label(new Rect(x, y, 100, 22), Loc.T("Up to"), app.SmallStyle); x += 50;
            for (int i = 0; i < names.Count; i++)
            {
                bool on = (i < ids.Count ? ids[i] : i + 1) <= maxR && (i + 1 >= names.Count || (i + 1 < ids.Count ? ids[i + 1] : i + 2) > maxR);
                if (GUI.Toggle(new Rect(x, y, 86, 22), on, Loc.T(names[i]), GUI.skin.button) && !on) c.SetScope(curBag, i < ids.Count ? ids[i] : i + 1);
                x += 88;
            }
            y += 28;
            CU.Label(app, new Rect(r.x + 4, y, r.width - 150, 54), c.BatchText(), "#c8b89a");
            if (CU.Button(new Rect(r.xMax - 140, y + 6, 134, 28), c.BatchButtonText(), c.Installed && batch != null && CF.I(batch, "count") > 0)) confirmAll = true;
            y += 60;
            // recipes
            GUI.Label(new Rect(r.x + 4, y, 300, 18), Loc.T("Shards into orbs"), app.TitleStyle);
            var recipes = c.Recipes;
            recipeScroll = CU.Rows(new Rect(r.x, y + 20, r.width, r.yMax - y - 20), recipeScroll, recipes.Count, 38, (i, rr) =>
            {
                var rec = recipes[i];
                double have = CraftingState.Have(rec, sv), cost = CF.N(rec, "cost");
                ChaosApp.Fill(rr, new Color(1f, 1f, 1f, 0.04f));
                app.DrawItem(new Rect(rr.x + 3, rr.y + 3, 32, 32), (ushort)CF.I(rec, "clientId"), 1);
                string nm = CF.T(rec, "name", CF.T(rec, "key"));
                if (nm.StartsWith("Orb of ")) nm = nm.Substring(7);
                GUI.Label(new Rect(rr.x + 40, rr.y + 1, rr.width - 150, 18), new GUIContent(nm, CraftingState.RecipeTip(rec, sv)), app.SmallStyle);
                CU.Label(app, new Rect(rr.x + 40, rr.y + 19, rr.width - 150, 18), CraftingState.CostText(rec, sv), have >= cost ? (CraftingState.IsShardRecipe(rec) ? "#e8a050" : "#c0a0ff") : "#6b6258", false);
                bool shift = Event.current.shift, ctrl = Event.current.control;
                int back = CraftingState.RecycleBack(rec); int owned = CF.I(rec, "count");
                string label = shift && back > 0 ? Loc.T("Recycle") : Loc.T("Make");
                if (CU.Button(new Rect(rr.xMax - 100, rr.y + 5, 94, 28), label, CraftingState.RecipeEnabled(rec, sv), CraftingState.RecipeTip(rec, sv)))
                {
                    if (shift && back > 0) { if (owned > 0) c.Recycle(CF.T(rec, "key"), Mathf.Min(owned, 100)); }
                    else { int n = CraftingState.CombineCount(have, cost, CF.N(sv, "maxCombine"), ctrl); if (n >= 1) c.Combine(CF.T(rec, "key"), n); }
                }
            });
        }

        // ---------------------------------------------------------------------------------------------- guide
        void Guide(ChaosApp app, CraftingState c, Rect body)
        {
            guidePage = CU.Tabs(new Rect(body.x + 4, body.y, 400, 24), new[] { Loc.T("Orbs"), Loc.T("Basics"), Loc.T("Plan"), Loc.T("Gems") }, guidePage);
            var view = new Rect(body.x + 4, body.y + 30, body.width - 8, body.height - 34);
            var lines = new List<KeyValuePair<string, string>>();
            if (guidePage == 0)
                foreach (var o in CF.Rows(CF.G(c.Info, "orbs")))
                {
                    string risk = CraftGuide.RiskOf(CF.T(o, "key"));
                    lines.Add(new KeyValuePair<string, string>(CF.T(o, "name") + "  -  " + CraftGuide.RiskText(risk), CraftGuide.RiskColor.TryGetValue(risk, out var rc) ? rc : "#d6c9ae"));
                    lines.Add(new KeyValuePair<string, string>("   " + CF.T(o, "text"), "#8c8070"));
                    string adv = CraftGuide.AdviceOf(CF.T(o, "key"));
                    if (adv.Length > 0) lines.Add(new KeyValuePair<string, string>("   " + adv, null));
                }
            else if (guidePage == 1)
                foreach (var b in CraftGuide.Basics) { lines.Add(new KeyValuePair<string, string>(Loc.T(b[0]), "#e8b84a")); lines.Add(new KeyValuePair<string, string>("   " + Loc.T(b[1]), null)); }
            else if (guidePage == 2)
                foreach (var p in CraftGuide.Plan) lines.Add(new KeyValuePair<string, string>(Loc.T(p), null));
            else
            {
                // the gem table (the server's gemguide message): how gems work, then every gem with its bonus per slot group
                foreach (var b in GemGuide.Basics(c.GemGuide)) { lines.Add(new KeyValuePair<string, string>(b.Key, "#e8b84a")); lines.Add(new KeyValuePair<string, string>("   " + b.Value, null)); }
                lines.Add(new KeyValuePair<string, string>(Loc.T("Every gem, from the worst quality to the best"), "#e8b84a"));
                var gem = GemGuide.Rows(c.GemGuide);
                if (gem.Count == 0) lines.Add(new KeyValuePair<string, string>(Loc.T("Open the crafting bench once to load the gem table."), null));
                foreach (var row in gem)
                {
                    lines.Add(new KeyValuePair<string, string>(row.Name, row.Color));
                    foreach (var g in row.Groups) lines.Add(new KeyValuePair<string, string>("   " + GemGuide.GroupLine(g), null));
                }
            }
            var st = CU.Wrap(app);
            float total = 0;
            var hs = lines.Select(l => st.CalcHeight(new GUIContent(l.Key), view.width - 24) + 2).ToList();
            total = hs.Sum();
            guideScroll = GUI.BeginScrollView(view, guideScroll, new Rect(0, 0, view.width - 18, Mathf.Max(view.height, total)));
            float y = 0;
            for (int i = 0; i < lines.Count; i++) { CU.Label(app, new Rect(0, y, view.width - 20, hs[i]), lines[i].Key, lines[i].Value); y += hs[i]; }
            GUI.EndScrollView();
        }
    }
}
