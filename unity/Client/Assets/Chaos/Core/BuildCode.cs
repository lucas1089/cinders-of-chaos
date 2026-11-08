// The full build code "CC1-..." (client game_passivetree/buildcode.lua, the website's PHP twin, vectors in docs/build_code_vectors.txt).
// One string holds the class, the level, the passive tree (the server's own tree code "CB<n>-" inside), the spell rotation and the
// worn gear. Applying the tree always goes through the server (buildPreview and buildApply of opcode 65), which decides by its rules.
//   "CC1-" + base64url(payload + checksum), no padding. payload = sections: tag (1 byte), length (2 bytes, high first), data.
//   tag 1 class (index into Classes), 2 level (2 bytes), 3 tree (version byte + tree code bytes), 4 spells (2 bytes each), 5 gear
//   (slot byte + 2 byte item id each, slots ascending). checksum = 3 bytes, h = (h * 257 + x) % 16777213 over "CC1" and the payload.
using System;
using System.Collections.Generic;
using System.Text;

namespace Chaos.Core
{
    public sealed class BuildCard
    {
        public string Class;
        public int Vocation;
        public int? Level;
        /// <summary>The server's tree code ("CB6-...").</summary>
        public string Tree;
        public TreeCode TreeInfo;
        public List<int> Spells = new List<int>();
        public List<KeyValuePair<int, int>> Gear = new List<KeyValuePair<int, int>>();
        public int Skipped;
    }

    /// <summary>What a tree code holds.</summary>
    public sealed class TreeCode
    {
        public int Version, Line;
        public bool Newer;
        public List<int> Nodes = new List<int>();
        public Dictionary<string, int> Paragon = new Dictionary<string, int>();
        public Dictionary<int, int> Masteries = new Dictionary<int, int>();
    }

    public static class BuildCode
    {
        public const string Prefix = "CC", TreePrefix = "CB";
        public const int Version = 1, MaxCode = 1000, MaxSpells = 16, TreeLayoutMax = 6;
        const string Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
        const long Mod = 16777213;

        /// <summary>Class key, vocation id, name. The index + 1 is the code's class byte. Append only.</summary>
        public static readonly string[][] Classes =
        {
            new[] { "warrior", "4", "Warrior" }, new[] { "juggernaut", "8", "Juggernaut" }, new[] { "berserker", "14", "Berserker" },
            new[] { "ranger", "3", "Ranger" }, new[] { "deadeye", "7", "Deadeye" }, new[] { "beastmaster", "15", "Beastmaster" },
            new[] { "mystic", "1", "Mystic" }, new[] { "elementalist", "5", "Elementalist" }, new[] { "illusionist", "10", "Illusionist" },
            new[] { "thief", "11", "Thief" }, new[] { "ninja", "12", "Ninja" }, new[] { "samurai", "13", "Samurai" },
            new[] { "monk", "17", "Monk" }, new[] { "shadowfist", "18", "Shadowfist" }, new[] { "ironsage", "19", "Iron Sage" },
            new[] { "necromancer", "20", "Necromancer" }, new[] { "lich", "21", "Lich" }, new[] { "bonelord", "22", "Bone Lord" },
            new[] { "templar", "23", "Templar" }, new[] { "inquisitor", "24", "Inquisitor" }, new[] { "sentinel", "25", "Sentinel" },
        };

        public static readonly string[] ParagonKeys = { "damage", "critDamage", "health", "reduction", "speed", "mana", "goldFind", "itemFind" };
        public static readonly int[] GearSlots = { 1, 2, 4, 5, 6, 7, 8, 9, 10 };

        static long Checksum(string head, IList<byte> bytes, int count)
        {
            long h = 0;
            foreach (char c in head) h = (h * 257 + c) % Mod;
            for (int i = 0; i < count; i++) h = (h * 257 + bytes[i]) % Mod;
            return h;
        }

        public static string ToBase64(IList<byte> bytes)
        {
            var sb = new StringBuilder();
            for (int i = 0; i < bytes.Count; i += 3)
            {
                int a = bytes[i], b = i + 1 < bytes.Count ? bytes[i + 1] : -1, c = i + 2 < bytes.Count ? bytes[i + 2] : -1;
                int n = a * 65536 + Math.Max(b, 0) * 256 + Math.Max(c, 0);
                int chars = 2 + (b >= 0 ? 1 : 0) + (c >= 0 ? 1 : 0);
                for (int k = 1; k <= chars; k++) sb.Append(Alphabet[(n >> (6 * (4 - k))) & 63]);
            }
            return sb.ToString();
        }

        /// <summary>The bytes of a base64url text, or null (bad character, bad length, not the canonical form).</summary>
        public static byte[] FromBase64(string text)
        {
            if (text == null || text.Length % 4 == 1) return null;
            var bytes = new List<byte>();
            for (int i = 0; i < text.Length; i += 4)
            {
                int len = Math.Min(4, text.Length - i);
                int n = 0;
                for (int k = 0; k < 4; k++)
                {
                    int v = 0;
                    if (k < len)
                    {
                        v = Alphabet.IndexOf(text[i + k]);
                        if (v < 0) return null;
                    }
                    n = n * 64 + v;
                }
                for (int k = 1; k <= len - 1; k++) bytes.Add((byte)((n >> (8 * (3 - k))) & 255));
            }
            if (ToBase64(bytes) != text) return null;   // the unused low bits of the last character must be zero
            return bytes.ToArray();
        }

        public static int ClassIndex(string key)
        {
            for (int i = 0; i < Classes.Length; i++) if (Classes[i][0] == key) return i + 1;
            return 0;
        }

        public static string ClassOfVocation(int vocation)
        {
            foreach (var c in Classes) if (c[1] == vocation.ToString()) return c[0];
            return null;
        }

        // ------------------------------------------------------------------------------------ the inner tree code
        static bool TreeBytes(string code, out int version, out byte[] bytes)
        {
            version = 0; bytes = null;
            if (code == null || !code.StartsWith(TreePrefix, StringComparison.Ordinal)) return false;
            int dash = code.IndexOf('-');
            if (dash < 3) return false;
            if (!int.TryParse(code.Substring(2, dash - 2), out version) || version < 1 || version > 255) return false;
            for (int i = 2; i < dash; i++) if (code[i] < '0' || code[i] > '9') return false;
            bytes = FromBase64(code.Substring(dash + 1));
            if (bytes == null || bytes.Length < 5) return false;
            int n = bytes.Length;
            if (Checksum(TreePrefix + version, bytes, n - 3) != bytes[n - 3] * 65536L + bytes[n - 2] * 256L + bytes[n - 1]) return false;
            return true;
        }

        public static TreeCode ReadTree(string code)
        {
            if (!TreeBytes(code, out int version, out byte[] bytes)) return null;
            var info = new TreeCode { Version = version };
            if (version > TreeLayoutMax) { info.Newer = true; return info; }
            int last = bytes.Length - 4;   // index of the last data byte
            info.Line = bytes[0];
            int flags = bytes.Length > 1 ? bytes[1] : 0;
            int pos = 2;
            if (flags % 2 == 1)
            {
                int count = pos <= last ? bytes[pos] : 0;
                pos++;
                for (int i = 0; i < count; i++)
                {
                    int k = pos <= last ? bytes[pos] : 0;
                    if (k < 1 || k > ParagonKeys.Length || pos + 1 > last) return null;
                    info.Paragon[ParagonKeys[k - 1]] = bytes[pos + 1];
                    pos += 2;
                }
            }
            if (version >= 2 && (flags / 2) % 2 == 1)
            {
                int count = pos <= last ? bytes[pos] : 0;
                pos++;
                for (int i = 0; i < count; i++)
                {
                    if (pos + 2 > last) return null;
                    info.Masteries[bytes[pos] * 256 + bytes[pos + 1]] = bytes[pos + 2];
                    pos += 3;
                }
            }
            if (pos > last + 1) return null;
            for (int i = pos; i <= last; i++)
                for (int bit = 0; bit < 8; bit++)
                    if ((bytes[i] >> bit & 1) == 1) info.Nodes.Add((i - pos) * 8 + bit);
            return info;
        }

        // ------------------------------------------------------------------------------------ decode and encode
        /// <summary>The card of a code, or null with the error kind: empty, toolong, format, version, damaged, checksum, class,
        /// tree, spells, gear, level.</summary>
        public static BuildCard Decode(string code, out string error)
        {
            error = null;
            code = (code ?? "").Trim();
            if (code.Length == 0) { error = "empty"; return null; }
            if (code.Length > MaxCode) { error = "toolong"; return null; }
            if (!code.StartsWith(Prefix, StringComparison.Ordinal)) { error = "format"; return null; }
            int dash = code.IndexOf('-');
            if (dash < 3) { error = "format"; return null; }
            for (int i = 2; i < dash; i++) if (code[i] < '0' || code[i] > '9') { error = "format"; return null; }
            for (int i = dash + 1; i < code.Length; i++)
                if (Alphabet.IndexOf(code[i]) < 0) { error = "format"; return null; }
            if (!int.TryParse(code.Substring(2, dash - 2), out int ver) || ver != Version) { error = "version"; return null; }
            byte[] bytes = FromBase64(code.Substring(dash + 1));
            if (bytes == null || bytes.Length < 3) { error = "damaged"; return null; }
            int n = bytes.Length;
            if (Checksum(Prefix + Version, bytes, n - 3) != bytes[n - 3] * 65536L + bytes[n - 2] * 256L + bytes[n - 1]) { error = "checksum"; return null; }
            var card = new BuildCard();
            var seen = new HashSet<int>();
            int p = 0, last = n - 3;   // last: count of payload bytes
            while (p < last)
            {
                if (p + 2 >= last) { error = "damaged"; return null; }
                int tag = bytes[p], len = bytes[p + 1] * 256 + bytes[p + 2];
                int from = p + 3, to = p + 2 + len;   // data is bytes[from..to]
                if (to >= last || !seen.Add(tag)) { error = "damaged"; return null; }
                switch (tag)
                {
                    case 1:
                        if (len != 1 || bytes[from] < 1 || bytes[from] > Classes.Length) { error = "class"; return null; }
                        card.Class = Classes[bytes[from] - 1][0];
                        card.Vocation = int.Parse(Classes[bytes[from] - 1][1]);
                        break;
                    case 2:
                    {
                        int level = len == 2 ? bytes[from] * 256 + bytes[from + 1] : 0;
                        if (level < 1) { error = "level"; return null; }
                        card.Level = level;
                        break;
                    }
                    case 3:
                    {
                        if (len < 6) { error = "tree"; return null; }
                        var t = new List<byte>();
                        for (int i = from + 1; i <= to; i++) t.Add(bytes[i]);
                        card.Tree = TreePrefix + bytes[from] + "-" + ToBase64(t);
                        card.TreeInfo = ReadTree(card.Tree);
                        if (card.TreeInfo == null) { error = "tree"; return null; }
                        break;
                    }
                    case 4:
                        if (len % 2 != 0 || len > MaxSpells * 2) { error = "spells"; return null; }
                        for (int i = from; i <= to; i += 2) card.Spells.Add(bytes[i] * 256 + bytes[i + 1]);
                        break;
                    case 5:
                    {
                        if (len % 3 != 0) { error = "gear"; return null; }
                        int prev = 0;
                        for (int i = from; i <= to; i += 3)
                        {
                            int slot = bytes[i], id = bytes[i + 1] * 256 + bytes[i + 2];
                            if (Array.IndexOf(GearSlots, slot) < 0 || slot <= prev || id == 0) { error = "gear"; return null; }
                            prev = slot;
                            card.Gear.Add(new KeyValuePair<int, int>(slot, id));
                        }
                        break;
                    }
                    default: card.Skipped++; break;
                }
                p = to + 1;
            }
            return card;
        }

        static void Push16(List<byte> o, int v) { o.Add((byte)(v / 256 % 256)); o.Add((byte)(v % 256)); }

        /// <summary>The code of a card (parts left null or empty stay out), or null with the error kind.</summary>
        public static string Encode(BuildCard card, out string error)
        {
            error = null;
            if (card == null) { error = "format"; return null; }
            var sections = new List<KeyValuePair<byte, List<byte>>>();
            if (card.Class != null)
            {
                int index = ClassIndex(card.Class);
                if (index == 0) { error = "class"; return null; }
                sections.Add(new KeyValuePair<byte, List<byte>>(1, new List<byte> { (byte)index }));
            }
            if (card.Level.HasValue)
            {
                if (card.Level.Value < 1 || card.Level.Value > 65535) { error = "level"; return null; }
                var d = new List<byte>();
                Push16(d, card.Level.Value);
                sections.Add(new KeyValuePair<byte, List<byte>>(2, d));
            }
            if (card.Tree != null)
            {
                if (!TreeBytes(card.Tree, out int version, out byte[] tb)) { error = "tree"; return null; }
                var d = new List<byte> { (byte)version };
                d.AddRange(tb);
                sections.Add(new KeyValuePair<byte, List<byte>>(3, d));
            }
            if (card.Spells != null && card.Spells.Count > 0)
            {
                var d = new List<byte>();
                var seenSpell = new HashSet<int>();
                foreach (int id in card.Spells)
                    if (id > 0 && id < 65536 && seenSpell.Add(id) && d.Count < MaxSpells * 2) Push16(d, id);
                if (d.Count > 0) sections.Add(new KeyValuePair<byte, List<byte>>(4, d));
            }
            if (card.Gear != null && card.Gear.Count > 0)
            {
                var bySlot = new Dictionary<int, int>();
                foreach (var g in card.Gear) if (g.Key > 0 && g.Value > 0 && g.Value < 65536) bySlot[g.Key] = g.Value;
                var d = new List<byte>();
                foreach (int slot in GearSlots)
                    if (bySlot.TryGetValue(slot, out int id)) { d.Add((byte)slot); Push16(d, id); }
                if (d.Count > 0) sections.Add(new KeyValuePair<byte, List<byte>>(5, d));
            }
            var bytes = new List<byte>();
            foreach (var s in sections)
            {
                bytes.Add(s.Key);
                Push16(bytes, s.Value.Count);
                bytes.AddRange(s.Value);
            }
            string head = Prefix + Version;
            long h = Checksum(head, bytes, bytes.Count);
            bytes.Add((byte)(h / 65536 % 256));
            bytes.Add((byte)(h / 256 % 256));
            bytes.Add((byte)(h % 256));
            string code = head + "-" + ToBase64(bytes);
            if (code.Length > MaxCode) { error = "toolong"; return null; }
            return code;
        }
    }
}
