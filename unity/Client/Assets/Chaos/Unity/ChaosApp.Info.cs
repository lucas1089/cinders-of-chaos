// The app side of the info and help windows (O433 phase 5, track Q): the window list, the static data store (Codex, How it works, Help search), the first-open
// How it works card, and the small calls the windows make (open a Codex entry, put a line in the chat input).
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>The static data of the info windows, read once from Resources (unity/tools/gen_info_data.lua writes the JSON files).</summary>
    public static class InfoStore
    {
        static CodexData codex;
        static HowItWorks how;
        static HelpIndex help;

        static string Read(string name)
        {
            using var _slow = SlowCalls.Scope("InfoStore.Read " + name, "load");
            var asset = Resources.Load<TextAsset>(name);
            return asset != null ? asset.text : "";
        }

        // the three loads are timed whole: the parse of the 670 KB Codex is the part of them that is not Resources.Load
        public static CodexData Codex { get { if (codex == null) { using (SlowCalls.Scope("InfoStore.Codex (read and parse)", "load")) codex = CodexData.Load(Read("Codex")); } return codex; } }
        public static HowItWorks How { get { if (how == null) { using (SlowCalls.Scope("InfoStore.How (read and parse)", "load")) how = HowItWorks.Load(Read("HowItWorks")); } return how; } }

        public static HelpIndex Help
        {
            get
            {
                if (help == null) { using (SlowCalls.Scope("InfoStore.Help (build the index)", "load")) help = HelpSearch.Build(How, Json.TryParse(Read("HelpSearch")), Codex); }
                return help;
            }
        }
    }

    public sealed partial class ChaosApp
    {
        /// <summary>The info and help windows, added by MakeWindows.</summary>
        void AddInfoWindows()
        {
            windows.Add(new DpsMeterWindow());
            windows.Add(new CodexWindow());
            windows.Add(new HelpSearchWindow());
            windows.Add(new HowItWorksWindow());
            windows.Add(new ProficiencyWindow());
            windows.Add(new HelperHudWindow());
        }

        /// <summary>Opens the Codex on an entry (a link of the crafting bench, an answer of the help search).</summary>
        public bool OpenCodex(string id)
        {
            var w = FindWindow<CodexWindow>();
            if (w == null) return false;
            return w.OpenEntry(id);
        }

        /// <summary>Opens the How it works card of a feature (true when there is one).</summary>
        public bool ShowHow(string key)
        {
            var w = FindWindow<HowItWorksWindow>();
            return w != null && w.Show(key);
        }

        /// <summary>Writes a line into the chat input (the player decides whether to send it).</summary>
        public void PutInChat(string text)
        {
            chatInput = text ?? "";
            GUI.FocusControl("chatInput");
        }

        readonly Dictionary<GameWindow, bool> howWasOpen = new Dictionary<GameWindow, bool>();

        /// <summary>First open (owner request 2026-11-03): a feature window opens its card by itself the first time a character sees it.</summary>
        internal void HowCheck(HowItWorksWindow how)
        {
            foreach (var win in windows)
            {
                bool was;
                howWasOpen.TryGetValue(win, out was);
                howWasOpen[win] = win.Open;
                if (!win.Open || was || win == how) continue;
                string key = win.HowKey;
                if (key != null) how.FirstOpen(this, key);
            }
        }
    }
}
