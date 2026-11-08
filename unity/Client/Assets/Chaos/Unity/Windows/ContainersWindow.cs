using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>Every open container, stacked: name, up and close buttons, a grid of slots (4 per row). Scrolls when long.
    /// Opens by itself when the server opens a container.</summary>
    public sealed class ContainersWindow : GameWindow
    {
        public override string Title => "Containers";
        public override KeyCode Hotkey => KeyCode.O;

        const float SlotSize = 34, Gap = 2, Head = 22, Between = 6;
        const int PerRow = 4;
        Vector2 scroll;
        // the container objects seen so far: a new object means the server opened (or reopened) one
        readonly Dictionary<byte, Container> known = new Dictionary<byte, Container>();
        readonly List<byte> gone = new List<byte>();

        protected override Rect Place(float w, float h)
        {
            float top = 48 + EquipmentWindow.Height + 8;
            return new Rect(w - 198, top, 188, Mathf.Clamp(h - top - 8, 160, 380));
        }

        public override void Reset() { known.Clear(); scroll = Vector2.zero; ItemSlots.Cancel(); }

        public override void Tick(ChaosApp app)
        {
            var open = app.Session?.Parser.Containers;
            if (open == null) return;
            foreach (var kv in open)
            {
                if (known.TryGetValue(kv.Key, out var old) && old == kv.Value) continue;
                known[kv.Key] = kv.Value;
                Open = true;
            }
            gone.Clear();
            foreach (var id in known.Keys) if (!open.ContainsKey(id)) gone.Add(id);
            foreach (var id in gone) known.Remove(id);
        }

        static int Rows(Container c) => (Mathf.Max(c.Capacity, c.Items.Count) + PerRow - 1) / PerRow;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var s = app.Session;
            if (s == null) return;
            var open = s.Parser.Containers;
            // copy the ids: the buttons below send packets, the dictionary changes on a later poll, not now
            var ids = new List<byte>(open.Keys);
            ids.Sort();
            if (ids.Count == 0)
            {
                GUI.Label(new Rect(inner.x + 4, inner.y + 4, inner.width - 8, 40), "No container is open.\nRight-click a bag to open it.", app.SmallStyle);
                ItemSlots.Ghost(app, new Rect(0, 0, Area.width, Area.height));
                return;
            }
            float contentH = 0;
            foreach (var id in ids) contentH += Head + Rows(open[id]) * (SlotSize + Gap) + Between;
            float viewW = inner.width - 20;
            scroll = GUI.BeginScrollView(inner, scroll, new Rect(0, 0, viewW, Mathf.Max(contentH, inner.height - 2)));
            float y = 0;
            foreach (var id in ids)
            {
                var c = open[id];
                ChaosApp.Fill(new Rect(0, y, viewW, Head - 2), new Color(0.16f, 0.09f, 0.06f, 0.9f));
                if (c.ItemId != 0) app.DrawItem(new Rect(1, y, Head - 2, Head - 2), c.ItemId, 0);
                GUI.Label(new Rect(Head, y - 1, viewW - Head - 44, Head), c.Name, app.SmallStyle);
                if (c.HasParent && GUI.Button(new Rect(viewW - 42, y, 20, Head - 2), "^")) s.UpContainer(c.Id);
                if (GUI.Button(new Rect(viewW - 20, y, 20, Head - 2), "x")) s.CloseContainer(c.Id);
                y += Head;
                int n = Mathf.Max(c.Capacity, c.Items.Count);
                for (int i = 0; i < n; i++)
                {
                    var r = new Rect((i % PerRow) * (SlotSize + Gap), y + (i / PerRow) * (SlotSize + Gap), SlotSize, SlotSize);
                    int slot = c.FirstIndex + i;
                    var it = i < c.Items.Count ? c.Items[i] : null;
                    ItemSlots.Slot(app, r, it, GameSession.ContainerPos(c.Id, slot), (byte)(slot & 0xFF), null);
                    if (it != null) ItemSlots.Frame(r, app.CardBorderColor(c.ItemId, it.Id));   // game_cardborder: a card in a deck bag
                }
                y += Rows(c) * (SlotSize + Gap) + Between;
            }
            GUI.EndScrollView();
            ItemSlots.Ghost(app, new Rect(0, 0, Area.width, Area.height));
        }
    }
}
