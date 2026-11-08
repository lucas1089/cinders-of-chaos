// Pets (client game_pets, extended opcode 254, server pets). Collect species, call one out, level it.
//   client -> server  open | close | get (every 3 s while open) | summon {species} | dismiss | rename {species, name}
//   server -> client  state {pets [{species, speciesName, name, look, level, xp, into, need, pct, element, abilities [{name, kind, desc, cooldown, unlocked, unlockAt}]}],
//                     catalog [{key, name, look, how, abilities [name]}], active, out, rest, zone, secondAt, cooldowns {death, summon}, open}
//                     xp {species, level, xp, into, need, pct}
using System;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core
{
    /// <summary>A line of the list: an owned pet or a species of the catalog the account has not got.</summary>
    public sealed class PetEntry
    {
        public string Key = "", Name = "", SpeciesName = "", How = "";
        public bool Owned;
        public int Look, Level;
        public Dictionary<string, object> Pet;
        public List<object> Abilities = new List<object>();
    }

    public sealed class PetAbilityLine { public string Title = "", Text = "", LockText; public bool Locked; }

    public sealed class PetButtons { public bool Summon, Dismiss, Rename; }

    public sealed class PetsState : CollectModel
    {
        public const byte OpcodeId = 254;
        public const double RefreshMs = 3000;

        public object State;
        public string Selected;
        public bool Visible;
        public double NextRefresh;

        public PetsState(ExtOpcodes e) : base(e, OpcodeId) { }

        public void Toggle() { if (Visible) Hide(); else Send("open"); }
        public void Hide() { if (Visible) { Visible = false; Send("close"); } }
        public void Summon(string species) { if (!string.IsNullOrEmpty(species)) Send("summon", D("species", species)); }
        public void Dismiss() { Send("dismiss"); }

        public bool Rename(string species, string text)
        {
            string name = CleanName(text);
            if (name == null || string.IsNullOrEmpty(species)) return false;
            return Send("rename", D("species", species, "name", name));
        }

        /// <summary>Every frame: while open, asks for the state every 3 seconds.</summary>
        public void Tick(double nowMs)
        {
            if (!Visible) return;
            if (NextRefresh == 0) NextRefresh = nowMs + RefreshMs;
            if (nowMs >= NextRefresh) { Send("get"); NextRefresh = nowMs + RefreshMs; }
        }

        public override void Handle(string action, object data)
        {
            if (action == "state")
            {
                State = data;
                if (CF.B(data, "open")) { Visible = true; NextRefresh = 0; }
                Selected = Pick(Entries(), Selected, CF.G(data, "active") as string);
            }
            else if (action == "xp" && State != null) ApplyXp(State, data);
        }

        public void Clear() { State = null; Selected = null; Visible = false; NextRefresh = 0; }

        // ---------------------------------------------------------------------------------------------- the view rules
        public List<PetEntry> Entries() => EntriesOf(State);

        public static List<PetEntry> EntriesOf(object state)
        {
            var o = new List<PetEntry>();
            var seen = new HashSet<string>();
            var catalog = new Dictionary<string, Dictionary<string, object>>();
            foreach (var c in CF.Rows(CF.G(state, "catalog"))) if (CF.G(c, "key") != null) catalog[CF.Str(CF.G(c, "key"))] = c;
            foreach (var p in CF.Rows(CF.G(state, "pets")))
            {
                if (CF.G(p, "species") == null) continue;
                string sp = CF.Str(CF.G(p, "species"));
                catalog.TryGetValue(sp, out var c);
                o.Add(new PetEntry { Key = sp, Owned = true, Pet = p, Name = CF.T(p, "name", CF.T(p, "speciesName")), SpeciesName = CF.T(p, "speciesName"), Look = CF.I(p, "look"), How = c != null ? CF.T(c, "how") : "", Level = CF.I(p, "level") });
                seen.Add(sp);
            }
            foreach (var c in CF.Rows(CF.G(state, "catalog")))
            {
                if (CF.G(c, "key") == null) continue;
                string key = CF.Str(CF.G(c, "key"));
                if (seen.Contains(key)) continue;
                o.Add(new PetEntry { Key = key, Owned = false, Name = CF.T(c, "name"), SpeciesName = CF.T(c, "name"), Look = CF.I(c, "look"), How = CF.T(c, "how"), Abilities = CF.Raw(CF.G(c, "abilities")) });
            }
            return o;
        }

        public static PetEntry Find(IEnumerable<PetEntry> entries, string key) => entries.FirstOrDefault(e => e.Key == key);

        public static string Pick(IList<PetEntry> entries, string wanted, string active)
        {
            if (wanted != null && Find(entries, wanted) != null) return wanted;
            if (active != null && Find(entries, active) != null) return active;
            return entries.Count > 0 ? entries[0].Key : null;
        }

        public string TitleText(PetEntry e) => e.Owned && e.Name != e.SpeciesName ? string.Format("{0} ({1})", e.Name, e.SpeciesName) : e.Name;

        public string RowSub(PetEntry e)
        {
            if (!e.Owned) return Loc.T("Not owned");
            string s = Loc.T("Level {0}", e.Level);
            if (CF.G(State, "active") is string a && a == e.Key) s += CF.B(State, "out") ? Loc.T(", out") : Loc.T(", resting");
            return s;
        }

        public static string XpText(object p)
        {
            if (!(p is Dictionary<string, object>)) return "";
            if (CF.N(p, "need") <= 0) return Loc.T("Level {0} (max)", CF.I(p, "level"));
            return Loc.T("Level {0}  -  {1} / {2} XP ({3}%)", CF.I(p, "level"), CF.I(p, "into"), CF.I(p, "need"), CF.I(p, "pct"));
        }

        public List<PetAbilityLine> AbilityLines(PetEntry e)
        {
            var o = new List<PetAbilityLine>();
            if (e.Owned && e.Pet != null)
            {
                foreach (var a in CF.Rows(CF.G(e.Pet, "abilities")))
                {
                    string cd = CF.N(a, "cooldown") > 0 ? Loc.T(" (every {0} s at most)", CF.I(a, "cooldown")) : "";
                    string kind = CF.T(a, "kind") == "combat" ? "combat" : "utility";
                    bool unlocked = CF.B(a, "unlocked");
                    o.Add(new PetAbilityLine { Title = string.Format("{0}  [{1}]", CF.T(a, "name", "?"), kind), Text = CF.T(a, "desc") + cd, Locked = !unlocked, LockText = unlocked ? null : Loc.T("Unlocks at pet level {0}.", CF.I(a, "unlockAt")) });
                }
            }
            else
            {
                int i = 0;
                foreach (var n in e.Abilities)
                {
                    i++;
                    o.Add(new PetAbilityLine { Title = CF.Str(n), Text = i == 1 ? Loc.T("From level 1.") : Loc.T("From level {0}.", CF.I(State, "secondAt")), Locked = true });
                }
            }
            return o;
        }

        public string StatusText()
        {
            if (State == null) return "";
            var parts = new List<string>();
            var cd = CF.M(State, "cooldowns");
            if (CF.N(cd, "death") > 0) parts.Add(Loc.T("Your pet is recovering from your death: {0} s.", CF.I(cd, "death")));
            if (CF.G(State, "active") != null)
            {
                if (CF.G(State, "rest") is string rest) parts.Add(rest);
                else if (CF.B(State, "out")) parts.Add(Loc.T("Your pet is with you."));
            }
            else parts.Add(Loc.T("No pet is out."));
            if (CF.G(State, "zone") is string zone)
            {
                string z = zone.StartsWith("utility", StringComparison.Ordinal) ? "utility abilities only" + zone.Substring(7) : zone.StartsWith("banned", StringComparison.Ordinal) ? "no pets" + zone.Substring(6) : zone;
                parts.Add(Loc.T("Here: {0}", z));
            }
            if (CF.N(cd, "summon") > 0) parts.Add(Loc.T("Call again in {0} s.", CF.I(cd, "summon")));
            return string.Join("  ", parts);
        }

        public PetButtons Buttons(PetEntry e)
        {
            bool active = e != null && CF.G(State, "active") is string a && a == e.Key;
            return new PetButtons { Summon = e != null && e.Owned && !active, Dismiss = e != null && e.Owned && active, Rename = e != null && e.Owned };
        }

        /// <summary>A name for the rename packet: trimmed, null when empty.</summary>
        public static string CleanName(string text)
        {
            text = (text ?? "").Trim();
            return text.Length == 0 ? null : text;
        }

        public static bool ApplyXp(object state, object data)
        {
            foreach (var p in CF.Rows(CF.G(state, "pets")))
                if (CF.Str(CF.G(p, "species")) == CF.Str(CF.G(data, "species")))
                {
                    foreach (string k in new[] { "level", "xp", "into", "need", "pct" }) p[k] = CF.G(data, k);
                    return true;
                }
            return false;
        }
    }
}
