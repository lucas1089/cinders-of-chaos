// The base server's item tooltip data: server packet 0x9E (ProtocolGame::sendTooltipData), the answer to the client packet 0x9F (parseTooltip).
// Request (client): 0x9F, u8 kind. Kind 0 = a virtual item: u16 sprite (client) id, u16 count. Kind 1 = an item we can see: position (u16 x, u16 y, u8 z),
// u16 sprite id, u8 stack position. The server checks the item is there and its client id matches.
// Answer (server): 0x9E, u8 entry count, then per entry u8 attribute id (ItemTooltipAttributes_t of enums.h) and u8 kind:
//   1 = a number: u8 negative flag, u32 absolute value, u32 attribute type (skill or combat type, 0xFFFFFFFF = none);
//   0 = a text: string.
// The first entries of an item are always its name (id 3) and its count (id 18). Chaos shows its own tooltip on extended opcode 242 (ItemTips); this
// packet is the stock one, the live check asks for it and checks it parses (O433 phase 21).
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class TooltipEntry
    {
        public byte Id;
        /// <summary>True for a number (Value, Type), false for a text (Text).</summary>
        public bool IsNumber;
        public long Value;
        /// <summary>The skill or combat type the number belongs to, -1 for none.</summary>
        public int Type = -1;
        public string Text = "";
    }

    public static class BaseTooltip
    {
        public const byte ServerOpcode = 0x9E;
        public const byte ClientOpcode = 0x9F;
        public const byte AttrName = 3, AttrWeight = 4, AttrCount = 18;

        /// <summary>Reads the body of 0x9E (the opcode byte is read).</summary>
        public static List<TooltipEntry> Read(ByteReader r)
        {
            int n = r.U8();
            var list = new List<TooltipEntry>(n);
            for (int i = 0; i < n; i++)
            {
                var e = new TooltipEntry { Id = r.U8() };
                byte kind = r.U8();
                if (kind == 1)
                {
                    bool neg = r.U8() != 0;
                    uint abs = r.U32();
                    uint type = r.U32();
                    e.IsNumber = true;
                    e.Value = neg ? -(long)abs : abs;
                    e.Type = unchecked((int)type);
                }
                else if (kind == 0) e.Text = r.Str();
                else throw new ProtocolException("tooltip entry kind " + kind);
                list.Add(e);
            }
            return list;
        }

        public static string Name(IList<TooltipEntry> list)
        {
            foreach (var e in list) if (e.Id == AttrName && !e.IsNumber) return e.Text;
            return "";
        }

        /// <summary>The request for an item we know only by its sprite id and count (0x9F kind 0).</summary>
        public static byte[] RequestVirtual(ushort spriteId, ushort count) =>
            new ByteWriter().U8(ClientOpcode).U8(0).U16(spriteId).U16(count).ToArray();

        /// <summary>The request for an item at a position (0x9F kind 1): a slot of the inventory, a container or a map tile.</summary>
        public static byte[] RequestItem(Pos p, ushort spriteId, byte stackPos) =>
            new ByteWriter().U8(ClientOpcode).U8(1).U16((ushort)p.X).U16((ushort)p.Y).U8((byte)p.Z).U16(spriteId).U8(stackPos).ToArray();
    }
}
