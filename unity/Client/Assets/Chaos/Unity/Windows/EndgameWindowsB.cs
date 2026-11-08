// Endgame windows, part B (track L): the Ember Descent (window, run HUD, boon offer, merchant), the Rift and Waystone atlases and invasions
// (calendar and HUD). Models: Core/EndgamePve.cs and Core/EndgameAtlas.cs. No Ctrl hotkeys; they open from the Adventure menu or by the server.
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    // ================================================================================================ Ember Descent
    public sealed class DescentWindow : GameWindow
    {
        bool lastVisible;
        public override string Title => Loc.T("Ember Descent");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 230, 70, 460, 400);
        public override void Reset() { lastVisible = false; Open = false; }

        public override void Tick(ChaosApp app)
        {
            var d = app.Session?.Endgame?.Descent;
            if (d == null) return;
            WindowSync.Run(ref lastVisible, this, d.InfoVisible, d.ShowInfo, d.HideInfo);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var d = app.Session?.Endgame?.Descent;
            if (d == null) return;
            float x = inner.x + 6, w = inner.width - 12, y = inner.y + 4;
            if (d.Info == null) { Eu.Label(app, new Rect(x, y, w, 20), Loc.T("Asking the server..."), Eu.Dim, 12); return; }
            foreach (var l in DescentView.InfoLines(d.Info)) y += Eu.Wrap(app, x, y, w, l.Text, l.Color, 12);
            y += 6;
            bool canCraft = DescentView.Craft(d.Info, out string craft);
            if (craft.Length > 0)
            {
                Eu.Label(app, new Rect(x, y, w - 130, 32), craft, Eu.Text, 11, false, TextAnchor.UpperLeft, true);
                if (Eu.Button(new Rect(x + w - 124, y, 124, 26), Loc.T("Forge Sigil"), canCraft)) d.Craft();
                y += 36;
            }
            DescentView.EntryButtons(d.Info, out var normal, out var weekly);
            float bw = (w - 8) / 2;
            if (Eu.Button(new Rect(x, y, bw, 32), normal.Text, normal.Can)) d.Start(false);
            if (Eu.Button(new Rect(x + bw + 8, y, bw, 32), weekly.Text, weekly.Can)) d.Start(true);
            y += 40;
            if (d.Message.Length > 0) Eu.Wrap(app, x, y, w, d.Message, Eu.Bright, 12);
        }
    }

    public sealed class DescentHudWindow : GameWindow
    {
        bool wasShown, dismissed, lastOpen;
        public override string Title => Loc.T("The Ember Descent");
        public override bool InMenu => false;
        protected override Rect Place(float w, float h) => new Rect(8, 108, 290, 330);
        public override void Reset() { wasShown = dismissed = lastOpen = false; Open = false; }

        public override void Tick(ChaosApp app)
        {
            var d = app.Session?.Endgame?.Descent;
            if (d == null) return;
            EndgameBridge.Wire(app);
            bool shown = d.HudShown(app.Session.Now);
            if (shown && !wasShown) { Open = true; dismissed = false; }
            if (!shown) Open = false;
            else
            {
                if (!Open && lastOpen && wasShown) dismissed = true;
                if (dismissed) Open = false;
            }
            lastOpen = Open; wasShown = shown;
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var d = app.Session?.Endgame?.Descent;
            if (d == null || d.Hud == null) return;
            var h = d.Hud;
            double now = app.Session.Now;
            float x = inner.x + 6, w = inner.width - 12, y = inner.y + 2;
            string theme = Json.Text(h, "theme");
            Eu.Label(app, new Rect(x, y, w, 18), Json.Bool(h, "weekly") ? Loc.T("The Ember Descent (weekly)") : Loc.T("The Ember Descent"), Eu.Bright, 14, true);
            y += 20;
            y += Eu.Wrap(app, x, y, w, DescentView.RoomLine(h) + (theme.Length > 0 ? "\n" + theme : ""), DescentView.RoomColor(Json.Text(h, "type")), 12, true);
            double left = d.TimeLeft(now);
            bool done = Json.Text(h, "state") == "done";
            Eu.Label(app, new Rect(x + w - 80, inner.y + 2, 80, 20), done ? Loc.T("Over") : Eg.Clock(left), left <= 60 ? "#ff4030" : left <= 300 ? "#ff9a30" : "#f4d27a", 15, true, TextAnchor.UpperRight);
            Eu.Bar(app, new Rect(x, y, w, 14), DescentView.Progress(h), "#8a3a10", Loc.T("Depth {0} / {1}", Json.Int(h, "depth"), Json.Int(h, "rooms")));
            y += 18;
            if (d.End != null)
            {
                y += Eu.Wrap(app, x, y, w, d.End.Title, d.End.Color, 14, true);
                foreach (string l in d.End.Lines) y += Eu.Wrap(app, x, y, w, l, d.End.Color, 12);
                return;
            }
            y += Eu.Wrap(app, x, y, w, DescentView.StateLine(h), Eu.Text, 12);
            Eu.Label(app, new Rect(x, y, w, 16), DescentView.EmbersLine(h), "#ff9a3c", 12, true);
            y += 20;
            var boons = Json.List(h, "boons");
            var curses = Json.List(h, "curses");
            Eu.Label(app, new Rect(x, y, w, 16), boons.Count > 0 ? Loc.T("Boons") : Loc.T("No boons yet"), Eu.Gold, 12, true);
            y += 17;
            foreach (object b in boons)
            {
                int s = Json.Get(b, "s") is double sd ? (int)sd : 1;
                Eu.Label(app, new Rect(x + 4, y, w - 8, 15), "+ " + Json.Text(b, "n") + (s > 1 ? " x" + s : "") + " - " + Json.Text(b, "d"), Eu.Good, 11);
                y += 15;
            }
            if (curses.Count > 0)
            {
                Eu.Label(app, new Rect(x, y, w, 16), Loc.T("Curses"), "#e03a1e", 12, true);
                y += 17;
                foreach (object c in curses) { Eu.Label(app, new Rect(x + 4, y, w - 8, 15), "- " + Json.Text(c, "n") + " - " + Json.Text(c, "d"), "#e03a1e", 11); y += 15; }
            }
            var party = Json.List(h, "party");
            if (party.Count > 1)
                foreach (object p in party) { Eu.Label(app, new Rect(x, y, w, 15), DescentView.PartyLine(p), Json.Bool(p, "alive") ? Eu.Text : Eu.Dim, 11); y += 15; }
            y += 4;
            if (Json.Text(h, "state") == "rest" && Eu.Button(new Rect(x, y, w * 0.5f, 24), Loc.T("Continue"), !Json.Bool(h, "ready"))) d.Ready();
            if (GUI.Button(new Rect(x + w * 0.5f + 6, y, w * 0.5f - 6, 24), Loc.T("Leave"))) d.Leave();
        }
    }

    public sealed class DescentOfferWindow : EgHudWindow
    {
        bool curse;
        object lastOffer;
        public override string Title => Loc.T("Choose a Boon");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 330, 110, 660, 320);
        protected override bool Wanted(ChaosApp app) => app.Session.Endgame.Descent.Offer != null;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var d = app.Session?.Endgame?.Descent;
            if (d == null || d.Offer == null) return;
            if (!ReferenceEquals(lastOffer, d.Offer)) { lastOffer = d.Offer; curse = false; }
            var offer = d.Offer;
            double now = app.Session.Now;
            string src = Json.Text(offer, "source");
            float x = inner.x + 6, w = inner.width - 12, y = inner.y + 2;
            Eu.Label(app, new Rect(x, y, w, 18), src == "shrine" ? Loc.T("The Shrine: Choose a Boon") : src == "merchant" ? Loc.T("Boon Cache: Choose a Boon") : Loc.T("Choose a Boon"), Eu.Bright, 14, true, TextAnchor.UpperCenter);
            y += 20;
            Eu.Label(app, new Rect(x, y, w, 16), Loc.T("Room {0} / {1}   -   {2} left to choose", Json.Int(offer, "room"), Json.Int(offer, "rooms"), Eg.Clock(d.OfferLeft(now))), Eu.Text, 12, false, TextAnchor.UpperCenter);
            y += 24;
            var cards = Json.List(offer, "cards");
            float cw = 190, gap = 12, total = cards.Count * cw + Math.Max(0, cards.Count - 1) * gap, cx = x + (w - total) / 2;
            for (int i = 0; i < cards.Count; i++)
            {
                var r = new Rect(cx + i * (cw + gap), y, cw, 170);
                Eu.Panel(r, 0.08f);
                Eu.Label(app, new Rect(r.x + 6, r.y + 4, r.width - 12, 20), DescentView.CardTitle(cards[i]), Eu.Bright, 14, true, TextAnchor.UpperCenter);
                Eu.Label(app, new Rect(r.x + 6, r.y + 26, r.width - 12, 16), DescentView.CardNote(cards[i]), Eu.Dim, 11, false, TextAnchor.UpperCenter);
                Eu.Label(app, new Rect(r.x + 8, r.y + 48, r.width - 16, 80), Json.Text(cards[i], "d"), Eu.Text, 12, false, TextAnchor.UpperLeft, true);
                if (GUI.Button(new Rect(r.x + 20, r.yMax - 32, r.width - 40, 26), Loc.T("Pick"))) { d.Pick(i + 1, curse); return; }
            }
            y += 178;
            if (Json.Get(offer, "curse") is Dictionary<string, object>)
            {
                var strip = new Rect(x, y, w, 40);
                Eu.Panel(strip, 0.08f);
                curse = GUI.Toggle(new Rect(strip.x + 6, strip.y + 4, 26, 24), curse, GUIContent.none);
                Eu.Label(app, new Rect(strip.x + 36, strip.y + 3, strip.width - 42, 34), Loc.T("Take the curse: ") + DescentView.CurseLine(Json.Get(offer, "curse")), "#e03a1e", 11, false, TextAnchor.UpperLeft, true);
            }
        }
    }

    public sealed class DescentShopWindow : EgHudWindow
    {
        public override string Title => Loc.T("Merchant");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 200, 120, 400, 320);
        protected override bool Wanted(ChaosApp app) => app.Session.Endgame.Descent.ShopVisible;
        Vector2 scroll;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var d = app.Session?.Endgame?.Descent;
            if (d == null || d.Shop == null) return;
            double embers = Json.Number(d.Shop, "embers");
            float x = inner.x + 6, w = inner.width - 12, y = inner.y + 2;
            Eu.Label(app, new Rect(x, y, w, 18), Loc.T("Your embers: {0}", Eg.Number(embers)), Eu.Bright, 13, true);
            y += 22;
            var wares = Json.List(d.Shop, "wares");
            var view = new Rect(x, y, w, inner.yMax - y - 2);
            int rowH = 56;
            scroll = GUI.BeginScrollView(view, scroll, new Rect(0, 0, view.width - 18, Mathf.Max(view.height, wares.Count * rowH)));
            for (int i = 0; i < wares.Count; i++)
            {
                var r = new Rect(0, i * rowH, view.width - 20, rowH - 3);
                Eu.Panel(r, 0.06f);
                Eu.Label(app, new Rect(r.x + 6, r.y + 3, r.width - 120, 18), Json.Text(wares[i], "n"), Eu.Text, 13, true);
                Eu.Label(app, new Rect(r.x + 6, r.y + 22, r.width - 120, 30), Json.Text(wares[i], "d"), Eu.Dim, 11, false, TextAnchor.UpperLeft, true);
                bool can = DescentView.Ware(wares[i], embers, out string text);
                if (Eu.Button(new Rect(r.xMax - 108, r.y + 14, 104, 26), text, can)) d.Buy(Json.Text(wares[i], "k"));
            }
            GUI.EndScrollView();
        }
    }

    // ================================================================================================ Rift Atlas and Waystone Atlas
    public abstract class AtlasWindowBase : GameWindow
    {
        bool lastVisible, dragging;
        Vector2 sideScroll;
        string confirm = "";
        protected abstract AtlasState St(ChaosApp app);
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 430, 40, 860, 540);
        public override void Reset() { lastVisible = false; Open = false; confirm = ""; }

        public override void Tick(ChaosApp app)
        {
            var a = St(app);
            if (a == null) return;
            WindowSync.Run(ref lastVisible, this, a.Visible, a.Open, a.Hide);
        }

        static Color NodeColor(string status, string kind)
        {
            switch (status)
            {
                case "alloc": return Eu.Hex(kind == "keystone" ? "#ff8a5a" : "#f6cf72");
                case "avail": return Eu.Hex("#7fd07f");
                case "reach": return Eu.Hex("#b8873a");
                case "start": return Eu.Hex("#ffffff");
                default: return Eu.Hex("#4a4438");
            }
        }

        static void Line(Vector2 a, Vector2 b, float width, Color c)
        {
            var d = b - a;
            float len = d.magnitude;
            if (len < 0.5f) return;
            var saved = GUI.matrix;
            GUIUtility.RotateAroundPivot(Mathf.Atan2(d.y, d.x) * Mathf.Rad2Deg, a);
            GUI.DrawTexture(new Rect(a.x, a.y - width / 2, len, width), Texture2D.whiteTexture, ScaleMode.StretchToFill, false, 0, c, 0, 0);
            GUI.matrix = saved;
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var a = St(app);
            if (a == null) return;
            float sideW = 270;
            var map = new Rect(inner.x + 4, inner.y + 2, inner.width - sideW - 12, inner.height - 30);
            ChaosApp.Fill(map, new Color(0f, 0f, 0f, 0.55f));
            if (a.Tree == null) Eu.Label(app, map, Loc.T("Asking the server..."), Eu.Dim, 13, false, TextAnchor.MiddleCenter);
            else DrawMap(app, a, map);
            Eu.Label(app, new Rect(map.x, map.yMax + 4, map.width, 20), a.StatusText, Eg.Hex(a.StatusColor, Eu.Bright), 12);
            if (Eu.Button(new Rect(map.xMax - 190, map.yMax + 3, 28, 22), "-")) a.ZoomBy(-1);
            if (Eu.Button(new Rect(map.xMax - 158, map.yMax + 3, 28, 22), "+")) a.ZoomBy(1);
            if (Eu.Button(new Rect(map.xMax - 126, map.yMax + 3, 126, 22), Loc.T("Center"))) a.Center();
            DrawSide(app, a, new Rect(map.xMax + 6, inner.y + 2, sideW, inner.height - 4));
        }

        void DrawMap(ChaosApp app, AtlasState a, Rect map)
        {
            var e = Event.current;
            if (e.type == EventType.ScrollWheel && map.Contains(e.mousePosition)) { a.ZoomBy(e.delta.y < 0 ? 1 : -1); e.Use(); }
            if (e.type == EventType.MouseDown && map.Contains(e.mousePosition) && e.button == 0) dragging = true;
            if (e.type == EventType.MouseUp) dragging = false;
            if (e.type == EventType.MouseDrag && dragging)
            {
                a.PanX += e.delta.x; a.PanY += e.delta.y;
                e.Use();
            }
            AtlasView.ClampPan(a.PanX, a.PanY, a.Zoom, a.World, map.width, map.height, out double px, out double py);
            a.PanX = px; a.PanY = py;
            Vector2 mid = new Vector2(map.width / 2 + (float)a.PanX, map.height / 2 + (float)a.PanY);
            GUI.BeginClip(map);
            double zoom = a.Zoom;
            foreach (var pair in a.Ix.Pairs)
            {
                var na = a.Ix.ById[pair[0]]; var nb = a.Ix.ById[pair[1]];
                AtlasView.Place(a.World, na, zoom, out int ax, out int ay);
                AtlasView.Place(a.World, nb, zoom, out int bx, out int by);
                string ls = AtlasView.LinkState(a.Ix, a.Alloc, pair[0], pair[1]);
                Color c = ls == "Active" ? Eu.Hex("#f6cf72") : ls == "Intermediate" ? Eu.Hex("#7a6a40") : Eu.Hex("#3a352c");
                Line(mid + new Vector2(ax, ay), mid + new Vector2(bx, by), ls == "Active" ? 4f : 2.5f, c);
            }
            foreach (var n in a.Ix.List)
            {
                AtlasView.Place(a.World, n, zoom, out int nx, out int ny);
                int size = AtlasView.NodeSize(n.K, zoom);
                var r = new Rect(mid.x + nx - size / 2f, mid.y + ny - size / 2f, size, size);
                if (r.xMax < 0 || r.yMax < 0 || r.x > map.width || r.y > map.height) continue;
                string st = a.StatusOf(n.I);
                ChaosApp.Fill(new Rect(r.x - 2, r.y - 2, r.width + 4, r.height + 4), n.I == a.Selected ? Color.white : new Color(0f, 0f, 0f, 0.9f));
                ChaosApp.Fill(r, NodeColor(st, n.K) * (st == "locked" ? 1f : 0.9f));
                string glyph = AtlasView.Glyph(a.Ix, n);
                if (size >= 18) GUI.Label(r, glyph.Length > 0 ? glyph.Substring(0, 1).ToUpperInvariant() : "", Eu.Style(app, Mathf.Clamp(size / 2, 9, 20), "#101010", true, TextAnchor.MiddleCenter));
                if (GUI.Button(r, GUIContent.none, GUIStyle.none)) { a.Pick(n.I); confirm = ""; }
            }
            GUI.EndClip();
        }

        void DrawSide(ChaosApp app, AtlasState a, Rect side)
        {
            float x = side.x, w = side.width, y = side.y;
            Eu.Label(app, new Rect(x, y, w, 24), Loc.T("Points: {0}", AtlasView.PointsLine(a.State)), Eu.Bright, 17, true);
            y += 26;
            Eu.Label(app, new Rect(x, y, w, 16), AtlasView.EarnedLine(a.State), Eu.Dim, 11);
            y += 22;
            var node = a.SelectedNode;
            Eu.Panel(new Rect(x, y, w, 196), 0.06f);
            float ny = y + 4;
            if (node == null)
            {
                Eu.Label(app, new Rect(x + 6, ny, w - 12, 20), Loc.T("No node selected"), Eu.Text, 13, true);
                Eu.Wrap(app, x + 6, ny + 22, w - 12, Loc.T("Click a node on the map to see what it does."), Eu.Dim, 11);
            }
            else
            {
                string kc = node.K == "keystone" ? "#ff8a5a" : node.K == "notable" ? "#f6cf72" : Eu.Text;
                Eu.Label(app, new Rect(x + 6, ny, w - 12, 20), node.N, kc, 14, true);
                Eu.Label(app, new Rect(x + 6, ny + 20, w - 12, 16), AtlasView.KindLine(node), Eu.Dim, 11);
                float th = Eu.Wrap(app, x + 6, ny + 38, w - 12, string.Join("\n", node.T), Eu.Text, 12);
                bool okA = a.CanAllocate(node.I, out string whyA), okR = a.CanRefund(node.I, out string whyR);
                string status = a.StatusOf(node.I);
                string line = status == "start" ? "" : a.Alloc.Contains(node.I) ? (okR ? Loc.T("Allocated.") : Loc.T("Allocated. Other nodes depend on it.")) : (okA ? Loc.T("Can be allocated.") : AtlasView.ReasonText(whyA));
                Eu.Label(app, new Rect(x + 6, y + 112, w - 12, 30), line, Eu.Bright, 11, false, TextAnchor.UpperLeft, true);
                if (Eu.Button(new Rect(x + 6, y + 146, w - 12, 22), Loc.T("Allocate"), okA)) { if (node.K == "keystone") confirm = "alloc"; else a.AllocateSelected(); }
                AtlasView.RefundLabels(a.State, out string gold, out string orb);
                float hw = (w - 18) / 2;
                if (Eu.Button(new Rect(x + 6, y + 170, hw, 22), gold, okR)) confirm = "refund:gold";
                if (Eu.Button(new Rect(x + 12 + hw, y + 170, hw, 22), orb, okR)) confirm = "refund:orb";
            }
            y += 202;
            if (confirm.Length > 0)
            {
                string q = confirm == "alloc" ? Loc.T("Allocate this keystone? You can hold only {0} at a time.", a.KeystoneMax)
                    : confirm.StartsWith("refund") ? Loc.T("Refund this node?") : Loc.T("Reset the whole atlas?");
                float qh = Eu.Wrap(app, x, y, w, q, "#f6cf72", 11);
                float hw2 = (w - 6) / 2;
                if (GUI.Button(new Rect(x, y + qh, hw2, 22), Loc.T("Yes")))
                {
                    if (confirm == "alloc") a.AllocateSelected();
                    else if (confirm == "refund:gold") a.RefundSelected("gold");
                    else if (confirm == "refund:orb") a.RefundSelected("orb");
                    else if (confirm == "reset:gold") a.Reset("gold");
                    else if (confirm == "reset:orb") a.Reset("orb");
                    confirm = "";
                }
                if (GUI.Button(new Rect(x + hw2 + 6, y + qh, hw2, 22), Loc.T("Cancel"))) confirm = "";
                y += qh + 26;
            }
            else if (Eu.Button(new Rect(x, y, w, 22), Loc.T("Reset atlas"), a.Alloc.Count > 0)) confirm = "reset:gold";
            if (confirm == "reset:gold") { }
            y += 28;
            // totals and the grid
            var view = new Rect(x, y, w, side.yMax - y);
            var rows = a.Grid();
            AtlasView.GridCount(rows, out int done, out int total);
            int lines = a.State != null ? Json.List(a.State, "totals").Count : 0;
            float contentH = 24 + Math.Max(1, lines) * 16 + 24 + rows.Count * 18 + 30;
            sideScroll = GUI.BeginScrollView(view, sideScroll, new Rect(0, 0, view.width - 18, Mathf.Max(view.height, contentH)));
            float cy = 0;
            Eu.Label(app, new Rect(0, cy, view.width - 18, 18), Loc.T("Totals"), Eu.Gold, 12, true);
            cy += 20;
            if (lines == 0) cy += Eu.Wrap(app, 0, cy, view.width - 18, a.IsWaystone ? Loc.T("Nothing allocated yet. Kill map bosses in waystone runs to earn points, then pick nodes on the map.") : Loc.T("Nothing allocated yet. Seal rifts to earn points, then pick nodes on the map."), Eu.Dim, 11);
            else foreach (string t in Eg.Strings(a.State, "totals")) cy += Eu.Wrap(app, 0, cy, view.width - 18, "- " + t, Eu.Text, 11);
            cy += 6;
            Eu.Label(app, new Rect(0, cy, view.width - 18, 18), Loc.T("Completed cells: {0} / {1}", done, total), Eu.Gold, 12, true);
            cy += 20;
            foreach (var row in rows)
            {
                Eu.Label(app, new Rect(0, cy, 60, 16), row.Label, row.Color, 11, true);
                for (int i = 0; i < row.Cells.Count; i++)
                {
                    var cr = new Rect(62 + i * 12, cy + 2, 10, 10);
                    ChaosApp.Fill(cr, row.Cells[i].Done ? Eu.Hex(row.Cells[i].Color ?? row.Color) : new Color(1f, 1f, 1f, 0.14f));
                }
                cy += 18;
            }
            GUI.EndScrollView();
        }
    }

    public sealed class RiftAtlasWindow : AtlasWindowBase
    {
        public override string Title => Loc.T("Rift Atlas");
        protected override AtlasState St(ChaosApp app) => app.Session?.Endgame?.RiftAtlas;
    }

    public sealed class WaystoneAtlasWindow : AtlasWindowBase
    {
        public override string Title => Loc.T("Waystone Atlas");
        protected override AtlasState St(ChaosApp app) => app.Session?.Endgame?.WaystoneAtlas;
    }

    // ================================================================================================ Invasions
    public sealed class InvasionWindow : GameWindow
    {
        bool lastVisible;
        Vector2 scroll;
        public override string Title => Loc.T("Invasions and events");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 210, 90, 420, 380);
        public override void Reset() { lastVisible = false; Open = false; }

        public override void Tick(ChaosApp app)
        {
            var s = app.Session?.Endgame?.Invasion;
            if (s == null) return;
            WindowSync.Run(ref lastVisible, this, s.CalendarVisible, s.ShowCalendar, s.HideCalendar);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var s = app.Session?.Endgame?.Invasion;
            if (s == null) return;
            var view = new Rect(inner.x + 4, inner.y + 2, inner.width - 8, inner.height - 4);
            int rowH = 24;
            int n = Math.Max(1, s.Calendar.Count);
            scroll = GUI.BeginScrollView(view, scroll, new Rect(0, 0, view.width - 18, Mathf.Max(view.height, n * rowH)));
            if (s.Calendar.Count == 0)
            {
                Eu.Label(app, new Rect(4, 2, 100, rowH), "-", Eu.Text, 12);
                Eu.Label(app, new Rect(110, 2, view.width - 130, rowH), Loc.T("Nothing planned yet."), Eu.Dim, 12);
            }
            for (int i = 0; i < s.Calendar.Count; i++)
            {
                object e = s.Calendar[i];
                var r = new Rect(0, i * rowH, view.width - 18, rowH - 2);
                Eu.Panel(r, 0.05f);
                Eu.Label(app, new Rect(6, r.y + 3, 130, rowH), Json.Text(e, "when"), Eu.Text, 12);
                Eu.Label(app, new Rect(140, r.y + 3, view.width - 270, rowH), Json.Text(e, "name"), InvasionView.KindColor(Json.Text(e, "kind")), 12, true);
                if (Json.Number(e, "inSeconds") > 0) Eu.Label(app, new Rect(view.width - 120, r.y + 3, 100, rowH), InvasionView.Countdown(Json.Number(e, "inSeconds")), Eu.Dim, 11, false, TextAnchor.UpperRight);
            }
            GUI.EndScrollView();
        }
    }

    public sealed class InvasionHudWindow : EgHudWindow
    {
        public override string Title => Loc.T("Invasion");
        protected override Rect Place(float w, float h) => new Rect(8, 108, 270, 230);
        protected override bool Wanted(ChaosApp app) => app.Session.Endgame.Invasion.HudShown;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var s = app.Session?.Endgame?.Invasion;
            if (s == null || s.Hud == null) return;
            var d = s.Hud;
            double now = app.Session.Now;
            float x = inner.x + 6, w = inner.width - 12, y = inner.y + 2;
            Eu.Label(app, new Rect(x, y, w - 60, 18), InvasionView.Title(d), Eg.Hex(Json.Text(d, "color"), Eu.Gold), 14, true);
            double left = s.TimeLeft(now);
            Eu.Label(app, new Rect(x + w - 60, y, 60, 18), Eg.Clock(left), left <= 60 ? "#ff4030" : "#f4d27a", 14, true, TextAnchor.UpperRight);
            y += 20;
            y += Eu.Wrap(app, x, y, w, InvasionView.Subtitle(d), Eu.Text, 11);
            Eu.Label(app, new Rect(x, y, w, 16), InvasionView.WaveLine(d, s.NextLeft(now)), Eu.Text, 12);
            y += 18;
            double progress = Json.Number(d, "progress");
            bool occ = Json.Text(d, "phase") == "occupied";
            Eu.Bar(app, new Rect(x, y, w, 14), progress, "#2f7a2a", occ ? Loc.T("Occupied") : Loc.T("Horde slain: {0}%", (int)progress));
            y += 18;
            if (!occ)
            {
                double breach = Json.Number(d, "breach");
                Eu.Bar(app, new Rect(x, y, w, 14), breach, InvasionView.BreachColor(breach), Loc.T("Breach: {0}%", (int)breach));
                y += 18;
            }
            var sides = InvasionView.SideLines(d);
            foreach (var l in sides) { Eu.Label(app, new Rect(x, y, w, 15), l.Key, l.Value, 11, true); y += 15; }
            if (sides.Count == 0 && Json.Get(d, "boss") is string boss)
            {
                Eu.Label(app, new Rect(x, y, w, 15), Loc.T("{0} - {1}%", boss, Json.Get(d, "bossHp") is double hp ? (int)hp : 100), Eu.Bad, 11, true);
                y += 15;
            }
            if (!s.Folded)
            {
                foreach (string l in InvasionView.TopLines(d)) { Eu.Label(app, new Rect(x, y, w, 15), l, Eu.Text, 11); y += 15; }
                Eu.Label(app, new Rect(x, y, w, 15), InvasionView.YouLine(Json.Get(d, "you")), Eu.Bright, 11, true);
                y += 17;
            }
            if (s.ResultText.Length > 0) y += Eu.Wrap(app, x, y, w, s.ResultText, s.ResultColor, 12, true);
            if (GUI.Button(new Rect(x + w - 70, inner.yMax - 24, 70, 20), s.Folded ? Loc.T("Unfold") : Loc.T("Fold"))) s.Folded = !s.Folded;
        }
    }
}
