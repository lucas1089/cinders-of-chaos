// The split stack dialog (phase 6, track V): moving a stackable item with more than one in the stack asks how many to move, as the main
// client's move window does. A drop with Ctrl held moves the whole stack at once. The count goes out as the last byte of the 0x78 move
// packet (Protocol.MoveItemPacket). Pure model: the number in the box, the slider steps and the rules of when the dialog opens.
using System;
using System.Globalization;

namespace Chaos.Core
{
    public sealed class SplitStackModel
    {
        /// <summary>A stack holds at most 100 (the server's limit, and the count byte the move packet carries).</summary>
        public const int StackMax = 100;

        public readonly int Max;
        public int Count;
        public string Text;

        public SplitStackModel(int stackCount, int initial = -1)
        {
            Max = Math.Max(1, Math.Min(StackMax, stackCount));
            Set(initial < 0 ? Max : initial);
        }

        public void Set(int n)
        {
            Count = Clamp(n, Max);
            Text = Count.ToString(CultureInfo.InvariantCulture);
        }

        public static int Clamp(int n, int max) => Math.Max(1, Math.Min(Math.Max(1, max), n));

        public void Step(int delta) => Set(Count + delta);
        public void One() => Set(1);
        public void Half() => Set((Max + 1) / 2);
        public void All() => Set(Max);

        /// <summary>The slider's value 0..1 and back.</summary>
        public float Fraction => Max <= 1 ? 1f : (Count - 1) / (float)(Max - 1);
        public void SetFraction(float f) => Set(1 + (int)Math.Round(Math.Max(0f, Math.Min(1f, f)) * (Max - 1)));

        /// <summary>The text of the number box: digits only; an empty or bad text leaves the count where it was, a number out of range is pulled in.</summary>
        public void SetText(string text)
        {
            text = text ?? "";
            var digits = new System.Text.StringBuilder();
            foreach (char c in text) if (c >= '0' && c <= '9' && digits.Length < 4) digits.Append(c);
            Text = digits.ToString();
            if (Text.Length == 0) return;
            int n;
            if (int.TryParse(Text, NumberStyles.None, CultureInfo.InvariantCulture, out n)) Count = Clamp(n, Max);
        }

        /// <summary>The count that goes in the packet.</summary>
        public byte PacketCount => (byte)Count;

        /// <summary>Does a move of this item ask for a count? A stackable with more than one, not when Ctrl is held (the whole stack moves) and not for a move that cannot split
        /// (a trade or market slot has its own count).</summary>
        public static bool Asks(bool stackable, int count, bool ctrl) => stackable && count > 1 && !ctrl;

        /// <summary>The count of a move that does not ask: the whole stack, at most StackMax, at least 1.</summary>
        public static byte Whole(int count) => (byte)Clamp(count, StackMax);
    }
}
