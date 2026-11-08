// Where the Unity client gets its sprite pair (Tibia.dat and the sprites) from, in this order (ROADMAP O433 phase 17):
//   1. the -chaosThings DIR flag: a folder of loose files (an explicit choice: when it is wrong the client says so, no fall back)
//   2. loose files in a folder (things/ beside the player, or the folder the login screen names): development
//   3. encrypted blobs in the client's own install, things_enc/*.chub, published by the unity channel
//      (server/deploy/publish_client_update.sh --unity; the main client's own update blobs, same format and key)
//   4. the main client's chaos.pack next to it: the launcher installs both side by side, the player in <install>/unity/ and the main
//      client's files, chaos.pack among them, in <install>/ (the pack is also tried beside the player and with -chaosPack FILE)
// The key of 3 and 4 is the client guard key the build already carries (ClientGuard, CHAOS_CLIENT_KEY): the main client's
// exe holds the same key. Pure logic over IPairFiles, so Core.Tests run it on made-up files and a made-up key.
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace Chaos.Core
{
    public enum PairOrigin { None, Flag, Loose, Blobs, MainPack }

    /// <summary>The file system the locator reads (a fake one in the tests).</summary>
    public interface IPairFiles
    {
        bool Exists(string path);
        long Length(string path);
        Stream Open(string path);
    }

    public sealed class DiskPairFiles : IPairFiles
    {
        public bool Exists(string path) => File.Exists(path);
        public long Length(string path) => new FileInfo(path).Length;
        public Stream Open(string path) => new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16, FileOptions.RandomAccess);
    }

    public sealed class PairRequest
    {
        public string FlagDir, LooseDir, InstallDir, PackFile;
        public byte[] Key;
        /// <summary>The key is the public development key (a package built without embed_client_key): used only to explain a failure.</summary>
        public bool KeyIsDev;
        /// <summary>Shards of blobs kept decrypted at once (about 30 MB each).</summary>
        public int MaxResidentShards = 6;
    }

    public sealed class PairResult
    {
        public PairOrigin Origin;
        public string Where, Error;
        public DatFile Dat;
        public SprFile Spr;
        public bool Ok => Dat != null && Spr != null;
    }

    public static class PairLocator
    {
        public const string BlobDir = "things_enc", BlobExt = ".chub", PackName = "chaos.pack";
        public const string Dat = "Tibia.dat", Spr = "Tibia.spr", Index = "Tibia.sprshards";

        public static PairResult Find(PairRequest r, IPairFiles fs)
        {
            var errors = new List<string>();
            if (!string.IsNullOrEmpty(r.FlagDir))
            {
                var f = Loose(fs, r.FlagDir, PairOrigin.Flag, errors);
                return f ?? Fail("-chaosThings " + r.FlagDir + ": " + string.Join("; ", errors));
            }
            if (!string.IsNullOrEmpty(r.LooseDir))
            {
                var l = Loose(fs, r.LooseDir, PairOrigin.Loose, errors);
                if (l != null) return l;
                // a folder without Tibia.dat is the normal case of a player's install, not a problem; one with a dat and a broken set is
                if (!fs.Exists(Path.Combine(r.LooseDir, Dat))) errors.Clear();
            }
            if (!string.IsNullOrEmpty(r.InstallDir))
            {
                string dir = Path.Combine(r.InstallDir, BlobDir);
                if (fs.Exists(Path.Combine(dir, Dat + BlobExt)))
                {
                    try { return Blobs(r, fs, dir); }
                    catch (Exception e) when (e is PackException || e is ProtocolException) { errors.Add("encrypted pair in " + dir + ": " + Explain(r, e.Message)); }
                }
            }
            foreach (string pack in PackCandidates(r))
            {
                if (!fs.Exists(pack)) continue;
                try { return Pack(r, fs, pack); }
                catch (Exception e) when (e is PackException || e is ProtocolException) { errors.Add(PackName + " " + pack + ": " + Explain(r, e.Message)); }
                break;
            }
            if (errors.Count == 0)
                errors.Add("no loose pair (" + Dat + " with " + Spr + " or " + Index + "), no " + BlobDir + "/ and no " + PackName + " next to the player");
            return Fail(string.Join("; ", errors));
        }

        static PairResult Fail(string why) => new PairResult { Origin = PairOrigin.None, Error = why };

        /// <summary>Where the main client's pack is looked for: -chaosPack FILE, the install folder above the player, beside the player.</summary>
        public static List<string> PackCandidates(PairRequest r)
        {
            var list = new List<string>();
            if (!string.IsNullOrEmpty(r.PackFile)) list.Add(r.PackFile);
            if (!string.IsNullOrEmpty(r.InstallDir))
            {
                string full = r.InstallDir.TrimEnd('/', '\\');
                string parent = Path.GetDirectoryName(full);
                if (!string.IsNullOrEmpty(parent)) list.Add(Path.Combine(parent, PackName));
                list.Add(Path.Combine(full, PackName));
            }
            return list;
        }

        static string Explain(PairRequest r, string why)
        {
            if (r.KeyIsDev && why.IndexOf("wrong key", StringComparison.Ordinal) >= 0)
                return why + " (this is a development package with the public key; the pair is encrypted for a keyed build: put loose files in things/ or use -chaosThings DIR)";
            return why;
        }

        // ---------------------------------------------------------------------------------------------------- loose files

        static PairResult Loose(IPairFiles fs, string dir, PairOrigin origin, List<string> errors)
        {
            string d = Path.Combine(dir, Dat), s = Path.Combine(dir, Spr), ix = Path.Combine(dir, Index);
            if (!fs.Exists(d)) { errors.Add("no " + Dat + " in " + dir); return null; }
            try
            {
                SprFile spr = null;
                if (fs.Exists(ix))
                {
                    try { spr = LooseShards(fs, dir, ix); }
                    catch (ProtocolException e) { errors.Add(e.Message); if (!fs.Exists(s)) return null; }   // the engine falls back to the single file
                }
                if (spr == null)
                {
                    if (!fs.Exists(s)) { errors.Add("no " + Spr + " or " + Index + " in " + dir); return null; }
                    spr = new SprFile(fs.Open(s));
                }
                DatFile dat;
                using (var ds = fs.Open(d)) dat = DatFile.Parse(ReadAll(ds, fs.Length(d)));
                return new PairResult { Origin = origin, Where = dir, Dat = dat, Spr = spr };
            }
            catch (ProtocolException e) { errors.Add(e.Message); return null; }
        }

        static SprFile LooseShards(IPairFiles fs, string dir, string indexPath)
        {
            SprShardIndex idx;
            using (var xs = fs.Open(indexPath)) idx = SprShardIndex.Parse(Encoding.UTF8.GetString(ReadAll(xs, fs.Length(indexPath))));
            // as the engine: every shard has to be there with the size the index gives, else the whole set is dropped
            foreach (var sh in idx.Shards)
            {
                string p = Path.Combine(dir, sh.Name);
                if (!fs.Exists(p)) throw new ProtocolException("sprite shards: missing shard " + sh.Name);
                if (fs.Length(p) != sh.Size) throw new ProtocolException("sprite shards: " + sh.Name + " has " + fs.Length(p) + " bytes, the index says " + sh.Size);
            }
            return new SprFile(new SprShardSet(idx, sh => fs.Open(Path.Combine(dir, sh.Name))));
        }

        // ---------------------------------------------------------------------------------------------------- update blobs

        static PairResult Blobs(PairRequest r, IPairFiles fs, string dir)
        {
            if (r.Key == null) throw new PackException("no client key");
            Func<string, byte[]> read = name =>
            {
                string p = Path.Combine(dir, name + BlobExt);
                if (!fs.Exists(p)) throw new PackException("missing " + name + BlobExt);
                using (var s = fs.Open(p)) return BlobReader.Decrypt(s, fs.Length(p), r.Key);
            };
            DatFile dat = DatFile.Parse(read(Dat));
            var idx = SprShardIndex.Parse(Encoding.UTF8.GetString(read(Index)));
            foreach (var sh in idx.Shards)      // present before the first sprite is asked for, as the engine checks its shards
                if (!fs.Exists(Path.Combine(dir, sh.Name + BlobExt))) throw new PackException("missing " + sh.Name + BlobExt);
            var spr = new SprFile(new SprShardSet(idx, sh => new MemoryStream(read(sh.Name), false), r.MaxResidentShards));
            return new PairResult { Origin = PairOrigin.Blobs, Where = dir, Dat = dat, Spr = spr };
        }

        // ---------------------------------------------------------------------------------------------------- chaos.pack

        /// <summary>The pair entries of a pack: data/things/&lt;digits&gt;/Tibia.dat, .sprshards, .spr or .NNN.spr.</summary>
        public static bool WantedEntry(string name, out string version, out string file)
        {
            version = file = null;
            var p = name.Split('/');
            if (p.Length != 4 || p[0] != "data" || p[1] != "things" || p[2].Length == 0) return false;
            foreach (char c in p[2]) if (c < '0' || c > '9') return false;
            string f = p[3];
            if (!f.StartsWith("Tibia.", StringComparison.Ordinal)) return false;
            if (!(f.EndsWith(".dat", StringComparison.Ordinal) || f.EndsWith(".spr", StringComparison.Ordinal) || f.EndsWith(".sprshards", StringComparison.Ordinal))) return false;
            version = p[2]; file = f;
            return true;
        }

        static PairResult Pack(PairRequest r, IPairFiles fs, string path)
        {
            if (r.Key == null) throw new PackException("no client key");
            PackContents c;
            using (var s = fs.Open(path))
                c = PackReader.Read(s, fs.Length(path), r.Key, n => { string v, f; return WantedEntry(n, out v, out f); });
            // the newest things folder that has a Tibia.dat
            string best = null;
            foreach (var n in c.Entries.Keys)
            {
                string v, f;
                if (!WantedEntry(n, out v, out f) || f != Dat) continue;
                if (best == null || string.CompareOrdinal(v.PadLeft(8, '0'), best.PadLeft(8, '0')) > 0) best = v;
            }
            if (best == null) throw new ProtocolException("the pack holds no data/things/*/" + Dat);
            string prefix = "data/things/" + best + "/";
            DatFile dat = DatFile.Parse(c.Entries[prefix + Dat]);
            c.Entries.Remove(prefix + Dat);
            SprFile spr;
            if (c.Entries.ContainsKey(prefix + Index))
            {
                var idx = SprShardIndex.Parse(Encoding.UTF8.GetString(c.Entries[prefix + Index]));
                foreach (var sh in idx.Shards) if (!c.Entries.ContainsKey(prefix + sh.Name)) throw new ProtocolException("sprite shards: missing shard " + sh.Name);
                var entries = c.Entries;
                spr = new SprFile(new SprShardSet(idx, sh => new MemoryStream(entries[prefix + sh.Name], false)));
            }
            else if (c.Entries.ContainsKey(prefix + Spr)) spr = new SprFile(new MemoryStream(c.Entries[prefix + Spr], false));
            else throw new ProtocolException("the pack holds no " + Index + " or " + Spr + " beside its " + Dat);
            return new PairResult { Origin = PairOrigin.MainPack, Where = path, Dat = dat, Spr = spr };
        }

        static byte[] ReadAll(Stream s, long length)
        {
            if (length > int.MaxValue - 64) throw new ProtocolException("file too large");
            var b = new byte[length];
            int got = 0;
            while (got < b.Length)
            {
                int k = s.Read(b, got, b.Length - got);
                if (k <= 0) throw new ProtocolException("short read");
                got += k;
            }
            return b;
        }
    }
}
