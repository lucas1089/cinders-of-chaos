// Phase 8, track A: the passive tree's remaining gap list (game_passivetree): the vocation trials (trials.lua, trialsmath.lua), the auto build (autobuild.lua,
// autobuildview.lua), the Paragon masteries and the exchange of tree points (paragonmastery.lua, paragonmasterymath.lua), node icons with the frames of each node
// kind (passivetree.otui, treedata/icons.lua, the painted option) and curved links between the nodes of one orbit (passivetree.lua BuildConnector). The server owns
// every rule and checks every request again; these classes show its state and send its actions on opcode 65.
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    public static class Phase8ATreeHandlers
    {
        /// <summary>The actions of this track; false for any other.</summary>
        public static bool Handle(PassiveTree t, string action, object data)
        {
            switch (action)
            {
                case "trialState": t.Trials.Receive(data); return true;
                case "autobuildList": case "autobuildPreview": case "autobuildError": case "autobuildApplied": return t.Auto.Handle(action, data);
                default: return false;
            }
        }
    }

    // ================================================================================================ trials
    public sealed class TrialNode
    {
        public string Name = "", Lore = "", Why = "";
        public bool Can, Switch, NeedsSpellEvents;
        public readonly List<KeyValuePair<string, bool>> Lines = new List<KeyValuePair<string, bool>>();
    }

    public sealed class TrialPair
    {
        public int Number;
        public string Tier = "";
        public bool Locked, ClearCan = true;
        public int Held;
        public TrialNode[] Nodes = { new TrialNode(), new TrialNode() };
    }

    public sealed class TrialTier
    {
        public string Name = "", Problem = "";
        public int MinLevel, Time, Lives;
        public bool Cleared;
        public double BossHealth;
    }

    /// <summary>What a node card of the trials panel shows (trialsmath.lua card).</summary>
    public sealed class TrialCard { public string Action = "", Status = "", StatusColor = "", Tooltip = ""; public bool Enabled; }

    public sealed class TreeTrials
    {
        public const string Good = "#7fd06a", Bad = "#e0654a", Dim = "#8c8070", Held = "#f6cf72";
        public const int MaxLines = 5;
        readonly ExtOpcodes ext;
        public bool Known, Supported, Running;
        public string Trial = "", Story = "";
        public int Level, Cleared, Tokens, MaxTokens = 10;
        public long SwitchGold;
        public readonly List<TrialTier> Tiers = new List<TrialTier>();
        public readonly List<TrialPair> Pairs = new List<TrialPair>();
        /// <summary>The confirmation the panel asks before choosing, switching or giving a pair up: set by Ask*, answered by Confirm or Cancel.</summary>
        public string AskTitle = "", AskText = "";
        int askPair, askSide;
        public bool Asking => AskText.Length > 0;
        public Action Changed = delegate { };

        public TreeTrials(ExtOpcodes e) { ext = e; }

        public void Request() { ext?.Send(PassiveTree.Opcode, "trialRequest", null); }

        public void Receive(object data)
        {
            if (!(data is Dictionary<string, object>)) return;
            Known = true;
            Supported = Json.Bool(data, "supported");
            Trial = Json.Text(data, "trial"); Story = Json.Text(data, "story");
            Level = Json.Int(data, "level"); Cleared = Json.Int(data, "tier");
            Tokens = Json.Int(data, "tokens"); MaxTokens = Json.Int(data, "maxTokens", 10);
            SwitchGold = (long)Json.Number(data, "switchGold");
            Running = Json.Bool(data, "running");
            Tiers.Clear(); Pairs.Clear();
            foreach (object t in Json.List(data, "tiers"))
            {
                var tier = new TrialTier { Name = Json.Text(t, "name"), MinLevel = Json.Int(t, "minLevel"), Cleared = Json.Bool(t, "cleared"), Problem = Json.Text(t, "problem"), Time = Json.Int(t, "time"), Lives = Json.Int(t, "lives"), BossHealth = Json.Number(t, "bossHealth") };
                Tiers.Add(tier);
            }
            int n = 0;
            foreach (object p in Json.List(data, "pairs"))
            {
                var pair = new TrialPair { Number = ++n, Tier = Json.Text(p, "tier"), Locked = Json.Bool(p, "locked"), Held = Json.Int(p, "held") };
                object clear = Json.Get(p, "clear");
                pair.ClearCan = !(clear is Dictionary<string, object>) || Json.Bool(clear, "can");
                int i = 0;
                foreach (object nd in Json.List(p, "nodes"))
                {
                    if (i >= 2) break;
                    var node = new TrialNode { Name = Json.Text(nd, "name"), Lore = Json.Text(nd, "lore"), Can = Json.Bool(nd, "can"), Why = Json.Text(nd, "why"), Switch = Json.Bool(nd, "switch"), NeedsSpellEvents = Json.Bool(nd, "needsSpellEvents") };
                    foreach (object l in Json.List(nd, "lines")) node.Lines.Add(new KeyValuePair<string, bool>(Json.Text(l, "text"), Json.Bool(l, "good")));
                    pair.Nodes[i++] = node;
                }
                Pairs.Add(pair);
            }
            Changed();
        }

        // ---- trialsmath.lua
        public static string Gold(double n)
        {
            long v = (long)Math.Floor(double.IsNaN(n) ? 0 : n);
            return v.ToString("N0", CultureInfo.InvariantCulture);
        }

        public static string Fit(string text, int max)
        {
            text = text ?? "";
            if (text.Length <= max) return text;
            return text.Substring(0, Math.Max(1, max - 3)) + "...";
        }

        public string TokensLine => Loc.T("Trial Tokens: {0} / {1}     Changing a held node costs 1 token and {2} gold", Tokens, MaxTokens, Gold(SwitchGold));
        public static string LockText(string tier) => Loc.T("Locked: clear on {0}", tier);
        string LockTooltip(TrialPair e) => Loc.T("Clear {0} on {1} to open this pair of nodes.", Trial, e.Tier);

        public TrialCard Card(TrialPair e, int side)
        {
            var node = e.Nodes[side - 1];
            if (Running)
                return new TrialCard { Action = e.Held == side ? Loc.T("Held") : Loc.T("In a trial"), Enabled = false, Status = e.Locked ? LockText(e.Tier) : Loc.T("Not during a trial"), StatusColor = Dim, Tooltip = Loc.T("Nodes cannot be changed while a trial runs.") };
            if (e.Locked)
                return new TrialCard { Action = Loc.T("Locked"), Enabled = false, Status = LockText(e.Tier), StatusColor = Dim, Tooltip = LockTooltip(e) };
            if (e.Held == side)
                return new TrialCard { Action = Loc.T("Held"), Enabled = false, Status = Loc.T("Held"), StatusColor = Held, Tooltip = Loc.T("You hold this node. Pick the other one to change (1 Trial Token and gold).") };
            if (e.Held == 0)
                return new TrialCard { Action = Loc.T("Choose"), Enabled = node.Can, Status = node.Can ? Loc.T("Free to choose") : node.Why, StatusColor = node.Can ? Good : Bad, Tooltip = Loc.T("The first choice of a pair is free. Choosing one locks the other.") };
            bool can = node.Can;
            var held = e.Nodes[e.Held - 1];
            return new TrialCard
            {
                Action = Loc.T("Switch"), Enabled = can, Status = can ? Loc.T("1 token + gold") : Loc.T("Needs a Trial Token"), StatusColor = can ? Held : Bad,
                Tooltip = Loc.T("Replaces {0}. Costs 1 Trial Token and {1} gold.", held.Name.Length > 0 ? held.Name : "?", Gold(SwitchGold)),
            };
        }

        /// <summary>The Clear button of a pair (gives the pair up: no node held, the price of a switch).</summary>
        public TrialCard ClearCard(TrialPair e)
        {
            if (Running) return new TrialCard { Enabled = false, Tooltip = Loc.T("Nodes cannot be changed while a trial runs.") };
            if (e.Locked) return new TrialCard { Enabled = false, Tooltip = LockTooltip(e) };
            if (e.Held == 0) return new TrialCard { Enabled = false, Tooltip = Loc.T("No node of this pair is held.") };
            var node = e.Nodes[e.Held - 1];
            string tip = Loc.T("Gives up {0} and leaves the pair empty. Costs 1 Trial Token and {1} gold.", node.Name.Length > 0 ? node.Name : "?", Gold(SwitchGold));
            if (!e.ClearCan) tip += "\n" + Loc.T("Needs a Trial Token");
            return new TrialCard { Enabled = e.ClearCan, Tooltip = tip };
        }

        /// <summary>The Enter button of a tier: text, enabled and tooltip.</summary>
        public TrialCard TierButton(int i)
        {
            var t = Tiers[i];
            string text = Loc.T("Enter {0}", t.Name) + (t.Cleared ? " " + Loc.T("(cleared)") : "");
            string tip = Loc.T("{0}: level {1}, {2} minutes, {3} lives, guardian about {4} health.", t.Name, t.MinLevel, t.Time / 60, t.Lives, Gold(t.BossHealth));
            if (Running) return new TrialCard { Action = text, Enabled = false, Tooltip = Loc.T("A trial is running.") };
            if (t.Problem.Length > 0) tip += "\n" + t.Problem;
            else if (t.Cleared) tip += "\n" + Loc.T("Cleared: another clear gives a Trial Token.");
            else tip += "\n" + Loc.T("The first clear opens a pair of nodes.");
            return new TrialCard { Action = text, Enabled = t.Problem.Length == 0, Tooltip = tip };
        }

        public string ConfirmText(TrialPair e, int side)
        {
            var node = e.Nodes[side - 1];
            var lines = new List<string>();
            foreach (var l in node.Lines) lines.Add((l.Value ? "+ " : "- ") + l.Key);
            string head = e.Held == 0 ? Loc.T("Choose {0}? The other node of the pair is locked while you hold it.", node.Name)
                : Loc.T("Switch to {0}? It costs 1 Trial Token and {1} gold coins.", node.Name, Gold(SwitchGold));
            return head + "\n\n" + string.Join("\n", lines);
        }

        public string ClearConfirmText(TrialPair e)
        {
            var node = e.Held > 0 ? e.Nodes[e.Held - 1] : null;
            return Loc.T("Give up {0} and leave this pair empty? It costs 1 Trial Token and {1} gold coins. You can choose a node of the pair again later, which costs a token again.", node != null && node.Name.Length > 0 ? node.Name : "?", Gold(SwitchGold));
        }

        // ---- actions
        /// <summary>Asks the confirmation for choosing or switching to a node (pair 1 to 3, side 1 or 2).</summary>
        public bool AskChoose(int pair, int side)
        {
            if (!Supported || pair < 1 || pair > Pairs.Count || side < 1 || side > 2) return false;
            var e = Pairs[pair - 1];
            if (!Card(e, side).Enabled) return false;
            askPair = pair; askSide = side;
            AskTitle = e.Held == 0 ? Loc.T("Choose a node") : Loc.T("Switch node");
            AskText = ConfirmText(e, side);
            Changed();
            return true;
        }

        public bool AskClear(int pair)
        {
            if (!Supported || pair < 1 || pair > Pairs.Count) return false;
            var e = Pairs[pair - 1];
            if (e.Held == 0 || !ClearCard(e).Enabled) return false;
            askPair = pair; askSide = 0;
            AskTitle = Loc.T("Give up a node");
            AskText = ClearConfirmText(e);
            Changed();
            return true;
        }

        public void Confirm()
        {
            if (!Asking) return;
            ext?.Send(PassiveTree.Opcode, "trialChoose", new Dictionary<string, object> { { "pair", askPair }, { "side", askSide } });
            Cancel();
        }

        public void Cancel() { AskTitle = ""; AskText = ""; Changed(); }

        public bool Enter(int tier)
        {
            if (!Supported || tier < 1 || tier > Tiers.Count || Running || Tiers[tier - 1].Problem.Length > 0) return false;
            ext?.Send(PassiveTree.Opcode, "trialEnter", new Dictionary<string, object> { { "tier", tier } });
            return true;
        }

        public void Leave() { ext?.Send(PassiveTree.Opcode, "trialLeave", null); }
    }

    // ================================================================================================ auto build
    public sealed class AutoBuildEntry
    {
        public string Id = "", Name = "", Text = "", Summary = "", Fit = "";
        public int Points;
    }

    public sealed class AutoBuildRow { public bool Heading; public string Id = "", Text = ""; public AutoBuildEntry Build; }

    public sealed class AutoBuildPreview
    {
        public string Build = "", Name = "";
        public int Owned, Held, Wanted;
        public int AddAdded, AddSkipped, AddOther, ResetAdded, ResetSkipped, ResetOther, ResetRemoved;
        public long ResetCost;
        public int ResetFree;
        public readonly List<int> AddNodes = new List<int>(), ResetNodes = new List<int>();
    }

    public sealed class AutoBuild
    {
        public const string Text = "#d8cfc0", Dim = "#8c8070", GoodColor = "#80c070", Warn = "#c0b080", Red = "#e07060";
        public const double PreviewTimeoutMs = 4000, RetryDelayMs = 700;
        public const int MaxTries = 3;
        readonly ExtOpcodes ext;
        readonly PassiveTree tree;
        public Func<double> Clock = () => Environment.TickCount;
        public readonly List<AutoBuildEntry> Role = new List<AutoBuildEntry>(), Focus = new List<AutoBuildEntry>();
        public int Owned, Held, Free, Cap;
        public string Selected = "", Failed = "";
        public AutoBuildPreview Preview;
        public string NoteText = "", NoteColor = "";
        string pendingBuild = "";
        int pendingTries;
        double pendingAt, retryAt = -1;
        public bool Opened;
        public string ConfirmTextShown = "";
        public Action Changed = delegate { };

        public AutoBuild(ExtOpcodes e, PassiveTree t) { ext = e; tree = t; }

        // ---- autobuildview.lua
        public static string Gold(double n) => TreeTrials.Gold(n);

        public static string Label(AutoBuildEntry b)
        {
            string text = (b.Name.Length > 0 ? b.Name : b.Id.Length > 0 ? b.Id : "?") + " - " + Loc.T("{0} points", b.Points);
            if (b.Fit == "primary") text += " [" + Loc.T("Primary") + "]";
            else if (b.Fit == "secondary") text += " [" + Loc.T("Secondary") + "]";
            return text;
        }

        public List<AutoBuildRow> Rows()
        {
            var rows = new List<AutoBuildRow>();
            if (Role.Count > 0)
            {
                rows.Add(new AutoBuildRow { Heading = true, Text = "- " + Loc.T("Recommended") + " -" });
                foreach (var b in Role) rows.Add(new AutoBuildRow { Id = b.Id, Build = b, Text = Label(b) });
            }
            if (Focus.Count > 0)
            {
                rows.Add(new AutoBuildRow { Heading = true, Text = "- " + Loc.T("Focus") + " -" });
                foreach (var b in Focus) rows.Add(new AutoBuildRow { Id = b.Id, Build = b, Text = Label(b) });
            }
            return rows;
        }

        public AutoBuildEntry Current()
        {
            foreach (var r in Rows()) if (!r.Heading && r.Id == Selected) return r.Build;
            return null;
        }

        string PriceText()
        {
            if (Preview == null) return "";
            if (Preview.ResetCost > 0) return Loc.T("{0} gold coins", Gold(Preview.ResetCost));
            if (Preview.ResetFree > 0) return Loc.T("free (a free reset is used)");
            return Loc.T("free");
        }

        /// <summary>The text under the list and its colour (V.detail).</summary>
        public string Detail(out string color)
        {
            color = Text;
            var b = Current();
            if (b == null) { color = Dim; return Loc.T("Pick a build. The tree shows what it would take."); }
            var lines = new List<string>();
            if (b.Text.Length > 0) lines.Add(b.Text);
            if (b.Summary.Length > 0) lines.Add(b.Summary);
            lines.Add(Loc.T("The build uses {0} points. You own {1} and {2} are free.", b.Points, Owned, Free));
            if (Preview == null || Preview.Build != b.Id)
            {
                if (NoteText.Length > 0) { lines.Add(NoteText); color = NoteColor.Length > 0 ? NoteColor : Text; return string.Join("\n", lines); }
                lines.Add(Loc.T("Asking the server for a preview..."));
                return string.Join("\n", lines);
            }
            lines.Add("");
            lines.Add(Loc.T("Apply: adds {0} nodes, takes nothing back, free.", Preview.AddAdded));
            if (Preview.AddSkipped > 0) lines.Add(Loc.T("{0} more nodes of the build need points you do not have yet.", Preview.AddSkipped));
            if (Preview.AddOther > 0) lines.Add(Loc.T("{0} nodes your class cannot hold are left out.", Preview.AddOther));
            if (Preview.ResetRemoved > 0) lines.Add(Loc.T("Reset and apply: takes back {0} nodes and builds this one ({1} nodes). Price: {2}.", Preview.ResetRemoved, Preview.ResetNodes.Count, PriceText()));
            else lines.Add(Loc.T("Reset and apply: your tree already fits this build, nothing is taken back."));
            if (NoteText.Length > 0) { lines.Add(""); lines.Add(NoteText); color = NoteColor.Length > 0 ? NoteColor : Text; }
            return string.Join("\n", lines);
        }

        public bool CanApply => Preview != null && Preview.AddAdded > 0;
        public bool CanReset => Preview != null && (Preview.ResetAdded > 0 || Preview.ResetRemoved > 0);

        public string ConfirmText() => Preview == null ? "" : Loc.T("Reset your tree and apply {0}?\nNodes taken back: {1}. Price: {2}.", Preview.Name.Length > 0 ? Preview.Name : Preview.Build, Preview.ResetRemoved, PriceText());

        /// <summary>Ask for the preview of the picked build now? Not when it is shown, asked already or failed (until picked again).</summary>
        public bool NeedsPreview()
        {
            if (Selected.Length == 0 || Failed == Selected) return false;
            if (Preview != null && Preview.Build == Selected) return false;
            return !(pendingBuild.Length > 0 && pendingBuild == Selected);
        }

        // ---- the panel's actions
        public void Open()
        {
            Opened = true; Failed = ""; NoteText = "";
            ext?.Send(PassiveTree.Opcode, "autobuildList", null);
            Changed();
        }

        /// <summary>Closes the panel and takes the preview back: the tree shows the saved allocation again.</summary>
        public void Close()
        {
            Opened = false;
            ClearPending();
            ConfirmTextShown = "";
            if (Preview != null)
            {
                Preview = null;
                tree.PreviewNodes = null;
                ext?.Send(PassiveTree.Opcode, "requestNodesUnlocked", null);
                ext?.Send(PassiveTree.Opcode, "requestPoints", null);
            }
            tree.Touch();
        }

        public void Pick(string id)
        {
            if (id == Selected && Failed != id) return;
            Selected = id; Failed = ""; NoteText = ""; NoteColor = "";
            ClearPending();
            AskPreview();
        }

        void ClearPending() { pendingBuild = ""; pendingTries = 0; pendingAt = 0; retryAt = -1; }

        void AskPreview()
        {
            Preview = null;
            tree.PreviewNodes = null;
            int tries = pendingBuild == Selected ? pendingTries + 1 : 1;
            ClearPending();
            if (Selected.Length > 0)
            {
                pendingBuild = Selected; pendingTries = tries; pendingAt = Clock();
                ext?.Send(PassiveTree.Opcode, "autobuildPreview", new Dictionary<string, object> { { "build", Selected } });
            }
            else
            {
                ext?.Send(PassiveTree.Opcode, "requestNodesUnlocked", null);
            }
            tree.Touch();
        }

        void FailPreview(string text)
        {
            if (pendingBuild.Length > 0) Failed = pendingBuild;
            ClearPending();
            NoteText = text; NoteColor = Red;
            tree.Touch();
        }

        /// <summary>Per frame while the panel is open: a preview that did not come in time is asked again, three tries in all, then an error line (V.onTimeout).</summary>
        public void Tick(double nowMs)
        {
            if (!Opened || pendingBuild.Length == 0) return;
            bool due = retryAt >= 0 ? nowMs >= retryAt : nowMs - pendingAt >= PreviewTimeoutMs;
            if (!due) return;
            retryAt = -1;
            if (pendingTries < MaxTries) { pendingAt = nowMs; AskPreview(); }
            else FailPreview(Loc.T("The server did not answer the preview. Close and reopen Auto build to try again."));
        }

        public bool Apply()
        {
            if (!CanApply) return false;
            ConfirmTextShown = "";
            ext?.Send(PassiveTree.Opcode, "autobuildApply", new Dictionary<string, object> { { "build", Preview.Build }, { "mode", "add" }, { "cost", 0 } });
            return true;
        }

        /// <summary>Asks the question before Reset and apply; Confirm sends it.</summary>
        public bool AskReset()
        {
            if (!CanReset) return false;
            ConfirmTextShown = ConfirmText();
            tree.Touch();
            return true;
        }

        public void ConfirmReset()
        {
            if (ConfirmTextShown.Length == 0 || !CanReset) { ConfirmTextShown = ""; return; }
            var p = Preview;
            ConfirmTextShown = "";
            ext?.Send(PassiveTree.Opcode, "autobuildApply", new Dictionary<string, object> { { "build", p.Build }, { "mode", "reset" }, { "cost", p.ResetCost } });
        }

        public void CancelReset() { ConfirmTextShown = ""; tree.Touch(); }

        // ---- the server's answers
        static List<AutoBuildEntry> Entries(object list)
        {
            var r = new List<AutoBuildEntry>();
            foreach (object b in Json.List(new Dictionary<string, object> { { "l", list } }, "l"))
                r.Add(new AutoBuildEntry { Id = Json.Text(b, "id"), Name = Json.Text(b, "name"), Text = Json.Text(b, "text"), Summary = Json.Text(b, "summary"), Points = Json.Int(b, "points"), Fit = Json.Text(b, "fit") });
            return r;
        }

        static void Nodes(object o, List<int> into) { foreach (object n in Json.List(o, "nodes")) if (n is double d) into.Add((int)d); }

        public bool Handle(string action, object data)
        {
            switch (action)
            {
                case "autobuildList":
                {
                    string group = Json.Text(data, "group");
                    if (group != "role" && group != "focus") return true;
                    var list = Entries(Json.Get(data, "builds"));
                    if (group == "role") { Role.Clear(); Role.AddRange(list); } else { Focus.Clear(); Focus.AddRange(list); }
                    Owned = Json.Int(data, "owned"); Held = Json.Int(data, "held"); Free = Json.Int(data, "free"); Cap = Json.Int(data, "cap");
                    if (Current() == null)
                    {
                        Selected = "";
                        foreach (var r in Rows()) if (!r.Heading) { Selected = r.Id; break; }
                    }
                    if (Opened && NeedsPreview()) AskPreview(); else tree.Touch();
                    return true;
                }
                case "autobuildPreview":
                {
                    if (!Opened || Json.Text(data, "build") != Selected) return true;   // an answer to an earlier pick
                    ClearPending();
                    Failed = "";
                    if (NoteColor == Red) { NoteText = ""; NoteColor = ""; }
                    var p = new AutoBuildPreview { Build = Json.Text(data, "build"), Name = Json.Text(data, "name"), Owned = Json.Int(data, "owned"), Held = Json.Int(data, "held"), Wanted = Json.Int(data, "wanted") };
                    object add = Json.Get(data, "add"), reset = Json.Get(data, "reset");
                    p.AddAdded = Json.Int(add, "added"); p.AddSkipped = Json.Int(add, "skipped"); p.AddOther = Json.Int(add, "other"); Nodes(add, p.AddNodes);
                    p.ResetAdded = Json.Int(reset, "added"); p.ResetSkipped = Json.Int(reset, "skipped"); p.ResetOther = Json.Int(reset, "other"); p.ResetRemoved = Json.Int(reset, "removed");
                    p.ResetCost = (long)Json.Number(reset, "cost"); p.ResetFree = Json.Int(reset, "free"); Nodes(reset, p.ResetNodes);
                    Preview = p;
                    // the tree shows what Reset and apply would build when it takes something back, else what Apply adds on top
                    var shown = p.ResetRemoved > 0 ? p.ResetNodes : p.AddNodes;
                    tree.PreviewNodes = new HashSet<int>(shown);
                    tree.Touch();
                    return true;
                }
                case "autobuildError":
                {
                    string text = Json.Text(data, "message", Loc.T("The build could not be applied."));
                    if (!Opened) { ClearPending(); tree.BoxTitle = Loc.T("Auto build"); tree.BoxText = text; tree.Touch(); return true; }
                    string answer = OnError(data);
                    if (answer == "retry") { retryAt = Clock() + RetryDelayMs; return true; }
                    if (answer == "fail") { FailPreview(text); return true; }
                    string build = Json.Text(data, "build");
                    if (build.Length > 0 && build != Selected) return true;   // the error of an earlier pick's preview
                    NoteText = text; NoteColor = Red;
                    tree.Touch();
                    return true;
                }
                case "autobuildApplied":
                {
                    Preview = null; tree.PreviewNodes = null;
                    ClearPending(); Failed = "";
                    NoteText = Json.Text(data, "message", Loc.T("Build applied.")); NoteColor = GoodColor;
                    ext?.Send(PassiveTree.Opcode, "autobuildList", null);   // the new points; its answer asks for the preview on the new tree
                    tree.Touch();
                    return true;
                }
            }
            return false;
        }

        /// <summary>How an error answers the pending preview: ignore (another build's, or nothing asked), retry (too fast, tries left) or fail (V.onError).</summary>
        string OnError(object data)
        {
            if (pendingBuild.Length == 0) return "ignore";
            string build = Json.Text(data, "build");
            if (build.Length > 0 && build != pendingBuild) return "ignore";
            if (Json.Bool(data, "retry") && pendingTries < MaxTries) return "retry";
            return "fail";
        }
    }

    // ================================================================================================ Paragon masteries
    public sealed class ParagonMasteryRow
    {
        public string Key = "", Name = "", Desc = "";
        public int Ranks;
        public double Value, Next;
    }

    public sealed partial class ParagonPanel
    {
        public int MasteryMaxRanks;
        public bool HasMastery, HasExchange;
        public readonly List<ParagonMasteryRow> MasteryRows = new List<ParagonMasteryRow>();
        public double ExchangeRatio = 1, ExchangeTreeFree, ExchangeConverted;

        void ParseMastery(object data)
        {
            MasteryRows.Clear();
            object m = Json.Get(data, "mastery");
            HasMastery = m is Dictionary<string, object>;
            if (HasMastery)
            {
                MasteryMaxRanks = Json.Int(m, "maxRanks");
                foreach (object r in Json.List(m, "rows"))
                    MasteryRows.Add(new ParagonMasteryRow { Key = Json.Text(r, "key"), Name = Json.Text(r, "name"), Desc = Json.Text(r, "desc"), Ranks = Json.Int(r, "ranks"), Value = Json.Number(r, "value"), Next = Json.Number(r, "next") });
            }
            object x = Json.Get(data, "exchange");
            HasExchange = x is Dictionary<string, object>;
            if (HasExchange) { ExchangeRatio = Json.Number(x, "ratio", 1); ExchangeTreeFree = Json.Number(x, "treeFree"); ExchangeConverted = Json.Number(x, "converted"); }
        }

        /// <summary>3 decimals, trailing zeros dropped: 0.0167 to "0.017".</summary>
        public static string Fmt3(double v)
        {
            string s = v.ToString("0.000", CultureInfo.InvariantCulture).TrimEnd('0');
            if (s.EndsWith(".", StringComparison.Ordinal)) s = s.Substring(0, s.Length - 1);
            return s;
        }

        /// <summary>Ranks one click buys: n limited by the free points and the room under the rank limit (0 when locked).</summary>
        public int MasteryBuy(ParagonMasteryRow row, int n)
        {
            if (!Known || !Unlocked || !HasMastery || row == null) return 0;
            int room = MasteryMaxRanks - row.Ranks;
            return Math.Max(0, Math.Min(n, Math.Min(room, FreePoints)));
        }

        public static string MasteryValueText(ParagonMasteryRow r) => "+" + Fmt(r.Value) + "%";
        public static string MasteryNextText(ParagonMasteryRow r) => "+" + Fmt3(r.Next) + "%";

        /// <summary>Free tree points that can be exchanged (0 when the exchange is not offered).</summary>
        public int Exchangeable => Known && Unlocked && HasExchange ? (int)Math.Max(0, Math.Floor(ExchangeTreeFree)) : 0;

        public double ExchangeGain(int n) => Math.Max(0, n) * ExchangeRatio;

        /// <summary>The "Info and Bonuses" lines of the masteries that have ranks.</summary>
        public List<string> MasteryLines()
        {
            var l = new List<string>();
            foreach (var r in MasteryRows) if (r.Ranks > 0) l.Add(Loc.T("+{0}% {1} ({2} ranks).", Fmt(r.Value), r.Name, r.Ranks));
            return l;
        }

        /// <summary>Buys n ranks of a mastery (1, 10 or 100) when the server would take it; the server checks again.</summary>
        public bool BuyMastery(ParagonMasteryRow row, int n)
        {
            if (MasteryBuy(row, n) < n) return false;
            ext.Send(PassiveTree.Opcode, "paragonMastery", new Dictionary<string, object> { { "key", row.Key }, { "n", n } });
            return true;
        }

        public string ExchangeAsk => Loc.T("Turn {0} free passive tree points into {1} Paragon points? This cannot be undone: the points stay Paragon points. Proceed?", Exchangeable, Fmt(ExchangeGain(Exchangeable)));

        public string ExchangeLine => Loc.T("Free passive tree points: {0}. Each one becomes {1} Paragon point(s), for good. Already exchanged: {2}.", Exchangeable, Fmt(ExchangeRatio), Fmt(ExchangeConverted));

        public bool Exchange()
        {
            int n = Exchangeable;
            if (n <= 0) return false;
            ext.Send(PassiveTree.Opcode, "paragonConvert", new Dictionary<string, object> { { "n", n } });
            return true;
        }
    }

    // ================================================================================================ node icons and curved links
    /// <summary>The clip of an icon key in its sheet (PassiveTreeIcons.json): the sheet is skills.png unless the key has its own file (keystones.png).</summary>
    public sealed class TreeIconClip { public string File = ""; public int X, Y, W, H; }

    public sealed class TreeIcons
    {
        public const string DefaultSheet = "skills.png";
        public readonly Dictionary<string, TreeIconClip> Clips = new Dictionary<string, TreeIconClip>();
        public readonly Dictionary<string, int[]> Painted = new Dictionary<string, int[]>();

        public static TreeIcons Parse(string json)
        {
            var t = new TreeIcons();
            object root = Json.Parse(json);
            if (Json.Get(root, "icons") is Dictionary<string, object> ic)
                foreach (var kv in ic)
                    t.Clips[kv.Key] = new TreeIconClip { File = Json.Text(kv.Value, "f"), X = Json.Int(kv.Value, "x"), Y = Json.Int(kv.Value, "y"), W = Json.Int(kv.Value, "w"), H = Json.Int(kv.Value, "h") };
            if (Json.Get(root, "painted") is Dictionary<string, object> pt)
                foreach (var kv in pt)
                    if (kv.Value is List<object> xy && xy.Count == 2 && xy[0] is double x && xy[1] is double y) t.Painted[kv.Key] = new[] { (int)x, (int)y };
            return t;
        }

        /// <summary>The icon key a node shows for a class variant: the variant's own key when it has one (a keystone's, a class lane's), else the node's (passivetree.lua create).</summary>
        public static string KeyFor(TreeNode n, string variant)
        {
            if (n == null) return "";
            if (!n.IsStart && !string.IsNullOrEmpty(variant) && n.VariantIcons.TryGetValue(variant, out string k) && k.Length > 0) return k;
            return n.Icon;
        }

        /// <summary>The sheet path (under the overlay's data folder) and clip of a key; with the painted option a keystone or mastery with a painted cell gives painted_nodes.png.</summary>
        public bool Resolve(string key, bool painted, out string path, out int x, out int y, out int w, out int h)
        {
            path = ""; x = y = w = h = 0;
            if (string.IsNullOrEmpty(key)) return false;
            if (painted && Painted.TryGetValue(key, out int[] cell))
            {
                path = PaintedIcons.NodePath; x = cell[0]; y = cell[1]; w = h = PaintedIcons.NodeCell;
                return true;
            }
            if (!Clips.TryGetValue(key, out var c) || c.W <= 0 || c.H <= 0) return false;
            path = ArtPaths.Data("images/passivetree/" + (c.File.Length > 0 ? c.File : DefaultSheet));
            if (!path.EndsWith(".png", StringComparison.Ordinal)) path += ".png";
            x = c.X; y = c.Y; w = c.W; h = c.H;
            return true;
        }
    }

    /// <summary>The geometry and frames of each node kind (passivetree.otui): the widget size the icon clip is drawn in, the frame picture drawn over it and its size, by the node's state.</summary>
    public static class TreeNodeArt
    {
        public enum State { Unallocated, CanAllocate, Allocated }

        public sealed class Geom { public double Size, FrameW, FrameH; public string[] Frames; }

        static readonly Dictionary<char, Geom> Kinds = new Dictionary<char, Geom>
        {
            { 'c', new Geom { Size = 27, FrameW = 56, FrameH = 56, Frames = new[] { "common_notallocated", "commont_canallocate", "common_active" } } },
            { 'u', new Geom { Size = 38, FrameW = 95, FrameH = 95, Frames = new[] { "uncommon_notallocated", "uncommon_canallocate", "uncommon_activated" } } },
            { 'r', new Geom { Size = 41, FrameW = 95, FrameH = 95, Frames = new[] { "rare_notallocated", "rare_canallocate", "rare_active" } } },
            { 'v', new Geom { Size = 38, FrameW = 95, FrameH = 95, Frames = new[] { "veryrare_notallocate", "veryrare_canallocate", "veryrare_active" } } },
            { 'm', new Geom { Size = 38, FrameW = 95, FrameH = 95, Frames = new[] { "NotableFrameUnallocated", "NotableFrameCanAllocate", "NotableFrameAllocated" } } },
            { 'd', new Geom { Size = 60, FrameW = 143, FrameH = 149, Frames = new[] { "KeystoneFrameUnallocated", "KeystoneFrameCanAllocate", "KeystoneFrameAllocated" } } },
            { 'M', new Geom { Size = 44, FrameW = 105, FrameH = 105, Frames = new[] { "rare_notallocated", "rare_canallocate", "rare_active" } } },
        };

        public static Geom Of(char type) => Kinds.TryGetValue(type, out var g) ? g : Kinds['c'];

        public static string FramePath(char type, State s) => ArtPaths.Data("images/passivetree/" + Of(type).Frames[(int)s] + ".png");

        /// <summary>The state of a node for its frame: saved (or planned, or in the preview) is allocated, a reachable node can be allocated, the rest not.</summary>
        public static State StateOf(bool allocated, bool reachable) => allocated ? State.Allocated : reachable ? State.CanAllocate : State.Unallocated;

        /// <summary>The icon clip is drawn at its widget size; the frame is centred on the node at its own size. Both scaled by the zoom; below this zoom a node is a plain disc (too small to read).</summary>
        public const double ArtMinZoom = 0.25;
    }

    /// <summary>The curved link between two nodes of one group and orbit: an arc round the group centre (passivetree.lua BuildConnector), when the shorter way round is under 0.9 pi.</summary>
    public static class TreeArcs
    {
        public const double MaxArc = Math.PI * 0.9;
        public const double Step = Math.PI / 18.0;

        /// <summary>The polyline of the arc from node a to node b round (cx, cy) in tree units, or null when the link is a straight line (other orbit, other group, no orbit, too wide).</summary>
        public static List<double[]> Arc(TreeNode a, TreeNode b, double cx, double cy)
        {
            if (a == null || b == null || a.Orbit <= 0 || a.Group != b.Group || a.Orbit != b.Orbit || a.Group == 0) return null;
            double a1 = Math.Atan2(a.X - cx, -(a.Y - cy)), a2 = Math.Atan2(b.X - cx, -(b.Y - cy));
            double r1 = Math.Sqrt((a.X - cx) * (a.X - cx) + (a.Y - cy) * (a.Y - cy)), r2 = Math.Sqrt((b.X - cx) * (b.X - cx) + (b.Y - cy) * (b.Y - cy));
            if (r1 < 1 || r2 < 1) return null;
            double d = a2 - a1;
            while (d > Math.PI) d -= 2 * Math.PI;
            while (d < -Math.PI) d += 2 * Math.PI;
            if (Math.Abs(d) >= MaxArc) return null;
            int n = Math.Max(2, (int)Math.Ceiling(Math.Abs(d) / Step));
            var pts = new List<double[]>();
            for (int i = 0; i <= n; i++)
            {
                double t = (double)i / n, ang = a1 + d * t, r = r1 + (r2 - r1) * t;
                pts.Add(new[] { cx + Math.Sin(ang) * r, cy - Math.Cos(ang) * r });
            }
            return pts;
        }
    }
}
