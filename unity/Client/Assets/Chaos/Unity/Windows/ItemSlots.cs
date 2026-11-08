using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>Item slot drawing and the drag and drop between windows (equipment and containers share it).
    /// Positions are window-local IMGUI coordinates, in UI units.</summary>
    static class ItemSlots
    {
        static bool dragging;
        static Pos srcPos;
        static ushort srcId;
        static byte srcStack;
        static int srcCount;
        static bool srcStackable;
        static GUIStyle faintStyle;

        /// <summary>The item under the pointer this frame (set by Slot on a repaint), for the tooltip drawn over the windows.</summary>
        public static Item HoverItem;
        public static Pos HoverPos;
        public static int HoverFrame = -1;

        /// <summary>A rarity frame (the unique colour for a unique), and a gold corner mark for a locked item. Draws nothing for a plain item.</summary>
        public static void Frame(Rect r, Item it)
        {
            string hex = ItemRarity.FrameColor(it);
            if (hex != null) Frame(r, hex);
            if (ItemRarity.IsLocked(it)) ChaosApp.Fill(new Rect(r.xMax - 7, r.y + 1, 6, 6), new Color(0.91f, 0.72f, 0.29f, 0.95f));
        }

        public static void Frame(Rect r, string hex)
        {
            if (hex == null || !ColorUtility.TryParseHtmlString(hex, out var c)) return;
            c.a = 0.95f;
            ChaosApp.Fill(new Rect(r.x, r.y, r.width, 2), c);
            ChaosApp.Fill(new Rect(r.x, r.yMax - 2, r.width, 2), c);
            ChaosApp.Fill(new Rect(r.x, r.y + 2, 2, r.height - 4), c);
            ChaosApp.Fill(new Rect(r.xMax - 2, r.y + 2, 2, r.height - 4), c);
        }

        /// <summary>A drop target: a left release over r with an item being dragged hands the item to take and ends the drag. True when it did.</summary>
        public static bool Drop(Rect r, System.Action<Pos, ushort, byte, int> take)
        {
            var e = Event.current;
            if (!dragging || e.type != EventType.MouseUp || e.button != 0 || !r.Contains(e.mousePosition)) return false;
            dragging = false;
            take(srcPos, srcId, srcStack, srcCount);
            e.Use();
            return true;
        }

        public static bool Dragging => dragging;

        public static void Cancel() { dragging = false; }

        /// <summary>The lowest container id the server is not using, for opening a bag.</summary>
        internal static byte FreeContainerId(ChaosApp app)
        {
            var open = app.Session?.Parser.Containers;
            for (byte i = 0; i < 16; i++) if (open == null || !open.ContainsKey(i)) return i;
            return 0;
        }

        /// <summary>One slot. it may be null (empty). where is its server position, stackPos what the server expects with it.
        /// Right-click uses the item. A left press starts a drag, a left release over the slot drops it here.</summary>
        public static void Slot(ChaosApp app, Rect r, Item it, Pos where, byte stackPos, string faint)
        {
            var e = Event.current;
            bool over = r.Contains(e.mousePosition);
            if (e.type == EventType.Repaint)
            {
                bool src = dragging && srcPos == where;
                ChaosApp.Fill(new Rect(r.x - 1, r.y - 1, r.width + 2, r.height + 2), new Color(0f, 0f, 0f, 0.8f));
                ChaosApp.Fill(r, over && dragging ? new Color(0.30f, 0.22f, 0.12f, 1f) : new Color(0.11f, 0.09f, 0.12f, 1f));
                if (it != null) app.DrawItem(new Rect(r.x + 1, r.y + 1, r.width - 2, r.height - 2), (ushort)it.Id, it.Count);
                if (it != null) Frame(new Rect(r.x + 1, r.y + 1, r.width - 2, r.height - 2), it);
                if (it != null && over && !dragging) { HoverItem = it; HoverPos = where; HoverFrame = Time.frameCount; }
                else if (!string.IsNullOrEmpty(faint))
                {
                    if (faintStyle == null)
                    {
                        faintStyle = new GUIStyle(app.SmallStyle) { alignment = TextAnchor.MiddleCenter, fontSize = 11 };
                        faintStyle.normal.textColor = new Color(1f, 1f, 1f, 0.28f);
                    }
                    GUI.Label(r, faint, faintStyle);
                }
                if (src) ChaosApp.Fill(r, new Color(1f, 1f, 1f, 0.18f));
                else if (over && !dragging) ChaosApp.Fill(r, new Color(1f, 1f, 1f, 0.08f));
                return;
            }
            if (!over) return;
            var iref = new ItemRef(where, stackPos, it);
            if (e.type == EventType.MouseDown && app.Crosshair.Active && it != null && e.button <= 1)
            {
                // "Use with ..." or "Trade with ...": this slot is the target (a right click ends it)
                if (e.button == 0) app.CrosshairClick(iref, null); else app.Crosshair.Cancel();
                e.Use();
            }
            else if (e.type == EventType.MouseDown && e.button == 1 && it != null && e.control)
            {
                app.ShowItemMenu(iref, app.MouseUi());
                e.Use();
            }
            else if (e.type == EventType.MouseDown && e.button == 1 && it != null)
            {
                app.RightClickItem(iref);   // a use, or "Use with ..." for a multi-use item (ChaosApp.Play.cs)
                e.Use();
            }
            else if (e.type == EventType.MouseDown && e.button == 0 && it != null && e.shift && !e.control)
            {
                // Shift + click: an item link while the chat line is being written, else a look (0x8C)
                if (!app.ChatFocused || !app.LinkItem(it, where)) app.Session?.Look(iref);
                e.Use();
            }
            else if (e.type == EventType.MouseDown && e.button == 0 && it != null)
            {
                dragging = true; srcPos = where; srcId = (ushort)it.Id; srcStack = stackPos; srcCount = it.Count; srcStackable = it.Type != null && it.Type.Stackable;
            }
            else if (e.type == EventType.MouseUp && e.button == 0 && dragging)
            {
                if (srcPos != where)
                {
                    // a stackable with more than one asks how many (the split stack dialog); Ctrl at the drop moves the whole stack
                    if (SplitStackModel.Asks(srcStackable, srcCount, e.control)) app.AskSplit(srcPos, srcId, srcStack, where, srcCount);
                    else app.Session?.MoveItem(srcPos, srcId, srcStack, where, SplitStackModel.Whole(srcCount));
                }
                dragging = false;
                e.Use();
            }
        }

        /// <summary>Call last in a window body: draws the dragged item at the pointer and ends a drag when the button is up.</summary>
        public static void Ghost(ChaosApp app, Rect window)
        {
            if (!dragging) return;
            var e = Event.current;
            if (e.type != EventType.Repaint) return;
            if (!Input.GetMouseButton(0)) { dragging = false; return; }
            if (window.Contains(e.mousePosition))
                app.DrawItem(new Rect(e.mousePosition.x - 16, e.mousePosition.y - 16, 32, 32), srcId, srcCount);
        }
    }
}
