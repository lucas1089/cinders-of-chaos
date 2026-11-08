// Phase 7, track Z: game_pvpzone. The safe exits and the Cinder Shrine of the Scorched Marches as flags on the minimap (pvpzone.lua setMarks): put on when the zone is entered,
// gone when it is left. Pure.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class PvpZoneFlags
    {
        /// <summary>The marks on this floor inside the tile box [x0, x1) x [y0, y1) of the minimap.</summary>
        public static List<PzMark> Visible(IList<PzMark> marks, int floor, int x0, int y0, int x1, int y1)
        {
            var o = new List<PzMark>();
            if (marks == null) return o;
            foreach (var m in marks) if (m.Z == floor && m.X >= x0 && m.X < x1 && m.Y >= y0 && m.Y < y1) o.Add(m);
            return o;
        }

        /// <summary>The colour of a flag: the white circle of a safe exit, the orange of the shrine.</summary>
        public static string Color(string kind) => kind == "shrine" ? "#ff8a3c" : "#f2f2f2";

        /// <summary>The tooltip of a flag: its name, else the kind.</summary>
        public static string Tip(PzMark m) => !string.IsNullOrEmpty(m.Name) ? m.Name : m.Kind == "shrine" ? Loc.T("Cinder Shrine") : Loc.T("Safe exit");
    }
}
