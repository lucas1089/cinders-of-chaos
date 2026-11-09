// Phase 29 (2026-11-09): what the app forgets when a game ends (a death and OK, a closed connection, Log out), so the next login starts clean.
// ResetWindows (ChaosApp.Windows.cs, called by Leave) calls ResetSessionState. The windows reset themselves through GameWindow.Reset.
// The rule behind the list: a GameSession's clock (Now) starts at zero at each login and every object it made (parser, hud, models) is new, so anything the
// app keeps across a Leave must either be compared with the session it was made for, hold a SessionStamp, or be cleared here.
using System;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        void ResetSessionState()
        {
            // a game that ended in the middle of something must not finish it in the next one
            autoWalk.Cancel(); npcApproach.Cancel();   // a path and an NPC walk of the old position
            Crosshair.Cancel();                        // "Use with ..." waiting for a target
            split = null; splitFocus = false;          // the "Move how many?" box of an item that is gone
            modalFor = 0; textFor = 0; modalChoice = ModalWindows.NoChoice; textBuf = "";
            hoverCreature = 0; hoverTip = null; hoverExtra = null; hoverNote = null;
            // the chat line: a death while typing left the keyboard on it, and the next game then took the walking keys
            chatFocused = false; chatInput = ""; chatLastLine = null; chatLastTab = null;
            try { GUI.FocusControl(null); GUIUtility.keyboardControl = 0; } catch (Exception) { }
            // the session clock restarts: times taken on the old one must not block the new one
            beamsStamp.Reset(); monsterAskStamp.Reset(); beams.Clear();
            announceShown = null; announceSeen = -1; announceBox = false;
            Array.Clear(hotPeak, 0, hotPeak.Length);   // a cooldown running at the death would flash the slot at the next login
            hotPulse.Clear(); wingsAt.Clear();
            menuItems.Clear(); menuFrame = -10;
            ItemSlots.Cancel();
        }
    }
}
