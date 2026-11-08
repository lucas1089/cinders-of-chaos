// The base server's market packets (O433 phase 22). Server: ProtocolGame::sendMarketEnter 0xF6, sendMarketLeave 0xF7, sendMarketDetail 0xF8 and the browse family
// 0xF9 (sendMarketBrowseItem, sendMarketAcceptOffer, sendMarketBrowseOwnOffers, sendMarketCancelOffer, sendMarketBrowseOwnHistory). Client: 0xF4 leave, 0xF5 browse,
// 0xF6 create offer, 0xF7 cancel offer, 0xF8 accept offer.
// A Chaos server never sends them: patch_market.py comments out the depot locker's market action (item 14405, actions.xml), nothing else calls
// sendMarketEnter, and the engine refuses the client packets outside the market (Player::isInMarket). The Chaos market is extended opcode 221 (market.lua).
// The cases are read anyway, so the parser does not stop at one (an unknown opcode costs the rest of the packet).
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class MarketOffer
    {
        public uint Timestamp;
        public ushort Counter, ItemId, Amount;
        public uint Price;
        /// <summary>The seller or buyer (browse and accept packets only).</summary>
        public string Player = "";
        /// <summary>History packets only: the offer's end state (expired, cancelled, accepted).</summary>
        public byte State;
    }

    public sealed class MarketDetail
    {
        public ushort ItemId;
        /// <summary>The 15 text lines in the server's order: armor, attack, container size, defense, description, decay, resistances, minimum level, minimum magic level,
        /// vocations, rune spell, skills, charges, weapon type, weight. An empty line is a value the item does not have.</summary>
        public readonly string[] Lines = new string[BaseMarket.DetailLines];
        /// <summary>Purchase and sale statistics: transactions, total price, highest, lowest (null when the server has none).</summary>
        public uint[] Purchases, Sales;
    }

    public sealed class BaseMarketState
    {
        public bool Open;
        public ulong Balance;
        public int OwnOfferCount;
        /// <summary>The depot's market goods: ware id to count.</summary>
        public readonly Dictionary<ushort, int> Depot = new Dictionary<ushort, int>();
        public ushort BrowseItem;
        public readonly List<MarketOffer> Buy = new List<MarketOffer>(), Sell = new List<MarketOffer>();
        /// <summary>The last own offers or history packet: kind (BaseMarket.OwnOffers or OwnHistory) and the lists.</summary>
        public ushort OwnKind;
        public readonly List<MarketOffer> OwnBuy = new List<MarketOffer>(), OwnSell = new List<MarketOffer>();
        public MarketDetail Detail;
        /// <summary>Packets read by opcode (0xF6 to 0xF9).</summary>
        public int Entered, Left, Details, Browses;
    }

    public static class BaseMarket
    {
        public const byte Enter = 0xF6, Leave = 0xF7, DetailOp = 0xF8, Browse = 0xF9;
        public const byte ClientLeave = 0xF4, ClientBrowse = 0xF5, ClientCreate = 0xF6, ClientCancel = 0xF7, ClientAccept = 0xF8;
        public const ushort OwnOffers = 0xFFFE, OwnHistory = 0xFFFF;
        public const int DetailLines = 15;

        /// <summary>Reads one packet of 0xF6 to 0xF9 (the opcode byte is read).</summary>
        public static void Read(byte op, ByteReader r, BaseMarketState m)
        {
            switch (op)
            {
                case Enter:
                    m.Balance = r.U64();
                    m.OwnOfferCount = r.U8();
                    m.Depot.Clear();
                    for (int n = r.U16(), i = 0; i < n; i++) { ushort ware = r.U16(); m.Depot[ware] = r.U16(); }
                    m.Open = true;
                    m.Entered++;
                    break;
                case Leave:
                    m.Open = false;
                    m.Left++;
                    break;
                case DetailOp:
                    m.Detail = ReadDetail(r);
                    m.Details++;
                    break;
                case Browse:
                {
                    ushort first = r.U16();
                    m.Browses++;
                    if (first == OwnOffers || first == OwnHistory)
                    {
                        m.OwnKind = first;
                        ReadOwn(r, first == OwnHistory, m.OwnBuy);
                        ReadOwn(r, first == OwnHistory, m.OwnSell);
                    }
                    else
                    {
                        m.BrowseItem = first;
                        ReadBrowse(r, first, m.Buy);
                        ReadBrowse(r, first, m.Sell);
                    }
                    break;
                }
                default: throw new ProtocolException("not a market opcode 0x" + op.ToString("X2"));
            }
        }

        static void ReadBrowse(ByteReader r, ushort item, List<MarketOffer> into)
        {
            into.Clear();
            uint n = r.U32();
            for (uint i = 0; i < n; i++)
                into.Add(new MarketOffer { ItemId = item, Timestamp = r.U32(), Counter = r.U16(), Amount = r.U16(), Price = r.U32(), Player = r.Str() });
        }

        static void ReadOwn(ByteReader r, bool history, List<MarketOffer> into)
        {
            into.Clear();
            uint n = r.U32();
            for (uint i = 0; i < n; i++)
            {
                var o = new MarketOffer { Timestamp = r.U32(), Counter = r.U16(), ItemId = r.U16(), Amount = r.U16(), Price = r.U32() };
                if (history) o.State = r.U8();
                into.Add(o);
            }
        }

        static MarketDetail ReadDetail(ByteReader r)
        {
            var d = new MarketDetail { ItemId = r.U16() };
            for (int i = 0; i < DetailLines; i++) d.Lines[i] = r.Str();
            d.Purchases = ReadStats(r);
            d.Sales = ReadStats(r);
            return d;
        }

        static uint[] ReadStats(ByteReader r)
        {
            if (r.U8() == 0) return null;
            return new[] { r.U32(), r.U32(), r.U32(), r.U32() };
        }

        // ---- the client packets (server parseMarketLeave, parseMarketBrowse, parseMarketCreateOffer, parseMarketCancelOffer, parseMarketAcceptOffer)
        public static byte[] LeaveRequest() => new byte[] { ClientLeave };
        /// <summary>0xF5: a ware id, or OwnOffers / OwnHistory.</summary>
        public static byte[] BrowseRequest(ushort what) => new ByteWriter().U8(ClientBrowse).U16(what).ToArray();
        /// <summary>0xF6: type (0 buy, 1 sell), the ware id, amount, price, anonymous.</summary>
        public static byte[] CreateRequest(bool sell, ushort ware, ushort amount, uint price, bool anonymous) =>
            new ByteWriter().U8(ClientCreate).U8((byte)(sell ? 1 : 0)).U16(ware).U16(amount).U32(price).U8((byte)(anonymous ? 1 : 0)).ToArray();
        public static byte[] CancelRequest(uint timestamp, ushort counter) => new ByteWriter().U8(ClientCancel).U32(timestamp).U16(counter).ToArray();
        public static byte[] AcceptRequest(uint timestamp, ushort counter, ushort amount) => new ByteWriter().U8(ClientAccept).U32(timestamp).U16(counter).U16(amount).ToArray();
    }
}
