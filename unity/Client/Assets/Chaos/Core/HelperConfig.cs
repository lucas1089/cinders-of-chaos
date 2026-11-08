// The helper's saved settings, one set per character (the Unity side keeps the JSON text in PlayerPrefs). A port of the shape of
// game_helper/helper_config.lua, reduced to what the Unity helper does: three healing rows, three potion rows, the mana training row,
// Auto Haste, the five-slot spell rotation (the magic shooter) with one profile, Auto Target and its mode A..H.
// Every number is clamped and every wrong type falls back to its default, so a hand-edited text cannot drive the casts out of range.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class HelperHealRow { public int Id, Percent; }
    public sealed class HelperPotionRow { public int Id, Percent, Priority = 1; }
    public sealed class HelperTrainRow { public int Id, Percent = 100; public bool Enabled; }
    public sealed class HelperHasteRow { public int Id; public bool Enabled, SafeCast; }
    public sealed class HelperSlot { public int Id, Percent, Creatures = 1, Priority = 1; public bool ForceCast, SelfCast; }

    public sealed class HelperConfig
    {
        public const int Version = 1, HealRows = 3, PotionRows = 3, Slots = 5, CreaturesMax = 8, IdMax = 1000000, RuneRows = 3, RuneHealRows = 2;
        public static readonly int[] TrainingPercents = { 50, 60, 70, 80, 90, 100 };

        /// <summary>The master switch: off, the helper does nothing (it never changes a setting by pausing).</summary>
        public bool Enabled;
        public bool MagicShooter, AutoTarget, AutoTurn = true;
        public int AutoTargetMode = HelperLogic.ModeDefault;
        public readonly List<HelperHealRow> Heals = new List<HelperHealRow>();
        public readonly List<HelperPotionRow> Potions = new List<HelperPotionRow>();
        public HelperTrainRow Training = new HelperTrainRow();
        public HelperHasteRow Haste = new HelperHasteRow();
        public readonly List<HelperSlot> Shooter = new List<HelperSlot>();
        /// <summary>The spell ids the Auto setup button wrote last (so a later click knows the rotation is still its own).</summary>
        public readonly List<int> AutoMarker = new List<int>();
        // track Q extras: healing runes on yourself (2 rows), attack runes of the selected profile (3 rows), party and friend heals, food, the Support
        // section, the bot HUD, and the named shooter presets (the live Shooter / RuneAttack / AutoTargetMode are the selected one's)
        public readonly List<HelperRuneHealRow> RuneHeal = new List<HelperRuneHealRow>();
        public readonly List<HelperRuneRow> RuneAttack = new List<HelperRuneRow>();
        public HelperAllies Allies = new HelperAllies();
        public bool AutoEat;
        public HelperSupportConfig Support = new HelperSupportConfig();
        public HelperHudSettings Hud = new HelperHudSettings();
        public readonly Dictionary<string, HelperProfile> Profiles = new Dictionary<string, HelperProfile>();
        public string SelectedProfile = "Default";

        public HelperConfig()
        {
            for (int i = 0; i < HealRows; i++) Heals.Add(new HelperHealRow());
            for (int i = 0; i < PotionRows; i++) Potions.Add(new HelperPotionRow());
            for (int i = 0; i < Slots; i++) Shooter.Add(new HelperSlot { Priority = i + 1 });
            int[] healDefaults = { 60, 40 };
            for (int i = 0; i < RuneHealRows; i++) RuneHeal.Add(new HelperRuneHealRow { Percent = healDefaults[i] });
            for (int i = 0; i < RuneRows; i++) RuneAttack.Add(new HelperRuneRow { Priority = i + 1 });
            Profiles["Default"] = new HelperProfile();
        }

        // ------------------------------------------------------------------------------------ shooter profiles
        /// <summary>Stores the live slots, rune rows and Auto Target mode in the selected profile.</summary>
        public void SaveLive()
        {
            var p = new HelperProfile { AutoTargetMode = AutoTargetMode };
            for (int i = 0; i < Slots; i++) p.Slots[i] = CopySlot(Shooter[i]);
            for (int i = 0; i < RuneRows; i++) p.Runes[i] = CopyRune(RuneAttack[i]);
            Profiles[SelectedProfile] = p;
        }

        static HelperSlot CopySlot(HelperSlot s) => new HelperSlot { Id = s.Id, Percent = s.Percent, Creatures = s.Creatures, Priority = s.Priority, ForceCast = s.ForceCast, SelfCast = s.SelfCast };
        static HelperRuneRow CopyRune(HelperRuneRow r) => new HelperRuneRow { Id = r.Id, Creatures = r.Creatures, HpMin = r.HpMin, HpMax = r.HpMax, Priority = r.Priority };

        static HelperProfile CopyOf(HelperProfile p)
        {
            var o = new HelperProfile { AutoTargetMode = p.AutoTargetMode };
            for (int i = 0; i < Slots; i++) o.Slots[i] = CopySlot(p.Slots[i]);
            for (int i = 0; i < RuneRows; i++) o.Runes[i] = CopyRune(p.Runes[i]);
            return o;
        }

        void LoadLive(HelperProfile p)
        {
            for (int i = 0; i < Slots; i++) Shooter[i] = CopySlot(p.Slots[i]);
            for (int i = 0; i < RuneRows; i++) RuneAttack[i] = CopyRune(p.Runes[i]);
            AutoTargetMode = p.AutoTargetMode;
        }

        /// <summary>Switches to a stored profile (the live one is kept first). False for an unknown name.</summary>
        public bool SelectProfile(string name)
        {
            if (!Profiles.ContainsKey(name)) return false;
            SaveLive();
            SelectedProfile = name;
            LoadLive(Profiles[name]);
            return true;
        }

        /// <summary>A new empty profile (copy: of the live one). Returns the problem text, or null when it was made and selected.</summary>
        public string AddProfile(string name, bool copy)
        {
            string why = HelperProfiles.NameProblem(name, n => Profiles.ContainsKey(n));
            if (why == null && Profiles.Count >= HelperProfiles.Max) why = "There are too many presets.";
            if (why != null) return why;
            SaveLive();
            Profiles[name] = copy ? CopyOf(Profiles[SelectedProfile]) : new HelperProfile();
            SelectProfile(name);
            return null;
        }

        public string RenameProfile(string name)
        {
            string old = SelectedProfile;
            string why = HelperProfiles.NameProblem(name, n => Profiles.ContainsKey(n) && n != old);
            if (why != null) return why;
            if (name == old) return null;
            SaveLive();
            Profiles[name] = Profiles[old];
            Profiles.Remove(old);
            SelectedProfile = name;
            return null;
        }

        /// <summary>Deletes the selected profile and selects the first one left. False when it is the only one.</summary>
        public bool DeleteProfile()
        {
            if (Profiles.Count <= 1) return false;
            Profiles.Remove(SelectedProfile);
            string next = HelperProfiles.Names(this)[0];
            SelectedProfile = next;
            LoadLive(Profiles[next]);
            return true;
        }

        public static int Clamp(double v, int lo, int hi, int fallback)
        {
            if (double.IsNaN(v) || double.IsInfinity(v)) return fallback;
            int n = (int)Math.Floor(v);
            return n < lo ? lo : n > hi ? hi : n;
        }

        static int Int(object o, string key, int lo, int hi, int fallback)
        {
            var v = Json.Get(o, key);
            return v is double d ? Clamp(d, lo, hi, fallback) : fallback;
        }

        static bool Bool(object o, string key, bool fallback) => Json.Get(o, key) is bool b ? b : fallback;

        // ------------------------------------------------------------------------------------ json
        public string ToJson()
        {
            var heals = new List<object>();
            foreach (var h in Heals) heals.Add(new Dictionary<string, object> { { "id", h.Id }, { "percent", h.Percent } });
            var potions = new List<object>();
            foreach (var p in Potions) potions.Add(new Dictionary<string, object> { { "id", p.Id }, { "percent", p.Percent }, { "priority", p.Priority } });
            var slots = new List<object>();
            foreach (var s in Shooter)
                slots.Add(new Dictionary<string, object> { { "id", s.Id }, { "percent", s.Percent }, { "creatures", s.Creatures }, { "priority", s.Priority },
                    { "forceCast", s.ForceCast }, { "selfCast", s.SelfCast } });
            var root = new Dictionary<string, object>
            {
                { "version", Version }, { "enabled", Enabled }, { "magicShooter", MagicShooter }, { "autoTarget", AutoTarget }, { "autoTurn", AutoTurn },
                { "autoTargetMode", AutoTargetMode }, { "heals", heals }, { "potions", potions }, { "slots", slots },
                { "training", new Dictionary<string, object> { { "id", Training.Id }, { "percent", Training.Percent }, { "enabled", Training.Enabled } } },
                { "haste", new Dictionary<string, object> { { "id", Haste.Id }, { "enabled", Haste.Enabled }, { "safecast", Haste.SafeCast } } },
                { "autoMarker", new List<int>(AutoMarker) },
                { "autoEat", AutoEat }, { "runeHeal", RuneHealJson() }, { "runes", RunesJson(RuneAttack) }, { "allies", AlliesJson() }, { "support", SupportJson() },
                { "hud", new Dictionary<string, object> { { "enabled", Hud.Enabled }, { "size", Hud.Size }, { "showTargeting", Hud.ShowTargeting }, { "showHaste", Hud.ShowHaste },
                    { "showPlayer", Hud.ShowPlayer }, { "showHealing", Hud.ShowHealing } } },
                { "profile", SelectedProfile }, { "profiles", ProfilesJson() },
            };
            return Json.Serialize(root);
        }

        List<object> RuneHealJson()
        {
            var o = new List<object>();
            foreach (var r in RuneHeal) o.Add(new Dictionary<string, object> { { "id", r.Id }, { "percent", r.Percent } });
            return o;
        }

        static List<object> RunesJson(IList<HelperRuneRow> rows)
        {
            var o = new List<object>();
            foreach (var r in rows) o.Add(new Dictionary<string, object> { { "id", r.Id }, { "creatures", r.Creatures }, { "hpMin", r.HpMin }, { "hpMax", r.HpMax }, { "priority", r.Priority } });
            return o;
        }

        static List<object> SlotsJson(IList<HelperSlot> slots)
        {
            var o = new List<object>();
            foreach (var s in slots)
                o.Add(new Dictionary<string, object> { { "id", s.Id }, { "percent", s.Percent }, { "creatures", s.Creatures }, { "priority", s.Priority }, { "forceCast", s.ForceCast }, { "selfCast", s.SelfCast } });
            return o;
        }

        Dictionary<string, object> AlliesJson()
        {
            var names = new List<object>();
            foreach (var n in Allies.FriendNames) names.Add(n);
            return new Dictionary<string, object>
            {
                { "party", new Dictionary<string, object> { { "enabled", Allies.PartyEnabled }, { "percent", Allies.PartyPercent } } },
                { "friends", new Dictionary<string, object> { { "enabled", Allies.FriendsEnabled }, { "percent", Allies.FriendsPercent }, { "names", names } } },
                { "spell", Allies.Spell }, { "group", new Dictionary<string, object> { { "id", Allies.GroupId }, { "count", Allies.GroupCount } } },
                { "rune", new Dictionary<string, object> { { "id", Allies.RuneId } } },
            };
        }

        Dictionary<string, object> SupportJson()
        {
            var slots = new List<object>();
            foreach (var s in Support.Slots) slots.Add(new Dictionary<string, object> { { "id", s.Id }, { "enabled", s.Enabled } });
            return new Dictionary<string, object> { { "enabled", Support.Enabled }, { "reserve", Support.Reserve }, { "slots", slots } };
        }

        Dictionary<string, object> ProfilesJson()
        {
            var o = new Dictionary<string, object>();
            foreach (var kv in Profiles)
            {
                if (kv.Key == SelectedProfile) continue;   // the selected one is the live values above
                var p = kv.Value;
                o[kv.Key] = new Dictionary<string, object> { { "slots", SlotsJson(p.Slots) }, { "runes", RunesJson(p.Runes) }, { "autoTargetMode", p.AutoTargetMode } };
            }
            return o;
        }

        /// <summary>Reads saved text; anything unreadable gives the defaults.</summary>
        public static HelperConfig FromJson(string text)
        {
            var c = new HelperConfig();
            object root = string.IsNullOrEmpty(text) ? null : Json.TryParse(text);
            if (!(root is Dictionary<string, object>)) return c;
            c.Enabled = Bool(root, "enabled", false);
            c.MagicShooter = Bool(root, "magicShooter", false);
            c.AutoTarget = Bool(root, "autoTarget", false);
            c.AutoTurn = Bool(root, "autoTurn", true);
            c.AutoTargetMode = Int(root, "autoTargetMode", 1, HelperLogic.ModeMax, HelperLogic.ModeDefault);
            var heals = Json.List(root, "heals");
            for (int i = 0; i < HealRows && i < heals.Count; i++)
            {
                c.Heals[i].Id = Int(heals[i], "id", 0, IdMax, 0);
                c.Heals[i].Percent = Int(heals[i], "percent", 0, 99, 0);
            }
            var potions = Json.List(root, "potions");
            for (int i = 0; i < PotionRows && i < potions.Count; i++)
            {
                c.Potions[i].Id = Int(potions[i], "id", 0, IdMax, 0);
                c.Potions[i].Percent = Int(potions[i], "percent", 0, 99, 0);
                c.Potions[i].Priority = Int(potions[i], "priority", 1, 2, 1);
            }
            var slots = Json.List(root, "slots");
            for (int i = 0; i < Slots && i < slots.Count; i++)
            {
                var s = c.Shooter[i];
                s.Id = Int(slots[i], "id", 0, IdMax, 0);
                s.Percent = Int(slots[i], "percent", 0, 99, 0);
                s.Creatures = Int(slots[i], "creatures", 1, CreaturesMax, 1);
                s.Priority = Int(slots[i], "priority", 1, Slots, i + 1);
                s.ForceCast = Bool(slots[i], "forceCast", false);
                s.SelfCast = Bool(slots[i], "selfCast", false);
            }
            var t = Json.Get(root, "training");
            c.Training.Id = Int(t, "id", 0, IdMax, 0);
            c.Training.Percent = Int(t, "percent", 50, 100, 100);
            c.Training.Enabled = Bool(t, "enabled", false);
            var h = Json.Get(root, "haste");
            c.Haste.Id = Int(h, "id", 0, IdMax, 0);
            c.Haste.Enabled = Bool(h, "enabled", false);
            c.Haste.SafeCast = Bool(h, "safecast", false);
            foreach (object o in Json.List(root, "autoMarker")) if (o is double d) c.AutoMarker.Add(Clamp(d, 0, IdMax, 0));
            c.ReadExtras(root);
            return c;
        }

        static HelperSlot ReadSlot(object o, int i) => new HelperSlot
        {
            Id = Int(o, "id", 0, IdMax, 0), Percent = Int(o, "percent", 0, 99, 0), Creatures = Int(o, "creatures", 1, CreaturesMax, 1), Priority = Int(o, "priority", 1, Slots, i + 1),
            ForceCast = Bool(o, "forceCast", false), SelfCast = Bool(o, "selfCast", false),
        };

        static HelperRuneRow ReadRune(object o, int i) => new HelperRuneRow
        {
            Id = Int(o, "id", 0, IdMax, 0), Creatures = Int(o, "creatures", 1, CreaturesMax, 1), HpMin = Int(o, "hpMin", 0, 100, 0), HpMax = Int(o, "hpMax", 0, 100, 0),
            Priority = Int(o, "priority", 1, RuneRows * 2, i + 1),
        };

        void ReadExtras(object root)
        {
            AutoEat = Bool(root, "autoEat", false);
            var rh = Json.List(root, "runeHeal");
            int[] healDefaults = { 60, 40 };
            for (int i = 0; i < RuneHealRows && i < rh.Count; i++)
            {
                RuneHeal[i].Id = Int(rh[i], "id", 0, IdMax, 0);
                RuneHeal[i].Percent = Int(rh[i], "percent", 1, 99, healDefaults[i]);
            }
            var runes = Json.List(root, "runes");
            for (int i = 0; i < RuneRows && i < runes.Count; i++) RuneAttack[i] = ReadRune(runes[i], i);
            var a = Json.Get(root, "allies");
            if (a is Dictionary<string, object>)
            {
                var party = Json.Get(a, "party"); var fr = Json.Get(a, "friends");
                Allies.PartyEnabled = Bool(party, "enabled", false); Allies.PartyPercent = Int(party, "percent", 1, 99, 70);
                Allies.FriendsEnabled = Bool(fr, "enabled", false); Allies.FriendsPercent = Int(fr, "percent", 1, 99, 70);
                var seen = new HashSet<string>();
                var names = Json.List(fr, "names");
                for (int i = 0; i < HelperAllies.Names; i++)
                {
                    string n = i < names.Count && names[i] is string ns ? HelperAlly.CleanName(ns) : null;
                    if (n != null && seen.Add(n.ToLowerInvariant())) Allies.FriendNames[i] = n; else Allies.FriendNames[i] = "";
                }
                Allies.Spell = Int(a, "spell", 0, IdMax, 0);
                var g = Json.Get(a, "group");
                Allies.GroupId = Int(g, "id", 0, IdMax, 0); Allies.GroupCount = Int(g, "count", 1, HelperAllies.GroupCountMax, 2);
                Allies.RuneId = Int(Json.Get(a, "rune"), "id", 0, IdMax, 0);
            }
            var sup = Json.Get(root, "support");
            if (sup is Dictionary<string, object>)
            {
                Support.Enabled = Bool(sup, "enabled", true);
                int r = Int(sup, "reserve", 0, 100, HelperSupport.DefaultReserve);
                Support.Reserve = Array.IndexOf(HelperSupport.Reserves, r) >= 0 ? r : HelperSupport.DefaultReserve;
                var seen = new HashSet<int>();
                foreach (object s in Json.List(sup, "slots"))
                {
                    int id = Int(s, "id", 0, IdMax, 0);
                    if (id > 0 && seen.Add(id) && Support.Slots.Count < HelperSupport.SupportMax) Support.Slots.Add(new SupportSlot { Id = id, Enabled = Bool(s, "enabled", true) });
                }
            }
            var hud = Json.Get(root, "hud");
            if (hud is Dictionary<string, object>)
            {
                Hud.Enabled = Bool(hud, "enabled", false);
                string size = Json.Text(hud, "size");
                Hud.Size = Array.IndexOf(HelperHud.Sizes, size) >= 0 ? size : "Normal";
                Hud.ShowTargeting = Bool(hud, "showTargeting", true); Hud.ShowHaste = Bool(hud, "showHaste", true);
                Hud.ShowPlayer = Bool(hud, "showPlayer", true); Hud.ShowHealing = Bool(hud, "showHealing", true);
            }
            string sel = Json.Text(root, "profile");
            var profiles = Json.Get(root, "profiles");
            Profiles.Clear();
            if (profiles is Dictionary<string, object> pd)
                foreach (var kv in pd)
                {
                    if (HelperProfiles.NameProblem(kv.Key, null) != null || Profiles.Count >= HelperProfiles.Max - 1) continue;
                    var p = new HelperProfile { AutoTargetMode = Int(kv.Value, "autoTargetMode", 1, HelperLogic.ModeMax, HelperLogic.ModeDefault) };
                    var sl = Json.List(kv.Value, "slots");
                    for (int i = 0; i < Slots && i < sl.Count; i++) p.Slots[i] = ReadSlot(sl[i], i);
                    var rl = Json.List(kv.Value, "runes");
                    for (int i = 0; i < RuneRows && i < rl.Count; i++) p.Runes[i] = ReadRune(rl[i], i);
                    Profiles[kv.Key] = p;
                }
            SelectedProfile = HelperProfiles.NameProblem(sel, null) == null ? sel : "Default";
            SaveLive();   // the live values are the selected profile's
        }

        public HelperConfig Copy() => FromJson(ToJson());

        /// <summary>The PlayerPrefs key of a character's helper settings.</summary>
        public static string PrefsKey(string world, string character) => "chaos.helper." + (string.IsNullOrEmpty(world) ? "-" : world) + "/" + (character ?? "").ToLowerInvariant();
    }
}
