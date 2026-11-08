// HUD models (track H): toasts, buff bar, cast bar, energy shield, monk chi, monster bar, anti-bot, options. JSON and text in
// and out through the extended opcode layer, and the rules of the main client's math modules.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class HudTests
    {
        sealed class Rig
        {
            public readonly ExtOpcodes Ext = new ExtOpcodes();
            public readonly List<byte[]> Sent = new List<byte[]>();
            public double Now;
            public readonly HudState Hud;
            public int Vocation;
            public Rig()
            {
                Ext.Transmit = p => Sent.Add(p);
                Hud = new HudState(Ext, () => Now, () => Vocation);
            }
            public void In(byte op, string json) => Ext.Receive(op, ExtOpcodes.ToWire(json));
            public void Text(byte op, string text) => Ext.Receive(op, text);
            /// <summary>The last packet sent as "op text".</summary>
            public string Last() { var p = Sent[Sent.Count - 1]; return p[1] + " " + Encoding.UTF8.GetString(p, 4, p.Length - 4); }
        }

        public static void Run(Action<bool, string> check)
        {
            Loc.Set("en");
            Toasts(check);
            Buffs(check);
            Cast(check);
            Shield(check);
            Chi(check);
            Monster(check);
            Bot(check);
            Options(check);
            Hello(check);
            Strings(check);
            Loc.Set("en");
        }

        // ------------------------------------------------------------------------------------ toasts
        static void Toasts(Action<bool, string> check)
        {
            var r = new Rig();
            var tc = r.Hud.Toasts;
            r.In(79, "{\"action\":\"achievement\",\"message\":\"The Thousandth Step: +50 points.\"}");
            check(tc.Active.Count == 1 && tc.Active[0].Type == "ACHIEVEMENT" && tc.Active[0].Style.DurationMs == 8000 && tc.Active[0].Style.TitleColor == "#5cc8c0", "toast: a flat message kind opens its toast type");
            r.In(79, "{\"action\":\"sale\",\"message\":\"x\"}");
            r.In(79, "{\"action\":\"market\",\"message\":\"y\"}");
            r.In(79, "{\"action\":\"pact\",\"message\":\"z\"}");
            check(tc.Active.Count == 3 && tc.Queue.Count == 1 && tc.Queue[0].Type == "PACT", "toast: three shown, the rest waits");
            r.In(79, "{\"action\":\"unknown\",\"message\":\"q\"}");
            r.In(79, "{\"action\":\"bounty\"}");
            check(tc.Queue.Count == 1, "toast: an unknown kind or a message without text is ignored");

            // time: the first one ends after 8 s, the queued one takes its place
            r.Now = 7999;
            tc.Tick(r.Now);
            check(tc.Active.Count == 3 && Math.Abs(tc.Active[0].Fraction(r.Now) - 1 / 8000.0) < 1e-9, "toast: timer fraction");
            r.Now = 8000;
            tc.Tick(r.Now);
            check(tc.Active.Count == 3 && tc.Queue.Count == 0 && tc.Active.Any(t => t.Type == "PACT") && tc.Active.All(t => t.Type != "ACHIEVEMENT"), "toast: an expired toast makes room for the queue");

            // queue limit: the oldest without buttons gives way, an invitation stays
            var q = new List<Toast>();
            Toast dropped = null;
            q.Add(new Toast { Type = "PARTY_INVITE", Style = ToastKinds.Styles["PARTY_INVITE"] });
            for (int i = 0; i < 12; i++) dropped = ToastCenter.Enqueue(q, new Toast { Type = "MARKET", Message = "m" + i, Style = ToastKinds.Styles["MARKET"] }, ToastKinds.QueueMax);
            check(q.Count == 12 && q[0].Type == "PARTY_INVITE" && dropped != null && dropped.Message == "m0", "toast: a full queue drops the oldest toast without buttons");

            // heights and stack
            bool cut;
            check(ToastKinds.HeightFor("MARKET", 20, out cut) == 110 && !cut, "toast: a short text keeps the base height");
            check(ToastKinds.HeightFor("MARKET", 100, out cut) == 28 + 100 + 18 && !cut, "toast: a long text grows the toast");
            check(ToastKinds.HeightFor("MARKET", 400, out cut) == 260 && cut, "toast: the height stops at 260, the text is cut");
            check(ToastKinds.HeightFor("PARTY_INVITE", 10, out cut) == 140, "toast: buttons make it 140");
            var ys = ToastKinds.Stack(new[] { 110, 140, 110 }, 46);
            check(ys[0] == 46 && ys[1] == 164 && ys[2] == 312, "toast: stacked below each other by height plus gap");

            // composed messages
            var r2 = new Rig();
            r2.In(79, "{\"action\":\"taskComplete\",\"taskName\":\"Dragons\",\"taskPoints\":100,\"killCount\":50,\"monsterLookType\":718}");
            var t0 = r2.Hud.Toasts.Active[0];
            check(t0.Type == "TASK_COMPLETE" && t0.Message == "Task Complete: of Dragons, killed 50 and received 100 task points" && t0.MonsterLook == 718, "toast: task complete message");
            r2.In(79, "{\"action\":\"taskComplete\",\"taskName\":\"x\"}");
            check(r2.Hud.Toasts.Active.Count == 1, "toast: a task message with missing fields is ignored");
            r2.In(79, "{\"action\":\"partyInvite\",\"inviterName\":\"Lury\",\"inviterResets\":30,\"element\":\"ice\",\"level\":1}");
            var inv = r2.Hud.Toasts.Active[1];
            check(inv.Message == "Lury [30] invited you to join their party for catacomb Ice level 1!" && inv.HasButtons, "toast: party invite text and buttons");
            r2.Sent.Clear();
            r2.Hud.Toasts.Accept(inv);
            check(r2.Last() == "151 accept_invite|Lury" && !r2.Hud.Toasts.Active.Contains(inv), "toast: Accept sends accept_invite on opcode 151 (plain text) and closes");
            r2.In(79, "{\"action\":\"partyInvite\",\"inviterName\":\"Bo\",\"level\":2,\"element\":\"fire\"}");
            r2.Hud.Toasts.Decline(r2.Hud.Toasts.Active.Last());
            check(r2.Last() == "151 decline_invite|Bo", "toast: Decline sends decline_invite");
            r2.In(79, "{\"action\":\"catacombFree\",\"element\":\"fire\",\"level\":3}");
            var cat = r2.Hud.Toasts.Active.Last();
            check(cat.Message == "The Fire Catacomb Level 3 is now free!", "toast: catacomb free text");
            r2.Hud.Toasts.Accept(cat);
            check(r2.Last() == "151 start_catacomb|solo|3|fire", "toast: Start sends start_catacomb|solo|level|element");
            r2.In(79, "{\"action\":\"catacombFree\",\"element\":\"ice\",\"level\":\"4\"}");
            r2.Hud.Toasts.Decline(r2.Hud.Toasts.Active.Last());
            check(r2.Last() == "152 leave_queue", "toast: declining a free catacomb sends leave_queue on 152");

            // danger line
            r2.Now = 1000;
            r2.In(79, "{\"action\":\"danger\",\"message\":\"Fire ahead\",\"caution\":true}");
            check(r2.Hud.Toasts.DangerShown(1000) && r2.Hud.Toasts.DangerCaution && r2.Hud.Toasts.DangerText == "Fire ahead" && !r2.Hud.Toasts.DangerShown(8001) && r2.Hud.Toasts.DangerShown(7999), "toast: danger line shows for 7 seconds");

            // every message type of the server maps to a style
            check(ToastKinds.MessageTypes.Values.All(v => ToastKinds.Styles.ContainsKey(v)), "toast: every message type has a style");
            check(ToastKinds.Styles.Count == 21, "toast: the 21 toast types of the main client");
        }

        // ------------------------------------------------------------------------------------ buff bar
        static void Buffs(Action<bool, string> check)
        {
            var r = new Rig();
            var b = r.Hud.Buffs;
            r.Now = 10000;
            check(b.ActiveNames(r.Now) == null, "buffs: no list yet");
            r.In(234, "{\"action\":\"full\",\"data\":{\"list\":[{\"k\":\"haste\",\"n\":\"Haste\",\"d\":\"Faster\",\"i\":\"buff:haste\",\"t\":0,\"l\":45000}," +
                       "{\"k\":\"burn\",\"n\":\"Burning\",\"i\":\"buff:burn\",\"t\":1,\"l\":3000,\"s\":2},{\"k\":\"aura\",\"n\":\"Holy Aura\",\"t\":0}]}}");
            check(b.Buffs.Count == 3 && b.Synced, "buffs: full list");
            var list = b.Ordered(out int nb);
            check(nb == 2 && list[0].Key == "haste" && list[1].Key == "aura" && list[2].Key == "burn", "buffs: buffs first, debuffs after, each in server order");
            check(Math.Abs(b.Buffs["haste"].Remaining(r.Now) - 45) < 1e-9 && b.Buffs["aura"].Remaining(r.Now) < 0 && b.Buffs["burn"].Stacks == 2, "buffs: time left, no timer, stacks");
            check(string.Join(",", b.ActiveNames(r.Now).OrderBy(x => x)) == "haste,holy aura", "buffs: active buff names exclude debuffs");

            r.Now = 20000;
            r.In(234, "{\"action\":\"diff\",\"data\":{\"add\":[{\"k\":\"shield\",\"n\":\"Magic Shield\",\"t\":0,\"l\":9000}],\"upd\":[{\"k\":\"haste\",\"l\":60000,\"s\":3}],\"del\":[\"aura\"]}}");
            check(b.Buffs.Count == 3 && !b.Buffs.ContainsKey("aura") && Math.Abs(b.Buffs["haste"].Remaining(r.Now) - 60) < 1e-9 && b.Buffs["haste"].Stacks == 3, "buffs: diff adds, updates and removes");
            r.In(234, "{\"action\":\"diff\",\"data\":{\"upd\":[{\"k\":\"nope\",\"l\":1}]}}");
            check(b.Buffs.Count == 3, "buffs: an update of an unknown key changes nothing");

            // a lost del: pruned 1.5 s past the end
            check(b.Prune(r.Now) == 1 && !b.Buffs.ContainsKey("burn") && b.Buffs.Count == 2, "buffs: prune drops the debuff whose time is long over");
            var r2 = new Rig();
            r2.In(234, "{\"action\":\"full\",\"data\":{\"list\":[{\"k\":\"a\",\"n\":\"A\",\"t\":0,\"l\":1000}]}}");
            check(r2.Hud.Buffs.Prune(2400) == 0 && r2.Hud.Buffs.Prune(2501) == 1, "buffs: a timed buff is dropped 1.5 s after its end");

            check(BuffBar.Format(45) == "45s" && BuffBar.Format(65) == "1:05" && BuffBar.Format(720) == "12m" && BuffBar.Format(7200) == "2h" && BuffBar.Format(90000) == "1d" && BuffBar.Format(-1) == "" && BuffBar.Format(0.2) == "1s", "buffs: compact time");
            check(BuffBar.FormatLong(3909) == "1h 05m 09s" && BuffBar.FormatLong(303) == "5m 03s" && BuffBar.FormatLong(45) == "45s", "buffs: long time");
            var e = b.Buffs["haste"];
            string tip = BuffBar.Tooltip(e, r.Now, false);
            check(tip.StartsWith("Haste\n") && tip.Contains("Stacks: 3") && tip.Contains("Time left: 1m 00s") && tip.Contains("Hold Alt for what it does."), "buffs: tooltip without Alt");
            string tipAlt = BuffBar.Tooltip(e, r.Now, true);
            check(tipAlt.Contains("Faster") && !tipAlt.Contains("Hold Alt"), "buffs: tooltip with Alt shows the description");
            check(BuffBar.Label(new BuffEntry { Name = "Holy Aura", Key = "aura" }) == "HA" && BuffBar.Label(new BuffEntry { Name = "Haste", Key = "h" }) == "HAS", "buffs: short label");
            var cd = BuffBar.Colour(new BuffEntry { Key = "burn", Debuff = true });
            var cb = BuffBar.Colour(new BuffEntry { Key = "haste" });
            check(cd[0] > cd[1] && cd[0] > cd[2] && cb.All(x => x >= 0 && x <= 1.01f), "buffs: debuff squares are red, buff colours stay in range");
            var cells = BuffBar.Flow(5, 80, 26, 2, out int height);
            check(cells.Count == 5 && cells[1] == (28, 0) && cells[2] == (0, 28) && height == 3 * 28 - 2, "buffs: cells flow in rows");
            BuffBar.Flow(0, 80, 26, 2, out int h0);
            check(h0 == 0, "buffs: an empty bar takes no space");
            b.Clear();
            check(b.Buffs.Count == 0 && !b.Synced, "buffs: clear");
            r.Sent.Clear();
            b.Sync();
            check(r.Last() == "234 {\"action\":\"sync\",\"data\":{}}", "buffs: sync message: " + r.Last());
        }

        // ------------------------------------------------------------------------------------ cast bar
        static void Cast(Action<bool, string> check)
        {
            var r = new Rig();
            var c = r.Hud.Cast;
            r.Now = 1000;
            r.In(231, "{\"action\":\"start\",\"data\":{\"s\":5,\"n\":\"Doomtide\",\"ms\":2000}}");
            check(c.Casting && c.Mine.Name == "Doomtide" && c.Mine.Ms == 2000 && c.MineText(1000) == "Doomtide  2.0s", "cast: own bar starts");
            check(Math.Abs(CastBar.Progress(1000, 2000, 2000) - 0.5) < 1e-9 && CastBar.Progress(1000, 2000, 500) == 0 && CastBar.Progress(1000, 2000, 9000) == 1 && CastBar.Progress(0, 0, 5) == 1, "cast: progress");
            check(CastBar.Label("Doomtide", 2000, 1200) == "Doomtide  0.8s", "cast: label with one decimal");
            r.In(231, "{\"action\":\"start\",\"data\":{\"n\":\"Bad\",\"ms\":0}}");
            check(c.Mine.Name == "Doomtide", "cast: a start without time is ignored");
            r.In(231, "{\"action\":\"end\",\"data\":{\"s\":4,\"r\":\"moved\"}}");
            check(c.Casting, "cast: an end for another serial is ignored");
            r.Now = 2500;
            r.In(231, "{\"action\":\"end\",\"data\":{\"s\":5,\"r\":\"moved\"}}");
            check(!c.Casting && c.MineText(r.Now) == "Interrupted: moved" && CastBar.State(c.Mine) == "interrupted", "cast: interrupted shows its reason");
            c.Tick(r.Now + 899);
            check(c.Mine != null, "cast: the result stays for 900 ms");
            c.Tick(r.Now + 900);
            check(c.Mine == null, "cast: then it goes");
            r.In(231, "{\"action\":\"start\",\"data\":{\"s\":6,\"n\":\"Wave\",\"ms\":1000}}");
            r.In(231, "{\"action\":\"end\",\"data\":{\"s\":6,\"r\":\"done\"}}");
            check(c.MineText(r.Now) == "Wave" && CastBar.State(c.Mine) == "done" && CastBar.ResultLabel("done") == null, "cast: done shows the name");
            c.Tick(r.Now + 250);
            check(c.Mine == null, "cast: a done bar goes after 250 ms");
            // a lost end
            r.Now = 10000;
            r.In(231, "{\"action\":\"start\",\"data\":{\"s\":7,\"n\":\"Lost\",\"ms\":1000}}");
            c.Tick(r.Now + 1000 + 4001);
            check(c.Mine != null && c.Mine.EndAt >= 0 && c.Mine.Result == "done", "cast: a cast whose end never came is closed as done");
            // cancel
            var r3 = new Rig();
            r3.In(231, "{\"action\":\"start\",\"data\":{\"s\":1,\"n\":\"Slow\",\"ms\":3000}}");
            check(r3.Hud.Cast.Cancel() && r3.Last() == "231 {\"action\":\"cancel\"}", "cast: clicking the bar cancels: " + r3.Last());
            r3.In(231, "{\"action\":\"end\",\"data\":{\"s\":1,\"r\":\"cancel\"}}");
            check(!r3.Hud.Cast.Cancel() && CastBar.ResultLabel("cancel") == "Cancelled" && CastBar.ResultLabel("weird") == "Interrupted", "cast: no cancel after the end; result texts");
            // others
            r3.Now = 500;
            r3.In(231, "{\"action\":\"other\",\"data\":{\"c\":4294967290,\"n\":\"Mage\",\"ms\":1500}}");
            check(r3.Hud.Cast.Others.ContainsKey(4294967290u), "cast: another caster");
            r3.In(231, "{\"action\":\"otherEnd\",\"data\":{\"c\":4294967290,\"r\":\"hit\"}}");
            r3.Hud.Cast.Tick(500 + 599);
            check(r3.Hud.Cast.Others.Count == 1, "cast: an ended bar of another caster stays 600 ms");
            r3.Hud.Cast.Tick(500 + 600);
            check(r3.Hud.Cast.Others.Count == 0, "cast: and goes");
            r3.In(231, "{\"action\":\"other\",\"data\":{\"c\":9,\"ms\":-1}}");
            check(r3.Hud.Cast.Others.Count == 0, "cast: an invalid other is ignored");
        }

        // ------------------------------------------------------------------------------------ shield and chi
        static void Shield(Action<bool, string> check)
        {
            int cur, max;
            check(EnergyShield.Parse("es:350:500", out cur, out max) && cur == 350 && max == 500, "shield: parse");
            check(EnergyShield.Parse("es:900:500", out cur, out max) && cur == 500, "shield: current is capped at max");
            check(EnergyShield.Parse("es:-5:-2", out cur, out max) && cur == 0 && max == 0, "shield: negatives become 0");
            check(!EnergyShield.Parse("es:1", out cur, out max) && !EnergyShield.Parse("chi:1:2", out cur, out max) && !EnergyShield.Parse("es:a:b", out cur, out max) && !EnergyShield.Parse(null, out cur, out max), "shield: bad text is refused");
            check(EnergyShield.Ease(0, 100, 450, 900) == 50 && EnergyShield.Ease(0, 100, 900, 900) == 100 && EnergyShield.Ease(80, 20, 300, 900) == 60, "shield: easing");
            check(EnergyShield.FillWidth(0, 100, 50) == 0 && EnergyShield.FillWidth(1, 1000, 50) == 1 && EnergyShield.FillWidth(100, 100, 50) == 50 && EnergyShield.Pair(350, 15300) == "350 / 15.3k", "shield: fill width and the short pair");

            var r = new Rig();
            r.Now = 1000;
            r.Text(224, "es:200:500");
            var s = r.Hud.Shield;
            check(s.Visible && s.Current == 200 && s.Max == 500, "shield: plain text on opcode 224");
            check(s.Tick(1000) == 0 && s.Tick(1450) == 100 && s.Tick(1900) == 200, "shield: eased from 0 to 200 over 900 ms");
            r.Now = 3000;
            r.Text(224, "es:100:500");
            check(s.Tick(3450) == 150 && s.Tick(3900) == 100, "shield: eases down");
            r.Text(224, "es:0:0");
            check(!s.Visible && s.Tick(4000) == 0, "shield: max 0 hides it");
            r.Text(224, "garbage");
            check(!s.Visible, "shield: garbage changes nothing");
            r.Sent.Clear();
            s.Hello();
            check(r.Last() == "224 hello", "shield: hello is plain text");
        }

        static void Chi(Action<bool, string> check)
        {
            int chi, max, decay;
            check(MonkChi.Parse("chi:3:5:8", out chi, out max, out decay) && chi == 3 && max == 5 && decay == 8, "chi: parse");
            check(MonkChi.Parse("chi:9:5:8", out chi, out max, out decay) && chi == 5, "chi: capped at max");
            check(!MonkChi.Parse("chi:3:5", out chi, out max, out decay) && !MonkChi.Parse("chi:-1:5:8", out chi, out max, out decay) && !MonkChi.Parse("es:1:2:3", out chi, out max, out decay) && !MonkChi.Parse("chi:a:5:8", out chi, out max, out decay), "chi: bad text refused");
            check(MonkChi.IsMonk(17) && MonkChi.IsMonk(19) && !MonkChi.IsMonk(16) && !MonkChi.IsMonk(20), "chi: monk vocations 17-19");
            check(MonkChi.Pip(2, 2, 5) == "full" && MonkChi.Pip(3, 2, 5) == "empty" && MonkChi.Pip(6, 2, 5) == "hidden", "chi: pip looks");

            var r = new Rig();
            r.Vocation = 18;
            r.Now = 1000;
            r.Text(247, "chi:3:5:8");
            var c = r.Hud.Chi;
            check(c.Active && c.Shown(1000) == 3 && c.Shown(8999) == 3 && c.Shown(9000) == 0, "chi: pips empty after the decay seconds");
            check(Math.Abs(c.FadeIn(5000) - 4) < 1e-9 && c.FadeIn(20000) == 0, "chi: seconds until it fades");
            r.Text(247, "chi:0:5:8");
            check(c.FadeIn(2000) < 0 && c.Shown(2000) == 0, "chi: no fade without chi");
            r.Vocation = 3;
            r.Text(247, "chi:2:5:8");
            check(!c.Active && c.Shown(2000) == 0, "chi: a character who is not a Monk hides the HUD");
            r.Vocation = 0;
            r.Text(247, "chi:2:5:0");
            check(c.Active && c.Shown(1e9) == 2, "chi: unknown vocation does not hide; decay 0 never fades");
        }

        // ------------------------------------------------------------------------------------ monster bar
        static void Monster(Action<bool, string> check)
        {
            var r = new Rig();
            var m = r.Hud.Monster;
            r.Now = 1000;
            m.Update(77, "Dragon", 100, r.Now, 16);
            check(r.Last() == "125 {\"action\":\"query\",\"data\":{\"cid\":77}}", "monster: a new target is queried: " + r.Last());
            int n = r.Sent.Count;
            m.Update(77, "Dragon", 100, r.Now + 100, 16);
            check(r.Sent.Count == n, "monster: the same target is not queried again");
            m.Update(0, null, 0, r.Now + 200, 16);
            m.Update(77, "Dragon", 100, r.Now + 300, 16);
            check(r.Sent.Count == n + 1, "monster: a target picked again is asked again (the level can change)");

            r.In(125, "{\"action\":\"info\",\"data\":{\"cid\":77,\"tier\":\"rare\",\"label\":\"Rare\",\"level\":420,\"mods\":[\"Blazing\",\"Swift\"]}}");
            var info = m.Info(77);
            check(info != null && info.Tier == "rare" && info.Level == 420 && info.Mods.Count == 2 && m.Key(77) == "rare", "monster: info from the server");
            r.In(125, "{\"action\":\"info\",\"data\":{\"cid\":77,\"tier\":\"rare\",\"role\":\"guardian\"}}");
            check(m.Info(77).Level == 420 && m.Key(77) == "guardian", "monster: the level is kept when the answer has none; a role wins over the tier");
            check(MonsterBar.StyleKey("legendary", null) == "legendary" && MonsterBar.StyleKey(null, null) == "normal" && MonsterBar.StyleKey("zzz", "omen") == "omen" && MonsterBar.StyleKey("zzz", null) == "normal", "monster: style keys");
            check(MonsterBar.Title("rare", "Rare", "Dragon") == "Rare Dragon" && MonsterBar.Title("normal", "", "Rat") == "Rat" && MonsterBar.Title("guardian", "Legendary", "Golem") == "Rift Guardian Golem" && MonsterBar.Title("boss", "", "Kaelgor") == "Kaelgor" && MonsterBar.Title("omen", "x", "O") == "Omen Guardian O", "monster: title tag");
            check(MonsterBar.LevelText(420) == "Lv 420" && MonsterBar.LevelText(0) == null && MonsterBar.PercentText(73) == "73%" && MonsterBar.PercentText(150) == "100%", "monster: level and percent text");
            check(MonsterBar.FillWidth(0, 200) == 0 && MonsterBar.FillWidth(0.1, 200) == 1 && MonsterBar.FillWidth(50, 200) == 100 && MonsterBar.FillWidth(100, 200) == 200, "monster: fill width keeps a sliver");
            check(MonsterBar.ModTip("Blazing").StartsWith("Blazing:") && MonsterBar.ModTip("Odd One") == "Odd One", "monster: modifier tips");
            // contrast of a tier colour against the dark ground, WCAG, at least 4.5 (monsterbarstyle_test.lua)
            double ground = Lum("#2a0c0a");
            bool contrast = true;
            foreach (var kv in MonsterBar.Styles)
            {
                double l = Lum(kv.Value.name);
                contrast &= (Math.Max(l, ground) + 0.05) / (Math.Min(l, ground) + 0.05) >= 4.5;
            }
            check(contrast, "monster: every tier colour reads on a dark ground");

            // the damage trail: holds 350 ms then shrinks
            var t = new Rig();
            var tm = t.Hud.Monster;
            tm.Update(5, "Orc", 100, 0, 16);
            tm.Update(5, "Orc", 60, 16, 16);
            check(tm.TrailValue == 100 && tm.TrailHoldLeft > 0, "monster: a hit leaves the old health lit");
            for (int i = 0; i < 30; i++) tm.Update(5, "Orc", 60, 32 + i * 10, 10);   // 300 ms: still held
            check(tm.TrailValue == 100, "monster: the trail holds");
            for (int i = 0; i < 200; i++) tm.Update(5, "Orc", 60, 400 + i * 16, 16);
            check(Math.Abs(tm.TrailValue - 60) < 0.01, "monster: then the trail shrinks to the health");
            tm.Update(5, "Orc", 90, 5000, 16);
            check(tm.TrailValue == 90, "monster: healing past the trail leaves nothing lit");

            // boss mechanics
            r.Now = 5000;
            r.In(125, "{\"action\":\"mech\",\"data\":{\"cid\":9,\"boss\":\"Kaelgor\",\"label\":\"Meteor Rain\",\"ms\":3000,\"kind\":\"telegraph\"}}");
            var mech = m.Mech;
            check(mech != null && mech.Kind == "telegraph" && mech.Ms == 3000, "monster: mechanic cast starts");
            check(MonsterBar.MechText(mech, 5000 + 600) == "Kaelgor: Meteor Rain 2.4s - move out", "monster: mechanic text: " + MonsterBar.MechText(mech, 5600));
            check(MonsterBar.MechFill(mech, 6500, 100) == 50 && MonsterBar.MechFill(mech, 8000, 100) == 100 && MonsterBar.MechFill(mech, 9000, 100) == 0, "monster: mechanic fill");
            check(MonsterBar.MechText(mech, 8000) == "Kaelgor: Meteor Rain" && MonsterBar.MechVisible(mech, 8600) && !MonsterBar.MechVisible(mech, 8601), "monster: stays 600 ms after the hit");
            r.In(125, "{\"action\":\"mech\",\"data\":{\"cid\":9,\"boss\":\"Kaelgor\",\"label\":\"x\",\"ms\":0,\"kind\":\"interrupted\"}}");
            check(m.Mech.Kind == "interrupted" && m.Mech.Label == "Meteor Rain" && MonsterBar.MechText(m.Mech, 5000).EndsWith("- interrupted!") && MonsterBar.MechFill(m.Mech, 5000, 80) == 80, "monster: an interrupt keeps the label");
            check(MonsterBar.StartMech(Json.Parse("{\"label\":\"A\",\"ms\":10,\"kind\":\"nonsense\"}"), 0).Kind == "telegraph" && MonsterBar.StartMech(Json.Parse("{\"ms\":10}"), 0) == null, "monster: unknown kind falls back; no label is not a cast");
            m.Tick(1e9);
            check(m.Mech == null, "monster: a finished mechanic is dropped");
        }

        static double Lum(string hex)
        {
            Func<int, double> ch = v => { double c = v / 255.0; return c <= 0.03928 ? c / 12.92 : Math.Pow((c + 0.055) / 1.055, 2.4); };
            return 0.2126 * ch(Convert.ToInt32(hex.Substring(1, 2), 16)) + 0.7152 * ch(Convert.ToInt32(hex.Substring(3, 2), 16)) + 0.0722 * ch(Convert.ToInt32(hex.Substring(5, 2), 16));
        }

        // ------------------------------------------------------------------------------------ anti-bot
        static void Bot(Action<bool, string> check)
        {
            var r = new Rig();
            var bot = r.Hud.Bot;
            r.Now = 1000;
            r.In(211, "{\"action\":\"check\",\"data\":{\"t\":\"tok1\",\"w\":\"sword\",\"o\":[{\"k\":\"a\",\"c\":3264},{\"k\":\"b\",\"c\":3277},{\"k\":\"c\",\"c\":3031}],\"s\":60,\"a\":1,\"r\":2}}");
            check(bot.Check != null && bot.Check.Word == "sword" && bot.Check.Options.Count == 3 && bot.Check.Options[1].ClientId == 3277 && bot.Check.Seconds == 60 && bot.Check.Retries == 2 && bot.TotalSeconds == 60, "antibot: a check is parsed");
            check(Antibot.Prompt("sword") == "Click the picture of: sword" && Antibot.TimeText(65) == "1:05" && Antibot.TimeText(9) == "0:09", "antibot: prompt and time text");
            check(Antibot.TimeColor(30) == "#d6c9ae" && Antibot.TimeColor(25) == "#e8b84a" && Antibot.TimeColor(10) == "#e03a1e" && Antibot.TimePercent(30, 60) == 50 && Antibot.TimePercent(5, 0) == 0, "antibot: countdown colour and percent");
            check(Math.Abs(bot.SecondsLeft(31000) - 30) < 1e-9 && bot.SecondsLeft(99999999) == 0, "antibot: seconds left");
            check(Antibot.RetryText(1) == "Another picture" && Antibot.RetryText(0) == "No more pictures", "antibot: retry text");

            r.Sent.Clear();
            check(bot.Answer("b") && r.Last() == "211 {\"action\":\"answer\",\"data\":{\"t\":\"tok1\",\"k\":\"b\"}}" && bot.Locked, "antibot: answering sends token and key: " + r.Last());
            check(!bot.Answer("a"), "antibot: a second answer waits for the result");
            r.In(211, "{\"action\":\"checkResult\",\"data\":{\"retry\":true,\"text\":\"Not that one\"}}");
            check(bot.Status == "Not that one" && bot.Check != null, "antibot: a wrong answer keeps the dialog");
            r.In(211, "{\"action\":\"check\",\"data\":{\"t\":\"tok2\",\"w\":\"shield\",\"o\":[{\"k\":\"a\",\"c\":1},{\"k\":\"b\",\"c\":2}],\"s\":50,\"a\":2,\"r\":1}}");
            check(bot.Check.Token == "tok2" && bot.TotalSeconds == 60 && !bot.Locked && bot.Status == "A new picture. Take your time.", "antibot: a new picture keeps the total time and unlocks");
            r.Sent.Clear();
            check(bot.Another() && r.Last() == "211 {\"action\":\"another\",\"data\":{\"t\":\"tok2\"}}", "antibot: another picture: " + r.Last());
            r.In(211, "{\"action\":\"check\",\"data\":{\"t\":\"tok3\",\"w\":\"axe\",\"o\":[{\"k\":\"a\",\"c\":1},{\"k\":\"b\",\"c\":2}],\"s\":50,\"a\":3,\"r\":0}}");
            check(!bot.Another(), "antibot: no more pictures when retries is 0");
            r.Now = 5000;
            r.In(211, "{\"action\":\"checkResult\",\"data\":{\"ok\":true,\"text\":\"Thank you\"}}");
            check(bot.StatusGood && bot.Locked && bot.CloseAt == 6500, "antibot: a right answer closes in 1.5 s");
            bot.Tick(6499);
            check(bot.Check != null, "antibot: still shown");
            bot.Tick(6500);
            check(bot.Check == null, "antibot: closed");
            r.In(211, "{\"action\":\"check\",\"data\":{\"t\":\"t\",\"w\":\"w\",\"o\":[{\"k\":\"a\",\"c\":1}],\"s\":5}}");
            check(bot.Check == null, "antibot: a check with one option is refused");
            r.In(211, "{\"action\":\"check\",\"data\":{\"t\":\"t\",\"w\":\"w\",\"o\":[{\"k\":\"a\",\"c\":0},{\"k\":\"b\",\"c\":2}],\"s\":5}}");
            check(bot.Check == null, "antibot: an option without a client id is refused");
            r.In(211, "{\"action\":\"check\",\"data\":{\"w\":\"w\",\"o\":[{\"k\":\"a\",\"c\":1},{\"k\":\"b\",\"c\":2}],\"s\":5}}");
            check(bot.Check == null, "antibot: a check without a token is refused");
            r.In(211, "{\"action\":\"check\",\"data\":{\"t\":\"t\",\"w\":\"w\",\"o\":[{\"k\":\"a\",\"c\":1},{\"k\":\"b\",\"c\":2}],\"s\":-4,\"a\":0}}");
            check(bot.Check.Seconds == 0 && bot.Check.Attempt == 1, "antibot: negative seconds and attempt 0 are clamped");

            // reports
            r.Sent.Clear();
            bot.OpenReport("Bad Guy");
            check(r.Last() == "211 {\"action\":\"reportOpen\",\"data\":{\"name\":\"Bad Guy\"}}", "report: open goes through the server: " + r.Last());
            r.In(211, "{\"action\":\"reportOpen\",\"data\":{\"name\":\"Bad Guy\",\"noteMax\":120,\"reasons\":[{\"k\":\"botting\",\"n\":\"Botting\"},{\"k\":\"other\",\"n\":\"Other\"}]}}");
            check(bot.ReportOpen && bot.Reasons.Count == 2 && bot.ReportNoteMax == 120 && bot.ReportName == "Bad Guy", "report: reasons and note size from the server");
            r.In(211, "{\"action\":\"reportOpen\",\"data\":{\"reasons\":[]}}");
            check(bot.Reasons.Count == 6 && bot.ReportNoteMax == 200, "report: no reasons falls back to the default six");
            string err;
            check(Antibot.ReportMessage("a", "botting", "", "Me", 200, out err) == null && err == "Type the name of the character you want to report.", "report: a name too short");
            check(Antibot.ReportMessage("9bad", "botting", "", "Me", 200, out err) == null, "report: a name must start with a letter");
            check(Antibot.ReportMessage("me", "botting", "", "Me", 200, out err) == null && err == "You cannot report yourself.", "report: not yourself (any case)");
            check(Antibot.ReportMessage("Bad Guy", "", "", "Me", 200, out err) == null && err == "Choose a reason.", "report: a reason is needed");
            check(Antibot.ReportMessage("Bad Guy", "other", "ab", "Me", 200, out err) == null && err.StartsWith("Describe"), "report: Other needs a note of 3 characters");
            var msg = Antibot.ReportMessage("  Bad Guy ", "other", "  he  said\tit  \n", "Me", 200, out err);
            check(msg != null && (string)msg["name"] == "Bad Guy" && (string)msg["note"] == "he said it" && (string)msg["reason"] == "other", "report: the message is cleaned");
            check(Antibot.CleanNote("ação\u0001 x", 200) == "ao x" && Antibot.CleanNote(new string('x', 300), 200).Length == 200 && Antibot.NoteCounter("abc", 200) == "3/200", "report: note cleaning and counter");
            check(Antibot.ValidName("Sir O'Neil-Smith") && !Antibot.ValidName("A") && !Antibot.ValidName(new string('a', 30)) && !Antibot.ValidName("Bob1"), "report: name rule");
            check(Antibot.CanReport(true, false) && !Antibot.CanReport(true, true) && !Antibot.CanReport(false, false), "report: only other players");
            r.Sent.Clear();
            check(bot.SendReport("Bad Guy", "botting", "afk bot", "Me") && r.Last() == "211 {\"action\":\"report\",\"data\":{\"name\":\"Bad Guy\",\"reason\":\"botting\",\"note\":\"afk bot\"}}", "report: send: " + r.Last());
            check(!bot.SendReport("Me", "botting", "", "Me") && bot.ReportStatus == "You cannot report yourself.", "report: an invalid report shows the error and sends nothing");
            r.Now = 9000;
            r.In(211, "{\"action\":\"reportResult\",\"data\":{\"ok\":true,\"text\":\"Report sent\"}}");
            check(bot.ReportStatus == "Report sent" && bot.ReportSent && bot.ReportCloseAt == 11500, "report: result closes in 2.5 s");
            bot.Tick(11500);
            check(!bot.ReportOpen, "report: closed");
        }

        // ------------------------------------------------------------------------------------ options
        static void Options(Action<bool, string> check)
        {
            var r = new Rig();
            var o = r.Hud.Options;
            check(HudOptions.IsOn(null) && HudOptions.IsOn("on") && !HudOptions.IsOn("false") && !HudOptions.IsOn("0"), "options: on unless explicitly off");
            check(HudOptions.NeedsSend(null, true, false) && !HudOptions.NeedsSend(true, true, false) && HudOptions.NeedsSend(true, false, false) && HudOptions.NeedsSend(true, true, true), "options: send on a new session, a change or a force");
            r.Sent.Clear();
            o.SendAll("pt-BR");
            string all = string.Join(" | ", r.Sent.Select(p => p[1] + " " + Encoding.UTF8.GetString(p, 4, p.Length - 4)));
            check(all == "186 {\"on\":true} | 188 {\"on\":true} | 157 {\"action\":\"hello\",\"data\":{\"lang\":\"pt-BR\"}}", "options: login messages: " + all);
            r.Sent.Clear();
            o.SetKeepAttacking(true);
            check(r.Sent.Count == 0, "options: an unchanged value is not sent again");
            o.SetKeepAttacking(false);
            check(r.Last() == "186 {\"on\":false}", "options: kitewalk off: " + r.Last());
            o.SetRightClickEquips(false);
            check(r.Last() == "188 {\"on\":false}", "options: right-click equips off");
            r.Sent.Clear();
            o.SendHello("xx");
            check(r.Last() == "157 {\"action\":\"hello\",\"data\":{\"lang\":\"en\"}}", "options: an unknown language says en");

            // scale
            r.In(157, "{\"action\":\"scale\",\"data\":{\"level\":150,\"f\":25}}");
            check(o.ScaleFactor == 25 && o.ScaleLevel == 150 && o.Scaled(4) == 100 && !o.LevelChanged(150) && o.LevelChanged(151) && !o.LevelChanged(0), "options: display scale from the server");
            r.In(157, "{\"action\":\"scale\",\"data\":{\"level\":1,\"f\":0}}");
            r.In(157, "{\"action\":\"scale\",\"data\":{\"level\":1,\"f\":2000000000}}");
            check(o.ScaleFactor == 25, "options: a factor out of range is ignored");
            r.In(157, "{\"action\":\"scale\",\"data\":{\"level\":151,\"f\":25.9}}");
            check(o.ScaleFactor == 25 && o.ScaleLevel == 151, "options: the factor is a whole number");
            r.In(188, "{\"action\":\"multiuse\",\"data\":{\"ids\":[3300,3301,\"x\"]}}");
            check(o.MultiUseIds.SetEquals(new[] { 3300, 3301 }), "options: the multi-use look list of the server");
            o.Reset();
            check(o.ScaleFactor == 1 && o.MultiUseIds.Count == 0, "options: reset");
            check(HudOptions.LanguageChoices.Select(c => c[0]).SequenceEqual(Loc.Languages), "options: the language choices are the Loc languages");
        }

        static void Hello(Action<bool, string> check)
        {
            var r = new Rig();
            r.Hud.Hello("en");
            var msgs = r.Sent.Select(p => p[1] + " " + Encoding.UTF8.GetString(p, 4, p.Length - 4)).ToList();
            check(msgs.Count == 5 && msgs[0] == "186 {\"on\":true}" && msgs[3] == "224 hello" && msgs[4].StartsWith("234 {\"action\":\"sync\""), "hud: login hello sends options, language, shield hello and the buff sync: " + string.Join(" | ", msgs));
            r.Sent.Clear();
            r.Hud.Hello("en");
            check(r.Sent.Count == 0, "hud: the hello goes out once");
            // a bad message does not break the others
            r.In(234, "not json");
            r.In(79, "{\"action\":\"market\",\"message\":\"ok\"}");
            check(r.Hud.Toasts.Active.Count == 1, "hud: an invalid message is skipped");
        }

        // ------------------------------------------------------------------------------------ texts
        static void Strings(Action<bool, string> check)
        {
            // every key the HUD asks for (Loc.T literals of Core/Hud.cs, the dynamic tables) has a pt-BR entry
            var keys = new HashSet<string>();
            foreach (var s in ToastKinds.Styles.Values) keys.Add(s.Title);
            foreach (var kv in MonsterBar.Styles) if (kv.Value.label.Length > 0) keys.Add(kv.Value.label);
            foreach (var s in MonsterBar.Mods.Values) keys.Add(s);
            foreach (var s in MonsterBar.MechHints.Values) keys.Add(s);
            foreach (var s in CastBar.ResultText.Values) keys.Add(s);
            foreach (var rr in Antibot.DefaultReasons()) keys.Add(rr.Name);
            string file = Path.GetFullPath(Path.Combine("..", "Client", "Assets", "Chaos", "Core", "Hud.cs"));
            if (!File.Exists(file)) file = Path.GetFullPath(Path.Combine("unity", "Client", "Assets", "Chaos", "Core", "Hud.cs"));
            if (File.Exists(file))
                foreach (Match m in Regex.Matches(File.ReadAllText(file), "\\bLoc\\.T\\(\"((?:[^\"\\\\]|\\\\.)*)\""))
                    keys.Add(m.Groups[1].Value);
            var missing = keys.Where(k => !LocStrings.PtBr.ContainsKey(k)).ToList();
            check(missing.Count == 0, "hud: every text of the models has a pt-BR entry" + (missing.Count > 0 ? ": " + string.Join(" | ", missing) : " (" + keys.Count + " keys)"));
            // placeholders survive translation
            var bad = HudStrings.PtBr.Where(kv => Regex.Matches(kv.Key, "\\{\\d\\}").Count != Regex.Matches(kv.Value, "\\{\\d\\}").Count).Select(kv => kv.Key).ToList();
            check(bad.Count == 0, "hud: translations keep their {n} placeholders" + (bad.Count > 0 ? ": " + string.Join(" | ", bad) : ""));
            Loc.Set("pt-BR");
            check(Loc.T("Options") == "Opções" && BuffBar.Tooltip(new BuffEntry { Name = "X", Key = "x" }, 0, false).Contains("Sem limite de tempo") && CastBar.ResultLabel("moved") == "Interrompida: você se mexeu", "hud: pt-BR texts reach the models");
            Loc.Set("en");
        }
    }
}
