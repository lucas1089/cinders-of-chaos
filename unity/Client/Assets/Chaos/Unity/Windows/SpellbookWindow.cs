// Spellbook (Ctrl+P): the server's spell list (opcode 219, Core/Spells.cs) with the filters of the main client's
// game_spellbook (learned, available soon, my vocation, all, runes; all / attack / support; search). A click casts
// (says the words), a right-click selects and shows the F1 to F12 buttons that put the spell on a hotkey slot, cooldowns
// (0xA4 / 0xA5) count down on the row. Texts go through Loc.T (English and pt-BR).
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class SpellbookWindow : GameWindow
    {
        static readonly string[] FilterKeys = { SpellBook.FilterLearned, SpellBook.FilterSoon, SpellBook.FilterVocation, SpellBook.FilterAll, SpellBook.FilterRunes };
        static readonly string[] KindKeys = { "all", "attack", "support" };
        const float Row = 34f;

        SpellBook hooked;
        bool wasOpen;
        int filter, kind;
        string search = "";
        Vector2 scroll;
        Spell selected;
        string loadedFor;
        GUIStyle nameStyle, wordsStyle, rightStyle, hintStyle;
        List<Spell> visible = new List<Spell>();
        string visibleKey;

        /// <summary>The hotkey slot (0..11) a spell is being picked for, -1 when none. The hotkey bar sets it.</summary>
        public int PickFor = -1;

        public override string Title => Loc.T("Spells");
        public override KeyCode Hotkey => KeyCode.P;

        protected override Rect Place(float w, float h) => new Rect(12f, 48f, 340f, 440f);

        public override void Reset()
        {
            hooked = null;
            selected = null;
            loadedFor = null;
            wasOpen = false;
            PickFor = -1;
            visibleKey = null;
        }

        static string PrefKey(string character) => "chaos.spellfilter." + character;

        public override void Tick(ChaosApp app)
        {
            var book = app.Session?.Spells;
            if (book == null) return;
            if (hooked != book)
            {
                hooked = book;
                book.ShowRequested += () => { Open = true; };
                book.Changed += () => visibleKey = null;
            }
            string name = app.World?.Player?.Name;
            if (name != null && name != loadedFor)
            {
                loadedFor = name;
                int saved = System.Array.IndexOf(FilterKeys, PlayerPrefs.GetString(PrefKey(name), SpellBook.FilterLearned));
                filter = saved < 0 ? 0 : saved;
                visibleKey = null;
            }
            if (Open && !wasOpen) book.Open();   // the server answers "unchanged" (two small messages) or sends the list
            wasOpen = Open;
        }

        void Styles(ChaosApp app)
        {
            if (nameStyle != null) return;
            nameStyle = new GUIStyle(app.SmallStyle) { fontSize = 12, clipping = TextClipping.Clip };
            wordsStyle = new GUIStyle(app.SmallStyle) { fontSize = 10, clipping = TextClipping.Clip };
            wordsStyle.normal.textColor = new Color(1f, 1f, 1f, 0.55f);
            rightStyle = new GUIStyle(app.SmallStyle) { fontSize = 11, alignment = TextAnchor.UpperRight };
            hintStyle = new GUIStyle(app.SmallStyle) { fontSize = 11, wordWrap = true };
            hintStyle.normal.textColor = new Color(1f, 1f, 1f, 0.6f);
        }

        static Color ElementColor(string element)
        {
            switch ((element ?? "").ToLowerInvariant())
            {
                case "fire": return new Color(0.91f, 0.35f, 0.16f);
                case "ice": return new Color(0.5f, 0.83f, 0.94f);
                case "energy": return new Color(0.69f, 0.44f, 1f);
                case "earth": return new Color(0.37f, 0.75f, 0.23f);
                case "holy": return new Color(0.96f, 0.89f, 0.48f);
                case "death": return new Color(0.54f, 0.23f, 0.62f);
                case "healing": return new Color(0.31f, 0.82f, 0.5f);
                case "physical": return new Color(0.69f, 0.63f, 0.56f);
                default: return new Color(0.72f, 0.09f, 0.06f);
            }
        }

        string StatusText(SpellStatus st)
        {
            switch (st)
            {
                case SpellStatus.Vocation: return Loc.T("Wrong vocation");
                case SpellStatus.Learn: return Loc.T("Needs learning");
                case SpellStatus.Quest: return Loc.T("Locked quest spell");
                case SpellStatus.Level: return Loc.T("Level too low");
                default: return "";
            }
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var book = app.Session?.Spells;
            if (book == null) return;
            Styles(app);
            var e = Event.current;
            float x = inner.x + 4, w = inner.width - 8, y = inner.y + 2;

            // filters
            var names = new string[FilterKeys.Length];
            names[0] = Loc.T("Learned"); names[1] = Loc.T("Available soon"); names[2] = Loc.T("My vocation"); names[3] = Loc.T("All spells"); names[4] = Loc.T("Runes");
            int f = GUI.SelectionGrid(new Rect(x, y, w, 40), filter, names, 3);
            if (f != filter)
            {
                filter = f;
                visibleKey = null;
                if (loadedFor != null) PlayerPrefs.SetString(PrefKey(loadedFor), FilterKeys[filter]);
            }
            y += 44;
            var kinds = new[] { Loc.T("All types"), Loc.T("Attack"), Loc.T("Support") };
            int k = GUI.Toolbar(new Rect(x, y, w, 22), kind, kinds);
            if (k != kind) { kind = k; visibleKey = null; }
            y += 26;
            GUI.Label(new Rect(x, y + 2, 56, 20), Loc.T("Search"), app.SmallStyle);
            GUI.SetNextControlName("spellSearch");
            string s = GUI.TextField(new Rect(x + 58, y, w - 58, 22), search, 40);
            if (GUI.GetNameOfFocusedControl() == "spellSearch") app.MarkTextEditing();
            if (s != search) { search = s; visibleKey = null; }
            y += 28;

            // the list, rebuilt when a filter, the text or the book changed (the level changes it too: keyed on it)
            int level = app.Session.Parser.Level;
            string key = filter + "|" + kind + "|" + search + "|" + level + "|" + book.Spells.Count + "|" + book.Sig;
            if (key != visibleKey)
            {
                visibleKey = key;
                visible = book.Visible(FilterKeys[filter], KindKeys[kind], search);
                if (selected != null && !visible.Contains(selected)) selected = null;
            }

            float detailH = selected != null ? 112f : 36f;
            var listRect = new Rect(x, y, w, inner.yMax - y - detailH - 4);
            if (!book.Loaded)
            {
                GUI.Label(listRect, Loc.T("Loading spells..."), hintStyle);
            }
            else if (visible.Count == 0)
            {
                GUI.Label(listRect, Loc.T("No spell matches."), hintStyle);
            }
            else
            {
                var content = new Rect(0, 0, w - 18, visible.Count * Row);
                scroll = GUI.BeginScrollView(listRect, scroll, content);
                int first = Mathf.Max(0, (int)(scroll.y / Row)), last = Mathf.Min(visible.Count, first + (int)(listRect.height / Row) + 2);
                for (int i = first; i < last; i++) DrawRow(app, book, visible[i], new Rect(0, i * Row, w - 18, Row - 2), e);
                GUI.EndScrollView();
            }

            DrawDetails(app, book, new Rect(x, inner.yMax - detailH, w, detailH));
        }

        void DrawRow(ChaosApp app, SpellBook book, Spell sp, Rect r, Event e)
        {
            var st = book.Status(sp);
            bool ready = st == SpellStatus.Ready;
            int cd = book.CooldownSeconds(sp);
            ChaosApp.Fill(r, sp == selected ? new Color(0.45f, 0.3f, 0.12f, 0.9f) : new Color(1f, 1f, 1f, 0.06f));
            var c = ElementColor(sp.Element);
            if (!ready) c.a = 0.35f;
            ChaosApp.Fill(new Rect(r.x + 3, r.y + 4, 24, r.height - 8), c);
            var tint = GUI.color;
            GUI.color = ready ? Color.white : new Color(1f, 1f, 1f, 0.5f);
            GUI.Label(new Rect(r.x + 32, r.y + 1, r.width - 100, 16), sp.Name, nameStyle);
            GUI.Label(new Rect(r.x + 32, r.y + 16, r.width - 100, 14), sp.Words, wordsStyle);
            GUI.Label(new Rect(r.xMax - 66, r.y + 1, 62, 16), Loc.T("Level {0}", sp.Level), rightStyle);
            GUI.Label(new Rect(r.xMax - 66, r.y + 16, 62, 14), Loc.T("Mana {0}", sp.Mana), rightStyle);
            GUI.color = tint;
            if (cd > 0)
            {
                ChaosApp.Fill(new Rect(r.x + 3, r.y + 4, 24, r.height - 8), new Color(0f, 0f, 0f, 0.7f));
                GUI.Label(new Rect(r.x + 3, r.y + 8, 24, 16), cd.ToString(), new GUIStyle(rightStyle) { alignment = TextAnchor.MiddleCenter });
            }
            if (e.type == EventType.MouseDown && r.Contains(e.mousePosition))
            {
                selected = sp;
                if (e.button == 0)
                {
                    if (PickFor >= 0) { app.FindWindow<HotkeyBarWindow>()?.Assign(PickFor, sp.Words); PickFor = -1; }
                    else book.Cast(sp);
                }
                e.Use();
            }
        }

        void DrawDetails(ChaosApp app, SpellBook book, Rect r)
        {
            if (selected == null)
            {
                string hint = PickFor >= 0 ? Loc.T("Pick a spell for F{0}", PickFor + 1) : Loc.T("Click a spell to cast it. Right-click to put it on a hotkey.");
                GUI.Label(r, hint, hintStyle);
                return;
            }
            var sp = selected;
            ChaosApp.Fill(r, new Color(0f, 0f, 0f, 0.35f));
            GUI.Label(new Rect(r.x + 6, r.y + 2, r.width - 12, 18), sp.Name + "  (" + Loc.T("Words: {0}", sp.Words) + ")", app.SmallStyle);
            var line = Loc.T("Level {0}", sp.Level) + "   " + Loc.T("Magic level {0}", sp.MagicLevel) + "   " + Loc.T("Mana {0}", sp.Mana) + "   " + Loc.T("Cooldown {0}s", (sp.Cooldown / 1000f).ToString("0.#", System.Globalization.CultureInfo.InvariantCulture));
            GUI.Label(new Rect(r.x + 6, r.y + 20, r.width - 12, 16), line, wordsStyle);
            string status = StatusText(book.Status(sp));
            GUI.Label(new Rect(r.x + 6, r.y + 36, r.width - 12, 36), status.Length > 0 ? status : sp.Description, hintStyle);
            // F1 to F12: a right-click selected the spell; these put it on a hotkey slot
            float bw = (r.width - 12) / 12f;
            for (int i = 0; i < 12; i++)
            {
                var b = new Rect(r.x + 6 + i * bw, r.yMax - 28, bw - 2, 22);
                if (GUI.Button(b, "F" + (i + 1))) app.FindWindow<HotkeyBarWindow>()?.Assign(i, sp.Words);
            }
            GUI.Label(new Rect(r.x + 6, r.yMax - 46, r.width - 12, 16), Loc.T("Put on a hotkey:"), wordsStyle);
        }
    }
}
