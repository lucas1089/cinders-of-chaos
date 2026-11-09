// Phase 7 track X: character cards (wings, aura, shader), the create character window, the spellbook area preview and detail rows, the hotbar options,
// slot drag and side slots, the helper's Follow, Auto sell, exercise weapon, potion gate, line of sight and level-up notice, and the top menu's More sub-menus.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class Phase7XTests
    {
        static object J(string json) => Json.TryParse(json);
        static KeyValuePair<int, int> Sz(int w, int h) => new KeyValuePair<int, int>(w, h);

        public static void Run(Action<bool, string> check)
        {
            Loc.Set("en");
            LayerChecks(check);
            CreateChecks(check);
            SpellAreaChecks(check);
            HotbarChecks(check);
            FollowChecks(check);
            SellChecks(check);
            GateChecks(check);
            SightChecks(check);
            ExerciseChecks(check);
            EngineChecks(check);
            ConfigChecks(check);
            MenuChecks(check);
            TextChecks(check);
            Loc.Set("en");
        }

        // ------------------------------------------------------------------------------------ wings, aura, shader
        static void LayerChecks(Action<bool, string> check)
        {
            Func<int, KeyValuePair<int, int>> size = id => id == 900 ? Sz(1, 1) : id == 901 ? Sz(2, 2) : id == 902 ? Sz(2, 2) : id == 128 ? Sz(1, 1) : Sz(0, 0);
            var plain = OutfitLayers.Plan(new Outfit(128, 1, 2, 3, 4), size, true);
            check(plain.Count == 1 && plain[0].Kind == OutfitLayer.Role.Body && plain[0].DX == 0 && plain[0].DY == 0, "layers: a plain outfit is its body alone, not moved");
            var winged = OutfitLayers.Plan(new Outfit(128, 1, 2, 3, 4) { Wings = 902 }, size, true);
            check(winged.Count == 2 && winged[0].Kind == OutfitLayer.Role.Wings && winged[1].Kind == OutfitLayer.Role.Body, "layers: wings behind the body");
            check(Math.Abs(winged[1].DX + 6f / 32f) < 1e-6 && Math.Abs(winged[1].DY + 6f / 32f) < 1e-6 && winged[0].DX == 0, "layers: a winged body is lifted 6 pixels up and left, the wings stay at the tile");
            var ring = OutfitLayers.Plan(new Outfit(128, 0, 0, 0, 0) { Aura = 900 }, size, true);
            check(ring.Count == 2 && ring[0].Kind == OutfitLayer.Role.Aura && ring[0].DX == 0, "layers: a ring aura sits under the body");
            var tall = OutfitLayers.Plan(new Outfit(128, 0, 0, 0, 0) { Aura = 901 }, size, true);
            check(tall.Count == 1, "layers: a big aura is left out of a card (it would hide the body)");
            var bigOn = OutfitLayers.Plan(new Outfit(128, 0, 0, 0, 0) { Aura = 901 }, size, false);
            check(bigOn.Count == 2 && Math.Abs(bigOn[0].DX - 0.5f) < 1e-6 && Math.Abs(bigOn[0].DY - 0.5f) < 1e-6, "layers: a big aura is moved by (w - 1) * 16 and (h - 1) * 16 pixels");
            var unknown = OutfitLayers.Plan(new Outfit(128, 0, 0, 0, 0) { Wings = 777 }, size, true);
            check(unknown.Count == 1 && unknown[0].DX == 0, "layers: wings the dat does not have are left out and do not lift the body");
            check(OutfitLayers.Plan(new Outfit { LookTypeEx = 5 }, size, true).Count == 0 && OutfitLayers.Plan(null, size, true).Count == 0, "layers: an item look or no outfit draws no layers");
            check(OutfitLayers.SmallAura(1, 1) && !OutfitLayers.SmallAura(1, 2) && !OutfitLayers.SmallAura(2, 1), "layers: a small aura is one tile");

            check(OutfitShaderTint.Of("").None && OutfitShaderTint.Of(null).None, "shader: no name, no tint");
            var frost = OutfitShaderTint.Of("chaos_frost_rime");
            var ember = OutfitShaderTint.Of("chaos_ember_glow");
            check(!frost.None && frost.B > frost.R && ember.R > ember.B, "shader: frost is blue, ember is warm");
            var pulse = OutfitShaderTint.Of("red_energizer");
            check(pulse.Swing > OutfitShaderTint.Of("chaos_holy_radiance").Swing && pulse.Strength(0.4) != pulse.Strength(0.0), "shader: a pulse beats harder than a glow and moves with time");
            var odd = OutfitShaderTint.Of("something_new");
            check(!odd.None && odd.R > 0.9f && odd.Strength(1) >= 0f && odd.Strength(1) <= 1f, "shader: a name with no colour word is a soft gold glow");
            foreach (string n in new[] { "blue_loohs", "bloohs_green", "blue Dortmond", "yellow _energizer", "ember_pixent", "chaos_void_flicker", "chaos_spectral_ghost", "chaos_cinder_crown", "chaos_ash_drift" })
            {
                var t = OutfitShaderTint.Of(n);
                for (double s = 0; s < 3; s += 0.37) { float v = t.Strength(s); if (v < 0f || v > 1f) { check(false, "shader: strength out of range for " + n); return; } }
            }
            check(true, "shader: every shader name gives a strength in 0..1");

            // the merge keeps wings, aura and shader of the website on the list's look (Phase 6 V), and the card draws them
            var list = new Outfit(128, 1, 2, 3, 4);
            var look = new AccountLook { Outfit = new Outfit(128, 9, 9, 9, 9) { Wings = 902, Aura = 900, Shader = "blue_pixent" } };
            var merged = CharCardText.Merge(list, look);
            var plan = OutfitLayers.Plan(merged, size, true);
            check(merged.Head == 1 && plan.Count == 3 && merged.Shader == "blue_pixent", "layers: the merged card look has aura, wings and body, the list's colours, the website's shader");
        }

        // ------------------------------------------------------------------------------------ create window
        const string AccountBlock = "{\"ok\":true,\"token\":\"t1\",\"expiresIn\":1800,\"account\":{\"terms\":true,\"termsUrl\":\"https://x.test/page?plugin=chaos&p=accept\"," +
            "\"slots\":{\"used\":3,\"limit\":5},\"rules\":{\"minL\":3,\"maxL\":20,\"maxW\":3}," +
            "\"classes\":[{\"id\":4,\"name\":\"Warrior\",\"plays\":\"Melee tank\",\"icon\":\"warrior\",\"locked\":false,\"lock\":\"\",\"male\":128,\"female\":136}," +
            "{\"id\":17,\"name\":\"Monk\",\"plays\":\"Fists\",\"icon\":\"monk\",\"locked\":true,\"lock\":\"monk\",\"male\":2050,\"female\":2051}]," +
            "\"season\":{\"id\":3,\"name\":\"Ashfall\",\"tag\":\"S3\",\"endsAt\":0,\"modifier\":\"\",\"modes\":[{\"key\":\"standard\",\"name\":\"Standard\",\"warning\":\"\",\"hc\":false}," +
            "{\"key\":\"hardcore\",\"name\":\"Hardcore\",\"warning\":\"One life.\",\"hc\":true}]}},\"looks\":{}}";

        static void CreateChecks(Action<bool, string> check)
        {
            var a = AccountApi.Parse(AccountBlock);
            var s = a.Create;
            check(a.Ok && s != null && s.Classes.Count == 2 && s.Classes[0].Id == 4 && s.Classes[0].Male == 128 && s.Classes[0].Female == 136 && s.Classes[1].Locked, "create: the login answer's classes, locks and looks are read");
            check(s.Terms && s.MinL == 3 && s.MaxL == 20 && s.MaxW == 3 && s.SeasonId == 3 && s.Modes.Count == 2 && s.Modes[1].Hardcore && s.TermsUrl.StartsWith("https://"), "create: the rules, the Terms and the running season are read");
            check(AccountApi.Parse("{\"ok\":true,\"token\":\"t\"}").Create == null && AccountApi.Parse("nope").Create == null, "create: an answer without an account block has no create state");
            check(CharCreate.FirstOpenClass(s) == 4 && CharCreate.FirstOpenClass(null) == -1 && CharCreate.ClassOf(s, 17).Locked, "create: the first open class is chosen, a locked one is marked");

            check(CharCreate.CheckName("Ana Lu").IsNone && CharCreate.CheckName("Anna").IsNone, "create: good names pass");
            check(CharCreate.CheckName("").Key == "Enter a name." && CharCreate.CheckName("Ana1").Key == "Use letters and spaces only.", "create: an empty name and a digit are refused");
            check(CharCreate.CheckName("Ana  Lu").Key == "Use one space between words." && CharCreate.CheckName("A Lu").Key == "Every word needs at least two letters.", "create: double spaces and one letter words are refused");
            var many = CharCreate.CheckName("Ana Bo Cy Di");
            check(many.Key == "Use at most {0} words." && (int)many.Args[0] == 3, "create: more words than the website allows");
            var shortName = CharCreate.CheckName("Al", 3, 20, 3);
            check(shortName.Key == "The name needs {0} to {1} letters." && CharCreate.CheckName(new string('a', 21)).Key == "The name needs {0} to {1} letters.", "create: the length limits are the website's");
            check(CharCreate.CheckName("  Ana  ").IsNone, "create: spaces around the name are trimmed");

            var seasons = CharCreate.SeasonChoices(s);
            check(seasons.Count == 3 && seasons[0].Season == 0 && seasons[1].Label == "Ashfall S3: Standard" && seasons[2].Hardcore && seasons[2].Mode == "hardcore" && seasons[2].Warning == "One life.", "create: No season first, then a choice per mode");
            check(CharCreate.SeasonChoices(null).Count == 1 && CharCreate.SeasonChoices(new CreateState()).Count == 1, "create: without a running season only No season");

            check(CharCreate.CanCreate(s, "Ana", 4, seasons[0], false, false).IsNone, "create: a name, an open class and no season can be created");
            check(CharCreate.CanCreate(s, "Ana", 17, seasons[0], false, false).Key.StartsWith("{0}: locked"), "create: a locked class cannot");
            check(CharCreate.CanCreate(s, "Ana", -1, seasons[0], false, false).Key == "Choose a class.", "create: no class chosen");
            check(CharCreate.CanCreate(s, "Ana", 4, seasons[2], false, false).Key.StartsWith("Hardcore has one life") && CharCreate.CanCreate(s, "Ana", 4, seasons[2], true, false).IsNone, "create: hardcore needs the tick");
            check(CharCreate.CanCreate(s, "Ana", 4, seasons[0], false, true).Key == "Creating your character..." && CharCreate.CanCreate(null, "Ana", 4, seasons[0], false, false).Key == "Reading your account from the website...", "create: busy and not yet read");
            s.Terms = false;
            check(CharCreate.CanCreate(s, "Ana", 4, seasons[0], false, false).Key.StartsWith("Accept the current Terms"), "create: the Terms must be accepted first");
            s.Terms = true;

            var look = CharCreate.PreviewOutfit(s.Classes[0], 0);
            check(look != null && look.LookType == 136 && look.Head == 78 && look.Body == 68 && look.Legs == 58 && look.Feet == 76 && look.Addons == 3 && CharCreate.PreviewOutfit(s.Classes[0], 1).LookType == 128, "create: the preview is the class look for the sex in the starter colours");
            check(CharCreate.PreviewOutfit(new CreateClass(), 1) == null && CharCreate.LookOf(null, 1) == 0, "create: a class with no look draws nothing");

            bool full;
            check(CharCreate.SlotsLine(3, 5, out full).Key == "Character slots: {0} of {1} used." && !full, "create: the slots line");
            check(CharCreate.SlotsLine(5, 5, out full).Key.StartsWith("No free character slot") && full && CharCreate.SlotsLine(2, -1, out full).IsNone, "create: no free slot, and no limit known");

            string req = CharCreate.CreateRequest("tok", "  Ana Lu ", 4, 0, seasons[2], true, "abc");
            var rj = J(req);
            check(Json.Text(rj, "action") == "create" && Json.Text(rj, "token") == "tok" && Json.Text(rj, "nonce") == "abc" && Json.Text(rj, "name") == "Ana Lu" && Json.Int(rj, "vocation") == 4 && Json.Int(rj, "sex") == 0
                && Json.Int(rj, "season") == 3 && Json.Text(rj, "mode") == "hardcore" && Json.Bool(rj, "hardcore") && Json.Int(rj, "town") == 0, "create: the request carries the fields of the website's create action");
            var noSeason = J(CharCreate.CreateRequest("t", "Ana", 4, 1, seasons[0], false, "n"));
            check(Json.Int(noSeason, "season") == 0 && Json.Text(noSeason, "mode") == "" && !Json.Bool(noSeason, "hardcore"), "create: no season is season 0");

            var ok = CharCreate.ParseCreate("{\"ok\":true,\"name\":\"Ana Lu\",\"message\":\"Created.\",\"look\":{\"type\":128}}");
            check(ok.Ok && ok.Name == "Ana Lu" && ok.Message == "Created.", "create: a good answer");
            var bad = CharCreate.ParseCreate("{\"ok\":false,\"errors\":[\"Name taken.\",\"Name taken.\",\"Bad IP.\"]}");
            check(!bad.Ok && bad.Message == "Name taken.\nBad IP." && !bad.TermsNeeded, "create: errors are one line each, no repeats");
            var terms = CharCreate.ParseCreate("{\"ok\":false,\"error\":\"terms\",\"message\":\"Accept the Terms.\",\"url\":\"https://x.test/accept\"}");
            check(terms.TermsNeeded && terms.Url == "https://x.test/accept" && terms.Message == "Accept the Terms.", "create: the Terms answer carries the accept page");
            check(CharCreate.ParseCreate("<html>").Error == "noanswer" && !CharCreate.ParseCreate("").Ok, "create: an answer that is not JSON is no answer");
        }

        // ------------------------------------------------------------------------------------ spellbook
        static void SpellAreaChecks(Action<bool, string> check)
        {
            var wave = new Spell { Name = "Wave", Target = "front", Element = "fire", Area = new List<List<int>> { new List<int> { 0, 1, 0 }, new List<int> { 1, 1, 1 }, new List<int> { 0, 2, 0 } } };
            var r = SpellArea.Roles(wave);
            check(r.Length == 3 && r[0][1] == AreaRole.Hit && r[0][0] == AreaRole.Empty && r[2][1] == AreaRole.Caster, "spell area: a front spell draws its matrix with you at the 2");
            var round = new Spell { Target = "area", Center = "target", Area = new List<List<int>> { new List<int> { 1, 1, 1 }, new List<int> { 1, 3, 1 }, new List<int> { 1, 1, 1 } } };
            var rr = SpellArea.Roles(round);
            check(rr[1][1] == AreaRole.TargetHit && SpellArea.HasTargetHit(rr), "spell area: an area centred on the target marks the target, hit with a 3");
            var tgt = new Spell { Target = "area", Center = "target", Area = new List<List<int>> { new List<int> { 2 } } };
            check(SpellArea.Roles(tgt)[0][0] == AreaRole.Target && !SpellArea.HasTargetHit(SpellArea.Roles(tgt)), "spell area: a 2 on a target centre is the target, not hit");
            var onYou = new Spell { Target = "area", Center = "caster", Area = new List<List<int>> { new List<int> { 1, 3, 1 } } };
            check(SpellArea.Roles(onYou)[0][1] == AreaRole.Caster, "spell area: an area centred on you shows you");
            var bolt = new Spell { Target = "single", Range = 3 };
            var br = SpellArea.Roles(bolt);
            check(br.Length == 4 && br[0][0] == AreaRole.TargetHit && br[1][0] == AreaRole.Empty && br[3][0] == AreaRole.Caster, "spell area: a single target shows the target at its range and you below");
            check(SpellArea.Roles(new Spell { Target = "single", Range = 40 }).Length == SpellArea.MaxSingleRange + 1 && SpellArea.Roles(new Spell { Target = "single", Range = 0 }).Length == 2, "spell area: the range is kept between 1 and 5");
            var self = SpellArea.Roles(new Spell { Target = "self" });
            check(self.Length == 1 && self[0].Length == 1 && self[0][0] == AreaRole.Caster && SpellArea.Roles(null)[0][0] == AreaRole.Caster, "spell area: a self spell is only you");
            check(SpellArea.Roles(new Spell { Target = "area" })[0][0] == AreaRole.Caster, "spell area: an area spell without a matrix is only you");
            check(SpellArea.Columns(r) == 3 && SpellArea.CellSize(r, 160, 100) == SpellArea.MaxCell && SpellArea.CellSize(r, 20, 20) == SpellArea.MinCell, "spell area: the cell is kept between 5 and 14 pixels");
            int arg;
            check(SpellArea.Note(wave, out arg) == "Cast facing north (up)." && SpellArea.Note(round, out arg) == "Centred on the target." && SpellArea.Note(onYou, out arg) == "Centred on you.", "spell area: the notes");
            check(SpellArea.Note(bolt, out arg) == "One target, range {0}." && arg == 3 && SpellArea.Note(new Spell { Target = "single" }, out arg) == "One target." && SpellArea.Note(new Spell { Target = "self" }, out arg) == "Affects only you.", "spell area: single target and self notes");
            check(SpellArea.HitCells(round) == 9 && SpellArea.HitCells(wave) == 4, "spell area: hit cells count the 1s and 3s");

            var names = new Dictionary<int, string> { { 0, "None" }, { 4, "Warrior" }, { 3, "Ranger" }, { 11, "Master Sorcerer" }, { 14, "Berserker" } };
            check(SpellDetails.Initials("Master Sorcerer") == "MS" && SpellDetails.Initials("Berserker") == "Ber" && SpellDetails.Initials("Elementalist") == "Ele" && SpellDetails.Initials("X") == "X", "spell details: initials, three letters for one word");
            check(SpellDetails.Seconds(0) == "-" && SpellDetails.Seconds(4000) == "4s" && SpellDetails.Seconds(2500) == "2.5s", "spell details: seconds");
            var everyone = SpellDetails.Vocations(new Spell(), names);
            check(everyone.Value == "Everyone" && everyone.Translate, "spell details: no vocations means everyone");
            var two = SpellDetails.Vocations(new Spell { Vocations = { 14, 4 } }, names);
            check(two.Value == "Wa, Ber".Replace("Wa", "War") && two.Tip == "Warrior, Berserker", "spell details: sorted initials and full names: " + two.Value);
            var all = SpellDetails.Vocations(new Spell { Vocations = { 4, 3, 11, 14 } }, names);
            check(all.Value == "Every class" && all.Translate, "spell details: every named class listed is Every class");
            var most = SpellDetails.Vocations(new Spell { Vocations = { 4, 3, 11 } }, names);
            check(most.Value == "Ran, War, MS" && !most.Translate && most.Tip == "Ranger, Warrior, Master Sorcerer", "spell details: three or fewer show their initials: " + most.Value);
            var four = SpellDetails.Vocations(new Spell { Vocations = { 3, 4, 11, 99 } }, names);
            check(four.Value == "4 classes" && four.Translate == false && four.Tip.EndsWith("#99"), "spell details: more than three with a named class missing show the count");
            var rows = SpellDetails.Rows(new Spell { Soul = 1, Group = 1, Type = "damage", Element = "fire", Target = "front", Scaling = "distance skill x weapon attack" }, names);
            check(rows.Count == 7 && rows[0].Key == "Soul" && rows[1].Value == "Attack" && rows[2].Value == "Damage" && rows[3].Value == "Fire" && rows[4].Value == "Area in front" && rows[5].Value == "dist. x weapon" && rows[5].Tip.StartsWith("distance"), "spell details: the stat rows after mana and cooldown");
            var bare = SpellDetails.Rows(new Spell(), names);
            check(bare.Count == 5 && bare[0].Key == "Group" && bare[0].Value == "-" && !bare[0].Translate && bare[3].Value == "-", "spell details: a spell with no data shows dashes and no Soul or Scales row");
        }

        // ------------------------------------------------------------------------------------ hotbar
        static void HotbarChecks(Action<bool, string> check)
        {
            check(HotbarOptions.ClampCount(7) == 6 || HotbarOptions.ClampCount(7) == 8, "hotbar: the count is one of 6, 8, 10, 12");
            check(HotbarOptions.ClampCount(9.1) == 10 && HotbarOptions.ClampCount(100) == 12 && HotbarOptions.ClampCount(double.NaN) == 12 && HotbarOptions.ClampCount(1) == 6, "hotbar: the nearest allowed count");
            check(HotbarOptions.ClampScale(101) == 100 && HotbarOptions.ClampScale(40) == 75 && HotbarOptions.ClampScale(300) == 125 && HotbarOptions.ClampScale(double.NaN) == 100 && HotbarOptions.ClampScale(112) == 110, "hotbar: the scale is a step of 5 between 75 and 125");
            var o = HotbarOptions.Parse("8|120");
            check(o.Count == 8 && o.Scale == 120 && o.Encode() == "8|120", "hotbar: options round trip");
            var d = HotbarOptions.Parse("");
            check(d.Count == 12 && d.Scale == 100 && HotbarOptions.Parse("x|y").Count == 12 && HotbarOptions.Parse("6").Scale == 100, "hotbar: a missing or bad save gives the defaults (twelve slots, as before)");

            var m = HotbarLayout.Metrics(12, 100);
            check(m.SlotW == 34 && m.SlotH == 40 && m.Gap == 2 && m.Pitch == 36 && m.Width == 2 * 4 + 2 * (34 + 6) + 12 * 34 + 11 * 2, "hotbar: the metrics at 100 percent keep the old pitch of 36");
            var big = HotbarLayout.Metrics(12, 125);
            check(big.Width > m.Width && big.SlotH == 50 && HotbarLayout.Metrics(6, 100).Width < m.Width, "hotbar: a larger scale and more slots are wider");
            bool cut;
            var fit = HotbarLayout.Fit(new HotbarOptions { Count = 12, Scale = 125 }, 400, out cut);
            check(cut && fit.Width <= 400 && fit.Scale >= 60, "hotbar: a narrow screen shrinks the scale first");
            var fit2 = HotbarLayout.Fit(new HotbarOptions { Count = 12, Scale = 100 }, 300, out cut);
            check(cut && fit2.Width <= 300 && fit2.Count < 12 && fit2.Count >= 4 && fit2.Scale == 60, "hotbar: then it drops slots by two (never under four)");
            var none = HotbarLayout.Fit(new HotbarOptions { Count = 12, Scale = 100 }, 10, out cut);
            check(none.Count == 4 && none.Scale == 60, "hotbar: a window too small for anything still keeps four slots at 60 percent");
            var wide = HotbarLayout.Fit(new HotbarOptions { Count = 8, Scale = 100 }, 2000, out cut);
            check(!cut && wide.Count == 8 && wide.Scale == 100, "hotbar: a wide screen cuts nothing");

            check(HotbarLayout.Shown(6).Count == 6 && HotbarLayout.Shown(12).Count == 12 && HotbarLayout.Shown(12)[11] == 11 && !HotbarLayout.Shown(12).Contains(12), "hotbar: the row shows count slots, the sockets are drawn apart");
            check(HotbarLayout.KeyLabel(0) == "F1" && HotbarLayout.KeyLabel(11) == "F12" && HotbarLayout.KeyLabel(12) == "Q" && HotbarLayout.KeyLabel(13) == "E" && HotbarLayout.KeyLabel(14) == "", "hotbar: key labels, Q and E for the sockets");
            check(HotbarLayout.SlotOfKey("F1") == 0 && HotbarLayout.SlotOfKey("F12") == 11 && HotbarLayout.SlotOfKey("Q") == 12 && HotbarLayout.SlotOfKey("E") == 13 && HotbarLayout.SlotOfKey("F13") == -1 && HotbarLayout.SlotOfKey("W") == -1 && HotbarLayout.SlotOfKey(null) == -1, "hotbar: keys press their slots");
            double qx = HotbarLayout.SlotX(m, 12), ex = HotbarLayout.SlotX(m, 13), f1 = HotbarLayout.SlotX(m, 0), f12 = HotbarLayout.SlotX(m, 11);
            check(qx < f1 && ex > f12 && f1 - (qx + m.SideW) == m.SideGap && ex - (f12 + m.SlotW) == m.SideGap, "hotbar: Q left of the row, E right of it, a gap of 6");
            check(HotbarLayout.SlotAt(m, f1 + 3, 5, 0) == 0 && HotbarLayout.SlotAt(m, qx + 3, 5, 0) == 12 && HotbarLayout.SlotAt(m, ex + 3, 5, 0) == 13 && HotbarLayout.SlotAt(m, f12 + 3, 5, 0) == 11, "hotbar: a point finds its slot");
            check(HotbarLayout.SlotAt(m, f1 + 3, 45, 0) == -1 && HotbarLayout.SlotAt(m, f1 + m.SlotW + 1, 5, 0) == -1 && HotbarLayout.SlotAt(m, 0, 5, 0) == -1, "hotbar: the gap, the margin and below the slots are no slot");

            // drag from slot to slot, the side slots, saving
            var bar = new HotbarModel();
            bar.SetText(0, "exura"); bar.SetItem(3, 3160, true); bar.SetMode(3, ItemMode.OnTarget);
            check(bar.Swap(0, 5) && bar[0].IsEmpty && bar[5].Text == "exura", "hotbar drag: a slot dropped on an empty one moves");
            check(bar.Swap(5, 3) && bar[5].Kind == HotKind.Item && bar[5].Mode == ItemMode.OnTarget && bar[3].Text == "exura", "hotbar drag: dropped on a filled slot they swap, the item keeps its mode");
            check(!bar.Swap(3, 3) && !bar.Swap(-1, 2) && !bar.Swap(2, 14) && !bar.Swap(14, 2) && bar[3].Text == "exura", "hotbar drag: the same slot or a bad slot changes nothing");
            check(bar.SetItem(HotbarModel.SideQ, 2874, false) && bar.SetText(HotbarModel.SideE, "utani hur") && bar[12].ItemId == 2874 && bar[13].Text == "utani hur", "hotbar: the side slots hold an item or a line");
            check(bar.Swap(2, 12) && bar[2].ItemId == 2874 && bar[12].IsEmpty, "hotbar drag: a row slot moves to a socket and back");
            check(bar.FirstEmpty() == 0 && HotbarModel.Total == 14, "hotbar: the first empty slot is in the main row");
            var saved = new string[14];
            for (int i = 0; i < 14; i++) saved[i] = bar.Saved(i);
            var again = new HotbarModel();
            again.Load(i => saved[i]);
            bool same = true;
            for (int i = 0; i < 14; i++) same &= again[i].Kind == bar[i].Kind && again[i].Text == bar[i].Text && again[i].ItemId == bar[i].ItemId && again[i].Mode == bar[i].Mode;
            check(same && again[13].Text == "utani hur", "hotbar: all fourteen slots save and load");
            var old = new HotbarModel();
            old.Load(i => i < 12 ? "line " + i : "");
            check(old[11].Text == "line 11" && old[12].IsEmpty && old[13].IsEmpty, "hotbar: a bar saved with twelve slots loads with empty sockets");
            old.Clear();
            check(old[0].IsEmpty && old[13].IsEmpty, "hotbar: Clear clears the sockets too");
        }

        // ------------------------------------------------------------------------------------ follow
        static HelperPlayer Pl(uint id, string name, int x, int y, int shield = 0, bool self = false, int z = 7) => new HelperPlayer { Id = id, Name = name, Position = new Pos(x, y, z), Shield = shield, IsSelf = self };

        static void FollowChecks(Action<bool, string> check)
        {
            var me = new Pos(100, 100, 7);
            var cfg = new HelperFollowCfg { Enabled = true, Mode = "name", Name = "Bob Ross", Distance = 1 };
            var players = new List<HelperPlayer> { Pl(1, "Me", 100, 100, 0, true), Pl(2, "Ann", 101, 100), Pl(3, "bob ross", 103, 100, 4) };
            var leader = HelperFollow.LeaderOf(cfg, players);
            check(leader != null && leader.Id == 3, "follow: the friend is found by name, any case");
            cfg.Mode = "leader";
            check(HelperFollow.LeaderOf(cfg, players).Id == 3, "follow: the party leader is the player with the leader shield");
            players[2].Shield = 3;   // a member, not the leader
            check(HelperFollow.LeaderOf(cfg, players) == null, "follow: a party member is not the leader");
            cfg.Mode = "name"; cfg.Name = "";
            check(HelperFollow.LeaderOf(cfg, players) == null && HelperFollow.LeaderOf(null, players) == null && HelperFollow.LeaderOf(cfg, null) == null, "follow: no name, no cfg, no players give no leader");
            check(HelperFollow.LeaderOf(new HelperFollowCfg { Mode = "name", Name = "Me" }, players) == null, "follow: you are never your own leader");
            cfg.Name = "Bob Ross"; players[2].Shield = 0;
            leader = HelperFollow.LeaderOf(cfg, players);

            var st = new FollowState();
            Func<HelperPlayer, uint, double, bool, string> go = (l, following, now, pz) => HelperFollow.Decide(cfg, st, new FollowInput { HelperOn = true, Pz = pz, Leader = l, From = me, Following = following, Now = now }, out string _w);
            string why;
            check(HelperFollow.Decide(cfg, st, new FollowInput { HelperOn = true, Leader = leader, From = me, Now = 1000 }, out why) == "follow" && why == "ask", "follow: a leader three tiles away is followed");
            check(HelperFollow.Decide(cfg, st, new FollowInput { HelperOn = true, Leader = leader, From = me, Now = 1100 }, out why) == null && why == "gap", "follow: not asked again within 250 ms");
            check(HelperFollow.Decide(cfg, st, new FollowInput { HelperOn = true, Leader = leader, From = me, Following = 3, Now = 1400 }, out why) == null && why == "following", "follow: already following the leader: nothing to do");
            check(HelperFollow.Decide(cfg, st, new FollowInput { HelperOn = true, Leader = null, From = me, Following = 3, Now = 1700 }, out why) == "release" && why == "away", "follow: the leader out of view releases the helper's own follow");
            var st2 = new FollowState();
            check(HelperFollow.Decide(cfg, st2, new FollowInput { HelperOn = true, Leader = leader, From = me, Following = 9, Now = 0 }, out why) == null && why == "other", "follow: a follow the player chose by hand is left alone");
            var next = Pl(3, "Bob Ross", 101, 100);
            var st3 = new FollowState();
            check(HelperFollow.Decide(cfg, st3, new FollowInput { HelperOn = true, Leader = next, From = me, Now = 0 }, out why) == null && why == "adjacent", "follow: next to the leader there is no need");
            check(HelperFollow.Decide(cfg, st3, new FollowInput { HelperOn = true, Pz = true, Leader = leader, From = me, Now = 0 }, out why) == null && why == "pz", "follow: a protection zone does nothing");
            check(HelperFollow.Decide(cfg, st3, new FollowInput { HelperOn = false, Leader = leader, From = me, Now = 0 }, out why) == null && why == "helperoff", "follow: the helper off does nothing");
            var otherFloor = Pl(3, "Bob Ross", 103, 100, 0, false, 8);
            check(HelperFollow.Decide(cfg, st3, new FollowInput { HelperOn = true, Leader = otherFloor, From = me, Now = 0 }, out why) == null && why == "away", "follow: another floor is out of reach");
            var farAway = Pl(3, "Bob Ross", 140, 100);
            check(HelperFollow.Decide(cfg, st3, new FollowInput { HelperOn = true, Leader = farAway, From = me, Now = 0 }, out why) == null && why == "away", "follow: beyond the window is out of view");

            // a leader behind a wall: five asks in a row that start no follow, then a rest of five seconds
            var st4 = new FollowState();
            int asks = 0; double t = 0;
            for (int i = 0; i < 12; i++, t += 300) if (HelperFollow.Decide(cfg, st4, new FollowInput { HelperOn = true, Leader = leader, From = me, Now = t }, out why) == "follow") asks++;
            check(asks == 5 && st4.HoldUntil > 0, "follow: five asks that start no follow, then it gives up for a while (asks " + asks + ")");
            check(HelperFollow.Decide(cfg, st4, new FollowInput { HelperOn = true, Leader = leader, From = me, Now = t + 100 }, out why) == null && why == "retry", "follow: during the rest nothing is asked");
            check(HelperFollow.Decide(cfg, st4, new FollowInput { HelperOn = true, Leader = leader, From = me, Now = st4.HoldUntil + 10 }, out why) == "follow", "follow: after the rest it asks again");

            // distance 3: close enough lets go, one tile farther takes it up again
            cfg.Distance = 3;
            var st5 = new FollowState();
            var near = Pl(3, "Bob Ross", 102, 100);
            check(HelperFollow.Decide(cfg, st5, new FollowInput { HelperOn = true, Leader = near, From = me, Following = 3, Now = 0 }, out why) == "release" && why == "near", "follow: at the chosen distance the follow is let go");
            check(HelperFollow.Decide(cfg, st5, new FollowInput { HelperOn = true, Leader = Pl(3, "Bob Ross", 104, 100), From = me, Now = 10 }, out why) == null && why == "near", "follow: one tile farther than that it waits (no flapping)");
            check(HelperFollow.Decide(cfg, st5, new FollowInput { HelperOn = true, Leader = Pl(3, "Bob Ross", 105, 100), From = me, Now = 20 }, out why) == "follow", "follow: two farther it follows again");
            cfg.Enabled = false;
            var st6 = new FollowState { Ours = true };
            check(HelperFollow.Decide(cfg, st6, new FollowInput { HelperOn = true, Leader = leader, From = me, Following = 3, Now = 0 }, out why) == "release" && why == "off", "follow: switching it off lets the helper's own follow go");
            check(HelperFollow.Decide(cfg, st6, new FollowInput { HelperOn = true, Leader = leader, From = me, Following = 3, Now = 0 }, out why) == null, "follow: and only once");
            check(go(leader, 0, 0, false) == null, "follow: off does nothing");
        }

        // ------------------------------------------------------------------------------------ auto sell
        static void SellChecks(Action<bool, string> check)
        {
            var cfg = new HelperSellCfg { Enabled = true, Interval = 5, BelowCap = false, Capacity = 100 };
            var st = new SellState();
            string why;
            check(HelperSell.Decide(new HelperSellCfg(), st, default(SellerView), 0, 500, true, out why) == null && why == "off", "sell: off does nothing");
            check(HelperSell.Decide(cfg, st, default(SellerView), 0, 500, false, out why) == null && why == "helperoff", "sell: helper off does nothing");
            check(HelperSell.Decide(cfg, st, default(SellerView), 0, 500, true, out why) == "sync" && why == "unknown", "sell: without the seller's state it asks the server");
            check(HelperSell.Decide(cfg, st, default(SellerView), 5000, 500, true, out why) == null, "sell: and not again within ten seconds");
            check(HelperSell.Decide(cfg, st, default(SellerView), 10000, 500, true, out why) == "sync", "sell: but after ten");
            var locked = new SellerView { Known = true, Unlocked = false };
            check(HelperSell.Decide(cfg, st, locked, 20000, 500, true, out why) == null && why == "locked", "sell: a locked seller waits (it may be bought a moment later)");
            check(HelperSell.Decide(cfg, st, locked, 10000 + HelperSell.StateStaleMs + 1, 500, true, out why) == "sync" && why == "locked", "sell: and looks again after five minutes");
            var ready = new SellerView { Known = true, Unlocked = true, Cooldown = 0 };
            var st2 = new SellState();
            check(HelperSell.Decide(cfg, st2, ready, 1000, 500, true, out why) == null && why == "wait", "sell: the first look at the state starts the count, no sale at the login");
            check(HelperSell.Decide(cfg, st2, ready, 1000 + 4 * 60000, 500, true, out why) == null, "sell: four minutes of five is too soon");
            check(HelperSell.Decide(cfg, st2, ready, 1000 + 5 * 60000, 500, true, out why) == "sell" && why == "timer", "sell: after the interval it asks");
            check(HelperSell.Decide(cfg, st2, ready, 1000 + 5 * 60000 + 1000, 500, true, out why) == null && why == "gap", "sell: never two asks within the server's cooldown");
            check(HelperSell.Decide(cfg, st2, new SellerView { Known = true, Unlocked = true, Cooldown = 12 }, 1000 + 12 * 60000, 500, true, out why) == null && why == "cooldown", "sell: the server's cooldown holds it");
            check(HelperSell.Decide(cfg, st2, ready, 1000 + 10 * 60000 + 2000, 500, true, out why) == "sell", "sell: the next interval counts from the last ask");
            cfg.BelowCap = true; cfg.Interval = 60;
            var st3 = new SellState();
            HelperSell.Decide(cfg, st3, ready, 0, 500, true, out why);
            check(HelperSell.Decide(cfg, st3, ready, 1000, 90, true, out why) == "sell" && why == "capacity", "sell: low capacity asks before the timer");
            check(HelperSell.Decide(cfg, st3, ready, 40000, 90, true, out why) == null, "sell: and not again within the 31 second gap");
            check(HelperSell.Decide(cfg, st3, ready, 1000 + 61000, 90, true, out why) == "sell" && why == "capacity", "sell: low capacity asks at most once a minute");
            check(HelperSell.Decide(cfg, new SellState { LastAsk = -1, Start = 0 }, ready, 1000, 500, true, out why) == null, "sell: plenty of capacity waits for the timer");
            check(HelperSellCfg.MinutesOf(30) == 30 && HelperSellCfg.MinutesOf(7) == -1, "sell: only the five intervals");
        }

        // ------------------------------------------------------------------------------------ potion gate
        static void GateChecks(Action<bool, string> check)
        {
            var g = new PotionGate();
            check(g.Allowed(100, 0, 3), "gate: a counted potion is allowed");
            check(g.Allowed(100, 0, 0), "gate: an uncounted potion is probed at once");
            g.Used(100, 0, 0);
            check(!g.Allowed(100, 1000, 0) && g.Allowed(100, 3000, 0), "gate: and again every three seconds");
            check(g.OnText("Using an everfull mana potion (never runs out).", 500) && g.Allowed(100, 600, 0), "gate: a Using answer says it is there, it is used like a counted one");
            g.Used(100, 600, 0);
            check(g.Allowed(100, 700, 0), "gate: found items are not probed again by the clock");
            check(g.OnText("Sorry, not possible.", 800) && !g.Allowed(100, 900, 0), "gate: a failure holds it while the answer settles");
            check(!g.Allowed(100, 1200, 0), "gate: still unsettled at 400 ms");
            check(!g.Allowed(100, 1400, 0) && !g.Allowed(100, 20000, 0) && g.Allowed(100, 800 + PotionGate.BackoffMs + 10, 0), "gate: a settled failure backs off for thirty seconds");
            // a spell's refusal never counts
            var g2 = new PotionGate();
            g2.Used(5, 0, 0);
            check(!g2.OnText("You do not have enough mana.", 100) && !g2.OnText("You are exhausted.", 100), "gate: a spell refusal is not a probe's answer");
            check(g2.OnText("Using one of 12 mana potions...", 200) && g2.Allowed(5, 250, 0), "gate: the probe's own Using answer still counts");
            // the "Using" that follows a failure takes it back
            var g3 = new PotionGate();
            g3.Used(7, 0, 0);
            g3.OnText("Sorry, not possible.", 100);
            check(g3.OnText("Using the last health potion.", 300) && g3.Allowed(7, 400, 0), "gate: a Using within 500 ms of a failure takes the failure back");
            // an answer after the reply window answers nothing
            var g4 = new PotionGate();
            g4.Used(9, 0, 0);
            check(!g4.OnText("Using a potion", 5000) && !g4.OnText("Sorry, not possible.", 5000), "gate: a text after 1.5 seconds answers no probe");
            // a probe of another item: the oldest unanswered one gets the text
            var g5 = new PotionGate();
            g5.Used(1, 0, 0); g5.Used(2, 100, 0);
            g5.OnText("Using a rune.", 300);
            check(g5.Allowed(1, 400, 0) && !g5.Allowed(2, 400, 0), "gate: the oldest unanswered probe takes the answer");
            g5.Reset();
            check(g5.Allowed(1, 0, 0) && g5.Allowed(2, 0, 0), "gate: Reset forgets everything");
        }

        // ------------------------------------------------------------------------------------ line of sight
        static void SightChecks(Action<bool, string> check)
        {
            var a = new Pos(10, 10, 7);
            var line = SightLine.Between(a, new Pos(14, 10, 7));
            check(line.Count == 3 && line[0].X == 11 && line[2].X == 13 && line.All(p => p.Y == 10), "sight: the tiles between two on a row");
            check(SightLine.Between(a, a).Count == 0 && SightLine.Between(a, new Pos(11, 10, 7)).Count == 0, "sight: no tiles between a tile and itself or its neighbour");
            var diag = SightLine.Between(a, new Pos(13, 13, 7));
            check(diag.Count == 2 && diag[0].X == 11 && diag[0].Y == 11 && diag[1].X == 12 && diag[1].Y == 12, "sight: a diagonal");
            var knight = SightLine.Between(a, new Pos(14, 12, 7));
            check(knight.Count == 3 && knight.All(p => p.X > 10 && p.X < 14), "sight: a slanted line steps along the long axis");
            check(SightLine.Clear(a, new Pos(14, 10, 7), p => false) && !SightLine.Clear(a, new Pos(14, 10, 7), p => p.X == 12), "sight: a blocking tile on the line ends it");
            check(SightLine.Clear(a, new Pos(14, 10, 7), p => p.X == 14 || p.X == 10), "sight: the end tiles never block");
            check(!SightLine.Clear(a, new Pos(14, 10, 8), p => false), "sight: another floor is never in sight");
            check(SightLine.Clear(new Pos(14, 10, 7), a, p => false) && SightLine.Between(new Pos(14, 12, 7), a).Count == 3, "sight: the other way round");
            // the helper's checks use it: an ally behind a wall is not healed, and an area does not count a monster behind one
            var allies = new HelperAllies { PartyEnabled = true, PartyPercent = 70 };
            var hurt = new List<HelperPlayer> { new HelperPlayer { Id = 2, Name = "Ann", Health = 30, Position = new Pos(14, 10, 7), Shield = 3 } };
            check(HelperAlly.Candidates(allies, hurt, a, (x, y) => SightLine.Clear(x, y, p => p.X == 12)).Count == 0 && HelperAlly.Candidates(allies, hurt, a, (x, y) => SightLine.Clear(x, y, p => false)).Count == 1, "sight: an ally behind a wall is not a heal candidate");
            var mons = new List<HelperCreature> { new HelperCreature(5, new Pos(13, 10, 7), 100) };
            var row = new[] { new[] { 1, 1, 1, 1, 1 } };
            check(HelperLogic.CountHits(a, Dir.East, row, mons, false, (x, y) => SightLine.Clear(x, y, p => p.X == 12)) == 0, "sight: a wave does not count a monster behind a wall (the line is blocked)");
            // on a world: a tile with a missile blocker (a thing with BlockMissile) blocks, an unknown tile does not
            var w = new World(DatFile.Parse(Program.SyntheticDat()));
            check(SightLine.Clear(w, a, new Pos(14, 10, 7)), "sight: tiles the client does not know do not block");
            check(!SightLine.Clear(w, a, new Pos(10, 10, 6)), "sight: a world also refuses another floor");
        }

        // ------------------------------------------------------------------------------------ exercise weapons
        static void ExerciseChecks(Action<bool, string> check)
        {
            var carry = new Dictionary<int, int> { { 27734, 1 }, { 27736, 1 } };
            Func<int, int> have = id => carry.TryGetValue(id, out int n) ? n : 0;
            check(HelperExercise.PickWeapon(0, have) == 27734, "exercise: any weapon picks the first of the list that you carry");
            check(HelperExercise.PickWeapon(27736, have) == 27736 && HelperExercise.PickWeapon(27732, have) == 0, "exercise: a chosen weapon must be carried");
            carry.Clear();
            check(HelperExercise.PickWeapon(0, have) == 0, "exercise: none carried, none used");
            check(HelperExercise.Weapons.Length == 8 && HelperExercise.Weapons[0].Key == 27732 && HelperExercise.Dummies.SequenceEqual(new[] { 27751, 27752 }), "exercise: the eight weapons and two dummies of the server");
            var me = new Pos(50, 50, 7);
            var dummies = new List<KeyValuePair<Pos, int>> { new KeyValuePair<Pos, int>(new Pos(53, 50, 7), 27751), new KeyValuePair<Pos, int>(new Pos(51, 52, 7), 27752), new KeyValuePair<Pos, int>(new Pos(50, 51, 8), 27751) };
            Pos at; int id;
            check(HelperExercise.Nearest(me, dummies, null, out at, out id) && at.X == 51 && id == 27752, "exercise: the nearest dummy on your floor");
            check(HelperExercise.Nearest(me, dummies, (p, q) => p.X != 51, out at, out id) && at.X == 53 && id == 27751, "exercise: a dummy with no clear line is skipped");
            check(!HelperExercise.Nearest(me, dummies, (p, q) => false, out at, out id) && id == 0, "exercise: none in sight, none used");
            check(!HelperExercise.Nearest(me, new List<KeyValuePair<Pos, int>>(), null, out at, out id), "exercise: no dummies");
            var cfg = new HelperExerciseCfg { Enabled = true };
            check(HelperExercise.Due(cfg, true, 2000) && !HelperExercise.Due(cfg, true, 1999) && !HelperExercise.Due(cfg, false, 9999) && !HelperExercise.Due(new HelperExerciseCfg(), true, 9999) && !HelperExercise.Due(null, true, 9999), "exercise: only in a protection zone, standing still for two seconds, switched on");
        }

        // ------------------------------------------------------------------------------------ the engine on a fake game
        sealed class Host : IHelperHost, IHelperHostExt, IHelperHostP7
        {
            public double Now { get; set; }
            public int Health { get; set; } = 100;
            public int MaxHealth { get; set; } = 100;
            public int Mana { get; set; } = 500;
            public int MaxMana { get; set; } = 500;
            public int Level { get; set; } = 100;
            public Pos Position { get; set; } = new Pos(100, 100, 7);
            public Dir Facing { get; set; } = Dir.North;
            public bool InProtectionZone { get; set; }
            public bool Hasted { get; set; }
            public uint AttackTarget { get; set; }
            public bool Following => FollowTarget != 0;
            public double MsSinceLastRead { get; set; }
            public int Vocation { get; set; } = 4;
            public bool Hungry { get; set; }
            public List<HelperPlayer> People = new List<HelperPlayer>();
            public List<string> Log = new List<string>(), Said = new List<string>();
            public Dictionary<int, int> Items = new Dictionary<int, int>();
            public IList<HelperCreature> Monsters() { return new List<HelperCreature>(); }
            public void Say(string words) { Said.Add(words); }
            public void Attack(uint id) { AttackTarget = id; }
            public void CancelAttack() { AttackTarget = 0; }
            public void Turn(Dir d) { Facing = d; }
            public int ItemCount(int id) { int n; return Items.TryGetValue(id, out n) ? n : 0; }
            public void UseOnSelf(int id) { Log.Add("self " + id); Items[id]--; }
            public IList<HelperPlayer> Players() { return People; }
            public bool UseOnCreature(int id, uint c) { if (ItemCount(id) <= 0) return false; Log.Add("on " + id + " " + c); Items[id]--; return true; }
            public bool UseItem(int id) { if (ItemCount(id) <= 0) return false; Log.Add("eat " + id); Items[id]--; return true; }
            public IList<string> OwnSummons() { return new List<string>(); }
            // P7
            public uint FollowTarget { get; set; }
            public void Follow(uint id) { FollowTarget = id; Log.Add("follow " + id); }
            public void CancelFollow() { FollowTarget = 0; Log.Add("unfollow"); }
            public bool SightClear(Pos a, Pos b) { return true; }
            public double IdleMs { get; set; } = 5000;
            public List<KeyValuePair<Pos, int>> Dummies = new List<KeyValuePair<Pos, int>>();
            public IList<KeyValuePair<Pos, int>> MapItems(int[] ids, int radius) { return Dummies; }
            public bool UseWithMapItem(int id, Pos at, int mapItem) { Log.Add("with " + id + " " + at.X + " " + mapItem); return true; }
            public bool UseByIdOnCreature(int id, uint c) { Log.Add("byid " + id + " " + c); return true; }
            public SellerView Seller { get; set; }
            public void SellerSync() { Log.Add("sync"); }
            public void SellerSell() { Log.Add("sell"); }
            public double FreeCapacity { get; set; } = 500;
        }

        static void Run(HelperEngine e, Host h, double from, double to, double step = 50)
        {
            for (double t = from; t <= to; t += step) { h.Now = t; e.Tick(); }
        }

        static HelperEngine Make(Host host, params Spell[] spells)
        {
            var book = new SpellBook(new ExtOpcodes()) { Clock = () => host.Now };
            foreach (var s in spells) book.Spells.Add(s);
            var e = new HelperEngine(book, host);
            e.Config.Enabled = true;
            return e;
        }

        static void EngineChecks(Action<bool, string> check)
        {
            // follow: the engine asks the host to follow the leader and pauses the fight while it does
            var h = new Host();
            h.People.Add(Pl(1, "Me", 100, 100, 0, true)); h.People.Add(Pl(2, "Bob Ross", 104, 100, 4));
            var e = Make(h);
            e.Config.Follow = new HelperFollowCfg { Enabled = true, Mode = "name", Name = "Bob Ross", Distance = 1 };
            Run(e, h, 1000, 1300);
            check(h.Log.Contains("follow 2") && h.FollowTarget == 2 && e.FollowAsks >= 1, "engine follow: the leader is followed (" + string.Join(",", h.Log) + ")");
            check(e.FollowWhy == "following", "engine follow: the status says following");
            h.Log.Clear();
            h.People.RemoveAt(1);
            Run(e, h, 1350, 1700);
            check(h.Log.Contains("unfollow") && h.FollowTarget == 0, "engine follow: the leader out of view releases the follow");
            e.Config.Enabled = false; h.Log.Clear(); h.People.Add(Pl(2, "Bob Ross", 104, 100));
            Run(e, h, 1800, 2200);
            check(!h.Log.Contains("follow 2") && e.FollowWhy == "helperoff", "engine follow: a helper that is off follows nobody");

            // auto sell
            var hs = new Host { Seller = new SellerView { Known = true, Unlocked = true } };
            var es = Make(hs);
            es.Config.Sell = new HelperSellCfg { Enabled = true, Interval = 5, BelowCap = true, Capacity = 100 };
            Run(es, hs, 1000, 1200, 250);
            check(hs.Log.Count == 0, "engine sell: nothing at the first look");
            hs.FreeCapacity = 40;
            Run(es, hs, 2000, 2500, 250);
            check(hs.Log.Contains("sell") && es.SellAsks == 1, "engine sell: low capacity asks the Auto Seller");
            hs.Log.Clear();
            var hu = new Host { Seller = default(SellerView) };
            var eu = Make(hu);
            eu.Config.Sell = new HelperSellCfg { Enabled = true };
            Run(eu, hu, 0, 1500, 250);
            check(hu.Log.Contains("sync") && !hu.Log.Contains("sell"), "engine sell: an unknown seller is asked about its state first");

            // exercise weapon
            var hx = new Host { InProtectionZone = true, IdleMs = 3000 };
            hx.Items[27734] = 1;
            hx.Dummies.Add(new KeyValuePair<Pos, int>(new Pos(102, 100, 7), 27751));
            var ex = Make(hx);
            ex.Config.Exercise = new HelperExerciseCfg { Enabled = true, Id = 0 };
            Run(ex, hx, 0, 600, 250);
            check(hx.Log.Contains("with 27734 102 27751") && ex.ExerciseUses == 1, "engine exercise: the weapon is used on the dummy (" + string.Join(",", hx.Log) + ")");
            hx.Log.Clear(); hx.IdleMs = 100;
            Run(ex, hx, 11000, 11500, 250);
            check(hx.Log.Count == 0, "engine exercise: not while the character moves");
            hx.IdleMs = 3000; hx.InProtectionZone = false;
            Run(ex, hx, 22000, 22500, 250);
            check(hx.Log.Count == 0, "engine exercise: not outside a protection zone");

            // the potion gate: a potion the client cannot count is probed by id, and the answer decides
            var hp = new Host { Health = 10 };
            var ep = Make(hp);
            ep.Config.Potions[0] = new HelperPotionRow { Id = 266, Percent = 90, Priority = 1 };
            hp.Level = 1000;
            var info = HelperPotions.Info(266);
            Run(ep, hp, 0, 400, 100);
            if (info != null && HelperPotions.CanDrink(266, hp.Level))
            {
                check(hp.Log.Any(l => l == "byid 266 0") && ep.GateProbes >= 1, "engine gate: an uncounted potion is probed by id (" + string.Join(",", hp.Log) + ")");
                int probes = hp.Log.Count(l => l.StartsWith("byid"));
                Run(ep, hp, 500, 2500, 100);
                check(hp.Log.Count(l => l.StartsWith("byid")) == probes, "engine gate: not probed again within three seconds");
                var hf = new Host { Health = 10, Level = 1000 };
                var ef = Make(hf);
                ef.Config.Potions[0] = new HelperPotionRow { Id = 266, Percent = 90, Priority = 1 };
                Run(ef, hf, 0, 300, 100);
                ef.OnServerText("Sorry, not possible.");   // within the reply window of the probe
                int pf = hf.Log.Count(l => l.StartsWith("byid"));
                Run(ef, hf, 400, 25000, 100);
                check(pf >= 1 && hf.Log.Count(l => l.StartsWith("byid")) == pf, "engine gate: a failed probe backs the potion off for thirty seconds");
                Run(ef, hf, 25100, 40000, 100);
                check(hf.Log.Count(l => l.StartsWith("byid")) > pf, "engine gate: and it is probed again after that");
                var hq = new Host { Health = 10, Level = 1000 };
                var eq = Make(hq);
                eq.Config.Potions[0] = new HelperPotionRow { Id = 266, Percent = 90, Priority = 1 };
                Run(eq, hq, 0, 300, 100);
                eq.OnServerText("Using an everfull health potion (never runs out).");
                int n0 = hq.Log.Count(l => l.StartsWith("byid"));
                Run(eq, hq, 700, 1500, 100);
                check(hq.Log.Count(l => l.StartsWith("byid")) > n0, "engine gate: a potion that answered Using is used again without the three second wait");
            }
            else check(true, "engine gate: (no stock potion 266 in this data)");
            var hn = new Host { Health = 10 };
            hn.Items[266] = 3;
            var en = Make(hn);
            en.Config.Potions[0] = new HelperPotionRow { Id = 266, Percent = 90, Priority = 1 };
            Run(en, hn, 0, 200, 100);
            check(!hn.Log.Any(l => l.StartsWith("byid")) && (hn.Log.Count == 0 || hn.Log[0] == "self 266"), "engine gate: a counted potion is used the old way");

            LevelUpChecks(check);
            SpellUnlockNames(check);
        }

        // A level up that opens a class spell is told by the spell's name: the Helper's notice and a toast carry it, and the spell list shows the spell as ready at that level (main
        // client: autorotation_ui.lua onLevelUp, game_spellbook). There is no server push of spell names: the client knows the list and the level (phase 28).
        static void SpellUnlockNames(Action<bool, string> check)
        {
            Loc.Set("en");
            var cls = HelperRotation.ClassOf(4);
            int lvA = 0, lvB = 0, newId = 0;
            for (int i = 0; i + 1 < cls.Presets.Count && lvB == 0; i++)
                foreach (int id in cls.Presets[i + 1].Spells)
                    if (Array.IndexOf(cls.Presets[i].Spells, id) < 0) { lvA = cls.Presets[i].Level; lvB = cls.Presets[i + 1].Level; newId = id; break; }
            var host = new Host { Level = lvA, Vocation = 4 };
            var ex = new ExtOpcodes();
            var book = new SpellBook(ex) { Clock = () => host.Now, LevelNow = () => host.Level, MagicLevelNow = () => 9999 };
            ex.Receive(219, "{\"action\":\"done\",\"data\":{\"sig\":\"x\"}}");
            var firstLevel = new Dictionary<int, int>();
            foreach (var pr in cls.Presets) foreach (int sid in pr.Spells) if (!firstLevel.ContainsKey(sid)) firstLevel[sid] = pr.Level;
            foreach (var kv in HelperRotation.SpellData) book.Spells.Add(new Spell { Id = kv.Key, Name = kv.Value.Name, Words = kv.Value.Words, Group = 1, Level = firstLevel.TryGetValue(kv.Key, out int fl) ? fl : 1 });
            foreach (var hh in cls.Heals) book.Spells.Add(new Spell { Id = hh.Id, Name = "Heal " + hh.Id, Words = "heal " + hh.Id, Group = 2, Level = 1 });
            var eng = new HelperEngine(book, host);
            eng.Config.Enabled = true;
            var spell = book.ById(newId);
            check(spell != null && spell.Name.Length > 0 && spell.Level == lvB, "spell unlock: the new spell is in the list with its name and level");
            eng.Tick();
            check(book.Status(spell) == SpellStatus.Level, "spell unlock: before the level the list shows the spell as waiting for its level");
            eng.AutoSetup(4);
            host.Level = lvB; host.Now = 1000;
            eng.Tick();
            check(book.Status(spell) == SpellStatus.Ready, "spell unlock: at its level the spell list shows it as ready");
            var n = eng.LevelNotice;
            check(n != null && n.NewIds.Contains(newId) && n.Names.Contains(spell.Name) && n.List.Contains(spell.Name), "spell unlock: the notice names the new spell");
            check(n != null && n.Line == "New spell available: " + n.List + ".", "spell unlock: the notice line is 'New spell available: NAME.'");
            var tc = new ToastCenter(new ExtOpcodes()) { Clock = () => 0 };
            var t = n == null ? null : tc.Add("MILESTONE", n.Line);
            check(t != null && t.Message.Contains(spell.Name) && tc.Active.Count + tc.Queue.Count == 1, "spell unlock: the toast carries the spell's name");
            Loc.Set("pt-BR");
            check(n != null && n.Line == "Nova magia disponível: " + n.List + ".", "spell unlock: the notice line in pt-BR");
            Loc.Set("en");
        }

        static void LevelUpChecks(Action<bool, string> check)
        {
            // find a Warrior preset level whose next preset has a spell the first one lacks
            var cls = HelperRotation.ClassOf(4);
            int lvA = 0, lvB = 0;
            for (int i = 0; i + 1 < cls.Presets.Count && lvB == 0; i++)
                foreach (int id in cls.Presets[i + 1].Spells)
                    if (Array.IndexOf(cls.Presets[i].Spells, id) < 0) { lvA = cls.Presets[i].Level; lvB = cls.Presets[i + 1].Level; break; }
            check(lvB > lvA && lvA > 0, "level-up: the class data has a preset with a new spell");
            Func<Host, HelperEngine> make = host =>
            {
                var ex = new ExtOpcodes();
                var book = new SpellBook(ex) { Clock = () => host.Now, LevelNow = () => host.Level, MagicLevelNow = () => 9999 };
                ex.Receive(219, "{\"action\":\"done\",\"data\":{\"sig\":\"x\"}}");
                // a spell opens at the level of the first preset that holds it, so a level-up really brings new ones
                var firstLevel = new Dictionary<int, int>();
                foreach (var pr in cls.Presets) foreach (int sid in pr.Spells) if (!firstLevel.ContainsKey(sid)) firstLevel[sid] = pr.Level;
                foreach (var kv in HelperRotation.SpellData) book.Spells.Add(new Spell { Id = kv.Key, Name = kv.Value.Name, Words = kv.Value.Words, Group = 1, Level = firstLevel.TryGetValue(kv.Key, out int fl) ? fl : 1 });
                foreach (var hh in cls.Heals) book.Spells.Add(new Spell { Id = hh.Id, Name = "Heal " + hh.Id, Words = "heal " + hh.Id, Group = 2, Level = 1 });
                var eng = new HelperEngine(book, host);
                eng.Config.Enabled = true;
                return eng;
            };
            var h = new Host { Level = lvA, Vocation = 4 };
            var e = make(h);
            e.Tick();   // the first reading of the level is not a level-up
            check(e.AutoSetup(4) != null && e.LevelNotice == null, "level-up: Auto setup wrote a rotation, no notice yet");
            h.Level = lvB; h.Now = 1000; e.Tick();
            check(e.LevelNotice != null && e.LevelNotice.NewIds.Count > 0 && e.LevelNotice.Names.Count == e.LevelNotice.NewIds.Count, "level-up: new spells give a notice, never a silent change");
            var before = e.Config.Shooter.Select(s => s.Id).ToList();
            check(e.Config.Shooter.Select(s => s.Id).SequenceEqual(before), "level-up: the shooter is not changed by the notice");
            int free = e.Config.Shooter.Count(s => s.Id == 0);
            e.Config.Shooter[4] = new HelperSlot { Priority = 5 };
            int added = e.AcceptLevelNotice();
            check(added >= 1 && e.LevelNotice == null && e.Config.Shooter.Count(s => s.Id != 0) >= 1, "level-up: Add puts the new spells into the empty slots");
            check(e.Config.AutoMarker.Count == 0, "level-up: an added rotation is the player's own from then on");
            // ignore: not offered again
            var h2 = new Host { Level = lvA, Vocation = 4 };
            var e2 = make(h2);
            e2.Tick(); e2.AutoSetup(4);
            h2.Level = lvB; h2.Now = 1000; e2.Tick();
            var ignoredIds = new List<int>(e2.LevelNotice.NewIds);
            e2.IgnoreLevelNotice();
            check(e2.LevelNotice == null && ignoredIds.All(id => e2.Config.IgnoredSpells.Contains(id)), "level-up: Ignore remembers the spells");
            check(e2.OnLevelUp(4) == LevelUpAction.None, "level-up: an ignored spell is not asked again");
            // auto-update on a rotation Auto setup wrote
            var h3 = new Host { Level = lvA, Vocation = 4 };
            var e3 = make(h3);
            e3.Config.AutoUpdateSpells = true;
            e3.Tick(); e3.AutoSetup(4);
            var oldIds = e3.Config.Shooter.Select(s => s.Id).ToList();
            h3.Level = lvB; h3.Now = 1000; e3.Tick();
            check(e3.LevelNotice == null && e3.LevelMessage.Length > 0 && !e3.Config.Shooter.Select(s => s.Id).SequenceEqual(oldIds), "level-up: Auto-update rewrites a rotation the button wrote and says so");
            // auto-update never touches the player's own rules
            var h4 = new Host { Level = lvA, Vocation = 4 };
            var e4 = make(h4);
            e4.Config.AutoUpdateSpells = true;
            e4.Tick(); e4.AutoSetup(4);
            e4.Config.Shooter[0] = new HelperSlot { Id = cls.Presets[0].Spells[0], Priority = 1, Percent = 33 };
            e4.Config.AutoMarker.Clear();
            var mine = e4.Config.Shooter.Select(s => s.Id).ToList();
            h4.Level = lvB; h4.Now = 1000; e4.Tick();
            check(e4.LevelNotice != null && e4.Config.Shooter.Select(s => s.Id).SequenceEqual(mine), "level-up: the player's own rotation is only offered, never changed");
            // a lower level or the same level is no level-up
            var h5 = new Host { Level = lvB, Vocation = 4 };
            var e5 = make(h5);
            e5.Tick();
            h5.Level = lvB; h5.Now = 1000; e5.Tick();
            h5.Level = lvA; h5.Now = 2000; e5.Tick();
            check(e5.LevelNotice == null, "level-up: no rise, no notice");

            // a class change takes the old class's spells out, after the spell list of the same packet
            var hv = new Host { Vocation = 4, Level = 100 };
            var evx = new ExtOpcodes();
            var bookv = new SpellBook(evx) { Clock = () => hv.Now };
            evx.Receive(219, "{\"action\":\"done\",\"data\":{\"sig\":\"x\"}}");
            bookv.Spells.Add(new Spell { Id = 1, Name = "Old", Words = "a", Group = 1, Level = 1, Vocations = { 4 } });
            bookv.Spells.Add(new Spell { Id = 2, Name = "New", Words = "b", Group = 1, Level = 1, Vocations = { 3 } });
            bookv.Spells.Add(new Spell { Id = 3, Name = "Any", Words = "c", Group = 1, Level = 1 });
            bookv.Spells.Add(new Spell { Id = 4, Name = "OldHeal", Words = "d", Group = 2, Level = 1, Vocations = { 4 } });
            var ev = new HelperEngine(bookv, hv);
            ev.Config.Enabled = true;
            ev.Config.Shooter[0] = new HelperSlot { Id = 1, Priority = 1 }; ev.Config.Shooter[1] = new HelperSlot { Id = 2, Priority = 2 }; ev.Config.Shooter[2] = new HelperSlot { Id = 3, Priority = 3 }; ev.Config.Shooter[3] = new HelperSlot { Id = 99, Priority = 4 };
            ev.Config.Heals[0] = new HelperHealRow { Id = 4, Percent = 50 };
            ev.Config.AutoMarker.Add(1);
            hv.Now = 0; ev.Tick();
            check(ev.Config.Shooter[0].Id == 1 && ev.ClassDrops == 0, "class change: the first vocation of a login is no change");
            hv.Vocation = 3; hv.Now = 100; ev.Tick();
            hv.Now = 300; ev.Tick();
            check(ev.ClassDrops == 0, "class change: nothing before the 400 ms that wait for the spell list");
            hv.Now = 600; ev.Tick();
            check(ev.Config.Shooter[0].Id == 0 && ev.Config.Shooter[0].Priority == 1 && ev.Config.Shooter[1].Id == 2 && ev.Config.Shooter[2].Id == 3 && ev.Config.Shooter[3].Id == 99, "class change: the old class's slot is emptied, the new class's, the open and the unknown spell stay");
            check(ev.Config.Heals[0].Id == 0 && ev.ClassDrops == 2 && ev.Config.AutoMarker.Count == 0 && ev.LevelMessage.StartsWith("Class changed: 2"), "class change: the old heal goes too, the marker is forgotten and the player is told");
            check(ev.DropOldClass(0) == 0 && ev.DropOldClass(3) == 0, "class change: a second pass drops nothing");

            // the pure rule
            var sel = new RotSelection(); sel.Ids.AddRange(new[] { 1, 2, 3 }); sel.Creatures.AddRange(new[] { 1, 1, 2 });
            List<int> n;
            check(RotationLevelUp.Decide(null, new int[0], null, false, null, out n) == LevelUpAction.None && n.Count == 0, "level-up rule: no selection, nothing");
            check(RotationLevelUp.Decide(sel, new[] { 1, 2, 3 }, null, false, null, out n) == LevelUpAction.None, "level-up rule: nothing new, nothing");
            check(RotationLevelUp.Decide(sel, new[] { 1 }, null, false, null, out n) == LevelUpAction.Notice && n.SequenceEqual(new[] { 2, 3 }), "level-up rule: new spells give a notice");
            check(RotationLevelUp.Decide(sel, new[] { 1 }, new[] { 1 }, true, null, out n) == LevelUpAction.Apply, "level-up rule: Auto-update on an untouched rotation applies");
            check(RotationLevelUp.Decide(sel, new[] { 1 }, new[] { 9 }, true, null, out n) == LevelUpAction.Notice, "level-up rule: Auto-update never touches a custom rotation");
            check(RotationLevelUp.Decide(sel, new[] { 1 }, new[] { 1 }, false, new HashSet<int> { 2, 3 }, out n) == LevelUpAction.None, "level-up rule: ignored spells are not offered");
            check(RotationLevelUp.Decide(sel, new int[0], null, true, null, out n) == LevelUpAction.Apply, "level-up rule: an empty rotation counts as untouched");
            check(RotationLevelUp.IsCustom(new[] { 1 }, new[] { 1 }) == false && RotationLevelUp.IsCustom(new[] { 1 }, null) && !RotationLevelUp.IsCustom(new int[0], null), "level-up rule: custom means not empty and not the button's set");
            var slots = new List<HelperSlot> { new HelperSlot { Id = 7, Priority = 1 }, new HelperSlot { Priority = 2 }, new HelperSlot { Priority = 3 } };
            check(RotationLevelUp.AddNew(slots, sel, new[] { 3, 2 }) == 2 && slots[1].Id == 3 && slots[1].Creatures == 2 && slots[2].Id == 2 && slots[0].Id == 7, "level-up rule: Add fills the empty slots in order with the creature count of the selection");
            check(RotationLevelUp.AddNew(slots, sel, new[] { 1 }) == 0, "level-up rule: no empty slot, nothing added");
        }

        // ------------------------------------------------------------------------------------ settings
        static void ConfigChecks(Action<bool, string> check)
        {
            var c = new HelperConfig();
            check(!c.Follow.Enabled && c.Follow.Mode == "name" && c.Follow.Distance == 1 && c.Sell.Interval == 30 && c.Sell.Capacity == 100 && !c.Exercise.Enabled && !c.AutoUpdateSpells && c.IgnoredSpells.Count == 0, "settings: the defaults of the main client");
            c.Follow = new HelperFollowCfg { Enabled = true, Mode = "leader", Name = "Bob Ross", Distance = 4 };
            c.Sell = new HelperSellCfg { Enabled = true, Interval = 15, BelowCap = true, Capacity = 250 };
            c.Exercise = new HelperExerciseCfg { Enabled = true, Id = 27735 };
            c.AutoUpdateSpells = true;
            c.IgnoredSpells.Add(42); c.IgnoredSpells.Add(7);
            var back = HelperConfig.FromJson(c.ToJson());
            check(back.Follow.Enabled && back.Follow.Mode == "leader" && back.Follow.Name == "Bob Ross" && back.Follow.Distance == 4, "settings: Follow round trips");
            check(back.Sell.Enabled && back.Sell.Interval == 15 && back.Sell.BelowCap && back.Sell.Capacity == 250 && back.Exercise.Enabled && back.Exercise.Id == 27735, "settings: Auto sell and the exercise weapon round trip");
            check(back.AutoUpdateSpells && back.IgnoredSpells.Count == 2 && back.IgnoredSpells.Contains(42) && back.IgnoredSpells.Contains(7), "settings: Auto-update and the ignored spells round trip");
            var bad = HelperConfig.FromJson("{\"follow\":{\"enabled\":true,\"mode\":\"x\",\"name\":\"1\",\"distance\":99},\"autoSell\":{\"enabled\":true,\"minutes\":7,\"capacity\":-5},\"exercise\":{\"id\":-3},\"ignoredSpells\":[\"a\",5]}");
            check(bad.Follow.Mode == "name" && bad.Follow.Name == "" && bad.Follow.Distance == HelperFollowCfg.DistanceMax && bad.Sell.Interval == 30 && bad.Sell.Capacity == 0 && bad.Exercise.Id == 0 && bad.IgnoredSpells.Count == 1, "settings: bad values are clamped to the main client's limits");
            var old = HelperConfig.FromJson("{\"enabled\":true,\"magicShooter\":true}");
            check(old.Enabled && old.MagicShooter && !old.Follow.Enabled && old.Sell.Interval == 30, "settings: an older save loads with the new sections off");
            var copy = c.Copy();
            check(copy.Follow.Name == "Bob Ross" && copy.IgnoredSpells.Contains(42), "settings: Copy keeps the new sections");
        }

        // ------------------------------------------------------------------------------------ top menu
        static void MenuChecks(Action<bool, string> check)
        {
            var character = TopMenu.Categories.First(c => c.Id == "character");
            var more = TopMenu.MoreOf(character);
            check(more != null && more.Text == "More" && more.Sub.Any(e => e.Text == "Inventory") && more.Sub.Any(e => e.Text == "Outfit" && e.Target == "win:OutfitWindow") && character.Entries.All(e => e.Text != "Inventory"), "menu: Character has a More sub-menu with Inventory and Outfit");
            check(TopMenu.MoreOf(TopMenu.Categories.First(c => c.Id == "economy")).Sub.Select(e => e.Text).OrderBy(x => x).SequenceEqual(new[] { "Ancestral Store", "House" }), "menu: Economy's More holds House and Ancestral Store");
            check(TopMenu.MoreOf(TopMenu.Categories.First(c => c.Id == "hunt")).Sub.Any(e => e.Text == "Map Markers"), "menu: Hunt's More holds Map Markers");
            check(TopMenu.MoreOf(TopMenu.Categories.First(c => c.Id == "social")) == null, "menu: Social has no More");
            var leaves = TopMenu.Leaves(character).ToList();
            check(leaves.Any(e => e.Target == "win:EquipmentWindow") && leaves.All(e => e.Sub == null && !e.Separator), "menu: Leaves opens the sub-menus");
            var system = TopMenu.Categories.First(c => c.Id == "system");
            var sysTexts = system.Entries.Where(e => !e.Separator).Select(e => e.Text).ToList();
            check(new[] { "Options", "Helper", "Admin Panel", "Join Discord", "Logout", "Exit" }.All(sysTexts.Contains), "menu: System lists Options, Helper, Admin Panel, Join Discord, Logout and Exit");
            check(system.Entries.Any(e => e.Separator) && system.Entries.First(e => e.Text == "Exit").Target == "act:exit" && system.Entries.First(e => e.Text == "Join Discord").Target == "act:discord", "menu: a separator sets Logout and Exit apart, the actions are named");
            var sorted = TopMenu.Sorted(system.Entries, e => e.Text);
            int sep = sorted.FindIndex(e => e.Separator);
            check(sep > 0 && sorted[sep + 1].Text == "Exit" || sorted[sep + 1].Text == "Logout", "menu: Logout and Exit stay after the separator when sorted");
            check(TopMenu.HotkeyText("P") == "Ctrl+P" && TopMenu.HotkeyText("") == "" && TopMenu.HotkeyText("None") == "" && TopMenu.HotkeyText(null) == "", "menu: the hotkey text of a row");
            // every window the menu names that is not an action or Info page is a window the app knows by the class name pattern
            check(leaves.Concat(TopMenu.Categories.SelectMany(c => TopMenu.Leaves(c))).All(e => e.Target.Length > 0), "menu: every leaf names a target");
        }

        // ------------------------------------------------------------------------------------ pt-BR
        static void TextChecks(Action<bool, string> check)
        {
            var keys = new List<string>();
            // every Core key the track returns for the window to translate
            keys.AddRange(new[] { "Enter a name.", "Use letters and spaces only.", "Use one space between words.", "Every word needs at least two letters.", "Use at most {0} words.", "The name needs {0} to {1} letters.",
                "{0} to {1} letters, up to {2} words.", "No season (standard character)", "Creating your character...", "Reading your account from the website...",
                "Accept the current Terms of Use on the website first, then come back.", "Choose a class.", "Hardcore has one life: tick \"I understand\" to choose it.",
                "{0}: locked for this account. Reach level 200 with any character of your account to unlock it.",
                "No free character slot: more are sold in the game store (Storage & Slots > Character Slot).", "Character slots: {0} of {1} used.",
                "Cast facing north (up).", "Centred on the target.", "Centred on you.", "One target, range {0}.", "One target.", "Affects only you.", "Everyone", "Every class", "{0} classes" });
            foreach (var w in HelperExercise.Weapons) keys.Add(w.Value);
            foreach (string why in new[] { "following", "ask", "away", "pz", "helperoff", "near", "adjacent", "other", "retry", "giveup", "gap", "off" }) keys.Add(HelperTextsP7.FollowText(why));
            foreach (string why in new[] { "timer", "capacity", "wait", "cooldown", "locked", "unknown", "helperoff", "gap", "off" }) keys.Add(HelperTextsP7.SellText(why));
            keys.AddRange(new[] { "Soul", "Group", "Type", "Element", "Scales", "Vocations", "Attack", "Healing", "Support", "Special", "Damage", "Summon", "Conjure", "Utility", "Single target", "Area", "Self", "Area in front" });
            keys.AddRange(new[] { "Options", "Helper", "Admin Panel", "Join Discord", "Logout", "Exit", "More", "Inventory", "Outfit", "House", "Ancestral Store", "Map Markers", "The community link is not available yet." });
            var missing = keys.Distinct().Where(k => !LocStrings.PtBr.ContainsKey(k)).ToList();
            check(missing.Count == 0, "pt-BR: every text the track shows has a translation: " + string.Join(" | ", missing.Take(8)));
            // and the Loc.T("...") keys of the new Unity files
            var unity = new[] { "ChaosApp.Phase7X.cs", Path.Combine("Windows", "HelperWindowP7.cs"), Path.Combine("Windows", "HotkeyBarWindow.cs"), Path.Combine("Windows", "SpellbookWindow.cs"), "ChaosApp.Progression.cs" };
            var lost = new List<string>();
            foreach (string f in unity)
            {
                string path = Find("unity", "Client", "Assets", "Chaos", "Unity", f) ?? Find("Client", "Assets", "Chaos", "Unity", f);
                if (path == null) continue;
                foreach (System.Text.RegularExpressions.Match m in System.Text.RegularExpressions.Regex.Matches(File.ReadAllText(path), "\\bLoc\\.T\\(\"((?:[^\"\\\\]|\\\\.)*)\""))
                {
                    string k = m.Groups[1].Value.Replace("\\\"", "\"");
                    if (!LocStrings.PtBr.ContainsKey(k)) lost.Add(f + ": " + k);
                }
            }
            check(lost.Count == 0, "pt-BR: every Loc.T key of the track's Unity files has a translation: " + string.Join(" | ", lost.Take(6)));
            // pt-BR keeps the argument indexes
            Loc.Set("pt-BR");
            check(Loc.T("The name needs {0} to {1} letters.", 3, 20) == "O nome precisa de 3 a 20 letras." && Loc.T("Use at most {0} words.", 3) == "Use no máximo 3 palavras.", "pt-BR: arguments keep their indexes");
            Loc.Set("en");
        }

        static string Find(params string[] parts)
        {
            string dir = Directory.GetCurrentDirectory();
            for (int i = 0; i < 8 && dir != null; i++)
            {
                string p = Path.Combine(new[] { dir }.Concat(parts).ToArray());
                if (File.Exists(p)) return p;
                dir = Path.GetDirectoryName(dir);
            }
            return null;
        }
    }
}
