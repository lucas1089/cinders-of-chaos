// Name shaders window (game_nameshaders, opcode 96, Core/Visual.cs NameShaderState) and the pages of the options window for sound, music, visual effects and layout
// (phase 5, track R). The options window (OptionsWindow.cs) shows the pages through VisualOptionsUi.Page. Every option is saved in PlayerPrefs by VisualPrefs.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>The name shaders the account owns: pick one and the own name wears it (a moving gradient on the name label).</summary>
    public sealed class NameShadersWindow : GameWindow
    {
        public override string Title => Loc.T("Name shaders");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 170, 90, 340, 380);

        string search = "";
        Vector2 scroll;
        string notice = "";
        double noticeAt;
        object hooked;

        public override void Reset() { Open = false; search = ""; notice = ""; hooked = null; }

        public override void Tick(ChaosApp app)
        {
            var v = app.Session?.Visual;
            if (v == null) return;
            if (hooked != v)
            {
                hooked = v;
                v.Names.Notified = (name, selected) => { notice = selected ? Loc.T("Name shader equipped: {0}", name) : Loc.T("Name shader unlocked: {0}", name); noticeAt = Time.unscaledTime; };
            }
            if (v.Names.OpenRequested) { v.Names.OpenRequested = false; Open = true; }
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var v = app.Session?.Visual;
            if (v == null) return;
            var names = v.Names;
            float y = inner.y;
            GUI.Label(new Rect(inner.x + 4, y, 60, 22), Loc.T("Search"), app.SmallStyle);
            search = GUI.TextField(new Rect(inner.x + 64, y, inner.width - 72, 22), search);
            y += 28;
            if (names.Shaders.Count == 0)
            {
                GUI.Label(new Rect(inner.x + 4, y, inner.width - 8, 44), Loc.T("The list comes with the outfit window."), app.SmallStyle);
                if (GUI.Button(new Rect(inner.x + 4, y + 46, inner.width - 8, 26), Loc.T("Load the list"))) app.Session.RequestOutfits();
                return;
            }
            var list = names.Filter(search);
            var view = new Rect(inner.x + 2, y, inner.width - 4, inner.height - (y - inner.y) - (notice.Length > 0 ? 24 : 4));
            var content = new Rect(0, 0, view.width - 18, list.Count * 30);
            scroll = GUI.BeginScrollView(view, scroll, content);
            for (int i = 0; i < list.Count; i++)
            {
                var s = list[i];
                var r = new Rect(0, i * 30, content.width, 28);
                bool current = s.Id == names.Current;
                ChaosApp.Fill(r, current ? new Color(0.25f, 0.18f, 0.08f, 0.9f) : new Color(0.08f, 0.06f, 0.1f, 0.9f));
                uint rgb = s.Available ? NameShaderState.At(s.Name, Time.unscaledTime * 1000.0) : 0x777777;
                var st = new GUIStyle(app.SmallStyle) { fontStyle = FontStyle.Bold };
                st.normal.textColor = new Color(((rgb >> 16) & 255) / 255f, ((rgb >> 8) & 255) / 255f, (rgb & 255) / 255f);
                GUI.Label(new Rect(r.x + 8, r.y + 3, r.width - 100, 22), s.Name, st);
                var b = new Rect(r.xMax - 88, r.y + 2, 84, 24);
                if (current) GUI.Label(b, Loc.T("Equipped"), app.SmallStyle);
                else if (!s.Available) GUI.Label(b, Loc.T("Locked"), app.SmallStyle);
                else if (GUI.Button(b, Loc.T("Equip"))) names.Select(s.Id);
            }
            GUI.EndScrollView();
            if (notice.Length > 0 && Time.unscaledTime - noticeAt < 8f) GUI.Label(new Rect(inner.x + 4, inner.yMax - 22, inner.width - 8, 20), notice, app.SmallStyle);
        }
    }

    /// <summary>The sound, visual and layout pages of the options window.</summary>
    public static class VisualOptionsUi
    {
        public static readonly string[] Pages = { "General", "Sound", "Visuals", "Layout" };

        static bool Check(ref float y, Rect inner, bool value, string text, ChaosApp app)
        {
            bool now = GUI.Toggle(new Rect(inner.x + 2, y, inner.width - 4, 22), value, text);
            y += 24;
            return now;
        }

        static int Choice(ref float y, Rect inner, string label, string[] keys, string[] texts, int cur, ChaosApp app)
        {
            GUI.Label(new Rect(inner.x + 2, y, 110, 22), label, app.SmallStyle);
            float bw = (inner.width - 116) / keys.Length;
            for (int i = 0; i < keys.Length; i++)
                if (GUI.Toggle(new Rect(inner.x + 112 + i * bw, y, bw - 3, 22), cur == i, texts[i], GUI.skin.button) && cur != i) cur = i;
            y += 26;
            return cur;
        }

        static float Slider(ref float y, Rect inner, string label, float value, float min, float max, string shown, ChaosApp app)
        {
            GUI.Label(new Rect(inner.x + 2, y, 140, 22), label, app.SmallStyle);
            float v = GUI.HorizontalSlider(new Rect(inner.x + 144, y + 6, inner.width - 200, 16), value, min, max);
            GUI.Label(new Rect(inner.xMax - 52, y, 50, 22), shown, app.SmallStyle);
            y += 26;
            return v;
        }

        /// <summary>Draws a page (1 sound, 2 visuals, 3 layout) of the options. inner is the options body. Saves when something changed.</summary>
        public static void Page(ChaosApp app, int page, Rect inner)
        {
            VisualPrefs.Load();
            GUI.changed = false;
            float y = inner.y + 30;
            if (page == 1) Sound(app, inner, ref y);
            else if (page == 2) Visuals(app, inner, ref y);
            else if (page == 3) LayoutPage(app, inner, ref y);
            if (GUI.changed) VisualPrefs.Save();
        }

        static void Sound(ChaosApp app, Rect inner, ref float y)
        {
            var s = VisualPrefs.Sound;
            s.Enabled = Check(ref y, inner, s.Enabled, Loc.T("Game sounds"), app);
            int vol = Choice(ref y, inner, Loc.T("Volume"), SoundLogic.VolumeOrder, new[] { Loc.T("Quiet"), Loc.T("Normal"), Loc.T("Loud") }, System.Array.IndexOf(SoundLogic.VolumeOrder, s.Volume), app);
            s.Volume = SoundLogic.VolumeOrder[Mathf.Max(0, vol)];
            s.Combat = Check(ref y, inner, s.Combat, Loc.T("Combat sounds"), app);
            s.Spells = Check(ref y, inner, s.Spells, Loc.T("Spell sounds"), app);
            s.Events = Check(ref y, inner, s.Events, Loc.T("Level up, loot and goals"), app);
            s.Ui = Check(ref y, inner, s.Ui, Loc.T("Window sounds"), app);
            if (GUI.Button(new Rect(inner.x + 2, y, inner.width - 4, 24), Loc.T("Play a test sound"))) app.PlayTestSound("levelup");
            y += 34;
            var m = VisualPrefs.Music;
            m.Enabled = Check(ref y, inner, m.Enabled, Loc.T("Region music"), app);
            m.Volume = Mathf.RoundToInt(Slider(ref y, inner, Loc.T("Music volume"), m.Volume, 0, 100, m.Volume + "%", app));
            m.Background = Check(ref y, inner, m.Background, Loc.T("Mute the music when the window is in the background"), app);
            string playing = app.MusicRegionPlaying;
            if (playing.Length > 0) GUI.Label(new Rect(inner.x + 2, y, inner.width - 4, 20), Loc.T("Now playing: {0}", Loc.T(RegionName(playing))), app.SmallStyle);
            y += 22;
            if (app.OverlayPath(SoundLogic.Dir + "hit_1.ogg") == null)
            {
                var st = new GUIStyle(app.SmallStyle) { wordWrap = true };
                st.normal.textColor = new Color(1f, 0.6f, 0.4f);
                GUI.Label(new Rect(inner.x + 2, y, inner.width - 4, 60), Loc.T("The sound files were not found. Set CHAOS_OVERLAY_DIR to the folder client/overlay/modules."), st);
            }
        }

        static string RegionName(string r)
        {
            switch (r) { case "town": return "Town"; case "hunt": return "Hunt"; case "dungeon": return "Dungeon"; case "boss": return "Boss"; case "arena": return "Arena"; default: return "Login"; }
        }

        static void Visuals(ChaosApp app, Rect inner, ref float y)
        {
            VisualPrefs.EffectPercent = EffectOpacity.Clamp(Slider(ref y, inner, Loc.T("Spell effect opacity"), VisualPrefs.EffectPercent, EffectOpacity.Min, EffectOpacity.Max, VisualPrefs.EffectPercent + "%", app));
            var fx = VisualPrefs.Fx;
            fx.HitFlash = Check(ref y, inner, fx.HitFlash, Loc.T("Hit flash"), app);
            fx.ScreenShake = Check(ref y, inner, fx.ScreenShake, Loc.T("Screen shake on big hits"), app);
            VisualPrefs.Decals = Check(ref y, inner, VisualPrefs.Decals, Loc.T("Stains on the ground after combat"), app);
            VisualPrefs.Globes = Check(ref y, inner, VisualPrefs.Globes, Loc.T("Health and mana globes"), app);
            var b = VisualPrefs.Beams;
            b.Enabled = Check(ref y, inner, b.Enabled, Loc.T("Loot beams"), app);
            if (b.Enabled)
            {
                b.Ground = Check(ref y, inner, b.Ground, Loc.T("Beams on ground items too"), app);
                b.Orbs = Check(ref y, inner, b.Orbs, Loc.T("Beams for orbs"), app);
                int h = Choice(ref y, inner, Loc.T("Beam height"), LootBeams.HeightOrder, new[] { Loc.T("Short"), Loc.T("Normal"), Loc.T("Tall") }, System.Array.IndexOf(LootBeams.HeightOrder, b.Height), app);
                b.Height = LootBeams.HeightOrder[Mathf.Max(0, h)];
                int it = Choice(ref y, inner, Loc.T("Beam light"), LootBeams.IntensityOrder, new[] { Loc.T("Soft"), Loc.T("Normal"), Loc.T("Bright") }, System.Array.IndexOf(LootBeams.IntensityOrder, b.Intensity), app);
                b.Intensity = LootBeams.IntensityOrder[Mathf.Max(0, it)];
            }
            VisualPrefs.ChestAuras = Check(ref y, inner, VisualPrefs.ChestAuras, Loc.T("Chest and Templar auras"), app);
            VisualPrefs.ItemOutlines = Check(ref y, inner, VisualPrefs.ItemOutlines, Loc.T("Rarity outline on items on the map"), app);
            VisualPrefs.Painted = Check(ref y, inner, VisualPrefs.Painted, Loc.T("Painted icons (bar, spellbook, passive tree)"), app);
            VisualPrefs.WingsOwn = Check(ref y, inner, VisualPrefs.WingsOwn, Loc.T("Level-up wings on my character"), app);
            VisualPrefs.WingsOthers = Check(ref y, inner, VisualPrefs.WingsOthers, Loc.T("Level-up wings on other characters"), app);
            VisualPrefs.PrintsOthers = Check(ref y, inner, VisualPrefs.PrintsOthers, Loc.T("Footprints of other characters"), app);
            VisualPrefs.GlowsOthers = Check(ref y, inner, VisualPrefs.GlowsOthers, Loc.T("Glows of other characters"), app);
            VisualPrefs.ErrorColorOn = Check(ref y, inner, VisualPrefs.ErrorColorOn, Loc.T("Error messages in their own colour"), app);
            VisualPrefs.UiFadeOn = Check(ref y, inner, VisualPrefs.UiFadeOn, Loc.T("Fade windows in and out"), app);
            bool weatherOld = Phase7Prefs.WeatherOn;
            Phase7Prefs.WeatherOn = Check(ref y, inner, Phase7Prefs.WeatherOn, Loc.T("Rain, embers and area colours"), app);
            if (weatherOld != Phase7Prefs.WeatherOn) Phase7Prefs.Save();
            if (GUI.Button(new Rect(inner.x + 2, y + 4, inner.width - 4, 24), Loc.T("Name shaders..."))) { var w = app.FindWindow<NameShadersWindow>(); if (w != null) w.Open = true; }
        }

        static void LayoutPage(ChaosApp app, Rect inner, ref float y)
        {
            GUI.Label(new Rect(inner.x + 2, y, 130, 22), Loc.T("Map zoom"), app.SmallStyle);
            if (GUI.Button(new Rect(inner.x + 120, y, 30, 22), "-")) { VisualPrefs.ViewRows = ViewZoom.Step(ViewZoom.Clamp(VisualPrefs.ViewRows, app.ViewMaxRows), -1, app.ViewMaxRows); }
            GUI.Label(new Rect(inner.x + 156, y, 150, 22), Loc.T("{0} rows", ViewZoom.Clamp(VisualPrefs.ViewRows, app.ViewMaxRows)), app.SmallStyle);
            if (GUI.Button(new Rect(inner.x + 280, y, 30, 22), "+")) { VisualPrefs.ViewRows = ViewZoom.Step(ViewZoom.Clamp(VisualPrefs.ViewRows, app.ViewMaxRows), 1, app.ViewMaxRows); }
            y += 28;
            var st = new GUIStyle(app.SmallStyle) { wordWrap = true };
            GUI.Label(new Rect(inner.x + 2, y, inner.width - 4, 40), Loc.T("Ctrl and the mouse wheel over the map zoom too. Wide view asks the server for the largest area, so up to 19 rows show in the classic view (11 in HD-2D and the live view)."), st);
            y += 46;
            VisualPrefs.WideView = Check(ref y, inner, VisualPrefs.WideView, Loc.T("Wide view (ask the server for 29 x 21 tiles)"), app);
            bool edit = Check(ref y, inner, HudLayout.Editing, Loc.T("Move the HUD pieces"), app);
            if (edit != HudLayout.Editing) { HudLayout.Editing = edit; if (!edit) app.SaveHud(); }
            if (GUI.Button(new Rect(inner.x + 2, y, inner.width - 4, 24), Loc.T("Put the HUD pieces back"))) app.ResetHud();
            y += 32;
            VisualPrefs.LayoutOn = Check(ref y, inner, VisualPrefs.LayoutOn, Loc.T("Remember window places per character"), app);
            // phase 7, track Q: the interface scale, the window frames and their skins
            y += 4;
            GUI.Label(new Rect(inner.x + 2, y, 130, 22), Loc.T("Interface scale"), app.SmallStyle);
            int oldScale = Phase7Prefs.UiScaleIndex;
            if (GUI.Button(new Rect(inner.x + 120, y, 30, 22), "-")) Phase7Prefs.UiScaleIndex = UiScaleOption.ClampIndex(Phase7Prefs.UiScaleIndex - 1);
            GUI.Label(new Rect(inner.x + 156, y, 110, 22), UiScaleOption.Percent(Phase7Prefs.UiScaleIndex) + "%", app.SmallStyle);
            if (GUI.Button(new Rect(inner.x + 280, y, 30, 22), "+")) Phase7Prefs.UiScaleIndex = UiScaleOption.ClampIndex(Phase7Prefs.UiScaleIndex + 1);
            y += 28;
            bool themeOld = Phase7Prefs.ThemeOn;
            Phase7Prefs.ThemeOn = Check(ref y, inner, Phase7Prefs.ThemeOn, Loc.T("Dark fantasy window frames"), app);
            string skinOld = Phase7Prefs.Skin;
            if (GUI.Button(new Rect(inner.x + 2, y, inner.width - 4, 24), Loc.T("Window skin: {0}", Loc.T(UiTheme.SkinNames[Phase7Prefs.Skin])))) Phase7Prefs.Skin = UiTheme.Next(Phase7Prefs.Skin);
            y += 30;
            if (oldScale != Phase7Prefs.UiScaleIndex || themeOld != Phase7Prefs.ThemeOn || skinOld != Phase7Prefs.Skin) Phase7Prefs.Save();
        }
    }
}
