// Customise Character (client game_outfitextras): the large look preview with a checkbox per layer, the Equipped now strip, the categories, a search box and the card grid of one category
// (a click picks, a card under the pointer is previewed), Apply. Phase 8 track B built the cosmetic rows; phase 9 track E adds the look categories (outfit, mount, wings, aura and shader from
// the outfit window's packet and the wardrobe, as picture cards laid out like the main client's list cards), the colour palette with its four tabs and the addon boxes, and the effect stage
// of the preview (a spell skin or kill effect under the pointer plays on it). Apply sends the look through the same 0xD3 packet as the Outfit window and the cosmetics through the panel.
// The rules are Core/Phase9E.cs (ExtrasLook, LookCards), Core/Phase8B.cs (ExtrasView) and OutfitExtrasPanel.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class OutfitExtrasWindow : SocialWindow
    {
        public override string Title => Loc.T("Customise Character");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.OutfitExtras;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 330), 50, Mathf.Min(660, w - 16), Mathf.Min(560, h - 60));

        string category = "outfit", search = "", colorTab = "head";
        int facing = LookPreview.South;
        bool showMount, showWings, showAura, showShader, compare;
        Vector2 cardScroll;
        Outfit working;
        int seenOpens;
        bool wasOpen;
        readonly StagePlay play = new StagePlay();

        public override void Reset()
        {
            base.Reset();
            category = "outfit"; search = ""; colorTab = "head"; facing = LookPreview.South; cardScroll = Vector2.zero;
            working = null; seenOpens = 0; wasOpen = false; compare = false; play.Clear();
        }

        /// <summary>The outfit window's packet: ask for it when the window opens, and start from the look it answers with. While this window is open the Outfit window stays closed (it opens on the same packet).</summary>
        public override void Tick(ChaosApp app)
        {
            base.Tick(app);
            var s = app.Session;
            if (s == null) return;
            var st = s.Outfits;
            if (st.Opens != seenOpens)
            {
                seenOpens = st.Opens;
                working = OutfitWindowState.Copy(st.Current);
                showMount = working.Mount > 0; showWings = working.Wings > 0; showAura = working.Aura > 0; showShader = !string.IsNullOrEmpty(working.Shader);
            }
            if (Open && !wasOpen) s.RequestOutfits();
            wasOpen = Open;
        }

        static int TabLines(string[] labels, float width, float minWidth)
        {
            float x = 0; int lines = 1;
            foreach (string l in labels)
            {
                float w = Mathf.Max(minWidth, 14f + l.Length * 7f);
                if (x + w > width) { x = 0; lines++; }
                x += w + 3;
            }
            return lines;
        }

        static Color Hex(int index)
        {
            OutfitColors.Rgb(index, out byte r, out byte g, out byte b);
            return new Color32(r, g, b, 255);
        }

        static bool OnlyMine(string kind) { try { return PlayerPrefs.GetInt(WardrobeView.PrefsKey(kind), 0) == 1; } catch { return false; } }
        static void SetOnlyMine(string kind, bool on) { try { PlayerPrefs.SetInt(WardrobeView.PrefsKey(kind), on ? 1 : 0); } catch { } }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var p = Panel(app.Session) as OutfitExtrasPanel;
            var s = app.Session;
            if (p == null || s == null) return;
            var st = s.Outfits;
            var rows = p.Rows();
            var small = new GUIStyle(app.SmallStyle) { fontSize = 12, wordWrap = true };
            foreach (var row in rows)
                if (!p.Form.ContainsKey("x_" + row.Key)) p.Form["x_" + row.Key] = System.Math.Max(0, row.Options.FindIndex(o => o.Value == row.Current)).ToString();
            System.Func<string, int> chosen = k => p.Form.ContainsKey("x_" + k) ? p.Index("x_" + k) : -1;
            bool haveLook = st.Opens > 0 && working != null;
            var keys = new List<string>();
            foreach (var r in rows) keys.Add(r.Key);
            var cats = ExtrasLook.Categories(st.HasExtras, keys);
            category = ExtrasLook.Known(category, cats);
            var cur = rows.Find(r => r.Key == category);
            bool lookCat = ExtrasLook.IsLook(category), colorCat = category == ExtrasLook.ColorsKey;
            var e = Event.current;

            // left: the large look preview, the layer boxes and the Equipped now strip
            float lw = 196;
            var stage = new Rect(inner.x + 6, inner.y + 4, lw - 8, lw - 8);
            ChaosApp.Fill(stage, new Color(0.07f, 0.06f, 0.08f, 1f));
            var me = app.World?.Player;

            // right: the categories, the search box, the cards (laid out first so a hover is known when the preview is drawn)
            float rx = inner.x + lw + 6, rw = inner.xMax - rx - 6;
            float cy = inner.y + 4;
            var labels = new string[cats.Count];
            for (int i = 0; i < cats.Count; i++)
            {
                var row = rows.Find(r => r.Key == cats[i]);
                labels[i] = row != null ? row.Label : ExtrasLook.Label(cats[i]);
            }
            int ci = cats.IndexOf(category);
            int ni = CU.Tabs(new Rect(rx, cy, rw, 24), labels, ci, 60);
            if (ni != ci) { category = cats[ni]; cur = rows.Find(r => r.Key == category); lookCat = ExtrasLook.IsLook(category); colorCat = category == ExtrasLook.ColorsKey; cardScroll = Vector2.zero; }
            cy += 26 * TabLines(labels, rw, 60) + 4;
            if (!colorCat)
            {
                GUI.Label(new Rect(rx, cy + 2, 52, 22), Loc.T("Search"), small);
                var sbox = new Rect(rx + 54, cy, rw - 54 - 28, 22);
                string ns = GUI.TextField(sbox, search);
                if (ns != search) { search = ns; cardScroll = Vector2.zero; }
                if (GUI.GetNameOfFocusedControl() == "" && GUI.changed) app.MarkTextEditing();
                if (GUI.Button(new Rect(rx + rw - 24, cy, 24, 22), "x")) { search = ""; cardScroll = Vector2.zero; }
                if (sbox.Contains(e.mousePosition)) app.MarkTextEditing();
                cy += 28;
            }
            LookCard hoverCard = null;
            int hoverIdx = -1;
            var view = new Rect(rx, cy, rw, inner.yMax - cy - 74);
            if (lookCat)
            {
                if (!haveLook) GUI.Label(new Rect(rx + 4, cy, rw - 8, 40), Loc.T("Asking the server..."), small);
                else
                {
                    List<WardrobeEntry> cat = null;
                    s.Cosmetics?.Wardrobe?.TryGetValue(category, out cat);
                    bool onlyMine = OnlyMine(category);
                    var cards = ExtrasLook.Cards(category, st, cat, onlyMine, search);
                    ExtrasLook.Count(ExtrasLook.Cards(category, st, cat, onlyMine, ""), out int have, out int all);
                    bool om = GUI.Toggle(new Rect(rx, cy - 2, rw - 70, 20), onlyMine, Loc.T("Only what I own"));
                    if (om != onlyMine) SetOnlyMine(category, om);
                    GUI.Label(new Rect(rx + rw - 66, cy - 2, 66, 20), have + " / " + all, app.SmallStyle);
                    view = new Rect(rx, cy + 22, rw, inner.yMax - cy - 22 - 74);
                    hoverCard = LookGrid(app, view, st, cards);
                    if (!view.Contains(e.mousePosition)) hoverCard = null;
                }
            }
            else if (colorCat)
            {
                if (!haveLook) GUI.Label(new Rect(rx + 4, cy, rw - 8, 40), Loc.T("Asking the server..."), small);
                else ColorsPanel(app, new Rect(rx, cy, rw, view.height + 28), st);
            }
            else if (cur != null)
            {
                var shown = ExtrasView.Filter(cur, search);
                int per = Mathf.Max(1, Mathf.FloorToInt((rw - 18) / 128f));
                float cw = (rw - 18 - (per - 1) * 4) / per;
                cardScroll = GUI.BeginScrollView(view, cardScroll, new Rect(0, 0, rw - 18, Mathf.Max(view.height, Mathf.CeilToInt(shown.Count / (float)per) * 46f)));
                int pick = chosen(cur.Key);
                for (int n = 0; n < shown.Count; n++)
                {
                    int oi = shown[n];
                    var r = new Rect((n % per) * (cw + 4), (n / per) * 46f, cw, 42);
                    bool on = oi == pick;
                    ChaosApp.Fill(r, on ? new Color(0.35f, 0.25f, 0.1f, 1f) : new Color(1f, 1f, 1f, 0.05f));
                    if (on) ItemSlots.Frame(r, "#e8b84a");
                    var tex = cur.Options[oi].Row != null ? app.ArtTexture(CosmeticIcons.Path(cur.Options[oi].Row) ?? "") : null;
                    float tx = r.x + 4;
                    if (tex != null) { GUI.DrawTexture(new Rect(r.x + 4, r.y + 5, 32, 32), tex, ScaleMode.ScaleToFit, true); tx = r.x + 40; }
                    GUI.Label(new Rect(tx, r.y + 2, r.xMax - tx - 2, 38), cur.Options[oi].Text, small);
                    var inScroll = Event.current.mousePosition;   // inside the scroll view the position is in content space
                    if (r.Contains(inScroll)) hoverIdx = oi;
                    if (e.type == EventType.MouseDown && e.button == 0 && r.Contains(inScroll)) { p.Form["x_" + cur.Key] = oi.ToString(); e.Use(); }
                }
                GUI.EndScrollView();
                if (!view.Contains(e.mousePosition)) hoverIdx = -1;
                if (cur.Locked > 0) GUI.Label(new Rect(rx, view.yMax + 2, rw, 20), Loc.T("{0} more not unlocked yet. See Character > Cosmetics and the Store.", cur.Locked), small);
            }

            // the large preview: the chosen options, the hovered card in place of its row's
            var opt = ExtrasView.Bundle(rows, chosen, cur != null && hoverIdx >= 0 ? cur.Key : null, hoverIdx);
            if (me != null)
            {
                var look = ExtrasView.Layers(haveLook ? working : me.Outfit, showMount, showWings, showAura, showShader);
                if (haveLook && hoverCard != null && lookCat)
                    look = ExtrasView.Layers(ExtrasLook.Apply(working, st, category, hoverCard), showMount || category == "mount", showWings || category == "wings", showAura || category == "aura", showShader || category == "shader");
                var fx = PreviewStage.EffectsOf(opt);
                if (fx == null || !app.DrawEffectStage(new Rect(stage.x + 2, stage.y + 2, stage.width - 4, stage.height - 4), fx, opt, look, me.Name, play, compare))
                {
                    if (fx == null) play.Clear();
                    app.DrawPreviewUnder(opt, stage);
                    app.DrawOutfitFx(new Rect(stage.x + 12, stage.y + 12, stage.width - 24, stage.height - 24), look, false, (Dir)facing);
                    app.DrawPreviewOver(opt, stage, me.Name);
                }
            }
            float y = stage.yMax + 4;
            if (GUI.Button(new Rect(inner.x + 6, y, 30, 22), "<")) facing = LookPreview.Turn(facing, -1);
            if (GUI.Button(new Rect(inner.x + 40, y, 30, 22), ">")) facing = LookPreview.Turn(facing, 1);
            if (play.HasStock && PreviewStage.EffectsOf(opt) != null) compare = GUI.Toggle(new Rect(inner.x + 76, y, lw - 80, 22), compare, Loc.T("Compare with default"));
            y += 26;
            showMount = GUI.Toggle(new Rect(inner.x + 6, y, 92, 20), showMount, Loc.T("Mount"));
            showWings = GUI.Toggle(new Rect(inner.x + 100, y, 92, 20), showWings, Loc.T("Wings"));
            y += 20;
            showAura = GUI.Toggle(new Rect(inner.x + 6, y, 92, 20), showAura, Loc.T("Aura"));
            showShader = GUI.Toggle(new Rect(inner.x + 100, y, 92, 20), showShader, Loc.T("Shader"));
            y += 24;
            // Equipped now: the look categories, then one line per cosmetic row with the chosen option; a click shows its category
            GUI.Label(new Rect(inner.x + 6, y, lw, 18), Loc.T("Equipped now"), app.SmallStyle);
            y += 18;
            var line = new GUIStyle(small) { fontSize = 11, wordWrap = false, clipping = TextClipping.Clip };
            var strip = new List<KeyValuePair<string, string>>();
            if (haveLook) foreach (string k in ExtrasLook.LookKeys) { if (!ExtrasLook.NeedsExtras(k) || st.HasExtras) strip.Add(new KeyValuePair<string, string>(k, ExtrasLook.Equipped(k, working, st))); }
            foreach (var row in rows) strip.Add(new KeyValuePair<string, string>(row.Key, ExtrasView.Equipped(row, chosen(row.Key))));
            foreach (var item in strip)
            {
                var r = new Rect(inner.x + 6, y, lw - 8, 16);
                if (item.Key == category) ChaosApp.Fill(r, new Color(1f, 1f, 1f, 0.06f));
                GUI.Label(r, item.Value, line);
                if (e.type == EventType.MouseDown && e.button == 0 && r.Contains(e.mousePosition)) { category = item.Key; cardScroll = Vector2.zero; e.Use(); }
                y += 16;
                if (y > inner.yMax - 18) break;
            }

            // bottom right: Apply and the status
            if (p.Status.Length > 0)
            {
                var old = GUI.contentColor; GUI.contentColor = ToneColor(p.StatusTone);
                GUI.Label(new Rect(rx, inner.yMax - 44, rw - 110, 40), p.Status, small);
                GUI.contentColor = old;
            }
            if (GUI.Button(new Rect(inner.xMax - 108, inner.yMax - 30, 100, 26), Loc.T("Apply")))
            {
                if (haveLook)
                {
                    var send = ExtrasLook.ToSend(working, showMount, showWings, showAura, showShader);
                    if (ExtrasLook.Changed(send, st.Current)) { s.SetOutfit(send); st.Current = OutfitWindowState.Copy(send); }
                }
                p.Apply();
            }
        }

        /// <summary>The picture cards of a look category: each card is a picture part (the look facing south, at the main client's list card scale) over its name. Returns the card under the pointer.</summary>
        LookCard LookGrid(ChaosApp app, Rect view, OutfitWindowState st, List<LookCard> cards)
        {
            const float CardH = 92f, PicH = 62f, Gap = 4f;
            var small = new GUIStyle(app.SmallStyle) { fontSize = 11, wordWrap = true, alignment = TextAnchor.UpperCenter };
            int per = Mathf.Max(1, Mathf.FloorToInt((view.width - 18) / (92f + Gap)));
            float cw = (view.width - 18 - (per - 1) * Gap) / per;
            LookCard hover = null;
            var e = Event.current;
            cardScroll = GUI.BeginScrollView(view, cardScroll, new Rect(0, 0, view.width - 18, Mathf.Max(view.height, Mathf.CeilToInt(cards.Count / (float)per) * (CardH + Gap))));
            var oldColor = GUI.color;
            for (int n = 0; n < cards.Count; n++)
            {
                var c = cards[n];
                var r = new Rect((n % per) * (cw + Gap), (n / per) * (CardH + Gap), cw, CardH);
                bool on = ExtrasLook.IsCurrent(working, category, c);
                ChaosApp.Fill(r, on ? new Color(0.35f, 0.25f, 0.1f, 1f) : new Color(1f, 1f, 1f, 0.05f));
                if (on) ItemSlots.Frame(r, "#e8b84a");
                if (c.Locked) GUI.color = new Color(oldColor.r, oldColor.g, oldColor.b, oldColor.a * UnlocksCore.LockedOpacity);
                var pic = new Rect(r.x + 2, r.y + 2, r.width - 4, PicH);
                app.DrawLookCard(pic, ExtrasLook.CardLook(working, category, c));
                GUI.Label(new Rect(r.x + 2, pic.yMax + 1, r.width - 4, CardH - PicH - 3), c.Name, small);
                GUI.color = oldColor;
                var m = Event.current.mousePosition;   // content space inside the scroll view
                if (r.Contains(m))
                {
                    hover = c;
                    if (c.Tip != null) app.SetTip(c.Tip);
                    if (e.type == EventType.MouseDown && e.button == 0)
                    {
                        if (!c.Locked)
                        {
                            working = ExtrasLook.Apply(working, st, category, c);
                            // a pick turns its layer on, "none" turns it off
                            if (category == "mount") showMount = !c.None; else if (category == "wings") showWings = !c.None;
                            else if (category == "aura") showAura = !c.None; else if (category == "shader") showShader = !c.None;
                        }
                        e.Use();
                    }
                }
            }
            GUI.EndScrollView();
            return hover;
        }

        /// <summary>The colour palette: the four tabs (head, primary, secondary, detail), the 7 x 19 colours and the two addon boxes.</summary>
        void ColorsPanel(ChaosApp app, Rect area, OutfitWindowState st)
        {
            var e = Event.current;
            float bw = (area.width - 8) / ExtrasLook.ColorTabs.Length;
            for (int i = 0; i < ExtrasLook.ColorTabs.Length; i++)
                if (GUI.Toggle(new Rect(area.x + 4 + i * bw, area.y, bw - 2, 24), colorTab == ExtrasLook.ColorTabs[i], ExtrasLook.TabLabel(ExtrasLook.ColorTabs[i]), GUI.skin.button)) colorTab = ExtrasLook.ColorTabs[i];
            float cell = Mathf.Clamp(Mathf.Floor((area.width - 14f) / ExtrasLook.ColorColumns) - 1f, 8f, 17f);
            float gx = area.x + 6, gy = area.y + 32;
            int curIdx = ExtrasLook.ColorOf(working, colorTab);
            for (int idx = 0; idx < ExtrasLook.ColorCount; idx++)
            {
                int row = idx / ExtrasLook.ColorColumns, col = idx % ExtrasLook.ColorColumns;
                var r = new Rect(gx + col * (cell + 1), gy + row * (cell + 1), cell, cell);
                ChaosApp.Fill(r, Hex(idx));
                if (idx == curIdx)
                {
                    ChaosApp.Fill(new Rect(r.x - 1, r.y - 1, cell + 2, 1), Color.white); ChaosApp.Fill(new Rect(r.x - 1, r.yMax, cell + 2, 1), Color.white);
                    ChaosApp.Fill(new Rect(r.x - 1, r.y, 1, cell), Color.white); ChaosApp.Fill(new Rect(r.xMax, r.y, 1, cell), Color.white);
                }
            }
            if (e.type == EventType.MouseDown && e.button == 0)
            {
                int hit = ExtrasLook.CellAt(e.mousePosition.x - gx, e.mousePosition.y - gy, cell, 1f);
                if (hit >= 0) { working = ExtrasLook.SetColor(working, colorTab, hit); e.Use(); }
            }
            float y = gy + ExtrasLook.ColorRows * (cell + 1) + 10;
            int allowed = st.AddonsOf(working.LookType);
            for (int bit = 0; bit < 2; bit++)
            {
                bool can = (allowed & (1 << bit)) != 0;
                bool has = (working.Addons & (1 << bit)) != 0;
                GUI.enabled = can;
                bool now = GUI.Toggle(new Rect(area.x + 6 + bit * 120, y, 116, 22), has, Loc.T("Addon {0}", bit + 1));
                GUI.enabled = true;
                if (now != has) working = ExtrasLook.SetAddon(working, st, bit, now);
            }
        }
    }
}
