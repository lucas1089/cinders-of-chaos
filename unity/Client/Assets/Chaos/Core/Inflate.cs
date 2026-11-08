// Packet compression, server to client (server src-patch 0069 and 0073, client base patches 0131 and 0135; docs: unity/README.md "Wire audit").
//
// What the server sends when config.lua packetCompression is true and the login carried the markers of the main client ("OTCv8TierByte" + "A"):
//   body -> raw deflate (one z_stream per connection, level 3, window 2^14, Z_SYNC_FLUSH after every packet, the 4 bytes 00 00 FF FF cut off)
//        -> u16 length of the deflated bytes -> XTEA (padded to 8) -> u32 0 where the adler32 goes -> u16 length of the packet.
// Only bodies of 128 bytes (packetCompressionMin) up to 60000 are deflated. Smaller and larger ones stay plain with a real adler32. Once a body
// is deflated it is sent deflated even when it did not shrink, so the stream sees every block.
//
// The client side (base patch 0131): add 00 00 FF FF back, inflate with the connection's stream, at most 65536 bytes per packet, input left over
// or a result over the cap closes the connection.
//
// RawInflater is that stream. A sync flush ends on an empty stored block, so every packet ends on a byte boundary at a block boundary: the only
// state kept between packets is the 32 KB history that back references reach into. No System.IO.Compression: a DeflateStream cannot be fed one
// packet at a time (it reads to the end of its source and then reports a truncated stream), and Unity's Mono has its own quirks there. The tests
// compare this decoder with DeflateStream and with vectors made by zlib.
using System;

namespace Chaos.Core
{
    /// <summary>A packet whose deflate stream cannot be read. The stream is out of step after it: the connection must close (the main client does).</summary>
    public sealed class CompressionException : ProtocolException
    {
        public CompressionException(string message) : base("compressed packet: " + message) { }
    }

    /// <summary>The inflate side of one connection's deflate stream (see the file comment).</summary>
    public sealed class RawInflater
    {
        public const int WindowSize = 32768, MaxOutput = 65536;
        static readonly byte[] Footer = { 0x00, 0x00, 0xFF, 0xFF };

        byte[] history = new byte[0];
        public long PacketsIn, BytesIn, BytesOut;

        // the input of one call (data plus the footer), the bit reader, the output
        byte[] inp;
        int pos, end, bitBuf, bitCnt;
        byte[] outp;
        int histLen, outLen;

        /// <summary>Inflates one packet body (the deflated bytes inside the XTEA layer, without the footer). Throws CompressionException.</summary>
        public byte[] Inflate(byte[] data, int offset, int count)
        {
            if (data == null || offset < 0 || count < 0 || offset + count > data.Length) throw new CompressionException("bad input range");
            inp = new byte[count + Footer.Length];
            Array.Copy(data, offset, inp, 0, count);
            Array.Copy(Footer, 0, inp, count, Footer.Length);
            pos = 0; end = inp.Length; bitBuf = 0; bitCnt = 0;
            histLen = history.Length;
            outp = new byte[histLen + Math.Max(256, Math.Min(MaxOutput + 1, count * 4))];
            Array.Copy(history, 0, outp, 0, histLen);
            outLen = 0;
            try
            {
                while (true)
                {
                    Block();
                    if (pos >= end && bitCnt == 0) break;
                }
            }
            finally { inp = null; }
            if (outLen == 0) throw new CompressionException("empty result");
            var result = new byte[outLen];
            Array.Copy(outp, histLen, result, 0, outLen);
            // the history for the next packet: the last 32 KB of everything so far
            int total = histLen + outLen, keep = Math.Min(WindowSize, total);
            var h = new byte[keep];
            Array.Copy(outp, total - keep, h, 0, keep);
            history = h;
            outp = null;
            PacketsIn++; BytesIn += count; BytesOut += outLen;
            return result;
        }

        // ------------------------------------------------------------------------------------------------ bits
        int Bits(int need)
        {
            long val = bitBuf;
            while (bitCnt < need)
            {
                if (pos >= end) throw new CompressionException("the stream ends inside a block");
                val |= (long)inp[pos++] << bitCnt;
                bitCnt += 8;
            }
            bitBuf = (int)(val >> need);
            bitCnt -= need;
            return (int)(val & ((1L << need) - 1));
        }

        void Put(byte b)
        {
            if (histLen + outLen >= outp.Length)
            {
                if (outLen >= MaxOutput) throw new CompressionException("more than " + MaxOutput + " bytes in one packet");
                Array.Resize(ref outp, Math.Min(outp.Length * 2, histLen + MaxOutput + 1));
            }
            if (outLen >= MaxOutput) throw new CompressionException("more than " + MaxOutput + " bytes in one packet");
            outp[histLen + outLen++] = b;
        }

        // ------------------------------------------------------------------------------------------------ blocks
        void Block()
        {
            int last = Bits(1);
            int type = Bits(2);
            // a block with the final bit ends the stream; the server never sends one (it only flushes), the main client refuses it too
            if (last != 0) throw new CompressionException("final block");
            switch (type)
            {
                case 0: Stored(); break;
                case 1: Codes(FixedLit, FixedDist); break;
                case 2: Dynamic(); break;
                default: throw new CompressionException("block type 3");
            }
        }

        void Stored()
        {
            bitBuf = 0; bitCnt = 0;   // the rest of the byte is padding
            if (pos + 4 > end) throw new CompressionException("stored block header cut short");
            int len = inp[pos] | inp[pos + 1] << 8;
            int nlen = inp[pos + 2] | inp[pos + 3] << 8;
            pos += 4;
            if (len != (~nlen & 0xFFFF)) throw new CompressionException("stored block length check");
            if (pos + len > end) throw new CompressionException("stored block cut short");
            for (int i = 0; i < len; i++) Put(inp[pos++]);
        }

        // ------------------------------------------------------------------------------------------------ huffman (the canonical decoder of zlib's contrib/puff)
        sealed class Huff
        {
            public readonly short[] Count = new short[16];
            public short[] Symbol;
        }

        static readonly short[] LenBase = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 };
        static readonly short[] LenExtra = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 };
        static readonly short[] DistBase = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 };
        static readonly short[] DistExtra = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 };
        static readonly byte[] CodeLengthOrder = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };

        static readonly Huff FixedLit = BuildFixedLit(), FixedDist = BuildFixedDist();

        static Huff BuildFixedLit()
        {
            var l = new short[288];
            for (int i = 0; i < 144; i++) l[i] = 8;
            for (int i = 144; i < 256; i++) l[i] = 9;
            for (int i = 256; i < 280; i++) l[i] = 7;
            for (int i = 280; i < 288; i++) l[i] = 8;
            var h = new Huff();
            Construct(h, l, 0, 288);
            return h;
        }

        static Huff BuildFixedDist()
        {
            var l = new short[30];
            for (int i = 0; i < 30; i++) l[i] = 5;
            var h = new Huff();
            Construct(h, l, 0, 30);
            return h;
        }

        /// <summary>Builds the decoding tables for n code lengths. 0 complete, less than 0 over-subscribed, more than 0 incomplete.</summary>
        static int Construct(Huff h, short[] length, int off, int n)
        {
            Array.Clear(h.Count, 0, h.Count.Length);
            for (int i = 0; i < n; i++) h.Count[length[off + i]]++;
            h.Symbol = new short[n];
            if (h.Count[0] == n) return 0;
            int left = 1;
            for (int len = 1; len <= 15; len++)
            {
                left <<= 1;
                left -= h.Count[len];
                if (left < 0) return left;
            }
            var offs = new short[16];
            for (int len = 1; len < 15; len++) offs[len + 1] = (short)(offs[len] + h.Count[len]);
            for (int sym = 0; sym < n; sym++)
                if (length[off + sym] != 0) h.Symbol[offs[length[off + sym]]++] = (short)sym;
            return left;
        }

        int Decode(Huff h)
        {
            int code = 0, first = 0, index = 0;
            for (int len = 1; len <= 15; len++)
            {
                code |= Bits(1);
                int count = h.Count[len];
                if (code - count < first) return h.Symbol[index + (code - first)];
                index += count;
                first += count;
                first <<= 1;
                code <<= 1;
            }
            throw new CompressionException("bad code");
        }

        void Dynamic()
        {
            int nlen = Bits(5) + 257, ndist = Bits(5) + 1, ncode = Bits(4) + 4;
            if (nlen > 286 || ndist > 30) throw new CompressionException("too many codes");
            var lengths = new short[320];
            for (int i = 0; i < ncode; i++) lengths[CodeLengthOrder[i]] = (short)Bits(3);
            for (int i = ncode; i < 19; i++) lengths[CodeLengthOrder[i]] = 0;
            var lencode = new Huff();
            if (Construct(lencode, lengths, 0, 19) != 0) throw new CompressionException("code length code");
            int idx = 0;
            while (idx < nlen + ndist)
            {
                int sym = Decode(lencode);
                if (sym < 16) lengths[idx++] = (short)sym;
                else
                {
                    int len = 0, rep;
                    if (sym == 16)
                    {
                        if (idx == 0) throw new CompressionException("repeat with no length");
                        len = lengths[idx - 1];
                        rep = 3 + Bits(2);
                    }
                    else if (sym == 17) rep = 3 + Bits(3);
                    else rep = 11 + Bits(7);
                    if (idx + rep > nlen + ndist) throw new CompressionException("too many lengths");
                    while (rep-- > 0) lengths[idx++] = (short)len;
                }
            }
            if (lengths[256] == 0) throw new CompressionException("no end of block code");
            var lit = new Huff();
            int err = Construct(lit, lengths, 0, nlen);
            if (err != 0 && (err < 0 || nlen - lit.Count[0] != 1)) throw new CompressionException("literal code");
            var dist = new Huff();
            err = Construct(dist, lengths, nlen, ndist);
            if (err != 0 && (err < 0 || ndist - dist.Count[0] != 1)) throw new CompressionException("distance code");
            Codes(lit, dist);
        }

        void Codes(Huff lit, Huff dist)
        {
            while (true)
            {
                int sym = Decode(lit);
                if (sym < 256) { Put((byte)sym); continue; }
                if (sym == 256) return;
                sym -= 257;
                if (sym >= 29) throw new CompressionException("bad length symbol");
                int len = LenBase[sym] + Bits(LenExtra[sym]);
                int ds = Decode(dist);
                if (ds >= 30) throw new CompressionException("bad distance symbol");
                int d = DistBase[ds] + Bits(DistExtra[ds]);
                if (d > histLen + outLen) throw new CompressionException("distance too far back");
                for (int i = 0; i < len; i++)
                {
                    byte b = outp[histLen + outLen - d];
                    Put(b);
                }
            }
        }
    }
}
