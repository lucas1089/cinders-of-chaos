using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>The ten equipment slots as a paper doll, plus capacity and soul. Right-click uses an item (a bag opens).</summary>
    public sealed class EquipmentWindow : GameWindow
    {
        public override string Title => "Equipment";
        public override KeyCode Hotkey => KeyCode.E;

        // server slot numbers: 1 head, 2 necklace, 3 backpack, 4 armor, 5 right hand, 6 left hand, 7 legs, 8 feet, 9 ring, 10 ammo
        static readonly int[,] Layout =
        {
            { 2, 1, 3 },
            { 5, 4, 6 },
            { 9, 7, 10 },
            { 0, 8, 0 },
        };
        static readonly string[] Names = { "", "Head", "Neck", "Bag", "Armor", "Right", "Left", "Legs", "Feet", "Ring", "Ammo" };
        const float SlotSize = 38, Gap = 6;

        protected override Rect Place(float w, float h) => new Rect(w - 178, 48, 168, 270);

        protected override void Body(ChaosApp app, Rect inner)
        {
            var s = app.Session;
            if (s == null) return;
            var inv = s.Parser.Inventory;
            float gridW = 3 * SlotSize + 2 * Gap;
            float x0 = inner.x + (inner.width - gridW) / 2, y0 = inner.y + 4;
            for (int row = 0; row < 4; row++)
                for (int col = 0; col < 3; col++)
                {
                    int slot = Layout[row, col];
                    if (slot == 0) continue;
                    var r = new Rect(x0 + col * (SlotSize + Gap), y0 + row * (SlotSize + Gap), SlotSize, SlotSize);
                    ItemSlots.Slot(app, r, inv[slot], GameSession.InventoryPos(slot), (byte)slot, Names[slot]);
                }
            float y = y0 + 4 * (SlotSize + Gap) + 2;
            GUI.Label(new Rect(inner.x + 6, y, inner.width - 12, 20), "Cap: " + (s.Parser.FreeCap / 100u), app.SmallStyle);
            GUI.Label(new Rect(inner.x + 6, y + 20, inner.width - 12, 20), "Soul: " + s.Parser.Soul, app.SmallStyle);
            ItemSlots.Ghost(app, new Rect(0, 0, Area.width, Area.height));
        }
    }
}
