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
        public const int Version = 1, HealRows = 3, PotionRows = 3, Slots = 5, CreaturesMax = 8, IdMax = 1000000;
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

        public HelperConfig()
        {
            for (int i = 0; i < HealRows; i++) Heals.Add(new HelperHealRow());
            for (int i = 0; i < PotionRows; i++) Potions.Add(new HelperPotionRow());
            for (int i = 0; i < Slots; i++) Shooter.Add(new HelperSlot { Priority = i + 1 });
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
            };
            return Json.Serialize(root);
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
            return c;
        }

        public HelperConfig Copy() => FromJson(ToJson());

        /// <summary>The PlayerPrefs key of a character's helper settings.</summary>
        public static string PrefsKey(string world, string character) => "chaos.helper." + (string.IsNullOrEmpty(world) ? "-" : world) + "/" + (character ?? "").ToLowerInvariant();
    }
}
