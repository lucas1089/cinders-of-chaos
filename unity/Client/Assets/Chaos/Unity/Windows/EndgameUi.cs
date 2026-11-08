// Drawing helpers of the endgame windows (track L): colours from "#rrggbb" texts, cached label styles, wrapped text, bars, and the base class of
// the small HUD windows that open by themselves while an activity runs (the tower panel, the dungeon counter, the raid, descent, invasion, siege,
// arena, battleground and Marches HUDs). The models are in Core/Endgame*.cs.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    static class Eu
    {
        public const string Text = "#d6c9ae", Dim = "#8c8070", Gold = "#e8b84a", Bright = "#f6cf72", Good = "#7fd07f", Bad = "#ff6040";

        public static Color Hex(string hex, string fallback = Text)
        {
            if (hex != null && ColorUtility.TryParseHtmlString(hex, out var c)) return c;
            return ColorUtility.TryParseHtmlString(fallback, out var f) ? f : Color.white;
        }

        static readonly Dictionary<string, GUIStyle> styles = new Dictionary<string, GUIStyle>();

        public static GUIStyle Style(ChaosApp app, int size = 12, string color = Text, bool bold = false, TextAnchor anchor = TextAnchor.UpperLeft, bool wrap = false)
        {
            string key = size + color + bold + anchor + wrap;
            if (styles.TryGetValue(key, out var s) && s != null && s.font == app.SmallStyle.font) return s;
            s = new GUIStyle(app.SmallStyle) { fontSize = size, fontStyle = bold ? FontStyle.Bold : FontStyle.Normal, alignment = anchor, wordWrap = wrap, clipping = TextClipping.Clip };
            s.normal.textColor = Hex(color);
            styles[key] = s;
            return s;
        }

        public static void Label(ChaosApp app, Rect r, string text, string color = Text, int size = 12, bool bold = false, TextAnchor anchor = TextAnchor.UpperLeft, bool wrap = false)
            => GUI.Label(r, text ?? "", Style(app, size, color, bold, anchor, wrap));

        public static float Height(ChaosApp app, string text, float width, int size = 12)
            => Style(app, size, Text, false, TextAnchor.UpperLeft, true).CalcHeight(new GUIContent(text ?? ""), width);

        /// <summary>Wrapped text at y; returns the height it took plus a gap.</summary>
        public static float Wrap(ChaosApp app, float x, float y, float w, string text, string color = Text, int size = 12, bool bold = false)
        {
            if (string.IsNullOrEmpty(text)) return 0;
            float h = Height(app, text, w, size);
            GUI.Label(new Rect(x, y, w, h), text, Style(app, size, color, bold, TextAnchor.UpperLeft, true));
            return h + 3;
        }

        public static void Bar(ChaosApp app, Rect r, double percent, string color, string text = null, int size = 11)
        {
            ChaosApp.Fill(r, new Color(0f, 0f, 0f, 0.8f));
            float f = Mathf.Clamp((float)percent, 0f, 100f) / 100f;
            ChaosApp.Fill(new Rect(r.x + 1, r.y + 1, (r.width - 2) * f, r.height - 2), Hex(color));
            if (!string.IsNullOrEmpty(text)) GUI.Label(r, text, Style(app, size, "#ffffff", true, TextAnchor.MiddleCenter));
        }

        public static void Panel(Rect r, float alpha = 0.06f) => ChaosApp.Fill(r, new Color(1f, 1f, 1f, alpha));

        public static bool Button(Rect r, string text, bool enabled = true)
        {
            bool was = GUI.enabled;
            GUI.enabled = was && enabled;
            bool hit = GUI.Button(r, text);
            GUI.enabled = was;
            return hit;
        }

        public static bool Toggle(Rect r, bool value, string text) => GUI.Toggle(r, value, text);

        public static string Two(double v) => ((long)System.Math.Max(0, System.Math.Floor(v))).ToString("00", System.Globalization.CultureInfo.InvariantCulture);
    }

    /// <summary>A small window that opens by itself while an activity runs and closes when it ends. The x hides it for this run.</summary>
    public abstract class EgHudWindow : GameWindow
    {
        bool wasWanted, dismissed, lastOpen;
        public override bool InMenu => false;
        /// <summary>True while the activity wants its HUD.</summary>
        protected abstract bool Wanted(ChaosApp app);
        public override void Reset() { wasWanted = false; dismissed = false; lastOpen = false; Open = false; }

        public override void Tick(ChaosApp app)
        {
            if (app.Session == null) return;
            EndgameBridge.Wire(app);
            bool wanted = Wanted(app);
            if (wanted && !wasWanted) { Open = true; dismissed = false; }
            if (!wanted) Open = false;
            else
            {
                if (!Open && lastOpen && wasWanted) dismissed = true;
                if (dismissed) Open = false;
            }
            lastOpen = Open;
            wasWanted = wanted;
        }
    }

    /// <summary>Wires the activities that change the fight mode (arena, battleground, Marches) and the lines the servers send as messages.
    /// The secure mode goes off for the fight and is restored after it, as the main client's secureOff / secureRestore do.</summary>
    static class EndgameBridge
    {
        static Chaos.Core.Endgame wired;
        static bool? secureBefore;

        public static void Wire(ChaosApp app)
        {
            var e = app.Session?.Endgame;
            if (e == null || e == wired) return;
            wired = e;
            secureBefore = null;
            System.Action off = () => SecureOff(app), on = () => SecureOn(app);
            e.Arena.Started = off; e.Arena.Ended = () => { app.Session?.CancelAttack(); on(); };
            e.Battleground.Started = off; e.Battleground.Ended = () => { app.Session?.CancelAttack(); on(); };
            e.PvpZone.Started = off; e.PvpZone.Ended = on;
            System.Action<string> line = t => app.PostLine(t);
            e.Raid.Notice = line; e.Descent.Notice = line; e.Battleground.Notice = line; e.Battleground.Alert = line; e.PvpZone.Notice = line;
        }

        static void SecureOff(ChaosApp app)
        {
            var s = app.Session;
            if (s == null) return;
            if (secureBefore == null) secureBefore = s.Modes.Secure;
            if (s.Modes.Secure)
            {
                var m = new FightModes { Fight = s.Modes.Fight, Chase = s.Modes.Chase, Secure = false };
                s.SetFightModes(m);
            }
        }

        static void SecureOn(ChaosApp app)
        {
            var s = app.Session;
            if (s == null) return;
            if (secureBefore == true && !s.Modes.Secure)
                s.SetFightModes(new FightModes { Fight = s.Modes.Fight, Chase = s.Modes.Chase, Secure = true });
            secureBefore = null;
        }
    }
}
