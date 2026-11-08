// Phase 7, track Z: game_bounty and game_dungeons. The creature's outfit the server sends inside a window (a contract's outfit, a dungeon's boss) as a table. Pure.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class OutfitJson
    {
        static int Pick(object t, string a, string b) => CF.G(t, a) is double ? CF.I(t, a) : CF.I(t, b);

        /// <summary>An outfit table in the spelling of the bounty board (type, head, body, legs, feet, addons) or of the dungeon list (lookType, lookTypeEx, lookHead, lookBody,
        /// lookLegs, lookFeet, lookAddons). fallbackLook is the contract's `look`, used when the table names no type. Null when nothing is to be drawn.</summary>
        public static Outfit Read(object table, double fallbackLook = 0)
        {
            int type = 0, ex = 0;
            if (table is Dictionary<string, object>)
            {
                type = Pick(table, "type", "lookType");
                ex = CF.I(table, "lookTypeEx");
            }
            if (type <= 0 && ex <= 0) type = (int)fallbackLook;
            if (type <= 0 && ex <= 0) return null;
            var o = new Outfit(type, Pick(table, "head", "lookHead"), Pick(table, "body", "lookBody"), Pick(table, "legs", "lookLegs"), Pick(table, "feet", "lookFeet"), Pick(table, "addons", "lookAddons"));
            if (type <= 0) o.LookTypeEx = ex;
            return o;
        }
    }
}
