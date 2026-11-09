// Phase 30 (2026-11-09): the tester bot system checks (server/tools/tester_checks.py) driven through the Unity core, part 1: summons, pets, party and shared experience
// (O433, unity/README.md "Tester checks on the Unity core (phase 30)"). A tester check asks the TEST ONLY helper (server/tools/tester_helper.lua, `!tester ...`, answers as one server
// text line "[tester-helper] kind json") for facts about a system, and holds them to a rule. These scenarios do the same through a GameSession: the words go out as a plain say, the answer
// is read from the session's chat lines, the rules are Core/TesterChecks.cs (tested in Core.Tests Phase30Tests). What the Unity core adds is the player's view of the same facts: the
// own summons in the world (creature type 3), the party frames, the pets window model and the experience of the 0xA0 stats packet.
// The helper acts only for a character named "Tester Xxx" with the storage 7102900 = 1 and only while data/scripts/zz_tester_helper.lua is installed: every scenario skips with that reason
// otherwise. Opt-in by name (--scenario testsummons,testpets,testparty,testpartyxp,...), never in `all`; they need no staff right.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using Chaos.Core;

namespace Chaos.Core.LiveCheck
{
    public sealed partial class LiveRun
    {
        public static readonly string[] TesterScenarios = { "testsummons", "testpets", "testparty", "testpartyxp", "testrift", "testwaystone", "testloot", "testchests", "testspellquest", "testunique", "testdual", "testauto" };

        const string NoHelper = "the tester helper did not answer: the character must be named 'Tester Xxx' with the storage 7102900 = 1 and data/scripts/zz_tester_helper.lua (TEST ONLY, server/tools/tester_helper.lua) must be installed";

        bool testerInfoChecked;

        // ------------------------------------------------------------------------------------ the helper, as a player talks to it
        /// <summary>Says `!tester COMMAND` and waits for the helper's answer line of that kind ("[tester-helper] KIND json"). A helper "error" line comes back as {err}. Null when nothing came in time.</summary>
        Dictionary<string, object> TSay(LiveClient who, string command, string kind, int waitMs = 6000, Action tick = null)
        {
            int from = who.Said.Count;
            who.S.Say("!tester " + command);
            Dictionary<string, object> found = null;
            WaitFor(waitMs, () =>
            {
                tick?.Invoke();
                for (int i = from; i < who.Said.Count; i++)
                {
                    var l = who.Said[i];
                    if (l.Who.Length != 0) continue;
                    if (!TesterChecks.TryParseLine(l.Text, out string k, out var d)) continue;
                    if (k == kind) { found = d; return true; }
                    if (k == "error") { found = d; return true; }
                }
                return false;
            });
            return found;
        }

        /// <summary>The teleports of the helper: "town" (the temple) and "hunt" (the hunt spot). True when it answered without an error; why says what not.</summary>
        bool TGo(string place, out string why)
        {
            var a = TSay(me, place, place, 6000);
            why = a == null ? "no helper answer" : TesterChecks.Err(a);
            if (a != null && why.Length == 0) Pump(1200, () => false);   // the session follows the teleport (a new map)
            return a != null && why.Length == 0;
        }

        /// <summary>The class (vocation name) of the logged in character as the Auto setup data names it.</summary>
        string TClass()
        {
            int voc = s.Spells.Vocation != 0 ? s.Spells.Vocation : vocation;
            var c = HelperRotation.ClassOf(voc);
            return c != null ? c.Name : "";
        }

        /// <summary>The first thing of every tester scenario: the character is a tester (the helper's name rule) and the helper answers `!tester info` with the creature id the Unity world holds as the player's own.</summary>
        bool TesterReady(ScenarioResult r)
        {
            if (!TesterChecks.Eligible(me.Character, 1)) { r.Skip("the character is not named 'Tester Xxx' (the helper acts for no other): " + NoHelper); return false; }
            var info = TSay(me, "info", "info", 7000);
            if (info == null || TesterChecks.Err(info).Length > 0) { r.Skip(NoHelper); return false; }
            long cid = TesterChecks.Int(info, "cid");
            if (cid != world.PlayerId) { r.Fail("the helper's creature id for the tester (" + cid + ") is not the id the Unity world holds for the player (" + world.PlayerId + ")"); return false; }
            if (!testerInfoChecked)
            {
                testerInfoChecked = true;
                var pos = TesterChecks.Obj(info, "pos");
                r.Note("helper answered: creature id equals the Unity player's, level " + TesterChecks.Int(info, "level") + " (Unity " + s.Parser.Level + "), position " + TesterChecks.Int(pos, "x") + "," + TesterChecks.Int(pos, "y") + "," + TesterChecks.Int(pos, "z") + " (Unity " + P(me.Pos) + ")");
            }
            return true;
        }

        string PartnerTester(ScenarioResult r)
        {
            string err = EnsurePartner();
            if (err != null) return err;
            if (!TesterChecks.Eligible(partner.Character, 1)) return "the partner is not named 'Tester Xxx' (the helper's party commands act for testers only)";
            var info = TSay(partner, "info", "info", 7000);
            if (info == null || TesterChecks.Err(info).Length > 0) return "the helper did not answer the partner (" + NoHelper + ")";
            return null;
        }

        /// <summary>The creatures the Unity world shows as the player's own summons (creature type 3).</summary>
        List<Creature> OwnSummons() => world.Creatures.Values.Where(c => c.Type == 3 && c.Position.X > 0).ToList();

        /// <summary>Looks at the summons of the tester every two seconds for `seconds`: the problems of every look (each once) and the last good answer.</summary>
        List<string> WatchSummons(double seconds, out Dictionary<string, object> last, Action<Dictionary<string, object>> each = null)
        {
            var problems = new List<string>();
            last = null;
            long end = Tick + (long)(seconds * 1000);
            while (Tick <= end && s.Closed == null)
            {
                var snap = TSay(me, "summons", "summons", 6000);
                if (snap != null && TesterChecks.Err(snap).Length == 0)
                {
                    last = snap;
                    foreach (var p in TesterChecks.SnapshotProblems(snap)) if (!problems.Contains(p)) problems.Add(p);
                    each?.Invoke(snap);
                }
                Pump((int)(TesterChecks.LookSeconds * 1000), () => false);
            }
            return problems;
        }

        /// <summary>The summons the helper lists that the Unity world does not show as own summons: the player's view must agree with the server's.</summary>
        string UnityMissing(Dictionary<string, object> snap)
        {
            var missing = new List<string>();
            foreach (var sm in TesterChecks.Rows(snap, "summons"))
            {
                long id = TesterChecks.Int(sm, "id");
                if (!world.Creatures.TryGetValue((uint)id, out var c) || c.Position.X <= 0) missing.Add(TesterChecks.Str(sm, "name", "summon") + " #" + id + " is not in the Unity world");
                else if (c.Type != 3) missing.Add(TesterChecks.Str(sm, "name", "summon") + " #" + id + " is creature type " + c.Type + " in the Unity world, not an own summon (3)");
            }
            return string.Join("; ", missing);
        }

        // ------------------------------------------------------------------------------------ beastmaster_wolf, necro_minions
        void ScTSummons(ScenarioResult r)
        {
            if (!TesterReady(r)) return;
            string cls = TClass();
            if (!TesterChecks.Summoners.TryGetValue(cls, out var sm)) { r.Skip("class '" + cls + "' has no summon check (Beastmaster: beastmaster_wolf, Necromancer, Lich and Bone Lord: necro_minions)"); return; }
            var mark = Mark.Of(me);
            if (!TGo("hunt", out string why)) { r.Skip("the helper did not bring the bot to its hunt spot (" + Cut80(why) + ")"); return; }
            Pump(1500, () => false);
            s.Say(sm.Words);
            Pump(3000, () => false);
            var snap = TSay(me, "summons", "summons", 6000);
            if (snap == null || TesterChecks.Err(snap).Length > 0)
            {
                r.Note("last server lines: " + string.Join(" | ", me.ServerTexts(0).TakeLast(4).Select(t => Cut80(t))));
                r.Skip("no answer to !tester summons" + (snap != null ? " (" + Cut80(TesterChecks.Err(snap)) + ")" : ""));
                return;
            }
            int count = (int)TesterChecks.Int(snap, "count");
            if (count == 0) { r.Skip("no summon after '" + sm.Words + "' (level " + s.Parser.Level + ": not learned, no mana or on cooldown)"); return; }
            if (count > sm.Cap + 1) { r.Fail(count + " summons after one cast, the cap is " + sm.Cap); return; }
            var problems = new StringBuilder();
            string seen = UnityMissing(snap);
            r.Note(sm.Check + ": " + count + " summon(s) after '" + sm.Words + "'; the Unity world shows " + OwnSummons().Count + " own summon(s) (type 3)");
            if (seen.Length > 0) problems.Append("Unity view: " + seen + "; ");
            var bad = WatchSummons(TesterChecks.WatchSeconds, out var last);
            if (bad.Count > 0) problems.Append(string.Join("; ", bad.Take(3))).Append("; ");
            // teleport away and back (town portal, leash): the engine lists everybody in sight again
            string afterTeleport = "";
            if (problems.Length == 0 && TGo("town", out _))
            {
                Pump(3000, () => false);
                TGo("hunt", out _);
                Pump(3000, () => false);
                var bad2 = WatchSummons(6.0, out var last2);
                if (bad2.Count > 0) problems.Append("after a teleport: " + string.Join("; ", bad2.Take(3))).Append("; ");
                afterTeleport = " and after a teleport (" + (last2 != null ? TesterChecks.Int(last2, "count") : 0) + " summon(s) left, Unity shows " + OwnSummons().Count + ")";
            }
            problems.Append(mark.Diff(me, "primary"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass(count + " summon(s) of the " + cls + ", the Unity world agrees (own summons, type 3), no wrong target in " + (int)TesterChecks.WatchSeconds + " s" + afterTeleport);
        }

        static string Cut80(string t) => t != null && t.Length > 80 ? t.Substring(0, 80) : t ?? "";

        // ------------------------------------------------------------------------------------ pets
        void ScTPets(ScenarioResult r)
        {
            if (!TesterReady(r)) return;
            var mark = Mark.Of(me);
            var pets = s.Pets;
            pets.State = null;
            pets.Show();
            if (!WaitFor(6000, () => pets.State != null)) { pets.Hide(); r.Skip("no answer from the pets window (below its level gate or not installed)"); return; }
            var owned = pets.Entries().Where(e => e.Owned).Select(e => e.Key).ToList();
            r.Note("pets window: " + pets.Entries().Count + " entries, " + owned.Count + " owned");
            if (owned.Count == 0)
            {
                // a pet of the helper (ChaosPets.grant): without one the check never ran
                var g = TSay(me, "pet", "pet", 6000);
                if (g != null && TesterChecks.True(g, "owns"))
                {
                    pets.State = null;
                    pets.Show();
                    WaitFor(6000, () => pets.State != null);
                    owned = pets.Entries().Where(e => e.Owned).Select(e => e.Key).ToList();
                    if (owned.Count == 0 && TesterChecks.Str(g, "key").Length > 0) owned.Add(TesterChecks.Str(g, "key"));
                    r.Note("the helper gave a pet: " + owned.Count + " owned in the window now");
                }
            }
            if (owned.Count == 0) { pets.Hide(); r.Skip("the bot owns no pet"); return; }
            if (!TGo("hunt", out string why)) { pets.Hide(); r.Skip("the helper did not bring the bot to its hunt spot (" + Cut80(why) + ")"); return; }
            pets.Summon(owned[0]);
            Pump(3000, () => false);
            var live = TSay(me, "pet", "pet", 6000) ?? new Dictionary<string, object>();
            long cid = TesterChecks.Int(live, "cid");
            if (cid == 0) { pets.Dismiss(); pets.Hide(); r.Skip("the pet did not come out (" + TesterChecks.PetRestText(live) + ")"); return; }
            var snap = TSay(me, "summons", "summons", 6000);
            if (snap == null || TesterChecks.Err(snap).Length > 0) { pets.Hide(); r.Skip("no answer to !tester summons"); return; }
            var problems = new StringBuilder();
            if (!TesterChecks.Rows(snap, "summons").Any(x => TesterChecks.Int(x, "id") == cid))
            {
                pets.Dismiss(); pets.Hide();
                r.Fail("the pet (creature " + cid + ") is out but not a summon of the bot");
                return;
            }
            // the player's view: the pet is an own summon in the world, and the pets window model names it as the active one
            string seen = UnityMissing(snap);
            if (seen.Length > 0) problems.Append("Unity view: " + seen + "; ");
            var status = pets.StatusText();
            r.Note("pet out: creature id " + cid + " seen by Unity as type " + (world.Creatures.TryGetValue((uint)cid, out var pc) ? pc.Type.ToString(CultureInfo.InvariantCulture) : "(not in the world)") + "; window status text '" + status + "'");
            var bad = WatchSummons(10.0, out _);
            if (bad.Count > 0) problems.Append(string.Join("; ", bad.Take(3))).Append("; ");
            pets.Dismiss();
            Pump(1500, () => false);
            var after = TSay(me, "summons", "summons", 6000);
            pets.Hide();
            bool goneInUnity = !world.Creatures.TryGetValue((uint)cid, out var pc2) || pc2.Position.X <= 0;
            if (after != null && TesterChecks.Rows(after, "summons").Any(x => TesterChecks.Int(x, "id") == cid)) problems.Append("the pet is still out after dismiss; ");
            if (!goneInUnity) problems.Append("the Unity world still shows the pet after dismiss; ");
            problems.Append(mark.Diff(me, "primary"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("pet " + owned[0] + ": out as an own summon (server and Unity), no wrong target in 10 s, gone after dismiss (server and Unity)");
        }

        // ------------------------------------------------------------------------------------ party
        /// <summary>Forms a party of the tester and its partner through the packets a client sends (invite 0xA3, join 0xA4). Returns the helper's party answer; problems get the Unity frame facts.</summary>
        Dictionary<string, object> TFormParty(StringBuilder problems, ScenarioResult r)
        {
            // out of any party an earlier run left (the helper removes a member where the leave packet is refused in a fight)
            TSay(me, "party leave", "party", 4000);
            TSay(partner, "party leave", "party", 4000);
            Pump(800, () => false);
            me.S.Party.Do(PartyAction.Invite, partner.World.PlayerId);
            Pump(1000, () => false);
            partner.S.Party.Do(PartyAction.Join, me.World.PlayerId);
            Pump(3000, () => false);
            var p = TSay(me, "party", "party", 6000);
            if (p == null || TesterChecks.Err(p).Length > 0) return p;
            r.Note("helper sees a party of " + TesterChecks.Int(p, "size") + "; Unity frames: " + me.S.Party.Members.Count + " (leader) and " + partner.S.Party.Members.Count + " (member) member(s)");
            if (TesterChecks.Int(p, "size") >= 2 && (me.S.Party.Members.Count != 2 || partner.S.Party.Members.Count != 2))
                problems.Append("the helper sees " + TesterChecks.Int(p, "size") + " members but the Unity party frames hold " + me.S.Party.Members.Count + " and " + partner.S.Party.Members.Count + "; ");
            return p;
        }

        void TLeaveParty()
        {
            // the packet first (the player's way), then the helper (the engine refuses the packet in a fight)
            partner?.S.Party.Do(PartyAction.Leave, 0);
            me.S.Party.Do(PartyAction.Leave, 0);
            Pump(500, () => false);
            if (partner != null) TSay(partner, "party leave", "party", 4000);
            TSay(me, "party leave", "party", 4000);
        }

        void ScTParty(ScenarioResult r)
        {
            if (!TesterReady(r)) return;
            string err = PartnerTester(r);
            if (err != null) { r.Skip(err); return; }
            var markA = Mark.Of(me);
            var markB = Mark.Of(partner);
            var problems = new StringBuilder();
            var p = TFormParty(problems, r);
            if (p == null || TesterChecks.Err(p).Length > 0) { TLeaveParty(); r.Skip("no answer to !tester party"); return; }
            if (TesterChecks.Int(p, "size") < 2)
            {
                TLeaveParty();
                r.Fail("invited the partner, it joined, the party has " + TesterChecks.Int(p, "size") + " member(s) (Unity frames " + me.S.Party.Members.Count + " and " + partner.S.Party.Members.Count + ")");
                return;
            }
            string detail = "party of " + TesterChecks.Int(p, "size");
            string cls = TClass();
            if (TesterChecks.Summoners.TryGetValue(cls, out var sm))
            {
                s.Say(sm.Words);
                Pump(3000, () => false);
                var bad = WatchSummons(12.0, out _);
                if (bad.Count > 0) problems.Append("in a party: " + string.Join("; ", bad.Take(3))).Append("; ");
                else detail += ", the " + cls + "'s summons keep their sides";
            }
            TLeaveParty();
            Pump(3000, () => false);
            var after = TSay(me, "party", "party", 6000);
            if (after != null && TesterChecks.Err(after).Length == 0 && TesterChecks.Int(after, "size") >= 2) problems.Append("left the party, the helper still sees " + TesterChecks.Int(after, "size") + " members; ");
            if (me.S.Party.InParty || partner.S.Party.InParty) problems.Append("left the party, the Unity frames still hold " + me.S.Party.Members.Count + " and " + partner.S.Party.Members.Count + " members; ");
            problems.Append(markA.Diff(me, "primary"));
            problems.Append(markB.Diff(partner, "partner"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass(detail + " (helper and Unity frames agree), gone after leaving");
        }

        // ------------------------------------------------------------------------------------ party_xp
        void ScTPartyXp(ScenarioResult r)
        {
            if (!TesterReady(r)) return;
            string err = PartnerTester(r);
            if (err != null) { r.Skip(err); return; }
            var markA = Mark.Of(me);
            var markB = Mark.Of(partner);
            var problems = new StringBuilder();
            bool decided;
            try { decided = PartyXpBody(r, problems); }
            finally
            {
                if (s.Closed == null)
                {
                    me.S.Party.Do(PartyAction.ShareOff, 0);
                    Pump(300, () => false);
                    TLeaveParty();
                    Pump(800, () => false);
                    TGo("hunt", out _);
                }
            }
            if (decided) return;   // the body set a skip
            problems.Append(markA.Diff(me, "primary"));
            problems.Append(markB.Diff(partner, "partner"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("shared experience switched on in the temple, the share the rule gives (class line bonus of the party frames) matches the engine, its verdict follows the rules, a real shared kill paid what the rule says, and the Unity experience (0xA0) and party frame agree");
        }

        /// <summary>The checks of party_xp. True when the scenario was decided (a skip); false: the problems say pass or fail.</summary>
        bool PartyXpBody(ScenarioResult r, StringBuilder problems)
        {
            var p = TFormParty(problems, r);
            if (p == null || TesterChecks.Err(p).Length > 0) { r.Skip("no answer to !tester party"); return true; }
            if (TesterChecks.Int(p, "size") < 2) { r.Skip("the party was not formed (" + TesterChecks.Int(p, "size") + " member(s))"); return true; }
            if (TesterChecks.Str(p, "leader") != me.Character) { r.Skip("the primary is not the leader of the party"); return true; }
            if (!TesterChecks.Has(p, "shareActive")) { r.Skip("the helper does not report the shared experience (old helper file)"); return true; }
            // the engine takes the switch in a fight only in a protection zone: the leader switches in the temple
            TGo("town", out _);
            me.S.Party.Do(PartyAction.ShareOn, 0);
            Pump(3000, () => false);
            var first = TSay(me, "party", "party", 6000);
            if (first != null && TesterChecks.Err(first).Length == 0 && !TesterChecks.True(first, "shareActive") && !TesterChecks.True(first, "leaderBlocked"))
            {
                me.S.Party.Do(PartyAction.ShareOn, 0);
                Pump(3000, () => false);
                first = TSay(me, "party", "party", 6000);
            }
            Pump(3000, () => false);
            var second = TSay(me, "party", "party", 6000);
            if (first == null || second == null || TesterChecks.Err(first).Length > 0 || TesterChecks.Err(second).Length > 0) { r.Skip("no answer to !tester party after the switch"); return true; }
            if (!TesterChecks.True(first, "shareActive") && !TesterChecks.True(second, "shareActive") && TesterChecks.True(first, "leaderBlocked")) { r.Skip("the engine refused the switch: the leader is in a fight outside a protection zone"); return true; }
            var a = TesterChecks.PartyShareProblems(first);
            var b = TesterChecks.PartyShareProblems(second);
            var bad = a.Where(x => b.Contains(x)).ToList();   // the engine's own update lags a tick: only what both looks saw
            r.Note("share: active " + TesterChecks.True(second, "shareActive") + ", enabled " + TesterChecks.True(second, "shareEnabled") + ", " + TesterChecks.Int(second, "lines") + " class line(s), " + TesterChecks.Int(second, "size") + " members, 1000 xp pays " + TesterChecks.Int(second, "shareOf1000") + " (rule " + TesterChecks.ShareExpected((int)TesterChecks.Int(second, "lines"), (int)TesterChecks.Int(second, "size")) + "); Unity xp state " + me.S.Party.XpOn + " / " + partner.S.Party.XpOn + ", text '" + me.S.Party.XpText() + "'");
            if (bad.Count > 0) { problems.Append(string.Join("; ", bad.Take(3))).Append("; "); return false; }
            // the Unity party frames follow the engine's switch (the 0xA8 round trip)
            // party_xp_core.lua: on 0 = switched off, 1 = working (the frame shows the bonus), 2 = switched on but not working ("XP off")
            int wantOn = TesterChecks.True(second, "shareActive") ? (TesterChecks.True(second, "shareEnabled") ? 1 : 2) : 0;
            WaitFor(5000, () => me.S.Party.XpOn == wantOn);
            if (me.S.Party.XpOn != wantOn) problems.Append("the engine says switched " + (wantOn == 0 ? "off" : "on") + " and " + (wantOn == 1 ? "working" : "not working") + " (frame state " + wantOn + "), the Unity party frame reads state " + me.S.Party.XpOn + "; ");
            else r.Note("the Unity party frame reads state " + wantOn + " like the engine (" + (wantOn == 1 ? "working, " + me.S.Party.XpText() : wantOn == 2 ? "on, not working: 'XP off'" : "off") + ")");
            long pays = TesterChecks.Int(second, "shareOf1000");
            // a real kill: the leader back at its hunt (no kill in a protection zone), one kill shared, one solo
            TGo("hunt", out _);
            double xp0 = me.S.Parser.Experience, xp1 = partner.S.Parser.Experience;
            var k = TSay(me, "party kill", "partykill", 18000);
            Pump(1500, () => false);
            var kp = new List<string>();
            string skip = TesterChecks.SharedKill(k, pays, kp);
            var sh = TesterChecks.Obj(k, "shared"); var so = TesterChecks.Obj(k, "solo");
            r.Note("kill: shared leader/partner " + TesterChecks.Int(sh, "leader") + "/" + TesterChecks.Int(sh, "partner") + " (share " + (TesterChecks.True(sh, "enabled") ? "working" : "off") + "), solo leader/partner " + TesterChecks.Int(so, "leader") + "/" + TesterChecks.Int(so, "partner") + "; Unity experience +" + (long)(me.S.Parser.Experience - xp0) + " (leader) and +" + (long)(partner.S.Parser.Experience - xp1) + " (partner)");
            if (kp.Count > 0) problems.Append(string.Join("; ", kp.Take(3))).Append("; ");
            else if (skip == null)
            {
                // the stats packets (0xA0) the Unity client reads must carry what the kills paid
                long lead = TesterChecks.Int(sh, "leader") + TesterChecks.Int(so, "leader"), mate = TesterChecks.Int(sh, "partner");
                if ((long)(me.S.Parser.Experience - xp0) < lead) problems.Append("the helper says the leader earned " + lead + " in the two kills, the Unity client's experience rose " + (long)(me.S.Parser.Experience - xp0) + "; ");
                if ((long)(partner.S.Parser.Experience - xp1) < mate) problems.Append("the helper says the partner earned " + mate + " from the shared kill, the Unity client's experience rose " + (long)(partner.S.Parser.Experience - xp1) + "; ");
            }
            if (problems.Length == 0 && skip != null) { r.Skip(skip); return true; }
            return false;
        }
    }
}
