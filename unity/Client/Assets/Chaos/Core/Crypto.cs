// XTEA, RSA (public key encrypt, no padding) and Adler-32 as the 10.98 protocol uses them.
using System;
using System.Numerics;

namespace Chaos.Core
{
    public static class Xtea
    {
        const uint Delta = 0x9E3779B9;
        const int Rounds = 32;

        static uint Get(byte[] b, int i) { return (uint)(b[i] | b[i + 1] << 8 | b[i + 2] << 16 | b[i + 3] << 24); }

        static void Put(byte[] b, int i, uint v)
        {
            b[i] = (byte)v; b[i + 1] = (byte)(v >> 8); b[i + 2] = (byte)(v >> 16); b[i + 3] = (byte)(v >> 24);
        }

        /// <summary>Encrypts in place, 8 bytes at a time; length must be a multiple of 8.</summary>
        public static void Encrypt(byte[] data, int offset, int length, uint[] key)
        {
            if (length % 8 != 0) throw new ArgumentException("xtea: length not a multiple of 8");
            for (int i = offset; i < offset + length; i += 8)
            {
                uint v0 = Get(data, i), v1 = Get(data, i + 4), sum = 0;
                for (int r = 0; r < Rounds; r++)
                {
                    v0 += ((v1 << 4 ^ v1 >> 5) + v1) ^ (sum + key[sum & 3]);
                    sum += Delta;
                    v1 += ((v0 << 4 ^ v0 >> 5) + v0) ^ (sum + key[sum >> 11 & 3]);
                }
                Put(data, i, v0);
                Put(data, i + 4, v1);
            }
        }

        public static void Decrypt(byte[] data, int offset, int length, uint[] key)
        {
            if (length % 8 != 0) throw new ProtocolException("xtea: length not a multiple of 8");
            for (int i = offset; i < offset + length; i += 8)
            {
                uint v0 = Get(data, i), v1 = Get(data, i + 4), sum = unchecked(Delta * Rounds);
                for (int r = 0; r < Rounds; r++)
                {
                    v1 -= ((v0 << 4 ^ v0 >> 5) + v0) ^ (sum + key[sum >> 11 & 3]);
                    sum -= Delta;
                    v0 -= ((v1 << 4 ^ v1 >> 5) + v1) ^ (sum + key[sum & 3]);
                }
                Put(data, i, v0);
                Put(data, i + 4, v1);
            }
        }
    }

    public sealed class Rsa
    {
        readonly BigInteger n;
        readonly BigInteger e;
        public readonly int Size;

        public Rsa(string modulusDecimal, int exponent = 65537)
        {
            n = BigInteger.Parse(modulusDecimal);
            e = exponent;
            Size = (int)((Bits(n) + 7) / 8);
        }

        static long Bits(BigInteger v)
        {
            long bits = 0;
            while (v > 0) { v >>= 1; bits++; }
            return bits;
        }

        /// <summary>Raw RSA of one block of Size bytes (big endian in and out), as the protocol does it.</summary>
        public byte[] Encrypt(byte[] block)
        {
            if (block.Length != Size) throw new ArgumentException("rsa: block must be " + Size + " bytes");
            BigInteger m = FromBigEndian(block);
            if (m >= n) throw new ArgumentException("rsa: block not below the modulus (first byte must be 0)");
            return ToBigEndian(BigInteger.ModPow(m, e, n), Size);
        }

        /// <summary>Tests only: raw decrypt with a private exponent.</summary>
        public byte[] DecryptWith(BigInteger d, byte[] block)
        {
            return ToBigEndian(BigInteger.ModPow(FromBigEndian(block), d, n), Size);
        }

        public static BigInteger FromBigEndian(byte[] b)
        {
            var le = new byte[b.Length + 1];
            for (int i = 0; i < b.Length; i++) le[i] = b[b.Length - 1 - i];
            return new BigInteger(le);
        }

        public static byte[] ToBigEndian(BigInteger v, int size)
        {
            byte[] le = v.ToByteArray();
            var outb = new byte[size];
            for (int i = 0; i < size && i < le.Length; i++) outb[size - 1 - i] = le[i];
            return outb;
        }
    }

    public static class Adler32
    {
        public static uint Of(byte[] data, int offset, int length)
        {
            uint a = 1, b = 0;
            int i = offset, end = offset + length;
            while (i < end)
            {
                int chunk = Math.Min(5552, end - i);
                for (int k = 0; k < chunk; k++)
                {
                    a += data[i++];
                    b += a;
                }
                a %= 65521;
                b %= 65521;
            }
            return b << 16 | a;
        }
    }
}
