// Cosmetics (client game_cosmetics) and the unlock rules of the outfit and cosmetic lists (client game_unlocks), extended opcode 225, server cosmetics.lua / wardrobe.lua.
//   client -> server  hello (500 ms after the login) | open | state | select {kind, id, line} | preview {id} | wardrobe
//   server -> client  state {rows [{id, kind, line, lineName, name, owned, selected, desc, how, item, color, accent, art, pulse, preview, source, play}], line, lineName,
//                     collection [{key, name, kind, kindName, owned, how, use, item}], score {score, next {points, left}, milestones [{points, done, rewards [{k, n, f}]}], groups [{g, n, p}]}, open}
//                     style {accent} | colors {full, names {name: "#rrggbb"}} (chat name colours) | looks {..} | tryfx {kind, art, p|pulse} | wardrobe {sex, hash, outfit|mount|wings|aura|shader [{l, n, o, a, s}]}
//                     result {ok, text}
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace Chaos.Core
{
    /// <summary>A row of a cosmetic list (a server row, the Default row, a collection row or the score row).</summary>
    public sealed class CosRow
    {
        public string Id = "", Kind = "", Line, Name = "", Desc, How, Color, Accent, Art, Source = "", LineName, KindName, Use, Key = "";
        public int Item;
        public double Pulse;
        public bool Owned, Selected, Preview, OtherLine, Collection;
        public bool? Locked;
        public List<object> Play;
    }

    /// <summary>The cosmetic kinds and the pure rules of CosmeticsLogic (cosmeticslogic.lua).</summary>
    public static class CosmeticsLogic
    {
        public static readonly string[][] Kinds =
        {
            new[] { "spellskin", "Spell Effects" }, new[] { "killfx", "Kill Effects" }, new[] { "lootbeam", "Loot Labels" }, new[] { "chatcolor", "Chat Colours" },
            new[] { "footprint", "Footprints" }, new[] { "outline", "Outlines" }, new[] { "levelfx", "Level-ups" }, new[] { "rarefx", "Rare Loot" },
            new[] { "emote", "Emotes" }, new[] { "collection", "Collection" },
        };
        public const string ScoreRow = "x:score";
        public static bool Drawn(string kind) => kind == "footprint" || kind == "outline";

        static readonly Dictionary<string, string> DefaultText = new Dictionary<string, string>
        {
            { "spellskin", "Your spells show their own effects." }, { "killfx", "No effect on your kills." }, { "lootbeam", "Your highlighted loot labels keep the dark background." },
            { "chatcolor", "Your name in chat keeps the colour of the message." }, { "footprint", "You leave no footprints." }, { "outline", "No outline around you." },
            { "levelfx", "No effect when you gain a level." }, { "rarefx", "No effect when a kill drops a rare item." }, { "emote", "No emote after a boss kill." },
        };

        static readonly Dictionary<string, string> GroupNames = new Dictionary<string, string>
        {
            { "outfit", "Outfits" }, { "mount", "Mounts" }, { "wings", "Wings" }, { "aura", "Auras" }, { "shader", "Shaders" }, { "frame", "Plate frames" }, { "spellskin", "Spell skins" },
            { "killfx", "Kill effects" }, { "levelfx", "Level-up effects" }, { "rarefx", "Rare loot effects" }, { "emote", "Emotes" }, { "lootbeam", "Loot labels" },
            { "chatcolor", "Chat colours" }, { "footprint", "Footprints" }, { "outline", "Outlines" }, { "title", "Titles" },
        };

        public static bool ValidColor(string s) => s != null && Regex.IsMatch(s, @"^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$");

        public static CosRow FromServer(Dictionary<string, object> r)
        {
            var row = new CosRow
            {
                Id = CF.Str(CF.G(r, "id")), Kind = CF.T(r, "kind"), Line = CF.G(r, "line") == null ? null : CF.Str(CF.G(r, "line")), Name = CF.T(r, "name"),
                Owned = CF.B(r, "owned"), Selected = CF.B(r, "selected"), Desc = CF.G(r, "desc") as string, How = CF.G(r, "how") as string, Item = CF.I(r, "item"),
                Color = CF.G(r, "color") as string, Accent = CF.G(r, "accent") as string, Art = CF.G(r, "art") as string, Pulse = CF.N(r, "pulse"), Preview = CF.B(r, "preview"),
                Source = CF.T(r, "source"), LineName = CF.G(r, "lineName") as string, Play = CF.G(r, "play") as List<object>,
            };
            if (CF.G(r, "locked") is bool l) row.Locked = l;
            return row;
        }

        public static List<CosRow> TabRows(IEnumerable<Dictionary<string, object>> rows, string kind, string line, string lineName)
        {
            var mine = new List<CosRow>(); var other = new List<CosRow>();
            bool anySelected = false;
            foreach (var r in rows)
            {
                if (CF.T(r, "kind") != kind) continue;
                var row = FromServer(r);
                if (kind == "spellskin")
                {
                    if (row.Line == line) { mine.Add(row); if (row.Selected) anySelected = true; }
                    else { row.OtherLine = true; other.Add(row); }
                }
                else { mine.Add(row); if (row.Selected) anySelected = true; }
            }
            var o = new List<CosRow>();
            if (kind != "spellskin" || line != null)
                o.Add(new CosRow
                {
                    Id = "0", Kind = kind, Line = line, Name = Loc.T("Default"), Owned = true, Selected = !anySelected,
                    Desc = DefaultText.TryGetValue(kind, out var d) ? Loc.T(d) : null,
                    How = kind == "spellskin" ? Loc.T("Every spell of your {0}", lineName ?? Loc.T("line")) : Loc.T("Every character"),
                });
            o.AddRange(mine); o.AddRange(other);
            return o;
        }

        public static List<CosRow> CollectionRows(IEnumerable<Dictionary<string, object>> collection, string filter, object scoreView)
        {
            var owned = new List<CosRow>(); var missing = new List<CosRow>();
            foreach (var r in collection)
            {
                if (!(CF.G(r, "key") is string key)) continue;
                var row = new CosRow
                {
                    Id = "x:" + key, Key = key, Collection = true, Name = CF.T(r, "name"), Kind = CF.T(r, "kind"), KindName = CF.G(r, "kindName") as string, Owned = CF.B(r, "owned"),
                    How = CF.G(r, "how") as string, Use = CF.G(r, "use") as string, Item = CF.I(r, "item"), Desc = CF.G(r, "desc") as string,
                };
                (row.Owned ? owned : missing).Add(row);
            }
            var o = new List<CosRow>();
            var score = ScoreRowOf(scoreView);
            if (score != null) o.Add(score);
            if (filter != "missing") o.AddRange(owned);
            if (filter != "owned") o.AddRange(missing);
            return o;
        }

        public static void CollectionCount(IEnumerable<Dictionary<string, object>> collection, out int have, out int all)
        {
            have = all = 0;
            foreach (var r in collection) if (CF.G(r, "key") is string) { all++; if (CF.B(r, "owned")) have++; }
        }

        public static string SubText(CosRow r)
        {
            if (r.Id == ScoreRow) return Loc.T("Rewards for owning cosmetics");
            if (r.Collection) return (r.KindName ?? r.Kind) + (r.Owned ? " - " + Loc.T("Unlocked") : " - " + (r.How ?? Loc.T("Locked")));
            if (r.OtherLine) return Loc.T("{0} - not your class", r.LineName ?? Loc.T("Another line"));
            if (r.Id == "0") return r.Selected ? Loc.T("In use") : Loc.T("Default");
            if (r.Selected) return Loc.T("In use");
            if (r.Owned) return Loc.T("Unlocked");
            return r.How ?? Loc.T("Locked");
        }

        public static bool CanUse(CosRow r) => r != null && r.Owned && !r.Selected && !r.OtherLine && !r.Collection;

        static int Whole(object v) => (int)Math.Floor(CF.Num(v));

        public static string ScoreLine(object view)
        {
            if (!(view is Dictionary<string, object>)) return "";
            string text = Loc.T("Collection score: {0}", Whole(CF.G(view, "score")));
            var next = CF.G(view, "next");
            if (next is Dictionary<string, object>) return text + " - " + Loc.T("next reward at {0} ({1} to go)", Whole(CF.G(next, "points")), Whole(CF.G(next, "left")));
            return text + " - " + Loc.T("every reward earned");
        }

        public static string RewardLabel(object r)
        {
            string n = CF.T(r, "n");
            switch (CF.T(r, "k"))
            {
                case "title": return CF.B(r, "f") ? Loc.T("Title {0} and a plate frame", n) : Loc.T("Title {0}", n);
                case "footprint": return Loc.T("Footprints {0}", n);
                case "chatcolor": return Loc.T("Chat colour {0}", n);
                case "killfx": return Loc.T("Kill effect {0}", n);
                case "outline": return Loc.T("Outline {0}", n);
            }
            return Loc.T("Cosmetic {0}", n);
        }

        public static List<string> MilestoneLines(object view)
        {
            var o = new List<string>();
            foreach (var m in CF.Rows(CF.G(view, "milestones")))
                o.Add((CF.B(m, "done") ? "[x] " : "[ ] ") + Loc.T("{0} points", Whole(CF.G(m, "points"))) + ": " + string.Join(", ", CF.Rows(CF.G(m, "rewards")).Select(RewardLabel)));
            return o;
        }

        public static string GroupLine(object view)
        {
            var o = new List<string>();
            foreach (var g in CF.Rows(CF.G(view, "groups")))
                if (GroupNames.TryGetValue(CF.T(g, "g"), out var name)) o.Add(Loc.T(name) + " " + Whole(CF.G(g, "n")) + " (" + Whole(CF.G(g, "p")) + ")");
            return string.Join(", ", o);
        }

        public static CosRow ScoreRowOf(object view)
        {
            if (!(view is Dictionary<string, object>) || CF.G(view, "score") == null) return null;
            return new CosRow
            {
                Id = ScoreRow, Key = "score", Collection = true, Owned = true, Kind = "score", Name = Loc.T("Collection score: {0}", Whole(CF.G(view, "score"))),
                Desc = string.Join("\n", MilestoneLines(view)), How = GroupLine(view),
            };
        }

        /// <summary>Chat name colours: a message with full replaces the table, else names are added; a bad colour removes the name.</summary>
        public static Dictionary<string, string> MergeColors(Dictionary<string, string> current, object msg)
        {
            if (!(msg is Dictionary<string, object>)) return current ?? new Dictionary<string, string>();
            var o = CF.B(msg, "full") || current == null ? new Dictionary<string, string>() : new Dictionary<string, string>(current);
            if (CF.G(msg, "names") is Dictionary<string, object> names)
                foreach (var kv in names)
                {
                    if (kv.Value is string c && ValidColor(c)) o[kv.Key] = c; else o.Remove(kv.Key);
                }
            return o;
        }

        /// <summary>The 1-based range of the speaker's name in a chat line (only before ": ", after a space, followed by nothing or " [").</summary>
        public static bool NameRange(string text, string name, out int first, out int last)
        {
            first = last = 0;
            if (string.IsNullOrEmpty(text) || string.IsNullOrEmpty(name)) return false;
            int stop = text.IndexOf(": ", StringComparison.Ordinal);
            string head = stop >= 0 ? text.Substring(0, stop) : text;
            int from = 0;
            while (true)
            {
                int s = head.IndexOf(" " + name, from, StringComparison.Ordinal);
                if (s < 0) return false;
                int a = s + 1 + name.Length;
                string after = a >= head.Length ? "" : head.Substring(a, Math.Min(2, head.Length - a));
                if (after == "" || after == " [") { first = s + 2; last = s + 1 + name.Length; return true; }
                from = s + 1;
            }
        }
    }

    /// <summary>Lock rules of the wardrobe and cosmetic lists (unlocks_core.lua).</summary>
    public static class UnlocksCore
    {
        public const float LockedOpacity = 0.45f;

        public static bool IsLocked(CosRow e)
        {
            if (e == null) return false;
            if (e.Locked.HasValue) return e.Locked.Value;
            if (e.Id == "0") return false;
            return !e.Owned;
        }

        public static bool CanUse(CosRow e) => e != null && !IsLocked(e);

        public static string Tooltip(CosRow e)
        {
            if (e == null) return null;
            string how = string.IsNullOrEmpty(e.How) ? null : e.How;
            if (IsLocked(e)) return how != null ? Loc.T("Not unlocked yet.") + "\n" + Loc.T("How to get it: {0}", Loc.T(how)) : Loc.T("Not unlocked yet.");
            return how != null ? Loc.T("Unlocked.") + "\n" + Loc.T(how) : null;
        }

        /// <summary>Unlocked rows first; the locked ones follow unless onlyMine hides them.</summary>
        public static List<CosRow> Filter(IEnumerable<CosRow> list, bool onlyMine)
        {
            var mine = new List<CosRow>(); var locked = new List<CosRow>();
            foreach (var e in list) (IsLocked(e) ? locked : mine).Add(e);
            if (!onlyMine) mine.AddRange(locked);
            return mine;
        }

        public static void Count(IEnumerable<CosRow> list, out int have, out int all)
        {
            have = all = 0;
            foreach (var e in list) { all++; if (!IsLocked(e)) have++; }
        }
    }

    /// <summary>One entry of the wardrobe (an outfit, mount, wings, aura or shader the account can or cannot wear).</summary>
    public sealed class WardrobeEntry { public int Look; public string Name = "", Source; public bool Owned; public object Add; }

    public sealed class CosmeticsState : CollectModel
    {
        public const byte OpcodeId = 225;
        public static readonly string[] WardrobeKinds = { "outfit", "mount", "wings", "aura", "shader" };

        public object State;
        public string Tab = "spellskin", SelectedId;
        public bool Visible;
        public string Accent;
        public Dictionary<string, string> NameColors = new Dictionary<string, string>();
        public Dictionary<string, List<WardrobeEntry>> Wardrobe;
        public string WardrobeHash = "";
        public string StatusText = "";
        public bool StatusOk;
        public double StatusAt;
        public bool OnlyMineAll;
        readonly HashSet<string> onlyMine = new HashSet<string>();

        public CosmeticsState(ExtOpcodes e) : base(e, OpcodeId) { }

        public void Hello() { Send("hello"); }
        public void Show() { Visible = true; Send("open"); }
        public void Hide() { Visible = false; }
        public void Toggle() { if (Visible) Hide(); else Show(); }
        public void AskWardrobe() { Send("wardrobe"); }
        public void Select(CosRow r) { if (r != null && CosmeticsLogic.CanUse(r)) Send("select", D("kind", r.Kind, "id", NumOrText(r.Id), "line", r.Line ?? (object)CF.G(State, "line"))); }
        public void PreviewRow(CosRow r) { if (r != null && r.Preview && !CosmeticsLogic.Drawn(r.Kind)) Send("preview", D("id", NumOrText(r.Id))); }
        public void SelectTab(string key) { Tab = key; SelectedId = null; }

        static object NumOrText(string id) => double.TryParse(id, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var d) ? d : (object)id;

        /// <summary>The "only mine" box of a list (kept per list for this session; the main client saves it per character).</summary>
        public bool OnlyMine(string list) => onlyMine.Contains(list);
        public void SetOnlyMine(string list, bool on) { if (on) onlyMine.Add(list); else onlyMine.Remove(list); }

        public override void Handle(string action, object data)
        {
            switch (action)
            {
                case "state":
                    State = data;
                    if (CF.B(data, "open")) Visible = true;
                    break;
                case "style": Accent = CosmeticsLogic.ValidColor(CF.G(data, "accent") as string) ? (string)CF.G(data, "accent") : null; break;
                case "colors": NameColors = CosmeticsLogic.MergeColors(NameColors, data); break;
                case "wardrobe": ReadWardrobe(data); break;
                case "result":
                    if (CF.T(data, "text").Length > 0) { StatusText = CF.T(data, "text"); StatusOk = CF.B(data, "ok"); StatusAt = Clock(); }
                    break;
            }
        }

        public void ReadWardrobe(object data)
        {
            if (!(data is Dictionary<string, object>)) return;
            var w = new Dictionary<string, List<WardrobeEntry>>();
            foreach (string kind in WardrobeKinds)
            {
                var list = new List<WardrobeEntry>();
                foreach (var c in CF.Rows(CF.G(data, kind)))
                {
                    bool shader = kind == "shader";
                    if (shader ? !(CF.G(c, "n") is string) : CF.N(c, "l") <= 0) continue;
                    bool owned = CF.G(c, "o") is bool b ? b : CF.N(c, "o") == 1;
                    list.Add(new WardrobeEntry { Look = CF.I(c, "l"), Name = CF.G(c, "n") as string ?? "", Owned = owned, Add = CF.G(c, "a"), Source = CF.G(c, "s") as string });
                }
                w[kind] = list;
            }
            Wardrobe = w;
            WardrobeHash = CF.T(data, "hash");
        }

        public void Clear() { State = null; Visible = false; SelectedId = null; NameColors = new Dictionary<string, string>(); Accent = null; Wardrobe = null; }

        public List<Dictionary<string, object>> ServerRows => CF.Rows(CF.G(State, "rows"));
        public List<Dictionary<string, object>> CollectionData => CF.Rows(CF.G(State, "collection"));

        /// <summary>The rows the tab shows, locked ones last (or hidden with "only mine").</summary>
        public List<CosRow> TabRows()
        {
            List<CosRow> rows = Tab == "collection"
                ? CosmeticsLogic.CollectionRows(CollectionData, null, CF.G(State, "score"))
                : CosmeticsLogic.TabRows(ServerRows, Tab, CF.G(State, "line") == null ? null : CF.Str(CF.G(State, "line")), CF.G(State, "lineName") as string);
            return UnlocksCore.Filter(rows, OnlyMine(Tab));
        }

        public CosRow RowOf(string id) => TabRows().FirstOrDefault(r => r.Id == id);

        public string StatusLine()
        {
            if (Tab == "spellskin") return CF.G(State, "lineName") is string ln ? Loc.T("Your class line: ") + ln : Loc.T("Your class has no spell skins yet.");
            if (CosmeticsLogic.Drawn(Tab)) return Loc.T("Account-wide; each character chooses.");
            if (Tab == "collection") { CosmeticsLogic.CollectionCount(CollectionData, out int have, out int all); return Loc.T("Earned") + " " + have + " / " + all + " " + Loc.T("(never sold)"); }
            return Loc.T("Unlocks are for your whole account; each character chooses.");
        }

        public string ScoreLine() => CF.G(State, "score") != null ? CosmeticsLogic.ScoreLine(CF.G(State, "score")) : "";

        /// <summary>The row the list should select: the kept one, the one in use, the score row of the collection, else the first.</summary>
        public string DefaultSelection()
        {
            if (SelectedId != null && RowOf(SelectedId) != null) return SelectedId;
            var rows = TabRows();
            var inUse = rows.FirstOrDefault(r => r.Selected);
            if (inUse != null) return inUse.Id;
            if (Tab == "collection" && RowOf(CosmeticsLogic.ScoreRow) != null) return CosmeticsLogic.ScoreRow;
            return "0";
        }
    }
}
