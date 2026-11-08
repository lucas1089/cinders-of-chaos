// Party: the base packets (client -> server 0xA3 invite, 0xA4 join, 0xA5 revoke, 0xA6 pass leadership, 0xA7 leave,
// 0xA8 shared experience; the shield of a creature arrives in 0x91) and the Chaos party frames, extended opcode 235
// (client game_partyframes, server partyframes.lua / partyframes_core.lua).
//
//   client -> server  open {buffs} | close | kick {id} | lead {id} | invite {name}
//   server -> client  state {leader, members = [entry], xp = {p, on}}   (every 500 ms to a watching client; empty list = no party)
// entry: i id, n name, lv level, vc vocation id, h / H health, m / M mana, p health percent, dz floors (down is +), d squares
// (in range only), far 1 (out of range: only p and dz), f flags (1 leader, 2 fight, 4 dead, 8 offline, 16 you), o outfit
// {t, h, b, l, f, a}, b buffs [{i icon, t 0 buff / 1 debuff, l ms left, n name}].
// The invitation is only a server line "<Leader> has invited you to join his party." (no packet): PartyFrames.OnServerText
// picks it up. Joining is 0xA4 with the leader's creature id, so the leader must be in view.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    /// <summary>Base 10.98 party packets, client to server.</summary>
    public static class PartyPackets
    {
        public const byte Invite = 0xA3, Join = 0xA4, Revoke = 0xA5, PassLeadership = 0xA6, Leave = 0xA7, ShareExperience = 0xA8;

        public static byte[] InvitePacket(uint creatureId) => new ByteWriter().U8(Invite).U32(creatureId).ToArray();
        public static byte[] JoinPacket(uint leaderId) => new ByteWriter().U8(Join).U32(leaderId).ToArray();
        public static byte[] RevokePacket(uint creatureId) => new ByteWriter().U8(Revoke).U32(creatureId).ToArray();
        public static byte[] PassLeadershipPacket(uint creatureId) => new ByteWriter().U8(PassLeadership).U32(creatureId).ToArray();
        public static byte[] LeavePacket() => new byte[] { Leave };
        /// <summary>0xA8: shared experience on or off (the second byte is unused by the server).</summary>
        public static byte[] ShareExperiencePacket(bool on) => new ByteWriter().U8(ShareExperience).U8(on ? (byte)1 : (byte)0).U8(0).ToArray();
    }

    /// <summary>The party shield of a creature (0x91).</summary>
    public static class PartyShield
    {
        public const int None = 0, WhiteYellow = 1, WhiteBlue = 2, Blue = 3, Yellow = 4, BlueShared = 5, YellowShared = 6,
                         BlueNoSharedBlink = 7, YellowNoSharedBlink = 8, BlueNoShared = 9, YellowNoShared = 10;

        public static bool IsLeader(int s) => s == Yellow || s == YellowShared || s == YellowNoSharedBlink || s == YellowNoShared;
        public static bool IsMember(int s) => s == Blue || s == BlueShared || s == BlueNoSharedBlink || s == BlueNoShared;
        public static bool InParty(int s) => IsLeader(s) || IsMember(s);
        /// <summary>The leader switched shared experience on (it works, or a member does not meet its rules yet).</summary>
        public static bool SharedEnabled(int s) => s == BlueShared || s == YellowShared || s == BlueNoSharedBlink || s == YellowNoSharedBlink;
        /// <summary>This creature invited you: joining is possible. The server (Player::getPartyShield, `player->isInviting(this)`) shows the inviting leader to the
        /// invited player as white and yellow. Found by the live check (O433 phase 21): the first version had the two the other way round.</summary>
        public static bool InvitedYou(int s) => s == WhiteYellow;
        /// <summary>You invited this creature: the invitation can be revoked. The server shows the invited player to the leader as white and blue (`isInviting(player)`).</summary>
        public static bool InvitedByYou(int s) => s == WhiteBlue;
    }

    public enum PartyAction { Invite, Join, Revoke, PassLeadership, Leave, ShareOn, ShareOff }

    /// <summary>What the right-click menu of a player offers, by the main client's rules (game_interface).</summary>
    public static class PartyMenu
    {
        /// <summary>The party entries for a player we are not: myShield and targetShield are 0x91 values.</summary>
        public static List<PartyAction> For(int myShield, int targetShield)
        {
            var list = new List<PartyAction>();
            bool leader = PartyShield.IsLeader(myShield), inParty = PartyShield.InParty(myShield);
            if (PartyShield.InvitedYou(targetShield) && !inParty) list.Add(PartyAction.Join);
            if (targetShield == PartyShield.None && (myShield == PartyShield.None || leader)) list.Add(PartyAction.Invite);
            if (leader && PartyShield.InvitedByYou(targetShield)) list.Add(PartyAction.Revoke);
            if (leader && PartyShield.IsMember(targetShield)) list.Add(PartyAction.PassLeadership);
            if (leader) list.Add(PartyShield.SharedEnabled(myShield) ? PartyAction.ShareOff : PartyAction.ShareOn);
            if (inParty) list.Add(PartyAction.Leave);
            return list;
        }

        /// <summary>The English label (the key of Loc.T) of an entry.</summary>
        public static string Label(PartyAction a)
        {
            switch (a)
            {
                case PartyAction.Invite: return "Invite to Party";
                case PartyAction.Join: return "Join Party";
                case PartyAction.Revoke: return "Revoke Invitation";
                case PartyAction.PassLeadership: return "Pass Leadership";
                case PartyAction.Leave: return "Leave Party";
                case PartyAction.ShareOn: return "Enable Shared Experience";
                default: return "Disable Shared Experience";
            }
        }
    }

    public sealed class PartyBuff
    {
        public string Icon = "", Name = "";
        public bool Debuff;
        public double EndsAt;   // ms on the party clock, 0 = unknown
    }

    public sealed class PartyMember
    {
        public const int FlagLeader = 1, FlagFight = 2, FlagDead = 4, FlagOffline = 8, FlagSelf = 16;
        public uint Id;
        public string Name = "";
        public int Level, Vocation, Percent, Floors, Flags;
        public bool Far;
        public double Hp, HpMax, Mp, MpMax, Distance = -1;
        public Outfit Outfit;
        public readonly List<PartyBuff> Buffs = new List<PartyBuff>();

        public bool Leader => (Flags & FlagLeader) != 0;
        public bool Fight => (Flags & FlagFight) != 0;
        public bool Dead => (Flags & FlagDead) != 0;
        public bool Offline => (Flags & FlagOffline) != 0;
        public bool Self => (Flags & FlagSelf) != 0;
        /// <summary>Mana as a percent (0 for a far member, who has none).</summary>
        public int ManaPercent => Far || MpMax <= 0 ? 0 : (int)Math.Max(0, Math.Min(100, Math.Round(Mp * 100 / MpMax)));

        public static PartyMember From(object e, double now)
        {
            if (!(e is Dictionary<string, object>)) return null;
            double id = Json.Number(e, "i", -1);
            string name = Json.Text(e, "n");
            if (id < 0 || name.Length == 0) return null;
            var m = new PartyMember
            {
                Id = (uint)id, Name = name, Level = (int)Math.Floor(Json.Number(e, "lv")), Vocation = (int)Math.Floor(Json.Number(e, "vc")),
                Percent = (int)Math.Max(0, Math.Min(100, Math.Floor(Json.Number(e, "p")))), Floors = (int)Math.Floor(Json.Number(e, "dz")),
                Flags = (int)Math.Floor(Json.Number(e, "f")), Far = Json.Number(e, "far") == 1,
            };
            if (!m.Far)
            {
                m.Hp = Json.Number(e, "h"); m.HpMax = Json.Number(e, "H"); m.Mp = Json.Number(e, "m"); m.MpMax = Json.Number(e, "M");
                if (Json.Get(e, "d") is double d) m.Distance = d;
            }
            object o = Json.Get(e, "o");
            if (o is Dictionary<string, object>)
                m.Outfit = new Outfit(Json.Int(o, "t"), Json.Int(o, "h"), Json.Int(o, "b"), Json.Int(o, "l"), Json.Int(o, "f"), Json.Int(o, "a"));
            foreach (object b in Json.List(e, "b"))
            {
                string icon = Json.Text(b, "i");
                if (icon.Length == 0) continue;
                double left = Json.Number(b, "l", -1);
                string bn = Json.Text(b, "n");
                m.Buffs.Add(new PartyBuff { Icon = icon, Debuff = Json.Number(b, "t") == 1, EndsAt = left >= 0 ? now + left : 0, Name = bn.Length > 40 ? bn.Substring(0, 40) : bn });
            }
            return m;
        }

        public string DistanceText() => Self ? "" : Far ? "far" : Distance < 0 ? "" : (int)Distance + " sq";
    }

    /// <summary>The party frames: the state of opcode 235 and the invitation line. Times are milliseconds on Clock.</summary>
    public sealed class PartyFrames
    {
        public const byte Opcode = 235;
        public const double StaleMs = 4500, InviteKeepMs = 300000;

        readonly ExtOpcodes ext;
        public Func<double> Clock = () => 0;
        /// <summary>Base packets go out through this (GameSession sets it to the connection).</summary>
        public Action<byte[]> Packet = delegate { };
        public readonly List<PartyMember> Members = new List<PartyMember>();
        public uint LeaderId;
        /// <summary>Shared experience: bonus percent and 0 not switched on, 1 works, 2 switched on but a member does not meet the rules; -1 unknown.</summary>
        public int XpPercent, XpOn = -1;
        public double LastState = -1;
        public int States;
        public Action Changed = delegate { };
        /// <summary>The leader who invited us, "" when none.</summary>
        public string InvitedBy = "";
        public double InvitedAt;
        public bool Watching;

        public PartyFrames(ExtOpcodes e)
        {
            ext = e;
            ext.On(Opcode, OnMessage);
        }

        public bool InParty => Members.Count > 0;
        public bool ViewerIsLeader { get { foreach (var m in Members) if (m.Self && m.Leader) return true; return false; } }
        public PartyMember Self { get { foreach (var m in Members) if (m.Self) return m; return null; } }
        public bool Stale(double now) => InParty && LastState >= 0 && now - LastState > StaleMs;

        public void Open(bool buffs = true)
        {
            Watching = true;
            ext.Send(Opcode, "open", new Dictionary<string, object> { { "buffs", buffs } });
        }

        public void Close()
        {
            if (!Watching) return;
            Watching = false;
            ext.Send(Opcode, "close");
        }

        public void Kick(uint id) { ext.Send(Opcode, "kick", new Dictionary<string, object> { { "id", id } }); }
        public void Lead(uint id) { ext.Send(Opcode, "lead", new Dictionary<string, object> { { "id", id } }); }
        public bool Invite(string name)
        {
            name = (name ?? "").Trim();
            if (name.Length < 2) return false;
            return ext.Send(Opcode, "invite", new Dictionary<string, object> { { "name", name } });
        }

        /// <summary>Does what a menu entry says, for the creature id (the base packets; Leave and the shared experience need none).</summary>
        public void Do(PartyAction a, uint id)
        {
            switch (a)
            {
                case PartyAction.Invite: Packet(PartyPackets.InvitePacket(id)); break;
                case PartyAction.Join: Packet(PartyPackets.JoinPacket(id)); InvitedBy = ""; break;
                case PartyAction.Revoke: Packet(PartyPackets.RevokePacket(id)); break;
                case PartyAction.PassLeadership: Packet(PartyPackets.PassLeadershipPacket(id)); break;
                case PartyAction.Leave: Packet(PartyPackets.LeavePacket()); break;
                case PartyAction.ShareOn: Packet(PartyPackets.ShareExperiencePacket(true)); break;
                case PartyAction.ShareOff: Packet(PartyPackets.ShareExperiencePacket(false)); break;
            }
        }

        void OnMessage(ExtMessage m)
        {
            if (m.Action == "state") Apply(m.Data, Clock());
        }

        /// <summary>Applies a state message: the member list is replaced, an empty one means no party.</summary>
        public void Apply(object data, double now)
        {
            Members.Clear();
            foreach (object e in Json.List(data, "members"))
            {
                var m = PartyMember.From(e, now);
                if (m != null) Members.Add(m);
            }
            LeaderId = (uint)Math.Max(0, Json.Number(data, "leader"));
            object xp = Json.Get(data, "xp");
            if (xp is Dictionary<string, object>) { XpPercent = (int)Math.Max(0, Math.Floor(Json.Number(xp, "p"))); XpOn = (int)Math.Floor(Json.Number(xp, "on")); }
            else { XpPercent = 0; XpOn = -1; }
            LastState = now;
            States++;
            if (InParty) InvitedBy = "";
            Changed();
        }

        public void Clear()
        {
            Members.Clear();
            LeaderId = 0; XpPercent = 0; XpOn = -1; LastState = -1; InvitedBy = ""; Watching = false;
        }

        /// <summary>The header text of the shared experience bonus, or "" (the main client's PartyMath.xpView).</summary>
        public string XpText()
        {
            if (!InParty || XpOn < 0) return "";
            if (XpOn == 1 && XpPercent > 0) return "+" + XpPercent + "% XP";
            return XpOn == 2 ? "XP off" : "";
        }

        // ------------------------------------------------------------------------------------ the invitation line
        /// <summary>The leader's name in "X has invited you to ...", or null.</summary>
        public static string InviterOf(string text) => NameBefore(text, " has invited you to ");
        /// <summary>The leader's name in "X has revoked ...", or null.</summary>
        public static string RevokerOf(string text) => NameBefore(text, " has revoked ");

        static string NameBefore(string text, string marker)
        {
            if (text == null) return null;
            int i = text.IndexOf(marker, StringComparison.Ordinal);
            if (i < 2 || i > 30 || text.IndexOf('\n') >= 0 || text.IndexOf('\r') >= 0) return null;
            return text.Substring(0, i);
        }

        /// <summary>A server message: an invitation or a revoke line.</summary>
        public void OnServerText(string text)
        {
            string who = InviterOf(text);
            if (who != null) { InvitedBy = who; InvitedAt = Clock(); Changed(); return; }
            string rev = RevokerOf(text);
            if (rev != null && InvitedBy.Length > 0 && string.Equals(rev, InvitedBy, StringComparison.OrdinalIgnoreCase)) { InvitedBy = ""; Changed(); }
        }

        /// <summary>The invitation is dropped after 5 minutes or on joining a party.</summary>
        public bool InvitationOpen(double now)
        {
            if (InvitedBy.Length == 0) return false;
            if (now - InvitedAt > InviteKeepMs || InParty) { InvitedBy = ""; return false; }
            return true;
        }

        /// <summary>The creature id of the player of that name among `candidates` (id, name), 0 when out of view.</summary>
        public static uint FindLeader(IEnumerable<KeyValuePair<uint, string>> candidates, string name)
        {
            foreach (var c in candidates)
                if (string.Equals(c.Value, name, StringComparison.OrdinalIgnoreCase)) return c.Key;
            return 0;
        }
    }
}
