// Windows of the world and map utilities (track O): Map Markers (game_mapmarkers settings), Map Overlay (settings and the toggle), Go to NPC (game_npctravel),
// Waystone, Town Portal and Hideout. Models: Core/WorldMarks.cs, WorldTravel.cs. The map drawing (marks, overlay, hideout ghosts) is ChaosApp.World.cs.
// No window has a Ctrl hotkey: they open from the top menu or when the server says so.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>Small drawing helpers the world and item windows share.</summary>
    static class Ui
    {
        public static Color Hex(string hex) => ColorUtility.TryParseHtmlString(hex ?? "", out var c) ? c : Color.white;

        public static GUIStyle Wrap(ChaosApp app, int size = 12)
        {
            return new GUIStyle(app.SmallStyle) { fontSize = size, wordWrap = true };
        }

        /// <summary>A text in a colour; the height of a wrapped text is given back.</summary>
        public static float Text(Rect r, string text, GUIStyle st, string hex = null)
        {
            var old = GUI.contentColor;
            if (hex != null) GUI.contentColor = Hex(hex);
            GUI.Label(r, text, st);
            GUI.contentColor = old;
            return r.height;
        }

        public static float Height(string text, GUIStyle st, float width) => st.CalcHeight(new GUIContent(text), width);

        /// <summary>A wrapped paragraph at (x, y); returns the y under it.</summary>
        public static float Para(string text, GUIStyle st, float x, float y, float w, string hex = null)
        {
            if (string.IsNullOrEmpty(text)) return y;
            float h = Height(text, st, w);
            Text(new Rect(x, y, w, h), text, st, hex);
            return y + h + 2;
        }

        public static bool Check(Rect r, bool on, string label, GUIStyle st)
        {
            bool v = GUI.Toggle(new Rect(r.x, r.y, 18, r.height), on, "");
            GUI.Label(new Rect(r.x + 20, r.y, r.width - 20, r.height), label, st);
            if (Event.current.type == EventType.MouseDown && new Rect(r.x + 20, r.y, r.width - 20, r.height).Contains(Event.current.mousePosition)) { v = !on; Event.current.Use(); }
            return v;
        }

        public static void Frame(Rect r, Color border)
        {
            ChaosApp.Fill(new Rect(r.x, r.y, r.width, 1), border); ChaosApp.Fill(new Rect(r.x, r.yMax - 1, r.width, 1), border);
            ChaosApp.Fill(new Rect(r.x, r.y, 1, r.height), border); ChaosApp.Fill(new Rect(r.xMax - 1, r.y, 1, r.height), border);
        }

        /// <summary>A row with a hover and a click; true when it was clicked.</summary>
        public static bool Row(Rect r, bool selected)
        {
            ChaosApp.Fill(r, selected ? new Color(0.45f, 0.33f, 0.1f, 0.8f) : new Color(1f, 1f, 1f, 0.05f));
            var e = Event.current;
            if (r.Contains(e.mousePosition))
            {
                if (e.type == EventType.Repaint) ChaosApp.Fill(r, new Color(1f, 1f, 1f, 0.08f));
                if (e.type == EventType.MouseDown && e.button == 0) { e.Use(); return true; }
            }
            return false;
        }
    }

    // ------------------------------------------------------------------------------------------------ map markers
    /// <summary>Settings of the map markers (game_mapmarkers): party members, arrows on the game view, points of interest and their categories, quest marks over NPCs.</summary>
    public sealed class MapMarkersWindow : GameWindow
    {
        public override string Title => Loc.T("Map Markers");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 170, 80, 340, 400);
        bool loaded;
        GUIStyle st;

        public override void Reset() { loaded = false; }

        /// <summary>The saved settings (PlayerPrefs chaos.mm.*) go into the model before the login hello.</summary>
        public override void Tick(ChaosApp app)
        {
            var m = app.Session?.Utils?.Marks;
            if (m == null || loaded) return;
            loaded = true;
            var s = m.Settings;
            s.Party = PlayerPrefs.GetInt("chaos.mm.party", 1) != 0; s.Poi = PlayerPrefs.GetInt("chaos.mm.poi", 1) != 0;
            s.Game = PlayerPrefs.GetInt("chaos.mm.game", 1) != 0; s.NpcMarks = PlayerPrefs.GetInt("chaos.mm.npc", 1) != 0;
            foreach (string c in MapMarkMath.Categories) s.Cats[c] = PlayerPrefs.GetInt("chaos.mm.cat." + c, 1) != 0;
        }

        static void Save(MapMarkSettings s)
        {
            PlayerPrefs.SetInt("chaos.mm.party", s.Party ? 1 : 0); PlayerPrefs.SetInt("chaos.mm.poi", s.Poi ? 1 : 0);
            PlayerPrefs.SetInt("chaos.mm.game", s.Game ? 1 : 0); PlayerPrefs.SetInt("chaos.mm.npc", s.NpcMarks ? 1 : 0);
            foreach (var kv in s.Cats) PlayerPrefs.SetInt("chaos.mm.cat." + kv.Key, kv.Value ? 1 : 0);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var m = app.Session?.Utils?.Marks;
            if (m == null) return;
            if (st == null) st = new GUIStyle(app.SmallStyle) { fontSize = 13 };
            var s = m.Settings;
            float x = inner.x + 6, y = inner.y + 4, w = inner.width - 12;
            bool v = Ui.Check(new Rect(x, y, w, 22), s.Party, Loc.T("Party members on the map"), st); if (v != s.Party) { m.SetKind("party", v); Save(s); } y += 24;
            v = Ui.Check(new Rect(x, y, w, 22), s.Game, Loc.T("Arrows on the game view"), st); if (v != s.Game) { m.SetKind("game", v); Save(s); } y += 24;
            v = Ui.Check(new Rect(x, y, w, 22), s.NpcMarks, Loc.T("Quest marks over NPCs"), st); if (v != s.NpcMarks) { m.SetKind("npcmarks", v); Save(s); } y += 24;
            v = Ui.Check(new Rect(x, y, w, 22), s.Poi, Loc.T("Points of interest"), st); if (v != s.Poi) { m.SetKind("poi", v); Save(s); } y += 28;
            GUI.enabled = s.Poi;
            foreach (string c in MapMarkMath.Categories)
            {
                bool on = s.Cat(c);
                bool nv = Ui.Check(new Rect(x + 16, y, w - 16, 22), on, Loc.T(MapMarkMath.CategoryLabel[c]), st);
                if (nv != on) { s.Cats[c] = nv; Save(s); m.Changed(); }
                y += 24;
            }
            GUI.enabled = true;
        }
    }

    // ------------------------------------------------------------------------------------------------ map overlay
    /// <summary>Settings and the switch of the map overlay (game_mapoverlay). The overlay itself is drawn over the game view by ChaosApp.World.cs.</summary>
    public sealed class MapOverlayWindow : GameWindow
    {
        public override string Title => Loc.T("Map Overlay");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 160, 90, 320, 290);
        bool loaded;
        GUIStyle st;

        public override void Reset() { loaded = false; }

        public override void Tick(ChaosApp app)
        {
            var o = app.Session?.Utils?.Overlay;
            if (o == null || loaded) return;
            loaded = true;
            var s = o.Settings;
            s.Opacity = MapOverlayState.StepOpacity(PlayerPrefs.GetFloat("chaos.mo.opacity", 0.6f), 0);
            s.Zoom = MapOverlayState.ClampZoom(PlayerPrefs.GetInt("chaos.mo.zoom", 2));
            s.Corner = PlayerPrefs.GetInt("chaos.mo.corner", 0) != 0;
            s.Party = PlayerPrefs.GetInt("chaos.mo.party", 1) != 0; s.Town = PlayerPrefs.GetInt("chaos.mo.town", 1) != 0;
            s.Events = PlayerPrefs.GetInt("chaos.mo.events", 1) != 0; s.Strip = PlayerPrefs.GetInt("chaos.mo.strip", 1) != 0;
        }

        public static void Save(MapOverlaySettings s)
        {
            PlayerPrefs.SetFloat("chaos.mo.opacity", (float)s.Opacity); PlayerPrefs.SetInt("chaos.mo.zoom", s.Zoom); PlayerPrefs.SetInt("chaos.mo.corner", s.Corner ? 1 : 0);
            PlayerPrefs.SetInt("chaos.mo.party", s.Party ? 1 : 0); PlayerPrefs.SetInt("chaos.mo.town", s.Town ? 1 : 0);
            PlayerPrefs.SetInt("chaos.mo.events", s.Events ? 1 : 0); PlayerPrefs.SetInt("chaos.mo.strip", s.Strip ? 1 : 0);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var o = app.Session?.Utils?.Overlay;
            if (o == null) return;
            if (st == null) st = new GUIStyle(app.SmallStyle) { fontSize = 13 };
            var s = o.Settings;
            float x = inner.x + 6, y = inner.y + 4, w = inner.width - 12;
            if (GUI.Button(new Rect(x, y, w, 28), o.Shown ? Loc.T("Hide the overlay") : Loc.T("Show the overlay"))) o.Toggle();
            y += 36;
            GUI.Label(new Rect(x, y, 90, 22), Loc.T("Opacity"), st);
            if (GUI.Button(new Rect(x + 100, y, 26, 22), "-")) { s.Opacity = MapOverlayState.StepOpacity(s.Opacity, -0.1); Save(s); }
            GUI.Label(new Rect(x + 130, y, 50, 22), MapOverlayState.Percent(s.Opacity), st);
            if (GUI.Button(new Rect(x + 184, y, 26, 22), "+")) { s.Opacity = MapOverlayState.StepOpacity(s.Opacity, 0.1); Save(s); }
            y += 28;
            GUI.Label(new Rect(x, y, 90, 22), Loc.T("Zoom"), st);
            if (GUI.Button(new Rect(x + 100, y, 26, 22), "-")) { s.Zoom = MapOverlayState.ClampZoom(s.Zoom - 1); Save(s); }
            GUI.Label(new Rect(x + 130, y, 50, 22), MapOverlayState.ZoomLabel(s.Zoom), st);
            if (GUI.Button(new Rect(x + 184, y, 26, 22), "+")) { s.Zoom = MapOverlayState.ClampZoom(s.Zoom + 1); Save(s); }
            y += 30;
            bool v = Ui.Check(new Rect(x, y, w, 22), s.Corner, Loc.T("A box in the top right corner"), st); if (v != s.Corner) { s.Corner = v; Save(s); } y += 24;
            v = Ui.Check(new Rect(x, y, w, 22), s.Strip, Loc.T("Control strip"), st); if (v != s.Strip) { s.Strip = v; Save(s); } y += 24;
            v = Ui.Check(new Rect(x, y, w, 22), s.Party, Loc.T("Party members"), st); if (v != s.Party) { s.Party = v; Save(s); } y += 24;
            v = Ui.Check(new Rect(x, y, w, 22), s.Town, Loc.T("Temple, depots and NPCs"), st); if (v != s.Town) { s.Town = v; Save(s); } y += 24;
            v = Ui.Check(new Rect(x, y, w, 22), s.Events, Loc.T("Rifts, bosses and events"), st); if (v != s.Events) { s.Events = v; Save(s); } y += 26;
            GUI.Label(new Rect(x, y, w, 40), Loc.T("Shift + wheel zooms, Ctrl + wheel changes the opacity, Shift + middle drag pans."), new GUIStyle(st) { wordWrap = true, fontSize = 11 });
        }
    }

    // ------------------------------------------------------------------------------------------------ go to npc
    /// <summary>Go to NPC (game_npctravel): the server takes you in front of the NPC of a service (it checks combat, instances and the cooldown).</summary>
    public sealed class GoToNpcWindow : GameWindow
    {
        public override string Title => Loc.T("Go to NPC");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 150, 90, 300, 440);
        Vector2 scroll;
        GUIStyle st;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var t = app.Session?.Utils?.Travel;
            if (t == null) return;
            if (st == null) st = new GUIStyle(app.SmallStyle) { fontSize = 13 };
            var keys = NpcTravel.Keys;
            scroll = GUI.BeginScrollView(inner, scroll, new Rect(0, 0, inner.width - 18, keys.Length * 30 + 4));
            for (int i = 0; i < keys.Length; i++)
            {
                string name = NpcTravel.Names.TryGetValue(keys[i], out string n) ? Loc.T(n) : keys[i];
                GUI.Label(new Rect(6, i * 30 + 4, inner.width - 130, 24), name, st);
                if (GUI.Button(new Rect(inner.width - 118, i * 30 + 2, 96, 24), Loc.T("Go to NPC"))) t.Travel(keys[i]);
            }
            GUI.EndScrollView();
        }
    }

    // ------------------------------------------------------------------------------------------------ waystone
    /// <summary>The waystone device (game_waystone): the tiers with their monster level and count, Open portals, the portal look.</summary>
    public sealed class WaystoneWindow : GameWindow
    {
        public override string Title => Loc.T("Waystone");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 190, 70, 380, 470);
        bool lastVisible;
        Vector2 scroll;
        GUIStyle st, small;

        public override void Reset() { lastVisible = false; Open = false; }

        public override void Tick(ChaosApp app)
        {
            var w = app.Session?.Utils?.Waystone;
            if (w == null) return;
            WindowSync.Run(ref lastVisible, this, w.Visible, () => w.Visible = true, w.Hide);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var w = app.Session?.Utils?.Waystone;
            if (w == null) return;
            if (st == null) { st = new GUIStyle(app.SmallStyle) { fontSize = 13 }; small = Ui.Wrap(app, 11); }
            float x = inner.x + 4, y = inner.y + 2, width = inner.width - 8;
            if (w.ChoicesVisible)
            {
                GUI.Label(new Rect(x, y, width, 22), Loc.T("Portal look"), st); y += 26;
                foreach (var c in w.Choices)
                {
                    if (GUI.Button(new Rect(x, y, width, 26), c.Text)) w.ApplyChoice(c.Id);
                    y += 30;
                }
                if (GUI.Button(new Rect(x, y + 4, width, 26), Loc.T("Back"))) w.ChoicesVisible = false;
                return;
            }
            float listH = inner.height - 100;
            var view = new Rect(x, y, width, listH);
            scroll = GUI.BeginScrollView(view, scroll, new Rect(0, 0, width - 18, w.Rows.Count * 40 + 2));
            for (int i = 0; i < w.Rows.Count; i++)
            {
                var r = w.Rows[i];
                var rr = new Rect(0, i * 40, width - 18, 38);
                if (Ui.Row(rr, i == w.Selected)) w.Select(i);
                var pic = new Rect(rr.x + 3, rr.y + 3, 32, 32);
                app.DrawItem(pic, (ushort)r.Look, 1);
                var col = r.Usable ? Color.white : new Color(1f, 1f, 1f, 0.5f);
                var old = GUI.contentColor; GUI.contentColor = col;
                GUI.Label(new Rect(rr.x + 42, rr.y + 2, rr.width - 46, 18), Loc.T("Waystone Tier {0}", r.Roman), st);
                string lv = WaystoneState.LevelText(r), ct = WaystoneState.CountText(r);
                GUI.Label(new Rect(rr.x + 42, rr.y + 19, rr.width - 46, 16), lv.Length > 0 && ct.Length > 0 ? lv + "  " + ct : lv + ct, small);
                GUI.contentColor = old;
            }
            GUI.EndScrollView();
            y += listH + 4;
            y = Ui.Para(w.Status, small, x, y, width);
            GUI.enabled = w.Selected < w.Rows.Count && w.Rows.Count > 0 && w.Rows[w.Selected].Usable;
            if (GUI.Button(new Rect(x, inner.yMax - 32, width * 0.55f, 28), Loc.T("Open portals"))) w.Teleport(w.Selected);
            GUI.enabled = true;
            if (GUI.Button(new Rect(x + width * 0.55f + 6, inner.yMax - 32, width * 0.45f - 6, 28), Loc.T("Portal look"))) w.AskChoice();
        }
    }

    // ------------------------------------------------------------------------------------------------ town portal
    /// <summary>Town Portal (game_townportal): the portal styles and Cast. The cast bar shows over the character (the cast bar of the HUD).</summary>
    public sealed class TownPortalWindow : GameWindow
    {
        public override string Title => Loc.T("Town Portal");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 190, 80, 380, 440);
        bool lastVisible;
        Vector2 scroll;
        GUIStyle st, small;

        public override void Reset() { lastVisible = false; Open = false; }

        public override void Tick(ChaosApp app)
        {
            var p = app.Session?.Utils?.Portal;
            if (p == null) return;
            p.Tick(app.Session.Now);
            WindowSync.Run(ref lastVisible, this, p.Visible, p.Open, () => p.Visible = false);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var p = app.Session?.Utils?.Portal;
            if (p == null) return;
            if (st == null) { st = new GUIStyle(app.SmallStyle) { fontSize = 13 }; small = Ui.Wrap(app, 11); }
            float x = inner.x + 4, y = inner.y + 2, width = inner.width - 8;
            GUI.Label(new Rect(x, y, width, 22), p.StatusText(), st); y += 24;
            float listH = inner.height - 190;
            scroll = GUI.BeginScrollView(new Rect(x, y, width, listH), scroll, new Rect(0, 0, width - 18, p.Styles.Count * 40 + 2));
            for (int i = 0; i < p.Styles.Count; i++)
            {
                var s = p.Styles[i];
                var rr = new Rect(0, i * 40, width - 18, 38);
                if (Ui.Row(rr, s.Id == p.SelectedId)) p.Pick(s.Id);
                if (s.ClientItem > 0) app.DrawItem(new Rect(rr.x + 3, rr.y + 3, 32, 32), (ushort)s.ClientItem, 1);
                var old = GUI.contentColor; GUI.contentColor = s.Owned ? Color.white : Ui.Hex("#8c8070");
                GUI.Label(new Rect(rr.x + 42, rr.y + 2, rr.width - 46, 18), s.Name + (s.Selected ? "  *" : ""), st);
                GUI.Label(new Rect(rr.x + 42, rr.y + 19, rr.width - 46, 16), TownPortalState.RouteText(s), small);
                GUI.contentColor = old;
            }
            GUI.EndScrollView();
            y += listH + 4;
            var cur = p.StyleOf(p.SelectedId);
            if (cur != null)
            {
                y = Ui.Para(cur.Desc, small, x, y, width);
                y = Ui.Para(cur.How, small, x, y, width, "#8c8070");
            }
            float by = inner.yMax - 32;
            GUI.enabled = p.CanCast;
            if (GUI.Button(new Rect(x, by, width * 0.5f - 3, 28), Loc.T("Cast"))) p.Cast();
            GUI.enabled = cur != null && cur.Owned && !cur.Selected;
            if (GUI.Button(new Rect(x + width * 0.5f + 3, by, width * 0.5f - 3, 28), Loc.T("Use this style"))) p.SelectCurrent();
            GUI.enabled = true;
        }
    }

    // ------------------------------------------------------------------------------------------------ hideout
    /// <summary>Hideout (game_hideout): decorate (the catalogue, what is placed), the hideout (theme, who may visit, enter, leave, like) and visits. Placing is done on the map (ChaosApp.World.cs).</summary>
    public sealed class HideoutWindow : GameWindow
    {
        public override string Title => Loc.T("Hideout");
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 280), 60, Mathf.Min(560, w - 16), Mathf.Min(500, h - 70));
        bool lastVisible;
        int tab;
        string cat = "all", source = "all", search = "", selectedKey = "";
        bool ownedOnly;
        int selectedPlaced;
        Vector2 scrollList, scrollPlaced, scrollTab;
        bool showByVisits;
        GUIStyle st, small;

        public override void Reset() { lastVisible = false; Open = false; tab = 0; selectedKey = ""; selectedPlaced = 0; }

        public override void Tick(ChaosApp app)
        {
            var h = app.Session?.Utils?.Hideout;
            if (h == null) return;
            WindowSync.Run(ref lastVisible, this, h.Visible, h.Open, () => h.Visible = false);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var h = app.Session?.Utils?.Hideout;
            if (h == null) return;
            if (st == null) { st = new GUIStyle(app.SmallStyle) { fontSize = 13 }; small = Ui.Wrap(app, 11); }
            float x = inner.x + 4, y = inner.y + 2, w = inner.width - 8;
            string[] tabs = { Loc.T("Decorate"), Loc.T("Hideout"), Loc.T("Visit") };
            for (int i = 0; i < 3; i++)
                if (GUI.Toggle(new Rect(x + i * (w / 3), y, w / 3 - 4, 24), tab == i, tabs[i], GUI.skin.button) && tab != i) { tab = i; if (i == 2) h.Visits(); }
            y += 28;
            GUI.Label(new Rect(x, y, w, 20), h.CountText(), small);
            if (h.ResultText.Length > 0) Ui.Text(new Rect(x, y + 16, w, 18), h.ResultText, small, h.ResultOk ? "#8cd08c" : "#e07060");
            y += 36;
            var body = new Rect(x, y, w, inner.yMax - y);
            if (tab == 0) Decorate(app, h, body);
            else if (tab == 1) Settings(app, h, body);
            else Visits(app, h, body);
        }

        void Decorate(ChaosApp app, HideoutState h, Rect b)
        {
            float lw = b.width * 0.52f;
            // filters
            float y = b.y;
            if (GUI.Button(new Rect(b.x, y, lw * 0.5f - 2, 22), cat == "all" ? Loc.T("Any category") : Loc.T(cat))) cat = NextCategory(h);
            string srcName = "";
            foreach (var s in HideoutState.Sources) if (s.Key == source) srcName = s.Value;
            if (GUI.Button(new Rect(b.x + lw * 0.5f, y, lw * 0.5f, 22), Loc.T(srcName))) source = NextSource();
            y += 24;
            GUI.SetNextControlName("hideSearch");
            search = GUI.TextField(new Rect(b.x, y, lw - 80, 22), search, 30);
            if (GUI.GetNameOfFocusedControl() == "hideSearch") app.MarkTextEditing();
            ownedOnly = GUI.Toggle(new Rect(b.x + lw - 76, y, 76, 22), ownedOnly, Loc.T("Unlocked"));
            y += 26;
            var rows = HideoutState.Filter(h.Catalogue, cat, source, ownedOnly, search);
            var view = new Rect(b.x, y, lw, b.yMax - y);
            scrollList = GUI.BeginScrollView(view, scrollList, new Rect(0, 0, lw - 18, rows.Count * 40 + 2));
            for (int i = 0; i < rows.Count; i++)
            {
                var r = rows[i];
                var rr = new Rect(0, i * 40, lw - 18, 38);
                if (Ui.Row(rr, r.Key == selectedKey)) selectedKey = r.Key;
                if (r.Item > 0) app.DrawItem(new Rect(rr.x + 3, rr.y + 3, 32, 32), (ushort)r.Item, 1);
                var old = GUI.contentColor; GUI.contentColor = r.Owned ? Color.white : Ui.Hex("#8c8070");
                GUI.Label(new Rect(rr.x + 40, rr.y + 2, rr.width - 44, 18), r.Name, st);
                GUI.Label(new Rect(rr.x + 40, rr.y + 19, rr.width - 44, 16), HideoutState.SubText(r), small);
                GUI.contentColor = old;
            }
            GUI.EndScrollView();

            // detail and placed list
            float dx = b.x + lw + 6, dw = b.width - lw - 6, dy = b.y;
            var row = h.RowOf(selectedKey);
            if (row != null)
            {
                GUI.Label(new Rect(dx, dy, dw, 20), row.Name, st); dy += 22;
                dy = Ui.Para((row.Owned ? Loc.T("Unlocked") : Loc.T("Locked")) + " - " + row.How, small, dx, dy, dw);
                dy = Ui.Para(row.Placed + " / " + row.Max + " " + Loc.T("placed") + (row.Block ? "  -  " + Loc.T("blocks the way") : ""), small, dx, dy, dw);
                bool can = h.CanPlace(row, out string why);
                GUI.enabled = can;
                if (GUI.Button(new Rect(dx, dy, dw, 26), Loc.T("Place"))) { app.StartHideoutPlacing(row, 1, 0); Open = false; }
                GUI.enabled = true;
                dy += 30;
                dy = Ui.Para(can ? (row.Layer == "wall" ? Loc.T("Hangs on the north or the west wall.") : row.Layer == "floor" ? Loc.T("A rug: objects may stand on it.") : "") : why, small, dx, dy, dw, can ? null : "#e0a050");
            }
            dy += 6;
            GUI.Label(new Rect(dx, dy, dw, 20), Loc.T("Placed"), st); dy += 22;
            float ph = b.yMax - dy - 60;
            scrollPlaced = GUI.BeginScrollView(new Rect(dx, dy, dw, ph), scrollPlaced, new Rect(0, 0, dw - 18, h.Placed.Count * 24 + 2));
            for (int i = 0; i < h.Placed.Count; i++)
            {
                var p = h.Placed[i];
                var r = h.RowOf(p.Key);
                var rr = new Rect(0, i * 24, dw - 18, 22);
                if (Ui.Row(rr, p.Id == selectedPlaced)) selectedPlaced = p.Id;
                GUI.Label(new Rect(rr.x + 4, rr.y, rr.width - 4, 22), (r != null ? r.Name : p.Key) + "  (" + p.X + ", " + p.Y + ")", small);
            }
            GUI.EndScrollView();
            float by = b.yMax - 54;
            bool owner = h.HasInside && h.Inside.IsOwner;
            var pl = h.PlacedOf(selectedPlaced);
            GUI.enabled = pl != null && owner;
            if (GUI.Button(new Rect(dx, by, dw * 0.5f - 2, 24), Loc.T("Move")) && pl != null) { var r = h.RowOf(pl.Key); if (r != null) { app.StartHideoutPlacing(r, pl.R, pl.Id); Open = false; } }
            GUI.enabled = pl != null;
            if (GUI.Button(new Rect(dx + dw * 0.5f + 2, by, dw * 0.5f - 2, 24), Loc.T("Put away"))) h.Remove(selectedPlaced);
            GUI.enabled = h.Placed.Count > 0;
            if (GUI.Button(new Rect(dx, by + 28, dw, 24), confirmClear ? Loc.T("Confirm") : Loc.T("Put all away"))) { if (confirmClear) { h.ClearAll(); confirmClear = false; } else confirmClear = true; }
            GUI.enabled = true;
        }

        bool confirmClear;

        string NextCategory(HideoutState h)
        {
            var list = new List<string> { "all" };
            list.AddRange(h.Categories);
            int i = list.IndexOf(cat);
            return list[(i + 1) % list.Count];
        }

        string NextSource()
        {
            var s = HideoutState.Sources;
            for (int i = 0; i < s.Length; i++) if (s[i].Key == source) return s[(i + 1) % s.Length].Key;
            return "all";
        }

        void Settings(ChaosApp app, HideoutState h, Rect b)
        {
            float y = b.y;
            GUI.Label(new Rect(b.x, y, b.width, 20), Loc.T("Theme"), st); y += 22;
            foreach (var t in h.Themes)
            {
                var rr = new Rect(b.x, y, b.width, 38);
                if (Ui.Row(rr, t.Selected))
                {
                    if (t.Owned) h.Theme(t.Key);
                }
                if (t.Item > 0) app.DrawItem(new Rect(rr.x + 3, rr.y + 3, 32, 32), (ushort)t.Item, 1);
                var old = GUI.contentColor; GUI.contentColor = t.Owned ? Color.white : Ui.Hex("#8c8070");
                GUI.Label(new Rect(rr.x + 40, rr.y + 2, rr.width - 44, 18), t.Name + (t.Selected ? "  (" + Loc.T("yours") + ")" : ""), st);
                GUI.Label(new Rect(rr.x + 40, rr.y + 19, rr.width - 44, 16), t.Owned ? t.Desc + "  " + t.MaxDecor + " " + Loc.T("decorations") : Loc.T("Locked") + " - " + t.How, small);
                GUI.contentColor = old;
                y += 40;
            }
            y += 4;
            GUI.Label(new Rect(b.x, y, b.width, 20), Loc.T("Who may visit"), st); y += 22;
            foreach (var p in h.Permissions)
            {
                bool on = h.Info.Perm == p.Id;
                if (Ui.Check(new Rect(b.x, y, b.width, 22), on, p.Name + " - " + p.Desc, small) && !on) h.SetPerm(p.Id);
                y += 24;
            }
            y += 4;
            string stats = Loc.T("Likes") + ": " + h.Info.Likes + "   " + Loc.T("Visits") + ": " + h.Info.Visits;
            if (h.HasInside) stats += "\n" + Loc.T("You are in the hideout of") + " " + h.Inside.OwnerName;
            y = Ui.Para(stats, small, b.x, y, b.width);
            y += 4;
            float bw = (b.width - 12) / 4;
            GUI.enabled = !(h.HasInside && h.Inside.IsOwner);
            if (GUI.Button(new Rect(b.x, y, bw, 26), Loc.T("Enter"))) h.Enter();
            GUI.enabled = h.HasInside;
            if (GUI.Button(new Rect(b.x + bw + 4, y, bw, 26), Loc.T("Leave"))) h.Leave();
            GUI.enabled = h.HasInside && h.Inside.IsOwner;
            if (GUI.Button(new Rect(b.x + 2 * (bw + 4), y, bw, 26), Loc.T("Kick"))) h.Kick();
            GUI.enabled = h.HasInside && !h.Inside.IsOwner;
            if (GUI.Button(new Rect(b.x + 3 * (bw + 4), y, bw, 26), Loc.T("Like"))) h.Like();
            GUI.enabled = true;
        }

        void Visits(ChaosApp app, HideoutState h, Rect b)
        {
            float y = b.y;
            float total = 40 + (h.Friends.Count + h.Recent.Count + (showByVisits ? h.ShowVisits.Count : h.ShowLikes.Count)) * 24 + 90;
            scrollTab = GUI.BeginScrollView(b, scrollTab, new Rect(0, 0, b.width - 18, total));
            float yy = 0;
            yy = VisitList(h, Loc.T("Friends, party and guild"), h.Friends, b.width - 18, yy);
            if (GUI.Toggle(new Rect(0, yy, 110, 22), !showByVisits, Loc.T("By likes"), GUI.skin.button) && showByVisits) showByVisits = false;
            if (GUI.Toggle(new Rect(114, yy, 110, 22), showByVisits, Loc.T("By visits"), GUI.skin.button) && !showByVisits) showByVisits = true;
            yy += 26;
            yy = VisitList(h, Loc.T("Showcase"), showByVisits ? h.ShowVisits : h.ShowLikes, b.width - 18, yy);
            yy = VisitList(h, Loc.T("Recent"), h.Recent, b.width - 18, yy);
            GUI.EndScrollView();
        }

        float VisitList(HideoutState h, string title, List<HideoutVisit> list, float w, float y)
        {
            GUI.Label(new Rect(0, y, w, 20), title, st); y += 22;
            foreach (var v in list)
            {
                var old = GUI.contentColor; if (v.Online) GUI.contentColor = Ui.Hex("#8cd08c");
                GUI.Label(new Rect(4, y, w - 70, 22), HideoutState.VisitLine(v), small);
                GUI.contentColor = old;
                if (GUI.Button(new Rect(w - 62, y, 60, 22), Loc.T("Visit"))) h.Visit(v.Guid);
                y += 24;
            }
            return y + 4;
        }
    }
}
