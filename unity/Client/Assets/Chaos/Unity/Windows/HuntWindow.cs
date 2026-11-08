// Hunt tracker (Ctrl+H), the main client's game_hunt on opcode 241: session time with pause and reset, experience and exp/h, time to the
// next level, loot, supplies, profit, damage, healing and kills, and four lists (Kills, Loot, Supplies, Chaos Drops). The server counts
// everything and pushes a state every 2 seconds while the window is open; the clock ticks here in between. Restock asks the server
// for a price first. Core: Core/Progression.cs (HuntTracker).
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class HuntWindow : GameWindow
    {
        static readonly string[] Tabs = { "Kills", "Loot", "Supplies", "Chaos Drops" };
        int tab = 1;
        Vector2 scroll;
        bool wasOpen, confirmReset;
        GUIStyle tiny, right;
        string copied = "";

        public override string Title => Loc.T("Hunt Tracker");
        public override KeyCode Hotkey => KeyCode.I;
        protected override Rect Place(float w, float h) => new Rect(8, 108, 300, 470);
        public override void Reset() { wasOpen = false; scroll = Vector2.zero; confirmReset = false; copied = ""; }

        public override void Tick(ChaosApp app)
        {
            var hunt = app.Session?.Progress?.Hunt;
            if (hunt == null) return;
            if (hunt.OpenRequested) { hunt.OpenRequested = false; Open = true; }
            if (Open && !wasOpen) hunt.Open();
            if (!Open && wasOpen) hunt.Close();
            wasOpen = Open;
        }

        static Color Hex(string hex) => ColorUtility.TryParseHtmlString(hex, out var c) ? c : Color.white;

        void Stat(ChaosApp app, string name, string value, string color, float x, float y, float w)
        {
            GUI.Label(new Rect(x, y, w * 0.45f, 18), name, tiny);
            var st = new GUIStyle(right);
            st.normal.textColor = Hex(color);
            GUI.Label(new Rect(x + w * 0.3f, y, w * 0.7f, 18), value, st);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var session = app.Session;
            var h = session?.Progress?.Hunt;
            if (h == null) return;
            if (tiny == null) { tiny = new GUIStyle(app.SmallStyle) { fontSize = 11 }; right = new GUIStyle(tiny) { alignment = TextAnchor.MiddleRight }; }
            float x = inner.x + 4, w = inner.width - 8, y = inner.y;
            if (!h.HasState) { GUI.Label(new Rect(x, y, w, 40), Loc.T("Waiting for the server..."), app.SmallStyle); return; }
            double now = session.Now;
            var big = new GUIStyle(app.SmallStyle) { fontSize = 18, fontStyle = FontStyle.Bold };
            GUI.Label(new Rect(x, y, w * 0.6f, 26), Fmt.Duration(h.Elapsed(now)), big);
            if (GUI.Button(new Rect(x + w - 150, y + 2, 70, 22), h.Paused ? Loc.T("Resume") : Loc.T("Pause"))) h.TogglePause();
            if (GUI.Button(new Rect(x + w - 76, y + 2, 76, 22), Loc.T("Reset"))) confirmReset = true;
            y += 30;
            // two columns of numbers
            string gain = "#7ccf5c", loss = "#e03a1e", plain = "#d6c9ae";
            string pfColor = h.Pf > 0 ? gain : h.Pf < 0 ? loss : plain, pfhColor = h.Pfh > 0 ? gain : h.Pfh < 0 ? loss : plain;
            float cw = w / 2 - 4;
            string[,] left =
            {
                { Loc.T("Experience"), Fmt.Short(h.Xp), plain }, { Loc.T("Next level"), h.NextLevel(), plain }, { Loc.T("Loot"), Fmt.Short(h.Lv), plain },
                { Loc.T("Supplies"), Fmt.Short(h.Sv), plain }, { Loc.T("Profit"), Fmt.Short(h.Pf), pfColor }, { Loc.T("Damage"), Fmt.Short(h.Dmg), plain }, { Loc.T("Healing"), Fmt.Short(h.Heal), plain },
            };
            string[,] rightCol =
            {
                { Loc.T("Exp/h"), Fmt.Short(h.Xph), plain }, { Loc.T("Kills"), Fmt.Short(h.Kc), plain }, { Loc.T("Loot/h"), Fmt.Short(h.Lvh), plain },
                { Loc.T("Supplies/h"), Fmt.Short(h.Svh), plain }, { Loc.T("Profit/h"), Fmt.Short(h.Pfh), pfhColor }, { Loc.T("Damage/s"), Fmt.Short(h.Dps), plain }, { Loc.T("Healing/s"), Fmt.Short(h.Hps), plain },
            };
            for (int i = 0; i < 7; i++)
            {
                Stat(app, left[i, 0], left[i, 1], left[i, 2], x, y + i * 18, cw);
                Stat(app, rightCol[i, 0], rightCol[i, 1], rightCol[i, 2], x + cw + 8, y + i * 18, cw);
            }
            y += 7 * 18 + 6;
            // tabs
            float tw = w / Tabs.Length;
            for (int i = 0; i < Tabs.Length; i++)
            {
                bool on = tab == i;
                if (GUI.Toggle(new Rect(x + i * tw, y, tw - 2, 22), on, Loc.T(Tabs[i]), GUI.skin.button) && !on) { tab = i; scroll = Vector2.zero; }
            }
            y += 26;
            float listH = inner.yMax - y - 30;
            DrawList(app, h, new Rect(x, y, w, listH));
            // bottom buttons
            float by = inner.yMax - 26;
            if (GUI.Button(new Rect(x, by, w / 2 - 2, 24), copied.Length > 0 ? copied : Loc.T("Copy summary"))) { GUIUtility.systemCopyBuffer = h.Summary(now); copied = Loc.T("Copied"); }
            if (GUI.Button(new Rect(x + w / 2 + 2, by, w / 2 - 2, 24), Loc.T("Restock"))) h.AskRestock();
            if (confirmReset) ResetBox(h, inner);
            else if (h.Quote != null) QuoteBox(h, inner);
        }

        void DrawList(ChaosApp app, HuntTracker h, Rect r)
        {
            ChaosApp.Fill(r, new Color(0f, 0f, 0f, 0.3f));
            int count = tab == 0 ? h.Kills.Count : tab == 1 ? h.Loot.Count : tab == 2 ? h.Supplies.Count : h.Drops.Count;
            const float rowH = 28f;
            scroll = GUI.BeginScrollView(r, scroll, new Rect(0, 0, r.width - 18, Mathf.Max(r.height, count * rowH)));
            float w = r.width - 22;
            if (count == 0) GUI.Label(new Rect(4, 2, w, 20), Loc.T("Nothing yet."), tiny);
            if (tab == 0)
            {
                for (int i = 0; i < h.Kills.Count; i++)
                {
                    var k = h.Kills[i];
                    GUI.Label(new Rect(4, i * rowH + 4, w * 0.6f, 20), k.Name, tiny);
                    var st = new GUIStyle(right);
                    int pct = h.Kc > 0 ? (int)(k.Count * 100.0 / h.Kc + 0.5) : 0;
                    GUI.Label(new Rect(w * 0.4f, i * rowH + 4, w * 0.6f - 4, 20), k.Count + "x  " + pct + "%", st);
                }
            }
            else
            {
                var list = tab == 1 ? h.Loot : tab == 2 ? h.Supplies : h.Drops;
                for (int i = 0; i < list.Count; i++)
                {
                    var it = list[i];
                    float y = i * rowH;
                    var icon = new Rect(2, y + 1, 26, 26);
                    app.DrawItem(icon, (ushort)it.Id, it.Count);
                    string color;
                    string label = HuntTracker.ItemLabel(it, out color);
                    var st = new GUIStyle(tiny);
                    st.normal.textColor = Hex(color);
                    GUI.Label(new Rect(32, y + 4, w - 100, 20), label, st);
                    if (tab != 3)
                    {
                        var vs = new GUIStyle(right);
                        GUI.Label(new Rect(w - 100, y + 4, 96, 20), Fmt.Short(it.Value), vs);
                    }
                }
            }
            GUI.EndScrollView();
        }

        void Modal(Rect inner, out Rect box)
        {
            ChaosApp.Fill(inner, new Color(0f, 0f, 0f, 0.6f));
            box = new Rect(inner.x + 10, inner.y + inner.height / 2 - 80, inner.width - 20, 160);
            ChaosApp.Fill(box, new Color(0.07f, 0.05f, 0.08f, 0.99f));
            ChaosApp.Fill(new Rect(box.x, box.y, box.width, 3), new Color(0.96f, 0.81f, 0.45f));
        }

        void ResetBox(HuntTracker h, Rect inner)
        {
            Modal(inner, out var box);
            var st = new GUIStyle(tiny) { wordWrap = true, alignment = TextAnchor.MiddleCenter, fontSize = 12 };
            GUI.Label(new Rect(box.x + 8, box.y + 10, box.width - 16, 90), Loc.T("Start a new hunting session from zero?"), st);
            if (GUI.Button(new Rect(box.x + 20, box.yMax - 36, box.width / 2 - 30, 26), Loc.T("Yes"))) { h.Reset(); confirmReset = false; }
            if (GUI.Button(new Rect(box.center.x + 10, box.yMax - 36, box.width / 2 - 30, 26), Loc.T("No"))) confirmReset = false;
        }

        void QuoteBox(HuntTracker h, Rect inner)
        {
            Modal(inner, out var box);
            var q = h.Quote;
            var st = new GUIStyle(tiny) { wordWrap = true, fontSize = 12 };
            string text;
            if (q.Why.Length > 0 || q.Rows.Count == 0)
            {
                text = q.Why == "pz" ? Loc.T("Restock works in a protection zone in town.") : q.Why == "instance" ? Loc.T("Restock does not work inside an instance.")
                    : q.Why == "money" ? Loc.T("Not enough gold for a restock (carried and bank).") : Loc.T("Nothing to restock: this session used no supplies yet.");
                GUI.Label(new Rect(box.x + 8, box.y + 10, box.width - 16, 100), text, st);
                if (GUI.Button(new Rect(box.center.x - 40, box.yMax - 36, 80, 26), Loc.T("Ok"))) h.Quote = null;
                return;
            }
            text = Loc.T("Buy back what this hunt used for {0} gold?", Fmt.Exact(q.Gold));
            if (q.Fee > 0) text += "\n" + Loc.T("It includes a {0}% convenience fee: {1} gold.", q.Pct, Fmt.Exact(q.Fee));
            int n = 0;
            foreach (var r in q.Rows) { if (n++ >= 5) break; text += "\n" + r.Key + "x " + r.Value; }
            GUI.Label(new Rect(box.x + 8, box.y + 8, box.width - 16, 110), text, st);
            if (GUI.Button(new Rect(box.x + 20, box.yMax - 36, box.width / 2 - 30, 26), Loc.T("Yes"))) h.Restock();
            if (GUI.Button(new Rect(box.center.x + 10, box.yMax - 36, box.width / 2 - 30, 26), Loc.T("No"))) h.Quote = null;
        }
    }
}
