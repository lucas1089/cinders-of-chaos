// Phase 9 track E glue: the effect stage of the look preview (spell skins and kill effects playing round the preview creature), the look cards, and the bar of the login screen.
// Rules: Core/Phase9E.cs. Drawing follows game_lookpreview (lookpreview.lua startFx / fxTick / relayout): every thing is drawn tile by tile from the dat and the sprite atlas.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>What a preview panel keeps of the effect it plays: the steps, the timeline and the clock (restarted when another effect is chosen or the compare switch turns).</summary>
    public sealed class StagePlay
    {
        public object Play;
        public bool Compare;
        public List<FxStep> Steps = new List<FxStep>();
        public FxTimeline Timeline = new FxTimeline();
        public StageScene Scene = new StageScene();
        public double Started;
        bool has;

        public bool HasStock => PreviewStage.HasStock(Steps);
        public void Clear() { Play = null; has = false; Steps.Clear(); Timeline = new FxTimeline(); }
        public bool Matches(object play, bool compare) => has && ReferenceEquals(Play, play) && Compare == compare;

        public void Begin(PreviewOption fx, bool compare, System.Func<FxSpec, int> phasesOf, double nowMs)
        {
            Play = fx.Play; Compare = compare; has = true;
            Steps = PreviewStage.Steps(fx.Play);
            Scene = PreviewStage.SceneOf(fx);
            Timeline = PreviewStage.Timeline(Steps, compare && PreviewStage.HasStock(Steps) ? '*' : 'b', phasesOf, Scene);
            Started = nowMs;
        }
    }

    public sealed partial class ChaosApp
    {
        ThingType FxThing(FxSpec s) => s == null ? null : (s.Missile ? dat?.Missile(s.Id) : dat?.Effect(s.Id));

        /// <summary>Draws the effect scene in the stage (a spell skin: the character facing a troll with the effects between them; a kill effect: the troll that dies). The stage rect is
        /// where the window draws; returns false when there is nothing to play (no dat), so the caller draws the plain figure.</summary>
        public bool DrawEffectStage(Rect stage, PreviewOption fx, PreviewOption whole, Outfit look, string name, StagePlay sp, bool compare)
        {
            if (dat == null || atlas == null || fx == null || sp == null) return false;
            double now = Time.realtimeSinceStartupAsDouble * 1000.0;
            if (!sp.Matches(fx.Play, compare))
                sp.Begin(fx, compare, spec => { var t = FxThing(spec); return t != null ? t.Idle.Phases : 1; }, now);
            if (sp.Steps.Count == 0) return false;
            double[] SizeOf(FxSpec spec)
            {
                var t = FxThing(spec);
                return t == null ? new double[] { 1, 1, 0, 0 } : new double[] { t.Idle.Width, t.Idle.Height, t.DisplacementX, t.DisplacementY };
            }
            PreviewStage.Extent(sp.Steps, SizeOf, sp.Scene, PreviewStage.FallbackBox, PreviewStage.FallbackBox, out double x0, out double y0, out double x1, out double y1);
            var L = PreviewStage.Layout(stage.width, stage.height, x0, y0, x1, y1);
            var local = new Rect(0, 0, stage.width, stage.height);
            bool repaint = Event.current.type == EventType.Repaint;
            GUI.BeginGroup(stage);
            if (repaint)
            {
                DrawPreviewUnder(whole, local);   // an outline glow or the prints, when the option is a bundle with them
                double ms = now - sp.Started;
                var active = PreviewStage.ActiveAt(sp.Timeline, ms);
                foreach (var a in active) if (IsGroundFx(a.Item.Spec)) DrawStageItem(L, a, sp.Scene);
                float alpha = sp.Scene.Kill ? (float)PreviewStage.TargetAlpha(sp.Timeline, ms) : 1f;
                var old = GUI.color;
                PreviewStage.CreatureRect(L, sp.Scene.Target, out double tx, out double ty, out double ts);
                GUI.color = new Color(1f, 1f, 1f, alpha * old.a);
                DrawOutfitFx(new Rect((float)tx, (float)ty, (float)ts, (float)ts), new Outfit(PreviewStage.Troll, 0, 0, 0, 0), false, sp.Scene.Kill ? Dir.South : Dir.West, (float)L.T);
                GUI.color = old;
                if (sp.Scene.HasCaster && look != null)
                {
                    PreviewStage.CreatureRect(L, sp.Scene.Caster, out double cx, out double cy, out double cs);
                    DrawOutfitFx(new Rect((float)cx, (float)cy, (float)cs, (float)cs), look, false, Dir.East, (float)L.T);
                }
                foreach (var a in active) if (!IsGroundFx(a.Item.Spec)) DrawStageItem(L, a, sp.Scene);
                DrawPreviewOver(whole, local, name);
                if (compare && sp.HasStock && active.Count > 0)
                {
                    var st = new GUIStyle(small) { alignment = TextAnchor.UpperCenter, fontSize = 11 };
                    st.normal.textColor = new Color(0.78f, 0.72f, 0.56f);
                    GUI.Label(new Rect(4, 2, local.width - 8, 18), active[0].Item.Side == 'a' ? Loc.T("Default effects") : Loc.T("With this skin"), st);
                }
            }
            GUI.EndGroup();
            return true;
        }

        static bool IsGroundFx(FxSpec s) => s != null && !s.Missile && GroundFx.IsGround(s.Id);

        /// <summary>One playing effect or missile: its tiles from the dat, placed as the map places them (its bottom right tile on the tile it plays on, displacement applied).</summary>
        void DrawStageItem(StageLayout L, FxActive a, StageScene scene)
        {
            var spec = a.Item.Spec;
            var t = FxThing(spec);
            if (t == null) return;
            var g = t.Idle;
            PreviewStage.ItemPlace(a, scene, out double ox, out double oy, out int px, out int py);
            int phase = spec.Missile ? (int)(a.Ms / 75) % System.Math.Max(1, g.Phases) : PreviewStage.PhaseAt(a.Ms, a.Item.Dur, g.Phases);
            if (!spec.Missile) { px = 0; py = 0; }   // an effect's pattern follows its tile (Effect::draw: position % patterns); the stage's tile is (0, 0)
            for (int h = 0; h < g.Height; h++)
                for (int w = 0; w < g.Width; w++)
                {
                    uint id = g.Sprite(w, h, 0, px % System.Math.Max(1, g.PatternX), py % System.Math.Max(1, g.PatternY), 0, phase);
                    if (id == 0) continue;
                    int slot = atlas.Sprite(id);
                    if (slot == 0) continue;
                    atlas.Upload();
                    PreviewStage.TilePixel(L, ox, oy, w, h, t.DisplacementX, t.DisplacementY, out double x, out double y);
                    var old = GUI.color;
                    GUI.color = new Color(1f, 1f, 1f, VisualRuntime.EffectAlpha * old.a);
                    GUI.DrawTextureWithTexCoords(new Rect((float)x, (float)y, (float)L.T, (float)L.T), atlas.Texture, atlas.Uv(slot));
                    GUI.color = old;
                }
        }

        /// <summary>A list card's picture (game_lookpreview fitCard): the look facing south at the largest scale that fits the picture part, feet centred. The rect is the picture part.</summary>
        public void DrawLookCard(Rect pic, Outfit look)
        {
            if (look == null || dat == null || atlas == null || Event.current.type != EventType.Repaint) return;
            var t = dat.Outfit(look.LookType);
            int w = t != null ? t.Idle.Width : 2, h = t != null ? t.Idle.Height : 2;
            var L = LookCards.Layout(LookCards.Figure(w, h, look.Mount > 0), pic.width, pic.height);
            GUI.BeginGroup(pic);
            DrawOutfitFx(new Rect(L.X, L.Y, L.Size, L.Size), look, false, Dir.South, L.Tile);
            GUI.EndGroup();
        }

        // ------------------------------------------------------------------------------------ client_chaos_topbar: the bar of the login screen
        int loginMenuOpen = -1;
        bool loginOptions, loginCredits;
        int loginOptionsPage;
        Vector2 loginCreditsScroll;
        List<SocialRow> loginCreditRows;
        string loginCreditsFor;

        /// <summary>The System drop-down on the login screen and the character list: the entries that make sense with no character (Core/Phase9E.cs LoginMenu). A window opened from it is
        /// drawn here too (the options page and the credits).</summary>
        void LoginBarGui(float w, float h)
        {
            using var _slow = SlowCalls.Scope("LoginBarGui", "OnGUI");
            var b = new Rect(10, 8, 100, 30);
            bool on = loginMenuOpen == 0;
            if (GUI.Toggle(b, on, Loc.T("System"), GUI.skin.button) != on) loginMenuOpen = on ? -1 : 0;
            var e = Event.current;
            if (loginMenuOpen == 0)
            {
                var items = LoginMenu.Shown(Loc.T);
                float rowH = 26f;
                var box = new Rect(b.x, b.yMax + 2, 200, items.Count * rowH + 6);
                if (e.type == EventType.MouseDown && !box.Contains(e.mousePosition) && !b.Contains(e.mousePosition)) loginMenuOpen = -1;
                GUI.Window(MenuWindowId + 14, box, _ =>
                {
                    Fill(new Rect(0, 0, box.width, box.height), new Color(0.05f, 0.04f, 0.06f, 0.97f));
                    Fill(new Rect(0, 0, box.width, 1), new Color(0.6f, 0.5f, 0.3f));
                    for (int i = 0; i < items.Count; i++)
                        if (GUI.Button(new Rect(3, 3 + i * rowH, box.width - 6, rowH - 2), Loc.T(items[i].Text), GUI.skin.label) ) { RunLoginEntry(items[i].Id); loginMenuOpen = -1; }
                }, GUIContent.none, GUIStyle.none);
                GUI.BringWindowToFront(MenuWindowId + 14);
            }
            if (loginOptions) LoginOptionsGui(w, h);
            if (loginCredits) LoginCreditsGui(w, h);
        }

        void RunLoginEntry(string id)
        {
            switch (id)
            {
                case "options": loginOptions = true; loginOptionsPage = 0; break;
                case "sound": loginOptions = true; loginOptionsPage = 1; break;
                case "credits": loginCredits = true; break;
                case "discord": status = Loc.T("The community link is not available yet."); break;
                case "exit": Application.Quit(); break;
            }
        }

        Rect loginOptionsRect = new Rect(-1, 0, 340, 460), loginCreditsRect = new Rect(-1, 0, 560, 520);

        void LoginOptionsGui(float w, float h)
        {
            if (loginOptionsRect.x < 0) loginOptionsRect = new Rect(w / 2 - 170, Mathf.Max(48f, h / 2 - 230), 340, Mathf.Min(460f, h - 60f));
            loginOptionsRect = GUI.Window(MenuWindowId + 15, loginOptionsRect, _ =>
            {
                var r = loginOptionsRect;
                Fill(new Rect(0, 0, r.width, r.height), new Color(0.04f, 0.03f, 0.05f, 0.95f));
                Fill(new Rect(0, 0, r.width, 24), new Color(0.16f, 0.09f, 0.06f, 1f));
                GUI.Label(new Rect(8, 2, r.width - 40, 22), Loc.T("Options"), titleStyle);
                if (GUI.Button(new Rect(r.width - 26, 2, 22, 20), "x")) loginOptions = false;
                var inner = new Rect(4, 28, r.width - 8, r.height - 32);
                float tw = (inner.width - 4) / LoginMenu.OptionPages.Length;
                for (int i = 0; i < LoginMenu.OptionPages.Length; i++)
                    if (GUI.Toggle(new Rect(inner.x + 2 + i * tw, inner.y, tw - 3, 24), loginOptionsPage == i, Loc.T(LoginMenu.OptionPages[i]), GUI.skin.button) && loginOptionsPage != i) loginOptionsPage = i;
                if (loginOptionsPage > 0) VisualOptionsUi.Page(this, loginOptionsPage, inner);
                else
                {
                    float y = inner.y + 30;
                    GUI.Label(new Rect(inner.x + 2, y, inner.width, 20), Loc.T("Language"), titleStyle);
                    y += 22;
                    float bw = (inner.width - 8) / HudOptions.LanguageChoices.Length;
                    for (int i = 0; i < HudOptions.LanguageChoices.Length; i++)
                    {
                        string code = HudOptions.LanguageChoices[i][0];
                        bool sel = Loc.Language == code;
                        if (GUI.Toggle(new Rect(inner.x + i * (bw + 4), y, bw, 26), sel, HudOptions.LanguageChoices[i][1], GUI.skin.button) && !sel)
                        {
                            Loc.Set(code);
                            PlayerPrefs.SetString(HudOptions.PrefLang, code);
                            PlayerPrefs.Save();
                        }
                    }
                    y += 40;
                    var st = new GUIStyle(small) { wordWrap = true, fontSize = 12 };
                    GUI.Label(new Rect(inner.x + 2, y, inner.width - 4, 60), Loc.T("The other options are in the game, once a character is in."), st);
                }
                GUI.DragWindow(new Rect(0, 0, r.width - 30, 24));
            }, GUIContent.none, GUIStyle.none);
        }

        void LoginCreditsGui(float w, float h)
        {
            if (loginCreditsRect.x < 0) loginCreditsRect = new Rect(w / 2 - 280, 48, Mathf.Min(560f, w - 16f), Mathf.Min(520f, h - 60f));
            if (loginCreditRows == null || loginCreditsFor != Loc.Language)
            {
                loginCreditsFor = Loc.Language;
                loginCreditRows = new CreditsPanel().BuildRows();
            }
            loginCreditsRect = GUI.Window(MenuWindowId + 16, loginCreditsRect, _ =>
            {
                var r = loginCreditsRect;
                Fill(new Rect(0, 0, r.width, r.height), new Color(0.04f, 0.03f, 0.05f, 0.95f));
                Fill(new Rect(0, 0, r.width, 24), new Color(0.16f, 0.09f, 0.06f, 1f));
                GUI.Label(new Rect(8, 2, r.width - 40, 22), Loc.T("Credits"), titleStyle);
                if (GUI.Button(new Rect(r.width - 26, 2, 22, 20), "x")) loginCredits = false;
                var view = new Rect(4, 28, r.width - 8, r.height - 32);
                var wrap = new GUIStyle(small) { wordWrap = true, fontSize = 12 };
                float y = 0;
                var heights = new List<float>();
                foreach (var row in loginCreditRows)
                {
                    string text = row.Text + (row.Sub != null && row.Sub.Length > 0 ? "  " + row.Sub : "");
                    float rh = Mathf.Max(18f, wrap.CalcHeight(new GUIContent(text), view.width - 24));
                    heights.Add(rh); y += rh + 2;
                }
                loginCreditsScroll = GUI.BeginScrollView(view, loginCreditsScroll, new Rect(0, 0, view.width - 18, y));
                float cy = 0;
                for (int i = 0; i < loginCreditRows.Count; i++)
                {
                    var row = loginCreditRows[i];
                    string text = row.Text + (row.Sub != null && row.Sub.Length > 0 ? "  " + row.Sub : "");
                    var st = new GUIStyle(wrap);
                    st.normal.textColor = row.Kind == RowKind.Section ? new Color(0.91f, 0.72f, 0.29f) : row.Tone == "dim" ? new Color(0.55f, 0.5f, 0.44f) : new Color(0.84f, 0.79f, 0.68f);
                    GUI.Label(new Rect(4, cy, view.width - 24, heights[i]), text, st);
                    cy += heights[i] + 2;
                }
                GUI.EndScrollView();
                GUI.DragWindow(new Rect(0, 0, r.width - 30, 24));
            }, GUIContent.none, GUIStyle.none);
        }
    }
}
