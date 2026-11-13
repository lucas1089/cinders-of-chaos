// Rift and Omen edge cases of the live check (O433 phase 26): a mortal character that dies alone inside a rift (riftsolodeath), the Omen arena for a party of two (omenparty)
// and the nova of a Wrathful Guardian on a mortal character (wrathnova). Same rules as LiveScenarios.cs: opt-in by --scenario, a time limit, a pass, fail or skip with the
// reason, names scrubbed from the reports, and what was opened is closed again. The staff commands the rift scenarios use that the server does not have (/rkill, /rnear,
// /rdie, /rsetlives, /rtime, /rgive) are a local-only revscript, see unity/README.md "Rift and Omen edge cases (phase 26)".
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
        /// <summary>Opens a rift or an Omen arena for a client that is not the primary (a mortal partner has no staff command for a key: the local helper /rgive gives one). True when
        /// the rift opened and the HUD of this client says it runs; else the scenario is set to skip and false comes back. `before` is where the client stood.</summary>
        bool OpenRiftAs(LiveClient c, ScenarioResult r, int tier, string mods, bool omen, out Pos before)
        {
            before = c.Pos;
            int keyServer = omen ? o.OmenKeyServerId : o.RiftKeyServerId;
            string keyName = omen ? "Omen Key" : "Rift Key";
            if (serverToClient == null || !serverToClient.TryGetValue(keyServer, out int keyClient)) { r.Skip("no items.otb node for the " + keyName + " (server id " + keyServer + ")"); return false; }
            var p = c.S.Parser;
            var hud = c.S.Progress.Rift;
            c.S.Say(o.RiftKeys);   // keys and loot of an earlier run out of the way (local helper)
            Pump(700, () => false);
            int say0 = c.Said.Count;
            c.S.Say(omen ? "/rgive omen" : "/rgive key " + tier.ToString(CultureInfo.InvariantCulture) + (string.IsNullOrEmpty(mods) ? "" : " " + mods));
            Pump(1500, () => false);
            ushort bagId = p.Inventory.Length > 3 && p.Inventory[3] != null ? (ushort)p.Inventory[3].Id : (ushort)0;
            if (bagId == 0) { r.Skip("no backpack on the character to hold a key"); return false; }
            foreach (var cid in p.Containers.Keys.ToList()) c.S.CloseContainer(cid);
            Pump(400, () => false);
            c.S.UseItem(GameSession.InventoryPos(3), bagId, 0);
            WaitFor(2500, () => p.Containers.Count > 0);
            int slot = -1;
            byte contId = 0;
            foreach (var ct in p.Containers.Values)
            {
                int i = ct.Items.FindIndex(it => it != null && it.Id == keyClient);
                if (i >= 0) { slot = i + ct.FirstIndex; contId = ct.Id; break; }
            }
            if (slot < 0)
            {
                var texts = c.ServerTexts(say0).Take(3).ToList();
                r.Skip("the local helper /rgive gave no " + keyName + " (a local-only revscript, README \"Rift and Omen edge cases (phase 26)\")" + (texts.Count > 0 ? "; server said: " + string.Join(" | ", texts) : ""));
                return false;
            }
            r.Note("a " + keyName + " (client id " + keyClient + ") is in the backpack of the mortal character");
            before = c.Pos;
            int say1 = c.Said.Count;
            hud.Hide();
            hud.State = "";
            c.S.UseItem(GameSession.ContainerPos(contId, slot), (ushort)keyClient, (byte)slot);
            bool entered = WaitFor(Math.Max(30000, o.ScenarioMs), () => (hud.Active && hud.State == "running") || c.S.Closed != null);
            if (!entered)
            {
                var texts = c.ServerTexts(say1).Take(3).ToList();
                r.Skip("the rift did not open within the time limit" + (texts.Count > 0 ? "; server said: " + string.Join(" | ", texts) : " (no slot ready on this server, or the key was refused)"));
                return false;
            }
            Pump(2500, () => false);
            return true;
        }

        /// <summary>FormParty, once more after a pause when the first try fails (a character that just came back from a death is not invitable at once); the server lines are added to the reason.</summary>
        string FormPartyRetry()
        {
            int t0 = me.Said.Count;
            string err = FormParty();
            if (err == null) return null;
            Pump(6000, () => false);
            string err2 = FormParty();
            if (err2 == null) return null;
            var texts = me.ServerTexts(t0).Take(3).ToList();
            var same = me.World.Creatures.Values.Where(c => c.Type == 0 && string.Equals(c.Name, partner.Character, StringComparison.OrdinalIgnoreCase)).Select(c => c.Id + (c.Id == partner.World.PlayerId ? " (its own id)" : " (not its id)") + " at " + P(c.Position)).ToList();
            return err2 + " [the primary knows " + same.Count + " creature(s) of that name: " + string.Join(", ", same) + "; the partner is at " + P(partner.Pos) + ", the primary at " + P(me.Pos) + "; partner in a party " + partner.S.Party.InParty + ", invited by '" + (partner.S.Party.InvitedBy.Length > 0 ? "someone" : "") + "']" + (texts.Count > 0 ? " (server said: " + string.Join(" | ", texts) + ")" : "");
        }

        /// <summary>The partner is alive and standing by the primary before a party scenario starts (an earlier scenario may have left it dead, at a temple on another floor or in a rift
        /// that is over): a dead one logs in again, a far one is called by the staff primary (/c).</summary>
        string BringPartnerBack()
        {
            if (partner == null || partner.S.Closed != null || partner.S.Parser.Dead) { if (partner != null) { string e = ReloginPartner(); if (e != null) return e; } else { string e = EnsurePartner(); if (e != null) return e; } }
            if (partner.Pos.Z != me.Pos.Z || PathFinder.Cheb(partner.Pos, me.Pos) > 6)
            {
                s.Say("/c " + partner.Character);
                WaitFor(6000, () => partner.Pos.Z == me.Pos.Z && PathFinder.Cheb(partner.Pos, me.Pos) <= 6);
                Pump(800, () => false);
            }
            return null;
        }

        /// <summary>The walk step that must work after a login (a stuck character is what the death scenarios guard against). A tile with another creature on it is not tried: the
        /// respawn of a dead character lands beside the temple tile, where the staff partner stands after its /t, and a player in a protection zone looks walkable to the client
        /// (the creature's walkthrough byte) while the server refuses the first step onto it (Player::canWalkthrough wants a second attempt inside 2 s). So the first free tile is
        /// stepped on, and a refused step goes on to the next free tile: only a character that none of its free tiles lets through is stuck (O546).</summary>
        bool StepAfterLogin(LiveClient c)
        {
            var pp = c.S.Parser;
            foreach (var d in new[] { Dir.South, Dir.North, Dir.East, Dir.West, Dir.SouthEast, Dir.SouthWest, Dir.NorthEast, Dir.NorthWest })
            {
                var to = WalkDirs.Step(c.Pos, d);
                var tile = c.World.Get(to);
                if (!Passable(c.World, to, c.World.PlayerId) || FloorChangeOf(tile) != null || HasOtherCreature(tile, c.World.PlayerId)) continue;
                if (!WaitFor(3000, () => c.S.CanWalk)) return false;
                int m0 = pp.PlayerMoves;
                c.S.Walk(d);
                if (WaitFor(2500, () => pp.PlayerMoves > m0)) return true;
            }
            return false;
        }

        /// <summary>True when a creature other than `selfId` stands on the tile.</summary>
        public static bool HasOtherCreature(Tile t, uint selfId) => t != null && t.Things.Any(th => th.IsCreature && th.Creature != null && th.Creature.Id != selfId);

        /// <summary>The rift of a mortal client is ended by its own deadline (the local /rtime): the staff command /rift fail is not for it.</summary>
        void EndRiftOf(LiveClient c, Pos before)
        {
            var hud = c.S.Progress.Rift;
            if (c.S.Closed == null && hud.Active && hud.Result.Length == 0 && !c.S.Parser.Dead)
            {
                c.S.Say(o.RiftTime + " 1");
                WaitFor(15000, () => hud.Result.Length > 0 || c.S.Closed != null);
                WaitFor(Math.Max(10000, (int)(hud.ExitIn * 1000) + 6000), () => PathFinder.Cheb(c.Pos, before) <= 30 && c.Pos.Z == before.Z || c.S.Closed != null);
            }
        }

        // ------------------------------------------------------------------------------------ riftsolodeath
        /// <summary>A mortal character (no staff rights, level 1200) opens a rift alone and dies inside it, twice. The first death leaves lives: the engine's death (0x28, the death
        /// window), the HUD's end message `left` with the lives left, the rift stays open for the fallen player, the next login puts the character back at the entrance with the
        /// HUD. The second death is the last life: end `failed`, the rift collapses, the key is lost (not refunded), the next login is at the temple, alive, with no rift HUD.
        /// The primary (staff) stays outside and must not hear of the run at all.</summary>
        void ScRiftSoloDeath(ScenarioResult r)
        {
            string err = EnsurePartner();
            if (err != null) { r.Skip(err); return; }
            if (serverToClient == null) { r.Skip("no items.otb: the rift key comes from it"); return; }
            if (partner.S.Party.InParty) LeaveWithRetry(partner, new[] { me }, 20000, out _);
            var markA = Mark.Of(me);
            var markB = Mark.Of(partner);
            var problems = new StringBuilder();
            var primaryRift = s.Progress.Rift;
            int primary228 = ops[228].Replies;
            int primaryRiftTexts0 = me.Said.Count;
            Pos home = partner.Pos;
            string mods = string.IsNullOrEmpty(o.RiftMods) ? "vitality:20" : o.RiftMods;
            bool done = false;
            Pos before = home;
            int bad0 = ExtBad();
            try
            {
                if (!OpenRiftAs(partner, r, 1, mods, false, out before)) return;
                var hud = partner.S.Progress.Rift;
                var pp = partner.S.Parser;
                var entry = partner.Pos;
                int lives0 = hud.Lives;
                r.Note("opened alone by the mortal character: " + HudLine(hud) + ", position " + P(home) + " to " + P(entry) + ", health " + pp.Health + "/" + pp.MaxHealth + ", level " + pp.Level);
                if (hud.Lives < 2) problems.Append("a solo rift starts with " + hud.Lives + " life/lives, expected 2 or more for the first death to leave one; ");
                if (PathFinder.Cheb(entry, home) <= 30 && entry.Z == home.Z) problems.Append("the mortal character was not taken into the rift (still at " + P(entry) + "); ");

                // ---- the first death: a life is lost, the rift stays open for the fallen player
                int d0 = SeenOf(partner, 0x28), t0 = partner.Said.Count, e0 = SeenOf(partner, 0x6D);
                var seenDeath = new Dictionary<byte, int>(pp.Seen);
                partner.S.Say("/rdie");
                bool died = WaitFor(10000, () => pp.Dead || partner.S.Closed != null);
                Pump(2500, () => false);
                var deathLines = LocalFree(partner, t0).Take(4).ToList();
                r.Note("first death: dead " + pp.Dead + ", 0x28 x" + (SeenOf(partner, 0x28) - d0) + " (type " + pp.DeathType + ", penalty " + pp.DeathPenalty + "%), health " + pp.Health + "/" + pp.MaxHealth + ", connection " + (partner.S.Closed == null ? "still open" : "closed by the server (" + partner.S.Closed + ")") +
                       "; HUD result '" + hud.Result + "' state '" + hud.State + "' text '" + hud.ResultText + "' lives " + hud.Lives + "/" + hud.LivesMax + "; lines [" + string.Join(" | ", deathLines) + "]; packets [" + PacketDiff(pp, seenDeath) + "]");
                if (!died) { problems.Append("the mortal character did not die after /rdie (the local command is missing?); "); goto finish; }
                if (SeenOf(partner, 0x28) - d0 != 1) problems.Append("0x28 seen " + (SeenOf(partner, 0x28) - d0) + " times on the first death; ");
                if (pp.DeathType != 0 && pp.DeathType != 1) problems.Append("death type " + pp.DeathType + "; ");
                if (pp.DeathPenalty < 0 || pp.DeathPenalty > 100) problems.Append("death penalty " + pp.DeathPenalty + "; ");
                if (hud.Result != "left" || hud.State != "left") problems.Append("the fallen player's HUD says result '" + hud.Result + "' state '" + hud.State + "', expected 'left'; ");
                string wantLives = (lives0 - 1).ToString(CultureInfo.InvariantCulture) + (lives0 - 1 == 1 ? " life left" : " lives left");
                if (hud.ResultText.IndexOf(wantLives, StringComparison.OrdinalIgnoreCase) < 0) problems.Append("the end text does not name '" + wantLives + "' ('" + hud.ResultText + "'); ");
                if (ops[228].Replies != primary228) problems.Append("the primary, who is not in the rift, got " + (ops[228].Replies - primary228) + " rift message(s); ");

                // the same character logs in again: back in the rift at the entrance, alive, with the HUD
                err = ReloginPartner();
                if (err != null) { problems.Append(err + "; "); goto finish; }
                hud = partner.S.Progress.Rift;
                pp = partner.S.Parser;
                WaitFor(6000, () => hud.Active);
                Pump(1500, () => false);
                r.Note("after the first login: position " + P(partner.Pos) + " (entrance " + P(entry) + "), health " + pp.Health + "/" + pp.MaxHealth + ", dead " + pp.Dead + ", HUD " + (hud.Active ? HudLine(hud) : "none") + "; lines [" + string.Join(" | ", LocalFree(partner, 0).TakeLast(3)) + "]");
                if (pp.Dead || pp.Health <= 0) problems.Append("the character came back dead; ");
                if (PathFinder.Cheb(partner.Pos, entry) > 6 || partner.Pos.Z != entry.Z) problems.Append("the fallen player did not return at the rift's entrance (at " + P(partner.Pos) + ", entrance " + P(entry) + "); ");
                if (!hud.Active) problems.Append("the returning player got no rift HUD; ");
                else
                {
                    if (hud.Lives != lives0 - 1) problems.Append("the returning player's HUD shows " + hud.Lives + " lives, expected " + (lives0 - 1) + "; ");
                    if (hud.Result.Length > 0) problems.Append("the returning player's HUD still carries the end '" + hud.Result + "'; ");
                    if (hud.State != "running") problems.Append("the returning player's HUD state is '" + hud.State + "', expected 'running'; ");
                }
                Pump(5500, () => false);   // the shield after a lost life lasts 5 s

                // ---- the last life: the rift collapses, the key is lost
                partner.S.Say("/rsetlives 1");
                WaitFor(3000, () => false);
                Pump(1200, () => false);
                int d1 = SeenOf(partner, 0x28), t1 = partner.Said.Count;
                var seenLast = new Dictionary<byte, int>(pp.Seen);
                partner.S.Say("/rdie");
                bool died2 = WaitFor(10000, () => pp.Dead || partner.S.Closed != null);
                Pump(2500, () => false);
                r.Note("last life: dead " + pp.Dead + ", 0x28 x" + (SeenOf(partner, 0x28) - d1) + " (type " + pp.DeathType + ", penalty " + pp.DeathPenalty + "%); HUD result '" + hud.Result + "' state '" + hud.State + "' lives " + hud.Lives + "/" + hud.LivesMax + " text '" + hud.ResultText + "'; lines [" + string.Join(" | ", LocalFree(partner, t1).Take(4)) + "]; packets [" + PacketDiff(pp, seenLast) + "]");
                if (!died2) { problems.Append("the character did not die on the second /rdie; "); goto finish; }
                if (SeenOf(partner, 0x28) - d1 != 1) problems.Append("0x28 seen " + (SeenOf(partner, 0x28) - d1) + " times on the last death; ");
                if (hud.Result != "failed" || hud.State != "failed") problems.Append("the HUD says result '" + hud.Result + "' state '" + hud.State + "' after the last life, expected 'failed'; ");
                if (hud.ResultText.IndexOf("No lives are left", StringComparison.OrdinalIgnoreCase) < 0 || hud.ResultText.IndexOf("key is lost", StringComparison.OrdinalIgnoreCase) < 0) problems.Append("the end text is '" + hud.ResultText + "', expected the lives and the lost key; ");
                if (hud.Lives != 0) problems.Append("the HUD shows " + hud.Lives + " lives at the end, expected 0; ");

                // log in again: at the temple, alive, no rift HUD, a step works, no key refunded
                err = ReloginPartner();
                if (err != null) { problems.Append(err + "; "); goto finish; }
                hud = partner.S.Progress.Rift;
                pp = partner.S.Parser;
                Pump(3500, () => false);
                serverToClient.TryGetValue(o.RiftKeyServerId, out int keyClient);
                EnsureBagOpen(partner);
                Pump(600, () => false);
                int keys = CarriedCount(partner, keyClient);
                bool step = StepAfterLogin(partner);
                r.Note("after the last login: position " + P(partner.Pos) + " (before the rift " + P(home) + "), health " + pp.Health + "/" + pp.MaxHealth + ", dead " + pp.Dead + ", rift HUD active " + hud.Active + " (state '" + hud.State + "', result '" + hud.Result + "'), Rift Keys carried " + keys + ", a step " + (step ? "confirmed" : "not confirmed") + "; lines [" + string.Join(" | ", LocalFree(partner, 0).TakeLast(3)) + "]");
                if (pp.Dead || pp.Health <= 0) problems.Append("the character came back dead after the last life; ");
                if (hud.Active) problems.Append("a rift HUD is on after the rift collapsed (state '" + hud.State + "', result '" + hud.Result + "'); ");
                if (PathFinder.Cheb(partner.Pos, home) > 30 || partner.Pos.Z != home.Z) problems.Append("the character is not back in town after the collapse (at " + P(partner.Pos) + ", town " + P(home) + "); ");
                if (keys > 0) problems.Append("the lost key came back (" + keys + " Rift Key(s) carried); ");
                if (!step) problems.Append("the character could not take a step after coming back; ");
                if (ops[228].Replies != primary228) problems.Append("the primary, who is not in the rift, got " + (ops[228].Replies - primary228) + " rift message(s); ");
                var strayTexts = me.ServerTexts(primaryRiftTexts0).Where(t => t.IndexOf("rift", StringComparison.OrdinalIgnoreCase) >= 0 && !t.StartsWith("rkeys ", StringComparison.Ordinal)).ToList();
                if (strayTexts.Count > 0) problems.Append("the primary heard of the run: [" + string.Join(" | ", strayTexts.Take(2)) + "]; ");
                done = true;
            }
            finally
            {
                EndRiftOf(partner, before);
                if (partner != null && partner.S.Closed == null && partner.S.Parser.Dead) { string e2 = ReloginPartner(); if (e2 != null) r.Note("login after the death: " + e2); }
                // the temple of the death login is on another floor than the primary: the staff primary calls the character back (the next scenario needs them together)
                if (partner != null && partner.S.Closed == null && (partner.Pos.Z != me.Pos.Z || PathFinder.Cheb(partner.Pos, me.Pos) > 6))
                {
                    s.Say("/c " + partner.Character);
                    WaitFor(6000, () => partner.Pos.Z == me.Pos.Z && PathFinder.Cheb(partner.Pos, me.Pos) <= 6);
                    Pump(800, () => false);
                }
            }
        finish:
            if (!done && problems.Length == 0) return;
            r.Note("invalid JSON or handler errors on the primary during the run: " + (ExtBad() - bad0));
            if (ExtBad() > bad0) problems.Append((ExtBad() - bad0) + " extended opcode message(s) were invalid JSON or threw in a handler; ");
            problems.Append(markA.Diff(me, "primary"));
            if (partner != null) problems.Append(markB.Diff(partner, "mortal"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("a mortal character died alone in a rift twice: first death (0x28, end 'left' with the lives, back at the entrance with the HUD after the login), last life (end 'failed', the rift collapsed, no key back, the next login at the temple, alive, no rift HUD, a step), the primary heard nothing, no parse failure");
        }

        // ------------------------------------------------------------------------------------ omenparty
        /// <summary>The Omen arena for a party of two: the staff primary uses an Omen Key, the mortal partner within 8 sqm comes along. Both get the Omen HUD of one run (omen name,
        /// title, shared lives with the party bonus, the party note), the guardian comes after the start delay, falls to the partner's and the primary's hits, both get the end
        /// message `success` and may open the guardian's chest once each, both come out.</summary>
        void ScOmenParty(ScenarioResult r)
        {
            string err = EnsurePartner();
            if (err != null) { r.Skip(err); return; }
            if (serverToClient == null) { r.Skip("no items.otb: the Omen Key and the chest ids come from it"); return; }
            err = BringPartnerBack();
            if (err != null) { r.Skip("the partner could not be brought back to the primary: " + err); return; }
            err = MeetPartner();
            if (err != null) { r.Skip("the two characters cannot be brought together: " + err); return; }
            var markA = Mark.Of(me);
            var markB = Mark.Of(partner);
            var problems = new StringBuilder();
            var rift = s.Progress.Rift;
            var prift = partner.S.Progress.Rift;
            var pp = partner.S.Parser;
            if (PathFinder.Cheb(me.Pos, partner.Pos) > 6 && !WalkTo(partner, me.Pos, 2, o.ScenarioMs, false, out string closer)) r.Note("the partner could not come closer: " + closer);
            err = FormPartyRetry();
            if (err != null) { r.Skip("the party could not be formed: " + err); return; }
            var partnerBefore = partner.Pos;
            int pTexts0 = partner.Said.Count, mTexts0 = me.Said.Count;
            var extBefore = ExtPackets();
            int bad0 = ExtBad();
            var pExtBefore = new Dictionary<byte, int>(pp.Seen);
            prift.Hide();
            Pos before = me.Pos;
            try
            {
                if (!OpenRift(r, out before, out int rift0, 1, null, true)) return;
                bool pin = WaitFor(8000, () => prift.Active);
                partner.S.Say("/rcalm");   // local helper: the tier 15 guardian kills a 10k mortal in seconds (seen on the first runs); this scenario is about the HUD and the rewards
                Pump(1500, () => false);
                r.Note("primary HUD: " + HudLine(rift) + ", omen '" + rift.Omen + "', title '" + rift.Title + "', notes [" + string.Join(" | ", rift.Notes) + "]");
                r.Note("partner HUD: " + (pin ? HudLine(prift) + ", omen '" + prift.Omen + "', title '" + prift.Title + "', notes [" + string.Join(" | ", prift.Notes) + "]" : "none (opcode 228 start never came)"));
                if (!pin) problems.Append("the partner got no Omen HUD (opcode 228 start) although in the party within 8 sqm; ");
                else
                {
                    if (prift.Omen != rift.Omen || prift.Title != rift.Title || prift.Omen.Length == 0) problems.Append("the two HUDs name different omens or none ('" + rift.Omen + "'/'" + prift.Omen + "', titles '" + rift.Title + "'/'" + prift.Title + "'); ");
                    if (prift.Lives != rift.Lives || prift.LivesMax != rift.LivesMax) problems.Append("the shared lives differ (" + rift.Lives + "/" + rift.LivesMax + " against " + prift.Lives + "/" + prift.LivesMax + "); ");
                    if (rift.LivesMax <= 3) problems.Append("two players in an Omen arena share " + rift.LivesMax + " lives, the party bonus (+1 per extra player) is missing; ");
                }
                bool pmoved = PartnerFarFromRift(partnerBefore);
                r.Note("partner position " + P(partnerBefore) + " to " + P(partner.Pos) + ", " + PathFinder.Cheb(partner.Pos, me.Pos) + " tiles from the primary");
                if (!pmoved) problems.Append("the partner was not taken into the arena (still at " + P(partner.Pos) + "); ");
                else if (partner.Pos.Z != me.Pos.Z || PathFinder.Cheb(partner.Pos, me.Pos) > 5) problems.Append("the partner arrived " + PathFinder.Cheb(partner.Pos, me.Pos) + " tiles from the primary (floor " + partner.Pos.Z + "/" + me.Pos.Z + "); ");
                var startTexts = GameTexts(partner, pTexts0);
                r.Note("partner's server lines on entering: " + startTexts.Count + (startTexts.Count > 0 ? " [" + string.Join(" | ", startTexts.Take(4)) + "]" : ""));
                if (!startTexts.Any(t => t.IndexOf("omen", StringComparison.OrdinalIgnoreCase) >= 0)) problems.Append("the partner got no 'omen' line from the server; ");
                if (!startTexts.Any(t => t.IndexOf("Party of 2", StringComparison.OrdinalIgnoreCase) >= 0)) problems.Append("the partner got no party note line from the server; ");
                // the guardian comes startDelay seconds after the arrival (an Omen arena has no packs)
                WaitFor(30000, () => rift.Boss == "alive" || rift.Boss == "dead" || rift.Result.Length > 0 || s.Closed != null);
                Pump(200, () => false);
                r.Note("guardian: primary HUD boss '" + rift.Boss + "' name '" + rift.BossName + "', partner HUD boss '" + prift.Boss + "' name '" + prift.BossName + "'");
                if (rift.Boss != "alive") { problems.Append("the guardian did not come within the time limit (boss '" + rift.Boss + "'); "); goto finish; }
                if (prift.Boss != "alive" || prift.BossName != rift.BossName) problems.Append("the partner's HUD disagrees about the guardian (boss '" + prift.Boss + "' name '" + prift.BossName + "'); ");
                // no walk and no wait: the guardian of tier 15 kills a mortal in seconds; whether it is in view from the mouth depends on the arena (a note, no check)
                Pump(300, () => false);
                var bossSeenP = partner.World.Creatures.Values.Any(c => c.Type == 1 && rift.BossName.Length > 0 && c.Name.IndexOf(rift.BossName, StringComparison.OrdinalIgnoreCase) >= 0);
                var bossSeenM = world.Creatures.Values.Any(c => c.Type == 1 && rift.BossName.Length > 0 && c.Name.IndexOf(rift.BossName, StringComparison.OrdinalIgnoreCase) >= 0);
                r.Note("the guardian is in view of the primary: " + bossSeenM + ", of the partner: " + bossSeenP);
                // the guardian dies: the partner hits first ('/rkill p' hits as the other member), then the primary
                var bossBefore = new Dictionary<byte, int>(pp.Seen);
                int kills = 0;
                long limit = Tick + 90000;
                while (Tick < limit && s.Closed == null && rift.Result.Length == 0)
                {
                    s.Say(kills < 3 ? o.RiftKill + " p" : o.RiftKill);
                    kills++;
                    Pump(2000, () => rift.Result.Length > 0 || s.Closed != null);
                }
                Pump(1500, () => prift.Result.Length > 0);
                r.Note("guardian '" + rift.BossName + "': " + kills + " kill command(s); primary " + HudLine(rift) + "; partner " + HudLine(prift));
                r.Note("partner packets since the guardian: [" + PacketDiff(pp, bossBefore) + "]; end text [" + prift.ResultText + "]");
                if (rift.Result != "success") { problems.Append("the arena did not end in success (result '" + rift.Result + "'); "); goto finish; }
                if (prift.Result != "success" || prift.Boss != "dead" || prift.State != "success") problems.Append("the partner's HUD did not show the success (result '" + prift.Result + "', boss '" + prift.Boss + "', state '" + prift.State + "'); ");
                if (prift.ExitIn <= 0) problems.Append("the partner's end message gives no exit time; ");
                if (prift.ResultText.IndexOf("guardian falls", StringComparison.OrdinalIgnoreCase) < 0) problems.Append("the partner's end text is '" + prift.ResultText + "', expected the guardian's fall; ");
                // the guardian's chest: every finisher may open it once. No Sealed Coffer in an Omen arena (the coffer belongs to the rift's plan, an arena has none).
                Pump(1200, () => false);
                s.Say(o.RiftGo + " chest");
                partner.S.Say(o.RiftGo + " chest");
                Pump(3000, () => false);
                var ids = RiftChestClientIds();
                var cofferIds = new HashSet<int>();
                foreach (int sid in new[] { o.CofferServerId, o.CofferFallbackServerId }) if (serverToClient.TryGetValue(sid, out int cc)) cofferIds.Add(cc);
                int rewards = 0;
                foreach (var who in new[] { (c: me, name: "primary"), (c: partner, name: "partner") })
                {
                    var chest = FindChest(who.c, ids);
                    if (chest == null) { problems.Append("the " + who.name + " sees no guardian chest (client ids " + string.Join(",", ids) + ") at " + P(who.c.Pos) + "; "); continue; }
                    var (tile, stack, cid) = chest.Value;
                    int t0 = who.c.Said.Count;
                    var seenC = new Dictionary<byte, int>(who.c.S.Parser.Seen);
                    if (PathFinder.Cheb(tile, who.c.Pos) > 1) WalkTo(who.c, tile, 1, 15000, false, out _);
                    who.c.S.UseItem(tile, (ushort)cid, (byte)stack);
                    bool got = WaitFor(8000, () => who.c.ServerTexts(t0).Any(t => t.IndexOf("gold to your bank", StringComparison.OrdinalIgnoreCase) >= 0));
                    Pump(1200, () => false);
                    var tx = GameTexts(who.c, t0);
                    r.Note(who.name + " opened the guardian's chest at " + P(tile) + ": " + (got ? "reward text" : "no reward text") + " [" + string.Join(" | ", tx.Take(3)) + "]; packets [" + PacketDiff(who.c.S.Parser, seenC) + "]");
                    if (got) rewards++; else problems.Append("the " + who.name + " got no reward text from the guardian's chest; ");
                }
                {
                    var chest = FindChest(partner, ids);
                    if (chest != null)
                    {
                        int t0 = partner.Said.Count;
                        partner.S.UseItem(chest.Value.tile, (ushort)chest.Value.id, (byte)chest.Value.stack);
                        Pump(1500, () => false);
                        var again = GameTexts(partner, t0);
                        r.Note("the partner uses the chest again: " + (again.Count > 0 ? string.Join(" | ", again.Take(2)) : "no text"));
                        if (again.Any(t => t.IndexOf("gold to your bank", StringComparison.OrdinalIgnoreCase) >= 0)) problems.Append("the same finisher was paid twice; ");
                    }
                }
                var coffer = FindChest(me, cofferIds);
                r.Note("a Sealed Coffer in the arena: " + (coffer == null ? "none (the coffer belongs to a rift's plan; an arena has none)" : "yes at " + P(coffer.Value.tile)));
                if (coffer != null) problems.Append("a Sealed Coffer stands in an Omen arena; ");
                bool out1 = WaitFor(Math.Max(15000, (int)(rift.ExitIn * 1000) + 8000), () => (!PathFarFromRift(before) && !PartnerFarFromRift(before)) || s.Closed != null || partner.S.Closed != null);
                Pump(1200, () => false);
                r.Note("exit: primary " + P(me.Pos) + " (was " + P(before) + "), partner " + P(partner.Pos) + " (was " + P(partnerBefore) + "), partner connection " + (partner.S.Closed == null ? "open" : "closed: " + partner.S.Closed) + ", primary connection " + (s.Closed == null ? "open" : "closed: " + s.Closed));
                if (PathFarFromRift(before)) problems.Append("the primary was not sent out of the arena; ");
                if (PathFinder.Cheb(partner.Pos, partnerBefore) > 30 || partner.Pos.Z != partnerBefore.Z) problems.Append("the partner was not sent out of the arena; ");
            }
            finally
            {
                CloseRiftNow(rift, before);
                LeavePartyBoth();
            }
        finish:
            r.Note("HUD results: primary '" + rift.Result + "', partner '" + prift.Result + "'; extended opcodes during the run (primary) [" + ExtDiff(extBefore) + "], invalid JSON or handler errors " + (ExtBad() - bad0));
            if (ExtBad() > bad0) problems.Append((ExtBad() - bad0) + " extended opcode message(s) were invalid JSON or threw in a handler; ");
            problems.Append(markA.Diff(me, "primary"));
            problems.Append(markB.Diff(partner, "partner"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("a party of two in an Omen arena: both got the Omen HUD of one run with the party note and the shared lives, the guardian came and fell, both HUDs showed the success, both opened the guardian's chest once (a repeat was refused), no coffer, both came out, no parse failure");
        }

        // ------------------------------------------------------------------------------------ wrathnova
        /// <summary>The nova of a Wrathful Guardian on a mortal character. The staff primary and the mortal partner (level 1200, 10253 health) take a tier 5 rift with the Wrath
        /// modifier (--wrath-mods), the primary clears the packs with the local kill command, the partner goes next to the guardian (local /rnear) and stays there. The server marks
        /// the ring (0x83 effects) every 8 s and 1.2 s later hits every run player inside it with a share of the maximum health as death damage, no attacker (rift.lua wrathTick,
        /// markedStrike, percentHit). What the partner's client reads: the damage numbers (message type 24), the effects, the health (0xA0), the health bar of the creature (0x8C).</summary>
        void ScWrathNova(ScenarioResult r)
        {
            string err = EnsurePartner();
            if (err != null) { r.Skip(err); return; }
            if (serverToClient == null) { r.Skip("no items.otb: the rift key comes from it"); return; }
            err = BringPartnerBack();
            if (err != null) { r.Skip("the partner could not be brought back to the primary: " + err); return; }
            err = MeetPartner();
            if (err != null) { r.Skip("the two characters cannot be brought together: " + err); return; }
            var markA = Mark.Of(me);
            var markB = Mark.Of(partner);
            var problems = new StringBuilder();
            var rift = s.Progress.Rift;
            var prift = partner.S.Progress.Rift;
            var pp = partner.S.Parser;
            if (PathFinder.Cheb(me.Pos, partner.Pos) > 6 && !WalkTo(partner, me.Pos, 2, o.ScenarioMs, false, out string closer)) r.Note("the partner could not come closer: " + closer);
            err = FormPartyRetry();
            if (err != null) { r.Skip("the party could not be formed: " + err); return; }
            prift.Hide();
            var fxEvents = new List<FxEvent>();
            var healthSeries = new List<(long t, int hp)>();
            int bad0 = ExtBad();
            var extBefore = ExtPackets();
            string mods = string.IsNullOrEmpty(o.WrathMods) ? "wrath:20" : o.WrathMods;
            Pos before = me.Pos;
            bool done = false;
            int pTexts0 = partner.Said.Count, mTexts0 = me.Said.Count;
            try
            {
                if (!OpenRift(r, out before, out int rift0, o.GuardianTier, mods)) return;
                bool pin = WaitFor(8000, () => prift.Active);
                Pump(1500, () => false);
                if (!pin) { r.Skip("the mortal partner was not taken into the rift (the local helper sets the game storage 7100990 = 1)"); return; }
                partner.World.Fx.Tap = e => { if (fxEvents.Count < 4000) fxEvents.Add(e); };
                r.Note("rift opened for two: primary " + HudLine(rift) + ", mods [" + string.Join("; ", rift.Mods.Select(RiftHud.ModLine)) + "]; partner " + HudLine(prift) + ", health " + pp.Health + "/" + pp.MaxHealth);
                if (rift.Mods.All(m => m.Name.IndexOf("Wrathful", StringComparison.OrdinalIgnoreCase) < 0)) { r.Skip("the rift has no Wrathful Guardian modifier (the key asked for '" + mods + "'; the guardian needs tier 4 or more)"); return; }
                partner.S.Say("/rtrace");   // local helper: the server log gets every hit the partner takes
                partner.S.Say("/rcalm");    // local helper: no damage from monsters (the guardian's own attacks killed a 10k character in 1 s), only the nova, which has no attacker
                Pump(600, () => false);
                // the packs: the primary (staff) clears them, so no reflected damage reaches the mortal
                int packs0 = rift.Killed, waves = 0;
                long limit = Tick + Math.Max(150000, o.ScenarioMs * 3);
                while (Tick < limit && s.Closed == null && rift.Boss != "alive" && rift.Boss != "dead" && rift.Result.Length == 0)
                {
                    s.Say(o.RiftKill);
                    waves++;
                    Pump(1500, () => rift.Boss == "alive" || rift.Boss == "dead" || rift.Result.Length > 0 || s.Closed != null);
                    if (waves == 3 && rift.Killed == packs0) { r.Skip("the staff kill command '" + o.RiftKill + "' killed nothing in 3 tries (a local-only revscript, README \"Rift and Omen edge cases (phase 26)\")"); return; }
                }
                r.Note("packs: " + waves + " wave(s), kills " + packs0 + " to " + rift.Killed + " of " + rift.BossAt + ", boss '" + rift.Boss + "'");
                if (rift.Boss != "alive") { problems.Append("the guardian did not come within the time limit (boss '" + rift.Boss + "'); "); goto finish; }
                // the mortal goes next to the guardian
                var from = partner.Pos;
                partner.S.Say(o.RiftNear);
                bool moved = WaitFor(6000, () => partner.Pos.Z != from.Z || PathFinder.Cheb(partner.Pos, from) > 4);
                Pump(1800, () => false);
                var boss = partner.World.Creatures.Values.Where(c => c.Type == 1 && rift.BossName.Length > 0 && c.Name.IndexOf(rift.BossName, StringComparison.OrdinalIgnoreCase) >= 0).OrderBy(c => PathFinder.Cheb(c.Position, partner.Pos)).FirstOrDefault();
                r.Note("the partner moved next to the guardian by '" + o.RiftNear + "': " + (moved ? P(from) + " to " + P(partner.Pos) : "no move") + "; guardian in view: " + (boss == null ? "no" : "yes, " + PathFinder.Cheb(boss.Position, partner.Pos) + " tiles away"));
                if (!moved || boss == null) { problems.Append("the partner could not be put next to the guardian; "); goto finish; }
                int maxHp = pp.MaxHealth;
                int fx0 = fxEvents.Count, line0 = partner.Said.Count;
                var seen0 = new Dictionary<byte, int>(pp.Seen);
                int hp0 = pp.Health, lowest = pp.Health, drops = 0;
                int last = pp.Health;
                int packets0 = (int)partner.S.Packets;
                long end = Tick + 40000;
                long lastDropAt = 0;
                int novaDrops = 0;
                long tStart = Tick;
                while (Tick < end && s.Closed == null && partner.S.Closed == null && rift.Result.Length == 0 && !pp.Dead)
                {
                    Pump(100, () => false);
                    if (pp.Health != last)
                    {
                        healthSeries.Add((Tick - tStart, pp.Health));
                        if (pp.Health < last) drops++;
                        last = pp.Health;
                    }
                    lowest = Math.Min(lowest, pp.Health);
                    // two hits that are a nova by their size (the share of the maximum health) end the watch
                    novaDrops = DamageNumbers(fxEvents.Skip(fx0)).Count(n => n.hit >= 0.15 * maxHp);
                    if (novaDrops >= 2 && Tick - lastDropAt > 2500) break;
                    if (novaDrops > 0 && lastDropAt == 0) lastDropAt = Tick;
                }
                Pump(1500, () => false);
                var evs = fxEvents.Skip(fx0).ToList();
                var numbers = DamageNumbers(evs).ToList();
                var rings = evs.Where(e => e.Kind == FxKind.Effect).GroupBy(e => e.Id).OrderByDescending(g => g.Count()).Take(4).Select(g => "effect " + g.Key + " x" + g.Count()).ToList();
                var anim = evs.Where(e => e.Kind == FxKind.AnimText).Take(4).Select(e => "'" + e.Text + "' colour " + e.Color).ToList();
                var lines = LocalFree(partner, line0).Where(t => !t.StartsWith("rtrace ", StringComparison.Ordinal)).Take(8).ToList();
                var rtrace = me.ServerTexts(mTexts0).Where(t => t.StartsWith("rtrace ", StringComparison.Ordinal)).Take(2).ToList();
                r.Note("the watch: " + (Tick - tStart) / 1000 + " s beside the guardian, health " + hp0 + " to " + pp.Health + " of " + maxHp + ", lowest " + lowest + ", " + drops + " drop(s), dead " + pp.Dead + "; damage numbers read: " +
                       numbers.Count + " [" + string.Join(" | ", numbers.Take(10).Select(n => n.hit + " (" + Math.Round(100.0 * n.hit / maxHp, 1).ToString(CultureInfo.InvariantCulture) + "% of the maximum, type " + n.type + (n.typed ? ", typed percent " + n.percent + " impact " + n.impact : "") + ")")) + "]");
                r.Note("effects read by the partner: " + evs.Count(e => e.Kind == FxKind.Effect) + " [" + string.Join(", ", rings) + "], animated texts " + evs.Count(e => e.Kind == FxKind.AnimText) + (anim.Count > 0 ? " [" + string.Join(" | ", anim) + "]" : "") + ", squares " + evs.Count(e => e.Kind == FxKind.Square) + ", missiles " + evs.Count(e => e.Kind == FxKind.Missile));
                r.Note("lines of the partner [" + string.Join(" | ", lines) + "]; packets since the guardian [" + PacketDiff(pp, seen0) + "]; the server trace [" + string.Join(" | ", rtrace) + "]");
                var healthPct = new List<string>();
                var bossNow = partner.World.Creatures.Values.FirstOrDefault(c => c.Type == 1 && rift.BossName.Length > 0 && c.Name.IndexOf(rift.BossName, StringComparison.OrdinalIgnoreCase) >= 0);
                r.Note("the partner's own health series (ms since the start of the watch): " + string.Join(", ", healthSeries.Take(24).Select(x => x.t + ":" + x.hp)) + "; guardian health bar " + (bossNow == null ? "gone" : bossNow.HealthPercent + "%"));
                if (numbers.Count == 0 && drops == 0) { problems.Append("no damage reached the mortal character in " + (Tick - tStart) / 1000 + " s beside the Wrathful Guardian: no damage number, no health drop (the nova should fire every 8 s); "); goto finish; }
                if (numbers.Count == 0) problems.Append("the health dropped " + drops + " time(s) but no damage number (message type 24) was read; ");
                // the nova: a hit of the wrath modifier's share of the maximum health (20% less the character's resistance to death damage), one every 8 s
                var novas = numbers.Where(n => n.hit >= 0.12 * maxHp && n.hit <= 0.30 * maxHp).ToList();
                if (novas.Count == 0) problems.Append("no hit of 12 to 30% of the maximum health reached the mortal character (the nova of '" + mods + "'); the hits read were [" + string.Join(", ", numbers.Take(8).Select(n => n.hit)) + "]; ");
                else r.Note("the nova hit " + novas.Count + " time(s) for " + string.Join(", ", novas.Select(n => n.hit + " (" + Math.Round(100.0 * n.hit / maxHp, 1).ToString(CultureInfo.InvariantCulture) + "%)")) + " with the wrath modifier at " + mods);
                if (rings.Count == 0) problems.Append("no magic effect (0x83) reached the partner while the nova marked the ring; ");
                if (partner.Thrown.Count > 0) problems.Append("the partner's session threw: " + partner.Thrown[0] + "; ");
                // the guardian dies, the run ends
                if (!pp.Dead)
                {
                    int kills = 0;
                    long limit2 = Tick + 90000;
                    while (Tick < limit2 && s.Closed == null && rift.Result.Length == 0)
                    {
                        s.Say(o.RiftKill);
                        kills++;
                        Pump(2000, () => rift.Result.Length > 0 || s.Closed != null);
                    }
                    r.Note("the guardian killed by " + kills + " command(s): primary result '" + rift.Result + "', partner result '" + prift.Result + "'");
                    if (rift.Result != "success") problems.Append("the rift did not end in success (result '" + rift.Result + "'); ");
                    WaitFor(Math.Max(15000, (int)(rift.ExitIn * 1000) + 8000), () => (!PathFarFromRift(before) && !PartnerFarFromRift(before)) || s.Closed != null || partner.S.Closed != null);
                    Pump(1200, () => false);
                }
                else
                {
                    r.Note("the partner died beside the guardian (0x28 x" + SeenOf(partner, 0x28) + "): the nova and the guardian's own attacks together");
                }
                done = true;
            }
            finally
            {
                partner.World.Fx.Tap = null;
                CloseRiftNow(rift, before);
                LeavePartyBoth();
                if (partner != null && partner.S.Closed == null && partner.S.Parser.Dead) { string e2 = ReloginPartner(); if (e2 != null) r.Note("partner login after its death: " + e2); }
            }
        finish:
            if (!done && problems.Length == 0) return;
            r.Note("extended opcodes during the run (primary) [" + ExtDiff(extBefore) + "], invalid JSON or handler errors " + (ExtBad() - bad0));
            if (ExtBad() > bad0) problems.Append((ExtBad() - bad0) + " extended opcode message(s) were invalid JSON or threw in a handler; ");
            problems.Append(markA.Diff(me, "primary"));
            if (partner != null) problems.Append(markB.Diff(partner, "mortal"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("a Wrathful Guardian's nova hit a mortal character with 10k health: damage numbers, effects and health read, no parse failure, no exception");
        }

        /// <summary>The damage the character received (message type 24 numbers): the first and the second value summed, with the message type and the typed fields.</summary>
        static IEnumerable<(long hit, int type, bool typed, int percent, int impact)> DamageNumbers(IEnumerable<FxEvent> events)
        {
            foreach (var e in events)
                if (e.Kind == FxKind.Number && e.Id == 24)
                    yield return ((long)e.Value + e.Value2, e.Id, e.Typed, e.Percent, e.Impact);
        }
    }
}
