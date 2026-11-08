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
        const float DetailH = 272f;   // header, the area preview with the rows beside it, the F1 to F12 row

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

        protected override Rect Place(float w, float h) => new Rect(12f, 48f, 340f, Mathf.Min(660f, Mathf.Max(440f, h - 60f)));

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

            float detailH = selected != null ? DetailH : 36f;
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
            var tint = GUI.color;
            GUI.color = ready ? Color.white : new Color(1f, 1f, 1f, 0.5f);
            // the spell's icon cell (or its rune's sprite); without the picture files the element colour square of before
            var iconRect = new Rect(r.x + 3, r.y + 2, 28, 28);
            if (!app.DrawSpellEntryIcon(iconRect, sp))
            {
                var c = ElementColor(sp.Element);
                if (!ready) c.a = 0.35f;
                ChaosApp.Fill(new Rect(r.x + 3, r.y + 4, 24, r.height - 8), c);
            }
            GUI.Label(new Rect(r.x + 32, r.y + 1, r.width - 100, 16), sp.Name, nameStyle);
            GUI.Label(new Rect(r.x + 32, r.y + 16, r.width - 100, 14), sp.Words, wordsStyle);
            GUI.Label(new Rect(r.xMax - 66, r.y + 1, 62, 16), Loc.T("Level {0}", sp.Level), rightStyle);
            GUI.Label(new Rect(r.xMax - 66, r.y + 16, 62, 14), Loc.T("Mana {0}", sp.Mana), rightStyle);
            GUI.color = tint;
            if (cd > 0)
            {
                ChaosApp.Fill(new Rect(r.x + 3, r.y + 2, 28, 28), new Color(0f, 0f, 0f, 0.7f));
                GUI.Label(new Rect(r.x + 3, r.y + 8, 28, 16), cd.ToString(), new GUIStyle(rightStyle) { alignment = TextAnchor.MiddleCenter });
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

        string tipText = "";
        Vector2 tipAt;

        static Color RoleColor(AreaRole role, Color hit)
        {
            switch (role)
            {
                case AreaRole.Hit: return hit;
                case AreaRole.Caster: return new Color(0.965f, 0.81f, 0.45f);
                case AreaRole.TargetHit: return hit;
                default: return new Color(0.10f, 0.08f, 0.09f);
            }
        }

        /// <summary>The area grid of the main client's details: your square, the tiles hit, the target (white frame), then the legend and the note.</summary>
        void DrawArea(ChaosApp app, Spell sp, Rect box)
        {
            ChaosApp.Fill(box, new Color(0.05f, 0.04f, 0.055f, 0.55f));
            var roles = SpellArea.Roles(sp);
            int cell = SpellArea.CellSize(roles, box.width, box.height - 30f);
            var hit = ElementColor(sp.Element);
            float gw = cell * SpellArea.Columns(roles);
            float gx = box.x + (box.width - gw) / 2f, gy = box.y + 4f;
            for (int r = 0; r < roles.Length; r++)
                for (int c = 0; c < roles[r].Length; c++)
                {
                    var role = roles[r][c];
                    var rc = new Rect(gx + c * cell, gy + r * cell, cell - 1, cell - 1);
                    ChaosApp.Fill(new Rect(rc.x - 1, rc.y - 1, rc.width + 2, rc.height + 2), new Color(0.16f, 0.13f, 0.15f));
                    ChaosApp.Fill(rc, RoleColor(role, hit));
                    if (role == AreaRole.Target || role == AreaRole.TargetHit)
                    {
                        float b = cell >= 9 ? 2f : 1f;
                        ChaosApp.Fill(new Rect(rc.x, rc.y, rc.width, b), Color.white);
                        ChaosApp.Fill(new Rect(rc.x, rc.yMax - b, rc.width, b), Color.white);
                        ChaosApp.Fill(new Rect(rc.x, rc.y, b, rc.height), Color.white);
                        ChaosApp.Fill(new Rect(rc.xMax - b, rc.y, b, rc.height), Color.white);
                    }
                }
            // legend: hit, you, target
            float ly = box.yMax - 28f, lx = box.x + 6f;
            ChaosApp.Fill(new Rect(lx, ly + 2, 9, 9), hit);
            GUI.Label(new Rect(lx + 12, ly - 2, 34, 16), Loc.T("Hit"), wordsStyle);
            ChaosApp.Fill(new Rect(lx + 46, ly + 2, 9, 9), new Color(0.965f, 0.81f, 0.45f));
            GUI.Label(new Rect(lx + 58, ly - 2, 34, 16), Loc.T("You"), wordsStyle);
            var tcol = SpellArea.HasTargetHit(roles) ? hit : new Color(0.10f, 0.08f, 0.09f);
            ChaosApp.Fill(new Rect(lx + 92, ly + 1, 11, 11), Color.white);
            ChaosApp.Fill(new Rect(lx + 94, ly + 3, 7, 7), tcol);
            GUI.Label(new Rect(lx + 106, ly - 2, 48, 16), Loc.T("Target"), wordsStyle);
            string note = SpellArea.Note(sp, out int arg);
            GUI.Label(new Rect(box.x + 4, box.yMax - 14, box.width - 8, 14), arg > 0 ? Loc.T(note, arg) : Loc.T(note), new GUIStyle(wordsStyle) { alignment = TextAnchor.UpperCenter });
        }

        void DrawStat(string key, string value, Rect row, string tip)
        {
            GUI.Label(new Rect(row.x, row.y, 62, row.height), key, wordsStyle);
            GUI.Label(new Rect(row.x + 62, row.y, row.width - 62, row.height), value, nameStyle);
            if (tip != null && Event.current.type == EventType.Repaint && row.Contains(Event.current.mousePosition)) { tipText = tip; tipAt = Event.current.mousePosition; }
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
            tipText = "";
            ChaosApp.Fill(r, new Color(0f, 0f, 0f, 0.35f));
            bool bigIcon = app.DrawSpellEntryIcon(new Rect(r.xMax - 38, r.y + 4, 32, 32), sp);
            GUI.Label(new Rect(r.x + 6, r.y + 2, r.width - (bigIcon ? 46 : 12), 18), sp.Name + "  (" + Loc.T("Words: {0}", sp.Words) + ")", app.SmallStyle);
            var line = Loc.T("Level {0}", sp.Level) + "   " + Loc.T("Magic level {0}", sp.MagicLevel) + "   " + Loc.T("Mana {0}", sp.Mana) + "   " + Loc.T("Cooldown {0}s", (sp.Cooldown / 1000f).ToString("0.#", System.Globalization.CultureInfo.InvariantCulture));
            GUI.Label(new Rect(r.x + 6, r.y + 20, r.width - (bigIcon ? 46 : 12), 16), line, wordsStyle);
            string status = StatusText(book.Status(sp));
            GUI.Label(new Rect(r.x + 6, r.y + 36, r.width - 12, 24), status.Length > 0 ? status : sp.Description, hintStyle);
            // game_spellsupports: the runes socketed in this spell (BookLine), with the effects in the tooltip
            string supTip = "";
            var supports = app.Session?.Utils?.Supports;
            string supLine = supports != null ? supports.BookLine(sp.Words, out supTip) : null;
            if (supLine != null)
            {
                var sr = new Rect(r.x + 6, r.y + 60, r.width - 12, 16);
                GUI.Label(sr, supLine, wordsStyle);
                if (supTip.Length > 0 && sr.Contains(Event.current.mousePosition)) app.SetTip(supTip);
            }
            // the area preview on the left, the rows of the main client on the right
            float top = r.y + 76f, boxH = r.yMax - 50f - top;
            DrawArea(app, sp, new Rect(r.x + 6, top, 160f, boxH));
            float ry = top;
            foreach (var st in SpellDetails.Rows(sp, book.VocationNames))
            {
                string val = st.Translate ? Loc.T(st.Value) : st.Value;
                if (!st.Translate && st.Key == "Vocations" && st.Value.EndsWith(" classes", System.StringComparison.Ordinal))
                    val = Loc.T("{0} classes", st.Value.Substring(0, st.Value.IndexOf(' ')));
                DrawStat(Loc.T(st.Key), val, new Rect(r.x + 172, ry, r.width - 178, 15), st.Tip);
                ry += 15f;
            }
            // F1 to F12: a right-click selected the spell; these put it on a hotkey slot
            float bw = (r.width - 12) / 12f;
            for (int i = 0; i < 12; i++)
            {
                var b = new Rect(r.x + 6 + i * bw, r.yMax - 28, bw - 2, 22);
                if (GUI.Button(b, "F" + (i + 1))) app.FindWindow<HotkeyBarWindow>()?.Assign(i, sp.Words);
            }
            GUI.Label(new Rect(r.x + 6, r.yMax - 46, r.width - 12, 16), Loc.T("Put on a hotkey:"), wordsStyle);
            if (tipText.Length > 0)
            {
                var tr2 = new Rect(Mathf.Min(tipAt.x + 10, r.xMax - 190), tipAt.y + 14, 186, 34);
                ChaosApp.Fill(tr2, new Color(0.04f, 0.03f, 0.04f, 0.95f));
                GUI.Label(new Rect(tr2.x + 3, tr2.y + 1, tr2.width - 6, tr2.height - 2), tipText, hintStyle);
            }
        }
    }
}
