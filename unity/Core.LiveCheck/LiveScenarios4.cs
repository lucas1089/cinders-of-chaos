// Endgame scenarios of the live check (O433 phase 24): a rift of a party (partyrift), a rift above tier 1 (rifttier, the phase 23 run with a tier and fixed modifiers),
// a failed rift (riftfail), an Omen arena (omen), the Sealed Coffer (coffer) and the modal windows of other senders (moremodals). Same rules as LiveScenarios.cs: opt-in by
// --scenario, a time limit, a pass, fail or skip with the reason, names scrubbed from the reports, and what was opened is closed again.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace Chaos.Core.LiveCheck
{
    public sealed partial class LiveRun
    {
        // ------------------------------------------------------------------------------------ helpers
        /// <summary>The primary (leader) invites the partner and the partner joins. Null on success, else why not.</summary>
        string FormParty()
        {
            var pCreature = Seeing(me, partner.Character);
            var mCreature = Seeing(partner, me.Character);
            if (pCreature == null || mCreature == null) return "the characters do not see each other";
            if (me.S.Party.InParty) me.S.Party.Do(PartyAction.Leave, 0);
            if (partner.S.Party.InParty) partner.S.Party.Do(PartyAction.Leave, 0);
            Pump(800, () => false);
            me.S.Party.Do(PartyAction.Invite, pCreature.Id);
            if (!WaitFor(5000, () => partner.S.Party.InvitedBy.Length > 0)) return "the partner got no invitation";
            partner.S.Party.Do(PartyAction.Join, mCreature.Id);
            if (!WaitFor(6000, () => me.S.Party.InParty && partner.S.Party.InParty && me.S.Party.Members.Count == 2 && partner.S.Party.Members.Count == 2))
                return "joining did not complete (frames " + me.S.Party.Members.Count + "/" + partner.S.Party.Members.Count + ")";
            return null;
        }

        void LeavePartyBoth()
        {
            if (partner != null && partner.S.Closed == null && partner.S.Party.InParty) partner.S.Party.Do(PartyAction.Leave, 0);
            Pump(800, () => false);
            if (me.S.Closed == null && me.S.Party.InParty) me.S.Party.Do(PartyAction.Leave, 0);
            Pump(600, () => false);
        }

        /// <summary>The server texts of a client from line `from` on, without the staff helper replies, cut to 170 characters.</summary>
        static List<string> GameTexts(LiveClient c, int from)
        {
            return c.ServerTexts(from).Where(t => !t.StartsWith("rkill ", StringComparison.Ordinal) && !t.StartsWith("rgo ", StringComparison.Ordinal) && !t.StartsWith("rtime ", StringComparison.Ordinal))
                .Select(t => t.Length > 170 ? t.Substring(0, 170) + "..." : t).ToList();
        }

        bool PartnerFarFromRift(Pos before) => partner.S.Closed == null && (PathFinder.Cheb(partner.Pos, before) > 30 || partner.Pos.Z != before.Z);

        /// <summary>The rift HUD of a client in one line (tier, kills, boss and state, lives, result).</summary>
        static string HudLine(RiftHud h) => "tier " + h.Tier + ", " + h.Killed + " of " + h.BossAt + " (total " + h.Total + "), boss '" + h.Boss + "', state '" + h.State + "', lives " + h.Lives + "/" + h.LivesMax +
                                            ", result '" + h.Result + "', exit in " + h.ExitIn + " s";

        // ------------------------------------------------------------------------------------ rifttier, omen
        void ScRiftTier(ScenarioResult r) => RiftBossRun(r, o.RiftTier, o.RiftMods, false);

        void ScOmen(ScenarioResult r) => RiftBossRun(r, 1, null, true);

        // ------------------------------------------------------------------------------------ partyrift
        void ScPartyRift(ScenarioResult r)
        {
            string err = EnsurePartner();
            if (err != null) { r.Skip(err); return; }
            if (serverToClient == null) { r.Skip("no items.otb: the rift key and the chest ids come from it"); return; }
            err = MeetPartner();
            if (err != null) { r.Skip("the two characters cannot be brought together: " + err); return; }
            var markA = Mark.Of(me);
            var markB = Mark.Of(partner);
            var problems = new StringBuilder();
            var rift = s.Progress.Rift;
            var prift = partner.S.Progress.Rift;
            var pp = partner.S.Parser;
            if (PathFinder.Cheb(me.Pos, partner.Pos) > 6 && !WalkTo(partner, me.Pos, 2, o.ScenarioMs, false, out string closer)) r.Note("the partner could not come closer: " + closer);
            r.Note("both characters " + PathFinder.Cheb(me.Pos, partner.Pos) + " tiles apart (the rift takes party members within 8 sqm on the same floor)");
            err = FormParty();
            if (err != null) { r.Skip("the party could not be formed: " + err); return; }
            var partnerBefore = partner.Pos;
            int pTexts0 = partner.Said.Count, mTexts0 = me.Said.Count;
            var extBefore = ExtPackets();
            int bad0 = ExtBad();
            string mods = string.IsNullOrEmpty(o.RiftMods) ? "vitality:20" : o.RiftMods;
            prift.Hide();
            bool done = false;
            Pos before = me.Pos;
            try
            {
                if (!OpenRift(r, out before, out int rift0, 1, mods)) return;
                // 1. both get the HUD, the same run, shared lives, both moved in
                bool pin = WaitFor(8000, () => prift.Active);
                Pump(1500, () => false);
                r.Note("primary HUD: " + HudLine(rift) + ", mods [" + string.Join("; ", rift.Mods.Select(RiftHud.ModLine)) + "]");
                r.Note("partner HUD: " + (pin ? HudLine(prift) : "none (opcode 228 start never came)"));
                if (!pin) problems.Append("the partner got no rift HUD (opcode 228 start) although in the party within 8 sqm; ");
                else
                {
                    if (prift.Tier != rift.Tier || prift.Total != rift.Total || prift.BossAt != rift.BossAt || prift.Theme != rift.Theme) problems.Append("the two HUDs describe different runs (tier " + rift.Tier + "/" + prift.Tier + ", total " + rift.Total + "/" + prift.Total + ", guardian at " + rift.BossAt + "/" + prift.BossAt + "); ");
                    if (prift.Lives != rift.Lives || prift.LivesMax != rift.LivesMax) problems.Append("the shared lives differ (" + rift.Lives + "/" + rift.LivesMax + " against " + prift.Lives + "/" + prift.LivesMax + "); ");
                    if (rift.LivesMax <= 3) r.Note("shared lives " + rift.LivesMax + " for two players: the party bonus (+1 per extra player) is not on the HUD");
                }
                bool pmoved = PartnerFarFromRift(partnerBefore);
                r.Note("partner position " + P(partnerBefore) + " to " + P(partner.Pos) + ", " + PathFinder.Cheb(partner.Pos, me.Pos) + " tiles from the primary");
                if (!pmoved) problems.Append("the partner was not taken into the rift (still at " + P(partner.Pos) + "); ");
                else if (partner.Pos.Z != me.Pos.Z || PathFinder.Cheb(partner.Pos, me.Pos) > 5) problems.Append("the partner arrived " + PathFinder.Cheb(partner.Pos, me.Pos) + " tiles from the primary (floor " + partner.Pos.Z + "/" + me.Pos.Z + "); ");
                var startTexts = GameTexts(partner, pTexts0);
                r.Note("partner's server lines on entering: " + startTexts.Count + (startTexts.Count > 0 ? " [" + string.Join(" | ", startTexts.Take(4)) + "]" : ""));
                if (!startTexts.Any(t => t.IndexOf("rift tier", StringComparison.OrdinalIgnoreCase) >= 0)) problems.Append("the partner got no 'Rift tier' line from the server; ");
                // 2. the packs, hit by both: the staff command hits as the primary, '/rkill p' as the partner (the kill credit goes to the one who hits)
                long exp0 = (long)pp.Experience, expM0 = (long)me.S.Parser.Experience;
                int texts0 = pp.ExpGainTexts;
                int packs0 = rift.Killed, waves = 0;
                long limit = Tick + Math.Max(150000, o.ScenarioMs * 3);
                while (Tick < limit && s.Closed == null && partner.S.Closed == null && rift.Boss != "alive" && rift.Boss != "dead" && rift.Result.Length == 0)
                {
                    s.Say(waves % 2 == 1 ? o.RiftKill + " p" : o.RiftKill);
                    waves++;
                    Pump(1500, () => rift.Boss == "alive" || rift.Boss == "dead" || rift.Result.Length > 0 || s.Closed != null);
                    if (waves == 3 && rift.Killed == packs0)
                    {
                        r.Skip("the staff kill command '" + o.RiftKill + "' killed nothing in 3 tries: this server has no such command (a local-only revscript, README \"Rift boss and modal windows (phase 23)\")");
                        return;
                    }
                }
                Pump(1500, () => false);
                r.Note("packs: " + waves + " wave(s), kills " + packs0 + " to " + rift.Killed + " of " + rift.BossAt + "; partner HUD kills " + prift.Killed + ", boss '" + prift.Boss + "'");
                if (rift.Boss != "alive") { problems.Append("the guardian did not come within the time limit (kills " + rift.Killed + " of " + rift.BossAt + "); "); goto finish; }
                if (prift.Killed != rift.Killed || prift.Boss != rift.Boss) problems.Append("the HUDs disagree after the packs (kills " + rift.Killed + "/" + prift.Killed + ", boss '" + rift.Boss + "'/'" + prift.Boss + "'); ");
                long exp1 = (long)pp.Experience, expM1 = (long)me.S.Parser.Experience;
                r.Note("kill credit: partner experience " + exp0 + " to " + exp1 + " (" + (pp.ExpGainTexts - texts0) + " experience line(s), last " + pp.LastExpGain + "); primary experience " + expM0 + " to " + expM1 +
                       " (a staff character gains none)");
                if (pp.ExpGainTexts - texts0 == 0 && exp1 <= exp0) r.Note("the partner got no experience from the kills it hit (the rift's experience cap, or no experience for a pack monster)");
                // 3. the guardian, hit by the partner
                // no walk to the guardian: the first kill command of the guardian stage clears every other monster of the run at once (the partner stands at the entrance)
                var bossBefore = new Dictionary<byte, int>(pp.Seen);
                int kills = 0;
                long limit2 = Tick + 90000;
                while (Tick < limit2 && s.Closed == null && rift.Result.Length == 0)
                {
                    s.Say(kills < 3 ? o.RiftKill + " p" : o.RiftKill);
                    kills++;
                    Pump(2000, () => rift.Result.Length > 0 || s.Closed != null);
                }
                Pump(1500, () => prift.Result.Length > 0);
                r.Note("guardian '" + rift.BossName + "': " + kills + " kill command(s); primary " + HudLine(rift) + "; partner " + HudLine(prift));
                r.Note("partner packets since the guardian: [" + PacketDiff(pp, bossBefore) + "]");
                if (rift.Result != "success") { problems.Append("the rift did not end in success (result '" + rift.Result + "'); "); goto finish; }
                if (prift.Result != "success" || prift.Boss != "dead" || prift.State != "success") problems.Append("the partner's HUD did not show the success (result '" + prift.Result + "', boss '" + prift.Boss + "', state '" + prift.State + "'); ");
                if (prift.ExitIn <= 0) problems.Append("the partner's end message gives no exit time; ");
                // 4. the reward chest: every finisher opens it once
                Pump(1200, () => false);
                s.Say(o.RiftGo + " chest");
                partner.S.Say(o.RiftGo + " chest");
                Pump(3000, () => false);
                var ids = RiftChestClientIds();
                int rewards = 0;
                foreach (var who in new[] { (c: me, name: "primary"), (c: partner, name: "partner") })
                {
                    var chest = FindChest(who.c, ids);
                    if (chest == null) { problems.Append("the " + who.name + " sees no reward chest (client ids " + string.Join(",", ids) + ") at " + P(who.c.Pos) + "; "); continue; }
                    var (tile, stack, cid) = chest.Value;
                    int t0 = who.c.Said.Count;
                    var seenC = new Dictionary<byte, int>(who.c.S.Parser.Seen);
                    if (PathFinder.Cheb(tile, who.c.Pos) > 1) WalkTo(who.c, tile, 1, 15000, false, out _);
                    who.c.S.UseItem(tile, (ushort)cid, (byte)stack);
                    bool got = WaitFor(8000, () => who.c.ServerTexts(t0).Any(t => t.IndexOf("gold to your bank", StringComparison.OrdinalIgnoreCase) >= 0));
                    Pump(1200, () => false);
                    var tx = GameTexts(who.c, t0);
                    r.Note(who.name + " opened the chest at " + P(tile) + ": " + (got ? "reward text" : "no reward text") + " [" + string.Join(" | ", tx.Take(3)) + "]; packets [" + PacketDiff(who.c.S.Parser, seenC) + "]");
                    if (got) rewards++; else problems.Append("the " + who.name + " got no reward text from the chest; ");
                }
                // a second use by the same finisher: the server refuses ("You already took your share")
                {
                    var chest = FindChest(me, ids);
                    if (chest != null)
                    {
                        int t0 = me.Said.Count;
                        s.UseItem(chest.Value.tile, (ushort)chest.Value.id, (byte)chest.Value.stack);
                        Pump(1500, () => false);
                        var again = GameTexts(me, t0);
                        r.Note("the primary uses the chest again: " + (again.Count > 0 ? string.Join(" | ", again.Take(2)) : "no text"));
                        if (again.Any(t => t.IndexOf("gold to your bank", StringComparison.OrdinalIgnoreCase) >= 0)) problems.Append("the same finisher was paid twice; ");
                    }
                }
                // 5. the exit: both go back
                bool out1 = WaitFor(Math.Max(15000, (int)(rift.ExitIn * 1000) + 8000), () => (!PathFarFromRift(before) && PartnerFarFromRift(before) == false && !(PathFinder.Cheb(partner.Pos, partnerBefore) > 30)) || s.Closed != null || partner.S.Closed != null);
                Pump(1200, () => false);
                r.Note("exit: primary " + P(me.Pos) + " (was " + P(before) + "), partner " + P(partner.Pos) + " (was " + P(partnerBefore) + ")");
                if (PathFarFromRift(before)) problems.Append("the primary was not sent out of the rift; ");
                if (PathFinder.Cheb(partner.Pos, partnerBefore) > 30 || partner.Pos.Z != partnerBefore.Z) problems.Append("the partner was not sent out of the rift; ");
                done = true;
            }
            finally
            {
                if (!done && s.Closed == null && rift.Active && rift.Result.Length == 0)
                {
                    s.Say("/rift fail");
                    WaitFor(15000, () => rift.Result.Length > 0 || s.Closed != null);
                    WaitFor(Math.Max(10000, (int)(rift.ExitIn * 1000) + 6000), () => !PathFarFromRift(before) || s.Closed != null);
                }
                LeavePartyBoth();
            }
        finish:
            r.Note("HUD results: primary '" + rift.Result + "', partner '" + prift.Result + "'; extended opcodes during the run (primary) [" + ExtDiff(extBefore) + "], invalid JSON or handler errors " + (ExtBad() - bad0));
            if (ExtBad() > bad0) problems.Append((ExtBad() - bad0) + " extended opcode message(s) were invalid JSON or threw in a handler; ");
            problems.Append(markA.Diff(me, "primary"));
            problems.Append(markB.Diff(partner, "partner"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("two accounts in a party opened a rift together: both got the HUD and the same run, the packs and the guardian fell to both, both HUDs showed the success, both opened the reward chest once, both came out, no parse failure on either connection");
        }

        // ------------------------------------------------------------------------------------ riftfail
        void ScRiftFail(ScenarioResult r)
        {
            var p = s.Parser;
            var rift = s.Progress.Rift;
            var mark = Mark.Of(me);
            var problems = new StringBuilder();
            if (serverToClient == null) { r.Skip("no items.otb: the rift key and the chest ids come from it"); return; }
            int tier = Math.Max(1, o.RiftTier);
            int texts0 = me.Said.Count;
            var extBefore = ExtPackets();
            int bad0 = ExtBad();
            var actions = new List<string>();
            bool recording = true;
            s.Ext.On(228, m => { if (recording && actions.Count < 400) actions.Add(m.Action); });
            if (!OpenRift(r, out Pos before, out int rift0, tier, o.RiftMods)) { recording = false; return; }
            bool done = false;
            try
            {
                r.Note("rift opened: " + HudLine(rift) + ", mods [" + string.Join("; ", rift.Mods.Select(RiftHud.ModLine)) + "]");
                // a wave of kills first, so the failure comes with progress on the HUD and monsters left
                s.Say(o.RiftKill);
                Pump(2500, () => false);
                int killed = rift.Killed;
                int monsters = world.Creatures.Values.Count(c => c.Type == 1);
                r.Note("before the time is up: kills " + killed + " of " + rift.BossAt + ", " + monsters + " monster(s) in view");
                // the server's own time-up rule: the deadline of the open rift is set a few seconds ahead (local-only staff command)
                int say1 = me.Said.Count;
                s.Say(o.RiftTime + " " + o.RiftFailSeconds.ToString(CultureInfo.InvariantCulture));
                bool timeSet = WaitFor(4000, () => me.ServerTexts(say1).Any(t => t.StartsWith("rtime ", StringComparison.Ordinal)));
                if (!timeSet) { r.Skip("the staff command '" + o.RiftTime + "' did not answer: this server has no command that shortens a rift (a local-only revscript, README \"Endgame scenarios (phase 24)\")"); return; }
                bool ended = WaitFor((o.RiftFailSeconds + 40) * 1000, () => rift.Result.Length > 0 || s.Closed != null);
                Pump(2500, () => false);
                var texts = GameTexts(me, say1);
                r.Note("end: result '" + rift.Result + "', HUD state '" + rift.State + "', boss '" + rift.Boss + "', exit in " + rift.ExitIn + " s, text '" + rift.ResultText + "', HUD hides in " + (rift.HideAt < 0 ? "never" : Math.Round((rift.HideAt - s.Now) / 1000.0) + " s"));
                r.Note("server lines from the time set to the end: " + texts.Count + " [" + string.Join(" | ", texts.Take(8)) + "]");
                if (!ended) { problems.Append("no end message within " + (o.RiftFailSeconds + 40) + " s of the deadline; "); goto finish; }
                if (rift.Result != "failed") problems.Append("the end message says '" + rift.Result + "', expected 'failed'; ");
                if (rift.State != "failed") problems.Append("the HUD state is '" + rift.State + "' after the failure; ");
                if (rift.ResultText.Length == 0) problems.Append("the end message has no text; ");
                else if (rift.ResultText.IndexOf("key", StringComparison.OrdinalIgnoreCase) < 0 && rift.ResultText.IndexOf("collapse", StringComparison.OrdinalIgnoreCase) < 0) problems.Append("the end text names no consequence ('" + rift.ResultText + "'); ");
                if (texts.Any(t => t.IndexOf("gold to your bank", StringComparison.OrdinalIgnoreCase) >= 0 || t.StartsWith("Rift chest", StringComparison.OrdinalIgnoreCase) || t.StartsWith("Rift reward", StringComparison.OrdinalIgnoreCase))) problems.Append("a failed rift paid a reward; ");
                if (rift.Boss == "dead") problems.Append("the HUD boss state is 'dead' in a failed rift; ");
                // no chest on the map, the character sent out at once
                bool out1 = WaitFor(15000, () => !PathFarFromRift(before) || s.Closed != null);
                Pump(1200, () => false);
                var chest = FindChest(me, RiftChestClientIds());
                r.Note("after the failure: position " + P(me.Pos) + " (before the rift " + P(before) + "), reward chest in view: " + (chest == null ? "no" : "yes at " + P(chest.Value.tile)));
                if (!out1) problems.Append("the character was not sent out of the failed rift; ");
                if (chest != null) problems.Append("a reward chest stands in view after the failure; ");
                done = true;
            }
            finally
            {
                recording = false;
                if (!done && s.Closed == null && rift.Active && rift.Result.Length == 0)
                {
                    s.Say("/rift fail");
                    WaitFor(15000, () => rift.Result.Length > 0 || s.Closed != null);
                    WaitFor(Math.Max(10000, (int)(rift.ExitIn * 1000) + 6000), () => !PathFarFromRift(before) || s.Closed != null);
                }
            }
        finish:
            r.Note("opcode 228 actions [" + string.Join(",", actions.GroupBy(x => x).Select(g => g.Key + " x" + g.Count())) + "]; extended opcodes [" + ExtDiff(extBefore) + "]; invalid JSON or handler errors " + (ExtBad() - bad0));
            if (ExtBad() > bad0) problems.Append((ExtBad() - bad0) + " extended opcode message(s) were invalid JSON or threw in a handler; ");
            problems.Append(mark.Diff(me, "primary"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("a rift ran out of time: the end message 'failed' with its text, no chest, no reward, the character sent out, no parse failure");
        }

        // ------------------------------------------------------------------------------------ coffer
        void ScCoffer(ScenarioResult r)
        {
            var p = s.Parser;
            var rift = s.Progress.Rift;
            var mark = Mark.Of(me);
            var problems = new StringBuilder();
            if (serverToClient == null) { r.Skip("no items.otb: the rift key and the coffer ids come from it"); return; }
            var ids = new HashSet<int>();
            foreach (int sid in new[] { o.CofferServerId, o.CofferFallbackServerId }) if (serverToClient.TryGetValue(sid, out int c)) ids.Add(c);
            var extBefore = ExtPackets();
            int bad0 = ExtBad();
            if (!OpenRift(r, out Pos before, out int rift0, 1, "coffer:100")) return;
            try
            {
                r.Note("rift opened: " + HudLine(rift) + ", HUD notes [" + string.Join(" | ", rift.Notes) + "]");
                if (!rift.Notes.Any(n => n.IndexOf("coffer", StringComparison.OrdinalIgnoreCase) >= 0)) { r.Skip("this rift has no Sealed Coffer (the HUD notes name none); the key asked for the modifier coffer:100"); return; }
                int say0 = me.Said.Count;
                s.Say(o.RiftGo + " coffer");
                if (!WaitFor(6000, () => me.ServerTexts(say0).Any(t => t.StartsWith("rgo ", StringComparison.Ordinal)))) { r.Skip("the staff command '" + o.RiftGo + "' did not answer: no local-only helper on this server"); return; }
                Pump(2500, () => false);
                var coffer = FindChest(me, ids);
                if (coffer == null) { problems.Append("no coffer in view after going to it (client ids " + string.Join(",", ids) + ") at " + P(me.Pos) + "; "); goto finish; }
                var (tile, stack, cid) = coffer.Value;
                r.Note("coffer: client id " + cid + " at " + P(tile) + ", " + PathFinder.Cheb(tile, me.Pos) + " tiles away");
                int t0 = me.Said.Count;
                int mon0 = world.Creatures.Values.Count(c => c.Type == 1);
                s.UseItem(tile, (ushort)cid, (byte)stack);
                bool woke = WaitFor(8000, () => me.ServerTexts(t0).Any(t => t.IndexOf("guards answer", StringComparison.OrdinalIgnoreCase) >= 0));
                Pump(1500, () => false);
                r.Note("coffer used: server lines [" + string.Join(" | ", GameTexts(me, t0).Take(3)) + "]; HUD notes [" + string.Join(" | ", rift.Notes) + "]; monsters in view " + mon0 + " to " + world.Creatures.Values.Count(c => c.Type == 1));
                if (!woke) problems.Append("using the coffer did not wake guards (no 'guards answer' line); ");
                if (!rift.Notes.Any(n => n.IndexOf("guard", StringComparison.OrdinalIgnoreCase) >= 0)) problems.Append("the HUD shows no coffer guard note after the seal broke; ");
                // using it again while guarded: the server says guards are left
                int t1 = me.Said.Count;
                s.UseItem(tile, (ushort)cid, (byte)stack);
                Pump(1500, () => false);
                r.Note("coffer used again while guarded: [" + string.Join(" | ", GameTexts(me, t1).Take(2)) + "]");
                // the guards die (the staff command hits every monster of the run): the coffer opens
                int t2 = me.Said.Count;
                s.Say(o.RiftKill);
                bool opened = WaitFor(10000, () => me.ServerTexts(t2).Any(t => t.IndexOf("seal breaks", StringComparison.OrdinalIgnoreCase) >= 0));
                Pump(1500, () => false);
                var openTexts = GameTexts(me, t2);
                r.Note("guards killed: [" + string.Join(" | ", openTexts.Where(t => t.IndexOf("coffer", StringComparison.OrdinalIgnoreCase) >= 0).Take(2)) + "]; HUD notes [" + string.Join(" | ", rift.Notes) + "]");
                if (!opened) problems.Append("the coffer did not open after its guards died; ");
                else if (!rift.Notes.Any(n => n.IndexOf("open", StringComparison.OrdinalIgnoreCase) >= 0)) problems.Append("the HUD does not say the coffer is open; ");
                // the open coffer is a container: use it
                s.Say(o.RiftGo + " coffer");
                Pump(2500, () => false);
                coffer = FindChest(me, ids);
                if (coffer != null && opened)
                {
                    foreach (var cc in p.Containers.Keys.ToList()) s.CloseContainer(cc);
                    Pump(400, () => false);
                    var seen3 = new Dictionary<byte, int>(p.Seen);
                    s.UseItem(coffer.Value.tile, (ushort)coffer.Value.id, (byte)coffer.Value.stack);
                    bool cont = WaitFor(6000, () => p.Containers.Count > 0);
                    Pump(800, () => false);
                    int items = p.Containers.Values.Sum(c => c.Items.Count);
                    r.Note("open coffer used: " + (cont ? "container with " + items + " item(s)" : "no container") + ", packets [" + PacketDiff(p, seen3) + "]");
                    if (!cont || items == 0) problems.Append("the open coffer showed no container or no items; ");
                }
                else if (opened) problems.Append("the open coffer is not in view; ");
            }
            finally
            {
                if (s.Closed == null && rift.Active && rift.Result.Length == 0)
                {
                    s.Say("/rift fail");
                    WaitFor(15000, () => rift.Result.Length > 0 || s.Closed != null);
                    WaitFor(Math.Max(10000, (int)(rift.ExitIn * 1000) + 6000), () => !PathFarFromRift(before) || s.Closed != null);
                }
            }
        finish:
            r.Note("extended opcodes [" + ExtDiff(extBefore) + "]; invalid JSON or handler errors " + (ExtBad() - bad0));
            if (ExtBad() > bad0) problems.Append((ExtBad() - bad0) + " extended opcode message(s) were invalid JSON or threw in a handler; ");
            problems.Append(mark.Diff(me, "primary"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("a Sealed Coffer: the HUD note, the seal broken (guards answered), used again while guarded, opened when the guards died, its container read, no parse failure");
        }

        // ------------------------------------------------------------------------------------ moremodals
        /// <summary>Answers every window on screen with the escape button and returns their descriptions.</summary>
        static List<string> DrainModals(ModalWindows m, Action pump)
        {
            var seen = new List<string>();
            int guard = 0;
            while (m.Current != null && guard++ < 6)
            {
                seen.Add(ModalLine(m.Current));
                m.Cancel();
                pump();
            }
            return seen;
        }

        void ScMoreModals(ScenarioResult r)
        {
            var problems = new StringBuilder();
            var mark = Mark.Of(me);
            int exercised = 0;
            var skipped = new List<string>();
            // A. the Memorial question: a character whose row says "not asked" gets a Yes / No window 3 s after the login (memorial.lua, ChaosMemorialLogin)
            string err = EnsurePartner();
            if (err != null) skipped.Add("memorial question: " + err);
            else
            {
                var pm = partner.S.Parser.Modals;
                var markB = Mark.Of(partner);
                WaitFor(9000, () => pm.Received > 0);
                if (pm.Received == 0) skipped.Add("memorial question: the partner's login brought no window (its chaos_memorial_optin row is already asked, or it is staff)");
                else
                {
                    exercised++;
                    var w = pm.Current;
                    r.Note("memorial window (partner, after login): " + (w == null ? "already answered by an earlier scenario" : ModalLine(w)));
                    if (w != null)
                    {
                        if (w.Title.Length == 0 || w.Message.Length == 0) problems.Append("memorial window without title or text; ");
                        if (w.Buttons.Count != 2) problems.Append("the memorial window has " + w.Buttons.Count + " buttons, expected Yes and No; ");
                        int t0 = partner.Said.Count;
                        int yes = w.Buttons.Any(b => b.Id == w.EnterButton) ? w.EnterButton : (w.Buttons.Count > 0 ? w.Buttons[0].Id : 1);
                        pm.Answer(yes, ModalWindows.NoChoice);
                        bool reacted = WaitFor(5000, () => partner.ServerTexts(t0).Count > 0);
                        r.Note("answered 0xF9 button " + yes + ": server text " + (reacted ? "'" + string.Join(" | ", partner.ServerTexts(t0).Take(2)) + "'" : "none"));
                        if (!reacted) problems.Append("the memorial answer brought no server text; ");
                    }
                    problems.Append(markB.Diff(partner, "partner"));
                }
            }
            // A2. the Ascendant Oracle: at stage 3 (the Choice, set in the local db) "choice" opens the list of ascended classes, a pick opens the confirm window, No cancels
            exercised += OraclePart(r, problems, skipped);
            // B. the Keeper of Trials: a greeting (the Ascendant Oracle beside him may open its own choice), then the trial window of the character's vocation
            exercised += KeeperPart(r, problems, skipped);
            // C. the welcome window, shown again by the staff command (newplayer.lua NP.showWelcome, modal id tutorial.modalBase; a console text when welcome.window is off)
            exercised += WelcomePart(r, problems, skipped);
            // D. the tutorial island: the staff command sends the partner there, the arrival window (Start / Skip), lesson 1 (Ok / Skip tutorial), the skip brings it back
            exercised += TutorialPart(r, problems, skipped);
            r.Note("not driven: the spell quest trial window (spellquest.lua, opened at a quest door of a level 1 to 100 line quest), the Oracle's Trial window (stage 2: Enter walks into a boss trial) and its final Ascend answer (changes the class for good)");
            if (skipped.Count > 0) r.Note("skipped parts: " + string.Join("; ", skipped));
            problems.Append(mark.Diff(me, "primary"));
            if (exercised == 0) r.Skip("no other modal sender was reachable: " + string.Join("; ", skipped));
            else if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass(exercised + " other modal sender(s) driven: windows parsed, answered with 0xF9, the server's reaction read, no parse failure");
        }

        int OraclePart(ScenarioResult r, StringBuilder problems, List<string> skipped)
        {
            var p = s.Parser;
            var npc = FindNpc(o.OracleNpc);
            if (npc == null && o.KeeperAt.HasValue && o.KeeperAt.Value.Z == me.Pos.Z) { WalkTo(me, o.KeeperAt.Value, 2, o.ScenarioMs, false, out _); npc = FindNpc(o.OracleNpc); }
            if (npc == null) { skipped.Add("Oracle: '" + o.OracleNpc + "' is not in view of " + P(me.Pos) + " (--keeper-at X,Y,Z: the market stalls beside the Keeper)"); return 0; }
            if (!WalkTo(me, npc.Position, 2, o.ScenarioMs, false, out string why))
            {
                if (PathFinder.Cheb(me.Pos, npc.Position) > 3 || me.Pos.Z != npc.Position.Z) { skipped.Add("Oracle: could not walk to " + o.OracleNpc + ": " + why); return 0; }
                r.Note("the Oracle stands behind a counter: talking from " + PathFinder.Cheb(me.Pos, npc.Position) + " tiles");
            }
            Pump(500, () => false);
            DrainModals(p.Modals, () => Pump(300, () => false));
            int lines0 = p.NpcTalk.Lines.Count;
            s.SayToNpc("hi");
            if (!WaitFor(6000, () => p.NpcTalk.Lines.Skip(lines0).Any(l => l.FromNpc))) { skipped.Add("Oracle: " + o.OracleNpc + " did not answer 'hi' (another NPC nearer?)"); return 0; }
            int recv0 = p.Modals.Received, lines1 = p.NpcTalk.Lines.Count;
            s.SayToNpc("choice");
            if (!WaitFor(6000, () => p.Modals.Received > recv0))
            {
                var said = p.NpcTalk.Lines.Skip(lines1).Where(l => l.FromNpc).Select(l => l.Text).Take(2).Select(t => t.Length > 100 ? t.Substring(0, 100) + "..." : t).ToList();
                s.SayToNpc("bye");
                skipped.Add("Oracle: 'choice' opened no window (the character is not at stage 3 of the ascension quest: storage 7101000 = 3 in the local db); the NPC said: " + (said.Count > 0 ? string.Join(" | ", said) : "nothing"));
                return 0;
            }
            Pump(300, () => false);
            var w = p.Modals.Current;
            r.Note("Oracle choice window: " + ModalLine(w));
            if (w.Title.Length == 0 || w.Choices.Count == 0 || w.Buttons.Count == 0) problems.Append("the Oracle's choice window has no title, no choice or no button; ");
            int recv1 = p.Modals.Received;
            int enter = w.Buttons.Any(b => b.Id == w.EnterButton) ? w.EnterButton : (w.Buttons.Count > 0 ? w.Buttons[0].Id : 1);
            p.Modals.Answer(enter, w.Choices.Count > 0 ? w.Choices[0].Id : ModalWindows.NoChoice);
            if (!WaitFor(6000, () => p.Modals.Received > recv1)) { problems.Append("a pick in the Oracle's list opened no confirm window; "); s.SayToNpc("bye"); return 1; }
            Pump(300, () => false);
            var c = p.Modals.Current;
            r.Note("Oracle confirm window: " + ModalLine(c) + (c.Id != w.Id ? "" : " (the same id as the list)"));
            if (c.Id == w.Id || c.Title.Length == 0 || c.Buttons.Count < 2) problems.Append("the confirm window is the list again, or has no title or fewer than two buttons; ");
            // the answer No (escape): the Oracle waits, nothing changes
            int t0 = me.Said.Count;
            p.Modals.Cancel();
            bool told = WaitFor(5000, () => me.ServerTexts(t0).Count > 0);
            r.Note("confirm answered with its escape button: server text " + (told ? "'" + string.Join(" | ", me.ServerTexts(t0).Take(2)) + "'" : "none"));
            if (!told) problems.Append("the answer 'No' to the Oracle's confirm window brought no server text; ");
            s.SayToNpc("bye");
            Pump(400, () => false);
            return 1;
        }

        int KeeperPart(ScenarioResult r, StringBuilder problems, List<string> skipped)
        {
            var p = s.Parser;
            var npc = FindNpc(o.KeeperNpc);
            if (npc == null && o.KeeperAt.HasValue)
            {
                var hint = o.KeeperAt.Value;
                if (hint.Z != me.Pos.Z) { skipped.Add("Keeper: the --keeper-at hint is on floor " + hint.Z + ", the player on " + me.Pos.Z); return 0; }
                WalkTo(me, hint, 2, o.ScenarioMs, false, out string approach);
                r.Note("approach to the Keeper's hint " + P(hint) + ": " + (approach.Length == 0 ? "arrived" : approach));
                npc = FindNpc(o.KeeperNpc);
            }
            if (npc == null) { skipped.Add("Keeper: '" + o.KeeperNpc + "' is not in view of " + P(me.Pos) + " (--keeper-at X,Y,Z)"); return 0; }
            if (!WalkTo(me, npc.Position, 2, o.ScenarioMs, false, out string why))
            {
                if (PathFinder.Cheb(me.Pos, npc.Position) > 3 || me.Pos.Z != npc.Position.Z) { problems.Append("could not walk to " + o.KeeperNpc + ": " + why + "; "); return 0; }
                r.Note("the Keeper stands behind a counter: talking from " + PathFinder.Cheb(me.Pos, npc.Position) + " tiles");
            }
            Pump(500, () => false);
            var old = DrainModals(p.Modals, () => Pump(300, () => false));
            if (old.Count > 0) r.Note("answered " + old.Count + " window(s) the server had sent before");
            int lines0 = p.NpcTalk.Lines.Count, recv0 = p.Modals.Received;
            s.SayToNpc("hi");
            if (!WaitFor(6000, () => p.NpcTalk.Lines.Skip(lines0).Any(l => l.FromNpc))) { problems.Append("the Keeper did not answer 'hi'; "); return 0; }
            Pump(1800, () => false);   // the Oracle's choice, when its NPC stands in range
            int exercised = 0;
            var greet = DrainModals(p.Modals, () => Pump(600, () => false));
            r.Note("greeting: " + p.NpcTalk.Lines.Skip(lines0).Count(l => l.FromNpc) + " NPC line(s), " + (p.Modals.Received - recv0) + " window(s) from the greeting" + (greet.Count > 0 ? ": " + string.Join(" || ", greet) : "") + (greet.Count > 0 ? "; each answered with its escape button" : ""));
            foreach (string g in greet) if (g.IndexOf("title ''", StringComparison.Ordinal) >= 0) problems.Append("a greeting window has no title; ");
            if (greet.Count > 0) exercised++;
            int recv1 = p.Modals.Received, lines1 = p.NpcTalk.Lines.Count;
            s.SayToNpc("trial");
            if (!WaitFor(6000, () => p.Modals.Received > recv1))
            {
                var said = p.NpcTalk.Lines.Skip(lines1).Where(l => l.FromNpc).Select(l => l.Text).Take(2).ToList();
                s.SayToNpc("bye");
                skipped.Add("Keeper: 'trial' made " + o.KeeperNpc + " send no window; the NPC said: " + (said.Count > 0 ? string.Join(" | ", said) : "nothing"));
                return exercised;
            }
            Pump(300, () => false);
            var w = p.Modals.Current;
            r.Note("trial window: " + ModalLine(w));
            exercised++;
            if (w.Title.Length == 0 || w.Choices.Count == 0 || w.Buttons.Count < 2) problems.Append("the trial window has no title, no tier choice or fewer than two buttons; ");
            var from = me.Pos;
            int t0 = me.Said.Count, packets0 = s.Packets;
            var seen0 = new Dictionary<byte, int>(p.Seen);
            int enter = w.Buttons.Any(b => b.Id == w.EnterButton) ? w.EnterButton : (w.Buttons.Count > 0 ? w.Buttons[0].Id : 1);
            int choice = w.Choices.Count > 0 ? w.Choices[0].Id : ModalWindows.NoChoice;
            p.Modals.Answer(enter, choice);
            r.Note("answered 0xF9: button " + enter + ", choice " + choice);
            bool reacted = WaitFor(10000, () => PathFinder.Cheb(me.Pos, from) > 30 || me.Pos.Z != from.Z || me.ServerTexts(t0).Count > 0);
            Pump(2500, () => false);
            bool inTrial = PathFinder.Cheb(me.Pos, from) > 30 || me.Pos.Z != from.Z;
            r.Note("trial reaction: " + (inTrial ? "taken into a trial room at " + P(me.Pos) + " (from " + P(from) + ")" : "no move") + ", server lines [" + string.Join(" | ", GameTexts(me, t0).Take(3)) + "], packets [" + PacketDiff(p, seen0) + "]");
            if (!reacted) problems.Append("the trial answer brought no reaction (no move, no server line); ");
            if (inTrial)
            {
                // out again: the passive tree window's Leave (trialLeave on the passive tree opcode)
                s.Ext.Send(PassiveTree.Opcode, "trialLeave", null);
                bool back = WaitFor(25000, () => PathFinder.Cheb(me.Pos, from) <= 30 && me.Pos.Z == from.Z);
                Pump(1500, () => false);
                r.Note("trial left: " + (back ? "back at " + P(me.Pos) : "still at " + P(me.Pos)));
                if (!back) problems.Append("the character did not come back from the trial room after trialLeave; ");
            }
            s.SayToNpc("bye");
            Pump(500, () => false);
            return exercised;
        }

        int TutorialPart(ScenarioResult r, StringBuilder problems, List<string> skipped)
        {
            if (partner == null || partner.S.Closed != null) { skipped.Add("tutorial: no partner connection"); return 0; }
            var pm = partner.S.Parser.Modals;
            var markB = Mark.Of(partner);
            DrainModals(pm, () => Pump(300, () => false));
            var home = partner.Pos;
            int recv0 = pm.Received, t0 = partner.Said.Count;
            s.Say("/newplayerkit " + partner.Character + ", tutorial");
            if (!WaitFor(8000, () => pm.Received > recv0))
            {
                var texts = GameTexts(me, 0).TakeLast(2).ToList();
                skipped.Add("tutorial: no arrival window after the staff command" + (texts.Count > 0 ? " (server said: " + string.Join(" | ", texts) + ")" : ""));
                return 0;
            }
            Pump(500, () => false);
            var w1 = pm.Current;
            bool onIsland = PathFinder.Cheb(partner.Pos, home) > 30 || partner.Pos.Z != home.Z;
            r.Note("tutorial arrival window (partner, " + (onIsland ? "taken to the island at " + P(partner.Pos) : "still at " + P(partner.Pos)) + "): " + ModalLine(w1));
            if (w1.Title.Length == 0 || w1.Message.Length == 0 || w1.Buttons.Count != 2) problems.Append("the tutorial arrival window has no title, no text or not two buttons; ");
            // Start tutorial (button 1): lesson 1 comes
            int recv1 = pm.Received;
            pm.Answer(1, ModalWindows.NoChoice);
            if (!WaitFor(6000, () => pm.Received > recv1)) { problems.Append("'Start tutorial' brought no lesson window; "); }
            else
            {
                Pump(400, () => false);
                var w2 = pm.Current;
                r.Note("lesson 1 window: " + ModalLine(w2));
                if (w2.Title.Length == 0 || w2.Message.Length == 0 || w2.Buttons.Count != 2) problems.Append("lesson 1 has no title, no text or not two buttons; ");
                // Skip tutorial (button 2): the character goes back to the temple
                int t1 = partner.Said.Count;
                pm.Answer(2, ModalWindows.NoChoice);
                bool back = WaitFor(10000, () => PathFinder.Cheb(partner.Pos, home) <= 30 && partner.Pos.Z == home.Z && partner.ServerTexts(t1).Count > 0);
                Pump(1500, () => false);
                r.Note("lesson 1 skipped: " + (back ? "back at " + P(partner.Pos) : "still at " + P(partner.Pos)) + ", server lines [" + string.Join(" | ", GameTexts(partner, t1).Take(3).Select(t => t.Replace("\n", " "))) + "]");
                if (!back) problems.Append("'Skip tutorial' did not bring the partner back from the island; ");
            }
            DrainModals(pm, () => Pump(300, () => false));
            problems.Append(markB.Diff(partner, "partner"));
            return 1;
        }

        int WelcomePart(ScenarioResult r, StringBuilder problems, List<string> skipped)
        {
            var p = s.Parser;
            DrainModals(p.Modals, () => Pump(300, () => false));
            int recv0 = p.Modals.Received, say0 = me.Said.Count;
            s.Say("/newplayerkit " + me.Character + ", welcome");
            if (!WaitFor(5000, () => p.Modals.Received > recv0))
            {
                var texts = GameTexts(me, say0);
                skipped.Add("welcome: no window after the staff command (newplayer_config.lua welcome.window is off: the welcome is a console text)" + (texts.Count > 0 ? "; server said " + texts.Count + " line(s): " + string.Join(" | ", texts.Take(2).Select(t => t.Replace("\n", " ").Length > 60 ? t.Replace("\n", " ").Substring(0, 60) + "..." : t.Replace("\n", " "))) : ""));
                return 0;
            }
            Pump(300, () => false);
            var w = p.Modals.Current;
            r.Note("welcome window: " + ModalLine(w));
            if (w.Title.Length == 0 || w.Message.Length == 0 || w.Buttons.Count == 0) problems.Append("the welcome window has no title, text or button; ");
            int button = w.Buttons.Any(b => b.Id == w.EnterButton) ? w.EnterButton : (w.Buttons.Count > 0 ? w.Buttons[0].Id : 1);
            p.Modals.Answer(button, ModalWindows.NoChoice);
            Pump(1200, () => false);
            r.Note("welcome answered with button " + button + ", " + p.Modals.Queue.Count + " window(s) left");
            if (s.Closed != null) problems.Append("the connection closed after the welcome answer: " + s.Closed + "; ");
            return 1;
        }
    }
}
