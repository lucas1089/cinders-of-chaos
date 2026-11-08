// Social and market glue of the app (O433 phase 4, track M): the windows (Windows/SocialWindows.cs), item links in the chat (Core/ChatLinks.cs: Shift+click an item,
// the names in colour, the tooltip of the link under the pointer), the "Inspect Player" entry of the right-click menu, the notices of the party finder.
using System.Collections.Generic;
using System.Text;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        GUIStyle chatRichStyle, chatPlainStyle;

        /// <summary>The social windows, added by MakeWindows.</summary>
        void AddSocialWindows()
        {
            windows.Add(new MarketWindow());
            windows.Add(new GuildWindow());
            windows.Add(new GuildWarWindow());
            windows.Add(new PartyFinderWindow());
            windows.Add(new GroupQueueWindow());
            windows.Add(new ReadyCheckWindow());
            windows.Add(new InspectWindow());
            windows.Add(new LeaderboardWindow());
            windows.Add(new FactionsWindow());
            windows.Add(new ConquestWindow());
        }

        /// <summary>Called when a character enters the game: the panels' callbacks into the app.</summary>
        void SocialEntered()
        {
            var s = session.Social;
            string who = (session.Parser.Talks.SelfName ?? "").ToLowerInvariant();
            string prefKey = "chaos.leaderboard.board." + (string.IsNullOrEmpty(who) ? "-" : who);
            s.PartyFinder.Notice = (text, kind) => PostLine(text);
            s.Links.Say = text => PostLine(text);
            s.Links.InsertChip = (name, token) =>
            {
                if (s.Links.AddChip(chatInput, name, token, out string why)) chatInput += "[" + name + "] ";
                else PostLine(why);
            };
            s.Leaderboard.SavedBoard = () => { try { string v = PlayerPrefs.GetString(prefKey, ""); return v.Length > 0 ? v : null; } catch { return null; } };
            s.Leaderboard.RememberBoard = key => { try { PlayerPrefs.SetString(prefKey, key); } catch { } };
            // the hall's crafting bench and other modules of the main client: say so rather than open nothing
            s.Guild.OpenModule = name => PostLine(Loc.T("That window is not available."));
        }

        /// <summary>Right-click "Inspect Player" on a player of the map (the server checks the range).</summary>
        void InspectPlayer(uint id, string name)
        {
            session?.Social?.Inspect.InspectCreature(id, name);
            var win = FindWindow<InspectWindow>();
            if (win != null) win.Open = true;
        }

        // ------------------------------------------------------------------------------------ item links in the chat
        /// <summary>Shift + click on an item of the equipment or a bag: asks the server for a link; the name goes into the chat line when it answers.
        /// True when the click was taken (also when refused with a line in the chat box).</summary>
        public bool LinkItem(Item it, Pos where)
        {
            if (session == null || it == null || !ChatLinksMath.Linkable(where)) return false;
            var links = session.Social.Links;
            var tab = session.Parser.Talks.Current;
            var ctx = ChatLinksMath.ContextOf(tab.Kind, tab.ChannelId, links.HelpAllowed, out string why);
            if (ctx == null) { PostLine(why); return true; }
            if (!ChatLinksMath.CanAdd(chatInput, links.Chips, "", new string('x', 30), out why)) { PostLine(why); return true; }
            // the server wants the slot on the page the window shows (as for the tooltip)
            var pos = where;
            if (pos.X == 0xFFFF && pos.Y >= 0x40 && session.Parser.Containers.TryGetValue((byte)(pos.Y - 0x40), out var cont))
                pos = new Pos(pos.X, pos.Y, pos.Z - cont.FirstIndex);
            links.Register(pos, it.Attr(ItemAttr.Id), ctx);
            return true;
        }

        /// <summary>What Enter sends: the chat line with its chips written out as links.</summary>
        string ChatSendText(string line) => session == null ? line : session.Social.Links.ExpandLine(line);

        static string RichText(string text) => (text ?? "").Replace("<", "<​");

        /// <summary>One chat line. A line with item links shows the names in their rarity colour and, under the pointer, the tooltip of the link.</summary>
        void DrawChatLine(Rect r, ChatLine line)
        {
            string display = line.Display;
            if (session == null || display.IndexOf('{') < 0 || ChatLinksMath.Parse(display).Count == 0) { GUI.Label(r, line.Stamp + " " + display, chatStyle); return; }
            if (chatRichStyle == null) { chatRichStyle = new GUIStyle(chatStyle) { richText = true }; chatPlainStyle = new GUIStyle(chatStyle) { richText = false }; }
            chatRichStyle.fontSize = chatStyle.fontSize; chatPlainStyle.fontSize = chatStyle.fontSize;
            string baseHex = "#" + ColorUtility.ToHtmlStringRGB(Rgb(line.Color));
            var pieces = ChatLinksMath.Pieces(display, baseHex);
            var sb = new StringBuilder();
            sb.Append("<color=").Append(baseHex).Append('>').Append(RichText(line.Stamp + " ")).Append("</color>");
            foreach (var part in pieces.Parts) sb.Append("<color=").Append(part.Value).Append('>').Append(RichText(part.Key)).Append("</color>");
            GUI.Label(r, sb.ToString(), chatRichStyle);
            var e = Event.current;
            if (e.type != EventType.Repaint || !r.Contains(e.mousePosition)) return;
            string full = line.Stamp + " " + pieces.Text;
            int idx = chatPlainStyle.GetCursorStringIndex(r, new GUIContent(full), e.mousePosition) - (line.Stamp.Length + 1);
            var range = ChatLinksMath.RangeAt(pieces.Ranges, idx);
            if (range == null) return;
            var links = session.Social.Links;
            var en = links.Lookup(range.Id);
            if (en == null) ShowTip(null, null, Loc.T("Loading..."));
            else if (en.Gone || en.Tip == null) ShowTip(null, null, Loc.T("This item link has expired."));
            else
            {
                var extra = new List<TipLine> { new TipLine { Text = ChatLinksMath.Footer(en.Owner, en.Left, links.Age(en)), Color = TipLines.Dim, Sep = true } };
                ShowTip(en.Tip, extra);
            }
        }
    }
}
