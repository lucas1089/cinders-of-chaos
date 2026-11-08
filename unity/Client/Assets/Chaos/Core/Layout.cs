// Layout rules of the main client's layout modules, the engine-free part (phase 5, track R): game_chaosview (map zoom), game_hudmove (movable HUD
// pieces), client_chaos_screenfit (a window taller than the screen scrolls), client_chaos_uifade (windows fade in and out) and game_chaoslayout
// (the saved window layout per character). The numbers and rules are the ones of the Lua logic files; the Unity side (ChaosApp.Visual.cs and
// GameWindow.Draw) applies them with PlayerPrefs. Floats only, no Unity types.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    // ============================================================================================================ map zoom
    /// <summary>The map zoom (game_chaosview). The main client shows `zoom` rows of tiles; Unity's map keeps the shape of the 15 x 11 view and shows 7 to 11 rows.
    /// More rows than the server sends (18 x 14, shown as 15 x 11) need the aware range change that Unity does not send yet.</summary>
    public static class ViewZoom
    {
        public const string Pref = "chaos.viewrows";
        public const int MinRows = 7, MaxRows = 11, DefaultRows = 11;
        public const int AwareWidth = 29, AwareHeight = 21, MaxDefaultRows = 15, TilePixels = 72;

        static int Odd(double n) { int i = (int)Math.Floor(n); return i % 2 == 0 ? i - 1 : i; }

        /// <summary>Rows kept to the odd numbers MinRows..MaxRows.</summary>
        public static int Clamp(int rows)
        {
            if (rows % 2 == 0) rows++;
            return Math.Max(MinRows, Math.Min(MaxRows, rows));
        }

        /// <summary>Columns for a row count: the 15 x 11 shape, rounded to an odd number.</summary>
        public static float Cols(int rows) => Clamp(rows) * 15f / 11f;

        public static int Step(int rows, int dir) => Clamp(rows + (dir > 0 ? 2 : dir < 0 ? -2 : 0));

        /// <summary>The furthest zoom out the area sent by the server allows (game_chaosview maxZoomOut): awareWidth / awareHeight, aspect = window width / height.</summary>
        public static int MaxZoomOut(int awareWidth, int awareHeight, double aspect)
        {
            int zoom = Odd(awareHeight <= 0 ? 13 : awareHeight);
            if (aspect <= 0) aspect = 1;
            while (zoom > 3)
            {
                int width = (int)Math.Floor(zoom * aspect);
                if (width % 2 == 0) width++;
                if (width <= awareWidth) return zoom;
                zoom -= 2;
            }
            return 3;
        }

        /// <summary>The zoom of a new player: about TilePixels per tile, from 11 rows up to 15, limited by maxZoom (the main client's defaultZoom).</summary>
        public static int DefaultZoom(double windowHeight, int maxZoom)
        {
            int rows = Odd(windowHeight / TilePixels);
            rows = Math.Max(11, Math.Min(MaxDefaultRows, rows));
            if (maxZoom >= 3) rows = Math.Min(rows, maxZoom);
            return rows;
        }
    }

    // ============================================================================================================ movable HUD
    /// <summary>The movable HUD pieces (game_hudmove): the character plate, the log out button, the chat and the top menu. The offset from the default place is kept
    /// per character in PlayerPrefs ("chaos.hudpos.name", JSON {id: [dx, dy]}); a piece stays fully on screen.</summary>
    public static class HudLayout
    {
        public const string Pref = "chaos.hudpos.";
        public const float DragMin = 3f;
        public static readonly string[] Pieces = { "status", "logout", "chat", "toolbar" };
        static readonly Dictionary<string, float[]> offsets = new Dictionary<string, float[]>();
        public static bool Editing;

        public static string Key(string character) => string.IsNullOrEmpty(character) ? null : Pref + character.ToLowerInvariant();

        public static bool Moved(string id) => offsets.ContainsKey(id);

        /// <summary>The place of a piece whose default is x, y, w, h on a sw x sh screen: the default plus the saved offset, kept fully on screen.</summary>
        public static void Place(string id, ref float x, ref float y, float w, float h, float sw, float sh)
        {
            if (!offsets.TryGetValue(id, out var o)) return;
            x = Clamp(x + o[0], w, sw);
            y = Clamp(y + o[1], h, sh);
        }

        static float Clamp(float v, float size, float room) => Math.Max(0f, Math.Min(Math.Max(0f, room - size), v));

        /// <summary>Moves a piece by a drag of (dx, dy) from where it is now (default at defX, defY, offset kept); the new offset is stored.</summary>
        public static void Drag(string id, float defX, float defY, float w, float h, float sw, float sh, float dx, float dy)
        {
            offsets.TryGetValue(id, out var o);
            float cx = defX + (o != null ? o[0] : 0f), cy = defY + (o != null ? o[1] : 0f);
            float nx = Clamp(cx + dx, w, sw), ny = Clamp(cy + dy, h, sh);
            float ox = nx - defX, oy = ny - defY;
            if (Math.Abs(ox) < 0.5f && Math.Abs(oy) < 0.5f) offsets.Remove(id); else offsets[id] = new[] { ox, oy };
        }

        public static void Reset(string id) { offsets.Remove(id); }
        public static void ResetAll() { offsets.Clear(); }

        public static string ToJson()
        {
            var d = new Dictionary<string, object>();
            foreach (var kv in offsets) d[kv.Key] = new List<object> { (double)kv.Value[0], (double)kv.Value[1] };
            return Json.Serialize(d);
        }

        public static void Load(string json)
        {
            offsets.Clear();
            if (!(Json.TryParse(json) is Dictionary<string, object> d)) return;
            foreach (string id in Pieces)
            {
                if (!d.TryGetValue(id, out object v) || !(v is List<object> l) || l.Count < 2 || !(l[0] is double a) || !(l[1] is double b)) continue;
                if (double.IsNaN(a) || double.IsNaN(b) || Math.Abs(a) > 4000 || Math.Abs(b) > 4000) continue;
                offsets[id] = new[] { (float)a, (float)b };
            }
        }
    }

    // ============================================================================================================ screen fit
    /// <summary>A window larger than the screen (client_chaos_screenfit): along one axis it may move only so far that it still covers the screen, so every part can be
    /// brought into view by dragging or by the mouse wheel; a window that fits stays inside as before.</summary>
    public static class ScreenFit
    {
        public const float WheelStep = 48f;

        public static bool Overflows(float size, float parent) => parent > 0 && size > parent;

        public static float Clamp(float pos, float size, float pStart, float pSize)
        {
            if (Overflows(size, pSize)) return Math.Min(pStart, Math.Max(pStart + pSize - size, pos));
            return Math.Max(pStart, Math.Min(pStart + pSize - size, pos));
        }

        /// <summary>Where a window opens: its start edge when it is larger than the parent, so the title shows.</summary>
        public static float OpenStart(float pos, float size, float pStart, float pSize) => Overflows(size, pSize) ? pStart : pos;

        /// <summary>One wheel notch: up shows the part above (the window moves down).</summary>
        public static float Wheel(float pos, float size, float pStart, float pSize, bool up)
        {
            if (!Overflows(size, pSize)) return pos;
            return Clamp(pos + (up ? WheelStep : -WheelStep), size, pStart, pSize);
        }
    }

    // ============================================================================================================ window fade
    /// <summary>Window fade in and out (client_chaos_uifade): in over 140 ms (ease out), out over 100 ms; a fade starts from the opacity the window has now.</summary>
    public sealed class UiFade
    {
        public const string Pref = "chaos.uifade";
        public const double InMs = 140, OutMs = 100, MinMs = 30;
        public const int Steps = 40;
        public const float MinW = 140, MinH = 80;
        bool isIn, active;
        double t0, ms;
        float from, current = 1f;

        /// <summary>The opacity now (1 when no fade runs and the window is shown).</summary>
        public float Value => current;
        public bool Running => active;

        /// <summary>May a window of this size fade? A small popup or tooltip does not.</summary>
        public static bool Eligible(bool on, float w, float h) => on && w >= MinW && h >= MinH;

        static float Clamp01(float v) => float.IsNaN(v) ? 0f : v < 0f ? 0f : v > 1f ? 1f : v;
        static float Round(float v) => (float)Math.Floor(Clamp01(v) * Steps + 0.5) / Steps;

        /// <summary>Starts a fade in or out from the opacity of now (a turn round in the middle takes only the time that is left).</summary>
        public void Begin(bool fadeIn, double now)
        {
            from = Clamp01(current);
            float span = fadeIn ? 1f - from : from;
            ms = Math.Max(MinMs, (fadeIn ? InMs : OutMs) * span);
            isIn = fadeIn; t0 = now; active = true;
        }

        /// <summary>One step: the opacity at now. Returns true while the fade runs; false when it is over (Value is then 0 or 1).</summary>
        public bool Step(double now)
        {
            if (!active) return false;
            double t = (now - t0) / ms;
            if (double.IsNaN(t) || t < 0) t = 0;
            float to = isIn ? 1f : 0f;
            if (t >= 1) { current = to; active = false; return false; }
            double e = isIn ? 1 - (1 - t) * (1 - t) * (1 - t) : t * t * 0.5 + t * 0.5;
            current = Round(from + (to - from) * (float)e);
            return true;
        }

        /// <summary>Starts hidden (0) or shown (1) with no fade.</summary>
        public void Snap(bool shown) { current = shown ? 1f : 0f; active = false; }
    }

    // ============================================================================================================ saved window layout
    /// <summary>The saved layout per character (game_chaoslayout): where each window is, and whether the windows that come back open were open. PlayerPrefs "chaos.layout.name", JSON {id: [x, y, open]}.</summary>
    public sealed class WindowLayout
    {
        public const string Pref = "chaos.layout.";
        public const int MaxWindows = 120;
        public sealed class Slot { public float X, Y; public bool Open; }
        readonly Dictionary<string, Slot> slots = new Dictionary<string, Slot>();
        public bool Dirty;

        public static string Key(string character) => string.IsNullOrEmpty(character) ? null : Pref + character.ToLowerInvariant();

        /// <summary>A window may be remembered when it has an id (the class name).</summary>
        public static bool Remembered(string id) => !string.IsNullOrEmpty(id) && id.Length <= 64;

        public bool TryGet(string id, out Slot s) => slots.TryGetValue(id, out s);

        /// <summary>Notes a window; Dirty is set when the place or the open state differs from the saved one.</summary>
        public void Note(string id, float x, float y, bool open)
        {
            if (!Remembered(id)) return;
            if (slots.TryGetValue(id, out var s))
            {
                if (Math.Abs(s.X - x) < 0.5f && Math.Abs(s.Y - y) < 0.5f && s.Open == open) return;
                s.X = x; s.Y = y; s.Open = open;
            }
            else
            {
                if (slots.Count >= MaxWindows) return;
                slots[id] = new Slot { X = x, Y = y, Open = open };
            }
            Dirty = true;
        }

        public string ToJson()
        {
            var d = new Dictionary<string, object>();
            foreach (var kv in slots) d[kv.Key] = new List<object> { Math.Round(kv.Value.X), Math.Round(kv.Value.Y), kv.Value.Open };
            Dirty = false;
            return Json.Serialize(d);
        }

        public static WindowLayout From(string json)
        {
            var l = new WindowLayout();
            if (!(Json.TryParse(json) is Dictionary<string, object> d)) return l;
            foreach (var kv in d)
            {
                if (l.slots.Count >= MaxWindows || !Remembered(kv.Key) || !(kv.Value is List<object> a) || a.Count < 2 || !(a[0] is double x) || !(a[1] is double y)) continue;
                if (double.IsNaN(x) || double.IsNaN(y) || Math.Abs(x) > 20000 || Math.Abs(y) > 20000) continue;
                l.slots[kv.Key] = new Slot { X = (float)x, Y = (float)y, Open = a.Count > 2 && a[2] is bool b && b };
            }
            return l;
        }

        public void Clear() { slots.Clear(); Dirty = false; }
        public int Count => slots.Count;
    }
}
