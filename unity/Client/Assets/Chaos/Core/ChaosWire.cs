// Small pieces of the Chaos wire that have no window of their own (unity/README.md "Wire audit").
using System;

namespace Chaos.Core
{
    /// <summary>The class byte of the basic data packet 0x9F (feature GameChaosVocationIds 154, client base patch 0016): the base slot (1 warrior,
    /// 2 ranger, 3 mystic, 6 thief, 7 necromancer, 8 monk, 9 templar), plus 10 for the first ascended class and plus 20 for the second. The main
    /// client turns it into the server's vocation id (docs/CLASSES.md) with the table below, copied from that patch.</summary>
    public static class ChaosVocation
    {
        static readonly int[][] ToServerId =
        {
            new[] { 0, 4, 3, 1, 1, 1, 11, 20, 17, 23 },
            new[] { 0, 8, 7, 5, 10, 10, 12, 21, 18, 24 },
            new[] { 0, 14, 15, 10, 10, 10, 13, 22, 19, 25 },
        };

        /// <summary>The vocation id of a class byte; a byte past the table (30 and up) is returned as it is, as the main client leaves it.</summary>
        public static int FromWire(int classByte)
        {
            int tier = classByte / 10, slot = classByte % 10;
            if (classByte < 0 || tier > 2) return classByte;
            return ToServerId[tier][slot];
        }
    }

    /// <summary>The client to server messages of the wire audit (docs: unity/README.md "Wire audit").</summary>
    public static class WirePackets
    {
        /// <summary>0x33: the aware range we want (u8 width, u8 height; the engine's ClientChangeMapAwareRange). The server answers with 0x42 and the map.</summary>
        public static byte[] ChangeAwareRange(int width, int height) => new byte[] { 0x33, (byte)width, (byte)height };
    }
}
