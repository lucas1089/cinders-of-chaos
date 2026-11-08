// Base gameplay actions of the Unity client (O433 phase 5, track P): look (0x8C, 0x8D), use with (0x83), use on a creature (0x84), rotate (0x85),
// the item menu on slots and map things, and the rules that pick a thing on a map tile. Layouts are TFS 1.4.2 protocolgame.cpp (10.98):
//   0x8C look      pos, u16 item id, u8 stack position            0x8D look at a creature of the battle list: u32 creature id
//   0x83 use with  from pos, u16 id, u8 stack, to pos, u16 id, u8 stack
//   0x84 use on a creature  from pos, u16 id, u8 stack, u32 creature id
//   0x85 rotate    pos, u16 id, u8 stack
//   0x7D request a trade: item pos, u16 id, u8 stack, u32 player id
// The answer to a look is a text message (0xB4 kind 22), which the chat already shows. The main client's rules come from the base module
// game_interface (createThingMenu, getTopLookThing, getTopUseThing); the Chaos entries from the hooks of the modules named at each entry.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class PlayPackets
    {
        static ByteWriter PutPos(ByteWriter w, Pos p) => w.U16((ushort)p.X).U16((ushort)p.Y).U8((byte)p.Z);

        public static byte[] Look(Pos p, ushort id, byte stack) => PutPos(new ByteWriter().U8(0x8C), p).U16(id).U8(stack).ToArray();
        public static byte[] LookCreature(uint id) => new ByteWriter().U8(0x8D).U32(id).ToArray();
        public static byte[] UseWith(Pos from, ushort id, byte stack, Pos to, ushort toId, byte toStack) =>
            PutPos(PutPos(new ByteWriter().U8(0x83), from).U16(id).U8(stack), to).U16(toId).U8(toStack).ToArray();
        public static byte[] UseOnCreature(Pos from, ushort id, byte stack, uint creature) =>
            PutPos(new ByteWriter().U8(0x84), from).U16(id).U8(stack).U32(creature).ToArray();
        public static byte[] Rotate(Pos p, ushort id, byte stack) => PutPos(new ByteWriter().U8(0x85), p).U16(id).U8(stack).ToArray();
        public static byte[] TradeRequest(Pos p, ushort id, byte stack, uint player) => PutPos(new ByteWriter().U8(0x7D), p).U16(id).U8(stack).U32(player).ToArray();
        public static byte[] TradeLookIn(bool counter, byte index) => new ByteWriter().U8(0x7E).U8((byte)(counter ? 1 : 0)).U8(index).ToArray();
        public static byte[] TradeAccept() => new byte[] { 0x7F };
        public static byte[] TradeClose() => new byte[] { 0x80 };
        public static byte[] VipAdd(string name) => new ByteWriter().U8(0xDC).Str(name).ToArray();
        public static byte[] VipRemove(uint guid) => new ByteWriter().U8(0xDD).U32(guid).ToArray();
        public static byte[] VipEdit(uint guid, string description, uint icon, bool notify) => new ByteWriter().U8(0xDE).U32(guid).Str(description).U32(icon).U8((byte)(notify ? 1 : 0)).ToArray();
        public static byte[] QuestLog() => new byte[] { 0xF0 };
        public static byte[] QuestLine(ushort quest) => new ByteWriter().U8(0xF1).U16(quest).ToArray();
    }

    /// <summary>One item the player points at: where it lies (the map tile, an equipment slot 0xFFFF / slot / 0, or a bag slot 0xFFFF / 0x40 + id / slot),
    /// the stack position the server expects with it, and the item itself.</summary>
    public struct ItemRef
    {
        public Pos Pos;
        public byte Stack;
        public Item Item;
        public ItemRef(Pos pos, byte stack, Item item) { Pos = pos; Stack = stack; Item = item; }
        public ushort Id => Item == null ? (ushort)0 : (ushort)Item.Id;
        /// <summary>In the equipment or a bag (x 0xFFFF).</summary>
        public bool Own => Pos.X == 0xFFFF;
        public bool InBag => Pos.X == 0xFFFF && Pos.Y >= 0x40;
        public bool Worn => Pos.X == 0xFFFF && Pos.Y >= 1 && Pos.Y < 0x40;
    }

    /// <summary>Which thing of a map tile a click means (base game_interface: getTopLookThing, getTopUseThing).</summary>
    public static class TilePick
    {
        static bool Plain(Thing t)
        {
            if (t.IsCreature || t.Item.Type == null) return false;
            var ty = t.Item.Type;
            return !ty.Ground && !ty.GroundBorder && !ty.OnBottom && !ty.OnTop;
        }

        /// <summary>The stack position of the thing a look means: the first plain thing (a creature counts), else the first thing; -1 for an empty tile.</summary>
        public static int LookIndex(Tile tile)
        {
            if (tile == null || tile.Things.Count == 0) return -1;
            for (int i = 0; i < tile.Things.Count; i++)
            {
                var t = tile.Things[i];
                if (t.IsCreature) return i;
                if (t.Item.Type != null && t.Item.Type.IgnoreLook) continue;
                if (Plain(t)) return i;
            }
            return 0;
        }

        /// <summary>The stack position of the thing a use means: a force-use item, else the first plain item that is not a splash, else the last item; -1 when there is none.</summary>
        public static int UseIndex(Tile tile)
        {
            if (tile == null || tile.Things.Count == 0) return -1;
            for (int i = 0; i < tile.Things.Count; i++)
            {
                var t = tile.Things[i];
                if (t.IsCreature) continue;
                var ty = t.Item.Type;
                if (ty != null && (ty.ForceUse || (Plain(t) && !ty.Splash))) return i;
            }
            for (int i = tile.Things.Count - 1; i >= 0; i--) if (!tile.Things[i].IsCreature) return i;
            return -1;
        }

        /// <summary>The creature standing last on the tile (the one drawn on top), or null.</summary>
        public static Creature TopCreature(Tile tile)
        {
            if (tile == null) return null;
            for (int i = tile.Things.Count - 1; i >= 0; i--) if (tile.Things[i].IsCreature) return tile.Things[i].Creature;
            return null;
        }

        public static ItemRef? ItemAt(Tile tile, int index)
        {
            if (tile == null || index < 0 || index >= tile.Things.Count || tile.Things[index].IsCreature) return null;
            return new ItemRef(tile.Pos, (byte)index, tile.Things[index].Item);
        }
    }

    /// <summary>What an item menu entry does. The menu is built by ItemMenu.Build, the window runs the action.</summary>
    public enum ItemAction { Look, Use, Open, UseWith, Rotate, Trade, WhereToFind, LootAdd, LootRemove, PouchSettings, Transmog, Lock, Unlock }

    public sealed class ItemMenuEntry
    {
        public ItemAction Action;
        public string Label = "";
        public bool Separator;
    }

    /// <summary>What the Chaos systems say about an item for its menu: the loot list, the Loot Bag, the lock rules.</summary>
    public sealed class ItemMenuContext
    {
        public bool OnLootList;
        public bool IsLootPouch;
        public bool AnotherPlayerInView;
        public bool CanUseWith = true;
        public int RarityOf;
    }

    public static class ItemMenu
    {
        /// <summary>The equipment slots whose item the Transmog window can change (game_transmog): head, armor, hands, legs and feet.</summary>
        public static bool TransmogSlot(Pos p) => p.X == 0xFFFF && p.Y >= 1 && p.Y <= 10 && p.Y != 2 && p.Y != 3 && p.Y != 9 && p.Y != 10;

        /// <summary>A real item for the finder, the loot list and the Pouch menu: no ground, border or fixed map piece.</summary>
        public static bool RealItem(Item it)
        {
            if (it == null || it.Id < 100) return false;
            var t = it.Type;
            if (t == null) return true;
            return !t.Ground && !t.GroundBorder && (t.Pickupable || !t.NotMoveable);
        }

        /// <summary>The entries of the right-click menu of an item: the base ones (Look, Use or Open, Use with, Rotate, Trade with) and the hooks of the Chaos
        /// modules (Where to find, Add to / Remove from Loot List, Pouch settings, Transmog, Lock item / Unlock item). The hooks are one group after a separator.</summary>
        public static List<ItemMenuEntry> Build(ItemRef r, ItemMenuContext ctx)
        {
            var o = new List<ItemMenuEntry>();
            var it = r.Item;
            if (it == null) return o;
            var t = it.Type;
            ItemMenuEntry E(ItemAction a, string label) => new ItemMenuEntry { Action = a, Label = label };
            if (t != null && t.Container) o.Add(E(ItemAction.Open, Loc.T("Open")));
            else o.Add(E(ItemAction.Use, Loc.T("Use")));
            if (t != null && t.MultiUse && ctx.CanUseWith) o.Add(E(ItemAction.UseWith, Loc.T("Use with ...")));
            if (t != null && t.Rotateable) o.Add(E(ItemAction.Rotate, Loc.T("Rotate")));
            o.Add(E(ItemAction.Look, Loc.T("Look")));
            if (r.Own && t != null && t.Pickupable && ctx.AnotherPlayerInView) o.Add(E(ItemAction.Trade, Loc.T("Trade with ...")));
            var hooks = new List<ItemMenuEntry>();
            if (RealItem(it)) hooks.Add(E(ItemAction.WhereToFind, Loc.T("Where to find")));
            if (RealItem(it) && t != null && t.Pickupable && !t.Container)
                hooks.Add(E(ctx.OnLootList ? ItemAction.LootRemove : ItemAction.LootAdd, ctx.OnLootList ? Loc.T("Remove from Loot List") : Loc.T("Add to Loot List")));
            if (r.Own && ctx.IsLootPouch) hooks.Add(E(ItemAction.PouchSettings, Loc.T("Pouch settings")));
            if (TransmogSlot(r.Pos)) hooks.Add(E(ItemAction.Transmog, Loc.T("Transmog")));
            bool locked = ItemRarity.IsLocked(it);
            const string name = "";   // the client has no item names: a Rift Key is locked by its rarity or unique mark
            if (CraftingLockMenu.Show(r.Pos, t != null && t.Stackable, t != null && t.Container, locked, ctx.RarityOf, it.Attr(ItemAttr.Unique) > 0, name, false)) hooks.Add(E(ItemAction.Lock, Loc.T("Lock item")));
            if (CraftingLockMenu.Show(r.Pos, t != null && t.Stackable, t != null && t.Container, locked, ctx.RarityOf, it.Attr(ItemAttr.Unique) > 0, name, true)) hooks.Add(E(ItemAction.Unlock, Loc.T("Unlock item")));
            if (hooks.Count > 0)
            {
                o.Add(new ItemMenuEntry { Separator = true });
                o.AddRange(hooks);
            }
            return o;
        }

        /// <summary>The plain right-click on an item of the equipment or a bag (Classic Controls): a multi-use item starts a use with, unless the server listed it as
        /// equipment and the option "Right-click equips items" is on (game_rightclickequip: then a plain use equips it).</summary>
        public static bool RightClickIsUseWith(Item it, ISet<int> multiUseEquipment, bool rightClickEquips)
        {
            if (it == null || it.Type == null || !it.Type.MultiUse) return false;
            if (rightClickEquips && multiUseEquipment != null && multiUseEquipment.Contains(it.Id)) return false;
            return true;
        }
    }

    /// <summary>The crosshair after "Use with ..." or "Trade with ...": the next click on the map or in a slot is the target.</summary>
    public sealed class CrosshairState
    {
        public enum Kind { None, UseWith, Trade }
        public Kind Mode;
        public ItemRef Source;
        public bool Active => Mode != Kind.None;

        public void Start(Kind k, ItemRef source) { Mode = k; Source = source; }
        public void Cancel() { Mode = Kind.None; Source = default(ItemRef); }

        /// <summary>The packet for a click on a map thing (target is an item: its position, id and stack) or a creature (id). Returns null when the click is not a valid target
        /// (a trade needs a player other than yourself); the crosshair then stays. A valid click ends the crosshair.</summary>
        public byte[] Click(ItemRef? targetItem, Creature creature, uint selfId)
        {
            if (!Active) return null;
            byte[] pkt = null;
            var s = Source;
            if (Mode == Kind.UseWith)
            {
                if (creature != null) pkt = PlayPackets.UseOnCreature(s.Pos, s.Id, s.Stack, creature.Id);
                else if (targetItem.HasValue) pkt = PlayPackets.UseWith(s.Pos, s.Id, s.Stack, targetItem.Value.Pos, targetItem.Value.Id, targetItem.Value.Stack);
            }
            else if (Mode == Kind.Trade)
            {
                if (creature != null && creature.Type == 0 && creature.Id != selfId) pkt = PlayPackets.TradeRequest(s.Pos, s.Id, s.Stack, creature.Id);
            }
            if (pkt != null) Cancel();
            return pkt;
        }
    }
}
