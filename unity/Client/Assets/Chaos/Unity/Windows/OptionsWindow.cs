// Options (Ctrl+U): the language of the client and of the server's texts (client_chaos_locale; PlayerPrefs chaos.lang, hello on
// opcode 157), keep attacking while moving (opcode 186), right-click equips items (opcode 188), the display scale the server
// reports (opcode 157, read only: the server scales its numbers) and the buff bar. The choices are saved in PlayerPrefs and
// told to the server at every login (GameSession.Poll -> HudState.Hello) and at every change.
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class OptionsWindow : GameWindow
    {
        bool loaded;
        int page;   // 0 General, then the pages of VisualOptionsUi (sound, visuals, layout)

        public override string Title => Loc.T("Options");
        public override KeyCode Hotkey => KeyCode.L;
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 170, Mathf.Max(8f, h / 2 - 250), 340, 500);
        public override void Reset() { loaded = false; }

        public override void Tick(ChaosApp app)
        {
            var hud = app.Session?.Hud;
            if (hud == null || loaded) return;
            loaded = true;
            hud.Options.KeepAttacking = PlayerPrefs.GetInt(HudOptions.PrefKite, 1) == 1;
            hud.Options.RightClickEquips = PlayerPrefs.GetInt(HudOptions.PrefEquip, 1) == 1;
            hud.Buffs.Shown = PlayerPrefs.GetInt("chaos.buffbar.shown", 1) == 1;
            hud.Buffs.Timers = PlayerPrefs.GetInt("chaos.buffbar.timers", 1) == 1;
        }

        string scatterFor;

        // the damage number scatter of the character: on or off and the strength (kept per character)
        void ScatterRows(ChaosApp app, Rect inner, ref float y)
        {
            string key = ScatterPrefs.Key(app.World?.Player?.Name);
            if (key != null && key != scatterFor) { scatterFor = key; ScatterPrefs.Current = ScatterPrefs.Read(PlayerPrefs.GetString(key, "")); }
            var cur = ScatterPrefs.Current;
            bool on = GUI.Toggle(new Rect(inner.x + 2, y, inner.width - 4, 22), cur.Enabled, Loc.T("Spread the damage numbers"));
            y += 24;
            int level = cur.Level;
            GUI.enabled = on;
            float bw = (inner.width - 8) / DamageScatter.Levels;
            for (int i = 1; i <= DamageScatter.Levels; i++)
                if (GUI.Toggle(new Rect(inner.x + 2 + (i - 1) * (bw + 2), y, bw, 22), level == i, ScatterPrefs.LevelName(i), GUI.skin.button) && level != i) level = i;
            GUI.enabled = true;
            y += 28;
            if (on != cur.Enabled || level != cur.Level)
            {
                ScatterPrefs.Current = new ScatterSettings { Enabled = on, Level = level };
                if (key != null) { PlayerPrefs.SetString(key, ScatterPrefs.Write(ScatterPrefs.Current)); PlayerPrefs.Save(); }
            }
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var hud = app.Session?.Hud;
            if (hud == null) return;
            var o = hud.Options;
            // the pages: General (below), Sound, Visuals and Layout (Windows/VisualWindows.cs)
            float tw = (inner.width - 4) / VisualOptionsUi.Pages.Length;
            for (int i = 0; i < VisualOptionsUi.Pages.Length; i++)
                if (GUI.Toggle(new Rect(inner.x + 2 + i * tw, inner.y, tw - 3, 24), page == i, Loc.T(VisualOptionsUi.Pages[i]), GUI.skin.button) && page != i) page = i;
            if (page > 0) { VisualOptionsUi.Page(app, page, inner); return; }
            float y = inner.y + 30;
            GUI.Label(new Rect(inner.x + 2, y, inner.width, 20), Loc.T("Language"), app.TitleStyle);
            y += 22;
            float bw = (inner.width - 8) / HudOptions.LanguageChoices.Length;
            for (int i = 0; i < HudOptions.LanguageChoices.Length; i++)
            {
                string code = HudOptions.LanguageChoices[i][0];
                bool on = Loc.Language == code;
                if (GUI.Toggle(new Rect(inner.x + i * (bw + 4), y, bw, 26), on, HudOptions.LanguageChoices[i][1], GUI.skin.button) && !on)
                {
                    Loc.Set(code);
                    PlayerPrefs.SetString(HudOptions.PrefLang, code);
                    PlayerPrefs.Save();
                    o.SendHello(code);   // the server writes its texts in this language too
                }
            }
            y += 36;
            bool kite = GUI.Toggle(new Rect(inner.x + 2, y, inner.width - 4, 22), o.KeepAttacking, Loc.T("Keep attacking while moving"));
            if (kite != o.KeepAttacking) { o.SetKeepAttacking(kite); PlayerPrefs.SetInt(HudOptions.PrefKite, kite ? 1 : 0); }
            y += 26;
            bool equip = GUI.Toggle(new Rect(inner.x + 2, y, inner.width - 4, 22), o.RightClickEquips, Loc.T("Right-click equips items"));
            if (equip != o.RightClickEquips) { o.SetRightClickEquips(equip); PlayerPrefs.SetInt(HudOptions.PrefEquip, equip ? 1 : 0); }
            y += 26;
            bool buffs = GUI.Toggle(new Rect(inner.x + 2, y, inner.width - 4, 22), hud.Buffs.Shown, Loc.T("Show the buff bar"));
            if (buffs != hud.Buffs.Shown)
            {
                hud.Buffs.Shown = buffs;
                PlayerPrefs.SetInt("chaos.buffbar.shown", buffs ? 1 : 0);
                if (buffs) hud.Buffs.Sync();
            }
            y += 26;
            bool timers = GUI.Toggle(new Rect(inner.x + 2, y, inner.width - 4, 22), hud.Buffs.Timers, Loc.T("Buff timers"));
            if (timers != hud.Buffs.Timers) { hud.Buffs.Timers = timers; PlayerPrefs.SetInt("chaos.buffbar.timers", timers ? 1 : 0); }
            y += 28;
            ScatterRows(app, inner, ref y);
            GUI.Label(new Rect(inner.x + 2, y, inner.width - 4, 20), Loc.T("Display scale: x{0}", o.ScaleFactor), app.SmallStyle);
            y += 26;
            if (GUI.Button(new Rect(inner.x + 2, y, inner.width - 4, 26), Loc.T("Report a player...")))
            {
                var target = app.World?.Creatures != null && app.Session.AttackTarget != 0 && app.World.Creatures.TryGetValue(app.Session.AttackTarget, out var c) && c.Type == 0 ? c.Name : "";
                app.OpenReport(target);
            }
        }
    }
}
