// Bank (Ctrl+J): the gold carried and in the bank, Deposit, Withdraw and Transfer with an amount box (digits, slider, 25% / 50% / All), Deposit all and
// Withdraw all. The server (extended opcode 60, Core/Bank.cs) does the maths and checks every amount. The banker NPC opens the window.
using System;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>Keeps a GameWindow's Open flag and a state object's Visible flag in step: a change made by the server (an NPC opens the window) or
    /// by the toolbar and hotkey (Open) wins, whichever happened since the last call.</summary>
    static class WindowSync
    {
        public static void Run(ref bool last, GameWindow win, bool visible, Action show, Action hide)
        {
            if (visible != last) win.Open = visible;
            else if (win.Open != visible) { if (win.Open) show(); else hide(); }
            last = visible;
        }
    }

    public sealed class BankWindow : GameWindow
    {
        public const int GoldItem = 3031;   // client id of the gold coin icon (as the main client's bank)

        public override string Title => Loc.T("Bank");
        public override KeyCode Hotkey => KeyCode.J;
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 170, 90, 340, 330);

        bool lastVisible;
        BankMode? mode;
        string amountText = "", recipient = "";
        GUIStyle big;

        public override void Reset() { lastVisible = false; mode = null; amountText = ""; recipient = ""; Open = false; }

        public override void Tick(ChaosApp app)
        {
            var bank = app.Session?.Bank;
            if (bank == null) return;
            WindowSync.Run(ref lastVisible, this, bank.Visible, bank.Show, bank.Hide);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var bank = app.Session?.Bank;
            if (bank == null) return;
            if (big == null) big = new GUIStyle(app.SmallStyle) { fontSize = 17, fontStyle = FontStyle.Bold };
            float y = inner.y + 4;
            Row(app, new Rect(inner.x + 4, y, inner.width - 8, 30), Loc.T("Gold you carry"), bank.HasState ? bank.GoldCarried.ToString("N0") : "-");
            Row(app, new Rect(inner.x + 4, y + 34, inner.width - 8, 30), Loc.T("Gold in the bank"), bank.HasState ? bank.GoldBank.ToString("N0") : "-");
            y += 74;
            float bw = (inner.width - 8 - 12) / 3;
            string[] labels = { Loc.T("Deposit"), Loc.T("Withdraw"), Loc.T("Transfer") };
            for (int i = 0; i < 3; i++)
                if (GUI.Toggle(new Rect(inner.x + 4 + i * (bw + 6), y, bw, 28), mode == (BankMode)i, labels[i], GUI.skin.button) && mode != (BankMode)i) { mode = (BankMode)i; amountText = ""; }
            y += 34;
            GUI.enabled = bank.HasState && bank.GoldCarried > 0;
            if (GUI.Button(new Rect(inner.x + 4, y, (inner.width - 14) / 2, 26), Loc.T("Deposit all"))) bank.DepositAll();
            GUI.enabled = bank.HasState && bank.GoldBank > 0;
            if (GUI.Button(new Rect(inner.x + 10 + (inner.width - 14) / 2, y, (inner.width - 14) / 2, 26), Loc.T("Withdraw all"))) bank.WithdrawAll();
            GUI.enabled = true;
            y += 36;
            if (mode == null) { GUI.Label(new Rect(inner.x + 4, y, inner.width - 8, 40), Loc.T("Pick Deposit, Withdraw or Transfer to type an amount."), app.SmallStyle); return; }

            var m = mode.Value;
            long max = bank.Limit(m);
            if (m == BankMode.Transfer)
            {
                GUI.Label(new Rect(inner.x + 4, y, 70, 22), Loc.T("To"), app.SmallStyle);
                GUI.SetNextControlName("bankName");
                recipient = GUI.TextField(new Rect(inner.x + 74, y, inner.width - 78, 22), recipient, 30);
                if (GUI.GetNameOfFocusedControl() == "bankName") app.MarkTextEditing();
                y += 28;
            }
            GUI.Label(new Rect(inner.x + 4, y, 70, 22), Loc.T("Amount"), app.SmallStyle);
            GUI.SetNextControlName("bankAmount");
            string typed = GUI.TextField(new Rect(inner.x + 74, y, inner.width - 78, 22), amountText, BankMath.MaxDigits);
            if (GUI.GetNameOfFocusedControl() == "bankAmount") app.MarkTextEditing();
            string digits = BankMath.Digits(typed);
            long amount = BankMath.Parse(digits, max);
            amountText = digits.Length > 0 && long.Parse(digits) > amount ? amount.ToString() : digits;   // over the limit: the box shows the limit
            y += 28;
            long slid = (long)GUI.HorizontalSlider(new Rect(inner.x + 4, y + 4, inner.width - 8, 16), amount, 0, Math.Max(1, max));
            if (slid != amount && max > 0) { amount = Math.Min(slid, max); amountText = amount.ToString(); }
            y += 24;
            float qw = (inner.width - 8 - 12) / 3;
            for (int i = 0; i < BankMath.Quick.Length; i++)
            {
                int pct = BankMath.Quick[i];
                if (GUI.Button(new Rect(inner.x + 4 + i * (qw + 6), y, qw, 24), pct >= 100 ? Loc.T("All") : pct + "%")) { amount = BankMath.QuickAmount(max, pct); amountText = amount.ToString(); }
            }
            y += 32;
            GUI.enabled = amount > 0 && (m != BankMode.Transfer || recipient.Trim().Length >= 2);
            if (GUI.Button(new Rect(inner.x + 4, y, inner.width - 8, 30), labels[(int)m]))
            {
                if (bank.Do(m, amount, recipient)) amountText = "";
            }
            GUI.enabled = true;
        }

        void Row(ChaosApp app, Rect r, string label, string value)
        {
            ChaosApp.Fill(r, new Color(1f, 1f, 1f, 0.05f));
            app.DrawItem(new Rect(r.x + 2, r.y + 1, 28, 28), GoldItem, 1);
            GUI.Label(new Rect(r.x + 36, r.y + 6, r.width * 0.5f, 22), label, app.SmallStyle);
            var st = new GUIStyle(big) { alignment = TextAnchor.MiddleRight };
            st.normal.textColor = new Color(0.96f, 0.81f, 0.3f);
            GUI.Label(new Rect(r.x + r.width * 0.4f, r.y + 2, r.width * 0.6f - 6, 26), value, st);
        }
    }
}
