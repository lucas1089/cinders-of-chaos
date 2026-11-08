// Hotkey bar: 12 slots, F1 to F12. A slot holds a line (spell words or any text) that is said when its key is pressed, or an item (HotbarModel, Core/HotbarSlots.cs).
// Text: click a slot to edit it (Enter or ok saves), right-click to pick a spell from the spellbook. A spell's words show the spell icon and its cooldown.
// Item: drop an item on a slot (drag it from the equipment or a bag), or use "Add to hotbar" in the item menu. The slot shows the item's sprite and how many you
// carry; a press or a click uses it (the item, on yourself, on the monster you attack, or with a crosshair for runes). Right-click picks the mode or removes it.
// Saved per character in PlayerPrefs, one string per slot. The keys work while the bar is open.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class HotkeyBarWindow : GameWindow
    {
        const int Slots = HotbarModel.Count;
        const float SlotW = 36f, SlotH = 40f, BarW = Slots * SlotW + 8f, BarH = 116f;

        readonly HotbarModel bar = new HotbarModel();
        string loadedFor;
        int editing = -1;
        string editText = "";
        bool focusEdit;
        GUIStyle keyStyle, textStyle, hintStyle, cooldownStyle, countStyle, markStyle;
        SessionHotbarHost host;
        GameSession hostFor;

        public HotkeyBarWindow()
        {
            Open = true;
        }

        public override string Title => Loc.T("Hotkeys");
        protected override Rect Place(float w, float h)
        {
            // bottom centre, but right of the chat window (it ends at about 468)
            float x = Mathf.Min(Mathf.Max((w - BarW) / 2f, 476f), Mathf.Max(0f, w - BarW));
            return new Rect(x, h - BarH - 8f, BarW, BarH);
        }

        public override void Reset()
        {
            loadedFor = null;
            editing = -1;
            host = null; hostFor = null;
            bar.Clear();
        }

        static string PrefKey(string character, int i) => "chaos.hotkey." + character + "." + (i + 1);

        void Load(string character)
        {
            loadedFor = character;
            editing = -1;
            bar.Load(i => PlayerPrefs.GetString(PrefKey(character, i), ""));
        }

        void Save(int i)
        {
            if (loadedFor == null) return;
            PlayerPrefs.SetString(PrefKey(loadedFor, i), bar.Saved(i));
            PlayerPrefs.Save();
        }

        /// <summary>Puts a line on a slot (the spellbook does it for a spell).</summary>
        public void Assign(int slot, string words)
        {
            if (slot < 0 || slot >= Slots || loadedFor == null) return;
            bar.SetText(slot, words ?? "");
            Save(slot);
            Open = true;
        }

        /// <summary>Puts an item on a slot (a drop, or "Add to hotbar"); a multi-use item (a rune, a potion) starts a "use with" crosshair, the others are used.</summary>
        public void AssignItem(int slot, int clientId, bool multiUse)
        {
            if (slot < 0 || slot >= Slots || loadedFor == null) return;
            if (!bar.SetItem(slot, clientId, multiUse)) return;
            if (editing == slot) editing = -1;
            Save(slot);
            Open = true;
        }

        /// <summary>The item menu's "Add to hotbar": the first empty slot; -1 when the bar is full or not loaded yet.</summary>
        public int AddItem(int clientId, bool multiUse)
        {
            if (loadedFor == null) return -1;
            int slot = bar.FirstEmpty();
            if (slot < 0) return -1;
            AssignItem(slot, clientId, multiUse);
            return slot;
        }

        void Commit()
        {
            if (editing >= 0)
            {
                bar.SetText(editing, editText);
                Save(editing);
            }
            editing = -1;
            GUI.FocusControl(null);
        }

        void BeginEdit(int i)
        {
            if (editing >= 0) Commit();
            editing = i;
            editText = bar[i].Kind == HotKind.Text ? bar[i].Text : "";
            focusEdit = true;
        }

        IHotbarHost HostFor(ChaosApp app)
        {
            var s = app.Session;
            if (s == null) return null;
            if (host == null || hostFor != s) { host = new SessionHotbarHost(s, r => app.Crosshair.Start(CrosshairState.Kind.UseWith, r)); hostFor = s; }
            return host;
        }

        void Press(ChaosApp app, int i)
        {
            switch (bar.Press(i, HostFor(app)))
            {
                case HotOutcome.NotCarried: app.PostLine(Loc.T("That item is not in your equipment or an open bag.")); break;
                case HotOutcome.NoTarget: app.PostLine(Loc.T("Attack a monster first.")); break;
            }
        }

        // the keys work with the bar closed too: Tick runs in the main GUI pass, not inside the window
        public override void Tick(ChaosApp app)
        {
            string name = app.World?.Player?.Name;
            if (name == null) return;
            if (name != loadedFor) Load(name);
            var e = Event.current;
            // not while the chat line or a slot has the keyboard
            if (e.type != EventType.KeyDown || editing >= 0 || app.ChatFocused || e.control || e.alt) return;
            for (int i = 0; i < Slots; i++)
            {
                if (e.keyCode != KeyCode.F1 + i) continue;
                if (!bar[i].IsEmpty) Press(app, i);
                e.Use();
                break;
            }
        }

        void ModeMenu(ChaosApp app, int slot)
        {
            var items = new List<KeyValuePair<string, System.Action>>();
            foreach (var m in HotbarModel.Modes)
            {
                var mode = m;
                string label = (bar[slot].Mode == mode ? "> " : "") + Loc.T(HotbarModel.ModeLabel(mode));
                items.Add(new KeyValuePair<string, System.Action>(label, () => { if (bar.SetMode(slot, mode)) Save(slot); }));
            }
            items.Add(new KeyValuePair<string, System.Action>("", null));
            items.Add(new KeyValuePair<string, System.Action>(Loc.T("Remove from hotbar"), () => { bar.ClearSlot(slot); Save(slot); }));
            app.ShowMenu(app.MouseUi(), items);
        }

        void DrawItemSlot(ChaosApp app, Rect r, HotSlot s)
        {
            int have = app.Session != null ? app.Session.CountItem(s.ItemId) : 0;
            var old = GUI.color;
            if (have <= 0) GUI.color = new Color(1f, 1f, 1f, 0.35f);
            app.DrawItem(new Rect(r.x + 1, r.y + 7, 32, 32), (ushort)s.ItemId, 0);
            GUI.color = old;
            if (have != 1)
            {
                countStyle.normal.textColor = Color.black;
                GUI.Label(new Rect(r.x + 1, r.y + 1, r.width - 1, r.height - 1), have.ToString(), countStyle);
                countStyle.normal.textColor = have <= 0 ? new Color(1f, 0.45f, 0.4f) : Color.white;
                GUI.Label(new Rect(r.x, r.y, r.width - 1, r.height - 1), have.ToString(), countStyle);
            }
            string mark = HotbarModel.ModeMark(s.Mode);
            if (mark.Length > 0) GUI.Label(new Rect(r.xMax - 12, r.y, 12, 14), mark, markStyle);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            string name = app.World?.Player?.Name;
            if (name == null) return;
            if (name != loadedFor) Load(name);
            if (keyStyle == null)
            {
                keyStyle = new GUIStyle(app.SmallStyle) { fontSize = 10, alignment = TextAnchor.UpperLeft };
                keyStyle.normal.textColor = new Color(1f, 0.85f, 0.4f);
                textStyle = new GUIStyle(app.SmallStyle) { fontSize = 11, alignment = TextAnchor.LowerLeft, clipping = TextClipping.Clip };
                cooldownStyle = new GUIStyle(app.SmallStyle) { fontSize = 16, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
                countStyle = new GUIStyle(app.SmallStyle) { fontSize = 12, fontStyle = FontStyle.Bold, alignment = TextAnchor.LowerRight };
                markStyle = new GUIStyle(app.SmallStyle) { fontSize = 11, fontStyle = FontStyle.Bold, alignment = TextAnchor.UpperRight };
                markStyle.normal.textColor = new Color(0.55f, 0.9f, 1f);
                hintStyle = new GUIStyle(app.SmallStyle) { fontSize = 12 };
                hintStyle.normal.textColor = new Color(1f, 1f, 1f, 0.5f);
            }
            var e = Event.current;

            for (int i = 0; i < Slots; i++)
            {
                var r = new Rect(inner.x + i * SlotW, inner.y, SlotW - 2f, SlotH);
                var s = bar[i];
                ChaosApp.Fill(r, i == editing ? new Color(0.45f, 0.3f, 0.12f, 0.95f) : new Color(1f, 1f, 1f, 0.08f));
                var spell = s.Kind == HotKind.Text ? app.Session?.Spells.ByWords(s.Text) : null;
                if (s.Kind == HotKind.Item) DrawItemSlot(app, r, s);
                else if (s.Kind == HotKind.Text)
                {
                    // a spell shows its icon; any other line (or no picture files) shows its text
                    bool icon = spell != null && app.DrawSpellIcon(new Rect(r.x + 1, r.y + 7, 32, 32), spell.Words, spell.Id);
                    if (!icon) GUI.Label(new Rect(r.x + 2, r.y + 14, r.width - 2, r.height - 14), s.Text, textStyle);
                }
                GUI.Label(new Rect(r.x + 2, r.y, r.width - 2, 14), "F" + (i + 1), keyStyle);
                int cd = spell != null ? app.Session.Spells.CooldownSeconds(spell) : 0;
                if (cd > 0)
                {
                    ChaosApp.Fill(r, new Color(0f, 0f, 0f, 0.65f));
                    GUI.Label(r, cd.ToString(), cooldownStyle);
                }
                // an item dragged from the equipment or a bag and released here
                if (ItemSlots.Drop(r, (pos, id, stack, count) => AssignItem(i, id, app.ItemIsMultiUse(id)))) continue;
                if (e.type == EventType.MouseDown && r.Contains(e.mousePosition))
                {
                    if (e.button == 0)
                    {
                        if (s.Kind == HotKind.Item) { if (editing >= 0) Commit(); Press(app, i); }
                        else BeginEdit(i);
                    }
                    else if (e.button == 1)
                    {
                        if (editing >= 0) Commit();
                        if (s.Kind == HotKind.Item) ModeMenu(app, i);
                        else
                        {
                            // right-click: pick a spell for this slot in the spellbook
                            var book = app.FindWindow<SpellbookWindow>();
                            if (book != null) { book.PickFor = i; book.Open = true; }
                        }
                    }
                    e.Use();
                }
            }

            var line = new Rect(inner.x, inner.y + SlotH + 6, inner.width, 24);
            if (editing < 0)
            {
                GUI.Label(line, Loc.T("Click a slot to set what it says. Right-click: pick a spell."), hintStyle);
                GUI.Label(new Rect(line.x, line.y + 14, line.width, 20), Loc.T("Drop an item on a slot to keep it there."), hintStyle);
                ItemSlots.Ghost(app, new Rect(0, 0, Area.width, Area.height));
                return;
            }
            // the walking keys must not move the character while a slot is edited
            app.MarkTextEditing();
            GUI.Label(new Rect(line.x, line.y + 2, 30, 22), "F" + (editing + 1), app.SmallStyle);
            bool enter = e.type == EventType.KeyDown && (e.keyCode == KeyCode.Return || e.keyCode == KeyCode.KeypadEnter);
            bool escape = e.type == EventType.KeyDown && e.keyCode == KeyCode.Escape;
            GUI.SetNextControlName("hotkeyEdit");
            editText = GUI.TextField(new Rect(line.x + 32, line.y, line.width - 82, 24), editText ?? "", 255);
            if (focusEdit && e.type == EventType.Repaint) { GUI.FocusControl("hotkeyEdit"); focusEdit = false; }
            if (GUI.Button(new Rect(line.xMax - 46, line.y, 46, 24), "ok") || enter || escape)
            {
                if (enter || escape) e.Use();
                Commit();
            }
        }
    }
}
