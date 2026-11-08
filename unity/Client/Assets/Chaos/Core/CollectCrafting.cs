// Crafting bench (client game_crafting, extended opcode 232, server crafting): orbs on a gear item, salvage into shards, shards into orbs, item lock.
//   client -> server  open | clear | select {path, id} | select {pos {x,y,z}, clientId} | apply {orb, path, id, sig, mod?} | gem {op: remove|shatter, socket, path, id, sig}
//                     salvage {path, id, sig} | salvageScope {mode} | salvageScope {bag, maxRarity} | salvageBatch {bag, maxRarity, sig} | combine {key, count} | recycle {key, count}
//                     lock {path, id, on} | lockAt {pos {x,y,z}, cid, on}
//   server -> client  info {orbs [{key, name, clientId, text, keyText?, wsText?}], reasons {code: text}}  (once)  | gemguide {...}
//                     state {open, counts {orbKey: n}, item {path, id, sig, clientId, name, rarity, rarityName, level, maxTier, maxMods, mods [{key, text, short, tier, lo, hi, side,
//                     group, bound, power, implicit}], prefixes [n, max], suffixes [n, max], binds [n, max], quality, qualityCap, locked, unique, ruined, corrupted, kind, waystone,
//                     orbs {orbKey: reason code}, pick {orbKey: [modKey]}, preview {orbKey: text}, sockets {count, max, list [{index, id, clientId, name, text, color, cost}]}, salvage {ok, why, shards, orbChance}},
//                     items [{path, id, clientId, name, rarity, rarityName, unique, key, locked}], history [{time, orb, item, text}],
//                     salvage {mode, installed, shards, shardName, shardSingular, shardClientId, bags [{name, path}], rarityNames, rarityIds, batch {bag, maxRarity, paths, count, shards, orbs, skipped, cap, sig},
//                     recipes [{key, name, clientId, cost, count, back, input, inputName, have}], maxCombine}}
//                     result {ok, text}
using System;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core
{
    public sealed class OrbRow
    {
        public string Key = "", Name = "", Text = "", Why = "", Line = "", Color = "", Preview = "";
        public int ClientId, Count;
        public bool CanUse, IsText;
    }

    public sealed class CraftingState : CollectModel
    {
        public const byte OpcodeId = 232;
        public static readonly string[] RarityColor =
        {
            "#c4cebc", "#5fd35f", "#4a8cff", "#b070ff", "#f6cf72", "#f6cf72", "#f6cf72", "#f6cf72", "#f6cf72", "#7fe6ff", "#7fe6ff", "#7fe6ff", "#7fe6ff", "#7fe6ff", "#7fe6ff",
        };
        public static readonly int[] RarityIdFallback = { 1, 2, 3, 4, 5, 10 };
        public static readonly Dictionary<string, string> GroupColor = new Dictionary<string, string>
        { { "absorb", "#7fa8ff" }, { "skill", "#9fdc7f" }, { "special", "#f6cf72" }, { "element", "#ff8a5a" }, { "chaos", "#ff70c0" }, { "rift", "#c0a0ff" } };
        public const string PowerColor = "#ff9a3c", KeyColor = "#c0a0ff";
        static readonly Dictionary<string, string> SkipText = new Dictionary<string, string>
        { { "locked", "locked" }, { "unique", "unique" }, { "gems", "with gems" }, { "above", "above the rarity" }, { "cap", "over the limit of {0}" }, { "notBackpack", "not in the backpack" } };

        public object Info, State, GemGuide;
        public string Mode = "orbs", SelectedMod, ResultText = "";
        public bool ResultOk = true, Visible;
        public readonly HashSet<string> Expanded = new HashSet<string>();
        public List<Dictionary<string, object>> Orbs = new List<Dictionary<string, object>>();

        public CraftingState(ExtOpcodes e) : base(e, OpcodeId) { }

        public void Toggle() { if (Visible) Visible = false; else Send("open"); }
        public void OpenSalvage() { Send("salvageScope", D("mode", "salvage")); Send("open"); }
        public void Clear() { Send("clear"); }

        public override void Handle(string action, object data)
        {
            switch (action)
            {
                case "info": Info = data; break;
                case "gemguide": GemGuide = data; break;
                case "state": OnState(data); break;
                case "result": ResultText = CF.T(data, "text"); ResultOk = !(CF.G(data, "ok") is bool b) || b; break;
            }
        }

        void OnState(object data)
        {
            var d = data as Dictionary<string, object>;
            if (d == null) return;
            if (!(d.ContainsKey("item") && d["item"] is Dictionary<string, object>)) d["item"] = null;
            var oldItem = Item;
            var newItem = d["item"] as Dictionary<string, object>;
            if (oldItem != null && newItem != null && CF.T(oldItem, "path") != CF.T(newItem, "path")) SelectedMod = null;
            var counts = CF.M(d, "counts");
            Orbs = new List<Dictionary<string, object>>();
            foreach (var o in CF.Rows(CF.G(Info, "orbs")))
            {
                var row = new Dictionary<string, object>(o);
                row["count"] = counts.TryGetValue(CF.T(o, "key"), out var c) ? c : 0.0;
                Orbs.Add(row);
            }
            State = data;
            var sv = Salvage;
            if (CF.B(d, "open") && sv != null && (CF.T(sv, "mode") == "salvage" || CF.T(sv, "mode") == "orbs")) Mode = CF.T(sv, "mode");
            if (SelectedMod != null && newItem != null && ModByKey(newItem, SelectedMod) == null) SelectedMod = null;
            if (newItem == null) SelectedMod = null;
            if (CF.B(d, "open")) { if (!Visible) ResultText = ""; Visible = true; }
        }

        public void ClearAll() { State = null; Visible = false; Mode = "orbs"; SelectedMod = null; ResultText = ""; Expanded.Clear(); }

        public Dictionary<string, object> Item => CF.G(State, "item") as Dictionary<string, object>;
        public Dictionary<string, object> Salvage => CF.G(State, "salvage") as Dictionary<string, object>;
        public List<Dictionary<string, object>> Mods => CF.Rows(CF.G(Item, "mods"));
        public List<Dictionary<string, object>> Items => CF.Rows(CF.G(State, "items"));
        public List<Dictionary<string, object>> History => CF.Rows(CF.G(State, "history"));

        public static Dictionary<string, object> ModByKey(object item, string key)
        {
            if (item == null || key == null) return null;
            return CF.Rows(CF.G(item, "mods")).FirstOrDefault(m => CF.T(m, "key") == key);
        }

        public void SetMode(string m)
        {
            if (m != "orbs" && m != "salvage") return;
            Mode = m;
            Send("salvageScope", D("mode", m));
        }

        public void SelectMod(string key) { SelectedMod = SelectedMod != key ? key : null; }

        /// <summary>A click on a gear item of the picker.</summary>
        public void SelectItem(Dictionary<string, object> it) { ResultText = ""; Send("select", D("path", CF.G(it, "path"), "id", CF.G(it, "id"))); }

        /// <summary>A backpack item dropped on the bench slot: its position and client id.</summary>
        public bool SelectAt(Pos pos, int clientId)
        {
            if (pos.X != 0xFFFF) { ResultText = Loc.T("Only items from your backpack can go on the bench."); ResultOk = false; return false; }
            ResultText = "";
            return Send("select", D("pos", D("x", (double)pos.X, "y", (double)pos.Y, "z", (double)pos.Z), "clientId", (double)clientId));
        }

        public bool ApplyOrb(string key)
        {
            var item = Item;
            if (item == null) return false;
            bool picks = CF.G(CF.M(item, "pick"), key) is List<object> l && l.Count > 0;
            var d = D("orb", key, "path", CF.G(item, "path"), "id", CF.G(item, "id"), "sig", CF.G(item, "sig"));
            if (picks && SelectedMod != null) d["mod"] = SelectedMod;
            return Send("apply", d);
        }

        public bool GemOp(string op, int socket)
        {
            var item = Item;
            if (item == null) return false;
            return Send("gem", D("op", op, "socket", (double)socket, "path", CF.G(item, "path"), "id", CF.G(item, "id"), "sig", CF.G(item, "sig")));
        }

        public bool SalvageItem() { var i = Item; return i != null && Send("salvage", D("path", CF.G(i, "path"), "id", CF.G(i, "id"), "sig", CF.G(i, "sig"))); }
        public bool ToggleLock() { var i = Item; return i != null && Send("lock", D("path", CF.G(i, "path"), "id", CF.G(i, "id"), "on", !CF.B(i, "locked"))); }

        public void SetScope(string bagPath, int maxRarity) { Send("salvageScope", D("bag", bagPath ?? "", "maxRarity", (double)maxRarity)); }

        public Dictionary<string, object> Batch => CF.G(Salvage, "batch") as Dictionary<string, object>;

        public bool SalvageAll()
        {
            var b = Batch;
            if (b == null || CF.N(b, "count") <= 0) return false;
            return Send("salvageBatch", D("bag", CF.T(b, "bag"), "maxRarity", CF.G(b, "maxRarity"), "sig", CF.G(b, "sig")));
        }

        /// <summary>The confirmation text of "salvage all".</summary>
        public string SalvageAllText()
        {
            var sv = Salvage; var b = Batch;
            if (sv == null || b == null) return "";
            var names = CF.Values(CF.G(sv, "rarityNames"));
            var ids = RarityIds(sv);
            string upTo = "?";
            for (int i = 0; i < names.Count; i++) if ((i < ids.Count ? ids[i] : i + 1) <= CF.N(b, "maxRarity")) upTo = Loc.T(names[i]);
            return Loc.T("Salvage {0} item(s) (rarity up to {1}) into {2} {3}?\nLocked items, uniques and items with gems are kept.\nThis cannot be undone.", CF.I(b, "count"), upTo, CF.I(b, "shards"), CF.T(sv, "shardName", "shards"));
        }

        public static List<int> RarityIds(object sv)
        {
            var ids = CF.Raw(CF.G(sv, "rarityIds")).Select(CF.Int).ToList();
            return ids.Count > 0 ? ids : RarityIdFallback.ToList();
        }

        public bool Combine(string key, int count) => Send("combine", D("key", key, "count", (double)count));
        public bool Recycle(string key, int count) => Send("recycle", D("key", key, "count", (double)count));

        // ---------------------------------------------------------------------------------------------- the bench view rules
        public static string RarityColorOf(double r) => r >= 0 && (int)r < RarityColor.Length && r >= 1 ? RarityColor[(int)r - 1] : "#d6c9ae";

        public string OrbReason(Dictionary<string, object> orb, out bool aimedNeedsMod)
        {
            aimedNeedsMod = false;
            var item = Item;
            string key = CF.T(orb, "key"), name = CF.T(orb, "name", key);
            int count = CF.I(orb, "count");
            string why = "";
            if (count <= 0) why = Loc.T("You have no {0}.", name);
            else if (item == null) why = Loc.T("Put an item on the bench first.");
            else
            {
                string code = CF.G(CF.M(item, "orbs"), key) as string;
                if (!string.IsNullOrEmpty(code)) why = CF.G(CF.M(Info, "reasons"), code) as string ?? code;
            }
            if (why.Length == 0 && item != null && CF.G(CF.M(item, "pick"), key) is List<object> pick && pick.Count > 0)
            {
                if (!pick.Any(k => CF.Str(k) == SelectedMod)) { why = SelectedMod != null ? Loc.T("That modifier cannot be chosen for this orb.") : Loc.T("Click a modifier of the item first."); aimedNeedsMod = true; }
            }
            return why;
        }

        public List<OrbRow> OrbRows()
        {
            var o = new List<OrbRow>();
            var item = Item;
            foreach (var orb in Orbs)
            {
                string why = OrbReason(orb, out _);
                string key = CF.T(orb, "key");
                string preview = why.Length == 0 && item != null ? CF.G(CF.M(item, "preview"), key) as string ?? "" : "";
                string text = item != null && CF.B(item, "waystone") && CF.G(orb, "wsText") is string ws ? ws : item != null && CF.T(item, "kind") == "riftkey" && CF.G(orb, "keyText") is string kt ? kt : CF.T(orb, "text");
                string line = why, color = "#a89074"; bool isText = false;
                if (preview.Length > 0) { line = preview; color = "#9fdc7f"; }
                else if (why.Length == 0) { line = text; color = "#8c8070"; isText = true; }
                else if (item == null && CF.I(orb, "count") > 0) { line = text; color = "#8c8070"; isText = true; }
                o.Add(new OrbRow { Key = key, Name = CF.T(orb, "name", key), ClientId = CF.I(orb, "clientId"), Count = CF.I(orb, "count"), Text = text, Why = why, Line = line, Color = color, Preview = preview, IsText = isText, CanUse = why.Length == 0 });
            }
            return o;
        }

        public static string ModText(Dictionary<string, object> m)
        {
            string text = CF.G(m, "short") is string s ? s : CF.T(m, "text");
            if (CF.G(m, "tier") != null)
            {
                text = string.Format("T{0}  {1}", CF.I(m, "tier"), text);
                if (CF.G(m, "lo") != null && CF.G(m, "hi") != null)
                    text += CF.N(m, "lo") == CF.N(m, "hi") ? string.Format("  [{0}]", CF.I(m, "lo")) : string.Format("  [{0}-{1}]", CF.I(m, "lo"), CF.I(m, "hi"));
            }
            return text;
        }

        public static string ModColor(Dictionary<string, object> m)
        {
            if (CF.B(m, "implicit")) return "#d04040";
            if (CF.B(m, "power")) return PowerColor;
            return GroupColor.TryGetValue(CF.T(m, "group"), out var c) ? c : "#d6c9ae";
        }

        public static string SideHeader(string side) => side == "implicit" ? Loc.T("Corrupted implicit") : side == "prefix" ? Loc.T("Prefixes") : Loc.T("Suffixes");

        /// <summary>The line under the item name: rarity and level, rift key, waystone, unique.</summary>
        public static string RarityLine(Dictionary<string, object> item, out string color)
        {
            double rarity = CF.N(item, "rarity");
            color = "#d6c9ae";
            if (CF.T(item, "kind") == "riftkey" && CF.B(item, "waystone"))
            { color = KeyColor; return Loc.T("{0}, tier {1} (monster level {2})", Loc.T(CF.T(item, "rarityName", "Normal Waystone")), CF.I(item, "tier"), CF.I(item, "level")); }
            if (CF.T(item, "kind") == "riftkey") { color = KeyColor; return Loc.T("Rift Key, tier {0} (level {1}+)", CF.I(item, "tier"), CF.I(item, "level")); }
            if (CF.B(item, "unique")) { color = "#e8582a"; return Loc.T("Unique item: orbs cannot change it"); }
            if (rarity > 0)
            {
                color = CF.B(item, "ruined") || CF.B(item, "corrupted") ? "#e03a1e" : RarityColorOf(rarity);
                return Loc.T("{0}, item level {1}", CF.T(item, "rarityName", "?"), CF.I(item, "level")) + (CF.G(item, "maxTier") != null ? Loc.T(" (up to T{0})", CF.I(item, "maxTier")) : "")
                    + (CF.B(item, "ruined") ? Loc.T("  RUINED") : "") + (CF.B(item, "corrupted") ? Loc.T("  CORRUPTED") : "");
            }
            return Loc.T("Normal item");
        }

        public static string ModCountLine(Dictionary<string, object> item)
        {
            var mods = CF.Rows(CF.G(item, "mods"));
            double rarity = CF.N(item, "rarity");
            var pre = CF.G(item, "prefixes") as List<object>; var suf = CF.G(item, "suffixes") as List<object>;
            if (rarity > 0 && pre != null && suf != null)
            {
                var binds = CF.G(item, "binds") as List<object>;
                return Loc.T("Modifiers {0}/{1} (prefixes {2}/{3}, suffixes {4}/{5}", mods.Count, CF.I(item, "maxMods"), CF.Int(pre.ElementAtOrDefault(0)), CF.Int(pre.ElementAtOrDefault(1)), CF.Int(suf.ElementAtOrDefault(0)), CF.Int(suf.ElementAtOrDefault(1)))
                    + (binds != null ? Loc.T(", bound {0}/{1}", CF.Int(binds.ElementAtOrDefault(0)), CF.Int(binds.ElementAtOrDefault(1))) : "") + ")";
            }
            if (rarity > 0 || CF.T(item, "kind") == "riftkey") return Loc.T("Modifiers: {0} / {1}", mods.Count, CF.I(item, "maxMods"));
            return mods.Count > 0 ? Loc.T("Modifiers: {0}", mods.Count) : Loc.T("No modifiers");
        }

        public static string QualityText(Dictionary<string, object> item, out int pct)
        {
            double q = CF.N(item, "quality"), cap = CF.N(item, "qualityCap");
            pct = cap > 0 ? (int)Math.Floor(100 * q / cap) : 0;
            return cap > 0 ? Loc.T("Quality +{0}% / {1}%", (long)q, (long)cap) : "";
        }

        public static string SocketHeader(Dictionary<string, object> item)
        {
            var s = CF.G(item, "sockets") as Dictionary<string, object>;
            int count = CF.I(s, "count");
            if (s == null || (count == 0 && CF.I(s, "max") == 0)) return null;
            if (count == 0) return Loc.T("No sockets (an Orb of Sockets gives up to {0})", CF.I(s, "max"));
            int filled = CF.Rows(CF.G(s, "list")).Count(r => CF.I(r, "id") > 0);
            return Loc.T("Sockets: {0} / {1}", filled, count);
        }

        public static List<Dictionary<string, object>> SocketList(Dictionary<string, object> item) => CF.Rows(CF.G(CF.G(item, "sockets"), "list"));

        // ---------------------------------------------------------------------------------------------- salvage tab
        public string SalvageItemText(out bool ok)
        {
            ok = false;
            var item = Item;
            if (item == null) return Loc.T("Put an item on the bench, or salvage a whole bag below.");
            var s = CF.M(item, "salvage");
            var sv = Salvage;
            ok = CF.B(s, "ok");
            if (ok) return Loc.T("{0}: {1} {2}, {3}% chance of an orb.", CF.T(item, "name", "?"), CF.I(s, "shards"), ShardWord(sv, CF.G(s, "shards")), CF.Str(CF.G(s, "orbChance"), "0"));
            return Loc.T("{0}: {1}", CF.T(item, "name", "?"), CF.T(s, "why", Loc.T("cannot be salvaged.")));
        }

        public static string ShardWord(object sv, object n) => CF.Num(n) == 1 ? CF.T(sv, "shardSingular", "shard") : CF.T(sv, "shardName", "shards");

        public string BatchText()
        {
            var b = Batch; var sv = Salvage;
            if (b == null) return "";
            int count = CF.I(b, "count");
            var lines = new List<string>();
            lines.Add(count > 0 ? Loc.T("{0} {1} -> {2} {3}, {4}% orb chance in total.", count, count == 1 ? Loc.T("item") : Loc.T("items"), CF.I(b, "shards"), ShardWord(sv, CF.G(b, "shards")), CF.Str(CF.G(b, "orbs"), "0")) : Loc.T("Nothing to salvage there."));
            var skipped = new List<string>();
            foreach (var kv in CF.M(b, "skipped"))
            {
                string text = SkipText.TryGetValue(kv.Key, out var t) ? t : kv.Key;
                skipped.Add(string.Format("{0} {1}", CF.Int(kv.Value), text.Replace("{0}", CF.I(b, "cap").ToString())));
            }
            skipped.Sort(StringComparer.Ordinal);
            if (skipped.Count > 0) lines.Add(Loc.T("Skipped: {0}.", string.Join(", ", skipped)));
            return string.Join("\n", lines);
        }

        public string BatchButtonText()
        {
            var b = Batch;
            int count = b == null ? 0 : CF.I(b, "count");
            return count > 1 ? Loc.T("Salvage {0} items", count) : count == 1 ? Loc.T("Salvage 1 item") : Loc.T("Salvage all");
        }

        public bool Installed => CF.G(Salvage, "installed") as bool? != false;

        // recipes (recipeview.lua)
        public static bool IsShardRecipe(object r) => CF.N(r, "input") > 0;
        public static double Have(object r, object sv) => IsShardRecipe(r) ? CF.N(r, "have") : CF.N(sv, "shards");
        public static string Currency(object r, object sv) => IsShardRecipe(r) ? CF.T(r, "inputName", "shards") : CF.T(sv, "shardName", "shards");
        public static string CostText(object r, object sv) => IsShardRecipe(r) ? CF.Group(CF.N(r, "cost")) + " " + Currency(r, sv) : Loc.T("{0} shards", CF.I(r, "cost"));

        public static int CombineCount(double have, double cost, double max, bool ctrl)
        {
            if (cost <= 0 || have < cost) return 0;
            if (!ctrl) return 1;
            return (int)Math.Max(1, Math.Min(max == 0 ? 1 : max, Math.Floor(have / cost)));
        }

        public static int RecycleBack(object r) => IsShardRecipe(r) ? 0 : CF.I(r, "back");

        public static bool RecipeEnabled(object r, object sv)
        {
            bool enough = Have(r, sv) >= CF.N(r, "cost");
            if (IsShardRecipe(r)) return enough;
            return CF.G(sv, "installed") as bool? != false && (enough || (RecycleBack(r) > 0 && CF.N(r, "count") > 0));
        }

        public static string RecipeTip(object r, object sv)
        {
            string name = CF.T(r, "name", CF.T(r, "key", "?"));
            string text = Loc.T("{0} {1} -> 1 {2} (you have {3}).\nCtrl+click: as many as you can, up to {4}.", CF.I(r, "cost"), Currency(r, sv), name, CF.I(r, "count"), CF.G(sv, "maxCombine") == null ? 1 : CF.I(sv, "maxCombine"));
            if (IsShardRecipe(r)) text += "\n" + Loc.T("Your {0}: {1}.", Currency(r, sv), CF.Group(Have(r, sv)));
            int back = RecycleBack(r);
            if (back > 0) text += "\n" + Loc.T("Shift+click: recycle your {0} into {1} {2} each.", name, back, Currency(r, sv));
            return text;
        }

        public List<Dictionary<string, object>> Recipes => CF.Rows(CF.G(Salvage, "recipes"));
    }

    /// <summary>The item lock menu rules (lockmenu.lua): which inventory positions can be locked from a right click.</summary>
    public static class CraftingLockMenu
    {
        public const int InventoryX = 0xFFFF;
        static readonly HashSet<int> Slots = new HashSet<int> { 1, 2, 3, 4, 5, 6, 7, 8, 9, 13 };

        public static bool OwnPosition(Pos pos, out Pos own)
        {
            own = pos;
            if (pos.X != InventoryX) return false;
            if (Slots.Contains(pos.Y)) { own = new Pos(InventoryX, pos.Y, 0); return true; }
            if (pos.Y >= 0x40 && pos.Y < 0x50 && pos.Z >= 0 && pos.Z <= 255) { own = pos; return true; }
            return false;
        }

        /// <summary>Whether the lock entries appear for an item: own inventory, not stackable or a container, locked / rarity / unique / a rift key.</summary>
        public static bool Applies(Pos pos, bool stackable, bool container, bool locked, int rarity, bool unique, string name)
        {
            if (!OwnPosition(pos, out _) || stackable || container) return false;
            if (locked || rarity > 0 || unique) return true;
            return name != null && name.ToLowerInvariant().Contains("rift key");
        }

        public static bool Show(Pos pos, bool stackable, bool container, bool locked, int rarity, bool unique, string name, bool wantLocked) => Applies(pos, stackable, container, locked, rarity, unique, name) && locked == wantLocked;

        public static Dictionary<string, object> Request(Pos pos, int clientId, bool on)
        {
            if (!OwnPosition(pos, out var own)) return null;
            return new Dictionary<string, object>
            {
                { "pos", new Dictionary<string, object> { { "x", (double)own.X }, { "y", (double)own.Y }, { "z", (double)own.Z } } },
                { "cid", (double)clientId }, { "on", on },
            };
        }
    }

    /// <summary>The guide of the bench (craftguideview.lua): the risk of each orb, a line of advice, basics and a plan.</summary>
    public static class CraftGuide
    {
        static readonly Dictionary<string, string> Risk = new Dictionary<string, string>
        {
            { "transmutation", "safe" }, { "alchemy", "safe" }, { "exalted", "safe" }, { "annulment", "gamble" }, { "scouring", "safe" }, { "chaos", "gamble" }, { "divine", "gamble" },
            { "sockets", "gamble" }, { "tempering", "safe" }, { "binding", "safe" }, { "excision", "safe" }, { "reforging", "gamble" }, { "ruin", "gamble" }, { "whetstone", "safe" },
            { "unveiling", "final" }, { "ember", "safe" }, { "crown", "safe" }, { "void", "final" },
        };
        public static readonly Dictionary<string, string> RiskColor = new Dictionary<string, string> { { "safe", "#9fdc7f" }, { "gamble", "#f6cf72" }, { "final", "#ff8a5a" } };

        public static string RiskOf(string key) => Risk.TryGetValue(key, out var r) ? r : "";

        public static string RiskText(string risk)
        {
            switch (risk)
            {
                case "safe": return Loc.T("Safe: it does what it says.");
                case "gamble": return Loc.T("Gamble: the result is random.");
                case "final": return Loc.T("Final: it cannot be undone.");
            }
            return "";
        }

        static readonly Dictionary<string, string> Advice = new Dictionary<string, string>
        {
            { "transmutation", "Your first orb. Use it on a plain item to give it a rarity and a few bonuses." },
            { "alchemy", "Like Awakening, but it can give a better rarity. Save it for a plain item with a good base and a high item level." },
            { "exalted", "Use it when the item has a free prefix or suffix: it adds one more bonus." },
            { "annulment", "Removes a random bonus. Bind the bonuses you want to keep first." },
            { "scouring", "Start over: the item becomes plain again, ready for a new Awakening or Gilding." },
            { "chaos", "Rerolls every bonus that is not bound. Bind your best bonus first, then reroll the rest." },
            { "divine", "Raises the rarity, but the bonuses are rolled again. Use the Crown Orb to keep them." },
            { "sockets", "Rolls a new number of sockets. Gems already in the item stay." },
            { "tempering", "The bonuses keep their tiers and get new numbers. Good when the tiers are right but the numbers are low." },
            { "binding", "Protects one bonus you pick from every orb. Use it before Upheaval or Unmaking." },
            { "excision", "Removes the bonus you pick. The safe way to get rid of a bad one." },
            { "reforging", "Rolls the tier and number of one bonus you pick again. It can go up or down." },
            { "ruin", "Often nothing happens; sometimes the bonuses get better. It never makes the item worse." },
            { "whetstone", "Adds 1% quality. Quality makes the whole item a little stronger." },
            { "unveiling", "Shows three choices for a veiled bonus. Pick one; the choice stays." },
            { "ember", "The best upgrade: one bonus you pick goes up exactly one tier." },
            { "crown", "Raises the rarity one step, keeps every bonus and adds one." },
            { "void", "The last orb for a finished Rare or better item: a big gamble, and after it no orb changes the item." },
        };

        public static string AdviceOf(string key) => Advice.TryGetValue(key, out var a) ? Loc.T(a) : "";

        public static readonly string[][] Basics =
        {
            new[] { "Rarity", "Common, Uncommon, Magic, Rare, Legendary, Divine. A better rarity has room for more bonuses. Uniques are fixed: orbs do not change them." },
            new[] { "Bonuses", "Each line of an item is a bonus (a modifier). Bonuses are prefixes or suffixes, and each rarity has a limit of each." },
            new[] { "Tiers", "A bonus has a tier from T1 (weak) to T8 (best). The item level decides the best tier it can roll." },
            new[] { "Bound", "A bound bonus is safe: orbs leave it alone. Only an Orb of Erasure frees it." },
            new[] { "Preview", "Put the item on the bench: the green line under each orb shows what it would do. Orbs also work with Use on the item." },
        };

        public static readonly string[] Plan =
        {
            "1. Lock the gear you want to keep. Salvage the rest into shards and combine the shards into orbs (Salvage tab).",
            "2. A plain item with a good base: Orb of Awakening, or Orb of Gilding for a better rarity.",
            "3. A free prefix or suffix: Orb of Grafting adds a bonus.",
            "4. A bad bonus: Orb of Excision removes the one you pick.",
            "5. A great bonus: Orb of Binding keeps it safe, then Orb of Upheaval rerolls the others.",
            "6. Make good bonuses better: Ember Orb (one tier up), Orb of Tempering (new numbers), Whetstone (quality).",
            "7. Raise the rarity: Crown Orb keeps every bonus and adds one.",
            "8. Only at the end: the gambles. A Void Orb is for good.",
        };

        /// <summary>One gem line of the guide: name, color, and the effect per group.</summary>
        public static string EffectText(object def, object values, object values2)
        {
            string label = CF.G(def, "label") is string l ? Loc.T(l) : "?";
            string fmt = CF.T(def, "fmt");
            if (fmt == "flat") return label + " +" + Series(values, "");
            if (fmt == "pair") return label + " +" + Series(values, "%") + ", " + (CF.G(def, "label2") is string l2 ? Loc.T(l2) : "?") + " +" + Series(values2, "%");
            return label + " +" + Series(values, "%");
        }

        static string Series(object values, string suffix) => string.Join(" / ", CF.Raw(values).Select(v => CF.Str(v))) + suffix;

        public static string CapText(object def) => CF.G(def, "cap") == null ? "" : CF.Str(CF.G(def, "cap")) + (CF.T(def, "fmt") == "flat" ? "" : "%");
    }
}
