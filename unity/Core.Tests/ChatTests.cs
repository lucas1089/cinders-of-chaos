// Chat checks (Core/Chat.cs, Core/GameChat.cs): byte-level packets in (0xAA with every 10.98 talk type, 0xAB to 0xB3 channels,
// 0xB4 console kinds, 0x28 death) and out (0x96, 0x97 to 0x9A, 0x9E, 0xA0), the tab model (unread, history cap, switching,
// closing), the typed-line rules, the ignore list, the floating speech and the fight modes.
using System;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class ChatTests
    {
        static readonly Pos P = new Pos(100, 100, 7);

        static GameParser Parser(out World w)
        {
            w = new World(null);
            var hero = new Creature { Id = 1, Name = "Hero", Position = P };
            var rat = new Creature { Id = 2, Name = "Rat", Position = new Pos(101, 100, 7), Type = 1 };
            w.Creatures[1] = hero; w.Creatures[2] = rat; w.PlayerId = 1;
            double t = 1000;
            var p = new GameParser(w) { Clock = () => t };
            p.Talks.Stamp = () => "12:00";
            return p;
        }

        static ByteWriter Talk(ByteWriter w, string name, int level, byte type, string text, Pos? at = null, int channel = -1)
        {
            w.U8(0xAA).U32(1).Str(name).U16((ushort)level).U8(type);
            if (at.HasValue) w.U16((ushort)at.Value.X).U16((ushort)at.Value.Y).U8((byte)at.Value.Z);
            if (channel >= 0) w.U16((ushort)channel);
            return w.Str(text);
        }

        public static void Run(Action<bool, string> check)
        {
            Incoming(check);
            Model(check);
            Typed(check);
            Outgoing(check);
            Bubbles(check);
            Fight(check);
        }

        static void Incoming(Action<bool, string> check)
        {
            var p = Parser(out var world);
            var m = p.Talks;
            var legacy = new List<string>();
            p.Chat = (who, text, type) => legacy.Add(type + "|" + who + "|" + text);
            var w = new ByteWriter();
            Talk(w, "Hero", 20, TalkType.Say, "hello", P);
            Talk(w, "Hero", 20, TalkType.Whisper, "psst", P);
            Talk(w, "Hero", 20, TalkType.Yell, "HEY", P);
            Talk(w, "Rat", 0, TalkType.MonsterSay, "squeak", new Pos(101, 100, 7));
            Talk(w, "Rat", 0, TalkType.MonsterYell, "SQUEAK", new Pos(101, 100, 7));
            Talk(w, "Hero", 20, TalkType.Spell, "exura", P);
            Talk(w, "Oracle", 0, TalkType.NpcFrom, "Welcome.", new Pos(103, 100, 7));
            Talk(w, "GM", 1, TalkType.Broadcast, "Restart soon");
            p.Parse(w.ToArray());
            var def = m.DefaultTab.Lines;
            check(def.Count == 8 && def[0].Display == "Hero: hello" && def[0].Level == 20 && def[0].Self && def[0].Color == 0xFFFF00 &&
                  def[2].Color == 0xFF4040 && def[3].Color == 0xFE6500 && def[6].Type == TalkType.NpcFrom && def[7].Type == TalkType.Broadcast,
                  "chat: say, whisper, yell, monster, spell, npc and broadcast lines go to Default with their colours");
            check(legacy.Count == 8 && legacy[0] == "1|Hero|hello", "chat: the legacy Chat callback still fires");
            check(m.Tabs.Count == 2 && m.Active == 0 && m.DefaultTab.Unread == 0, "chat: public lines open no tab");

            // floating speech: say, whisper, yell, monster say and yell, spell float over the speaker; npc and broadcast do not
            double now = 1000;
            check(m.Bubbles.For(1, now).Count == 3 && m.Bubbles.For(2, now).Count == 2 && m.Bubbles.Count == 5,
                  "chat: bubbles over the speakers: " + m.Bubbles.Count);

            // an unknown talk type stops the packet instead of misreading it
            bool threw = false;
            try { p.Parse(new ByteWriter().U8(0xAA).U32(1).Str("X").U16(1).U8(99).Str("t").ToArray()); } catch (ProtocolException) { threw = true; }
            check(threw, "chat: unknown talk type throws");

            // private messages: a tab of the sender with an unread count; both in one packet, then the rest of the packet still reads
            w = new ByteWriter();
            Talk(w, "Mira", 40, TalkType.PrivateFrom, "psst you there?");
            Talk(w, "Mira", 40, TalkType.PrivateFrom, "hello?");
            Talk(w, "Gm", 1, TalkType.PrivateRedFrom, "report seen");
            w.U8(0x1D);
            bool ping = false;
            p.Pinged = () => ping = true;
            p.Parse(w.ToArray());
            var mira = m.FindPrivate("mira");
            check(mira != null && mira.Kind == TabKind.Private && mira.Lines.Count == 2 && mira.Unread == 2 && m.FindPrivate("GM") != null && ping,
                  "chat: private from opens a tab per sender with unread counts");
            check(mira.Lines[0].Color == 0x5FF7F7 && m.FindPrivate("gm").Lines[0].Color == 0xF55E5E, "chat: private colours, red for a GM");

            // channels: list, open (focus), a line with the channel id, the server closing it
            w = new ByteWriter().U8(0xAB).U8(3).U16(2).Str("Guild").U16(4).Str("Party").U16(7).Str("Help");
            p.Parse(w.ToArray());
            check(m.Channels.Count == 3 && m.Channels[2].Id == 7 && m.Channels[2].Name == "Help" && m.ChannelListArrived, "chat: 0xAB channel list");
            w = new ByteWriter().U8(0xAC).U16(7).Str("Help").U16(2).Str("Ann").Str("Bob").U16(0);
            Talk(w, "Ann", 12, TalkType.ChannelYellow, "anyone?", null, 7);
            Talk(w, "Bob", 13, TalkType.ChannelOrange, "yes", null, 7);
            Talk(w, "Ann", 12, TalkType.ChannelRed, "!", null, 9);
            p.Parse(w.ToArray());
            var help = m.FindChannel(7);
            check(help != null && help.Name == "Help" && help.Lines.Count == 2 && help.Lines[0].Display == "Ann: anyone?" && help.Lines[1].Color == 0xFE6500 &&
                  m.Current == help && help.Unread == 0, "chat: 0xAC opens and focuses the channel, lines go to it");
            var other = m.FindChannel(9);
            check(other != null && other.Name == "Channel 9" && other.Lines.Count == 1 && other.Unread == 1, "chat: a line of an unopened channel makes a tab");
            p.Parse(new ByteWriter().U8(0xAD).Str("Zed").ToArray());
            check(m.Current.Kind == TabKind.Private && m.Current.Name == "Zed", "chat: 0xAD opens a private tab");
            p.Parse(new ByteWriter().U8(0xB2).U16(60).Str("Mira's channel").U16(1).Str("Hero").U16(0).ToArray());
            check(m.FindChannel(60) != null && m.Current.ChannelId == 60, "chat: 0xB2 own channel");
            p.Parse(new ByteWriter().U8(0xB3).U16(60).U8(0x1D).ToArray());
            check(m.FindChannel(60) == null && m.Tabs.Count == 7 && m.Active >= 0 && m.Active < m.Tabs.Count, "chat: 0xB3 closes the tab");

            // 0xB4: console kinds by tab, numbers over creatures still reach the effect feed
            var q = Parser(out var w2);
            w2.Fx.Enabled = true;
            var mm = q.Talks;
            mm.OpenChannel(5, "Party", false);
            var b = new ByteWriter();
            b.U8(0xB4).U8(17).Str("You see a rat.");          // status default -> Server Log
            b.U8(0xB4).U8(13).Str("red console");              // console red -> Default
            b.U8(0xB4).U8(4).Str("blue console");              // console blue -> Default
            b.U8(0xB4).U8(35).U16(5).Str("Ann: party hello");  // party -> the Party channel tab
            b.U8(0xB4).U8(34).U16(8).Str("party left");         // party kind of a channel not open -> Server Log
            b.U8(0xB4).U8(23).U16((ushort)P.X).U16((ushort)P.Y).U8((byte)P.Z).U32(50).U8(180).U32(0).U8(0).Str("A rat loses 50 hitpoints.");
            b.U8(0xB4).U8(19).Str("You advanced to level 5.");
            q.Parse(b.ToArray());
            check(mm.LogTab.Lines.Count == 3 && mm.LogTab.Lines[0].Text == "You see a rat." && mm.LogTab.Lines[1].Text == "party left" &&
                  mm.LogTab.Lines[2].Color == 0xFE6500, "chat: console kinds go to Server Log: " + mm.LogTab.Lines.Count);
            check(mm.DefaultTab.Lines.Count == 2 && mm.DefaultTab.Lines[0].Color == 0xF55E5E && mm.DefaultTab.Lines[1].Color == 0x5FF7F7, "chat: red and blue console go to Default");
            check(mm.FindChannel(5).Lines.Count == 1 && mm.FindChannel(5).Unread == 1, "chat: party text goes to the open channel");
            check(w2.Fx.Count == 1, "chat: a damage number is not chat and still reaches the effect feed");

            // 0x28: type 0 carries a penalty byte, type 1 none; the next message still reads
            q = Parser(out w2);
            int died = 0;
            q.Died = () => died++;
            ping = false;
            q.Pinged = () => ping = true;
            q.Parse(new byte[] { 0x28, 0x00, 100, 0x1D });
            check(q.Dead && q.DeathType == 0 && q.DeathPenalty == 100 && died == 1 && ping, "death: regular death with penalty 100");
            q = Parser(out w2);
            q.Parse(new byte[] { 0x28, 0x00, 55 });
            check(q.Dead && q.DeathPenalty == 55, "death: penalty 55");
            q = Parser(out w2);
            ping = false;
            q.Pinged = () => ping = true;
            q.Parse(new byte[] { 0x28, 0x01, 0x1D });
            check(q.Dead && q.DeathType == 1 && q.DeathPenalty == 0 && ping, "death: an unfair-fight death has no penalty byte");
        }

        static void Model(Action<bool, string> check)
        {
            var m = new ChatModel { Stamp = () => "t" };
            m.SelfName = "Hero";
            m.HistoryCap = 5;
            for (int i = 0; i < 9; i++) m.OnTalk("Ann", 1, TalkType.Say, -1, "line " + i);
            check(m.DefaultTab.Lines.Count == 5 && m.DefaultTab.Lines[0].Text == "line 4" && m.DefaultTab.Lines[4].Text == "line 8", "chat model: the history keeps the newest {cap} lines");
            m.OnText(17, -1, "x");
            check(m.LogTab.Unread == 1 && m.DefaultTab.Unread == 0, "chat model: unread counts the tabs not shown");
            m.Step(1);
            check(m.Active == 1 && m.LogTab.Unread == 0, "chat model: Tab switches and clears the unread count");
            m.Step(1);
            check(m.Active == 0, "chat model: Tab wraps");
            m.Step(-1);
            check(m.Active == 1, "chat model: Shift+Tab wraps back");
            m.OpenChannel(3, "Trade", true);
            m.OpenPrivate("Zed", false);
            check(m.Tabs.Count == 4 && m.Current.Name == "Trade" && m.Tabs[3].Name == "Zed", "chat model: tab order");
            check(m.Close(0) == null && m.Close(1) == null && m.Tabs.Count == 4, "chat model: Default and Server Log cannot close");
            var closed = m.Close(2);
            check(closed != null && closed.ChannelId == 3 && m.Tabs.Count == 3 && m.Current.Name == "Zed" || m.Current == m.Tabs[m.Active], "chat model: closing a tab picks a neighbour");
            check(m.Active >= 0 && m.Active < m.Tabs.Count, "chat model: the active index stays in range");
            m.OpenChannel(4, "NPCs", true);
            check(m.Current.Kind == TabKind.Npc, "chat model: the NPCs channel is an Npc tab");
            m.Reset();
            check(m.Tabs.Count == 2 && m.DefaultTab.Lines.Count == 0 && m.Active == 0, "chat model: reset");

            // ignore: players are dropped (any case), monsters and NPCs are not
            m.Ignored.Add("spammer");
            check(m.OnTalk("Spammer", 1, TalkType.Say, -1, "buy") == null && m.OnTalk("Spammer", 1, TalkType.PrivateFrom, -1, "buy") == null &&
                  m.FindPrivate("spammer") == null && m.DefaultTab.Lines.Count == 0, "chat model: ignored players are dropped, and open no private tab");
            check(m.OnTalk("Spammer", 0, TalkType.MonsterSay, -1, "grr") != null, "chat model: a monster of that name is not ignored");

            // colours
            check(TalkType.Color(TalkType.PrivateFrom) == 0x5FF7F7 && TalkType.Color(TalkType.Broadcast) == 0xF55E5E && TalkType.Color(0) == 0xFFFFFF,
                  "chat model: colours by type");
            check(TalkType.HasPosition(1) && TalkType.HasPosition(36) && !TalkType.HasPosition(7) && TalkType.HasChannel(14) && !TalkType.HasChannel(13) &&
                  TalkType.IsBare(13) && !TalkType.Known(99), "chat model: layout of each type");
        }

        static void Typed(Action<bool, string> check)
        {
            var m = new ChatModel { Stamp = () => "t" };
            m.SelfName = "Hero";
            var p = m.Plan("  hello  ");
            check(p.Send && p.Type == TalkType.Say && p.Text == "hello", "typed: plain text says on Default");
            check(!m.Plan("   ").Send && !m.Plan(null).Send, "typed: an empty line sends nothing");
            p = m.Plan("#y run");
            check(p.Send && p.Type == TalkType.Yell && p.Text == "run", "typed: #y yells");
            p = m.Plan("#w quiet");
            check(p.Send && p.Type == TalkType.Whisper && p.Text == "quiet", "typed: #w whispers");
            check(m.Plan("#y").Send && m.Plan("#y").Type == TalkType.Say, "typed: #y alone is plain text");
            p = m.Plan("*Mira* hi there");
            check(p.Send && p.Type == TalkType.PrivateTo && p.Receiver == "Mira" && p.Text == "hi there", "typed: *name* text is a private message");
            check(m.Plan("*Mira*").Send && m.Plan("*Mira*").Type == TalkType.Say, "typed: *name* without text is plain text");
            m.OpenChannel(7, "Help", true);
            p = m.Plan("anyone?");
            check(p.Send && p.Type == TalkType.ChannelYellow && p.Channel == 7 && p.Text == "anyone?", "typed: on a channel tab the line goes to the channel");
            p = m.Plan("*Mira* psst");
            check(p.Type == TalkType.PrivateTo && p.Receiver == "Mira", "typed: *name* works on a channel tab too");
            m.OpenPrivate("Zed", true);
            p = m.Plan("yo");
            check(p.Type == TalkType.PrivateTo && p.Receiver == "Zed" && p.Text == "yo", "typed: on a private tab the line goes to that player");
            m.OpenChannel(0xFFFF, "NPCs", true);
            p = m.Plan("trade");
            check(p.Type == TalkType.NpcTo && p.Text == "trade", "typed: on the NPCs tab the line is for the NPC");
            m.Select(1);
            check(m.Plan("hi").Type == TalkType.Say, "typed: on Server Log the line says");
            check(m.Plan(new string('a', 400)).Text.Length == 255, "typed: lines are cut at 255");
            check(!m.Plan("/ignore Bob").Send && m.IsIgnored("bob") && !m.Plan("/unignore bob").Send && !m.IsIgnored("Bob"), "typed: /ignore and /unignore edit the list");
            m.EchoPrivate("Zed", "psst");
            check(m.Current.Name == "Zed" && m.Current.Lines.Last().Self && m.Current.Lines.Last().Speaker == "Hero", "typed: a sent private message shows in its tab");
        }

        static void Outgoing(Action<bool, string> check)
        {
            check(ChatPackets.Talk(TalkType.Say, 0, "", "hi").SequenceEqual(new byte[] { 0x96, 1, 2, 0, (byte)'h', (byte)'i' }), "out: say matches the old SayPacket");
            check(ChatPackets.Talk(TalkType.Say, 0, "", "hi").SequenceEqual(Protocol.SayPacket("hi")), "out: say equals Protocol.SayPacket");
            check(ChatPackets.Talk(TalkType.Yell, 0, "", "a").SequenceEqual(new byte[] { 0x96, 3, 1, 0, (byte)'a' }), "out: yell");
            check(ChatPackets.Talk(TalkType.PrivateTo, 0, "Bo", "x").SequenceEqual(new byte[] { 0x96, 5, 2, 0, (byte)'B', (byte)'o', 1, 0, (byte)'x' }), "out: private has the receiver first");
            check(ChatPackets.Talk(TalkType.ChannelYellow, 0x0107, "", "x").SequenceEqual(new byte[] { 0x96, 7, 0x07, 0x01, 1, 0, (byte)'x' }), "out: channel has the channel id first");
            check(ChatPackets.Talk(TalkType.NpcTo, 0, "", "x").SequenceEqual(new byte[] { 0x96, 12, 1, 0, (byte)'x' }), "out: NPC channel line");
            check(ChatPackets.RequestChannels().SequenceEqual(new byte[] { 0x97 }), "out: 0x97 request channels");
            check(ChatPackets.JoinChannel(5).SequenceEqual(new byte[] { 0x98, 5, 0 }), "out: 0x98 join");
            check(ChatPackets.LeaveChannel(0x0102).SequenceEqual(new byte[] { 0x99, 2, 1 }), "out: 0x99 leave");
            check(ChatPackets.OpenPrivate("Al").SequenceEqual(new byte[] { 0x9A, 2, 0, (byte)'A', (byte)'l' }), "out: 0x9A open private");
            check(ChatPackets.CloseNpcChannel().SequenceEqual(new byte[] { 0x9E }), "out: 0x9E close NPC channel");
        }

        static void Bubbles(Action<bool, string> check)
        {
            check(BubbleSet.LifeFor("hi") == 3000 && BubbleSet.LifeFor(new string('x', 100)) == 6000 && BubbleSet.LifeFor(new string('x', 1000)) == 12000,
                  "bubbles: lifetime by length, 3 s to 12 s");
            var s = new BubbleSet();
            s.Add(1, "A", "one", 1, 0xFFFF00, 0);
            s.Add(1, "A", "two", 1, 0xFFFF00, 100);
            s.Add(1, "A", "three", 1, 0xFFFF00, 200);
            s.Add(1, "A", "four", 1, 0xFFFF00, 300);
            s.Add(2, "B", "other", 1, 0xFFFF00, 300);
            var l = s.For(1, 400);
            check(l.Count == 3 && l[0].Text == "two" && l[2].Text == "four", "bubbles: at most 3 stack per creature, oldest first");
            check(s.For(2, 400).Count == 1 && s.Count == 4, "bubbles: other creatures keep theirs");
            check(s.For(1, 3150).Count == 2 && s.For(1, 3150)[0].Text == "three", "bubbles: they end after their lifetime");
            check(s.Active(3150).Count == 3 && s.Count == 3 && s.Active(10000).Count == 0, "bubbles: Active drops the finished ones");
            s.Add(0, "A", "no creature", 1, 0, 0);
            s.Add(3, "A", "", 1, 0, 0);
            check(s.Count == 0, "bubbles: no creature or no text adds none");
        }

        static void Fight(Action<bool, string> check)
        {
            var m = new FightModes();
            check(m.Packet().SequenceEqual(new byte[] { 0xA0, 2, 0, 1, 0 }), "fight: balanced, stand, secure on (the secure byte is 1 when on: Player::secureMode, found live in phase 22)");
            m = new FightModes { Fight = FightModes.Offensive, Chase = true, Secure = false };
            check(m.Packet().SequenceEqual(new byte[] { 0xA0, 1, 1, 0, 0 }), "fight: offensive, chase, secure off (byte 0)");
            check(new FightModes { Fight = FightModes.Defensive }.Packet()[1] == 3, "fight: defensive is 3");
            check(m.Encode() == "1,1,0", "fight: saved form");
            var d = FightModes.Decode("3,1,0");
            check(d.Fight == 3 && d.Chase && !d.Secure, "fight: decode");
            d = FightModes.Decode("junk");
            check(d.Fight == 2 && !d.Chase && d.Secure, "fight: junk decodes to the defaults");
            d = FightModes.Decode("9,0,1");
            check(d.Fight == 2, "fight: an out of range mode keeps the default");
        }
    }
}
