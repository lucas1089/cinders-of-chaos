// Crafting tables (client game_craftingtable, extended opcode 91, server crafting tables) and the seven crafting skills (client game_craftskills).
//   client -> server  {action, data}: fetch {category, page} | craft {category, craftId} | tip {category, craftId}
//   server -> client  fetch {category, totalPages, page, crafts [{index, name, id, clientId, level, cost, count, storage, playerStorage, storageText, materials [{id, clientId, count, player, name}],
//                     bonus {kind gear|stack, level, odds [{rarity, name, pct, extra}]}}]}
//                     chunkedFetch {chunkData {msgID, index, count, payload}} (a big fetch in pieces; the joined text is a whole message again)
//                     show {category} (a table was used) | money N | craft {success} (accepted) | message {kind ok|.., text} | tip {category, craftId, tip}
// Craft skills: the 0xA1 skills packet carries seven more skills after fishing (u16 level, u16 base, u8 percent): crafting, woodcutting, mining, herbalist, armorsmith, weaponsmith, jewelsmith.
using System;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core
{
    public sealed class CraftMaterial { public int Id, ClientId, Need, Have; public string Name; }

    public sealed class CraftOdd { public int Rarity, Extra; public string Name = ""; public double Pct; }

    public sealed class CraftRecipe
    {
        public string Category = "", Name = "", LockText = "";
        public int Index, Id, ClientId, Level, Count = 1;
        public double Cost;
        public bool Locked;
        public string BonusKind = "";
        public int BonusLevel;
        public List<CraftOdd> Odds = new List<CraftOdd>();
        public List<CraftMaterial> Materials = new List<CraftMaterial>();
    }

    public sealed class CraftCategory { public string Key = "", Name = ""; public int Skill; }

    public sealed class CraftCheck
    {
        public bool Ok = true, RecipeOk;
        public List<string> Reasons = new List<string>();
        public List<bool> Mats = new List<bool>();
    }

    public sealed class CraftContext { public double? Money; public int? Skill; public string AtTable; public bool Near = true; }

    public sealed class CraftJob { public CraftRecipe Recipe; public double StartedAt = -1, SentAt, LastStart = -1; public int Left, Done; }

    public sealed class CraftTableState : CollectModel
    {
        public const byte OpcodeId = 91;
        public const int PageSize = 10, MaxRepeat = 50, TableRange = 1, CraftMs = 860, CooldownMs = 1000, TableSeconds = 290;
        public const string Good = "#8fd16a", Bad = "#e07060", Warn = "#e0a050", Dim = "#8c8070", TextColor = "#d6c9ae";

        public static readonly CraftCategory[] Categories =
        {
            new CraftCategory { Key = "herbalist", Name = "Herbalist", Skill = 10 }, new CraftCategory { Key = "woodcutting", Name = "Woodcutting", Skill = 8 },
            new CraftCategory { Key = "mining", Name = "Mining", Skill = 9 }, new CraftCategory { Key = "generalcrafting", Name = "General Crafting", Skill = 7 },
            new CraftCategory { Key = "armorsmith", Name = "Armorsmith", Skill = 11 }, new CraftCategory { Key = "weaponsmith", Name = "Weaponsmith", Skill = 12 },
            new CraftCategory { Key = "jewelsmith", Name = "Jewelsmith", Skill = 13 },
        };
        public static readonly string[] SkillNames = { "Crafting", "Woodcutting", "Mining", "Herbalist", "Armorsmith", "Weaponsmith", "Jewelsmith" };

        sealed class Cat { public readonly Dictionary<int, CraftRecipe> Recipes = new Dictionary<int, CraftRecipe>(); public readonly HashSet<int> Pages = new HashSet<int>(); public int? TotalPages; }
        sealed class Chunk { public int Count, Have; public readonly Dictionary<int, string> Parts = new Dictionary<int, string>(); }

        readonly Dictionary<string, Cat> cats = new Dictionary<string, Cat>();
        readonly Dictionary<string, Chunk> chunks = new Dictionary<string, Chunk>();
        readonly Dictionary<string, Dictionary<int, double>> asked = new Dictionary<string, Dictionary<int, double>>();
        readonly Dictionary<string, object> tips = new Dictionary<string, object>();
        public readonly Dictionary<string, int> Selected = new Dictionary<string, int>();
        public string Current = "herbalist", Mode = "all", Search = "", StatusText = "", StatusColor = TextColor, AtTable;
        public double? Money;
        public double TableAt;
        public Pos? TablePos;
        public bool Visible;
        public int Qty = 1;
        public CraftJob Craft;
        public double ProgressPct = -1;
        public double NextSendAt = -1, TimeoutAt = -1;
        /// <summary>The player's position (the session sets it), for the "stand next to the table" rule.</summary>
        public Func<Pos?> PlayerPos = () => null;
        /// <summary>A crafting skill level 0..6, or null when unknown.</summary>
        public Func<int, int?> SkillLevel = i => null;

        public CraftTableState(ExtOpcodes e) : base(e, OpcodeId) { }

        // ---------------------------------------------------------------------------------------------- the wire
        protected override void HandleMessage(ExtMessage m)
        {
            string a = m.Action;
            object d = m.Data;
            if (a == "chunkedFetch" && CF.G(m.Root, "chunkData") is Dictionary<string, object> cd)
            {
                string text = AddChunk(cd);
                if (text == null) return;
                if (!(Json.TryParse(text) is Dictionary<string, object> whole)) return;
                a = CF.T(whole, "action"); d = CF.G(whole, "data");
            }
            Handle(a, d);
        }

        public override void Handle(string a, object d)
        {
            if (a == "fetch" && d is Dictionary<string, object>) OnFetch(d);
            else if (a == "show" && d is Dictionary<string, object> && Category(CF.T(d, "category")) != null) OnShow(CF.T(d, "category"));
            else if (a == "money" && d is double money) Money = money;
            else if (a == "craft" && d is Dictionary<string, object>) OnAccepted();
            else if (a == "message" && d is Dictionary<string, object>) OnMessage(CF.T(d, "kind") == "ok", CF.T(d, "text"));
            else if (a == "tip" && d is Dictionary<string, object>) tips[TipKey(CF.T(d, "category"), CF.I(d, "craftId"))] = CF.G(d, "tip") as Dictionary<string, object> ?? (object)false;
        }

        public string AddChunk(Dictionary<string, object> cd)
        {
            if (!(cd.ContainsKey("payload") && cd["payload"] is string payload)) return null;
            string id = CF.Str(CF.G(cd, "msgID"));
            int i = (int)Math.Floor(CF.N(cd, "index")), n = (int)Math.Floor(CF.N(cd, "count"));
            if (i < 1 || n < 1 || i > n || n > 10000) return null;
            if (!chunks.TryGetValue(id, out var e) || e.Count != n) chunks[id] = e = new Chunk { Count = n };
            if (!e.Parts.ContainsKey(i)) e.Have++;
            e.Parts[i] = payload;
            if (e.Have < n) return null;
            chunks.Remove(id);
            var sb = new System.Text.StringBuilder();
            for (int k = 1; k <= n; k++) sb.Append(e.Parts[k]);
            return ExtOpcodes.FromWire(sb.ToString()) is string s ? s : null;
        }

        void Req(string action, Dictionary<string, object> data) { Send(action, data); }

        // ---------------------------------------------------------------------------------------------- categories and recipes
        public static CraftCategory Category(string key) => Categories.FirstOrDefault(c => c.Key == key);
        public static int? SkillIndex(string key) { var c = Category(key); return c == null ? (int?)null : c.Skill - 7; }
        public static string FmtNum(double n) => n < 0 ? "-" + CF.Group(-n) : CF.Group(n);
        public static string GoldText(double n) => FmtNum(n) + " gp";
        public static int PageOf(int index) => (Math.Max(1, index) - 1) / PageSize + 1;
        public static string TipKey(string category, int index) => "craftingtable:" + category + ":" + index;

        Cat CatState(string key) { if (!cats.TryGetValue(key, out var c)) cats[key] = c = new Cat(); return c; }

        public static CraftRecipe ToRecipe(Dictionary<string, object> raw, string category)
        {
            if (CF.N(raw, "index") < 1) return null;
            var r = new CraftRecipe
            {
                Category = category, Index = (int)Math.Floor(CF.N(raw, "index")), Name = CF.T(raw, "name", "?"), Id = CF.I(raw, "id"), ClientId = CF.I(raw, "clientId"), Level = CF.I(raw, "level"),
                Cost = CF.N(raw, "cost"), Count = Math.Max(1, CF.I(raw, "count")),
            };
            r.Locked = CF.N(raw, "storage") > 0 && CF.N(raw, "playerStorage") != 1;
            r.LockText = CF.T(raw, "storageText");
            var b = CF.G(raw, "bonus") as Dictionary<string, object>;
            if (b != null && CF.G(b, "odds") is List<object>)
            {
                string kind = CF.T(b, "kind");
                if (kind == "gear")
                {
                    r.BonusKind = "gear"; r.BonusLevel = CF.I(b, "level");
                    foreach (var o in CF.Rows(CF.G(b, "odds"))) if (CF.N(o, "pct") > 0) r.Odds.Add(new CraftOdd { Rarity = CF.I(o, "rarity"), Name = CF.T(o, "name", "Rarity " + CF.I(o, "rarity")), Pct = CF.N(o, "pct") });
                    r.Odds = r.Odds.OrderBy(o => o.Rarity).ToList();
                }
                else if (kind == "stack")
                {
                    r.BonusKind = "stack";
                    foreach (var o in CF.Rows(CF.G(b, "odds"))) if (CF.N(o, "pct") > 0 && CF.N(o, "extra") > 0) r.Odds.Add(new CraftOdd { Extra = (int)Math.Floor(CF.N(o, "extra")), Pct = CF.N(o, "pct") });
                    r.Odds = r.Odds.OrderBy(o => o.Extra).ToList();
                }
            }
            foreach (var m in CF.Rows(CF.G(raw, "materials")))
                r.Materials.Add(new CraftMaterial { Id = CF.I(m, "id"), ClientId = CF.I(m, "clientId"), Need = Math.Max(1, CF.I(m, "count")), Have = CF.I(m, "player"), Name = CF.G(m, "name") is string n && n.Length > 0 ? n : null });
            return r;
        }

        void OnFetch(object data)
        {
            string key = CF.T(data, "category");
            if (Category(key) == null) return;
            var c = CatState(key);
            int total = (int)Math.Floor(CF.N(data, "totalPages"));
            if (total >= 0) c.TotalPages = total;
            int page = (int)Math.Floor(CF.N(data, "page"));
            if (page >= 1) c.Pages.Add(page);
            foreach (var raw in CF.Rows(CF.G(data, "crafts"))) { var r = ToRecipe(raw, key); if (r != null) c.Recipes[r.Index] = r; }
            if (key == Current || key == AtTable) FetchMissing(key, Clock());
        }

        public List<int> MissingPages(string key)
        {
            var c = CatState(key);
            if (!c.TotalPages.HasValue) return new List<int> { 1 };
            var o = new List<int>();
            for (int p = 1; p <= c.TotalPages.Value; p++) if (!c.Pages.Contains(p)) o.Add(p);
            return o;
        }

        public bool Loaded(string key) => cats.TryGetValue(key, out var c) && c.TotalPages.HasValue && MissingPages(key).Count == 0;

        public void MarkStale(string key) { var c = CatState(key); c.Pages.Clear(); asked.Remove(key); }

        /// <summary>Asks the pages that are missing (each at most every 3 s).</summary>
        public void FetchMissing(string key, double nowMs)
        {
            if (!asked.TryGetValue(key, out var a)) asked[key] = a = new Dictionary<int, double>();
            foreach (int p in MissingPages(key))
                if (!a.TryGetValue(p, out var t) || nowMs - t > 3000) { a[p] = nowMs; Req("fetch", D("category", key, "page", (double)p)); }
        }

        public List<CraftRecipe> Recipes(string key) => cats.TryGetValue(key, out var c) ? c.Recipes.Values.OrderBy(r => r.Index).ToList() : new List<CraftRecipe>();

        public CraftRecipe SelectedRecipe() => cats.TryGetValue(Current, out var c) && Selected.TryGetValue(Current, out int i) && c.Recipes.TryGetValue(i, out var r) ? r : null;

        public void SelectTab(string key, double nowMs)
        {
            if (Category(key) == null) return;
            if (key != Current && Craft == null) StatusText = "";
            Current = key;
            if (!Loaded(key)) FetchMissing(key, nowMs);
        }

        public void SelectRecipe(int index) { if (cats.TryGetValue(Current, out var c) && c.Recipes.ContainsKey(index)) { Selected[Current] = index; Qty = 1; if (Craft == null) StatusText = ""; } }

        public void OnShow(string key)
        {
            AtTable = key; TableAt = Clock(); TablePos = PlayerPos();
            foreach (string k in cats.Keys.ToList()) MarkStale(k);
            Visible = true;
            SelectTab(key, Clock());
        }

        public void Refresh() { foreach (string k in cats.Keys.ToList()) MarkStale(k); FetchMissing(Current, Clock()); }

        public void Hide() { Visible = false; if (Craft != null) StopCraft(null, null); }

        public void Clear()
        {
            cats.Clear(); chunks.Clear(); asked.Clear(); tips.Clear(); Selected.Clear(); Money = null; AtTable = null; TablePos = null; Visible = false; Craft = null; ProgressPct = -1; StatusText = "";
        }

        // ---------------------------------------------------------------------------------------------- the rules of a craft
        public bool IsNear()
        {
            var p = PlayerPos(); var t = TablePos;
            if (!t.HasValue || !p.HasValue) return false;
            return p.Value.Z == t.Value.Z && Math.Abs(p.Value.X - t.Value.X) <= TableRange && Math.Abs(p.Value.Y - t.Value.Y) <= TableRange;
        }

        public string TableCategory(double nowMs) => AtTable != null && nowMs - TableAt <= TableSeconds * 1000 ? AtTable : null;

        public CraftContext Context(string key, double nowMs)
        {
            int? si = SkillIndex(key);
            return new CraftContext { Money = Money, Skill = si.HasValue ? SkillLevel(si.Value) : null, AtTable = TableCategory(nowMs), Near = IsNear() };
        }

        public static CraftCheck Check(CraftRecipe r, CraftContext ctx)
        {
            var o = new CraftCheck();
            if (r.Locked) o.Reasons.Add("locked");
            if (ctx.Skill.HasValue && ctx.Skill.Value < r.Level) o.Reasons.Add("skill");
            if (ctx.Money.HasValue && ctx.Money.Value < r.Cost) o.Reasons.Add("gold");
            bool shortOf = false;
            foreach (var m in r.Materials) { bool enough = m.Have >= m.Need; o.Mats.Add(enough); if (!enough) shortOf = true; }
            if (shortOf) o.Reasons.Add("materials");
            o.RecipeOk = o.Reasons.Count == 0;
            if (ctx.AtTable != r.Category) o.Reasons.Add("table"); else if (!ctx.Near) o.Reasons.Add("away");
            o.Ok = o.Reasons.Count == 0;
            return o;
        }

        public static int MaxCraftable(CraftRecipe r, double? money)
        {
            double n = double.PositiveInfinity;
            foreach (var m in r.Materials) n = Math.Min(n, Math.Floor((double)m.Have / m.Need));
            if (r.Cost > 0 && money.HasValue) n = Math.Min(n, Math.Floor(money.Value / r.Cost));
            if (double.IsPositiveInfinity(n)) n = MaxRepeat;
            return (int)Math.Max(0, Math.Min(n, MaxRepeat));
        }

        public static string ReasonText(string key, CraftRecipe r, CraftContext ctx)
        {
            var cat = Category(r.Category);
            switch (key)
            {
                case "locked": return Loc.T("Recipe not unlocked yet.{0}", r.LockText.Length > 0 ? " " + r.LockText : "");
                case "skill": return Loc.T("Needs {0} {1} (yours {2}).", Loc.T(SkillNames[(cat != null ? cat.Skill : 7) - 7]), r.Level, ctx.Skill ?? 0);
                case "gold": return Loc.T("Needs {0} (you carry {1}).", GoldText(r.Cost), GoldText(ctx.Money ?? 0));
                case "materials": return Loc.T("Materials missing.");
                case "table": return Loc.T("Use a {0} table to craft this.", cat != null ? cat.Name : "crafting");
                case "away": return Loc.T("Go back to the crafting table.");
            }
            return "";
        }

        public static string BlockText(CraftCheck check, CraftRecipe r, CraftContext ctx) => check.Reasons.Count > 0 ? ReasonText(check.Reasons[0], r, ctx) : "";

        public static bool Matches(CraftRecipe r, string text)
        {
            text = (text ?? "").Trim().ToLowerInvariant();
            if (text.Length == 0) return true;
            if (r.Name.ToLowerInvariant().Contains(text)) return true;
            return r.Materials.Any(m => m.Name != null && m.Name.ToLowerInvariant().Contains(text));
        }

        public static List<CraftRecipe> Filter(IEnumerable<CraftRecipe> list, string search, string mode, CraftContext ctx)
            => list.Where(r => Matches(r, search) && (mode != "craftable" || Check(r, ctx).RecipeOk)).ToList();

        public static string RowSub(CraftRecipe r) => (r.Count > 1 ? string.Format("x{0}  -  ", r.Count) : "") + string.Format("Lv {0}  -  {1}", r.Level, GoldText(r.Cost));
        public static string HaveNeed(CraftMaterial m) => FmtNum(m.Have) + "/" + FmtNum(m.Need);
        public static string MaterialName(CraftMaterial m, string fallback = null) => m.Name ?? fallback ?? "item " + m.Id;

        public static string PctText(double p)
        {
            string s = p.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture).TrimEnd('0');
            if (s.EndsWith(".")) s = s.Substring(0, s.Length - 1);
            return s + "%";
        }

        public static string BonusText(CraftRecipe r)
        {
            if (r.Odds.Count == 0) return "";
            if (r.BonusKind == "gear") return Loc.T("Rarity at item level {0}: {1}", r.BonusLevel, string.Join(" / ", r.Odds.Select(o => o.Name + " " + PctText(o.Pct))));
            return Loc.T("Bonus yield: {0}", string.Join(" / ", r.Odds.Select(o => string.Format("+{0} at {1}", o.Extra, PctText(o.Pct)))));
        }

        public static int Progress(double startMs, double nowMs) => startMs < 0 ? 0 : (int)Math.Max(0, Math.Min(100, Math.Floor((nowMs - startMs) * 100 / CraftMs)));
        public static double RepeatDelay(double lastStartMs, double nowMs) => lastStartMs < 0 ? 0 : Math.Max(0, lastStartMs + CooldownMs + 150 - nowMs);
        public static int ClampQty(int q, int max) => Math.Max(1, Math.Min(q, Math.Min(Math.Max(1, max), MaxRepeat)));

        public static string PlainTip(CraftRecipe r)
        {
            var cat = Category(r.Category);
            string b = BonusText(r);
            return r.Name + (r.Count > 1 ? " x" + r.Count : "") + "\n" + Loc.T("{0} level {1}, {2}", Loc.T(SkillNames[(cat != null ? cat.Skill : 7) - 7]), r.Level, GoldText(r.Cost)) + "\n" + (b.Length > 0 ? b : Loc.T("A crafted item may roll a rarity."));
        }

        public bool NeedsTip(string category, int index) => !tips.ContainsKey(TipKey(category, index));
        public object TipOf(string category, int index) => tips.TryGetValue(TipKey(category, index), out var t) ? t : null;
        public void AskTip(string category, int index) { tips[TipKey(category, index)] = null; Req("tip", D("category", category, "craftId", (double)index)); }

        public void ChangeQty(int delta, double nowMs)
        {
            var r = SelectedRecipe();
            Qty = ClampQty(Qty + delta, r == null ? 1 : MaxCraftable(r, Money));
        }

        // ---------------------------------------------------------------------------------------------- crafting
        public bool DoCraft(double nowMs)
        {
            var r = SelectedRecipe();
            if (r == null || Craft != null) return false;
            var ctx = Context(r.Category, nowMs);
            var check = Check(r, ctx);
            if (!check.Ok) { StatusText = BlockText(check, r, ctx); StatusColor = Warn; return false; }
            Craft = new CraftJob { Recipe = r, Left = Qty };
            StatusText = Loc.T("Crafting {0}...", r.Name); StatusColor = TextColor;
            SendCraft(nowMs);
            return true;
        }

        void SendCraft(double nowMs)
        {
            if (Craft == null) return;
            Craft.SentAt = nowMs; Craft.StartedAt = -1;
            Req("craft", D("category", Craft.Recipe.Category, "craftId", (double)Craft.Recipe.Index));
            ProgressPct = 0; TimeoutAt = nowMs + 5000; NextSendAt = -1;
        }

        void OnAccepted()
        {
            if (Craft == null) return;
            Craft.StartedAt = Clock(); Craft.LastStart = Craft.SentAt;
        }

        /// <summary>Called every frame while a craft runs: progress, the 5 s timeout, the next repeat.</summary>
        public void Tick(double nowMs)
        {
            if (Craft == null) return;
            if (Craft.StartedAt >= 0) ProgressPct = Progress(Craft.StartedAt, nowMs);
            if (TimeoutAt >= 0 && nowMs >= TimeoutAt) { StopCraft(Loc.T("No answer from the server."), Bad); return; }
            if (NextSendAt >= 0 && nowMs >= NextSendAt)
            {
                NextSendAt = -1;
                var again = cats.TryGetValue(Craft.Recipe.Category, out var c) && c.Recipes.TryGetValue(Craft.Recipe.Index, out var rr) ? rr : Craft.Recipe;
                var ctx = Context(again.Category, nowMs);
                var check = Check(again, ctx);
                if (!check.Ok) { StopCraft(Loc.T("Stopped after {0}: {1}", Craft.Done, BlockText(check, again, ctx)), Warn); return; }
                Craft.Recipe = again;
                SendCraft(nowMs);
            }
        }

        void OnMessage(bool ok, string text)
        {
            var r = Craft != null ? Craft.Recipe : SelectedRecipe();
            if (r != null && !ok)
            {
                int p = PageOf(r.Index);
                if (!asked.TryGetValue(r.Category, out var a)) asked[r.Category] = a = new Dictionary<int, double>();
                a[p] = Clock();
                Req("fetch", D("category", r.Category, "page", (double)p));
            }
            if (Craft == null) { StatusText = text; StatusColor = ok ? Good : Bad; return; }
            if (!ok)
            {
                int done = Craft.Done;
                StopCraft(done > 0 ? Loc.T("{0} ({1} crafted before)", text, done) : text, Bad);
                return;
            }
            Craft.Done++; Craft.Left--;
            ProgressPct = 100;
            if (Craft.Left <= 0)
            {
                int done = Craft.Done;
                StopCraft(done > 1 ? Loc.T("{0} ({1} crafted)", text, done) : text, Good);
                return;
            }
            StatusText = Loc.T("{0} ({1} crafted, {2} to go)", text, Craft.Done, Craft.Left); StatusColor = Good;
            TimeoutAt = -1;
            NextSendAt = Clock() + RepeatDelay(Craft.LastStart, Clock());
        }

        void StopCraft(string text, string color)
        {
            Craft = null; ProgressPct = -1; TimeoutAt = -1; NextSendAt = -1;
            if (text != null) { StatusText = text; StatusColor = color ?? TextColor; }
        }

        public string HintText(double nowMs)
        {
            string at = TableCategory(nowMs);
            if (at != null && IsNear()) return Loc.T("You stand at the {0} table. Materials and gold are counted in your backpack; a crafted item may roll a rarity.", Category(at).Name);
            if (at != null) return Loc.T("You left the {0} table: go back to it to craft.", Category(at).Name);
            return Loc.T("Use a crafting table to craft. Each table crafts the recipes of its tab.");
        }
    }

    /// <summary>The seven crafting skills (game_craftskills): level, base, percent, with the row text of the main client.</summary>
    public static class CraftSkills
    {
        public static string Tooltip(int index, SkillValue v)
        {
            string name = CraftTableState.SkillNames[index];
            return v.Level > v.Base
                ? Loc.T("{0}: {1} (base {2})\n{3}% to the next level", Loc.T(name), v.Level, v.Base, v.Percent)
                : Loc.T("{0}: {1}\n{2}% to the next level", Loc.T(name), v.Level, v.Percent);
        }

        /// <summary>The short level text (15.3k) the main client's formatShortNumber gives.</summary>
        public static string ShortLevel(int level) => CF.Short(level);
    }
}
