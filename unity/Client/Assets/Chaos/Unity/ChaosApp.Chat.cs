// Chat panel with tabs, floating speech over creatures and the death window. The model is Core/Chat.cs (ChatModel,
// filled by GameParser); this file only draws it. Keys while the chat line has focus: Enter sends, Escape leaves the line,
// Tab / Shift+Tab switch tabs, Ctrl+O the channel list, Ctrl+E closes the tab (the windows keep those keys otherwise).
// Right-click on a tab closes it. Private message: "*name* text", or the "Message to" field of the channel list.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        GUIStyle bubbleStyle;
        ChatLine chatLastLine;
        ChatTab chatLastTab;
        const string FightPref = "chaos.fight";

        static Color Rgb(uint c, float a = 1f) => new Color(((c >> 16) & 255) / 255f, ((c >> 8) & 255) / 255f, (c & 255) / 255f, a);

        /// <summary>A new session: the saved fight modes, sent at the login.</summary>
        void ChatEntered()
        {
            chatLastLine = null; chatLastTab = null;
            if (session != null) session.Modes = FightModes.Decode(PlayerPrefs.GetString(FightPref, ""));
        }

        static string TabLabel(ChatTab t)
        {
            switch (t.Kind)
            {
                case TabKind.Default: return Loc.T("Default");
                case TabKind.ServerLog: return Loc.T("Server Log");
                default: return t.Name;
            }
        }

        void ChatPanel(float w, float h, float scale)
        {
            Rect box = ChatRect(w, h);
            if (!chatOpen)
            {
                uiRects.Add(Scaled(box, scale));
                if (GUI.Button(box, Loc.T("Chat"))) chatOpen = true;
                chatFocused = false;
                return;
            }
            var m = session?.Talks;
            if (m == null) return;
            uiRects.Add(Scaled(box, scale));
            Fill(box, new Color(0.04f, 0.03f, 0.05f, 0.9f));
            if (GUI.Button(new Rect(box.xMax - 28, box.y + 4, 24, 22), "x")) { chatOpen = false; GUI.FocusControl(null); return; }
            var chans = FindWindow<ChannelsWindow>();
            if (GUI.Button(new Rect(box.xMax - 56, box.y + 4, 24, 22), "+")) chans.Open = !chans.Open;

            var e = Event.current;
            bool ctrl = e.control || e.command;
            bool enter = e.type == EventType.KeyDown && (e.keyCode == KeyCode.Return || e.keyCode == KeyCode.KeypadEnter);
            // chat keys: Tab steps the channel with the line focused, Ctrl+Tab at any time (plain Tab elsewhere is the map overlay's, as in the main client)
            if (e.type == EventType.KeyDown && e.keyCode == KeyCode.Tab && OverlayKeys.ChatTab(chatFocused, ctrl, TextEditing))
            {
                m.Step(e.shift ? -1 : 1);
                e.Use();
            }
            else if (e.type == EventType.KeyDown && chatFocused && ctrl && e.keyCode == KeyCode.O) { chans.Open = true; e.Use(); }
            else if (e.type == EventType.KeyDown && chatFocused && ctrl && e.keyCode == KeyCode.E) { session.CloseTab(m.Active); e.Use(); }
            else if (enter && chatFocused)
            {
                session.Talk(ChatSendText(chatInput));
                chatInput = "";
                GUI.FocusControl(null);
                e.Use();
            }
            else if (enter && !TextEditing && !(session.Parser.Dead)) { GUI.FocusControl("chatInput"); e.Use(); }
            else if (e.type == EventType.KeyDown && e.keyCode == KeyCode.Escape && chatFocused) { GUI.FocusControl(null); e.Use(); }

            // tabs
            int n = m.Tabs.Count;
            float stripW = box.width - 8 - 56;
            float tw = Mathf.Min(120f, stripW / n);
            for (int i = 0; i < n; i++)
            {
                var tab = m.Tabs[i];
                var r = new Rect(box.x + 4 + i * tw, box.y + 4, tw - 2, 22);
                bool act = i == m.Active;
                if (e.type == EventType.MouseDown && e.button == 1 && r.Contains(e.mousePosition) && tab.Closable)
                {
                    session.CloseTab(i);
                    e.Use();
                    break;
                }
                var old = GUI.contentColor;
                if (!act && tab.Unread > 0) GUI.contentColor = tab.Kind == TabKind.Private ? new Color(1f, 0.45f, 0.45f) : new Color(1f, 0.75f, 0.3f);
                string label = TabLabel(tab) + (tab.Unread > 0 ? " (" + tab.Unread + ")" : "");
                if (GUI.Toggle(r, act, label, GUI.skin.button) && !act) m.Select(i);
                GUI.contentColor = old;
            }

            var cur = m.Current;
            Rect list = new Rect(box.x + 4, box.y + 30, box.width - 8, box.height - 66);
            float lineW = list.width - 20, total = 0;
            var lines = cur.Lines;
            var heights = new float[lines.Count];
            for (int i = 0; i < lines.Count; i++) { heights[i] = chatStyle.CalcHeight(new GUIContent(lines[i].Stamp + " " + ChatLinksMath.Plain(lines[i].Display)), lineW); total += heights[i]; }
            var last = lines.Count > 0 ? lines[lines.Count - 1] : null;
            if ((last != chatLastLine || cur != chatLastTab) && e.type == EventType.Repaint)
            {
                chatScroll.y = Mathf.Max(0, total - list.height);
                chatLastLine = last; chatLastTab = cur;
            }
            chatScroll = GUI.BeginScrollView(list, chatScroll, new Rect(0, 0, lineW, Mathf.Max(total, list.height)));
            float y = 0;
            for (int i = 0; i < lines.Count; i++)
            {
                chatStyle.normal.textColor = Rgb(lines[i].Color);
                DrawChatLine(new Rect(0, y, lineW, heights[i]), lines[i]);   // item links in colour (ChaosApp.Social.cs)
                y += heights[i];
            }
            GUI.EndScrollView();

            GUI.SetNextControlName("chatInput");
            chatInput = GUI.TextField(new Rect(box.x + 6, box.yMax - 32, box.width - 12, 26), chatInput, 255);
            chatFocused = GUI.GetNameOfFocusedControl() == "chatInput";
            if (!chatFocused && chatInput.Length == 0)
            {
                var hint = new GUIStyle(small);
                hint.normal.textColor = new Color(1f, 1f, 1f, 0.4f);
                GUI.Label(new Rect(box.x + 10, box.yMax - 31, box.width - 20, 24), Loc.T("Press Enter to talk"), hint);
            }
        }

        /// <summary>The floating speech of one creature: the newest line nearest to it, above its name (yTop is the top of the name
        /// label, in the map group's units). Works for the classic view and the front-art live view: both feed LabelPoints.</summary>
        void DrawBubbles(Creature c, float x, float yTop)
        {
            var list = session.Talks.Bubbles.For(c.Id, session.Now);
            if (list.Count == 0) return;
            if (bubbleStyle == null)
                bubbleStyle = new GUIStyle(small) { fontSize = 13, wordWrap = true, alignment = TextAnchor.LowerCenter, fontStyle = FontStyle.Bold, clipping = TextClipping.Overflow };
            const float width = 190f;
            float y = yTop - 2;
            for (int i = list.Count - 1; i >= 0; i--)
            {
                var b = list[i];
                string text = b.Type == TalkType.Whisper ? b.Text.ToLowerInvariant() : b.Text;
                float hgt = bubbleStyle.CalcHeight(new GUIContent(text), width);
                y -= hgt;
                var r = new Rect(x - width / 2, y, width, hgt);
                float fade = Mathf.Clamp01((float)((b.Life - (session.Now - b.Born)) / 400.0));
                bubbleStyle.normal.textColor = new Color(0f, 0f, 0f, fade);
                GUI.Label(new Rect(r.x + 1, r.y + 1, r.width, r.height), text, bubbleStyle);
                bubbleStyle.normal.textColor = Rgb(b.Color, fade);
                GUI.Label(r, text, bubbleStyle);
            }
        }

        /// <summary>The death window: a modal box over the game. OK (or Enter) leaves for the character list, like the main client.</summary>
        void DeathWindow(float w, float h, float scale)
        {
            var p = session?.Parser;
            if (p == null || !p.Dead) return;
            uiRects.Add(new Rect(0, 0, UnityEngine.Screen.width, UnityEngine.Screen.height));
            Fill(new Rect(0, 0, w, h), new Color(0.25f, 0f, 0f, 0.45f));
            var box = new Rect(w / 2 - 190, h / 2 - 90, 380, 180);
            Fill(box, new Color(0.04f, 0.03f, 0.05f, 0.97f));
            Fill(new Rect(box.x, box.y, box.width, 28), new Color(0.35f, 0.08f, 0.06f, 1f));
            GUI.Label(new Rect(box.x + 10, box.y + 3, box.width - 20, 24), Loc.T("Death"), titleStyle);
            var body = new GUIStyle(small) { wordWrap = true, alignment = TextAnchor.UpperCenter };
            string text = Loc.T("You are dead.");
            if (p.DeathType == 0) text += "\n" + Loc.T("Experience and skill loss: {0}% of the normal penalty.", p.DeathPenalty);
            GUI.Label(new Rect(box.x + 16, box.y + 40, box.width - 32, 80), text, body);
            var e = Event.current;
            bool key = e.type == EventType.KeyDown && (e.keyCode == KeyCode.Return || e.keyCode == KeyCode.KeypadEnter);
            if (GUI.Button(new Rect(box.center.x - 50, box.yMax - 46, 100, 32), Loc.T("OK")) || key)
            {
                session.Logout();
                Leave(Loc.T("You died."));
            }
        }
    }
}
