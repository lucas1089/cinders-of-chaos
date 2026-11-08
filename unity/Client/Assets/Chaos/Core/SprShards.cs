// The sharded sprite file of the main client, read as the engine reads it (client/base-patches/0048-sharded-sprites.patch,
// SpriteManager::loadShardedSpr; writer client/tools/sprites/spr_shards.py; client/MANIFEST.md "Sharded sprites").
//
// <name>.sprshards is a text index: the format line "chaos-spr-shards 1", then `signature N`, `sprites N`, `per-shard N` (information
// only) and one `shard FIRST COUNT FILE SIZE SHA256` line per shard, in id order, with no gap. Each shard file is a normal .spr
// (u32 signature, u32 count, count x u32 address inside the shard, the records) that holds the sprite ids FIRST .. FIRST+COUNT-1;
// the id inside the shard is id - FIRST + 1. The engine checks the format line, that the shards cover 1..sprites with no gap, every
// file's size and its header (signature, count) and draws nothing for a shard that fails; this reader does the same.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;

namespace Chaos.Core
{
    public sealed class SprShardIndex
    {
        public sealed class Shard
        {
            public uint First, Count;
            public string Name, Sha256;
            public long Size;
        }

        public uint Signature, Total;
        public readonly List<Shard> Shards = new List<Shard>();

        public static SprShardIndex Parse(string text)
        {
            var idx = new SprShardIndex();
            bool haveFormat = false, haveSignature = false, haveTotal = false;
            foreach (var raw in (text ?? "").Split('\n'))
            {
                string line = raw.Trim();
                if (line.Length == 0 || line[0] == '#') continue;
                if (!haveFormat)
                {
                    if (line != "chaos-spr-shards 1") throw new ProtocolException("sprite shards: unknown index format");
                    haveFormat = true;
                    continue;
                }
                var w = line.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                switch (w[0])
                {
                    case "signature":
                        if (w.Length < 2 || !uint.TryParse(w[1], NumberStyles.None, CultureInfo.InvariantCulture, out idx.Signature)) throw new ProtocolException("sprite shards: bad line " + line);
                        haveSignature = true;
                        break;
                    case "sprites":
                        if (w.Length < 2 || !uint.TryParse(w[1], NumberStyles.None, CultureInfo.InvariantCulture, out idx.Total)) throw new ProtocolException("sprite shards: bad line " + line);
                        haveTotal = true;
                        break;
                    case "per-shard":
                        break;      // informative: the ranges decide
                    case "shard":
                        var s = new Shard();
                        if (w.Length < 6 || !uint.TryParse(w[1], NumberStyles.None, CultureInfo.InvariantCulture, out s.First) ||
                            !uint.TryParse(w[2], NumberStyles.None, CultureInfo.InvariantCulture, out s.Count) ||
                            !long.TryParse(w[4], NumberStyles.None, CultureInfo.InvariantCulture, out s.Size))
                            throw new ProtocolException("sprite shards: bad shard line " + line);
                        s.Name = w[3]; s.Sha256 = w[5];
                        if (s.Name.Length == 0 || s.Name[0] == '.' || s.Name.IndexOf('/') >= 0 || s.Name.IndexOf('\\') >= 0 || s.Name.IndexOf(':') >= 0)
                            throw new ProtocolException("sprite shards: bad shard file name " + s.Name);
                        long expect = idx.Shards.Count == 0 ? 1 : (long)idx.Shards[idx.Shards.Count - 1].First + idx.Shards[idx.Shards.Count - 1].Count;
                        if (s.First != expect) throw new ProtocolException("sprite shards: " + s.Name + " starts at " + s.First + ", expected " + expect);
                        if (s.Count > (0xFFFFFFFFu - 8) / 4 || s.Size < 8 + 4L * s.Count) throw new ProtocolException("sprite shards: " + s.Name + " is too small for its sprites");
                        idx.Shards.Add(s);
                        break;
                    default:
                        throw new ProtocolException("sprite shards: bad index line " + line);
                }
            }
            if (!haveFormat || !haveSignature || !haveTotal || idx.Shards.Count == 0) throw new ProtocolException("sprite shards: incomplete index");
            var last = idx.Shards[idx.Shards.Count - 1];
            if ((long)last.First + last.Count - 1 != idx.Total) throw new ProtocolException("sprite shards: the shards do not hold exactly the sprites the index names");
            return idx;
        }

        /// <summary>The shard that holds `id` (1-based), or null.</summary>
        public Shard Find(uint id)
        {
            int lo = 0, hi = Shards.Count - 1;
            while (lo <= hi)
            {
                int mid = (lo + hi) / 2;
                var s = Shards[mid];
                if (id < s.First) hi = mid - 1;
                else if (id >= (long)s.First + s.Count) lo = mid + 1;
                else return s;
            }
            return null;
        }
    }

    /// <summary>The shards of one sprite file, opened when a sprite needs them. `maxResident` shards stay open (the least recently
    /// used closes first): a shard of encrypted blobs lives in memory (about 30 MB), loose ones are file handles.</summary>
    public sealed class SprShardSet : IDisposable
    {
        public readonly SprShardIndex Index;
        readonly Func<SprShardIndex.Shard, Stream> openShard;
        readonly int maxResident;
        readonly object gate = new object();
        readonly Dictionary<string, SprFile> resident = new Dictionary<string, SprFile>();
        readonly LinkedList<string> order = new LinkedList<string>();
        readonly HashSet<string> failed = new HashSet<string>();
        public string LastError;
        public int Opens;

        public SprShardSet(SprShardIndex index, Func<SprShardIndex.Shard, Stream> openShard, int maxResident = int.MaxValue)
        {
            Index = index; this.openShard = openShard; this.maxResident = Math.Max(1, maxResident);
        }

        /// <summary>RGBA of a sprite; null for an empty id, an id out of range or a shard that does not open (LastError says why, as the
        /// engine logs it once: that shard draws nothing).</summary>
        public byte[] Rgba(uint id)
        {
            var sh = Index.Find(id);
            if (sh == null) return null;
            SprFile file = Get(sh);
            return file == null ? null : file.Rgba(id - sh.First + 1);
        }

        SprFile Get(SprShardIndex.Shard sh)
        {
            lock (gate)
            {
                SprFile f;
                if (resident.TryGetValue(sh.Name, out f))
                {
                    order.Remove(sh.Name);
                    order.AddFirst(sh.Name);
                    return f;
                }
                if (failed.Contains(sh.Name)) return null;
                try
                {
                    Stream s = openShard(sh);
                    long have = s.Length;
                    if (have != sh.Size) { s.Dispose(); throw new ProtocolException(sh.Name + " has " + have + " bytes, the index says " + sh.Size); }
                    f = new SprFile(s);
                    if (f.Signature != Index.Signature || f.Count != sh.Count) { f.Dispose(); throw new ProtocolException(sh.Name + ": header does not match the index"); }
                }
                catch (Exception e)
                {
                    failed.Add(sh.Name);
                    LastError = "sprite shard " + sh.Name + ": " + e.Message;
                    return null;
                }
                Opens++;
                resident[sh.Name] = f;
                order.AddFirst(sh.Name);
                while (resident.Count > maxResident)
                {
                    string drop = order.Last.Value;
                    order.RemoveLast();
                    resident[drop].Dispose();
                    resident.Remove(drop);
                }
                return f;
            }
        }

        public int ResidentCount { get { lock (gate) return resident.Count; } }

        public void Dispose()
        {
            lock (gate)
            {
                foreach (var f in resident.Values) f.Dispose();
                resident.Clear();
                order.Clear();
            }
        }
    }
}
