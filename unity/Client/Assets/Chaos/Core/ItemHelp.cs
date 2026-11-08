// Alt help of the item tooltip: one plain line per term on the item (a port of game_itemtooltip/itemhelp.lua, O372). The keys are the modifier
// attribute keys the server sends (m.k), lower case, without the "chaos_mod_" prefix; a key not listed falls back to its group.
// The text tables below come from itemhelp.lua; Core.Tests/ItemTipExtrasTests.cs checks the rules.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class ItemHelp
    {
        public const string Prefix = "chaos_mod_";

        static Dictionary<string, string> Mods()
        {
            return new Dictionary<string, string>
            {
                { "bossdamage", Loc.T("Damage to Elites and Bosses: more damage to elite monsters and bosses.") },
                { "dodge", Loc.T("Dodge: a chance that a hit misses you.") },
                { "reflect", Loc.T("Reflect Damage: sends a part of the damage you take back to the attacker.") },
                { "thorns", Loc.T("Thorns: a monster that hits you takes this much damage.") },
                { "monsterreduction", Loc.T("Damage Taken from Monsters: monsters hurt you less.") },
                { "block", Loc.T("Block Chance: a chance to stop a hit with your shield.") },
                { "bleedchance", Loc.T("Chance to Bleed: your hits can make the target bleed over time.") },
                { "ignitechance", Loc.T("Chance to Ignite: your hits can set the target on fire.") },
                { "poisonchance", Loc.T("Chance to Poison: your hits can poison the target.") },
                { "chillchance", Loc.T("Chance to Chill: your hits can slow the target down.") },
                { "shockchance", Loc.T("Chance to Shock: a shocked monster takes more damage from everyone.") },
                { "physpen", Loc.T("Physical Penetration: your physical hits ignore a part of the monster's resistance.") },
                { "elepen", Loc.T("Elemental Penetration: your elemental hits ignore a part of the monster's resistance.") },
                { "execute", Loc.T("Execute: a monster below this share of its health dies at once.") },
                { "dot", Loc.T("Damage over Time: bleeding, burning and poison you cause hurt more.") },
                { "attackspeed", Loc.T("Attack Speed: you attack more often.") },
                { "gearspeed", Loc.T("Attack Speed: you attack more often.") },
                { "bowspeed", Loc.T("Attack Speed: you attack more often.") },
                { "movespeed", Loc.T("Movement Speed: you walk faster.") },
                { "lifeonkill", Loc.T("Life on Kill: heals you each time you kill a monster.") },
                { "manaonkill", Loc.T("Mana on Kill: gives you mana each time you kill a monster.") },
                { "lifeonhit", Loc.T("Health on Hit: heals you a little with each hit you land.") },
                { "manaonhit", Loc.T("Mana on Hit: gives you a little mana with each hit you land.") },
                { "regen", Loc.T("Health Regeneration: you get health back every second.") },
                { "experience", Loc.T("Experience: more experience from monsters.") },
                { "goldfind", Loc.T("Gold Find: monsters drop more gold.") },
                { "itemfind", Loc.T("Item Find: monsters drop more items.") },
                { "rarityfind", Loc.T("Rarity Find: the items you find are more often rare.") },
                { "healing", Loc.T("Healing Done: your healing spells and potions heal more.") },
                { "goblinchance", Loc.T("Treasure Goblin Chance: a treasure goblin appears near you more often.") },
                { "cdr", Loc.T("Cooldown Reduction: your spells are ready again sooner.") },
                { "manacost", Loc.T("Mana Cost Reduction: your spells cost less mana.") },
                { "energyshield", Loc.T("Energy Shield: a shield that takes damage before your health and refills itself.") },
                { "energyshieldpct", Loc.T("Energy Shield: a shield that takes damage before your health and refills itself.") },
                { "esrecharge", Loc.T("Faster Energy Shield Recharge: your energy shield refills faster.") },
                { "bowdistance", Loc.T("Distance Fighting: adds to your ranged skill while you use a bow.") },
                { "bowcrit", Loc.T("Critical Strike Chance with Bows: more critical hits with a bow.") },
                { "multishot", Loc.T("Extra Projectile Chance: a chance to shoot one more arrow.") },
                { "arrowfire", Loc.T("Element damage with Bows: a part of your bow damage becomes this element.") },
                { "arrowice", Loc.T("Element damage with Bows: a part of your bow damage becomes this element.") },
                { "arrowenergy", Loc.T("Element damage with Bows: a part of your bow damage becomes this element.") },
                { "arrowearth", Loc.T("Element damage with Bows: a part of your bow damage becomes this element.") },
                { "rarity_criticalhitchance", Loc.T("Critical: a chance to hit for more; the second number is how much more.") },
                { "rarity_lifeleechchance", Loc.T("Life Leech: heals you by a part of the damage you deal.") },
                { "rarity_manaleechchance", Loc.T("Mana Leech: gives you mana from a part of the damage you deal.") },
                { "rarity_maglevelskill", Loc.T("Magic: adds magic levels, so your spells hit and heal harder.") },
                { "rarity_shieldskill", Loc.T("Shielding: adds to your shielding skill, so you block more.") },
            };
        }

        static Dictionary<string, string> Groups()
        {
            return new Dictionary<string, string>
            {
                { "absorb", Loc.T("Absorb: takes away a share of the damage of that element you take.") },
                { "skill", Loc.T("Skill bonus: adds levels to that skill, as if you trained it.") },
                { "element", Loc.T("Element damage: adds damage of that element to your hits.") },
            };
        }

        static Dictionary<string, string> Bases()
        {
            return new Dictionary<string, string>
            {
                { "attack", Loc.T("Attack: the base damage of the weapon.") },
                { "defense", Loc.T("Defense: blocks a part of the hits you take.") },
                { "armor", Loc.T("Armour: lowers the physical damage you take.") },
                { "dps", Loc.T("Estimated DPS: about how much damage per second your auto attack deals with it.") },
                { "yourinterval", Loc.T("Your Attack Interval: the seconds between your auto attacks with it.") },
            };
        }

        /// <summary>The key of a modifier as the tables know it.</summary>
        public static string Key(string k)
        {
            k = (k ?? "").ToLowerInvariant();
            return k.StartsWith(Prefix, StringComparison.Ordinal) ? k.Substring(Prefix.Length) : k;
        }

        public static string Hint() => Loc.T("Hold Alt for what each line does.");

        /// <summary>The help lines of a tooltip (no repeats, in reading order).</summary>
        public static List<string> Lines(object tip)
        {
            var outl = new List<string>();
            if (!(tip is Dictionary<string, object>)) return outl;
            Action<string> add = line => { if (line != null) outl.Add(line); };
            object unique = Json.Get(tip, "unique");
            bool uniqueTip = unique is Dictionary<string, object>;
            if (uniqueTip && Json.Get(unique, "set") != null && !(Json.Get(unique, "set") is bool sb0 && !sb0)) add(Loc.T("Set: wear more pieces of the set for extra bonuses."));
            else if (uniqueTip) add(Loc.T("Unique: a named item with fixed modifiers, often with a power of its own."));
            else if (Json.Get(tip, "rarityName") is string rn) add(Loc.T("{0}: the rarity. Rarer items roll more modifiers.", Loc.T(rn)));
            if (Json.Get(tip, "set") != null && !uniqueTip) add(Loc.T("Set: wear more pieces of the set for extra bonuses."));
            if (Json.Get(tip, "level") != null) add(Loc.T("Item Level: a higher item level can roll higher tiers."));
            object quality = Json.Get(tip, "quality");
            if (quality is Dictionary<string, object> && Json.Number(quality, "q") > 0) add(Loc.T("Quality: makes the base stats stronger."));

            var bases = Bases();
            foreach (object b in Json.List(tip, "base"))
            {
                string k = Json.Text(b, "k");
                add(k.Length > 0 && bases.TryGetValue(k, out string t) ? t : null);
            }

            int best = 0;
            bool range = false, bound = false, sides = false, implicit_ = false, power = false;
            foreach (object m in Json.List(tip, "mods"))
            {
                if (!(m is Dictionary<string, object>)) continue;
                int tier = (int)Json.Number(m, "tr");
                if (tier > 0 && tier > best) best = tier;
                if (Json.Get(m, "lo") != null && Json.Get(m, "hi") != null) range = true;
                if (Json.Get(m, "bd") != null && !(Json.Get(m, "bd") is bool bd && !bd)) bound = true;
                string sd = Json.Text(m, "sd");
                if (sd == "p" || sd == "s") sides = true;
                if (sd == "i") implicit_ = true;
                if (Json.Get(m, "pw") != null && !(Json.Get(m, "pw") is bool pw && !pw)) power = true;
            }
            if (best > 0) add(Loc.T("T{0}: the tier, T1 weak to T8 best.", best));
            if (range) add(Loc.T("[low-high]: the range this modifier can roll in."));
            if (sides) add(Loc.T("Prefixes and Suffixes: an item holds a few of each; orbs add, change or remove them."));
            if (implicit_) add(Loc.T("Corrupted implicit: an extra modifier the corruption gave."));
            if (bound) add(Loc.T("Bound: orbs do not change this modifier."));
            if (power) add(Loc.T("Power: a special effect; its line says what it does."));

            var mods = Mods();
            var groups = Groups();
            foreach (object m in Json.List(tip, "mods")) add(ModLine(m, mods, groups));

            object socks = Json.Get(tip, "sockets");
            if (socks is Dictionary<string, object> && Json.Number(socks, "count") > 0) add(Loc.T("Sockets: put gems in them for extra bonuses."));
            if (Json.Get(tip, "veil") is Dictionary<string, object>) add(Loc.T("Veiled: a hidden modifier; an Orb of Unveiling shows it."));

            var seen = new HashSet<string>();
            var list = new List<string>();
            foreach (string line in outl) if (seen.Add(line)) list.Add(line);
            return list;
        }

        static string ModLine(object m, Dictionary<string, string> mods, Dictionary<string, string> groups)
        {
            if (!(m is Dictionary<string, object>)) return null;
            if (mods.TryGetValue(Key(Json.Text(m, "k")), out string t)) return t;
            string g = Json.Text(m, "g");
            return g.Length > 0 && groups.TryGetValue(g, out string gt) ? gt : null;
        }
    }
}
