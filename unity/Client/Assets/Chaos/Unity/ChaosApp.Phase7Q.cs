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
            using var _slow = SlowCalls.Scope(SlowCalls.Log.On ? "ArtRepeat " + rel : null, "load");
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
            using var _slow = SlowCalls.Scope("DrawWindowChrome", "OnGUI");
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

        // ---- the controls: buttons and text fields take the skin's pictures
        string controlSkin = "";
        struct StyleBackup { public Texture2D N, H, A, F, ON, OH, OA, OF; public RectOffset Border; public Color Text; }
        StyleBackup buttonBackup, fieldBackup;
        bool controlBackedUp;

        static Texture2D Cut(Texture2D sheet, int state)
        {
            var t = new Texture2D(UiTheme.SheetW, UiTheme.StateH, TextureFormat.RGBA32, false) { filterMode = FilterMode.Bilinear, wrapMode = TextureWrapMode.Clamp };
            t.SetPixels(sheet.GetPixels(0, UiTheme.StateRow(sheet.height, state), UiTheme.SheetW, UiTheme.StateH));
            t.Apply(false);
            return t;
        }

        static StyleBackup Backup(GUIStyle s) => new StyleBackup { N = s.normal.background, H = s.hover.background, A = s.active.background, F = s.focused.background, ON = s.onNormal.background, OH = s.onHover.background, OA = s.onActive.background, OF = s.onFocused.background, Border = new RectOffset(s.border.left, s.border.right, s.border.top, s.border.bottom), Text = s.normal.textColor };

        static void Restore(GUIStyle s, StyleBackup b)
        {
            s.normal.background = b.N; s.hover.background = b.H; s.active.background = b.A; s.focused.background = b.F;
            s.onNormal.background = b.ON; s.onHover.background = b.OH; s.onActive.background = b.OA; s.onFocused.background = b.OF;
            s.border = b.Border;
            s.normal.textColor = s.hover.textColor = s.active.textColor = s.focused.textColor = b.Text;
            s.onNormal.textColor = s.onHover.textColor = s.onActive.textColor = s.onFocused.textColor = b.Text;
        }

        /// <summary>Gives the IMGUI buttons and text fields the pictures of the chosen skin (and puts the stock look back when the theme is off). Runs every OnGUI, acts on a change.</summary>
        void ApplyControlSkin()
        {
            using var _slow = SlowCalls.Scope("ApplyControlSkin", "OnGUI");
            Phase7Prefs.Load();
            string want = Phase7Prefs.ThemeOn ? Phase7Prefs.Skin : "";
            if (want == controlSkin) return;
            if (!controlBackedUp) { buttonBackup = Backup(GUI.skin.button); fieldBackup = Backup(GUI.skin.textField); controlBackedUp = true; }
            controlSkin = want;
            if (want == "") { Restore(GUI.skin.button, buttonBackup); Restore(GUI.skin.textField, fieldBackup); return; }
            var pal = UiTheme.PaletteOf(want);
            var sheet = ArtTexture(UiTheme.ButtonSheet(want), true) ?? ArtTexture(UiTheme.ButtonSheet("classic"), true);
            if (sheet != null && sheet.width >= UiTheme.SheetW && sheet.height >= UiTheme.StateH * UiTheme.SheetStates)
            {
                var b = GUI.skin.button;
                var n = Cut(sheet, 0); var h = Cut(sheet, 1); var p = Cut(sheet, 2);
                b.normal.background = n; b.hover.background = h; b.active.background = p; b.focused.background = n;
                b.onNormal.background = p; b.onHover.background = p; b.onActive.background = p; b.onFocused.background = p;
                int e = UiTheme.ButtonBorder;
                b.border = new RectOffset(e, e, e, e);
                var text = HexColor(pal.Text);
                b.normal.textColor = text; b.hover.textColor = HexColor(pal.GoldBright); b.active.textColor = HexColor(pal.Gold); b.focused.textColor = text;
                b.onNormal.textColor = b.onHover.textColor = b.onActive.textColor = b.onFocused.textColor = HexColor(pal.Gold);
            }
            var field = ArtTexture(UiTheme.FieldPicture(false), true);
            var focus = ArtTexture(UiTheme.FieldPicture(true), true);
            if (field != null)
            {
                var f = GUI.skin.textField;
                f.normal.background = field; f.hover.background = field; f.active.background = focus ?? field; f.focused.background = focus ?? field;
                f.onNormal.background = field; f.onHover.background = field; f.onActive.background = focus ?? field; f.onFocused.background = focus ?? field;
                int e = UiTheme.FieldBorder;
                f.border = new RectOffset(e, e, e, e);
                f.normal.textColor = f.hover.textColor = f.active.textColor = f.focused.textColor = HexColor(pal.Text);
            }
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

        // ------------------------------------------------------------------------------------------------ look preview extras
        static void FlattenPreview(PreviewOption o, List<PreviewOption> into)
        {
            if (o == null || into.Count > 12) return;
            if (o.Kind == "bundle" && o.Parts != null) { foreach (var p in o.Parts) FlattenPreview(p, into); return; }
            into.Add(o);
        }

        /// <summary>What sits under the figure of the look preview: the outline glow and the footprints behind it (game_lookpreview draws them in its effect stage).</summary>
        public void DrawPreviewUnder(PreviewOption opt, Rect stage)
        {
            if (opt == null || Event.current.type != EventType.Repaint) return;
            var all = new List<PreviewOption>();
            FlattenPreview(opt, all);
            double now = Time.realtimeSinceStartupAsDouble * 1000.0;
            foreach (var o in all)
            {
                if (o.Kind == "outline" && !string.IsNullOrEmpty(o.Art))
                {
                    var tex = OverlayTex("game_cosmeticfx/images/glows/" + o.Art + ".png");
                    float a = o.Pulse ? CosmeticFxState.PulseOpacity(now) : 1f;
                    if (tex != null) Pic(tex, new Rect(stage.x, stage.y, stage.width, stage.height), new Color(1f, 1f, 1f, 0.85f * a));
                    else Pic(texSoft ?? (texSoft = MakeTex(64, 64, (u, v) => { float d = Mathf.Sqrt((u - 0.5f) * (u - 0.5f) + (v - 0.5f) * (v - 0.5f)) * 2f; return 1f - d * d; })), new Rect(stage.x, stage.y, stage.width, stage.height), new Color(1f, 0.8f, 0.4f, 0.4f * a));
                }
                else if (o.Kind == "footprint" && !string.IsNullOrEmpty(o.Art))
                {
                    var tex = OverlayTex("game_cosmeticfx/images/prints/" + o.Art + ".png");
                    if (tex == null) continue;
                    float s = stage.width * 0.16f;
                    for (int i = 0; i < 4; i++)
                    {
                        // a trail going down and to the left, older prints fainter, left and right feet alternating
                        float x = stage.center.x + (i % 2 == 0 ? -s * 0.6f : s * 0.6f) - i * s * 0.25f, y = stage.yMax - s * 0.7f - i * s * 0.55f;
                        var m = GUI.matrix;
                        GUIUtility.RotateAroundPivot(-12f + i * 6f, new Vector2(x, y));
                        Pic(tex, new Rect(x - s / 2, y - s / 2, s, s), new Color(1f, 1f, 1f, 0.9f - i * 0.2f));
                        GUI.matrix = m;
                    }
                }
            }
        }

        /// <summary>What sits over the figure: a name plate frame with the character's name.</summary>
        public void DrawPreviewOver(PreviewOption opt, Rect stage, string name)
        {
            if (opt == null || Event.current.type != EventType.Repaint) return;
            var all = new List<PreviewOption>();
            FlattenPreview(opt, all);
            foreach (var o in all)
            {
                if (o.Kind != "nameplate" || string.IsNullOrEmpty(o.Frame)) continue;
                var st = new GUIStyle(small) { alignment = TextAnchor.MiddleCenter, fontSize = 12, fontStyle = FontStyle.Bold };
                float w = Mathf.Min(stage.width - 8, st.CalcSize(new GUIContent(name)).x + 18);
                var box = new Rect(stage.center.x - w / 2, stage.y + 4, w, 19);
                if (!DrawPlatePicture(o.Frame, box)) { Fill(box, new Color(0.05f, 0.04f, 0.06f, 0.8f)); Ui.Frame(box, HexColor(NameplateState.FrameColor(o.Frame))); }
                st.normal.textColor = HexColor(NameplateState.NameColor);
                GUI.Label(box, name, st);
            }
        }

        /// <summary>Shows a store name plate frame on the own plate for ten seconds (NameplateState.BeginTry); false when the plates are not ready.</summary>
        public bool TryPlateFrame(string frame)
        {
            var u = Utils;
            return u != null && world != null && world.PlayerId != 0 && u.Plates.BeginTry(world.PlayerId, frame, session.Now);
        }

        // ------------------------------------------------------------------------------------------------ streamer badge
        /// <summary>The small STREAMER badge (client_chaos_topbar setBadge 'streamer'): beside the top menu in the game, in the top right corner elsewhere. Gone in cinema mode.</summary>
        void StreamerBadgeGui(float w, float h)
        {
            using var _slow = SlowCalls.Scope("StreamerBadgeGui", "OnGUI");
            if (!streamer.Streamer || streamer.Cinema) return;
            string text = Loc.T("STREAMER");
            var st = new GUIStyle(small) { alignment = TextAnchor.MiddleCenter, fontSize = 11, fontStyle = FontStyle.Bold };
            st.normal.textColor = Color.white;
            float bw = st.CalcSize(new GUIContent(text)).x + 14;
            var r = screen == Screen.Game ? new Rect(Mathf.Max(4f, topBarRect.x - bw - 6f), topBarRect.y + 4f, bw, 20f) : new Rect(w - bw - 8f, 8f, bw, 20f);
            Fill(r, new Color(0.62f, 0.08f, 0.06f, 0.92f));
            Fill(new Rect(r.x, r.y, r.width, 1f), new Color(0.9f, 0.4f, 0.3f, 0.9f));
            GUI.Label(r, text, st);
            if (r.Contains(Event.current.mousePosition)) GUI.Label(new Rect(Mathf.Max(4f, r.xMax - 260f), r.yMax + 2f, 260f, 20f), Loc.T("Streamer mode is on (Ctrl+Shift+S). Options > Misc."), small);
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
            using var _slow = SlowCalls.Scope("Phase7QUpdate", "Update");
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
