// Phase 7, track Q: UI, map and visual rows (the rules are in Core/Phase7Q.cs, Core/Layout.cs ViewZoom):
//   the interface scale option, the themed window frames and skins, the map mark pictures, the explored minimap kept over a relog and the windows that come
//   back after a death, the tiled weather pictures and the name plate pictures. Pictures are the main client's own files read through the overlay folders
//   (ArtTexture); every drawing keeps its older stand-in, so a missing file never breaks a window.
using System;
using System.Collections.Generic;
using System.IO;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>The options of this track, kept in PlayerPrefs.</summary>
    public static class Phase7Prefs
    {
        public static int UiScaleIndex = UiScaleOption.DefaultIndex;
        public static bool ThemeOn = true, WeatherOn = true;
        public static string Skin = "classic";
        public const string WeatherPref = "chaos.weather";
        static bool loaded;

        public static void Load()
        {
            if (loaded) return;
            loaded = true;
            try
            {
                UiScaleIndex = UiScaleOption.ParseSaved(PlayerPrefs.GetInt(UiScaleOption.Pref, UiScaleOption.DefaultIndex));
                ThemeOn = PlayerPrefs.GetInt(UiTheme.Pref, 1) == 1;
                Skin = UiTheme.Normalize(PlayerPrefs.GetString(UiTheme.SkinPref, "classic"));
                WeatherOn = PlayerPrefs.GetInt(WeatherPref, 1) == 1;
            }
            catch (Exception) { }
        }

        public static void Save()
        {
            PlayerPrefs.SetInt(UiScaleOption.Pref, UiScaleIndex);
            PlayerPrefs.SetInt(UiTheme.Pref, ThemeOn ? 1 : 0);
            PlayerPrefs.SetString(UiTheme.SkinPref, Skin);
            PlayerPrefs.SetInt(WeatherPref, WeatherOn ? 1 : 0);
            PlayerPrefs.Save();
        }
    }

    public sealed partial class ChaosApp
    {
        readonly Dictionary<string, Texture2D> repeatTex = new Dictionary<string, Texture2D>();
        GUIStyle themedTitle;
        string themedTitleSkin;
        World minimapLoadedFor;
        string minimapLoadedName;
        int minimapSavedVersion;
        double minimapSavedAt;
        World reopenChecked;

        // ------------------------------------------------------------------------------------------------ pictures
        /// <summary>A picture of the overlay folders that repeats (tiles of rain and ambient specks); null when missing.</summary>
        Texture2D ArtRepeat(string rel)
        {
            if (repeatTex.TryGetValue(rel, out var t)) return t;
            t = null;
            string path = OverlayPath(rel);
            if (path != null)
            {
                try
                {
                    t = new Texture2D(2, 2, TextureFormat.RGBA32, false) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Repeat };
                    if (!t.LoadImage(File.ReadAllBytes(path))) { Destroy(t); t = null; }
                }
                catch (Exception) { t = null; }
            }
            repeatTex[rel] = t;
            return t;
        }

        /// <summary>Draws a repeated tile picture over r, scrolled by (ox, oy) pixels, as the main client's repeated image does.</summary>
        static void DrawTiled(Texture2D tex, int tile, Rect r, double ox, double oy, Color c)
        {
            if (tex == null || c.a <= 0.003f) return;
            TiledArt.Uv(tile, ox, oy, r.width, r.height, out double u, out double v, out double du, out double dv);
            var old = GUI.color; GUI.color = c;
            GUI.DrawTextureWithTexCoords(r, tex, new Rect((float)u, (float)v, (float)du, (float)dv));
            GUI.color = old;
        }

        /// <summary>A map mark picture of w x h pixels (times k) centred on at; false when the picture is missing, so the caller draws its square.</summary>
        bool ArtMark(string rel, Vector2 at, int w, int h, Color tint, float k = 1f)
        {
            if (rel == null) return false;
            var tex = ArtTexture(rel);
            if (tex == null) return false;
            if (Event.current.type == EventType.Repaint) Pic(tex, new Rect(at.x - w * k / 2f, at.y - h * k / 2f, w * k, h * k), tint);
            return true;
        }

        /// <summary>A picture cut in nine with its own borders in UI units (dst) and in texture fractions (src): left, top, right, bottom.</summary>
        static void NineSliceEdges(Texture2D t, Rect r, float el, float et, float er, float eb, float ul, float ut, float ur, float ub, Color c)
        {
            if (t == null) return;
            var old = GUI.color; GUI.color = c;
            float[] xs = { r.x, r.x + el, r.xMax - er, r.xMax }, ys = { r.y, r.y + et, r.yMax - eb, r.yMax };
            float[] us = { 0f, ul, 1f - ur, 1f }, vs = { 1f, 1f - ut, ub, 0f };
            for (int j = 0; j < 3; j++)
                for (int i = 0; i < 3; i++)
                {
                    var dst = new Rect(xs[i], ys[j], Mathf.Max(0f, xs[i + 1] - xs[i]), Mathf.Max(0f, ys[j + 1] - ys[j]));
                    if (dst.width <= 0f || dst.height <= 0f) continue;
                    var src = new Rect(us[i], vs[j + 1], us[i + 1] - us[i], vs[j] - vs[j + 1]);
                    GUI.DrawTextureWithTexCoords(dst, t, src);
                }
            GUI.color = old;
        }

        // ------------------------------------------------------------------------------------------------ the window theme
        /// <summary>The style of a window title: the theme's colour when the theme is on.</summary>
        public GUIStyle WindowTitleStyle
        {
            get
            {
                Phase7Prefs.Load();
                if (!Phase7Prefs.ThemeOn) return titleStyle;
                if (themedTitle == null || themedTitleSkin != Phase7Prefs.Skin)
                {
                    themedTitle = new GUIStyle(titleStyle);
                    themedTitle.normal.textColor = HexColor(UiTheme.PaletteOf(Phase7Prefs.Skin).Title);
                    themedTitleSkin = Phase7Prefs.Skin;
                }
                return themedTitle;
            }
        }

        /// <summary>The frame of a game window of w x h (inside the window's own group): the skin's window picture cut in nine, the four corner pieces and the crest.
        /// False when the theme is off or the pictures are not there; the window then draws its flat style.</summary>
        public bool DrawWindowChrome(float w, float h)
        {
            Phase7Prefs.Load();
            if (!Phase7Prefs.ThemeOn) return false;
            string skin = Phase7Prefs.Skin;
            var tex = ArtTexture(UiTheme.Window(skin), true) ?? (skin != "classic" ? ArtTexture(UiTheme.Window("classic"), true) : null);
            if (tex == null) return false;
            if (Event.current.type != EventType.Repaint) return true;
            var pal = UiTheme.PaletteOf(skin);
            Fill(new Rect(0, 0, w, h), HexColor(pal.Bg) * new Color(1f, 1f, 1f, 0.94f));
            NineSliceEdges(tex, new Rect(0, 0, w, h), UiTheme.EdgeSide, UiTheme.EdgeTop, UiTheme.EdgeSide, UiTheme.EdgeBottom,
                UiTheme.BorderL / (float)UiTheme.ArtSize, UiTheme.BorderT / (float)UiTheme.ArtSize, UiTheme.BorderR / (float)UiTheme.ArtSize, UiTheme.BorderB / (float)UiTheme.ArtSize, Color.white);
            if (UiTheme.ShowCorners(w, h))
            {
                float s = UiTheme.CornerDraw, i = UiTheme.CornerInset;
                string[] which = { "tl", "tr", "bl", "br" };
                var pos = new[] { new Vector2(-i, -i), new Vector2(w - s + i, -i), new Vector2(-i, h - s + i), new Vector2(w - s + i, h - s + i) };
                for (int k = 0; k < 4; k++)
                {
                    var ct = ArtTexture(UiTheme.Corner(skin, which[k]), true) ?? (skin != "classic" ? ArtTexture(UiTheme.Corner("classic", which[k]), true) : null);
                    if (ct != null) Pic(ct, new Rect(pos[k].x, pos[k].y, s, s), Color.white);
                }
            }
            if (UiTheme.ShowCrest(w))
            {
                var cr = ArtTexture(UiTheme.Crest(skin), true) ?? (skin != "classic" ? ArtTexture(UiTheme.Crest("classic"), true) : null);
                if (cr != null) Pic(cr, new Rect((w - UiTheme.CrestDrawW) / 2f, -UiTheme.CrestUp, UiTheme.CrestDrawW, UiTheme.CrestDrawH), Color.white);
            }
            return true;
        }

        // ------------------------------------------------------------------------------------------------ name plate picture
        /// <summary>The plate of a player's name: the frame picture cut in nine (game_nameplate); false without the picture, the bordered box is drawn instead.</summary>
        bool DrawPlatePicture(string frame, Rect box)
        {
            var tex = ArtTexture(PlateArt.Path(frame));
            if (tex == null) return false;
            float e = PlateArt.Edge(box.width, box.height);
            float ux = PlateArt.Border / (float)PlateArt.Width, uy = PlateArt.Border / (float)PlateArt.Height;
            NineSliceEdges(tex, box, e, e, e, e, ux, uy, ux, uy, Color.white);
            return true;
        }

        // ------------------------------------------------------------------------------------------------ the explored map and the death note
        string MinimapFile(string name)
        {
            string f = MinimapStore.FileName(name);
            return f == null ? null : Path.Combine(Application.persistentDataPath, "minimap", f);
        }

        void LoadMinimap(string name)
        {
            try
            {
                string path = MinimapFile(name);
                if (path != null && File.Exists(path)) MinimapStore.Load(File.ReadAllBytes(path), Minimap);
            }
            catch (Exception e) { Debug.Log("chaos minimap: could not read the saved map: " + e.Message); }
            minimapSavedVersion = Minimap.Version;
            minimapSavedAt = Time.realtimeSinceStartup * 1000.0;
        }

        void SaveMinimap()
        {
            if (minimapLoadedName == null || minimapLoadedFor == null) return;
            try
            {
                string path = MinimapFile(minimapLoadedName);
                if (path == null) return;
                Directory.CreateDirectory(Path.GetDirectoryName(path));
                string tmp = path + ".tmp";
                File.WriteAllBytes(tmp, MinimapStore.Save(Minimap));
                if (File.Exists(path)) File.Delete(path);
                File.Move(tmp, path);
                minimapSavedVersion = Minimap.Version;
                minimapSavedAt = Time.realtimeSinceStartup * 1000.0;
            }
            catch (Exception e) { Debug.Log("chaos minimap: could not save the map: " + e.Message); }
        }

        static double WallMs() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

        /// <summary>Every frame in the game: loads the character's explored map once, saves it every minute, reopens the overlay and the minimap window after a death.</summary>
        void Phase7QUpdate()
        {
            if (screen != Screen.Game || session == null || world?.Player == null || minimapWorld != world) return;
            string name = world.Player.Name;
            if (string.IsNullOrEmpty(name)) return;
            if (minimapLoadedFor != world)
            {
                minimapLoadedFor = world; minimapLoadedName = name;
                LoadMinimap(name);
            }
            else if (MinimapStore.DueForSave(Minimap.Version, minimapSavedVersion, Time.realtimeSinceStartup * 1000.0, minimapSavedAt)) SaveMinimap();
            if (reopenChecked != world && Utils != null)
            {
                reopenChecked = world;
                var note = DeathNote.Parse(PlayerPrefs.GetString(DeathNote.Pref, ""));
                if (note.Reopens(name, WallMs()))
                {
                    if (note.Overlay) Utils.Overlay.Show(true);
                    if (note.Minimap) { var mw = FindWindow<MinimapWindow>(); if (mw != null) mw.Open = true; }
                }
                if (note.Any) PlayerPrefs.SetString(DeathNote.Pref, "");
            }
        }

        /// <summary>Called first in Leave: the explored map is saved, and after a death the windows that were open are noted for the next game start.</summary>
        void Phase7QLeave(string why)
        {
            try
            {
                SaveMinimap();
                if (session != null && world?.Player != null && why == Loc.T("You died."))
                {
                    var mw = FindWindow<MinimapWindow>();
                    var note = new DeathNote { Name = world.Player.Name, AtMs = WallMs(), Overlay = Utils != null && Utils.Overlay.Shown, Minimap = mw != null && mw.Open };
                    PlayerPrefs.SetString(DeathNote.Pref, note.Any ? note.Serialize() : "");
                }
            }
            catch (Exception e) { Debug.Log("chaos: leave note failed: " + e.Message); }
            minimapLoadedFor = null; minimapLoadedName = null;
        }
    }
}
