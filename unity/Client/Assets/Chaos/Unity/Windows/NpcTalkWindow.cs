// NPC talk panel: the NPC channel of the main client's game_npctalk. The NPC's private lines (talk type 10, Core/NpcTrade.cs
// NpcTalkState) and what we said, quick words (hi, trade, bye, yes, no), a chip for every {keyword} of the NPC's last line,
// and a line to type to the NPC. It opens by itself when an NPC speaks to us. Texts go through Loc.T (English and pt-BR).
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class NpcTalkWindow : GameWindow
    {
        const float LineH = 20f;
        string input = "";
        Vector2 scroll;
        int seenVersion = -1;
        bool toBottom, focusInput;
        GUIStyle npcStyle, playerStyle, chipStyle;

        public override string Title => Loc.T("NPC");

        protected override Rect Place(float w, float h) => new Rect(w * 0.5f - 200f, h - 330f, 400f, 250f);

        public override void Reset()
        {
            input = "";
            seenVersion = -1;
            scroll = Vector2.zero;
        }

        public override void Tick(ChaosApp app)
        {
            var talk = app.Session?.Parser.NpcTalk;
            if (talk == null || talk.Version == seenVersion) return;
            seenVersion = talk.Version;
            toBottom = true;
            // a new line of the NPC opens the panel (a line of ours does not)
            if (talk.Lines.Count > 0 && talk.Lines[talk.Lines.Count - 1].FromNpc) Open = true;
        }

        void Say(ChaosApp app, string text)
        {
            app.Session?.SayToNpc(text);
            toBottom = true;
        }

        void Chip(ChaosApp app, ref float x, float y, string word, bool strong)
        {
            string label = Loc.T(word);
            float w = Mathf.Max(48f, chipStyle.CalcSize(new GUIContent(label)).x + 14);
            var old = GUI.color;
            if (strong) GUI.color = new Color(1f, 0.9f, 0.6f);
            if (GUI.Button(new Rect(x, y, w, 24), label, chipStyle)) Say(app, word);
            GUI.color = old;
            x += w + 4;
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var session = app.Session;
            if (session == null) return;
            var talk = session.Parser.NpcTalk;
            if (npcStyle == null)
            {
                npcStyle = new GUIStyle(app.SmallStyle) { wordWrap = true };
                npcStyle.normal.textColor = new Color(0.84f, 0.79f, 0.68f);
                playerStyle = new GUIStyle(npcStyle);
                playerStyle.normal.textColor = new Color(0.55f, 0.5f, 0.44f);
                chipStyle = new GUIStyle(GUI.skin.button) { fontSize = 11 };
            }
            var e = Event.current;
            double now = session.Now;

            // header: who we talk to
            string who = talk.Npc.Length > 0 && talk.Focused(now) ? talk.Npc : Loc.T("Nobody is talking to you.");
            GUI.Label(new Rect(inner.x + 4, inner.y, inner.width - 8, 20), who, app.SmallStyle);

            // log
            float bottomH = 30 + 28 + 28 + 4;
            var list = new Rect(inner.x + 2, inner.y + 22, inner.width - 4, inner.height - 22 - bottomH);
            float lineW = list.width - 20, total = 0;
            int n = talk.Lines.Count;
            var heights = new float[n];
            var texts = new string[n];
            for (int i = 0; i < n; i++)
            {
                var l = talk.Lines[i];
                texts[i] = l.Speaker + ": " + NpcTalkState.Plain(l.Text);
                heights[i] = Mathf.Max(LineH, (l.FromNpc ? npcStyle : playerStyle).CalcHeight(new GUIContent(texts[i]), lineW)) + 2;
                total += heights[i];
            }
            if (toBottom && e.type == EventType.Repaint) { scroll.y = Mathf.Max(0, total - list.height); toBottom = false; }
            scroll = GUI.BeginScrollView(list, scroll, new Rect(0, 0, lineW, Mathf.Max(total, list.height)));
            float y = 0;
            for (int i = 0; i < n; i++)
            {
                GUI.Label(new Rect(0, y, lineW, heights[i]), texts[i], talk.Lines[i].FromNpc ? npcStyle : playerStyle);
                y += heights[i];
            }
            GUI.EndScrollView();

            // quick words and keyword chips of the last NPC line
            float by = list.yMax + 2;
            float x = inner.x + 4;
            foreach (string word in NpcTalkState.QuickWords) Chip(app, ref x, by, word, true);
            foreach (string word in NpcTalkState.AnswerWords) Chip(app, ref x, by, word, false);
            float ky = by + 28;
            x = inner.x + 4;
            foreach (string k in talk.CurrentKeywords())
            {
                float w = Mathf.Max(34f, chipStyle.CalcSize(new GUIContent(k)).x + 12);
                if (x + w > inner.xMax - 4) break;
                if (GUI.Button(new Rect(x, ky, w, 24), k, chipStyle)) Say(app, k);
                x += w + 4;
            }

            // the line to the NPC
            bool enter = e.type == EventType.KeyDown && (e.keyCode == KeyCode.Return || e.keyCode == KeyCode.KeypadEnter);
            var box = new Rect(inner.x + 4, inner.yMax - 28, inner.width - 74, 24);
            GUI.SetNextControlName("npcInput");
            input = GUI.TextField(box, input, 255);
            bool focused = GUI.GetNameOfFocusedControl() == "npcInput";
            if (focused) app.MarkTextEditing();
            if (focusInput && e.type == EventType.Repaint) { GUI.FocusControl("npcInput"); focusInput = false; }
            bool send = GUI.Button(new Rect(box.xMax + 4, box.y, 62, 24), Loc.T("Send"));
            if (enter && focused) { send = true; e.Use(); }
            if (send && input.Trim().Length > 0)
            {
                Say(app, input);
                input = "";
                focusInput = true;
            }
        }
    }
}
