// Phase 14, track H: the wire-type audit. The server's Lua JSON encoder (base lib/core/json.lua) writes a Lua boolean as true/false, but many Chaos payloads carry flags as the
// numbers 1 and 0 (`open = 1`, `done = 1`, `pw = 1`, `boss = seg.boss and 1 or 0`), some values as text (tostring, storage values), an empty table as [] (never {}), and a table keyed
// by the strings "1", "2" as an object. Json.Truthy, Json.AsNumber, Json.Text and Json.List read all of these; Json.Bool stays strict (for what this client wrote itself).
// Every payload below is the shape of the cited server file.
using System;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class Phase14HTests
    {
        public static void Run(Action<bool, string> check)
        {
            TruthyChecks(check);
            ReaderChecks(check);
            ServerShapes(check);
        }

        static GameSession NewSession() => new GameSession(new World(DatFile.Parse(Program.SyntheticDat())), new GameSession.Options());

        static void Feed(GameSession s, byte op, string json)
        {
            foreach (var part in ExtChunks.Split(ExtOpcodes.ToWire(json))) s.Ext.Receive(op, part);
        }

        static void TruthyChecks(Action<bool, string> check)
        {
            check(Json.Truthy(true) && !Json.Truthy(false) && Json.Truthy(1.0) && Json.Truthy(-1.0) && Json.Truthy(0.5) && !Json.Truthy(0.0) && !Json.Truthy(double.NaN), "truthy: booleans and numbers (nonzero is true)");
            check(Json.Truthy("1") && Json.Truthy("true") && Json.Truthy("TRUE") && Json.Truthy(" 1 ") && !Json.Truthy("0") && !Json.Truthy("false") && !Json.Truthy("") && !Json.Truthy("yes"), "truthy: the strings 1 and true");
            check(!Json.Truthy(null) && Json.Truthy(null, true) && Json.Truthy(new List<object>(), true) && !Json.Truthy(new Dictionary<string, object>()) && Json.Truthy(new Dictionary<string, object>(), true), "truthy: null, a list or an object give the fallback");
            check(!Json.Truthy(0.0, true) && !Json.Truthy(false, true) && !Json.Truthy("0", true), "truthy: a value that is there wins over the fallback");
            var o = Json.Parse("{\"a\":1,\"b\":0,\"c\":true,\"d\":null,\"e\":\"1\"}");
            check(Json.Truthy(o, "a") && !Json.Truthy(o, "b") && Json.Truthy(o, "c") && !Json.Truthy(o, "d") && Json.Truthy(o, "d", true) && Json.Truthy(o, "e") && !Json.Truthy(o, "missing") && Json.Truthy(o, "missing", true) && !Json.Truthy(null, "a"),
                "truthy: by key, with a fallback for a missing or null key");
            check(!Json.Bool(o, "a") && Json.Bool(o, "c") && !Json.Bool(o, "e"), "bool: strict (only a JSON boolean) for what this client wrote itself");
            check(CF.On(1.0) && !CF.On(0.0) && CF.On("1") && CF.On(true) && !CF.On(null), "collect: CF.On follows Json.Truthy");
        }

        static void ReaderChecks(Action<bool, string> check)
        {
            var o = Json.Parse("{\"n\":\"12\",\"f\":\"1.5\",\"bad\":\"x\",\"i\":7,\"big\":\"99999999999\",\"txt\":12,\"half\":1.5,\"neg\":-4,\"e\":\"\",\"t\":true,\"nan\":\"NaN\",\"inf\":\"Infinity\"}");
            check(Json.Int(o, "n") == 12 && Json.Number(o, "f") == 1.5 && Json.Int(o, "bad", 3) == 3 && Json.Number(o, "bad", 2.5) == 2.5 && Json.Int(o, "i") == 7, "numbers: a numeric string reads as a number, text that is not one gives the fallback");
            check(Json.Int(o, "big") == int.MaxValue && Json.Int(o, "e", 9) == 9 && Json.Int(o, "t", 5) == 5 && Json.Number(o, "nan", 1) == 1 && Json.Number(o, "inf", 1) == 1, "numbers: a huge string clamps, empty text, a boolean, NaN and Infinity give the fallback");
            check(Json.Text(o, "txt") == "12" && Json.Text(o, "half") == "1.5" && Json.Text(o, "neg") == "-4" && Json.Text(o, "t", "no") == "no" && Json.Text(o, "missing", "z") == "z", "text: a whole number reads as the digits Lua tostring writes, a boolean is not text");
            check(Json.NumberText(100000) == "100000" && Json.NumberText(0.25) == "0.25" && Json.NumberText(-0.0) == "0", "text: NumberText of whole and fractional numbers");
            // an empty Lua table is [] (rxi json: an empty table is an array): an object member reads as missing, a list as empty
            var e = Json.Parse("{\"cooldowns\":[],\"rows\":[],\"state\":[]}");
            check(Json.Get(Json.Get(e, "cooldowns"), "death") == null && Json.Number(Json.Get(e, "cooldowns"), "death", 4) == 4 && Json.List(e, "rows").Count == 0 && !Json.Truthy(Json.Get(e, "state"), "open"), "empty table: [] where an object is expected reads as missing, nothing throws");
            check(SFmt.Rows(e, "rows").Count == 0 && CF.Rows(Json.Get(e, "state")).Count == 0, "empty table: the row readers give no rows for []");
            // a table keyed by the strings "1", "2" is an object on the wire
            var k = Json.Parse("{\"acts\":{\"2\":{\"k\":\"b\"},\"1\":{\"k\":\"a\"},\"10\":{\"k\":\"c\"}},\"names\":{\"x\":1},\"plain\":[{\"k\":\"z\"}]}");
            var acts = Json.List(k, "acts");
            check(acts.Count == 3 && Json.Text(acts[0], "k") == "a" && Json.Text(acts[1], "k") == "b" && Json.Text(acts[2], "k") == "c", "list: an object keyed by 1, 2, 10 reads as the list in number order");
            check(Json.List(k, "names").Count == 0 && Json.List(k, "plain").Count == 1 && Json.List(k, "none").Count == 0, "list: an object with other keys is no list, an array is itself");
        }

        // ------------------------------------------------------------------------------------ the exact shapes of the server files
        static void ServerShapes(Action<bool, string> check)
        {
            // weeklychest.lua send (weeklychest_core.lua K.view): `shown = 1` on the first push after the window opened, `open` is the COUNT of activities the character can do,
            // the rows of acts carry done and open as 1 / 0
            var s = NewSession();
            Feed(s, WeeklyState.OpcodeId, "{\"action\":\"state\",\"data\":{\"shown\":1,\"endsIn\":86400,\"acts\":[{\"k\":\"dungeon\",\"done\":1,\"open\":1,\"lv\":100},{\"k\":\"rift\",\"done\":0,\"open\":1,\"lv\":100},{\"k\":\"waystone\",\"done\":0,\"open\":0,\"lv\":1100}]," +
                "\"got\":1,\"need\":2,\"bonusNeed\":0,\"open\":2,\"chests\":3,\"chest\":{\"given\":0,\"gold\":1500000,\"it\":[]},\"bonus\":{\"given\":0,\"lo\":800,\"hi\":1200}}}");
            var rows = s.Weekly.Rows();
            check(s.Weekly.State != null && rows.Count == 3 && rows[0].Status == "Done" && rows[1].Status == "Not yet" && rows[2].Status.StartsWith("Unlocks at level 1100"), "weekly chest: done and open as 1 and 0 give Done, Not yet and the unlock level");
            check(Json.Truthy(s.Weekly.State, "shown") && !s.Weekly.Visible, "weekly chest: `shown = 1` is read and does not open the window (the main client ignores it too: the window opens by the player, the state only fills it)");
            string chest = s.Weekly.ChestLine(out _);
            check(chest.Contains("2 of 2") && s.Weekly.Head().StartsWith("1 of 2"), "weekly chest: `open` is the count of activities (2), not a flag: " + chest);

            // pets.lua: `open = open and 1 or nil` (the window was asked for) and the cooldowns as an object, [] when empty
            var p = NewSession();
            Feed(p, PetsState.OpcodeId, "{\"action\":\"state\",\"data\":{\"open\":1,\"pets\":[],\"catalog\":[],\"cooldowns\":{\"death\":0,\"summon\":0}}}");
            check(p.Pets.Visible, "pets: open = 1 shows the window");
            var p2 = NewSession();
            Feed(p2, PetsState.OpcodeId, "{\"action\":\"state\",\"data\":{\"pets\":[],\"catalog\":[],\"cooldowns\":[]}}");
            check(!p2.Pets.Visible && p2.Pets.State != null, "pets: no open key and cooldowns as [] (an empty table) keep the window shut and keep the state");

            // hunt.lua: open = 1 (phase 13), p = paused as 1 or 0 (hunt_core.lua)
            var h = NewSession();
            Feed(h, HuntTracker.Opcode, "{\"action\":\"state\",\"data\":{\"open\":1,\"p\":1,\"t\":60,\"xp\":1,\"xph\":1,\"lvl\":2,\"left\":0,\"ttl\":0}}");
            check(h.Progress.Hunt.HasState && h.Progress.Hunt.OpenRequested, "hunt: open = 1 asks for the window");

            // lootfilter.lua rows: u, o, pw as 1 or 0 (or missing)
            var li = LootInfo.From(Json.Parse("{\"r\":5,\"u\":1,\"o\":0,\"pw\":1,\"g\":\"equipment\",\"nm\":\"Emberfang\"}"));
            check(li.U && !li.O && li.Pw && li.G == "equipment", "loot row: u = 1, o = 0, pw = 1 read as flags");
            check(Json.Truthy(Json.Parse("{\"pw\":1}"), "pw") && !Json.Truthy(Json.Parse("{\"pw\":0}"), "pw"), "tooltip flags: pw = 1 on, 0 off");

            // combatlog_core.lua: boss, live and share as 1 or 0
            var seg = Json.Parse("{\"boss\":1,\"live\":0,\"share\":1}");
            check(Json.Truthy(seg, "boss") && !Json.Truthy(seg, "live") && Json.Truthy(seg, "share"), "combat log: boss, live, share as 1 and 0");

            // mentor.lua status: booleans are real booleans on the server (K.view `and true or false`); the same values as numbers must read the same
            var m = NewSession();
            Feed(m, MentorPanel.Opcode, "{\"action\":\"status\",\"data\":{\"enabled\":1,\"canPick\":1,\"seeking\":0,\"graduated\":0,\"canMentor\":0,\"open\":1,\"me\":{\"name\":\"Kit\",\"level\":20,\"voc\":\"Hunter\"}," +
                "\"rules\":{\"exp\":10,\"dmg\":15,\"maxLevel\":100,\"accountDays\":30,\"gradLevel\":100},\"lines\":[],\"invites\":[],\"shop\":[],\"top\":[]}}");
            check(m.Community.Mentor.Visible && m.Community.Mentor.StatusData != null && MentorPanel.PickText(m.Community.Mentor.StatusData).Contains("up to level 100"), "mentor: enabled, canPick and open as numbers show the window and the pick text");

            // stash.lua access message: canWithdraw and canDeposit read as flags, also as 1 and 0
            var st = NewSession();
            Feed(st, StashState.Opcode, "{\"action\":\"Stash\",\"data\":{\"make\":\"access\",\"canWithdraw\":1,\"canDeposit\":1}}");
            bool on = st.Stash.CanWithdraw && st.Stash.CanDeposit;
            Feed(st, StashState.Opcode, "{\"action\":\"Stash\",\"data\":{\"make\":\"access\",\"canWithdraw\":0,\"canDeposit\":0}}");
            check(on && !st.Stash.CanWithdraw && !st.Stash.CanDeposit, "stash: an access message with 1 and 0 sets the flags");
        }
    }
}
