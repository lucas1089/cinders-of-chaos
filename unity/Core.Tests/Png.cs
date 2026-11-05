// A minimal RGBA PNG writer for the probe (no image library).
using System.IO;
using System.IO.Compression;

namespace Chaos.Core.Tests
{
    static class Png
    {
        static readonly uint[] Table = MakeTable();

        static uint[] MakeTable()
        {
            var t = new uint[256];
            for (uint n = 0; n < 256; n++)
            {
                uint c = n;
                for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
                t[n] = c;
            }
            return t;
        }

        static uint Crc(byte[] b, int off, int n)
        {
            uint c = 0xFFFFFFFFu;
            for (int i = off; i < off + n; i++) c = Table[(c ^ b[i]) & 0xFF] ^ (c >> 8);
            return c ^ 0xFFFFFFFFu;
        }

        static void Chunk(Stream s, string type, byte[] data)
        {
            var buf = new byte[4 + data.Length];
            for (int i = 0; i < 4; i++) buf[i] = (byte)type[i];
            data.CopyTo(buf, 4);
            Be(s, (uint)data.Length);
            s.Write(buf, 0, buf.Length);
            Be(s, Crc(buf, 0, buf.Length));
        }

        static void Be(Stream s, uint v)
        {
            s.WriteByte((byte)(v >> 24)); s.WriteByte((byte)(v >> 16)); s.WriteByte((byte)(v >> 8)); s.WriteByte((byte)v);
        }

        public static void Write(string path, byte[] rgba, int w, int h)
        {
            using var f = File.Create(path);
            f.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }, 0, 8);
            var ihdr = new MemoryStream();
            Be(ihdr, (uint)w); Be(ihdr, (uint)h);
            ihdr.Write(new byte[] { 8, 6, 0, 0, 0 }, 0, 5);
            Chunk(f, "IHDR", ihdr.ToArray());
            var raw = new MemoryStream();
            for (int y = 0; y < h; y++)
            {
                raw.WriteByte(0);
                raw.Write(rgba, y * w * 4, w * 4);
            }
            var z = new MemoryStream();
            using (var zs = new ZLibStream(z, CompressionLevel.Optimal, true)) raw.WriteTo(zs);
            Chunk(f, "IDAT", z.ToArray());
            Chunk(f, "IEND", new byte[0]);
        }
    }
}
