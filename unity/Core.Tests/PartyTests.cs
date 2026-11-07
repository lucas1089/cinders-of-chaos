// Party (base packets, shields, the menu, opcode 235 frames, the invitation line), the character select cards and the
// character plate numbers (experience percent, bars).
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Chaos.Core.Tests
{
    static class PartyTests
    {
        static string Hex(byte[] b) => string.Concat(b.Select(x => x.ToString("x2")));
        static string Text(byte[] sent) => Encoding.UTF8.GetString(sent, 4, sent.Length - 4);

        public static void Run(Action<bool, string> check)
        {
            Packets(check);
            Shields(check);
            Frames(check);
            Invitation(check);
            CharSelect(check);
            PlateChecks(check);
            LocLabels(check);
        }

        static void Packets(Action<bool, string> check)
        {
            check(Hex(PartyPackets.InvitePacket(0x01020304)) == "a304030201", "party: invite packet 0xA3 + creature id");
            check(Hex(PartyPackets.JoinPacket(7)) == "a407000000", "party: join packet 0xA4");
            check(Hex(PartyPackets.RevokePacket(7)) == "a507000000", "party: revoke packet 0xA5");
            check(Hex(PartyPackets.PassLeadershipPacket(9)) == "a609000000", "party: pass leadership packet 0xA6");
            check(Hex(PartyPackets.LeavePacket()) == "a7", "party: leave packet 0xA7");
            check(Hex(PartyPackets.ShareExperiencePacket(true)) == "a80100" && Hex(PartyPackets.ShareExperiencePacket(false)) == "a80000", "party: shared experience packet 0xA8");

            // the shield of a creature arrives in 0x91 and lands on the creature
            var w = new World(DatFile.Parse(Program.SyntheticDat()));
            var c = new Creature { Id = 77, Name = "Ally" };
            w.Creatures[77] = c;
            new GameParser(w).Parse(new ByteWriter().U8(0x91).U32(77).U8(PartyShield.Yellow).ToArray());
            check(c.Shield == PartyShield.Yellow, "party: 0x91 sets the shield");
        }

        static void Shields(Action<bool, string> check)
        {
            check(PartyShield.IsLeader(PartyShield.YellowShared) && PartyShield.IsMember(PartyShield.BlueNoShared) && !PartyShield.InParty(PartyShield.WhiteBlue) &&
                  PartyShield.SharedEnabled(PartyShield.BlueNoSharedBlink) && !PartyShield.SharedEnabled(PartyShield.YellowNoShared), "party: shield classes");
            // right-click rules of the main client
            Func<int, int, string> menu = (mine, target) => string.Join(",", PartyMenu.For(mine, target));
            check(menu(PartyShield.None, PartyShield.None) == "Invite", "party menu: no party, a free player: invite");
            check(menu(PartyShield.None, PartyShield.WhiteBlue) == "Join", "party menu: a player who invited us: join");
            check(menu(PartyShield.None, PartyShield.Blue) == "", "party menu: not in a party, another party's member: nothing");
            check(menu(PartyShield.Yellow, PartyShield.None) == "Invite,ShareOn,Leave", "party menu: leader, free player: invite, shared exp on, leave");
            check(menu(PartyShield.YellowShared, PartyShield.Blue) == "PassLeadership,ShareOff,Leave", "party menu: leader, member: pass leadership");
            check(menu(PartyShield.Yellow, PartyShield.WhiteYellow) == "Revoke,ShareOn,Leave", "party menu: leader, invited player: revoke");
            check(menu(PartyShield.Blue, PartyShield.None) == "Leave", "party menu: plain member can only leave");
            check(PartyMenu.Label(PartyAction.Leave) == "Leave Party", "party menu: labels are the Loc keys");
        }

        static void Frames(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var sent = new List<byte[]>();
            ext.Transmit = p => sent.Add(p);
            double now = 5000;
            var party = new PartyFrames(ext) { Clock = () => now };
            var packets = new List<byte[]>();
            party.Packet = packets.Add;
            int changes = 0;
            party.Changed = () => changes++;

            party.Open(true);
            check(sent.Count == 1 && sent[0][0] == 0x32 && sent[0][1] == 235 && Text(sent[0]) == "{\"action\":\"open\",\"data\":{\"buffs\":true}}", "party frames: open sends {buffs}: " + Text(sent[0]));
            check(!party.InParty && party.XpText() == "", "party frames: no party before a state");

            string state = "{\"action\":\"state\",\"data\":{\"leader\":10,\"xp\":{\"p\":20,\"on\":1},\"members\":[" +
                "{\"i\":10,\"n\":\"Mira\",\"lv\":120,\"vc\":8,\"h\":900,\"H\":1000,\"m\":50,\"M\":200,\"p\":90,\"dz\":0,\"d\":0,\"f\":17,\"o\":{\"t\":128,\"h\":78,\"b\":68,\"l\":58,\"f\":76,\"a\":3},\"b\":[{\"i\":\"haste\",\"t\":0,\"l\":3000,\"n\":\"Haste\"}]}," +
                "{\"i\":11,\"n\":\"Bran\",\"lv\":98,\"vc\":20,\"h\":10,\"H\":400,\"m\":0,\"M\":100,\"p\":3,\"dz\":0,\"d\":4,\"f\":2}," +
                "{\"i\":12,\"n\":\"Far One\",\"lv\":60,\"vc\":3,\"p\":40,\"dz\":-2,\"far\":1,\"f\":0}," +
                "{\"n\":\"no id\"},{\"i\":13}]}}";
            ext.Receive(235, state);
            check(party.InParty && party.Members.Count == 3 && party.LeaderId == 10 && changes == 1 && party.States == 1, "party frames: a state fills the members (bad entries dropped)");
            var mira = party.Members[0];
            check(mira.Name == "Mira" && mira.Level == 120 && mira.Leader && mira.Self && !mira.Fight && mira.HpMax == 1000 && mira.Percent == 90 &&
                  mira.ManaPercent == 25 && mira.Outfit.LookType == 128 && mira.Outfit.Addons == 3 && mira.Outfit.Feet == 76 &&
                  mira.Buffs.Count == 1 && mira.Buffs[0].Icon == "haste" && mira.Buffs[0].EndsAt == 8000 && !mira.Buffs[0].Debuff, "party frames: member fields, outfit and buffs");
            var bran = party.Members[1];
            check(bran.Fight && !bran.Leader && !bran.Self && bran.Distance == 4 && bran.DistanceText() == "4 sq" && bran.Percent == 3, "party frames: flags and distance");
            var far = party.Members[2];
            check(far.Far && far.Floors == -2 && far.Hp == 0 && far.ManaPercent == 0 && far.DistanceText() == "far" && far.Outfit == null, "party frames: a far member has only percent and floors");
            check(party.ViewerIsLeader && party.Self == mira && party.XpOn == 1 && party.XpPercent == 20 && party.XpText() == "+20% XP", "party frames: leader, self and the shared experience bonus");
            check(!party.Stale(5000 + 4000) && party.Stale(5000 + 4600), "party frames: stale after 4.5 s without a state");

            party.XpOn = 2;
            check(party.XpText() == "XP off", "party frames: shared experience switched on but not working");
            sent.Clear();
            party.Kick(11); party.Lead(12); party.Invite(" Nova ");
            check(Text(sent[0]) == "{\"action\":\"kick\",\"data\":{\"id\":11}}" && Text(sent[1]) == "{\"action\":\"lead\",\"data\":{\"id\":12}}" &&
                  Text(sent[2]) == "{\"action\":\"invite\",\"data\":{\"name\":\"Nova\"}}" && !party.Invite("x") && sent.Count == 3, "party frames: kick, lead and invite actions");

            party.Do(PartyAction.Invite, 5); party.Do(PartyAction.Leave, 0); party.Do(PartyAction.ShareOn, 0);
            check(packets.Count == 3 && Hex(packets[0]) == "a305000000" && Hex(packets[1]) == "a7" && Hex(packets[2]) == "a80100", "party frames: Do sends the base packets");

            ext.Receive(235, "{\"action\":\"state\",\"data\":{\"members\":[]}}");
            check(!party.InParty && !party.ViewerIsLeader && party.XpText() == "" && party.LeaderId == 0, "party frames: an empty list is no party");
            ext.Receive(235, "not json");
            ext.Receive(235, "{\"action\":\"other\",\"data\":{}}");
            check(!party.InParty, "party frames: other actions and bad text are ignored");
            sent.Clear();
            party.Close();
            check(Text(sent[0]) == "{\"action\":\"close\"}", "party frames: close");
            party.Close();
            check(sent.Count == 1, "party frames: close once");
        }

        static void Invitation(Action<bool, string> check)
        {
            check(PartyFrames.InviterOf("Mira has invited you to join her party.") == "Mira" && PartyFrames.InviterOf("hello") == null &&
                  PartyFrames.InviterOf("x has invited you to join his party.") == null && PartyFrames.InviterOf("Line\nbreak has invited you to ") == null,
                  "invitation: the leader's name in the server line");
            check(PartyFrames.RevokerOf("Mira has revoked his invitation.") == "Mira", "invitation: revoke line");

            var ext = new ExtOpcodes();
            double now = 1000;
            var party = new PartyFrames(ext) { Clock = () => now };
            party.OnServerText("Mira has invited you to join her party.");
            check(party.InvitationOpen(now) && party.InvitedBy == "Mira", "invitation: opens");
            party.OnServerText("Someone has revoked his invitation.");
            check(party.InvitedBy == "Mira", "invitation: another leader's revoke does not close it");
            party.OnServerText("mira has revoked her invitation.");
            check(!party.InvitationOpen(now), "invitation: the leader's revoke closes it");
            party.OnServerText("Mira has invited you to join her party.");
            check(!party.InvitationOpen(now + PartyFrames.InviteKeepMs + 1), "invitation: dropped after 5 minutes");
            party.OnServerText("Mira has invited you to join her party.");
            ext.Receive(235, "{\"action\":\"state\",\"data\":{\"members\":[{\"i\":1,\"n\":\"Me\",\"f\":17}]}}");
            check(!party.InvitationOpen(now), "invitation: joining a party closes it");

            var near = new List<KeyValuePair<uint, string>> { new KeyValuePair<uint, string>(4, "Bran"), new KeyValuePair<uint, string>(5, "Mira") };
            check(PartyFrames.FindLeader(near, "mira") == 5 && PartyFrames.FindLeader(near, "Zed") == 0, "invitation: the leader is found by name among creatures in view");
        }

        static void CharSelect(Action<bool, string> check)
        {
            check(ClassTable.Of(4).Text == "Warrior" && ClassTable.Of(8).Text == "Juggernaut (Warrior)" && ClassTable.Of(8).Base == 4 && ClassTable.Of(25).Text == "Sentinel (Templar)" &&
                  ClassTable.Of(2).Name == "Mystic" && ClassTable.Of(6).Name == "Illusionist" && ClassTable.Of(0).Name == "No class" && ClassTable.Of(99).Name == "Unknown class" &&
                  ClassTable.Of(17).Color == "#e0b84a", "charselect: classes, ascensions, retired ids");

            var list = new List<CharacterEntry>
            {
                new CharacterEntry { Name = "Alpha", Level = 12, Vocation = 4, World = "Cinders", Host = "10.0.0.1", Port = 7172, Outfit = new Outfit(128, 1, 2, 3, 4) },
                new CharacterEntry { Name = "Beta", Level = 300, Vocation = 14, World = "", Host = "10.0.0.1", Port = 7172 },
                new CharacterEntry { Name = "Gamma", Level = 0, Vocation = 20, World = "Cinders" },
            };
            var m = CharSelectModel.Build(list, "Beta");
            check(m.Cards.Count == 3 && m.Selected == 1 && m.Current.Name == "Beta" && m.Cards[1].ClassText == "Berserker (Warrior)" && m.Cards[1].World == "Cinders of Chaos" &&
                  m.Cards[0].Level == 12 && m.Cards[0].Outfit.LookType == 128 && m.Cards[0].Entry == list[0] && m.Cards[2].Class.Line == "Necromancer", "charselect: cards from the login list, last character selected");
            check(CharSelectModel.Build(list, "Nobody").Selected == 0 && CharSelectModel.Build(new List<CharacterEntry>()).Selected == -1 && CharSelectModel.Build(null).Cards.Count == 0, "charselect: first card by default, empty list");
            check(CharSelectModel.Move(0, 3, "Up") == 0 && CharSelectModel.Move(0, 3, "Down") == 1 && CharSelectModel.Move(1, 3, "End") == 2 && CharSelectModel.Move(2, 3, "Home") == 0 &&
                  CharSelectModel.Move(0, 10, "PageDown", 4) == 4 && CharSelectModel.Move(1, 10, "PageUp", 4) == 0 && CharSelectModel.Move(2, 3, "Right") == 2 && CharSelectModel.Move(0, 0, "Down") == -1,
                  "charselect: keyboard navigation stays inside the list");
            m.Navigate("Down");
            check(m.Selected == 2, "charselect: Navigate moves the selection");
            check(CharSelectModel.CreateUrl("play.cindersofchaos.com") == "https://cindersofchaos.com/createcharacter.php" && CharSelectModel.CreateUrl("example.org") == "https://example.org/createcharacter.php" &&
                  CharSelectModel.CreateUrl("127.0.0.1") == null && CharSelectModel.CreateUrl("localhost") == null && CharSelectModel.CreateUrl("") == null && CharSelectModel.CreateUrl("a b/c") == null,
                  "charselect: the create link opens the website page, none for a local server");
        }

        static void PlateChecks(Action<bool, string> check)
        {
            check(Plate.FillWidth(0, 100, 50) == 0 && Plate.FillWidth(1, 1000, 50) == 1 && Plate.FillWidth(50, 100, 50) == 25 && Plate.FillWidth(200, 100, 50) == 50 && Plate.FillWidth(5, 0, 50) == 0, "plate: fill width");
            check(Plate.Percent(0, 100) == 0 && Plate.Percent(1, 1000) == 1 && Plate.Percent(999, 1000) == 99 && Plate.Percent(1000, 1000) == 100 && Plate.Percent(5, 0) == 0, "plate: percent never rounds to a false full bar");
            check(Plate.Short(950) == "950" && Plate.Short(15300) == "15.3k" && Plate.Short(20000) == "20k" && Plate.Short(2500000) == "2.5m" && Plate.Short(3e9) == "3b", "plate: short numbers");
            check(Plate.BarText(15300, 20000, false) == "15.3k / 20k" && Plate.BarText(73, 100, true) == "73%", "plate: bar text, numbers and percent");

            check(Plate.ExperienceFor(1) == 0 && Plate.ExperienceFor(2) == 100 && Plate.ExperienceFor(8) == 4200 && Plate.ExperienceFor(100) == 15694800 &&
                  Plate.ExperienceFor(101) == 16180000, "plate: experience needed by the stock formula: " + Plate.ExperienceFor(100) + " " + Plate.ExperienceFor(101));
            ulong lo = Plate.ExperienceFor(100), hi = Plate.ExperienceFor(101);
            check(Plate.ExperiencePercent(lo, 100) == 0 && Plate.ExperiencePercent(lo + (hi - lo) / 2, 100) == 50 && Plate.ExperiencePercent(hi - 1, 100) == 99 &&
                  Plate.ExperiencePercent(hi + 5, 100) == 100 && Plate.ExperiencePercent(0, 100) == 0, "plate: experience percent to the next level");
            check(Plate.ExperienceToNext(lo, 100) == hi - lo && Plate.ExperienceToNext(hi, 100) == 0, "plate: experience still missing");
            check(Plate.LevelPercent(-3) == 0 && Plate.LevelPercent(42) == 42 && Plate.LevelPercent(250) == 100, "plate: the server's percent is kept inside 0-100");

            // 0xA0 carries level, experience and the percent: the parser keeps them for the plate, and its percent matches the formula
            var w = new World(DatFile.Parse(Program.SyntheticDat()));
            var parser = new GameParser(w);
            ulong xp = lo + (hi - lo) * 3 / 10;
            var b = new ByteWriter().U8(0xA0).U32(800).U32(1000).U32(5000).U32(8000).U32((uint)(xp & 0xFFFFFFFF)).U32((uint)(xp >> 32)).U16(100).U8((byte)Plate.ExperiencePercent(xp, 100));
            b.Zeros(10).U32(60).U32(200).U8(30).U8(30).U8(10).U8(100).U16(2520).U16(220).Zeros(7);
            parser.Parse(b.ToArray());
            check(parser.Level == 100 && parser.Experience == xp && parser.LevelPercent == 30 && parser.Health == 800 && parser.MaxMana == 200 &&
                  Plate.ExperiencePercent(parser.Experience, parser.Level) == parser.LevelPercent, "plate: 0xA0 gives level, experience and the percent (matches the formula)");
        }

        static void LocLabels(Action<bool, string> check)
        {
            // the party menu labels come from Core, so the source scan of Loc.T does not see them
            var keys = Enum.GetValues(typeof(PartyAction)).Cast<PartyAction>().Select(PartyMenu.Label).ToList();
            var missing = keys.Where(k => !LocStrings.PtBr.ContainsKey(k)).ToList();
            check(missing.Count == 0, "party: every menu label has a pt-BR text" + (missing.Count > 0 ? ": " + string.Join(" | ", missing) : ""));
        }
    }
}
