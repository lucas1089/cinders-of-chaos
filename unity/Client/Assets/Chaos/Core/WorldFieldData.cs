// Timed fields of the tile overlays (client game_tileoverlays fielddata.lua, made from items.xml and items.otb by client/tools/gen_field_timers.py):
// client item id -> milliseconds until the field is gone, and its name. Copied from the Lua table; unity/tools/ has no generator for it.
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class FieldData
    {
        public static readonly Dictionary<int, KeyValuePair<int, string>> Fields = new Dictionary<int, KeyValuePair<int, string>>
        {
            { 105, new KeyValuePair<int, string>(120000, "poison gas") },
            { 2118, new KeyValuePair<int, string>(360000, "fire") },
            { 2119, new KeyValuePair<int, string>(240000, "fire") },
            { 2120, new KeyValuePair<int, string>(120000, "fire") },
            { 2122, new KeyValuePair<int, string>(120000, "energy field") },
            { 2128, new KeyValuePair<int, string>(20000, "magic wall") },
            { 2129, new KeyValuePair<int, string>(20000, "magic wall") },
            { 2130, new KeyValuePair<int, string>(45000, "rush wood") },
            { 2132, new KeyValuePair<int, string>(240000, "fire") },
            { 2133, new KeyValuePair<int, string>(120000, "fire") },
            { 2134, new KeyValuePair<int, string>(120000, "poison gas") },
            { 2135, new KeyValuePair<int, string>(120000, "energy field") },
            { 10181, new KeyValuePair<int, string>(20000, "magic wall") },
            { 10182, new KeyValuePair<int, string>(45000, "rush wood") },
            { 21465, new KeyValuePair<int, string>(360000, "yellow flame") },
        };
    }
}
