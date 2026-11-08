// The combat helper (Ctrl+H): heals by health thresholds (spells and potions), mana training, Auto Haste, the five-slot spell rotation
// (the magic shooter), Auto Target by mode A..H, and Auto setup (the class presets of the main client's game_helperrotation).
// The loop is Core/HelperEngine.cs (tested); this window owns the engine, ticks it once per frame whether it is open or not, and edits
// its settings. The settings are saved per character in PlayerPrefs (chaos.helper.<world>/<character>) at every change.
// Pacing is the main client's: 50 ms loop, a rate guard per cast channel, a cast waits for the server's cooldown packet (see HelperEngine.cs).
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class HelperWindow : GameWindow
    {
        enum Pick { None, Heal, Training, Haste, Slot, Potion }

        HelperEngine engine;
        GameSession engineFor;
        string loadedFor;
        int lastFrame = -1, lastHealth = -1;
        bool dirty;
        int tab;
        Pick pick;
        int pickIndex;
        Vector2 scroll;
        string message = "";
        GUIStyle hint, rowName;

        public override string Title => Loc.T("Helper");
        public override KeyCode Hotkey => KeyCode.H;
        protected override Rect Place(float w, float h) => new Rect(w - 392f, 48f, 372f, 470f);

        /// <summary>The running helper (null before the character is in the game).</summary>
        public HelperEngine Engine => engine;

        public override void Reset()
        {
            engine = null; engineFor = null; loadedFor = null; lastHealth = -1; pick = Pick.None; message = ""; dirty = false;
        }

        // ------------------------------------------------------------------------------------ the loop, once per frame
        public override void Tick(ChaosApp app)
        {
            var s = app.Session;
            if (s == null) { engine = null; return; }
            string name = app.World?.Player?.Name;
            if (name == null) return;
            if (engine == null || engineFor != s || loadedFor != name)
            {
                var host = new SessionHelperHost(s);
                engine = new HelperEngine(s.Spells, host);
                engineFor = s; loadedFor = name;
                engine.Config = HelperConfig.FromJson(PlayerPrefs.GetString(HelperConfig.PrefsKey("-", name), ""));
                var e = engine;
                // the server's answers to a cast confirm it (0xA4 / 0xA5); the session's own handlers keep working
                var spellCd = s.Parser.SpellCooldown; var groupCd = s.Parser.GroupCooldown;
                s.Parser.SpellCooldown = (id, ms) => { spellCd(id, ms); e.OnSpellCooldown(id); };
                s.Parser.GroupCooldown = (g, ms) => { groupCd(g, ms); e.OnGroupCooldown(g); };
                lastHealth = -1;
            }
            if (Time.frameCount == lastFrame) return;   // OnGUI runs several times a frame
            lastFrame = Time.frameCount;
            int hp = s.Parser.Health;
            if (lastHealth >= 0 && hp < lastHealth) engine.OnHealthChanged(lastHealth, hp);
            lastHealth = hp;
            engine.Tick();
            if (dirty) { dirty = false; PlayerPrefs.SetString(HelperConfig.PrefsKey("-", loadedFor), engine.Config.ToJson()); PlayerPrefs.Save(); }
        }

        // ------------------------------------------------------------------------------------ drawing
        void Styles(ChaosApp app)
        {
            if (hint != null) return;
            hint = new GUIStyle(app.SmallStyle) { fontSize = 11, wordWrap = true };
            hint.normal.textColor = new Color(1f, 1f, 1f, 0.6f);
            rowName = new GUIStyle(app.SmallStyle) { fontSize = 12, clipping = TextClipping.Clip };
        }

        string SpellName(int id)
        {
            if (id <= 0) return Loc.T("(empty)");
            var sp = engine.Book.ById(id);
            return sp != null ? sp.Name : "#" + id;
        }

        static string PotionName(int id)
        {
            if (id <= 0) return Loc.T("(empty)");
            var p = HelperPotions.Info(id);
            return p != null ? p.Name : "#" + id;
        }

        string StatusText()
        {
            switch (engine.Why)
            {
                case "helperoff": return Loc.T("Helper off");
                case "pz": return Loc.T("Paused: protection zone");
                case "follow": return Loc.T("Paused: following");
                case "freeze": return Loc.T("Paused: waiting for the server");
                default: return Loc.T("Running");
            }
        }

        int Stepper(Rect r, int v, int lo, int hi, int step, string suffix)
        {
            float bw = 24f;
            if (GUI.Button(new Rect(r.x, r.y, bw, r.height), "-")) { v = Mathf.Max(lo, v - step); dirty = true; }
            GUI.Label(new Rect(r.x + bw, r.y + 2, r.width - bw * 2, r.height), v + suffix, new GUIStyle(hint) { alignment = TextAnchor.UpperCenter, fontSize = 12 });
            if (GUI.Button(new Rect(r.xMax - bw, r.y, bw, r.height), "+")) { v = Mathf.Min(hi, v + step); dirty = true; }
            return v;
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            if (engine == null || app.Session == null) return;
            Styles(app);
            ui = app;
            var cfg = engine.Config;
            float x = inner.x + 4, w = inner.width - 8, y = inner.y + 2;

            bool on = GUI.Toggle(new Rect(x, y, 150, 24), cfg.Enabled, Loc.T("Helper on"));
            if (on != cfg.Enabled) { cfg.Enabled = on; dirty = true; }
            GUI.Label(new Rect(x + 150, y + 2, w - 150, 20), StatusText(), new GUIStyle(hint) { alignment = TextAnchor.UpperRight });
            y += 28;

            if (pick != Pick.None) { DrawPicker(x, y, w, inner.yMax - y); return; }

            int t = GUI.Toolbar(new Rect(x, y, w, 24), tab, new[] { Loc.T("Healing"), Loc.T("Shooter"), Loc.T("Target") });
            if (t != tab) { tab = t; message = ""; }
            y += 30;
            if (tab == 0) DrawHealing(x, y, w);
            else if (tab == 1) DrawShooter(x, y, w);
            else DrawTarget(x, y, w);
        }

        // ---- healing ----
        void DrawHealing(float x, float y, float w)
        {
            var cfg = engine.Config;
            GUI.Label(new Rect(x, y, w, 18), Loc.T("Healing spells"), rowName);
            y += 20;
            for (int i = 0; i < cfg.Heals.Count; i++, y += 26)
            {
                var row = cfg.Heals[i];
                if (GUI.Button(new Rect(x, y, w - 130, 24), SpellName(row.Id))) { pick = Pick.Heal; pickIndex = i; scroll = Vector2.zero; }
                row.Percent = Stepper(new Rect(w - 120 + x, y, 120, 24), row.Percent, 0, 99, 5, Loc.T("% health"));
            }
            y += 6;
            GUI.Label(new Rect(x, y, w, 18), Loc.T("Potions"), rowName);
            y += 20;
            for (int i = 0; i < cfg.Potions.Count; i++, y += 26)
            {
                var row = cfg.Potions[i];
                string name = PotionName(row.Id);
                if (row.Id > 0)
                {
                    string kind = HelperPotions.RowKind(row);
                    name += "  (" + engine.Host.ItemCount(row.Id) + ")";
                    if (HelperPotions.Info(row.Id).Kind == "both") name += kind == "mana" ? " " + Loc.T("mana") : " " + Loc.T("health");
                }
                if (GUI.Button(new Rect(x, y, w - 130, 24), name))
                {
                    if (Event.current.button == 1 && row.Id > 0 && HelperPotions.Info(row.Id).Kind == "both") { row.Priority = row.Priority == 2 ? 1 : 2; dirty = true; }
                    else { pick = Pick.Potion; pickIndex = i; scroll = Vector2.zero; }
                }
                string suffix = HelperPotions.RowKind(row) == "mana" ? Loc.T("% mana") : Loc.T("% health");
                row.Percent = Stepper(new Rect(w - 120 + x, y, 120, 24), row.Percent, 0, 99, 5, suffix);
            }
            GUI.Label(new Rect(x, y, w, 30), Loc.T("Right-click a spirit potion row to switch it between health and mana."), hint);
            y += 36;
            var tr = cfg.Training;
            bool te = GUI.Toggle(new Rect(x, y, 110, 24), tr.Enabled, Loc.T("Mana training"));
            if (te != tr.Enabled) { tr.Enabled = te; dirty = true; }
            if (GUI.Button(new Rect(x + 112, y, w - 112 - 130, 24), SpellName(tr.Id))) { pick = Pick.Training; scroll = Vector2.zero; }
            tr.Percent = Stepper(new Rect(w - 120 + x, y, 120, 24), tr.Percent, 50, 100, 10, Loc.T("% mana"));
            y += 30;
            var hs = cfg.Haste;
            bool he = GUI.Toggle(new Rect(x, y, 110, 24), hs.Enabled, Loc.T("Auto haste"));
            if (he != hs.Enabled) { hs.Enabled = he; dirty = true; }
            if (GUI.Button(new Rect(x + 112, y, w - 112 - 130, 24), SpellName(hs.Id))) { pick = Pick.Haste; scroll = Vector2.zero; }
            bool sc = GUI.Toggle(new Rect(w - 120 + x, y, 120, 24), hs.SafeCast, Loc.T("In protection zone"));
            if (sc != hs.SafeCast) { hs.SafeCast = sc; dirty = true; }
        }

        // ---- shooter ----
        void DrawShooter(float x, float y, float w)
        {
            var cfg = engine.Config;
            bool ms = GUI.Toggle(new Rect(x, y, 170, 24), cfg.MagicShooter, Loc.T("Spell rotation"));
            if (ms != cfg.MagicShooter) { cfg.MagicShooter = ms; dirty = true; }
            bool at = GUI.Toggle(new Rect(x + 175, y, w - 175, 24), cfg.AutoTurn, Loc.T("Auto turn"));
            if (at != cfg.AutoTurn) { cfg.AutoTurn = at; dirty = true; }
            y += 30;
            GUI.Label(new Rect(x, y, w, 18), Loc.T("Spells are tried from the top; a slot casts when the mana and the monster count are met."), hint);
            y += 34;
            for (int i = 0; i < cfg.Shooter.Count; i++, y += 28)
            {
                var slot = cfg.Shooter[i];
                if (GUI.Button(new Rect(x, y, w - 214, 24), (i + 1) + ". " + SpellName(slot.Id))) { pick = Pick.Slot; pickIndex = i; scroll = Vector2.zero; }
                slot.Percent = Stepper(new Rect(x + w - 208, y, 100, 24), slot.Percent, 0, 99, 5, Loc.T("% mana"));
                slot.Creatures = Stepper(new Rect(x + w - 104, y, 104, 24), slot.Creatures, 1, HelperConfig.CreaturesMax, 1, "+");
            }
            GUI.Label(new Rect(x, y, w, 18), Loc.T("Mana percent and the number of monsters to cast on."), hint);
            y += 24;
            if (GUI.Button(new Rect(x, y, 150, 28), Loc.T("Auto setup")))
            {
                string m = engine.AutoSetup(Vocation());
                message = m ?? Loc.T("No rotation for this class and level yet (is the spell list loaded?).");
                if (m != null) dirty = true;
            }
            if (GUI.Button(new Rect(x + 156, y, w - 156, 28), Loc.T("Clear slots")))
            {
                for (int i = 0; i < cfg.Shooter.Count; i++) cfg.Shooter[i] = new HelperSlot { Priority = i + 1 };
                dirty = true; message = "";
            }
            y += 34;
            if (message.Length > 0) GUI.Label(new Rect(x, y, w, 60), message, hint);
        }

        ChaosApp ui;
        /// <summary>The server's vocation id: the spell list's header, else the character list's.</summary>
        int Vocation() { return engine.Book.Vocation != 0 ? engine.Book.Vocation : (ui?.World?.PlayerVocation ?? 0); }

        // ---- target ----
        static readonly string[] ModeText =
        {
            "Closest", "Farthest", "Lowest health", "Highest health", "Most monsters around it", "Closest, then lowest health",
            "Closest, then highest health", "Farthest, then lowest health",
        };

        void DrawTarget(float x, float y, float w)
        {
            var cfg = engine.Config;
            bool at = GUI.Toggle(new Rect(x, y, w, 24), cfg.AutoTarget, Loc.T("Auto target"));
            if (at != cfg.AutoTarget) { cfg.AutoTarget = at; dirty = true; if (!at) engine.LockedTarget = 0; }
            y += 30;
            GUI.Label(new Rect(x, y, w, 34), Loc.T("Attacks a monster within 7 x 5 tiles by the rule below and keeps it until it is gone."), hint);
            y += 40;
            for (int i = 0; i < ModeText.Length; i++, y += 28)
            {
                bool sel = cfg.AutoTargetMode == i + 1;
                if (GUI.Toggle(new Rect(x, y, w, 24), sel, HelperLogic.ModeKeys[i] + ": " + Loc.T(ModeText[i]), GUI.skin.button) && !sel) { cfg.AutoTargetMode = i + 1; dirty = true; }
            }
        }

        // ---- the picker ----
        void DrawPicker(float x, float y, float w, float h)
        {
            var cfg = engine.Config;
            if (GUI.Button(new Rect(x, y, 80, 24), Loc.T("Back"))) { pick = Pick.None; return; }
            y += 30;
            var rows = new List<KeyValuePair<int, string>> { new KeyValuePair<int, string>(0, Loc.T("(empty)")) };
            if (pick == Pick.Potion)
            {
                foreach (var p in HelperPotions.List)
                    rows.Add(new KeyValuePair<int, string>(p.Id, p.Name + "  (" + engine.Host.ItemCount(p.Id) + ")  " + (p.Level > 0 ? Loc.T("Level {0}", p.Level) : "")));
            }
            else
            {
                var list = pick == Pick.Slot ? HelperPickers.Attack(engine.Book) : pick == Pick.Haste ? HelperPickers.Haste(engine.Book) : HelperPickers.Healing(engine.Book);
                SpellBook.Sort(list);
                foreach (var s in list) rows.Add(new KeyValuePair<int, string>(s.Id, s.Name + "  (" + Loc.T("Level {0}", s.Level) + ", " + Loc.T("Mana {0}", s.Mana) + ")"));
                if (!engine.Book.Loaded) GUI.Label(new Rect(x, y, w, 20), Loc.T("Loading spells..."), hint);
            }
            const float Row = 26f;
            var view = new Rect(x, y, w, h - 34);
            scroll = GUI.BeginScrollView(view, scroll, new Rect(0, 0, w - 18, rows.Count * Row));
            for (int i = 0; i < rows.Count; i++)
            {
                if (!GUI.Button(new Rect(0, i * Row, w - 18, Row - 2), rows[i].Value)) continue;
                int id = rows[i].Key;
                switch (pick)
                {
                    case Pick.Heal: cfg.Heals[pickIndex].Id = id; break;
                    case Pick.Potion: cfg.Potions[pickIndex].Id = id; break;
                    case Pick.Training: cfg.Training.Id = id; break;
                    case Pick.Haste: cfg.Haste.Id = id; break;
                    case Pick.Slot: cfg.Shooter[pickIndex].Id = id; break;
                }
                dirty = true;
                pick = Pick.None;
                break;
            }
            GUI.EndScrollView();
        }
    }
}
