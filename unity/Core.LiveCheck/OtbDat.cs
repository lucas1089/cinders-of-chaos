// A DatFile for the parser built from the server's items.otb, for a run without the real Tibia.dat (the pair is not in git).
// The parser reads only four things of an item type: whether a count / fluid byte follows the mark, whether a phase byte follows, and for the
// stack order the ground flag. The server writes the same bytes from the items.otb node (server/tools/check_item_wire.py: a count byte for a
// stackable node, a fluid byte for a splash or fluid container, a phase byte with FLAG_ANIMATION), and install_all keeps the dat and the otb in
// step (item_wire.csv). So the type of a client id here is: Stackable, Splash, Fluid from the node, Phases 2 with FLAG_ANIMATION, Ground for group 1, GroundBorder / OnBottom / OnTop from FLAG_ALWAYSONTOP and attribute 0x2B (top order).
using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;

namespace Chaos.Core.LiveCheck
{
    public static class OtbDat
    {
        const uint FlagBlockSolid = 1u << 0, FlagBlockProjectile = 1u << 1, FlagBlockPathfind = 1u << 2, FlagStackable = 1u << 7, FlagAlwaysOnTop = 1u << 13, FlagAnimation = 1u << 24;
        const int GroupGround = 1, GroupSplash = 11, GroupFluid = 12;

        public sealed class Node { public int Server, Client, Group, TopOrder, Speed; public uint Flags; }

        /// <summary>The item nodes of an items.otb (those with a server id and a client id).</summary>
        public static List<Node> ReadNodes(byte[] data)
        {
            var nodes = new List<Node>();
            int i = 4;   // the version word
            var payload = new List<byte>();
            int depth = 0, type = -1;
            bool inNode = false, root = true;
            void Flush()
            {
                if (!inNode) return;
                inNode = false;
                if (root) { root = false; return; }
                var pl = payload.ToArray();
                if (pl.Length < 4) return;
                uint flags = BitConverter.ToUInt32(pl, 0);
                int k = 4, sid = 0, cid = 0, top = 0, speed = 0;
                while (k + 3 <= pl.Length)
                {
                    byte at = pl[k];
                    int ln = pl[k + 1] | pl[k + 2] << 8;
                    k += 3;
                    if (k + ln > pl.Length) break;
                    if (at == 0x10 && ln == 2) sid = pl[k] | pl[k + 1] << 8;
                    else if (at == 0x11 && ln == 2) cid = pl[k] | pl[k + 1] << 8;
                    else if (at == 0x2B && ln == 1) top = pl[k];
                    else if (at == 0x14 && ln == 2) speed = pl[k] | pl[k + 1] << 8;
                    k += ln;
                }
                if (sid != 0 && cid != 0) nodes.Add(new Node { Server = sid, Client = cid, Group = type, Flags = flags, TopOrder = top, Speed = speed });
            }
            while (i < data.Length)
            {
                byte b = data[i++];
                if (b == 0xFD && i < data.Length) { if (inNode) payload.Add(data[i]); i++; continue; }
                if (b == 0xFE)
                {
                    Flush();
                    depth++;
                    type = i < data.Length ? data[i] : -1;
                    i++;
                    payload.Clear();
                    inNode = true;
                    continue;
                }
                if (b == 0xFF) { Flush(); depth--; continue; }
                if (inNode) payload.Add(b);
            }
            if (depth < 0) throw new InvalidDataException("items.otb: unbalanced nodes");
            return nodes;
        }

        /// <summary>The floor changes of items.xml by client id (the otb node of the server id gives the client id): "down", "north", ... (the first value of an item's
        /// floorchange attribute, lower case; the floor change bits of the otb flags count too). Stairs, ramps, holes and trapdoors have one; ladders and ropes that need a use have none.</summary>
        public static Dictionary<int, string> FloorChanges(string itemsXml, byte[] otb)
        {
            var byServer = new Dictionary<int, int>();
            var result = new Dictionary<int, string>();
            string[] otbKinds = { "down", "north", "east", "south", "west" };   // item flag bits 8 to 12 of items.otb
            foreach (var n in ReadNodes(otb))
            {
                byServer[n.Server] = n.Client;
                for (int bit = 0; bit < otbKinds.Length; bit++)
                    if ((n.Flags & (1u << (8 + bit))) != 0 && !result.ContainsKey(n.Client)) result[n.Client] = otbKinds[bit];
            }
            foreach (Match m in Regex.Matches(itemsXml, @"<item\b([^>]*?)(/?)>"))
            {
                if (m.Groups[2].Value.Length > 0) continue;
                int bodyStart = m.Index + m.Length;
                int end = itemsXml.IndexOf("</item>", bodyStart, StringComparison.Ordinal);
                string body = itemsXml.Substring(bodyStart, (end >= 0 ? end : bodyStart) - bodyStart);
                var fc = Regex.Match(body, "key=\"floorchange\"\\s+value=\"(\\w+)\"");
                if (!fc.Success) continue;
                string val = fc.Groups[1].Value.ToLowerInvariant();
                int from = -1, to = -1;
                foreach (Match a in Regex.Matches(m.Groups[1].Value, "(\\w+)=\"([^\"]*)\""))
                {
                    int.TryParse(a.Groups[2].Value, out int v);
                    switch (a.Groups[1].Value)
                    {
                        case "id": from = to = v; break;
                        case "fromid": from = v; break;
                        case "toid": to = v; break;
                    }
                }
                if (from < 0 || to < from || to - from > 5000) continue;
                for (int id = from; id <= to; id++)
                    if (byServer.TryGetValue(id, out int cid) && !result.ContainsKey(cid)) result[cid] = val;
            }
            return result;
        }

        public static DatFile Build(byte[] otb)
        {
            var nodes = ReadNodes(otb);
            int max = 100;
            foreach (var n in nodes) max = Math.Max(max, n.Client);
            var items = new ThingType[max + 1];
            foreach (var n in nodes)
            {
                var t = items[n.Client];
                if (t == null)
                {
                    t = items[n.Client] = new ThingType
                    {
                        Category = ThingCategory.Item, Id = n.Client,
                        Groups = new[] { new FrameGroup { Width = 1, Height = 1, Layers = 1, PatternX = 1, PatternY = 1, PatternZ = 1, Phases = 1, Sprites = new uint[1] } },
                    };
                }
                if ((n.Flags & FlagStackable) != 0) t.Stackable = true;
                // what walking needs (the live scenarios path over the tiles they see): the server's block flags, and the ground's speed for the step time
                if ((n.Flags & FlagBlockSolid) != 0) t.NotWalkable = true;
                if ((n.Flags & FlagBlockPathfind) != 0) t.BlockPath = true;
                if ((n.Flags & FlagBlockProjectile) != 0) t.BlockMissile = true;
                if (n.Group == GroupGround && n.Speed > 0) t.GroundSpeed = n.Speed;
                if (n.Group == GroupSplash) t.Splash = true;
                if (n.Group == GroupFluid) t.Fluid = true;
                if (n.Group == GroupGround) t.Ground = true;
                else if ((n.Flags & FlagAlwaysOnTop) != 0)
                {
                    // the server keeps these in top order after the ground (1 borders, 2 bottom, 3 and up top), the client's four classes
                    if (n.TopOrder == 1) t.GroundBorder = true; else if (n.TopOrder == 2) t.OnBottom = true; else t.OnTop = true;
                }
                if ((n.Flags & FlagAnimation) != 0) t.Groups[0].Phases = 2;
            }
            var empty = new ThingType[1];
            return new DatFile { Signature = 0, Items = items, Outfits = empty, Effects = empty, Missiles = empty };
        }
    }
}
