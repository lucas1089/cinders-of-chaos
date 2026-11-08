// Windows of the base gameplay actions (track P): the player trade window, the VIP list, the quest log and the look preview. Models: Core/PlayLists.cs, Core/PlayLook.cs.
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>Player trade: your offer and the other player's side by side, a click on an item looks at it (0x7E), Accept (0x7F) and Reject (0x80).
    /// Opens by itself when the server opens the trade (0x7D) and closes with it (0x7F). Closing it with the x rejects.</summary>
    public sealed class TradeWindow : GameWindow
    {
        public override string Title => Loc.T("Trade");
        public override bool InMenu => false;
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 230, 120, 460, 330);

        bool lastTradeOpen, lastOpen;
        Vector2 scrollOwn, scrollOther;
        const float Cell = 36;

        public override void Reset() { lastTradeOpen = false; lastOpen = false; Open = false; }

        public override void Tick(ChaosApp app)
        {
            var t = app.Session?.PlayerTrade;
            if (t == null) return;
            if (t.Open && !lastTradeOpen) Open = true;
            else if (!t.Open && lastTradeOpen) Open = false;
            else if (t.Open && lastOpen && !Open) t.Close();   // the x: reject
            lastTradeOpen = t.Open;
            lastOpen = Open;
        }

        void Side(ChaosApp app, PlayerTradeState t, TradeSide side, bool counter, Rect r, ref Vector2 scroll)
        {
            GUI.Label(new Rect(r.x, r.y, r.width, 20), PlayerTradeState.Header(side, !counter), app.SmallStyle);
            var box = new Rect(r.x, r.y + 22, r.width, r.height - 22);
            ChaosApp.Fill(box, new Color(0.08f, 0.06f, 0.09f, 1f));
            int perRow = Mathf.Max(1, (int)((box.width - 16) / (Cell + 3)));
            int rows = Mathf.Max(1, (side.Items.Count + perRow - 1) / perRow);
            var view = new Rect(0, 0, box.width - 16, rows * (Cell + 3) + 4);
            scroll = GUI.BeginScrollView(box, scroll, view);
            for (int i = 0; i < side.Items.Count; i++)
            {
                var it = side.Items[i];
                var cell = new Rect(3 + (i % perRow) * (Cell + 3), 3 + (i / perRow) * (Cell + 3), Cell, Cell);
                ChaosApp.Fill(cell, new Color(0.13f, 0.1f, 0.14f, 1f));
                if (Event.current.type == EventType.Repaint) app.DrawItem(cell, (ushort)it.Id, it.Count);
                if (cell.Contains(Event.current.mousePosition) && Event.current.type == EventType.MouseDown && Event.current.button == 0)
                {
                    t.LookAt(counter, i);
                    Event.current.Use();
                }
            }
            GUI.EndScrollView();
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var t = app.Session?.PlayerTrade;
            if (t == null || !t.Open) { GUI.Label(new Rect(inner.x + 8, inner.y + 8, inner.width - 16, 22), Loc.T("No trade is open."), app.SmallStyle); return; }
            float half = (inner.width - 12) / 2, h = inner.height - 70;
            Side(app, t, t.Own, false, new Rect(inner.x + 2, inner.y, half, h), ref scrollOwn);
            Side(app, t, t.Counter, true, new Rect(inner.x + 10 + half, inner.y, half, h), ref scrollOther);
            float y = inner.y + h + 6;
            string note = t.Accepted ? Loc.T("You accepted. Waiting for {0}.", string.IsNullOrEmpty(t.Counter.Name) ? "?" : t.Counter.Name)
                : t.Counter.Items.Count == 0 ? Loc.T("Waiting for the other offer.") : Loc.T("Click an item to look at it. Accept when both offers are right.");
            GUI.Label(new Rect(inner.x + 4, y, inner.width - 8, 20), note, app.SmallStyle);
            GUI.enabled = !t.Accepted && t.Own.Items.Count > 0 && t.Counter.Items.Count > 0;
            if (GUI.Button(new Rect(inner.x + 4, y + 26, 100, 26), Loc.T("Accept"))) t.Accept();
            GUI.enabled = true;
            if (GUI.Button(new Rect(inner.x + 112, y + 26, 100, 26), Loc.T("Reject"))) { t.Close(); Open = false; }
        }
    }

    /// <summary>The VIP list: friends with their online state, add by name, edit (description, icon, notify), remove, and a click to talk in private.</summary>
    public sealed class VipWindow : GameWindow
    {
        public override string Title => Loc.T("VIP List");
        protected override Rect Place(float w, float h) => new Rect(8, 200, 250, 340);

        string addText = "", filter = "", editText = "";
        uint editing;
        int editIcon;
        bool editNotify;
        Vector2 scroll;
        GUIStyle faint;

        public override void Reset() { addText = ""; filter = ""; editing = 0; scroll = Vector2.zero; Open = false; }

        static Color Dot(VipEntry e) => e.Status == 1 ? new Color(0.35f, 0.85f, 0.35f) : e.Status == 2 ? new Color(0.9f, 0.75f, 0.25f) : new Color(0.5f, 0.5f, 0.52f);

        protected override void Body(ChaosApp app, Rect inner)
        {
            var vip = app.Session?.Vip;
            if (vip == null) return;
            if (faint == null) faint = new GUIStyle(app.SmallStyle) { fontSize = 11 };
            float x = inner.x + 4, y = inner.y + 2, w = inner.width - 8;
            GUI.SetNextControlName("vipAdd");
            addText = GUI.TextField(new Rect(x, y, w - 56, 24), addText, VipState.MaxName);
            if (GUI.GetNameOfFocusedControl() == "vipAdd") app.MarkTextEditing();
            string why = addText.Length == 0 ? "" : vip.CheckName(addText);
            GUI.enabled = addText.Trim().Length > 0 && why.Length == 0;
            bool enter = GUI.GetNameOfFocusedControl() == "vipAdd" && Event.current.type == EventType.KeyDown && Event.current.keyCode == KeyCode.Return;
            if (GUI.Button(new Rect(x + w - 52, y, 52, 24), Loc.T("Add")) || (enter && GUI.enabled)) { vip.Add(addText); addText = ""; if (enter) Event.current.Use(); }
            GUI.enabled = true;
            y += 28;
            if (why.Length > 0) { GUI.Label(new Rect(x, y, w, 18), why, faint); y += 18; }
            GUI.Label(new Rect(x, y, w, 20), Loc.T("{0} online of {1}", vip.OnlineCount(), vip.Count), faint);
            y += 22;
            float bottom = editing != 0 ? 118 : 0;
            var list = vip.Sorted(filter);
            var area = new Rect(x, y, w, inner.yMax - y - bottom);
            var view = new Rect(0, 0, w - 16, Mathf.Max(area.height, list.Count * 24f));
            scroll = GUI.BeginScrollView(area, scroll, view);
            var e = Event.current;
            for (int i = 0; i < list.Count; i++)
            {
                var v = list[i];
                var row = new Rect(0, i * 24, w - 16, 23);
                bool over = row.Contains(e.mousePosition);
                if (e.type == EventType.Repaint)
                {
                    ChaosApp.Fill(row, over ? new Color(0.2f, 0.15f, 0.12f, 1f) : new Color(0.09f, 0.07f, 0.1f, 1f));
                    ChaosApp.Fill(new Rect(row.x + 5, row.y + 8, 8, 8), Dot(v));
                    GUI.Label(new Rect(row.x + 18, row.y + 1, row.width - 40, 22), v.Name, app.SmallStyle);
                    if (v.Notify) GUI.Label(new Rect(row.xMax - 22, row.y + 1, 20, 22), "!", faint);
                }
                if (over && e.type == EventType.MouseDown)
                {
                    if (e.button == 0 && e.clickCount >= 2) { app.Session.Talks.OpenPrivate(v.Name, true); e.Use(); }
                    else if (e.button == 1)
                    {
                        var vv = v;
                        var at = new Vector2(e.mousePosition.x + Area.x + area.x - scroll.x, e.mousePosition.y + Area.y + area.y - scroll.y);
                        app.ShowMenu(at, new List<KeyValuePair<string, Action>>
                        {
                            new KeyValuePair<string, Action>(Loc.T("Send message"), () => app.Session.Talks.OpenPrivate(vv.Name, true)),
                            new KeyValuePair<string, Action>(Loc.T("Edit"), () => { editing = vv.Guid; editText = vv.Description; editIcon = vv.Icon; editNotify = vv.Notify; }),
                            new KeyValuePair<string, Action>(Loc.T("Remove"), () => { vip.Remove(vv.Guid); if (editing == vv.Guid) editing = 0; }),
                            new KeyValuePair<string, Action>(Loc.T("Copy Name"), () => GUIUtility.systemCopyBuffer = vv.Name),
                        });
                        e.Use();
                    }
                }
            }
            GUI.EndScrollView();
            if (list.Count == 0) GUI.Label(new Rect(x + 4, y + 4, w - 8, 40), vip.Count == 0 ? Loc.T("Add the names of your friends to see when they are online.") : Loc.T("Nobody matches."), faint);
            if (editing != 0) Editor(app, vip, new Rect(x, inner.yMax - 114, w, 112));
        }

        void Editor(ChaosApp app, VipState vip, Rect r)
        {
            var v = vip.Get(editing);
            if (v == null) { editing = 0; return; }
            ChaosApp.Fill(r, new Color(0.12f, 0.09f, 0.12f, 1f));
            GUI.Label(new Rect(r.x + 6, r.y + 2, r.width - 12, 20), Loc.T("Edit {0}", v.Name), app.SmallStyle);
            GUI.SetNextControlName("vipEdit");
            editText = GUI.TextField(new Rect(r.x + 6, r.y + 24, r.width - 12, 24), editText, VipState.MaxDescription);
            if (GUI.GetNameOfFocusedControl() == "vipEdit") app.MarkTextEditing();
            if (GUI.Button(new Rect(r.x + 6, r.y + 52, 26, 22), "<")) editIcon = (editIcon + VipState.MaxIcon) % (VipState.MaxIcon + 1);
            GUI.Label(new Rect(r.x + 36, r.y + 52, 90, 22), Loc.T("Icon {0}", editIcon), app.SmallStyle);
            if (GUI.Button(new Rect(r.x + 112, r.y + 52, 26, 22), ">")) editIcon = (editIcon + 1) % (VipState.MaxIcon + 1);
            editNotify = GUI.Toggle(new Rect(r.x + 146, r.y + 52, r.width - 150, 22), editNotify, Loc.T("Tell me when they log in"));
            if (GUI.Button(new Rect(r.x + 6, r.y + 80, 70, 24), Loc.T("Save"))) { vip.Edit(editing, editText, editIcon, editNotify); editing = 0; }
            if (GUI.Button(new Rect(r.x + 82, r.y + 80, 70, 24), Loc.T("Cancel"))) editing = 0;
        }
    }

    /// <summary>The quest log: the quests with a done mark on the left, the missions of the picked one on the right. Opening it asks the server (0xF0), a pick asks the lines (0xF1).</summary>
    public sealed class QuestLogWindow : GameWindow
    {
        public override string Title => Loc.T("Quest Log");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 300, 70, 600, 440);

        Vector2 scrollList, scrollText;
        bool wasOpen;
        GUIStyle wrap;

        public override void Reset() { wasOpen = false; scrollList = scrollText = Vector2.zero; Open = false; }

        public override void Tick(ChaosApp app)
        {
            var q = app.Session?.Quests;
            if (q == null) return;
            if (Open && !wasOpen) q.Request();
            wasOpen = Open;
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var q = app.Session?.Quests;
            if (q == null) return;
            if (wrap == null) wrap = new GUIStyle(app.SmallStyle) { wordWrap = true, fontSize = 12, alignment = TextAnchor.UpperLeft };
            q.HideCompleted = GUI.Toggle(new Rect(inner.x + 6, inner.y + 2, 200, 22), q.HideCompleted, Loc.T("Hide completed quests"));
            if (GUI.Button(new Rect(inner.xMax - 90, inner.y + 2, 84, 22), Loc.T("Refresh"))) q.Request();
            GUI.Label(new Rect(inner.x + 210, inner.y + 2, inner.width - 310, 22), q.Loaded ? q.Summary() : Loc.T("Loading..."), app.SmallStyle);
            float top = inner.y + 28, listW = 230;
            var left = new Rect(inner.x + 4, top, listW, inner.yMax - top - 4);
            var right = new Rect(inner.x + listW + 12, top, inner.width - listW - 16, inner.yMax - top - 4);
            ChaosApp.Fill(left, new Color(0.08f, 0.06f, 0.09f, 1f));
            ChaosApp.Fill(right, new Color(0.08f, 0.06f, 0.09f, 1f));
            var list = q.Visible();
            scrollList = GUI.BeginScrollView(left, scrollList, new Rect(0, 0, listW - 16, Mathf.Max(left.height, list.Count * 24f)));
            var e = Event.current;
            for (int i = 0; i < list.Count; i++)
            {
                var it = list[i];
                var row = new Rect(0, i * 24, listW - 16, 23);
                bool sel = q.Selected == it.Id;
                if (e.type == EventType.Repaint)
                {
                    ChaosApp.Fill(row, sel ? new Color(0.3f, 0.2f, 0.12f, 1f) : row.Contains(e.mousePosition) ? new Color(0.2f, 0.15f, 0.12f, 1f) : new Color(0.1f, 0.08f, 0.11f, 1f));
                    string mark = it.Completed ? "<color=#7fe07f>x</color> " : "  ";
                    var st = new GUIStyle(app.SmallStyle) { richText = true, fontSize = 12 };
                    GUI.Label(new Rect(row.x + 4, row.y + 1, row.width - 6, 22), mark + it.Name.Replace("<", "<​"), st);
                }
                if (e.type == EventType.MouseDown && e.button == 0 && row.Contains(e.mousePosition)) { q.Select(it.Id); e.Use(); }
            }
            GUI.EndScrollView();
            if (q.Selected < 0) { GUI.Label(new Rect(right.x + 8, right.y + 8, right.width - 16, 40), Loc.T("Pick a quest to read its missions."), wrap); return; }
            var ms = q.Missions((ushort)q.Selected);
            if (ms == null) { GUI.Label(new Rect(right.x + 8, right.y + 8, right.width - 16, 22), Loc.T("Loading..."), wrap); return; }
            float tw = right.width - 24, y = 4;
            foreach (var m in ms) y += wrap.CalcHeight(new GUIContent(m.Name), tw) + wrap.CalcHeight(new GUIContent(m.Description), tw) + 10;
            scrollText = GUI.BeginScrollView(right, scrollText, new Rect(0, 0, tw, Mathf.Max(right.height, y)));
            y = 4;
            var bold = new GUIStyle(wrap) { fontStyle = FontStyle.Bold };
            foreach (var m in ms)
            {
                float h1 = bold.CalcHeight(new GUIContent(m.Name), tw);
                GUI.Label(new Rect(6, y, tw, h1), m.Name, bold);
                y += h1;
                float h2 = wrap.CalcHeight(new GUIContent(m.Description), tw);
                GUI.Label(new Rect(6, y, tw, h2), m.Description, wrap);
                y += h2 + 10;
            }
            GUI.EndScrollView();
        }
    }

    /// <summary>The shared look preview: your character with the option another window picked (an outfit, a mount, wings, an aura, a shader or a store bundle), turn buttons and
    /// the plain figure. Other windows call ChaosApp.ShowLookPreview. The map's effect stage and the shader are not drawn: the panel lists what the look changes.</summary>
    public sealed class LookPreviewWindow : GameWindow
    {
        public override string Title => Loc.T("Look Preview");
        public override bool InMenu => false;
        protected override Rect Place(float w, float h) => new Rect(w - 360, 330, 220, 330);

        public PreviewOption Option;
        public bool Simple, AutoTurn;
        int facing = LookPreview.South;
        double lastTurn;

        public override void Reset() { Option = null; Simple = false; AutoTurn = false; facing = LookPreview.South; Open = false; }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var me = app.World?.Player;
            if (me == null) return;
            if (AutoTurn && Time.realtimeSinceStartupAsDouble * 1000 - lastTurn > LookPreview.AutoTurnMs) { facing = LookPreview.Turn(facing, 1); lastTurn = Time.realtimeSinceStartupAsDouble * 1000; }
            var o = LookPreview.Compose(Simple, me.Outfit, Option, null, out string note);
            var stage = new Rect(inner.x + 20, inner.y + 4, inner.width - 40, inner.width - 40);
            ChaosApp.Fill(stage, new Color(0.07f, 0.06f, 0.08f, 1f));
            app.DrawOutfit(new Rect(stage.x + 8, stage.y + 8, stage.width - 16, stage.height - 16), o, (Dir)facing);
            float y = stage.yMax + 6;
            if (GUI.Button(new Rect(inner.x + 6, y, 34, 24), "<")) facing = LookPreview.Turn(facing, -1);
            if (GUI.Button(new Rect(inner.x + 44, y, 34, 24), ">")) facing = LookPreview.Turn(facing, 1);
            AutoTurn = GUI.Toggle(new Rect(inner.x + 86, y, inner.width - 92, 24), AutoTurn, Loc.T("Slow turn"));
            y += 28;
            bool wearer = LookPreview.HasWearer(Option);
            GUI.enabled = wearer;
            Simple = GUI.Toggle(new Rect(inner.x + 6, y, inner.width - 12, 22), Simple && wearer, Loc.T("Plain figure"));
            GUI.enabled = true;
            y += 24;
            var st = new GUIStyle(app.SmallStyle) { wordWrap = true, fontSize = 11 };
            string what = Loc.T("Look {0}, addons {1}", o.LookType, o.Addons);
            if (o.Mount > 0) what += ", " + Loc.T("mount {0}", o.Mount);
            if (o.Wings > 0) what += ", " + Loc.T("wings {0}", o.Wings);
            if (o.Aura > 0) what += ", " + Loc.T("aura {0}", o.Aura);
            if (!string.IsNullOrEmpty(o.Shader)) what += ", " + Loc.T("shader {0}", o.Shader);
            GUI.Label(new Rect(inner.x + 6, y, inner.width - 12, 36), what, st);
            y += 36;
            if (note != null) GUI.Label(new Rect(inner.x + 6, y, inner.width - 12, 40), note, st);
        }
    }
}
