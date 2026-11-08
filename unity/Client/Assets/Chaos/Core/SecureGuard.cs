// Secure mode held off for a match and put back after it (O433 phase 23). The arena, the battleground and the Scorched Marches need secure mode off (the servers
// end a match for a fighter who still has it on, and the base PvP rule refuses an attack on an unmarked player while the attacker has it on). The main client's
// secureOff / secureRestore (game_arena, game_battleground, game_pvpzone) turn it off at the start and back on at the end when it was on before.
// This is that rule without Unity types, so Core.Tests can run it: the Unity side (EndgameBridge, FightWindow) only calls it.
using System;

namespace Chaos.Core
{
    public sealed class SecureGuard
    {
        readonly Func<FightModes> get;
        readonly Action<FightModes> set;
        bool? before;

        public SecureGuard(Func<FightModes> getModes, Action<FightModes> setModes) { get = getModes; set = setModes; }

        /// <summary>True between Off and On: the secure mode on screen is the match's, not the player's choice.</summary>
        public bool Active => before != null;

        /// <summary>The player's own choice while a match holds the mode off (null when no match does).</summary>
        public bool? Before => before;

        /// <summary>A match began: remember the player's choice once (a second match starting inside the first keeps the first) and send secure off when it was on.</summary>
        public void Off()
        {
            var m = get();
            if (m == null) return;
            if (before == null) before = m.Secure;
            if (m.Secure) set(new FightModes { Fight = m.Fight, Chase = m.Chase, Secure = false });
        }

        /// <summary>A match ended: secure on again when it was on before and is still off. Always forgets the choice.</summary>
        public void On()
        {
            var m = get();
            if (m != null && before == true && !m.Secure) set(new FightModes { Fight = m.Fight, Chase = m.Chase, Secure = true });
            before = null;
        }

        /// <summary>A new session: nothing is held.</summary>
        public void Reset() { before = null; }

        /// <summary>The player toggled secure mode in the Fight window while a match holds it: that is their choice now, and it is what the end of the match restores.</summary>
        public void UserChose(bool secure) { if (before != null) before = secure; }

        /// <summary>The modes to save to the player's preferences after a change in the Fight window. While a match holds secure mode off the window shows off, but the
        /// preference stays what the player had (a saved off would start the next session without protection); a change of the switch itself is saved as chosen.</summary>
        public FightModes ToSave(FightModes shown, bool secureChanged)
        {
            bool secure = shown.Secure;
            if (before != null && !secureChanged) secure = before.Value;
            return new FightModes { Fight = shown.Fight, Chase = shown.Chase, Secure = secure };
        }
    }
}
