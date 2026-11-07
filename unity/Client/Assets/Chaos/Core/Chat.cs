// Chat model (no Unity types): the talk types of 10.98, the tabs (Default, Server Log, channels, private), unread counts, the
// history cap, line colours, an ignore list, the floating speech bubbles over creatures, the requests the chat sends and the
// fight modes. GameParser fills a ChatModel (Core/GameChat.cs); the Unity side only draws it.
//
// Wire (10.98, as the main client and the server's engine use it):
//   0xAA talk:   u32 statement, string name, u16 level, u8 type, then by type
//                position for say 1, whisper 2, yell 3, spell 9, NPC 10, monster say 36, monster yell 37;
//                u16 channel id for 6, 7, 8, 14; nothing for private 4, 15, broadcast 13; then string text.
//   0x96 say:    u8 type, then receiver (string) for 5 and 16, channel id (u16) for 7, 8, 14; then string text.
//   0xA0 fight:  u8 fight mode (1 offensive, 2 balanced, 3 defensive), u8 chase (0 stand, 1 chase),
//                u8 secure (0 on, 1 off), u8 pvp mode (0).
using System;
using System.Collections.Generic;
using System.Text;

namespace Chaos.Core
{
    /// <summary>The talk types of 0xAA and 0x96.</summary>
    public static class TalkType
    {
        public const byte Say = 1, Whisper = 2, Yell = 3, PrivateFrom = 4, PrivateTo = 5, ChannelManager = 6, ChannelYellow = 7,
                          ChannelOrange = 8, Spell = 9, NpcFrom = 10, NpcTo = 12, Broadcast = 13, ChannelRed = 14,
                          PrivateRedFrom = 15, PrivateRedTo = 16, MonsterSay = 36, MonsterYell = 37;

        /// <summary>Types whose 0xAA carries the speaker's position.</summary>
        public static bool HasPosition(byte t) => t == Say || t == Whisper || t == Yell || t == Spell || t == NpcFrom || t == MonsterSay || t == MonsterYell;
        /// <summary>Types whose 0xAA (and 0x96) carries a channel id.</summary>
        public static bool HasChannel(byte t) => t == ChannelManager || t == ChannelYellow || t == ChannelOrange || t == ChannelRed;
        /// <summary>Types the server sends with neither position nor channel.</summary>
        public static bool IsBare(byte t) => t == PrivateFrom || t == PrivateRedFrom || t == Broadcast || t == PrivateTo || t == PrivateRedTo || t == NpcTo;
        public static bool Known(byte t) => HasPosition(t) || HasChannel(t) || IsBare(t);
        /// <summary>A line a creature says on the map: it also floats over the creature.</summary>
        public static bool Floats(byte t) => t == Say || t == Whisper || t == Yell || t == Spell || t == MonsterSay || t == MonsterYell;
        public static bool IsPrivateIn(byte t) => t == PrivateFrom || t == PrivateRedFrom;

        /// <summary>Line colour 0xRRGGBB, the main client's speak-type colours.</summary>
        public static uint Color(byte t)
        {
            switch (t)
            {
                case Say: case Whisper: case ChannelYellow: return 0xFFFF00;
                case Yell: return 0xFF4040;
                case PrivateFrom: case PrivateTo: case NpcFrom: case NpcTo: return 0x5FF7F7;
                case ChannelOrange: case MonsterSay: case MonsterYell: case Spell: return 0xFE6500;
                case Broadcast: case ChannelRed: case PrivateRedFrom: case PrivateRedTo: return 0xF55E5E;
                case ChannelManager: return 0xFFFFFF;
                default: return 0xFFFFFF;   // 0: a server message
            }
        }
    }

    /// <summary>One line of a tab.</summary>
    public sealed class ChatLine
    {
        public double At;
        /// <summary>The wall-clock time shown in front of the line (ChatModel.Stamp).</summary>
        public string Stamp = "";
        public string Speaker = "";
        public int Level;
        public string Text = "";
        public byte Type;
        public uint Color;
        public bool Self;
        /// <summary>"Name [level]: text" for a speaker, the text alone for a server line.</summary>
        public string Display => Speaker.Length == 0 ? Text : Speaker + ": " + Text;
    }

    public enum TabKind { Default, ServerLog, Channel, Private, Npc }

    public sealed class ChatTab
    {
        public string Key = "", Name = "";
        public TabKind Kind;
        public int ChannelId = -1;
        public readonly List<ChatLine> Lines = new List<ChatLine>();
        public int Unread;
        public bool Closable => Kind != TabKind.Default && Kind != TabKind.ServerLog;
    }

    public sealed class ChatChannel { public int Id; public string Name = ""; }

    /// <summary>What a typed line turns into.</summary>
    public sealed class TalkPlan
    {
        public byte Type;
        public int Channel;
        public string Receiver = "";
        public string Text = "";
        /// <summary>False: nothing to send (empty line, or a client command already done).</summary>
        public bool Send;
    }

    /// <summary>A line floating over a creature.</summary>
    public sealed class Bubble
    {
        public uint CreatureId;
        public string Speaker = "", Text = "";
        public byte Type;
        public uint Color;
        public double Born, Life;
        public bool Alive(double now) => now - Born < Life;
    }

    /// <summary>The floating speech over creatures: lifetime by length, at most MaxPerCreature stacked (oldest first).</summary>
    public sealed class BubbleSet
    {
        public const double MsPerChar = 60, MinMs = 3000, MaxMs = 12000;
        public int MaxPerCreature = 3;
        readonly List<Bubble> all = new List<Bubble>();
        readonly List<Bubble> scratch = new List<Bubble>();

        public static double LifeFor(string text) => Math.Max(MinMs, Math.Min(MaxMs, MsPerChar * (text ?? "").Length));

        public void Add(uint creature, string speaker, string text, byte type, uint color, double now)
        {
            if (creature == 0 || string.IsNullOrEmpty(text)) return;
            all.Add(new Bubble { CreatureId = creature, Speaker = speaker, Text = text, Type = type, Color = color, Born = now, Life = LifeFor(text) });
            int n = 0;
            for (int i = all.Count - 1; i >= 0; i--)
                if (all[i].CreatureId == creature && ++n > MaxPerCreature) all.RemoveAt(i);
        }

        /// <summary>Drops the finished ones.</summary>
        public void Prune(double now) { all.RemoveAll(b => !b.Alive(now)); }

        /// <summary>The live bubbles of one creature, oldest first (draw top to bottom: the newest ends up nearest the creature).</summary>
        public List<Bubble> For(uint creature, double now)
        {
            scratch.Clear();
            foreach (var b in all) if (b.CreatureId == creature && b.Alive(now)) scratch.Add(b);
            return scratch;
        }

        /// <summary>Every live bubble (what the Unity side reads once per frame).</summary>
        public List<Bubble> Active(double now)
        {
            Prune(now);
            return all;
        }

        public void Clear() { all.Clear(); }
        public int Count => all.Count;
    }

    /// <summary>The chat: tabs, history, unread counts, ignore list, bubbles and the typed-line rules.</summary>
    public sealed class ChatModel
    {
        public const string DefaultKey = "default", LogKey = "log";
        public int HistoryCap = 500;
        public Func<double> Clock = () => 0;
        public Func<string> Stamp = () => DateTime.Now.ToString("HH:mm");
        public string SelfName = "";
        public readonly List<ChatTab> Tabs = new List<ChatTab>();
        /// <summary>The index of the tab shown.</summary>
        public int Active;
        /// <summary>The channels the server offered with 0xAB (the Ctrl+O list).</summary>
        public readonly List<ChatChannel> Channels = new List<ChatChannel>();
        public bool ChannelListArrived;
        public readonly HashSet<string> Ignored = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        public readonly BubbleSet Bubbles = new BubbleSet();
        /// <summary>Raised when a channel list or a new tab should draw attention (the Unity side opens the dialog on the list).</summary>
        public Action ChannelsListed = delegate { };

        public ChatModel()
        {
            Tabs.Add(new ChatTab { Key = DefaultKey, Name = "Default", Kind = TabKind.Default });
            Tabs.Add(new ChatTab { Key = LogKey, Name = "Server Log", Kind = TabKind.ServerLog });
        }

        public ChatTab Current => Tabs[Math.Max(0, Math.Min(Active, Tabs.Count - 1))];
        public ChatTab DefaultTab => Tabs[0];
        public ChatTab LogTab => Tabs[1];

        public ChatTab Find(string key) { foreach (var t in Tabs) if (t.Key == key) return t; return null; }
        public ChatTab FindChannel(int id) => Find("ch:" + id);
        public ChatTab FindPrivate(string name) => Find("pm:" + (name ?? "").ToLowerInvariant());

        public void Select(int index)
        {
            if (index < 0 || index >= Tabs.Count) return;
            Active = index;
            Tabs[index].Unread = 0;
        }

        /// <summary>Tab / Shift+Tab: the next (+1) or previous (-1) tab, wrapping.</summary>
        public void Step(int dir)
        {
            int n = Tabs.Count;
            Select(((Active + dir) % n + n) % n);
        }

        /// <summary>Shows a channel (made when new). focus: switch to it, as the main client does when the server opens one.</summary>
        public ChatTab OpenChannel(int id, string name, bool focus)
        {
            var t = FindChannel(id);
            if (t == null)
            {
                bool npc = string.Equals(name, "NPCs", StringComparison.OrdinalIgnoreCase);
                t = new ChatTab { Key = "ch:" + id, Name = string.IsNullOrEmpty(name) ? "Channel " + id : name, Kind = npc ? TabKind.Npc : TabKind.Channel, ChannelId = id };
                Tabs.Add(t);
            }
            else if (!string.IsNullOrEmpty(name)) t.Name = name;
            if (focus) Select(Tabs.IndexOf(t));
            return t;
        }

        public ChatTab OpenPrivate(string name, bool focus)
        {
            if (string.IsNullOrEmpty(name)) return null;
            var t = FindPrivate(name);
            if (t == null)
            {
                t = new ChatTab { Key = "pm:" + name.ToLowerInvariant(), Name = name, Kind = TabKind.Private };
                Tabs.Add(t);
            }
            if (focus) Select(Tabs.IndexOf(t));
            return t;
        }

        /// <summary>Removes a tab (Default and Server Log stay). The caller sends the leave request for a channel (see Leaves).</summary>
        public ChatTab Close(int index)
        {
            if (index < 0 || index >= Tabs.Count || !Tabs[index].Closable) return null;
            var t = Tabs[index];
            Tabs.RemoveAt(index);
            if (Active > index || Active >= Tabs.Count) Active--;
            Active = Math.Max(0, Math.Min(Active, Tabs.Count - 1));
            Tabs[Active].Unread = 0;
            return t;
        }

        /// <summary>The server closed a channel (0xB3).</summary>
        public void ServerClosed(int id)
        {
            var t = FindChannel(id);
            if (t != null) Close(Tabs.IndexOf(t));
        }

        public static uint ColorOf(byte type) => TalkType.Color(type);

        public ChatLine AddLine(ChatTab tab, string speaker, int level, string text, byte type, uint color, bool self = false)
        {
            var l = new ChatLine { At = Clock(), Stamp = Stamp(), Speaker = speaker ?? "", Level = level, Text = text ?? "", Type = type, Color = color, Self = self };
            tab.Lines.Add(l);
            if (tab.Lines.Count > HistoryCap) tab.Lines.RemoveRange(0, tab.Lines.Count - HistoryCap);
            if (Current != tab) tab.Unread++;
            return l;
        }

        public bool IsIgnored(string name) => !string.IsNullOrEmpty(name) && Ignored.Contains(name);

        /// <summary>A 0xAA line. Public speech goes to Default, private messages to a tab of the sender, channel lines to the
        /// channel's tab, a broadcast to Default. Ignored players (not monsters or NPCs) are dropped. Returns the line, or null.</summary>
        public ChatLine OnTalk(string speaker, int level, byte type, int channel, string text)
        {
            bool fromPlayer = type != TalkType.MonsterSay && type != TalkType.MonsterYell && type != TalkType.NpcFrom && type != TalkType.Broadcast;
            if (fromPlayer && IsIgnored(speaker)) return null;
            uint col = TalkType.Color(type);
            bool self = speaker.Length > 0 && string.Equals(speaker, SelfName, StringComparison.OrdinalIgnoreCase);
            ChatTab tab;
            if (TalkType.IsPrivateIn(type)) tab = OpenPrivate(speaker, false);
            else if (TalkType.HasChannel(type)) tab = FindChannel(channel) ?? OpenChannel(channel, null, false);
            else tab = DefaultTab;
            return AddLine(tab, speaker, level, text, type, col, self);
        }

        /// <summary>A server text message (0xB4 of a console kind). Guild and party kinds go to their channel tab when it is open.</summary>
        public ChatLine OnText(byte kind, int channel, string text)
        {
            ChatTab tab = LogTab;
            if (channel >= 0 && (kind == 33 || kind == 34 || kind == 35)) tab = FindChannel(channel) ?? LogTab;
            else if (kind == 4 || kind == 13) tab = DefaultTab;   // the console blue and red messages
            return AddLine(tab, "", 0, text, 0, TextColor(kind));
        }

        /// <summary>Console colours of the text message kinds (10.98): blue 4, red 13 and 18, orange 19 and 20, green 22 and 31, the rest white.</summary>
        public static uint TextColor(byte kind)
        {
            switch (kind)
            {
                case 4: return 0x5FF7F7;
                case 13: case 18: return 0xF55E5E;
                case 19: case 20: case 30: return 0xFE6500;
                case 22: case 31: return 0x00EB00;
                case 32: return 0x5FF7F7;
                case 33: return 0x00EB00;
                case 34: case 35: return 0x5FF7F7;
                default: return 0xFFFFFF;
            }
        }

        /// <summary>A client-side notice (Server Log).</summary>
        public ChatLine AddLocal(string text) => AddLine(LogTab, "", 0, text, 0, 0xFFFFFF);

        // ---- typed lines ----

        /// <summary>What a typed line sends. "*name* text" is a private message to name, "#y text" yells, "#w text" whispers, "/ignore name"
        /// and "/unignore name" edit the ignore list (nothing is sent); else the line goes to the tab shown: say on Default and Server Log,
        /// the channel on a channel tab, the receiver on a private tab, the NPC channel on the NPCs tab.</summary>
        public TalkPlan Plan(string input)
        {
            var p = new TalkPlan();
            string s = (input ?? "").Trim();
            if (s.Length == 0) return p;
            if (s.Length > 255) s = s.Substring(0, 255);
            if (s.Length > 8 && s.StartsWith("/ignore ", StringComparison.OrdinalIgnoreCase)) { Ignored.Add(s.Substring(8).Trim()); return p; }
            if (s.Length > 10 && s.StartsWith("/unignore ", StringComparison.OrdinalIgnoreCase)) { Ignored.Remove(s.Substring(10).Trim()); return p; }
            if (s[0] == '*')
            {
                int end = s.IndexOf('*', 1);
                if (end > 1)
                {
                    string text = s.Substring(end + 1).Trim();
                    if (text.Length > 0) return Private(s.Substring(1, end - 1).Trim(), text);
                }
            }
            if (s.Length > 3 && s[0] == '#' && s[2] == ' ' && (s[1] == 'y' || s[1] == 'Y' || s[1] == 'w' || s[1] == 'W'))
            {
                p.Send = true;
                p.Type = char.ToLowerInvariant(s[1]) == 'y' ? TalkType.Yell : TalkType.Whisper;
                p.Text = s.Substring(3).Trim();
                p.Send = p.Text.Length > 0;
                return p;
            }
            var tab = Current;
            p.Send = true;
            p.Text = s;
            switch (tab.Kind)
            {
                case TabKind.Channel: p.Type = TalkType.ChannelYellow; p.Channel = tab.ChannelId; break;
                case TabKind.Private: p.Type = TalkType.PrivateTo; p.Receiver = tab.Name; break;
                case TabKind.Npc: p.Type = TalkType.NpcTo; p.Channel = tab.ChannelId; break;
                default: p.Type = TalkType.Say; break;
            }
            return p;
        }

        TalkPlan Private(string to, string text)
        {
            return new TalkPlan { Send = to.Length > 0, Type = TalkType.PrivateTo, Receiver = to, Text = text };
        }

        /// <summary>After a private message went out: open the receiver's tab (the server does not echo it) and show the line.</summary>
        public void EchoPrivate(string to, string text)
        {
            var tab = OpenPrivate(to, true);
            if (tab != null) AddLine(tab, SelfName, 0, text, TalkType.PrivateTo, TalkType.Color(TalkType.PrivateTo), true);
        }

        public void Reset()
        {
            Tabs.RemoveRange(2, Tabs.Count - 2);
            DefaultTab.Lines.Clear(); LogTab.Lines.Clear();
            DefaultTab.Unread = LogTab.Unread = 0;
            Active = 0;
            Channels.Clear();
            Bubbles.Clear();
        }
    }

    /// <summary>The requests the chat sends, as packet bodies.</summary>
    public static class ChatPackets
    {
        /// <summary>0x96: type, then the receiver (private) or channel id, then the text.</summary>
        public static byte[] Talk(byte type, int channel, string receiver, string text)
        {
            var w = new ByteWriter().U8(0x96).U8(type);
            if (type == TalkType.PrivateTo || type == TalkType.PrivateRedTo) w.Str(receiver ?? "");
            else if (TalkType.HasChannel(type)) w.U16((ushort)channel);
            return w.Str(text ?? "").ToArray();
        }
        public static byte[] Talk(TalkPlan p) => Talk(p.Type, p.Channel, p.Receiver, p.Text);
        public static byte[] RequestChannels() => new byte[] { 0x97 };
        public static byte[] JoinChannel(int id) => new ByteWriter().U8(0x98).U16((ushort)id).ToArray();
        public static byte[] LeaveChannel(int id) => new ByteWriter().U8(0x99).U16((ushort)id).ToArray();
        public static byte[] OpenPrivate(string name) => new ByteWriter().U8(0x9A).Str(name ?? "").ToArray();
        public static byte[] CloseNpcChannel() => new byte[] { 0x9E };
    }

    /// <summary>Fight, chase and secure modes (0xA0). Saved as "fight,chase,secure" ("2,0,1").</summary>
    public sealed class FightModes
    {
        public const byte Offensive = 1, Balanced = 2, Defensive = 3;
        public byte Fight = Balanced;
        public bool Chase;
        public bool Secure = true;

        public byte[] Packet() => new byte[] { 0xA0, Fight, (byte)(Chase ? 1 : 0), (byte)(Secure ? 0 : 1), 0 };
        public string Encode() => Fight + "," + (Chase ? 1 : 0) + "," + (Secure ? 1 : 0);

        public static FightModes Decode(string s)
        {
            var m = new FightModes();
            var parts = (s ?? "").Split(',');
            if (parts.Length != 3) return m;
            if (byte.TryParse(parts[0], out byte f) && f >= Offensive && f <= Defensive) m.Fight = f;
            m.Chase = parts[1] == "1";
            m.Secure = parts[2] != "0";
            return m;
        }
    }
}
