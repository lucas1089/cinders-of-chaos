// Phase 8, track B: game_market, the Modifiers filter of Browse and of a buy order (marketview.lua: V.modCatalog, V.modChoices, V.tierOptions, V.modRequest, V.modCount,
// V.matchedMods, V.orderFilterText). Pure logic, no UnityEngine. The server reads the request in market_core.lua C.modFilter. Tests: Core.Tests/Phase8BTests.cs.
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    public sealed class ModEntry
    {
        public string Key = "", Name = "", Group = "", Side = "";
        public List<string> Tiers = new List<string>();
    }

    /// <summary>Every modifier and legendary power of the Codex (a power is stored as the modifier chaos_mod_{power}), by group then name.</summary>
    public sealed class ModCatalog
    {
        public readonly List<ModEntry> List = new List<ModEntry>();
        public readonly Dictionary<string, ModEntry> ByKey = new Dictionary<string, ModEntry>();
        public static readonly string[][] Groups = { new[] { "prefix", "Prefixes" }, new[] { "suffix", "Suffixes" }, new[] { "power", "Legendary powers" } };

        /// <summary>One choice of a modifier combo: the shown text and the key ("" for a heading or no modifier).</summary>
        public struct Choice { public string Text, Key; }

        public static ModCatalog Build(CodexData codex)
        {
            var cat = new ModCatalog();
            if (codex == null) return cat;
            foreach (var tab in codex.Tabs)
                foreach (var e in tab.Entries)
                {
                    string key = null, group = null;
                    if (e.Id.StartsWith("mod:", StringComparison.Ordinal)) key = e.Id.Substring(4);
                    else if (e.Id.StartsWith("power:", StringComparison.Ordinal)) { key = "chaos_mod_" + e.Id.Substring(6); group = "power"; }
                    if (key == null || key.Length == 0 || cat.ByKey.ContainsKey(key)) continue;
                    string side = e.F.TryGetValue("side", out object s) && s as string == "prefix" ? "prefix" : "suffix";
                    var m = new ModEntry { Key = key, Name = e.Name.Length > 0 ? e.Name : key, Side = side, Group = group ?? side };
                    if (e.Tv != null) m.Tiers.AddRange(e.Tv);
                    cat.ByKey[key] = m; cat.List.Add(m);
                }
            // two modifiers of one name (a flat and a percent one): the best tier's value tells them apart
            var count = new Dictionary<string, int>();
            foreach (var m in cat.List) { count.TryGetValue(m.Name, out int n); count[m.Name] = n + 1; }
            foreach (var m in cat.List) if (count[m.Name] > 1) m.Name += " (" + (m.Tiers.Count > 0 ? m.Tiers[m.Tiers.Count - 1] : m.Key) + ")";
            int Order(string g) => g == "prefix" ? 1 : g == "suffix" ? 2 : 3;
            cat.List.Sort((a, b) => a.Group != b.Group ? Order(a.Group).CompareTo(Order(b.Group)) : string.CompareOrdinal(a.Name, b.Name));
            return cat;
        }

        public string NameOf(string key) => key != null && ByKey.TryGetValue(key, out var m) ? m.Name : key ?? "";

        /// <summary>The choices of a modifier combo for what was typed: a heading per group, every word typed must be in the name. `first` is the key of the first match ("" none).</summary>
        public List<Choice> Choices(string query, out string first)
        {
            var words = new List<string>();
            foreach (var w in (query ?? "").ToLowerInvariant().Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries)) words.Add(w);
            var o = new List<Choice> { new Choice { Text = words.Count > 0 ? Loc.T("Matching modifiers...") : Loc.T("Choose a modifier..."), Key = "" } };
            first = "";
            foreach (var g in Groups)
            {
                bool head = false;
                foreach (var m in List)
                {
                    if (m.Group != g[0]) continue;
                    string name = m.Name.ToLowerInvariant();
                    bool hit = true;
                    foreach (var w in words) if (name.IndexOf(w, StringComparison.Ordinal) < 0) { hit = false; break; }
                    if (!hit) continue;
                    if (!head) { o.Add(new Choice { Text = "-- " + Loc.T(g[1]) + " --", Key = "" }); head = true; }
                    o.Add(new Choice { Text = m.Name, Key = m.Key });
                    if (first.Length == 0) first = m.Key;
                }
            }
            if (words.Count > 0 && first.Length == 0) o[0] = new Choice { Text = Loc.T("No modifier matches"), Key = "" };
            return o;
        }
    }

    /// <summary>One row of the Modifiers section: the typed search, the chosen modifier key, the minimum value (text) and the minimum tier (0 any, 1 to 8).</summary>
    public sealed class ModRow { public string Search = "", Key = "", Min = ""; public int Tier; }

    /// <summary>The Modifiers section of the Browse tab (and what a buy order takes from it).</summary>
    public sealed class ModForm
    {
        public readonly List<ModRow> Rows = new List<ModRow>();
        public bool Count;   // mode "at least N"
        public string Need = "", Sockets = "", Quality = "";
        public bool FreeP, FreeS, Power, Bound;
    }

    public static class MarketMods
    {
        /// <summary>The server's limits (market_config.lua modFilter; the meta message sends them).</summary>
        public struct Limits { public int MaxRows, MaxTier, MaxValue, MaxSockets, MaxQuality; }
        public static readonly Limits Default = new Limits { MaxRows = 6, MaxTier = 8, MaxValue = 1000000, MaxSockets = 8, MaxQuality = 30 };

        public static Limits LimitsOf(object meta)
        {
            var l = Default;
            object m = Json.Get(meta, "modFilter");
            if (m == null) return l;
            if (SFmt.Has(m, "maxRows")) l.MaxRows = Math.Max(1, Json.Int(m, "maxRows"));
            if (SFmt.Has(m, "maxTier")) l.MaxTier = Math.Max(1, Json.Int(m, "maxTier"));
            if (SFmt.Has(m, "maxValue")) l.MaxValue = Math.Max(1, Json.Int(m, "maxValue"));
            if (SFmt.Has(m, "maxSockets")) l.MaxSockets = Math.Max(1, Json.Int(m, "maxSockets"));
            if (SFmt.Has(m, "maxQuality")) l.MaxQuality = Math.Max(1, Json.Int(m, "maxQuality"));
            return l;
        }

        /// <summary>"Any tier", then T1+ to T7+ and T8 (T1 is the lowest, T8 the best).</summary>
        public static List<string> TierOptions(int maxTier)
        {
            var o = new List<string> { Loc.T("Any tier") };
            for (int t = 1; t <= maxTier; t++) o.Add("T" + t + (t < maxTier ? "+" : ""));
            return o;
        }

        /// <summary>A whole number from a box: "" is 0, null when it does not read.</summary>
        static long? Whole(string text)
        {
            text = (text ?? "").Replace(" ", "");
            if (text.Length == 0) return 0;
            foreach (char c in text) if (c < '0' || c > '9') return null;
            return long.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out long v) ? v : long.MaxValue;
        }

        /// <summary>The Modifiers section as the filter fields the server reads (mods, need, sockets, quality, freeP, freeS, power, bound); null and why when it is not valid.</summary>
        public static Dictionary<string, object> Request(ModForm form, Limits lim, out string why)
        {
            why = "";
            var mods = new List<object>();
            var seen = new HashSet<string>();
            int i = 0;
            foreach (var r in form.Rows)
            {
                i++;
                if (string.IsNullOrEmpty(r.Key)) continue;
                if (!seen.Add(r.Key)) { why = Loc.T("Each modifier only once per search."); return null; }
                long? min = Whole(r.Min);
                if (min == null) { why = Loc.T("Row {0}: the minimum value is a whole number.", i); return null; }
                long m = Math.Min(min.Value, lim.MaxValue);
                int tier = Math.Max(0, Math.Min(r.Tier, lim.MaxTier));
                var row = new Dictionary<string, object> { { "k", r.Key } };
                if (m > 0) row["min"] = (double)m;
                if (tier > 0) row["t"] = (double)tier;
                mods.Add(row);
            }
            if (mods.Count > lim.MaxRows) { why = Loc.T("At most {0} modifiers per search.", lim.MaxRows); return null; }
            var o = new Dictionary<string, object> { { "mods", mods } };
            if (form.Count && mods.Count > 0)
            {
                long? need = Whole(form.Need);
                if (need == null || need < 1 || need > mods.Count) { why = Loc.T("\"At least\" needs a number from 1 to {0} (the modifiers chosen).", mods.Count); return null; }
                if (need < mods.Count) o["need"] = (double)need.Value;
            }
            long? sockets = Whole(form.Sockets), quality = Whole(form.Quality);
            if (sockets == null) { why = Loc.T("Sockets: a whole number."); return null; }
            if (quality == null) { why = Loc.T("Quality: a whole number."); return null; }
            if (sockets > 0) o["sockets"] = (double)Math.Min(sockets.Value, lim.MaxSockets);
            if (quality > 0) o["quality"] = (double)Math.Min(quality.Value, lim.MaxQuality);
            if (form.FreeP) o["freeP"] = true;
            if (form.FreeS) o["freeS"] = true;
            if (form.Power) o["power"] = true;
            if (form.Bound) o["bound"] = true;
            return o;
        }

        /// <summary>How many conditions a request holds (the toggle button shows it).</summary>
        public static int Count(Dictionary<string, object> req)
        {
            if (req == null) return 0;
            int n = req.TryGetValue("mods", out object m) && m is List<object> l ? l.Count : 0;
            foreach (string k in new[] { "sockets", "quality", "freeP", "freeS", "power", "bound" }) if (req.ContainsKey(k)) n++;
            return n;
        }

        /// <summary>The lines of an offer's tooltip that the modifier rows of the search matched, best first ("Matches: Name (T5)").</summary>
        public static List<string> MatchedMods(object tip, object req)
        {
            var o = new List<string>();
            var want = new Dictionary<string, object>();
            foreach (var r in Json.List(req, "mods")) want[Json.Text(r, "k", "").ToLowerInvariant()] = r;
            if (want.Count == 0) return o;
            foreach (var m in Json.List(tip, "mods"))
            {
                if (!want.TryGetValue(Json.Text(m, "k", "").ToLowerInvariant(), out object r)) continue;
                double value = Json.Text(m, "g", "") == "special" && Json.Number(m, "v2") != 0 ? Json.Number(m, "v2") : Json.Number(m, "v");
                double tr = Json.Number(m, "tr");
                if (value >= Json.Number(r, "min") && tr >= Json.Number(r, "t"))
                {
                    string name = Json.Text(m, "t", "");
                    if (name.Length == 0) name = Json.Text(m, "l", "");
                    if (name.Length == 0) name = Json.Text(m, "k", "");
                    o.Add(Loc.T("Matches: ") + name + (tr > 0 ? " (T" + (int)tr + ")" : ""));
                }
            }
            return o;
        }

        /// <summary>The filter of an order in words (rarity, item level, modifiers, sockets ...); "Any" when empty. nameOf gives a modifier's name.</summary>
        public static string FilterText(object f, Func<string, string> nameOf)
        {
            if (f == null || !(f is Dictionary<string, object>)) return Loc.T("Any");
            var parts = new List<string>();
            int rarity = Json.Int(f, "rarity");
            if (rarity > 0) parts.Add((MarketMath.RarityName(rarity) ?? Loc.T("Rarity {0}", rarity)) + "+");
            if (Json.Int(f, "ilvl") > 0) parts.Add(Loc.T("iLvl {0}", Json.Int(f, "ilvl")) + "+");
            var mods = new List<string>();
            foreach (var m in Json.List(f, "mods"))
            {
                string key = Json.Text(m, "k", ""), t = nameOf != null ? nameOf(key) : key;
                if (Json.Int(m, "min") > 0) t += " " + Json.Int(m, "min") + "+";
                if (Json.Int(m, "t") > 0) t += " T" + Json.Int(m, "t") + "+";
                mods.Add(t);
            }
            if (mods.Count > 0)
                parts.Add(SFmt.Has(f, "need") && Json.Int(f, "need") < mods.Count ? Loc.T("{0} of: {1}", Json.Int(f, "need"), string.Join(", ", mods)) : string.Join(", ", mods));
            if (Json.Int(f, "sockets") > 0) parts.Add(Loc.T(Json.Int(f, "sockets") > 1 ? "{0}+ sockets" : "{0}+ socket", Json.Int(f, "sockets")));
            if (Json.Int(f, "quality") > 0) parts.Add(Loc.T("quality {0}%+", Json.Int(f, "quality")));
            if (Json.Truthy(f, "freeP")) parts.Add(Loc.T("free prefix"));
            if (Json.Truthy(f, "freeS")) parts.Add(Loc.T("free suffix"));
            if (Json.Truthy(f, "power")) parts.Add(Loc.T("legendary power"));
            if (Json.Truthy(f, "bound")) parts.Add(Loc.T("bound modifier"));
            return parts.Count == 0 ? Loc.T("Any") : string.Join(" - ", parts);
        }
    }
}
