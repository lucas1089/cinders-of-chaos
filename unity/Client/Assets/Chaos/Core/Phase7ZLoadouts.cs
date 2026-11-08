// Phase 7, track Z: game_loadouts. The action bar profile of a loadout slot (loadouts.lua rememberProfile / applyProfile): saving a loadout keeps the hotkey bar as it is in a
// profile of that slot, loading the loadout puts the bar back. The main client names a base client profile; Unity has one bar, so the profile is a copy of the 12 slots. Pure,
// the store is a pair of delegates (PlayerPrefs in Unity).
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class HotbarProfiles
    {
        public const char Sep = '\u0001';
        readonly Func<string, string> get;
        readonly Action<string, string> set;

        public HotbarProfiles(Func<string, string> get, Action<string, string> set) { this.get = get; this.set = set; }

        /// <summary>The name of the profile of a loadout slot.</summary>
        public static string NameOf(int slot) => "Loadout " + slot;

        static string NameKey(string character, int slot) => "chaos.loadout.profile." + LoadoutsState.ProfileKey(character, slot);
        static string ContentKey(string character, string name) => "chaos.hotbarprofile." + (character ?? "?").ToLowerInvariant() + "." + name;

        public static string Pack(IList<string> slots) => string.Join(Sep.ToString(), slots);

        public static string[] Unpack(string packed, int count)
        {
            var o = new string[count];
            var parts = (packed ?? "").Split(Sep);
            for (int i = 0; i < count; i++) o[i] = i < parts.Length ? parts[i] : "";
            return o;
        }

        /// <summary>A loadout was saved in this slot: the bar as it is becomes its profile.</summary>
        public void Remember(string character, int slot, IList<string> bar)
        {
            if (slot <= 0 || bar == null) return;
            string name = NameOf(slot);
            set(ContentKey(character, name), Pack(bar));
            set(NameKey(character, slot), name);
        }

        /// <summary>The profile remembered for a slot, "" when none (the "Action bar:" line of the details).</summary>
        public string ProfileOf(string character, int slot)
        {
            string n = get(NameKey(character, slot)) ?? "";
            return n.Length > 0 && (get(ContentKey(character, n)) ?? "").Length > 0 ? n : "";
        }

        /// <summary>The 12 saved slot strings of the slot's profile, null when none is remembered.</summary>
        public string[] Recall(string character, int slot, int count)
        {
            string n = ProfileOf(character, slot);
            return n.Length == 0 ? null : Unpack(get(ContentKey(character, n)), count);
        }

        /// <summary>A loadout slot was deleted: its profile goes too.</summary>
        public void Forget(string character, int slot)
        {
            string n = get(NameKey(character, slot)) ?? "";
            if (n.Length == 0) return;
            set(ContentKey(character, n), "");
            set(NameKey(character, slot), "");
        }
    }
}
