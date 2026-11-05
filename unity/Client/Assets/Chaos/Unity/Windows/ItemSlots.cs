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
        static GUIStyle faintStyle;

        public static void Cancel() { dragging = false; }

        /// <summary>The lowest container id the server is not using, for opening a bag.</summary>
        static byte FreeContainerId(ChaosApp app)
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
            if (e.type == EventType.MouseDown && e.button == 1 && it != null)
            {
                app.Session?.UseItem(where, (ushort)it.Id, stackPos, FreeContainerId(app));
                e.Use();
            }
            else if (e.type == EventType.MouseDown && e.button == 0 && it != null)
            {
                dragging = true; srcPos = where; srcId = (ushort)it.Id; srcStack = stackPos; srcCount = it.Count;
            }
            else if (e.type == EventType.MouseUp && e.button == 0 && dragging)
            {
                if (srcPos != where)
                    app.Session?.MoveItem(srcPos, srcId, srcStack, where, (byte)Mathf.Clamp(srcCount, 1, 100));
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
