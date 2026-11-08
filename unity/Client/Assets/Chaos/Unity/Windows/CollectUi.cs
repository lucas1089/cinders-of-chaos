// The drawing helpers and the window base of the collection, season and crafting windows (O433 phase 4, track N): bars, tabs, a wrapped label,
// a button that can be off, a yes / no box, and ModelWindow, a window that follows the Visible flag of its model (the server may open it).
using System;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>A window whose open state belongs to a model: opening it asks the server, a server message may open it, closing tells the model.</summary>
    public abstract class ModelWindow : GameWindow
    {
        bool last;
        protected abstract bool ModelVisible(ChaosApp app);
        protected abstract void ModelShow(ChaosApp app);
        protected abstract void ModelHide(ChaosApp app);
        /// <summary>Per-frame work of the model (timers).</summary>
        protected virtual void ModelTick(ChaosApp app) { }

        public override void Reset() { last = false; Open = false; }

        public override void Tick(ChaosApp app)
        {
            if (app.Session == null) return;
            bool v = ModelVisible(app);
            if (v != last) Open = v;
            else if (Open != v) { if (Open) ModelShow(app); else ModelHide(app); }
            last = ModelVisible(app);
            ModelTick(app);
        }
    }

    static class CU
    {
        static GUIStyle wrap, wrapDim;

        public static Color Hex(string hex, Color fallback) => hex != null && ColorUtility.TryParseHtmlString(hex, out var c) ? c : fallback;

        public static GUIStyle Wrap(ChaosApp app)
        {
            if (wrap == null) wrap = new GUIStyle(app.SmallStyle) { wordWrap = true };
            return wrap;
        }

        /// <summary>A label in a colour (hex), wrapped.</summary>
        public static void Label(ChaosApp app, Rect r, string text, string hex = null, bool wrapText = true, TextAnchor align = TextAnchor.UpperLeft)
        {
            var st = new GUIStyle(wrapText ? Wrap(app) : app.SmallStyle) { alignment = align };
            st.normal.textColor = Hex(hex, st.normal.textColor);
            GUI.Label(r, text, st);
        }

        public static void Bar(ChaosApp app, Rect r, int percent, string text, Color fill)
        {
            ChaosApp.Fill(r, new Color(0f, 0f, 0f, 0.8f));
            ChaosApp.Fill(new Rect(r.x + 1, r.y + 1, (r.width - 2) * Mathf.Clamp(percent, 0, 100) / 100f, r.height - 2), fill);
            if (!string.IsNullOrEmpty(text))
            {
                var st = new GUIStyle(app.SmallStyle) { alignment = TextAnchor.MiddleCenter, fontSize = Mathf.Min(app.SmallStyle.fontSize, 11) };
                GUI.Label(r, text, st);
            }
        }

        /// <summary>A button that is greyed and does nothing when off.</summary>
        public static bool Button(Rect r, string text, bool enabled = true, string tip = null)
        {
            var prev = GUI.enabled;
            GUI.enabled = enabled && prev;
            bool hit = GUI.Button(r, new GUIContent(text, tip));
            GUI.enabled = prev;
            return hit;
        }

        /// <summary>A row of tab buttons; returns the chosen index.</summary>
        public static int Tabs(Rect r, string[] labels, int current, float minWidth = 60f)
        {
            float x = r.x;
            for (int i = 0; i < labels.Length; i++)
            {
                float w = Mathf.Max(minWidth, 14f + labels[i].Length * 7f);
                if (x + w > r.xMax) { x = r.x; r.y += 26; }
                if (GUI.Toggle(new Rect(x, r.y, w, 24), i == current, labels[i], GUI.skin.button) && i != current) current = i;
                x += w + 3;
            }
            return current;
        }

        public static string Field(ChaosApp app, Rect r, string name, string text, int max)
        {
            GUI.SetNextControlName(name);
            text = GUI.TextField(r, text ?? "", max);
            if (GUI.GetNameOfFocusedControl() == name) app.MarkTextEditing();
            return text;
        }

        /// <summary>A small box over the window with a question; true when answered yes (answered = true on any button).</summary>
        public static bool Ask(ChaosApp app, Rect inner, string text, string yes, string no, out bool answered)
        {
            answered = false;
            var box = new Rect(inner.x + 20, inner.y + inner.height / 2 - 60, inner.width - 40, 120);
            ChaosApp.Fill(box, new Color(0.08f, 0.06f, 0.1f, 0.98f));
            ChaosApp.Fill(new Rect(box.x, box.y, box.width, 2), new Color(0.6f, 0.4f, 0.15f, 1f));
            GUI.Label(new Rect(box.x + 8, box.y + 8, box.width - 16, 70), text, Wrap(app));
            bool ok = false;
            if (GUI.Button(new Rect(box.x + box.width / 2 - 110, box.yMax - 34, 100, 26), yes)) { ok = true; answered = true; }
            if (GUI.Button(new Rect(box.x + box.width / 2 + 10, box.yMax - 34, 100, 26), no)) answered = true;
            return ok;
        }

        /// <summary>The tooltip of the hovered control (GUIContent tooltip) drawn near the mouse.</summary>
        public static void Tooltip(ChaosApp app, Rect window)
        {
            string tip = GUI.tooltip;
            if (string.IsNullOrEmpty(tip) || Event.current.type != EventType.Repaint) return;
            var m = Event.current.mousePosition;
            var st = Wrap(app);
            float w = Mathf.Min(300f, window.width - 8);
            float h = st.CalcHeight(new GUIContent(tip), w - 8) + 6;
            var r = new Rect(Mathf.Clamp(m.x + 12, 2, window.width - w - 2), Mathf.Clamp(m.y + 16, 2, window.height - h - 2), w, h);
            ChaosApp.Fill(r, new Color(0.05f, 0.04f, 0.07f, 0.97f));
            GUI.Label(new Rect(r.x + 4, r.y + 3, r.width - 8, r.height - 6), tip, st);
        }

        public static string Ago(double seconds) => Fmt.Duration(seconds);

        /// <summary>A scroll view of n rows of equal height; draws each row with draw(i, rect).</summary>
        public static Vector2 Rows(Rect view, Vector2 scroll, int count, float rowH, Action<int, Rect> draw)
        {
            float w = view.width - 18;
            scroll = GUI.BeginScrollView(view, scroll, new Rect(0, 0, w, Mathf.Max(view.height, count * rowH)));
            int first = Mathf.Max(0, (int)(scroll.y / rowH) - 1), last = Mathf.Min(count, first + (int)(view.height / rowH) + 3);
            for (int i = first; i < last; i++) draw(i, new Rect(0, i * rowH, w, rowH - 2));
            GUI.EndScrollView();
            return scroll;
        }
    }
}
