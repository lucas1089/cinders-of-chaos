// Phase 6 track W (P1 systems): passive tree totals, skill tooltips, picking an item up from its ground label, loot filter peek, rule counters
// and sounds, item tooltip Alt help, Ctrl compare and source lines, stash Find my item and the never-stash list, store gift, rotation countdown
// and try on, the damage scatter options.
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Chaos.Core.Tests
{
    static class Phase6WTests
    {
        static object J(string json) => Json.TryParse(json);

        public static void Run(Action<bool, string> check)
        {
            Loc.Set("en");
            TreeTotalsChecks(check);
            SkillTipChecks(check);
            GroundPickChecks(check);
            PeekChecks(check);
            RulesChecks(check);
            TipChecks(check);
            StashChecks(check);
            StoreChecks(check);
            ScatterChecks(check);
            Loc.Set("en");
        }

        static void TreeTotalsChecks(Action<bool, string> check)
        {
            var t = TreeTotals.Parse(J("{\"attributes\":[{\"k\":\"str\",\"n\":\"Strength\",\"raw\":280,\"eff\":221.7,\"cap\":200},{\"k\":\"dex\",\"n\":\"Dexterity\",\"raw\":50,\"eff\":50,\"cap\":200}],"
                + "\"damage\":[{\"k\":\"fire\",\"n\":\"Fire\",\"raw\":30,\"eff\":30,\"cap\":100}],\"crit\":{\"chance\":{\"total\":12.5,\"tree\":5,\"other\":7.5},\"amount\":{\"total\":60,\"tree\":20,\"paragon\":10,\"other\":30}},"
                + "\"attackSpeed\":{\"total\":15,\"tree\":10,\"gear\":5}}"));
            check(t.Lines.Count == 6, "tree totals: two attributes, one damage row, two crit lines and the attack speed");
            check(t.Lines[0].Kind == 'o' && t.Lines[0].Text == "Strength: 280 points -> 221.7 effective (full value up to 200)", "tree totals: an attribute over its cap shows raw and effective: " + t.Lines[0].Text);
            check(t.Lines[1].Kind == 't' && t.Lines[1].Text == "Dexterity: 50 points (full value up to 200)", "tree totals: an attribute under its cap shows the cap");
            check(t.Lines[2].Text == "Fire: +30% (full value up to +100%)", "tree totals: a damage row");
            check(t.Lines[3].Kind == 'h' && t.Lines[3].Text == "Critical chance: 12.5% (tree 5%, gear and other 7.5%)", "tree totals: critical chance");
            check(t.Lines[4].Text == "Critical damage: +60% (tree 20%, Paragon 10%, gear and other 30%)", "tree totals: critical damage");
            check(t.Lines[5].Text.StartsWith("Attack speed: +15% (tree 10%, gear 5%"), "tree totals: attack speed");
            check(TreeTotals.Parse(null).Lines.Count == 0 && TreeTotals.Parse(J("{}")).Lines.Count == 0, "tree totals: nothing from an empty answer");

            var ext = new ExtOpcodes();
            var sent = new List<string>(); ext.Transmit = p => sent.Add(Encoding.UTF8.GetString(p, 4, p.Length - 4));
            var tree = new PassiveTree(ext);
            check(tree.TotalsStale, "tree totals: stale before the first request");
            tree.RequestTotals();
            check(!tree.TotalsStale && sent.Count == 1 && sent[0].Contains("statTotals"), "tree totals: the request is statTotals");
            ext.Receive(65, "{\"action\":\"statTotals\",\"data\":{\"attributes\":[{\"k\":\"a\",\"n\":\"A\",\"raw\":1,\"eff\":1,\"cap\":2}]}}");
            check(tree.Totals != null && tree.Totals.Lines.Count == 1, "tree totals: the answer is kept");
            ext.Receive(65, "{\"action\":\"sendNodes\",\"data\":{\"nodes\":[1],\"masteries\":[],\"preset\":1,\"presetsTable\":[]}}");
            check(tree.TotalsStale, "tree totals: a new allocation makes them stale");
        }

        static void SkillTipChecks(Action<bool, string> check)
        {
            check(SkillStats.BarTip("Melee", 42, 17) == "Melee: 42\n17% to the next level", "skills: the bar tooltip");
            check(SkillStats.MeleeTip().Contains("share one skill"), "skills: the Melee row tooltip");
            check(SkillStats.Boosted(new SkillValue { Level = 12, Base = 10 }) && !SkillStats.Boosted(new SkillValue { Level = 10, Base = 10 }), "skills: boosted above the base level");
        }

        static void GroundPickChecks(Action<bool, string> check)
        {
            var w = new World(DatFile.Parse(Program.SyntheticDat()));
            var center = new Pos(100, 100, 7);
            w.Center = center;
            var sword = new ThingType { Pickupable = true };
            var floor = new ThingType { Ground = true };
            Action<Pos, ThingType, int, int> put = (p, ty, id, count) => w.GetOrMake(p).Things.Add(new Thing { Item = new Item { Id = id, Count = count, Type = ty } });
            var spot = center.Offset(1, 0);
            put(spot, floor, 100, 0); put(spot, sword, 3264, 1); put(spot, sword, 3265, 1);
            var ext = new ExtOpcodes();
            var sent = new List<string>(); ext.Transmit = p => sent.Add(Encoding.UTF8.GetString(p, 4, p.Length - 4));
            double now = 0;
            var gm = new GroundLabelsModel(ext) { Clock = () => now };
            var moves = new List<string>(); var notes = new List<string>();
            bool backpack = true;
            gm.MoveToBackpack = (from, id, stack, count) => moves.Add(from.X + "," + from.Y + ":" + id + ":" + stack + ":" + count);
            gm.Notice = t => notes.Add(t);
            gm.HasBackpack = () => backpack;
            gm.Scan(w, center);
            var tile = w.Get(spot);
            int stack;
            var top = GroundPick.Find(tile, new GroundRow { Info = new LootInfo { Id = 3264, C = 1, S = 1 } }, out stack);
            check(top != null && stack == 1 && GroundPick.TopStack(tile) == 1, "ground pick: the top item of the pile is stack 1");
            var low = GroundPick.Find(tile, new GroundRow { Info = new LootInfo { Id = 3265, C = 1, S = 2 } }, out stack);
            check(low != null && stack == 2, "ground pick: the lower item is found by its id");
            check(GroundPick.Find(tile, new GroundRow { Info = new LootInfo { Id = 9999, C = 1, S = 1 } }, out stack) == null, "ground pick: an item that is gone is not found");

            gm.Activate(spot, new GroundRow { Info = new LootInfo { Id = 3264, C = 1, S = 1 } });
            check(moves.Count == 1 && moves[0] == "101,100:3264:1:1", "ground pick: the top item moves at once: " + string.Join("|", moves));
            moves.Clear(); sent.Clear();
            var lowRow = new GroundRow { Info = new LootInfo { Id = 3265, C = 1, S = 2 } };
            gm.Activate(spot, lowRow);
            check(moves.Count == 0 && sent.Count == 1 && sent[0].Contains("\"raise\"") && sent[0].Contains("[101,100,7]") && sent[0].Contains("3265"), "ground pick: a lower item is raised by the server first: " + string.Join("|", sent));
            ext.Receive(230, "{\"action\":\"raised\",\"data\":{\"p\":[101,100,7],\"id\":3265,\"err\":\"far\"}}");
            check(notes.Count == 1 && notes[0] == "That item is too far away." && moves.Count == 0, "ground pick: a raise error is told");
            gm.Activate(spot, lowRow);
            // the server put it on top: swap the two things
            var things = tile.Things;
            var t1 = things[1]; things[1] = things[2]; things[2] = t1;
            ext.Receive(230, "{\"action\":\"raised\",\"data\":{\"p\":[101,100,7],\"id\":3265}}");
            check(moves.Count == 1 && moves[0] == "101,100:3265:1:1", "ground pick: once raised, the item is moved into the backpack");
            moves.Clear(); notes.Clear();
            gm.Activate(spot, new GroundRow { Info = new LootInfo { Id = 9999, C = 1, S = 1 } });
            check(notes.Count == 1 && notes[0] == "That item is gone." && moves.Count == 0, "ground pick: an item that left the tile is told gone");
            backpack = false; notes.Clear();
            gm.Activate(spot, new GroundRow { Info = new LootInfo { Id = 3264, C = 1, S = 2 } });
            check(notes.Count == 1 && notes[0].Contains("no backpack") && moves.Count == 0, "ground pick: no backpack, no move");
            check(GroundPick.ErrorText("sight") == "You cannot reach that item from here." && GroundPick.ErrorText("fixed") == "You cannot pick that up.", "ground pick: the raise error texts");
        }

        static void PeekChecks(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var sent = new List<string>(); ext.Transmit = p => sent.Add(Encoding.UTF8.GetString(p, 4, p.Length - 4));
            var lf = new LootFilterModel(ext);
            lf.RequestPeek(3);
            check(sent.Count == 1 && sent[0].Contains("\"peek\"") && sent[0].Contains("\"cid\":3"), "peek: the request names the container");
            ext.Receive(238, "{\"action\":\"peek\",\"data\":{\"cid\":3,\"corpse\":true,\"items\":[{\"i\":0,\"id\":3264,\"c\":1,\"r\":4,\"g\":\"equipment\"},{\"i\":2,\"id\":3031,\"c\":40,\"g\":\"currency\"}]}}");
            var set = lf.PeekOf(3);
            check(set != null && set.Corpse && set.Items.Count == 2 && set.Items[0].Id == 3264 && set.Items[2].C == 40, "peek: the rows are kept by slot index");
            var s = new LootFilterSettings { Highlight = 4 };
            var d = LootPeek.Decorate(set.Items[0], true, s);
            check(d.State == "highlight" && d.Glow && !d.Soft && d.Color == "#a35cf0", "peek: a Rare item glows in the rarity colour");
            var coin = LootPeek.Decorate(set.Items[2], true, new LootFilterSettings { Highlight = 4, Dim = 0 });
            check(coin.State == "normal" && !coin.Glow && !coin.Dim, "peek: a plain item stays as it is");
            var dimmed = LootPeek.Decorate(new LootInfo { G = "equipment", R = 1 }, true, new LootFilterSettings { Dim = 2 });
            check(dimmed.Dim, "peek: a dimmed item of a corpse is veiled");
            check(!LootPeek.Decorate(new LootInfo { G = "equipment", R = 1 }, false, new LootFilterSettings { Dim = 2 }).Dim, "peek: a bag does not veil");
            check(LootPeek.Decorate(new LootInfo { O = true, G = "currency" }, true, s).Soft, "peek: an orb glows as a thin ring");
            var item = new Item { Id = 3264, Count = 1 };
            check(LootPeek.RowFits(set.Items[0], item, true, false), "peek: the same client id fits");
            check(!LootPeek.RowFits(set.Items[0], new Item { Id = 3265 }, true, false) && !LootPeek.RowFits(set.Items[0], null, true, false) && !LootPeek.RowFits(set.Items[0], item, false, false), "peek: another id, no item or no row does not fit");
            var attr = new Item { Id = 3264, Count = 1, Attrs = new Dictionary<ushort, ulong> { { ItemAttr.Rarity, 1 } } };
            check(!LootPeek.RowFits(set.Items[0], attr, true, true) && LootPeek.RowFits(set.Items[0], attr, true, false), "peek: with item attributes a row of another rarity belongs to another item");
            var c = new Container { Id = 3, ItemId = 2853, FirstIndex = 0 };
            c.Items.Add(new Item { Id = 1, Count = 2 });
            string sig = LootPeek.Signature(c);
            c.Items.Add(new Item { Id = 5, Count = 1 });
            check(sig != LootPeek.Signature(c), "peek: the signature changes with the contents");
            lf.ForgetPeek(3);
            check(lf.PeekOf(3) == null, "peek: a closed container is forgotten");
        }

        static void RulesChecks(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var sent = new List<string>(); ext.Transmit = p => sent.Add(Encoding.UTF8.GetString(p, 4, p.Length - 4));
            var lf = new LootFilterModel(ext);
            ext.Receive(238, "{\"action\":\"settings\",\"data\":{\"s\":{},\"unlocked\":true,\"snd\":{\"rules\":{\"unique\":3,\"power\":9,\"orb\":2},\"vol\":55,\"mute\":true,\"hunt\":false},\"counts\":{\"session\":{\"unique\":2,\"orb\":7},\"total\":{\"unique\":10}}}}");
            check(lf.Sound.Rules["unique"] == 3 && lf.Sound.Rules["power"] == 0 && lf.Sound.Rules["orb"] == 2 && lf.Sound.Rules["rarity"] == 0, "rules: a sound id out of range is 0, a missing one stays at 0");
            check(lf.Sound.Volume == 55 && lf.Sound.Mute && !lf.Sound.Hunt, "rules: volume, mute and the tracker flag");
            check(lf.CountSession["unique"] == 2 && lf.CountSession["orb"] == 7 && lf.CountTotal["unique"] == 10 && lf.CountTotal["tier"] == 0, "rules: the counters of the settings message");
            ext.Receive(238, "{\"action\":\"kill\",\"data\":{\"k\":1,\"m\":\"Rat\",\"items\":[],\"hits\":{\"unique\":1},\"counts\":{\"session\":{\"unique\":3},\"total\":{\"unique\":11}}}}");
            check(lf.CountSession["unique"] == 3 && lf.LastHits["unique"] == 1, "rules: a kill carries the new counters and its hits");
            ext.Receive(238, "{\"action\":\"counts\",\"data\":{\"session\":{},\"total\":{\"power\":4}}}");
            check(lf.CountSession["unique"] == 0 && lf.CountTotal["power"] == 4, "rules: a counts message replaces both");
            var snd = lf.Sound.Copy();
            snd.Volume = 80; snd.Rules["tier"] = 4;
            check(!snd.Same(lf.Sound), "rules: an edited copy differs");
            lf.SetSound(snd);
            check(sent.Count == 1 && sent[0].Contains("\"sound\"") && sent[0].Contains("\"vol\":80") && sent[0].Contains("\"tier\":4") && lf.Sound.Volume == 80, "rules: the sound settings are sent back whole");
            sent.Clear();
            lf.ResetCounts("all", "orb"); lf.ResetCounts("session");
            check(sent.Count == 2 && sent[0].Contains("\"scope\":\"all\"") && sent[0].Contains("\"rule\":\"orb\"") && sent[1].Contains("\"scope\":\"session\"") && !sent[1].Contains("rule"), "rules: reset by rule and by scope");
            check(LootRules.Number(1234567) == "1,234,567" && LootRules.SoundName(0) == "No sound" && LootRules.SoundName(5) == "Fanfare", "rules: number and sound names");
            var rows = LootPreview.Build(new LootFilterSettings { Highlight = 4, Tier = 3 });
            check(rows.Count == 13 && rows[0].Text == "Gear without rarity: shown", "preview: gear without rarity, the six rarity rows, the tier row, a unique, an orb and three plain: " + rows.Count);
            check(rows.Any(r => r.Text == "Rare gear: glows") && rows.Any(r => r.Text == "A unique: glows") && rows.Any(r => r.Text == "Common gear with a T3 modifier: glows"), "preview: the thresholds decide what glows");
            var defaults = LootSoundSettings.Normalize(null);
            check(defaults.Rules["unique"] == 5 && defaults.Rules["power"] == 1 && defaults.Volume == 70 && defaults.Hunt && !defaults.Mute, "rules: the sound defaults");
        }

        static void TipChecks(Action<bool, string> check)
        {
            var tip = J("{\"name\":\"Fire Sword\",\"kind\":\"weapon\",\"cmp\":[6],\"level\":50,\"rarityName\":\"Rare\",\"quality\":{\"q\":5},"
                + "\"base\":[{\"k\":\"attack\",\"l\":\"Attack\",\"v\":40}],\"mods\":[{\"k\":\"chaos_mod_dodge\",\"sd\":\"p\",\"tr\":5,\"lo\":1,\"hi\":3},{\"k\":\"zzz\",\"g\":\"element\",\"sd\":\"s\",\"tr\":3,\"bd\":true}],"
                + "\"sockets\":{\"count\":2},\"stats\":[{\"k\":\"attack\",\"l\":\"Attack\",\"v\":40,\"fmt\":\"n\"},{\"k\":\"armor\",\"l\":\"Armour\",\"v\":2}]}");
            var help = ItemHelp.Lines(tip);
            check(help.Count > 8 && help[0] == "Rare: the rarity. Rarer items roll more modifiers.", "help: the first line names the rarity: " + (help.Count > 0 ? help[0] : ""));
            check(help.Contains("Item Level: a higher item level can roll higher tiers.") && help.Contains("Quality: makes the base stats stronger."), "help: item level and quality");
            check(help.Contains("Attack: the base damage of the weapon."), "help: a base stat");
            check(help.Contains("T5: the tier, T1 weak to T8 best.") && help.Contains("[low-high]: the range this modifier can roll in.") && help.Contains("Bound: orbs do not change this modifier."), "help: the best tier, the range and bound");
            check(help.Contains("Dodge: a chance that a hit misses you.") && help.Contains("Element damage: adds damage of that element to your hits."), "help: a modifier by key and by group");
            check(help.Contains("Sockets: put gems in them for extra bonuses.") && help.Count == help.Distinct().Count(), "help: sockets and no repeats");
            check(ItemHelp.Lines(J("{\"unique\":{\"set\":true}}")).Contains("Set: wear more pieces of the set for extra bonuses.") && ItemHelp.Lines(J("{\"unique\":{}}")).Contains("Unique: a named item with fixed modifiers, often with a power of its own."), "help: sets and uniques");
            check(ItemHelp.Key("CHAOS_MOD_Dodge") == "dodge", "help: the modifier key loses its prefix");

            // compare
            check(ItemCompare.Comparable(tip) && !ItemCompare.Comparable(J("{\"kind\":\"rune\",\"stats\":[{\"k\":\"a\",\"v\":1}]}")), "compare: only gear with slots and numbers");
            var worn = J("{\"name\":\"Old Sword\",\"kind\":\"weapon\",\"stats\":[{\"k\":\"attack\",\"l\":\"Attack\",\"v\":35},{\"k\":\"dodge\",\"l\":\"Dodge\",\"v\":4,\"fmt\":\"pct\"}]}");
            var diff = ItemCompare.Diff(tip, worn);
            check(diff.Count == 3 && diff[0].Key == "attack" && diff[0].D == 5 && diff[0].Better && diff[1].Key == "armor" && diff[1].D == 2 && diff[2].Key == "dodge" && diff[2].D == -4 && !diff[2].Better, "compare: hovered minus worn, then what only the worn one has");
            check(ItemCompare.DiffText(diff[0]) == "+5 Attack" && ItemCompare.DiffText(diff[2]) == "-4% Dodge", "compare: the difference text: " + ItemCompare.DiffText(diff[2]));
            var lowRow = ItemCompare.Diff(J("{\"stats\":[{\"k\":\"cost\",\"l\":\"Cost\",\"v\":5,\"low\":true}]}"), J("{\"stats\":[{\"k\":\"cost\",\"l\":\"Cost\",\"v\":8,\"low\":true}]}"));
            check(lowRow.Count == 1 && lowRow[0].D == -3 && lowRow[0].Better, "compare: a lower-is-better row that falls is better");
            var scaled = ItemCompare.Diff(J("{\"ds\":2,\"stats\":[{\"k\":\"hp\",\"l\":\"Health\",\"v\":200,\"sc\":true}]}"), J("{\"ds\":1,\"stats\":[{\"k\":\"hp\",\"l\":\"Health\",\"v\":50,\"sc\":true}]}"));
            check(scaled.Count == 1 && scaled[0].D == 100, "compare: a scaled row of the worn item is brought to the hovered item's scale");
            var bySlot = new Dictionary<int, object> { { 6, worn }, { 9, J("{\"kind\":\"shield\"}") } };
            var tipTwo = J("{\"kind\":\"weapon\",\"cmp\":[6,9],\"stats\":[{\"k\":\"a\",\"v\":1}]}");
            check(ItemCompare.CompareWith(tipTwo, bySlot, null, null).Count == 1, "compare: a weapon is not compared with a shield");
            check(ItemCompare.CompareWith(tipTwo, bySlot, "me", new Dictionary<int, string> { { 6, "me" } }).Count == 0, "compare: never the hovered item itself");
            var plain = ItemCompare.ExtraRows(tip, false, false, new List<object>(), false);
            check(plain.Count == 2 && plain[0].Text == "Hold Ctrl to compare" && plain[1].Text == "Hold Alt for what each line does." && !plain[1].Sep, "extra rows: the two hints");
            var withCtrl = ItemCompare.ExtraRows(tip, true, false, new List<object> { worn }, false);
            check(withCtrl[0].Text == "Compared with Old Sword" && withCtrl.Any(r => r.Text == "+5 Attack" && r.Color == ItemCompare.BetterColor) && withCtrl.Any(r => r.Text == "-4% Dodge" && r.Color == ItemCompare.WorseColor), "extra rows: Ctrl lists the differences in green and red");
            check(ItemCompare.ExtraRows(tip, true, false, new List<object>(), false).Any(r => r.Text == "Nothing equipped to compare") && !ItemCompare.ExtraRows(tip, true, false, new List<object>(), true).Any(r => r.Text == "Nothing equipped to compare"), "extra rows: nothing equipped, unless an answer is on its way");
            var alt = ItemCompare.ExtraRows(tip, false, true, new List<object>(), false);
            check(alt.Count > 5 && alt.Any(r => r.Color == ItemCompare.HelpColor) && !alt.Any(r => r.Text == "Hold Alt for what each line does."), "extra rows: Alt lists the help lines");

            // source lines
            var src = TipLines.SourceLines(J("{\"s\":[{\"k\":\"monster\",\"n\":\"Abyssal Crab\",\"v\":\"2%\"},{\"k\":\"monster\",\"n\":\"Abyssal Crab\"},{\"k\":\"monster\",\"n\":\"Rat\"}],\"e\":{\"p\":0.01},\"t\":250,\"u\":{\"n\":[\"Emblem\"],\"m\":3}}"));
            check(src.Count == 3 && src[0].Text == "Drops from: Abyssal Crab (2%), Rat" && src[0].Color == TipLines.Dim, "sources: one entry per name, as a drop line: " + (src.Count > 0 ? src[0].Text : ""));
            check(src[1].Text == "~1 in 100 kills, or 250 Conquest Tokens" && src[1].Color == TipLines.Gold, "sources: the effort and the token price: " + src[1].Text);
            check(src[2].Text == "Used in: Emblem +3 more", "sources: what a material is for");
            check(TipLines.OneIn(0.0005) == 2000 && TipLines.OneIn(0.4) == 3 && TipLines.OneIn(0.9) == 1 && TipLines.OneIn(0) == 0, "sources: one in n, rounded as a player reads it");
            check(TipLines.SourceLines(null).Count == 0 && TipLines.SourceLines(J("{\"t\":10}")).Single().Text == "Conquest vendor: 10 tokens", "sources: nothing without a block, a vendor price alone");
            var full = TipLines.Lines(J("{\"name\":\"Gem\",\"weight\":1.5,\"src\":{\"s\":[{\"k\":\"drop\",\"n\":\"Wolf\"}]}}"), 100);
            check(full.Count == 2 && full[0].Text == "Drops from: Wolf" && full[0].Sep && full[1].Text == "Weight 1.5 oz" && !full[1].Sep, "sources: they sit above the weight in the tooltip lines");
        }

        static void StashChecks(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var sent = new List<string>(); ext.Transmit = p => sent.Add(Encoding.UTF8.GetString(p, 4, p.Length - 4));
            var st = new StashState(ext);
            ext.Receive(110, "{\"action\":\"Stash\",\"data\":{\"make\":\"forceBlockList\",\"items\":[{\"sprite\":2160,\"name\":\"crystal coin\",\"id\":2160}]}}");
            check(st.Blocks.Count == 1 && st.Blocks[0].Sprite == 2160 && st.Blocks[0].Id == 2160, "never stash: the snapshot fills the list");
            ext.Receive(110, "{\"action\":\"Stash\",\"data\":{\"make\":\"addBlockItem\",\"status\":true,\"itemData\":{\"sprite\":5,\"name\":\"sword\",\"id\":3264}}}");
            check(st.Blocks.Count == 2, "never stash: an added type joins");
            ext.Receive(110, "{\"action\":\"Stash\",\"data\":{\"make\":\"addBlockItem\",\"status\":false,\"itemData\":{\"sprite\":2160,\"name\":\"crystal coin\",\"id\":2160}}}");
            check(st.Blocks.Count == 1 && st.Blocks[0].Id == 3264, "never stash: status false takes a type off");
            st.ToggleBlock(new Pos(0xFFFF, 0x40, 2), 2);
            check(sent.Count == 1 && sent[0].Contains("ChangeStash") && sent[0].Contains("\"stackpos\":2") && sent[0].Contains("\"Pos\""), "never stash: toggling sends the item's position");
            sent.Clear();
            st.Unblock(3264);
            check(sent[0].Contains("\"RemoveUI\":true") && sent[0].Contains("\"itemId\":3264"), "never stash: remove sends the type id");

            check(StashFinder.CleanQuery("  ab ") == "ab" && StashFinder.CleanQuery("a") == null && StashFinder.CleanQuery(" a ") == null && StashFinder.CleanQuery(new string('x', 41)) == null, "find: the query is trimmed, 2 to 40 letters");
            sent.Clear();
            st.Finder.Request("fire", 1, 1000);
            check(sent.Count == 1 && sent[0].Contains("\"Find\"") && sent[0].Contains("\"q\":\"fire\"") && sent[0].Contains("\"page\":1"), "find: the request carries the query and page");
            check(st.Finder.StatusText() == "Searching...", "find: searching until answered");
            ext.Receive(110, "{\"action\":\"Stash\",\"data\":{\"make\":\"found\",\"q\":\"old\",\"page\":1,\"pages\":1,\"total\":0,\"items\":[]}}");
            check(!st.Finder.Answered, "find: an answer for another query is dropped");
            ext.Receive(110, "{\"action\":\"Stash\",\"data\":{\"make\":\"found\",\"q\":\"fire\",\"page\":1,\"pages\":2,\"total\":9,\"shown\":8,\"capped\":false,\"items\":["
                + "{\"loc\":\"equip\",\"name\":\"fire sword\",\"count\":1,\"cid\":3264,\"rarity\":4,\"slot\":5},"
                + "{\"loc\":\"bag\",\"name\":\"fire rune\",\"count\":50,\"cid\":2300,\"where\":\"Backpack > Pouch\",\"slot\":3},"
                + "{\"loc\":\"stash\",\"name\":\"fire axe\",\"count\":1,\"cid\":3274,\"unique\":true,\"tab\":2,\"row\":7},"
                + "{\"loc\":\"stash\",\"name\":\"fire gem\",\"count\":3,\"cid\":3500,\"tab\":1,\"item\":3500}]}}");
            var f = st.Finder;
            check(f.Answered && f.Results.Count == 4 && f.Pages == 2 && f.StatusText() == "9 found, the first 8 listed. Type more of the name.", "find: the answer is kept: " + f.StatusText());
            check(StashFinder.Title(f.Results[0]) == "Fire sword (Rare)" && StashFinder.Title(f.Results[1]) == "Fire rune x50" && StashFinder.Title(f.Results[2]) == "Fire axe (Unique)", "find: titles with the rarity and the count");
            check(StashFinder.Color(f.Results[2]) == ItemRarity.UniqueColor && StashFinder.Color(f.Results[0]) == "#a35cf0", "find: colours by rarity, unique first");
            check(StashFinder.WhereText(f.Results[0], null) == "Equipped: Right hand" && StashFinder.WhereText(f.Results[1], null) == "Carried: Backpack > Pouch", "find: where text of worn and carried items");
            check(StashFinder.WhereText(f.Results[2], StashFinder.TabText) == "Stash: Old tab 2 tab", "find: where text of a stash entry");
            check(StashFinder.Action(f.Results[0]) == "equip" && StashFinder.Action(f.Results[1]) == "container" && StashFinder.Action(f.Results[2]) == "stash", "find: what a click does");
            check(StashFinder.Hint(f.Results[2]).StartsWith("Click: open the stash"), "find: the hint of a stash result");
            check(StashFinder.IsEntry(f.Results[2], new StashItem { Row = 7 }) && !StashFinder.IsEntry(f.Results[2], new StashItem { Row = 8 }) && StashFinder.IsEntry(f.Results[3], new StashItem { Id = 3500, Row = -1 }), "find: a result is an entry by row, or by item id when it has no row");
            check(f.PageText() == "Page 1 of 2", "find: the page text");
            sent.Clear();
            f.Turn(1, 2000);
            check(sent.Count == 1 && sent[0].Contains("\"page\":2"), "find: the next page is asked");
            f.Turn(1, 2000);
            check(sent.Count == 2 && sent[1].Contains("\"page\":2") == false || f.Page == 2, "find: no page past the last");
            f.Request(null, 1, 3000);
            check(f.Results.Count == 0 && f.Query == null, "find: a null query clears the list");
            f.Error = "short";
            check(f.StatusText() == "Type at least 2 letters.", "find: the short query message");
            check(StashFinder.GoText(f.Results.Count > 0 ? f.Results[0] : new FindResult { Loc = "purse" }).Contains("purse"), "find: the purse hint");
        }

        static void StoreChecks(Action<bool, string> check)
        {
            check(StoreRotation.Left(3 * 86400 + 4 * 3600 + 5) == "3d 04h" && StoreRotation.Left(5 * 3600 + 7 * 60) == "5h 07m" && StoreRotation.Left(12 * 60) == "12m" && StoreRotation.Left(5) == "1m" && StoreRotation.Left(-4) == "0m", "store rotation: days and hours, hours and minutes, minutes");
            check(StoreRotation.Label("This week", -1, 0) == "This week" && StoreRotation.Label("This week", 90000, 0) == "This week (1d 01h)", "store rotation: the label with and without a countdown");
            check(StoreTryOn.SecondsLeft(10000, 8500) == 2 && StoreTryOn.SecondsLeft(10000, 10000) == 0 && StoreTryOn.Countdown(8) == "8s" && StoreTryOn.Countdown(0) == null, "store try on: seconds left rounded up, the button text");
            check(StoreTryOn.HexOrEmpty("#a1B2c3", false) == "#a1B2c3" && StoreTryOn.HexOrEmpty("#a1b2c3d4", false) == "" && StoreTryOn.HexOrEmpty("#a1b2c3d4", true) == "#a1b2c3d4" && StoreTryOn.HexOrEmpty("red", true) == "" && StoreTryOn.HexOrEmpty("#12345g", false) == "", "store try on: a colour is #rrggbb, an accent may carry alpha");

            var ext = new ExtOpcodes();
            var sent = new List<string>(); ext.Transmit = p => sent.Add(Encoding.UTF8.GetString(p, 4, p.Length - 4));
            double clock = 100;
            var st = new StoreState(ext) { Clock = () => clock };
            ext.Receive(218, "{\"action\":\"categories\",\"data\":[{\"name\":\"This week\",\"type\":\"item\",\"item\":2160,\"pages\":1,\"endsIn\":3600},{\"name\":\"Wings\",\"type\":\"item\",\"item\":2160,\"pages\":1}]}");
            check(st.Categories.Count == 2 && st.Categories[0].EndsAt == 3700 && st.Categories[1].EndsAt == -1, "store: a rotating category counts from the time its list came");
            sent.Clear();
            ext.Receive(218, "{\"action\":\"category_page\",\"data\":{\"category\":1,\"page\":1,\"offers\":[{\"type\":\"item\",\"item\":2160,\"title\":\"Red chat\",\"cost\":50,\"gift\":true,\"preview\":{\"effect\":true,\"color\":\"#ff0000\",\"accent\":\"#00112233\"}},{\"type\":\"item\",\"item\":1,\"title\":\"Plain\",\"cost\":5}]}}");
            var o = st.Offers[0];
            check(o.Gift && o.PreviewEffect && o.PreviewColor == "#ff0000" && o.PreviewAccent == "#00112233" && !st.Offers[1].PreviewEffect, "store: the offer's preview fields are read");
            sent.Clear();
            check(st.TryOn(o) && sent.Count == 1 && sent[0].Contains("\"preview\"") && sent[0].Contains("\"category\":1") && sent[0].Contains("\"offer\":1"), "store: TRY ON sends the preview action with the place of the offer");
            check(!st.TryOn(st.Offers[1]), "store: an offer without an effect has no try on");
            check(!st.AskGift(o, "  ") && !st.AskGift(st.Offers[1], "Bob"), "store: a gift needs a name and a gift offer");
            check(st.AskGift(o, " Bob ") && st.ConfirmOffer == o && st.GiftTo == "Bob", "store: the gift asks for a confirmation first");
            sent.Clear();
            check(st.ConfirmBuy() && sent.Count == 1 && sent[0].Contains("\"buy\"") && sent[0].Contains("\"gift\":\"Bob\"") && st.GiftTo.Length == 0, "store: the confirmed gift names the character");
            st.AskBuy(o); st.CancelBuy();
            check(st.ConfirmOffer == null && st.GiftTo.Length == 0, "store: cancel clears the offer and the gift name");
            sent.Clear();
            st.AskBuy(o); st.ConfirmBuy();
            check(!sent[0].Contains("gift"), "store: a plain purchase carries no gift name");
        }

        static void ScatterChecks(Action<bool, string> check)
        {
            var d = ScatterPrefs.Read("");
            check(d.Enabled && d.Level == 2, "scatter prefs: the default is on, Normal");
            var r = ScatterPrefs.Read("{\"enabled\":false,\"level\":3}");
            check(!r.Enabled && r.Level == 3, "scatter prefs: a stored choice is read");
            check(ScatterPrefs.Read("{\"level\":99}").Level == 3 && ScatterPrefs.Read("{\"level\":-4}").Level == 1 && ScatterPrefs.Read("not json").Level == 2, "scatter prefs: a hand-edited level is clamped, junk is the default");
            check(ScatterPrefs.Read(ScatterPrefs.Write(new ScatterSettings { Enabled = false, Level = 1 })).Level == 1 && !ScatterPrefs.Read(ScatterPrefs.Write(new ScatterSettings { Enabled = false, Level = 1 })).Enabled, "scatter prefs: written and read back");
            check(ScatterPrefs.Key("Bob Knight") == "chaos.damagescatter.bob knight" && ScatterPrefs.Key("") == null && ScatterPrefs.LevelName(1) == "Subtle" && ScatterPrefs.LevelName(3) == "Wide", "scatter prefs: the key per character and the level names");
            var sc = new DamageScatter(1) { Settings = new ScatterSettings { Enabled = false, Level = 2 } };
            ScatterRoll roll;
            check(!sc.Pick(new Pos(1, 1, 7), 0, 0, false, out roll), "scatter prefs: off, no roll");
        }
    }
}
