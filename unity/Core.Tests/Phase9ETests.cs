// Phase 9, track E (Core/Phase9E.cs): the Customise Character categories and palette, the list card layout, the effect stage of the look preview, the entries of the login bar and the
// saved window sizes.
using System;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class Phase9ETests
    {
        static object J(string json) => Json.TryParse(json);

        public static void Run(Action<bool, string> check)
        {
            Loc.Set("en");
            CategoryChecks(check);
            ColorChecks(check);
            CardLayoutChecks(check);
            StageChecks(check);
            ExtrasPreviewChecks(check);
            LoginChecks(check);
            SizeChecks(check);
            Loc.Set("en");
        }

        static OutfitWindowState State()
        {
            var st = new OutfitWindowState { HasExtras = true, Opens = 1 };
            st.Outfits.Add(new OutfitChoice { LookType = 128, Name = "Citizen", Addons = 3 });
            st.Outfits.Add(new OutfitChoice { LookType = 130, Name = "Mage", Addons = 1 });
            st.Mounts.Add(new NamedId { Id = 368, Name = "Widow Queen" });
            st.Wings.Add(new NamedId { Id = 1500, Name = "Ash Wings" });
            st.Auras.Add(new NamedId { Id = 1600, Name = "Ember Ring" });
            st.Shaders.Add(new NamedId { Id = 0, Name = "Frost Pulse" });
            return st;
        }

        // ------------------------------------------------------------------------------------ game_outfitextras: categories and cards
        static void CategoryChecks(Action<bool, string> check)
        {
            var keys = new[] { "outline", "footprint", "killfx" };
            var all = ExtrasLook.Categories(true, keys);
            check(string.Join(",", all) == "outfit,mount,wings,aura,shader,colors,outline,footprint,killfx", "extras: look categories, the colours, then the cosmetic rows (" + string.Join(",", all) + ")");
            var plain = ExtrasLook.Categories(false, keys);
            check(!plain.Contains("wings") && !plain.Contains("aura") && !plain.Contains("shader") && plain.Contains("outfit") && plain.Contains("mount") && plain[2] == "colors", "extras: wings, aura and shader need the Chaos lists");
            check(ExtrasLook.Known("wings", plain) == "outfit" && ExtrasLook.Known("outline", plain) == "outline", "extras: a category that is gone falls back to the first");
            check(ExtrasLook.IsLook("mount") && !ExtrasLook.IsLook("colors") && !ExtrasLook.IsLook("outline") && ExtrasLook.NeedsExtras("shader") && !ExtrasLook.NeedsExtras("mount"), "extras: which keys are looks");
            check(ExtrasLook.Label("shader") == "Shader" && ExtrasLook.TabLabel("secondary") == "Secondary", "extras: the labels");
            Loc.Set("pt");
            Loc.Set("en");

            var st = State();
            var cat = new List<WardrobeEntry> { new WardrobeEntry { Look = 140, Name = "Shaman", Source = "quest" }, new WardrobeEntry { Look = 128, Name = "Citizen" } };
            var outfits = ExtrasLook.Cards("outfit", st, cat, false, "");
            check(outfits.Count == 3 && !outfits[0].None && outfits[2].Locked && outfits[2].Id == 140, "extras cards: owned outfits, then the locked one of the wardrobe (" + outfits.Count + ")");
            check(ExtrasLook.Cards("outfit", st, cat, true, "").Count == 2, "extras cards: only what I own drops the locked ones");
            var mounts = ExtrasLook.Cards("mount", st, null, false, "");
            check(mounts.Count == 2 && mounts[0].None && mounts[1].Id == 368, "extras cards: None comes first for a mount");
            check(ExtrasLook.Cards("outfit", st, null, false, "").All(c => !c.None), "extras cards: an outfit has no None card");
            check(ExtrasLook.Cards("mount", st, null, false, "widow").Count == 1 && ExtrasLook.Cards("mount", st, null, false, "none").Count == 1, "extras cards: the search matches every word, None too");
            check(ExtrasLook.Cards("mount", st, null, false, "zzz").Count == 0, "extras cards: a search that matches nothing");
            ExtrasLook.Count(outfits, out int have, out int cnt);
            check(have == 2 && cnt == 3, "extras cards: the have / all count (" + have + "/" + cnt + ")");
            ExtrasLook.Count(mounts, out have, out cnt);
            check(have == 1 && cnt == 1, "extras cards: None counts for neither");
            check(ExtrasLook.Cards("shader", st, null, false, "").Last().Name == "Frost Pulse" && ExtrasLook.Cards("shader", st, null, false, "").Last().Id == 0, "extras cards: a shader is a name");

            var o = new Outfit(128, 10, 20, 30, 40, 3);
            var mage = outfits[1];
            var o2 = ExtrasLook.Apply(o, st, "outfit", mage);
            check(o2.LookType == 130 && o2.Addons == 1 && o2.Head == 10 && o.LookType == 128, "extras apply: a new look keeps the colours and only the addons it allows; the old outfit is untouched");
            check(ExtrasLook.Apply(o, st, "mount", mounts[1]).Mount == 368 && ExtrasLook.Apply(ExtrasLook.Apply(o, st, "mount", mounts[1]), st, "mount", mounts[0]).Mount == 0, "extras apply: a mount, and None clears it");
            var wing = new LookCard { Id = 1500, Name = "Ash Wings" };
            check(ExtrasLook.Apply(o, st, "wings", wing).Wings == 1500 && ExtrasLook.Apply(o, st, "aura", new LookCard { Id = 1600 }).Aura == 1600, "extras apply: wings and aura");
            var sh = ExtrasLook.Apply(o, st, "shader", new LookCard { Name = "Frost Pulse" });
            check(sh.Shader == "Frost Pulse" && ExtrasLook.Apply(sh, st, "shader", new LookCard { None = true }).Shader == "", "extras apply: a shader by name, None clears it");
            check(ExtrasLook.IsCurrent(o2, "outfit", mage) && !ExtrasLook.IsCurrent(o2, "outfit", outfits[0]) && ExtrasLook.IsCurrent(o, "mount", mounts[0]) && ExtrasLook.IsCurrent(sh, "shader", new LookCard { Name = "Frost Pulse" }), "extras: the card in use");

            var look = ExtrasLook.CardLook(new Outfit(128, 1, 2, 3, 4, 3, 368), "outfit", mage);
            check(look.LookType == 130 && look.Head == 1 && look.Addons == 0 && look.Mount == 0, "extras card look: an outfit card shows the look in the colours being edited");
            check(ExtrasLook.CardLook(o, "mount", mounts[1]).LookType == 368 && ExtrasLook.CardLook(o, "mount", mounts[0]) == null, "extras card look: a mount alone, None draws nothing");
            var wl = ExtrasLook.CardLook(new Outfit(128, 1, 2, 3, 4, 1, 368), "wings", wing);
            check(wl.LookType == 128 && wl.Wings == 1500 && wl.Mount == 0 && wl.Aura == 0, "extras card look: wings on the character");

            check(ExtrasLook.Equipped("mount", new Outfit(128, 0, 0, 0, 0, 0, 368), st) == "Mount: Widow Queen" && ExtrasLook.Equipped("wings", o, st) == "Wings: -" && ExtrasLook.Equipped("outfit", o, st) == "Outfit: Citizen", "extras: the Equipped now line of a look category");
            check(ExtrasLook.Equipped("aura", new Outfit(128, 0, 0, 0, 0) { Aura = 99 }, st) == "Aura: 99" && ExtrasLook.Equipped("shader", sh, st) == "Shader: Frost Pulse", "extras: a worn entry the list lacks shows its id");
            var rich = new Outfit(130, 1, 2, 3, 4, 1, 368) { Wings = 1500, Aura = 1600, Shader = "Frost Pulse" };
            var sent = ExtrasLook.ToSend(rich, false, true, false, false);
            check(sent.Mount == 0 && sent.Wings == 1500 && sent.Aura == 0 && sent.Shader == "" && rich.Mount == 368, "extras send: a layer left off is none");
            check(ExtrasLook.Changed(rich, sent) && !ExtrasLook.Changed(rich, OutfitWindowState.Copy(rich)), "extras send: Apply sends the look only when it changed");
        }

        static void ColorChecks(Action<bool, string> check)
        {
            var o = new Outfit(128, 10, 20, 30, 40, 1);
            check(ExtrasLook.ColorTabs.Length == 4 && ExtrasLook.ColorOf(o, "head") == 10 && ExtrasLook.ColorOf(o, "primary") == 20 && ExtrasLook.ColorOf(o, "secondary") == 30 && ExtrasLook.ColorOf(o, "detail") == 40, "palette: the four tabs paint head, body, legs and feet");
            var n = ExtrasLook.SetColor(o, "secondary", 77);
            check(n.Legs == 77 && n.Head == 10 && n.Body == 20 && n.Feet == 40 && o.Legs == 30, "palette: a cell sets one field on a copy");
            check(ExtrasLook.SetColor(o, "head", 133).Head == 10 && ExtrasLook.SetColor(o, "head", -1).Head == 10 && ExtrasLook.SetColor(o, "head", 132).Head == 132, "palette: the grid is 133 cells");
            check(ExtrasLook.CellAt(0, 0, 16, 1) == 0 && ExtrasLook.CellAt(17 * 18 + 3, 0, 16, 1) == 18 && ExtrasLook.CellAt(2, 17 * 6 + 2, 16, 1) == 6 * 19, "palette: a pointer position is a cell");
            check(ExtrasLook.CellAt(16.5f, 2, 16, 1) == -1 && ExtrasLook.CellAt(-1, 2, 16, 1) == -1 && ExtrasLook.CellAt(17 * 19, 2, 16, 1) == -1 && ExtrasLook.CellAt(2, 17 * 7, 16, 1) == -1, "palette: the gap between cells and the outside are no cell");
            var st = State();
            check(ExtrasLook.SetAddon(new Outfit(130, 0, 0, 0, 0, 0), st, 1, true).Addons == 0 && ExtrasLook.SetAddon(new Outfit(130, 0, 0, 0, 0, 0), st, 0, true).Addons == 1, "palette: an addon the look does not allow stays off");
            check(ExtrasLook.SetAddon(new Outfit(128, 0, 0, 0, 0, 3), st, 0, false).Addons == 2, "palette: an addon box clears its bit");
        }

        // ------------------------------------------------------------------------------------ game_lookpreview: list cards
        static void CardLayoutChecks(Action<bool, string> check)
        {
            var L = LookCards.Layout(LookCards.Fallback, 100, 100);
            check(L.Scale == 2f && L.Tile == 64f && L.Size == 128f, "card: a 100 px card holds the figure at 2x (" + L.Scale + ")");
            float feetY = L.Y + (LookCards.Fallback.Fy + 32) * L.Tile / 32f;
            check(Math.Abs(feetY - L.FeetY) <= 1f, "card: the feet stand where the layout says (" + feetY + " / " + L.FeetY + ")");
            check(L.FeetY <= 100 && L.FeetY > 50, "card: the feet are inside the card");
            check(LookCards.Layout(LookCards.Fallback, 200, 200).Scale == 3f, "card: a large card gets 3x");
            check(LookCards.Layout(LookCards.Fallback, 20, 20).Scale == 1f, "card: a small card takes the smallest scale");
            check(LookCards.Layout(LookCards.Fallback, 66, 66).Scale == 1.5f && LookCards.Layout(LookCards.Fallback, 66, 66).Tile == 48f, "card: 1.5x gives a 48 px tile");
            var mounted = LookCards.Figure(2, 2, true);
            check(mounted.Top == LookCards.Fallback.Top - LookCards.Rider && LookCards.Figure(2, 2, false).Top == LookCards.Fallback.Top, "card: a rider reaches above its mount");
            var big = LookCards.Figure(4, 3, false);
            check(big.Left == LookCards.Fallback.Left - 64 && big.Top == LookCards.Fallback.Top - 32, "card: a big thing reaches one tile more per size");
            check(LookCards.Layout(big, 100, 100).Scale < LookCards.Layout(LookCards.Fallback, 100, 100).Scale || LookCards.Layout(big, 100, 100).Scale == 1f, "card: a bigger figure never gets a bigger scale");
        }

        // ------------------------------------------------------------------------------------ game_lookpreview: the effect stage
        const string Skin = "[{\"a\":{\"id\":10,\"dx\":0,\"dy\":0,\"ms\":300,\"n\":\"fire_cloud\"},\"b\":{\"id\":20,\"dx\":0,\"dy\":0,\"ms\":500,\"n\":\"ember_nova\"}},"
            + "{\"a\":{\"id\":11,\"m\":1,\"n\":\"fire_ball\"},\"b\":{\"id\":21,\"m\":1,\"n\":\"ember_ball\"}},"
            + "{\"b\":{\"id\":22,\"dx\":1,\"dy\":-1,\"n\":\"ember_explosion\"}}]";

        static void StageChecks(Action<bool, string> check)
        {
            var play = J(Skin);
            var steps = PreviewStage.Steps(play);
            check(steps.Count == 3 && steps[0].A.Id == 10 && steps[0].B.Ms == 500 && steps[1].B.Missile && !steps[0].A.Missile && steps[2].A == null && steps[2].B.Dx == 1 && steps[2].B.Dy == -1, "stage: the steps parse, a missile has m");
            check(PreviewStage.Steps(J("[1,2,{\"a\":{\"id\":0}},{}]")).Count == 0 && PreviewStage.Steps(null).Count == 0 && PreviewStage.Steps(J("{}")).Count == 0, "stage: junk makes no steps");
            check(PreviewStage.HasStock(steps) && !PreviewStage.HasStock(PreviewStage.Steps(J("[{\"b\":{\"id\":5}}]"))) && PreviewStage.HasMissile(steps), "stage: stock and missile flags");
            check(PreviewStage.Steps(J("[{\"b\":{\"id\":5,\"m\":0}}]"))[0].B.Missile == false && PreviewStage.Steps(J("[{\"b\":{\"id\":5,\"m\":true}}]"))[0].B.Missile, "stage: m is a flag, 0 is not a missile");

            var opt = PreviewStage.FromPlayRow("spellskin", play);
            check(opt != null && opt.Kind == "effects" && !opt.KillFx && PreviewStage.FromPlayRow("killfx", play).KillFx && PreviewStage.FromPlayRow("rarefx", play).KillFx, "stage: a kill or rare-loot effect plays on a troll that dies");
            check(PreviewStage.FromPlayRow("spellskin", null) == null && PreviewStage.FromPlayRow("spellskin", J("[]")) == null && PreviewStage.FromPlayRow("spellskin", J("[{}]")) == null, "stage: a row without steps has no stage");
            var bundle = new PreviewOption { Kind = "bundle", Parts = new List<PreviewOption> { PreviewOption.Of("wings", 5), opt } };
            check(PreviewStage.EffectsOf(bundle) == opt && PreviewStage.EffectsOf(opt) == opt && PreviewStage.EffectsOf(PreviewOption.Of("wings", 5)) == null && PreviewStage.EffectsOf(null) == null, "stage: the effects option inside a bundle");

            var spell = PreviewStage.SceneOf(opt);
            var kill = PreviewStage.SceneOf(PreviewStage.FromPlayRow("killfx", play));
            check(spell.HasCaster && !spell.Kill && spell.Target.X == 2 && spell.Caster.X == 0 && kill.Kill && !kill.HasCaster && kill.Target.X == 0, "stage: a spell scene has a caster and a troll two tiles east, a kill scene the troll alone");

            check(PreviewStage.LandsOn(steps[1].B, true, spell) == "missile" && PreviewStage.LandsOn(steps[0].B, true, spell) == "target", "stage: with a missile the other effects are its impact");
            var nova = new FxSpec { Id = 1, Name = "ember_nova" };
            check(PreviewStage.LandsOn(nova, false, spell) == "caster" && PreviewStage.LandsOn(new FxSpec { Id = 1, Name = "Big Explosion" }, false, spell) == "target" && PreviewStage.LandsOn(nova, false, kill) == "target", "stage: a name that says it hits is on the target, a nova round the caster, a kill effect on the target");

            check(PreviewStage.Duration(new FxSpec { Missile = true }, 3) == 420 && PreviewStage.Duration(new FxSpec { Ms = 800 }, 3) == 800 && PreviewStage.Duration(new FxSpec(), 4) == 400 && PreviewStage.Duration(new FxSpec(), 0) == 100, "stage: durations");
            var tl = PreviewStage.Timeline(steps, 'b', s => 4, spell);
            check(tl.Items.Count == 3 && tl.Items[0].Start == 0 && tl.Items[0].Dur == 500 && tl.Items[1].Start == 750 && tl.Items[1].Dur == 420 && tl.Items[2].Start == 750 + 420 + 250, "stage: the skin's items follow one another with a gap");
            double total = 750 + 420 + 250 + 400 + 900 - 0;
            check(tl.Total == total - 0 && tl.Lead == 0, "stage: the loop ends with a pause (" + tl.Total + ")");
            var tlA = PreviewStage.Timeline(steps, 'a', s => 4, spell);
            check(tlA.Items.Count == 2 && tlA.Items.All(i => i.Side == 'a'), "stage: the stock side has the stock effects only");
            var both = PreviewStage.Timeline(steps, '*', s => 4, spell);
            check(both.Items.Count == 5 && both.Items[0].Side == 'a' && both.Items[2].Side == 'b' && both.Items[2].Start > both.Items[1].Start, "stage: compare plays every stock effect, then every skin effect");
            var tlk = PreviewStage.Timeline(steps, 'b', s => 4, kill);
            check(tlk.Lead == 600 && tlk.Items[0].Start == 600 && tlk.Items.Where(i => !i.Spec.Missile).All(i => i.At == "target"), "stage: a kill scene starts after the troll has stood a while");
            check(PreviewStage.Timeline(new List<FxStep>(), 'b', null, spell).Total == 0 && PreviewStage.Timeline(new List<FxStep>(), 'b', null, spell).Items.Count == 0, "stage: no steps, no loop");

            check(PreviewStage.ActiveAt(tl, 100).Count == 1 && PreviewStage.ActiveAt(tl, 100)[0].Item == tl.Items[0] && Math.Abs(PreviewStage.ActiveAt(tl, 250)[0].Frac - 0.5) < 1e-9, "stage: what plays at a time, and how far into it");
            check(PreviewStage.ActiveAt(tl, 600).Count == 0 && PreviewStage.ActiveAt(tl, 100 + tl.Total).Count == 1 && PreviewStage.ActiveAt(tl, -tl.Total + 100).Count == 1, "stage: a gap plays nothing, the loop starts over (also for a clock before the start)");
            check(PreviewStage.PhaseAt(0, 400, 4) == 0 && PreviewStage.PhaseAt(150, 400, 4) == 1 && PreviewStage.PhaseAt(399, 400, 4) == 3 && PreviewStage.PhaseAt(900, 400, 4) == 3 && PreviewStage.PhaseAt(5, 0, 4) == 0 && PreviewStage.PhaseAt(5, 400, 0) == 0, "stage: the frame of an effect, the last held");
            check(PreviewStage.TargetAlpha(tlk, 100) == 1 && PreviewStage.TargetAlpha(tlk, 600 + 175) == 0.5 && PreviewStage.TargetAlpha(tlk, 600 + 400) == 0 && PreviewStage.TargetAlpha(tl, 5000) == 1 && PreviewStage.TargetAlpha(null, 0) == 1, "stage: the troll of a kill scene fades after the lead");
            check(PreviewStage.TargetAlpha(tlk, tlk.Total + 100) == 1, "stage: and stands again when the loop starts over");

            PreviewStage.MissilePattern(2, 0, out int px, out int py);
            check(px == 2 && py == 1, "stage: a missile flying east");
            PreviewStage.MissilePattern(-2, 0, out px, out py);
            check(px == 0 && py == 1, "stage: west");
            PreviewStage.MissilePattern(0, -1, out px, out py);
            check(px == 1 && py == 0, "stage: north");
            PreviewStage.MissilePattern(0, 1, out px, out py);
            check(px == 1 && py == 2, "stage: south");
            PreviewStage.MissilePattern(2, 2, out px, out py);
            check(px == 2 && py == 2, "stage: south east");
            PreviewStage.MissilePattern(0, 0, out px, out py);
            check(px == 1 && py == 1, "stage: no flight");

            var ball = new FxActive { Item = tl.Items[1], Frac = 0.5 };
            PreviewStage.ItemPlace(ball, spell, out double ox, out double oy, out px, out py);
            check(ox == 1 && oy == 0 && px == 2 && py == 1, "stage: a missile is half way from the caster to the troll at half its flight");
            PreviewStage.ItemPlace(new FxActive { Item = tl.Items[1], Frac = 1 }, spell, out ox, out oy, out _, out _);
            check(ox == 2 && oy == 0, "stage: and lands on the troll");
            PreviewStage.ItemPlace(new FxActive { Item = tl.Items[1], Frac = 0 }, kill, out ox, out oy, out px, out py);
            check(ox == -2 && oy == -1 && px == 2 && py == 2, "stage: with no caster a missile comes from two tiles away (" + ox + "," + oy + ")");
            PreviewStage.ItemPlace(new FxActive { Item = tl.Items[2] }, spell, out ox, out oy, out px, out py);
            check(ox == 3 && oy == -1 && px == 0 && py == 0, "stage: an impact is moved by the step's own offset");
            PreviewStage.ItemPlace(new FxActive { Item = new FxItem { Spec = nova, At = "caster" } }, spell, out ox, out oy, out _, out _);
            check(ox == 0 && oy == 0, "stage: a nova plays on the caster");

            PreviewStage.Extent(steps, s => new double[] { 1, 1, 0, 0 }, spell, PreviewStage.FallbackBox, PreviewStage.FallbackBox, out double x0, out double y0, out double x1, out double y1);
            check(x0 == -0.25 && x1 == 4 && y0 == -1 && y1 == 1, "stage: the extent holds both creatures and the effects (" + x0 + "," + y0 + " - " + x1 + "," + y1 + ")");
            PreviewStage.Extent(new List<FxStep>(), null, kill, PreviewStage.FallbackBox, PreviewStage.FallbackBox, out x0, out y0, out x1, out y1);
            check(x0 == -0.25 && x1 == 0.75 && y0 == -0.25 && y1 == 0.75, "stage: a lone troll's box");
            var layout = PreviewStage.Layout(200, 200, x0, y0, x1, y1);
            check(layout.Scale == 2 && layout.T == 64 && layout.Size == 128, "stage: a small scene gets 2x");
            check(Math.Abs(layout.TileX + x0 * layout.T + (x1 - x0) * layout.T / 2 - 100) <= 1, "stage: the scene is centred");
            PreviewStage.Extent(steps, s => new double[] { 3, 3, 0, 0 }, spell, PreviewStage.FallbackBox, PreviewStage.FallbackBox, out x0, out y0, out x1, out y1);
            var tight = PreviewStage.Layout(180, 140, x0, y0, x1, y1);
            check(tight.Scale < 2 && (x1 - x0) * 32 * tight.Scale <= 180.0001 || tight.Scale == 1, "stage: a wide scene gets a smaller scale (" + tight.Scale + ")");
            PreviewStage.CreatureRect(layout, new StageTile { X = 2, Y = 0 }, out double cx, out double cy, out double cs);
            check(cs == 2 * layout.T && cx == layout.TileX + layout.T && cy == layout.TileY - layout.T, "stage: the creature square of a tile is two tiles, its own tile the lower right quarter");
            PreviewStage.TilePixel(layout, 0, 0, 0, 0, 0, 0, out double tx, out double ty);
            check(tx == layout.TileX && ty == layout.TileY, "stage: a one tile effect on the stage tile sits on it");
            PreviewStage.TilePixel(layout, 0, 0, 1, 1, 0, 0, out tx, out ty);
            check(tx == layout.TileX - layout.T && ty == layout.TileY - layout.T, "stage: the next tile of a bigger thing is left and up");
            PreviewStage.TilePixel(layout, 0, 0, 0, 0, 16, 8, out tx, out ty);
            check(tx == layout.TileX - 32 && ty == layout.TileY - 16, "stage: the displacement moves it up and left at the stage's scale");
        }

        static void ExtrasPreviewChecks(Action<bool, string> check)
        {
            var play = J(Skin);
            var row = new OutfitExtrasPanel.ExtraRow { Key = "spellskin", Label = "Spell effect" };
            row.Options.Add(new OutfitExtrasPanel.Option { Text = "Default", Value = "0" });
            row.Options.Add(new OutfitExtrasPanel.Option { Text = "Ember", Value = "7", Row = new CosRow { Id = "7", Kind = "spellskin", Play = (List<object>)play } });
            check(ExtrasView.Preview(row, 1) == null && ExtrasView.Preview(row, 1, true) != null && ExtrasView.Preview(row, 1, true).Kind == "effects" && ExtrasView.Preview(row, 0, true) == null, "extras preview: a spell skin plays on the stage only for the card under the pointer");
            var kill = new OutfitExtrasPanel.ExtraRow { Key = "killfx", Label = "Kill effect" };
            kill.Options.Add(new OutfitExtrasPanel.Option { Text = "Default", Value = "0" });
            kill.Options.Add(new OutfitExtrasPanel.Option { Text = "Burst", Value = "9", Row = new CosRow { Id = "9", Kind = "killfx", Play = (List<object>)play } });
            check(ExtrasView.Preview(kill, 1, true).KillFx, "extras preview: a kill effect plays on a troll that dies");
            var rows = new List<OutfitExtrasPanel.ExtraRow> { row, kill };
            var none = ExtrasView.Bundle(rows, k => 1, null, -1);
            check(none == null, "extras preview: the chosen skins alone put no effect on the stage");
            var hover = ExtrasView.Bundle(rows, k => 1, "killfx", 1);
            check(hover != null && PreviewStage.EffectsOf(hover) != null && PreviewStage.EffectsOf(hover).KillFx, "extras preview: the hovered card does");
        }

        // ------------------------------------------------------------------------------------ client_chaos_topbar: the login screen
        static void LoginChecks(Action<bool, string> check)
        {
            var shown = LoginMenu.Shown(s => s);
            check(string.Join(",", shown.Select(e => e.Text)) == "Credits,Exit,Join Discord,Options,Sound", "login bar: the System entries of the main client that need no character, sorted (" + string.Join(",", shown.Select(e => e.Text)) + ")");
            check(!shown.Any(e => e.Text.IndexOf("Developer", StringComparison.OrdinalIgnoreCase) >= 0 || e.Text.IndexOf("Console", StringComparison.OrdinalIgnoreCase) >= 0 || e.Text.IndexOf("Admin", StringComparison.Ordinal) >= 0 || e.Text == "Logout"), "login bar: no Developer, Admin or Logout entry");
            var pt = LoginMenu.Shown(s => s == "Sound" ? "Som" : s == "Exit" ? "Sair" : s == "Options" ? "Opções" : s == "Credits" ? "Créditos" : "Entrar no Discord");
            check(pt[0].Text == "Credits" && pt[1].Text == "Join Discord" && pt[2].Text == "Options" && pt[3].Text == "Exit" && pt[4].Text == "Sound", "login bar: sorted by the shown text of the language, accents folded");
            check(LoginMenu.Entries.All(e => e.Target.StartsWith("act:")) && LoginMenu.Entries.Select(e => e.Id).Distinct().Count() == LoginMenu.Entries.Length, "login bar: every entry is an action with its own id");
            check(LoginMenu.Visible(false) && !LoginMenu.Visible(true), "login bar: shown before the login, not in the game");
            check(LoginMenu.IsOffline("Options") && LoginMenu.IsOffline("Exit") && !LoginMenu.IsOffline("Logout") && !LoginMenu.IsOffline("Helper") && !LoginMenu.IsOffline("Admin Panel"), "login bar: which in-game System entries it repeats");
            var system = TopMenu.Categories.First(c => c.Id == LoginMenu.Category);
            foreach (string t in new[] { "Options", "Credits", "Join Discord", "Exit" })
                check(system.Entries.Any(e => e.Text == t), "login bar: " + t + " is also an entry of the in-game System menu");
            check(LoginMenu.OptionPages.Length == 4 && LoginMenu.OptionPages[0] == "General" && LoginMenu.OptionPages.Contains("Sound"), "login bar: the options pages");
        }

        // ------------------------------------------------------------------------------------ game_chaoslayout: window sizes
        static void SizeChecks(Action<bool, string> check)
        {
            float w = 50, h = 20;
            WindowSize.Clamp(ref w, ref h, 800, 600);
            check(w == WindowSize.MinW && h == WindowSize.MinH, "window size: the smallest a window may be");
            w = 5000; h = 5000;
            WindowSize.Clamp(ref w, ref h, 800, 600);
            check(w == 800 && h == 600, "window size: not larger than the screen");
            w = float.NaN; h = 300;
            WindowSize.Clamp(ref w, ref h, 800, 600);
            check(w == WindowSize.MinW && h == 300, "window size: NaN becomes the minimum");
            w = 400; h = 300;
            WindowSize.Clamp(ref w, ref h, 100, 100);
            check(w == WindowSize.MinW && h == WindowSize.MinH, "window size: a tiny screen still keeps the minimum");
            WindowSize.GripRect(300, 200, out float gx, out float gy, out float gs);
            check(gx + gs <= 300 && gy + gs <= 200 && gx > 200 && gy > 100, "window size: the grip is in the bottom right corner");
            check(WindowSize.Valid(300, 200) && !WindowSize.Valid(100, 200) && !WindowSize.Valid(300, 50) && !WindowSize.Valid(30000, 200) && !WindowSize.Valid(float.NaN, 200), "window size: which saved sizes are restored");

            var l = new WindowLayout();
            l.Note("SkillsWindow", 10, 20, true);
            l.Note("BattleListWindow", 30, 40, false);
            l.NoteSize("SkillsWindow", 333, 222);
            check(l.Dirty && l.TryGet("SkillsWindow", out var slot) && slot.W == 333 && slot.H == 222, "layout size: the size of a window is noted");
            string json = l.ToJson();
            var back = WindowLayout.From(json);
            check(back.TryGet("SkillsWindow", out var s1) && s1.X == 10 && s1.Y == 20 && s1.Open && s1.W == 333 && s1.H == 222, "layout size: the size comes back with the place");
            check(back.TryGet("BattleListWindow", out var s2) && s2.W == 0 && s2.H == 0 && !s2.Open, "layout size: a window the player never resized has none");
            check(json.Contains("[10,20,true,333,222]") && json.Contains("[30,40,false]"), "layout size: only a resized window has the extra pair (" + json + ")");
            l.Dirty = false;
            l.NoteSize("SkillsWindow", 333, 222);
            check(!l.Dirty, "layout size: the same size is no change");
            l.NoteSize("SkillsWindow", 0, 0);
            check(l.Dirty && l.TryGet("SkillsWindow", out var s3) && s3.W == 0 && s3.H == 0 && !l.ToJson().Contains("333"), "layout size: a double click on the grip forgets the size");
            l.NoteSize("Unknown", 300, 300);
            check(!l.TryGet("Unknown", out _), "layout size: a size needs a noted window");
            var old = WindowLayout.From("{\"A\":[1,2,true]}");
            check(old.TryGet("A", out var s4) && s4.X == 1 && s4.W == 0 && s4.Open, "layout size: a layout saved before the sizes still reads");
            var junk = WindowLayout.From("{\"A\":[1,2,true,5,5],\"B\":[1,2,true,\"x\",300],\"C\":[1,2,false,400,300]}");
            check(junk.TryGet("A", out var j1) && j1.W == 0 && junk.TryGet("B", out var j2) && j2.W == 0 && junk.TryGet("C", out var j3) && j3.W == 400 && j3.H == 300, "layout size: a size too small or not a number is dropped, the place stays");
        }
    }
}
