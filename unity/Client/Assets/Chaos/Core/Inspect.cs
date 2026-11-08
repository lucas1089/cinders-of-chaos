// Inspect Player (client game_playerinspect, extended opcode 240, server inspect.lua + inspect_core.lua).
//   client -> server  inspect {cid} | inspect {name} | privacy {} | privacy {allow}
//   server -> client  result {name, level, voc, vocId, ascended, guild {name, rank}, ach, rift, trials, outfit, self, parts, paragon, title, bestiary, bosses, pvp,
//                              collection, passive, combat {...}}
//                     equip {name, rows [{slot, tip}]}   (one per part; a result says how many follow)
//                     tree {name, nodes, masteries, ...}   records {name, rows [{key, name, value}]}   denied {code, text}   privacy {allow}
// A big message comes in chunks (ExtOpcodes joins them). Windows: the right-click "Inspect" entry of a player on the map asks by creature id, the top menu
// asks by typed name. The passive tree of the inspected character is a summary line with a View tree button (the read-only window of Phase7ZInspect.cs).
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    public static class InspectMath
    {
        public const int MaxTrialTier = 3, MaxRecordRows = 24;

        /// <summary>Equipment slots in the window's order (row, then column) with their names.</summary>
        public static readonly int[] SlotOrder = { 2, 1, 3, 6, 4, 5, 9, 7, 13, 8 };
        public static string SlotName(int slot)
        {
            switch (slot)
            {
                case 2: return "Amulet"; case 1: return "Helmet"; case 3: return "Backpack"; case 6: return "Left hand"; case 4: return "Armour";
                case 5: return "Right hand"; case 9: return "Ring"; case 7: return "Legs"; case 13: return "Badge"; case 8: return "Boots";
                default: return "";
            }
        }

        public static readonly string[] TypeOrder = { "physical", "fire", "energy", "earth", "ice", "holy", "death", "water", "arcane", "drown", "lifedrain", "manadrain" };
        public static string TypeName(string k)
        {
            switch (k)
            {
                case "physical": return "Physical"; case "fire": return "Fire"; case "energy": return "Energy"; case "earth": return "Earth"; case "ice": return "Ice";
                case "holy": return "Holy"; case "death": return "Death"; case "water": return "Water"; case "arcane": return "Arcane"; case "drown": return "Drowning";
                case "lifedrain": return "Life drain"; case "manadrain": return "Mana drain"; default: return k;
            }
        }

        /// <summary>A typed name: letters, spaces, ' and -, 2 to 29 characters. Null when it is not one.</summary>
        public static string CleanName(string name)
        {
            if (name == null) return null;
            var parts = name.Trim().Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
            string n = string.Join(" ", parts);
            if (n.Length < 2 || n.Length > 29 || !char.IsLetter(n[0])) return null;
            foreach (char c in n) if (!char.IsLetter(c) && c != ' ' && c != '\'' && c != '-') return null;
            return n;
        }

        public static string Num(double n) => SFmt.Money(n);

        public sealed class Stat { public string Label = "", Value = "", Tone = "text"; }
        public sealed class Section { public string Title = ""; public List<Stat> Rows = new List<Stat>(); }

        static void Add(List<Stat> l, string label, string value, string tone = "text") { l.Add(new Stat { Label = label, Value = value, Tone = tone }); }

        /// <summary>The header lines: name, class, ascended badge, title, guild.</summary>
        public static List<KeyValuePair<string, string>> Header(object d)
        {
            var o = new List<KeyValuePair<string, string>>();
            string voc = Json.Text(d, "voc").Length > 0 ? Json.Text(d, "voc") : Loc.T("No vocation");
            o.Add(new KeyValuePair<string, string>(Json.Text(d, "name"), "gold"));
            o.Add(new KeyValuePair<string, string>(Loc.T("Level {0} {1}", Json.Int(d, "level"), voc), "text"));
            if (Json.Bool(d, "ascended")) o.Add(new KeyValuePair<string, string>(Loc.T("Ascended class"), "gold"));
            if (Json.Text(d, "title").Length > 0) o.Add(new KeyValuePair<string, string>(Json.Text(d, "title"), "#7fc4d6"));
            object g = Json.Get(d, "guild");
            o.Add(SFmt.IsMap(g) && Json.Text(g, "name").Length > 0
                ? new KeyValuePair<string, string>(Loc.T("{0} of {1}", Json.Text(g, "rank").Length > 0 ? Loc.T(Json.Text(g, "rank")) : Loc.T("Member"), Json.Text(g, "name")), "text")
                : new KeyValuePair<string, string>(Loc.T("No guild"), "dim"));
            return o;
        }

        static bool Pos(object d, string key) => Json.Number(d, key) > 0;

        /// <summary>The profile sections: Progress and Combat. A field the server did not send has no row.</summary>
        public static List<Section> Stats(object d)
        {
            var progress = new List<Stat>(); var combat = new List<Stat>();
            if (Pos(d, "paragon")) Add(progress, Loc.T("Paragon points"), Num(Json.Number(d, "paragon")));
            object pa = Json.Get(d, "passive");
            if (SFmt.IsMap(pa) && (Pos(pa, "total") || Pos(pa, "spent")))
                Add(progress, Loc.T("Passive points"), Num(Json.Number(pa, "spent")) + " / " + Num(Math.Max(Json.Number(pa, "total"), Json.Number(pa, "spent"))));
            Add(progress, Loc.T("Achievement points"), Num(Json.Number(d, "ach")), Pos(d, "ach") ? "text" : "dim");
            if (Pos(d, "collection")) Add(progress, Loc.T("Collection score"), Num(Json.Number(d, "collection")));
            object be = Json.Get(d, "bestiary");
            if (SFmt.IsMap(be) && Pos(be, "points"))
            {
                string rank = Json.Text(be, "rank");
                Add(progress, Loc.T("Bestiary"), rank.Length > 0 ? Num(Json.Number(be, "points")) + " (" + Loc.T(rank) + ")" : Num(Json.Number(be, "points")));
            }
            object bo = Json.Get(d, "bosses");
            if (SFmt.IsMap(bo) && Pos(bo, "got")) Add(progress, Loc.T("Boss Points"), Num(Json.Number(bo, "got")) + " / " + Num(Json.Number(bo, "total")));
            if (Pos(d, "rift")) Add(combat, Loc.T("Best rift sealed"), Loc.T("Tier {0}", Json.Int(d, "rift"))); else Add(combat, Loc.T("Best rift sealed"), Loc.T("None"), "dim");
            int trials = Json.Int(d, "trials");
            if (trials > 0) Add(combat, Loc.T("Vocation Trials"), Loc.T("Tier {0} of {1}", trials, MaxTrialTier), trials >= MaxTrialTier ? "good" : "text");
            else Add(combat, Loc.T("Vocation Trials"), Loc.T("None"), "dim");
            object pv = Json.Get(d, "pvp");
            if (SFmt.IsMap(pv) && Pos(pv, "rating"))
            {
                string tier = Json.Text(pv, "tier");
                Add(combat, Loc.T("PvP: {0}", Loc.T(Json.Text(pv, "name").Length > 0 ? Json.Text(pv, "name") : "Arena")), tier.Length > 0 ? Num(Json.Number(pv, "rating")) + " (" + tier + ")" : Num(Json.Number(pv, "rating")));
            }
            return new List<Section> { new Section { Title = Loc.T("Progress"), Rows = progress }, new Section { Title = Loc.T("Combat"), Rows = combat } };
        }

        static Dictionary<string, double> ByType(object list)
        {
            var map = new Dictionary<string, double>();
            if (list is List<object> l) foreach (object r in l) if (SFmt.IsMap(r) && Json.Text(r, "k").Length > 0) map[Json.Text(r, "k")] = Json.Number(r, "pct");
            return map;
        }

        /// <summary>The combat sheet (Offense, Defense, Resistances); empty when the server sent no combat block.</summary>
        public static List<Section> CombatStats(object d)
        {
            object c = Json.Get(d, "combat");
            var res = new List<Section>();
            if (!SFmt.IsMap(c)) return res;
            var off = new List<Stat>(); var def = new List<Stat>(); var rs = new List<Stat>();
            if (Pos(c, "attack")) Add(off, Loc.T("Weapon attack"), Num(Json.Number(c, "attack")));
            if (Pos(c, "hit")) Add(off, Loc.T("Average hit"), Num(Json.Number(c, "hit")));
            if (Pos(c, "maxHit")) Add(off, Loc.T("Highest hit"), Num(Json.Number(c, "maxHit")), "gold");
            if (Pos(c, "attackSpeed")) Add(off, Loc.T("Attack speed"), "+" + SFmt.Pct(Json.Number(c, "attackSpeed")) + "%");
            if (Pos(c, "critChance")) Add(off, Loc.T("Critical chance"), SFmt.Pct(Json.Number(c, "critChance")) + "%");
            if (Pos(c, "critAmount")) Add(off, Loc.T("Critical damage"), "+" + SFmt.Pct(Json.Number(c, "critAmount")) + "%");
            object ll = Json.Get(c, "lifeLeech"), ml = Json.Get(c, "manaLeech");
            if (SFmt.IsMap(ll)) Add(off, Loc.T("Life leech"), SFmt.Pct(Json.Number(ll, "chance")) + "% / " + SFmt.Pct(Json.Number(ll, "amount")) + "%");
            if (SFmt.IsMap(ml)) Add(off, Loc.T("Mana leech"), SFmt.Pct(Json.Number(ml, "chance")) + "% / " + SFmt.Pct(Json.Number(ml, "amount")) + "%");
            var dmg = ByType(Json.Get(c, "damage"));
            foreach (var k in TypeOrder) if (dmg.TryGetValue(k, out double v)) Add(off, Loc.T("{0} damage", Loc.T(TypeName(k))), "+" + SFmt.Pct(v) + "%");
            if (Pos(c, "defense")) Add(def, Loc.T("Defense"), Num(Json.Number(c, "defense")));
            if (Pos(c, "armor")) Add(def, Loc.T("Armor"), Num(Json.Number(c, "armor")));
            if (Pos(c, "mitigation")) Add(def, Loc.T("Damage reduction"), SFmt.Pct(Json.Number(c, "mitigation")) + "%");
            if (Pos(c, "maxHealth")) Add(def, Loc.T("Maximum health"), Num(Json.Number(c, "maxHealth")));
            if (Pos(c, "maxMana")) Add(def, Loc.T("Maximum mana"), Num(Json.Number(c, "maxMana")));
            if (Pos(c, "moveSpeed")) Add(def, Loc.T("Movement speed"), Num(Json.Number(c, "moveSpeed")));
            var rmap = ByType(Json.Get(c, "resist"));
            foreach (var k in TypeOrder) if (rmap.TryGetValue(k, out double v)) Add(rs, Loc.T(TypeName(k)), SFmt.Pct(v) + "%", v < 0 ? "bad" : "good");
            res.Add(new Section { Title = Loc.T("Offense"), Rows = off });
            res.Add(new Section { Title = Loc.T("Defense"), Rows = def });
            res.Add(new Section { Title = Loc.T("Resistances"), Rows = rs });
            return res;
        }

        /// <summary>The Outfit of the result's outfit table.</summary>
        public static Outfit OutfitOf(object d)
        {
            object o = Json.Get(d, "outfit");
            if (!SFmt.IsMap(o)) return null;
            return new Outfit(Json.Int(o, "type"), Json.Int(o, "head"), Json.Int(o, "body"), Json.Int(o, "legs"), Json.Int(o, "feet"), Json.Int(o, "addons"), Json.Int(o, "mount"));
        }

        /// <summary>The client id an equipment tip is drawn as: its transmog look when it has one.</summary>
        public static int TipItem(object tip)
        {
            int look = Json.Int(Json.Get(tip, "look"), "cid");
            return look > 0 ? look : Json.Int(tip, "id");
        }
    }

    public sealed class InspectPanel : SocialPanel
    {
        public const byte Opcode = 240;
        readonly ExtOpcodes ext;
        public object Data, TreeData;
        /// <summary>Phase 7 track Y: shows the inspected character's tree in the passive tree window (set by the app).</summary>
        public Action<object> ViewTree = delegate { };
        public readonly Dictionary<int, object> Tips = new Dictionary<int, object>();
        public List<KeyValuePair<string, string>> Records;
        public int PartsExpected, PartsGot;
        public bool AllowMe, PrivacyKnown;
        public string Denied = "";

        public InspectPanel(ExtOpcodes e)
        {
            ext = e;
            Tabs.Add(new KeyValuePair<string, string>("gear", "Equipment"));
            Tabs.Add(new KeyValuePair<string, string>("profile", "Profile"));
            Tabs.Add(new KeyValuePair<string, string>("combat", "Combat"));
            Tabs.Add(new KeyValuePair<string, string>("records", "Records"));
            Tab = "gear";
            e.On(Opcode, OnMessage);
        }

        void Send(string action, object data = null) { ext.Send(Opcode, action, data ?? new Dictionary<string, object>()); }

        public override void Show() { if (!Visible) { Visible = true; Send("privacy"); } }
        public override void Clear() { base.Clear(); Data = TreeData = null; Tips.Clear(); Records = null; PartsExpected = PartsGot = 0; PrivacyKnown = false; Denied = ""; Tab = "gear"; }

        public bool Complete => Data != null && PartsGot >= PartsExpected;

        /// <summary>Asks for a typed name (false and a message when the name is not valid).</summary>
        public bool InspectName(string name)
        {
            Show();
            string clean = InspectMath.CleanName(name);
            if (clean == null) { Say(Loc.T("Enter the name of a player."), false); return false; }
            Status = Loc.T("Inspecting {0}...", clean); StatusTone = "dim"; Denied = "";
            Send("inspect", SFmt.Map("name", clean));
            Changed();
            return true;
        }

        /// <summary>Asks for a player in view by its creature id (the right-click menu).</summary>
        public void InspectCreature(uint id, string name)
        {
            Show();
            Status = Loc.T("Inspecting {0}...", name); StatusTone = "dim"; Denied = "";
            Send("inspect", SFmt.Map("cid", id));
            Changed();
        }

        public void SetPrivacy(bool allow) { AllowMe = allow; Send("privacy", SFmt.Map("allow", allow)); Changed(); }

        void OnMessage(ExtMessage m)
        {
            object d = m.Data;
            if (!SFmt.IsMap(d)) return;
            switch (m.Action)
            {
                case "result":
                    Data = d; Tips.Clear(); TreeData = null; Records = null; PartsExpected = Json.Int(d, "parts"); PartsGot = 0; Denied = "";
                    Visible = true;
                    Header1 = Json.Text(d, "name");
                    Status = Json.Bool(d, "self") ? Loc.T("This is you.") : ""; StatusTone = "dim";
                    if (Tab == "combat" && InspectMath.CombatStats(d).Count == 0) Tab = "gear";
                    break;
                case "equip":
                    if (Data == null || Json.Text(d, "name") != Json.Text(Data, "name")) return;
                    foreach (var r in SFmt.Rows(d, "rows"))
                    {
                        int slot = Json.Int(r, "slot");
                        if (Array.IndexOf(InspectMath.SlotOrder, slot) >= 0 && SFmt.IsMap(Json.Get(r, "tip"))) Tips[slot] = Json.Get(r, "tip");
                    }
                    PartsGot++;
                    break;
                case "tree": if (Data != null && Json.Text(d, "name") == Json.Text(Data, "name") && Json.Get(d, "nodes") is List<object>) TreeData = d; break;
                case "records":
                    if (Data != null && Json.Text(d, "name") == Json.Text(Data, "name") && Json.Get(d, "rows") is List<object>)
                    {
                        Records = new List<KeyValuePair<string, string>>();
                        foreach (var r in SFmt.Rows(d, "rows"))
                            if (Json.Text(r, "name").Length > 0 && SFmt.Has(r, "value") && Records.Count < InspectMath.MaxRecordRows)
                                Records.Add(new KeyValuePair<string, string>(Json.Text(r, "name"), Json.Get(r, "value") is double dv ? SFmt.Money(dv) : Json.Text(r, "value")));
                    }
                    break;
                case "denied":
                    Data = null; TreeData = null; Tips.Clear(); Records = null;
                    Denied = Json.Text(d, "text", Loc.T("Nothing to show."));
                    Status = Denied; StatusTone = "bad"; Visible = true; Header1 = "";
                    break;
                case "privacy": AllowMe = Json.Bool(d, "allow"); PrivacyKnown = true; Form["privacy"] = AllowMe ? "1" : "0"; break;
            }
            Changed();
        }

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            l.Input(Loc.T("Player"), "name", Loc.T("character name")).Btn(Loc.T("Inspect"), true, () => InspectName(Text("name")));
            if (Data == null)
            {
                if (Denied.Length > 0) l.Text(Denied, "bad");
                else l.Text(Loc.T("Type a name, or right-click a player on the map and pick Inspect."), "dim");
            }
            else
            {
                foreach (var h in InspectMath.Header(Data)) l.Text(h.Key, h.Value);
                switch (Tab)
                {
                    case "profile": SectionRows(l, InspectMath.Stats(Data)); TreeRow(l); break;
                    case "combat": SectionRows(l, InspectMath.CombatStats(Data)); break;
                    case "records":
                        if (Records == null) l.Text(Loc.T("Nothing to show."), "dim");
                        else if (Records.Count == 0) l.Text(Loc.T("No records yet."), "dim");
                        else foreach (var r in Records) l.Row(r.Key, r.Value);
                        break;
                    default: GearRows(l); break;
                }
            }
            l.Combo(Loc.T("Others may inspect me"), "privacy", new List<string> { Loc.T("No"), Loc.T("Yes") }).Hint = "privacy";
            return l.Rows;
        }

        public override void OnForm(string key)
        {
            if (key == "privacy") { bool allow = Index("privacy") == 1; if (allow != AllowMe) SetPrivacy(allow); }
        }

        void GearRows(RowList l)
        {
            l.Section(Loc.T("Equipment") + (Complete ? "" : "  ..."));
            foreach (int slot in InspectMath.SlotOrder)
            {
                Tips.TryGetValue(slot, out object tip);
                var r = l.Row(Loc.T(InspectMath.SlotName(slot)), tip != null ? Json.Text(tip, "name") : "", "dim");
                if (tip != null)
                {
                    int rarity = Json.Int(tip, "rarity"); bool unique = Json.Bool(tip, "unique");
                    r.Right = Json.Text(tip, "name");
                    r.Tone = rarity > 0 || unique ? SFmt.RarityTone(rarity, unique) : "text";
                    r.Item(InspectMath.TipItem(tip), Json.Int(tip, "count", 1), rarity > 0 || unique ? SFmt.RarityTone(rarity, unique) : null, tip);
                }
            }
        }

        void SectionRows(RowList l, List<InspectMath.Section> sections)
        {
            bool any = false;
            foreach (var s in sections)
            {
                if (s.Rows.Count == 0) continue;
                any = true;
                l.Section(s.Title);
                foreach (var r in s.Rows) l.Row(r.Label, r.Value, r.Tone);
            }
            if (!any) l.Text(Loc.T("Nothing to show."), "dim");
        }

        void TreeRow(RowList l)
        {
            if (TreeData == null) return;
            var tree = TreeData;
            l.Row(Loc.T("Passive Tree ({0})", Json.List(TreeData, "nodes").Count), Loc.T("{0} / {1} points", Json.Int(TreeData, "spent"), Json.Int(TreeData, "total")), "dim")
                .Btn(Loc.T("View tree"), true, () => ViewTree(tree));
        }
    }
}
