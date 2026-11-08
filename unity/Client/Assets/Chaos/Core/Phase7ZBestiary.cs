// Phase 7, track Z: game_bestiary, the on-screen task tracker (bestiary.lua renderTracker / toggleTracker / foldTracker). Pure.
using System.Collections.Generic;

namespace Chaos.Core
{
    /// <summary>The task tracker HUD of the main client: the active kill tasks and bounty contracts, one line and a thin bar each. It is on by default; an empty tracker stays out of
    /// the way unless the menu just turned it on (it then shows a hint). A click on the title folds it.</summary>
    public sealed class TaskTrackerState
    {
        public const string PrefsEnabled = "chaos.bestiary.tracker", PrefsFolded = "chaos.bestiary.tracker.folded";

        public bool Enabled = true, Folded, Opened;

        /// <summary>Is the tracker drawn: on, and a task to show or opened from the menu.</summary>
        public bool Visible(int rows) => Enabled && (rows > 0 || Opened);

        public string Title(int rows) => Folded ? Loc.T("Tasks ({0}) +", rows) : Loc.T("Tasks");

        public const string EmptyHint = "No task yet: Hunt > Kill Tasks or Adventure > Bounty Board.";

        /// <summary>The menu entry: shown and open it hides (true when it turned off), else it opens and turns on.</summary>
        public bool Toggle(int rows)
        {
            if (Visible(rows)) { Opened = false; Enabled = false; return true; }
            Opened = true; Enabled = true;
            return false;
        }

        public void Fold() { Folded = !Folded; }

        /// <summary>"B" for a bounty contract, "T" for a kill task.</summary>
        public static string Kind(object row) => CF.T(row, "k") == "bounty" ? "B" : "T";

        public static string KindColor(object row) => CF.T(row, "k") == "bounty" ? "#e03a1e" : "#e8b84a";

        public static string BarColor(object row) => CF.T(row, "k") == "bounty" ? "#8a1010" : "#a3844b";

        /// <summary>The rows that are tables (the tracker packet may carry junk).</summary>
        public static List<Dictionary<string, object>> Rows(IEnumerable<object> rows)
        {
            var o = new List<Dictionary<string, object>>();
            if (rows != null) foreach (var r in rows) if (r is Dictionary<string, object> d) o.Add(d);
            return o;
        }
    }
}
