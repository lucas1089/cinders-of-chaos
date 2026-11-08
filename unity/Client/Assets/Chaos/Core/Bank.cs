// Bank (client game_bank, extended opcode 60, server bank.lua): deposit, withdraw and transfer gold. The server does the maths and checks every
// amount; this file keeps the amount box's input in step and builds the requests. Gold only (the star currency of the imported client has no use
// in this game).
//
//   client -> server  openBank | deposit [currency, amount] | withdraw [currency, amount] | depositAll [currency] | withdrawAll [currency]
//                     | transfer [currency, playerName, amount]      (data is a JSON array, currency "gold")
//   server -> client  open [goldCarried, goldBank, starBank, starCarried]
//                     npc                                            the banker NPC opens the window
// A reopen within the server's rate limit (300 ms) gets no reply, so the window shows at once with the last state and asks for a fresh one.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class BankMath
    {
        public const int MaxDigits = 10;   // Chaos.bank.maxAmount is 2,000,000,000
        public static readonly int[] Quick = { 25, 50, 100 };

        /// <summary>The digits of a typed text, at most MaxDigits.</summary>
        public static string Digits(string text)
        {
            var sb = new System.Text.StringBuilder();
            foreach (char c in text ?? "") if (c >= '0' && c <= '9' && sb.Length < MaxDigits) sb.Append(c);
            return sb.ToString();
        }

        /// <summary>The typed amount clamped to 0..max.</summary>
        public static long Parse(string text, long max)
        {
            string d = Digits(text);
            long n = d.Length == 0 ? 0 : long.Parse(d, System.Globalization.CultureInfo.InvariantCulture);
            return Math.Min(n, Math.Max(0, max));
        }

        /// <summary>A quick button's amount: pct of max rounded down, 100 is all of it.</summary>
        public static long QuickAmount(long max, int pct)
        {
            max = Math.Max(0, max);
            return pct >= 100 ? max : max * pct / 100;
        }
    }

    public enum BankMode { Deposit, Withdraw, Transfer }

    public sealed class BankState
    {
        public const byte Opcode = 60;
        public const string Gold = "gold";

        readonly ExtOpcodes ext;
        public long GoldCarried, GoldBank, StarBank, StarCarried;
        public bool HasState;
        /// <summary>The window is shown.</summary>
        public bool Visible;
        /// <summary>The player asked and no reply came yet.</summary>
        public bool Pending;
        public int Replies;
        public Action Changed = delegate { };

        public BankState(ExtOpcodes e)
        {
            ext = e;
            ext.On(Opcode, OnMessage);
        }

        void OnMessage(ExtMessage m)
        {
            if (m.Action == "npc") { if (!Visible) Show(); }
            else if (m.Action == "open" && m.Data is List<object> list)
            {
                GoldCarried = Amount(list, 0); GoldBank = Amount(list, 1); StarBank = Amount(list, 2); StarCarried = Amount(list, 3);
                HasState = true;
                Replies++;
                // a reply opens the window only when asked for or already open
                if (Pending || Visible) { Pending = false; Visible = true; }
                Changed();
            }
        }

        static long Amount(List<object> l, int i) => i < l.Count && l[i] is double d && !double.IsNaN(d) ? (long)Math.Max(0, d) : 0;

        /// <summary>Shows the window at once (the last state of this session, else empty) and asks for a fresh state.</summary>
        public void Show()
        {
            Pending = true;
            Visible = true;
            ext.Send(Opcode, "openBank");
        }

        public void Hide() { Visible = false; Pending = false; }
        public void Toggle() { if (Visible) Hide(); else Show(); }

        /// <summary>What the amount box may ask for.</summary>
        public long Limit(BankMode mode) => mode == BankMode.Deposit ? GoldCarried : GoldBank;

        /// <summary>The action and data of a request, or null when there is nothing to send.</summary>
        public static KeyValuePair<string, List<object>>? Request(BankMode mode, long amount, string name)
        {
            if (amount < 1) return null;
            switch (mode)
            {
                case BankMode.Deposit: return new KeyValuePair<string, List<object>>("deposit", new List<object> { Gold, amount });
                case BankMode.Withdraw: return new KeyValuePair<string, List<object>>("withdraw", new List<object> { Gold, amount });
                default:
                    name = (name ?? "").Trim();
                    if (name.Length < 2) return null;
                    return new KeyValuePair<string, List<object>>("transfer", new List<object> { Gold, name, amount });
            }
        }

        /// <summary>Sends a deposit, withdrawal or transfer of the amount (clamped to the limit). False when nothing was sent.</summary>
        public bool Do(BankMode mode, long amount, string name = null)
        {
            amount = Math.Min(amount, Limit(mode));
            var r = Request(mode, amount, name);
            if (r == null) return false;
            return ext.Send(Opcode, r.Value.Key, r.Value.Value);
        }

        public void DepositAll() { ext.Send(Opcode, "depositAll", new List<object> { Gold }); }
        public void WithdrawAll() { ext.Send(Opcode, "withdrawAll", new List<object> { Gold }); }

        /// <summary>A new character must not see this one's balance.</summary>
        public void Clear() { GoldCarried = GoldBank = StarBank = StarCarried = 0; HasState = false; Visible = false; Pending = false; }
    }
}
