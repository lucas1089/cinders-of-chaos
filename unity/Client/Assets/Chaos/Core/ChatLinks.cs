// Item links in chat (client game_chatlinks, extended opcode 249, server itemlink.lua + itemlink_core.lua).
// A link in a message is   [Item Name]{<r><id>}   (r = rarity as a hex digit or u for a unique, id = 9 characters a-z 0-9), made by the server. Other clients show
// the text as it is; this one shows "[Item Name]" in the rarity colour and the tooltip of the snapshot on hover.
//   client -> server  register {n, items [{pos {x, y, z}, iid}], ctx {kind, id}} | get {id}
//   server -> client  registered {n, links [{token, name, rarity}]} | refused {n, reason} | link {id, tip, owner, left} | link {id, gone} | caps {help}
// Shift + left click on an item of the equipment or a bag puts "[Item Name]" in the chat line (up to 3 per message); the name is written out as its link
// when the message is sent. The chat window (ChaosApp.Chat.cs) shows the names in colour and asks the tooltip of the link under the pointer.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    public sealed class ChatLink
    {
        public string Name = "", Id = "";
        public int Rarity, First, Last;   // byte positions of "[Name]{...}": First inclusive, Last inclusive
        public bool Unique;
    }

    /// <summary>The text of a chat line split for a coloured label: the shown text, its parts (text, colour) and the link ranges in the shown text.</summary>
    public sealed class LinkPieces
    {
        public string Text = "";
        public readonly List<KeyValuePair<string, string>> Parts = new List<KeyValuePair<string, string>>();
        public readonly List<LinkRange> Ranges = new List<LinkRange>();
    }

    public sealed class LinkRange { public int First, Last; public string Id = "", Name = ""; public int Rarity; public bool Unique; }   // First inclusive, Last exclusive

    public sealed class LinkChip { public string Name = "", Token = ""; }

    public static class ChatLinksMath
    {
        public const int MaxLinks = 3, MaxText = 250;
        public const double Ttl = 600, AskInterval = 2, GoneTtl = 60;
        public const int MaxStore = 120;
        public const string NormalColor = "#e4d8c0";

        /// <summary>The rarity colours of the item tooltip, by rarity id (1 Common .. 5 Legendary, 10 Divine; the old ids are the rarity they became).</summary>
        public static string ColorOf(int rarity, bool unique)
        {
            if (unique) return ItemRarity.UniqueColor;
            string c = ItemRarity.Color(ItemRarity.Canon(rarity));
            return string.IsNullOrEmpty(c) ? NormalColor : c;
        }

        public static bool ValidId(string id)
        {
            if (id == null || id.Length != 9) return false;
            foreach (char c in id) if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))) return false;
            return true;
        }

        static bool IsHex(char c) => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');

        /// <summary>The links of a text, in order (links past MaxLinks stay plain text). The name has no [ ] { } or control characters.</summary>
        public static List<ChatLink> Parse(string text)
        {
            var o = new List<ChatLink>();
            if (string.IsNullOrEmpty(text)) return o;
            int pos = 0;
            while (o.Count < MaxLinks)
            {
                int s = text.IndexOf('[', pos);
                if (s < 0) break;
                int i = s + 1;
                while (i < text.Length)
                {
                    char c = text[i];
                    if (c == ']' || c == '[' || c == '{' || c == '}' || char.IsControl(c)) break;
                    i++;
                }
                if (i >= text.Length || text[i] != ']' || i == s + 1) { pos = s + 1; continue; }
                // "]{<r><9 characters>}": 12 characters from e
                int e = i + 1;
                if (e + 11 < text.Length && text[e] == '{' && IsRarityChar(text[e + 1]) && text[e + 11] == '}')
                {
                    string id = text.Substring(e + 2, 9);
                    if (ValidId(id))
                    {
                        char r = text[e + 1];
                        o.Add(new ChatLink { Name = text.Substring(s + 1, i - s - 1), Id = id, Rarity = r == 'u' ? 0 : Convert.ToInt32(r.ToString(), 16), Unique = r == 'u', First = s, Last = e + 11 });
                        pos = e + 12;
                        continue;
                    }
                }
                pos = s + 1;
            }
            return o;
        }

        static bool IsRarityChar(char c) => IsHex(c) || c == 'u';

        /// <summary>The text as it is shown or copied: "[Item Name]" without the marker.</summary>
        public static string Plain(string text)
        {
            if (string.IsNullOrEmpty(text) || text.IndexOf('{') < 0) return text;
            var links = Parse(text);
            if (links.Count == 0) return text;
            var sb = new StringBuilder();
            int cursor = 0;
            foreach (var k in links)
            {
                sb.Append(text, cursor, k.First - cursor);
                sb.Append('[').Append(k.Name).Append(']');
                cursor = k.Last + 1;
            }
            sb.Append(text, cursor, text.Length - cursor);
            return sb.ToString();
        }

        public static LinkPieces Pieces(string text, string baseColor)
        {
            var p = new LinkPieces();
            var shown = new StringBuilder();
            int cursor = 0;
            Action<string, string> add = (s, color) => { if (s.Length > 0) { p.Parts.Add(new KeyValuePair<string, string>(s, color)); shown.Append(s); } };
            foreach (var k in Parse(text))
            {
                add(text.Substring(cursor, k.First - cursor), baseColor);
                string label = "[" + k.Name + "]";
                p.Ranges.Add(new LinkRange { First = shown.Length, Last = shown.Length + label.Length, Id = k.Id, Name = k.Name, Rarity = k.Rarity, Unique = k.Unique });
                add(label, ColorOf(k.Rarity, k.Unique));
                cursor = k.Last + 1;
            }
            add((text ?? "").Substring(cursor), baseColor);
            p.Text = shown.ToString();
            return p;
        }

        /// <summary>The range under a character index of the shown text.</summary>
        public static LinkRange RangeAt(List<LinkRange> ranges, int index)
        {
            foreach (var r in ranges) if (index >= r.First && index < r.Last) return r;
            return null;
        }

        // ------------------------------------------------------------------------------------ chips in the chat line
        /// <summary>Chips that are still in the text (the player may have deleted one), in order.</summary>
        public static List<LinkChip> LiveChips(string text, List<LinkChip> chips)
        {
            var o = new List<LinkChip>();
            int from = 0;
            foreach (var c in chips)
            {
                int s = (text ?? "").IndexOf("[" + c.Name + "]", from, StringComparison.Ordinal);
                if (s >= 0) { o.Add(c); from = s + c.Name.Length + 2; }
            }
            return o;
        }

        /// <summary>The text with each chip replaced by its token, in order.</summary>
        public static string Expand(string text, List<LinkChip> chips, out int used)
        {
            text = text ?? "";
            used = 0;
            var sb = new StringBuilder();
            int from = 0;
            foreach (var c in chips)
            {
                int s = text.IndexOf("[" + c.Name + "]", from, StringComparison.Ordinal);
                if (s < 0) continue;
                sb.Append(text, from, s - from).Append(c.Token);
                from = s + c.Name.Length + 2;
                used++;
            }
            sb.Append(text, from, text.Length - from);
            return sb.ToString();
        }

        /// <summary>May one more chip go in? False and the reason when not. extraName/extraToken describe the chip to add.</summary>
        public static bool CanAdd(string text, List<LinkChip> chips, string extraName, string extraToken, out string why)
        {
            why = "";
            var live = LiveChips(text, chips);
            if (live.Count >= MaxLinks) { why = Loc.T("You can link up to {0} items in one message.", MaxLinks); return false; }
            int len = Expand(text, live, out _).Length + extraToken.Length - (extraName.Length + 2);
            if (len + 1 > MaxText) { why = Loc.T("The message is too long for another item link."); return false; }
            return true;
        }

        /// <summary>Where a link may be sent: the context for the server, or null and why.</summary>
        public static Dictionary<string, object> ContextOf(TabKind kind, int channelId, bool helpAllowed, out string why)
        {
            why = "";
            if (kind == TabKind.Npc) { why = Loc.T("Items cannot be linked in NPC conversations."); return null; }
            if (kind == TabKind.Private) return SFmt.Map("kind", "private");
            if (kind == TabKind.Default || kind == TabKind.ServerLog) return SFmt.Map("kind", "say");
            if (channelId == 7 && !helpAllowed) { why = Loc.T("Item links are not allowed in the Help channel."); return null; }
            return SFmt.Map("kind", "channel", "id", channelId);
        }

        /// <summary>A message that goes to a tab where links are not allowed loses the markers (the names stay).</summary>
        public static string Scrub(string text, bool allowed) => allowed ? text : Plain(text);

        /// <summary>An item on the equipment or in a bag (x 0xFFFF) can be linked.</summary>
        public static bool Linkable(Pos p) => p.X == 0xFFFF;

        public static string IidText(ulong iid) => iid.ToString(CultureInfo.InvariantCulture);

        public static string Footer(string owner, double left, double age)
        {
            double rest = Math.Max(0, left - age);
            return Loc.T("Linked by {0} - {1} min left", string.IsNullOrEmpty(owner) ? "?" : owner, Math.Max(0, (int)Math.Ceiling(rest / 60)));
        }
    }

    /// <summary>The snapshots received, the chips of the line being written and the requests in flight (opcode 249).</summary>
    public sealed class ChatLinksState
    {
        public const byte Opcode = 249;
        readonly ExtOpcodes ext;
        public sealed class Entry { public object Tip; public string Owner = ""; public double Left, At; public bool Gone; }
        readonly Dictionary<string, Entry> entries = new Dictionary<string, Entry>();
        readonly List<string> order = new List<string>();
        readonly Dictionary<string, double> asked = new Dictionary<string, double>();
        readonly Dictionary<int, double> requests = new Dictionary<int, double>();
        int nonce;
        public readonly List<LinkChip> Chips = new List<LinkChip>();
        public bool HelpAllowed;
        public Func<double> Clock = () => 0;
        /// <summary>A chip came back from the server: the app puts "[name] " at the end of the chat line.</summary>
        public Action<string, string> InsertChip = delegate { };
        /// <summary>A refusal or a note for the player (a line in the chat box).</summary>
        public Action<string> Say = delegate { };
        public int Registered, Refused;

        public ChatLinksState(ExtOpcodes e) { ext = e; e.On(Opcode, OnMessage); }

        double NowSec => Clock() / 1000.0;

        /// <summary>Asks the server to make a link of an item: pos and iid as the item's own, ctx from ContextOf.</summary>
        public bool Register(Pos pos, ulong iid, Dictionary<string, object> ctx)
        {
            nonce++;
            requests[nonce] = NowSec;
            var item = SFmt.Map("pos", SFmt.Map("x", (int)pos.X, "y", (int)pos.Y, "z", (int)pos.Z), "iid", ChatLinksMath.IidText(iid));
            return ext.Send(Opcode, "register", SFmt.Map("n", nonce, "items", new List<object> { item }, "ctx", ctx));
        }

        void OnMessage(ExtMessage m)
        {
            object d = m.Data;
            if (!SFmt.IsMap(d)) return;
            switch (m.Action)
            {
                case "registered":
                    requests.Remove(Json.Int(d, "n"));
                    foreach (var k in SFmt.Rows(d, "links"))
                        if (Json.Text(k, "token").Length > 0 && Json.Text(k, "name").Length > 0) { Registered++; InsertChip(Json.Text(k, "name"), Json.Text(k, "token")); }
                    break;
                case "refused":
                    requests.Remove(Json.Int(d, "n"));
                    Refused++;
                    Say(Json.Text(d, "reason", Loc.T("That item cannot be linked.")));
                    break;
                case "link":
                    string id = Json.Text(d, "id");
                    if (!ChatLinksMath.ValidId(id)) return;
                    if (Json.Truthy(d, "gone") || !SFmt.IsMap(Json.Get(d, "tip"))) Put(id, new Entry { Gone = true });
                    else Put(id, new Entry { Tip = Json.Get(d, "tip"), Owner = Json.Text(d, "owner"), Left = SFmt.Has(d, "left") ? Json.Number(d, "left") : ChatLinksMath.Ttl });
                    break;
                case "caps": HelpAllowed = Json.Truthy(d, "help"); break;
            }
        }

        void Put(string id, Entry e)
        {
            e.At = NowSec;
            if (!entries.ContainsKey(id)) order.Add(id);
            entries[id] = e;
            while (order.Count > ChatLinksMath.MaxStore) { entries.Remove(order[0]); order.RemoveAt(0); }
        }

        /// <summary>The entry when it is still good: a snapshot for the time it lives, an expired answer for a minute.</summary>
        public Entry Get(string id)
        {
            if (!entries.TryGetValue(id, out var e)) return null;
            double life = e.Gone ? ChatLinksMath.GoneTtl : ChatLinksMath.Ttl;
            if (NowSec - e.At >= life) { entries.Remove(id); order.Remove(id); return null; }
            return e;
        }

        /// <summary>The snapshot of a link under the pointer: the entry, and a request when there is none (at most one per AskInterval and id).</summary>
        public Entry Lookup(string id)
        {
            var e = Get(id);
            if (e != null) return e;
            if (!ChatLinksMath.ValidId(id)) return null;
            double now = NowSec;
            if (asked.TryGetValue(id, out double last) && now - last < ChatLinksMath.AskInterval) return null;
            asked[id] = now;
            ext.Send(Opcode, "get", SFmt.Map("id", id));
            return null;
        }

        public double Age(Entry e) => NowSec - e.At;

        /// <summary>Puts the chip in the line being written. False and a line to say when it does not fit.</summary>
        public bool AddChip(string line, string name, string token, out string why)
        {
            var live = ChatLinksMath.LiveChips(line, Chips);
            Chips.Clear(); Chips.AddRange(live);
            if (!ChatLinksMath.CanAdd(line, Chips, name, token, out why)) return false;
            Chips.Add(new LinkChip { Name = name, Token = token });
            return true;
        }

        /// <summary>The line with its chips written out as links (the chips are used up).</summary>
        public string ExpandLine(string line)
        {
            var live = ChatLinksMath.LiveChips(line, Chips);
            string o = ChatLinksMath.Expand(line, live, out _);
            Chips.Clear();
            return o;
        }

        public void Clear() { entries.Clear(); order.Clear(); asked.Clear(); requests.Clear(); Chips.Clear(); HelpAllowed = false; }
    }
}
