// The chat, death and fight-mode parts of GameParser and GameSession (see Chat.cs for the model and the wire layouts).
using System;

namespace Chaos.Core
{
    public sealed partial class GameParser
    {
        /// <summary>Tabs, history, bubbles. Filled by 0xAA, 0xAB to 0xB3 and the console kinds of 0xB4.</summary>
        public readonly ChatModel Talks = new ChatModel();
        /// <summary>0x28: the character died. Dead stays true for the session; the Unity side shows the death window.</summary>
        public bool Dead;
        /// <summary>0 regular death, 1 unfair fight (only the regular one carries a penalty).</summary>
        public int DeathType, DeathPenalty = 100;
        public Action Died = delegate { };
        /// <summary>A channel was opened by the server (id, name): the Unity side may focus it.</summary>
        public Action<int, string> ChannelOpenedByServer = delegate { };

        void Death(ByteReader r)
        {
            // 10.98 with the death type and penalty features (the main client enables both): u8 type, u8 penalty when regular
            DeathType = r.U8();
            DeathPenalty = DeathType == 0 ? r.U8() : 0;
            Dead = true;
            Died();
        }

        void Talk(ByteReader r)
        {
            r.U32();
            string name = r.Str();
            int level = r.U16();
            byte type = r.U8();
            Pos at = default;
            int channel = -1;
            // an NPC line carries a position on the stock server; read it only when the bytes left say so (NpcTalkState.HasPosition)
            if (NpcTalkState.IsNpcTalkType(type)) { if (NpcTalkState.HasPosition(r)) at = ReadPos(r); }
            else if (TalkType.HasPosition(type)) at = ReadPos(r);
            else if (TalkType.HasChannel(type)) channel = r.U16();
            else if (!TalkType.IsBare(type)) throw new ProtocolException("unknown talk type " + type);
            string text = r.Str();
            Talks.Clock = Clock;
            if (W.Player != null) Talks.SelfName = W.Player.Name;
            var line = Talks.OnTalk(name, level, type, channel, text);
            if (line != null && TalkType.Floats(type) && TalkType.HasPosition(type))
                Talks.Bubbles.Add(SpeakerAt(name, at), name, text, type, line.Color, Clock());
            // NPC dialogue (NpcTalkWindow): private NPC lines, and plain says of an NPC while a conversation runs
            if (NpcTalkState.IsNpcTalkType(type)) NpcTalk.FromNpc(name, text, Clock());
            else if (type == 1 && NpcTalk.Focused(Clock()) && IsNpc(name)) NpcTalk.FromNpc(name, text, Clock());
            Chat(name, text, type);
        }

        bool IsNpc(string name)
        {
            foreach (var c in W.Creatures.Values) if (c.Type == 2 && c.Name == name) return true;
            return false;
        }

        /// <summary>The creature of that name nearest to the position the line came from (same floor, within 2 tiles), 0 when none.</summary>
        uint SpeakerAt(string name, Pos at)
        {
            uint best = 0;
            int bestD = int.MaxValue;
            foreach (var c in W.Creatures.Values)
            {
                if (c.Name != name || c.Position.Z != at.Z) continue;
                int d = Math.Max(Math.Abs(c.Position.X - at.X), Math.Abs(c.Position.Y - at.Y));
                if (d < bestD) { bestD = d; best = c.Id; }
            }
            return bestD <= 2 ? best : 0;
        }

        void TextMessage(ByteReader r)
        {
            byte kind = r.U8();
            Pos at = default; uint v1 = 0, v2 = 0; byte c1 = 0, c2 = 0;
            int channel = -1;
            int percent = 0, impact = 0; uint owner = 0;
            bool typed = false;
            if (kind >= 23 && kind <= 29)
            {
                at = ReadPos(r);
                v1 = r.U32(); c1 = r.U8();
                if (kind == 23 || kind == 24 || kind == 27) { v2 = r.U32(); c2 = r.U8(); }
                // typed impact numbers (src-patch 0051, feature 155, capability bit 7): u16 percent x100, u8 type, u32 creature id
                if (Features.Has(ClientFeatures.ImpactText)) { percent = r.U16(); impact = r.U8(); owner = r.U32(); typed = true; }
            }
            else if (kind >= 33 && kind <= 35) channel = r.U16();
            string text = r.Str();
            if (kind < 23 || kind > 29)
            {
                Talks.Clock = Clock;
                text = ShortNumbers.InMessage(kind, text);   // client_chaos_numbers: 15300 is 15.3k in status and look texts
                Talks.OnText(kind, channel, text);
                if (LootScreen.OnScreen(kind)) Text(text);   // game_lootscreen: the loot line stays off the screen, the chat tabs still get it
                Chat("", text, 0);
            }
            else if (W.Fx.Enabled)   // damage, heal and experience numbers
                W.Fx.Push(typed ? FxEvent.TypedNumber(kind, at, v1, c1, v2, c2, text, percent, impact, owner) : FxEvent.Number(kind, at, v1, c1, v2, c2, text));
        }

        void ChannelList(ByteReader r)
        {
            Talks.Channels.Clear();
            for (int n = r.U8(), i = 0; i < n; i++) Talks.Channels.Add(new ChatChannel { Id = r.U16(), Name = r.Str() });
            Talks.ChannelListArrived = true;
            Talks.ChannelsListed();
        }

        /// <summary>0xAC and 0xB2: id, name, the users in the channel, the invited ones. The tab opens and takes the focus.</summary>
        void ChannelOpened(ByteReader r, bool focus)
        {
            int id = r.U16();
            string name = r.Str();
            for (int n = r.U16(), i = 0; i < n; i++) r.Str();
            for (int n = r.U16(), i = 0; i < n; i++) r.Str();
            Talks.Clock = Clock;
            Talks.OpenChannel(id, name, focus);
            ChannelOpenedByServer(id, name);
        }

        void PrivateOpened(ByteReader r)
        {
            Talks.Clock = Clock;
            Talks.OpenPrivate(r.Str(), true);
        }

        void ChannelClosed(ByteReader r) { Talks.ServerClosed(r.U16()); }
    }

    public sealed partial class GameSession
    {
        /// <summary>Fight, chase and secure modes. Sent once when the character enters the game and at every change (SetFightModes).</summary>
        public FightModes Modes = new FightModes();
        bool modesSent;

        public ChatModel Talks => parser.Talks;

        /// <summary>Called by Poll: the fight modes go out once after the login.</summary>
        void ChatPoll()
        {
            if (modesSent || !parser.LoggedIn || conn == null) return;
            modesSent = true;
            conn.Send(Modes.Packet());
        }

        public void SetFightModes(FightModes m)
        {
            Modes = m;
            if (modesSent) conn?.Send(m.Packet());
        }

        /// <summary>A typed line: say, yell, whisper, a channel line, a private message or a client command (see ChatModel.Plan).</summary>
        public void Talk(string input)
        {
            var plan = parser.Talks.Plan(input);
            if (!plan.Send || conn == null) return;
            conn.Send(ChatPackets.Talk(plan));
            if (plan.Type == TalkType.PrivateTo) parser.Talks.EchoPrivate(plan.Receiver, plan.Text);
        }

        public void RequestChannels() => conn?.Send(ChatPackets.RequestChannels());
        public void JoinChannel(int id) => conn?.Send(ChatPackets.JoinChannel(id));
        /// <summary>Asks the server to open a private message tab with a player (0x9A); the tab opens when the server answers (0xAD).</summary>
        public void OpenPrivate(string name) { if (!string.IsNullOrWhiteSpace(name)) conn?.Send(ChatPackets.OpenPrivate(name.Trim())); }

        /// <summary>Closes the tab at an index: a channel is left on the server, the NPC channel closed, a private tab just goes.</summary>
        public void CloseTab(int index)
        {
            var t = parser.Talks.Close(index);
            if (t == null) return;
            if (t.Kind == TabKind.Channel) conn?.Send(ChatPackets.LeaveChannel(t.ChannelId));
            else if (t.Kind == TabKind.Npc) conn?.Send(ChatPackets.CloseNpcChannel());
        }
    }
}
