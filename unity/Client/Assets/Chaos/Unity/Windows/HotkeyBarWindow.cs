// Hotkey bar: the main row F1 to F12 (6, 8, 10 or 12 shown) and the two round side slots Q and E of the main client's hotbar. A slot holds a line (spell words or
// any text) that is said when its key is pressed, or an item (HotbarModel, Core/HotbarSlots.cs).
// Text: click a slot to edit it (Enter or ok saves), right-click to pick a spell from the spellbook. A spell's words show the spell icon and its cooldown.
// Item: drop an item on a slot (drag it from the equipment or a bag), or use "Add to hotbar" in the item menu. The slot shows the item's sprite and how many you
// carry; a press or a click uses it (the item, on yourself, on the monster you attack, or with a crosshair for runes). Right-click picks the mode or removes it.
// Drag a filled slot onto another to move it (a filled target swaps). The gear button opens the slot count and the scale (Core/Phase7XHotbar.cs).
// Saved per character in PlayerPrefs, one string per slot and one for the options. The keys work while the bar is open.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class HotkeyBarWindow : GameWindow
    {
        const float ExtraH = 76f;   // under the slots: the hint lines or the options

        readonly HotbarModel bar = new HotbarModel();
        string loadedFor;
        int editing = -1;
        string editText = "";
        bool focusEdit;
        GUIStyle keyStyle, textStyle, hintStyle, cooldownStyle, countStyle, markStyle;
        SessionHotbarHost host;
        GameSession hostFor;

        HotbarOptions options = HotbarOptions.Default;
        HotbarMetrics m = HotbarLayout.Metrics(HotbarOptions.DefaultCount, HotbarOptions.DefaultScale);
        string sizedKey;
        bool showOptions;
        int dragFrom = -1;
        Vector2 dragStart;
        bool dragMoved;

        public HotkeyBarWindow()
        {
            Open = true;
        }

        public override string Title => Loc.T("Hotkeys");
        protected override Rect Place(float w, float h)
        {
            // bottom centre, but right of the chat window (it ends at about 468)
            float bw = m.Width + 8f;
            float x = Mathf.Min(Mathf.Max((w - bw) / 2f, 476f), Mathf.Max(0f, w - bw));
            return new Rect(x, h - BarH() - 8f, bw, BarH());
        }

        float BarH() => m.SlotH + ExtraH;

        public override void Reset()
        {
            loadedFor = null;
            editing = -1;
            host = null; hostFor = null;
            dragFrom = -1;
            showOptions = false;
            sizedKey = null;
            options = HotbarOptions.Default;
            bar.Clear();
        }

        static string PrefKey(string character, int i) => "chaos.hotkey." + character + "." + (i + 1);
        static string OptKey(string character) => "chaos.hotbar.opts." + character;

        void Load(string character)
        {
            loadedFor = character;
            editing = -1;
            bar.Load(i => PlayerPrefs.GetString(PrefKey(character, i), ""));
            options = HotbarOptions.Parse(PlayerPrefs.GetString(OptKey(character), ""));
            sizedKey = null;
        }

        void Save(int i)
        {
            if (loadedFor == null) return;
            PlayerPrefs.SetString(PrefKey(loadedFor, i), bar.Saved(i));
            PlayerPrefs.Save();
        }

        void SaveOptions()
        {
            if (loadedFor == null) return;
            PlayerPrefs.SetString(OptKey(loadedFor), options.Encode());
            PlayerPrefs.Save();
        }

        /// <summary>The metrics of the options, fitted to the screen width, and the window resized to them around its bottom centre.</summary>
        static float UiWidth() => UnityEngine.Screen.width / ChaosApp.UiScale(UnityEngine.Screen.width, UnityEngine.Screen.height, UnityEngine.Screen.dpi);
        string SizeKey() => options.Encode() + "|" + (int)UiWidth();

        void Resize()
        {
            m = HotbarLayout.Fit(options, UiWidth() - 16f, out _);
            sizedKey = SizeKey();
            float cx = Area.x + Area.width / 2f, bottom = Area.yMax;
            Area.width = m.Width + 8f;
            Area.height = BarH();
            Area.x = cx - Area.width / 2f;
            Area.y = bottom - Area.height;
        }

        /// <summary>Puts a line on a slot (the spellbook does it for a spell).</summary>
        public void Assign(int slot, string words)
        {
            if (slot < 0 || slot >= HotbarModel.Total || loadedFor == null) return;
            bar.SetText(slot, words ?? "");
            Save(slot);
            Open = true;
        }

        /// <summary>Puts an item on a slot (a drop, or "Add to hotbar"); a multi-use item (a rune, a potion) starts a "use with" crosshair, the others are used.</summary>
        public void AssignItem(int slot, int clientId, bool multiUse)
        {
            if (slot < 0 || slot >= HotbarModel.Total || loadedFor == null) return;
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
            if (sizedKey == null || sizedKey != SizeKey()) Resize();   // here, not in Body: the window rect Body runs in is the one GUI.Window hands back
            var e = Event.current;
            // not while the chat line or a slot has the keyboard
            if (e.type != EventType.KeyDown || editing >= 0 || app.ChatFocused || e.control || e.alt) return;
            int slot = HotbarLayout.SlotOfKey(e.keyCode.ToString());
            if (slot < 0) return;
            // the bare Q and E belong to the side slots only when they hold something
            if (slot >= HotbarModel.Count && (bar[slot].IsEmpty || e.shift)) return;
            if (!bar[slot].IsEmpty) Press(app, slot);
            e.Use();
        }

        void ModeMenu(ChaosApp app, int slot)
        {
            var items = new List<KeyValuePair<string, System.Action>>();
            foreach (var mo in HotbarModel.Modes)
            {
                var mode = mo;
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
            float icon = Mathf.Min(32f * m.Scale / 100f, r.width - 2f);
            app.DrawItem(new Rect(r.x + 1, r.y + r.height - icon - 1f, icon, icon), (ushort)s.ItemId, 0);
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

        /// <summary>One slot: its frame, content, key label and cooldown; the mouse rules (click, drop an item, drag to move, right-click).</summary>
        void DrawSlot(ChaosApp app, Rect r, int i, Event e)
        {
            bool side = i >= HotbarModel.Count;
            var s = bar[i];
            Color fill = i == editing ? new Color(0.45f, 0.3f, 0.12f, 0.95f) : (dragFrom >= 0 && dragMoved && r.Contains(e.mousePosition) ? new Color(0.6f, 0.45f, 0.15f, 0.7f) : new Color(1f, 1f, 1f, 0.08f));
            ChaosApp.Fill(r, fill);
            if (side)   // the round sockets of the main client: a gold ring
            {
                var ring = new Color(0.85f, 0.65f, 0.25f, 0.55f);
                ChaosApp.Fill(new Rect(r.x, r.y, r.width, 1), ring); ChaosApp.Fill(new Rect(r.x, r.yMax - 1, r.width, 1), ring);
                ChaosApp.Fill(new Rect(r.x, r.y, 1, r.height), ring); ChaosApp.Fill(new Rect(r.xMax - 1, r.y, 1, r.height), ring);
            }
            var spell = s.Kind == HotKind.Text ? app.Session?.Spells.ByWords(s.Text) : null;
            if (s.Kind == HotKind.Item) DrawItemSlot(app, r, s);
            else if (s.Kind == HotKind.Text)
            {
                // a spell shows its icon; any other line (or no picture files) shows its text
                float icon = Mathf.Min(32f * m.Scale / 100f, r.width - 2f);
                bool drawn = spell != null && app.DrawSpellIcon(new Rect(r.x + 1, r.yMax - icon - 1f, icon, icon), spell.Words, spell.Id);
                if (!drawn) GUI.Label(new Rect(r.x + 2, r.y + 14, r.width - 2, r.height - 14), s.Text, textStyle);
            }
            GUI.Label(new Rect(r.x + 2, r.y, r.width - 2, 14), HotbarLayout.KeyLabel(i), keyStyle);
            int cd = spell != null ? app.Session.Spells.CooldownSeconds(spell) : 0;
            if (cd > 0)
            {
                ChaosApp.Fill(r, new Color(0f, 0f, 0f, 0.65f));
                GUI.Label(r, cd.ToString(), cooldownStyle);
            }
            // an item dragged from the equipment or a bag and released here
            if (ItemSlots.Drop(r, (pos, id, stack, count) => AssignItem(i, id, app.ItemIsMultiUse(id)))) return;
            // a slot dragged from another slot and released here
            if (dragFrom >= 0 && dragMoved && e.type == EventType.MouseUp && e.button == 0 && r.Contains(e.mousePosition))
            {
                if (editing >= 0) Commit();
                if (bar.Swap(dragFrom, i)) { Save(dragFrom); Save(i); }
                dragFrom = -1; dragMoved = false;
                e.Use();
                return;
            }
            if (!r.Contains(e.mousePosition)) return;
            if (e.type == EventType.MouseDown && e.button == 0)
            {
                if (s.IsEmpty) { BeginEdit(i); e.Use(); return; }
                dragFrom = i; dragStart = e.mousePosition; dragMoved = false;   // a click or a drag: told at the release
                e.Use();
            }
            else if (e.type == EventType.MouseUp && e.button == 0 && dragFrom == i && !dragMoved)
            {
                dragFrom = -1;
                if (editing >= 0) Commit();
                if (s.Kind == HotKind.Item) Press(app, i); else BeginEdit(i);
                e.Use();
            }
            else if (e.type == EventType.MouseDown && e.button == 1)
            {
                if (editing >= 0) Commit();
                if (s.Kind == HotKind.Item) ModeMenu(app, i);
                else
                {
                    // right-click: pick a spell for this slot in the spellbook
                    var book = app.FindWindow<SpellbookWindow>();
                    if (book != null) { book.PickFor = i; book.Open = true; }
                }
                e.Use();
            }
        }

        void OptionsPanel(ChaosApp app, Rect line)
        {
            GUI.Label(new Rect(line.x, line.y, 70, 20), Loc.T("Slots"), hintStyle);
            var labels = new string[HotbarOptions.Counts.Length];
            int cur = 0;
            for (int k = 0; k < labels.Length; k++) { labels[k] = HotbarOptions.Counts[k].ToString(); if (HotbarOptions.Counts[k] == options.Count) cur = k; }
            int pick = GUI.Toolbar(new Rect(line.x + 70, line.y, Mathf.Min(line.width - 150, 200f), 20), cur, labels);
            if (pick != cur) { options.Count = HotbarOptions.Counts[pick]; SaveOptions(); sizedKey = null; }
            GUI.Label(new Rect(line.x, line.y + 24, 120, 20), Loc.T("Bar size: {0}%", options.Scale), hintStyle);
            float sv = GUI.HorizontalSlider(new Rect(line.x + 124, line.y + 29, Mathf.Min(line.width - 210, 160f), 14), options.Scale, HotbarOptions.ScaleMin, HotbarOptions.ScaleMax);
            int ns = HotbarOptions.ClampScale(sv);
            if (ns != options.Scale) { options.Scale = ns; SaveOptions(); sizedKey = null; }
            if (GUI.Button(new Rect(line.xMax - 76, line.y + 24, 76, 20), Loc.T("Reset"))) { options = HotbarOptions.Default; SaveOptions(); sizedKey = null; }
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            string name = app.World?.Player?.Name;
            if (name == null) return;
            if (name != loadedFor) Load(name);
            if (sizedKey == null || sizedKey != SizeKey()) return;   // Tick resizes first
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

            // a slot dragged out of the bar and let go outside any slot stays where it was
            if (dragFrom >= 0 && e.type == EventType.MouseDrag && (e.mousePosition - dragStart).sqrMagnitude > 36f) dragMoved = true;
            if (dragFrom >= 0 && e.type == EventType.Repaint && !Input.GetMouseButton(0)) { dragFrom = -1; dragMoved = false; }

            foreach (int i in HotbarLayout.Shown(m.Count))
                DrawSlot(app, new Rect(inner.x + (float)HotbarLayout.SlotX(m, i), inner.y, m.SlotW, m.SlotH), i, e);
            DrawSlot(app, new Rect(inner.x + (float)HotbarLayout.SlotX(m, HotbarModel.SideQ), inner.y, m.SideW, m.SlotH), HotbarModel.SideQ, e);
            DrawSlot(app, new Rect(inner.x + (float)HotbarLayout.SlotX(m, HotbarModel.SideE), inner.y, m.SideW, m.SlotH), HotbarModel.SideE, e);

            // the slot being dragged follows the pointer
            if (dragFrom >= 0 && dragMoved && e.type == EventType.Repaint)
            {
                var s = bar[dragFrom];
                var g = new Rect(e.mousePosition.x - 16, e.mousePosition.y - 16, 32, 32);
                ChaosApp.Fill(g, new Color(0.45f, 0.3f, 0.12f, 0.8f));
                if (s.Kind == HotKind.Item) app.DrawItem(g, (ushort)s.ItemId, 0);
                else
                {
                    var spell = app.Session?.Spells.ByWords(s.Text);
                    if (spell == null || !app.DrawSpellIcon(g, spell.Words, spell.Id)) GUI.Label(g, s.Text, textStyle);
                }
            }

            var line = new Rect(inner.x, inner.y + m.SlotH + 6, inner.width, 24);
            // the gear: slot count and scale
            if (GUI.Button(new Rect(inner.xMax - 24, inner.y + m.SlotH + 4, 22, 18), showOptions ? "x" : "*")) showOptions = !showOptions;
            if (showOptions)
            {
                if (editing >= 0) Commit();
                OptionsPanel(app, new Rect(line.x, line.y + 18, inner.width, 44));
                return;
            }
            if (editing < 0)
            {
                GUI.Label(line, Loc.T("Click a slot to set what it says. Right-click: pick a spell."), hintStyle);
                GUI.Label(new Rect(line.x, line.y + 14, line.width, 20), Loc.T("Drop an item on a slot to keep it there. Drag a slot to move it."), hintStyle);
                ItemSlots.Ghost(app, new Rect(0, 0, Area.width, Area.height));
                return;
            }
            // the walking keys must not move the character while a slot is edited
            app.MarkTextEditing();
            GUI.Label(new Rect(line.x, line.y + 2, 30, 22), HotbarLayout.KeyLabel(editing), app.SmallStyle);
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
