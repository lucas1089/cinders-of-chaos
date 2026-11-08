// Bestiary and kill tasks (client game_bestiary, extended opcode 253, server bestiary.lua).
//   client -> server  open | summary | list | entry {id} | take {id} | board | accept {key} | abandon {key} | reroll | query
//   server -> client  summary {known, total, completed, percent, points, stagePoints, taskPoints, rank {name, exp, next, nextName}, cats [{key, name, known, completed, total}],
//                     diffs [{key, name}], stages [names], count, open}
//                     list {first, last, rows [[id, name, cat, diff, level, kills, stage, look], ...]}   (parts, complete at the last)
//                     entry {id, name, cat, diff, diffName, stage, kills, next, th [kills], level, minLevel, maxLevel, health, exp, points [..], elements [{name, pct}],
//                     immunities [..], areas [{text}], spawns, loot [{cid, name, chance, max, bossOnly}], uniques [{cid, name}], bonus {damage, exp},
//                     task {active, can, required, reward, text}, outfit}
//                     kill {id, kills, stage, next}  | board {offers [..], tasks [..], active, maxActive, doneDay, dailyLimit, doneWeek, weeklyLimit, rerolls, nextIn}
//                     tracker {rows [{k, label, p, r}]}  | show {tab}
using System;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core
{
    public sealed class BestiaryRow
    {
        public int Id, Level, Kills, Stage, Look;
        public string Name = "";
        public string Cat = "", Diff = "";
    }

    public sealed class BestiaryState : CollectModel
    {
        public const byte OpcodeId = 253;
        public const int PageSize = 60;
        public const string All = "all";
        public static readonly string[] StageColors = { "#6b6258", "#d6c9ae", "#5a8fff", "#b070ff", "#f6cf72" };

        public object Summary, Detail, Board;
        public List<BestiaryRow> Rows = new List<BestiaryRow>();
        public readonly Dictionary<int, BestiaryRow> ById = new Dictionary<int, BestiaryRow>();
        public bool ListComplete, ListAsked;
        public string SelectedCat = All, Tab = "bestiary", Search = "";
        public bool KnownOnly;
        public int Page = 1, SelectedId;
        public List<object> TrackerRows = new List<object>();
        public bool Visible;
        public double BoardAt;

        public BestiaryState(ExtOpcodes e) : base(e, OpcodeId) { }

        public void Open() { if (Visible) Visible = false; else Send("open"); }
        public void ShowTasks() { Send("board"); Visible = true; Tab = "tasks"; }
        public void SetTab(string tab) { Tab = tab; if (tab == "tasks") Send("board"); }
        public void Query() { Send("query"); }
        public void SelectEntry(int id) { SelectedId = id; Send("entry", D("id", (double)id)); }
        public void TakeTask(int id) { Send("take", D("id", (double)id)); }
        public void Accept(string key) { Send("accept", D("key", key)); }
        public void Abandon(string key) { Send("abandon", D("key", key)); }
        public void Reroll() { Send("reroll"); }
        public void AskList() { Send("list"); }

        public override void Handle(string action, object data)
        {
            switch (action)
            {
                case "summary":
                    Summary = data;
                    if (CF.B(data, "open")) { Visible = true; Tab = "bestiary"; }
                    if ((!ListComplete || Rows.Count != CF.I(data, "count")) && !ListAsked) { ListAsked = true; AskList(); }
                    if (!CatKeys().Contains(SelectedCat)) SelectedCat = All;
                    break;
                case "list":
                    if (CF.B(data, "first")) { Rows = new List<BestiaryRow>(); ById.Clear(); ListComplete = false; }
                    foreach (object raw in CF.Raw(CF.G(data, "rows")))
                    {
                        var r = ToRow(raw);
                        if (r == null) continue;
                        Rows.Add(r);
                        ById[r.Id] = r;
                    }
                    if (CF.B(data, "last"))
                    {
                        ListComplete = true; ListAsked = false;
                        if (SelectedId == 0) foreach (var r in Rows) if (r.Stage >= 1) { SelectEntry(r.Id); break; }
                    }
                    break;
                case "entry":
                    Detail = data;
                    SelectedId = CF.I(data, "id");
                    if (ById.TryGetValue(SelectedId, out var row)) { row.Kills = CF.I(data, "kills"); row.Stage = CF.I(data, "stage"); }
                    if (!Visible) { Visible = true; Tab = "bestiary"; }
                    break;
                case "kill": OnKill(data); break;
                case "board": Board = data; BoardAt = Clock(); break;
                case "tracker": TrackerRows = CF.Raw(CF.G(data, "rows")).Where(x => x is Dictionary<string, object>).ToList(); break;
                case "show": Visible = true; Tab = CF.T(data, "tab") == "tasks" ? "tasks" : "bestiary"; break;
            }
        }

        public static BestiaryRow ToRow(object raw)
        {
            if (!(raw is List<object> a)) return null;
            object At(int i) => i < a.Count ? a[i] : null;
            return new BestiaryRow { Id = CF.Int(At(0)), Name = CF.Str(At(1), "?"), Cat = CF.Str(At(2)), Diff = CF.Str(At(3)), Level = CF.Int(At(4)), Kills = CF.Int(At(5)), Stage = CF.Int(At(6)), Look = CF.Int(At(7)) };
        }

        void OnKill(object data)
        {
            int id = CF.I(data, "id");
            bool changed = false;
            if (ById.TryGetValue(id, out var r)) { changed = r.Stage != CF.I(data, "stage"); r.Kills = CF.I(data, "kills"); r.Stage = CF.I(data, "stage"); }
            if (!Visible) return;
            if (Detail != null && CF.I(Detail, "id") == id)
            {
                if (changed) Send("entry", D("id", (double)id));
                else if (Detail is Dictionary<string, object> d) { d["kills"] = CF.G(data, "kills"); d["next"] = CF.G(data, "next"); }
            }
            if (changed) Send("summary");
        }

        public void Clear()
        {
            Summary = null; Detail = null; Board = null; Rows = new List<BestiaryRow>(); ById.Clear(); ListComplete = false; ListAsked = false;
            SelectedId = 0; TrackerRows = new List<object>(); Visible = false; SelectedCat = All; Page = 1;
        }

        IEnumerable<string> CatKeys() { yield return All; foreach (var c in CF.Rows(CF.G(Summary, "cats"))) yield return CF.Str(CF.G(c, "key")); }

        // ---------------------------------------------------------------------------------------------- the view rules
        public List<BestiaryRow> Filtered() => Filter(Rows, SelectedCat, Search, KnownOnly);

        public static List<BestiaryRow> Filter(IEnumerable<BestiaryRow> rows, string cat, string query, bool knownOnly)
        {
            string q = (query ?? "").Trim().ToLowerInvariant();
            return rows.Where(r => (cat == null || cat == All || r.Cat == cat) && (!knownOnly || r.Stage >= 1) && (q.Length == 0 || r.Name.ToLowerInvariant().Contains(q))).ToList();
        }

        public static List<T> Paged<T>(IList<T> list, int page, int size, out int shownPage, out int pages)
        {
            pages = Math.Max(1, (list.Count + size - 1) / size);
            shownPage = Math.Max(1, Math.Min(page, pages));
            return list.Skip((shownPage - 1) * size).Take(size).ToList();
        }

        public string CatName(string key) { foreach (var c in CF.Rows(CF.G(Summary, "cats"))) if (CF.Str(CF.G(c, "key")) == key) return CF.T(c, "name"); return key ?? ""; }
        public string DiffName(string key) { foreach (var c in CF.Rows(CF.G(Summary, "diffs"))) if (CF.Str(CF.G(c, "key")) == key) return CF.T(c, "name"); return key ?? ""; }

        public string StageName(int stage) => StageName(stage, CF.Raw(CF.G(Summary, "stages")));

        public static string StageName(int stage, List<object> names)
        {
            if (stage <= 0) return Loc.T("Undiscovered");
            return stage - 1 < names.Count && names[stage - 1] is string s ? Loc.T(s) : Loc.T("Stage {0}", stage);
        }

        public string HeaderText()
        {
            var rank = CF.M(Summary, "rank");
            return Loc.T("Known {0} / {1}   Completed {2} ({3})   Points {4}   Rank: {5}", CF.I(Summary, "known"), CF.I(Summary, "total"), CF.I(Summary, "completed"),
                CF.Pct(CF.N(Summary, "percent")), CF.I(Summary, "points"), CF.T(rank, "name"));
        }

        public string HeaderTip()
        {
            var rank = CF.M(Summary, "rank");
            string tip = Loc.T("Bestiary points: {0} from stages, {1} from kill tasks.", CF.I(Summary, "stagePoints"), CF.I(Summary, "taskPoints"));
            if (CF.N(rank, "exp") > 0) tip += "\n" + Loc.T("Rank bonus: +{0} experience from every monster.", CF.Pct(CF.N(rank, "exp")));
            if (CF.G(rank, "next") != null) tip += "\n" + Loc.T("Next rank: {0} at {1} points.", CF.T(rank, "nextName"), CF.I(rank, "next"));
            return tip;
        }

        public static string KillText(double kills, object next) => CF.Num(next) > 0 ? Loc.T("Kills {0} / {1}", (long)kills, (long)CF.Num(next)) : Loc.T("Kills {0}", (long)kills);

        public static int StagePercent(double kills, IList<string> th)
        {
            double prev = 0;
            foreach (string t in th)
            {
                double k = CF.Num(t);
                if (kills < k) return (int)Math.Floor((kills - prev) * 100 / Math.Max(1, k - prev));
                prev = k;
            }
            return 100;
        }

        public static string ElementsText(object list)
        {
            var parts = new List<string>();
            foreach (object e in CF.Raw(list))
            {
                double taken = -CF.N(e, "pct");
                parts.Add(string.Format("{0} {1}{2}", CF.T(e, "name"), taken > 0 ? "+" : "", CF.Pct(taken)));
            }
            return string.Join(", ", parts);
        }

        public static string ChanceText(double c)
        {
            if (c >= 10) return ((long)Math.Floor(c + 0.5)) + "%";
            if (c >= 1) return c.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture) + "%";
            return c.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture) + "%";
        }

        public static string RewardText(object r)
        {
            var p = new List<string>();
            if (CF.N(r, "gold") > 0) p.Add(CF.Short(CF.N(r, "gold")) + " gold");
            double chaos = CF.N(r, "chaos"), divine = CF.N(r, "divine");
            if (chaos > 0) p.Add((long)chaos + (chaos > 1 ? Loc.T(" Orbs of Upheaval") : Loc.T(" Orb of Upheaval")));
            if (divine > 0) p.Add((long)divine + (divine > 1 ? Loc.T(" Orbs of Fate") : Loc.T(" Orb of Fate")));
            if (CF.N(r, "exp") > 0) p.Add(CF.Short(CF.N(r, "exp")) + " exp");
            if (CF.N(r, "points") > 0) p.Add((long)CF.N(r, "points") + " points");
            return string.Join(", ", p);
        }

        public static string RewardShort(object r)
        {
            var p = new List<string>();
            if (CF.N(r, "gold") > 0) p.Add(CF.Short(CF.N(r, "gold")) + " gold");
            if (CF.N(r, "chaos") > 0) p.Add((long)CF.N(r, "chaos") + " Upheaval");
            if (CF.N(r, "divine") > 0) p.Add((long)CF.N(r, "divine") + " Fate");
            if (CF.N(r, "exp") > 0) p.Add(CF.Short(CF.N(r, "exp")) + " exp");
            if (CF.N(r, "points") > 0) p.Add((long)CF.N(r, "points") + " points");
            return string.Join(", ", p);
        }

        public static string Plural(string name, int count)
        {
            if (count == 1) return name;
            string l = name.ToLowerInvariant();
            if (l.EndsWith("s")) return name;
            if (l.Length >= 2 && l.EndsWith("y") && "aeiou".IndexOf(l[l.Length - 2]) < 0) return name.Substring(0, name.Length - 1) + "ies";
            if (l.EndsWith("x") || l.EndsWith("ch") || l.EndsWith("sh")) return name + "es";
            if (l.EndsWith("man")) return name.Substring(0, name.Length - 3) + "men";
            return name + "s";
        }

        public static string TaskText(object t)
        {
            int n = CF.I(t, "required");
            if (CF.T(t, "kind") == "family") return Loc.T("Kill {0} {1} of level {2}-{3}.", n, CF.T(t, "label"), CF.I(t, "lo"), CF.I(t, "hi"));
            return Loc.T("Kill {0} {1}.", n, Plural(CF.T(t, "label"), n));
        }

        /// <summary>The tracker line: text, percent, done.</summary>
        public static string TrackerLine(object row, out int pct, out bool done)
        {
            double p = CF.N(row, "p"), r = Math.Max(1, CF.N(row, "r"));
            pct = (int)Math.Floor(Math.Min(p, r) * 100 / r);
            done = p >= r;
            return string.Format("{0} {1}/{2}", CF.T(row, "label", "?"), (long)p, (long)r);
        }

        public static string LimitsText(object t) => Loc.T("Active {0} / {1}   Today {2} / {3}   This week {4} / {5}", CF.I(t, "active"), CF.I(t, "maxActive"), CF.I(t, "doneDay"), CF.I(t, "dailyLimit"), CF.I(t, "doneWeek"), CF.I(t, "weeklyLimit"));

        /// <summary>Why a task cannot be accepted, or null.</summary>
        public static string AcceptBlock(object t)
        {
            int active = CF.I(t, "active");
            if (active >= CF.I(t, "maxActive")) return Loc.T("You hold {0} kill tasks: the most at once.", active);
            if (CF.I(t, "doneDay") + active >= CF.I(t, "dailyLimit")) return Loc.T("At most {0} kill tasks a day (completed and held).", CF.I(t, "dailyLimit"));
            if (CF.I(t, "doneWeek") + active >= CF.I(t, "weeklyLimit")) return Loc.T("At most {0} kill tasks a week (completed and held).", CF.I(t, "weeklyLimit"));
            return null;
        }

        /// <summary>Seconds left of the board timer now.</summary>
        public double NextIn(double nowMs) => Math.Max(0, CF.N(Board, "nextIn") - (nowMs - BoardAt) / 1000.0);
    }
}
