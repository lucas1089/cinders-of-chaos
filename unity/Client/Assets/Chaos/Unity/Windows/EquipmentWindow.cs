using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>The ten equipment slots (the badge slot 13 in place of ammo) as a paper doll, plus capacity and soul. Right-click uses an item (a bag opens).
    /// Phase 6 (the bag panel of the main client, game_bagpanel): a tab row on top (Equip, Quest, Stats, Shop open their windows), the coins of the open bags
    /// (gold, platinum, crystal and the total) and the Chaos Coins, and the character's outfit beside the numbers.</summary>
    public sealed class EquipmentWindow : GameWindow
    {
        public override string Title => "Equipment";
        public override KeyCode Hotkey => KeyCode.E;

        // server slot numbers: 1 head, 2 necklace, 3 backpack, 4 armor, 5 right hand, 6 left hand, 7 legs, 8 feet, 9 ring, 13 badge (src-patch 0058: where the ammo slot was)
        static readonly int[,] Layout =
        {
            { 2, 1, 3 },
            { 5, 4, 6 },
            { 9, 7, 13 },
            { 0, 8, 0 },
        };
        static readonly string[] Names = { "", "Head", "Neck", "Bag", "Armor", "Right", "Left", "Legs", "Feet", "Ring", "", "", "", "Badge" };
        const float SlotSize = 38, Gap = 6, TabH = 22;
        /// <summary>The height of the window: containers are placed under it (ContainersWindow).</summary>
        public const float Height = 376;

        GUIStyle tabStyle, tinyStyle;

        protected override Rect Place(float w, float h) => new Rect(w - 178, 48, 168, Height);

        protected override void Body(ChaosApp app, Rect inner)
        {
            var s = app.Session;
            if (s == null) return;
            if (tabStyle == null)
            {
                tabStyle = new GUIStyle(GUI.skin.button) { fontSize = 11 };
                tinyStyle = new GUIStyle(app.SmallStyle) { fontSize = 12 };
            }
            var inv = s.Parser.Inventory;
            Tabs(app, inner);
            float gridW = 3 * SlotSize + 2 * Gap;
            float x0 = inner.x + (inner.width - gridW) / 2, y0 = inner.y + TabH + 8;
            for (int row = 0; row < 4; row++)
                for (int col = 0; col < 3; col++)
                {
                    int slot = Layout[row, col];
                    if (slot == 0) continue;
                    var r = new Rect(x0 + col * (SlotSize + Gap), y0 + row * (SlotSize + Gap), SlotSize, SlotSize);
                    ItemSlots.Slot(app, r, inv[slot], GameSession.InventoryPos(slot), (byte)slot, BadgeSlot.SlotTooltip(slot, inv[slot] != null) ?? Names[slot]);
                }
            float y = y0 + 4 * (SlotSize + Gap) + 2;
            // the numbers on the left, the character on the right
            float figure = 64;
            var pic = new Rect(inner.xMax - figure - 4, y, figure, figure);
            ChaosApp.Fill(pic, new Color(0f, 0f, 0f, 0.45f));
            var me = app.Session?.Parser != null ? app.World?.Player : null;
            if (me != null) app.DrawOutfit(new Rect(pic.x + 4, pic.y + 4, pic.width - 8, pic.height - 8), me.Outfit);
            float lw = inner.width - figure - 14;
            GUI.Label(new Rect(inner.x + 6, y, lw, 18), Loc.T("Cap: {0}", s.Parser.FreeCap / 100u), tinyStyle);
            GUI.Label(new Rect(inner.x + 6, y + 16, lw, 18), Loc.T("Soul: {0}", s.Parser.Soul), tinyStyle);
            long gold = BagPanel.Gold(OpenCoins(s));
            var goldRect = new Rect(inner.x + 6, y + 32, lw, 18);
            GUI.Label(goldRect, Loc.T("Gold: {0}", Plate.Short(gold)), tinyStyle);
            var counts = BagPanel.CoinCounts(OpenCoins(s));
            GUI.Label(new Rect(inner.x + 6, y + 48, inner.width - 12, 18), Loc.T("{0} gold, {1} platinum, {2} crystal", counts[0], counts[1], counts[2]), tinyStyle);
            double coins = s.Store != null ? s.Store.Coins : -1;
            if (coins >= 0) GUI.Label(new Rect(inner.x + 6, y + 64, inner.width - 12, 18), Loc.T("Chaos Coins: {0}", Plate.Short(coins)), tinyStyle);
            PurseRow(app, new Rect(inner.x + 6, y + 86, inner.width - 12, 22));
            ItemSlots.Ghost(app, new Rect(0, 0, Area.width, Area.height));
        }

        /// <summary>The Purse button under the equipment (game_bagpanel, 2026-11-09): what is bought in the store is delivered to the purse (inventory slot 11), so the player
        /// needs a way to open it. The request is the main client's: use the item of that slot (Core/Phase29.cs PurseButton, GameSession.UsePurse). With no purse the chat says so.</summary>
        void PurseRow(ChaosApp app, Rect r)
        {
            var s = app.Session;
            bool has = PurseButton.Has(s.Parser.Inventory);
            var old = GUI.color;
            if (!has) GUI.color = new Color(1f, 1f, 1f, 0.6f);
            if (GUI.Button(r, new GUIContent(Loc.T("Purse"), PurseButton.Tooltip), tabStyle))
            {
                if (!s.UsePurse(ItemSlots.FreeContainerId(app))) app.PostLine(PurseButton.NoPurse);
            }
            GUI.color = old;
            if (r.Contains(Event.current.mousePosition) && Event.current.type == EventType.Repaint)
            {
                var tip = new GUIStyle(app.SmallStyle) { fontSize = 11, wordWrap = true };
                var tr = new Rect(r.x - 6, r.y - 44, r.width + 12, 40);
                ChaosApp.Fill(tr, new Color(0.03f, 0.02f, 0.04f, 0.95f));
                GUI.Label(new Rect(tr.x + 4, tr.y + 2, tr.width - 8, tr.height - 4), PurseButton.Tooltip, tip);
            }
        }

        /// <summary>Gold, platinum and crystal coins in the open containers, as (client id, count) pairs.</summary>
        static IEnumerable<KeyValuePair<int, int>> OpenCoins(GameSession s)
        {
            foreach (var c in s.Parser.Containers.Values)
                foreach (var it in c.Items)
                    if (it != null && BagPanel.Coins.ContainsKey(it.Id)) yield return new KeyValuePair<int, int>(it.Id, it.Count);
        }

        /// <summary>The tab row: Equip is this window; the others open the window of the same name (shown only when the client has it).</summary>
        void Tabs(ChaosApp app, Rect inner)
        {
            var tabs = BagPanel.Tabs(app.HasWindowNamed);
            var texts = new float[tabs.Count];
            for (int i = 0; i < tabs.Count; i++) texts[i] = tabStyle.CalcSize(new GUIContent(Loc.T(tabs[i].Text))).x;
            var widths = BagPanel.TabWidths(texts, inner.width);
            float x = inner.x;
            for (int i = 0; i < tabs.Count; i++)
            {
                var r = new Rect(x, inner.y, widths[i], TabH);
                bool equip = tabs[i].Id == "equip";
                var old = GUI.color;
                if (equip) GUI.color = new Color(1f, 0.9f, 0.6f);
                if (GUI.Button(r, Loc.T(tabs[i].Text), tabStyle) && !equip) app.ToggleWindowNamed(tabs[i].Window);
                GUI.color = old;
                x += widths[i] + 1;
            }
        }
    }
}
