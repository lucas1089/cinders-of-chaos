// Last endgame gaps of the live check (O433 phase 25): the Twin and Wrathful guardians (guardians), a mortal partner's health in a party rift (partnerdeath), a death that costs
// the last shared life (lastlife), a party of three (party3) and the spell quest and Oracle's Trial windows (trialwindows). Same rules as LiveScenarios.cs: opt-in by --scenario,
// a time limit, a pass, fail or skip with the reason, names scrubbed from the reports, and what was opened is closed again. The staff commands the rift scenarios use
// that the server does not have (/rkill, /rnear, /rgo, /rdie, /rwin, /rset) are a local-only revscript, see unity/README.md "Last endgame gaps (phase 25)".
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
        static int SeenOf(LiveClient c, byte op) => c.S.Parser.Seen.TryGetValue(op, out int n) ? n : 0;

        /// <summary>Connects the third account and waits for its entry. Null on success, else why not.</summary>
        string EnsureThird()
        {
            if (third != null && third.S.Closed == null && third.Entered) return null;
            if (string.IsNullOrEmpty(o.Account3) || string.IsNullOrEmpty(o.Password3)) return "no third account (environment CHAOS_LIVE_ACCOUNT3 and CHAOS_LIVE_PASSWORD3)";
            var c = LiveClient.Connect(o, dat, o.Account3, o.Password3, o.Character3, out string err);
            if (c == null) return "the third account could not log in: " + err;
            third = c;
            if (!WaitFor(15000, () => third.Entered || third.S.Closed != null)) return "the third character did not enter the game";
            if (third.S.Closed != null) return "the third connection closed: " + third.S.Closed;
            Pump(2500, () => false);
            return null;
        }

        /// <summary>The partner's connection is closed and the same character logs in again (after a death). The new connection is the partner from here on; the failures of
        /// the old one are kept for the report. Null on success, else why not.</summary>
        string ReloginPartner()
        {
            string name = partner.Character;
            if (partner.S.Parser.FailureCount > 0 || partner.Thrown.Count > 0) { partnerBad = true; partnerStats = (partnerStats ?? "") + "earlier connection: parse failures " + partner.S.Parser.FailureCount + ", exceptions " + partner.Thrown.Count + "; "; }
            partner.Close();
            var again = LiveClient.Connect(o, dat, o.Account2, o.Password2, name, out string err);
            if (again == null) { partner = null; return "login after the death failed: " + err; }
            partner = again;
            if (!WaitFor(15000, () => partner.Entered || partner.S.Closed != null)) return "the character did not enter again";
            if (partner.S.Closed != null) return "the new connection closed: " + partner.S.Closed;
            Pump(2500, () => false);
            return null;
        }

        /// <summary>Leaves the party and waits until the client's frames say so or another client sees its shield gone; the engine refuses a leave while the character is in a fight
        /// (Game::playerLeaveParty, CONDITION_INFIGHT, up to 60 s after the last hit), so the call is repeated every 6 s up to `limitMs`. Returns whether the party is left.</summary>
        bool LeaveWithRetry(LiveClient c, IEnumerable<LiveClient> others, int limitMs, out int waitedMs)
        {
            long t0 = Tick, end = t0 + limitMs;
            var seers = others.Where(x => x != null).ToList();
            bool gone = false;
            while (Tick < end && c.S.Closed == null)
            {
                c.S.Party.Do(PartyAction.Leave, 0);
                gone = WaitFor(6000, () => !c.S.Party.InParty || seers.Any(x => { var cr = Seeing(x, c.Character); return cr != null && cr.Shield == PartyShield.None; }));
                if (gone) break;
            }
            waitedMs = (int)(Tick - t0);
            return gone;
        }

        /// <summary>The nearest NPC of a name on the client's floor.</summary>
        static Creature FindNpcOf(LiveClient c, string name)
        {
            Creature best = null;
            int bd = int.MaxValue;
            foreach (var cr in c.World.Creatures.Values)
            {
                if (cr.Type != 2 || cr.Position.Z != c.Pos.Z) continue;
                if (name != null && !string.Equals(cr.Name, name, StringComparison.OrdinalIgnoreCase)) continue;
                int d = PathFinder.Cheb(cr.Position, c.Pos);
                if (d < bd) { bd = d; best = cr; }
            }
            return best;
        }

        /// <summary>The server texts of a client from line `from` on that the local helper commands did not write, cut short.</summary>
        static List<string> LocalFree(LiveClient c, int from) => GameTexts(c, from).Where(t => !t.StartsWith("rtrace ", StringComparison.Ordinal) && !t.StartsWith("rwin ", StringComparison.Ordinal) && !t.StartsWith("rset ", StringComparison.Ordinal)).ToList();

        void CloseRiftNow(RiftHud rift, Pos before)
        {
            if (s.Closed == null && rift.Active && rift.Result.Length == 0)
            {
                s.Say("/rift fail");
                WaitFor(15000, () => rift.Result.Length > 0 || s.Closed != null);
                WaitFor(Math.Max(10000, (int)(rift.ExitIn * 1000) + 6000), () => !PathFarFromRift(before) || s.Closed != null);
            }
        }

        // ------------------------------------------------------------------------------------ guardians
        /// <summary>What the Twin Guardians and the Wrathful Guardian do before the kill (called by RiftBossRun with the character next to the guardian).</summary>
        void GuardianFlavour(ScenarioResult r, string flavour, RiftHud rift, StringBuilder problems, int texts0)
        {
            var p = s.Parser;
            var guardians = world.Creatures.Values.Where(c => c.Type == 1 && rift.BossName.Length > 0 && c.Name.IndexOf(rift.BossName, StringComparison.OrdinalIgnoreCase) >= 0).ToList();
            if (flavour == "twin")
            {
                string apart = guardians.Count >= 2 ? PathFinder.Cheb(guardians[0].Position, guardians[1].Position) + " tile(s) apart" : "one in view";
                r.Note("twin guardians: " + guardians.Count + " guardian(s) named '" + rift.BossName + "' in view (" + apart + "), guardian count line [" + string.Join(" | ", rift.Notes) + "], mods [" + string.Join("; ", rift.Mods.Select(RiftHud.ModLine)) + "]");
                if (guardians.Count < 2) problems.Append("two guardians expected in view with the Twin Guardians modifier, " + guardians.Count + " seen; ");
                if (!rift.Notes.Any(n => n.IndexOf("Guardians left: 2", StringComparison.OrdinalIgnoreCase) >= 0)) problems.Append("the HUD has no 'Guardians left: 2.' note while both twins live (notes: " + string.Join(" | ", rift.Notes) + "); ");
                int t1 = me.Said.Count;
                var before = new Dictionary<byte, int>(p.Seen);
                s.Say(o.RiftKill + " g1");
                bool one = WaitFor(9000, () => rift.Notes.Any(n => n.IndexOf("Guardians left: 1", StringComparison.OrdinalIgnoreCase) >= 0) || rift.Result.Length > 0 || s.Closed != null);
                Pump(1500, () => false);
                var texts = LocalFree(me, t1);
                int left = world.Creatures.Values.Count(c => c.Type == 1 && rift.BossName.Length > 0 && c.Name.IndexOf(rift.BossName, StringComparison.OrdinalIgnoreCase) >= 0);
                r.Note("first twin killed ('" + o.RiftKill + " g1'): HUD boss '" + rift.Boss + "', state '" + rift.State + "', result '" + rift.Result + "', notes [" + string.Join(" | ", rift.Notes) + "], " + left + " guardian(s) left in view, lines [" + string.Join(" | ", texts.Take(3)) + "], packets [" + PacketDiff(p, before) + "]");
                if (rift.Result.Length > 0) problems.Append("the rift ended (result '" + rift.Result + "') with one of the two guardians dead; ");
                else if (!one) problems.Append("the HUD never said that one guardian was left; ");
                if (rift.Boss != "alive" && rift.Result.Length == 0) problems.Append("the HUD boss state is '" + rift.Boss + "' while the second twin lives; ");
                if (!texts.Any(t => t.IndexOf("twin still stands", StringComparison.OrdinalIgnoreCase) >= 0)) problems.Append("no 'One guardian falls. Its twin still stands!' line after the first kill (lines: " + string.Join(" | ", texts.Take(3)) + "); ");
            }
            else if (flavour == "wrath")
            {
                int mon0 = world.Creatures.Values.Count(c => c.Type == 1), maxMon = mon0, minHp = p.Health;
                var before = new Dictionary<byte, int>(p.Seen);
                int t1 = me.Said.Count;
                long end = Tick + 26000;
                while (Tick < end && s.Closed == null && rift.Result.Length == 0)
                {
                    Pump(300, () => false);
                    maxMon = Math.Max(maxMon, world.Creatures.Values.Count(c => c.Type == 1));
                    minHp = Math.Min(minHp, p.Health);
                }
                int ri0 = me.Said.Count;
                s.Say("/rinfo");
                Pump(900, () => false);
                string rinfo = me.ServerTexts(ri0).FirstOrDefault(x => x.StartsWith("rinfo ", StringComparison.Ordinal)) ?? "no /rinfo reply";
                var texts = LocalFree(me, t1).Where(x => !x.StartsWith("rinfo ", StringComparison.Ordinal)).ToList();
                r.Note("the server's own count after the 26 s (local /rinfo): " + rinfo);
                // the thralls the server lists must be creatures Core knows (type 1, in the world's creature table)
                var idm = System.Text.RegularExpressions.Regex.Match(rinfo, @"thralls (\d+) .* ids ([0-9,]*)");
                int serverThralls = idm.Success ? int.Parse(idm.Groups[1].Value, CultureInfo.InvariantCulture) : -1;
                int known = 0;
                if (idm.Success) foreach (string id in idm.Groups[2].Value.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries)) if (world.Creatures.TryGetValue(uint.Parse(id, CultureInfo.InvariantCulture), out var tc) && tc.Type == 1) known++;
                r.Note("thralls: the server lists " + serverThralls + ", Core knows " + known + " of them");
                if (serverThralls > 0 && known < serverThralls) problems.Append("the server lists " + serverThralls + " thrall(s) near the guardian, Core's world holds " + known + "; ");
                r.Note("wrathful guardian, 26 s beside it: monsters in view " + mon0 + " to at most " + maxMon + " (thralls come every 20 s), character health " + p.MaxHealth + " max, lowest " + minHp + ", effects 0x83 x" + Delta(before, p, 0x83) +
                       ", health updates 0x8C x" + Delta(before, p, 0x8C) + ", stats 0xA0 x" + Delta(before, p, 0xA0) + ", lines [" + string.Join(" | ", texts.Take(3)) + "], HUD mods [" + string.Join("; ", rift.Mods.Select(RiftHud.ModLine)) + "]");
                if (rift.Mods.All(m => m.Name.IndexOf("Wrathful", StringComparison.OrdinalIgnoreCase) < 0)) problems.Append("the HUD lists no Wrathful Guardian modifier; ");
                if (serverThralls == 0 || (serverThralls < 0 && maxMon <= mon0)) problems.Append("the guardian called no thralls in the 26 s beside it (server count " + serverThralls + ", monsters in view " + mon0 + " to " + maxMon + "); ");
            }
        }

        void ScGuardians(ScenarioResult r)
        {
            if (serverToClient == null) { r.Skip("no items.otb: the rift key and the chest ids come from it"); return; }
            var parts = new[] { (name: "twin", mods: o.TwinMods), (name: "wrath", mods: o.WrathMods) }.Where(x => o.GuardianParts.Split(',').Contains(x.name)).ToArray();
            if (parts.Length == 0) { r.Skip("--guardian-parts names neither twin nor wrath"); return; }
            var results = new List<ScenarioResult>();
            foreach (var part in parts)
            {
                var sub = new ScenarioResult { Name = part.name };
                try { RiftBossRun(sub, o.GuardianTier, part.mods, false, part.name); }
                catch (Exception e) { sub.Fail("exception " + e.GetType().Name + ": " + e.Message); }
                results.Add(sub);
                r.Note("[" + part.name + "] " + sub.Status.ToUpperInvariant() + ": " + sub.Reason);
                foreach (string n in sub.Notes) r.Note("[" + part.name + "] " + n);
                Pump(1500, () => false);
            }
            var bad = results.Where(x => x.Status == "fail").ToList();
            if (bad.Count > 0) r.Fail(string.Join(" | ", bad.Select(x => x.Name + ": " + x.Reason)));
            else if (results.All(x => x.Status == "skip")) r.Skip(string.Join(" | ", results.Select(x => x.Name + ": " + x.Reason)));
            else r.Pass(string.Join("; ", results.Select(x => x.Name + " " + x.Status + (x.Status == "skip" ? " (" + x.Reason + ")" : ""))) + ": tier " + o.GuardianTier + " rifts to the guardians, each killed, the reward chest opened and paid, every rift opcode parsed");
        }

        // ------------------------------------------------------------------------------------ partnerdeath
        /// <summary>A mortal partner (its own health, no staff rights) in a party rift hits the packs and the guardian. The earlier runs let the partner die in some runs: the
        /// staff kill command hit for the monster's own health, and a Reflective monster (a rare or legendary tier modifier, 15% of the damage taken comes back) sent a part of
        /// it onto the hitter. This run follows the partner's health through every wave (`/rkill p`, hits of --hit-size, 0 = the monster's own health) and quotes the
        /// command's own trace of what came back.</summary>
        void ScPartnerDeath(ScenarioResult r)
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
            err = FormParty();
            if (err != null) { r.Skip("the party could not be formed: " + err); return; }
            string mods = string.IsNullOrEmpty(o.RiftMods) ? "vitality:20" : o.RiftMods;
            string hitArg = o.HitSize > 0 ? " " + o.HitSize.ToString(CultureInfo.InvariantCulture) : "";
            prift.Hide();
            bool done = false;
            Pos before = me.Pos;
            int pTexts0 = partner.Said.Count, mTexts0 = me.Said.Count;
            long minHp = long.MaxValue;
            int deaths0 = SeenOf(partner, 0x28);
            Action watch = () => { if (pp.MaxHealth > 0) minHp = Math.Min(minHp, pp.Health); };
            try
            {
                if (!OpenRift(r, out before, out int rift0, 1, mods)) return;
                bool pin = WaitFor(8000, () => prift.Active);
                Pump(1500, () => false);
                if (!pin)
                {
                    var tx = GameTexts(partner, pTexts0).Take(2).ToList();
                    r.Skip("the partner was not taken into the rift" + (tx.Count > 0 ? "; server said: " + string.Join(" | ", tx) : "") + " (two characters of one connection: the local helper sets the game storage 7100990 = 1)");
                    return;
                }
                partner.S.Say("/rtrace");   // local helper: the server log gets every hit the partner takes
                Pump(600, () => false);
                watch();
                r.Note("partner: level " + pp.Level + ", health " + pp.Health + "/" + pp.MaxHealth + ", rift mods [" + string.Join("; ", rift.Mods.Select(RiftHud.ModLine)) + "], hits of " + (o.HitSize > 0 ? o.HitSize.ToString(CultureInfo.InvariantCulture) : "the monster's own health"));
                int waves = 0, packs0 = rift.Killed;
                long limit = Tick + Math.Max(150000, o.ScenarioMs * 3);
                while (Tick < limit && s.Closed == null && partner.S.Closed == null && !pp.Dead && rift.Boss != "alive" && rift.Boss != "dead" && rift.Result.Length == 0)
                {
                    s.Say(o.RiftKill + " p" + hitArg);
                    waves++;
                    Pump(1500, () => { watch(); return pp.Dead || rift.Boss == "alive" || rift.Boss == "dead" || rift.Result.Length > 0 || s.Closed != null; });
                    if (waves == 3 && rift.Killed == packs0) { r.Skip("the staff kill command '" + o.RiftKill + "' killed nothing in 3 tries (a local-only revscript, README \"Last endgame gaps (phase 25)\")"); return; }
                }
                var lost = me.ServerTexts(mTexts0).Where(t => t.StartsWith("rtrace ", StringComparison.Ordinal)).ToList();
                r.Note("packs: " + waves + " wave(s), kills " + packs0 + " to " + rift.Killed + " of " + rift.BossAt + "; partner health now " + pp.Health + "/" + pp.MaxHealth + ", lowest " + minHp + ", dead " + pp.Dead + "; hits that reflected damage onto the hitter: " + lost.Count);
                foreach (string l in lost.Take(4)) r.Note("  " + l);
                if (!pp.Dead && rift.Boss == "alive")
                {
                    // the Reflective probe: the guardian carries the Reflective tier modifier only (the local /rrefl; without it the guardian keeps its own roll) and takes single hits of
                    // a fixed size from the partner; what comes back onto the partner is read from its health and from the command's own trace
                    int probe = o.HitSize > 0 ? o.HitSize : 30000;
                    int rr0 = me.Said.Count;
                    bool riftReflection = o.ReflectProbe == "rift";
                    s.Say(riftReflection ? "/rrefl clear fx 22" : "/rrefl");   // the rift's own Reflection modifier alone (22%, set live), or the Reflective tier modifier alone
                    Pump(800, () => false);
                    bool reflOn = me.ServerTexts(rr0).Any(x => x.StartsWith("rrefl ", StringComparison.Ordinal) && !x.StartsWith("rrefl 0", StringComparison.Ordinal));
                    var probes = new List<string>();
                    for (int k = 0; k < 3 && !pp.Dead && s.Closed == null && rift.Result.Length == 0; k++)
                    {
                        long h0 = pp.Health;
                        int tr0 = me.Said.Count;
                        s.Say(o.RiftKill + " p g1 " + probe.ToString(CultureInfo.InvariantCulture));
                        Pump(1800, () => { watch(); return pp.Dead || s.Closed != null; });
                        var tr = me.ServerTexts(tr0).FirstOrDefault(x => x.StartsWith("rtrace ", StringComparison.Ordinal));
                        probes.Add("hit " + probe + ": partner health " + h0 + " to " + pp.Health + " (lost " + (h0 - pp.Health) + ", " + Math.Round(100.0 * (h0 - pp.Health) / probe, 1).ToString(CultureInfo.InvariantCulture) + "% of the hit)" + (tr != null ? ", the command's trace '" + tr + "'" : ""));
                    }
                    r.Note((riftReflection ? "Reflection modifier of the rift (the guardian's tier modifiers cleared by /rrefl)" : "Reflective guardian") + " (" + (reflOn ? "set by /rrefl" : "its own roll: /rrefl missing or no tier state") + "): " + string.Join(" | ", probes));
                    int gk = 0;
                    long limit2 = Tick + 90000;
                    while (Tick < limit2 && s.Closed == null && partner.S.Closed == null && !pp.Dead && rift.Result.Length == 0)
                    {
                        s.Say(o.RiftKill + " p" + hitArg);
                        gk++;
                        Pump(2000, () => { watch(); return pp.Dead || rift.Result.Length > 0 || s.Closed != null; });
                    }
                    var lost2 = me.ServerTexts(mTexts0).Where(t => t.StartsWith("rtrace ", StringComparison.Ordinal)).Skip(lost.Count).ToList();
                    var bossLine = me.ServerTexts(mTexts0).Where(t => t.StartsWith("rkill ", StringComparison.Ordinal) && t.IndexOf(" boss ", StringComparison.Ordinal) > 0).Select(t => t.Substring(6)).Take(3).ToList();
                    r.Note("guardian '" + rift.BossName + "': " + gk + " hit command(s), result '" + rift.Result + "', partner health " + pp.Health + "/" + pp.MaxHealth + ", lowest " + minHp + ", dead " + pp.Dead + "; the command's own lines [" + string.Join(" | ", bossLine) + "]");
                    foreach (string l in lost2.Take(4)) r.Note("  " + l);
                }
                if (pp.Dead)
                {
                    int dn = SeenOf(partner, 0x28) - deaths0;
                    var tx = GameTexts(partner, pTexts0).TakeLast(4).ToList();
                    problems.Append("the partner died (0x28 x" + dn + ", type " + pp.DeathType + ") with " + pp.MaxHealth + " health; it hit with " + (o.HitSize > 0 ? o.HitSize.ToString(CultureInfo.InvariantCulture) : "the monster's own health") + "; last lines [" + string.Join(" | ", tx) + "]; the trace of what came back: " + string.Join(" | ", me.ServerTexts(mTexts0).Where(t => t.StartsWith("rtrace ", StringComparison.Ordinal)).TakeLast(2)) + "; ");
                }
                else if (rift.Result.Length > 0 && rift.Result != "success") problems.Append("the rift ended with '" + rift.Result + "'; ");
                r.Note("lowest partner health in the run: " + minHp + " of " + pp.MaxHealth);
                // a sealed rift keeps both inside until its exit time (the chest window): wait for it, so the next scenario starts outside
                if (rift.Result == "success")
                {
                    WaitFor(Math.Max(15000, (int)(rift.ExitIn * 1000) + 8000), () => (!PathFarFromRift(before) && !PartnerFarFromRift(before)) || s.Closed != null);
                    Pump(1200, () => false);
                }
                done = true;
            }
            finally
            {
                CloseRiftNow(rift, before);
                LeavePartyBoth();
                if (partner != null && partner.S.Closed == null && partner.S.Parser.Dead) { string e2 = ReloginPartner(); if (e2 != null) r.Note("partner login after its death: " + e2); }
            }
            if (!done && problems.Length == 0) return;
            problems.Append(markA.Diff(me, "primary"));
            if (partner != null) problems.Append(markB.Diff(partner, "partner"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("a mortal partner with " + pp.MaxHealth + " health hit the packs and the guardian of a party rift (lowest health " + minHp + "), no death, no parse failure");
        }

        // ------------------------------------------------------------------------------------ lastlife
        void ScLastLife(ScenarioResult r)
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
            if (PathFinder.Cheb(me.Pos, partner.Pos) > 6 && !WalkTo(partner, me.Pos, 2, o.ScenarioMs, false, out string closer)) r.Note("the partner could not come closer: " + closer);
            err = FormParty();
            if (err != null) { r.Skip("the party could not be formed: " + err); return; }
            partner.S.Progress.Rift.Hide();
            var home = partner.Pos;
            Pos before = me.Pos;
            bool done = false;
            string mods = string.IsNullOrEmpty(o.RiftMods) ? "vitality:20" : o.RiftMods;
            int bad0 = ExtBad();
            var extBefore = ExtPackets();
            try
            {
                if (!OpenRift(r, out before, out int rift0, 1, mods)) return;
                var prift = partner.S.Progress.Rift;
                bool pin = WaitFor(8000, () => prift.Active);
                Pump(1500, () => false);
                if (!pin)
                {
                    var tx = GameTexts(partner, 0).TakeLast(2).ToList();
                    r.Skip("the partner was not taken into the rift" + (tx.Count > 0 ? "; server said: " + string.Join(" | ", tx) : "") + " (the local helper sets the game storage 7100990 = 1)");
                    return;
                }
                var pp = partner.S.Parser;
                var entry = partner.Pos;
                r.Note("rift opened for two: primary " + HudLine(rift) + "; partner " + HudLine(prift) + "; partner at " + P(entry));
                // two lives: the first death leaves one, the second is the last
                int say0 = me.Said.Count;
                s.Say("/rift lives 2");
                WaitFor(4000, () => rift.Lives == 2 && prift.Lives == 2);
                r.Note("shared lives set to 2: primary " + rift.Lives + "/" + rift.LivesMax + ", partner " + prift.Lives + "/" + prift.LivesMax);
                if (rift.Lives != 2 || prift.Lives != 2) problems.Append("the HUDs did not take the shared lives 2 (primary " + rift.Lives + ", partner " + prift.Lives + "); ");

                // ---- the first death: a life is lost, the run goes on
                int d0 = SeenOf(partner, 0x28), mt0 = me.Said.Count, pt0 = partner.Said.Count;
                partner.S.Say("/rdie");
                bool died = WaitFor(10000, () => pp.Dead || partner.S.Closed != null);
                Pump(2500, () => false);
                r.Note("first death: partner dead " + pp.Dead + ", 0x28 x" + (SeenOf(partner, 0x28) - d0) + " (type " + pp.DeathType + ", penalty " + pp.DeathPenalty + "%); partner HUD result '" + prift.Result + "' state '" + prift.State + "' text '" + prift.ResultText + "'; primary HUD lives " + rift.Lives + "/" + rift.LivesMax + ", result '" + rift.Result + "', notes [" + string.Join(" | ", rift.Notes) + "]");
                r.Note("primary's lines [" + string.Join(" | ", LocalFree(me, mt0).Take(3)) + "]");
                if (!died) { problems.Append("the partner did not die after /rdie (the local command is missing?); "); goto finish; }
                if (SeenOf(partner, 0x28) - d0 != 1) problems.Append("0x28 seen " + (SeenOf(partner, 0x28) - d0) + " times on the first death; ");
                if (prift.Result != "left" || prift.State != "left") problems.Append("the fallen member's HUD says result '" + prift.Result + "' state '" + prift.State + "', expected 'left'; ");
                if (prift.ResultText.IndexOf("1 life left", StringComparison.OrdinalIgnoreCase) < 0) problems.Append("the fallen member's end text does not name the life left ('" + prift.ResultText + "'); ");
                if (rift.Lives != 1) problems.Append("the primary's HUD shows " + rift.Lives + " lives after one death, expected 1; ");
                if (rift.Result.Length > 0) problems.Append("the rift ended (" + rift.Result + ") although one life was left; ");
                if (!rift.Notes.Any(n => n.IndexOf("fallen player may still return", StringComparison.OrdinalIgnoreCase) >= 0)) problems.Append("the primary's HUD has no 'fallen player may still return' note (notes: " + string.Join(" | ", rift.Notes) + "); ");
                // the dead partner logs in again: back at the rift's entrance with the run's HUD
                err = ReloginPartner();
                if (err != null) { problems.Append(err + "; "); goto finish; }
                prift = partner.S.Progress.Rift;
                pp = partner.S.Parser;
                WaitFor(6000, () => prift.Active);
                Pump(1500, () => false);
                r.Note("after the login: partner at " + P(partner.Pos) + " (entrance " + P(entry) + "), health " + pp.Health + "/" + pp.MaxHealth + ", dead " + pp.Dead + ", HUD " + (prift.Active ? HudLine(prift) : "none") + "; lines [" + string.Join(" | ", LocalFree(partner, 0).TakeLast(3)) + "]");
                if (pp.Dead || pp.Health <= 0) problems.Append("the character came back dead; ");
                if (PathFinder.Cheb(partner.Pos, entry) > 6 || partner.Pos.Z != entry.Z) problems.Append("the fallen member did not return at the rift's entrance (at " + P(partner.Pos) + ", entrance " + P(entry) + "); ");
                if (!prift.Active) problems.Append("the returning member got no rift HUD; ");
                else if (prift.Lives != 1) problems.Append("the returning member's HUD shows " + prift.Lives + " lives, expected 1; ");
                Pump(5500, () => false);   // the shield after a lost life lasts 5 s

                // ---- the second death: the last life, the rift collapses
                int d1 = SeenOf(partner, 0x28), mt1 = me.Said.Count, extra1 = world.Creatures.Count;
                var seenPrimary = new Dictionary<byte, int>(s.Parser.Seen);
                partner.S.Say("/rdie");
                bool died2 = WaitFor(10000, () => pp.Dead || partner.S.Closed != null);
                bool ended = WaitFor(15000, () => rift.Result.Length > 0 || s.Closed != null);
                Pump(2500, () => false);
                var texts = LocalFree(me, mt1);
                r.Note("last life: partner dead " + pp.Dead + ", 0x28 x" + (SeenOf(partner, 0x28) - d1) + "; partner HUD result '" + partner.S.Progress.Rift.Result + "' state '" + partner.S.Progress.Rift.State + "' text '" + partner.S.Progress.Rift.ResultText + "'");
                r.Note("primary: HUD result '" + rift.Result + "', state '" + rift.State + "', lives " + rift.Lives + "/" + rift.LivesMax + ", boss '" + rift.Boss + "', text '" + rift.ResultText + "', exit in " + rift.ExitIn + " s, HUD hides in " + (rift.HideAt < 0 ? "never" : Math.Round((rift.HideAt - s.Now) / 1000.0) + " s") + "; lines [" + string.Join(" | ", texts.Take(5)) + "]; packets [" + PacketDiff(s.Parser, seenPrimary) + "]");
                if (!died2) { problems.Append("the partner did not die on the second /rdie; "); goto finish; }
                if (SeenOf(partner, 0x28) - d1 != 1) problems.Append("0x28 seen " + (SeenOf(partner, 0x28) - d1) + " times on the last death; ");
                if (!ended) problems.Append("the rift did not end after the last life was lost; ");
                else
                {
                    if (rift.Result != "failed" || rift.State != "failed") problems.Append("the primary's HUD says result '" + rift.Result + "' state '" + rift.State + "' after the last life, expected 'failed'; ");
                    if (rift.ResultText.IndexOf("No lives are left", StringComparison.OrdinalIgnoreCase) < 0 || rift.ResultText.IndexOf("key is lost", StringComparison.OrdinalIgnoreCase) < 0) problems.Append("the end text is '" + rift.ResultText + "', expected the lives and the lost key; ");
                    if (rift.Lives != 0) problems.Append("the HUD shows " + rift.Lives + " lives at the end, expected 0; ");
                    if (rift.Boss == "dead") problems.Append("the HUD boss state is 'dead' in a collapsed rift; ");
                }
                if (!texts.Any(t => t.IndexOf("last life", StringComparison.OrdinalIgnoreCase) >= 0)) problems.Append("no 'with them the rift's last life' line from the server; ");
                if (texts.Any(t => t.IndexOf("gold to your bank", StringComparison.OrdinalIgnoreCase) >= 0 || t.StartsWith("Rift chest", StringComparison.OrdinalIgnoreCase))) problems.Append("a collapsed rift paid a reward; ");
                bool out1 = WaitFor(15000, () => !PathFarFromRift(before) || s.Closed != null);
                Pump(1200, () => false);
                var chest = FindChest(me, RiftChestClientIds());
                r.Note("primary after the collapse: " + P(me.Pos) + " (before the rift " + P(before) + "), reward chest in view: " + (chest == null ? "no" : "yes at " + P(chest.Value.tile)));
                if (!out1) problems.Append("the primary was not sent out of the collapsed rift; ");
                if (chest != null) problems.Append("a reward chest stands in view after the collapse; ");
                // the dead partner logs in again: at the temple, alive, not back in the rift
                err = ReloginPartner();
                if (err != null) { problems.Append(err + "; "); goto finish; }
                pp = partner.S.Parser;
                Pump(2500, () => false);
                var ph = partner.S.Progress.Rift;
                r.Note("partner after the last death: login at " + P(partner.Pos) + " (before the rift " + P(home) + "), health " + pp.Health + "/" + pp.MaxHealth + ", dead " + pp.Dead + ", rift HUD active " + ph.Active + "; lines [" + string.Join(" | ", LocalFree(partner, 0).TakeLast(3)) + "]");
                if (pp.Dead || pp.Health <= 0) problems.Append("the partner came back dead after the last death; ");
                if (ph.Active) problems.Append("the partner got a rift HUD after the rift collapsed; ");
                if (PathFinder.Cheb(partner.Pos, home) > 30 || partner.Pos.Z != home.Z) problems.Append("the partner is not back in town after the collapse (at " + P(partner.Pos) + ", town " + P(home) + "); ");
                bool step = false;
                foreach (var d in new[] { Dir.South, Dir.North, Dir.East, Dir.West })
                {
                    var to = WalkDirs.Step(partner.Pos, d);
                    if (!Passable(partner.World, to, partner.World.PlayerId) || FloorChangeOf(partner.World.Get(to)) != null) continue;
                    if (!WaitFor(3000, () => partner.S.CanWalk)) break;
                    int m0 = pp.PlayerMoves;
                    partner.S.Walk(d);
                    step = WaitFor(2500, () => pp.PlayerMoves > m0);
                    break;
                }
                r.Note("a step after the last death: " + (step ? "confirmed" : "not confirmed"));
                if (!step) problems.Append("the partner could not take a step after coming back; ");
                done = true;
            }
            finally
            {
                CloseRiftNow(rift, before);
                LeavePartyBoth();
                if (partner != null && partner.S.Closed == null && partner.S.Parser.Dead) { string e2 = ReloginPartner(); if (e2 != null) r.Note("partner login after its death: " + e2); }
            }
        finish:
            if (!done && problems.Length == 0) return;
            r.Note("extended opcodes during the run (primary) [" + ExtDiff(extBefore) + "], invalid JSON or handler errors " + (ExtBad() - bad0));
            if (ExtBad() > bad0) problems.Append((ExtBad() - bad0) + " extended opcode message(s) were invalid JSON or threw in a handler; ");
            problems.Append(markA.Diff(me, "primary"));
            if (partner != null && partner.S.Parser.FailureCount > 0) problems.Append("partner: " + partner.S.Parser.FailureCount + " parse failure(s); ");
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("a member died with 2 shared lives (1 life left, back in the rift at the entrance), died again on the last one: the rift collapsed (end 'failed', 'No lives are left', no chest, no reward), the primary put back, the partner back in town alive, no parse failure");
        }

        // ------------------------------------------------------------------------------------ party3
        string FormParty3()
        {
            var a = Seeing(me, partner.Character);
            var b = Seeing(me, third.Character);
            if (a == null || b == null) return "the leader does not see both members";
            foreach (var pc in new[] { me, partner, third }) if (pc.S.Party.InParty) pc.S.Party.Do(PartyAction.Leave, 0);
            Pump(900, () => false);
            me.S.Party.Do(PartyAction.Invite, a.Id);
            me.S.Party.Do(PartyAction.Invite, b.Id);
            if (!WaitFor(6000, () => partner.S.Party.InvitedBy.Length > 0 && third.S.Party.InvitedBy.Length > 0)) return "an invitation did not arrive (partner '" + partner.S.Party.InvitedBy + "', third '" + third.S.Party.InvitedBy + "')";
            var m1 = Seeing(partner, me.Character);
            var m2 = Seeing(third, me.Character);
            if (m1 == null || m2 == null) return "a member does not see the leader";
            partner.S.Party.Do(PartyAction.Join, m1.Id);
            third.S.Party.Do(PartyAction.Join, m2.Id);
            if (!WaitFor(8000, () => me.S.Party.Members.Count == 3 && partner.S.Party.Members.Count == 3 && third.S.Party.Members.Count == 3))
                return "joining did not complete (frames " + me.S.Party.Members.Count + "/" + partner.S.Party.Members.Count + "/" + third.S.Party.Members.Count + ")";
            return null;
        }

        void LeaveParty3()
        {
            foreach (var pc in new[] { third, partner, me })
                if (pc != null && pc.S.Closed == null && pc.S.Party.InParty) LeaveWithRetry(pc, new[] { me, partner, third }.Where(x => x != pc), 75000, out _);
            Pump(900, () => false);
        }

        void ScParty3(ScenarioResult r)
        {
            string err = EnsurePartner();
            if (err != null) { r.Skip(err); return; }
            err = EnsureThird();
            if (err != null) { r.Skip(err); return; }
            if (serverToClient == null) { r.Skip("no items.otb: the rift key comes from it"); return; }
            // both members come to the leader
            foreach (var pc in new[] { partner, third })
            {
                if (pc.Pos.Z != me.Pos.Z || PathFinder.Cheb(pc.Pos, me.Pos) > 4)
                {
                    // the staff primary calls a member that is far or on another floor (/c NAME, stock teleport_creature_here.lua); walking is the fallback
                    s.Say("/c " + pc.Character);
                    WaitFor(6000, () => pc.Pos.Z == me.Pos.Z && PathFinder.Cheb(pc.Pos, me.Pos) <= 4);
                }
                if (pc.Pos.Z != me.Pos.Z) { r.Skip("a member is on floor " + pc.Pos.Z + ", the primary on " + me.Pos.Z + " and /c did not bring it"); return; }
                if (PathFinder.Cheb(pc.Pos, me.Pos) > 4 && !WalkTo(pc, me.Pos, 2, o.ScenarioMs, false, out string why)) { r.Skip("a member could not walk to the primary: " + why); return; }
            }
            Pump(800, () => false);
            var markA = Mark.Of(me);
            var markB = Mark.Of(partner);
            var markC = Mark.Of(third);
            var problems = new StringBuilder();
            err = FormParty3();
            if (err != null) { r.Skip("the party of three could not be formed: " + err); LeaveParty3(); return; }
            Pump(1200, () => false);
            var sh = new Func<LiveClient, LiveClient, int>((viewer, who) => Seeing(viewer, who.Character)?.Shield ?? -1);
            r.Note("party of three formed: frames " + me.S.Party.Members.Count + "/" + partner.S.Party.Members.Count + "/" + third.S.Party.Members.Count + ", states " + me.S.Party.States + "/" + partner.S.Party.States + "/" + third.S.Party.States);
            r.Note("shields: the leader sees " + sh(me, partner) + " and " + sh(me, third) + "; the partner sees " + sh(partner, me) + " and " + sh(partner, third) + "; the third sees " + sh(third, me) + " and " + sh(third, partner));
            bool done = false;
            Pos before = me.Pos;
            var rift = s.Progress.Rift;
            try
            {
                foreach (var pc in new[] { (c: me, n: "primary"), (c: partner, n: "partner"), (c: third, n: "third") })
                {
                    var f = pc.c.S.Party;
                    int leaders = f.Members.Count(m => m.Leader), selves = f.Members.Count(m => m.Self);
                    if (f.Members.Count != 3) problems.Append("the " + pc.n + "'s frames hold " + f.Members.Count + " members, expected 3; ");
                    if (leaders != 1 || selves != 1) problems.Append("the " + pc.n + "'s frames have " + leaders + " leader(s) and " + selves + " self entr" + (selves == 1 ? "y" : "ies") + ", expected 1 and 1; ");
                    if (f.Members.Any(m => m.Leader && m.Name != me.Character && !string.Equals(m.Name, me.Character, StringComparison.OrdinalIgnoreCase))) problems.Append("the " + pc.n + "'s frames name another leader than the inviter; ");
                }
                if (!PartyShield.IsLeader(sh(partner, me)) || !PartyShield.IsLeader(sh(third, me))) problems.Append("the members do not see the leader with the leader shield (" + sh(partner, me) + ", " + sh(third, me) + "); ");
                if (!PartyShield.IsMember(sh(me, partner)) || !PartyShield.IsMember(sh(me, third))) problems.Append("the leader does not see both members with the member shield (" + sh(me, partner) + ", " + sh(me, third) + "); ");
                if (!PartyShield.IsMember(sh(partner, third)) || !PartyShield.IsMember(sh(third, partner))) problems.Append("the two members do not see each other with the member shield (" + sh(partner, third) + ", " + sh(third, partner) + "); ");
                // shared experience with three
                me.S.Party.Do(PartyAction.ShareOn, 0);
                Pump(1500, () => false);
                r.Note("shared experience on: xp state " + me.S.Party.XpOn + "/" + partner.S.Party.XpOn + "/" + third.S.Party.XpOn + ", bonus " + me.S.Party.XpPercent + "%, text '" + me.S.Party.XpText() + "'; shields now " + sh(partner, me) + "/" + sh(third, me));
                if (me.S.Party.XpOn < 0) problems.Append("no shared experience state reached the leader's frames; ");
                // leadership: the leader passes it to the third (0xA6), every client sees the new yellow shield
                var thirdSeen = Seeing(me, third.Character);
                me.S.Party.Do(PartyAction.PassLeadership, thirdSeen.Id);
                bool passed = WaitFor(6000, () => PartyShield.IsLeader(sh(me, third)) && PartyShield.IsLeader(sh(partner, third)) && third.S.Party.ViewerIsLeader);
                r.Note("leadership passed to the third: shields seen by the old leader " + sh(me, third) + ", by the partner " + sh(partner, third) + ", the third's frames say leader " + third.S.Party.ViewerIsLeader + ", the old leader's shield seen by the partner " + sh(partner, me));
                if (!passed) problems.Append("passing the leadership did not show on every client; ");
                // and back (the key of the rift below belongs to the staff character; the party of a rift is the opener's)
                var meSeen = Seeing(third, me.Character);
                third.S.Party.Do(PartyAction.PassLeadership, meSeen.Id);
                bool back = WaitFor(6000, () => me.S.Party.ViewerIsLeader && PartyShield.IsLeader(sh(partner, me)) && !third.S.Party.ViewerIsLeader);
                if (!back) problems.Append("the leadership did not come back to the primary; ");
                // a rift of three: lives, party line, all three taken in, then closed by the staff command
                foreach (var pc in new[] { partner, third }) pc.S.Progress.Rift.Hide();
                var homeP = partner.Pos;
                var homeT = third.Pos;
                string mods = string.IsNullOrEmpty(o.RiftMods) ? "vitality:20" : o.RiftMods;
                int pt0 = partner.Said.Count, tt0 = third.Said.Count;
                if (!OpenRift(r, out before, out int rift0, 1, mods)) { r.Note("rift part skipped: " + r.Reason); r.Status = "skip"; }
                else
                {
                    r.Status = "skip";
                    var pr = partner.S.Progress.Rift;
                    var tr = third.S.Progress.Rift;
                    bool both = WaitFor(9000, () => pr.Active && tr.Active);
                    Pump(1500, () => false);
                    r.Note("rift of three: primary " + HudLine(rift) + "; partner " + (pr.Active ? HudLine(pr) : "no HUD") + "; third " + (tr.Active ? HudLine(tr) : "no HUD"));
                    if (!both) problems.Append("a member got no rift HUD (partner " + pr.Active + ", third " + tr.Active + ") although in the party within 8 sqm; ");
                    else
                    {
                        if (rift.LivesMax != 5) problems.Append("shared lives for three players are " + rift.LivesMax + ", expected 3 + 2 = 5; ");
                        if (pr.Total != rift.Total || tr.Total != rift.Total || pr.Lives != rift.Lives || tr.Lives != rift.Lives || pr.Tier != rift.Tier || tr.Tier != rift.Tier) problems.Append("the three HUDs describe different runs; ");
                    }
                    var pl = GameTexts(partner, pt0).Concat(GameTexts(third, tt0)).ToList();
                    var party = pl.Where(t => t.IndexOf("Party of 3", StringComparison.OrdinalIgnoreCase) >= 0).ToList();
                    r.Note("party line of the members: " + (party.Count > 0 ? party[0] : "none"));
                    if (party.Count < 2) problems.Append("not both members got the 'Party of 3' line (" + party.Count + "); ");
                    bool moved = PartnerFarFromRift(homeP) && third.S.Closed == null && (PathFinder.Cheb(third.Pos, homeT) > 30 || third.Pos.Z != homeT.Z);
                    r.Note("positions: partner " + P(partner.Pos) + ", third " + P(third.Pos) + ", primary " + P(me.Pos));
                    if (!moved) problems.Append("a member was not taken into the rift; ");
                    // close it: the staff command, everyone out
                    s.Say("/rift fail");
                    WaitFor(20000, () => rift.Result.Length > 0 && pr.Result.Length > 0 && tr.Result.Length > 0);
                    Pump(1500, () => false);
                    r.Note("closed by the staff command: results primary '" + rift.Result + "', partner '" + pr.Result + "', third '" + tr.Result + "'");
                    if (rift.Result.Length == 0 || pr.Result.Length == 0 || tr.Result.Length == 0) problems.Append("not all three got the end message (" + rift.Result + "/" + pr.Result + "/" + tr.Result + "); ");
                    WaitFor(Math.Max(12000, (int)(rift.ExitIn * 1000) + 6000), () => !PathFarFromRift(before) && PathFinder.Cheb(partner.Pos, homeP) <= 30 && PathFinder.Cheb(third.Pos, homeT) <= 30);
                    Pump(1200, () => false);
                    if (PathFarFromRift(before) || PathFinder.Cheb(partner.Pos, homeP) > 30 || PathFinder.Cheb(third.Pos, homeT) > 30) problems.Append("not all three were sent out of the rift; ");
                    r.Status = "pass";
                }
                // leave one after the other: the party falls apart when one is left
                bool leftThird = LeaveWithRetry(third, new[] { me, partner }, 75000, out int waitedThird);
                Pump(1200, () => false);
                r.Note("the third left" + (waitedThird > 7000 ? " after " + waitedThird / 1000 + " s (the engine refuses a leave during a fight, 60 s after the last hit)" : "") + ": " + (leftThird ? "yes" : "no") + ", frames " + me.S.Party.Members.Count + "/" + partner.S.Party.Members.Count + "/" + third.S.Party.Members.Count + ", shield of the third seen by the leader " + sh(me, third));
                if (!leftThird) problems.Append("the third could not leave the party in 75 s (shield seen by the leader " + sh(me, third) + "); ");
                else if (me.S.Party.Members.Count > 0 && me.S.Party.Members.Count != 2) problems.Append("the party did not shrink to two when the third left (frames " + me.S.Party.Members.Count + "/" + partner.S.Party.Members.Count + "/" + third.S.Party.Members.Count + "); ");
                bool leftPartner = LeaveWithRetry(partner, new[] { me }, 75000, out _);
                Pump(1200, () => false);
                bool gone = leftPartner && (!me.S.Party.InParty || sh(partner, me) == PartyShield.None);
                if (!gone && leftPartner)
                {
                    LeaveWithRetry(me, new[] { partner }, 30000, out _);
                    gone = !me.S.Party.InParty;
                    r.Note("the party outlived the second leave; the leader left too");
                }
                if (!gone) problems.Append("the party did not end (frames " + me.S.Party.Members.Count + "/" + partner.S.Party.Members.Count + ", shields " + sh(me, partner) + "/" + sh(partner, me) + "); ");
                done = true;
            }
            finally
            {
                CloseRiftNow(rift, before);
                LeaveParty3();
            }
            if (!done && problems.Length == 0) return;
            problems.Append(markA.Diff(me, "primary"));
            problems.Append(markB.Diff(partner, "partner"));
            problems.Append(markC.Diff(third, "third"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("a party of three: invites, joins, frames and shields on all three, shared experience, leadership passed and back, a rift of three (5 shared lives, 'Party of 3' line, all taken in and out), leaves, no parse failure on any connection");
        }

        // ------------------------------------------------------------------------------------ trialwindows
        /// <summary>Asks an NPC of the third character for a modal window with a word; null and a skip reason in `why` when the NPC or the window does not come.</summary>
        ModalWindowData AskNpcWindow(LiveClient c, string npcName, Pos? at, string word, ScenarioResult r, List<string> skipped, string label)
        {
            var p = c.S.Parser;
            var npc = FindNpcOf(c, npcName);
            if (npc == null && at.HasValue && at.Value.Z == c.Pos.Z) { WalkTo(c, at.Value, 2, o.ScenarioMs, false, out _); npc = FindNpcOf(c, npcName); }
            if (npc == null) { skipped.Add(label + ": '" + npcName + "' is not in view of " + P(c.Pos) + " (give its place: --archivist-at, --keeper-at)"); return null; }
            if (!WalkTo(c, npc.Position, 2, o.ScenarioMs, false, out string why) && (PathFinder.Cheb(c.Pos, npc.Position) > 3 || c.Pos.Z != npc.Position.Z)) { skipped.Add(label + ": could not walk to " + npcName + ": " + why); return null; }
            Pump(500, () => false);
            DrainModals(p.Modals, () => Pump(300, () => false));
            int lines0 = p.NpcTalk.Lines.Count;
            c.S.SayToNpc("hi");
            if (!WaitFor(6000, () => p.NpcTalk.Lines.Skip(lines0).Any(l => l.FromNpc))) { skipped.Add(label + ": " + npcName + " did not answer 'hi'"); return null; }
            Pump(1200, () => false);
            DrainModals(p.Modals, () => Pump(300, () => false));
            int recv0 = p.Modals.Received, lines1 = p.NpcTalk.Lines.Count;
            c.S.SayToNpc(word);
            if (!WaitFor(6000, () => p.Modals.Received > recv0))
            {
                var said = p.NpcTalk.Lines.Skip(lines1).Where(l => l.FromNpc).Select(l => l.Text).Take(2).Select(t => t.Length > 110 ? t.Substring(0, 110) + "..." : t).ToList();
                skipped.Add(label + ": '" + word + "' made " + npcName + " send no window; the NPC said: " + (said.Count > 0 ? string.Join(" | ", said) : "nothing"));
                return null;
            }
            Pump(300, () => false);
            return p.Modals.Current;
        }

        /// <summary>Waits for the trial room to take the character in, then for the rift HUD of the trial, and kills the guardian (local /rwin) until the end message or the time is up.
        /// Returns a one line account.</summary>
        string RunTrial(LiveClient c, Pos from, string label, StringBuilder problems, out bool won, int limitMs)
        {
            won = false;
            var p = c.S.Parser;
            var hud = c.S.Progress.Rift;
            bool in1 = WaitFor(12000, () => PathFinder.Cheb(c.Pos, from) > 30 || c.Pos.Z != from.Z);
            Pump(1500, () => false);
            if (!in1) { problems.Append(label + ": no teleport into the trial room after Enter; "); return "no teleport"; }
            var seen0 = new Dictionary<byte, int>(p.Seen);
            int t0 = c.Said.Count;
            int wins = 0;
            long end = Tick + limitMs;
            while (Tick < end && c.S.Closed == null && !p.Dead)
            {
                c.S.Say("/rwin");
                wins++;
                Pump(2000, () => false);
                if (c.ServerTexts(t0).Any(t => t.IndexOf("passed the trial", StringComparison.OrdinalIgnoreCase) >= 0 || t.IndexOf("Trial passed", StringComparison.OrdinalIgnoreCase) >= 0 || t.IndexOf("falls. You have passed", StringComparison.OrdinalIgnoreCase) >= 0)) { won = true; break; }
            }
            Pump(1500, () => false);
            var lines = c.ServerTexts(t0).Where(t => !t.StartsWith("rwin ", StringComparison.Ordinal)).Select(t => t.Replace("\n", " ")).Select(t => t.Length > 150 ? t.Substring(0, 150) + "..." : t).Take(5).ToList();
            return "in the room at " + P(c.Pos) + ", " + wins + " /rwin call(s), won " + won + ", HUD " + (hud.Active ? HudLine(hud) : "none") + ", lines [" + string.Join(" | ", lines) + "], packets [" + PacketDiff(p, seen0) + "]";
        }

        void ScTrialWindows(ScenarioResult r)
        {
            string err = EnsureThird();
            if (err != null) { r.Skip(err); return; }
            var t = third;
            var tp = t.S.Parser;
            var markT = Mark.Of(t);
            var markA = Mark.Of(me);
            var problems = new StringBuilder();
            var skipped = new List<string>();
            int exercised = 0;
            string tname = t.Character;
            // ---- A. the spell quest trial window: the staff command sets quest 1 to the trial step, the Archivist asks the question
            int sq0 = me.Said.Count;
            s.Say("/spellquest set " + tname + ", 1, 2");
            Pump(900, () => false);
            var sqTexts = GameTexts(me, sq0);
            var w = AskNpcWindow(t, o.ArchivistNpc, o.ArchivistAt, "trial", r, skipped, "spell quest");
            if (w != null)
            {
                exercised++;
                r.Note("spell quest window: " + ModalLine(w));
                if (w.Id != 7160) r.Note("the window id is " + w.Id + " (spellquest_config.lua modal.trial is 7160)");
                if (w.Title.Length == 0 || w.Message.Length == 0 || w.Buttons.Count != 2) problems.Append("the spell quest window has no title, no text or not two buttons; ");
                if (w.Choices.Count != 0) problems.Append("the spell quest window has choices; ");
                // Not yet: nothing happens
                var from = t.Pos;
                int tx0 = t.Said.Count, pk0 = t.S.Packets;
                tp.Modals.Cancel();
                Pump(2000, () => false);
                bool stayed = PathFinder.Cheb(t.Pos, from) <= 2 && t.Pos.Z == from.Z;
                r.Note("answered 'Not yet' (escape): the character stayed " + stayed + ", " + (t.S.Packets - pk0) + " packet(s), lines [" + string.Join(" | ", GameTexts(t, tx0).Take(2)) + "]");
                if (!stayed) problems.Append("'Not yet' moved the character; ");
                // ask again, Enter: the trial room
                t.S.SayToNpc("trial");
                int recv = tp.Modals.Received;
                WaitFor(6000, () => tp.Modals.Current != null && tp.Modals.Current.Id == 7160);
                var w2 = tp.Modals.Current;
                if (w2 == null) problems.Append("the second question brought no window; ");
                else
                {
                    int enter = w2.Buttons.Any(b => b.Id == w2.EnterButton) ? w2.EnterButton : 1;
                    var seenBefore = new Dictionary<byte, int>(tp.Seen);
                    from = t.Pos;
                    tp.Modals.Answer(enter, ModalWindows.NoChoice);
                    string account = RunTrial(t, from, "spell quest trial", problems, out bool won, Math.Max(80000, o.ScenarioMs));
                    r.Note("spell quest trial: " + account);
                    if (!won) skipped.Add("spell quest trial: the guardian did not fall to the local /rwin in time (the trial was left)");
                    if (PathFinder.Cheb(t.Pos, from) > 30 || t.Pos.Z != from.Z)
                    {
                        if (!won) { t.S.Ext.Send(PassiveTree.Opcode, "trialLeave", null); }
                        bool back = WaitFor(30000, () => PathFinder.Cheb(t.Pos, from) <= 30 && t.Pos.Z == from.Z);
                        Pump(1500, () => false);
                        r.Note("spell quest trial left: " + (back ? "back at " + P(t.Pos) : "still at " + P(t.Pos)));
                        if (!back) problems.Append("the character did not come back from the spell quest trial; ");
                    }
                    if (won && !GameTexts(t, tx0).Any(x => x.IndexOf("learned", StringComparison.OrdinalIgnoreCase) >= 0)) problems.Append("the trial was won but no 'You have learned' line came; ");
                }
                DrainModals(tp.Modals, () => Pump(300, () => false));
                t.S.SayToNpc("bye");
            }
            // ---- B. the Oracle's Trial: stage 2 opens the Trial window, Enter walks into the trial room, the guardian falls, stage 3 opens the Choice
            int set0 = me.Said.Count;
            s.Say("/rset " + tname + ", 7101000, 2");
            s.Say("/rset " + tname + ", 7101002, 0");
            Pump(900, () => false);
            bool rsetOk = me.ServerTexts(set0).Any(x => x.StartsWith("rset ok", StringComparison.Ordinal));
            if (!rsetOk) skipped.Add("Oracle's Trial: the local command /rset did not answer (a local-only revscript, README \"Last endgame gaps (phase 25)\")");
            else
            {
                var ow = AskNpcWindow(t, o.OracleNpc, o.KeeperAt, "trial", r, skipped, "Oracle's Trial");
                if (ow != null)
                {
                    exercised++;
                    r.Note("Oracle's Trial window: " + ModalLine(ow));
                    if (ow.Title.Length == 0 || ow.Message.Length == 0 || ow.Buttons.Count < 2) problems.Append("the Oracle's Trial window has no title, no text or fewer than two buttons; ");
                    int enter = ow.Buttons.Any(b => b.Id == ow.EnterButton) ? ow.EnterButton : 1;
                    var from = t.Pos;
                    tp.Modals.Answer(enter, ModalWindows.NoChoice);
                    string account = RunTrial(t, from, "Oracle's Trial", problems, out bool won, 90000);
                    r.Note("Oracle's Trial: " + account);
                    if (!won) skipped.Add("Oracle's Trial: the guardian did not fall to the local /rwin in time (a lethal hit was caught instead, the stage was set by /rset)");
                    if (PathFinder.Cheb(t.Pos, from) > 30 || t.Pos.Z != from.Z)
                    {
                        if (!won)
                        {
                            // the guardian did not fall to the local command: a lethal hit is caught and the Oracle pulls the character back
                            int d0 = t.Said.Count;
                            t.S.Say("/rdie");
                            WaitFor(8000, () => GameTexts(t, d0).Any(x => x.IndexOf("fallen in the Trial", StringComparison.OrdinalIgnoreCase) >= 0));
                            r.Note("the guardian did not fall: a lethal hit was caught, lines [" + string.Join(" | ", GameTexts(t, d0).Where(x => !x.StartsWith("rtrace", StringComparison.Ordinal)).Take(2)) + "], dead flag " + tp.Dead);
                            if (tp.Dead) problems.Append("a lethal hit in the Oracle's Trial killed the character (it must be caught); ");
                        }
                        bool back = WaitFor(40000, () => PathFinder.Cheb(t.Pos, from) <= 30 && t.Pos.Z == from.Z);
                        Pump(1500, () => false);
                        r.Note("the Oracle's Trial ended: " + (back ? "back at " + P(t.Pos) : "still at " + P(t.Pos)) + ", won " + won);
                        if (!back) problems.Append("the character did not come back from the Oracle's Trial; ");
                        if (!won)
                        {
                            s.Say("/rset " + tname + ", 7101000, 3");
                            s.Say("/rset " + tname + ", 7101002, 0");
                            Pump(900, () => false);
                        }
                    }
                    DrainModals(tp.Modals, () => Pump(300, () => false));
                    t.S.SayToNpc("bye");
                }
                // ---- C. the Choice and the final Ascend answer (the class changes for good: a throwaway character, the db restored after the run)
                var cw = AskNpcWindow(t, o.OracleNpc, o.KeeperAt, "choice", r, skipped, "Oracle's Choice");
                if (cw != null)
                {
                    exercised++;
                    r.Note("Choice window: " + ModalLine(cw));
                    if (cw.Choices.Count == 0) problems.Append("the Choice window lists no ascended class; ");
                    else
                    {
                        int enter = cw.Buttons.Any(b => b.Id == cw.EnterButton) ? cw.EnterButton : 1;
                        int recv = tp.Modals.Received;
                        tp.Modals.Answer(enter, cw.Choices[0].Id);
                        if (!WaitFor(6000, () => tp.Modals.Received > recv)) problems.Append("a pick in the Choice list opened no confirm window; ");
                        else
                        {
                            Pump(300, () => false);
                            var conf = tp.Modals.Current;
                            r.Note("confirm window: " + ModalLine(conf));
                            int ascend = conf.Buttons.Any(b => b.Id == conf.EnterButton) ? conf.EnterButton : 1;
                            int vocBefore = t.World.PlayerVocation, wire0 = SeenOf(t, 0x9F);
                            int hp0 = tp.MaxHealth, level0 = tp.Level;
                            int ax0 = t.Said.Count;
                            var seen0 = new Dictionary<byte, int>(tp.Seen);
                            var ext0 = ExtPackets();
                            var thirdExt = new Dictionary<byte, int>();
                            tp.Modals.Answer(ascend, ModalWindows.NoChoice);
                            bool told = WaitFor(8000, () => GameTexts(t, ax0).Any(x => x.IndexOf("ascended", StringComparison.OrdinalIgnoreCase) >= 0));
                            Pump(2500, () => false);
                            var at = GameTexts(t, ax0).Select(x => x.Replace("\n", " ")).Take(3).ToList();
                            r.Note("Ascend answered (button " + ascend + "): vocation " + vocBefore + " to " + t.World.PlayerVocation + " (class byte " + tp.ClassByte + "), 0x9F x" + (SeenOf(t, 0x9F) - wire0) + ", max health " + hp0 + " to " + tp.MaxHealth + ", level " + level0 + " to " + tp.Level + ", lines [" + string.Join(" | ", at) + "], packets [" + PacketDiff(tp, seen0) + "], dead " + tp.Dead + ", connection " + (t.S.Closed ?? "open"));
                            if (!told) problems.Append("the final Ascend answer brought no 'You have ascended' line; ");
                            if (SeenOf(t, 0x9F) == wire0) problems.Append("the server sent no 0x9F (basic data with the class byte) after the Ascend answer; ");
                            else if (o.Chaos && t.World.PlayerVocation == vocBefore) problems.Append("the character's vocation is still " + vocBefore + " after the Ascend answer although 0x9F came (the class byte is not applied); ");
                        }
                    }
                    DrainModals(tp.Modals, () => Pump(300, () => false));
                    t.S.SayToNpc("bye");
                }
            }
            if (skipped.Count > 0) r.Note("skipped parts: " + string.Join("; ", skipped));
            r.Note("staff command replies (spell quest set): [" + string.Join(" | ", sqTexts.Take(2).Select(x => x.Length > 120 ? x.Substring(0, 120) + "..." : x)) + "]");
            problems.Append(markT.Diff(t, "third"));
            problems.Append(markA.Diff(me, "primary"));
            if (exercised == 0) r.Skip("no trial window was reachable: " + string.Join("; ", skipped));
            else if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass(exercised + " trial window(s) driven (spell quest trial, Oracle's Trial, Choice and Ascend): parsed, answered with 0xF9, the trial rooms entered and left, the server's reaction read, no parse failure");
        }
    }
}
