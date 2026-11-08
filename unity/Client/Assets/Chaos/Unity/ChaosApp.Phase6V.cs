// Phase 6, track V: the P0 user experience of the main client that Unity lacked.
//   * Login screen: the news bar (event schedule, boosted creature and boss, players online) from the website's login services, and the medallions and crests
//     around the sign-in panel (Core/LoginExtras.cs).
//   * Character select: the website's account API adds wings, aura and shader, the last login line, the season tag and the slots header; a class badge per card.
//   * Auto-walk to a clicked tile (a quick click: the path is found here, 0x64 goes out, Escape sends 0xBE, any manual step ends it; a held button still walks towards the pointer).
//   * NPC: right click on an NPC offers Talk (walks up when out of its talk radius, then says hi) and a speech bubble over the NPC shows its latest reply and keyword chips.
//   * The split stack dialog: dropping a stackable with more than one asks how many to move; Ctrl moves the whole stack.
// Models: Core/AutoWalk.cs, Core/NpcBubble.cs, Core/SplitStack.cs, Core/LoginExtras.cs, Core/HudBars.cs (the eased plate bars: ChaosApp.Plate.cs).
using System;
using System.Collections;
using System.Collections.Generic;
using System.Text;
using Chaos.Core;
using UnityEngine;
using UnityEngine.Networking;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        const int SplitWindowId = 9300;

        // ------------------------------------------------------------------------------------ login: news and medallions
        LoginNews news;
        string newsHost = "", hostSeen = "";
        double hostSeenAt;
        bool newsBusy;
        Texture2D medallionTex;
        GUIStyle newsTitle, newsRow, newsDim;

        /// <summary>Draws the medallions, the crests and the news bar around the sign-in panel (LoginGui passes the panel's rect).</summary>
        void LoginExtrasGui(float w, float h, Rect panel)
        {
            // the services are asked for once the host has stopped changing
            string hostNow = (host ?? "").Trim();
            if (hostNow != hostSeen) { hostSeen = hostNow; hostSeenAt = Time.unscaledTime; }
            if (!newsBusy && hostNow != newsHost && Time.unscaledTime - hostSeenAt > 1.0)
            {
                newsHost = hostNow;
                string url = SiteUrls.Services(hostNow);
                news = null;
                if (url != null) StartCoroutine(FetchNews(url));
            }
            if (newsTitle == null)
            {
                newsTitle = new GUIStyle(small) { fontSize = 12, fontStyle = FontStyle.Bold };
                newsTitle.normal.textColor = new Color(0.96f, 0.81f, 0.45f);
                newsRow = new GUIStyle(small) { fontSize = 12, clipping = TextClipping.Clip };
                newsDim = new GUIStyle(newsRow);
                newsDim.normal.textColor = new Color(0.65f, 0.6f, 0.58f);
            }
            if (medallionTex == null) medallionTex = MakeMedallion();
            LoginDecor.Medallions(panel.x, panel.y, panel.width, Application.isMobilePlatform, out float lx, out float ly, out float rx, out float ry);
            if (Event.current.type == EventType.Repaint)
            {
                GUI.DrawTexture(new Rect(lx, ly, LoginDecor.Medallion, LoginDecor.Medallion), medallionTex);
                GUI.DrawTexture(new Rect(rx, ry, LoginDecor.Medallion, LoginDecor.Medallion), medallionTex);
                LoginDecor.Crests(panel.x, panel.y, panel.width, panel.height, out float cx, out float ty, out float by);
                Crest(cx, ty); Crest(cx, by);
            }
            // players online (the main client's server status line)
            if (news != null && news.PlayersOnline >= 0)
            {
                var ok = new GUIStyle(newsRow) { alignment = TextAnchor.MiddleCenter };
                ok.normal.textColor = new Color(0.31f, 0.68f, 0.35f);
                GUI.Label(new Rect(panel.x, panel.yMax + 4, panel.width, 18), Loc.T("Server online - {0} players", news.PlayersOnline), ok);
            }
            const float PW = 250, PH = 112, Gap = 8;
            float top = panel.yMax + 26;
            var st = LoginBar.Of(news, true, false, top + PH + 4 > h, false, false);
            if (!st.Bar) return;
            var xs = LoginBar.Row(new[] { PW, PW }, new[] { st.Info, st.Boost }, w, Gap);
            if (xs[0] >= 0) EventsPanel(new Rect(xs[0], top, PW, PH));
            if (xs[1] >= 0) BoostedPanel(new Rect(xs[1], top, PW, PH));
        }

        void Crest(float x, float y)
        {
            var gold = new Color(0.6f, 0.45f, 0.18f, 0.9f);
            Fill(new Rect(x, y + LoginDecor.CrestH / 2 - 1, LoginDecor.CrestW, 2), gold);
            Fill(new Rect(x + LoginDecor.CrestW / 2 - 6, y + LoginDecor.CrestH / 2 - 6, 12, 12), new Color(0.04f, 0.03f, 0.05f, 1f));
            Fill(new Rect(x + LoginDecor.CrestW / 2 - 4, y + LoginDecor.CrestH / 2 - 4, 8, 8), gold);
        }

        /// <summary>A rune disc, drawn in code (no art file needed): a gold ring, a dark centre, a gold diamond.</summary>
        static Texture2D MakeMedallion()
        {
            const int N = 64;
            var t = new Texture2D(N, N, TextureFormat.RGBA32, false) { filterMode = FilterMode.Bilinear, wrapMode = TextureWrapMode.Clamp };
            var px = new Color32[N * N];
            for (int y = 0; y < N; y++)
                for (int x = 0; x < N; x++)
                {
                    float dx = x - (N - 1) / 2f, dy = y - (N - 1) / 2f, r = Mathf.Sqrt(dx * dx + dy * dy);
                    Color c = new Color(0, 0, 0, 0);
                    if (r <= 30f) c = new Color(0.05f, 0.04f, 0.06f, 0.95f);
                    if (r > 26f && r <= 30f) c = new Color(0.6f, 0.45f, 0.18f, 1f);
                    if (r <= 22f && Mathf.Abs(dx) + Mathf.Abs(dy) <= 14f && Mathf.Abs(dx) + Mathf.Abs(dy) >= 9f) c = new Color(0.96f, 0.81f, 0.45f, 1f);
                    float edge = Mathf.Clamp01(31f - r);
                    c.a *= edge;
                    px[y * N + x] = c;
                }
            t.SetPixels32(px);
            t.Apply();
            return t;
        }

        void EventsPanel(Rect r)
        {
            Fill(r, new Color(0.04f, 0.03f, 0.05f, 0.85f));
            Fill(new Rect(r.x, r.y, r.width, 1), new Color(0.6f, 0.45f, 0.18f));
            GUI.Label(new Rect(r.x + 6, r.y + 2, r.width - 12, 18), Loc.T("Event schedule"), newsTitle);
            var now = DateTime.Now;
            float y = r.y + 22;
            foreach (var e in news.Upcoming(now, 4))
            {
                bool running = e.Running(now);
                var c = ColorUtility.TryParseHtmlString(e.ColorLight, out var cc) ? cc : new Color(0.84f, 0.79f, 0.68f);
                Fill(new Rect(r.x + 6, y + 4, 8, 8), c);
                GUI.Label(new Rect(r.x + 18, y, r.width - 24, 20), e.Name, newsRow);
                string when = running ? Loc.T("now") : LoginNews.DaysUntil(e, now) <= 1 ? Loc.T("tomorrow") : Loc.T("in {0} days", LoginNews.DaysUntil(e, now));
                var right = new GUIStyle(newsDim) { alignment = TextAnchor.MiddleRight };
                GUI.Label(new Rect(r.x + 6, y, r.width - 12, 20), when, right);
                y += 21;
            }
        }

        void BoostedPanel(Rect r)
        {
            Fill(r, new Color(0.04f, 0.03f, 0.05f, 0.85f));
            Fill(new Rect(r.x, r.y, r.width, 1), new Color(0.6f, 0.45f, 0.18f));
            GUI.Label(new Rect(r.x + 6, r.y + 2, r.width - 12, 18), Loc.T("Boosted today"), newsTitle);
            float y = r.y + 24;
            foreach (var pair in new[] { new KeyValuePair<string, BoostedMonster>(Loc.T("Creature"), news.Creature), new KeyValuePair<string, BoostedMonster>(Loc.T("Boss"), news.Boss) })
            {
                if (pair.Value == null) continue;
                var pic = new Rect(r.x + 8, y, 40, 40);
                Fill(pic, new Color(0f, 0f, 0f, 0.5f));
                DrawOutfit(pic, pair.Value.Outfit);
                GUI.Label(new Rect(r.x + 54, y + 2, r.width - 60, 18), pair.Key, newsDim);
                GUI.Label(new Rect(r.x + 54, y + 20, r.width - 60, 18), pair.Value.Name, newsRow);
                y += 44;
            }
        }

        IEnumerator FetchNews(string url)
        {
            newsBusy = true;
            using (var req = UnityWebRequest.Get(url))
            {
                req.timeout = 6;
                yield return req.SendWebRequest();
                if (req.result == UnityWebRequest.Result.Success) news = LoginNews.Parse(req.downloadHandler.text);
            }
            newsBusy = false;
        }

        // ------------------------------------------------------------------------------------ character select: the website's account API
        AccountAnswer acct;
        string acctToken = "", acctError = "";
        bool acctBusy;
        LoginResult acctFor;

        bool AccountApiOn => PlayerPrefs.GetInt("chaos.account.api", 1) == 1;

        /// <summary>Asks the website for the looks of this account's characters (one login, the answer carries them). Called when the list of characters changes.</summary>
        void AccountStart()
        {
            acct = null; acctError = "";
            string url = SiteUrls.Account(host);
            if (url == null || !AccountApiOn || acctBusy || string.IsNullOrEmpty(account) || string.IsNullOrEmpty(password)) return;
            StartCoroutine(AccountLogin(url, account, password, login));
        }

        IEnumerator AccountLogin(string url, string user, string pass, LoginResult forList)
        {
            acctBusy = true;
            string body = AccountApi.LoginRequest(user, pass, AccountApi.Nonce(() => UnityEngine.Random.Range(0, 16)));
            string text = "";
            yield return PostJson(url, body, t => text = t);
            acctBusy = false;
            var a = AccountApi.Parse(text);
            if (screen != Screen.Characters || forList != login)
            {
                if (a.Ok && a.Token.Length > 0) StartCoroutine(PostJson(url, AccountApi.LogoutRequest(a.Token), _ => { }));   // left the list meanwhile
                yield break;
            }
            if (a.Ok) { acct = a; acctToken = a.Token; acctFor = forList; }
            else acctError = a.Error;
        }

        static IEnumerator PostJson(string url, string body, Action<string> done)
        {
            using (var req = new UnityWebRequest(url, "POST"))
            {
                req.uploadHandler = new UploadHandlerRaw(Encoding.UTF8.GetBytes(body));
                req.downloadHandler = new DownloadHandlerBuffer();
                req.SetRequestHeader("Content-Type", "application/json");
                req.timeout = 8;
                yield return req.SendWebRequest();
                done(req.downloadHandler != null ? req.downloadHandler.text : "");
            }
        }

        /// <summary>Back to the login screen or into the game: the token ends here and on the website; the looks are dropped.</summary>
        void AccountEnd()
        {
            string url = SiteUrls.Account(host);
            if (acctToken.Length > 0 && url != null) StartCoroutine(PostJson(url, AccountApi.LogoutRequest(acctToken), _ => { }));
            acctToken = ""; acct = null; acctError = "";
        }

        AccountLook LookOf(string name)
        {
            AccountLook l = null;
            return acct != null && acct.Looks.TryGetValue(name, out l) ? l : null;
        }

        // ------------------------------------------------------------------------------------ auto-walk and the walk-up to an NPC
        readonly AutoWalkState autoWalk = new AutoWalkState();
        readonly NpcApproach npcApproach = new NpcApproach();
        double clickDownAt = -100;
        Vector2 clickDownPos;
        bool clickFromMap;
        const float TapSeconds = 0.25f, TapPixels = 8f;

        /// <summary>A held button walks towards the pointer only after the tap time: a quick click is an auto-walk.</summary>
        bool ClickHeldLong => Time.unscaledTime - clickDownAt >= TapSeconds;

        void Phase6VUpdate()
        {
            if (session == null || world?.Player == null) return;
            double now = session.Now;
            Pos me = world.Player.Position;
            bool typing = chatFocused || TextEditing;
            if (!typing)
            {
                if (Input.GetMouseButtonDown(0))
                {
                    clickDownAt = Time.unscaledTime; clickDownPos = Input.mousePosition;
                    clickFromMap = PointerOnMap && !PlayBlocksWalk && !PlayUsedClick;
                }
                else if (Input.GetMouseButtonUp(0) && clickFromMap)
                {
                    clickFromMap = false;
                    if (!ClickHeldLong && ((Vector2)Input.mousePosition - clickDownPos).magnitude < TapPixels && PointerOnMap && !PlayBlocksWalk && !PlayUsedClick && !Crosshair.Active) WalkToClick(me);
                }
                // Escape stops the walk (0xBE) and the walk-up
                if (Input.GetKeyDown(KeyCode.Escape) && (autoWalk.Active || npcApproach.Active))
                {
                    session.SendRaw(AutoWalkPackets.StopPacket());
                    autoWalk.Cancel(); npcApproach.Cancel();
                }
            }
            var r = autoWalk.Update(me, now);
            if (npcApproach.Active)
            {
                world.Creatures.TryGetValue(npcApproach.NpcId, out var npc);
                if (r == AutoWalkState.Result.Interrupted || r == AutoWalkState.Result.Stalled) { string n = npcApproach.NpcName; npcApproach.Cancel(); PostLine(Loc.T("You cannot reach {0}.", n)); }
                else
                    switch (npcApproach.Update(npc != null, me, npc != null ? npc.Position : me, now))
                    {
                        case NpcApproach.Step.Greet:
                            if (autoWalk.Active) { session.SendRaw(AutoWalkPackets.StopPacket()); autoWalk.Cancel(); }
                            session.SayToNpc("hi");
                            break;
                        case NpcApproach.Step.Failed:
                            if (autoWalk.Active) { session.SendRaw(AutoWalkPackets.StopPacket()); autoWalk.Cancel(); }
                            PostLine(Loc.T("You cannot reach {0}.", npcApproach.NpcName));
                            break;
                    }
            }
        }

        /// <summary>The tile under a quick click is the goal; a creature there, an unknown or blocked tile and no path give "There is no way.".</summary>
        void WalkToClick(Pos me)
        {
            PickAtMouse(false, out var c, out var t, out var it);
            if (t == null || c != null || t.Pos == me) return;
            npcApproach.Cancel();
            StartAutoWalk(me, t.Pos, 0);
        }

        bool StartAutoWalk(Pos me, Pos goal, int range)
        {
            uint self = world.PlayerId;
            var path = PathFinder.Find(me, goal, p => WalkMap.Walkable(world, p, self), range);
            if (path == null) { PostLine(Loc.T("There is no way.")); return false; }
            if (path.Count == 0) return true;
            if (path.Count > AutoWalkPackets.MaxSteps) path.RemoveRange(AutoWalkPackets.MaxSteps, path.Count - AutoWalkPackets.MaxSteps);
            session.SendRaw(AutoWalkPackets.WalkPacket(path));
            autoWalk.Start(me, path, session.Now);
            return true;
        }

        /// <summary>Talk to an NPC: says hi at once when in its talk radius, else walks up first and greets on arrival (gives up after 10 seconds or when the way is blocked).</summary>
        public void TalkToNpc(Creature c)
        {
            if (session == null || world?.Player == null || c == null) return;
            var win = FindWindow<NpcTalkWindow>();
            if (win != null) win.Open = true;
            Pos me = world.Player.Position;
            if (NpcBubble.InRange(me, c.Position)) { npcApproach.Cancel(); session.SayToNpc("hi"); return; }
            uint self = world.PlayerId;
            var path = NpcApproach.PathTo(me, c.Position, p => WalkMap.Walkable(world, p, self));
            if (path == null || path.Count == 0) { PostLine(Loc.T("You cannot reach {0}.", c.Name)); return; }
            npcApproach.Start(c.Id, c.Name, session.Now);
            if (path.Count > AutoWalkPackets.MaxSteps) path.RemoveRange(AutoWalkPackets.MaxSteps, path.Count - AutoWalkPackets.MaxSteps);
            session.SendRaw(AutoWalkPackets.WalkPacket(path));
            autoWalk.Start(me, path, session.Now);
        }

        /// <summary>Right click on an NPC: Talk, Look, Copy Name (an NPC is never attacked).</summary>
        void NpcMenu(Creature c)
        {
            uint id = c.Id;
            string name = c.Name;
            var items = new List<KeyValuePair<string, Action>>
            {
                new KeyValuePair<string, Action>(Loc.T("Talk"), () => { if (world != null && world.Creatures.TryGetValue(id, out var npc)) TalkToNpc(npc); }),
                new KeyValuePair<string, Action>(Loc.T("Look"), () => session.LookAtCreature(id)),
                new KeyValuePair<string, Action>("", null),
                new KeyValuePair<string, Action>(Loc.T("Copy Name"), () => GUIUtility.systemCopyBuffer = name),
            };
            ShowMenu(MouseUi(), items);
        }

        // ------------------------------------------------------------------------------------ the NPC speech bubble
        GUIStyle bubbleText, bubbleName, bubbleChip;

        /// <summary>The bubble over the NPC we talk to: its name, its latest reply (wrapped, at most 8 lines), keyword chips and an end button. Drawn inside the map group (`map`: its rect in UI units).</summary>
        void NpcBubbleGui(Rect map, float scale)
        {
            var talk = session?.Parser.NpcTalk;
            if (talk == null || world?.Player == null || view == null && !HdLabelsOn) return;
            double now = session.Now;
            if (!talk.Focused(now) || talk.Npc.Length == 0) return;
            string text = null;
            for (int i = talk.Lines.Count - 1; i >= 0; i--) if (talk.Lines[i].FromNpc) { text = NpcTalkState.Plain(talk.Lines[i].Text); break; }
            if (text == null) return;
            if (bubbleText == null)
            {
                bubbleText = new GUIStyle(small) { fontSize = 12, clipping = TextClipping.Clip };
                bubbleText.normal.textColor = new Color(0.12f, 0.09f, 0.06f);
                bubbleName = new GUIStyle(bubbleText) { fontStyle = FontStyle.Bold };
                bubbleChip = new GUIStyle(GUI.skin.button) { fontSize = 11 };
            }
            Func<string, float> measure = s => bubbleText.CalcSize(new GUIContent(s)).x;
            float tile = map.height / ViewTilesH;
            foreach (var (c, sp) in LabelPoints())
            {
                if (c.Type != 2 || !string.Equals(c.Name, talk.Npc, StringComparison.OrdinalIgnoreCase)) continue;
                if (!NpcBubble.InRange(world.Player.Position, c.Position)) continue;
                float x = sp.x / scale - map.x, y = (UnityEngine.Screen.height - sp.y) / scale;
                var lines = NpcBubble.Visible(NpcBubble.Wrap(text, NpcBubble.MaxWidth - 2 * NpcBubble.Pad, measure));
                float longest = 0;
                foreach (string l in lines) longest = Mathf.Max(longest, measure(l));
                float width = NpcBubble.WidthFor(Mathf.Max(longest, measure(c.Name) + 22), map.width - 8);
                var chips = new List<string>();
                float cx = 0;
                foreach (string k in talk.CurrentKeywords())
                {
                    float cw = Mathf.Max(30f, bubbleChip.CalcSize(new GUIContent(k)).x + 10);
                    if (cx + cw > width - 2 * NpcBubble.Pad || chips.Count >= 6) break;
                    chips.Add(k); cx += cw + 4;
                }
                float height = NpcBubble.Pad * 2 + 18 + lines.Count * NpcBubble.LineH + (chips.Count > 0 ? 26 : 0);
                float nameTop = y - InfoLift.ForView(c, tile, HdLabelsOn) - Mathf.Max(3f, Mathf.Round(tile / 14f)) - 22;
                var place = NpcBubble.Place(width, height, x, nameTop, x, y + tile * 0.5f, 0, 0, map.width, map.height);
                var box = new Rect(place.X, place.Y, width, height);
                uiRects.Add(Scaled(new Rect(map.x + box.x, map.y + box.y, box.width, box.height), scale));
                var paper = new Color(0.93f, 0.88f, 0.74f, 0.97f);
                Fill(new Rect(box.x - 1, box.y - 1, box.width + 2, box.height + 2), new Color(0.35f, 0.25f, 0.1f));
                Fill(box, paper);
                for (int i = 0; i < (int)NpcBubble.TailH; i++)   // the tail: a stair of shrinking bars pointing at the NPC
                {
                    float tw = NpcBubble.TailW * (1f - i / NpcBubble.TailH);
                    float ty = place.Below ? place.TailY + NpcBubble.TailH - 1 - i : place.TailY + i;
                    Fill(new Rect(place.TailX + (NpcBubble.TailW - tw) / 2, ty, tw, 1), paper);
                }
                GUI.Label(new Rect(box.x + NpcBubble.Pad, box.y + NpcBubble.Pad - 2, width - 2 * NpcBubble.Pad - 18, 18), c.Name, bubbleName);
                if (GUI.Button(new Rect(box.xMax - 22, box.y + 3, 18, 16), "x")) session.SayToNpc("bye");
                float ly = box.y + NpcBubble.Pad + 16;
                foreach (string l in lines) { GUI.Label(new Rect(box.x + NpcBubble.Pad, ly, width - 2 * NpcBubble.Pad, NpcBubble.LineH + 2), l, bubbleText); ly += NpcBubble.LineH; }
                float chipX = box.x + NpcBubble.Pad;
                foreach (string k in chips)
                {
                    float cw = Mathf.Max(30f, bubbleChip.CalcSize(new GUIContent(k)).x + 10);
                    if (GUI.Button(new Rect(chipX, ly + 3, cw, 20), k, bubbleChip)) session.SayToNpc(k);
                    chipX += cw + 4;
                }
                break;
            }
        }

        // ------------------------------------------------------------------------------------ the split stack dialog
        SplitStackModel split;
        Pos splitFrom, splitTo;
        ushort splitId;
        byte splitStack;
        bool splitFocus;

        /// <summary>Opens the "how many" dialog for a move of a stackable item; Ctrl at the drop skips it (ItemSlots).</summary>
        public void AskSplit(Pos from, ushort id, byte stackPos, Pos to, int count)
        {
            split = new SplitStackModel(count);
            splitFrom = from; splitTo = to; splitId = id; splitStack = stackPos; splitFocus = true;
        }

        void SplitGui(float w, float h, float scale)
        {
            if (split == null) return;
            MarkTextEditing();   // no walking or hotkeys while it is open
            var box = new Rect((w - 260) / 2, Mathf.Max(30, h / 3 - 40), 260, 138);
            var e = Event.current;
            bool ok = false, cancel = false;
            DialogBox(SplitWindowId, box, Loc.T("Move how many?"), inner =>
            {
                DrawItem(new Rect(inner.x, inner.y, 40, 40), splitId, split.Count);
                GUI.SetNextControlName("splitCount");
                string typed = GUI.TextField(new Rect(inner.x + 48, inner.y + 8, 60, 24), split.Text, 3);
                if (typed != split.Text) split.SetText(typed);
                if (splitFocus && e.type == EventType.Repaint) { GUI.FocusControl("splitCount"); splitFocus = false; }
                GUI.Label(new Rect(inner.x + 112, inner.y + 8, 100, 24), "/ " + split.Max, small);
                float f = GUI.HorizontalSlider(new Rect(inner.x, inner.y + 46, inner.width, 16), split.Fraction, 0f, 1f);
                if (Mathf.Abs(f - split.Fraction) > 0.0001f) split.SetFraction(f);
                float bx = inner.x;
                if (GUI.Button(new Rect(bx, inner.y + 66, 28, 22), "-")) split.Step(-1);
                if (GUI.Button(new Rect(bx + 30, inner.y + 66, 28, 22), "+")) split.Step(1);
                if (GUI.Button(new Rect(bx + 62, inner.y + 66, 36, 22), "1")) split.One();
                if (GUI.Button(new Rect(bx + 100, inner.y + 66, 56, 22), Loc.T("Half"))) split.Half();
                if (GUI.Button(new Rect(bx + 158, inner.y + 66, 76, 22), Loc.T("All"))) split.All();
                if (GUI.Button(new Rect(inner.x, inner.y + 94, 110, 24), Loc.T("Move"))) ok = true;
                if (GUI.Button(new Rect(inner.x + 124, inner.y + 94, 110, 24), Loc.T("Cancel"))) cancel = true;
            });
            if (e.type == EventType.KeyDown && (e.keyCode == KeyCode.Return || e.keyCode == KeyCode.KeypadEnter)) { ok = true; e.Use(); }
            else if (e.type == EventType.KeyDown && e.keyCode == KeyCode.Escape) { cancel = true; e.Use(); }
            if (ok) { session?.MoveItem(splitFrom, splitId, splitStack, splitTo, split.PacketCount); split = null; }
            else if (cancel) split = null;
        }

        // ------------------------------------------------------------------------------------ windows by class name (the bag panel's tabs)
        public bool HasWindowNamed(string name)
        {
            if (windows.Count == 0) MakeWindows();
            foreach (var win in windows) if (win.GetType().Name == name) return true;
            return false;
        }

        public void ToggleWindowNamed(string name)
        {
            foreach (var win in windows) if (win.GetType().Name == name) { win.Open = !win.Open; return; }
        }

        /// <summary>Called at the end of GameGui for the pieces of this track.</summary>
        void Phase6VGui(float w, float h, float scale)
        {
            SplitGui(w, h, scale);
        }
    }
}
