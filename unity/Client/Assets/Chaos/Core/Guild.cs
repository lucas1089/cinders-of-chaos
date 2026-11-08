// Guild (client game_guild, extended opcode 252, server guild.lua + guild_hall.lua) and Guild Wars (client game_guildwar, opcode 197, server
// guildwar.lua + guildboss.lua). Both are state windows: the server sends the whole state, the panel turns it into rows.
//   Guild    server -> client  state {open, tab, guild, perks {now, list}, members, hall, depot, log, top} | none {open, text} | message {ok, text} | openModule {name}
//            client -> server  open {tab} | refresh {tab} | deposit {amount} | withdraw {amount} | buyHall {from} | upgrade {key} | payRent | take {id} | scroll
//   GuildWar server -> client  state {open, tab, guild, options, wars {pending, active, history}, board {active, history}, boss} | message {ok, text}
//                              | log {id, title, score, lines}
//            client -> server  open {tab} | refresh {tab} | close | declare {target, fragLimit, hours, stake} | accept {id} | decline {id} | cancel {id}
//                              | surrender {id} | log {id} | bossGold {amount} | bossItem {key} | bossSummon
// Every request carries the tab shown (data.tab). The state of the war window comes in chunks (ExtOpcodes joins them).
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    /// <summary>Text helpers of the guild window (guildmath.lua).</summary>
    public static class GuildMath
    {
        public static string LevelText(object g) => Loc.T("Guild level {0} / {1}", SFmt.Has(g, "level") ? Json.Int(g, "level") : 1, SFmt.Has(g, "maxLevel") ? Json.Int(g, "maxLevel") : 20);

        public static string XpText(object g)
        {
            if (Json.Number(g, "need") <= 0) return Loc.T("Max level");
            return Loc.T("{0} / {1} GXP ({2}%)", SFmt.Money(Json.Number(g, "into")), SFmt.Money(Json.Number(g, "need")), Json.Int(g, "pct"));
        }

        public static int Percent(object g)
        {
            double need = Json.Number(g, "need");
            if (need <= 0) return 100;
            return (int)Math.Max(0, Math.Min(100, Math.Floor(Json.Number(g, "into") * 100 / need)));
        }

        public static string PerksNow(object p)
        {
            var parts = new List<string>();
            if (Json.Number(p, "xp") > 0) parts.Add("+" + Json.Int(p, "xp") + Loc.T("% experience"));
            if (Json.Number(p, "loot") > 0) parts.Add("+" + Json.Int(p, "loot") + Loc.T("% loot"));
            if (Json.Number(p, "respec") > 0) parts.Add(Loc.T("respec -{0}%", Json.Int(p, "respec")));
            if (Json.Number(p, "depotSlots") > 0) parts.Add(Loc.T("+{0} stash slots", Json.Int(p, "depotSlots")));
            if (Json.Truthy(p, "scroll")) parts.Add(Loc.T("daily hall scroll"));
            if (Json.Truthy(p, "aura")) parts.Add(Loc.T("guild aura"));
            return parts.Count == 0 ? Loc.T("No perks yet: they start at guild level 2.") : string.Join(", ", parts);
        }

        public static string RentText(object h)
        {
            if (!Json.Truthy(h, "owned")) return Loc.T("Your guild owns no guild hall.");
            string rent = Loc.T("{0} gold a week", SFmt.Money(Json.Number(h, "rent")));
            string st = Json.Text(h, "rentState");
            if (st == "paid") return Loc.T("Rent {0}, paid until {1} ({2} left).", rent, Json.Text(h, "paidUntil", "?"), SFmt.Duration(Json.Number(h, "rentLeft")));
            if (st == "grace") return Loc.T("Rent {0} is DUE. The upgrades lock in {1}.", rent, SFmt.Duration(Json.Number(h, "graceLeft")));
            return Loc.T("Rent {0} is UNPAID: the upgrades are locked until it is paid.", rent);
        }

        public static string RentTone(object h)
        {
            string st = Json.Text(h, "rentState");
            return h == null || st == "paid" ? "good" : st == "grace" ? "warn" : "bad";
        }

        public static string UpgradeText(object u)
        {
            int tier = Json.Int(u, "tier"), max = SFmt.Has(u, "max") ? Json.Int(u, "max") : 1;
            string tiers = max > 1 ? " " + tier + "/" + max : "";
            string state;
            if (tier >= max) state = Json.Truthy(u, "active") ? Loc.T("owned") : Loc.T("owned, locked");
            else if (tier > 0) state = Loc.T("next: {0} gold, level {1}", SFmt.Money(Json.Number(u, "cost")), Json.Int(u, "level"));
            else state = Loc.T("{0} gold, guild level {1}", SFmt.Money(Json.Number(u, "cost")), Json.Int(u, "level"));
            return Json.Text(u, "name", "?") + tiers + " - " + state;
        }

        public static string MemberText(object m) => Loc.T("{0} ({1}, level {2})", Json.Text(m, "name", "?"), Json.Text(m, "rank", "?"), Json.Int(m, "level"));
        public static string MemberPoints(object m) => Loc.T("{0} this week / {1}", SFmt.Money(Json.Number(m, "week")), SFmt.Money(Json.Number(m, "total")));
        public static string TopText(object t) => Loc.T("{0}. {1} (level {2})", Json.Int(t, "rank"), Json.Text(t, "name", "?"), Json.Int(t, "level"));
    }

    public sealed class GuildPanel : SocialPanel
    {
        public const byte Opcode = 252;
        public static readonly string[] TabKeys = { "overview", "members", "hall", "depot", "top" };
        readonly ExtOpcodes ext;
        public object State;
        public bool NoGuild;
        /// <summary>The hall's crafting bench asks the app to open a module of the main client by name.</summary>
        public Action<string> OpenModule = delegate { };
        /// <summary>The guild wars window (the Open button of the overview).</summary>
        public Action OpenWars = delegate { };

        public GuildPanel(ExtOpcodes e)
        {
            ext = e;
            Tabs.Add(new KeyValuePair<string, string>("overview", "Overview"));
            Tabs.Add(new KeyValuePair<string, string>("members", "Members"));
            Tabs.Add(new KeyValuePair<string, string>("hall", "Guild Hall"));
            Tabs.Add(new KeyValuePair<string, string>("depot", "Guild Stash"));
            Tabs.Add(new KeyValuePair<string, string>("top", "Top Guilds"));
            Tab = "overview";
            e.On(Opcode, OnMessage);
        }

        public void Send(string action, Dictionary<string, object> data = null)
        {
            data = data ?? new Dictionary<string, object>();
            if (!data.ContainsKey("tab")) data["tab"] = Tab;
            ext.Send(Opcode, action, data);
        }

        public override void Show() { Send("open"); }   // the answer shows the window
        public override void SelectTab(string key) { Tab = key; Send("refresh"); Changed(); }
        public override void Clear() { base.Clear(); State = null; NoGuild = false; }

        void OnMessage(ExtMessage m)
        {
            object d = m.Data ?? new Dictionary<string, object>();
            switch (m.Action)
            {
                case "state":
                    State = d; NoGuild = false;
                    string tab = Json.Text(d, "tab");
                    if (Json.Truthy(d, "open") && Array.IndexOf(TabKeys, tab) >= 0) Tab = tab;
                    var g = Json.Get(d, "guild");
                    Header1 = Json.Text(g, "name") + "   " + GuildMath.LevelText(g);
                    Header2 = Loc.T("You: {0}. This week: {1} GXP{2}.", Json.Text(g, "rankName"), SFmt.Money(Json.Number(g, "weekPoints")),
                        Json.Int(g, "weekRank") > 0 ? Loc.T(", rank {0} of the guilds", Json.Int(g, "weekRank")) : "");
                    if (Json.Truthy(d, "open")) Visible = true;
                    break;
                case "none":
                    State = null; NoGuild = true;
                    Header1 = Loc.T("No guild"); Header2 = "";
                    Status = Json.Text(d, "text"); StatusTone = "dim";
                    if (Json.Truthy(d, "open")) Visible = true;
                    break;
                case "message": Status = Json.Text(d, "text"); StatusTone = Json.Truthy(d, "ok") ? "good" : "bad"; break;
                case "openModule": if (Json.Text(d, "name").Length > 0) OpenModule(Json.Text(d, "name")); break;
            }
            Changed();
        }

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            if (State == null) return l.Rows;
            switch (Tab)
            {
                case "members": Members(l); break;
                case "hall": Hall(l); break;
                case "depot": Depot(l); break;
                case "top": Top(l); break;
                default: Overview(l); break;
            }
            return l.Rows;
        }

        void Overview(RowList l)
        {
            object g = Json.Get(State, "guild"), perks = Json.Get(State, "perks");
            l.Bar(GuildMath.XpText(g), GuildMath.Percent(g));
            l.Section(Loc.T("Perks for online members"));
            l.Text(GuildMath.PerksNow(Json.Get(perks, "now")), "good");
            foreach (var p in SFmt.Rows(perks, "list")) l.Text(Loc.T("Level") + " " + Json.Int(p, "level") + ": " + Json.Text(p, "text"), Json.Truthy(p, "active") ? "text" : "locked");
            if (Json.Truthy(g, "scroll"))
                l.Row(Loc.T("Guild hall scroll (one a day)"), Json.Truthy(g, "scrollTaken") ? Loc.T("taken today") : "").Btn(Loc.T("Take"), !Json.Truthy(g, "scrollTaken"), () => Send("scroll"));
            l.Section(Loc.T("Guild bank: {0} gold", SFmt.Money(Json.Number(g, "bank"))));
            l.Input(Loc.T("Amount"), "amount", "5k, 2.5m")
                .Btn(Loc.T("Deposit"), true, () => Amount("deposit"))
                .Btn(Loc.T("Withdraw"), Json.Truthy(g, "canWithdraw"), () => Amount("withdraw"), Json.Truthy(g, "canWithdraw") ? "" : Loc.T("Only the guild leader can withdraw."));
            l.Text(Loc.T("Deposits come from your carried gold, then your bank balance (at least {0}). Withdrawals go to the leader's bank balance.", SFmt.Money(Json.Number(g, "minDeposit"))), "dim");
            l.Row(Loc.T("Guild wars and the weekly guild boss")).Btn(Loc.T("Open"), true, () => OpenWars());
            l.Section(Loc.T("Guild log"));
            var log = Json.List(State, "log");
            if (log.Count == 0) l.Text(Loc.T("Nothing yet."), "dim");
            foreach (object line in log) l.Text(line as string ?? "");
        }

        public bool Amount(string action)
        {
            long n = SFmt.ParseAmount(Text("amount"));
            if (n <= 0) return false;
            Send(action, SFmt.Map("amount", n));
            return true;
        }

        void Members(RowList l)
        {
            l.Section(Loc.T("Contribution (guild XP)"));
            var members = SFmt.Rows(State, "members");
            if (members.Count == 0) l.Text(Loc.T("No members."), "dim");
            foreach (var m in members) l.Row(GuildMath.MemberText(m), GuildMath.MemberPoints(m), Json.Truthy(m, "online") ? "good" : "");
            l.Text(Loc.T("Guild XP comes from experience (a 1 percent share, capped per day), bounties, rifts, world bosses, invasions and the guild siege."), "dim");
        }

        void Hall(RowList l)
        {
            object h = Json.Get(State, "hall");
            if (!Json.Truthy(h, "owned"))
            {
                l.Section(Loc.T("Guild hall"));
                l.Text(Loc.T("A guild hall costs {0} gold and needs guild level {1}. The guild leader buys it.", SFmt.Money(Json.Number(h, "cost")), Json.Int(h, "level")));
                l.Row(Loc.T("Pay from the guild bank")).Btn(Loc.T("Buy"), Json.Truthy(h, "canBuyBank"), () => Send("buyHall", SFmt.Map("from", "bank")), Json.Text(h, "reason"));
                l.Row(Loc.T("Pay with your own gold")).Btn(Loc.T("Buy"), Json.Truthy(h, "canBuySelf"), () => Send("buyHall", SFmt.Map("from", "self")), Json.Text(h, "reasonSelf"));
                if (Json.Text(h, "reason").Length > 0) l.Text(Json.Text(h, "reason"), "dim");
                return;
            }
            l.Section(Loc.T("Guild hall (slot {0})", Json.Int(h, "slot")));
            l.Text(GuildMath.RentText(h), GuildMath.RentTone(h));
            l.Row(Loc.T("Weekly rent from the guild bank"), SFmt.Money(Json.Number(h, "rent")) + " " + Loc.T("gold"))
                .Btn(Loc.T("Pay rent"), Json.Truthy(h, "canManage"), () => Send("payRent"), Json.Truthy(h, "canManage") ? "" : Loc.T("Leader and vice-leaders only."));
            l.Text(Loc.T("Enter through the portal next to the temple. Unpaid rent locks the upgrades; nothing is deleted."), "dim");
            l.Section(Loc.T("Upgrades"));
            foreach (var u in SFmt.Rows(h, "upgrades"))
            {
                bool maxed = Json.Int(u, "tier") >= (SFmt.Has(u, "max") ? Json.Int(u, "max") : 1);
                string key = Json.Text(u, "key");
                var row = l.Row(GuildMath.UpgradeText(u), "", maxed ? (Json.Truthy(u, "active") ? "good" : "bad") : "");
                row.Tip = Json.Text(u, "info");
                if (!maxed) row.Btn(Loc.T("Buy"), Json.Truthy(h, "canManage") && Json.Truthy(u, "canBuy"), () => Send("upgrade", SFmt.Map("key", key)), Json.Text(u, "reason"));
            }
            var hub = Json.List(h, "hub");
            if (hub.Count > 0)
            {
                l.Section(Loc.T("Teleport hub"));
                var names = new List<string>();
                foreach (object o in hub) names.Add(o as string ?? "");
                l.Text(string.Join(", ", names));
            }
        }

        void Depot(RowList l)
        {
            object dep = Json.Get(State, "depot");
            if (!Json.Truthy(dep, "owned"))
            {
                l.Section(Loc.T("Guild Stash"));
                l.Text(Loc.T("Your guild hall has no Guild Stash yet (a hall upgrade)."), "dim");
                return;
            }
            bool active = Json.Truthy(dep, "active");
            l.Section(Loc.T("Guild Stash ({0} / {1})", Json.Int(dep, "used"), Json.Int(dep, "capacity")) + (active ? "" : Loc.T(" - LOCKED")));
            l.Text(Loc.T("Drop an item on the large trunk in your guild hall to store it. Take items back here (in the hall)."), "dim");
            var items = SFmt.Rows(dep, "items");
            if (items.Count == 0) l.Text(Loc.T("Empty."), "dim");
            foreach (var it in items)
            {
                object id = Json.Get(it, "id");
                l.Row(Json.Int(it, "count", 1) + " x " + Json.Text(it, "name", "?")).Item(Json.Int(it, "clientId"), Json.Int(it, "count", 1))
                    .Btn(Loc.T("Take"), active, () => Send("take", SFmt.Map("id", id)));
            }
            l.Section(Loc.T("Stash log"));
            var log = Json.List(dep, "log");
            if (log.Count == 0) l.Text(Loc.T("Nothing yet."), "dim");
            foreach (object line in log) l.Text(line as string ?? "");
        }

        void Top(RowList l)
        {
            object top = Json.Get(State, "top");
            l.Section(Loc.T("Top guilds this week (resets in {0})", SFmt.Duration(Json.Number(top, "resetIn"))));
            var rows = SFmt.Rows(top, "rows");
            if (rows.Count == 0) l.Text(Loc.T("No guild earned guild XP this week yet."), "dim");
            foreach (var t in rows) l.Row(GuildMath.TopText(t), SFmt.Money(Json.Number(t, "points")) + " GXP", Json.Truthy(t, "own") ? "#ffe7a6" : "");
            if (Json.Text(top, "lastWinner").Length > 0) l.Text(Loc.T("Top guild of last week: {0}", Json.Text(top, "lastWinner")), "gold");
        }
    }

    /// <summary>Text helpers of the guild wars window (guildwarview.lua).</summary>
    public static class GuildWarMath
    {
        public static readonly int[] DefaultFrags = { 10, 25, 50 };

        public static string HoursText(double h)
        {
            long n = (long)Math.Floor(h);
            if (n >= 24 && n % 24 == 0) { long d = n / 24; return Loc.T(d == 1 ? "{0} day" : "{0} days", d); }
            return Loc.T(n == 1 ? "{0} hour" : "{0} hours", n);
        }

        public static long Winnings(double stake, double fee)
        {
            double pot = 2 * Math.Max(0, Math.Floor(stake));
            return (long)(pot - Math.Floor(pot * fee / 100));
        }

        public static string StakeText(long stake, double fee) =>
            stake <= 0 ? Loc.T("no stake") : Loc.T("{0} gold per side (the winner gets {1})", SFmt.Money(stake), SFmt.Money(Winnings(stake, fee)));

        /// <summary>The declare request or null and why.</summary>
        public static Dictionary<string, object> DeclareRequest(string target, double fragLimit, double hours, string stakeText, object options, out string why)
        {
            why = "";
            target = (target ?? "").Trim();
            if (target.Length == 0) { why = Loc.T("Type the name of the guild."); return null; }
            long stake = SFmt.ParseAmount(stakeText);
            if (stake < 0) { why = Loc.T("The stake is a number of gold (500k, 2m, ...)."); return null; }
            double smin = Json.Number(options, "stakeMin");
            if (stake > 0 && stake < smin) { why = Loc.T("A stake is at least {0} gold (or none).", SFmt.Money(smin)); return null; }
            if (SFmt.Has(options, "stakeMax") && stake > Json.Number(options, "stakeMax")) { why = Loc.T("A stake is at most {0} gold.", SFmt.Money(Json.Number(options, "stakeMax"))); return null; }
            if (fragLimit <= 0 || hours <= 0) { why = Loc.T("Pick a frag limit and a duration."); return null; }
            return SFmt.Map("target", target, "fragLimit", (long)fragLimit, "hours", (long)hours, "stake", stake);
        }

        public static string Title(object w) => Json.Text(w, "own", "?") + " vs " + Json.Text(w, "enemy", "?");
        public static string Score(object w) => Json.Int(w, "ownKills") + " : " + Json.Int(w, "enemyKills");

        public static string Status(object w)
        {
            string st = Json.Text(w, "status");
            if (st == "pending")
                return Json.Truthy(w, "incoming") ? Loc.T("Declared on you: answer within {0}", SFmt.Duration(Json.Number(w, "left"))) : Loc.T("Offer sent: waiting {0} for the answer", SFmt.Duration(Json.Number(w, "left")));
            if (st == "active") return Loc.T("{0} (first to {1}), ends in {2}", Score(w), Json.Int(w, "fragLimit"), SFmt.Duration(Json.Number(w, "left")));
            string r = Json.Text(w, "result", st);
            string word;
            switch (r) { case "won": word = Loc.T("Won"); break; case "lost": word = Loc.T("Lost"); break; case "draw": word = Loc.T("Draw"); break; case "declined": word = Loc.T("Declined"); break; case "cancelled": word = Loc.T("Taken back"); break; case "expired": word = Loc.T("Expired"); break; default: word = r; break; }
            return st == "ended" ? word + " " + Score(w) + " - " + Json.Text(w, "reason") : word;
        }

        public static string Tone(object w)
        {
            string st = Json.Text(w, "status"), res = Json.Text(w, "result");
            if (st == "pending") return Json.Truthy(w, "incoming") ? "warn" : "text";
            if (st == "active") return "bad";
            if (res == "won") return "good";
            if (res == "lost") return "bad";
            return "dim";
        }

        public static string BoardLine(object w)
        {
            string s = Json.Text(w, "own", "?") + " " + Json.Int(w, "ownKills") + " : " + Json.Int(w, "enemyKills") + " " + Json.Text(w, "enemy", "?");
            if (Json.Text(w, "status") == "active") return s + Loc.T(" (first to {0}, {1} left)", Json.Int(w, "fragLimit"), SFmt.Duration(Json.Number(w, "left")));
            return s + " - " + Json.Text(w, "reason");
        }

        public static string KillLine(object k) =>
            Loc.T("{0} {1} killed {2} (level {3})", Json.Text(k, "at"), Json.Text(k, "killer", "?"), Json.Text(k, "victim", "?"), Json.Int(k, "level"))
            + (Json.Truthy(k, "counted") ? "" : Loc.T(" - not counted: {0}", Json.Text(k, "reason")));

        public static int FuelPercent(object b)
        {
            double need = Json.Number(b, "need");
            return need <= 0 ? 0 : (int)Math.Max(0, Math.Min(100, Math.Floor(Json.Number(b, "fuel") * 100 / need)));
        }

        public static string FuelText(object b) => Loc.T("{0} / {1} embers ({2}%)", SFmt.Money(Json.Number(b, "fuel")), SFmt.Money(Json.Number(b, "need")), FuelPercent(b));

        public static string BossState(object b, out string tone)
        {
            if (!SFmt.Has(b, "guild") || Json.Get(b, "guild") == null || !Json.Truthy(b, "guild", true)) { tone = "dim"; return Loc.T("Join a guild to fight the guild boss."); }
            if (Json.Truthy(b, "killed")) { tone = "good"; return Loc.T("Slain this week in {0}. The stone rests until the reset ({1}).", SFmt.Clock(Json.Number(b, "bestSeconds")), SFmt.Duration(Json.Number(b, "resetIn"))); }
            if (Json.Truthy(b, "running")) { tone = "warn"; return Loc.T("Your guild is fighting the guild boss now."); }
            if (Json.Truthy(b, "canSummon")) { tone = "warn"; return Loc.T("The stone is full: summon the guild boss."); }
            tone = "dim";
            return Json.Text(b, "reason");
        }

        public static string BannerText(object bn)
        {
            if (Json.Int(bn, "tier") <= 0) return Loc.T("No guild banner yet: the first kill raises the Ember Banner.");
            int k = Json.Int(bn, "kills");
            string s = Loc.T(k == 1 ? "{0} ({1} kill)" : "{0} ({1} kills)", Json.Text(bn, "name"), k);
            if (Json.Int(bn, "next") > 0) s += Loc.T(", next tier at {0}", Json.Int(bn, "next"));
            return s;
        }

        public static string BossBoardLine(object r) =>
            Json.Truthy(r, "killed") ? Loc.T("{0}. {1} - slain in {2} by {3}", Json.Int(r, "rank"), Json.Text(r, "name", "?"), SFmt.Clock(Json.Number(r, "seconds")), Json.Int(r, "players"))
                : Loc.T("{0}. {1} - {2} damage", Json.Int(r, "rank"), Json.Text(r, "name", "?"), SFmt.Money(Json.Number(r, "damage")));

        public static string SpoilsLine(object sp, double pool)
        {
            double gold = Json.Number(sp, "gold");
            int pct = pool > 0 ? (int)Math.Floor(gold * 100 / pool + 0.5) : 0;
            return Loc.T("{0}: {1} gold ({2}%)", Json.Text(sp, "name", "?"), SFmt.Money(gold), pct);
        }
    }

    public sealed class GuildWarPanel : SocialPanel
    {
        public const byte Opcode = 197;
        public static readonly string[] TabKeys = { "wars", "declare", "board", "boss" };
        readonly ExtOpcodes ext;
        public object State, Log;
        string confirmSurrender = "";

        public GuildWarPanel(ExtOpcodes e)
        {
            ext = e;
            Tabs.Add(new KeyValuePair<string, string>("wars", "Wars"));
            Tabs.Add(new KeyValuePair<string, string>("declare", "Declare War"));
            Tabs.Add(new KeyValuePair<string, string>("board", "War Board"));
            Tabs.Add(new KeyValuePair<string, string>("boss", "Guild Boss"));
            Tab = "wars";
            Form["frag"] = "1"; Form["hours"] = "1";
            e.On(Opcode, OnMessage);
        }

        public void Send(string action, Dictionary<string, object> data = null)
        {
            data = data ?? new Dictionary<string, object>();
            if (!data.ContainsKey("tab")) data["tab"] = Tab;
            ext.Send(Opcode, action, data);
        }

        public override void Show() { Send("open"); }
        public override void Hide() { if (Visible) { Visible = false; Send("close"); } }
        public void OpenTab(string key) { if (Array.IndexOf(TabKeys, key) >= 0) Tab = key; Send("open"); }
        public override void SelectTab(string key) { Tab = key; confirmSurrender = ""; Send("refresh"); Changed(); }
        public override void Clear() { base.Clear(); State = Log = null; confirmSurrender = ""; }

        void OnMessage(ExtMessage m)
        {
            object d = m.Data ?? new Dictionary<string, object>();
            switch (m.Action)
            {
                case "state":
                    State = d;
                    if (Json.Truthy(d, "open") && Array.IndexOf(TabKeys, Json.Text(d, "tab")) >= 0) Tab = Json.Text(d, "tab");
                    var g = Json.Get(d, "guild");
                    if (SFmt.IsMap(g))
                    {
                        Header1 = Json.Text(g, "name");
                        Header2 = Loc.T("{0} of {1} wars and offers. Guild bank: {2} gold.", Json.Int(g, "wars"), Json.Int(Json.Get(d, "options"), "maxWars"), SFmt.Money(Json.Number(g, "bank")));
                    }
                    else { Header1 = Loc.T("Guild Wars"); Header2 = ""; }
                    if (Json.Truthy(d, "open")) Visible = true;
                    break;
                case "message": Status = Json.Text(d, "text"); StatusTone = Json.Truthy(d, "ok") ? "good" : "bad"; break;
                case "log": Log = d; break;
            }
            Changed();
        }

        object G => Json.Get(State, "guild") is Dictionary<string, object> g ? g : null;

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            if (State == null) return l.Rows;
            switch (Tab)
            {
                case "declare": Declare(l); break;
                case "board": Board(l); break;
                case "boss": Boss(l); break;
                default: Wars(l); break;
            }
            return l.Rows;
        }

        SocialRow WarRow(RowList l, object w)
        {
            var r = l.Row(GuildWarMath.Title(w), GuildWarMath.Status(w), GuildWarMath.Tone(w));
            r.Tip = Json.Text(w, "terms");
            if (Json.Text(w, "terms").Length > 0) l.Text(Json.Text(w, "terms"), "dim");
            return r;
        }

        void Wars(RowList l)
        {
            var g = G;
            if (g == null) { l.Text(Loc.T("You are not in a guild. The War Board shows the wars of the server."), "dim"); return; }
            bool can = Json.Truthy(g, "canDeclare");
            object wars = Json.Get(State, "wars");
            var pending = SFmt.Rows(wars, "pending"); var active = SFmt.Rows(wars, "active");
            l.Section(Loc.T("Offers"));
            if (pending.Count == 0) l.Text(Loc.T("No open offers."), "dim");
            foreach (var w in pending)
            {
                object id = Json.Get(w, "id");
                var row = WarRow(l, w);
                if (Json.Truthy(w, "incoming"))
                {
                    bool needLeader = Json.Number(w, "stake") > 0 && !Json.Truthy(g, "canStake");
                    row.Btn(Loc.T("Accept"), can && !needLeader, () => Send("accept", SFmt.Map("id", id)), needLeader ? Loc.T("A war with gold at stake is accepted by the guild leader.") : "");
                    row.Btn(Loc.T("Decline"), can, () => Send("decline", SFmt.Map("id", id)));
                }
                else row.Btn(Loc.T("Take back"), can, () => Send("cancel", SFmt.Map("id", id)));
            }
            l.Section(Loc.T("Running wars"));
            if (active.Count == 0) l.Text(Loc.T("Your guild is at peace."), "dim");
            foreach (var w in active)
            {
                object id = Json.Get(w, "id");
                string key = SFmt.IsMap(w) ? ((long)Json.Number(w, "id")).ToString(CultureInfo.InvariantCulture) : "";
                bool sure = confirmSurrender == key;
                WarRow(l, w)
                    .Btn(sure ? Loc.T("Sure?") : Loc.T("Surrender"), can, () => { if (confirmSurrender == key) { confirmSurrender = ""; Send("surrender", SFmt.Map("id", id)); } else { confirmSurrender = key; Changed(); } }, Loc.T("The other guild wins the war and both stakes."))
                    .Btn(Loc.T("Kill log"), true, () => Send("log", SFmt.Map("id", id)));
            }
            if (Log != null)
            {
                l.Section(Loc.T("Kill log: {0} ({1})", Json.Text(Log, "title"), Json.Text(Log, "score")));
                var lines = SFmt.Rows(Log, "lines");
                if (lines.Count == 0) l.Text(Loc.T("No kills yet."), "dim");
                foreach (var k in lines) l.Text(GuildWarMath.KillLine(k), Json.Truthy(k, "counted") ? "text" : "dim");
            }
            l.Section(Loc.T("History"));
            var hist = SFmt.Rows(wars, "history");
            if (hist.Count == 0) l.Text(Loc.T("No wars yet."), "dim");
            foreach (var w in hist)
            {
                object id = Json.Get(w, "id");
                var row = WarRow(l, w);
                if (Json.Text(w, "status") == "ended") row.Btn(Loc.T("Kill log"), true, () => Send("log", SFmt.Map("id", id)));
            }
            object o = Json.Get(State, "options");
            l.Text(Loc.T("Counted kills: a victim of level {0} or more (and at least half the killer's level), not from the same IP or account, the same victim once per {1} minutes.", Json.Int(o, "minVictimLevel"), Json.Int(o, "sameVictimMinutes")), "dim");
        }

        public bool Declare()
        {
            object o = Json.Get(State, "options");
            var fr = Json.List(o, "fragLimits"); var du = Json.List(o, "durations");
            double frag = fr.Count > 0 ? (Index("frag") < fr.Count ? (fr[Index("frag")] as double? ?? 0) : 0) : 0;
            double hours = du.Count > 0 ? (Index("hours") < du.Count ? (du[Index("hours")] as double? ?? 0) : 0) : 0;
            var req = GuildWarMath.DeclareRequest(Text("target"), frag, hours, Text("stake"), o, out string why);
            if (req == null) { Say(why, false); return false; }
            Send("declare", req);
            return true;
        }

        void Declare(RowList l)
        {
            var g = G; object o = Json.Get(State, "options");
            if (g == null) { l.Text(Loc.T("You are not in a guild."), "dim"); return; }
            l.Section(Loc.T("Declare war"));
            if (!Json.Truthy(g, "canDeclare")) l.Text(Loc.T("Only the guild leader and the vice-leaders declare war."), "bad");
            l.Input(Loc.T("Guild"), "target");
            var frags = new List<string>(); foreach (object n in Json.List(o, "fragLimits")) frags.Add(Loc.T("{0} kills", n is double dd ? (long)dd : 0));
            l.Combo(Loc.T("Frag limit"), "frag", frags);
            var hrs = new List<string>(); foreach (object n in Json.List(o, "durations")) hrs.Add(GuildWarMath.HoursText(n is double dd ? dd : 0));
            l.Combo(Loc.T("Duration"), "hours", hrs);
            if (Json.Truthy(g, "canStake"))
            {
                l.Input(Loc.T("Gold stake per side"), "stake", "500k, 2m");
                l.Text(Loc.T("Optional (empty = none): {0} to {1} gold from the guild bank ({2} gold). The winner gets both stakes minus {3}%.",
                    SFmt.Money(Json.Number(o, "stakeMin")), SFmt.Money(Json.Number(o, "stakeMax")), SFmt.Money(Json.Number(g, "bank")), Json.Int(o, "fee")), "dim");
            }
            else l.Text(Loc.T("Only the guild leader can put gold at stake."), "dim");
            l.Row(Loc.T("The other guild accepts or declines in game within {0} hours.", Json.Int(o, "offerHours"))).Btn(Loc.T("Declare war"), Json.Truthy(g, "canDeclare"), () => Declare());
            l.Text(Loc.T("Wars use the guild war emblems: kills between the two guilds give no skull. They end at the frag limit, when the time is up (more kills wins, a tie is a draw) or by surrender. Season characters fight only guilds of their own realm."), "dim");
            if (SFmt.Has(o, "emblemsLive") && !Json.Truthy(o, "emblemsLive", true)) l.Text(Loc.T("The war emblems show after the next login."), "dim");
        }

        void Board(RowList l)
        {
            object b = Json.Get(State, "board");
            l.Section(Loc.T("Wars now"));
            var act = SFmt.Rows(b, "active");
            if (act.Count == 0) l.Text(Loc.T("No guilds are at war."), "dim");
            foreach (var w in act) l.Text(GuildWarMath.BoardLine(w), "gold");
            l.Section(Loc.T("Latest wars"));
            var hist = SFmt.Rows(b, "history");
            if (hist.Count == 0) l.Text(Loc.T("No war has ended yet."), "dim");
            foreach (var w in hist) l.Text(GuildWarMath.BoardLine(w));
            l.Text(Loc.T("The website shows the same board."), "dim");
        }

        void Boss(RowList l)
        {
            object b = Json.Get(State, "boss");
            l.Section(Loc.T("{0}, the weekly guild boss", Json.Text(b, "boss", "?")));
            string tone;
            string stateText = GuildWarMath.BossState(b, out tone);
            bool inGuild = Json.Get(b, "guild") != null && Json.Truthy(b, "guild", true);
            if (!inGuild) { l.Text(stateText, tone); }
            else
            {
                l.Bar(GuildWarMath.FuelText(b), GuildWarMath.FuelPercent(b));
                l.Text(stateText, tone);
                l.Text(Loc.T("Summons this week: {0} of {1}", Json.Int(b, "attempts"), Json.Int(b, "maxAttempts")) + Loc.T(" - week resets in {0}", SFmt.Duration(Json.Number(b, "resetIn"))), "dim");
                l.Row(Loc.T("{0} in the hall now", Json.Int(b, "players"))).Btn(Loc.T("Summon"), Json.Truthy(b, "canSummon"), () => Send("bossSummon"));
                l.Text(Loc.T("The leader or a vice-leader summons it in the guild hall: you alone or every member in the hall (level {0}+, up to {1}) comes along.", Json.Int(b, "minLevel"), Json.Int(b, "maxPlayers")), "dim");
                l.Section(Loc.T("Feed the Summoning Stone"));
                object gold = Json.Get(b, "gold");
                double per = Json.Number(gold, "perEmber");
                long typed = SFmt.ParseAmount(Text("bossGold"));
                l.Input(Loc.T("Gold"), "bossGold", Loc.T("{0} gold = 1 ember (at least {1})", SFmt.Money(per), SFmt.Money(Json.Number(gold, "min"))))
                    .Btn(Loc.T("Feed"), !Json.Truthy(b, "killed") && typed > 0, () => { long n = SFmt.ParseAmount(Text("bossGold")); if (n > 0) Send("bossGold", SFmt.Map("amount", n)); });
                if (typed > 0 && per > 0) l.Text(Loc.T("{0} embers", (long)Math.Floor(typed / per)), "dim");
                foreach (var m in SFmt.Rows(b, "materials"))
                {
                    string key = Json.Text(m, "key");
                    l.Row(Loc.T("{0}: {1} embers each (you carry {2})", Json.Text(m, "name", "?"), Json.Int(m, "embers"), Json.Int(m, "have"))).Item(Json.Int(m, "clientId"))
                        .Btn(Loc.T("Feed all"), Json.Int(m, "have") > 0 && !Json.Truthy(b, "killed"), () => Send("bossItem", SFmt.Map("key", key)));
                }
                l.Section(Loc.T("Guild banner"));
                l.Text(GuildWarMath.BannerText(Json.Get(b, "banner")));
                l.Section(Loc.T("This week's fuel"));
                var cs = SFmt.Rows(b, "contributors");
                if (cs.Count == 0) l.Text(Loc.T("No embers yet."), "dim");
                foreach (var c in cs) l.Text(Loc.T("{0}: {1} embers", Json.Text(c, "name", "?"), SFmt.Money(Json.Number(c, "embers"))) + (Json.Number(c, "gold") > 0 ? Loc.T(" ({0} gold)", SFmt.Money(Json.Number(c, "gold"))) : ""));
                if (Json.Number(b, "pool") > 0)
                {
                    l.Section(Loc.T("This week's spoils: {0} gold", SFmt.Money(Json.Number(b, "pool"))));
                    l.Text(Loc.T("Split among the rewarded fighters by damage and healing; everyone gets a floor share."), "dim");
                    foreach (var sp in SFmt.Rows(b, "spoils")) l.Text(GuildWarMath.SpoilsLine(sp, Json.Number(b, "pool")));
                }
            }
            l.Section(Loc.T("Guild boss board this week"));
            var board = SFmt.Rows(b, "board");
            if (board.Count == 0) l.Text(Loc.T("No guild has fought it this week."), "dim");
            foreach (var r in board) l.Text(GuildWarMath.BossBoardLine(r), Json.Truthy(r, "own") ? "#ffe7a6" : "");
        }
    }
}
