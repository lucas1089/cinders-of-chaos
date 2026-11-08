// The slots of the hotkey bar (O433 phase 6, track U): a slot says a line (spell words or any text, as before) or holds an item.
// An item slot shows the item's sprite and how many you carry, and a press uses it the way the main client's hotbar does
// (game_hotbar sits on the base action bar: use the item from the equipment or an open bag, use it on yourself, use it on the
// monster you attack, or "use with" a crosshair for a rune). The same packets as the item menu: 0x82 use, 0x84 use on a creature,
// and the crosshair of ChaosApp.Play.cs for 0x83 / 0x84. The slot is saved as one string per slot: plain text as before, an item as
// "item:<client id>:<mode>", so a bar saved by an older client still loads.
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    public enum HotKind { Empty, Text, Item }

    /// <summary>What a press of an item slot does.</summary>
    public enum ItemMode { Use, OnSelf, OnTarget, WithCrosshair }

    public struct HotSlot
    {
        public HotKind Kind;
        public string Text;
        public int ItemId;
        public ItemMode Mode;
        public bool IsEmpty => Kind == HotKind.Empty;
    }

    public enum HotOutcome { None, Said, Used, UsedOnSelf, UsedOnTarget, Crosshair, NotCarried, NoTarget }

    /// <summary>What the hotbar needs from the game: the carried items, the target, the actions.</summary>
    public interface IHotbarHost
    {
        int CountItem(int clientId);
        bool UseItem(int clientId);
        bool UseOnCreature(int clientId, uint creature);
        bool StartCrosshair(int clientId);
        uint AttackTarget { get; }
        uint SelfId { get; }
        void Say(string text);
    }

    public sealed class HotbarModel
    {
        public const int Count = 12;
        public const string ItemPrefix = "item:";
        readonly HotSlot[] slots = new HotSlot[Count];

        public HotSlot this[int i] => i >= 0 && i < Count ? slots[i] : default(HotSlot);

        /// <summary>The slot a saved string means: empty, a line to say, or an item with its mode ("item:3160:2"; a mode out of range or missing is Use).</summary>
        public static HotSlot Parse(string s)
        {
            if (string.IsNullOrWhiteSpace(s)) return default(HotSlot);
            if (s.StartsWith(ItemPrefix, StringComparison.Ordinal))
            {
                string[] p = s.Substring(ItemPrefix.Length).Split(':');
                if (p.Length >= 1 && int.TryParse(p[0], NumberStyles.None, CultureInfo.InvariantCulture, out int id) && id > 0 && id <= 65535)
                {
                    var mode = ItemMode.Use;
                    if (p.Length >= 2 && int.TryParse(p[1], NumberStyles.None, CultureInfo.InvariantCulture, out int m) && m >= 0 && m <= (int)ItemMode.WithCrosshair) mode = (ItemMode)m;
                    return new HotSlot { Kind = HotKind.Item, ItemId = id, Mode = mode, Text = "" };
                }
            }
            return new HotSlot { Kind = HotKind.Text, Text = s };
        }

        public static string Encode(HotSlot s)
        {
            switch (s.Kind)
            {
                case HotKind.Text: return s.Text ?? "";
                case HotKind.Item: return ItemPrefix + s.ItemId.ToString(CultureInfo.InvariantCulture) + ":" + ((int)s.Mode).ToString(CultureInfo.InvariantCulture);
                default: return "";
            }
        }

        public string Saved(int i) => Encode(this[i]);

        public void Load(Func<int, string> get)
        {
            for (int i = 0; i < Count; i++) slots[i] = Parse(get(i));
        }

        public void Clear() { for (int i = 0; i < Count; i++) slots[i] = default(HotSlot); }

        public bool SetText(int i, string text)
        {
            if (i < 0 || i >= Count) return false;
            slots[i] = Parse(text ?? "");
            // text typed by hand that looks like an item slot stays a line to say: only SetItem makes an item
            if (slots[i].Kind == HotKind.Item) slots[i] = new HotSlot { Kind = HotKind.Text, Text = text };
            return true;
        }

        public bool SetItem(int i, int clientId, bool multiUse)
        {
            if (i < 0 || i >= Count || clientId <= 0 || clientId > 65535) return false;
            slots[i] = new HotSlot { Kind = HotKind.Item, ItemId = clientId, Mode = DefaultMode(multiUse), Text = "" };
            return true;
        }

        public bool SetMode(int i, ItemMode mode)
        {
            if (i < 0 || i >= Count || slots[i].Kind != HotKind.Item) return false;
            slots[i].Mode = mode;
            return true;
        }

        public void ClearSlot(int i) { if (i >= 0 && i < Count) slots[i] = default(HotSlot); }

        /// <summary>The first empty slot, -1 when all twelve are taken.</summary>
        public int FirstEmpty()
        {
            for (int i = 0; i < Count; i++) if (slots[i].IsEmpty) return i;
            return -1;
        }

        /// <summary>A rune, a potion or any multi-use item starts a "use with" by default; other items are used.</summary>
        public static ItemMode DefaultMode(bool multiUse) => multiUse ? ItemMode.WithCrosshair : ItemMode.Use;

        public static readonly ItemMode[] Modes = { ItemMode.Use, ItemMode.OnSelf, ItemMode.OnTarget, ItemMode.WithCrosshair };

        /// <summary>The menu text of a mode (English keys; the window runs them through Loc.T).</summary>
        public static string ModeLabel(ItemMode m)
        {
            switch (m)
            {
                case ItemMode.OnSelf: return "Use on yourself";
                case ItemMode.OnTarget: return "Use on target";
                case ItemMode.WithCrosshair: return "Use with ...";
                default: return "Use";
            }
        }

        /// <summary>The short mark drawn in the corner of an item slot.</summary>
        public static string ModeMark(ItemMode m)
        {
            switch (m)
            {
                case ItemMode.OnSelf: return "S";
                case ItemMode.OnTarget: return "T";
                case ItemMode.WithCrosshair: return "+";
                default: return "";
            }
        }

        /// <summary>A press of a slot. A line is said (a spell's words cast it); an item goes by its mode: "on target" needs the monster you attack (the main client's action bar does
        /// nothing without one), the crosshair needs the item in the equipment or an open bag, like every other use.</summary>
        public HotOutcome Press(int i, IHotbarHost host)
        {
            var s = this[i];
            if (host == null || s.IsEmpty) return HotOutcome.None;
            if (s.Kind == HotKind.Text)
            {
                host.Say(s.Text);
                return HotOutcome.Said;
            }
            if (host.CountItem(s.ItemId) <= 0) return HotOutcome.NotCarried;
            switch (s.Mode)
            {
                case ItemMode.OnSelf:
                    return host.SelfId != 0 && host.UseOnCreature(s.ItemId, host.SelfId) ? HotOutcome.UsedOnSelf : HotOutcome.NotCarried;
                case ItemMode.OnTarget:
                    if (host.AttackTarget == 0) return HotOutcome.NoTarget;
                    return host.UseOnCreature(s.ItemId, host.AttackTarget) ? HotOutcome.UsedOnTarget : HotOutcome.NotCarried;
                case ItemMode.WithCrosshair:
                    return host.StartCrosshair(s.ItemId) ? HotOutcome.Crosshair : HotOutcome.NotCarried;
                default:
                    return host.UseItem(s.ItemId) ? HotOutcome.Used : HotOutcome.NotCarried;
            }
        }
    }

    public sealed partial class GameSession
    {
        /// <summary>The first copy of an item in the equipment or an open bag, as the thing the use packets name (position, stack position, item); false when none is carried.</summary>
        public bool FindCarried(int clientId, out ItemRef found)
        {
            found = default(ItemRef);
            for (int slot = 1; slot < parser.Inventory.Length; slot++)
            {
                var it = parser.Inventory[slot];
                if (it != null && it.Id == clientId) { found = new ItemRef(InventoryPos(slot), 0, it); return true; }
            }
            foreach (var kv in parser.Containers)
            {
                var c = kv.Value;
                for (int i = 0; i < c.Items.Count; i++)
                {
                    if (c.Items[i] == null || c.Items[i].Id != clientId) continue;
                    int slot = c.FirstIndex + i;
                    found = new ItemRef(ContainerPos(c.Id, slot), (byte)slot, c.Items[i]);
                    return true;
                }
            }
            return false;
        }
    }

    /// <summary>IHotbarHost over a GameSession; the crosshair belongs to the window layer, which hands in how to start it.</summary>
    public sealed class SessionHotbarHost : IHotbarHost
    {
        readonly GameSession s;
        readonly Action<ItemRef> crosshair;

        public SessionHotbarHost(GameSession session, Action<ItemRef> startCrosshair) { s = session; crosshair = startCrosshair; }

        public int CountItem(int clientId) => s.CountItem(clientId);
        public bool UseItem(int clientId) => s.UseCarriedItem(clientId);
        public bool UseOnCreature(int clientId, uint creature) => s.UseItemOnCreature(clientId, creature);
        public uint AttackTarget => s.AttackTarget;
        public uint SelfId => s.Parser.W.PlayerId;
        public void Say(string text) { s.Spells.CastOrSay(text); }

        public bool StartCrosshair(int clientId)
        {
            if (crosshair == null || !s.FindCarried(clientId, out var r)) return false;
            crosshair(r);
            return true;
        }
    }
}
