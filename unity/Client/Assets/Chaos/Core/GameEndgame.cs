// Endgame part of GameSession (track L): the Endgame object (Core/Endgame.cs) and its first requests, a moment after the login.
using System;

namespace Chaos.Core
{
    public sealed partial class GameSession
    {
        /// <summary>The endgame activities: tower, dungeons, raid, descent, atlases, invasions, siege, arena, battleground, Marches, bounty board.</summary>
        public Endgame Endgame { get; private set; }

        /// <summary>Called by the constructor, after Ext exists.</summary>
        void InitEndgame()
        {
            Endgame = new Endgame(Ext, () => Now, () => (DateTime.UtcNow - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds);
        }

        /// <summary>Called by Poll: the first requests of the modules (the main client asks on game start; Unity waits like the other tracks).</summary>
        void EndgamePoll()
        {
            if (enteredAt >= 0 && Now - enteredAt > 2200) Endgame.Start();
        }
    }
}
