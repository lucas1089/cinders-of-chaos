// Little endian readers and writers for the game protocol and the sprite files.
// Pure C#, no engine types: the console tests (unity/Core.Tests) compile this file too.
using System;
using System.Text;

namespace Chaos.Core
{
    public class ProtocolException : Exception
    {
        public ProtocolException(string message) : base(message) { }
    }

    /// <summary>Reads a byte buffer from a position; throws ProtocolException past the end.</summary>
    public sealed class ByteReader
    {
        static readonly Encoding Latin1 = Encoding.GetEncoding("ISO-8859-1");

        readonly byte[] buf;
        readonly int end;
        public int Pos;

        public ByteReader(byte[] buffer) : this(buffer, 0, buffer.Length) { }

        public ByteReader(byte[] buffer, int offset, int length)
        {
            buf = buffer;
            Pos = offset;
            end = offset + length;
        }

        public int Remaining => end - Pos;
        public bool AtEnd => Pos >= end;
        public byte[] Buffer => buf;

        void Need(int n)
        {
            if (Pos + n > end)
                throw new ProtocolException("read past the end at " + Pos + " (+" + n + ", end " + end + ")");
        }

        public byte U8() { Need(1); return buf[Pos++]; }
        public sbyte I8() { return unchecked((sbyte)U8()); }
        public byte PeekU8() { Need(1); return buf[Pos]; }

        public ushort PeekU16()
        {
            Need(2);
            return (ushort)(buf[Pos] | buf[Pos + 1] << 8);
        }

        public ushort U16()
        {
            ushort v = PeekU16();
            Pos += 2;
            return v;
        }

        public uint U32()
        {
            Need(4);
            uint v = (uint)(buf[Pos] | buf[Pos + 1] << 8 | buf[Pos + 2] << 16 | buf[Pos + 3] << 24);
            Pos += 4;
            return v;
        }

        public int I32() { return unchecked((int)U32()); }

        public ulong U64()
        {
            ulong lo = U32();
            ulong hi = U32();
            return lo | hi << 32;
        }

        public double Double()
        {
            // stock encoding of a "double": u8 precision, u32 value + int.MaxValue
            byte precision = U8();
            long v = (long)U32() - int.MaxValue;
            return v / Math.Pow(10, precision);
        }

        public string Str()
        {
            int n = U16();
            Need(n);
            string s = Latin1.GetString(buf, Pos, n);
            Pos += n;
            return s;
        }

        public void Skip(int n) { Need(n); Pos += n; }

        public byte[] Bytes(int n)
        {
            Need(n);
            var b = new byte[n];
            Array.Copy(buf, Pos, b, 0, n);
            Pos += n;
            return b;
        }
    }

    /// <summary>Grows as it is written.</summary>
    public sealed class ByteWriter
    {
        static readonly Encoding Latin1 = Encoding.GetEncoding("ISO-8859-1");

        byte[] buf = new byte[256];
        public int Length;

        void Room(int n)
        {
            if (Length + n <= buf.Length) return;
            int size = buf.Length;
            while (size < Length + n) size *= 2;
            Array.Resize(ref buf, size);
        }

        public ByteWriter U8(byte v) { Room(1); buf[Length++] = v; return this; }

        public ByteWriter U16(ushort v)
        {
            Room(2);
            buf[Length++] = (byte)v;
            buf[Length++] = (byte)(v >> 8);
            return this;
        }

        public ByteWriter U32(uint v)
        {
            Room(4);
            for (int i = 0; i < 4; i++) buf[Length++] = (byte)(v >> (8 * i));
            return this;
        }

        public ByteWriter Str(string s)
        {
            byte[] b = Latin1.GetBytes(s ?? "");
            U16((ushort)b.Length);
            return Raw(b);
        }

        public ByteWriter Raw(byte[] b) { return Raw(b, 0, b.Length); }

        public ByteWriter Raw(byte[] b, int off, int n)
        {
            Room(n);
            Array.Copy(b, off, buf, Length, n);
            Length += n;
            return this;
        }

        public ByteWriter Zeros(int n)
        {
            Room(n);
            Array.Clear(buf, Length, n);
            Length += n;
            return this;
        }

        public byte[] ToArray()
        {
            var b = new byte[Length];
            Array.Copy(buf, b, Length);
            return b;
        }
    }
}
