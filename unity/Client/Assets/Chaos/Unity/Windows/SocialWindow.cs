// The window of a SocialPanel (Core/Social.cs): tabs, two header lines, a scrolling list of rows (section, text, row with buttons, input, combo, bar) and a status
// line. One class per window below: market, guild, guild wars, party finder, group queue (and its ready check box), inspect, leaderboards, factions, Conquest vendor.
// None has a Ctrl hotkey: the top menu opens them (TopMenu entries, level unlocks of opcode 115) or the server does (NPCs, a guild hall stone).
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public abstract class SocialWindow : GameWindow
    {
        Vector2 scroll;
        bool mouseInView;
        bool lastPanelVisible, lastOpen;
        GUIStyle wrap, bold, right;
        protected static readonly Dictionary<string, Color> Tones = new Dictionary<string, Color>
        {
            { "text", new Color(0.84f, 0.79f, 0.68f) }, { "dim", new Color(0.55f, 0.5f, 0.44f) }, { "good", new Color(0.56f, 0.82f, 0.42f) }, { "warn", new Color(0.96f, 0.81f, 0.45f) },
            { "bad", new Color(0.88f, 0.35f, 0.25f) }, { "gold", new Color(0.91f, 0.72f, 0.29f) }, { "coins", new Color(0.5f, 0.82f, 1f) }, { "unique", new Color(0.88f, 0.48f, 0.14f) },
            { "locked", new Color(0.42f, 0.38f, 0.34f) },
        };

        /// <summary>The panel of this window (null before the session exists).</summary>
        protected abstract SocialPanel Panel(GameSession s);

        public override void Reset() { lastPanelVisible = lastOpen = false; Open = false; scroll = Vector2.zero; }

        public static Color ToneColor(string tone)
        {
            if (string.IsNullOrEmpty(tone)) return Tones["text"];
            if (Tones.TryGetValue(tone, out var c)) return c;
            return ColorUtility.TryParseHtmlString(tone, out c) ? c : Tones["text"];
        }

        /// <summary>A change made by the server (the panel became visible) or by the player (Open toggled): whichever happened since the last pass.</summary>
        public override void Tick(ChaosApp app)
        {
            var p = Panel(app.Session);
            if (p == null) return;
            if (p.Visible != lastPanelVisible) Open = p.Visible;
            else if (Open != lastOpen) { if (Open) p.Show(); else p.Hide(); }
            lastPanelVisible = p.Visible;
            lastOpen = Open;
        }

        /// <summary>Drawn over the header, to the right (an outfit): returns nothing; the rows start below the header.</summary>
        protected virtual void DrawExtra(ChaosApp app, SocialPanel p, Rect header) { }

        void Styles(ChaosApp app)
        {
            if (wrap != null) return;
            wrap = new GUIStyle(app.SmallStyle) { wordWrap = true, fontSize = 12 };
            bold = new GUIStyle(app.SmallStyle) { fontSize = 14, fontStyle = FontStyle.Bold };
            right = new GUIStyle(app.SmallStyle) { alignment = TextAnchor.MiddleRight, fontSize = 12 };
        }

        static float ButtonWidth(GUIStyle s, string text) => Mathf.Max(56f, s.CalcSize(new GUIContent(text)).x + 18f);

        protected override void Body(ChaosApp app, Rect inner)
        {
            var p = Panel(app.Session);
            if (p == null) return;
            Styles(app);
            float x = inner.x + 4, w = inner.width - 8, y = inner.y;
            if (p.Header1.Length > 0) { GUI.Label(new Rect(x, y, w, 22), p.Header1, bold); y += 22; }
            if (p.Header2.Length > 0) { float hh = wrap.CalcHeight(new GUIContent(p.Header2), w); GUI.Label(new Rect(x, y, w, hh), p.Header2, wrap); y += hh + 2; }
            DrawExtra(app, p, new Rect(x, inner.y, w, y - inner.y));
            if (p.Tabs.Count > 1)
            {
                int n = p.Tabs.Count, perRow = Mathf.Max(1, Mathf.Min(n, Mathf.FloorToInt(w / 92f)));
                float tw = (w - (perRow - 1) * 3) / perRow;
                for (int i = 0; i < n; i++)
                {
                    var r = new Rect(x + (i % perRow) * (tw + 3), y + (i / perRow) * 26, tw, 24);
                    bool on = p.Tab == p.Tabs[i].Key;
                    if (GUI.Toggle(r, on, Loc.T(p.Tabs[i].Value), GUI.skin.button) && !on) { p.SelectTab(p.Tabs[i].Key); scroll = Vector2.zero; }
                }
                y += ((n - 1) / perRow + 1) * 26 + 2;
            }
            float statusH = p.Status.Length > 0 ? Mathf.Max(20, wrap.CalcHeight(new GUIContent(p.Status), w)) + 2 : 0;
            var view = new Rect(x, y, w, inner.yMax - y - statusH);
            DrawRows(app, p, view);
            if (statusH > 0)
            {
                var old = GUI.contentColor;
                GUI.contentColor = ToneColor(p.StatusTone);
                GUI.Label(new Rect(x, inner.yMax - statusH, w, statusH), p.Status, wrap);
                GUI.contentColor = old;
            }
        }

        float RowHeight(SocialRow r, float w)
        {
            switch (r.Kind)
            {
                case RowKind.Section: return 24;
                case RowKind.Text: return Mathf.Max(18, wrap.CalcHeight(new GUIContent(r.Text), w)) + 2;
                case RowKind.Bar: return 20;
                case RowKind.Input: case RowKind.Combo: return 26;
                default: return (r.ItemId > 0 ? 32 : 26) + (r.Sub.Length > 0 ? 16 : 0);
            }
        }

        void DrawRows(ChaosApp app, SocialPanel p, Rect view)
        {
            var rows = p.BuildRows();
            mouseInView = view.Contains(Event.current.mousePosition);
            float innerW = view.width - 18, total = 0;
            var heights = new float[rows.Count];
            for (int i = 0; i < rows.Count; i++) { heights[i] = RowHeight(rows[i], innerW); total += heights[i]; }
            scroll = GUI.BeginScrollView(view, scroll, new Rect(0, 0, innerW, Mathf.Max(total, view.height)));
            float y = 0;
            var e = Event.current;
            for (int i = 0; i < rows.Count; i++)
            {
                DrawRow(app, p, rows[i], new Rect(0, y, innerW, heights[i]), e, view);
                y += heights[i];
            }
            GUI.EndScrollView();
        }

        void DrawRow(ChaosApp app, SocialPanel p, SocialRow r, Rect rect, Event e, Rect view)
        {
            var old = GUI.contentColor;
            switch (r.Kind)
            {
                case RowKind.Section:
                    ChaosApp.Fill(new Rect(rect.x, rect.y + 2, rect.width, rect.height - 3), new Color(0.16f, 0.09f, 0.06f, 0.9f));
                    GUI.contentColor = ToneColor("gold");
                    GUI.Label(new Rect(rect.x + 4, rect.y + 2, rect.width - 8, rect.height - 3), r.Text, bold);
                    break;
                case RowKind.Text:
                    GUI.contentColor = ToneColor(r.Tone);
                    GUI.Label(rect, r.Text, wrap);
                    break;
                case RowKind.Bar:
                    ChaosApp.Fill(new Rect(rect.x, rect.y + 2, rect.width, 16), new Color(0.12f, 0.1f, 0.12f, 1f));
                    ChaosApp.Fill(new Rect(rect.x, rect.y + 2, rect.width * r.Percent / 100f, 16), new Color(0.54f, 0.33f, 0.06f, 1f));
                    GUI.contentColor = Color.white;
                    GUI.Label(new Rect(rect.x + 4, rect.y + 1, rect.width - 8, 18), r.Text, wrap);
                    break;
                case RowKind.Input: InputRow(app, p, r, rect); break;
                case RowKind.Combo: ComboRow(app, p, r, rect); break;
                default: PlainRow(app, r, rect, e, view); break;
            }
            GUI.contentColor = old;
        }

        void PlainRow(ChaosApp app, SocialRow r, Rect rect, Event e, Rect view)
        {
            float line = rect.height - (r.Sub.Length > 0 ? 16 : 0);
            float mid = rect.y + line / 2;
            ChaosApp.Fill(new Rect(rect.x, rect.y + 1, rect.width, rect.height - 2), new Color(1f, 1f, 1f, 0.04f));
            float x = rect.x + 2;
            if (r.ItemId > 0)
            {
                var ir = new Rect(rect.x + 2, rect.y + 1, 28, 28);
                app.DrawItem(ir, (ushort)r.ItemId, r.Count);
                if (r.Frame != null) ItemSlots.Frame(ir, r.Frame);
                x += 34;
            }
            // buttons from the right edge
            float edge = rect.xMax - 2;
            for (int i = r.Buttons.Count - 1; i >= 0; i--)
            {
                var b = r.Buttons[i];
                float bw = ButtonWidth(GUI.skin.button, b.Text);
                var br = new Rect(edge - bw, mid - 11, bw, 22);
                bool was = GUI.enabled;
                GUI.enabled = b.Enabled;
                if (GUI.Button(br, new GUIContent(b.Text, b.Tip))) b.Click();
                GUI.enabled = was;
                edge -= bw + 4;
            }
            float avail = Mathf.Max(40, edge - x);
            float rightW = r.Right.Length > 0 ? Mathf.Min(avail * 0.5f, right.CalcSize(new GUIContent(r.Right)).x + 6) : 0;
            GUI.contentColor = ToneColor(r.Tone);
            GUI.Label(new Rect(x, mid - 11, avail - rightW, 22), r.Text, app.SmallStyle);
            if (rightW > 0) GUI.Label(new Rect(edge - rightW, mid - 11, rightW, 22), r.Right, right);
            if (r.Sub.Length > 0)
            {
                GUI.contentColor = ToneColor("dim");
                GUI.Label(new Rect(x, rect.y + line - 2, rect.width - x, 16), r.Sub, app.SmallStyle);
            }
            // hover: a tooltip table (item) and the panel's request for it
            if (e.type == EventType.Repaint && mouseInView && rect.Contains(e.mousePosition))
            {
                if (r.Hover != null) r.Hover();
                if (r.ItemTip != null) app.ShowTip(r.ItemTip);
                else if (r.Tip.Length > 0) app.ShowTip(null, null, r.Tip);
            }
        }

        void InputRow(ChaosApp app, SocialPanel p, SocialRow r, Rect rect)
        {
            float labelW = Mathf.Min(rect.width * 0.38f, 200f);
            GUI.contentColor = ToneColor("text");
            GUI.Label(new Rect(rect.x + 2, rect.y + 2, labelW, 22), r.Text, app.SmallStyle);
            float edge = rect.xMax - 2;
            for (int i = r.Buttons.Count - 1; i >= 0; i--)
            {
                var b = r.Buttons[i];
                float bw = ButtonWidth(GUI.skin.button, b.Text);
                bool was = GUI.enabled;
                GUI.enabled = b.Enabled;
                if (GUI.Button(new Rect(edge - bw, rect.y + 2, bw, 22), new GUIContent(b.Text, b.Tip))) b.Click();
                GUI.enabled = was;
                edge -= bw + 4;
            }
            var fr = new Rect(rect.x + labelW + 6, rect.y + 2, Mathf.Max(40, edge - (rect.x + labelW + 6)), 22);
            string name = "soc_" + GetType().Name + "_" + r.Key;
            GUI.SetNextControlName(name);
            string cur = p.Text(r.Key);
            string next = GUI.TextField(fr, cur, 255);
            if (GUI.GetNameOfFocusedControl() == name) app.MarkTextEditing();
            if (next != cur) { p.Form[r.Key] = next; p.OnForm(r.Key); }
            if (cur.Length == 0 && next.Length == 0 && r.Hint.Length > 0 && GUI.GetNameOfFocusedControl() != name)
            {
                GUI.contentColor = new Color(1f, 1f, 1f, 0.3f);
                GUI.Label(new Rect(fr.x + 4, fr.y, fr.width - 8, 22), r.Hint, app.SmallStyle);
            }
        }

        void ComboRow(ChaosApp app, SocialPanel p, SocialRow r, Rect rect)
        {
            float labelW = Mathf.Min(rect.width * 0.38f, 200f);
            GUI.contentColor = ToneColor("text");
            GUI.Label(new Rect(rect.x + 2, rect.y + 2, labelW, 22), r.Text, app.SmallStyle);
            int n = r.Options.Count;
            int idx = n == 0 ? 0 : Mathf.Clamp(p.Index(r.Key), 0, n - 1);
            var br = new Rect(rect.x + labelW + 6, rect.y + 2, rect.width - labelW - 8, 22);
            var e = Event.current;
            if (GUI.Button(br, n == 0 ? "-" : r.Options[idx] + "   >") && n > 0)
            {
                int step = e != null && e.button == 1 ? -1 : 1;
                p.Form[r.Key] = ((idx + step + n) % n).ToString(System.Globalization.CultureInfo.InvariantCulture);
                p.OnForm(r.Key);
            }
        }
    }
}
