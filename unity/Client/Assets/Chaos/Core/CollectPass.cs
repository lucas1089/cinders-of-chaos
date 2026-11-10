// Season Pass (client game_battlepass, extended opcode 227, server seasonpass).
//   client -> server  open | tiers {season} | claim {tier, track (0 free, 1 premium)} | claimAll | buy {what, price, gift?} | giftPrice {what, gift} | frame {on}
//   server -> client  state {season {id, pass, name, tag, status (active|grace|upcoming|soon|...), endsIn, claimEndsIn, startsIn}, tier, maxTier, into, need, premium,
//                     claimed [freeBits, premiumBits] ("1" per claimed tier), daily {list [{text, target, progress, done, xp}], resetIn}, weekly {..},
//                     sources [{name, key, today, cap}], coins, frame {name, on}, offers [{what, name, price, full, owned, why, text, contents, look, item}], open}
//                     tiers {season, total, rows [{tier, free {item?, count?, look?, addons?, kind?, text, color?}, premium {..}}]}  (parts)
//                     giftPrice {what, price, name} | notice {text}
using System;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core
{
    public sealed class PassTiers
    {
        public int Season, Total;
        public readonly Dictionary<int, object> Rows = new Dictionary<int, object>();
        public bool Complete { get { if (Total <= 0) return false; for (int t = 1; t <= Total; t++) if (!Rows.ContainsKey(t)) return false; return true; } }
    }

    public sealed class PassState : CollectModel
    {
        public const byte OpcodeId = 227;
        public const int Free = 0, Premium = 1, MaxTiers = 1000;

        public object State;
        public PassTiers Tiers;
        int tiersAsked = -1;
        public double StateAt;
        public bool Visible, ScrollToCurrent;
        public string Page = "rewards", Notice = "";
        public double NoticeAt;
        /// <summary>The offer a gift price was asked for, and the answer to confirm.</summary>
        public object PendingGiftOffer;
        public string ConfirmText;
        public Dictionary<string, object> ConfirmBuyData;

        public PassState(ExtOpcodes e) : base(e, OpcodeId) { }

        public void Show() { Visible = true; Send("open"); }
        public void Hide() { Visible = false; CancelConfirm(); }
        public void Toggle() { if (Visible) Hide(); else Show(); }
        public void ClaimAll() { Send("claimAll"); }
        public void Claim(int tier, int track) { Send("claim", D("tier", (double)tier, "track", (double)track)); }
        public void SetFrame(bool on) { Send("frame", D("on", on)); }
        public void AskGift(object offer, string name)
        {
            if (string.IsNullOrWhiteSpace(name)) return;
            PendingGiftOffer = offer;
            Send("giftPrice", D("what", CF.G(offer, "what"), "gift", name.Trim()));
        }

        /// <summary>The confirmation text of a buy (own account or a gift) and the packet kept for Confirm.</summary>
        public void AskBuy(object offer, long price, string gift)
        {
            string name = CF.T(offer, "name");
            if (gift != null) ConfirmText = Loc.T("Give {0} to {1} for {2} Chaos Coins?", name, gift, price);
            else if (price < (CF.G(offer, "full") != null ? CF.N(offer, "full") : price)) ConfirmText = Loc.T("Upgrade to {0} for {1} Chaos Coins (the difference to what your account owns)?", name, price);
            else ConfirmText = Loc.T("Buy {0} for {1} Chaos Coins?", name, price);
            ConfirmBuyData = D("what", CF.G(offer, "what"), "price", (double)price);
            if (gift != null) ConfirmBuyData["gift"] = gift;
        }

        public bool Confirm()
        {
            if (ConfirmBuyData == null) return false;
            var d = ConfirmBuyData; ConfirmBuyData = null; ConfirmText = null;
            return Send("buy", d);
        }

        public void CancelConfirm() { ConfirmBuyData = null; ConfirmText = null; }

        public override void Handle(string action, object data)
        {
            switch (action)
            {
                case "state":
                    {
                        if (data is Dictionary<string, object> d)
                            foreach (string k in new[] { "season", "daily", "weekly" }) if (d.ContainsKey(k) && !(d[k] is Dictionary<string, object>)) d.Remove(k);
                        State = data;
                        StateAt = Clock();
                        int id = CF.I(CF.G(data, "season"), "id");
                        if (CF.G(data, "season") != null && (Tiers == null || Tiers.Season != id) && tiersAsked != id) { tiersAsked = id; Send("tiers", D("season", (double)id)); }
                        if (CF.B(data, "open")) { Visible = true; ScrollToCurrent = true; }
                        break;
                    }
                case "tiers": Tiers = MergeTiers(Tiers, data); if (Tiers.Complete) ScrollToCurrent = true; break;
                case "giftPrice":
                    if (PendingGiftOffer != null && CF.Str(CF.G(PendingGiftOffer, "what")) == CF.Str(CF.G(data, "what")))
                    {
                        var o = PendingGiftOffer; PendingGiftOffer = null;
                        AskBuy(o, CF.Long(CF.G(data, "price")), CF.T(data, "name"));
                    }
                    break;
                case "notice": if (CF.T(data, "text").Length > 0) { Notice = CF.T(data, "text"); NoticeAt = Clock(); } break;
            }
        }

        public void Clear() { State = null; Tiers = null; tiersAsked = -1; Visible = false; ConfirmBuyData = null; ConfirmText = null; }

        public static PassTiers MergeTiers(PassTiers cache, object msg)
        {
            if (!(msg is Dictionary<string, object>)) return cache ?? new PassTiers();
            int season = CF.I(msg, "season");
            if (cache == null || cache.Season != season)
                cache = new PassTiers { Season = season, Total = Math.Max(0, Math.Min((int)Math.Floor(CF.N(msg, "total")), MaxTiers)) };
            foreach (var r in CF.Rows(CF.G(msg, "rows"))) if (CF.G(r, "tier") != null) cache.Rows[CF.I(r, "tier")] = r;
            return cache;
        }

        // ---------------------------------------------------------------------------------------------- the view rules
        public object Season => CF.G(State, "season");
        public string SeasonStatus => CF.T(Season, "status");
        public int Tier => CF.I(State, "tier");
        public int MaxTier => CF.I(State, "maxTier");
        public bool HasPremium => CF.B(State, "premium");

        /// <summary>claimed | claimable | premium | locked | closed.</summary>
        public static string CellState(object state, int tier, int track)
        {
            var claimed = CF.Raw(CF.G(state, "claimed"));
            string bits = track < claimed.Count && claimed[track] is string s ? s : "";
            if (tier >= 1 && tier <= bits.Length && bits[tier - 1] == '1') return "claimed";
            if (tier > CF.I(state, "tier")) return "locked";
            if (track == Premium && !CF.B(state, "premium")) return "premium";
            string st = CF.T(CF.G(state, "season"), "status");
            if (st != "active" && st != "grace") return "closed";
            return "claimable";
        }

        public static int ClaimableCount(object state)
        {
            int n = 0, top = Math.Min(CF.I(state, "tier"), CF.I(state, "maxTier"));
            for (int t = 1; t <= top; t++) { if (CellState(state, t, Free) == "claimable") n++; if (CellState(state, t, Premium) == "claimable") n++; }
            return n;
        }

        public static string FormatTime(double seconds)
        {
            long s = (long)Math.Max(0, Math.Floor(seconds));
            long d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60;
            return d > 0 ? string.Format("{0}d {1:00}h {2:00}m", d, h, m) : string.Format("{0}h {1:00}m {2:00}s", h, m, s % 60);
        }

        public static double Left(double sent, double passed) => Math.Max(0, sent - Math.Max(0, passed));

        public static int Progress(object state, out string text)
        {
            int tier = CF.I(state, "tier"), max = CF.I(state, "maxTier");
            if (max > 0 && tier >= max) { text = Loc.T("Max tier reached"); return 100; }
            double into = CF.N(state, "into"), need = CF.N(state, "need");
            if (need <= 0) { text = ""; return 0; }
            text = Loc.T("{0} / {1} XP to tier {2}", (long)into, (long)need, tier + 1);
            return (int)Math.Floor(into * 100 / need);
        }

        /// <summary>The line above the bars: ends in, claim within, starts in, coming soon.</summary>
        public string TimerText(double nowMs)
        {
            double passed = (nowMs - StateAt) / 1000.0;
            switch (SeasonStatus)
            {
                case "active": return Loc.T("Season ends in {0}", FormatTime(Left(CF.N(Season, "endsIn"), passed)));
                case "grace": return Loc.T("Season over: claim within {0}", FormatTime(Left(CF.N(Season, "claimEndsIn"), passed)));
                case "upcoming": return Loc.T("Starts in {0}", FormatTime(Left(CF.N(Season, "startsIn"), passed)));
                case "soon": return Loc.T("Starts: Coming soon");   // the launch date is open (O463): no start, no finish
            }
            return "";
        }

        public string Title()
        {
            if (Season == null) return Loc.T("Season Pass");
            return string.Format("{0} - {1} {2}", CF.T(Season, "pass", "?"), CF.T(Season, "name", "?"), CF.T(Season, "tag"));
        }

        public static string OfferButton(object offer, out bool enabled)
        {
            enabled = false;
            if (!(offer is Dictionary<string, object>)) return "";
            if (CF.B(offer, "owned")) return Loc.T("Owned");
            if (CF.G(offer, "price") == null) return Loc.T("Unavailable");
            enabled = true;
            double price = CF.N(offer, "price"), full = CF.G(offer, "full") != null ? CF.N(offer, "full") : price;
            return price < full ? Loc.T("Upgrade {0}", (long)price) : Loc.T("Buy {0}", (long)price);
        }

        public static string SourceLine(object s) => string.Format("{0} {1} / {2}", CF.T(s, "name", CF.T(s, "key", "?")), (long)CF.N(s, "today"), (long)CF.N(s, "cap"));

        /// <summary>Challenge row: text, progress text, percent, done.</summary>
        public static string Challenge(object c, out string progress, out int pct, out bool done)
        {
            double target = Math.Max(1, CF.N(c, "target") == 0 ? 1 : CF.N(c, "target"));
            double p = Math.Min(target, CF.N(c, "progress"));
            done = CF.B(c, "done");
            if (done) { progress = Loc.T("Done"); pct = 100; return CF.T(c, "text"); }
            progress = (long)p + " / " + (long)target;
            pct = (int)Math.Floor(p * 100 / target);
            return CF.T(c, "text");
        }

        public string DailyTitle(double nowMs) => CF.G(State, "daily") == null ? "" : Loc.T("Daily challenges (new in {0})", FormatTime(Left(CF.N(CF.G(State, "daily"), "resetIn"), (nowMs - StateAt) / 1000.0)));
        public string WeeklyTitle(double nowMs) => CF.G(State, "weekly") == null ? "" : Loc.T("Weekly challenges (new in {0})", FormatTime(Left(CF.N(CF.G(State, "weekly"), "resetIn"), (nowMs - StateAt) / 1000.0)));
    }
}
