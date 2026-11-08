// Channel list: the chat channels the server offers (opcode 0xAB, asked with 0x97 when the window opens). Click a channel to
// join it (0x98; the server opens the tab). "Message to" opens a private message tab with a player (0x9A). Opens from the
// "+" button of the chat, or Ctrl+O while the chat line has focus.
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class ChannelsWindow : GameWindow
    {
        Vector2 scroll;
        string who = "";
        bool wasOpen;

        public override string Title => Loc.T("Channels");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 130, h / 2 - 160, 260, 320);
        public override void Reset() { scroll = Vector2.zero; who = ""; wasOpen = false; Open = false; }

        public override void Tick(ChaosApp app)
        {
            if (Open && !wasOpen && app.Session != null) app.Session.RequestChannels();
            wasOpen = Open;
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var m = app.Session?.Talks;
            if (m == null) return;
            var list = new Rect(inner.x, inner.y, inner.width, inner.height - 76);
            const float rowH = 26f;
            if (m.Channels.Count == 0)
            {
                GUI.Label(list, Loc.T(m.ChannelListArrived ? "No channels." : "Loading channels..."), app.SmallStyle);
            }
            else
            {
                scroll = GUI.BeginScrollView(list, scroll, new Rect(0, 0, list.width - 18, rowH * m.Channels.Count));
                for (int i = 0; i < m.Channels.Count; i++)
                {
                    var ch = m.Channels[i];
                    var tab = m.FindChannel(ch.Id);
                    var r = new Rect(0, i * rowH, list.width - 18, rowH - 2);
                    var old = GUI.contentColor;
                    if (tab != null) GUI.contentColor = new Color(0.6f, 1f, 0.6f);
                    if (GUI.Button(r, ch.Name))
                    {
                        if (tab != null) m.Select(m.Tabs.IndexOf(tab));
                        else app.Session.JoinChannel(ch.Id);
                        Open = false;
                    }
                    GUI.contentColor = old;
                }
                GUI.EndScrollView();
            }
            float y = inner.yMax - 70;
            GUI.Label(new Rect(inner.x, y, inner.width, 22), Loc.T("Message to"), app.SmallStyle);
            GUI.SetNextControlName("pmTo");
            who = GUI.TextField(new Rect(inner.x, y + 24, inner.width - 74, 26), who, 30);
            if (GUI.GetNameOfFocusedControl() == "pmTo") app.MarkTextEditing();
            var e = Event.current;
            bool enter = e.type == EventType.KeyDown && (e.keyCode == KeyCode.Return || e.keyCode == KeyCode.KeypadEnter) && GUI.GetNameOfFocusedControl() == "pmTo";
            if ((GUI.Button(new Rect(inner.xMax - 70, y + 24, 70, 26), Loc.T("Open")) || enter) && who.Trim().Length > 0)
            {
                app.Session.OpenPrivate(who);
                who = "";
                Open = false;
                if (enter) e.Use();
            }
        }
    }
}
