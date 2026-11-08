// The info models of a session (O433 phase 5, track Q): the DPS meter (opcode 204). The static data windows (Codex, How it works, Help search) need no session:
// they read Resources/*.json through Unity/InfoStore.cs. InitInfo is called by the GameSession constructor.
using System;

namespace Chaos.Core
{
    public sealed class InfoState
    {
        public readonly DpsMeter Dps;

        public InfoState(ExtOpcodes ext) { Dps = new DpsMeter(ext); }
    }

    public sealed partial class GameSession
    {
        /// <summary>The DPS meter and the other info models.</summary>
        public InfoState Info { get; private set; }

        void InitInfo() { Info = new InfoState(Ext); }
    }
}
