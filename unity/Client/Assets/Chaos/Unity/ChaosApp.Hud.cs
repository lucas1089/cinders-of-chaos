// HUD of the game screen (phase 3, track H), drawn from the models of Core/Hud.cs: toasts and the danger line at the right and
// top, the buff bar, energy shield bar and chi pips under the character plate, the tiered monster bar with the boss mechanic bar,
// cast bars over casters, the anti-bot presence check (modal) and the player report dialog. No icon art: buffs are coloured
// squares with a short label.
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        GUIStyle toastText, hudTiny;
        string reportReason = "", reportNote = "", reportNameEdit;
        bool reportWasOpen;
        const int CheckWindowId = 9100, ReportWindowId = 9101;

        static Color HexColor(string hex, Color fallback)
        {
            return ColorUtility.TryParseHtmlString(hex, out var c) ? c : fallback;
        }

        /// <summary>Draws every HUD element. Call after the windows, before the context menu.</summary>
        void HudGui(float w, float h, float scale)
        {
            var hud = session?.Hud;
            if (hud == null) return;
            if (toastText == null)
            {
                toastText = new GUIStyle(small) { wordWrap = true, fontSize = 12 };
                hudTiny = new GUIStyle(small) { fontSize = 11, alignment = TextAnchor.MiddleCenter, clipping = TextClipping.Clip };
            }
            double now = session.Now;
            HudGlobes(w, h, scale);   // ChaosApp.Art.cs (the orb pictures; nothing without them)
            HudPlateExtras(hud, now, scale);
            HudMonsterBar(hud, w, now, scale);
            HudCastBars(hud, h, now, scale);
            HudToasts(hud, w, now, scale);
            HudAntibot(hud, w, h, now, scale);
        }

        // ------------------------------------------------------------------------------------ under the plate
        void HudPlateExtras(HudState hud, double now, float scale)
        {
            float y = StatusRect().yMax + 4, x = StatusRect().x, bw = StatusRect().width;
            if (hud.Shield.Visible)
            {
                var r = new Rect(x, y, bw, 12);
                Fill(new Rect(r.x - 1, r.y - 1, r.width + 2, r.height + 2), new Color(0f, 0f, 0f, 0.9f));
                Fill(new Rect(r.x, r.y, EnergyShield.FillWidth(hud.Shield.Tick(now), hud.Shield.Max, (int)r.width), r.height), new Color(0.35f, 0.7f, 0.95f));
                var st = new GUIStyle(hudTiny);
                st.normal.textColor = Color.white;
                GUI.Label(r, Loc.T("Shield") + " " + EnergyShield.Pair(hud.Shield.Shown, hud.Shield.Max), st);
                y += 16;
            }
            if (hud.Chi.Active)
            {
                int chi = hud.Chi.Shown(now);
                for (int i = 1; i <= hud.Chi.Max; i++)
                {
                    var r = new Rect(x + (i - 1) * 18, y, 14, 14);
                    string look = MonkChi.Pip(i, chi, hud.Chi.Max);
                    Fill(new Rect(r.x - 1, r.y - 1, 16, 16), new Color(0f, 0f, 0f, 0.9f));
                    Fill(r, look == "full" ? new Color(0.95f, 0.75f, 0.2f) : new Color(0.2f, 0.17f, 0.12f));
                }
                double fade = hud.Chi.FadeIn(now);
                if (fade >= 0 && chi > 0) GUI.Label(new Rect(x + hud.Chi.Max * 18 + 2, y - 2, 60, 18), BuffBar.Format(fade), hudTiny);
                y += 18;
            }
            if (!hud.Buffs.Shown || hud.Buffs.Buffs.Count == 0) return;
            var list = hud.Buffs.Ordered(out int nBuffs);
            // a cell is as wide as its widest short name or timer, and tall enough for the name over the timer
            var nameStyle = new GUIStyle(hudTiny) { fontStyle = FontStyle.Bold };
            var timeStyle = new GUIStyle(hudTiny) { fontSize = 10, alignment = TextAnchor.LowerCenter };
            float textW = 0;
            bool anyIcon = false;
            foreach (var bf in list)
            {
                // a buff with its own picture needs no label width; one without keeps the short name (track U)
                if (BuffTexture(bf) != null) anyIcon = true;
                else textW = Mathf.Max(textW, nameStyle.CalcSize(new GUIContent(BuffBar.Label(bf))).x);
                if (hud.Buffs.Timers && bf.EndAt >= 0) textW = Mathf.Max(textW, timeStyle.CalcSize(new GUIContent(BuffBar.Format(bf.Remaining(now)))).x);
            }
            int cw = (int)Mathf.Ceil(TopbarLayout.CellWidth(textW, 0, 26, 6)), ch = hud.Buffs.Timers ? (anyIcon ? 40 : 32) : 26;
            var cells = BuffBar.Flow(list.Count, (int)bw, cw, ch, 2, out int height);
            var e = Event.current;
            string tip = null;
            Rect tipAt = default;
            bool alt = Input.GetKey(KeyCode.LeftAlt) || Input.GetKey(KeyCode.RightAlt);
            for (int i = 0; i < list.Count; i++)
            {
                var b = list[i];
                var r = new Rect(x + cells[i].x, y + cells[i].y, cw, ch);
                var c = BuffBar.Colour(b);
                var frameCol = b.Debuff ? new Color(0.9f, 0.2f, 0.15f) : new Color(0.7f, 0.55f, 0.2f);
                // the buff's own 26 px picture in a thin frame; without the file the coloured cell with its short name
                var pic = new Rect(r.x + Mathf.Floor((r.width - BuffIcons.Size) / 2f), r.y, BuffIcons.Size, BuffIcons.Size);
                bool hasPic = BuffTexture(b) != null;
                if (hasPic)
                {
                    Fill(new Rect(pic.x - 1, pic.y - 1, pic.width + 2, pic.height + 2), frameCol);
                    DrawBuffIcon(pic, b);
                }
                else
                {
                    Fill(new Rect(r.x - 1, r.y - 1, r.width + 2, r.height + 2), frameCol);
                    Fill(r, new Color(c[0], c[1], c[2]));
                    var st = new GUIStyle(hudTiny) { fontStyle = FontStyle.Bold };
                    st.normal.textColor = Color.white;
                    GUI.Label(hud.Buffs.Timers && b.EndAt >= 0 ? new Rect(r.x, r.y, r.width, 16) : r, BuffBar.Label(b), st);
                }
                if (hud.Buffs.Timers && b.EndAt >= 0)
                {
                    var tt = new GUIStyle(hudTiny) { fontSize = 10, alignment = TextAnchor.LowerCenter };
                    tt.normal.textColor = Color.black;
                    var tr = hasPic ? new Rect(r.x, r.y + BuffIcons.Size + 1, r.width, 13) : new Rect(r.x, r.yMax - 14, r.width, 14);
                    GUI.Label(new Rect(tr.x + 1, tr.y + 1, tr.width, tr.height), BuffBar.Format(b.Remaining(now)), tt);
                    tt.normal.textColor = Color.white;
                    GUI.Label(tr, BuffBar.Format(b.Remaining(now)), tt);
                }
                if (b.Stacks > 1)
                {
                    var ss = new GUIStyle(hudTiny) { fontSize = 10, alignment = TextAnchor.UpperRight };
                    ss.normal.textColor = Color.yellow;
                    GUI.Label(r, ((int)b.Stacks).ToString(), ss);
                }
                if (r.Contains(e.mousePosition)) { tip = BuffBar.Tooltip(b, now, alt); tipAt = r; }
            }
            uiRects.Add(Scaled(new Rect(x, y, bw, height), scale));
            if (tip != null)
            {
                float th = 16 * (tip.Split('\n').Length) + 8;
                var tr = new Rect(tipAt.x, tipAt.yMax + 4, 240, th);
                Fill(tr, new Color(0.03f, 0.02f, 0.04f, 0.95f));
                GUI.Label(new Rect(tr.x + 4, tr.y + 2, tr.width - 8, tr.height - 4), tip, toastText);
            }
        }

        // ------------------------------------------------------------------------------------ monster bar
        void HudMonsterBar(HudState hud, float w, double now, float scale)
        {
            uint target = session.AttackTarget;
            Creature c = null;
            if (target != 0) world.Creatures.TryGetValue(target, out c);
            if (c != null && c.Type != 1) c = null;   // monsters only, as the main client
            hud.Monster.Update(c != null ? c.Id : 0u, c?.Name, c != null ? c.HealthPercent : 0, now, Mathf.Min(100f, Time.unscaledDeltaTime * 1000f));
            float y = 46;
            bool artDone = false;
            if (c != null)
            {
                var info = hud.Monster.Info(c.Id);
                string key = MonsterBar.StyleKey(info?.Tier, info?.Role);
                var style = MonsterBar.Styles[key];
                // the frame art of game_monsterbar when its pictures are there (track U), else the drawn bar below
                float artBottom = HudMonsterBarArt(hud, c, info, key, style, w, y, now, scale);
                if (artBottom >= 0) { y = artBottom + 8; artDone = true; }
                else
                {
                    Color nameCol = HexColor(style.name, Color.white);
                    var box = new Rect(w / 2 - 150, y, 300, 40);
                    uiRects.Add(Scaled(box, scale));
                    Fill(new Rect(box.x - 2, box.y - 2, box.width + 4, box.height + 4), nameCol * 0.7f);
                    Fill(box, new Color(0.05f, 0.03f, 0.04f, 0.92f));
                    string title = MonsterBar.Title(key, info?.Label ?? "", c.Name);
                    var ns = new GUIStyle(small) { fontSize = 13, fontStyle = FontStyle.Bold };
                    ns.normal.textColor = nameCol;
                    GUI.Label(new Rect(box.x + 6, box.y + 1, box.width - 70, 20), title, ns);
                    string lv = MonsterBar.LevelText(info?.Level ?? 0);
                    var rs = new GUIStyle(hudTiny) { alignment = TextAnchor.MiddleRight };
                    rs.normal.textColor = new Color(0.85f, 0.8f, 0.7f);
                    if (lv != null) GUI.Label(new Rect(box.xMax - 64, box.y + 1, 58, 20), lv, rs);
                    var bar = new Rect(box.x + 6, box.y + 22, box.width - 12, 12);
                    Fill(bar, new Color(0f, 0f, 0f, 0.9f));
                    int tw = MonsterBar.FillWidth(hud.Monster.TrailValue, (int)bar.width);
                    Fill(new Rect(bar.x, bar.y, tw, bar.height), new Color(1f, 1f, 1f, 0.55f));
                    int fw = MonsterBar.FillWidth(hud.Monster.Percent, (int)bar.width);
                    Fill(new Rect(bar.x, bar.y, fw, bar.height), key == "normal" ? new Color(0.78f, 0.25f, 0.2f) : nameCol * 0.9f);
                    var ps = new GUIStyle(hudTiny);
                    ps.normal.textColor = Color.white;
                    GUI.Label(bar, MonsterBar.PercentText(hud.Monster.Percent), ps);
                    // modifier chips under the bar
                    if (info != null && info.Mods.Count > 0)
                    {
                        string tip = null;
                        var e = Event.current;
                        for (int i = 0; i < info.Mods.Count; i++)
                        {
                            var chip = new Rect(box.x + 6 + i * 22, box.yMax + 4, 20, 20);
                            Fill(chip, new Color(0.25f, 0.12f, 0.12f, 0.95f));
                            string nm = info.Mods[i];
                            GUI.Label(chip, nm.Length > 0 ? nm.Substring(0, 1).ToUpperInvariant() : "?", hudTiny);
                            if (chip.Contains(e.mousePosition)) tip = nm + ": " + MonsterBar.ModTip(nm);
                        }
                        if (tip != null)
                        {
                            var tr = new Rect(box.x, box.yMax + 28, 300, 36);
                            Fill(tr, new Color(0.03f, 0.02f, 0.04f, 0.95f));
                            GUI.Label(new Rect(tr.x + 4, tr.y + 2, tr.width - 8, tr.height - 4), tip, toastText);
                        }
                    }
                    y = box.yMax + 8;
                }
            }
            var mech = hud.Monster.Mech;
            if (MonsterBar.MechVisible(mech, now))
            {
                var r = new Rect(w / 2 - 150, c != null ? y + (!artDone && info0(hud, c) ? 28 : 0) : y, 300, 22);
                uiRects.Add(Scaled(r, scale));
                Fill(new Rect(r.x - 1, r.y - 1, r.width + 2, r.height + 2), new Color(0f, 0f, 0f, 0.9f));
                Fill(new Rect(r.x, r.y, MonsterBar.MechFill(mech, now, (int)r.width), r.height), HexColor(MonsterBar.MechColors[mech.Kind], Color.red));
                var ms = new GUIStyle(hudTiny);
                ms.normal.textColor = Color.white;
                GUI.Label(r, MonsterBar.MechText(mech, now), ms);
            }
        }

        static bool info0(HudState hud, Creature c) { var i = hud.Monster.Info(c.Id); return i != null && i.Mods.Count > 0; }

        // ------------------------------------------------------------------------------------ cast bars
        void HudCastBars(HudState hud, float h, double now, float scale)
        {
            var cast = hud.Cast;
            if (cast.Mine == null && cast.Others.Count == 0) return;
            uint me = world?.Player != null ? world.Player.Id : 0;
            bool placedMine = false;
            foreach (var (c, sp) in LabelPoints())
            {
                float x = sp.x / scale, y = (UnityEngine.Screen.height - sp.y) / scale;
                if (c.Id == me && cast.Mine != null)
                {
                    DrawCastBar(new Rect(x - 60, y - 64, 120, 16), cast.Mine, cast.MineText(now), now, true, scale);
                    placedMine = true;
                }
                else if (cast.Others.TryGetValue(c.Id, out var o))
                    DrawCastBar(new Rect(x - 40, y - 50, 80, 10), o, null, now, false, scale);
            }
            // without a label point (the character is not in view yet): above the middle of the screen
            if (cast.Mine != null && !placedMine)
                DrawCastBar(new Rect(UnityEngine.Screen.width / scale / 2 - 70, h * 0.55f, 140, 18), cast.Mine, cast.MineText(now), now, true, scale);
        }

        void DrawCastBar(Rect r, CastEntry e, string text, double now, bool mine, float scale)
        {
            string state = CastBar.State(e);
            Color col = state == "interrupted" ? new Color(0.54f, 0.1f, 0.1f) : state == "done" ? new Color(0.85f, 0.69f, 0.29f) : e.Portal ? new Color(0.29f, 0.42f, 0.82f) : new Color(0.75f, 0.54f, 0.16f);
            float p = e.EndAt >= 0 ? 1f : (float)CastBar.Progress(e.Start, e.Ms, now);
            Fill(new Rect(r.x - 1, r.y - 1, r.width + 2, r.height + 2), new Color(0f, 0f, 0f, 0.9f));
            Fill(new Rect(r.x, r.y, r.width * p, r.height), col);
            if (text != null)
            {
                var st = new GUIStyle(hudTiny);
                st.normal.textColor = Color.white;
                GUI.Label(r, text, st);
            }
            if (mine)
            {
                uiRects.Add(Scaled(r, scale));
                var ev = Event.current;
                if (ev.type == EventType.MouseDown && ev.button == 0 && r.Contains(ev.mousePosition) && session.Hud.Cast.Cancel()) ev.Use();
            }
        }

        // ------------------------------------------------------------------------------------ toasts
        void HudToasts(HudState hud, float w, double now, float scale)
        {
            var tc = hud.Toasts;
            // hunt warning: a window at the top centre
            if (tc.DangerShown(now))
            {
                var box = new Rect(w / 2 - 190, 150, 380, 60);
                uiRects.Add(Scaled(box, scale));
                Fill(box, new Color(0.9f, 0.85f, 0.8f, 0.96f));
                Fill(new Rect(box.x, box.y, box.width, 20), new Color(0.56f, 0.1f, 0.1f));
                var hs = new GUIStyle(small) { fontSize = 12, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
                hs.normal.textColor = Color.white;
                GUI.Label(new Rect(box.x, box.y, box.width, 20), tc.DangerCaution ? Loc.T("CAUTION") : Loc.T("DANGER"), hs);
                var ds = new GUIStyle(toastText) { alignment = TextAnchor.MiddleCenter };
                ds.normal.textColor = new Color(0.56f, 0.1f, 0.1f);
                GUI.Label(new Rect(box.x + 8, box.y + 22, box.width - 16, 36), tc.DangerText, ds);
            }
            if (tc.Active.Count == 0) return;
            float bw = 340, x = w - bw - 12;
            var heights = new List<int>();
            foreach (var t in tc.Active) heights.Add(ToastHeight(t, bw));
            var ys = ToastKinds.Stack(heights, 46);
            Toast close = null, accept = null, decline = null;
            for (int i = 0; i < tc.Active.Count; i++)
            {
                var t = tc.Active[i];
                var box = new Rect(x, ys[i], bw, heights[i]);
                uiRects.Add(Scaled(box, scale));
                Fill(new Rect(box.x - 2, box.y - 2, box.width + 4, box.height + 4), HexColor(t.Style.BorderColor, Color.gray));
                Fill(box, new Color(0.05f, 0.04f, 0.06f, 0.96f));
                var ts = new GUIStyle(small) { fontSize = 12, fontStyle = FontStyle.Bold };
                ts.normal.textColor = HexColor(t.Style.TitleColor, Color.white);
                GUI.Label(new Rect(box.x + 8, box.y + 3, box.width - 40, 20), Loc.T(t.Style.Title), ts);
                if (GUI.Button(new Rect(box.xMax - 24, box.y + 3, 20, 18), "x")) close = t;
                bool buttons = t.HasButtons;
                float textBottom = buttons ? ToastKinds.ButtonTextBottom : ToastKinds.TextBottom;
                // the toast type's own 48 px icon at the left (game_chaosnotify); the text moves right of it when the picture is there
                float iconY = box.y + ToastKinds.TextTop + Mathf.Max(0f, Mathf.Floor((box.height - ToastKinds.TextTop - textBottom - ToastIcons.Size) / 2f));
                float textX = ToastHasIcon(t) && DrawToastIcon(new Rect(box.x + 8, iconY, ToastIcons.Size, ToastIcons.Size), t.Type) ? ToastIconIndent : 0f;
                var tr = new Rect(box.x + 8 + textX, box.y + ToastKinds.TextTop, box.width - 16 - textX, box.height - ToastKinds.TextTop - textBottom);
                GUI.Label(tr, t.Message, toastText);
                if (buttons)
                {
                    string yes = t.Type == "CATACOMB_FREE" ? Loc.T("Start") : Loc.T("Accept");
                    if (GUI.Button(new Rect(box.x + 8, box.yMax - 66, 150, 26), yes)) accept = t;
                    if (GUI.Button(new Rect(box.x + 170, box.yMax - 66, 150, 26), Loc.T("Decline"))) decline = t;
                }
                // timer bar and the seconds left
                var bar = new Rect(box.x + 8, box.yMax - 16, box.width - 44, 8);
                Fill(bar, new Color(0f, 0f, 0f, 0.8f));
                Fill(new Rect(bar.x, bar.y, bar.width * (float)t.Fraction(now), bar.height), HexColor(t.Style.TitleColor, Color.white));
                var cs = new GUIStyle(hudTiny) { alignment = TextAnchor.MiddleRight };
                GUI.Label(new Rect(box.xMax - 34, box.yMax - 20, 28, 16), Mathf.CeilToInt((float)t.Left(now) / 1000f).ToString(), cs);
            }
            if (accept != null) tc.Accept(accept);
            else if (decline != null) tc.Decline(decline);
            else if (close != null) tc.Close(close);
        }

        const float ToastIconIndent = ToastIcons.Size + 8;
        bool ToastHasIcon(Toast t) => ArtTexture(ToastIcons.Path(t.Type)) != null;

        int ToastHeight(Toast t, float width)
        {
            float th = toastText.CalcHeight(new GUIContent(t.Message), width - 16 - (ToastHasIcon(t) ? ToastIconIndent : 0f));
            return ToastKinds.HeightFor(t.Type, th, out _);
        }

        // ------------------------------------------------------------------------------------ anti-bot
        /// <summary>Opens the report dialog through the server (it sends the reasons), prefilled with a name. Called by the player menu and the options window.</summary>
        public void OpenReport(string name)
        {
            if (session == null) return;
            reportReason = "";
            reportNote = "";
            reportNameEdit = name ?? "";
            session.Hud.Bot.OpenReport(name ?? "");
        }

        void HudAntibot(HudState hud, float w, float h, double now, float scale)
        {
            var bot = hud.Bot;
            if (bot.Check != null)
            {
                var box = new Rect(w / 2 - 230, h / 2 - 150, 460, 300);
                uiRects.Add(Scaled(box, scale));
                var chk = bot.Check;
                GUI.Window(CheckWindowId, box, _ =>
                {
                    Fill(new Rect(0, 0, box.width, box.height), new Color(0.04f, 0.03f, 0.05f, 0.97f));
                    Fill(new Rect(0, 0, box.width, 3), new Color(0.96f, 0.81f, 0.45f));
                    var ts = new GUIStyle(titleStyle) { alignment = TextAnchor.MiddleCenter };
                    GUI.Label(new Rect(8, 8, box.width - 16, 24), Loc.T("Presence check"), ts);
                    var ps = new GUIStyle(small) { alignment = TextAnchor.MiddleCenter, fontSize = 16 };
                    GUI.Label(new Rect(8, 36, box.width - 16, 26), Antibot.Prompt(chk.Word), ps);
                    double left = bot.SecondsLeft(now);
                    var bar = new Rect(20, 68, box.width - 40, 16);
                    Fill(bar, new Color(0f, 0f, 0f, 0.9f));
                    Color tc = HexColor(Antibot.TimeColor(left), Color.white);
                    Fill(new Rect(bar.x, bar.y, bar.width * Antibot.TimePercent(left, bot.TotalSeconds) / 100f, bar.height), tc * 0.8f);
                    var cs = new GUIStyle(hudTiny);
                    cs.normal.textColor = Color.white;
                    GUI.Label(bar, Antibot.TimeText(left), cs);
                    int n = chk.Options.Count;
                    float cell = 64, gap = 10, total = n * cell + (n - 1) * gap;
                    float sx = (box.width - total) / 2;
                    for (int i = 0; i < n; i++)
                    {
                        var r = new Rect(sx + i * (cell + gap), 96, cell, cell);
                        Fill(new Rect(r.x - 2, r.y - 2, r.width + 4, r.height + 4), new Color(0.5f, 0.4f, 0.2f));
                        Fill(r, new Color(0.1f, 0.08f, 0.1f));
                        DrawItem(new Rect(r.x + 8, r.y + 8, r.width - 16, r.height - 16), (ushort)chk.Options[i].ClientId, 1);
                        if (!bot.Locked && GUI.Button(r, GUIContent.none, GUIStyle.none)) bot.Answer(chk.Options[i].Key);
                    }
                    var ss = new GUIStyle(small) { alignment = TextAnchor.MiddleCenter, fontSize = 13 };
                    ss.normal.textColor = bot.StatusGood ? new Color(0.44f, 0.85f, 0.66f) : bot.StatusBad ? new Color(0.88f, 0.23f, 0.12f) : new Color(0.55f, 0.5f, 0.44f);
                    GUI.Label(new Rect(8, 176, box.width - 16, 24), bot.Status, ss);
                    bool canAnother = chk.Retries > 0 && !bot.Locked;
                    GUI.enabled = canAnother;
                    if (GUI.Button(new Rect(box.width / 2 - 90, 214, 180, 28), Antibot.RetryText(chk.Retries))) bot.Another();
                    GUI.enabled = true;
                }, GUIContent.none, GUIStyle.none);
                GUI.BringWindowToFront(CheckWindowId);
            }
            if (bot.ReportOpen)
            {
                if (!reportWasOpen) { reportNameEdit = bot.ReportName; reportWasOpen = true; }
                var box = new Rect(w / 2 - 200, h / 2 - 190, 400, 400);
                uiRects.Add(Scaled(box, scale));
                GUI.Window(ReportWindowId, box, _ =>
                {
                    Fill(new Rect(0, 0, box.width, box.height), new Color(0.04f, 0.03f, 0.05f, 0.97f));
                    Fill(new Rect(0, 0, box.width, 24), new Color(0.16f, 0.09f, 0.06f, 1f));
                    GUI.Label(new Rect(8, 2, box.width - 40, 22), Loc.T("Report Player"), titleStyle);
                    if (GUI.Button(new Rect(box.width - 26, 2, 22, 20), "x")) bot.ReportOpen = false;
                    GUI.Label(new Rect(10, 32, 120, 20), Loc.T("Character"), small);
                    GUI.SetNextControlName("reportName");
                    reportNameEdit = GUI.TextField(new Rect(10, 52, box.width - 20, 24), reportNameEdit ?? "", 29);
                    GUI.Label(new Rect(10, 82, 120, 20), Loc.T("Reason"), small);
                    int per = 2;
                    float rw = (box.width - 24) / per;
                    for (int i = 0; i < bot.Reasons.Count; i++)
                    {
                        var rr = bot.Reasons[i];
                        var r = new Rect(10 + (i % per) * (rw + 4), 104 + (i / per) * 28, rw, 26);
                        if (GUI.Toggle(r, reportReason == rr.Key, Loc.T(rr.Name), GUI.skin.button)) reportReason = rr.Key;
                    }
                    float ny = 104 + ((bot.Reasons.Count + per - 1) / per) * 28 + 8;
                    GUI.Label(new Rect(10, ny, 160, 20), Loc.T("Note"), small);
                    var cs = new GUIStyle(hudTiny) { alignment = TextAnchor.MiddleRight };
                    GUI.Label(new Rect(box.width - 90, ny, 80, 20), Antibot.NoteCounter(reportNote, bot.ReportNoteMax), cs);
                    GUI.SetNextControlName("reportNote");
                    reportNote = GUI.TextArea(new Rect(10, ny + 22, box.width - 20, 70), reportNote ?? "", bot.ReportNoteMax);
                    string focus = GUI.GetNameOfFocusedControl();
                    if (focus == "reportName" || focus == "reportNote") MarkTextEditing();
                    var ss = new GUIStyle(small) { fontSize = 13, wordWrap = true };
                    ss.normal.textColor = bot.ReportStatusGood ? new Color(0.44f, 0.85f, 0.66f) : new Color(0.88f, 0.23f, 0.12f);
                    GUI.Label(new Rect(10, ny + 98, box.width - 20, 36), bot.ReportStatus, ss);
                    GUI.enabled = !bot.ReportSent;
                    if (GUI.Button(new Rect(10, box.height - 38, 180, 28), Loc.T("Send report")))
                        bot.SendReport(reportNameEdit, reportReason, reportNote, world?.Player?.Name);
                    GUI.enabled = true;
                    if (GUI.Button(new Rect(box.width - 190, box.height - 38, 180, 28), Loc.T("Close"))) bot.ReportOpen = false;
                }, GUIContent.none, GUIStyle.none);
            }
            else reportWasOpen = false;
        }
    }
}
