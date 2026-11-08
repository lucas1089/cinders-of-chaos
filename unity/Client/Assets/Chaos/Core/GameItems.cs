// Items and economy parts of GameParser and GameSession: the outfit window (0xC8), modal windows (0xFA), text windows (0x96, 0x97), and the
// Chaos item modules on extended opcodes: rich tooltips (242), bank (60), stash (110), store (218). Layouts: Dialogs.cs, ItemInfo.cs, Bank.cs,
// Stash.cs, Store.cs.
using System;

namespace Chaos.Core
{
    public sealed partial class GameParser
    {
        public readonly OutfitWindowState Outfits = new OutfitWindowState();
        public readonly ModalWindows Modals = new ModalWindows();
        public readonly TextWindows Texts = new TextWindows();
        /// <summary>An equipment slot got or lost an item (0x78, 0x79).</summary>
        public Action InventoryChanged = delegate { };

        void ItemsMessage(byte op, ByteReader r)
        {
            switch (op)
            {
                case 0xC8: Outfits.Read(r, ReadOutfit, Identity.Markers); break;
                case 0xFA: Modals.Read(r); break;
                case 0x96: Texts.ReadText(r, rd => ReadItem(rd, rd.U16())); break;
                case 0x97: Texts.ReadHouse(r); break;
            }
        }
    }

    public sealed partial class GameSession
    {
        /// <summary>Rich item tooltips (opcode 242).</summary>
        public ItemTips Tips { get; private set; }
        /// <summary>The bank (60), the stash (110) and the Chaos store (218).</summary>
        public BankState Bank { get; private set; }
        public StashState Stash { get; private set; }
        public StoreState Store { get; private set; }
        public OutfitWindowState Outfits => parser.Outfits;
        public ModalWindows Modals => parser.Modals;
        public TextWindows Texts => parser.Texts;
        bool stashAsked;

        /// <summary>Called by the constructor, after Ext and the parser exist.</summary>
        void InitItems()
        {
            Tips = new ItemTips(Ext) { Clock = () => Now };
            Bank = new BankState(Ext);
            Stash = new StashState(Ext);
            Store = new StoreState(Ext) { Clock = () => Now / 1000.0 };
            Action<byte[]> send = p => conn?.Send(p);
            parser.Outfits.Send = send;
            parser.Modals.Send = send;
            parser.Texts.Send = send;
            parser.InventoryChanged = () => Tips.DropSetTips();
        }

        /// <summary>Called by Poll: the stash's categories a moment after the login (the main client waits 100 ms).</summary>
        void ItemsPoll()
        {
            if (!stashAsked && enteredAt >= 0 && Now - enteredAt > 1200) { stashAsked = true; Stash.Prefetch(); }
        }

        /// <summary>The outfit window: 0xD2, the window comes back as 0xC8.</summary>
        public void RequestOutfits() { Outfits.Request(); }
        /// <summary>Wears a look (0xD3). The wings, aura and shader are sent only on an Identity.Chaos connection.</summary>
        public void SetOutfit(Outfit o) { Outfits.Apply(o, opt.Identity != null && opt.Identity.Markers); }
    }
}
