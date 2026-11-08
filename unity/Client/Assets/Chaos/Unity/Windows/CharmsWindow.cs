// Charms (opcode 198, Core/CollectCharms.cs): a grid of cells, charms placed by drag and drop (place, move, take back), the list of charms you carry,
// salvage and reforge, the totals and the unlock groups. Drag a charm of the list onto a cell, a placed charm to another cell or onto the list. Top menu (Character).
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class CharmsWindow : ModelWindow
    {
        public override string Title => Loc.T("Charms");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 380, 50, 760, 520);

        Vector2 sideScroll;
        CharmDrag drag;
        Dictionary<string, object> dragCharm;
        Rect gridRect, bagRect;

        protected override bool ModelVisible(ChaosApp app) => app.Session.Charms.Visible;
        protected override void ModelShow(ChaosApp app) => app.Session.Charms.Show();
        protected override void ModelHide(ChaosApp app) { app.Session.Charms.Hide(); drag = null; }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var c = app.Session?.Charms;
            if (c == null) return;
            var e = Event.current;
            if (c.State == null) { GUI.Label(new Rect(inner.x + 8, inner.y + 8, 300, 22), Loc.T("Loading..."), app.SmallStyle); return; }
            GUI.Label(new Rect(inner.x + 6, inner.y, inner.width - 12, 20), c.Header(), app.SmallStyle);
            float step = CharmsState.Cell + CharmsState.Gap;
            float gw = c.Cols * step, gh = c.Rows * step;
            gridRect = new Rect(inner.x + 8, inner.y + 26, gw, gh);
            var mouse = e.mousePosition;

            // cells
            var preview = drag != null && gridRect.Contains(mouse) ? c.Preview(drag, mouse.x - gridRect.x, mouse.y - gridRect.y) : null;
            var lit = new Dictionary<string, bool>();
            if (preview != null) foreach (var cell in preview.Cells) lit[CharmsState.Key(cell[0], cell[1])] = preview.Ok;
            foreach (var cell in c.Cells)
            {
                int cx = CF.I(cell, "x"), cy = CF.I(cell, "y");
                var r = new Rect(gridRect.x + (cx - 1) * step, gridRect.y + (cy - 1) * step, CharmsState.Cell, CharmsState.Cell);
                bool open = CF.B(cell, "open");
                ChaosApp.Fill(r, open ? new Color(0.2f, 0.17f, 0.2f, 1f) : new Color(0.1f, 0.08f, 0.08f, 1f));
                if (!open) { GUI.Label(r, new GUIContent("", Loc.T("Locked: {0}", CF.T(cell, "why")))); GUI.Label(new Rect(r.x + 14, r.y + 12, 18, 18), "x", app.SmallStyle); }
                if (lit.TryGetValue(CharmsState.Key(cx, cy), out bool ok)) ChaosApp.Fill(r, ok ? new Color(0.37f, 0.69f, 0.29f, 0.45f) : new Color(0.75f, 0.27f, 0.24f, 0.45f));
            }
            // placed charms
            foreach (var p in c.Placed)
            {
                if (drag != null && drag.Kind == "placed" && drag.Id == CF.I(p, "id")) continue;
                var rr = CharmsState.Rect(CF.I(p, "x"), CF.I(p, "y"), CF.I(p, "w"), CF.I(p, "h"));
                var r = new Rect(gridRect.x + rr[0], gridRect.y + rr[1], rr[2], rr[3]);
                Tile(app, r, p, true, CF.G(p, "active") != null && !CF.B(p, "active") ? 0.4f : 1f, CF.I(p, "w"), CF.I(p, "h"));
                if (e.type == EventType.MouseDown && e.button == 0 && r.Contains(mouse) && drag == null) { drag = CharmsState.DragOf(p, "placed"); dragCharm = p; e.Use(); }
            }

            // the list of charms you carry (right side)
            float bx = gridRect.xMax + 12;
            bagRect = new Rect(bx, inner.y + 26, inner.xMax - bx - 4, 150);
            GUI.Box(bagRect, GUIContent.none);
            GUI.Label(new Rect(bagRect.x + 4, bagRect.y + 2, 200, 18), Loc.T("Your charms"), app.SmallStyle);
            var bag = c.Bag;
            if (bag.Count == 0) GUI.Label(new Rect(bagRect.x + 6, bagRect.y + 24, bagRect.width - 12, 40), Loc.T("No charms to place."), CU.Wrap(app));
            int per = Mathf.Max(1, (int)((bagRect.width - 20) / 46));
            for (int i = 0; i < bag.Count; i++)
            {
                var b = bag[i];
                var r = new Rect(bagRect.x + 6 + (i % per) * 46, bagRect.y + 22 + (i / per) * 46, 44, 44);
                if (r.yMax > bagRect.yMax) break;
                if (drag != null && drag.Kind == "bag" && drag.Ref == CF.Str(CF.G(b, "ref"))) { ChaosApp.Fill(r, new Color(1f, 1f, 1f, 0.05f)); continue; }
                Tile(app, new Rect(r.x, r.y, 44 * Mathf.Min(1, CF.I(b, "w")), 44), b, false, 1f, 1, 1);
                if (CF.Str(CF.G(b, "ref")) == c.SelectedRef) ItemSlots.Frame(r, "#fff0c0");
                if (r.Contains(mouse) && e.type == EventType.MouseDown && e.button == 0 && drag == null) { c.SelectedRef = CF.Str(CF.G(b, "ref")); drag = CharmsState.DragOf(b, "bag"); dragCharm = b; e.Use(); }
            }

            // buttons and status
            float by = bagRect.yMax + 6;
            var sel = c.BagEntry(c.SelectedRef);
            if (CU.Button(new Rect(bx, by, 120, 24), Loc.T("Salvage"), c.CanSalvage, sel != null ? Loc.T("Break the charm into {0} charm shards", CF.I(sel, "salvage")) : Loc.T("Select a charm of your list"))) c.SalvageSelected();
            if (CU.Button(new Rect(bx + 126, by, 120, 24), Loc.T("Reforge"), c.CanReforge, sel != null && CF.G(sel, "reforge") != null ? Loc.T("Roll the values again for {0} charm shards", CF.I(sel, "reforge")) : Loc.T("Select a charm of your list (uniques cannot be reforged)"))) c.ReforgeSelected();
            CU.Label(app, new Rect(bx, by + 28, inner.xMax - bx - 4, 40), c.StatusText, c.StatusColor);

            // totals and unlocks
            var side = new Rect(bx, by + 70, inner.xMax - bx - 4, inner.yMax - by - 74);
            var lines = new List<KeyValuePair<string, string>>();
            lines.AddRange(c.TotalsLines());
            lines.Add(new KeyValuePair<string, string>("", null));
            lines.AddRange(c.UnlockLines());
            sideScroll = CU.Rows(side, sideScroll, lines.Count, 20, (i, r) => { if (lines[i].Value != null) CU.Label(app, r, lines[i].Key, lines[i].Value, false); });

            // an item of a bag or a container dropped on the grid is placed where it falls (game_charms onDropItem)
            if (drag == null && ItemSlots.Dragging)
                ItemSlots.Drop(gridRect, (pos, id, stack, count) =>
                {
                    var it = MarketDrop.BagItem(app.Session?.Parser.Containers, pos);
                    var act = c.ItemDropAction(pos, it != null ? it.Attr(ItemAttr.Id) : 0UL, mouse.x - gridRect.x, mouse.y - gridRect.y, out string why);
                    if (act != null) c.Send(act);
                    else if (why != null) { c.StatusText = why; c.StatusColor = CharmsState.ColorBad; }
                });
            if (drag == null) ItemSlots.Ghost(app, new Rect(0, 0, Area.width, Area.height));

            // the drag
            if (drag != null)
            {
                float side2 = 44;
                var gr = new Rect(mouse.x - side2 / 2, mouse.y - side2 / 2, side2 * Mathf.Max(1, drag.W), side2 * Mathf.Max(1, drag.H));
                if (e.type == EventType.Repaint) Tile(app, gr, dragCharm, drag.Kind == "placed", 0.85f, drag.W, drag.H);
                if (e.type == EventType.MouseUp && e.button == 0)
                {
                    string target = gridRect.Contains(mouse) ? "grid" : bagRect.Contains(mouse) ? "bag" : null;
                    var act = c.DropAction(drag, target, mouse.x - gridRect.x, mouse.y - gridRect.y, out string why);
                    if (act != null) c.Send(act);
                    else if (why != null) { c.StatusText = why; c.StatusColor = CharmsState.ColorBad; }
                    drag = null; dragCharm = null;
                    e.Use();
                }
            }
            else if (e.type == EventType.Repaint) HoverTip(app, c, mouse, inner);
        }

        void Tile(ChaosApp app, Rect r, Dictionary<string, object> ch, bool placed, float alpha, int cw, int chh)
        {
            var prev = GUI.color;
            GUI.color = new Color(1, 1, 1, alpha);
            // the slot picture of the tile's shape (the main client's charmslot_WxH), the plain dark square without it
            string slotPath = CharmSlots.Path(cw, chh);
            var slotTex = slotPath != null ? app.ArtTexture(slotPath) : null;
            if (slotTex != null) GUI.DrawTexture(r, slotTex, ScaleMode.StretchToFill, true);
            else ChaosApp.Fill(r, new Color(0.11f, 0.09f, 0.12f, alpha));
            string rarity = CF.T(ch, "rarity");
            Color frame = CU.Hex(CharmColor(ch), new Color(0.91f, 0.72f, 0.29f));
            ItemSlots.Frame(r, "#" + ColorUtility.ToHtmlStringRGB(frame));
            int look = CF.I(ch, "item");
            float side = Mathf.Min(r.width, r.height) >= 80 ? 64 : 32;
            if (look > 0) app.DrawItem(new Rect(r.center.x - side / 2, r.center.y - side / 2, side, side), (ushort)look, 1);
            else GUI.Label(new Rect(r.x, r.y + r.height / 2 - 9, r.width, 18), rarity.Length > 0 ? rarity.Substring(0, 1) : "?", new GUIStyle(app.SmallStyle) { alignment = TextAnchor.MiddleCenter });
            if (CharmsState.Glows(ch)) ChaosApp.Fill(new Rect(r.x, r.y, r.width, 2), frame);
            GUI.color = prev;
        }

        static string CharmColor(Dictionary<string, object> ch) => CF.G(ch, "color") as string ?? "#e8b84a";

        void HoverTip(ChaosApp app, CharmsState c, Vector2 mouse, Rect inner)
        {
            string tip = null;
            foreach (var p in c.Placed)
            {
                var rr = CharmsState.Rect(CF.I(p, "x"), CF.I(p, "y"), CF.I(p, "w"), CF.I(p, "h"));
                if (new Rect(gridRect.x + rr[0], gridRect.y + rr[1], rr[2], rr[3]).Contains(mouse)) tip = CharmsState.Tooltip(p, true);
            }
            if (tip == null)
            {
                var bag = c.Bag; int per = Mathf.Max(1, (int)((bagRect.width - 20) / 46));
                for (int i = 0; i < bag.Count; i++)
                    if (new Rect(bagRect.x + 6 + (i % per) * 46, bagRect.y + 22 + (i / per) * 46, 44, 44).Contains(mouse)) tip = CharmsState.Tooltip(bag[i], false);
            }
            if (tip == null) { CU.Tooltip(app, new Rect(0, 0, Area.width, Area.height)); return; }
            var st = CU.Wrap(app);
            float w = 260, h = st.CalcHeight(new GUIContent(tip), w - 8) + 6;
            var r = new Rect(Mathf.Min(mouse.x + 14, Area.width - w - 2), Mathf.Min(mouse.y + 14, Area.height - h - 2), w, h);
            ChaosApp.Fill(r, new Color(0.05f, 0.04f, 0.07f, 0.97f));
            GUI.Label(new Rect(r.x + 4, r.y + 3, w - 8, h - 6), tip, st);
        }
    }

}
