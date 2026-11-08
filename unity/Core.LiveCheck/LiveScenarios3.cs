// More play scenarios of the live check (O433 phase 23): modal (an NPC's modal window, 0xFA in, answer 0xF9 out) and riftboss (a rift cleared to its guardian, the guardian
// killed, the reward chest opened). Same rules as LiveScenarios.cs: opt-in by --scenario, a time limit, a pass, fail or skip with the reason, and what was opened is closed again.
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
        /// <summary>How many packets each extended opcode brought so far (the table's opcodes and the ones outside it).</summary>
        Dictionary<byte, int> ExtPackets()
        {
            var d = new Dictionary<byte, int>();
            foreach (var kv in ops) if (kv.Value.RawReplies > 0) d[kv.Key] = kv.Value.RawReplies;
            foreach (var kv in other) d[kv.Key] = kv.Value.RawReplies;
            return d;
        }

        /// <summary>Invalid JSON and handler exceptions on every extended opcode so far.</summary>
        int ExtBad() => ops.Values.Sum(x => x.Invalid + x.HandlerErrors) + other.Values.Sum(x => x.Invalid + x.HandlerErrors);

        /// <summary>"228 x73 245 x4": the extended opcodes that brought packets since `before`.</summary>
        string ExtDiff(Dictionary<byte, int> before)
        {
            var now = ExtPackets();
            return string.Join(" ", now.Where(kv => kv.Value > (before.TryGetValue(kv.Key, out int n) ? n : 0)).OrderBy(kv => kv.Key)
                .Select(kv => kv.Key.ToString(CultureInfo.InvariantCulture) + " x" + (kv.Value - (before.TryGetValue(kv.Key, out int n2) ? n2 : 0))));
        }

        /// <summary>"6E x1 70 x2": the packet types the parser read since `before`, with their counts (the ping is left out).</summary>
        static string PacketDiff(GameParser p, Dictionary<byte, int> before)
        {
            return string.Join(" ", p.Seen.Where(kv => kv.Key != 0x1D && kv.Value > (before.TryGetValue(kv.Key, out int n) ? n : 0)).OrderBy(kv => kv.Key)
                .Select(kv => kv.Key.ToString("X2", CultureInfo.InvariantCulture) + " x" + (kv.Value - (before.TryGetValue(kv.Key, out int n2) ? n2 : 0))));
        }

        static int Delta(Dictionary<byte, int> before, GameParser p, byte op) => (p.Seen.TryGetValue(op, out int now) ? now : 0) - (before.TryGetValue(op, out int b) ? b : 0);

        // ------------------------------------------------------------------------------------ modal
        /// <summary>The window's id, title, message, buttons and choices as one report line (the title and the button texts are game text, no names).</summary>
        static string ModalLine(ModalWindowData w)
        {
            return "id " + w.Id + ", title '" + w.Title + "', message " + w.Message.Length + " chars, buttons " + string.Join(",", w.Buttons.Select(b => b.Id + ":" + b.Text)) +
                   ", " + w.Choices.Count + " choice(s)" + (w.Choices.Count > 0 ? " (" + string.Join(", ", w.Choices.Take(3).Select(c => c.Id + ":" + c.Text)) + (w.Choices.Count > 3 ? ", ..." : "") + ")" : "") +
                   ", enter " + w.EnterButton + ", escape " + w.EscapeButton + (w.Priority ? ", priority" : "");
        }

        void ScModal(ScenarioResult r)
        {
            var p = s.Parser;
            var mark = Mark.Of(me);
            var problems = new StringBuilder();
            var npc = FindNpc(o.ModalNpc);
            if (npc == null && o.ModalAt.HasValue)
            {
                var hint = o.ModalAt.Value;
                if (hint.Z != me.Pos.Z) { r.Skip("no NPC '" + o.ModalNpc + "' in view and the --modal-at hint is on floor " + hint.Z + ", the player on " + me.Pos.Z); return; }
                WalkTo(me, hint, 2, o.ScenarioMs, false, out string approach);
                r.Note("approach to the hint " + P(hint) + ": " + (approach.Length == 0 ? "arrived" : approach));
                npc = FindNpc(o.ModalNpc);
            }
            if (npc == null) { r.Skip("NPC '" + o.ModalNpc + "' is not in view of " + P(me.Pos) + " (--modal-npc NAME, --modal-at X,Y,Z; the character must be at the NPC's town)"); return; }
            // within 2 tiles when a way leads there; an NPC behind a market counter is reached to within 3 (the stock NPC talk radius)
            if (!WalkTo(me, npc.Position, 2, o.ScenarioMs, false, out string why))
            {
                if (PathFinder.Cheb(me.Pos, npc.Position) > 3 || me.Pos.Z != npc.Position.Z) { r.Fail("could not walk to " + o.ModalNpc + ": " + why); return; }
                r.Note("the NPC stands behind a counter: talking from " + PathFinder.Cheb(me.Pos, npc.Position) + " tiles");
            }
            Pump(500, () => false);
            // a window left over from the login (a tutorial or a welcome) is answered first, so the one we ask for is the one on screen
            int old = 0;
            while (p.Modals.Current != null && old < 5) { p.Modals.Cancel(); old++; Pump(300, () => false); }
            if (old > 0) r.Note("answered " + old + " window(s) the server had sent before");
            int lines0 = p.NpcTalk.Lines.Count;
            s.SayToNpc("hi");
            if (!WaitFor(6000, () => p.NpcTalk.Lines.Skip(lines0).Any(l => l.FromNpc))) { r.Fail("the NPC did not answer 'hi' (distance " + PathFinder.Cheb(npc.Position, me.Pos) + ")"); return; }
            int recv0 = p.Modals.Received, win0 = Seen(0xFA), say0 = me.Said.Count, lines1 = p.NpcTalk.Lines.Count;
            s.SayToNpc(o.ModalWord);
            if (!WaitFor(6000, () => p.Modals.Received > recv0))
            {
                var said = p.NpcTalk.Lines.Skip(lines1).Where(l => l.FromNpc).Select(l => l.Text).Take(2).ToList();
                s.SayToNpc("bye");
                r.Skip("'" + o.ModalWord + "' made " + o.ModalNpc + " send no modal window (0xFA seen " + (Seen(0xFA) - win0) + " time(s)); the NPC said: " + (said.Count > 0 ? string.Join(" | ", said) : "nothing"));
                return;
            }
            Pump(300, () => false);
            var w = p.Modals.Current;
            r.Note("window 1 (0xFA x" + (Seen(0xFA) - win0) + "): " + ModalLine(w));
            if (w.Title.Length == 0) problems.Append("the window has no title; ");
            if (w.Buttons.Count == 0) problems.Append("the window has no button; ");
            if (w.Buttons.Select(b => b.Id).Distinct().Count() != w.Buttons.Count) problems.Append("two buttons share an id; ");
            if (w.Buttons.Count > 0 && !w.Buttons.Any(b => b.Id == w.EnterButton)) r.Note("the enter button " + w.EnterButton + " is not one of the button ids");
            if (w.Buttons.Count > 0 && !w.Buttons.Any(b => b.Id == w.EscapeButton)) r.Note("the escape button " + w.EscapeButton + " is not one of the button ids");
            uint firstId = w.Id;
            // answer a button and a choice: the enter button (Read in the list of tales) with the first choice
            int button = w.Buttons.Any(b => b.Id == w.EnterButton) ? w.EnterButton : (w.Buttons.Count > 0 ? w.Buttons[0].Id : 0);
            int choice = w.Choices.Count > 0 ? w.Choices[0].Id : ModalWindows.NoChoice;
            int recv1 = p.Modals.Received, lines2 = p.NpcTalk.Lines.Count, say1 = me.Said.Count, packets1 = s.Packets;
            if (!p.Modals.Answer(button, choice)) { r.Fail("the window on screen could not be answered"); return; }
            r.Note("answered 0xF9: window " + firstId + ", button " + button + ", choice " + (choice == ModalWindows.NoChoice ? "none" : choice.ToString(CultureInfo.InvariantCulture)));
            // the server got it when it reacts: a second window (the tale), an NPC line or a server text
            bool reacted = WaitFor(6000, () => p.Modals.Received > recv1 || p.NpcTalk.Lines.Skip(lines2).Any(l => l.FromNpc) || me.ServerTexts(say1).Count > 0);
            Pump(400, () => false);
            if (!reacted) problems.Append("the answer (button " + button + ", choice " + choice + ") brought no reaction: no new window, no NPC line, no server text; ");
            else if (p.Modals.Received > recv1)
            {
                var w2 = p.Modals.Current;
                r.Note("window 2, the server's reaction to the answer: " + ModalLine(w2));
                // the answer carried the choice: the list entry we picked is the title of the window that came back (the list's " (new)" mark cut off)
                if (w.Choices.Count > 0)
                {
                    string picked = w.Choices[0].Text;
                    int paren = picked.LastIndexOf(" (", StringComparison.Ordinal);
                    if (paren > 0) picked = picked.Substring(0, paren);
                    r.Note("the choice reached the server: window 2's title " + (w2.Title.IndexOf(picked, StringComparison.OrdinalIgnoreCase) >= 0 ? "names the entry we picked ('" + picked + "')" : "does not name the entry we picked ('" + picked + "'), the NPC may order its list differently"));
                }
                if (w2.Id == firstId && w.Choices.Count > 0 && w.Choices.Count == w2.Choices.Count && w.Message == w2.Message) problems.Append("the same window came back unchanged; ");
                if (w2.Title.Length == 0) problems.Append("window 2 has no title; ");
                // the escape button, no choice: the window closes and nothing more comes
                int recv2 = p.Modals.Received;
                p.Modals.Cancel();
                Pump(1800, () => false);
                r.Note("escape answer: " + (p.Modals.Received > recv2 ? "the server sent another window" : "no further window") + ", " + p.Modals.Queue.Count + " window(s) left in the queue");
            }
            else r.Note("the answer made the server say: " + string.Join(" | ", me.ServerTexts(say1).Take(2).Concat(p.NpcTalk.Lines.Skip(lines2).Where(l => l.FromNpc).Select(l => l.Text).Take(2))));
            p.Modals.Clear();
            s.SayToNpc("bye");
            Pump(600, () => false);
            if (s.Closed != null) problems.Append("the connection closed: " + s.Closed + "; ");
            problems.Append(mark.Diff(me, "primary"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("modal window 0xFA parsed (id " + firstId + ", " + w.Buttons.Count + " button(s), " + w.Choices.Count + " choice(s)), answered 0xF9 with a button and a choice, the server reacted" + (p.Modals.Received > recv1 ? " with a second window" : "") + ", no parse failure");
        }

        // ------------------------------------------------------------------------------------ rift boss
        /// <summary>The chest item of the rift reward: its client ids (rift_config.lua chest.itemId, then the stock fallback id) from the otb.</summary>
        HashSet<int> RiftChestClientIds()
        {
            var ids = new HashSet<int>();
            if (serverToClient == null) return ids;
            foreach (int server in new[] { o.RiftChestServerId, o.RiftChestFallbackServerId })
                if (serverToClient.TryGetValue(server, out int c)) ids.Add(c);
            return ids;
        }

        /// <summary>The nearest tile in view that holds one of the chest ids, with the stack position of the item on it.</summary>
        (Pos tile, int stack, int id)? FindChest(LiveClient a, HashSet<int> ids)
        {
            (Pos, int, int)? best = null;
            int bd = int.MaxValue;
            foreach (var kv in a.World.Tiles)
            {
                if (kv.Key.Z != a.Pos.Z) continue;
                for (int i = 0; i < kv.Value.Things.Count; i++)
                {
                    var th = kv.Value.Things[i];
                    if (th.IsCreature || th.Item == null || !ids.Contains(th.Item.Id)) continue;
                    int d = PathFinder.Cheb(kv.Key, a.Pos);
                    if (d < bd) { bd = d; best = (kv.Key, i, th.Item.Id); }
                }
            }
            return best;
        }

        void ScRiftBoss(ScenarioResult r)
        {
            var p = s.Parser;
            var mark = Mark.Of(me);
            var problems = new StringBuilder();
            var rift = s.Progress.Rift;
            var extBefore = ExtPackets();
            int bad0 = ExtBad();
            var seen0 = new Dictionary<byte, int>(p.Seen);
            int texts0 = me.Said.Count;
            if (serverToClient == null) { r.Skip("no items.otb: the rift key and the chest ids come from it"); return; }
            var actions = new List<string>();
            bool recording = true;
            s.Ext.On(228, m => { if (recording && actions.Count < 400) actions.Add(m.Action); });
            if (!OpenRift(r, out Pos before, out int rift0)) { recording = false; return; }
            var states = new List<string>();
            Action snap = () =>
            {
                string st = (rift.Boss.Length > 0 ? rift.Boss : "-") + "/" + (rift.State.Length > 0 ? rift.State : "-") + " " + rift.Killed + " of " + rift.BossAt + " (total " + rift.Total + ")";
                if (states.Count == 0 || !states[states.Count - 1].StartsWith((rift.Boss.Length > 0 ? rift.Boss : "-") + "/" + (rift.State.Length > 0 ? rift.State : "-"), StringComparison.Ordinal)) states.Add(st);
            };
            snap();
            r.Note("rift opened: tier " + rift.Tier + ", " + rift.Total + " monsters, the guardian after " + rift.BossAt + " kills, theme '" + rift.Theme + "', " + rift.Mods.Count + " modifier(s), position " + P(before) + " to " + P(me.Pos));
            bool done = false;
            try
            {
                int packs0 = rift.Killed, waves = 0;
                long limit = Tick + Math.Max(150000, o.ScenarioMs * 3);
                // 1. the packs: the staff command kills every monster round the character until the guardian comes
                while (Tick < limit && s.Closed == null && rift.Boss != "alive" && rift.Boss != "dead" && rift.Result.Length == 0)
                {
                    s.Say(o.RiftKill);
                    waves++;
                    Pump(1500, () => rift.Boss == "alive" || rift.Boss == "dead" || rift.Result.Length > 0 || s.Closed != null);
                    snap();
                    if (waves == 3 && rift.Killed == packs0)
                    {
                        var texts = me.ServerTexts(texts0).Where(t => t.IndexOf("rift", StringComparison.OrdinalIgnoreCase) < 0).Take(3).ToList();
                        r.Skip("the staff kill command '" + o.RiftKill + "' killed nothing in 3 tries: this server has no such command (a local-only revscript for the run, README \"Rift boss and modal windows (phase 23)\"); the rift has " +
                               rift.Total + " monsters and the guardian comes after " + rift.BossAt + " kills" + (texts.Count > 0 ? "; server said: " + string.Join(" | ", texts) : ""));
                        return;
                    }
                }
                r.Note("packs: " + waves + " wave(s) of '" + o.RiftKill + "', kills " + packs0 + " to " + rift.Killed + " of " + rift.BossAt + " (total " + rift.Total + "), HUD boss '" + rift.Boss + "', state '" + rift.State + "'");
                r.Note("monsters hit per wave (the command's own reply): " + string.Join(",", me.ServerTexts(texts0).Where(x => x.StartsWith("rkill ", StringComparison.Ordinal)).Select(x => x.Substring(6)).Take(60)));
                if (rift.Boss != "alive") { problems.Append("the guardian did not come within the time limit (kills " + rift.Killed + " of " + rift.BossAt + ", boss '" + rift.Boss + "', state '" + rift.State + "'); "); goto finish; }
                if (rift.Killed < rift.BossAt) problems.Append("the guardian came after " + rift.Killed + " kills, the HUD says " + rift.BossAt + "; ");
                if (rift.BossName.Length == 0) problems.Append("the HUD names no guardian; ");
                r.Note("guardian: '" + rift.BossName + "', HUD line '" + rift.BossLine() + "', percent " + rift.BossPercent());
                // 2. to the guardian: its arena is far from the entrance
                var spawnPos = me.Pos;
                s.Say(o.RiftNear);
                bool moved = WaitFor(6000, () => me.Pos.Z != spawnPos.Z || PathFinder.Cheb(me.Pos, spawnPos) > 4);
                Pump(1800, () => false);
                var boss = world.Creatures.Values.Where(c => c.Type == 1 && (rift.BossName.Length > 0 && c.Name.IndexOf(rift.BossName, StringComparison.OrdinalIgnoreCase) >= 0)).OrderBy(c => PathFinder.Cheb(c.Position, me.Pos)).FirstOrDefault();
                r.Note("moved next to the guardian by '" + o.RiftNear + "': " + (moved ? P(spawnPos) + " to " + P(me.Pos) : "no move (the command is missing?)") + "; guardian in view: " +
                       (boss == null ? "no" : "yes, " + PathFinder.Cheb(boss.Position, me.Pos) + " tiles away, health " + boss.HealthPercent + "%") + "; monsters in view " + world.Creatures.Values.Count(c => c.Type == 1));
                if (moved && boss == null) problems.Append("the guardian '" + rift.BossName + "' is not among the creatures in view after the move; ");
                snap();
                // 3. the guardian dies
                var beforeKill = new Dictionary<byte, int>(p.Seen);
                int kills = 0;
                long limit2 = Tick + 90000;
                while (Tick < limit2 && s.Closed == null && rift.Result.Length == 0)
                {
                    s.Say(o.RiftKill);
                    kills++;
                    Pump(2000, () => rift.Result.Length > 0 || s.Closed != null);
                    snap();
                }
                snap();
                r.Note("guardian: " + kills + " kill command(s); end message '" + rift.Result + "', HUD state '" + rift.State + "', boss '" + rift.Boss + "', exit in " + rift.ExitIn + " s, text '" + rift.ResultText + "'");
                r.Note("packets since the guardian was in view: [" + PacketDiff(p, beforeKill) + "]");
                if (rift.Result != "success") { problems.Append("the rift did not end in success (result '" + rift.Result + "', state '" + rift.State + "'); "); goto finish; }
                if (rift.Boss != "dead") problems.Append("the HUD boss state is '" + rift.Boss + "' after the success; ");
                if (rift.State != "success") problems.Append("the HUD state is '" + rift.State + "' after the success; ");
                if (rift.ExitIn <= 0) problems.Append("the end message gives no exit time; ");
                // 4. the reward chest: it stands on the tile where the guardian died
                Pump(1200, () => false);
                var chestIds = RiftChestClientIds();
                var chest = FindChest(me, chestIds);
                int texts1 = me.Said.Count;
                var beforeChest = new Dictionary<byte, int>(p.Seen);
                var extChest = ExtPackets();
                uint free0 = p.FreeCap;
                if (chest == null)
                {
                    r.Note("no reward chest in view (client ids " + string.Join(",", chestIds) + ") at " + P(me.Pos));
                    problems.Append("the reward chest is not on the map after the success (client ids " + string.Join(",", chestIds) + "); ");
                }
                else
                {
                    var (tile, stack, cid) = chest.Value;
                    r.Note("reward chest: client id " + cid + " at " + P(tile) + " (stack position " + stack + "), " + PathFinder.Cheb(tile, me.Pos) + " tiles from the character");
                    if (PathFinder.Cheb(tile, me.Pos) > 1)
                    {
                        if (!WalkTo(me, tile, 1, 20000, false, out string wchest)) r.Note("walk to the chest: " + wchest);
                    }
                    EnsureBagOpen(me);
                    s.UseItem(tile, (ushort)cid, (byte)stack);
                    bool reward = WaitFor(8000, () => me.ServerTexts(texts1).Any(t => t.IndexOf("gold", StringComparison.OrdinalIgnoreCase) >= 0 || t.IndexOf("reward", StringComparison.OrdinalIgnoreCase) >= 0 || t.IndexOf("chest", StringComparison.OrdinalIgnoreCase) >= 0));
                    Pump(1500, () => false);
                    var chestTexts = me.ServerTexts(texts1).Take(4).ToList();
                    r.Note("chest used: server texts " + chestTexts.Count + (chestTexts.Count > 0 ? " (" + string.Join(" | ", chestTexts.Select(t => t.Length > 160 ? t.Substring(0, 160) + "..." : t)) + ")" : "") + "; packets [" + PacketDiff(p, beforeChest) + "]; extended [" + ExtDiff(extChest) + "]; capacity " + free0 + " to " + p.FreeCap);
                    int itemPackets = Delta(beforeChest, p, 0x6E) + Delta(beforeChest, p, 0x70) + Delta(beforeChest, p, 0x71) + Delta(beforeChest, p, 0x72) + Delta(beforeChest, p, 0x78) + Delta(beforeChest, p, 0x79);
                    if (!reward) problems.Append("opening the chest gave no reward text (texts: " + string.Join(" | ", chestTexts) + "); ");
                    else if (itemPackets == 0 && p.FreeCap == free0) r.Note("the reward text came, but no container, slot or capacity change (the reward may be gold in the bank only)");
                }
                // 5. the exit
                bool out2 = WaitFor(Math.Max(15000, (int)(rift.ExitIn * 1000) + 8000), () => !PathFarFromRift(before) || s.Closed != null);
                Pump(1200, () => false);
                r.Note("exit: position " + P(me.Pos) + " (before the rift " + P(before) + "), " + (out2 ? "back at the temple" : "still inside after the exit time"));
                if (!out2) problems.Append("the character was not sent out of the rift after the exit time; ");
                done = true;
            }
            finally
            {
                recording = false;
                // a rift left open (a skip or an early return) is closed by the staff command
                if (!done && s.Closed == null && rift.Active && rift.Result.Length == 0)
                {
                    s.Say("/rift fail");
                    WaitFor(15000, () => rift.Result.Length > 0 || s.Closed != null);
                    WaitFor(Math.Max(10000, (int)(rift.ExitIn * 1000) + 6000), () => !PathFarFromRift(before) || s.Closed != null);
                }
            }
        finish:
            snap();
            r.Note("HUD states: " + string.Join(" > ", states) + "; opcode 228 actions [" + string.Join(",", actions.GroupBy(x => x).Select(g => g.Key + " x" + g.Count())) + "]");
            r.Note("extended opcodes during the rift: [" + ExtDiff(extBefore) + "]; invalid JSON or handler errors: " + (ExtBad() - bad0));
            r.Note("packet types during the rift: [" + PacketDiff(p, seen0) + "]");
            if (ExtBad() > bad0) problems.Append((ExtBad() - bad0) + " extended opcode message(s) were invalid JSON or threw in a handler; ");
            problems.Append(mark.Diff(me, "primary"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("a rift cleared to its guardian (" + rift.Killed + " kills, HUD waiting > alive > dead), the guardian killed, the reward chest opened and paid, every rift opcode and container packet parsed, no failure");
        }
    }
}
