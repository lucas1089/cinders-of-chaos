// NPC trade window: the buy and sell list of an NPC shop (0x7A, 0x7B, Core/NpcTrade.cs), the way the main client's
// game_npctradewindow shows it. Buy and Sell tabs, search, a row per item (sprite, name, price, weight), an amount slider
// bounded by money, capacity and stock, the total price and an OK button. It opens when the NPC opens its shop and sends
// 0x7C when it is closed here. The balance is the player's money (cash plus bank), or the NPC's own currency (opcode 113).
// Texts go through Loc.T (English and pt-BR).
using System.Globalization;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class NpcTradeWindow : GameWindow
    {
        const float Row = 40f;
        TradeMode mode = TradeMode.Buy;
        string search = "";
        Vector2 scroll;
        ShopItem selected;
        int amount = 1;
        bool ignoreCap, ignoreEquipped = true;
        int seenVersion = -1;
        bool wasOpen;
        GUIStyle nameStyle, infoStyle, rightStyle;

        public override string Title => Loc.T("Trade");

        protected override Rect Place(float w, float h) => new Rect(w * 0.5f - 210f, 60f, 420f, 500f);

        public override void Reset()
        {
            mode = TradeMode.Buy;
            search = "";
            selected = null;
            amount = 1;
            seenVersion = -1;
            wasOpen = false;
        }

        public override void Tick(ChaosApp app)
        {
            var session = app.Session;
            if (session == null) return;
            var trade = session.Parser.Trade;
            if (trade.Version != seenVersion)
            {
                seenVersion = trade.Version;
                // keep the selected row when the list was refreshed after a purchase, else forget it
                if (selected != null) selected = trade.Items.Find(i => i.Id == selected.Id && i.SubType == selected.SubType);
            }
            if (trade.Open && !wasOpen)
            {
                Open = true;
                mode = TradeMode.Buy;
                selected = null;
                search = "";
            }
            // closed with the x or the toolbar: tell the server
            if (!Open && trade.Open) session.NpcClose();
            if (!trade.Open && Open && wasOpen) Open = false;   // the server (or walking away) closed the shop
            wasOpen = trade.Open;
        }

        static string Num(ulong v) => v.ToString("N0", CultureInfo.InvariantCulture);

        string Weight(uint w) => (w / 100f).ToString("0.00", CultureInfo.InvariantCulture) + " oz";

        protected override void Body(ChaosApp app, Rect inner)
        {
            var session = app.Session;
            if (session == null) return;
            var trade = session.Parser.Trade;
            if (nameStyle == null)
            {
                nameStyle = new GUIStyle(app.SmallStyle) { fontSize = 13, fontStyle = FontStyle.Bold };
                infoStyle = new GUIStyle(app.SmallStyle) { fontSize = 11 };
                infoStyle.normal.textColor = new Color(1f, 1f, 1f, 0.6f);
                rightStyle = new GUIStyle(app.SmallStyle) { alignment = TextAnchor.UpperRight };
            }
            if (!trade.Open)
            {
                GUI.Label(new Rect(inner.x + 8, inner.y + 8, inner.width - 16, 24), Loc.T("No shop is open. Say hi and trade to an NPC."), app.SmallStyle);
                return;
            }
            var e = Event.current;
            uint freeCap = session.Parser.FreeCap;
            float x = inner.x + 4, w = inner.width - 8, y = inner.y;

            // header: the NPC and the balance
            GUI.Label(new Rect(x, y, w * 0.5f, 20), trade.Npc, nameStyle);
            string cur = trade.Gold ? Loc.T("Gold") : trade.Currency.Name;
            GUI.Label(new Rect(x + w * 0.4f, y, w * 0.6f, 20), Loc.T("{0}: {1}", cur, Num(trade.Balance)), rightStyle);
            y += 22;
            GUI.Label(new Rect(x + w * 0.45f, y, w * 0.55f, 20), Loc.T("Capacity: {0}", Weight(freeCap)), rightStyle);

            // tabs
            if (GUI.Toggle(new Rect(x, y, 80, 24), mode == TradeMode.Buy, Loc.T("Buy"), GUI.skin.button) && mode != TradeMode.Buy) SetMode(TradeMode.Buy);
            if (GUI.Toggle(new Rect(x + 84, y, 80, 24), mode == TradeMode.Sell, Loc.T("Sell"), GUI.skin.button) && mode != TradeMode.Sell) SetMode(TradeMode.Sell);
            y += 28;

            // search
            GUI.Label(new Rect(x, y + 2, 60, 22), Loc.T("Search"), app.SmallStyle);
            GUI.SetNextControlName("tradeSearch");
            search = GUI.TextField(new Rect(x + 60, y, w - 60, 24), search, 40);
            if (GUI.GetNameOfFocusedControl() == "tradeSearch") app.MarkTextEditing();
            y += 28;

            // list
            float footer = 118;
            var listRect = new Rect(x, y, w, inner.yMax - y - footer);
            var rows = trade.List(mode, search);
            ChaosApp.Fill(listRect, new Color(0f, 0f, 0f, 0.35f));
            if (rows.Count == 0)
                GUI.Label(new Rect(listRect.x + 8, listRect.y + 6, listRect.width - 16, 40),
                          mode == TradeMode.Buy ? Loc.T("Nothing for sale.") : Loc.T("The NPC buys nothing you carry."), app.SmallStyle);
            float contentW = listRect.width - 18;
            scroll = GUI.BeginScrollView(listRect, scroll, new Rect(0, 0, contentW, Mathf.Max(listRect.height, rows.Count * Row)));
            for (int i = 0; i < rows.Count; i++)
            {
                var it = rows[i];
                var row = new Rect(0, i * Row, contentW, Row - 2);
                bool sel = selected != null && selected.Id == it.Id && selected.SubType == it.SubType;
                bool afford = mode == TradeMode.Sell || trade.Balance >= it.Buy;
                if (e.type == EventType.Repaint)
                {
                    ChaosApp.Fill(row, sel ? new Color(0.35f, 0.24f, 0.1f, 0.9f) : new Color(1f, 1f, 1f, 0.05f));
                    app.DrawItem(new Rect(row.x + 4, row.y + 4, 32, 32), it.Id, mode == TradeMode.Sell ? trade.GoodsCount(it.Id) : 1);
                    var old = GUI.color;
                    if (!afford) GUI.color = new Color(1f, 1f, 1f, 0.45f);
                    GUI.Label(new Rect(row.x + 42, row.y + 2, row.width - 46, 18), it.Name, nameStyle);
                    string info = Loc.T("Price {0}", Num(NpcTradeState.Price(it, mode)));
                    if (it.Weight > 0) info += ", " + Weight(it.Weight);
                    GUI.Label(new Rect(row.x + 42, row.y + 20, row.width - 46, 16), info, infoStyle);
                    GUI.color = old;
                }
                else if (e.type == EventType.MouseDown && row.Contains(e.mousePosition))
                {
                    if (e.button == 1) session.NpcLook(it);
                    else { selected = it; amount = 1; }
                    e.Use();
                }
            }
            GUI.EndScrollView();

            // footer: amount, total, options, OK
            y = listRect.yMax + 6;
            int max = trade.Max(selected, mode, freeCap, ignoreCap);
            amount = NpcTradeState.ClampAmount(amount, max);
            GUI.Label(new Rect(x, y, 80, 20), Loc.T("Amount"), app.SmallStyle);
            if (max > 1)
                amount = Mathf.RoundToInt(GUI.HorizontalSlider(new Rect(x + 80, y + 5, w - 150, 16), amount, 1, max));
            GUI.Label(new Rect(x + w - 66, y, 66, 20), amount.ToString(CultureInfo.InvariantCulture) + " / " + max, rightStyle);
            y += 24;
            ulong total = NpcTradeState.Total(selected, amount, mode);
            GUI.Label(new Rect(x, y, w, 20), Loc.T("Total: {0}", Num(total)), nameStyle);
            y += 22;
            string block = null;
            if (mode == TradeMode.Buy)
            {
                ignoreCap = GUI.Toggle(new Rect(x, y, w * 0.6f, 20), ignoreCap, Loc.T("Ignore capacity"));
                if (selected != null) block = trade.BuyBlock(selected, amount, freeCap, ignoreCap);
            }
            else
            {
                ignoreEquipped = GUI.Toggle(new Rect(x, y, w * 0.6f, 20), ignoreEquipped, Loc.T("Ignore equipped"));
                if (selected != null) block = trade.SellBlock(selected, amount);
            }
            var hint = block == "money" ? Loc.T("Not enough money.") : block == "capacity" ? Loc.T("Not enough capacity.") : "";
            GUI.Label(new Rect(x + w * 0.4f, y, w * 0.6f - 70, 20), hint, rightStyle);
            bool can = selected != null && block == null;
            var was = GUI.enabled;
            GUI.enabled = can;
            if (GUI.Button(new Rect(x + w - 64, y - 2, 64, 24), Loc.T("OK")))
            {
                if (mode == TradeMode.Buy) session.NpcBuy(selected, amount, ignoreCap);
                else session.NpcSell(selected, amount, ignoreEquipped);
            }
            GUI.enabled = was;
        }

        void SetMode(TradeMode m)
        {
            mode = m;
            selected = null;
            amount = 1;
            scroll = Vector2.zero;
        }
    }
}
