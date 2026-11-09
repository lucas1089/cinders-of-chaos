// Phase 29 (2026-11-09): parity with the main client fixes of that day (readable stack counts, the Purse button), the rules of a new login (SessionStamp, a fresh
// session holds nothing of the old one) and the completed quest in the base quest log (O433, unity/README.md "Parity with the 2026-11-09 client fixes (phase 29)").
using System;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class Phase29Tests
    {
        static GameSession NewSession() => new GameSession(new World(DatFile.Parse(Program.SyntheticDat())), new GameSession.Options());

        static string Source(string rel)
        {
            string root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Client", "Assets", "Chaos"));
            string f = Path.Combine(root, rel);
            return File.Exists(f) ? File.ReadAllText(f) : null;
        }

        public static void Run(Action<bool, string> check)
        {
            StackCounts(check);
            Purse(check);
            Stamps(check);
            NewLogin(check);
            CompletedQuest(check);
        }

        // ------------------------------------------------------------------------------------ stack counts
        static void StackCounts(Action<bool, string> check)
        {
            check(StackCountLook.Hex == "#f2e8d5" && StackCountLook.Rgb == 0xF2E8D5, "stack count: the main client's cream #f2e8d5");
            check(StackCountLook.FontSize >= StackCountLook.SlotTextSize && StackCountLook.FontSize >= 11, "stack count: not smaller than the slot's other text (" + StackCountLook.SlotTextSize + ") nor the main client's 11 px");
            const uint darkestSlot = 0x1C171F;   // the inventory slot fill (0.11, 0.09, 0.12)
            double now = StackCountLook.Contrast(StackCountLook.Rgb, darkestSlot), before = StackCountLook.Contrast(0x6B6258, darkestSlot);
            check(now >= 7.0, "stack count: the cream reads on the slot fill (contrast " + now.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture) + " is at least 7)");
            check(before < 4.5, "stack count: the dim colour of the old cell would fail the same rule (contrast " + before.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture) + ")");
            check(StackCountLook.Outline.Length >= 4 && StackCountLook.Outline.Select(o => o[0]).Distinct().Count() >= 3 && StackCountLook.Outline.Any(o => o[0] < 0) && StackCountLook.Outline.Any(o => o[0] > 0) && StackCountLook.Outline.Any(o => o[1] < 0) && StackCountLook.Outline.Any(o => o[1] > 0),
                "stack count: the outline covers all four sides");
            check(StackCountLook.OutlineAlpha >= 0.8f, "stack count: the outline is dark enough to read on a white sprite");
            check(StackCountLook.Text(1) == "" && StackCountLook.Text(0) == "" && StackCountLook.Text(2) == "2" && StackCountLook.Text(1234) == "1234", "stack count: no number for a single item");
            check(!StackCountLook.HotbarShows(1) && StackCountLook.HotbarShows(0) && StackCountLook.HotbarShows(7), "stack count: the hotbar shows 0 and 2 or more, not 1");
            check(StackCountLook.HotbarRgb(0) == 0xFF7366u && StackCountLook.HotbarRgb(5) == StackCountLook.Rgb, "stack count: the hotbar count is red when none is carried, else the cream");
            // the glue draws through the one function (the inventory, containers, trade lists and hotbar all call DrawItem or DrawStackCount)
            string win = Source("Unity/ChaosApp.Windows.cs"), bar = Source("Unity/Windows/HotkeyBarWindow.cs");
            if (win == null || bar == null) { check(true, "stack count: sources not found, glue scan skipped"); return; }
            check(win.Contains("DrawStackCount(r, StackCountLook.Text(count), StackCountLook.Rgb)") && win.Contains("StackCountLook.Outline") && win.Contains("StackCountLook.FontSize"), "stack count: DrawItem draws the count with StackCountLook (cream, size, outline)");
            check(bar.Contains("app.DrawStackCount(") && !Regex.IsMatch(bar, "Color\\.white;\\s*\\r?\\n\\s*GUI\\.Label\\([^;]*have\\.ToString"), "stack count: the hotbar item count uses the same drawing");
        }

        // ------------------------------------------------------------------------------------ the Purse
        static void Purse(Action<bool, string> check)
        {
            check(PurseButton.Slot == 11 && PurseButton.ServerItemId == 26052, "purse: inventory slot 11, the engine's store inbox (server store_delivery.lua)");
            check(PurseButton.Held(null) == null && PurseButton.Held(new Item[5]) == null && !PurseButton.Has(new Item[BadgeSlot.InventorySize]), "purse: no item, a short array or an empty slot is no purse");
            check(BadgeSlot.InventorySize > PurseButton.Slot, "purse: the parser's inventory reaches slot 11 (size " + BadgeSlot.InventorySize + ")");
            var s = NewSession();
            Pos usedPos = default(Pos); ushort usedId = 0; int uses = 0;
            s.ItemUsed = (pos, id) => { usedPos = pos; usedId = id; uses++; };
            check(!s.UsePurse(3) && uses == 0, "purse: with an empty slot nothing is sent (the caller says 'You have no purse.')");
            s.Parser.Parse(new ByteWriter().U8(0x78).U8(11).U16(100).U8(0xFF).ToArray());
            check(PurseButton.Has(s.Parser.Inventory) && s.Parser.Inventory[11].Id == 100 && s.Parser.FailureCount == 0, "purse: 0x78 for slot 11 fills it");
            check(s.UsePurse(3) && uses == 1 && usedPos.X == 0xFFFF && usedPos.Y == 11 && usedPos.Z == 0 && usedId == 100, "purse: the button uses the item of slot 11, as the main client's button does");
            var wire = Protocol.UseItemPacket(GameSession.InventoryPos(11), 100, 11, 3);
            check(wire.Length > 0 && wire.Contains((byte)0x82) && BitConverter.ToString(wire).Contains("FF-FF-0B-00-00-64-00-0B-03"), "purse: the request on the wire is 0x82 position 65535/11/0, item, stack position 11, container window 3");
            check(Core.LiveCheck.LiveRun.OptInScenarios.Contains("purse") && !Core.LiveCheck.LiveRun.AllScenarios.Contains("purse"), "purse: the live scenario 'purse' is opt-in by name (LiveScenarios10.cs)");
            string ci = Source("../../../../tools/ci/unity_live_check.sh");
            if (ci != null) check(ci.Contains("newplayer,questlog,purse,firstunlock,firstkill"), "purse: the CI group newplayer runs the purse scenario");
            Loc.Set("en");
            check(PurseButton.NoPurse == "You have no purse." && PurseButton.Tooltip.StartsWith("Opens your purse", StringComparison.Ordinal), "purse: the texts of the main client");
            Loc.Set("pt-BR");
            check(Loc.T("Purse") == "Bolsa" && PurseButton.NoPurse == "Você não tem bolsa." && PurseButton.Tooltip == "Abre a sua bolsa. O que você compra na loja chega lá.", "purse: pt-BR");
            Loc.Set("en");
            string eq = Source("Unity/Windows/EquipmentWindow.cs");
            if (eq == null) { check(true, "purse: sources not found, glue scan skipped"); return; }
            check(eq.Contains("PurseRow(app") && eq.Contains("s.UsePurse(") && eq.Contains("PurseButton.NoPurse") && eq.Contains("Loc.T(\"Purse\")"), "purse: the inventory window has the button, it calls UsePurse and says so with no purse");
        }

        // ------------------------------------------------------------------------------------ a new login starts clean
        static void Stamps(Action<bool, string> check)
        {
            var a = new object(); var b = new object();
            var st = new SessionStamp();
            check(st.Due(a, 0, 250) && !st.IsSet, "stamp: never set is due");
            st.Mark(a, 600000);
            check(!st.Due(a, 600100, 250) && st.Due(a, 600250, 250) && st.Due(a, 700000, 250), "stamp: on its own session the gap counts");
            check(st.Due(b, 100, 250), "stamp: a new session is due at once, whatever the old clock said (the loot scan, beams and the monster tier question went quiet after a death)");
            check(st.Due(a, 500000, 250), "stamp: a clock that ran back is a new clock");
            check(st.Due(null, 600100, 250), "stamp: no session is always due");
            st.Mark(b, 40);
            check(!st.Due(b, 100, 250) && st.Due(a, 41, 250), "stamp: marked again for the new session, the old one is due");
            st.Reset();
            check(st.Due(b, 41, 250) && !st.IsSet, "stamp: Reset is due now");
            // the plain double of the old glue: the bug the stamp replaces
            double oldAt = 600000, newNow = 100;
            check(!(newNow - oldAt >= 250), "stamp: the old comparison (now - at >= gap) stays false for the whole age of the old session");
            // the glue holds no plain time of a session any more
            foreach (var (file, name) in new[] { ("Unity/ChaosApp.Visual.cs", "beamsAt"), ("Unity/ChaosApp.Phase7Y.cs", "monsterAskAt"), ("Unity/Windows/LootWindow.cs", "lastScan") })
            {
                string src = Source(file);
                if (src == null) { check(true, "stamp: " + file + " not found, scan skipped"); continue; }
                check(!Regex.IsMatch(src, "\\b" + name + "\\b"), "stamp: " + file + " keeps no plain double '" + name + "' (a SessionStamp)");
            }
            string app = Source("Unity/ChaosApp.Phase29.cs"), wins = Source("Unity/ChaosApp.Windows.cs");
            if (app == null || wins == null) { check(true, "stamp: sources not found, reset scan skipped"); return; }
            check(wins.Contains("ResetSessionState();") && app.Contains("beamsStamp.Reset()") && app.Contains("monsterAskStamp.Reset()") && app.Contains("autoWalk.Cancel()") && app.Contains("Crosshair.Cancel()") && app.Contains("split = null") && app.Contains("chatFocused = false"),
                "new login: ResetWindows (called by Leave) clears the app's session state: stamps, walks, crosshair, split box, chat focus");
        }

        // What a new login must find: a new parser, quest log, hud and clock, nothing of the character that died. The windows compare by session object (HelperWindow.engineFor and the others),
        // the app clears the rest (ChaosApp.Phase29.cs), so the Core object must not share anything between two sessions.
        static void NewLogin(Action<bool, string> check)
        {
            var old = NewSession();
            var p = old.Parser;
            p.Parse(new ByteWriter().U8(0x28).U8(0).U8(7).ToArray());
            p.Parse(new ByteWriter().U8(0x78).U8(11).U16(100).U8(0xFF).ToArray());
            p.Parse(new ByteWriter().U8(0x78).U8(3).U16(100).U8(0xFF).ToArray());
            p.Parse(new ByteWriter().U8(0xF0).U16(1).U16(5).Str("Done").U8(1).ToArray());
            check(p.Dead && p.DeathType == 0 && p.DeathPenalty == 7 && PurseButton.Has(p.Inventory) && p.Quests.Loaded && p.Quests.Done() == 1, "new login: the old session holds a death, a purse and a loaded quest log");
            old.Hud.Monster.Query(77, 600000);
            var s = NewSession();
            var q = s.Parser;
            check(!q.Dead && q.DeathPenalty == 100, "new login: the new session is not dead (the penalty is the default again, not the old 7)");
            check(q.Inventory.All(x => x == null) && !PurseButton.Has(q.Inventory), "new login: the new session has no inventory (the login's 0x78 packets fill it)");
            check(!q.Quests.Loaded && q.Quests.Quests.Count == 0 && q.Quests.Selected == -1 && !ReferenceEquals(q.Quests, p.Quests), "new login: a new quest log, not loaded");
            check(q.Containers.Count == 0 && q.Failures.Count == 0 && q.FailureCount == 0, "new login: no open container, no failure");
            check(!ReferenceEquals(s.Hud, old.Hud) && !ReferenceEquals(s.Spells, old.Spells) && !ReferenceEquals(s.Parser, old.Parser) && !ReferenceEquals(s.Talks, old.Talks), "new login: the parts of a session (hud, spell list, parser, chat) are new objects");
            check(!s.Spells.Loaded && s.Hud.Monster.Info(77) == null, "new login: no spell list and no monster info of the old game");
            check(s.Now < 5000, "new login: the clock of a new session starts near zero (" + (int)s.Now + " ms), so a time kept from the old session lies in its future");
            check(!ReferenceEquals(s.Utils, old.Utils) && !ReferenceEquals(s.Social, old.Social), "new login: utilities and social state are new objects");
            check(p.Dead, "new login: the old session is left as it was (the app disposes it, nothing is shared)");
        }

        // ------------------------------------------------------------------------------------ the completed quest
        // The base server (ProtocolGame::sendQuestLog, sendQuestLine; quests.cpp): the log holds the started quests with a completed flag; a line lists the started missions,
        // and Mission::getName adds " (completed)" to a done one. Values below are quests.xml's own ("Hask's Old Backpack": one mission, three states, endvalue 3).
        static void CompletedQuest(Action<bool, string> check)
        {
            Loc.Set("en");
            var s = NewSession();
            var p = s.Parser;
            var log = new ByteWriter().U8(0xF0).U16(3).U16(12).Str("Hask's Old Backpack").U8(1).U16(20).Str("Sweetmarch").U8(0).U16(31).Str("The Beginning").U8(1);
            p.Parse(log.ToArray());
            check(p.Quests.Loaded && p.Quests.Quests.Count == 3 && p.Quests.Quests[0].Completed && !p.Quests.Quests[1].Completed && p.Quests.Quests[2].Completed && p.FailureCount == 0, "completed quest: the log flags are read per quest");
            check(p.Quests.Done() == 2 && p.Quests.Summary() == "2 of 3 quests done", "completed quest: two of three done, the summary says so");
            p.Quests.HideCompleted = true;
            var vis = p.Quests.Visible();
            check(vis.Count == 1 && vis[0].Name == "Sweetmarch", "completed quest: 'Hide completed quests' leaves the open one");
            p.Quests.HideCompleted = false;
            check(p.Quests.Visible().Count == 3, "completed quest: showing all lists all three");
            // the line of a done quest: the mission name ends with (completed), the text is the last state's
            p.Parse(new ByteWriter().U8(0xF1).U16(12).U8(1).Str("Dwarven Armor Quest (completed)").Str("You have completed Dwarven Armor Quest!").ToArray());
            var ms = p.Quests.Missions(12);
            check(ms != null && ms.Count == 1 && ms[0].Name == "Dwarven Armor Quest (completed)" && ms[0].Description == "You have completed Dwarven Armor Quest!" && p.FailureCount == 0, "completed quest: the line of a done quest is read, the mission is marked (completed)");
            // two missions of one quest: one done, one running (Sweetmarch's two missions with their own storage)
            p.Parse(new ByteWriter().U8(0xF1).U16(20).U8(2).Str("Pastry Decoration (completed)").Str("You founded the sixth pastry decoration, go back talk to Terhelm.").Str("Find the Boss room").Str("Use the teleport near Terhelm to start finding the boss room.").ToArray());
            var two = p.Quests.Missions(20);
            check(two != null && two.Count == 2 && two[0].Name.EndsWith("(completed)", StringComparison.Ordinal) && !two[1].Name.EndsWith("(completed)", StringComparison.Ordinal), "completed quest: a quest with one done and one running mission keeps both in the server's order");
            // selecting a done quest asks its line again and keeps it selected while hidden rows change
            var sent = new System.Collections.Generic.List<byte[]>();
            p.Quests.Send = sent.Add;
            p.Quests.Select(31);
            check(sent.Count == 1 && sent[0].Length == 3 && sent[0][0] == 0xF1 && sent[0][1] == 31 && p.Quests.Selected == 31, "completed quest: a click on a done quest asks its line (0xF1, id)");
            p.Quests.HideCompleted = true;
            p.Parse(new ByteWriter().U8(0xF0).U16(3).U16(12).Str("Hask's Old Backpack").U8(1).U16(20).Str("Sweetmarch").U8(0).U16(31).Str("The Beginning").U8(1).ToArray());
            check(p.Quests.Selected == 31 && p.Quests.Visible().Count == 1, "completed quest: a refresh keeps the selection of a done quest that is hidden");
            // a quest that ends as completed between two refreshes: the flag follows
            p.Parse(new ByteWriter().U8(0xF0).U16(3).U16(12).Str("Hask's Old Backpack").U8(1).U16(20).Str("Sweetmarch").U8(1).U16(31).Str("The Beginning").U8(1).ToArray());
            check(p.Quests.Done() == 3 && p.Quests.Visible().Count == 0 && p.Quests.Summary() == "3 of 3 quests done" && p.FailureCount == 0, "completed quest: when the last quest ends the flag follows and the hidden list is empty");
            Loc.Set("pt-BR");
            check(p.Quests.Summary().Length > 0 && !p.Quests.Summary().StartsWith("3 of", StringComparison.Ordinal), "completed quest: the summary is in pt-BR");
            Loc.Set("en");
        }
    }
}
