// The helper window's extra tabs (track Q): Runes (healing runes on yourself, attack runes on the target), Allies (party and friend heals),
// Support (the support spells the helper keeps up), More (food, the bot HUD, the carried Everfull flasks) and the shooter presets bar.
// The rules are Core/HelperExtras.cs and Core/HelperSupport.cs; this file only draws and edits the settings.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class HelperWindow
    {
        enum ExtraPick { None, RuneHeal, RuneAttack, AllyRune, AllySpell, AllyGroup, SupportAdd }

        ExtraPick extraPick;
        int extraIndex;
        string presetName = "";
        string presetKey = "";   // phase 8 track A: the key that cycles the presets (HelperPresetKey), "" none
        bool settingPresetKey;
        readonly string[] nameEdit = { null, null, null, null, null };
        Vector2 supportScroll;

        string RuneName(int id)
        {
            if (id <= 0) return Loc.T("(empty)");
            var r = HelperRunes.Info(id);
            return r != null ? Loc.T(r.Name) : "#" + id;
        }

        // ------------------------------------------------------------------------------------ shooter presets
        float DrawProfiles(float x, float y, float w)
        {
            var cfg = engine.Config;
            var names = HelperProfiles.Names(cfg);
            GUI.Label(new Rect(x, y + 3, 60, 20), Loc.T("Preset"), rowName);
            if (GUI.Button(new Rect(x + 56, y, 24, 24), "<")) { cfg.SelectProfile(Neighbour(names, cfg.SelectedProfile, -1)); dirty = true; }
            GUI.Label(new Rect(x + 82, y + 3, 130, 20), cfg.SelectedProfile, new GUIStyle(rowName) { alignment = TextAnchor.UpperCenter });
            if (GUI.Button(new Rect(x + 214, y, 24, 24), ">")) { cfg.SelectProfile(Neighbour(names, cfg.SelectedProfile, 1)); dirty = true; }
            presetName = GUI.TextField(new Rect(x + 244, y, 92, 24), presetName, HelperProfiles.NameMax);
            if (GUI.Button(new Rect(x + 340, y, w - 340, 24), Loc.T("New")))
            {
                string why = cfg.AddProfile(presetName.Trim(), false);
                message = why != null ? Loc.T(why) : Loc.T("Preset made.");
                if (why == null) { presetName = ""; dirty = true; }
            }
            y += 28;
            if (GUI.Button(new Rect(x + 56, y, 80, 22), Loc.T("Copy")))
            {
                string why = cfg.AddProfile(presetName.Trim(), true);
                message = why != null ? Loc.T(why) : Loc.T("Preset made.");
                if (why == null) { presetName = ""; dirty = true; }
            }
            if (GUI.Button(new Rect(x + 140, y, 80, 22), Loc.T("Rename")))
            {
                string why = cfg.RenameProfile(presetName.Trim());
                message = why != null ? Loc.T(why) : Loc.T("Preset renamed.");
                if (why == null) { presetName = ""; dirty = true; }
            }
            if (GUI.Button(new Rect(x + 224, y, 80, 22), Loc.T("Delete")))
            {
                message = cfg.DeleteProfile() ? Loc.T("Preset deleted.") : Loc.T("The last preset stays.");
                dirty = true;
            }
            // the preset key (helper.lua toggleShooterPreset on a hotkey): one press goes to the next preset; no default key
            string keyLabel = settingPresetKey ? Loc.T("Press a key...") : Loc.T("Key: {0}", HelperPresetKey.Label(presetKey));
            if (GUI.Button(new Rect(x + 308, y, Mathf.Max(60f, w - 308f), 22), keyLabel)) { settingPresetKey = !settingPresetKey; }
            if (settingPresetKey) CapturePresetKey();
            return 56f;
        }

        /// <summary>While the button waits for a key: the next key press is the preset key (Escape cancels, Backspace clears it).</summary>
        void CapturePresetKey()
        {
            var e = Event.current;
            if (e.type != EventType.KeyDown || e.keyCode == KeyCode.None) return;
            if (e.keyCode == KeyCode.Escape) { settingPresetKey = false; e.Use(); return; }
            if (e.keyCode == KeyCode.Backspace) { SavePresetKey(""); settingPresetKey = false; e.Use(); return; }
            string name = e.keyCode.ToString();
            if (!HelperPresetKey.Valid(name)) { message = Loc.T("That key is used by the game."); e.Use(); return; }
            SavePresetKey(name);
            settingPresetKey = false;
            e.Use();
        }

        void SavePresetKey(string name)
        {
            presetKey = name;
            if (loadedFor == null) return;
            PlayerPrefs.SetString(HelperPresetKey.PrefKey(loadedFor), name);
            PlayerPrefs.Save();
        }

        /// <summary>Once per frame: the preset key cycles to the next preset and tells which (the main client's "Preset: Name").</summary>
        void PresetKeyTick(ChaosApp app)
        {
            if (presetKey.Length == 0 || engine == null || app.TypingNow || settingPresetKey) return;
            if (!System.Enum.TryParse(presetKey, out KeyCode code) || !Input.GetKeyDown(code)) return;
            string msg = HelperPresetKey.Cycle(engine.Config);
            if (msg == null) return;
            dirty = true;
            app.PostLine(msg);
        }

        static string Neighbour(List<string> names, string current, int step)
        {
            int i = names.IndexOf(current);
            if (i < 0) return names[0];
            return names[((i + step) % names.Count + names.Count) % names.Count];
        }

        // ------------------------------------------------------------------------------------ the tabs
        void DrawExtras(float x, float y, float w, float h)
        {
            if (tab == 3) DrawRunes(x, y, w);
            else if (tab == 4) DrawAllies(x, y, w);
            else if (tab == 5) DrawSupport(x, y, w, h);
            else if (tab == 7) DrawFollowSell(x, y, w);   // phase 7 track X: HelperWindowP7.cs
            else DrawMore(x, y, w);
        }

        void DrawRunes(float x, float y, float w)
        {
            var cfg = engine.Config;
            GUI.Label(new Rect(x, y, w, 18), Loc.T("Healing runes (on yourself)"), rowName);
            y += 20;
            for (int i = 0; i < cfg.RuneHeal.Count; i++, y += 26)
            {
                var row = cfg.RuneHeal[i];
                string name = RuneName(row.Id) + (row.Id > 0 ? "  (" + engine.Host.ItemCount(row.Id) + ")" : "");
                if (GUI.Button(new Rect(x, y, w - 130, 24), name)) { extraPick = ExtraPick.RuneHeal; extraIndex = i; scroll = Vector2.zero; }
                row.Percent = Stepper(new Rect(x + w - 120, y, 120, 24), row.Percent, 1, 99, 5, Loc.T("% health"));
            }
            y += 8;
            GUI.Label(new Rect(x, y, w, 18), Loc.T("Attack runes (on the target, with the spell rotation on)"), rowName);
            y += 20;
            for (int i = 0; i < cfg.RuneAttack.Count; i++, y += 56)
            {
                var row = cfg.RuneAttack[i];
                string name = RuneName(row.Id) + (row.Id > 0 ? "  (" + engine.Host.ItemCount(row.Id) + ")" : "");
                if (GUI.Button(new Rect(x, y, w - 110, 24), (i + 1) + ". " + name)) { extraPick = ExtraPick.RuneAttack; extraIndex = i; scroll = Vector2.zero; }
                row.Creatures = Stepper(new Rect(x + w - 104, y, 104, 24), row.Creatures, 1, HelperConfig.CreaturesMax, 1, "+");
                row.HpMin = Stepper(new Rect(x, y + 26, (w - 8) / 2, 24), row.HpMin, 0, 100, 10, Loc.T("% from"));
                row.HpMax = Stepper(new Rect(x + (w + 8) / 2, y + 26, (w - 8) / 2, 24), row.HpMax, 0, 100, 10, Loc.T("% up to"));
            }
            GUI.Label(new Rect(x, y, w, 50), Loc.T("A rune is used when the monsters in its area reach the count and the target's health fits. 0% up to means no limit. Runes must be in your equipment or an open bag. Each kind of rune waits a second."), hint);
        }

        void DrawAllies(float x, float y, float w)
        {
            var cfg = engine.Config;
            var a = cfg.Allies;
            bool pe = GUI.Toggle(new Rect(x, y, 130, 24), a.PartyEnabled, Loc.T("Heal the party"));
            if (pe != a.PartyEnabled) { a.PartyEnabled = pe; dirty = true; }
            a.PartyPercent = Stepper(new Rect(x + w - 120, y, 120, 24), a.PartyPercent, 5, 95, 5, Loc.T("% health"));
            y += 28;
            bool fe = GUI.Toggle(new Rect(x, y, 130, 24), a.FriendsEnabled, Loc.T("Heal friends"));
            if (fe != a.FriendsEnabled) { a.FriendsEnabled = fe; dirty = true; }
            a.FriendsPercent = Stepper(new Rect(x + w - 120, y, 120, 24), a.FriendsPercent, 5, 95, 5, Loc.T("% health"));
            y += 28;
            for (int i = 0; i < HelperAllies.Names; i++, y += 24)
            {
                if (nameEdit[i] == null) nameEdit[i] = a.FriendNames[i];
                string t = GUI.TextField(new Rect(x + 20, y, w - 20, 22), nameEdit[i], HelperAlly.NameMax);
                if (t != nameEdit[i])
                {
                    nameEdit[i] = t;
                    string clean = HelperAlly.CleanName(t) ?? "";
                    if (clean != a.FriendNames[i]) { a.FriendNames[i] = clean; dirty = true; }
                }
                GUI.Label(new Rect(x, y + 2, 20, 20), (i + 1) + ".", hint);
            }
            y += 6;
            GUI.Label(new Rect(x, y, 120, 20), Loc.T("Single spell"), rowName);
            if (GUI.Button(new Rect(x + 120, y - 2, w - 120, 24), SpellName(a.Spell))) { extraPick = ExtraPick.AllySpell; scroll = Vector2.zero; }
            y += 28;
            GUI.Label(new Rect(x, y, 120, 20), Loc.T("Group spell"), rowName);
            if (GUI.Button(new Rect(x + 120, y - 2, w - 120 - 96, 24), SpellName(a.GroupId))) { extraPick = ExtraPick.AllyGroup; scroll = Vector2.zero; }
            a.GroupCount = Stepper(new Rect(x + w - 92, y - 2, 92, 24), a.GroupCount, 1, HelperAllies.GroupCountMax, 1, "+");
            y += 28;
            GUI.Label(new Rect(x, y, 120, 20), Loc.T("Healing rune"), rowName);
            if (GUI.Button(new Rect(x + 120, y - 2, w - 120, 24), RuneName(a.RuneId))) { extraPick = ExtraPick.AllyRune; scroll = Vector2.zero; }
            y += 30;
            GUI.Label(new Rect(x, y, w, 60), Loc.T("Your own healing comes first. Only players in the helper's 7 x 5 window are healed, a protection zone pauses it, and each player gets a heal at most every 1.2 seconds."), hint);
        }

        void DrawSupport(float x, float y, float w, float h)
        {
            var sup = engine.Config.Support;
            bool en = GUI.Toggle(new Rect(x, y, 150, 24), sup.Enabled, Loc.T("Support on"));
            if (en != sup.Enabled) { sup.Enabled = en; dirty = true; }
            GUI.Label(new Rect(x + 150, y + 2, w - 150, 20), HelperSupport.ReasonText(engine.SupportWhy), new GUIStyle(hint) { alignment = TextAnchor.UpperRight });
            y += 28;
            int ri = System.Array.IndexOf(HelperSupport.Reserves, sup.Reserve);
            int nr = Stepper(new Rect(x + w - 190, y, 190, 24), ri < 0 ? 2 : ri, 0, HelperSupport.Reserves.Length - 1, 1, "");
            if (nr != ri) { sup.Reserve = HelperSupport.Reserves[nr]; dirty = true; }
            GUI.Label(new Rect(x, y + 2, w - 190, 20), Loc.T("Mana kept after a cast: {0}%", sup.Reserve), hint);
            y += 30;
            var view = new Rect(x, y, w, h - 120);
            float timerH = sup.Timers.Count > 0 ? 24f + sup.Timers.Count * 28f : 0f;
            supportScroll = GUI.BeginScrollView(view, supportScroll, new Rect(0, 0, w - 18, Mathf.Max(sup.Slots.Count * 28f + timerH, 10f)));
            for (int i = 0; i < sup.Slots.Count; i++)
            {
                var slot = sup.Slots[i];
                float ry = i * 28f;
                bool on = GUI.Toggle(new Rect(0, ry, 20, 24), slot.Enabled, GUIContent.none);
                if (on != slot.Enabled) { slot.Enabled = on; dirty = true; }
                GUI.Label(new Rect(22, ry + 2, w - 18 - 22 - 150, 20), SpellName(slot.Id), rowName);
                string why;
                engine.SupportRun.Status.TryGetValue(slot.Id, out why);
                GUI.Label(new Rect(w - 18 - 150, ry + 2, 90, 20), HelperSupport.ReasonText(why), hint);
                if (GUI.Button(new Rect(w - 18 - 56, ry, 26, 24), "^") && i > 0) { sup.Slots.RemoveAt(i); sup.Slots.Insert(i - 1, slot); dirty = true; break; }
                if (GUI.Button(new Rect(w - 18 - 28, ry, 26, 24), "x")) { sup.Slots.RemoveAt(i); dirty = true; break; }
            }
            if (sup.Timers.Count > 0)
            {
                float ty = sup.Slots.Count * 28f + 4;
                GUI.Label(new Rect(0, ty, w - 18, 20), Loc.T("Timer rules: cast every N seconds while you attack a monster"), hint);
                ty += 20;
                for (int i = 0; i < sup.Timers.Count; i++)
                {
                    var r = sup.Timers[i];
                    float ry = ty + i * 28f;
                    bool on = GUI.Toggle(new Rect(0, ry, 20, 24), r.Enabled, GUIContent.none);
                    if (on != r.Enabled) { r.Enabled = on; dirty = true; }
                    GUI.Label(new Rect(22, ry + 2, w - 18 - 22 - 90, 20), r.Name.Length > 0 ? r.Name : r.Words, rowName);
                    GUI.Label(new Rect(w - 18 - 90, ry + 2, 62, 20), Loc.T("{0} s", r.Cooldown), hint);
                    if (GUI.Button(new Rect(w - 18 - 28, ry, 26, 24), "x")) { sup.Timers.RemoveAt(i); dirty = true; break; }
                }
            }
            GUI.EndScrollView();
            y += h - 120 + 4;
            if (sup.Slots.Count < HelperSupport.SupportMax && GUI.Button(new Rect(x, y, 110, 26), Loc.T("Add spell"))) { extraPick = ExtraPick.SupportAdd; scroll = Vector2.zero; }
            if (GUI.Button(new Rect(x + 116, y, w - 116, 26), Loc.T("Fill from my class")))
            {
                int n = engine.AutoSupport(true);
                message = n > 0 ? Loc.T("{0} support spells set.", n) : Loc.T("No support spells for this class and level yet (is the spell list loaded?).");
                if (n > 0) dirty = true;
            }
            GUI.Label(new Rect(x, y + 30, w, 36), Loc.T("Spells are cast when off cooldown and while their effect is not on. Fight buffs wait for a monster."), hint);
        }

        void DrawMore(float x, float y, float w)
        {
            var cfg = engine.Config;
            bool eat = GUI.Toggle(new Rect(x, y, w, 24), cfg.AutoEat, Loc.T("Auto eat food"));
            if (eat != cfg.AutoEat) { cfg.AutoEat = eat; dirty = true; }
            y += 26;
            GUI.Label(new Rect(x, y, w, 30), Loc.T("Eats a carried food every two minutes. Food must be in your equipment or an open bag."), hint);
            y += 38;
            var hud = cfg.Hud;
            bool he = GUI.Toggle(new Rect(x, y, 170, 24), hud.Enabled, Loc.T("Show Bot HUD"));
            if (he != hud.Enabled) { hud.Enabled = he; dirty = true; }
            if (GUI.Button(new Rect(x + 176, y, w - 176, 24), Loc.T("Size: {0}", Loc.T(hud.Size))))
            {
                int i = System.Array.IndexOf(HelperHud.Sizes, hud.Size);
                hud.Size = HelperHud.Sizes[(i + 1) % HelperHud.Sizes.Length];
                dirty = true;
            }
            y += 28;
            bool a = GUI.Toggle(new Rect(x, y, w / 2, 22), hud.ShowTargeting, Loc.T("Combat")); if (a != hud.ShowTargeting) { hud.ShowTargeting = a; dirty = true; }
            bool b = GUI.Toggle(new Rect(x + w / 2, y, w / 2, 22), hud.ShowHealing, Loc.T("Healing")); if (b != hud.ShowHealing) { hud.ShowHealing = b; dirty = true; }
            y += 24;
            bool c = GUI.Toggle(new Rect(x, y, w / 2, 22), hud.ShowHaste, Loc.T("Support")); if (c != hud.ShowHaste) { hud.ShowHaste = c; dirty = true; }
            bool d = GUI.Toggle(new Rect(x + w / 2, y, w / 2, 22), hud.ShowPlayer, Loc.T("Player")); if (d != hud.ShowPlayer) { hud.ShowPlayer = d; dirty = true; }
            y += 34;
            GUI.Label(new Rect(x, y, w, 18), Loc.T("Everfull flasks carried"), rowName);
            y += 20;
            var held = engine.Held;
            string hs = held == null || !held.Received ? Loc.T("Waiting for the server...") : HeldText(held);
            GUI.Label(new Rect(x, y, w, 40), hs, hint);
            y += 36;
            GUI.Label(new Rect(x, y, w, 50), Loc.T("A health or mana potion row on the stock potion drinks the Everfull flask you carry in that slot."), hint);
            if (message.Length > 0) GUI.Label(new Rect(x, y + 50, w, 40), message, hint);
        }

        static string HeldText(EverfullHeld held)
        {
            string h = held.Health != null ? (HelperPotions.Info(held.Health.Look)?.Name ?? "#" + held.Health.Look) : Loc.T("none");
            string m = held.Mana != null ? (HelperPotions.Info(held.Mana.Look)?.Name ?? "#" + held.Mana.Look) : Loc.T("none");
            return Loc.T("Health slot: {0}", h) + "\n" + Loc.T("Mana slot: {0}", m);
        }

        // ------------------------------------------------------------------------------------ the picker of the extra tabs
        void DrawExtraPicker(float x, float y, float w, float h)
        {
            var cfg = engine.Config;
            if (GUI.Button(new Rect(x, y, 80, 24), Loc.T("Back"))) { extraPick = ExtraPick.None; return; }
            y += 30;
            var rows = new List<KeyValuePair<int, string>>();
            if (extraPick != ExtraPick.SupportAdd) rows.Add(new KeyValuePair<int, string>(0, Loc.T("(empty)")));
            int vocation = Vocation();
            switch (extraPick)
            {
                case ExtraPick.RuneHeal:
                case ExtraPick.AllyRune:
                    foreach (var r in HelperRunes.Offered("heal", vocation)) rows.Add(new KeyValuePair<int, string>(r.Id, Loc.T(r.Name) + "  (" + engine.Host.ItemCount(r.Id) + ")"));
                    break;
                case ExtraPick.RuneAttack:
                    foreach (var r in HelperRunes.Offered("attack", vocation)) rows.Add(new KeyValuePair<int, string>(r.Id, Loc.T(r.Name) + "  (" + engine.Host.ItemCount(r.Id) + ")"));
                    break;
                case ExtraPick.AllySpell:
                case ExtraPick.AllyGroup:
                    {
                        var list = HelperAlly.Offered(extraPick == ExtraPick.AllySpell ? HelperAlly.Single : HelperAlly.Group, engine.Book.ById, s => engine.CanCast(s.Id), vocation);
                        foreach (var kv in list) rows.Add(new KeyValuePair<int, string>(kv.Key.Id, kv.Key.Name + "  (" + Loc.T("Level {0}", kv.Key.Level) + ")"));
                        if (!engine.Book.Loaded) GUI.Label(new Rect(x, y, w, 20), Loc.T("Loading spells..."), hint);
                        break;
                    }
                case ExtraPick.SupportAdd:
                    {
                        var have = new HashSet<int>();
                        foreach (var s in cfg.Support.Slots) have.Add(s.Id);
                        foreach (var c in HelperSupport.Candidates(engine.Book.Spells, id => engine.CanCast(id)))
                            if (!have.Contains(c.Spell.Id)) rows.Add(new KeyValuePair<int, string>(c.Spell.Id, c.Spell.Name + "  (" + Loc.T("Level {0}", c.Spell.Level) + ")"));
                        if (!engine.Book.Loaded) GUI.Label(new Rect(x, y, w, 20), Loc.T("Loading spells..."), hint);
                        break;
                    }
            }
            const float Row = 26f;
            var view = new Rect(x, y, w, h - 34);
            scroll = GUI.BeginScrollView(view, scroll, new Rect(0, 0, w - 18, rows.Count * Row));
            for (int i = 0; i < rows.Count; i++)
            {
                if (!GUI.Button(new Rect(0, i * Row, w - 18, Row - 2), rows[i].Value)) continue;
                int id = rows[i].Key;
                switch (extraPick)
                {
                    case ExtraPick.RuneHeal: cfg.RuneHeal[extraIndex].Id = id; break;
                    case ExtraPick.RuneAttack: cfg.RuneAttack[extraIndex].Id = id; break;
                    case ExtraPick.AllyRune: cfg.Allies.RuneId = id; break;
                    case ExtraPick.AllySpell: cfg.Allies.Spell = id; break;
                    case ExtraPick.AllyGroup: cfg.Allies.GroupId = id; break;
                    case ExtraPick.SupportAdd: if (cfg.Support.Slots.Count < HelperSupport.SupportMax) cfg.Support.Slots.Add(new SupportSlot { Id = id }); break;
                }
                dirty = true;
                extraPick = ExtraPick.None;
                break;
            }
            GUI.EndScrollView();
        }
    }

    /// <summary>The helper's bot HUD (game_helperhud): a small movable window with one row per ticked section (combat, healing, support, player). Opens
    /// by itself while "Show Bot HUD" is on in the helper window, and is not in the Windows list.</summary>
    public sealed class HelperHudWindow : GameWindow
    {
        public override bool Resizable => false;   // sets its own size (phase 9, track E)
        HelperWindow helper;
        GUIStyle small;

        public override string Title => Loc.T("Bot HUD");
        public override bool InMenu => false;
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 150f, 50f, 300f, 60f);

        public override void Tick(ChaosApp app)
        {
            if (helper == null) helper = app.FindWindow<HelperWindow>();
            var e = helper != null ? helper.Engine : null;
            Open = e != null && app.Session != null && e.Config.Hud.Enabled;
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var e = helper != null ? helper.Engine : null;
            if (e == null || app.Session == null) return;
            if (small == null) small = new GUIStyle(app.SmallStyle) { fontSize = 12, clipping = TextClipping.Clip };
            var p = app.Session.Parser;
            string target = "";
            if (e.Host.AttackTarget != 0 && app.World != null && app.World.Creatures.TryGetValue(e.Host.AttackTarget, out var c)) target = c.Name;
            var rows = HelperHud.Entries(e.Config, target, id => { var s = e.Book.ById(id); return s != null ? s.Name : null; }, p.Health, p.MaxHealth, p.Mana, p.MaxMana, p.Level);
            var shape = HelperHud.Layout(e.Config.Hud.Size, rows.Count);
            int active = HelperHud.ActiveCount(rows);
            Area.width = Mathf.Min(shape.Width, 680f);
            Area.height = 24f + 22f + shape.CardHeight + 8f;
            float y = inner.y;
            var dot = active > 0 ? new Color(0.27f, 0.68f, 0.15f) : new Color(0.44f, 0.44f, 0.44f);
            ChaosApp.Fill(new Rect(inner.x + 4, y + 5, 8, 8), dot);
            var tint = GUI.color;
            GUI.color = dot;
            GUI.Label(new Rect(inner.x + 18, y, inner.width - 20, 18), active > 0 ? Loc.T("Active: {0} modules", active) : Loc.T("Standby"), small);
            GUI.color = tint;
            y += 20;
            int per = shape.RowsPerColumn;
            for (int col = 0; col < (shape.TwoColumns ? 2 : 1); col++)
            {
                float cx = inner.x + 2 + col * (shape.CardWidth + 6);
                ChaosApp.Fill(new Rect(cx, y, shape.CardWidth, shape.CardHeight), new Color(1f, 1f, 1f, 0.06f));
                for (int i = 0; i < per; i++)
                {
                    int idx = col * per + i;
                    if (idx >= rows.Count) break;
                    var r = rows[idx];
                    float ry = y + 4 + i * (HelperHud.RowHeight + HelperHud.RowSpacing);
                    GUI.color = r.Active ? new Color(0.91f, 0.91f, 0.91f) : new Color(0.49f, 0.45f, 0.44f);
                    GUI.Label(new Rect(cx + 6, ry, 70, 15), r.Name, small);
                    GUI.color = r.Active ? new Color(0.85f, 0.78f, 0.66f) : new Color(0.43f, 0.40f, 0.38f);
                    GUI.Label(new Rect(cx + 78, ry, shape.CardWidth - 84, 15), r.Value, small);
                    GUI.color = tint;
                }
            }
        }
    }
}
