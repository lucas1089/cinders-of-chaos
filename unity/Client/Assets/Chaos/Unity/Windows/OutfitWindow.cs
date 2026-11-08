// Outfit window (Ctrl+U): the looks, addons, mounts and the four colours the server lists (0xC8, Core/Dialogs.cs OutfitWindowState); on an
// Identity.Chaos connection also the wings, auras and shaders the character owns. Ok sends the look (0xD3). Opening it asks the server (0xD2),
// which answers with the lists. The wings, auras and shaders are chosen by name: the preview draws the outfit and its colours only.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class OutfitWindow : GameWindow
    {
        enum Tab { Outfit, Mount, Wings, Aura, Shader, Colors }

        public override string Title => Loc.T("Outfit");
        public override KeyCode Hotkey => KeyCode.U;
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 230, 70, 460, 400);

        Outfit working = new Outfit();
        int seenOpens;
        bool wasOpen;
        Tab tab = Tab.Outfit;
        int colorSlot;   // 0 head, 1 body, 2 legs, 3 feet
        Vector2 scroll;

        public override void Reset() { seenOpens = 0; wasOpen = false; Open = false; scroll = Vector2.zero; }

        public override void Tick(ChaosApp app)
        {
            var s = app.Session;
            if (s == null) return;
            var st = s.Outfits;
            if (st.Opens != seenOpens)
            {
                // the server sent the window (our request, or a script)
                seenOpens = st.Opens;
                working = OutfitWindowState.Copy(st.Current);
                Open = true;
                wasOpen = true;
                if (tab == Tab.Wings && !st.HasExtras) tab = Tab.Outfit;
                return;
            }
            if (Open && !wasOpen) s.RequestOutfits();   // opened by the hotkey or the toolbar: ask
            wasOpen = Open;
        }

        static Color Hex(int index)
        {
            OutfitColors.Rgb(index, out byte r, out byte g, out byte b);
            return new Color32(r, g, b, 255);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var s = app.Session;
            if (s == null) return;
            var st = s.Outfits;
            if (st.Opens == 0) { GUI.Label(new Rect(inner.x + 6, inner.y + 6, inner.width - 12, 40), Loc.T("Asking the server..."), app.SmallStyle); return; }

            // preview and addons
            var pic = new Rect(inner.x + 4, inner.y + 4, 120, 120);
            ChaosApp.Fill(pic, new Color(0.11f, 0.09f, 0.12f, 1f));
            app.DrawOutfit(new Rect(pic.x + 8, pic.y + 8, pic.width - 16, pic.height - 16), working);
            int allowed = st.AddonsOf(working.LookType);
            for (int bit = 0; bit < 2; bit++)
            {
                var r = new Rect(pic.x, pic.yMax + 6 + bit * 24, pic.width, 22);
                bool has = (working.Addons & (1 << bit)) != 0;
                bool can = (allowed & (1 << bit)) != 0;
                GUI.enabled = can;
                bool now = GUI.Toggle(r, has, Loc.T("Addon {0}", bit + 1));
                GUI.enabled = true;
                if (now != has) working.Addons = now ? working.Addons | (1 << bit) : working.Addons & ~(1 << bit);
            }
            string wearing = Wearing(st);
            GUI.Label(new Rect(pic.x, pic.yMax + 56, pic.width + 12, 60), wearing, app.SmallStyle);

            // tabs
            var tabs = new List<Tab> { Tab.Outfit, Tab.Mount };
            if (st.HasExtras) { tabs.Add(Tab.Wings); tabs.Add(Tab.Aura); tabs.Add(Tab.Shader); }
            tabs.Add(Tab.Colors);
            float tx = inner.x + 132, tw = (inner.width - 136) / tabs.Count;
            for (int i = 0; i < tabs.Count; i++)
                if (GUI.Toggle(new Rect(tx + i * tw, inner.y + 2, tw - 2, 24), tab == tabs[i], TabLabel(tabs[i]), GUI.skin.button) && tab != tabs[i]) { tab = tabs[i]; scroll = Vector2.zero; }

            var list = new Rect(tx, inner.y + 30, inner.width - 136, inner.height - 76);
            ChaosApp.Fill(list, new Color(1f, 1f, 1f, 0.04f));
            if (tab == Tab.Colors) ColorsPanel(app, list);
            else ListPanel(app, st, list);

            // buttons
            float by = inner.yMax - 36;
            if (GUI.Button(new Rect(inner.x + inner.width - 200, by, 96, 30), Loc.T("Ok"))) { s.SetOutfit(working); Open = false; wasOpen = false; }
            if (GUI.Button(new Rect(inner.x + inner.width - 100, by, 96, 30), Loc.T("Cancel"))) { st.Close(); Open = false; wasOpen = false; }
        }

        static string TabLabel(Tab t)
        {
            switch (t)
            {
                case Tab.Outfit: return Loc.T("Outfit");
                case Tab.Mount: return Loc.T("Mount");
                case Tab.Wings: return Loc.T("Wings");
                case Tab.Aura: return Loc.T("Aura");
                case Tab.Shader: return Loc.T("Shader");
                default: return Loc.T("Colors");
            }
        }

        string Wearing(OutfitWindowState st)
        {
            var parts = new List<string>();
            var o = st.FindOutfit(working.LookType);
            if (o != null) parts.Add(o.Name);
            foreach (var m in st.Mounts) if (m.Id == working.Mount) parts.Add(m.Name);
            foreach (var w in st.Wings) if (w.Id == working.Wings && working.Wings != 0) parts.Add(w.Name);
            foreach (var a in st.Auras) if (a.Id == working.Aura && working.Aura != 0) parts.Add(a.Name);
            if (!string.IsNullOrEmpty(working.Shader)) parts.Add(working.Shader);
            return string.Join(", ", parts);
        }

        static string KindOf(Tab t)
        {
            switch (t) { case Tab.Outfit: return "outfit"; case Tab.Mount: return "mount"; case Tab.Wings: return "wings"; case Tab.Aura: return "aura"; default: return "shader"; }
        }

        static bool OnlyMine(string kind) { try { return PlayerPrefs.GetInt(WardrobeView.PrefsKey(kind), 0) == 1; } catch { return false; } }
        static void SetOnlyMine(string kind, bool on) { try { PlayerPrefs.SetInt(WardrobeView.PrefsKey(kind), on ? 1 : 0); } catch { } }

        // the stock list of the server plus the wardrobe's locked entries (game_unlocks)
        static List<WardrobeRow> Display(ChaosApp app, OutfitWindowState st, string kind, bool onlyMine)
        {
            var stock = new List<KeyValuePair<int, string>>();
            switch (kind)
            {
                case "outfit": foreach (var o in st.Outfits) stock.Add(new KeyValuePair<int, string>(o.LookType, o.Name)); break;
                case "mount": foreach (var m in st.Mounts) stock.Add(new KeyValuePair<int, string>(m.Id, m.Name)); break;
                case "wings": foreach (var m in st.Wings) stock.Add(new KeyValuePair<int, string>(m.Id, m.Name)); break;
                case "aura": foreach (var m in st.Auras) stock.Add(new KeyValuePair<int, string>(m.Id, m.Name)); break;
                default: foreach (var m in st.Shaders) stock.Add(new KeyValuePair<int, string>(0, m.Name)); break;
            }
            List<WardrobeEntry> cat = null;
            app.Session?.Cosmetics?.Wardrobe?.TryGetValue(kind, out cat);
            return WardrobeView.Display(kind, stock, cat, onlyMine);
        }

        void ListPanel(ChaosApp app, OutfitWindowState st, Rect list)
        {
            // rows: name, selected, pick (null: locked), outfit to draw, tooltip
            var rows = new List<(string name, bool on, System.Action pick, Outfit look, string tip, bool locked)>();
            string kind = KindOf(tab);
            bool onlyMine = OnlyMine(kind);
            var shown = Display(app, st, kind, onlyMine);
            WardrobeView.Count(shown, out int have, out int all);
            switch (tab)
            {
                case Tab.Mount: rows.Add((Loc.T("None"), working.Mount == 0, () => working.Mount = 0, null, null, false)); break;
                case Tab.Wings: rows.Add((Loc.T("None"), working.Wings == 0, () => working.Wings = 0, null, null, false)); break;
                case Tab.Aura: rows.Add((Loc.T("None"), working.Aura == 0, () => working.Aura = 0, null, null, false)); break;
                case Tab.Shader: rows.Add((Loc.T("None"), string.IsNullOrEmpty(working.Shader), () => working.Shader = "", null, null, false)); break;
            }
            foreach (var w in shown)
            {
                var c = w;
                string tip = c.Tip;
                System.Action none = null;
                switch (tab)
                {
                    case Tab.Outfit:
                        rows.Add((c.Name, working.LookType == c.Id && !c.Locked, c.Locked ? none : () => working = st.WithLook(working, c.Id),
                            new Outfit(c.Id, working.Head, working.Body, working.Legs, working.Feet, 0), tip, c.Locked));
                        break;
                    case Tab.Mount:
                        rows.Add((c.Name, working.Mount == c.Id && !c.Locked, c.Locked ? none : () => working.Mount = c.Id, new Outfit(c.Id, 0, 0, 0, 0), tip, c.Locked));
                        break;
                    case Tab.Wings:
                        rows.Add((c.Name, working.Wings == c.Id && !c.Locked, c.Locked ? none : () => working.Wings = c.Id, null, tip, c.Locked));
                        break;
                    case Tab.Aura:
                        rows.Add((c.Name, working.Aura == c.Id && !c.Locked, c.Locked ? none : () => working.Aura = c.Id, null, tip, c.Locked));
                        break;
                    default:
                        rows.Add((c.Name, working.Shader == c.Name && !c.Locked, c.Locked ? none : () => working.Shader = c.Name, null, tip, c.Locked));
                        break;
                }
            }
            // "Only what I own" and the count of the list (the locked rows of the catalogue come after the owned ones)
            var head = new Rect(list.x + 4, list.y + 2, list.width - 8, 20);
            bool om = GUI.Toggle(new Rect(head.x, head.y, head.width - 70, 20), onlyMine, Loc.T("Only what I own"));
            if (om != onlyMine) SetOnlyMine(kind, om);
            GUI.Label(new Rect(head.xMax - 66, head.y, 66, 20), have + " / " + all, app.SmallStyle);
            var view = new Rect(list.x, list.y + 24, list.width, list.height - 24);
            const float RowH = 38f;
            scroll = GUI.BeginScrollView(view, scroll, new Rect(0, 0, view.width - 18, Mathf.Max(view.height, rows.Count * RowH)));
            var oldColor = GUI.color;
            for (int i = 0; i < rows.Count; i++)
            {
                var r = new Rect(0, i * RowH, view.width - 18, RowH - 2);
                ChaosApp.Fill(r, rows[i].on ? new Color(0.6f, 0.45f, 0.12f, 0.4f) : new Color(1f, 1f, 1f, 0.05f));
                if (rows[i].locked) GUI.color = new Color(oldColor.r, oldColor.g, oldColor.b, oldColor.a * UnlocksCore.LockedOpacity);
                float x = 4;
                if (rows[i].look != null) { app.DrawOutfit(new Rect(r.x + 2, r.y + 1, RowH - 4, RowH - 4), rows[i].look); x = RowH + 2; }
                GUI.Label(new Rect(r.x + x, r.y + 8, r.width - x, 22), rows[i].name, app.SmallStyle);
                GUI.color = oldColor;
                if (rows[i].tip != null && r.Contains(Event.current.mousePosition)) app.SetTip(rows[i].tip);
                if (Event.current.type == EventType.MouseDown && Event.current.button == 0 && r.Contains(Event.current.mousePosition))
                {
                    if (rows[i].pick != null) rows[i].pick();
                    Event.current.Use();
                }
            }
            GUI.EndScrollView();
        }

        void ColorsPanel(ChaosApp app, Rect list)
        {
            string[] names = { Loc.T("Head"), Loc.T("Primary"), Loc.T("Secondary"), Loc.T("Detail") };
            float bw = (list.width - 8) / 4;
            for (int i = 0; i < 4; i++)
                if (GUI.Toggle(new Rect(list.x + 4 + i * bw, list.y + 4, bw - 2, 24), colorSlot == i, names[i], GUI.skin.button)) colorSlot = i;
            const float Cell = 14f;
            float gx = list.x + 6, gy = list.y + 38;
            int cur = colorSlot == 0 ? working.Head : colorSlot == 1 ? working.Body : colorSlot == 2 ? working.Legs : working.Feet;
            for (int row = 0; row < 7; row++)
                for (int col = 0; col < 19; col++)
                {
                    int idx = row * 19 + col;
                    var r = new Rect(gx + col * (Cell + 1), gy + row * (Cell + 1), Cell, Cell);
                    ChaosApp.Fill(r, Hex(idx));
                    if (idx == cur) { ChaosApp.Fill(new Rect(r.x - 1, r.y - 1, Cell + 2, 1), Color.white); ChaosApp.Fill(new Rect(r.x - 1, r.yMax, Cell + 2, 1), Color.white); ChaosApp.Fill(new Rect(r.x - 1, r.y, 1, Cell), Color.white); ChaosApp.Fill(new Rect(r.xMax, r.y, 1, Cell), Color.white); }
                    if (Event.current.type == EventType.MouseDown && Event.current.button == 0 && r.Contains(Event.current.mousePosition))
                    {
                        if (colorSlot == 0) working.Head = idx; else if (colorSlot == 1) working.Body = idx; else if (colorSlot == 2) working.Legs = idx; else working.Feet = idx;
                        Event.current.Use();
                    }
                }
        }
    }
}
