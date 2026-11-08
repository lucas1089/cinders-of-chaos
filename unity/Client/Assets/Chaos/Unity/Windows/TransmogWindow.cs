// Transmog (opcode 212, Core/CollectTransmog.cs): equipped items on the left, the looks of the chosen item's kind in the middle, the fee and the buttons, and the Collection
// page (kinds and appearance sets). The "Transmog" entry of the item menu of the main client is not in Unity: use the top menu (Character).
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class TransmogWindow : ModelWindow
    {
        public override string Title => Loc.T("Transmog");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 340, 50, 680, 540);

        Vector2 slotScroll, lookScroll, collScroll;

        protected override bool ModelVisible(ChaosApp app) => app.Session.Transmog.Visible;
        protected override void ModelShow(ChaosApp app) => app.Session.Transmog.Show();
        protected override void ModelHide(ChaosApp app) => app.Session.Transmog.Hide();

        protected override void Body(ChaosApp app, Rect inner)
        {
            var t = app.Session?.Transmog;
            if (t == null) return;
            if (t.State == null) { GUI.Label(new Rect(inner.x + 8, inner.y + 8, 300, 22), Loc.T("Loading..."), app.SmallStyle); return; }
            int tab = CU.Tabs(new Rect(inner.x + 4, inner.y, 300, 24), new[] { Loc.T("Wardrobe"), Loc.T("Collection") }, t.Page == "collection" ? 1 : 0);
            t.Page = tab == 1 ? "collection" : "wardrobe";
            var tot = CF.M(t.State, "total");
            CU.Bar(app, new Rect(inner.x + 220, inner.y + 3, inner.width - 360, 18), (int)TransmogState.Percent(CF.G(tot, "unlocked"), CF.G(tot, "total")), TransmogState.ProgressText(CF.G(tot, "unlocked"), CF.G(tot, "total")), new Color(0.2f, 0.5f, 0.45f));
            GUI.Label(new Rect(inner.xMax - 130, inner.y + 2, 126, 20), Loc.T("Gold") + ": " + TransmogState.Gold(CF.N(t.State, "money")), new GUIStyle(app.SmallStyle) { alignment = TextAnchor.UpperRight });
            var body = new Rect(inner.x, inner.y + 30, inner.width, inner.height - 30);
            if (t.Page == "collection") Collection(app, t, body); else Wardrobe(app, t, body);
            CU.Tooltip(app, new Rect(0, 0, Area.width, Area.height));
        }

        void Wardrobe(ChaosApp app, TransmogState t, Rect body)
        {
            var slots = t.Slots;
            var left = new Rect(body.x + 4, body.y, 200, body.height - 4);
            slotScroll = CU.Rows(left, slotScroll, slots.Count, 44, (i, r) =>
            {
                var s = slots[i];
                bool sel = t.HasSlot && t.SelectedSlot == CF.I(s, "slot");
                var item = CF.G(s, "item") as Dictionary<string, object>;
                ChaosApp.Fill(r, sel ? new Color(0.35f, 0.25f, 0.1f, 1f) : new Color(1f, 1f, 1f, 0.04f));
                if (item != null) app.DrawItem(new Rect(r.x + 3, r.y + 5, 32, 32), (ushort)CF.I(item, "cid"), 1);
                CU.Label(app, new Rect(r.x + 40, r.y + 2, r.width - 44, 20), item != null ? CF.T(item, "name") : CF.T(s, "name"), item == null ? "#8c8070" : null, false);
                CU.Label(app, new Rect(r.x + 40, r.y + 21, r.width - 44, 20), TransmogState.SlotSub(s), "#8c8070", false);
                if (Event.current.type == EventType.MouseDown && Event.current.button == 0 && r.Contains(Event.current.mousePosition)) { t.SelectSlot(CF.I(s, "slot")); Event.current.Use(); }
            });

            float mx = left.xMax + 8, mw = 230;
            var item2 = t.SelectedItem();
            string kind = t.KindOfSelected();
            string kindTitle = Loc.T("Wardrobe");
            foreach (var k in CF.Rows(CF.G(t.State, "kinds"))) if (CF.T(k, "key") == kind) kindTitle = CF.T(k, "name") + "  " + TransmogState.ProgressText(CF.G(k, "unlocked"), CF.G(k, "total"));
            GUI.Label(new Rect(mx, body.y, mw, 20), kindTitle, app.SmallStyle);
            t.Search = CU.Field(app, new Rect(mx, body.y + 22, mw, 22), "transmogSearch", t.Search, 30);
            var looks = t.Looks();
            var lr = new Rect(mx, body.y + 48, mw, body.height - 54);
            if (kind.Length == 0) GUI.Label(lr, Loc.T("Select an equipped helmet, armor, legs, boots, weapon or shield."), CU.Wrap(app));
            else if (looks == null) GUI.Label(lr, Loc.T("Loading..."), app.SmallStyle);
            else if (looks.Count == 0) GUI.Label(lr, t.LooksByKind[kind].Count == 0 ? Loc.T("No appearance of this kind unlocked yet. Carry or equip an item once to add its look to your wardrobe.") : Loc.T("Nothing matches the search."), CU.Wrap(app));
            else
            {
                int per = Mathf.Max(1, (int)((lr.width - 18) / 40));
                int rows = (looks.Count + per - 1) / per;
                lookScroll = GUI.BeginScrollView(lr, lookScroll, new Rect(0, 0, lr.width - 18, Mathf.Max(lr.height, rows * 40)));
                for (int i = 0; i < looks.Count; i++)
                {
                    var l = looks[i];
                    var r = new Rect((i % per) * 40, (i / per) * 40, 38, 38);
                    bool sel = t.SelectedLook != null && CF.Str(CF.G(t.SelectedLook, "id")) == CF.Str(CF.G(l, "id"));
                    ChaosApp.Fill(r, sel ? new Color(0.45f, 0.33f, 0.1f, 1f) : new Color(0.11f, 0.09f, 0.12f, 1f));
                    app.DrawItem(new Rect(r.x + 3, r.y + 3, 32, 32), (ushort)CF.I(l, "cid"), 1);
                    GUI.Label(r, new GUIContent("", CF.T(l, "name") + (CF.G(l, "set") != null ? "\n" + Loc.T("{0} set", CF.T(l, "set")) : "")));
                    if (Event.current.type == EventType.MouseDown && Event.current.button == 0 && r.Contains(Event.current.mousePosition)) { t.Select(l); Event.current.Use(); }
                }
                GUI.EndScrollView();
            }

            // detail
            float dx = mx + mw + 8, dw = body.xMax - dx - 4;
            var d = t.Detail();
            if (item2 != null)
            {
                ChaosApp.Fill(new Rect(dx, body.y, 44, 44), new Color(0.11f, 0.09f, 0.12f, 1f));
                app.DrawItem(new Rect(dx + 6, body.y + 6, 32, 32), (ushort)CF.I(item2, "cid"), 1);
                var look = t.SelectedLook ?? CF.G(item2, "look") as Dictionary<string, object>;
                if (look != null)
                {
                    ChaosApp.Fill(new Rect(dx + 50, body.y, 44, 44), new Color(0.11f, 0.09f, 0.12f, 1f));
                    app.DrawItem(new Rect(dx + 56, body.y + 6, 32, 32), (ushort)CF.I(look, "cid"), 1);
                }
                // the live preview (game_transmog previewItem): the equipped item drawn as the picked look, big; without a pick, as it looks now
                if (dw >= 170)
                {
                    var pv = new Rect(dx + dw - 68, body.y, 68, 68);
                    ChaosApp.Fill(pv, new Color(0.11f, 0.09f, 0.12f, 1f));
                    int pcid = look != null ? CF.I(look, "cid") : CF.I(item2, "cid");
                    if (pcid > 0) app.DrawItem(new Rect(pv.x + 2, pv.y + 2, 64, 64), (ushort)pcid, 1);
                }
                GUI.Label(new Rect(dx, body.y + 48, dw, 20), CF.T(item2, "name"), app.TitleStyle);
                string lt = t.SelectedLook != null ? Loc.T("Preview: {0}", CF.T(t.SelectedLook, "name")) : CF.G(item2, "look") is Dictionary<string, object> own ? Loc.T("Looks like: {0}", CF.T(own, "name")) : Loc.T("Shows its own look");
                GUI.Label(new Rect(dx, body.y + 68, dw, 20), lt, app.SmallStyle);
            }
            GUI.Label(new Rect(dx, body.y + 94, dw, 40), d.Fee, CU.Wrap(app));
            GUI.Label(new Rect(dx, body.y + 134, dw, 70), d.Hint, CU.Wrap(app));
            if (CU.Button(new Rect(dx, body.yMax - 100, dw, 28), Loc.T("Apply"), d.Apply)) t.ApplySelected();
            if (CU.Button(new Rect(dx, body.yMax - 68, dw, 28), Loc.T("Remove"), d.Remove)) t.RemoveSelected();
            CU.Label(app, new Rect(dx, body.yMax - 36, dw, 34), t.StatusText, t.StatusOk ? "#8fd16a" : "#ff7a5c");
        }

        void Collection(ChaosApp app, TransmogState t, Rect body)
        {
            var kinds = CF.Rows(CF.G(t.State, "kinds"));
            var sets = t.SortedSets();
            int count = kinds.Count + sets.Count + 2;
            collScroll = CU.Rows(new Rect(body.x + 4, body.y, body.width - 8, body.height - 4), collScroll, count, 30, (i, r) =>
            {
                if (i == 0) { GUI.Label(r, Loc.T("Appearances by kind"), app.TitleStyle); return; }
                if (i <= kinds.Count)
                {
                    var k = kinds[i - 1];
                    GUI.Label(new Rect(r.x + 4, r.y + 4, 180, 20), CF.T(k, "name"), app.SmallStyle);
                    CU.Bar(app, new Rect(r.x + 190, r.y + 6, r.width - 200, 16), (int)TransmogState.Percent(CF.G(k, "unlocked"), CF.G(k, "total")), TransmogState.ProgressText(CF.G(k, "unlocked"), CF.G(k, "total")), new Color(0.2f, 0.5f, 0.45f));
                    return;
                }
                if (i == kinds.Count + 1) { GUI.Label(r, Loc.T("Appearance sets"), app.TitleStyle); return; }
                var s = sets[i - kinds.Count - 2];
                bool owned = CF.B(s, "owned");
                string src = CF.T(s, "source");
                string col = owned ? "#8fd16a" : TransmogState.SourceColors.TryGetValue(src, out var c) ? c : "#a89c86";
                var prev = GUI.color;
                if (!owned) GUI.color = new Color(1, 1, 1, 0.6f);
                GUI.Label(new Rect(r.x + 4, r.y + 2, 200, 20), new GUIContent(CF.T(s, "name"), CF.T(s, "desc")), app.SmallStyle);
                CU.Label(app, new Rect(r.x + 4, r.y + 15, 200, 15), TransmogState.SetLine(s), col, false);
                float x = r.x + 210;
                foreach (var l in CF.Rows(CF.G(s, "looks")))
                {
                    if (x + 30 > r.xMax) break;
                    app.DrawItem(new Rect(x, r.y, 28, 28), (ushort)CF.I(l, "cid"), 1);
                    GUI.Label(new Rect(x, r.y, 28, 28), new GUIContent("", CF.T(l, "name")));
                    x += 30;
                }
                GUI.color = prev;
            });
        }
    }
}
