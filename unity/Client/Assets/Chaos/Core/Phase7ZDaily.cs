// Phase 7, track Z: game_daily. The login order (the window waits while a modal dialog or another login window is on screen, daily.lua waitForOtherWindows) and the walk-away
// rule (walking more than 3 tiles from where the window opened closes it and tells the server). Pure.
using System;

namespace Chaos.Core
{
    public static class DailyGate
    {
        public const double WaitMs = 500;

        /// <summary>The server opens the window by itself at the login ("Login": 1): then it waits for a modal dialog (the welcome, the tutorial) and the other windows that open at
        /// the login (the patch notes). Any other open shows at once.</summary>
        public static bool ShouldWait(int login, bool modalOpen, bool otherLoginWindowOpen) => login == 1 && (modalOpen || otherLoginWindowOpen);
    }

    /// <summary>The anchor of the open window. A jump (the placement at the login, a teleport, a floor change) moves the anchor, a walk more than 3 tiles away closes the window.</summary>
    public sealed class DailyAnchor
    {
        public const int AwayTiles = 3;
        Pos anchor;
        bool has;

        public bool Has => has;
        public void Set(Pos p) { anchor = p; has = true; }
        public void Clear() { has = false; }

        /// <summary>The player moved from oldPos to newPos: true when the window must close. After a close the anchor is gone.</summary>
        public bool Moved(Pos oldPos, Pos newPos, bool windowOpen)
        {
            if (!has) return false;
            bool jump = oldPos.Z != newPos.Z || Math.Max(Math.Abs(oldPos.X - newPos.X), Math.Abs(oldPos.Y - newPos.Y)) > 1;
            if (jump) { anchor = newPos; return false; }
            if (windowOpen && newPos.Z == anchor.Z && Math.Max(Math.Abs(anchor.X - newPos.X), Math.Abs(anchor.Y - newPos.Y)) > AwayTiles)
            {
                has = false;
                return true;
            }
            return false;
        }
    }
}
