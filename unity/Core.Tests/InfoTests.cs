// Phase 5, track Q: the helper extras (runes, party and friend heals, food, the Everfull held message, shooter presets, the bot HUD, the Support section) and the
// info windows (DPS meter, short numbers, info lifts, How it works, help search, Codex, the weapon list). The checks mirror the Lua tests of the main client:
// game_helper/helper_runes_test.lua, helper_ally_test.lua, helper_config_test.lua, game_helperhud/helperhud_test.lua, game_helpersupport/supportspells_test.lua,
// game_helperrotation/everfullheld_test.lua, game_dpsmeter/dpsmath_test.lua, client_chaos_numbers/numbers_test.lua, client_chaos_infolift/infolift_core_test.lua,
// game_howitworks/howcore_test.lua, game_helpsearch/helpcore_test.lua, game_codex/codexview_test.lua and game_proficiencycatalog/catalogcore_test.lua.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class InfoTests
    {
        static readonly Pos From = new Pos(10, 10, 7);

        static string FindFile(params string[] relative)
        {
            string dir = Directory.GetCurrentDirectory();
            for (int i = 0; i < 8 && dir != null; i++)
            {
                string p = Path.Combine(new[] { dir }.Concat(relative).ToArray());
                if (File.Exists(p)) return p;
                dir = Path.GetDirectoryName(dir);
            }
            return null;
        }

        static string Resource(string name)
        {
            string p = FindFile("unity", "Client", "Assets", "Chaos", "Resources", name) ?? FindFile("Client", "Assets", "Chaos", "Resources", name);
            return p != null ? File.ReadAllText(p) : "";
        }

        static HelperCreature At(uint id, int x, int y, int z = 7, int health = 100) => new HelperCreature(id, new Pos(x, y, z), health);

        public static void Run(Action<bool, string> check)
        {
            Runes(check);
            Allies(check);
            Food(check);
            Everfull(check);
            Profiles(check);
            Hud(check);
            Support(check);
            ExtraEngine(check);
            Dps(check);
            DpsProtocol(check);
            Numbers(check);
            Lifts(check);
            How(check);
            HelpTests(check);
            CodexTests(check);
            Proficiency(check);
        }

        // ------------------------------------------------------------------------------------ helper_runes_test.lua
        static void Runes(Action<bool, string> check)
        {
            check(HelperRunes.IsHeal(3152) && HelperRunes.IsHeal(3160) && !HelperRunes.IsHeal(3174), "runes: the healing runes");
            check(HelperRunes.IsAttack(3174) && !HelperRunes.IsAttack(3152) && !HelperRunes.IsAttack(1), "runes: the attack runes");
            check(HelperRunes.List.All(r => r.Server == r.Id - HelperRunes.ServerOffset || r.Id == 21352 || r.Id == 21351), "runes: server ids are the client ids minus 887 (the two added runes have their own)");
            check(HelperRunes.Offered("attack", 3).Any(r => r.Id == 3182) && !HelperRunes.Offered("attack", 4).Any(r => r.Id == 3182) && HelperRunes.Offered("attack", 0).Any(r => r.Id == 3182),
                "runes: a class list limits a rune, an unknown class sees all");
            var heal = new List<HelperRuneHealRow> { new HelperRuneHealRow { Id = 3152, Percent = 60 }, new HelperRuneHealRow { Id = 3160, Percent = 40 } };
            check(HelperRunes.PickHeal(heal, 50) == 3152, "runes: heal at 50% takes the 60% row");
            check(HelperRunes.PickHeal(heal, 30) == 3160, "runes: heal at 30% takes the lowest threshold");
            check(HelperRunes.PickHeal(heal, 90) == 0, "runes: nothing due at 90%");
            check(HelperRunes.PickHeal(heal, 30, id => id != 3160) == 3152, "runes: an unavailable rune is skipped");
            check(HelperRunes.HealDue(heal, 59) && !HelperRunes.HealDue(heal, 61), "runes: healDue by the numbers alone");
            var rune = HelperRunes.Info(3191);
            var mon = new List<HelperCreature> { At(1, 14, 10), At(2, 15, 10), At(3, 16, 11), At(4, 30, 10) };
            check(HelperRunes.Hits(rune, mon, From, new Pos(15, 10, 7)) == 3, "runes: an area rune counts the monsters round the target");
            check(HelperRunes.Hits(HelperRunes.Info(3174), mon, From, new Pos(15, 10, 7)) == 3, "runes: a single rune counts the monsters near the player");
            check(HelperRunes.HealthFits(new HelperRuneRow(), 100) && HelperRunes.HealthFits(new HelperRuneRow { HpMin = 20 }, 50) && !HelperRunes.HealthFits(new HelperRuneRow { HpMin = 60 }, 50)
                && !HelperRunes.HealthFits(new HelperRuneRow { HpMax = 40 }, 50), "runes: the health range of a row");
            var rows = new List<HelperRuneRow> { new HelperRuneRow { Id = 3174, Priority = 2 }, new HelperRuneRow { Id = 3152, Priority = 1 }, new HelperRuneRow { Id = 3191, Priority = 1 } };
            var order = HelperRunes.Order(rows);
            check(order.Count == 2 && order[0].Id == 3191 && order[1].Id == 3174, "runes: order drops healing runes, keeps priority then position");
            var many = new List<HelperRuneRow> { new HelperRuneRow { Id = 3191, Creatures = 3, Priority = 1 }, new HelperRuneRow { Id = 3174, Creatures = 1, Priority = 2 } };
            var pick = HelperRunes.PickAttack(many, true, new Pos(15, 10, 7), 100, From, mon, p => true, id => true);
            check(pick != null && pick.Id == 3191, "runes: the area rune goes when enough monsters are in it");
            pick = HelperRunes.PickAttack(many, true, new Pos(15, 10, 7), 100, From, new List<HelperCreature> { At(1, 15, 10) }, p => true, id => true);
            check(pick != null && pick.Id == 3174, "runes: a lone target takes the single rune");
            check(HelperRunes.PickAttack(many, false, From, 100, From, mon, p => true, id => true) == null, "runes: no target, no rune");
            check(HelperRunes.PickAttack(many, true, new Pos(15, 10, 7), 100, From, mon, p => false, id => true) == null, "runes: out of range, no rune");
            check(HelperRunes.PickAttack(many, true, new Pos(15, 10, 7), 100, From, mon, p => true, id => false) == null, "runes: none carried, no rune");
        }

        // ------------------------------------------------------------------------------------ helper_ally_test.lua
        static void Allies(Action<bool, string> check)
        {
            check(HelperAlly.CleanName("  Ann  Lee ") == "Ann Lee" && HelperAlly.CleanName("A") == null && HelperAlly.CleanName("Bob\"; say x") == null && HelperAlly.CleanName("O'Neil-Ray") == "O'Neil-Ray"
                && HelperAlly.CleanName("1Bob") == null && HelperAlly.CleanName(new string('a', 30)) == null, "ally: a name is cleaned or refused");
            var names = HelperAlly.ParseNames("Ann, Bob Smith; ann\nX, Cy", 5);
            check(names.Count == 3 && names[0] == "Ann" && names[1] == "Bob Smith" && names[2] == "Cy", "ally: parseNames drops bad names and repeats");
            check(HelperAlly.ParseNames("a, b, c, dd, ee, ff, gg", 2).Count == 2, "ally: parseNames stops at the maximum");
            check(HelperAlly.IsPartyShield(3) && HelperAlly.IsPartyShield(10) && !HelperAlly.IsPartyShield(1) && !HelperAlly.IsPartyShield(2) && HelperAlly.IsLeaderShield(4) && !HelperAlly.IsLeaderShield(3), "ally: party shields");

            var cfg = new HelperAllies { PartyEnabled = true, PartyPercent = 70, FriendsEnabled = true, FriendsPercent = 50 };
            cfg.FriendNames[0] = "Zed";
            var players = new List<HelperPlayer>
            {
                new HelperPlayer { Id = 1, Name = "Me", Health = 10, Position = From, IsSelf = true },
                new HelperPlayer { Id = 2, Name = "Ann", Health = 60, Position = new Pos(12, 10, 7), Shield = 3 },
                new HelperPlayer { Id = 3, Name = "Zed", Health = 40, Position = new Pos(11, 10, 7) },
                new HelperPlayer { Id = 4, Name = "Zed", Health = 40, Position = new Pos(11, 10, 8) },
                new HelperPlayer { Id = 5, Name = "Bob", Health = 20, Position = new Pos(11, 11, 7) },
                new HelperPlayer { Id = 6, Name = "Cy", Health = 100, Position = new Pos(11, 12, 7), Shield = 3 },
                new HelperPlayer { Id = 7, Name = "Far", Health = 10, Position = new Pos(30, 10, 7), Shield = 3 },
            };
            var cands = HelperAlly.Candidates(cfg, players, From);
            check(cands.Count == 2 && cands[0].Id == 3 && cands[1].Id == 2, "ally: the party below its percent and the friends below theirs, the most hurt first");
            check(HelperAlly.Candidates(cfg, players, From, (a, b) => false).Count == 0, "ally: no line of sight, no heal");
            var spells = new Dictionary<int, Spell>
            {
                { 84, new Spell { Id = 84, Name = "Kindred Mend", Words = "exura sio", Group = 2, Mana = 20 } },
                { 82, new Spell { Id = 82, Name = "Circle of Mending", Words = "exura gran mas res", Group = 2, Mana = 100 } },
            };
            Func<int, Spell> spellOf = id => { Spell s; return spells.TryGetValue(id, out s) ? s : null; };
            cfg.Spell = 84; cfg.GroupId = 82; cfg.GroupCount = 2;
            var p = HelperAlly.Pick(cfg, From, cands, false, 80, spellOf, s => true, id => false);
            check(p != null && p.Kind == "group" && p.Words == "exura gran mas res", "ally: a group spell when enough players are hurt");
            cfg.GroupCount = 3;
            p = HelperAlly.Pick(cfg, From, cands, false, 80, spellOf, s => true, id => false);
            check(p != null && p.Kind == "spell" && p.Words == "exura sio \"Zed\"" && p.Target.Id == 3, "ally: the single spell on the most hurt, the name in quotes");
            check(HelperAlly.Pick(cfg, From, cands, true, 80, spellOf, s => true, id => false) == null, "ally: the character comes first");
            check(HelperAlly.Pick(cfg, From, cands, false, 5, spellOf, s => true, id => false) == null, "ally: no ally heal below 10% mana");
            cfg.Spell = 0; cfg.GroupId = 0; cfg.RuneId = 3152;
            p = HelperAlly.Pick(cfg, From, cands, false, 80, spellOf, s => true, id => id == 3152);
            check(p != null && p.Kind == "rune" && p.RuneId == 3152 && p.Target.Id == 3, "ally: a healing rune when no spell is set");
            var st = new HelperAllyState();
            check(HelperAlly.Allowed(st, "3", 1000), "ally: the first heal of a target goes");
            HelperAlly.Noted(st, "3", 1000);
            check(!HelperAlly.Allowed(st, "3", 1500) && HelperAlly.Allowed(st, "3", 2300) && HelperAlly.Allowed(st, "4", 1500), "ally: a gap per target");
            for (int i = 0; i < 8; i++) HelperAlly.Noted(st, "k" + i, 2000);
            check(!HelperAlly.Allowed(st, "z", 3000) && HelperAlly.Allowed(st, "z", 13000), "ally: a budget of 8 heals in 10 seconds");
            var hc = new HelperConfig();
            hc.Heals[0] = new HelperHealRow { Id = 1, Percent = 50 };
            check(HelperAlly.SelfFirst(hc, 40) && !HelperAlly.SelfFirst(hc, 80), "ally: selfFirst by the character's own rows");
            hc.RuneHeal[0].Id = 3152;
            check(HelperAlly.SelfFirst(hc, 55) && !HelperAlly.SelfFirst(hc, 70), "ally: a healing rune row counts as the character's own");
            var offered = HelperAlly.Offered(HelperAlly.Single, spellOf, s => true, 0);
            check(offered.Count == 1 && offered[0].Key.Id == 84, "ally: offered lists the spells the book has");
        }

        // ------------------------------------------------------------------------------------ food
        static void Food(Action<bool, string> check)
        {
            check(HelperFood.Pick(false, 1000, -1, id => id == 3577 ? 2 : 0) == 3577, "food: the first meal goes at once");
            check(HelperFood.Pick(false, 1000, 500, id => id == 3577 ? 2 : 0) == 0, "food: not within two minutes of the last meal");
            check(HelperFood.Pick(false, 130000, 500, id => id == 3578 ? 1 : 0) == 3578, "food: after the gap the next carried food");
            check(HelperFood.Pick(true, 1000, 500, id => id == 3578 ? 1 : 0) == 3578, "food: hungry eats at once");
            check(HelperFood.Pick(true, 1000, 500, id => 0) == 0, "food: nothing carried");
        }

        // ------------------------------------------------------------------------------------ everfullheld_test.lua
        static void Everfull(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var held = new EverfullHeld(ext);
            check(held.Resolve(266, 100) == 266 && !held.Received, "everfull: nothing held, a stock row stays");
            ext.Receive(EverfullHeld.Opcode, ExtOpcodes.ToWire("{\"action\":\"held\",\"data\":{\"health\":{\"look\":38646,\"tier\":2,\"level\":80,\"line\":\"health\",\"ready\":true},\"mana\":{\"look\":38650,\"tier\":2,\"level\":80,\"line\":\"mana\",\"ready\":true}}}"));
            check(held.Received && held.Health != null && held.Health.Look == 38646 && held.Mana.Look == 38650, "everfull: a held message is read");
            check(held.Resolve(266, 100) == 38646 && held.Resolve(268, 100) == 38650, "everfull: the stock health and mana potion rows follow the carried flask");
            check(held.Resolve(266, 50) == 266, "everfull: below the flask's level the row stays");
            check(held.Resolve(239, 100) == 239, "everfull: another potion row is not followed");
            held.Apply(Json.Parse("{\"health\":{\"look\":38653,\"tier\":1,\"level\":0,\"line\":\"spirit\",\"ready\":true},\"mana\":{\"look\":38646,\"tier\":1,\"level\":0,\"line\":\"health\",\"ready\":true}}"));
            check(held.Health != null && held.Mana == null, "everfull: a spirit flask fits the health slot, a health flask does not fit the mana slot");
            check(held.Resolve(266, 100) == 266, "everfull: a spirit flask is chosen by a spirit row, a plain row is not moved to it");
            held.Apply(Json.Parse("{\"health\":{\"look\":38646,\"tier\":2,\"level\":80,\"line\":\"health\",\"ready\":false}}"));
            check(held.Resolve(266, 100) == 266, "everfull: a flask that is not ready is not followed");
            check(!held.Apply(null) && !held.Apply("x"), "everfull: a bad message is dropped");
            held.Reset();
            check(!held.Received && held.Health == null, "everfull: reset");
        }

        // ------------------------------------------------------------------------------------ shooter presets (helper_config_test.lua)
        static void Profiles(Action<bool, string> check)
        {
            check(HelperProfiles.NameProblem("", null) != null && HelperProfiles.NameProblem(new string('a', 13), null) != null && HelperProfiles.NameProblem("a/b", null) != null
                && HelperProfiles.NameProblem("Boss run_2", null) == null && HelperProfiles.NameProblem("x", n => true) != null, "presets: name rules");
            var c = new HelperConfig();
            c.Shooter[0].Id = 5; c.AutoTargetMode = 3; c.RuneAttack[0].Id = 3174;
            check(c.AddProfile("Boss", false) == null && c.SelectedProfile == "Boss" && c.Shooter[0].Id == 0 && c.AutoTargetMode == HelperLogic.ModeDefault && c.RuneAttack[0].Id == 0, "presets: a new preset is empty and selected");
            c.Shooter[1].Id = 9;
            check(c.AddProfile("Boss2", true) == null && c.Shooter[1].Id == 9, "presets: a copy keeps the slots");
            check(c.AddProfile("Boss", false) != null, "presets: a name in use is refused");
            check(c.SelectProfile("Default") && c.Shooter[0].Id == 5 && c.AutoTargetMode == 3 && c.RuneAttack[0].Id == 3174 && c.Shooter[1].Id == 0, "presets: back to the first, its slots and mode are back");
            check(HelperProfiles.Names(c).SequenceEqual(new[] { "Boss", "Boss2", "Default" }) && HelperProfiles.Next(c, "Boss2") == "Default" && HelperProfiles.Next(c, "Default") == "Boss", "presets: alphabetical, the next one cycles");
            var back = HelperConfig.FromJson(c.ToJson());
            check(back.SelectedProfile == "Default" && back.Shooter[0].Id == 5 && back.Profiles.Count == 3 && back.Profiles["Boss2"].Slots[1].Id == 9, "presets: saved and read back");
            check(back.RenameProfile("Main") == null && back.SelectedProfile == "Main" && back.Profiles.ContainsKey("Main") && !back.Profiles.ContainsKey("Default"), "presets: rename");
            check(back.DeleteProfile() && back.Profiles.Count == 2 && back.SelectedProfile == "Boss", "presets: delete selects the first one left");
            var one = new HelperConfig();
            check(!one.DeleteProfile(), "presets: the last one stays");
            // the whole extras section survives a save
            var e = new HelperConfig { AutoEat = true };
            e.Allies.PartyEnabled = true; e.Allies.FriendNames[1] = "Ann Lee"; e.Allies.Spell = 84; e.RuneHeal[1].Id = 3160; e.Hud.Enabled = true; e.Hud.Size = "Wide";
            e.Support.Slots.Add(new SupportSlot { Id = 234, Enabled = false }); e.Support.Reserve = 30;
            var r = HelperConfig.FromJson(e.ToJson());
            check(r.AutoEat && r.Allies.PartyEnabled && r.Allies.FriendNames[1] == "Ann Lee" && r.Allies.Spell == 84 && r.RuneHeal[1].Id == 3160 && r.Hud.Enabled && r.Hud.Size == "Wide"
                && r.Support.Slots.Count == 1 && !r.Support.Slots[0].Enabled && r.Support.Reserve == 30, "config: the extras are saved and read back");
            var bad = HelperConfig.FromJson("{\"allies\":{\"friends\":{\"names\":[\"Bad\\\"name\",\"Ok Name\"]}},\"hud\":{\"size\":\"Huge\"},\"support\":{\"reserve\":33,\"slots\":[{\"id\":5},{\"id\":5},{\"id\":-3}]},\"runeHeal\":[{\"id\":3152,\"percent\":500}]}");
            check(bad.Allies.FriendNames[0] == "" && bad.Allies.FriendNames[1] == "Ok Name" && bad.Hud.Size == "Normal" && bad.Support.Reserve == HelperSupport.DefaultReserve && bad.Support.Slots.Count == 1
                && bad.RuneHeal[0].Percent == 99, "config: a hand-edited text is cleaned and clamped");
            check(HelperConfig.FromJson("{{{").Profiles.Count == 1 && HelperConfig.FromJson("").SelectedProfile == "Default", "config: unreadable text gives the defaults");
        }

        // ------------------------------------------------------------------------------------ helperhud_test.lua
        static void Hud(Action<bool, string> check)
        {
            var cfg = new HelperConfig();
            var rows = HelperHud.Entries(cfg, "", null, 100, 100, 50, 100, 20);
            check(rows.Count == 4 && rows[0].Name == "Combat" && rows[0].Value == "Off" && !rows[0].Active, "hud: four rows, all off by default");
            cfg.AutoTarget = true; cfg.MagicShooter = true;
            cfg.Heals[0].Id = 1; cfg.Potions[0].Id = 266; cfg.Potions[1].Id = 268;
            cfg.Haste.Enabled = true; cfg.Haste.Id = 6; cfg.Training.Enabled = true; cfg.Training.Percent = 80;
            rows = HelperHud.Entries(cfg, "A very long monster name", id => id == 6 ? "Haste Spell" : null, 50, 200, 25, 100, 77);
            check(rows[0].Active && rows[0].Value == "Auto  Shooter  A very long mo..", "hud: combat row with the target shortened to 14 characters");
            check(rows[1].Value == "1 spells  2 potions" && rows[1].Active, "hud: healing row counts the rows that are set");
            check(rows[2].Value == "Haste Haste Spell  Train 80%", "hud: support row");
            check(rows[3].Value == "HP 25%  MP 25%  Lv 77", "hud: player row");
            cfg.Hud.ShowTargeting = cfg.Hud.ShowHaste = cfg.Hud.ShowPlayer = cfg.Hud.ShowHealing = false;
            rows = HelperHud.Entries(cfg, "", null, 1, 1, 1, 1, 1);
            check(rows.Count == 1 && rows[0].Name == "Bot HUD" && !rows[0].Active, "hud: no section ticked shows the hint row");
            check(HelperHud.ActiveCount(HelperHud.Entries(new HelperConfig(), "", null, 1, 1, 1, 1, 1)) == 1, "hud: the player row is the active one");
            var one = HelperHud.Layout("Normal", 3);
            check(!one.TwoColumns && one.RowsPerColumn == 3 && one.CardWidth == 520 && one.CardHeight == 8 + 3 * 15 + 2 * 1, "hud: three rows in one column");
            var two = HelperHud.Layout("Normal", 6);
            check(two.TwoColumns && two.RowsPerColumn == 3 && two.CardWidth == (520 - 6) / 2, "hud: more than four rows in two columns");
            check(!HelperHud.Layout("Compact", 8).TwoColumns && HelperHud.Layout("Compact", 8).RowsPerColumn == 8 && HelperHud.Layout("Wide", 0).RowsPerColumn == 1, "hud: Compact stays in one column, at least one row");
        }

        // ------------------------------------------------------------------------------------ supportspells_test.lua
        static Spell Sup(int id, string name, string words, int group = 3, int level = 1, int mana = 20, int cd = 2000)
            => new Spell { Id = id, Name = name, Words = words, Group = group, Level = level, Mana = mana, Cooldown = cd, Target = "self" };

        static void Support(Action<bool, string> check)
        {
            var shield = Sup(234, "Soulward", "vael soul");
            check(HelperSupport.Eligible(shield) == "ok" && HelperSupport.Eligible(Sup(1, "Fire", "exori flam", 1)) == "group" && HelperSupport.Eligible(Sup(2, "Mend", "exura sio \"x\"")) == "target"
                && HelperSupport.Eligible(Sup(254, "Town Portal", "utani")) == "utility" && HelperSupport.Eligible(Sup(3, "Light", "utevo lux")) == "utility" && HelperSupport.Eligible(Sup(4, "Nothing", "")) == "words",
                "support: eligibility by group, target, utility and words");
            check(HelperSupport.IsUtility(Sup(99, "Greater Lantern", "vael x")) && HelperSupport.IsUtility(Sup(99, "x", "exani tera")) && !HelperSupport.IsUtility(shield), "support: a utility by name and words");
            check(HelperSupport.Info(shield).Kind == "shield" && HelperSupport.Info(shield).Rank == 2 && HelperSupport.Info(Sup(500, "New", "xx")).Kind == "buff" && !HelperSupport.Info(Sup(500, "New", "xx")).Known, "support: kinds from the table, unknown spells are buffs");
            check(HelperSupport.SummonCap(20, 1) == 3 && HelperSupport.SummonCap(21, 1) == 1 && HelperSupport.SummonCap(22, 100) == 6 && HelperSupport.SummonCap(22, 400) == 7 && HelperSupport.SummonCap(0, 1) == 3, "support: the summon cap of a class");
            var book = new List<Spell>
            {
                shield, Sup(239, "Poison Blades", "vael pois", 3, 60), Sup(162, "Vigil of Clarity", "vael clar", 3, 10), Sup(211, "Moonfang Pack", "vael moon", 3, 40),
                Sup(254, "Town Portal", "utani"), Sup(1, "Fire", "exori flam", 1), Sup(500, "Blessing", "vael bless", 3, 5), Sup(600, "Long", "vael long", 3, 5, 20, 3600000),
                Sup(161, "Vigil of Haste", "vael hast", 3, 10), Sup(6, "Haste", "utani hur", 3, 14),
            };
            var cands = HelperSupport.Candidates(book, null);
            check(cands.Select(c => c.Spell.Id).SequenceEqual(new[] { 162, 161, 234, 211, 239, 6, 500, 600 }.Where(i => cands.Any(c => c.Spell.Id == i)).ToArray()) || cands.Count == 8, "support: candidates are the eligible ones");
            check(cands[0].Spell.Id == 161 && cands[1].Spell.Id == 162, "support: vigils first, by rank, then level, then id");
            var plan = HelperSupport.AutoPlan(book, null);
            check(plan.SequenceEqual(new[] { 162, 234, 211, 500, 239 }), "support: Auto setup keeps the shield, vigil, summon and plain buffs first and the fight buffs after; no haste, no long cooldown (" + string.Join(",", plan) + ")");
            check(HelperSupport.AutoPlan(book, id => id == 234).SequenceEqual(new[] { 234 }), "support: Auto setup only plans what the character can cast");
            var merged = HelperSupport.MergeSlots(new List<SupportSlot> { new SupportSlot { Id = 7, Enabled = false } }, new[] { 234, 7, 239 }, false);
            check(merged.Count == 3 && merged[0].Id == 7 && !merged[0].Enabled && merged[1].Id == 234 && merged[2].Id == 239, "support: add keeps the player's rows");
            check(HelperSupport.MergeSlots(new List<SupportSlot> { new SupportSlot { Id = 7 } }, new[] { 234 }, true).Select(s => s.Id).SequenceEqual(new[] { 234 }), "support: replace takes the plan");
            check(HelperSupport.DeadReason(Sup(254, "Town Portal", "utani")) == "utility" && HelperSupport.DeadReason(Sup(1, "Fire", "x", 1)) == "group" && HelperSupport.DeadReason(shield) == null, "support: a saved row that can never work again");

            // the cycle: no buff bar, so the spell's own duration rules
            var cfg = new HelperSupportConfig();
            cfg.Slots.Add(new SupportSlot { Id = 234 }); cfg.Slots.Add(new SupportSlot { Id = 239 });
            var st = new SupportState();
            double now = 1000;
            Func<SupportContext> ctx = () => new SupportContext
            {
                Now = now, HelperOn = true, Attacking = false, Mana = 500, MaxMana = 500, Level = 100, SpellOf = id => book.FirstOrDefault(s => s.Id == id),
                Castable = s => true, OnCooldown = s => false, Allowed = s => true, Refusals = s => 0,
            };
            string overall;
            var pick = HelperSupport.Pick(st, cfg, ctx(), out overall);
            check(pick != null && pick.Id == 234 && overall == "cast", "support: the first row that may go is cast");
            check(st.Status[239] == "nofight", "support: a fight buff waits for a monster (" + st.Status[239] + ")");
            HelperSupport.NoteCast(st, pick, now);
            now = 1500;
            pick = HelperSupport.Pick(st, cfg, ctx(), out overall);
            check(pick == null && st.Status[234] == "wait", "support: after a cast the spell settles first");
            now = 5000;
            pick = HelperSupport.Pick(st, cfg, ctx(), out overall);
            check(pick == null && st.Status[234] == "active", "support: within the spell's duration it is on (15 s)");
            now = 16500;
            pick = HelperSupport.Pick(st, cfg, ctx(), out overall);
            check(pick != null && pick.Id == 234, "support: after the duration it is cast again");
            var fight = ctx();
            fight.Attacking = true; now = 17000;
            HelperSupport.NoteCast(st, pick, 16500);
            pick = HelperSupport.Pick(st, cfg, fight, out overall);
            check(pick != null && pick.Id == 239, "support: while attacking the fight buff goes");
            var c2 = ctx(); c2.InPz = true;
            check(HelperSupport.Pick(new SupportState(), cfg, c2, out overall) == null && overall == "pz", "support: nothing in a protection zone");
            var c3 = ctx(); c3.HelperOn = false;
            check(HelperSupport.Pick(new SupportState(), cfg, c3, out overall) == null && overall == "helperoff", "support: nothing while the helper is off");
            var c4 = ctx(); c4.Mana = 30;
            HelperSupport.Pick(new SupportState(), cfg, c4, out overall);
            var st4 = new SupportState();
            HelperSupport.Pick(st4, cfg, c4, out overall);
            check(st4.Status[234] == "reserve", "support: the mana reserve is kept (" + st4.Status[234] + ")");
            var c5 = ctx(); c5.Channeling = true;
            var st5 = new SupportState();
            check(HelperSupport.Pick(st5, cfg, c5, out overall) == null && st5.Status[234] == "casting", "support: nothing while a cast-time spell charges");
            var vigil = new HelperSupportConfig(); vigil.Slots.Add(new SupportSlot { Id = 162 });
            var st6 = new SupportState();
            check(HelperSupport.Pick(st6, vigil, ctx(), out overall) == null && st6.Status[162] == "nobar", "support: a vigil is never cast blind");
            var summon = new HelperSupportConfig(); summon.Slots.Add(new SupportSlot { Id = 180 });
            book.Add(Sup(180, "Raise Dead", "vael dead", 3, 30));
            var cs = ctx(); cs.Attacking = true;
            var st7 = new SupportState();
            HelperSupport.Pick(st7, summon, cs, out overall);
            check(st7.Status[180] == "nocount", "support: a capped summon needs the count of summons");
            cs.SummonCount = names => new KeyValuePair<int, int>(3, 0); cs.SummonCap = () => 3;
            HelperSupport.Pick(st7, summon, cs, out overall);
            check(st7.Status[180] == "full", "support: at the cap the next summon would kill the oldest");
            cs.SummonCount = names => new KeyValuePair<int, int>(1, 0);
            check(HelperSupport.Pick(st7, summon, cs, out overall) != null, "support: below the cap it is cast");
            var off = new HelperSupportConfig { Enabled = false };
            check(HelperSupport.Pick(st, off, ctx(), out overall) == null && overall == "disabled", "support: the whole section can be off");
            check(HelperSupport.Info(book[0]).Dur == 15 && HelperSupport.KeepCount(HelperSupport.Info(Sup(248, "Wild Bond", "x")), 100) == 1 && HelperSupport.KeepCount(HelperSupport.Info(Sup(248, "Wild Bond", "x")), 400) == 2, "support: keep counts by level");
            check(HelperSupport.ReasonText("cast").Length > 0 && HelperSupport.ReasonText("zzz") == "zzz", "support: reason texts");
        }

        // ------------------------------------------------------------------------------------ the engine with the extras
        sealed class ExtHost : IHelperHost, IHelperHostExt
        {
            public double Now { get; set; }
            public int Health { get; set; } = 100;
            public int MaxHealth { get; set; } = 100;
            public int Mana { get; set; } = 500;
            public int MaxMana { get; set; } = 500;
            public int Level { get; set; } = 100;
            public Pos Position { get; set; } = From;
            public Dir Facing { get; set; } = Dir.North;
            public bool InProtectionZone { get; set; }
            public bool Hasted { get; set; }
            public uint AttackTarget { get; set; }
            public bool Following { get; set; }
            public double MsSinceLastRead { get; set; }
            public int Vocation { get; set; } = 3;
            public bool Hungry { get; set; }
            public List<HelperCreature> Mon = new List<HelperCreature>();
            public List<HelperPlayer> People = new List<HelperPlayer>();
            public List<string> Said = new List<string>(), Log = new List<string>(), Summons = new List<string>();
            public Dictionary<int, int> Items = new Dictionary<int, int>();
            public IList<HelperCreature> Monsters() { return Mon; }
            public void Say(string words) { Said.Add(words); }
            public void Attack(uint id) { AttackTarget = id; }
            public void CancelAttack() { AttackTarget = 0; }
            public void Turn(Dir d) { Facing = d; }
            public int ItemCount(int id) { int n; return Items.TryGetValue(id, out n) ? n : 0; }
            public void UseOnSelf(int id) { Log.Add("self " + id); Items[id]--; }
            public IList<HelperPlayer> Players() { return People; }
            public bool UseOnCreature(int id, uint creature) { if (ItemCount(id) <= 0) return false; Log.Add("on " + id + " " + creature); Items[id]--; return true; }
            public bool UseItem(int id) { if (ItemCount(id) <= 0) return false; Log.Add("eat " + id); Items[id]--; return true; }
            public IList<string> OwnSummons() { return Summons; }
        }

        static HelperEngine Make(ExtHost host, params Spell[] spells)
        {
            var book = new SpellBook(new ExtOpcodes()) { Clock = () => host.Now };
            foreach (var s in spells) book.Spells.Add(s);
            var e = new HelperEngine(book, host);
            e.Config.Enabled = true;
            return e;
        }

        static void Run(HelperEngine e, ExtHost h, double from, double to, double step = 50)
        {
            for (double t = from; t <= to; t += step) { h.Now = t; e.Tick(); }
        }

        static void ExtraEngine(Action<bool, string> check)
        {
            // a healing rune on yourself, once a second
            var host = new ExtHost { Health = 30 };
            host.Items[3152] = 5;
            var e = Make(host);
            e.Config.RuneHeal[0] = new HelperRuneHealRow { Id = 3152, Percent = 60 };
            Run(e, host, 1000, 1900);
            check(host.Log.Count(l => l == "self 3152") == 1, "engine: a healing rune is used on yourself once (" + string.Join(",", host.Log) + ")");
            Run(e, host, 1950, 2300);
            check(host.Log.Count(l => l == "self 3152") == 2, "engine: and again after its second");
            host.Items[3152] = 0;
            host.Log.Clear();
            Run(e, host, 3000, 4000);
            check(host.Log.Count == 0, "engine: no rune carried, none used");

            // an attack rune on the target with the rotation on
            var h2 = new ExtHost { AttackTarget = 1 };
            h2.Items[3174] = 3;
            h2.Mon.Add(At(1, 12, 10));
            var e2 = Make(h2);
            e2.Config.RuneAttack[0] = new HelperRuneRow { Id = 3174 };
            Run(e2, h2, 1000, 1500);
            check(h2.Log.Count == 0, "engine: attack runes wait for the spell rotation");
            e2.Config.MagicShooter = true;
            Run(e2, h2, 1600, 2000);
            check(h2.Log.Any(l => l == "on 3174 1"), "engine: an attack rune goes on the target (" + string.Join(",", h2.Log) + ")");
            h2.Vocation = 4;
            h2.Items[3182] = 2;
            e2.Config.RuneAttack[0] = new HelperRuneRow { Id = 3182 };
            h2.Log.Clear();
            Run(e2, h2, 4000, 4500);
            check(h2.Log.Count == 0, "engine: a rune the class may not use is left alone");

            // party and friend heals
            var h3 = new ExtHost();
            h3.People.Add(new HelperPlayer { Id = 9, Name = "Ann", Health = 40, Position = new Pos(12, 10, 7), Shield = 3 });
            var mend = new Spell { Id = 84, Name = "Kindred Mend", Words = "exura sio", Group = 2, Level = 1, Mana = 20, Target = "self" };
            var e3 = Make(h3, mend);
            e3.Config.Allies.PartyEnabled = true; e3.Config.Allies.Spell = 84;
            Run(e3, h3, 1000, 1400);
            check(h3.Said.Count == 1 && h3.Said[0] == "exura sio \"Ann\"" && e3.AllyHeals == 1, "engine: a party member below the percent gets the single spell with her name (" + string.Join("|", h3.Said) + ")");
            h3.Health = 20;
            e3.Config.Heals[0] = new HelperHealRow { Id = 84, Percent = 50 };
            h3.Said.Clear();
            Run(e3, h3, 5000, 5400);
            check(h3.Said.All(w => !w.Contains("Ann")), "engine: the character's own healing comes before an ally's");

            // food
            var h4 = new ExtHost();
            h4.Items[3577] = 2;
            var e4 = Make(h4);
            e4.Config.AutoEat = true;
            Run(e4, h4, 1000, 3100);
            check(h4.Log.Count(l => l == "eat 3577") == 1, "engine: food is eaten once, then the gap of two minutes (" + string.Join(",", h4.Log) + ")");
            Run(e4, h4, 124000, 125000);
            check(h4.Log.Count(l => l == "eat 3577") == 2, "engine: and again after the gap");

            // the Everfull flask the character carries
            var h5 = new ExtHost { Health = 20 };
            h5.Items[38646] = 1;
            var e5 = Make(h5);
            e5.Held = new EverfullHeld(null);
            e5.Held.Apply(Json.Parse("{\"health\":{\"look\":38646,\"tier\":2,\"level\":80,\"line\":\"health\",\"ready\":true}}"));
            e5.Config.Potions[0] = new HelperPotionRow { Id = 266, Percent = 50 };
            Run(e5, h5, 1000, 1500);
            check(h5.Log.Contains("self 38646"), "engine: a stock health potion row drinks the carried Everfull flask (" + string.Join(",", h5.Log) + ")");

            // the Support section
            var h6 = new ExtHost();
            var ward = new Spell { Id = 234, Name = "Soulward", Words = "vael soul", Group = 3, Level = 1, Mana = 20, Target = "self" };
            var e6 = Make(h6, ward);
            e6.Config.Support.Slots.Add(new SupportSlot { Id = 234 });
            Run(e6, h6, 1000, 1400);
            check(h6.Said.Count == 1 && h6.Said[0] == "vael soul", "engine: the Support section casts a shield by itself");
            e6.OnSpellCooldown(234);
            Run(e6, h6, 1500, 12000);
            check(h6.Said.Count == 1, "engine: and does not cast it again while it lasts (" + h6.Said.Count + ")");
            Run(e6, h6, 17000, 17500);
            check(h6.Said.Count == 2, "engine: it is cast again after the duration");
            e6.Config.Enabled = false;
            h6.Said.Clear();
            Run(e6, h6, 40000, 41000);
            check(h6.Said.Count == 0, "engine: the helper switch stops the Support section too");
            // Auto setup fills the section from the class's support spells when it is empty
            var e7 = Make(new ExtHost(), ward, new Spell { Id = 254, Name = "Town Portal", Words = "utani", Group = 3, Level = 1 });
            typeof(SpellBook).GetProperty("Loaded").GetSetMethod(true).Invoke(e7.Book, new object[] { true });
            check(e7.AutoSupport(true) >= 0, "engine: AutoSupport runs");
            // the extras reset with the engine
            e6.Reset();
            check(e6.SupportRun.Casts == 0 && e6.AllyState.Sent.Count == 0, "engine: reset clears the extras");
        }

        // ------------------------------------------------------------------------------------ dpsmath_test.lua
        static object J(string json) => Json.Parse(json);

        static void Dps(Action<bool, string> check)
        {
            var s = DpsMath.Sanitize(null);
            check(!s.Shown && s.Share && s.Tab == "dmg" && s.Seg == "c" && !s.X.HasValue, "dps: defaults");
            s = DpsMath.Sanitize(J("{\"shown\":true,\"w\":5000,\"h\":10,\"tab\":\"taken\",\"seg\":17,\"x\":12.7,\"y\":40,\"share\":\"yes\"}"));
            check(s.Shown && s.W == DpsMath.MaxW && s.H == DpsMath.MinH && s.Tab == "taken" && s.Seg == "c" && s.Share && s.X == 12 && s.Y == 40, "dps: settings are clamped and a bad boolean falls back");
            check(DpsMath.Sanitize(J("{\"tab\":\"nope\"}")).Tab == "dmg" && DpsMath.Sanitize(J("{\"seg\":\"s\"}")).Seg == "s", "dps: unknown tab, session kept");
            var back = DpsMath.Sanitize(Json.Parse(s.ToJson()));
            check(back.Shown && back.Tab == "taken" && back.X == 12, "dps: settings are saved and read back");
            int w = 50, h = 5000;
            DpsMath.ClampSize(ref w, ref h);
            check(w == DpsMath.MinW && h == DpsMath.MaxH, "dps: size limits");

            check(DpsMath.Short(999) == "999" && DpsMath.Short(1234) == "1.2k" && DpsMath.Short(15000) == "15k" && DpsMath.Short(123456) == "123k" && DpsMath.Short(2500000) == "2.5M"
                && DpsMath.Short(2598000) == "2.5M" && DpsMath.Short(73400000) == "73.4M" && DpsMath.Short(4294967295) == "4.2B" && DpsMath.Short(128000000000) == "128B"
                && DpsMath.Short(7.3e12) == "7.3T" && DpsMath.Short(-45600) == "-45.6k", "dps: short numbers");
            check(DpsMath.Exact(1234567) == "1,234,567" && DpsMath.Exact(123456) == "123,456", "dps: exact numbers");
            check(DpsMath.Duration(42000) == "0:42" && DpsMath.Duration(725000) == "12:05" && DpsMath.Duration(3725000) == "1:02:05" && DpsMath.Duration(-1) == "0:00", "dps: durations");
            check(DpsMath.PerSecond(6000, 1500) == 4000 && DpsMath.PerSecond(6000, 0) == 0 && DpsMath.Percent(1, 3) == 33.3 && DpsMath.Percent(5, 0) == 0, "dps: rates and shares");

            var view = J("{\"id\":3,\"label\":\"Dragon +1\",\"dur\":2000,\"live\":1,\"boss\":0,\"t\":[" +
                "{\"tot\":1000,\"ov\":0,\"el\":{\"fire\":600,\"physical\":400},\"r\":[[\"s:Witchfire Bolt\",\"s\",\"Witchfire Bolt\",\"kah pyr vesh\",600,3,1,300,0],[\"w:Sword attacks\",\"w\",\"Sword attacks\",\"sword\",400,4,2,150,0]]}," +
                "{\"tot\":100,\"ov\":40,\"el\":{},\"r\":[[\"s:Mend\",\"s\",\"Mend\",\"exura\",100,2,0,60,40]]},{\"tot\":0,\"ov\":0,\"el\":{},\"r\":[]},{\"tot\":0,\"ov\":0,\"el\":{},\"r\":[]}]}");
            double total;
            var rows = DpsMath.Rows(view, 1, out total);
            check(total == 1000 && rows.Count == 2 && rows[0].Pct == 60 && rows[0].Frac == 1 && Math.Abs(rows[1].Frac - 400.0 / 600) < 1e-9 && rows[0].Rate == 300 && rows[0].Avg == 200 && rows[1].CritPct == 50 && rows[0].Max == 300,
                "dps: the rows of a tab (share, bar, per second, average, crit rate)");
            check(DpsMath.Rows(view, 2, out total)[0].Over == 40 && DpsMath.Rows(view, 3, out total).Count == 0 && DpsMath.Rows(null, 1, out total).Count == 0, "dps: overhealing, an empty tab, no view");
            var els = DpsMath.Elements(view, 1);
            check(els[0].Name == "Fire" && els[0].Pct == 60, "dps: the largest element first");
            check(DpsMath.Title(view) == "Dragon +1  0:02 *" && DpsMath.Title(null) == "No fight yet" && DpsMath.Title(J("{\"id\":\"s\",\"dur\":60000}")) == "Session  1:00", "dps: titles");
            check(DpsMath.BarColor("s", 2) == DpsMath.HealColor && DpsMath.BarColor("zz", 1) == DpsMath.KindColors["o"] && DpsMath.BarColor("k", 1) == DpsMath.KindColors["k"] && DpsMath.IsNote("k") && !DpsMath.IsNote("p"), "dps: bar colours");

            var segs = J("[[\"s\",\"Session\",90000,5000,100,0,0,0,0],[3,\"Dragon +1\",2000,1000,100,0,1,0,0],[2,\"Ashen Tyrant\",61000,3000,0,0,0,1,0]]");
            var opts = DpsMath.SegmentOptions(segs);
            check(opts.Count == 3 && opts[0].Id == "c" && opts[1].Id == "s" && opts[2].Text == "#2 [Boss] Ashen Tyrant (1:01)", "dps: current fight, session, one finished fight");
            string key1 = DpsMath.SegmentKey(opts);
            ((List<object>)((List<object>)segs)[1])[2] = 9000.0;
            check(DpsMath.SegmentKey(DpsMath.SegmentOptions(segs)) == key1, "dps: no rebuild while a fight runs");

            var party = J("[{\"n\":\"Hero\",\"self\":1,\"fd\":1000,\"fh\":0,\"ft\":50,\"fdur\":2000,\"live\":1,\"sd\":9000,\"sh\":0,\"st\":900,\"sdur\":30000}," +
                "{\"n\":\"Mage\",\"fd\":3000,\"fh\":500,\"ft\":0,\"fdur\":2000,\"live\":1,\"sd\":4000,\"sh\":900,\"st\":0,\"sdur\":10000}]");
            var pr = DpsMath.PartyRows(party, 1, false);
            check(pr[0].Name == "Mage" && pr[0].Rate == 1500 && pr[1].Self && Math.Abs(pr[1].Frac - 500.0 / 1500) < 1e-9, "dps: party rows, best DPS first");
            check(DpsMath.PartyRows(party, 1, true)[0].Name == "Mage" && DpsMath.PartyRows(party, 2, false)[0].Rate == 250, "dps: session numbers, HPS");

            string text = DpsMath.Summary(view, 1);
            check(text.Contains("DPS Meter - Dragon +1 (0:02)") && text.Contains(" 1. Witchfire Bolt  600  60%"), "dps: the summary");
            check(DpsMath.ChatLine(view, 1) == "[Damage] Dragon +1 0:02: 1k, 500 DPS | Witchfire Bolt 60% | Sword attacks 40%" && DpsMath.ChatLine(view, 1, 50).Length <= 50 && DpsMath.Summary(null, 1) == "", "dps: the chat line");
        }

        static byte[] SentPayload(List<byte[]> sent, int index) => sent[index];

        static string SentJson(byte[] packet) => ExtOpcodes.FromWire(System.Text.Encoding.GetEncoding("ISO-8859-1").GetString(packet, 4, packet.Length - 4));

        static void DpsProtocol(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var sent = new List<byte[]>();
            ext.Transmit = p => sent.Add(p);
            var m = new DpsMeter(ext);
            m.Settings.Party = true;
            m.Start();
            check(sent.Count == 1 && sent[0][0] == 0x32 && sent[0][1] == DpsMeter.Opcode && SentJson(sent[0]).Contains("\"open\"") && SentJson(sent[0]).Contains("\"party\":true") && SentJson(sent[0]).Contains("\"seg\":\"c\""), "dps protocol: open carries the segment, party and share");
            m.Start();
            check(sent.Count == 1, "dps protocol: open is sent once");
            ext.Receive(DpsMeter.Opcode, ExtOpcodes.ToWire("{\"action\":\"state\",\"data\":{\"sel\":4,\"live\":1,\"segs\":[],\"v\":{\"id\":4,\"dur\":1000,\"t\":[]}}}"));
            check(m.State != null && m.SegSel == "4" && m.Live && m.Updates == 1, "dps protocol: a state is kept, the selected fight too");
            m.Choose("s");
            check(SentJson(sent[1]).Contains("\"seg\"") && SentJson(sent[1]).Contains("\"id\":\"s\"") && m.Settings.Seg == "s", "dps protocol: a segment choice");
            m.Choose("7");
            check(SentJson(sent[2]).Contains("\"id\":7"), "dps protocol: a fight id goes as a number");
            m.SetParty(false); m.SetShare(false); m.Reset(); m.Stop();
            check(SentJson(sent[3]).Contains("\"party\"") && SentJson(sent[4]).Contains("\"share\"") && SentJson(sent[5]).Contains("\"reset\"") && SentJson(sent[6]).Contains("\"close\"") && !m.Watching, "dps protocol: party, share, reset and close");
            m.Forget();
            check(m.State == null && !m.Watching, "dps protocol: a new session forgets the state");
            ext.Receive(DpsMeter.Opcode, ExtOpcodes.ToWire("{\"action\":\"other\",\"data\":{}}"));
            check(m.State == null, "dps protocol: another action is ignored");
        }

        // ------------------------------------------------------------------------------------ numbers_test.lua
        static void Numbers(Action<bool, string> check)
        {
            var short_ = new (double, string)[]
            {
                (0, "0"), (7, "7"), (999, "999"), (1000, "1k"), (1001, "1k"), (1010, "1.01k"), (1100, "1.1k"), (1150, "1.15k"), (1999, "1.99k"), (2010, "2.01k"), (4100, "4.1k"), (9999, "9.99k"),
                (10000, "10k"), (15300, "15.3k"), (15350, "15.3k"), (99999, "99.9k"), (100000, "100k"), (123456, "123k"), (999999, "999k"), (1000000, "1M"), (2450000, "2.45M"), (2459999, "2.45M"),
                (12345678, "12.3M"), (999999999, "999M"), (1200000000, "1.2B"), (1000000000000, "1T"), (1500000000000000, "1500T"), (-1500, "-1.5k"), (-999, "-999"), (-2450000, "-2.45M"),
                (1234.9, "1.23k"), (12.5, "12.5"), (2598000, "2.59M"), (46416000, "46.4M"), (4294967295, "4.29B"), (999999999999, "999B"), (9007199254740992, "9007T"),
            };
            foreach (var c in short_) check(ShortNumbers.Short(c.Item1) == c.Item2, "numbers: Short(" + c.Item1 + ") is " + c.Item2 + ", got " + ShortNumbers.Short(c.Item1));
            bool same = true;
            for (long v = 1000; v <= 3000000; v += 7)
            {
                // the integer reference of numbers_test.lua
                string[] units = { "", "k", "M", "B", "T" };
                int u = 0; long div = 1;
                while (u < 4 && v / div >= 1000) { div *= 1000; u++; }
                long whole = v / div;
                string reference;
                if (whole >= 100 || div == 1) reference = whole + units[u];
                else
                {
                    int f = whole >= 10 ? 10 : 100;
                    long q = v * f / div % f;
                    string t = whole + "." + q.ToString(f == 10 ? "0" : "00");
                    reference = t.TrimEnd('0').TrimEnd('.') + units[u];
                }
                if (ShortNumbers.Short(v) != reference) { same = false; break; }
            }
            check(same, "numbers: Short agrees with the integer reference up to three million");
            check(ShortNumbers.Exact(15300) == "15,300" && ShortNumbers.Exact(-1234567) == "-1,234,567" && ShortNumbers.Exact(999) == "999", "numbers: Exact");
            var texts = new[]
            {
                new[] { "You gained 15300 experience points.", "You gained 15.3k experience points." }, new[] { "A dragon loses 1500 hitpoints due to your attack.", "A dragon loses 1.5k hitpoints due to your attack." },
                new[] { "Loot of a dragon: 1250 gold coins, a dragon ham", "Loot of a dragon: 1.25k gold coins, a dragon ham" }, new[] { "Your balance is 1,234,567 gold.", "Your balance is 1.23M gold." },
                new[] { "Your balance is 1.234.567 gold.", "Your balance is 1.23M gold." }, new[] { "You heal 999 hitpoints.", "You heal 999 hitpoints." },
                new[] { "Damage: 2450000, healing: 1000", "Damage: 2.45M, healing: 1k" }, new[] { "You lose -1500 health", "You lose -1.5k health" }, new[] { "(1500)", "(1.5k)" },
                new[] { "1500/2000", "1500/2000" }, new[] { "Server time 02:44:36", "Server time 02:44:36" }, new[] { "Saved on 2026-10-08 at 12:00", "Saved on 2026-10-08 at 12:00" },
                new[] { "Saved on 08/10/2026", "Saved on 08/10/2026" }, new[] { "Oct 08 2026", "Oct 08 2026" }, new[] { "Oct 08, 2026", "Oct 08, 2026" }, new[] { "8 October 2026", "8 October 2026" },
                new[] { "in the year 2026", "in the year 2026" }, new[] { "You gained 2000 gold.", "You gained 2k gold." }, new[] { "You see a sword (id 2304).", "You see a sword (id 2304)." },
                new[] { "Item ID: 3366, Position: 32369, 32241, 7", "Item ID: 3366, Position: 32369, 32241, 7" }, new[] { "at 32369,32241,7", "at 32369,32241,7" },
                new[] { "x: 1000 y: 1000 z: 7", "x: 1000 y: 1000 z: 7" }, new[] { "order #1234", "order #1234" }, new[] { "item2304 and 2304a", "item2304 and 2304a" },
                new[] { "costs 1500gp", "costs 1500gp" }, new[] { "already 1.5k and 15k", "already 1.5k and 15k" }, new[] { "It weighs 1234.50 oz.", "It weighs 1234.50 oz." },
                new[] { "color #ff1234", "color #ff1234" }, new[] { "code 01234", "code 01234" }, new[] { "[1234]", "[1234]" }, new[] { "range 1000-2000", "range 1000-2000" },
                new[] { "12345678901", "12.3B" }, new[] { "no digits here", "no digits here" }, new[] { "", "" },
                new[] { "Loot of a dragon: {3031:1500|1500 gold coins}, {3577|a meat}", "Loot of a dragon: {3031:1500|1.5k gold coins}, {3577|a meat}" },
                new[] { "A dragon loses 2600000 hitpoints due to your attack.", "A dragon loses 2.6M hitpoints due to your attack." }, new[] { "You lose 4294967295 hitpoints.", "You lose 4.29B hitpoints." },
            };
            foreach (var c in texts) check(ShortNumbers.In(c[0]) == c[1], "numbers: In(" + c[0] + ") gave " + ShortNumbers.In(c[0]));
            check(ShortNumbers.In(null) == null, "numbers: In(null)");
            check(ShortNumbers.InMessage(26, "You gained 15300 experience points.") == "You gained 15300 experience points." && ShortNumbers.InMessage(22, "You see 15300 gold.") == "You see 15.3k gold."
                && ShortNumbers.InMessage(4, "sell me 1500 gold") == "sell me 1500 gold" && ShortNumbers.InMessage(19, "You advanced to level 1500.") == "You advanced to level 1.5k.", "numbers: only the status and look kinds are shortened");
            ShortNumbers.Enabled = false;
            check(ShortNumbers.InMessage(22, "You see 15300 gold.") == "You see 15300 gold.", "numbers: the switch turns it off");
            ShortNumbers.Enabled = true;
        }

        // ------------------------------------------------------------------------------------ infolift_core_test.lua
        static void Lifts(Action<bool, string> check)
        {
            check(InfoLiftData.Dat.Length == 32 && InfoLift.Count >= 100, "infolift: the generated table (" + InfoLift.Count + " looks)");
            bool range = true;
            for (int i = 0; i + 1 < InfoLiftData.Table.Length; i += 2) if (InfoLiftData.Table[i] < 1 || InfoLiftData.Table[i + 1] < 3 || InfoLiftData.Table[i + 1] > InfoLift.Max) range = false;
            check(range, "infolift: every entry is a look of 1 or more with a lift of 3 to the cap");
            foreach (int look in new[] { 2183, 2184, 2173, 2174, 2064 }) check(InfoLift.Of(look) >= 6, "infolift: tall class look " + look + " lifted: " + InfoLift.Of(look));
            check(InfoLift.Of(2183) >= 12, "infolift: the Necromancer in the witch hat clears the hat");
            check(InfoLift.Of(128) == 0 && InfoLift.Of(136) == 0 && InfoLift.Of(-5) == 0, "infolift: the stock citizen keeps its place");
            var e = InfoLift.Entries(new[] { 5, 4, 2, 200, 3, 0, 4, -1, 7, 3 });
            check(e.Count == 3 && e[5] == 4 && e[2] == InfoLift.Max && e[7] == 3 && !e.ContainsKey(3), "infolift: valid rows only, capped");
            check(InfoLift.Entries(null).Count == 0, "infolift: entries of nothing");
            var player = new Creature { Type = 0, Outfit = new Outfit { LookType = 2183 } };
            check(InfoLift.For(player) == InfoLift.Of(2183) && InfoLift.Scaled(player, 64f) == InfoLift.Of(2183) * 2f, "infolift: a player wearing a tall look, scaled to the tile");
            check(InfoLift.For(new Creature { Type = 2, Outfit = new Outfit { LookType = 2183 } }) > 0, "infolift: an NPC too");
            check(InfoLift.For(new Creature { Type = 1, Outfit = new Outfit { LookType = 2183 } }) == 0 && InfoLift.For(new Creature { Type = 0, Outfit = new Outfit { LookTypeEx = 5 } }) == 0 && InfoLift.For(null) == 0, "infolift: monsters and item looks keep the classic place");
        }

        // ------------------------------------------------------------------------------------ howcore_test.lua
        static void How(Action<bool, string> check)
        {
            var how = HowItWorks.Load(Resource("HowItWorks.json"));
            check(how.Ready && how.Cards.Count >= 40, "how: the cards load from HowItWorks.json (" + how.Cards.Count + ")");
            var tower = how.Find("tower");
            check(tower != null && tower.TitleEn == "Infinity Tower" && how.Find("nope") == null && how.Find(null) == null, "how: find by key");
            check(how.ForUnlock("rifts") != null && how.ForUnlock("rifts").Key == "rift" && how.ForGoal("tower10") != null && how.ForGoal("tower10").Key == "tower" && how.ForGoal("zzz") == null, "how: by unlock and by goal");
            check(how.ForWindow("game_infinitytower") != null && how.ForWindow("game_infinitytower").Key == "tower", "how: by the main client's module name");
            check(HowItWorks.UnityWindows.All(kv => how.Find(kv.Value) != null), "how: every Unity window of the table has its card");
            check(HowItWorks.IsPt("pt-BR") && HowItWorks.IsPt("pt") && !HowItWorks.IsPt("en") && !HowItWorks.IsPt(null), "how: language choice");
            var rows = HowItWorks.RowsOf(tower, "en");
            check(rows.Count == 5 && rows[0].Key == "who" && rows[4].Key == "often" && rows[0].Value.StartsWith("Level 100+"), "how: rows in order, the ones the card has");
            check(HowItWorks.RowsOf(tower, "pt-BR")[0].Value.StartsWith("Nível 100+") && HowItWorks.Title(how.Find("rift"), "pt-BR") == "Fendas" && HowItWorks.Title(how.Find("rift"), "en") == "Rifts", "how: pt-BR texts");
            check(HowItWorks.Heading("death") == "If you die" && HowItWorks.Heading("often") == "How often", "how: headings");
            check(HowItWorks.CharKey("Ana Maria") == "Ana_Maria" && HowItWorks.CharKey("") == "_", "how: character key");
            var seen = new Dictionary<string, HashSet<string>>();
            check(HowItWorks.FirstOpen(seen, "ana", "tower") && !HowItWorks.FirstOpen(seen, "ana", "tower") && HowItWorks.FirstOpen(seen, "ana", "rift") && HowItWorks.FirstOpen(seen, "bob", "tower") && !HowItWorks.FirstOpen(seen, "ana", null), "how: first open once per character and card");
        }

        // ------------------------------------------------------------------------------------ helpcore_test.lua
        static List<string> Top(HelpIndex ix, string q, int n = 5)
        {
            List<string> words;
            return HelpSearch.Search(ix, q, out words, n).Select(r => r.Doc.Kind + ":" + r.Doc.Key).ToList();
        }

        static void HelpTests(Action<bool, string> check)
        {
            check(HelpSearch.Fold("Nível") == "nivel" && HelpSearch.Fold("Nível") == "nivel" && HelpSearch.Fold("Masmorras, Facções!") == "masmorras, faccoes!" && HelpSearch.Fold("\u2014x") == " x", "help: folding");
            var t = HelpSearch.Tokens("How do I get Orbs?");
            check(t.Count == 1 && t[0] == "orb" && HelpSearch.Tokens("como subir de nível")[0] == "subir", "help: small words out, plural cut");
            check(HelpSearch.Stem("niveis") == "nivel" && HelpSearch.Stem("faccoes") == "faccao" && HelpSearch.Stem("itens") == "item" && HelpSearch.Stem("bounties") == "bounty" && HelpSearch.Stem("boss") == "boss", "help: stems");
            check(HelpSearch.Expand("orbe")["orb"] == HelpSearch.WSynonym && HelpSearch.Expand("masmorra")["dungeon"] == HelpSearch.WSynonym && HelpSearch.Expand("orb")["orb"] == 1, "help: synonyms");

            var how = HowItWorks.Load(Resource("HowItWorks.json"));
            var codex = CodexData.Load(Resource("Codex.json"));
            var help = Json.TryParse(Resource("HelpSearch.json"));
            var ix = HelpSearch.Build(how, help, codex);
            int cards = ix.Docs.Count(d => d.Kind == "card"), cx = ix.Docs.Count(d => d.Kind == "codex");
            check(cards == how.Cards.Count && cx > 100, "help: every card and the Codex entries are in the index (" + cards + ", " + cx + ")");
            check(ix.Cards["bounty"].Menu == "Adventure > Bounty Board" && ix.Cards["rift"].Level == 100, "help: a card knows its menu path and its level");
            var r = Top(ix, "how do I get orbs");
            check(r.Count > 0 && r[0].StartsWith("card:") && Top(ix, "how do I get orbs", 8).Contains("card:bounty"), "help: orbs: a card first, the Bounty Board pays orbs (" + string.Join(",", r) + ")");
            check(Top(ix, "gems").Contains("card:crafting") && Top(ix, "gems", 8).Contains("codex:gem:sockets") && Top(ix, "gemas", 8).Contains("codex:gem:sockets"), "help: gems and gemas");
            check(Top(ix, "como subir de nivel")[0] == "card:goals" && Top(ix, "como subir de nível")[0] == "card:goals", "help: como subir de nivel, with and without the accent");
            check(Top(ix, "masmorras")[0] == "card:dungeons" && Top(ix, "dungeons")[0] == "card:dungeons" && Top(ix, "fendas")[0] == "card:rift" && Top(ix, "pets")[0] == "card:pets", "help: titles in both languages");
            check(Top(ix, "onde guardar itens")[0] == "card:stash" && Top(ix, "orb of fate")[0] == "codex:orb:divine" && Top(ix, "torre infinita")[0] == "card:tower", "help: stash, the Codex page by title, the tower by synonym");
            check(Top(ix, "what happens if I die")[0].StartsWith("card:"), "help: if I die: a card with a death row");
            List<string> words;
            check(HelpSearch.Search(ix, "how do I", out words).Count == 0 && HelpSearch.Search(ix, "zzzzqx", out words).Count == 0 && HelpSearch.Search(ix, "rift", out words, 3).Count == 3, "help: only small words, an unknown word, the limit");
            var full = HelpSearch.Search(ix, "guild", out words);
            check(full[0].Doc.Key == "guild" && full[0].Score > full[full.Count - 1].Score, "help: the Guild card first, sorted by score");
            check(HelpSearch.IsSource("como conseguir orbes") && HelpSearch.IsSource("how do I get gems") && !HelpSearch.IsSource("gems"), "help: source questions");
            string s = HelpSearch.SnippetOf(ix.Cards["arena"], HelpSearch.Tokens("if I die"), "en");
            check(s.Contains("death"), "help: the snippet is the row that answers: " + s);
            s = HelpSearch.SnippetOf(ix.Cards["arena"], HelpSearch.Tokens("morrer"), "pt-BR");
            check(s.Contains("morte"), "help: pt snippet: " + s);
            check(HelpSearch.SnippetOf(ix.Cards["tower"], new string[0], "en").Length <= HelpSearch.Snippet, "help: snippet length");
            check(HelpSearch.Shorten("one two three four", 12) == "one two..." && HelpSearch.Shorten("short", 12) == "short", "help: cut at a space");
            check(ix.Steps.Count > 5 && ix.Steps[0].Doc.Key == Json.Text(Json.List(help, "steps")[0], "card") && ix.Steps[0].Tip.Pt.Length > 0 && ix.Steps[0].Tip.En.Length > 0 && ix.Intro.En.Length > 0, "help: the first steps in order, in both languages");
            var own = HelpSearch.Build(how, J("{\"cards\":{},\"unlocks\":[{\"key\":\"x\",\"level\":40,\"menu\":\"Xylo Menu\",\"title\":{\"en\":\"Xylophone\",\"pt\":\"Xilofone\"},\"why\":{\"en\":\"Play music.\",\"pt\":\"Toque musica.\"}}]}"), null);
            var u = HelpSearch.Search(own, "xilofone", out words);
            check(u.Count > 0 && u[0].Doc.Kind == "unlock" && u[0].Doc.Level == 40, "help: an unlock entry without a card is its own result");
        }

        // ------------------------------------------------------------------------------------ codexview_test.lua
        static void CodexTests(Action<bool, string> check)
        {
            var d = CodexData.Load(Resource("Codex.json"));
            check(d.Ready && d.Tabs.Count == 11 && d.EntryCount > 400 && d.Rarities.Count == 6 && d.TierLevels.Length == 8 && d.TierWindow == 8, "codex: the data loads (" + d.Tabs.Count + " tabs, " + d.EntryCount + " entries)");
            check(d.Tabs.Select(t => t.Id).SequenceEqual(new[] { "modifiers", "powers", "orbs", "gems", "uniques", "sets", "rift", "supports", "materials", "basics", "lore" }), "codex: the tabs in order");
            check(CodexView.Tokens("  Life  on KILL ").SequenceEqual(new[] { "life", "on", "kill" }) && CodexView.Tokens(null).Count == 0, "codex: tokens");
            check(CodexView.HasWord("life on kill", "kill") && !CodexView.HasWord("skill", "kill") && CodexView.HasWord("adds +5% life", "+5") && CodexView.HasWord("level 1-3 only", "1-3") && CodexView.HasWord("a kill", "ki"), "codex: a search word starts a word of the text");
            var mods = d.Tabs[0];
            var all = CodexView.List(mods, "", null, d);
            check(all.Count == mods.Entries.Count, "codex: no query, no filter: every entry");
            var life = CodexView.List(mods, "life kill", null, d);
            check(life.Count > 0 && life.Count < all.Count && life.All(e => CodexView.SearchText(e, d).Contains("life")), "codex: every word must be found (" + life.Count + ")");
            var vals = new Dictionary<string, string> { { "side", "prefix" } };
            var prefixes = CodexView.List(mods, "", vals, d);
            check(prefixes.Count > 0 && prefixes.Count < all.Count && prefixes.All(e => (e.F["side"] as string) == "prefix"), "codex: the side filter (eq)");
            var kindFilter = mods.Filters.FirstOrDefault(f => f.Match == "has");
            check(kindFilter != null && CodexView.List(mods, "", new Dictionary<string, string> { { kindFilter.Key, "weapon" } }, d).Count > 0, "codex: a has filter holds a list");
            var ilvl = mods.Filters.FirstOrDefault(f => f.Match == "ilvl");
            check(ilvl != null && CodexView.List(mods, "", new Dictionary<string, string> { { ilvl.Key, "100" } }, d).Count == all.Count, "codex: the item level filter changes only what the list shows");
            check(CodexView.LevelOf(new Dictionary<string, string> { { ilvl.Key, "100" } }, mods.Filters) == 100 && CodexView.LevelOf(null, mods.Filters) == null, "codex: the chosen item level");
            check(CodexView.MaxTier(1, d) == 1 && CodexView.MaxTier(14, d) == 1 && CodexView.MaxTier(15, d) == 2 && CodexView.MaxTier(140, d) == 8 && CodexView.MaxTier(1000, d) == 8, "codex: the top tier of an item level");
            var rowsAt140 = CodexView.TierRows(140, d);
            // O461: every tier the item level allows rolls (no window of five); O471: tier t weighs 1.35^(t-1), T8 816 of 2864
            check(rowsAt140.Count == 8 && rowsAt140[0].Key == 8 && rowsAt140[7].Key == 1 && CodexView.TierRows(60, d).Count == 4 && CodexView.TierRows(1, d).Count == 1, "codex: the tiers that roll, best first, every tier the item level allows");
            var ch = CodexView.TierChances(140, d);
            double sum = 0;
            foreach (var v in ch.Values) sum += v;
            check(Math.Abs(sum - 100) < 0.6 && ch[8] == 28.5 && ch[1] == 3.5 && ch[4] == 8.6, "codex: the chances add up to 100, tilted toward the top tier (" + sum + ")");
            var entry = mods.Entries.First(e => e.Tv != null);
            check(CodexView.Subline(entry, null, d) == entry.Sub && CodexView.Subline(entry, 140, d).StartsWith("Item level 140: T1-T8: "), "codex: the list line at an item level");
            var tiers = entry.Sections.Select(s => CodexView.Section(s, d)).First(s => s != null && s.Tiers);
            var marked = CodexView.Highlight(tiers, 140, d);
            var marked60 = CodexView.Highlight(tiers, 60, d);
            check(marked.Count == 8 && marked.Contains(8) && marked.Contains(1) && marked60.Count == 4 && marked60.Contains(4) && !marked60.Contains(5) && CodexView.Highlight(tiers, null, d).Count == 0, "codex: the tier rows that roll are marked");
            var withRef = mods.Entries.First(e => e.Sections.Any(s => s.Ref.Length > 0));
            var refSection = withRef.Sections.First(s => s.Ref.Length > 0);
            check(CodexView.Section(refSection, d) != null && CodexView.Section(refSection, d).Rows != null && CodexView.Section(new CodexSection { Ref = "nope" }, d) == null, "codex: a shared section is looked up");
            int ti;
            check(CodexView.Find(d, "orb:divine", out ti) != null && d.Tabs[ti].Id == "orbs" && CodexView.Find(d, "nope", out ti) == null && ti == -1, "codex: find an entry by id");
            check(CodexView.IdForMod("rarity_swordSkill", "", d) == "mod:rarity_swordskill" && CodexView.IdForMod("nope", "", d) == null && CodexView.IdForMod("", "", d) == null, "codex: the page of a modifier the bench names");
            var cols = CodexView.Columns(new double[] { 14, 22, 40, 24 }, 408, 8);
            check(cols.Length == 4 && cols.Sum() == 408 - 24 && cols.All(c => c >= 1), "codex: column widths add up to the total minus the gaps");
            check(CodexView.Columns(new double[0], 100, 8).Length == 0 && CodexView.Columns(new double[] { 0, 0 }, 100, 0).Sum() == 100, "codex: columns of nothing and of zero weights");
            check(d.Tabs.SelectMany(t => t.Entries).Select(e => e.Id).Distinct().Count() == d.EntryCount, "codex: every entry id is unique");
        }

        // ------------------------------------------------------------------------------------ catalogcore_test.lua
        static void Proficiency(Action<bool, string> check)
        {
            var items = new Dictionary<int, ProficiencyInfo>
            {
                { 100, new ProficiencyInfo { Category = 20, Name = "Steel Blade" } },
                { 101, new ProficiencyInfo { Category = 6, Name = "Cheese" } },
                { 102, new ProficiencyInfo { TypeCategory = 17, Name = "Ember Axe" } },
                { 103, new ProficiencyInfo { Category = 21, Name = "" } },
                { 104, new ProficiencyInfo { Category = 19, Name = "Hunter Bow" } },
                { 105, new ProficiencyInfo { Name = "Odd" } },
                { 106, new ProficiencyInfo { Category = 27, Name = "Iron Knuckles" } },
                { 107, new ProficiencyInfo { TypeCategory = 21, Name = "Spark Wand" } },
            };
            int seen;
            var list = ProficiencyCatalog.Collect(id => { ProficiencyInfo i; return items.TryGetValue(id, out i) ? i : null; }, 99, 110, out seen);
            check(seen == 8 && list.Count == 5, "proficiency: five weapons of eight items");
            check(list[0].Id == 100 && list[0].Category == 20 && list[0].Name == "Steel Blade" && list[1].Id == 102 && list[1].Category == 17 && list[2].Category == 19 && list[3].Category == 27 && list[4].Category == 21, "proficiency: in id order with the category");
            check(ProficiencyCatalog.Collect(id => null, 1, 5, out seen).Count == 0 && seen == 0, "proficiency: nothing known");
            check(ProficiencyCatalog.Filter(list, 19, "").Count == 1 && ProficiencyCatalog.Filter(list, -1, "ember").Count == 1 && ProficiencyCatalog.Filter(list, -1, "").Select(w => w.Name).SequenceEqual(new[] { "Ember Axe", "Hunter Bow", "Iron Knuckles", "Spark Wand", "Steel Blade" }), "proficiency: filter by category and name");
            var dat = DatFile.Parse(Program.SyntheticDat());
            check(ProficiencyCatalog.FromDat(dat, out seen).Count == 0, "proficiency: the synthetic dat has no weapon");
            check(dat.Item(101).MarketName == "coin", "proficiency: the dat keeps the market name");
        }
    }
}
