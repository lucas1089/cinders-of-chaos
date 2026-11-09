// Items glue of the app: the rich tooltip drawn over the windows (opcode 242, Core/ItemInfo.cs), the modal window (0xFA) and the text window of
// books and signs (0x96, 0x97). All three are server-driven overlays: they have no toolbar button.
using System.Collections.Generic;
using System.Text;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        const int ModalWindowId = 9100, TextWindowId = 9101;
        GUIStyle tipStyle, tipTitleStyle, dlgStyle;
        uint modalFor, textFor;
        int modalChoice = ModalWindows.NoChoice;
        string textBuf = "";
        Vector2 dlgScroll;

        /// <summary>The tooltip, the modal window and the text window. Call last in the game GUI, over the windows.</summary>
        void ItemsGui(float w, float h, float scale)
        {
            using var _slow = SlowCalls.Scope("ItemsGui", "OnGUI");
            if (session == null) return;
            ItemTipGui(w, h);
            ModalGui(w, h, scale);
            TextWindowGui(w, h, scale);
        }

        static string Hex(string hex) => string.IsNullOrEmpty(hex) ? "#d6c9ae" : hex;
        static string RichSafe(string text) => (text ?? "").Replace("<", "<​");

        static string Rich(TipLine l)
        {
            if (l.Parts == null) return "<color=" + Hex(l.Color) + ">" + RichSafe(l.Text) + "</color>";
            var sb = new StringBuilder();
            for (int i = 0; i + 1 < l.Parts.Length; i += 2)
                if (l.Parts[i].Length > 0) sb.Append("<color=").Append(Hex(l.Parts[i + 1])).Append('>').Append(RichSafe(l.Parts[i])).Append("</color>");
            return sb.ToString();
        }

        // ------------------------------------------------------------------------------------ tooltip
        void ItemTipGui(float w, float h)
        {
            var e = Event.current;
            if (e.type != EventType.Repaint) return;
            var tips = session.Tips;
            if (hoverTipFrame == Time.frameCount) { tips.HoverEnded(); DrawTipBox(hoverTip, hoverExtra, hoverNote, w, h); return; }   // a social window's tooltip (ShowTip)
            if (ItemSlots.HoverFrame != Time.frameCount || ItemSlots.HoverItem == null) { tips.HoverEnded(); return; }
            var it = ItemSlots.HoverItem;
            var pos = ItemSlots.HoverPos;
            // the server wants the slot on the page the window shows
            if (pos.X == 0xFFFF && pos.Y >= 0x40 && session.Parser.Containers.TryGetValue((byte)(pos.Y - 0x40), out var cont))
                pos = new Pos(pos.X, pos.Y, pos.Z - cont.FirstIndex);
            var ident = ItemTips.Describe(it, pos);
            var tip = tips.Lookup(ident, session.Now);
            if (tip == null) return;
            DrawTipBox(tip, WornCompareRows(tip, ident), null, w, h);
        }

        /// <summary>The Ctrl compare and the Alt help rows of an item tooltip (game_itemtooltip): worn items of the same kind come from the tip cache, asked at once.</summary>
        List<TipLine> WornCompareRows(object tip, TipIdent hovered)
        {
            bool ctrl = Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl);
            bool alt = Input.GetKey(KeyCode.LeftAlt) || Input.GetKey(KeyCode.RightAlt);
            var others = new List<object>();
            bool waiting = false;
            if (ctrl && ItemCompare.Comparable(tip))
            {
                var bySlot = new Dictionary<int, object>();
                var keys = new Dictionary<int, string>();
                var inv = session.Parser.Inventory;
                foreach (int slot in ItemCompare.Slots(tip))
                {
                    if (slot < 1 || slot >= inv.Length || inv[slot] == null) continue;
                    var d = ItemTips.Describe(inv[slot], GameSession.InventoryPos(slot));
                    var worn = session.Tips.Quick(d, session.Now, out bool w);
                    waiting |= w;
                    bySlot[slot] = worn; keys[slot] = d.Key;
                }
                others = ItemCompare.CompareWith(tip, bySlot, hovered.Key, keys);
            }
            compareSide = others;   // the worn items of the same kind are drawn as plates beside the main one (game_itemtooltip panels)
            return ItemCompare.ExtraRows(tip, ctrl, alt, others, waiting);
        }

        // a window (market row, inspect slot, chat link) asks for a tooltip for this frame: a tip table with extra lines under it, or just a note
        object hoverTip;
        List<TipLine> hoverExtra;
        string hoverNote;
        int hoverTipFrame = -1;

        public void ShowTip(object tip, List<TipLine> extra = null, string note = null)
        {
            hoverTip = tip; hoverExtra = extra; hoverNote = note; hoverTipFrame = Time.frameCount;
        }

        /// <summary>The worn items' tips of the Ctrl compare for this frame (side plates), cleared when drawn.</summary>
        List<object> compareSide = new List<object>();

        /// <summary>One tooltip plate: its height for a tip and its lines.</summary>
        float PlateHeight(object tip, List<TipLine> lines)
        {
            float height = 8f * 2 + (tip != null ? 22 : 0);
            foreach (var l in lines) height += 16f + (l.Sep ? 6 : 0);
            return height;
        }

        void DrawPlate(Rect r, object tip, List<TipLine> lines)
        {
            const float Pad = 8f, Line = 16f;
            string name = tip != null ? TipLines.Title(Json.Text(tip, "name")) : "";
            int count = tip != null ? Json.Int(tip, "count", 1) : 1;
            if (count > 1) name += " x" + count;
            Fill(new Rect(r.x - 1, r.y - 1, r.width + 2, r.height + 2), new Color(0.5f, 0.4f, 0.2f, 0.9f));
            Fill(r, new Color(0.05f, 0.04f, 0.06f, 0.97f));
            float y = r.y + Pad;
            if (tip != null)
            {
                GUI.Label(new Rect(r.x + Pad, y, r.width - 2 * Pad, 22), "<color=" + Hex(TipLines.TitleColor(tip)) + ">" + RichSafe(name) + "</color>", tipTitleStyle);
                y += 22;
            }
            foreach (var l in lines)
            {
                if (l.Sep) { Fill(new Rect(r.x + Pad, y + 2, r.width - 2 * Pad, 1), new Color(1f, 1f, 1f, 0.12f)); y += 6; }
                GUI.Label(new Rect(r.x + Pad, y, r.width - 2 * Pad, Line + 2), Rich(l), tipStyle);
                y += Line;
            }
        }

        void DrawTipCardBox(object tip, List<TipLine> extra, string note, float w, float h)
        {
            var card = TipCard.Build(tip, session.Parser.Level);
            int count = Json.Int(tip, "count", 1);
            if (count > 1) card.Title += " x" + count;
            var notes = new List<TipLine>();
            if (note != null) notes.Add(new TipLine { Text = note, Color = TipLines.Text, Sep = true });
            if (extra != null) notes.AddRange(extra);
            const float Width = 320f;
            var boxes = PlanCard(card, Width, notes, out float height);
            Vector2 m = MouseUi();
            var r = new Rect(m.x + 16, m.y + 16, Width, height);
            if (r.xMax > w - 4) r.x = Mathf.Max(4, m.x - 16 - Width);
            if (r.yMax > h - 4) r.y = Mathf.Max(4, h - 4 - height);
            var side = new List<KeyValuePair<object, List<TipLine>>>();
            foreach (object o in compareSide)
                if (o != null) side.Add(new KeyValuePair<object, List<TipLine>>(o, TipLines.Lines(o, session.Parser.Level)));
            compareSide = new List<object>();
            var rects = TooltipPlates.Place(r.x, r.y, Width, height, w, h, side.Count, i => PlateHeight(side[i].Key, side[i].Value));
            DrawCard(r, card, boxes);
            for (int i = 0; i < side.Count; i++) DrawPlate(new Rect(rects[i].x, rects[i].y, rects[i].width, rects[i].height), side[i].Key, side[i].Value);
        }

        void DrawTipBox(object tip, List<TipLine> extra, string note, float w, float h)
        {
            if (tipStyle == null)
            {
                tipStyle = new GUIStyle(small) { fontSize = 12, richText = true, wordWrap = false, clipping = TextClipping.Clip };
                tipTitleStyle = new GUIStyle(small) { fontSize = 15, fontStyle = FontStyle.Bold, richText = true, wordWrap = false };
            }
            if (tip != null)
            {
                // phase 8 track A: the card layout of game_itemtooltip (head, stat tiles, modifier groups, chips, foot, rarity glow)
                DrawTipCardBox(tip, extra, note, w, h);
                return;
            }
            var lines = tip != null ? TipLines.Lines(tip, session.Parser.Level) : new List<TipLine>();
            if (note != null) lines.Add(new TipLine { Text = note, Color = TipLines.Text });
            if (extra != null) lines.AddRange(extra);
            const float Width = 300f;
            float height = PlateHeight(tip, lines);
            Vector2 m = MouseUi();
            var r = new Rect(m.x + 16, m.y + 16, Width, height);
            if (r.xMax > w - 4) r.x = Mathf.Max(4, m.x - 16 - Width);
            if (r.yMax > h - 4) r.y = Mathf.Max(4, h - 4 - height);
            // the worn items of the Ctrl compare as plates beside the main one, on the side with room (TooltipPlates)
            var side = new List<KeyValuePair<object, List<TipLine>>>();
            foreach (object o in compareSide)
                if (o != null) side.Add(new KeyValuePair<object, List<TipLine>>(o, TipLines.Lines(o, session.Parser.Level)));
            compareSide = new List<object>();
            var rects = TooltipPlates.Place(r.x, r.y, Width, height, w, h, side.Count, i => PlateHeight(side[i].Key, side[i].Value));
            DrawPlate(r, tip, lines);
            for (int i = 0; i < side.Count; i++) DrawPlate(new Rect(rects[i].x, rects[i].y, rects[i].width, rects[i].height), side[i].Key, side[i].Value);
        }

        // ------------------------------------------------------------------------------------ modal window
        void DialogBox(int id, Rect box, string title, System.Action<Rect> body)
        {
            uiRects.Add(Scaled(box, UiScale(UnityEngine.Screen.width, UnityEngine.Screen.height, UnityEngine.Screen.dpi)));
            GUI.Window(id, box, _ =>
            {
                Fill(new Rect(0, 0, box.width, box.height), new Color(0.04f, 0.03f, 0.05f, 0.97f));
                Fill(new Rect(0, 0, box.width, 24), new Color(0.16f, 0.09f, 0.06f, 1f));
                GUI.Label(new Rect(8, 2, box.width - 16, 22), RichSafe(title), titleStyle);
                body(new Rect(8, 30, box.width - 16, box.height - 38));
            }, GUIContent.none, GUIStyle.none);
            GUI.BringWindowToFront(id);
        }

        void ModalGui(float w, float h, float scale)
        {
            var m = session.Modals.Current;
            if (m == null) { modalFor = 0; return; }
            if (modalFor != m.Id) { modalFor = m.Id; modalChoice = ModalWindows.NoChoice; dlgScroll = Vector2.zero; }
            if (dlgStyle == null) dlgStyle = new GUIStyle(small) { fontSize = 13, wordWrap = true };
            const float Width = 380f, Btn = 28f;
            float msgH = Mathf.Max(20f, dlgStyle.CalcHeight(new GUIContent(m.Message), Width - 16));
            float listH = m.Choices.Count > 0 ? Mathf.Min(150f, m.Choices.Count * 24f + 4f) : 0f;
            float height = 30 + msgH + (listH > 0 ? listH + 8 : 0) + Btn + 16;
            var box = new Rect((w - Width) / 2, Mathf.Max(20, (h - height) / 3), Width, height);
            var e = Event.current;
            bool answered = false;
            DialogBox(ModalWindowId, box, m.Title, inner =>
            {
                GUI.Label(new Rect(inner.x, inner.y, inner.width, msgH), RichSafe(m.Message), dlgStyle);
                float y = inner.y + msgH + 4;
                if (m.Choices.Count > 0)
                {
                    var view = new Rect(inner.x, y, inner.width, listH);
                    dlgScroll = GUI.BeginScrollView(view, dlgScroll, new Rect(0, 0, inner.width - 18, m.Choices.Count * 24f));
                    for (int i = 0; i < m.Choices.Count; i++)
                    {
                        var c = m.Choices[i];
                        bool on = modalChoice == c.Id;
                        if (GUI.Toggle(new Rect(0, i * 24f, inner.width - 18, 22), on, RichSafe(c.Text), GUI.skin.button) && !on) modalChoice = c.Id;
                    }
                    GUI.EndScrollView();
                    y += listH + 8;
                }
                int n = Mathf.Max(1, m.Buttons.Count);
                float bw = (inner.width - (n - 1) * 6) / n;
                for (int i = 0; i < m.Buttons.Count; i++)
                    if (GUI.Button(new Rect(inner.x + i * (bw + 6), y, bw, Btn), RichSafe(m.Buttons[i].Text))) { session.Modals.Answer(m.Buttons[i].Id, modalChoice); answered = true; return; }
            });
            if (answered) return;
            if (e.type == EventType.KeyDown)
            {
                if (e.keyCode == KeyCode.Escape) { session.Modals.Cancel(); e.Use(); }
                else if (e.keyCode == KeyCode.Return || e.keyCode == KeyCode.KeypadEnter) { session.Modals.Answer(m.EnterButton, modalChoice); e.Use(); }
            }
        }

        // ------------------------------------------------------------------------------------ text window (books, signs, house door lists)
        void TextWindowGui(float w, float h, float scale)
        {
            var t = session.Texts.Current;
            if (t == null) { textFor = 0; return; }
            if (textFor != t.Id)
            {
                textFor = t.Id; textBuf = t.Text; dlgScroll = Vector2.zero;
            }
            if (dlgStyle == null) dlgStyle = new GUIStyle(small) { fontSize = 13, wordWrap = true };
            var box = new Rect((w - 420) / 2, Mathf.Max(20, h / 2 - 190), 420, 380);
            var e = Event.current;
            bool closed = false;
            DialogBox(TextWindowId, box, t.House ? Loc.T("Door list") : t.Writer.Length > 0 || t.CanWrite ? Loc.T("Writing") : Loc.T("Text"), inner =>
            {
                float y = inner.y;
                if (t.Item != null)
                {
                    var pic = new Rect(inner.x, y, 36, 36);
                    Fill(pic, new Color(0.11f, 0.09f, 0.12f, 1f));
                    DrawItem(pic, (ushort)t.Item.Id, t.Item.Count);
                    ItemSlots.Frame(pic, t.Item);
                }
                string by = t.Writer.Length > 0 ? Loc.T("Written by {0}", t.Writer) + (t.Date.Length > 0 ? "  " + t.Date : "") : t.CanWrite ? Loc.T("Up to {0} characters.", t.MaxLength) : "";
                GUI.Label(new Rect(inner.x + 44, y + 4, inner.width - 44, 30), RichSafe(by), dlgStyle);
                y += 42;
                var area = new Rect(inner.x, y, inner.width, inner.height - 42 - 40);
                if (t.CanWrite)
                {
                    GUI.SetNextControlName("textWindow");
                    textBuf = GUI.TextArea(area, textBuf, Mathf.Max(1, t.MaxLength));
                    if (GUI.GetNameOfFocusedControl() == "textWindow") MarkTextEditing();
                }
                else
                {
                    float need = Mathf.Max(area.height, dlgStyle.CalcHeight(new GUIContent(t.Text), area.width - 20));
                    dlgScroll = GUI.BeginScrollView(area, dlgScroll, new Rect(0, 0, area.width - 18, need));
                    GUI.Label(new Rect(0, 0, area.width - 18, need), RichSafe(t.Text), dlgStyle);
                    GUI.EndScrollView();
                }
                float by2 = inner.yMax - 32;
                if (t.CanWrite)
                {
                    if (GUI.Button(new Rect(inner.x, by2, inner.width / 2 - 3, 30), Loc.T("Ok"))) { session.Texts.Close(textBuf); closed = true; return; }
                    if (GUI.Button(new Rect(inner.x + inner.width / 2 + 3, by2, inner.width / 2 - 3, 30), Loc.T("Cancel"))) { session.Texts.Close(null); closed = true; return; }
                }
                else if (GUI.Button(new Rect(inner.x, by2, inner.width, 30), Loc.T("Close"))) { session.Texts.Close(null); closed = true; }
            });
            if (closed) return;
            if (e.type == EventType.KeyDown && e.keyCode == KeyCode.Escape) { session.Texts.Close(null); e.Use(); }
        }
    }
}
