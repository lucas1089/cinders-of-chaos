// Hotkey bar: 12 slots, F1 to F12. Each holds a line (spell words or any text) that is said when its key is pressed.
// Click a slot to edit its text (Enter or ok saves). Saved per character in PlayerPrefs. The keys work while the bar is open.
using UnityEngine;

namespace Chaos.Client
{
    public sealed class HotkeyBarWindow : GameWindow
    {
        const int Slots = 12;
        const float SlotW = 36f, SlotH = 40f, BarW = Slots * SlotW + 8f, BarH = 102f;

        readonly string[] texts = new string[Slots];
        string loadedFor;
        int editing = -1;
        bool focusEdit;
        GUIStyle keyStyle, textStyle, hintStyle;

        public HotkeyBarWindow()
        {
            Open = true;
            for (int i = 0; i < Slots; i++) texts[i] = "";
        }

        public override string Title => "Hotkeys";
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
            for (int i = 0; i < Slots; i++) texts[i] = "";
        }

        static string PrefKey(string character, int i) => "chaos.hotkey." + character + "." + (i + 1);

        void Load(string character)
        {
            loadedFor = character;
            editing = -1;
            for (int i = 0; i < Slots; i++) texts[i] = PlayerPrefs.GetString(PrefKey(character, i), "");
        }

        void Save(int i)
        {
            if (loadedFor == null) return;
            PlayerPrefs.SetString(PrefKey(loadedFor, i), texts[i] ?? "");
            PlayerPrefs.Save();
        }

        void Commit()
        {
            if (editing >= 0) Save(editing);
            editing = -1;
            GUI.FocusControl(null);
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
                hintStyle = new GUIStyle(app.SmallStyle) { fontSize = 12 };
                hintStyle.normal.textColor = new Color(1f, 1f, 1f, 0.5f);
            }
            var e = Event.current;

            // the keys: not while the chat line or a slot has the keyboard
            if (e.type == EventType.KeyDown && editing < 0 && !app.ChatFocused && !e.control && !e.alt)
            {
                for (int i = 0; i < Slots; i++)
                {
                    if (e.keyCode != KeyCode.F1 + i) continue;
                    if (!string.IsNullOrWhiteSpace(texts[i])) app.Session?.Say(texts[i]);
                    e.Use();
                    break;
                }
            }

            for (int i = 0; i < Slots; i++)
            {
                var r = new Rect(inner.x + i * SlotW, inner.y, SlotW - 2f, SlotH);
                ChaosApp.Fill(r, i == editing ? new Color(0.45f, 0.3f, 0.12f, 0.95f) : new Color(1f, 1f, 1f, 0.08f));
                GUI.Label(new Rect(r.x + 2, r.y, r.width - 2, 14), "F" + (i + 1), keyStyle);
                GUI.Label(new Rect(r.x + 2, r.y + 14, r.width - 2, r.height - 14), texts[i], textStyle);
                if (e.type == EventType.MouseDown && e.button == 0 && r.Contains(e.mousePosition))
                {
                    if (editing >= 0) Save(editing);
                    editing = i;
                    focusEdit = true;
                    e.Use();
                }
            }

            var line = new Rect(inner.x, inner.y + SlotH + 6, inner.width, 24);
            if (editing < 0)
            {
                GUI.Label(line, "Click a slot to set what it says.", hintStyle);
                return;
            }
            // the walking keys must not move the character while a slot is edited
            app.MarkTextEditing();
            GUI.Label(new Rect(line.x, line.y + 2, 30, 22), "F" + (editing + 1), app.SmallStyle);
            bool enter = e.type == EventType.KeyDown && (e.keyCode == KeyCode.Return || e.keyCode == KeyCode.KeypadEnter);
            bool escape = e.type == EventType.KeyDown && e.keyCode == KeyCode.Escape;
            GUI.SetNextControlName("hotkeyEdit");
            texts[editing] = GUI.TextField(new Rect(line.x + 32, line.y, line.width - 82, 24), texts[editing] ?? "", 255);
            if (focusEdit && e.type == EventType.Repaint) { GUI.FocusControl("hotkeyEdit"); focusEdit = false; }
            if (GUI.Button(new Rect(line.xMax - 46, line.y, 46, 24), "ok") || enter || escape)
            {
                if (enter || escape) e.Use();
                Commit();
            }
        }
    }
}
