// Phase 8, track B: gaps of the P2 partial rows (Core/Phase8B*.cs): the market's Modifiers filter, the helper's buff bar rules and Timer rules, the wide view in the 3D views, the charm slot
// art, the effect icons, the ground rings, the map overlay keys, the open backpacks, the Customise Character view, the info lift per view, the mount layer.
using System;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class Phase8BTests
    {
        static object J(string json) => Json.TryParse(json);

        public static void Run(Action<bool, string> check)
        {
            Loc.Set("en");
            MarketModChecks(check);
            SupportChecks(check);
            ViewChecks(check);
            ArtChecks(check);
            KeyChecks(check);
            ContainerChecks(check);
            ExtrasChecks(check);
            Loc.Set("en");
        }

        // ------------------------------------------------------------------------------------ game_market: the Modifiers filter
        const string CodexJson = "{\"tabs\":[{\"id\":\"modifiers\",\"name\":\"Modifiers\",\"entries\":["
            + "{\"id\":\"mod:rarity_arcaneabsorb\",\"name\":\"Arcane Absorb\",\"f\":{\"side\":\"suffix\"},\"tv\":[\"+2%\",\"+10-14%\"]},"
            + "{\"id\":\"mod:rarity_firedmg\",\"name\":\"Fire Damage\",\"f\":{\"side\":\"prefix\"},\"tv\":[\"+3\",\"+30\"]},"
            + "{\"id\":\"mod:rarity_firedmgpct\",\"name\":\"Fire Damage\",\"f\":{\"side\":\"prefix\"},\"tv\":[\"+3%\",\"+30%\"]},"
            + "{\"id\":\"mod:rarity_vitality\",\"name\":\"Vitality\",\"f\":{\"side\":\"suffix\"},\"tv\":[\"+1\"]}]},"
            + "{\"id\":\"powers\",\"name\":\"Powers\",\"entries\":[{\"id\":\"power:arclightning\",\"name\":\"Arc Lightning\",\"f\":{\"side\":\"prefix\"},\"tv\":[\"2-3%\"]}]},"
            + "{\"id\":\"orbs\",\"name\":\"Orbs\",\"entries\":[{\"id\":\"orb:chaos\",\"name\":\"Chaos\"}]}]}";

        static void MarketModChecks(Action<bool, string> check)
        {
            var cat = ModCatalog.Build(CodexData.Load(CodexJson));
            check(cat.List.Count == 5, "market mods: modifiers and powers of the Codex, no orbs (" + cat.List.Count + ")");
            check(cat.ByKey.ContainsKey("chaos_mod_arclightning") && cat.ByKey["chaos_mod_arclightning"].Group == "power", "market mods: a power is the modifier chaos_mod_{power}");
            check(cat.List[0].Group == "prefix" && cat.List[cat.List.Count - 1].Group == "power", "market mods: sorted prefixes, suffixes, powers");
            check(cat.ByKey["rarity_firedmg"].Name == "Fire Damage (+30)" && cat.ByKey["rarity_firedmgpct"].Name == "Fire Damage (+30%)", "market mods: two modifiers of one name are told apart by their best tier");
            var ch = cat.Choices("fire dam", out string first);
            check(first == "rarity_firedmgpct" && ch.Count == 4 && ch[1].Text == "-- Prefixes --" && ch[1].Key == "", "market mods: the typeahead matches every word, one heading per group (" + ch.Count + ")");
            cat.Choices("zzz", out string none);
            check(none == "" && cat.Choices("zzz", out _)[0].Text == "No modifier matches", "market mods: a search that matches nothing chooses nothing");
            check(cat.Choices("", out _).Count == 1 + 3 + 5, "market mods: an empty search lists all with three headings");

            var form = new ModForm();
            form.Rows.Add(new ModRow { Key = "rarity_vitality", Min = "5", Tier = 3 });
            form.Rows.Add(new ModRow { Key = "" });
            form.Rows.Add(new ModRow { Key = "chaos_mod_arclightning", Tier = 99 });
            form.Sockets = "2"; form.Quality = "99"; form.FreeP = true;
            var req = MarketMods.Request(form, MarketMods.Default, out string why);
            var mods = (List<object>)req["mods"];
            check(req != null && mods.Count == 2 && Json.Number(mods[0], "min") == 5 && Json.Number(mods[0], "t") == 3, "market mods: rows without a modifier are left out, min and tier kept");
            check(Json.Number(mods[1], "t") == 8 && !((Dictionary<string, object>)mods[1]).ContainsKey("min"), "market mods: the tier is capped at 8, a zero minimum is not sent");
            check(Json.Number(req, "sockets") == 2 && Json.Number(req, "quality") == 30 && Json.Bool(req, "freeP") && !req.ContainsKey("need") && !req.ContainsKey("bound"), "market mods: sockets, quality capped at 30, free prefix");
            check(MarketMods.Count(req) == 5, "market mods: the toggle counts rows and flags (" + MarketMods.Count(req) + ")");

            form.Rows.Add(new ModRow { Key = "rarity_vitality" });
            check(MarketMods.Request(form, MarketMods.Default, out why) == null && why == "Each modifier only once per search.", "market mods: a modifier only once");
            form.Rows.RemoveAt(3);
            form.Rows[0].Min = "x";
            check(MarketMods.Request(form, MarketMods.Default, out why) == null && why == "Row 1: the minimum value is a whole number.", "market mods: the minimum is a whole number");
            form.Rows[0].Min = "5";
            form.Count = true; form.Need = "3";
            check(MarketMods.Request(form, MarketMods.Default, out why) == null && why.Contains("from 1 to 2"), "market mods: 'at least' needs 1 up to the rows chosen");
            form.Need = "1";
            var counted = MarketMods.Request(form, MarketMods.Default, out why);
            check(Json.Number(counted, "need") == 1, "market mods: 'at least 1 of 2' sends need");
            form.Need = "2";
            check(!MarketMods.Request(form, MarketMods.Default, out why).ContainsKey("need"), "market mods: 'at least all' is the plain filter");
            var tooMany = new ModForm();
            for (int i = 0; i < 7; i++) tooMany.Rows.Add(new ModRow { Key = "k" + i });
            check(MarketMods.Request(tooMany, MarketMods.Default, out why) == null && why == "At most 6 modifiers per search.", "market mods: at most six rows");
            check(MarketMods.LimitsOf(J("{\"modFilter\":{\"maxRows\":4,\"maxTier\":6}}")).MaxRows == 4 && MarketMods.LimitsOf(null).MaxRows == 6, "market mods: the limits come from the meta message");
            check(MarketMods.TierOptions(8).Count == 9 && MarketMods.TierOptions(8)[1] == "T1+" && MarketMods.TierOptions(8)[8] == "T8", "market mods: tier choices T1+ to T8");

            var tip = J("{\"mods\":[{\"k\":\"rarity_vitality\",\"v\":7,\"tr\":4,\"t\":\"+7 Vitality\"},{\"k\":\"RARITY_ARCANEABSORB\",\"v\":1,\"tr\":1,\"t\":\"+1% Arcane Absorb\"}]}");
            var want = J("{\"mods\":[{\"k\":\"rarity_vitality\",\"min\":5,\"t\":3},{\"k\":\"rarity_arcaneabsorb\",\"min\":9}]}");
            var lines = MarketMods.MatchedMods(tip, want);
            check(lines.Count == 1 && lines[0] == "Matches: +7 Vitality (T4)", "market mods: the tooltip lines the search matched (" + string.Join("|", lines) + ")");
            check(MarketMods.FilterText(want, cat.NameOf) == "Vitality 5+ T3+, rarity_arcaneabsorb 9+".Replace("rarity_arcaneabsorb", "Arcane Absorb"), "market mods: an order's filter in words");
            check(MarketMods.FilterText(J("{\"rarity\":3,\"ilvl\":40,\"sockets\":2,\"need\":1,\"mods\":[{\"k\":\"a\"},{\"k\":\"b\"}],\"freeS\":true}"), null) == "Magic+ - iLvl 40+ - 1 of: a, b - 2+ sockets - free suffix", "market mods: rarity, level, rows, sockets and flags in one line");
            check(MarketMods.FilterText(null, null) == "Any" && MarketMods.FilterText(J("{}"), null) == "Any", "market mods: no filter is Any");

            var o = MarketMath.CheckOrder(J("{\"price\":{\"gold\":{\"min\":100,\"max\":2000000000}},\"fee\":{\"pct\":1,\"min\":1,\"coinGold\":1}}"), 5, "2", "1000", "gold", 3, 0, "", out _, out _, out string w2, req);
            var filter = o != null ? Json.Get(o, "filter") : null;
            check(o != null && Json.List(filter, "mods").Count == 2 && Json.Number(filter, "sockets") == 2, "market mods: a buy order carries the Browse modifiers in its filter (" + w2 + ")");
            var plain = MarketMath.CheckOrder(J("{\"price\":{\"gold\":{\"min\":100,\"max\":2000000000}},\"fee\":{\"pct\":1,\"min\":1,\"coinGold\":1}}"), 5, "2", "1000", "gold", 3, 0, "", out _, out _, out _, new Dictionary<string, object> { { "mods", new List<object>() } });
            check(plain != null && !((Dictionary<string, object>)Json.Get(plain, "filter")).ContainsKey("mods"), "market mods: an empty list of rows is no filter");
        }

        // ------------------------------------------------------------------------------------ game_helpersupport: buff bar, user off, timer rules
        static Spell Sp(int id, string name, int group = 3, int cd = 2000, int level = 1) => new Spell { Id = id, Name = name, Words = "w" + id, Group = group, Cooldown = cd, Level = level, Mana = 0 };

        static SupportContext Ctx(double now, Dictionary<int, Spell> book, Func<string[], bool?> bar, Func<bool?> hasted = null)
            => new SupportContext { Now = now, HelperOn = true, Attacking = true, SpellOf = id => book.TryGetValue(id, out var s) ? s : null, BuffActive = bar, Hasted = hasted };

        static void SupportChecks(Action<bool, string> check)
        {
            var vigil = Sp(162, "Vigil of Dawn");
            var book = new Dictionary<int, Spell> { { 162, vigil } };
            var cfg = new HelperSupportConfig();
            cfg.Slots.Add(new SupportSlot { Id = 162 });
            var st = new SupportState();
            bool? barOn = null;
            Func<string[], bool?> bar = names => barOn;
            string overall;
            check(HelperSupport.Pick(st, cfg, Ctx(1000, book, bar), out overall) == null && st.Status[162] == "nobar", "support bar: a vigil is never cast blind (no bar data)");
            barOn = false;
            var pick = HelperSupport.Pick(st, cfg, Ctx(2000, book, bar), out overall);
            check(pick != null && pick.Id == 162, "support bar: a vigil the bar shows off is cast");
            HelperSupport.NoteCast(st, vigil, 2000);
            barOn = true;
            HelperSupport.Pick(st, cfg, Ctx(9000, book, bar), out overall);
            check(st.Status[162] == "active" && st.BarOn[162], "support bar: a vigil the bar shows on is active");
            barOn = false;
            HelperSupport.Pick(st, cfg, Ctx(12000, book, bar), out overall);
            check(st.Status[162] == "useroff" && st.UserOff.ContainsKey(162), "support bar: a vigil that went off by itself is the player's switch");
            check(HelperSupport.TakeUserOff(st, cfg, 12500).Count == 0 && cfg.Slots[0].Enabled, "support bar: not unticked before the confirm time");
            var off = HelperSupport.TakeUserOff(st, cfg, 14100);
            check(off.Count == 1 && off[0] == 162 && !cfg.Slots[0].Enabled, "support bar: unticked after two seconds, so it is not cast again");

            // a death or login close by: not the player's
            var st2 = new SupportState();
            cfg.Slots[0].Enabled = true;
            barOn = true;
            HelperSupport.Pick(st2, cfg, Ctx(1000, book, bar), out overall);
            HelperSupport.NoteClear(st2, 1500, HelperSupport.SessionGraceMs);
            barOn = false;
            HelperSupport.Pick(st2, cfg, Ctx(3000, book, bar), out overall);
            check(st2.UserOff.Count == 0, "support bar: a drop within the grace of a death or login is not the player's");
            // two vigils dropping in the same tick: not the player's
            var st3 = new SupportState();
            st3.UserOff[1] = 5000; st3.UserOff[2] = 5000;
            var cfg3 = new HelperSupportConfig(); cfg3.Slots.Add(new SupportSlot { Id = 1 }); cfg3.Slots.Add(new SupportSlot { Id = 2 });
            check(HelperSupport.TakeUserOff(st3, cfg3, 9000).Count == 0 && st3.UserOff.Count == 0, "support bar: two vigils dropping in one tick are not the player's");

            // a buff the bar shows on counts, one it never showed counts by duration
            var buff = Sp(222, "Red Frenzy");
            var book2 = new Dictionary<int, Spell> { { 222, buff } };
            var cfg2 = new HelperSupportConfig(); cfg2.Slots.Add(new SupportSlot { Id = 222 });
            var st4 = new SupportState();
            bool? on = true;
            HelperSupport.Pick(st4, cfg2, Ctx(1000, book2, n => on), out overall);
            check(st4.Status[222] == "active" && st4.Seen.Contains(222), "support bar: a fight buff the bar shows on is active");
            on = false;
            HelperSupport.Pick(st4, cfg2, Ctx(2000, book2, n => on), out overall);
            check(st4.Status[222] == "cast", "support bar: a buff the bar has shown and no longer shows is cast again");
            var st5 = new SupportState();
            HelperSupport.Pick(st5, cfg2, Ctx(1000, book2, n => null, () => null), out overall);
            check(st5.Status[222] == "cast", "support bar: no bar data and never cast is cast");
            HelperSupport.NoteCast(st5, buff, 1000);
            HelperSupport.Pick(st5, cfg2, Ctx(5000, book2, n => null), out overall);
            check(st5.Status[222] == "wait" || st5.Status[222] == "active", "support bar: after a cast the duration rule decides without a bar (" + st5.Status[222] + ")");
            var haste = Sp(6, "Haste");
            var cfgH = new HelperSupportConfig(); cfgH.Slots.Add(new SupportSlot { Id = 6 });
            var stH = new SupportState();
            HelperSupport.Pick(stH, cfgH, new SupportContext { Now = 1000, HelperOn = true, Attacking = true, SpellOf = id => haste, BuffActive = n => false, Hasted = () => true }, out overall);
            check(stH.Status[6] == "active", "support bar: a haste shows in the player's own state");
            check(HelperSupport.ReasonText("useroff") == "Switched off by you", "support bar: reason text");
            check(HelperSupport.Info(haste).Bar.SequenceEqual(new[] { "haste", "haste" }), "support bar: the names the bar may show it under (" + string.Join(",", HelperSupport.Info(haste).Bar) + ")");

            // Auto setup: nine fight buffs, eight rows, the ninth a Timer rule
            var spells = new List<Spell>();
            int[] ids = { 209, 217, 222, 233, 239, 245, 72, 223, 226 };
            for (int i = 0; i < ids.Length; i++) spells.Add(Sp(ids[i], "Buff " + ids[i], 3, 25000, 100 - i));
            var plan = HelperSupport.AutoPlanFull(spells, id => true, out var timers);
            check(plan.Count == 8 && timers.Count == 1, "auto support: eight Support rows and the ninth buff a Timer rule (" + plan.Count + "/" + timers.Count + ")");
            check(timers[0].Id == 226 && timers[0].Cooldown == 26 && timers[0].Words == "w226", "auto support: the rule's cooldown is the longer of the spell's and its effect, plus one second (" + timers[0].Cooldown + ")");
            var merged = HelperSupport.MergeTimers(new List<SupportTimerRule> { new SupportTimerRule { Id = 1, Words = "W226" } }, timers, false);
            check(merged.Count == 1, "auto support: a planned rule with words already there is not added twice");
            check(HelperSupport.MergeTimers(new List<SupportTimerRule> { new SupportTimerRule { Id = 1, Words = "x" } }, timers, true).Count == 1 && HelperSupport.MergeTimers(new List<SupportTimerRule>(), timers, true)[0].Id == 226, "auto support: replace drops the player's rules");
            var rule = new SupportTimerRule { Id = 9, Words = "w9", Cooldown = 30 };
            check(HelperSupport.TimerDue(rule, double.NaN, 1000, true, false, double.NaN), "timer rule: due at the first fight");
            check(!HelperSupport.TimerDue(rule, double.NaN, 1000, false, false, double.NaN) && !HelperSupport.TimerDue(rule, double.NaN, 1000, true, true, double.NaN), "timer rule: not without a monster, not in a protection zone");
            check(!HelperSupport.TimerDue(rule, 1000, 20000, true, false, double.NaN) && HelperSupport.TimerDue(rule, 1000, 31001, true, false, double.NaN), "timer rule: every cooldown seconds");
            check(!HelperSupport.TimerDue(rule, double.NaN, 3000, true, false, 1000) && HelperSupport.TimerDue(rule, double.NaN, 3600, true, false, 1000), "timer rule: the first casts of the rules are a stagger apart");
            rule.Enabled = false;
            check(!HelperSupport.TimerDue(rule, double.NaN, 1000, true, false, double.NaN), "timer rule: an unticked rule is off");
            var cfgJ = new HelperConfig();
            cfgJ.Support.Timers.Add(new SupportTimerRule { Id = 5, Words = "vyr ira", Name = "Red Frenzy", Cooldown = 41, Enabled = false });
            var back = HelperConfig.FromJson(cfgJ.ToJson());
            check(back.Support.Timers.Count == 1 && back.Support.Timers[0].Cooldown == 41 && !back.Support.Timers[0].Enabled && back.Support.Timers[0].Name == "Red Frenzy", "timer rule: saved and loaded with the helper settings");
        }

        // ------------------------------------------------------------------------------------ game_chaosview, game_chaosinfolift, game_lookpreview
        static void ViewChecks(Action<bool, string> check)
        {
            var w = new World(null) { Center = new Pos(100, 100, 7) };
            FrontLive.Window(w, null, out int x0, out int y0, out int x1, out int y1);
            check(x0 == 100 - 8 - 1 && x1 == 100 + 9 + 1 && y0 == 100 - 6 - 1 && y1 == 100 + 7 + 1, "wide view: the live window of the default 17 x 13 is the old one");
            w.Range = new AwareRange(29, 21);
            FrontLive.Window(w, null, out x0, out y0, out x1, out y1);
            check(x0 == 100 - 14 - 1 && x1 == 100 + 15 + 1 && y0 == 100 - 10 - 1 && y1 == 100 + 11 + 1, "wide view: the live window follows the wide aware range (" + x0 + " " + x1 + " " + y0 + " " + y1 + ")");
            var tiles = new World(null) { Center = new Pos(10, 10, 7) };
            tiles.Range = new AwareRange(29, 21);
            tiles.AddThing(new Pos(10 + 13, 10 + 9, 7), new Thing { Item = new Item { Id = 100 } });
            int wideHash = Hd2dWorld3d.ViewHash(tiles);
            tiles.Range = AwareRange.Default;
            check(wideHash != Hd2dWorld3d.ViewHash(tiles), "wide view: an item at the edge of the wide range is in the HD-2D hash, not in the default one");
            check(ViewZoom.MaxRowsFor(new AwareRange(29, 21)) == 19 && ViewZoom.MaxRowsFor(AwareRange.Default) == 11, "wide view: every view may draw 19 rows at 29 x 21, 11 at the default");

            var c = new Creature { Type = 0, Outfit = new Outfit(0, 0, 0, 0, 0) };
            check(InfoLift.ForView(c, 64f, true) == 0f && InfoLift.ForView(c, 64f, false) == InfoLift.Scaled(c, 64f), "info lift: none in the 3D views (the label is at the figure's top), the table in the classic view");
            int tall = 0;
            foreach (var kv in InfoLift.Entries(InfoLiftData.Table)) { tall = kv.Key; break; }
            if (tall > 0)
            {
                var p = new Creature { Type = 0, Outfit = new Outfit(tall, 0, 0, 0, 0) };
                check(InfoLift.ForView(p, 32f, false) > 0f && InfoLift.ForView(p, 32f, true) == 0f, "info lift: a tall look is lifted in the classic view only");
            }

            Func<int, KeyValuePair<int, int>> size = id => new KeyValuePair<int, int>(1, 1);
            Func<int, KeyValuePair<float, float>> disp = id => new KeyValuePair<float, float>(8f, 16f);
            var rider = OutfitLayers.Plan(new Outfit(128, 1, 2, 3, 4) { Mount = 400, Wings = 902 }, size, true, disp);
            check(rider.Count == 3 && rider[0].Kind == OutfitLayer.Role.Mount && rider[1].Kind == OutfitLayer.Role.Wings && rider[2].Kind == OutfitLayer.Role.Body, "look preview: mount, wings, body from back to front");
            check(Math.Abs(rider[2].DY - (-(6f / 32f) - 0.5f)) < 1e-4 && Math.Abs(rider[2].DX - (-(6f / 32f) - 0.25f)) < 1e-4, "look preview: the rider rides up by the mount's displacement");
            var plainRider = OutfitLayers.Plan(new Outfit(128, 1, 2, 3, 4) { Mount = 400 }, size, true);
            check(plainRider.Count == 2 && plainRider[1].DX == 0f, "look preview: without a displacement table the rider stays");
            check(OutfitLayers.Plan(new Outfit(128, 1, 2, 3, 4) { Mount = 400 }, id => new KeyValuePair<int, int>(0, 0), true).Count == 1, "look preview: a mount the pair does not have is left out");
        }

        // ------------------------------------------------------------------------------------ game_charms, game_cosmetics, game_groundfx
        static void ArtChecks(Action<bool, string> check)
        {
            check(CharmSlots.Path(1, 1) == "../data/images/chaos/charmslot_1x1.png" && CharmSlots.Path(2, 2) == "../data/images/chaos/charmslot_2x2.png" && CharmSlots.Path(2, 1).EndsWith("2x1.png") && CharmSlots.Path(1, 2).EndsWith("1x2.png"), "charm slots: the four shapes have a picture");
            check(CharmSlots.Path(3, 1) == null && CharmSlots.Path(1, 3) == null && CharmSlots.Path(0, 0) == null, "charm slots: another shape stays on the plain frame");

            var play = (List<object>)J("[{\"b\":{\"n\":\"fx_short\",\"ms\":300}},{\"b\":{\"n\":\"fx_long\",\"ms\":900}},{\"b\":{\"n\":\"missile_x\",\"m\":true,\"ms\":2000}}]");
            check(Json.Text(CosmeticIcons.MainEffect(play), "n") == "fx_long", "effect icons: the main effect is the longest non-missile one");
            check(Json.Text(CosmeticIcons.MainEffect((List<object>)J("[{\"b\":{\"n\":\"missile_only\",\"m\":true}}]")), "n") == "missile_only", "effect icons: only a missile: the first one");
            check(CosmeticIcons.MainEffect(null) == null && CosmeticIcons.MainEffect(new List<object>()) == null, "effect icons: no steps, no effect");
            check(CosmeticIcons.FxPath(J("{\"n\":\"fx_long\"}")) == "game_cosmetics/images/fx/fx_long.png" && CosmeticIcons.FxPath(J("{\"n\":\"../x\"}")) == null && CosmeticIcons.FxPath(J("{}")) == null, "effect icons: the file of a spec, never a path outside the folder");
            check(CosmeticIcons.PrintPath("claw") == "game_cosmeticfx/images/prints/claw.png" && CosmeticIcons.PrintPath("claw.png") == "game_cosmeticfx/images/prints/claw.png" && CosmeticIcons.PrintPath("a/b") == null && CosmeticIcons.PrintPath("") == null, "effect icons: the print of a footprint");
            check(CosmeticIcons.Path(new CosRow { Kind = "spellskin", Play = play }) == "game_cosmetics/images/fx/fx_long.png", "effect icons: a spell skin row draws its main effect");
            check(CosmeticIcons.Path(new CosRow { Kind = "footprint", Id = "4", Art = "claw" }) == "game_cosmeticfx/images/prints/claw.png" && CosmeticIcons.Path(new CosRow { Kind = "footprint", Id = "0", Art = "claw" }) == null, "effect icons: a footprint draws its print, the default none");
            check(CosmeticIcons.Path(new CosRow { Kind = "chatcolor", Color = "#ff0000" }) == null && CosmeticIcons.Path(null) == null, "effect icons: a colour or item row has none");

            check(GroundRing.Size(0f) == 0.8f && Math.Abs(GroundRing.Size(1f) - 2.7f) < 1e-5f && GroundRing.Size(5f) == GroundRing.Size(1f), "ground rings: the ring grows from 0.8 to 2.7 tiles");
            check(Math.Abs(GroundRing.Alpha(0f) - 0.75f) < 1e-5f && GroundRing.Alpha(1f) == 0f && Math.Abs(GroundRing.GlowOpacity(0f) - 0.25f) < 1e-5f, "ground rings: they fade out");
            var quads = new List<float[]>();
            GroundRing.Quads(1f, quads);
            check(quads.Count == 2 && quads[0][3] == 1f && quads[1][3] == 0f && Math.Abs(quads[0][1] - 2.7f * 0.55f) < 1e-4f && Math.Abs(quads[1][0] - 2.7f * 0.8f) < 1e-4f, "ground rings: ring first, then the glow, flattened");
            var ring = GroundRing.Rgba(true); var glow = GroundRing.Rgba(false);
            check(ring.Length == 32 * 32 * 4 && ring[(16 * 32 + 16) * 4 + 3] == 0 && glow[(16 * 32 + 16) * 4 + 3] > 200, "ground rings: the ring is hollow, the glow is bright in the middle");
            check(ring[3] == 0 && ring.Where((b, i) => i % 4 == 3 && b > 0).Any(), "ground rings: the ring picture has a visible band");
        }

        // ------------------------------------------------------------------------------------ game_mapoverlay keys
        static void KeyChecks(Action<bool, string> check)
        {
            var r = new KeyRepeat();
            check(r.Step(true, 0) && !r.Step(true, 100) && !r.Step(true, 249) && r.Step(true, 250) && !r.Step(true, 280) && r.Step(true, 300), "overlay keys: one step at the press, then after 250 ms one every 50 ms");
            check(!r.Step(false, 400) && r.Step(true, 410), "overlay keys: a new press steps at once");
            OverlayKeys.Dir(true, false, true, false, out int dx, out int dy);
            check(dx == -1 && dy == -1, "overlay keys: up and left");
            OverlayKeys.Dir(false, false, true, true, out dx, out dy);
            check(dx == 0 && dy == 0, "overlay keys: opposite keys cancel");
            check(OverlayKeys.Pans(true, true, false) && !OverlayKeys.Pans(false, true, false) && !OverlayKeys.Pans(true, false, false) && !OverlayKeys.Pans(true, true, true), "overlay keys: Shift + arrows pan only while the overlay is shown and nothing is typed");
            check(OverlayKeys.ChatTab(true, false, false) && OverlayKeys.ChatTab(false, true, false) && !OverlayKeys.ChatTab(false, false, false) && !OverlayKeys.ChatTab(false, true, true), "overlay keys: the chat's next channel is Tab in the line or Ctrl+Tab");
            check(OverlayKeys.ToggleTab(false, false, false) && !OverlayKeys.ToggleTab(true, false, false) && !OverlayKeys.ToggleTab(false, true, false) && !OverlayKeys.ToggleTab(false, false, true), "overlay keys: Tab toggles the overlay outside the chat line");
            MapOverlayState.KeyPan(0, 0, 1, -1, 0, OverlayKeys.PanPixels, out double px, out double py);
            check(px == 48 && py == -48, "overlay keys: a pan step is 48 pixels (48 tiles at x1)");
        }

        // ------------------------------------------------------------------------------------ game_chaoslayout: the open backpacks
        static void ContainerChecks(Action<bool, string> check)
        {
            var k = ContainerKeys.KeyOf(new List<ContainerKeys.Step> { new ContainerKeys.Step { I = 3, Id = 2854 }, new ContainerKeys.Step { I = 1, Id = 1987 }, new ContainerKeys.Step { I = 0, Id = 1991 } });
            check(k == "3_2854/1_1987/0_1991" && ContainerKeys.Parse(k).Count == 3 && ContainerKeys.Depth(k) == 3, "containers: a key is the steps from an inventory slot");
            check(ContainerKeys.ParentKey(k) == "3_2854/1_1987" && ContainerKeys.ParentKey("3_2854") == null, "containers: the parent key");
            check(ContainerKeys.Parse("0_5") == null && ContainerKeys.Parse("12_5") == null && ContainerKeys.Parse("3_x") == null && ContainerKeys.Parse("") == null && ContainerKeys.Parse("3_5/ -1_5") == null, "containers: a key must start at slot 1 to 11 with item ids");
            check(ContainerKeys.KeyOf(new List<ContainerKeys.Step>()) == null, "containers: no steps, no key");
            check(ContainerKeys.FromPosition(new Pos(65535, 3, 0), 2854, null) == "3_2854" && ContainerKeys.FromPosition(new Pos(100, 3, 7), 2854, null) == null, "containers: an inventory slot gives a key, the map does not");
            check(ContainerKeys.FromPosition(new Pos(65535, 64 + 2, 1), 1987, cid => cid == 2 ? "3_2854" : null) == "3_2854/1_1987" && ContainerKeys.FromPosition(new Pos(65535, 64 + 5, 1), 1987, cid => null) == null, "containers: a slot of an open container needs that container's key");

            var saved = new List<ContainerEntry> { new ContainerEntry { Key = "3_2854/1_1987" }, new ContainerEntry { Key = "3_2854" }, new ContainerEntry { Key = "3_2854" }, new ContainerEntry { Key = "bad" }, new ContainerEntry { Key = "4_9" } };
            check(ContainerKeys.Entries(saved).Count == 3, "containers: entries are cleaned, one per key");
            var plan = ContainerKeys.PlanOf(saved, new List<string>());
            check(plan.Count == 3 && plan[0].Key == "3_2854" && plan[1].Key == "4_9" && plan[2].Key == "3_2854/1_1987" && !plan[0].Transient, "containers: parents first, then the saved order (" + string.Join(",", plan.Select(p => p.Key)) + ")");
            var plan2 = ContainerKeys.PlanOf(new List<ContainerEntry> { new ContainerEntry { Key = "3_2854/1_1987" } }, new List<string>());
            check(plan2.Count == 2 && plan2[0].Key == "3_2854" && plan2[0].Transient && !plan2[1].Transient, "containers: a parent that is not saved is opened and closed again");
            check(ContainerKeys.PlanOf(saved, new List<string> { "3_2854", "4_9" }).Count == 1, "containers: what is open already is not opened");
            var slots = new List<ContainerKeys.Slot> { new ContainerKeys.Slot { Index = 0, Id = 1987, Container = true }, new ContainerKeys.Slot { Index = 1, Id = 1987, Container = false }, new ContainerKeys.Slot { Index = 2, Id = 1987, Container = true } };
            check(ContainerKeys.Resolve(slots, new ContainerKeys.Step { I = 2, Id = 1987 }, null) == 2 && ContainerKeys.Resolve(slots, new ContainerKeys.Step { I = 1, Id = 1987 }, null) == 0, "containers: the item at the saved index, else the first container of that id");
            check(ContainerKeys.Resolve(slots, new ContainerKeys.Step { I = 0, Id = 1987 }, new HashSet<int> { 0 }) == 2 && ContainerKeys.Resolve(slots, new ContainerKeys.Step { I = 0, Id = 55 }, null) == -1, "containers: an item another step took is skipped, a missing id gives none");

            var mem = new ContainerMemory();
            mem.NoteUse(new Pos(65535, 3, 0), 2854, 1000);
            check(mem.Opened(7, 2854, 1500) == "3_2854" && mem.KeyOfContainer(7) == "3_2854" && mem.Dirty, "containers: the window that opens takes the pending use of its item id");
            mem.NoteUse(new Pos(65535, 64 + 7, 1), 1987, 2000);
            check(mem.Opened(8, 5555, 2100) == null && !mem.Known(8), "containers: a window with another item id than the pending one is unnamed");
            check(mem.Opened(8, 1987, 2200) == "3_2854/1_1987", "containers: a bag in an open container is keyed by its parent");
            mem.NoteUse(new Pos(65535, 4, 0), 9, 3000);
            check(mem.Opened(9, 9, 7000) == null, "containers: a pending open expires after three seconds");
            var snap = mem.Snapshot();
            check(snap.Count == 2 && snap[0].Key == "3_2854" && snap[1].Key == "3_2854/1_1987", "containers: the snapshot is in container id order");
            string json = mem.ToJson();
            var back = ContainerMemory.FromJson(json);
            check(!mem.Dirty && back.Count == 2 && back[1].Key == "3_2854/1_1987", "containers: saved and loaded");
            check(ContainerMemory.FromJson("not json").Count == 0 && ContainerMemory.PrefKey("Ana") == "chaos.containers.ana" && ContainerMemory.PrefKey("") == null, "containers: a bad save is empty, the key is per character");
            mem.Closed(7);
            check(!mem.Known(7) && mem.CidOf("3_2854/1_1987") == 8, "containers: a closed window is forgotten");
            mem.Clear();
            check(mem.Snapshot().Count == 0, "containers: cleared for a new character");

            // the restore walks the plan one open at a time
            var rs = new ContainerRestore(new List<ContainerEntry> { new ContainerEntry { Key = "3_2854/0_1987" }, new ContainerEntry { Key = "5_77" } }, new List<string>(), 0);
            var open = new Dictionary<string, int>();
            var inventory = new Dictionary<int, int> { { 3, 2854 }, { 5, 77 } };
            var sent = new List<string>();
            double t = 0;
            for (int i = 0; i < 80 && !rs.Done; i++)
            {
                t += 100;
                bool did = rs.Step(t, slot => inventory.TryGetValue(slot, out int id) ? id : 0, key => open.ContainsKey(key), key => open.TryGetValue(key, out int cid) ? cid : -1,
                    cid => new List<ContainerKeys.Slot> { new ContainerKeys.Slot { Index = 0, Id = 1987, Container = true } }, out Pos pos, out int useId, out int stack, out int closeCid);
                if (!did) continue;
                if (closeCid >= 0) { sent.Add("close " + closeCid); continue; }
                sent.Add(pos.X + "," + pos.Y + "," + pos.Z + " item " + useId + " stack " + stack);
                // the server answers 200 ms later: the window is open
                string key = useId == 2854 ? "3_2854" : useId == 1987 ? "3_2854/0_1987" : "5_77";
                open[key] = open.Count + 1;
            }
            check(rs.Done && rs.Sent == 3 && rs.Skipped == 0, "containers: the restore opened the parent, its child and the other slot (" + rs.Sent + " sent, " + rs.Skipped + " skipped)");
            check(sent.Count == 4 && sent[0] == "65535,3,0 item 2854 stack 3" && sent[1] == "65535,5,0 item 77 stack 5" && sent[2] == "65535,65,0 item 1987 stack 0" && sent[3].StartsWith("close "), "containers: the uses go out in order, the transient parent is closed at the end (" + string.Join(" | ", sent) + ")");
            var gone = new ContainerRestore(new List<ContainerEntry> { new ContainerEntry { Key = "3_2854" } }, new List<string>(), 0);
            for (int i = 0; i < 20 && !gone.Done; i++) gone.Step(i * 200.0, slot => 0, key => false, key => -1, cid => null, out _, out _, out _, out _);
            check(gone.Done && gone.Skipped == 1 && gone.Sent == 0, "containers: an item that is gone is skipped");
            check(new ContainerRestore(new List<ContainerEntry>(), new List<string>(), 0).Done, "containers: nothing saved, nothing to do");
        }

        // ------------------------------------------------------------------------------------ game_outfitextras
        static void ExtrasChecks(Action<bool, string> check)
        {
            var row = new OutfitExtrasPanel.ExtraRow { Key = "outline", Label = "Outline", Current = "0" };
            row.Options.Add(new OutfitExtrasPanel.Option { Text = "Default", Value = "0" });
            row.Options.Add(new OutfitExtrasPanel.Option { Text = "Ember Glow", Value = "3", Row = new CosRow { Kind = "outline", Id = "3", Art = "ember", Pulse = 1 } });
            row.Options.Add(new OutfitExtrasPanel.Option { Text = "Frost Glow", Value = "4", Row = new CosRow { Kind = "outline", Id = "4", Art = "frost" } });
            check(ExtrasView.Filter(row, "").Count == 3 && ExtrasView.Filter(row, "glow").Count == 2 && ExtrasView.Filter(row, "ember glow").SequenceEqual(new[] { 1 }) && ExtrasView.Filter(row, "zzz").Count == 0, "extras: the search keeps the cards that hold every word");
            check(ExtrasView.Filter(row, "FROST").SequenceEqual(new[] { 2 }) && ExtrasView.Filter(null, "x").Count == 0, "extras: the search ignores case");
            var p1 = ExtrasView.Preview(row, 1);
            check(p1 != null && p1.Kind == "outline" && p1.Art == "ember" && p1.Pulse && ExtrasView.Preview(row, 0) == null && ExtrasView.Preview(row, 9) == null, "extras: an outline card previews its glow, the default nothing");
            var frame = new OutfitExtrasPanel.ExtraRow { Key = "frame", Label = "Plate frame", Current = "" };
            frame.Options.Add(new OutfitExtrasPanel.Option { Text = "Title frame", Value = "" });
            frame.Options.Add(new OutfitExtrasPanel.Option { Text = "Gilded", Value = "gilded" });
            check(ExtrasView.Preview(frame, 1).Kind == "nameplate" && ExtrasView.Preview(frame, 1).Frame == "gilded" && ExtrasView.Preview(frame, 0) == null, "extras: a plate frame previews as a name plate");
            var chat = new OutfitExtrasPanel.ExtraRow { Key = "chatcolor", Label = "Chat colour" };
            chat.Options.Add(new OutfitExtrasPanel.Option { Text = "Red", Value = "2" });
            check(ExtrasView.Preview(chat, 0) == null, "extras: a chat colour is not drawn on the figure");
            var rows = new List<OutfitExtrasPanel.ExtraRow> { row, frame };
            var b = ExtrasView.Bundle(rows, k => k == "outline" ? 2 : 1, null, -1);
            check(b != null && b.Kind == "bundle" && b.Parts.Count == 2 && b.Parts[0].Art == "frost", "extras: the preview is the chosen options of every row");
            var hov = ExtrasView.Bundle(rows, k => k == "outline" ? 2 : 1, "outline", 1);
            check(hov.Parts[0].Art == "ember" && hov.Parts[1].Frame == "gilded", "extras: the hovered card stands in for its row's choice");
            check(ExtrasView.Bundle(rows, k => 0, null, -1) == null, "extras: nothing chosen, no bundle");
            check(ExtrasView.Equipped(row, 1) == "Outline: Ember Glow" && ExtrasView.Equipped(row, -1) == "Outline: Default", "extras: the Equipped now line");
            var worn = new Outfit(128, 1, 2, 3, 4, 3, 400) { Wings = 5, Aura = 6, Shader = "ember" };
            var o = ExtrasView.Layers(worn, false, true, false, false);
            check(o.Mount == 0 && o.Wings == 5 && o.Aura == 0 && o.Shader == "" && worn.Mount == 400, "extras: the layer boxes remove parts of a copy, never of the worn outfit");
        }
    }
}
