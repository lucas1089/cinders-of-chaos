// Progression systems: the passive tree (layout file, planner, opcode 65 messages, build codes with the shared vectors of
// docs/build_code_vectors.txt), the combat stat rows and simple skills (119), goals (178), the hunt tracker (241), the rift HUD (228),
// the Info and Services pages (237) and the level-gated top menu (115).
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

namespace Chaos.Core.Tests
{
    static class ProgressionTests
    {
        static string Text(byte[] sent) => Encoding.UTF8.GetString(sent, 4, sent.Length - 4);

        static string Find(params string[] relative)
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

        static void Msg(ExtOpcodes ext, byte op, string json) => ext.Receive(op, ExtOpcodes.ToWire(json));

        public static void Run(Action<bool, string> check)
        {
            Loc.Set("en");
            TreeFile(check);
            Planner(check);
            TreeMessages(check);
            BuildCodes(check);
            SkillRows(check);
            GoalsChecks(check);
            HuntChecks(check);
            RiftChecks(check);
            InfoChecks(check);
            MenuChecks(check);
            LocChecks(check);
        }

        // ------------------------------------------------------------------------------------ the tree layout file
        static PassiveTree Tree(out ExtOpcodes ext, out List<byte[]> sent)
        {
            ext = new ExtOpcodes();
            var list = new List<byte[]>();
            ext.Transmit = p => list.Add(p);
            sent = list;
            var tree = new PassiveTree(ext);
            string path = Find("unity", "Client", "Assets", "Chaos", "Resources", "PassiveTree.json") ?? Find("Client", "Assets", "Chaos", "Resources", "PassiveTree.json");
            if (path != null) tree.Load(File.ReadAllText(path));
            return tree;
        }

        static void TreeFile(Action<bool, string> check)
        {
            var tree = Tree(out _, out _);
            check(tree.Ready, "passive tree: PassiveTree.json found and parsed");
            if (!tree.Ready) return;
            var d = tree.Data;
            check(d.Nodes.Count > 600 && d.Nodes.ContainsKey(1) && d.Nodes[1].IsStart, "passive tree: " + d.Nodes.Count + " nodes, node 1 is the root");
            int starts = d.Ordered.Count(n => n.IsStart), keystones = d.Ordered.Count(n => n.Type == 'd'), masteries = d.Ordered.Count(n => n.IsMastery);
            check(starts == 8 && masteries == 7 && keystones >= 30, "passive tree: 8 start nodes (the root and seven class sections), 7 masteries, keystones (" + starts + "/" + masteries + "/" + keystones + ")");
            // links are symmetric over the shown graph
            tree.Line = "";
            var adj = tree.Graph();
            bool symmetric = adj.All(kv => kv.Value.All(o => adj.ContainsKey(o) && adj[o].Contains(kv.Key)));
            check(symmetric && adj.Count > 500, "passive tree: the graph is undirected");
            var m = d.Ordered.First(n => n.IsMastery);
            check(m.Effects.Length >= 3 && m.Effects[0].Name.Length > 0 && m.Line.Length > 0 && m.Classes.Length > 0, "passive tree: a mastery has effects, a line and classes");
            // a keystone shows its own text per class variant
            var ks = d.Ordered.First(n => n.Type == 'd' && n.Variants.Count > 3);
            string a = ks.For("knight").Name, b = ks.For("lich").Name;
            check(ks.For(null).Name.Length > 0 && (a != b || ks.Variants["knight"].Desc != ks.Variants["lich"].Desc), "passive tree: keystone variants differ per class");
            // the bounds cover the layout
            check(d.MaxX - d.MinX > 2000 && d.MaxY - d.MinY > 2000, "passive tree: the layout is large (" + (d.MaxX - d.MinX) + " x " + (d.MaxY - d.MinY) + ")");
            // a class line section is only seen by its line
            var thiefStart = d.Ordered.First(n => n.IsStart && n.Line == "thief");
            tree.Line = "thief";
            check(tree.Shown(thiefStart) && !tree.Shown(d.Ordered.First(n => n.IsStart && n.Line == "monk")) && tree.Starts().Count() == 2, "passive tree: a class section shows to its own line");
            tree.Line = "warrior"; // every line has a section since O449 (the Warrior, Ranger and Mystic lines were the three without)
            check(tree.Starts().Count() == 2 && tree.Shown(d.Ordered.First(n => n.IsStart && n.Line == "warrior")), "passive tree: the Warrior line has its own class section");
            tree.Line = "nonesuch";
            check(tree.Starts().Count() == 1, "passive tree: a line without a section starts at the root only");
            check(d.Ordered.Where(n => n.Hidden).All(n => !tree.Shown(n)), "passive tree: hidden nodes are never shown");
        }

        // ------------------------------------------------------------------------------------ planner
        static void Planner(Action<bool, string> check)
        {
            var tree = Tree(out var ext, out var sent);
            if (!tree.Ready) return;
            Msg(ext, 65, "{\"action\":\"sendPoints\",\"data\":6}");
            Msg(ext, 65, "{\"action\":\"sendNodes\",\"data\":{\"preset\":1,\"presetsTable\":[{\"name\":\"Main\"}],\"nodes\":[2],\"masteries\":[],\"vocation\":\"knight\",\"cls\":\"warrior\",\"line\":\"warrior\"}}");
            check(tree.Free == 6 && tree.Allocated.Contains(2) && tree.Vocation == "knight" && tree.Cls == "warrior" && tree.Line == "warrior" && tree.PresetNames[0] == "Main" && tree.Synced,
                "passive tree: sendPoints and sendNodes");
            var owned = tree.Owned();
            check(owned.Contains(1) && owned.Contains(2), "passive tree: the root and saved nodes are owned");

            // a plain node two steps from what we own
            var adj = tree.Graph();
            int near = adj[2].First(n => n != 1 && !tree.Data.Nodes[n].IsStart && tree.Allowed(tree.Data.Nodes[n]) && !tree.Allocated.Contains(n));
            int far = adj[near].First(n => n != 2 && n != 1 && !tree.Data.Nodes[n].IsStart && tree.Allowed(tree.Data.Nodes[n]) && !tree.Allocated.Contains(n) && !tree.Data.Nodes[n].IsMastery);
            var click = tree.ClickNode(far);
            check(click == PassiveTree.Click.Planned && tree.PlanList.SequenceEqual(new[] { near, far }) || (tree.PlanList.Count >= 1 && tree.PlanList.Last() == far), "passive tree: a click plans the path to the node (" + string.Join(",", tree.PlanList) + ")");
            int planned = tree.PlanList.Count;
            string cost = tree.CostText(out bool fits);
            check(fits && cost == "Plan: " + planned + " / 6 points" && tree.UndoCount == 1, "passive tree: the plan cost text and one undo step");
            // saved nodes are not planned again, clicking one does nothing
            check(tree.ClickNode(2) == PassiveTree.Click.Saved, "passive tree: a saved node cannot be planned");
            // apply sends the plan
            sent.Clear();
            tree.Apply();
            string req = sent.Count == 1 ? Text(sent[0]) : "";
            check(req.StartsWith("{\"action\":\"planApply\",\"data\":{\"nodes\":[") && req.Contains(far.ToString()) && req.Contains("\"masteries\":[]"), "passive tree: Apply sends planApply " + req);
            // removing the first planned node removes the whole path behind it
            var removed = tree.RemovePlanned(tree.PlanList[0]);
            check(tree.PlanList.Count == 0 && removed.Count == planned, "passive tree: taking out a planned node removes what hung on it");
            check(tree.Undo() && tree.PlanList.Count == planned && tree.Redo() && tree.PlanList.Count == 0, "passive tree: undo and redo");
            tree.Undo();
            // the server saved the plan: planned ids leave the plan
            Msg(ext, 65, "{\"action\":\"sendNodes\",\"data\":{\"preset\":1,\"presetsTable\":[{\"name\":\"Main\"}],\"nodes\":[2," + near + "," + far + "],\"vocation\":\"knight\",\"cls\":\"warrior\",\"line\":\"warrior\"}}");
            check(tree.PlanList.Count == 0 && tree.Allocated.Contains(far), "passive tree: ids the server saved leave the plan");
            Msg(ext, 65, "{\"action\":\"planResult\",\"data\":{\"ok\":true,\"message\":\"Applied 2 nodes.\"}}");
            check(tree.PlanOk && tree.PlanMessage == "Applied 2 nodes." && tree.UndoCount == 0, "passive tree: planResult ok");
            Msg(ext, 65, "{\"action\":\"planResult\",\"data\":{\"ok\":false,\"message\":\"Too fast\"}}");
            check(!tree.PlanOk && tree.BoxText == "Too fast", "passive tree: planResult failure opens a box");

            // a node of another class is locked
            var locked = tree.Data.Ordered.FirstOrDefault(n => !n.IsStart && tree.Shown(n) && n.Classes.Length > 0 && !tree.Allowed(n));
            if (locked != null) check(tree.ClickNode(locked.Id) == PassiveTree.Click.Locked && tree.BoxText.Contains("another class"), "passive tree: a node of another class is locked");
            else check(true, "passive tree: (no foreign class node shown to this line)");

            // no path: a node of a section the line does not see
            var other = tree.Data.Ordered.FirstOrDefault(n => n.Line.Length > 0 && n.Line != "warrior" && !n.IsStart);
            check(other == null || tree.ClickNode(other.Id) == PassiveTree.Click.None, "passive tree: a node of another line's section does nothing");

            // masteries need an effect before Apply
            tree.ResetPlan();
            var mast = tree.Data.Ordered.FirstOrDefault(n => n.IsMastery && tree.Shown(n) && tree.Allowed(n));
            if (mast != null)
            {
                var cl = tree.ClickNode(mast.Id);
                check(cl == PassiveTree.Click.Planned || cl == PassiveTree.Click.ChooseMastery || cl == PassiveTree.Click.NoPath, "passive tree: a mastery click plans or reports");
                if (tree.PlanSet.Contains(mast.Id))
                {
                    check(tree.MissingMasteries().Contains(mast.Id), "passive tree: a planned mastery needs its effect");
                    tree.Free = 100;
                    sent.Clear();
                    tree.Apply();
                    check(sent.Count == 0 && tree.BoxText.Length > 0, "passive tree: Apply waits for the mastery effect");
                    check(tree.SetPlanMastery(mast.Id, 2) && tree.MissingMasteries().Count == 0, "passive tree: the effect is chosen");
                    tree.Apply();
                    check(Text(sent[0]).Contains("\"masteries\":[{\"id\":" + mast.Id + ",\"choice\":2}]"), "passive tree: planApply carries the mastery choice");
                }
            }

            // search
            var hits = tree.Search("strength");
            check(hits.Count > 5 && hits.All(id => tree.SearchText(tree.Data.Nodes[id]).Contains("strength")) && tree.Search("  ").Count == 0, "passive tree: search finds nodes by their text");
            check(PassiveTree.Step(0, 3, 1) == 1 && PassiveTree.Step(3, 3, 1) == 1 && PassiveTree.Step(1, 3, -1) == 3 && PassiveTree.Step(0, 0, 1) == 0, "passive tree: search stepping wraps");

            // other requests
            sent.Clear();
            tree.Open(); tree.RefundNode(7); tree.ResetTree(); tree.ChangeSavedMastery(5, 2);
            var texts = sent.Select(Text).ToList();
            check(texts.Contains("{\"action\":\"requestPoints\"}") && texts.Contains("{\"action\":\"requestNodesUnlocked\"}") && texts.Contains("{\"action\":\"refundNode\",\"data\":{\"id\":7}}") &&
                  texts.Contains("{\"action\":\"resetPreset\",\"data\":1}") && texts.Contains("{\"action\":\"masteryChoose\",\"data\":{\"id\":5,\"choice\":2}}"), "passive tree: open, refund, reset and mastery requests");
        }

        static void TreeMessages(Action<bool, string> check)
        {
            var tree = Tree(out var ext, out var sent);
            Msg(ext, 65, "{\"action\":\"respecInfo\",\"data\":{\"level\":300,\"full\":75000,\"paragon\":0,\"node\":2500,\"free\":\"level\",\"freeBelowLevel\":50}}");
            check(tree.Respec != null && tree.Respec.Full == 75000 && tree.Respec.Node == 2500 && tree.Respec.Free == "level" && tree.Respec.FreeBelowLevel == 50, "passive tree: respecInfo");
            Msg(ext, 65, "{\"action\":\"bossPoints\",\"data\":{\"got\":3,\"total\":10,\"label\":\"Boss points 3/10\"}}");
            check(tree.BossGot == 3 && tree.BossTotal == 10, "passive tree: boss points");
            Msg(ext, 65, "{\"action\":\"sendMessage\",\"data\":{\"title\":\"Error\",\"message\":\"No.\"}}");
            check(tree.BoxTitle == "Error" && tree.BoxText == "No.", "passive tree: sendMessage");
            Msg(ext, 65, "{\"action\":\"buildPreview\",\"data\":{\"code\":\"CB6-x\",\"nodes\":[2,3],\"wanted\":2,\"points\":5,\"cost\":100,\"change\":true,\"summary\":\"2 nodes\"}}");
            check(tree.PreviewNodes != null && tree.PreviewNodes.Contains(3) && tree.PreviewCost == 100 && tree.PreviewSummary.StartsWith("2 nodes"), "passive tree: build preview");
            sent.Clear();
            tree.ApplyBuild();
            check(Text(sent[0]) == "{\"action\":\"buildApply\",\"data\":{\"code\":\"CB6-x\",\"cost\":100}}", "passive tree: buildApply sends the code and the previewed price");
            Msg(ext, 65, "{\"action\":\"buildApplied\",\"data\":{\"message\":\"Build imported.\"}}");
            check(tree.PreviewNodes == null && tree.BuildMessage == "Build imported.", "passive tree: build applied");
            Msg(ext, 65, "{\"action\":\"buildError\",\"data\":{\"message\":\"Wrong class\"}}");
            check(tree.BuildError && tree.BuildMessage == "Wrong class", "passive tree: build error");
            sent.Clear();
            tree.PreviewBuild("hello");
            check(sent.Count == 0 && tree.BuildError, "passive tree: a bad full code is refused before the server");
            tree.PreviewBuild("CB6-AwCRDq4");
            check(Text(sent[0]) == "{\"action\":\"buildPreview\",\"data\":{\"code\":\"CB6-AwCRDq4\"}}", "passive tree: a tree code goes to the server as it is");
            tree.ExportBuild(true);
            check(Text(sent[1]) == "{\"action\":\"buildExport\",\"data\":{\"full\":true}}", "passive tree: full export request");
            tree.Cls = "deadeye"; tree.Level = 600;
            Msg(ext, 65, "{\"action\":\"buildCode\",\"data\":{\"code\":\"CB6-AwCRDq4\",\"nodes\":[2],\"full\":true,\"gear\":[{\"slot\":1,\"id\":2466}]}}");
            var card = BuildCode.Decode(tree.BuildCodeText, out string err);
            check(card != null && card.Class == "deadeye" && card.Level == 600 && card.Tree == "CB6-AwCRDq4" && card.Gear.Count == 1 && card.Gear[0].Value == 2466, "passive tree: a full export becomes a CC1 code " + err);
        }

        // ------------------------------------------------------------------------------------ build codes
        static void BuildCodes(Action<bool, string> check)
        {
            string path = Find("docs", "build_code_vectors.txt");
            check(path != null, "build code: vectors file found");
            if (path == null) return;
            int ok = 0, bad = 0;
            string sample = null;
            foreach (string line in File.ReadAllLines(path))
            {
                if (line.Length == 0 || line[0] == '#') continue;
                var parts = line.Split('|');
                if (parts[0] == "ok")
                {
                    ok++;
                    string name = parts[1], desc = parts[2], code = parts[3];
                    var card = BuildCode.Decode(code, out string err);
                    check(card != null, "build code " + name + ": decodes (" + err + ")");
                    if (card == null) continue;
                    check(Describe(card) == desc, "build code " + name + ": text form " + Describe(card));
                    if (!desc.Contains("skipped=")) check(BuildCode.Encode(FromDescription(desc), out _) == code, "build code " + name + ": encodes to the same code");
                    if (name == "deadeye 600") sample = code;
                }
                else if (parts[0] == "bad")
                {
                    bad++;
                    var card = BuildCode.Decode(parts[2], out string err);
                    check(card == null && err == parts[1], "build code bad " + parts[2] + ": " + err + " (wanted " + parts[1] + ")");
                }
            }
            check(ok >= 8 && bad >= 15, "build code: vectors read (" + ok + " ok, " + bad + " bad)");
            if (sample != null)
            {
                const string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
                int passed = 0;
                for (int i = 4; i < sample.Length; i++)
                    for (int k = 0; k < alphabet.Length; k += 7)
                        if (alphabet[k] != sample[i] && BuildCode.Decode(sample.Substring(0, i) + alphabet[k] + sample.Substring(i + 1), out _) != null) passed++;
                check(passed == 0, "build code: every one-character change is refused");
                check(BuildCode.Decode(sample.Substring(0, sample.Length - 1), out _) == null && BuildCode.Decode("  " + sample + "\n", out _) != null, "build code: truncated refused, spaces ignored");
            }
            check(BuildCode.Encode(new BuildCard { Class = "paladin" }, out string e1) == null && e1 == "class", "build code: unknown class");
            check(BuildCode.Encode(new BuildCard { Level = 0 }, out string e2) == null && e2 == "level", "build code: level 0");
            check(BuildCode.Encode(new BuildCard { Tree = "CB6-AwCRDq5" }, out string e3) == null && e3 == "tree", "build code: a damaged tree code");
            var many = new BuildCard { Spells = Enumerable.Range(101, 20).ToList() };
            many.Spells.Add(101);
            var cardMany = BuildCode.Decode(BuildCode.Encode(many, out _), out _);
            check(cardMany.Spells.Count == BuildCode.MaxSpells && cardMany.Spells[0] == 101, "build code: spells capped, order kept");
            check(BuildCode.ClassIndex("monk") == 13 && BuildCode.ClassOfVocation(20) == "necromancer" && BuildCode.ClassOfVocation(2) == null && BuildCode.Classes.Length == 21, "build code: class tables");
        }

        static string Describe(BuildCard c)
        {
            var parts = new List<string>();
            if (c.Class != null) parts.Add("class=" + c.Class);
            if (c.Level.HasValue) parts.Add("level=" + c.Level.Value);
            if (c.Tree != null)
            {
                parts.Add("tree=" + c.Tree);
                var t = c.TreeInfo;
                if (t.Newer) parts.Add("newer=1");
                else
                {
                    parts.Add("line=" + t.Line);
                    parts.Add("nodes=" + string.Join(",", t.Nodes));
                    var p = BuildCode.ParagonKeys.Where(k => t.Paragon.ContainsKey(k)).Select(k => k + ":" + t.Paragon[k]).ToList();
                    if (p.Count > 0) parts.Add("paragon=" + string.Join(",", p));
                    var ms = t.Masteries.OrderBy(kv => kv.Key).Select(kv => kv.Key + ":" + kv.Value).ToList();
                    if (ms.Count > 0) parts.Add("masteries=" + string.Join(",", ms));
                }
            }
            if (c.Spells.Count > 0) parts.Add("spells=" + string.Join(",", c.Spells));
            if (c.Gear.Count > 0) parts.Add("gear=" + string.Join(",", c.Gear.Select(g => g.Key + ":" + g.Value)));
            if (c.Skipped > 0) parts.Add("skipped=" + c.Skipped);
            return string.Join(";", parts);
        }

        static BuildCard FromDescription(string desc)
        {
            var c = new BuildCard();
            if (desc.Length == 0) return c;
            foreach (string kv in desc.Split(';'))
            {
                int eq = kv.IndexOf('=');
                string k = kv.Substring(0, eq), v = kv.Substring(eq + 1);
                if (k == "class") c.Class = v;
                else if (k == "tree") c.Tree = v;
                else if (k == "level") c.Level = int.Parse(v);
                else if (k == "spells") c.Spells = v.Split(',').Select(int.Parse).ToList();
                else if (k == "gear") c.Gear = v.Split(',').Select(g => new KeyValuePair<int, int>(int.Parse(g.Split(':')[0]), int.Parse(g.Split(':')[1]))).ToList();
            }
            return c;
        }

        // ------------------------------------------------------------------------------------ skills
        static void SkillRows(Action<bool, string> check)
        {
            var none = SkillStats.Build(null);
            check(SkillStats.Rows.All(r => none[r].Visible && none[r].Text == "-"), "skill stats: '-' in the five rows before the server's numbers");
            var rows = SkillStats.Build(Json.Parse("{\"damage\":15300,\"defense\":120,\"armor\":0,\"mitigation\":0.256}"));
            check(rows["damage"].Visible && rows["damage"].Text == "15.3k" && rows["damage"].Green, "skill stats: damage short and green");
            check(!rows["attack"].Visible, "skill stats: no attack row for a wand or bare hands");
            check(rows["defense"].Text == "120" && rows["armor"].Text == "0" && !rows["armor"].Green, "skill stats: defense and a zero armor");
            check(rows["mitigation"].Text == "+25.6%" && rows["mitigation"].Green, "skill stats: mitigation as a percent");
            var ext = new ExtOpcodes();
            var sent = new List<byte[]>();
            ext.Transmit = p => sent.Add(p);
            var stats = new SkillStats(ext);
            stats.Get();
            check(Text(sent[0]) == "{\"action\":\"get\",\"data\":{}}", "skill stats: get");
            Msg(ext, 119, "{\"action\":\"stats\",\"data\":{\"attack\":40,\"defense\":9,\"armor\":3,\"mitigation\":0}}");
            check(stats.Last != null && SkillStats.Build(stats.Last)["attack"].Visible, "skill stats: a stats message is kept");
            var sk = new SkillValue[7];
            sk[SkillStats.Sword] = new SkillValue { Level = 80, Base = 80, Percent = 10 };
            sk[SkillStats.Club] = new SkillValue { Level = 90, Base = 85, Percent = 5 };
            sk[SkillStats.Axe] = new SkillValue { Level = 90, Base = 90, Percent = 40 };
            var melee = SkillStats.Melee(sk);
            check(melee.Level == 90 && melee.Percent == 40, "simple skills: the best of sword, club and axe, a tie by the higher percent");
            check(SkillStats.ShowFist(17) && SkillStats.ShowFist(19) && !SkillStats.ShowFist(4), "simple skills: fist is for the Monk line");
        }

        // ------------------------------------------------------------------------------------ goals
        static void GoalsChecks(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var sent = new List<byte[]>();
            ext.Transmit = p => sent.Add(p);
            var g = new Goals(ext);
            string notice = "";
            g.Notice = t => notice = t;
            g.Open(); g.RequestTracker(); g.SkipWelcome(); g.Close();
            check(sent.Select(Text).SequenceEqual(new[] { "{\"action\":\"open\",\"data\":{}}", "{\"action\":\"tracker\",\"data\":{}}", "{\"action\":\"welcomeSkip\",\"data\":{}}", "{\"action\":\"close\",\"data\":{}}" }), "goals: open, tracker, welcomeSkip and close");
            Msg(ext, 178, "{\"action\":\"goals\",\"data\":{\"header\":{\"level\":310,\"done\":4,\"total\":9,\"season\":{},\"more\":2,\"next\":500,\"nextName\":\"Deep Rifts\"," +
                "\"band\":{\"key\":\"b\",\"name\":\"World bosses\",\"text\":\"Hunt world bosses.\",\"from\":300,\"to\":499,\"index\":4,\"count\":13}}," +
                "\"goals\":[{\"key\":\"a\",\"level\":300,\"state\":\"open\",\"title\":\"Slay a boss\",\"why\":\"w\",\"effort\":\"1h\",\"progress\":0,\"target\":1,\"reward\":\"Orb\",\"where\":{\"k\":\"info\",\"page\":\"rift\"}}," +
                "{\"key\":\"b\",\"level\":400,\"state\":\"locked\",\"title\":\"Later\",\"progress\":0,\"target\":3}," +
                "{\"key\":\"c\",\"level\":300,\"state\":\"open\",\"title\":\"Kill 10\",\"progress\":4,\"target\":10}]," +
                "\"upcoming\":[{\"key\":\"u\",\"level\":350,\"title\":\"Arena\"}],\"gear\":[{\"text\":\"Wear a rare\",\"where\":{\"k\":\"finder\",\"id\":5}}]," +
                "\"hunts\":[{\"id\":\"h1\",\"name\":\"Ruins\",\"lo\":300,\"hi\":350,\"where\":{\"k\":\"hunts\"}}],\"hereWhere\":{\"k\":\"temple\",\"pos\":{\"x\":10,\"y\":20,\"z\":7},\"label\":\"Temple\"}}}");
            check(g.HasHeader && g.Done == 4 && g.Total == 9 && g.HasSeason && g.GoalList.Count == 3 && g.Upcoming.Count == 1 && g.Gear.Count == 1 && g.Hunts.Count == 1 && g.Here != null && g.Here.HasPos, "goals: the goals message fills the window");
            check(g.HeaderLine() == "Level 300-499: World bosses" && g.SummaryLine() == "Goals done: 4 / 9   Next band at level 500: Deep Rifts" && g.BandPercent == 30, "goals: header, summary and band strip");
            check(g.GoalList[0].Where.Button() == "Open" && g.GoalList[0].Where.Page == "rift" && g.Gear[0].Value.Button() == "Item Finder" && g.Here.Button() == "Show on map" && g.Hunts[0].Where.Button() == "Bestiary", "goals: where buttons");
            check(Goals.BarLabel(g.GoalList[0]) == "Not yet" && Goals.BarLabel(g.GoalList[1]) == "Unlocks at level 400" && Goals.BarLabel(g.GoalList[2]) == "4 / 10" && g.GoalList[2].Percent == 40, "goals: bar labels and percent");
            Msg(ext, 178, "{\"action\":\"tracker\",\"data\":{\"rows\":[{\"key\":\"a\",\"title\":\"Slay a boss\",\"progress\":0,\"target\":1},{\"key\":\"c\",\"title\":\"Kill 10\",\"progress\":4,\"target\":10}]}}");
            check(g.Tracker.Count == 2 && g.Tracker[1].TrackerText(false) == "Kill 10  4/10" && g.Tracker[0].TrackerText(false) == "Slay a boss" && g.TrackerHasRows, "goals: tracker rows");
            Msg(ext, 178, "{\"action\":\"ascension\",\"data\":{\"rows\":[{\"key\":\"x\",\"title\":\"Step\",\"progress\":2,\"target\":2,\"state\":\"done\"}]}}");
            check(g.Ascension[0].TrackerText(true) == "Step  Done", "goals: a finished ascension step says Done");
            Msg(ext, 178, "{\"action\":\"welcome\",\"data\":{\"title\":\"Welcome\",\"step\":2,\"count\":7,\"rows\":[{\"key\":\"w\",\"title\":\"Walk\",\"progress\":0,\"target\":1,\"hint\":\"Use arrows\"}]}}");
            check(g.Welcome.Count == 1 && g.WelcomeStep == 2 && g.WelcomeCount == 7 && g.Welcome[0].Hint == "Use arrows", "goals: the welcome path");
            Msg(ext, 178, "{\"action\":\"done\",\"data\":{\"text\":\"Slay a boss\"}}");
            check(notice == "Goal done: Slay a boss" && g.DoneCount == 1, "goals: done notice");
            Msg(ext, 178, "{\"action\":\"goals\",\"data\":{}}");
            check(!g.HasHeader && g.GoalList.Count == 0 && g.HeaderLine() == "Next Goals", "goals: an empty message clears the window");
        }

        // ------------------------------------------------------------------------------------ hunt
        static void HuntChecks(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var sent = new List<byte[]>();
            ext.Transmit = p => sent.Add(p);
            double now = 10000;
            var h = new HuntTracker(ext) { Clock = () => now };
            h.Open();
            check(Text(sent[0]) == "{\"action\":\"open\",\"data\":{}}", "hunt: open");
            Msg(ext, 241, "{\"action\":\"state\",\"data\":{\"open\":true,\"t\":3725,\"p\":0,\"xp\":1234567,\"xph\":50000,\"lvl\":300,\"left\":999,\"ttl\":3600,\"lv\":2500000,\"lvh\":900000,\"sv\":1200,\"svh\":400,\"pf\":2498800,\"pfh\":-5,\"dmg\":1000,\"dps\":12.5,\"heal\":50,\"hps\":1,\"kc\":30," +
                "\"k\":[[\"rat\",20],[\"bat\",10]],\"l\":[[2400,3,150,\"magic sword\",5,0,0],[2500,1,1,\"gold\",0,0,0],[2600,2,5,\"orb of upheaval\",0,0,1]],\"s\":[[100,5,20,\"arrow\"]],\"x\":[[3000,1,\"soulreaper\",0,1,0]]}}");
            check(h.HasState && h.OpenRequested && !h.Paused && h.Xp == 1234567 && h.Level == 300 && h.Kc == 30 && h.Kills.Count == 2 && h.Loot.Count == 3 && h.Supplies.Count == 1 && h.Drops.Count == 1, "hunt: the state fills the tracker");
            check(Fmt.Duration(h.Elapsed(now)) == "1h 02m 05s" && Fmt.Duration(h.Elapsed(now + 5000)) == "1h 02m 10s", "hunt: the session clock ticks between states");
            check(Fmt.Short(h.Xp) == "1.2M" && Fmt.Exact(h.Xp) == "1,234,567" && Fmt.Short(-5) == "-5" && h.NextLevel() == "1h 00m 00s", "hunt: short and exact numbers, the next level time");
            string c;
            check(HuntTracker.ItemLabel(h.Loot[0], out c) == "[Legendary] Magic sword" && c == "#ffd040", "hunt: a rarity label");
            check(HuntTracker.ItemLabel(h.Drops[0], out c) == "[Unique] Soulreaper" && c == "#e07b24", "hunt: a unique label");
            check(HuntTracker.ItemLabel(h.Loot[2], out c) == "Orb of upheaval" && c == "#4fd8d0" && HuntTracker.ItemLabel(h.Loot[1], out c) == "Gold", "hunt: an orb and a plain item");
            sent.Clear();
            h.TogglePause(); h.Reset(); h.AskRestock();
            check(sent.Select(Text).SequenceEqual(new[] { "{\"action\":\"pause\",\"data\":{}}", "{\"action\":\"reset\",\"data\":{}}", "{\"action\":\"restockQuote\",\"data\":{}}" }), "hunt: pause, reset and restock quote");
            Msg(ext, 241, "{\"action\":\"state\",\"data\":{\"p\":1,\"t\":100,\"ttl\":-1}}");
            check(h.Paused && Fmt.Duration(h.Elapsed(now + 9000)) == "1m 40s" && h.NextLevel() == "-", "hunt: a paused session does not tick");
            sent.Clear();
            h.TogglePause();
            check(Text(sent[0]) == "{\"action\":\"resume\",\"data\":{}}", "hunt: resume");
            Msg(ext, 241, "{\"action\":\"restockQuote\",\"data\":{\"rows\":[[100,5,20,\"arrow\"]],\"gold\":20,\"fee\":2,\"pct\":10,\"money\":999}}");
            check(h.Quote != null && h.Quote.Gold == 20 && h.Quote.Fee == 2 && h.Quote.Rows[0].Key == 5 && h.Quote.Rows[0].Value == "arrow", "hunt: restock quote");
            h.Restock();
            check(h.Quote == null && Text(sent[1]) == "{\"action\":\"restock\",\"data\":{}}", "hunt: restock");
            check(h.Summary(now).Contains("Hunt session:"), "hunt: summary text");
        }

        // ------------------------------------------------------------------------------------ rift
        static void RiftChecks(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var sent = new List<byte[]>();
            ext.Transmit = p => sent.Add(p);
            double now = 1000;
            var r = new RiftHud(ext) { Clock = () => now };
            r.Query();
            check(Text(sent[0]) == "{\"action\":\"query\",\"data\":{}}", "rift: query");
            Msg(ext, 228, "{\"action\":\"start\",\"data\":{\"tier\":4,\"theme\":\"Ash\",\"left\":300,\"limit\":300,\"total\":50,\"killed\":10,\"bossAt\":40,\"boss\":\"waiting\",\"state\":\"running\",\"bossName\":\"Vorn\"," +
                "\"mods\":[{\"name\":\"Teeming\",\"text\":\"+30% packs\",\"tier\":3},{\"name\":\"Gift\",\"text\":\"More loot\",\"boon\":true}],\"bonus\":{\"quantity\":20,\"rarity\":0,\"experience\":10}," +
                "\"notes\":[\"A coffer\"],\"lives\":2,\"livesMax\":4,\"swift\":120}}");
            check(r.Active && r.Tier == 4 && r.Mods.Count == 2 && r.Notes.Count == 1 && r.Lives == 2, "rift: start fills the HUD");
            check(r.LeftNow(1000) == 300 && r.LeftNow(11000) == 290 && Fmt.Clock(r.LeftNow(76000)) == "3:45", "rift: the clock counts down from the server's value");
            check(r.BossPercent() == 25 && r.BossLine() == "Guardian in 30 kills" && RiftHud.ModLine(r.Mods[0]) == "Teeming III: +30% packs" && RiftHud.ModLine(r.Mods[1]) == "Gift: More loot", "rift: progress, guardian line and modifier lines");
            check(r.BonusLine() == "+20% quantity, +10% experience" && r.LivesLine() == "Lives: 2 / 4", "rift: bonus and lives lines");
            check(r.SwiftLine(290, out bool met).StartsWith("Swift: seal within 2:00 (1:50 to spare)") && met && !r.SwiftLine(100, out met).StartsWith("Swift: seal") && !met, "rift: the swift line");
            check(RiftHud.ClockColor(100) == "#f4d27a" && RiftHud.ClockColor(50) == "#ff9a30" && RiftHud.ClockColor(10) == "#ff4030", "rift: clock colours");
            Msg(ext, 228, "{\"action\":\"update\",\"data\":{\"tier\":4,\"left\":250,\"limit\":300,\"total\":50,\"killed\":45,\"bossAt\":40,\"boss\":\"alive\",\"state\":\"running\",\"bossName\":\"Vorn\"}}");
            check(r.BossPercent() == 100 && r.BossLine() == "The guardian Vorn is here!" && r.Mods.Count == 0, "rift: an update replaces the numbers");
            Msg(ext, 228, "{\"action\":\"end\",\"data\":{\"result\":\"success\",\"text\":\"Sealed!\",\"exitIn\":10}}");
            check(r.State == "success" && r.Boss == "dead" && r.ResultText == "Sealed!" && r.HideAt == now + 12000, "rift: an end message shows the result and a hide time");
            r.Hide();
            check(!r.Active && r.ResultText == "", "rift: hide");
        }

        // ------------------------------------------------------------------------------------ info and services
        static void InfoChecks(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var sent = new List<byte[]>();
            ext.Transmit = p => sent.Add(p);
            var info = new ChaosInfo(ext);
            check(info.PageShown(ChaosInfo.Page("character")) && info.IsPageOffered("rift"), "info: every page is offered before the catalog");
            info.Show("character");
            check(Text(sent[0]) == "{\"action\":\"catalog\"}", "info: opening a page asks the catalog");
            Msg(ext, 237, "{\"action\":\"catalog\",\"data\":{\"ids\":[\"sheet\",\"pos\",\"serverinfo\",\"uptime\",\"changename\",\"plateframe\"],\"vocations\":\"warrior|juggernaut\"}}");
            check(info.HasCatalog && info.Offered.Contains("sheet") && info.IsPageOffered("character") && !info.IsPageOffered("rift") && !info.IsPageOffered("house") && info.IsPageOffered("services"), "info: the catalog decides which pages show");
            check(info.AutoIds(ChaosInfo.Page("character")).SequenceEqual(new[] { "sheet", "pos" }), "info: only the auto commands the server offers");
            check(info.VocationOptions().Count == 2 && info.VocationOptions()[1].Key == "Juggernaut" && info.VocationOptions()[1].Value == "juggernaut", "info: vocation choices");
            sent.Clear();
            info.Show("character");
            check(Text(sent[0]) == "{\"action\":\"run\",\"page\":\"character\",\"ids\":[\"sheet\",\"pos\"],\"params\":[\"\",\"\"]}" && info.Output == "Loading...", "info: a page runs its auto commands " + (sent.Count > 0 ? Text(sent[0]) : ""));
            Msg(ext, 237, "{\"action\":\"result\",\"data\":{\"page\":\"character\",\"parts\":[{\"id\":\"sheet\",\"text\":\"[ Offense ]\\nHit 5\"},{\"id\":\"pos\",\"text\":\"10, 20, 7\"}]}}");
            check(info.Output == "[ Offense ]\nHit 5\n\n[ Position ]\n10, 20, 7", "info: result parts with headings");
            check(ChaosInfo.Param("$", "  Nova ") == "Nova" && ChaosInfo.Param("$", " ") == null && ChaosInfo.Param("list", "") == "list" && ChaosInfo.Param("", "x") == "", "info: button params");
            var services = ChaosInfo.Page("services");
            info.Show("services");
            Msg(ext, 237, "{\"action\":\"services\",\"data\":{\"nameTokens\":1,\"vocationTokens\":0,\"freeSwitch\":\"juggernaut\",\"familiarReady\":false,\"familiarLevel\":200,\"webshopOrders\":-1,\"frames\":[\"frost\"],\"activeFrame\":\"\"}}");
            check(info.NeedMet("nameTokens") && !info.NeedMet("vocationTokens") && info.NeedMet("freeSwitch") && !info.NeedMet("familiarReady") && info.NeedMet("webshopOrders") && info.NeedMet("frames") && !info.NeedMet("activeFrame") && info.NeedMet(""), "info: which buttons the Services state allows");
            string st = info.ServicesText();
            check(st.Contains("Name Change tokens: 1") && st.Contains("Free switch: available (to juggernaut)") && st.Contains("Familiar: from level 200") && st.Contains("Your frames: Frost"), "info: the Services status text");
            sent.Clear();
            var nameRow = services.Rows[0];
            info.Press(services, nameRow, nameRow.Buttons[0], "Bob");
            check(Text(sent[0]) == "{\"action\":\"run\",\"page\":\"services\",\"ids\":[\"changename\"],\"params\":[\"Bob\"]}", "info: a button runs its command with the field");
            sent.Clear();
            info.Press(services, nameRow, nameRow.Buttons[0], " ");
            check(sent.Count == 0 && info.Output.StartsWith("Fill in"), "info: an empty field is refused");
            Msg(ext, 237, "{\"action\":\"store\",\"data\":{\"points\":50,\"entries\":[{\"id\":2,\"kind\":\"Item\",\"name\":\"Big\",\"item\":9,\"price\":80},{\"id\":1,\"kind\":\"Item\",\"name\":\"Small\",\"price\":20},{\"id\":3,\"name\":1}]}}");
            var rows = info.StoreRows(out long points);
            check(points == 50 && rows.Count == 2 && rows[0].Name == "Small" && rows[0].Afford && !rows[1].Afford && rows[1].Missing == 30, "info: store rows sorted by price with what is missing");
            sent.Clear();
            info.Buy(1);
            check(Text(sent[0]) == "{\"action\":\"buy\",\"id\":1,\"count\":1}", "info: buy");
            Msg(ext, 237, "{\"action\":\"npc\",\"data\":{\"page\":\"house\"}}");
            check(info.OpenPage == "house", "info: an NPC can open a page");
        }

        // ------------------------------------------------------------------------------------ top menu
        static void MenuChecks(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var sent = new List<byte[]>();
            ext.Transmit = p => sent.Add(p);
            var u = new MenuUnlocks(ext);
            int change = 0;
            u.Changed = () => change++;
            int level;
            check(u.Status("Passive Tree", out level) == MenuStatus.Open && u.BlockedLevel("Passive Tree") == 0, "menu: everything is open before the server's state");
            Msg(ext, 115, "{\"action\":\"state\",\"data\":{\"entries\":[{\"key\":\"tree\",\"level\":10,\"menu\":\"Passive Tree\"},{\"key\":\"rift\",\"level\":50,\"menu\":\"Rifts\"},{\"key\":\"arena\",\"level\":90,\"menu\":\"Arena\"}],\"unlocked\":[\"tree\"],\"seen\":[],\"next\":{\"key\":\"rift\",\"level\":50}}}");
            check(u.Loaded && u.Status("Passive Tree", out level) == MenuStatus.Open && u.IsNew("Passive Tree"), "menu: an unlocked entry is open and new");
            check(u.Status("Rifts", out level) == MenuStatus.Locked && level == 50 && u.BlockedLevel("Rifts") == 50, "menu: the next entry is locked with its level");
            check(u.Status("Arena", out level) == MenuStatus.Hidden && level == 90 && u.Status("Skills", out level) == MenuStatus.Open, "menu: later entries are hidden, unnamed ones open");
            sent.Clear();
            check(u.MarkSeen("Passive Tree") == "tree" && Text(sent[0]) == "{\"action\":\"seen\",\"data\":{\"key\":\"tree\"}}" && !u.IsNew("Passive Tree") && u.MarkSeen("Passive Tree") == null, "menu: opening an entry tells the server once");
            Msg(ext, 115, "{\"action\":\"new\",\"data\":{\"key\":\"rift\",\"level\":50,\"menu\":\"Rifts\",\"title\":\"Rifts\",\"why\":[\"Line one\",\"Line two\"]}}");
            check(u.Announcement != null && u.Announcement.Line2 == "Line two" && u.Status("Rifts", out level) == MenuStatus.Open && u.NextKey == "", "menu: a new unlock opens the entry");
            u.ShowAll = true;
            check(u.Status("Arena", out level) == MenuStatus.Open, "menu: the option shows the whole menu");
            u.Hello();
            check(Text(sent[sent.Count - 1]) == "{\"action\":\"hello\",\"data\":{}}", "menu: hello");

            check(TopMenu.SortKey("  Épico") == "epico" && TopMenu.SortKey("Zeta") == "zeta", "menu: the sort key folds accents");
            var sorted = TopMenu.Sorted(new[]
            {
                new MenuEntry { Text = "Zeta", Target = "a" }, new MenuEntry { Text = "More", Sub = new[] { new MenuEntry { Text = "x" } } },
                new MenuEntry { Text = "alpha", Target = "b" }, new MenuEntry { Separator = true }, new MenuEntry { Text = "Beta", Target = "c" }, new MenuEntry { Text = "Aaa", Target = "d" },
            }, e => e.Text);
            check(string.Join(",", sorted.Select(e => e.Separator ? "|" : e.Text)) == "alpha,Zeta,More,|,Aaa,Beta", "menu: alphabetical, sub-menus last, groups kept: " + string.Join(",", sorted.Select(e => e.Separator ? "|" : e.Text)));
            // the "More" sub-menus (phase 7 track X) are opened: the leaves are unique across the whole menu
            var leaves = TopMenu.Categories.SelectMany(c => TopMenu.Leaves(c)).ToList();
            var texts = leaves.Select(e => e.Text).ToList();
            check(texts.Count == texts.Distinct().Count() && leaves.All(e => e.Target.StartsWith("win:") || e.Target.StartsWith("info:") || e.Target.StartsWith("act:")), "menu: entries are unique and name a window, an info page or an action");
            check(leaves.Where(e => e.Target.StartsWith("info:")).All(e => ChaosInfo.Page(e.Target.Substring(5)) != null), "menu: every info entry names a real page");
        }

        // ------------------------------------------------------------------------------------ pt-BR
        static void LocChecks(Action<bool, string> check)
        {
            // texts of the Core data files marked with Lk.N and the page texts must have a pt-BR entry
            var keys = new HashSet<string>();
            foreach (var p in ChaosInfo.Pages)
            {
                keys.Add(p.Title); keys.Add(p.Text);
                if (p.Idle.Length > 0) keys.Add(p.Idle);
                foreach (var h in p.Headings.Values) keys.Add(h);
                foreach (var r in p.Rows)
                {
                    if (r.Label.Length > 0) keys.Add(r.Label);
                    if (r.Hint.Length > 0) keys.Add(r.Hint);
                    foreach (var b in r.Buttons) { keys.Add(b.Text); if (b.Hint.Length > 0) keys.Add(b.Hint); if (b.Why.Length > 0) keys.Add(b.Why); }
                }
            }
            keys.Add(ChaosInfo.Idle);
            foreach (var c in TopMenu.Categories) keys.Add(c.Text);
            foreach (var s in new[] { "Open", "Kill Tasks", "Item Finder", "Show on map", "Bestiary", "Common", "Uncommon", "Magic", "Rare", "Legendary", "Divine" }) keys.Add(s);
            // and the Loc.T("...") keys of the progression Core files (the Unity sources are scanned by ExtTests)
            string core = Find("unity", "Client", "Assets", "Chaos", "Core", "Progression.cs") ?? Find("Client", "Assets", "Chaos", "Core", "Progression.cs");
            if (core != null)
                foreach (string name in new[] { "Progression.cs", "PassiveTree.cs", "TopMenu.cs" })
                    foreach (System.Text.RegularExpressions.Match m in System.Text.RegularExpressions.Regex.Matches(File.ReadAllText(Path.Combine(Path.GetDirectoryName(core), name)), "\\bLoc\\.T\\(\"((?:[^\"\\\\]|\\\\.)*)\""))
                        keys.Add(m.Groups[1].Value.Replace("\\\"", "\""));
            var missing = keys.Where(k => !LocStrings.PtBr.ContainsKey(k)).ToList();
            check(missing.Count == 0, "loc: progression texts have pt-BR" + (missing.Count > 0 ? ": " + string.Join(" | ", missing) : " (" + keys.Count + " keys)"));
        }
    }
}
