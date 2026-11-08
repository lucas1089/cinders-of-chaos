// The 10.98 thing types (.dat) and sprites (.spr) of the client pair, as the pair's .otfi describes them:
// extended (u32 sprite ids), transparency (RGBA pixels), frame durations, frame groups for outfits.
using System;
using System.Collections.Generic;
using System.IO;

namespace Chaos.Core
{
    public enum ThingCategory { Item = 0, Outfit = 1, Effect = 2, Missile = 3 }

    public sealed class FrameGroup
    {
        public byte Type;          // 0 idle, 1 moving (outfits with two groups)
        public int Width, Height, ExactSize, Layers, PatternX, PatternY, PatternZ, Phases;
        public bool Async;
        public int LoopCount, StartPhase;
        public int[] MinDuration, MaxDuration;   // per phase, ms; null without frame durations
        public uint[] Sprites;

        /// <summary>The sprite id of one tile of the thing (stock index order).</summary>
        public uint Sprite(int w, int h, int layer, int px, int py, int pz, int phase)
        {
            int i = ((((((phase % Phases) * PatternZ + pz % PatternZ) * PatternY + py % PatternY) * PatternX
                       + px % PatternX) * Layers + layer) * Height + h) * Width + w;
            return Sprites[i];
        }
    }

    public sealed class ThingType
    {
        public ThingCategory Category;
        public int Id;
        public bool Ground, GroundBorder, OnBottom, OnTop, Container, Stackable, ForceUse, MultiUse;
        public bool Fluid, Splash, NotWalkable, NotMoveable, BlockMissile, BlockPath, Pickupable, Hangable;
        public bool HookSouth, HookEast, Rotateable, DontHide, Translucent, Lying, AnimateAlways, FullGround;
        public bool IgnoreLook, Usable, TopEffect, NoMoveAnimation;
        public int MarketCategory = -1;
        public string MarketName = "";
        public int GroundSpeed, LightLevel, LightColor, DisplacementX, DisplacementY, Elevation, MinimapColor;
        public FrameGroup[] Groups;

        public FrameGroup Idle => Groups[0];
        public FrameGroup Moving => Groups.Length > 1 ? Groups[1] : Groups[0];
        public const int QuiverCategory = 25;   // client base patch 0174: quivers carry a count, by market category
        /// <summary>The server sends a count / fluid byte after the id of these items.</summary>
        public bool HasSubType => Stackable || Fluid || Splash || MarketCategory == QuiverCategory;
        /// <summary>The server sends a phase byte after these items (the dat has more than one phase).</summary>
        public bool HasPhaseByte => Groups[0].Phases > 1;
    }

    public sealed class DatOptions
    {
        public bool Extended = true;        // u32 sprite ids
        public bool FrameDurations = true;  // animation block after phases > 1
        public bool FrameGroups = true;     // outfits carry 1-2 frame groups
        /// <summary>Custom flag bytes and how many data bytes follow (-1: u8 count of 16-byte records).</summary>
        public Dictionary<byte, int> Extra = new Dictionary<byte, int> { { 39, 16 }, { 41, 0 }, { 42, -1 }, { 43, 0 }, { 46, 4 }, { 62, 16 } };
    }

    public sealed class DatFile
    {
        public uint Signature;
        public ThingType[] Items, Outfits, Effects, Missiles;   // index = id (items from 100; outfits, effects, missiles from 1)

        public ThingType Item(int id) => id >= 100 && id < Items.Length ? Items[id] : null;
        public ThingType Outfit(int id) => id >= 1 && id < Outfits.Length ? Outfits[id] : null;
        public ThingType Effect(int id) => id >= 1 && id < Effects.Length ? Effects[id] : null;
        public ThingType Missile(int id) => id >= 1 && id < Missiles.Length ? Missiles[id] : null;

        public static DatFile Load(string path, DatOptions opt = null) => Parse(File.ReadAllBytes(path), opt);

        public static DatFile Parse(byte[] data, DatOptions opt = null)
        {
            opt = opt ?? new DatOptions();
            var r = new ByteReader(data);
            var dat = new DatFile { Signature = r.U32() };
            int items = r.U16(), outfits = r.U16(), effects = r.U16(), missiles = r.U16();
            dat.Items = ReadCategory(r, ThingCategory.Item, 100, items, opt);
            dat.Outfits = ReadCategory(r, ThingCategory.Outfit, 1, outfits, opt);
            dat.Effects = ReadCategory(r, ThingCategory.Effect, 1, effects, opt);
            dat.Missiles = ReadCategory(r, ThingCategory.Missile, 1, missiles, opt);
            if (!r.AtEnd) throw new ProtocolException("dat: " + r.Remaining + " trailing bytes (wrong options?)");
            return dat;
        }

        static ThingType[] ReadCategory(ByteReader r, ThingCategory cat, int first, int last, DatOptions opt)
        {
            var list = new ThingType[last + 1];
            for (int id = first; id <= last; id++)
            {
                var t = new ThingType { Category = cat, Id = id };
                ReadFlags(r, t, opt);
                int groups = 1;
                if (opt.FrameGroups && cat == ThingCategory.Outfit) groups = r.U8();
                if (groups < 1 || groups > 2) throw new ProtocolException("dat: " + cat + " " + id + ": " + groups + " frame groups");
                t.Groups = new FrameGroup[groups];
                for (int g = 0; g < groups; g++)
                {
                    var fg = new FrameGroup();
                    if (opt.FrameGroups && cat == ThingCategory.Outfit) fg.Type = r.U8();
                    fg.Width = r.U8();
                    fg.Height = r.U8();
                    fg.ExactSize = fg.Width > 1 || fg.Height > 1 ? r.U8() : 32;
                    fg.Layers = r.U8();
                    fg.PatternX = r.U8();
                    fg.PatternY = r.U8();
                    fg.PatternZ = r.U8();
                    fg.Phases = r.U8();
                    if (fg.Width == 0 || fg.Height == 0 || fg.Layers == 0 || fg.PatternX == 0 || fg.PatternY == 0 || fg.PatternZ == 0 || fg.Phases == 0)
                        throw new ProtocolException("dat: " + cat + " " + id + ": a zero size");
                    if (fg.Phases > 1 && opt.FrameDurations)
                    {
                        fg.Async = r.U8() == 0;
                        fg.LoopCount = r.I32();
                        fg.StartPhase = r.I8();
                        fg.MinDuration = new int[fg.Phases];
                        fg.MaxDuration = new int[fg.Phases];
                        for (int p = 0; p < fg.Phases; p++)
                        {
                            fg.MinDuration[p] = (int)r.U32();
                            fg.MaxDuration[p] = (int)r.U32();
                        }
                    }
                    int n = fg.Width * fg.Height * fg.Layers * fg.PatternX * fg.PatternY * fg.PatternZ * fg.Phases;
                    fg.Sprites = new uint[n];
                    for (int i = 0; i < n; i++) fg.Sprites[i] = opt.Extended ? r.U32() : r.U16();
                    t.Groups[g] = fg;
                }
                list[id] = t;
            }
            return list;
        }

        // 10.10+ flag table (10.98)
        static void ReadFlags(ByteReader r, ThingType t, DatOptions opt)
        {
            while (true)
            {
                byte f = r.U8();
                if (f == 0xFF) return;
                switch (f)
                {
                    case 0: t.Ground = true; t.GroundSpeed = r.U16(); break;
                    case 1: t.GroundBorder = true; break;
                    case 2: t.OnBottom = true; break;
                    case 3: t.OnTop = true; break;
                    case 4: t.Container = true; break;
                    case 5: t.Stackable = true; break;
                    case 6: t.ForceUse = true; break;
                    case 7: t.MultiUse = true; break;
                    case 8: case 9: r.U16(); break;               // writable, writable once: max length
                    case 10: t.Fluid = true; break;
                    case 11: t.Splash = true; break;
                    case 12: t.NotWalkable = true; break;
                    case 13: t.NotMoveable = true; break;
                    case 14: t.BlockMissile = true; break;
                    case 15: t.BlockPath = true; break;
                    case 16: t.NoMoveAnimation = true; break;
                    case 17: t.Pickupable = true; break;
                    case 18: t.Hangable = true; break;
                    case 19: t.HookSouth = true; break;
                    case 20: t.HookEast = true; break;
                    case 21: t.Rotateable = true; break;
                    case 22: t.LightLevel = r.U16(); t.LightColor = r.U16(); break;
                    case 23: t.DontHide = true; break;
                    case 24: t.Translucent = true; break;
                    case 25: t.DisplacementX = r.U16(); t.DisplacementY = r.U16(); break;
                    case 26: t.Elevation = r.U16(); break;
                    case 27: t.Lying = true; break;
                    case 28: t.AnimateAlways = true; break;
                    case 29: t.MinimapColor = r.U16(); break;
                    case 30: r.U16(); break;                      // lens help
                    case 31: t.FullGround = true; break;
                    case 32: t.IgnoreLook = true; break;
                    case 33: r.U16(); break;                      // cloth slot
                    case 34:                                      // market
                        t.MarketCategory = r.U16(); r.U16(); r.U16(); t.MarketName = r.Str(); r.U16(); r.U16();
                        break;
                    case 35: r.U16(); break;                      // default action
                    case 36: case 37: break;                      // wrappable, unwrappable
                    case 38: t.TopEffect = true; break;
                    case 254: t.Usable = true; break;
                    default:
                        int extra;
                        if (!opt.Extra.TryGetValue(f, out extra))
                            throw new ProtocolException("dat: unknown flag " + f + " on " + t.Category + " " + t.Id);
                        if (extra >= 0) r.Skip(extra);
                        else r.Skip(16 * r.U8());
                        break;
                }
            }
        }
    }

    /// <summary>Random access to the sprites of a .spr file; decodes one 32x32 sprite to RGBA.</summary>
    public sealed class SprFile : IDisposable
    {
        public const int Size = 32;
        readonly Stream s;
        readonly bool transparency;
        readonly object gate = new object();
        public readonly uint Signature;
        public readonly uint Count;
        byte[] rec = new byte[8192];

        public SprFile(Stream stream, bool extended = true, bool transparency = true)
        {
            s = stream;
            this.transparency = transparency;
            var head = new byte[8];
            ReadAt(0, head, 8);
            Signature = (uint)(head[0] | head[1] << 8 | head[2] << 16 | head[3] << 24);
            Count = extended ? (uint)(head[4] | head[5] << 8 | head[6] << 16 | head[7] << 24) : (uint)(head[4] | head[5] << 8);
            headerSize = extended ? 8 : 6;
        }

        readonly int headerSize;
        readonly SprShardSet shards;

        /// <summary>A sprite file kept as shards (Core/SprShards.cs): the ids are looked up in the shard that holds them.</summary>
        public SprFile(SprShardSet shards)
        {
            this.shards = shards;
            transparency = true;
            Signature = shards.Index.Signature;
            Count = shards.Index.Total;
        }

        /// <summary>Why the last shard that did not open failed, or null (sharded files only).</summary>
        public string ShardError => shards?.LastError;

        public static SprFile Open(string path) => new SprFile(new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 4096, FileOptions.RandomAccess));

        void ReadAt(long pos, byte[] into, int n)
        {
            s.Position = pos;
            int got = 0;
            while (got < n)
            {
                int k = s.Read(into, got, n - got);
                if (k <= 0) throw new ProtocolException("spr: short read at " + pos);
                got += k;
            }
        }

        /// <summary>RGBA32, rows top to bottom (32*32*4 bytes); null for an empty sprite or an id out of range.</summary>
        public byte[] Rgba(uint id)
        {
            if (id == 0 || id > Count) return null;
            if (shards != null) return shards.Rgba(id);
            lock (gate)
            {
                var off = new byte[4];
                ReadAt(headerSize + 4L * (id - 1), off, 4);
                long at = (uint)(off[0] | off[1] << 8 | off[2] << 16 | off[3] << 24);
                if (at == 0) return null;
                var head = new byte[5];
                ReadAt(at, head, 5);   // 3 bytes colour key, u16 size
                int size = head[3] | head[4] << 8;
                if (size == 0) return null;
                if (rec.Length < size) rec = new byte[size];
                ReadAt(at + 5, rec, size);
                return Decode(rec, size, transparency);
            }
        }

        public static byte[] Decode(byte[] data, int size, bool transparency)
        {
            var px = new byte[Size * Size * 4];
            int p = 0, i = 0, bpp = transparency ? 4 : 3;
            while (p + 4 <= size)
            {
                int skip = data[p] | data[p + 1] << 8;
                int count = data[p + 2] | data[p + 3] << 8;
                p += 4;
                i += skip;
                if (i + count > Size * Size || p + count * bpp > size) throw new ProtocolException("spr: bad record");
                for (int k = 0; k < count; k++, i++, p += bpp)
                {
                    px[i * 4] = data[p];
                    px[i * 4 + 1] = data[p + 1];
                    px[i * 4 + 2] = data[p + 2];
                    px[i * 4 + 3] = transparency ? data[p + 3] : (byte)255;
                }
            }
            return px;
        }

        public void Dispose() { if (shards != null) shards.Dispose(); else s.Dispose(); }
    }
}
